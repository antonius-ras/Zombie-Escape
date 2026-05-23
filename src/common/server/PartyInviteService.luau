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
local DISPLAY_NAME_CACHE_TTL_SECONDS = 3600 -- เพิ่มค่าคงที่สำหรับจำเวลาชื่อผู้เล่น

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
local displayNameCache: {[number]: { name: string, expiresAt: number }} = {}
local friendListCacheByUserId: {[number]: { expiresAt: number, friends: {any}, friendIds: {number} }} = {}
local userPartyIdCacheByUserId: {[number]: { expiresAt: number, value: string? }} = {}
local lastInviteAtByUserId: {[number]: number} = {}

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
	local success, err = pcall(function()
		MessagingService:PublishAsync(PARTY_TOPIC_NAME, payload)
	end)
	if not success then
		warn(string.format("[PartyInviteService] Failed to publish event: %s", tostring(err)))
	end
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

-- เพิ่มฟังก์ชัน UpdateParty สำหรับแก้ปัญหา Race Condition ด้วย UpdateAsync
local function updateParty(partyId: string, transformFunction: (any) -> (any?)): (boolean, any?)
	local updatedValue
	local success, err = pcall(function()
		updatedValue = partyMap:UpdateAsync(partyId, function(oldParty)
			if not oldParty then return nil end
			local updatedParty = transformFunction(oldParty)
			
			-- หากมีการคืนค่าข้อมูลใหม่ ให้จดบันทึกเวลาอัปเดต
			if updatedParty then
				updatedParty.updatedAt = os.time()
			end
			
			-- คืนค่า updatedParty ตรงๆ (ถ้าเป็น nil จะเป็นการลบ Key)
			return updatedParty
		end, PARTY_TTL_SECONDS)
	end)
	if not success then
		warn(string.format("[PartyInviteService] updateParty failed for %s: %s", partyId, tostring(err)))
	end
	return success, updatedValue
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
	if cached and type(cached.name) == "string" and cached.name ~= "" and cached.expiresAt > os.clock() then
		return cached.name
	end

	local player = Players:GetPlayerByUserId(userId)
	if player and type(player.DisplayName) == "string" and player.DisplayName ~= "" then
		displayNameCache[userId] = { name = player.DisplayName, expiresAt = os.clock() + DISPLAY_NAME_CACHE_TTL_SECONDS }
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
				displayNameCache[userId] = { name = displayName, expiresAt = os.clock() + DISPLAY_NAME_CACHE_TTL_SECONDS }
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
	local idsToResolve = {}

	-- ขั้นตอนที่ 1: รวบรวม ID เพื่อนทั้งหมด
	local pageCount = 0
	while true do
		pageCount += 1
		for _, friend in ipairs(pages:GetCurrentPage()) do
			table.insert(friendIds, friend.Id)
			-- ถ้าไม่มี DisplayName มาให้ (หรือเป็นค่าว่าง) ให้จดไว้ไปดึงแบบ Batch
			if not friend.DisplayName or friend.DisplayName == "" then
				table.insert(idsToResolve, friend.Id)
			else
				displayNameCache[friend.Id] = { name = friend.DisplayName, expiresAt = os.clock() + DISPLAY_NAME_CACHE_TTL_SECONDS }
			end
		end
		if pages.IsFinished or pageCount >= 5 then break end
		local advancedOk = pcall(function() pages:AdvanceToNextPageAsync() end)
		if not advancedOk then break end
	end

	-- ขั้นตอนที่ 2: ดึง DisplayName แบบ Batch (แบ่งกลุ่มละ 100 ตามกฎ Roblox)
	if #idsToResolve > 0 then
		for i = 1, #idsToResolve, 100 do
			pcall(function()
				local chunk = table.move(idsToResolve, i, math.min(i + 99, #idsToResolve), 1, {})
				local userInfos = Players:GetUserInfosByUserIdsAsync(chunk)
				for _, info in ipairs(userInfos) do
					displayNameCache[info.Id] = { name = info.DisplayName, expiresAt = os.clock() + DISPLAY_NAME_CACHE_TTL_SECONDS }
				end
			end)
		end
	end

	-- ขั้นตอนที่ 3: ประกอบร่างข้อมูลส่งกลับ
	for _, fId in ipairs(friendIds) do
		table.insert(friends, {
			userId = fId,
			name = if displayNameCache[fId] then displayNameCache[fId].name else tostring(fId),
		})
	end

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
	
	-- แก้ไข: ดึงชื่อคนที่หายไปแบบรวบยอด (Batch) ป้องกันเน็ตเวิร์กคอขวด
	local idsToResolve = {}
	for _, userId in ipairs(party.memberUserIds) do
		if not getPartyMemberName(party, userId) then
			local cached = displayNameCache[userId]
			if not (cached and cached.expiresAt > os.clock()) then
				table.insert(idsToResolve, userId)
			end
		end
	end
	
	if #idsToResolve > 0 then
		pcall(function()
			local userInfos = Players:GetUserInfosByUserIdsAsync(idsToResolve)
			for _, info in ipairs(userInfos) do
				displayNameCache[info.Id] = { name = info.DisplayName, expiresAt = os.clock() + DISPLAY_NAME_CACHE_TTL_SECONDS }
			end
		end)
	end

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
	
	-- Batch fetch party IDs in parallel
	local partyIdsByUserId = {}
	local runningThread = coroutine.running()
	local MAX_CONCURRENT_REQUESTS = 15
	local completedCount = 0
	local totalToFetch = #friendIds
	local resumed = false

	local function resume()
		if resumed then return end
		resumed = true
		task.spawn(runningThread)
	end

	local function fetchPartyId(userId)
		local ok, partyId = pcall(function()
			return userPartyMap:GetAsync(tostring(userId))
		end)
		if ok then
			partyIdsByUserId[userId] = partyId
		end
		
		completedCount += 1
		if completedCount >= totalToFetch then
			resume()
		end
	end

	for i = 1, math.min(MAX_CONCURRENT_REQUESTS, totalToFetch) do
		task.spawn(function()
			for j = i, totalToFetch, MAX_CONCURRENT_REQUESTS do
				fetchPartyId(friendIds[j])
			end
		end)
	end
	
	if totalToFetch > 0 then coroutine.yield() end

	for _, friend in ipairs(friends) do
		local presence = presenceByUserId[friend.userId]
		if not presence then
			continue
		end

		local friendPartyId = partyIdsByUserId[friend.userId]
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
	local now = os.clock()
	local lastInviteAt = lastInviteAtByUserId[player.UserId]
	if lastInviteAt and now - lastInviteAt < 2 then
		return { ok = false, message = "too_fast" }
	end
	lastInviteAtByUserId[player.UserId] = now

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

	local ok = pcall(function()
		inviteMap:SetAsync(invite.inviteId, invite, INVITE_TTL_SECONDS)
	end)

	if not ok then
		return { ok = false, message = "invite_save_failed" }
	end

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

	-- ใช้ UpdateAsync เพื่อแก้ปัญหา Race Condition ตอนรับคนเข้าปาร์ตี้
	local errorMessage = nil

	local success, updatedPartySnapshot = updateParty(invite.partyId, function(party)
		if not party then
			errorMessage = "party_not_found"
			return nil -- กรณีปาร์ตี้ไม่มีอยู่แล้ว (หรือถูกลบ) ให้คืน nil ตามเดิม
		end

		if #party.memberUserIds >= MAX_PARTY_SIZE then
			errorMessage = "party_full"
			return party -- คืนค่าเดิมกลับไปเพื่อยกเลิกการอัปเดต โดยไม่ลบปาร์ตี้ทิ้ง
		end

		if not containsUser(party.memberUserIds, player.UserId) then
			table.insert(party.memberUserIds, player.UserId)
		end
		
		ensureMemberNames(party)
		party.memberNames[tostring(player.UserId)] = player.DisplayName
		party.memberNames[tostring(invite.fromUserId)] = invite.fromName
		
		errorMessage = nil -- Clear error on successful pass
		return party
	end)

	removeInvite(inviteId)

	if not success or errorMessage or not updatedPartySnapshot then
		return { ok = false, message = errorMessage or "update_failed" }
	end

	setUserPartyId(player.UserId, updatedPartySnapshot.partyId)
	broadcastPartyUpdate(updatedPartySnapshot)
	
	return { ok = true, data = buildPartySnapshot(updatedPartySnapshot) }
end

local function handleLeaveParty(player: Player)
	local partyId = getUserPartyId(player.UserId)
	if not partyId then
		return { ok = false, message = "not_in_party" }
	end

	local wasDeleted = false

	local success, updatedPartySnapshot = updateParty(partyId, function(party)
		if not party then return nil end
		
		removeUser(party.memberUserIds, player.UserId)
		clearPartyMemberName(party, player.UserId)
		
		if #party.memberUserIds == 0 then
			wasDeleted = true
			return nil -- ลบปาร์ตี้ถ้าไม่เหลือใคร
		end

		if party.leaderUserId == player.UserId then
			party.leaderUserId = party.memberUserIds[1]
		end
		
		return party
	end)

	clearUserPartyId(player.UserId)
	broadcastPartyCleared({ player.UserId })

	if not success then return { ok = false, message = "update_failed" } end
	if wasDeleted then return { ok = true } end
	
	if updatedPartySnapshot then
		broadcastPartyUpdate(updatedPartySnapshot)
	end
	return { ok = true, data = if updatedPartySnapshot then buildPartySnapshot(updatedPartySnapshot) else nil }
end

local function handleKickMember(player: Player, payload: {[string]: any})
	local targetUserId = tonumber(payload.targetUserId)
	if not targetUserId or targetUserId == player.UserId then
		return { ok = false, message = "invalid_target" }
	end

	local partyId = getUserPartyId(player.UserId)
	if not partyId then return { ok = false, message = "not_in_party" } end

	local errorMessage = nil

	local success, updatedPartySnapshot = updateParty(partyId, function(party)
		if not party then
			errorMessage = "party_not_found"
			return nil
		end
		if party.leaderUserId ~= player.UserId then
			errorMessage = "only_leader_can_kick"
			return party -- แก้ไข: คืนค่าเดิมเพื่อยกเลิก โดยไม่ลบปาร์ตี้ทิ้ง
		end
		if not containsUser(party.memberUserIds, targetUserId) then
			errorMessage = "target_not_in_party"
			return party -- แก้ไข: คืนค่าเดิม
		end

		removeUser(party.memberUserIds, targetUserId)
		clearPartyMemberName(party, targetUserId)
		
		if #party.memberUserIds == 0 then return nil end -- ลบจริงๆ เมื่อไม่มีใครเหลือ
		
		errorMessage = nil
		return party
	end)

	if not success or errorMessage or not updatedPartySnapshot then
		return { ok = false, message = errorMessage or "update_failed" }
	end

	clearUserPartyId(targetUserId)
	broadcastPartyCleared({ targetUserId })
	broadcastPartyUpdate(updatedPartySnapshot)
	return { ok = true, data = buildPartySnapshot(updatedPartySnapshot) }
end

local function handleDisbandParty(player: Player)
	local partyId = getUserPartyId(player.UserId)
	if not partyId then return { ok = false, message = "not_in_party" } end

	local membersToClear = {}
	local success = updateParty(partyId, function(party)
		if not party then return nil end
		if party.leaderUserId ~= player.UserId then return party end -- ไม่ให้ลบถ้าไม่ใช่หัวหน้า

		membersToClear = table.clone(party.memberUserIds)
		return nil -- คืนค่า nil เพื่อลบข้อมูลปาร์ตี้ออกจาก MemoryStore จริงๆ
	end)

	if not success then return { ok = false, message = "disband_failed" } end

	for _, userId in ipairs(membersToClear) do
		clearUserPartyId(userId)
	end
	broadcastPartyCleared(membersToClear)
	return { ok = true }
end

local function updatePartyForLeavingUser(userId: number)
	local partyId = getUserPartyId(userId)
	if not partyId then return end

	local wasDeleted = false

	local success, updatedPartySnapshot = updateParty(partyId, function(party)
		if not party then return nil end
		removeUser(party.memberUserIds, userId)
		clearPartyMemberName(party, userId)
		
		if #party.memberUserIds == 0 then
			wasDeleted = true
			return nil -- ลบปาร์ตี้
		end

		if party.leaderUserId == userId then
			party.leaderUserId = party.memberUserIds[1]
		end
		
		return party
	end)
	
	clearUserPartyId(userId)

	-- แก้ไข: ย้าย Side Effects ออกมาข้างนอกลูปการเซฟ (Pure Function)
	if success then
		broadcastPartyCleared({ userId })
		if not wasDeleted and updatedPartySnapshot then
			broadcastPartyUpdate(updatedPartySnapshot)
		end
	end
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

	pcall(function()
		subscription = MessagingService:SubscribeAsync(PARTY_TOPIC_NAME, onPartyMessage)
	end)
	
	playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
		friendListCacheByUserId[player.UserId] = nil
		displayNameCache[player.UserId] = nil -- ป้องกัน Memory Leak จากผู้เล่นที่ออกจากเซิร์ฟเวอร์
		lastInviteAtByUserId[player.UserId] = nil -- ลบ Rate Limit Cache
		updatePartyForLeavingUser(player.UserId)
	end)
	
	-- ลูปสำหรับทำความสะอาด Cache ทุกๆ 60 วินาที
	task.spawn(function()
		while initialized do
			task.wait(60)
			local now = os.clock()
			
			for userId, data in pairs(displayNameCache) do
				if data.expiresAt and data.expiresAt < now then
					displayNameCache[userId] = nil
				end
			end
			
			for userId, data in pairs(friendListCacheByUserId) do
				if data.expiresAt and data.expiresAt < now then
					friendListCacheByUserId[userId] = nil
				end
			end
			
			for userId, data in pairs(userPartyIdCacheByUserId) do
				if data.expiresAt and data.expiresAt < now then
					userPartyIdCacheByUserId[userId] = nil
				end
			end
		end
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
	table.clear(displayNameCache) -- ล้าง Cache เมื่อปิดระบบ
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