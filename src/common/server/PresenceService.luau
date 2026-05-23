local PresenceService = {}

local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")

local PRESENCE_MAP_NAME = "GlobalPresenceV1"
local USER_PARTY_MAP_NAME = "GlobalUserPartyMapV1"
local PRESENCE_TTL_SECONDS = 40
local HEARTBEAT_INTERVAL_SECONDS = 6
local PRESENCE_READ_CACHE_TTL_SECONDS = 15 -- Cache duration increased to reduce quota usage

local initialized = false
local running = false
local placeType = "lobby"
local presenceMap = MemoryStoreService:GetHashMap(PRESENCE_MAP_NAME)
local userPartyMap = MemoryStoreService:GetHashMap(USER_PARTY_MAP_NAME)
local localPresenceByUserId: {[number]: {[string]: any}} = {}
local presenceReadCacheByUserId: {[number]: { found: boolean, value: any, expiresAt: number }} = {}
local pendingPresenceFetches: {[string]: {thread}} = {}
local partyIdCache: {[number]: { partyId: string? }} = {}
local playerAddedConn: RBXScriptConnection?
local playerRemovingConn: RBXScriptConnection?

local function getPresenceKey(userId: number): string
	return tostring(userId)
end


local function buildPresencePayload(userId: number): {[string]: any}
	-- ใช้ Local Cache แทนการเรียก GetAsync ทุกครั้ง
	local cachedParty = partyIdCache[userId]
	local partyId = nil
	
	if cachedParty then
		partyId = cachedParty.partyId
	else
		local ok, val = pcall(function()
			return userPartyMap:GetAsync(tostring(userId))
		end)
		if ok then 
			partyId = val 
			partyIdCache[userId] = { partyId = partyId }
		end
	end

	return {
		userId = userId,
		placeType = placeType,
		placeId = game.PlaceId,
		jobId = game.JobId,
		partyId = partyId,
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

	local ok, err = pcall(function()
		presenceMap:SetAsync(getPresenceKey(userId), payload, PRESENCE_TTL_SECONDS)
	end)
	if not ok then
		warn(string.format("[PresenceService] Failed to write presence for %d: %s", userId, tostring(err)))
	end
end

local function removePresence(userId: number)
	localPresenceByUserId[userId] = nil
	presenceReadCacheByUserId[userId] = nil
	partyIdCache[userId] = nil
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
		local players = Players:GetPlayers()
		local playerCount = #players
		
		-- คำนวณ throttle time ให้เหมาะสมกับจำนวนผู้เล่น
		-- พยายามให้ลูปทั้งลูปใช้เวลาไม่เกิน 50% ของ PRESENCE_TTL_SECONDS
		local totalBudget = PRESENCE_TTL_SECONDS * 0.5
		local throttle = math.max(0.05, totalBudget / math.max(playerCount, 1))

		-- Heartbeat processing
		for _, player in ipairs(players) do
			if not running then break end
			writePresence(player.UserId)
			task.wait(throttle)
		end
		
		-- Cache cleanup
		local now = os.clock()
		for userId, cacheData in pairs(presenceReadCacheByUserId) do
			if now >= cacheData.expiresAt then
				presenceReadCacheByUserId[userId] = nil
			end
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
	
	local idsToFetch = {}
	local seen = {} -- Deduplication
	
	for _, userId in ipairs(userIds) do
		if seen[userId] then continue end
		seen[userId] = true
		
		local localPresence = localPresenceByUserId[userId]
		if localPresence then
			result[userId] = localPresence
			continue
		end

		local cachedEntry = presenceReadCacheByUserId[userId]
		if cachedEntry and cachedEntry.expiresAt > now then
			if cachedEntry.found then result[userId] = cachedEntry.value end
			continue
		end
		
		table.insert(idsToFetch, userId)
	end

	-- Parallel fetch with strict concurrency limits to prevent quota exhaustion
	if #idsToFetch > 0 then
		local runningThread = coroutine.running()
		local MAX_CONCURRENT_REQUESTS = 15
		local completedCount = 0
		local currentIndex = 0
		local totalToFetch = #idsToFetch
		local resumed = false

		local function resume()
			if resumed then return end
			resumed = true
			task.spawn(runningThread)
		end

		local function fetchNext()
			currentIndex += 1
			local index = currentIndex
			if index > totalToFetch then 
				return 
			end

			local userId = idsToFetch[index]
			local presenceKey = getPresenceKey(userId)

			-- 1. ตรวจสอบว่ากำลังยิงดึงข้อมูลนี้อยู่หรือไม่
			if pendingPresenceFetches[presenceKey] then
				table.insert(pendingPresenceFetches[presenceKey], coroutine.running())
				coroutine.yield() -- รอให้ตัวแรกดึงเสร็จ
				
				-- พอตื่นขึ้นมา ให้ลองดึงข้อมูลจาก Cache
				local cached = presenceReadCacheByUserId[userId]
				if cached and cached.found then result[userId] = cached.value end
				
				completedCount += 1
				if completedCount >= totalToFetch then resume() else fetchNext() end
			else
				-- 2. ถ้าเป็นคนแรกที่ยิงดึง
				pendingPresenceFetches[presenceKey] = {}
				
				task.spawn(function()
					local ok, presence = pcall(function()
						return presenceMap:GetAsync(presenceKey)
					end)

					if ok then
						cachePresenceRead(userId, presence)
						if presence then result[userId] = presence end
					end

					-- 3. ปลุกทุกคนที่รอคิว
					local waitingThreads = pendingPresenceFetches[presenceKey]
					pendingPresenceFetches[presenceKey] = nil
					for _, thread in ipairs(waitingThreads) do
						task.spawn(thread)
					end

					completedCount += 1
					if completedCount >= totalToFetch then
						resume()
					else
						fetchNext()
					end
				end)
			end
		end

		for i = 1, math.min(MAX_CONCURRENT_REQUESTS, totalToFetch) do
			fetchNext()
		end

		if not resumed then
			coroutine.yield()
		end
	end
	return result
end

function PresenceService.UpdatePartyId(userId: number, partyId: string?)
	partyIdCache[userId] = { partyId = partyId }
	
	-- If player is local, trigger an immediate presence update to reflect the change
	if Players:GetPlayerByUserId(userId) then
		task.spawn(writePresence, userId)
	end
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
	table.clear(partyIdCache)
end

return PresenceService