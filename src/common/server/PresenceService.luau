local PresenceService = {}

local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")

local PRESENCE_MAP_NAME = "GlobalPresenceV1"
local PRESENCE_TTL_SECONDS = 40
local HEARTBEAT_INTERVAL_SECONDS = 10
local PRESENCE_READ_CACHE_TTL_SECONDS = 15 -- แก้ไข: เพิ่มเวลา Cache เพื่อลดการเรียก MemoryStore ซ้ำซ้อน

local initialized = false
local running = false
local placeType = "lobby"
local presenceMap = MemoryStoreService:GetHashMap(PRESENCE_MAP_NAME)
local localPresenceByUserId: {[number]: {[string]: any}} = {}
local presenceReadCacheByUserId: {[number]: { found: boolean, value: any, expiresAt: number }} = {}

local playerAddedConn: RBXScriptConnection?
local playerRemovingConn: RBXScriptConnection?

local function getPresenceKey(userId: number): string
	return tostring(userId)
end

local function buildPresencePayload(userId: number): {[string]: any}
	return {
		userId = userId,
		placeType = placeType,
		placeId = game.PlaceId,
		jobId = game.JobId,
		updatedAt = os.time(),
	}
end

local function cachePresenceRead(userId: number, presence: any)
	presenceReadCacheByUserId[userId] = {
		found = presence ~= nil,
		value = presence,
		expiresAt = os.clock() + PRESENCE_READ_CACHE_TTL_SECONDS,
	}
end

local function writePresence(userId: number)
	local payload = buildPresencePayload(userId)
	localPresenceByUserId[userId] = payload
	cachePresenceRead(userId, payload)

	pcall(function()
		presenceMap:SetAsync(getPresenceKey(userId), payload, PRESENCE_TTL_SECONDS)
	end)
end

local function removePresence(userId: number)
	localPresenceByUserId[userId] = nil
	presenceReadCacheByUserId[userId] = nil
	pcall(function()
		presenceMap:RemoveAsync(getPresenceKey(userId))
	end)
end

local function onPlayerAdded(player: Player)
	writePresence(player.UserId)
end

local function onPlayerRemoving(player: Player)
	removePresence(player.UserId)
end

local function heartbeatLoop()
	while running do
		for _, player in ipairs(Players:GetPlayers()) do
			if not running then break end
			writePresence(player.UserId)
			task.wait(0.1) -- แก้ไข: หน่วงเวลาเล็กน้อยเพื่อไม่ให้เรียก MemoryStore ถี่เกินไป (Throttling)
		end
		task.wait(HEARTBEAT_INTERVAL_SECONDS)
	end
end

function PresenceService.Init(currentPlaceType: string?)
	if initialized then
		return
	end

	if currentPlaceType and currentPlaceType ~= "" then
		placeType = currentPlaceType
	end

	initialized = true
	running = true

	for _, player in ipairs(Players:GetPlayers()) do
		writePresence(player.UserId)
	end

	playerAddedConn = Players.PlayerAdded:Connect(onPlayerAdded)
	playerRemovingConn = Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(heartbeatLoop)
end

function PresenceService.GetPresenceByUserIds(userIds: {number}): {[number]: any}
	local result: {[number]: any} = {}
	local now = os.clock()

	for _, userId in ipairs(userIds) do
		local localPresence = localPresenceByUserId[userId]
		if localPresence then
			result[userId] = localPresence
			continue
		end

		local cachedEntry = presenceReadCacheByUserId[userId]
		if cachedEntry and cachedEntry.expiresAt > now then
			if cachedEntry.found then
				result[userId] = cachedEntry.value
			end
			continue
		end

		local ok, presence = pcall(function()
			return presenceMap:GetAsync(getPresenceKey(userId))
		end)
		if ok then
			cachePresenceRead(userId, presence)
			if presence then
				result[userId] = presence
			end
		end
	end

	return result
end

function PresenceService.Destroy()
	if playerAddedConn then
		playerAddedConn:Disconnect()
		playerAddedConn = nil
	end

	if playerRemovingConn then
		playerRemovingConn:Disconnect()
		playerRemovingConn = nil
	end

	running = false
	initialized = false
	table.clear(localPresenceByUserId)
	table.clear(presenceReadCacheByUserId)
end

return PresenceService
