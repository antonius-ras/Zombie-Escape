-- ============================================================
-- DataManager.luau | ModuleScript (Server-side)
-- Description: Manages loading/saving player data using ProfileService
--              with real-time data synchronization to the client.
-- ============================================================

local DataManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileService = require((ReplicatedStorage :: any).common.modules.ProfileService)

-- Remote Events for Server <-> Client synchronization
local remotes = ReplicatedStorage:FindFirstChild("common") and ReplicatedStorage.common:FindFirstChild("remotes")

-- Create remotes folder if it doesn't exist
if not remotes then
	local common = ReplicatedStorage:FindFirstChild("common") or Instance.new("Folder")
	common.Name = "common"
	common.Parent = ReplicatedStorage
	remotes = Instance.new("Folder")
	remotes.Name = "remotes"
	remotes.Parent = common
end

local function getOrCreateRemote(className: string, name: string)
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end

-- DataSync: Server → Client when data updates
local DataSyncEvent: RemoteEvent = getOrCreateRemote("RemoteEvent", "DataSync")
-- RequestData: Client requests data upon scene reload
local RequestDataFunction: RemoteFunction = getOrCreateRemote("RemoteFunction", "RequestData")

-- Profile Template & Store

local ProfileTemplate = {
	Coins = 0,
	TotalWins = 0,
	TotalHits = 0,
	KillsZombie = 0,
	KillsHuman = 0,
	inventory = {},
}

local ProfileStore = ProfileService.GetProfileStore("PlayerData_v1", ProfileTemplate)
local Profiles: { [Player]: any } = {}

local initialized = false
local playerAddedConn: RBXScriptConnection?
local playerRemovingConn: RBXScriptConnection?

-- Internal Helpers

-- Deep copy helper function to prevent external modification of table data references
local function deepCopy<T>(original: T): T
	if type(original) ~= "table" then
		return original
	end

	local copy = {}
	for k, v in pairs(original :: any) do
		if type(v) == "table" then
			copy[k] = deepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy :: any
end

