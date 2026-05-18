local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerListClientManager = {}

local GET_SERVERS_RF_NAME = "GetServersInfo"
local JOIN_SERVER_RF_NAME = "JoinServerByJob"

local initialized = false
local getServersRF: RemoteFunction
local joinServerRF: RemoteFunction

local function normalizeServers(rawServers: {any}?): {any}
	local servers = {}
	if type(rawServers) ~= "table" then
		return servers
	end

	for _, rawServer in ipairs(rawServers) do
		if type(rawServer) ~= "table" then
			continue
		end

		local jobId = tostring(rawServer.jobId or "")
		if jobId == "" then
			continue
		end

		local previewUserIds = {}
		if type(rawServer.previewUserIds) == "table" then
			for _, rawUserId in ipairs(rawServer.previewUserIds) do
				local userId = tonumber(rawUserId)
				if userId and userId > 0 then
					table.insert(previewUserIds, userId)
				end
			end
		end

		table.insert(servers, {
			jobId = jobId,
			playerCount = math.max(0, tonumber(rawServer.playerCount) or 0),
			maxPlayers = math.max(0, tonumber(rawServer.maxPlayers) or 0),
			startTime = tonumber(rawServer.startTime) or 0,
			placeId = tonumber(rawServer.placeId) or 0,
			previewUserIds = previewUserIds,
			mapName = if type(rawServer.mapName) == "string" then rawServer.mapName else "",
			canJoin = rawServer.canJoin ~= false,
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

function ServerListClientManager.Init()
	if initialized then
		return
	end

	local remotesFolder = ReplicatedStorage:WaitForChild("shared"):WaitForChild("Remotes")
	getServersRF = remotesFolder:WaitForChild(GET_SERVERS_RF_NAME)
	joinServerRF = remotesFolder:WaitForChild(JOIN_SERVER_RF_NAME)
	initialized = true
end

function ServerListClientManager.GetServers(): {any}
	if not initialized then
		ServerListClientManager.Init()
	end

	local ok, response = pcall(function()
		return getServersRF:InvokeServer()
	end)
	if not ok then
		return {}
	end

	return normalizeServers(response)
end

function ServerListClientManager.JoinServer(jobId: string): (boolean, string?)
	if not initialized then
		ServerListClientManager.Init()
	end

	local ok, response = pcall(function()
		return joinServerRF:InvokeServer(jobId)
	end)
	if not ok then
		return false, "join_request_failed"
	end

	if response and response.ok then
		return true, nil
	end

	return false, response and response.message or "join_failed"
end

return ServerListClientManager