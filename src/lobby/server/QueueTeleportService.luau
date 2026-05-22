local QueueTeleportService = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local QueueConfig = require((ReplicatedStorage :: any).shared:WaitForChild("QueueConfig"))
local PartyInviteService = require((ServerScriptService :: any).common:WaitForChild("PartyInviteService"))

local REQUEST_REMOTE_NAME = "QueueTeleportRequest"
local STATUS_REMOTE_NAME = "QueueTeleportStatus"
local REQUEST_COOLDOWN_SECONDS = 1.5

local initialized = false
local requestConnection: RBXScriptConnection?
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
		sendTeleportFailed(player, "Not in party")
		return
	end

	if partyData.leaderUserId ~= player.UserId then
		sendTeleportFailed(player, "Only leader can start matchmaking")
		return
	end

	local memberUserIds = partyData.memberUserIds
	if #memberUserIds == 0 then
		sendTeleportFailed(player, "Party is empty")
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

		-- แก้ไข: ดึงรายชื่อสมาชิกที่อัปเดตที่สุดก่อนวาร์ป (ป้องกันกรณีมีคนออกระหว่างนับถอยหลัง)
		local currentParty = PartyInviteService.GetPartyDataForUser(player.UserId)
		local playersToTeleportIds = if currentParty then currentParty.memberUserIds else { player.UserId }

		local partyPlayers, missingCount = getPartyPlayers(playersToTeleportIds)
		if #partyPlayers == 0 or missingCount > 0 then
			firePartyStatus(playersToTeleportIds, "party_queue_failed", "Some party members are not ready")
			return
		end

		local ok, err = pcall(function()
			local teleportOptions = Instance.new("TeleportOptions")
			-- สำหรับกรณีที่มี partyId เราสามารถส่งไปเป็นข้อมูลได้ (ถ้าต้องการ)
			if currentParty then
				-- ตัวอย่าง: teleportOptions:SetTeleportData({ partyId = currentParty.partyId })
			end
			
			TeleportService:TeleportAsync(QueueConfig.GameplayPlaceId, partyPlayers, teleportOptions)
		end)
		if not ok then
			warn("[QueueTeleportService] Party teleport failed", err)
			firePartyStatus(playersToTeleportIds, "party_queue_failed", "Party teleport failed")
		end
	end)
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
		sendTeleportFailed(player, "Leave the party before starting solo")
		return
	end

	local success, err = pcall(function()
		TeleportService:TeleportAsync(QueueConfig.GameplayPlaceId, { player })
	end)

	if not success then
		warn("[QueueTeleportService] Solo teleport failed for", player.Name, err)
		sendTeleportFailed(player, "Teleport failed")
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
end

function QueueTeleportService.Destroy()
	if requestConnection then
		requestConnection:Disconnect()
		requestConnection = nil
	end

	requestEvent = nil
	statusEvent = nil
	lastRequestAtByUserId = {}
	partyQueueStateByPartyId = {}
	initialized = false
end

return QueueTeleportService