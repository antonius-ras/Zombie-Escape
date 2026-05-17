local ServerListFetcher = {}

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local PartyInviteService = require((ServerScriptService :: any).common:WaitForChild("PartyInviteService"))

local initialized = false
local serverMap = MemoryStoreService:GetSortedMap("ActiveServers")
local GET_SERVERS_RF_NAME = "GetServersInfo"
local JOIN_SERVER_RF_NAME = "JoinServerByJob"
local IS_STUDIO = RunService:IsStudio()

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

local function getPlayersForServerJoin(player: Player): ({Player}?, string?)
	local partyData = PartyInviteService.GetPartyDataForUser(player.UserId)
	if not partyData then
		return { player }, nil
	end

	if partyData.leaderUserId ~= player.UserId then
		return nil, "not_party_leader"
	end

	local memberUserIds = partyData.memberUserIds
	if type(memberUserIds) ~= "table" or #memberUserIds == 0 then
		return nil, "party_member_missing"
	end

	local partyPlayers, missingCount = getPartyPlayers(memberUserIds)
	if #partyPlayers == 0 or missingCount > 0 then
		return nil, "party_member_missing"
	end

	return partyPlayers, nil
end

local function getOrCreateRemoteFunction(name: string): RemoteFunction
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	local remoteFunction = Instance.new("RemoteFunction")
	remoteFunction.Name = name
	remoteFunction.Parent = ReplicatedStorage
	return remoteFunction
end

local function buildServerEntries(): {any}
	local success, data = pcall(function()
		return serverMap:GetRangeAsync(Enum.SortDirection.Descending, 50)
	end)

	local servers = {}
	if not success or not data then
		return servers
	end

	for _, entry in ipairs(data) do
		local value = entry.value
		if type(value) ~= "table" then
			continue
		end

		local playerCount = math.max(0, tonumber(value.PlayerCount) or 0)
		local maxPlayers = math.max(playerCount, tonumber(value.MaxPlayers) or 0)
		local jobId = tostring(entry.key)
		local canJoin = not IS_STUDIO and jobId ~= "Studio_TestServer"
		if maxPlayers > 0 and playerCount >= maxPlayers then
			canJoin = false
		end

		table.insert(servers, {
			jobId = jobId,
			playerCount = playerCount,
			maxPlayers = maxPlayers,
			startTime = tonumber(value.StartTime) or 0,
			placeId = tonumber(value.PlaceId) or 0,
			previewUserIds = if type(value.PreviewUserIds) == "table" then table.clone(value.PreviewUserIds) else {},
			mapName = if type(value.MapName) == "string" then value.MapName else "",
			canJoin = canJoin,
		})
	end

	table.sort(servers, function(left, right)
		if left.playerCount == right.playerCount then
			return left.startTime > right.startTime
		end

		return left.playerCount > right.playerCount
	end)

	return servers
end

function ServerListFetcher.Init()
	if initialized then
		return
	end

	initialized = true

	local getServersFunc = getOrCreateRemoteFunction(GET_SERVERS_RF_NAME)
	local joinServerFunc = getOrCreateRemoteFunction(JOIN_SERVER_RF_NAME)

	-- เมื่อ UI ฝั่งผู้เล่นขอข้อมูลมา ให้ทำงานฟังก์ชันนี้
	getServersFunc.OnServerInvoke = function(_player)
		return buildServerEntries()
	end

	joinServerFunc.OnServerInvoke = function(player: Player, jobId: string)
		if type(jobId) ~= "string" or jobId == "" then
			return { ok = false, message = "invalid_server" }
		end

		if IS_STUDIO then
			return { ok = false, message = "studio_teleport_unsupported" }
		end

		if jobId == "Studio_TestServer" then
			return { ok = false, message = "studio_server_unavailable" }
		end

		local success, serverInfo = pcall(function()
			return serverMap:GetAsync(jobId)
		end)
		if not success or type(serverInfo) ~= "table" then
			return { ok = false, message = "server_unavailable" }
		end

		local placeId = tonumber(serverInfo.PlaceId)
		if not placeId or placeId <= 0 then
			return { ok = false, message = "invalid_place" }
		end

		local playersToTeleport, playerMessage = getPlayersForServerJoin(player)
		if not playersToTeleport then
			return { ok = false, message = playerMessage or "join_failed" }
		end

		local playerCount = math.max(0, tonumber(serverInfo.PlayerCount) or 0)
		local maxPlayers = math.max(playerCount, tonumber(serverInfo.MaxPlayers) or 0)
		if maxPlayers > 0 then
			local availableSlots = math.max(0, maxPlayers - playerCount)
			if availableSlots <= 0 then
				return { ok = false, message = "server_full" }
			end

			if #playersToTeleport > availableSlots then
				return { ok = false, message = "party_too_large" }
			end
		end

		local teleportOk, teleportError = pcall(function()
			local teleportOptions = Instance.new("TeleportOptions")
			teleportOptions.ServerInstanceId = jobId
			TeleportService:TeleportAsync(placeId, playersToTeleport, teleportOptions)
		end)
		if not teleportOk then
			warn("[ServerListFetcher] Join server failed", teleportError)
			return { ok = false, message = "join_failed" }
		end

		return { ok = true }
	end
end

return ServerListFetcher
