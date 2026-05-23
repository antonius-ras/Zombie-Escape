local QueueTeleportService = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local MessagingService = game:GetService("MessagingService")

local QueueConfig = require((ReplicatedStorage :: any).shared:WaitForChild("QueueConfig"))
local LocalizationKeys = require((ReplicatedStorage :: any).common.modules:WaitForChild("LocalizationKeys"))
local PartyInviteService = require((ServerScriptService :: any).common:WaitForChild("PartyInviteService"))

local REQUEST_REMOTE_NAME = "QueueTeleportRequest"
local STATUS_REMOTE_NAME = "QueueTeleportStatus"
local PARTY_TELEPORT_TOPIC = "PartyTeleportEvent"
local REQUEST_COOLDOWN_SECONDS = 1.5

local initialized = false
local requestConnection: RBXScriptConnection?
local playerRemovingConn: RBXScriptConnection?
local teleportSubscription: RBXScriptConnection?
local requestEvent: RemoteEvent?
local statusEvent: RemoteEvent?
local lastRequestAtByUserId: {[number]: number} = {}
local partyQueueStateByPartyId: {[string]: { token: number, cancelled: boolean }} = {}
local nextPartyQueueToken = 0

local function getOrCreateRemote(remotesFolder: Instance, remoteName: string): RemoteEvent
	local existing = remotesFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local created = Instance.new("RemoteEvent")
	created.Name = remoteName
	created.Parent = remotesFolder
	return created
end

local function sendTeleportFailed(player: Player, message: string)
	if not statusEvent then
		return
	end
	statusEvent:FireClient(player, "failed", message)
end

local function firePartyStatus(memberUserIds: {number}, status: string, value: any?)
	if not statusEvent then
		return
	end

	for _, userId in ipairs(memberUserIds) do
		local member = Players:GetPlayerByUserId(userId)
		if member then
			statusEvent:FireClient(member, status, value)
		end
	end
end

local function getPartyPlayers(memberUserIds: {number}): ({Player}, number)
	local players = {}
	local missingCount = 0
	for _, userId in ipairs(memberUserIds) do
		local member = Players:GetPlayerByUserId(userId)
		if member then
			table.insert(players, member)
		else
			missingCount += 1
		end
	end
	return players, missingCount
end

local function startPartyQueue(player: Player)
	local partyData = PartyInviteService.GetPartyDataForUser(player.UserId)
	if not partyData then
		sendTeleportFailed(player, LocalizationKeys["errors.not_in_party"])
		return
	end

	if partyData.leaderUserId ~= player.UserId then
		sendTeleportFailed(player, LocalizationKeys["errors.only_leader_can_start"])
		return
	end

	local memberUserIds = partyData.memberUserIds
	if #memberUserIds == 0 then
		sendTeleportFailed(player, LocalizationKeys["errors.party_empty"])
		return
	end

	if partyQueueStateByPartyId[partyData.partyId] then
		return
	end

	nextPartyQueueToken += 1
	local queueState = {
		token = nextPartyQueueToken,
		cancelled = false,
	}
	partyQueueStateByPartyId[partyData.partyId] = queueState

	local countdown = QueueConfig.PartyCountdownSeconds or QueueConfig.SoloCountdownSeconds
	firePartyStatus(memberUserIds, "party_queue_started", countdown)

	task.spawn(function()
		local remaining = countdown
		while remaining > 0 do
			task.wait(1)
			if partyQueueStateByPartyId[partyData.partyId] ~= queueState or queueState.cancelled then
				return
			end

			remaining -= 1
			firePartyStatus(memberUserIds, "party_queue_tick", remaining)
		end

		if partyQueueStateByPartyId[partyData.partyId] ~= queueState or queueState.cancelled then
			return
		end

		partyQueueStateByPartyId[partyData.partyId] = nil
		firePartyStatus(memberUserIds, "party_queue_teleporting")

		-- ตรวจสอบว่าหัวหน้าปาร์ตี้ยังอยู่ในเซิร์ฟเวอร์หรือไม่ (Code Review Fix)
		if not player:IsDescendantOf(Players) then
			firePartyStatus(memberUserIds, "party_queue_failed", LocalizationKeys["errors.leader_left"])
			return
		end

		-- Get the latest party member list immediately before teleporting (Code Review Fix)
		local currentParty = PartyInviteService.GetPartyDataForUser(player.UserId)
		if not currentParty or currentParty.partyId ~= partyData.partyId then
			firePartyStatus(memberUserIds, "party_queue_failed", LocalizationKeys["errors.not_in_party"])
			return
		end

		-- แยกสมาชิกในปาร์ตี้เป็น Local (ในเซิร์ฟเวอร์เดียวกัน) และ Remote (เซิร์ฟเวอร์อื่น)
		local localPlayers = {}
		local remoteUserIds = {}

		for _, userId in ipairs(currentParty.memberUserIds) do
			local p = Players:GetPlayerByUserId(userId)
			if p then
				table.insert(localPlayers, p)
			else
				table.insert(remoteUserIds, userId)
			end
		end

		-- Teleport Local Players ทันที
		if #localPlayers > 0 then
			local ok, accessCode = pcall(function()
				return TeleportService:ReserveServer(QueueConfig.GameplayPlaceId)
			end)

			if ok then
				local teleportOptions = Instance.new("TeleportOptions")
				teleportOptions.ReservedServerAccessCode = accessCode
				
				local teleportSuccess, teleportError = pcall(function()
					TeleportService:TeleportAsync(QueueConfig.GameplayPlaceId, localPlayers, teleportOptions)
				end)
				
				if not teleportSuccess then
					warn("[QueueTeleportService] TeleportAsync failed:", teleportError)
					firePartyStatus(currentParty.memberUserIds, "party_queue_failed", LocalizationKeys["errors.teleport_failed"])
					return
				end

				-- ส่ง AccessCode ไปให้ Remote Players เพื่อให้เขาวาร์ปตามมา
				if #remoteUserIds > 0 then
					local pubSuccess, pubError = pcall(function()
						MessagingService:PublishAsync(PARTY_TELEPORT_TOPIC, {
							memberUserIds = remoteUserIds,
							accessCode = accessCode,
							placeId = QueueConfig.GameplayPlaceId
						})
					end)
					if not pubSuccess then
						warn("[QueueTeleportService] Failed to publish teleport event:", pubError)
						firePartyStatus(currentParty.memberUserIds, "party_queue_failed", LocalizationKeys["errors.teleport_failed"])
					end
				end
			else
				warn("[QueueTeleportService] Failed to reserve server:", accessCode)
				firePartyStatus(currentParty.memberUserIds, "party_queue_failed", LocalizationKeys["errors.teleport_failed"])
			end
		end
	end)