-- Sync leaderstats (Coins only)
local function syncLeaderstats(player: Player, profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local coinsValue = leaderstats:FindFirstChild("Coins")
	if coinsValue and coinsValue:IsA("IntValue") then
		coinsValue.Value = profile.Data.Coins
	end
end

local function cloneInventory(inventory)
	return deepCopy(inventory or {})
end

local function ensureInventory(profile)
	if type(profile.Data.inventory) ~= "table" then
		profile.Data.inventory = {}
	end
end

-- Synchronizes full data structure to the specific client
local function syncClientFull(player: Player, profile)
	DataSyncEvent:FireClient(player, {
		Coins = profile.Data.Coins,
		TotalWins = profile.Data.TotalWins,
		TotalHits = profile.Data.TotalHits,
		KillsZombie = profile.Data.KillsZombie,
		KillsHuman = profile.Data.KillsHuman,
		inventory = cloneInventory(profile.Data.inventory),
	})
end

-- Synchronizes a specific updated key to the client
local function syncClientKey(player: Player, key: string, value: any)
	DataSyncEvent:FireClient(player, { [key] = value })
end

-- Player Lifecycle

local function PlayerAdded(player: Player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile() -- Fills missing profile template keys automatically
		ensureInventory(profile)

		profile:ListenToRelease(function()
			Profiles[player] = nil
			player:Kick("Data session conflict detected. Please rejoin the game.")
		end)

		if player:IsDescendantOf(Players) then
			Profiles[player] = profile

			-- Create Roblox leaderstats
			local leaderstats = player:FindFirstChild("leaderstats") or Instance.new("Folder")
			leaderstats.Name = "leaderstats"
			leaderstats.Parent = player

			local coinsValue = leaderstats:FindFirstChild("Coins")
			if not coinsValue then
				coinsValue = Instance.new("IntValue")
				coinsValue.Name = "Coins"
				coinsValue.Parent = leaderstats
			end
			coinsValue.Value = profile.Data.Coins

			-- Full sync data to the client right after successful loading
			syncClientFull(player, profile)

			print("Successfully loaded data for " .. player.Name .. ":", profile.Data)
		else
			profile:Release()
		end
	else
		player:Kick("Database server failure. Failed to load profile data.")
	end
end

local function PlayerRemoving(player: Player)
	local profile = Profiles[player]
	if profile ~= nil then
		profile:Release()
		Profiles[player] = nil
	end
end

-- RequestData Handler (Triggered by client scene changes)

RequestDataFunction.OnServerInvoke = function(player: Player)
	local profile = Profiles[player]
	if profile == nil then
		return nil
	end
	return {
		Coins = profile.Data.Coins,
		TotalWins = profile.Data.TotalWins,
		TotalHits = profile.Data.TotalHits,
		KillsZombie = profile.Data.KillsZombie,
		KillsHuman = profile.Data.KillsHuman,
		inventory = cloneInventory(profile.Data.inventory),
	}
end

-- Public API

function DataManager.GetPlayerProfile(player: Player)
	return Profiles[player]
end

-- Returns a deep copy to prevent direct modification of profile data tables
function DataManager.GetPlayerData(player: Player)
	local profile = Profiles[player]
	return profile and deepCopy(profile.Data) or nil
end

function DataManager.GetPlayerValue(player: Player, key: string)
	local profile = Profiles[player]
	if profile == nil then
		return nil
	end

	local value = profile.Data[key]
	if type(value) == "table" then
		return deepCopy(value)
	end
	return value
end

-- Set key value with dynamic data type template verification
function DataManager.SetPlayerValue(player: Player, key: string, value: any): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end

	-- Validate value data type matching against ProfileTemplate
	if ProfileTemplate[key] ~= nil and type(value) ~= type(ProfileTemplate[key]) then
		return false
	end

	if key == "inventory" and type(value) ~= "table" then
		return false
	end

	profile.Data[key] = value

	if key == "Coins" then
		syncLeaderstats(player, profile)
	end

	if key == "inventory" then
		ensureInventory(profile)
	end

	if key == "inventory" then
		syncClientKey(player, key, cloneInventory(profile.Data.inventory))
	else
		syncClientKey(player, key, value)
	end
	return true
end

-- Protected tracking for callback modifications with warning output alerts
function DataManager.UpdatePlayerData(player: Player, updater: (data: {}) -> ()): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end
	if type(updater) ~= "function" then
		return false
	end

	local success, err = pcall(updater, profile.Data)
	if success then
		ensureInventory(profile)
		syncLeaderstats(player, profile)
		syncClientFull(player, profile)
	else
		warn("UpdatePlayerData failed for " .. player.Name .. ": " .. tostring(err))
	end
	return success
end

function DataManager.AddCoins(player: Player, amount: number): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end
	if type(amount) ~= "number" then
		return false
	end
	return DataManager.SetPlayerValue(player, "Coins", profile.Data.Coins + amount)
end

function DataManager.AddValue(player: Player, key: string, amount: number): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end

	if type(amount) ~= "number" then
		return false
	end

	local currentValue = profile.Data[key]
	if type(currentValue) ~= "number" then
		return false
	end

	return DataManager.SetPlayerValue(player, key, currentValue + amount)
end

function DataManager.GetInventory(player: Player)
	local profile = Profiles[player]
	if profile == nil then
		return nil
	end

	ensureInventory(profile)
	return cloneInventory(profile.Data.inventory)
end

-- Clean entry validation updates for non-positive absolute amount counts
function DataManager.SetInventoryItem(player: Player, itemName: string, amount: number): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end

	if type(itemName) ~= "string" or itemName == "" then
		return false
	end

	if type(amount) ~= "number" then
		return false
	end

	ensureInventory(profile)
	if amount <= 0 then
		profile.Data.inventory[itemName] = nil
	else
		profile.Data.inventory[itemName] = amount
	end

	syncClientKey(player, "inventory", cloneInventory(profile.Data.inventory))
	return true
end

-- Clean entry validation updates for non-positive relative item accumulation
function DataManager.AddInventoryItem(player: Player, itemName: string, amount: number): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end

	if type(itemName) ~= "string" or itemName == "" then
		return false
	end

	if type(amount) ~= "number" then
		return false
	end

	ensureInventory(profile)
	local currentAmount = profile.Data.inventory[itemName] or 0
	local newAmount = currentAmount + amount

	if newAmount <= 0 then
		profile.Data.inventory[itemName] = nil
	else
		profile.Data.inventory[itemName] = newAmount
	end

	syncClientKey(player, "inventory", cloneInventory(profile.Data.inventory))
	return true
end

function DataManager.RemoveInventoryItem(player: Player, itemName: string, amount: number): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end

	if type(itemName) ~= "string" or itemName == "" then
		return false
	end

	if type(amount) ~= "number" then
		return false
	end

	ensureInventory(profile)
	local currentAmount = profile.Data.inventory[itemName] or 0
	local newAmount = currentAmount - amount
	if newAmount <= 0 then
		profile.Data.inventory[itemName] = nil
	else
		profile.Data.inventory[itemName] = newAmount
	end
	syncClientKey(player, "inventory", cloneInventory(profile.Data.inventory))
	return true
end

-- Lifecycle Management Initialization / Destruction

function DataManager.Init()
	if initialized then
		return
	end
	initialized = true

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerAdded, player)
	end

	playerAddedConn = Players.PlayerAdded:Connect(PlayerAdded)
	playerRemovingConn = Players.PlayerRemoving:Connect(PlayerRemoving)
end

function DataManager.Destroy()
	if playerAddedConn then
		playerAddedConn:Disconnect()
		playerAddedConn = nil
	end

	if playerRemovingConn then
		playerRemovingConn:Disconnect()
		playerRemovingConn = nil
	end
	initialized = false
end

return DataManager
