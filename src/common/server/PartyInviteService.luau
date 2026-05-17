local PartyInviteService = {}

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PresenceService = require(script.Parent:WaitForChild("PresenceService"))

local PARTY_MAP_NAME = "GlobalPartyMapV1"
local USER_PARTY_MAP_NAME = "GlobalUserPartyMapV1"
local INVITE_MAP_NAME = "GlobalPartyInviteMapV1"
local PARTY_TOPIC_NAME = "GlobalPartyEventsV1"

local PARTY_TTL_SECONDS = 60 * 60
local INVITE_TTL_SECONDS = 30
local MAX_PARTY_SIZE = 4
local FRIEND_LIST_CACHE_TTL_SECONDS = 15
local USER_PARTY_CACHE_TTL_SECONDS = 5

local REQUEST_RF_NAME = "PartyRequestRF"
local PARTY_EVENT_RE_NAME = "PartyEventRE"

local initialized = false
local subscription: RBXScriptConnection?
local playerRemovingConn: RBXScriptConnection?

local partyMap = MemoryStoreService:GetHashMap(PARTY_MAP_NAME)
local userPartyMap = MemoryStoreService:GetHashMap(USER_PARTY_MAP_NAME)
local inviteMap = MemoryStoreService:GetHashMap(INVITE_MAP_NAME)

local requestRF: RemoteFunction?
local partyEventRE: RemoteEvent?
local displayNameCache: {[number]: string} = {}
local friendListCacheByUserId: {[number]: { expiresAt: number, friends: {any}, friendIds: {number} }} = {}
local userPartyIdCacheByUserId: {[number]: { expiresAt: number, value: string? }} = {}

local function getOrCreateRemote(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end

	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local function publishEvent(payload: {[string]: any})
	if payload.originJobId == nil then
		payload.originJobId = game.JobId
	end
	pcall(function()
		MessagingService:PublishAsync(PARTY_TOPIC_NAME, payload)
	end)
end

local function containsUser(userIds: {number}, userId: number): boolean
	for _, id in ipairs(userIds) do
		if id == userId then
			return true
		end
	end
	return false
end

local function removeUser(userIds: {number}, userId: number)
	for i, id in ipairs(userIds) do
		if id == userId then
			table.remove(userIds, i)
			return
		end
	end
end

local function getUserPartyId(userId: number): string?
	local cached = userPartyIdCacheByUserId[userId]
	if cached and cached.expiresAt > os.clock() then
		return cached.value
	end

	local ok, partyId = pcall(function()
		return userPartyMap:GetAsync(tostring(userId))
	end)
	if ok then
		userPartyIdCacheByUserId[userId] = {
			expiresAt = os.clock() + USER_PARTY_CACHE_TTL_SECONDS,
			value = partyId,
		}
		return partyId
	end
	return nil
end

local function setUserPartyId(userId: number, partyId: string)
	userPartyIdCacheByUserId[userId] = {
		expiresAt = os.clock() + USER_PARTY_CACHE_TTL_SECONDS,
		value = partyId,
	}
	pcall(function()
		userPartyMap:SetAsync(tostring(userId), partyId, PARTY_TTL_SECONDS)
	end)
end

local function clearUserPartyId(userId: number)
	userPartyIdCacheByUserId[userId] = {
		expiresAt = os.clock() + USER_PARTY_CACHE_TTL_SECONDS,
		value = nil,
	}
	pcall(function()
		userPartyMap:RemoveAsync(tostring(userId))
	end)
end

local function getPartyById(partyId: string): {[string]: any}?
	local ok, party = pcall(function()
		return partyMap:GetAsync(partyId)
	end)
	if ok then
		return party
	end
	return nil
end

local function saveParty(party: {[string]: any})
	party.updatedAt = os.time()
	pcall(function()
		partyMap:SetAsync(party.partyId, party, PARTY_TTL_SECONDS)
	end)
end

local function deleteParty(partyId: string)
	pcall(function()
		partyMap:RemoveAsync(partyId)
	end)
end

local function ensureMemberNames(party: {[string]: any}): {[string]: string}
	if type(party.memberNames) ~= "table" then
		party.memberNames = {}
	end
	return party.memberNames
end

local function setPartyMemberName(party: {[string]: any}, userId: number, name: string?)
	if type(name) ~= "string" or name == "" then
		return
	end

	local memberNames = ensureMemberNames(party)
	memberNames[tostring(userId)] = name
end

local function clearPartyMemberName(party: {[string]: any}, userId: number)
	local memberNames = party.memberNames
	if type(memberNames) ~= "table" then
		return
	end
	memberNames[tostring(userId)] = nil
end

local function getPartyMemberName(party: {[string]: any}, userId: number): string?
	local memberNames = party.memberNames
	if type(memberNames) ~= "table" then
		return nil
	end

	local cached = memberNames[tostring(userId)]
	if type(cached) == "string" and cached ~= "" then
		return cached
	end
	return nil
end

local function resolveDisplayName(userId: number, cachedName: string?): string
	if type(cachedName) == "string" and cachedName ~= "" then
		return cachedName
	end

	local cached = displayNameCache[userId]
	if type(cached) == "string" and cached ~= "" then
		return cached
	end

	local player = Players:GetPlayerByUserId(userId)
	if player and type(player.DisplayName) == "string" and player.DisplayName ~= "" then
		displayNameCache[userId] = player.DisplayName
		return player.DisplayName
	end

	local ok, userInfos = pcall(function()
		return Players:GetUserInfosByUserIdsAsync({ userId })
	end)
	if ok and type(userInfos) == "table" then
		local info = userInfos[1]
		if type(info) == "table" then
			local displayName = info.DisplayName
			if type(displayName) == "string" and displayName ~= "" then
				displayNameCache[userId] = displayName
				return displayName
			end
		end
	end

	return tostring(userId)
end

local function getFriendListEntries(userId: number): ({any}?, {number}?, string?)
	local cached = friendListCacheByUserId[userId]
	if cached and cached.expiresAt > os.clock() then
		return cached.friends, cached.friendIds, nil
	end

	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(userId)
	end)
	if not ok or not pages then
		return nil, nil, "friends_fetch_failed"
	end

	local friends = {}
	local friendIds = {}

	repeat
		for _, friend in ipairs(pages:GetCurrentPage()) do
			local displayName = friend.DisplayName
			if type(displayName) ~= "string" or displayName == "" then
				displayName = resolveDisplayName(friend.Id, nil)
			end

			table.insert(friends, {
				userId = friend.Id,
				name = displayName,
			})
			table.insert(friendIds, friend.Id)
		end

		if pages.IsFinished then
			break
		end

		local advancedOk = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advancedOk then
			break
		end
	until #friends >= 100

	friendListCacheByUserId[userId] = {
		expiresAt = os.clock() + FRIEND_LIST_CACHE_TTL_SECONDS,
		friends = friends,
		friendIds = friendIds,
	}

	return friends, friendIds, nil