end

-- รับคำสั่งวาร์ปข้ามเซิร์ฟเวอร์
local function handlePartyTeleportEvent(message)
	local data = message.Data
	if type(data) ~= "table" then return end
	
	local playersToTeleport = {} -- scope local ภายในฟังก์ชัน
	for _, userId in ipairs(data.memberUserIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(playersToTeleport, player)
		end
	end
	
	if #playersToTeleport > 0 and data.placeId == QueueConfig.GameplayPlaceId then
		local teleportOptions = Instance.new("TeleportOptions")
		teleportOptions.ReservedServerAccessCode = data.accessCode
		pcall(function()
			TeleportService:TeleportAsync(data.placeId, playersToTeleport, teleportOptions)
		end)
	end
end

local function cancelPartyQueue(player: Player)
	local partyData = PartyInviteService.GetPartyDataForUser(player.UserId)
	if not partyData then
		return
	end

	local queueState = partyQueueStateByPartyId[partyData.partyId]
	if not queueState then
		return
	end

	queueState.cancelled = true
	partyQueueStateByPartyId[partyData.partyId] = nil
	firePartyStatus(partyData.memberUserIds, "party_queue_cancelled", player.DisplayName)
end

local function onQueueTeleportRequest(player: Player, mode: string)
	local now = os.clock()
	local lastRequestAt = lastRequestAtByUserId[player.UserId]
	if lastRequestAt and now - lastRequestAt < REQUEST_COOLDOWN_SECONDS then
		return
	end
	lastRequestAtByUserId[player.UserId] = now

	if mode == "party_start" then
		startPartyQueue(player)
		return
	end

	if mode == "party_cancel" then
		cancelPartyQueue(player)
		return
	end

	if mode ~= "solo" then
		return
	end

	if PartyInviteService.GetPartyDataForUser(player.UserId) then
		sendTeleportFailed(player, LocalizationKeys["errors.leave_party_before_solo"])
		return
	end

	local success, err = pcall(function()
		TeleportService:TeleportAsync(QueueConfig.GameplayPlaceId, { player })
	end)

	if not success then
		warn("[QueueTeleportService] Solo teleport failed for", player.Name, err)
		sendTeleportFailed(player, LocalizationKeys["errors.teleport_failed"])
	end
end

function QueueTeleportService.Init()
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

	requestEvent = getOrCreateRemote(remotesFolder, REQUEST_REMOTE_NAME)
	statusEvent = getOrCreateRemote(remotesFolder, STATUS_REMOTE_NAME)

	requestConnection = requestEvent.OnServerEvent:Connect(onQueueTeleportRequest)
	playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
		lastRequestAtByUserId[player.UserId] = nil
	end)

	pcall(function()
		teleportSubscription = MessagingService:SubscribeAsync(PARTY_TELEPORT_TOPIC, handlePartyTeleportEvent)
	end)
end

function QueueTeleportService.Destroy()
	if requestConnection then
		requestConnection:Disconnect()
		requestConnection = nil
	end
	if playerRemovingConn then
		playerRemovingConn:Disconnect()
		playerRemovingConn = nil
	end
	if teleportSubscription then
		teleportSubscription:Disconnect()
		teleportSubscription = nil
	end

	requestEvent = nil
	statusEvent = nil
	table.clear(lastRequestAtByUserId)
	table.clear(partyQueueStateByPartyId)
	initialized = false
end

return QueueTeleportService