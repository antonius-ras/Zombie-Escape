local ServerBroadcaster = {}

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")

local initialized = false
local running = false
local startTime = os.time()
local serverMap = MemoryStoreService:GetSortedMap("ActiveServers")
local SERVER_TTL_SECONDS = 30
local PREVIEW_USER_LIMIT = 4
local DEFAULT_SERVER_LABEL = "GAMEPLAY"

local function getServerJobId(): string
	local jobId = game.JobId
	if jobId == "" then
		return "Studio_TestServer"
	end

	return jobId
end

local function getPreviewUserIds(): {number}
	local previewUserIds = {}
	for index, player in ipairs(Players:GetPlayers()) do
		if index > PREVIEW_USER_LIMIT then
			break
		end

		table.insert(previewUserIds, player.UserId)
	end

	return previewUserIds
end

local function getServerLabel(): string
	local workspaceLabel = workspace:GetAttribute("ServerListMapName")
	if type(workspaceLabel) == "string" and workspaceLabel ~= "" then
		return workspaceLabel
	end

	local fallbackLabel = workspace:GetAttribute("MapName")
	if type(fallbackLabel) == "string" and fallbackLabel ~= "" then
		return fallbackLabel
	end

	return DEFAULT_SERVER_LABEL
end

local function removeServerInfo()
	pcall(function()
		serverMap:RemoveAsync(getServerJobId())
	end)
end

local function updateServerInfo()
	local jobId = getServerJobId()
	local playerCount = #Players:GetPlayers()

	local data = {
		PlayerCount = playerCount,
		MaxPlayers = Players.MaxPlayers,
		StartTime = startTime,
		PlaceId = game.PlaceId,
		PreviewUserIds = getPreviewUserIds(),
		MapName = getServerLabel(),
	}

	pcall(function()
		serverMap:SetAsync(jobId, data, SERVER_TTL_SECONDS, playerCount)
	end)
end

function ServerBroadcaster.Init()
	if initialized then
		return
	end

	initialized = true
	running = true

	task.spawn(function()
		while running do
			updateServerInfo()
			task.wait(15)
		end
	end)
end

function ServerBroadcaster.Destroy()
	running = false
	initialized = false
	removeServerInfo()
end

return ServerBroadcaster