end

local function buildPartySnapshot(party: {[string]: any}): {[string]: any}
	local members = {}
	ensureMemberNames(party)
	for _, userId in ipairs(party.memberUserIds) do
		local name = resolveDisplayName(userId, getPartyMemberName(party, userId))
		setPartyMemberName(party, userId, name)
		table.insert(members, {
			userId = userId,
			name = name,
		})
	end

	return {
		partyId = party.partyId,
		leaderUserId = party.leaderUserId,
		members = members,
		updatedAt = party.updatedAt,
	}
end

local function firePartyUpdateToLocalPlayers(snapshot: {[string]: any}, memberUserIds: {number})
	if not partyEventRE then
		return
	end

	for _, userId in ipairs(memberUserIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			partyEventRE:FireClient(player, "PartyUpdated", snapshot)
		end
	end
end

local function firePartyClearedToLocalPlayers(userIds: {number})
	if not partyEventRE then
		return
	end

	for _, userId in ipairs(userIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			partyEventRE:FireClient(player, "PartyUpdated", nil)
		end
	end
end

local function broadcastPartyUpdate(party: {[string]: any})
	local snapshot = buildPartySnapshot(party)
	firePartyUpdateToLocalPlayers(snapshot, party.memberUserIds)
	publishEvent({
		kind = "party_update",
		memberUserIds = party.memberUserIds,
		snapshot = snapshot,
	})
end

local function broadcastPartyCleared(targetUserIds: {number})
	firePartyClearedToLocalPlayers(targetUserIds)
	publishEvent({
		kind = "party_clear",
		targetUserIds = targetUserIds,
	})
end

local function createPartyForLeader(leaderUserId: number): {[string]: any}
	local leader = Players:GetPlayerByUserId(leaderUserId)
	local leaderName = if leader then leader.DisplayName else resolveDisplayName(leaderUserId, nil)

	local party = {
		partyId = HttpService:GenerateGUID(false),
		leaderUserId = leaderUserId,
		memberUserIds = { leaderUserId },
		memberNames = {
			[tostring(leaderUserId)] = leaderName,
		},
		updatedAt = os.time(),
	}

	saveParty(party)
	setUserPartyId(leaderUserId, party.partyId)
	return party
end

local function getOrCreatePartyForLeader(userId: number)
	local existingPartyId = getUserPartyId(userId)
	if existingPartyId then
		local existingParty = getPartyById(existingPartyId)
		if existingParty then
			if existingParty.leaderUserId ~= userId then
				return existingParty, "not_leader"
			end
			return existingParty, nil
		end
		clearUserPartyId(userId)
	end

	return createPartyForLeader(userId), nil
end

local function removeInvite(inviteId: string)
	pcall(function()
		inviteMap:RemoveAsync(inviteId)
	end)
end

local function getInvite(inviteId: string): {[string]: any}?
	local ok, invite = pcall(function()
		return inviteMap:GetAsync(inviteId)
	end)
	if ok then
		return invite
	end
	return nil
end

local function sendInviteToUser(invite: {[string]: any})
	if not partyEventRE then
		return
	end

	local localTarget = Players:GetPlayerByUserId(invite.toUserId)
	if localTarget then
		partyEventRE:FireClient(localTarget, "InviteReceived", invite)
	end

	publishEvent({
		kind = "invite",
		toUserId = invite.toUserId,
		invite = invite,
	})
end

local function handleGetOnlineFriends(player: Player)
	local friends, friendIds, errorMessage = getFriendListEntries(player.UserId)
	if not friends or not friendIds then
		return { ok = false, message = errorMessage or "friends_fetch_failed" }
	end

	local presenceByUserId = PresenceService.GetPresenceByUserIds(friendIds)
	local result = {}

	for _, friend in ipairs(friends) do
		local presence = presenceByUserId[friend.userId]
		if not presence then
			continue
		end

		local friendPartyId = getUserPartyId(friend.userId)
		local isInParty = type(friendPartyId) == "string" and friendPartyId ~= ""

		local status = "OFFLINE"
		local canInvite = false

		if isInParty then
			status = "IN_PARTY"
		elseif presence.placeType == "gameplay" then
			status = "IN_GAMEPLAY"
		elseif presence.placeType == "lobby" then
			if presence.jobId == game.JobId then
				status = "LOBBY_SAME"
			else
				status = "LOBBY_OTHER"
			end
			canInvite = true
		end

		table.insert(result, {
			userId = friend.userId,
			name = friend.name,
			status = status,
			canInvite = canInvite,
		})
	end

	return { ok = true, data = result }
end

local function handleGetParty(player: Player)
	local partyId = getUserPartyId(player.UserId)
	if not partyId then
		return { ok = true, data = nil }
	end

	local party = getPartyById(partyId)
	if not party then
		clearUserPartyId(player.UserId)
		return { ok = true, data = nil }
	end

	return { ok = true, data = buildPartySnapshot(party) }
end

local function handleSendInvite(player: Player, payload: {[string]: any})
	local toUserId = tonumber(payload.toUserId)
	if not toUserId then
		return { ok = false, message = "invalid_target" }
	end

	if toUserId == player.UserId then
		return { ok = false, message = "cannot_invite_self" }
	end

	local presenceByUserId = PresenceService.GetPresenceByUserIds({ toUserId })
	local targetPresence = presenceByUserId[toUserId]
	if not targetPresence or targetPresence.placeType ~= "lobby" then
		return { ok = false, message = "target_not_in_lobby" }
	end

	local party, err = getOrCreatePartyForLeader(player.UserId)
	setPartyMemberName(party, player.UserId, player.DisplayName)
	if err == "not_leader" then
		return { ok = false, message = "only_leader_can_invite" }
	end

	if #party.memberUserIds >= MAX_PARTY_SIZE then
		return { ok = false, message = "party_full" }
	end

	if containsUser(party.memberUserIds, toUserId) then
		return { ok = false, message = "already_in_party" }
	end

	local targetPartyId = getUserPartyId(toUserId)
	if targetPartyId then
		return { ok = false, message = "target_already_in_party" }
	end

	local invite = {
		inviteId = HttpService:GenerateGUID(false),
		fromUserId = player.UserId,
		fromName = player.DisplayName,
		toUserId = toUserId,
		partyId = party.partyId,
		createdAt = os.time(),
		expiresAt = os.time() + INVITE_TTL_SECONDS,
	}

	pcall(function()
		inviteMap:SetAsync(invite.inviteId, invite, INVITE_TTL_SECONDS)
	end)

	sendInviteToUser(invite)
	return { ok = true, data = invite }
end

local function handleRespondInvite(player: Player, payload: {[string]: any})
	local inviteId = tostring(payload.inviteId or "")
	if inviteId == "" then
		return { ok = false, message = "invalid_invite_id" }
	end

	local accept = payload.accept == true
	local invite = getInvite(inviteId)
	if not invite then
		return { ok = false, message = "invite_not_found" }
	end

	if invite.toUserId ~= player.UserId then
		return { ok = false, message = "invite_not_for_player" }
	end

	if os.time() > (invite.expiresAt or 0) then
		removeInvite(inviteId)
		return { ok = false, message = "invite_expired" }
	end

	if not accept then
		removeInvite(inviteId)
		publishEvent({
			kind = "invite_declined",
			toUserId = invite.fromUserId,
			fromUserId = player.UserId,
			fromName = player.DisplayName,
		})
		return { ok = true }
	end

	if getUserPartyId(player.UserId) then
		removeInvite(inviteId)
		return { ok = false, message = "already_in_party" }
	end

	local party = getPartyById(invite.partyId)
	if not party then
		removeInvite(inviteId)
		return { ok = false, message = "party_not_found" }
	end

	if #party.memberUserIds >= MAX_PARTY_SIZE then
		removeInvite(inviteId)
		return { ok = false, message = "party_full" }
	end

	if not containsUser(party.memberUserIds, player.UserId) then
		table.insert(party.memberUserIds, player.UserId)
	end
	setPartyMemberName(party, player.UserId, player.DisplayName)
	setPartyMemberName(party, invite.fromUserId, invite.fromName)

	saveParty(party)
	setUserPartyId(player.UserId, party.partyId)
	removeInvite(inviteId)

	broadcastPartyUpdate(party)
	return { ok = true, data = buildPartySnapshot(party) }
end

local function handleLeaveParty(player: Player)
	local partyId = getUserPartyId(player.UserId)
	if not partyId then
		return { ok = false, message = "not_in_party" }
	end

	local party = getPartyById(partyId)
	clearUserPartyId(player.UserId)

	if not party then
		broadcastPartyCleared({ player.UserId })
		return { ok = true }
	end

	removeUser(party.memberUserIds, player.UserId)
	clearPartyMemberName(party, player.UserId)
	broadcastPartyCleared({ player.UserId })

	if #party.memberUserIds == 0 then
		deleteParty(party.partyId)
		return { ok = true }
	end

	if party.leaderUserId == player.UserId then
		party.leaderUserId = party.memberUserIds[1]
	end

	saveParty(party)
	broadcastPartyUpdate(party)
	return { ok = true, data = buildPartySnapshot(party) }
end

local function handleKickMember(player: Player, payload: {[string]: any})
	local targetUserId = tonumber(payload.targetUserId)
	if not targetUserId then
		return { ok = false, message = "invalid_target" }
	end

	if targetUserId == player.UserId then
		return { ok = false, message = "cannot_kick_self" }
	end

	local partyId = getUserPartyId(player.UserId)
	if not partyId then
		return { ok = false, message = "not_in_party" }
	end

	local party = getPartyById(partyId)
	if not party then
		clearUserPartyId(player.UserId)
		return { ok = false, message = "party_not_found" }
	end

	if party.leaderUserId ~= player.UserId then
		return { ok = false, message = "only_leader_can_kick" }
	end

	if not containsUser(party.memberUserIds, targetUserId) then
		return { ok = false, message = "target_not_in_party" }
	end

	removeUser(party.memberUserIds, targetUserId)
	clearPartyMemberName(party, targetUserId)
	clearUserPartyId(targetUserId)
	broadcastPartyCleared({ targetUserId })

	if #party.memberUserIds == 0 then
		deleteParty(party.partyId)
		return { ok = true }
	end

	saveParty(party)
	broadcastPartyUpdate(party)
	return { ok = true, data = buildPartySnapshot(party) }
end

local function handleDisbandParty(player: Player)
	local partyId = getUserPartyId(player.UserId)
	if not partyId then
		return { ok = false, message = "not_in_party" }
	end

	local party = getPartyById(partyId)
	if not party then
		clearUserPartyId(player.UserId)
		broadcastPartyCleared({ player.UserId })
		return { ok = true }
	end

	if party.leaderUserId ~= player.UserId then
		return { ok = false, message = "only_leader_can_disband" }
	end

	local memberUserIds = table.clone(party.memberUserIds)
	for _, userId in ipairs(memberUserIds) do
		clearUserPartyId(userId)
	end

	deleteParty(party.partyId)
	broadcastPartyCleared(memberUserIds)
	return { ok = true }
end

local function updatePartyForLeavingUser(userId: number)
	local partyId = getUserPartyId(userId)
	if not partyId then
		return
	end

	local party = getPartyById(partyId)
	clearUserPartyId(userId)
	if not party then
		return
	end

	removeUser(party.memberUserIds, userId)
	clearPartyMemberName(party, userId)
	broadcastPartyCleared({ userId })

	if #party.memberUserIds == 0 then
		deleteParty(party.partyId)
		return
	end

	if party.leaderUserId == userId then
		party.leaderUserId = party.memberUserIds[1]
	end

	saveParty(party)
	broadcastPartyUpdate(party)
end

local function onPartyMessage(message)
	if not partyEventRE then
		return
	end

	local data = message.Data
	if type(data) ~= "table" then
		return
	end

	if data.originJobId == game.JobId then
		return
	end

	if data.kind == "invite" then
		local target = Players:GetPlayerByUserId(tonumber(data.toUserId) or -1)
		if target then
			partyEventRE:FireClient(target, "InviteReceived", data.invite)
		end
		return
	end

	if data.kind == "party_update" then
		local snapshot = data.snapshot
		local members = data.memberUserIds
		if type(snapshot) ~= "table" or type(members) ~= "table" then
			return
		end

		for _, userId in ipairs(members) do
			local target = Players:GetPlayerByUserId(tonumber(userId) or -1)
			if target then
				partyEventRE:FireClient(target, "PartyUpdated", snapshot)
			end
		end
		return
	end

	if data.kind == "invite_declined" then
		local target = Players:GetPlayerByUserId(tonumber(data.toUserId) or -1)
		if target then
			partyEventRE:FireClient(target, "InviteDeclined", {
				fromUserId = data.fromUserId,
				fromName = data.fromName,
			})
		end
		return
	end

	if data.kind == "party_clear" then
		local targetUserIds = data.targetUserIds
		if type(targetUserIds) ~= "table" then
			return
		end

		for _, userId in ipairs(targetUserIds) do
			local target = Players:GetPlayerByUserId(tonumber(userId) or -1)
			if target then
				partyEventRE:FireClient(target, "PartyUpdated", nil)
			end
		end
	end
end

local function onRequest(player: Player, action: string, payload: {[string]: any}?)
	payload = payload or {}

	if action == "GetOnlineFriends" then
		return handleGetOnlineFriends(player)
	end
	if action == "GetParty" then
		return handleGetParty(player)
	end
	if action == "SendInvite" then
		return handleSendInvite(player, payload)
	end
	if action == "RespondInvite" then
		return handleRespondInvite(player, payload)
	end
	if action == "LeaveParty" then
		return handleLeaveParty(player)
	end
	if action == "KickMember" then
		return handleKickMember(player, payload)
	end
	if action == "DisbandParty" then
		return handleDisbandParty(player)
	end

	return { ok = false, message = "unknown_action" }
end

function PartyInviteService.Init()
	if initialized then
		return
	end
	initialized = true

	local sharedFolder = ReplicatedStorage:WaitForChild("shared")
	local remotesFolder = sharedFolder:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = sharedFolder
	end

	requestRF = getOrCreateRemote(remotesFolder, "RemoteFunction", REQUEST_RF_NAME) :: RemoteFunction
	partyEventRE = getOrCreateRemote(remotesFolder, "RemoteEvent", PARTY_EVENT_RE_NAME) :: RemoteEvent
	requestRF.OnServerInvoke = onRequest

	subscription = MessagingService:SubscribeAsync(PARTY_TOPIC_NAME, onPartyMessage)
	playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
		friendListCacheByUserId[player.UserId] = nil
		updatePartyForLeavingUser(player.UserId)
	end)
end

function PartyInviteService.Destroy()
	if subscription then
		subscription:Disconnect()
		subscription = nil
	end

	if playerRemovingConn then
		playerRemovingConn:Disconnect()
		playerRemovingConn = nil
	end

	if requestRF then
		requestRF.OnServerInvoke = nil
	end

	requestRF = nil
	partyEventRE = nil
	initialized = false
	table.clear(friendListCacheByUserId)
	table.clear(userPartyIdCacheByUserId)
end

function PartyInviteService.GetPartyDataForUser(userId: number): {[string]: any}?
	local partyId = getUserPartyId(userId)
	if not partyId then
		return nil
	end

	local party = getPartyById(partyId)
	if not party then
		clearUserPartyId(userId)
		return nil
	end

	return {
		partyId = party.partyId,
		leaderUserId = party.leaderUserId,
		memberUserIds = table.clone(party.memberUserIds),
	}
end

return PartyInviteService
