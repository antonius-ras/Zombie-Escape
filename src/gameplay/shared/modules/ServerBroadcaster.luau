local ServerBroadcaster = {}

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")

local initialized = false
local running = false
local startTime = os.time()
local serverMap = MemoryStoreService:GetSortedMap("ActiveServers")

local function updateServerInfo()
	local jobId = game.JobId
	if jobId == "" then
		jobId = "Studio_TestServer"
	end

	local data = {
		PlayerCount = #Players:GetPlayers(),
		StartTime = startTime,
		PlaceId = game.PlaceId,
	}

	pcall(function()
		serverMap:SetAsync(jobId, data, 30)
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
end

return ServerBroadcaster
