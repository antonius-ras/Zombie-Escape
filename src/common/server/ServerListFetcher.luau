local ServerListFetcher = {}

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local initialized = false
local serverMap = MemoryStoreService:GetSortedMap("ActiveServers")

function ServerListFetcher.Init()
	if initialized then
		return
	end

	initialized = true

	local getServersFunc = ReplicatedStorage:WaitForChild("GetServersInfo")

	-- เมื่อ UI ฝั่งผู้เล่นขอข้อมูลมา ให้ทำงานฟังก์ชันนี้
	getServersFunc.OnServerInvoke = function(_player)
		local success, data = pcall(function()
			return serverMap:GetRangeAsync(Enum.SortDirection.Descending, 50)
		end)

		local servers = {}
		if success and data then
			for _, entry in pairs(data) do
				servers[entry.key] = entry.value
			end
		end

		return servers
	end
end

return ServerListFetcher
