-- ============================================================
-- DataManager.luau | ModuleScript (Server-side)
-- หน้าที่: จัดการโหลด/เซฟข้อมูลผู้เล่นด้วย ProfileService
--          พร้อม sync ข้อมูล real-time ไปยัง client (2 scenes)
-- ============================================================

local DataManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileService = require((ReplicatedStorage :: any).common.modules.ProfileService)

-- Remote Events สำหรับ sync ข้อมูลระหว่าง Server <-> Client

local remotes = ReplicatedStorage:FindFirstChild("common") and ReplicatedStorage.common:FindFirstChild("remotes")

-- สร้าง remotes folder ถ้ายังไม่มี
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

-- DataSync: Server → Client เมื่อข้อมูลเปลี่ยน
local DataSyncEvent: RemoteEvent = getOrCreateRemote("RemoteEvent", "DataSync")
-- RequestData: Client ขอข้อมูลตอน scene โหลดใหม่
local RequestDataFunction: RemoteFunction = getOrCreateRemote("RemoteFunction", "RequestData")

-- ============================================================
-- Profile Template & Store
-- ============================================================
local ProfileTemplate = {
	Coins = 0,
	TotalWins = 0,
	TotalHits = 0,
	KillsZombie = 0,
	KillsHuman = 0,
	inventory = {}, -- อนาคตอาจเพิ่มระบบไอเทม
}

local ProfileStore = ProfileService.GetProfileStore("PlayerData_v1", ProfileTemplate)
local Profiles: { [Player]: any } = {}

local initialized = false
local playerAddedConn: RBXScriptConnection?
local playerRemovingConn: RBXScriptConnection?

-- ============================================================
-- Internal Helpers
-- ============================================================

-- sync leaderstats (Coins เท่านั้น)
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
	return table.clone(inventory or {})
end

local function ensureInventory(profile)
	if type(profile.Data.inventory) ~= "table" then
		profile.Data.inventory = {}
	end
end

-- ส่งข้อมูลทั้งหมดไปให้ client คนนั้น (ใช้ตอน scene เปลี่ยน หรือข้อมูล update)
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

-- ส่งเฉพาะ key ที่เปลี่ยน (ประหยัด bandwidth)
local function syncClientKey(player: Player, key: string, value: any)
	DataSyncEvent:FireClient(player, { [key] = value })
end

-- ============================================================
-- Player Lifecycle
-- ============================================================
local function PlayerAdded(player: Player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile() -- เติม key ที่หายไปจาก template อัตโนมัติ
		ensureInventory(profile)

		profile:ListenToRelease(function()
			Profiles[player] = nil
			player:Kick(
				"ข้อมูลกำลังโหลดซ้อนทับกัน กรุณาเข้าเกมใหม่อีกครั้ง"
			)
		end)

		if player:IsDescendantOf(Players) then
			Profiles[player] = profile

			-- สร้าง leaderstats
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

			--  sync ข้อมูลทั้งหมดไปให้ client ทันทีที่โหลดเสร็จ
			syncClientFull(player, profile)

			print("โหลดข้อมูลของ", player.Name, "สำเร็จ:", profile.Data)
		else
			profile:Release()
		end
	else
		player:Kick(
			"เซิร์ฟเวอร์ฐานข้อมูลขัดข้อง ไม่สามารถโหลดข้อมูลได้"
		)
	end
end

local function PlayerRemoving(player: Player)
	local profile = Profiles[player]
	if profile ~= nil then
		profile:Release()
		Profiles[player] = nil
	end
end

-- ============================================================
-- RequestData Handler (Client ขอข้อมูลตอน scene เปลี่ยน)
-- ใช้ใน Lobby และ Gameplay ตอน LocalScript เริ่มทำงาน
-- ============================================================
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

-- ============================================================
-- Public API
-- ============================================================

function DataManager.GetPlayerProfile(player: Player)
	return Profiles[player]
end

function DataManager.GetPlayerData(player: Player)
	local profile = Profiles[player]
	return profile and profile.Data or nil
end

function DataManager.GetPlayerValue(player: Player, key: string)
	local profile = Profiles[player]
	if profile == nil then
		return nil
	end

	return profile.Data[key]
end

-- Set ค่า key ใดก็ได้ + auto sync
function DataManager.SetPlayerValue(player: Player, key: string, value: any): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end

	if key == "inventory" and type(value) ~= "table" then
		return false
	end

	profile.Data[key] = value

	-- sync leaderstats ถ้าเป็น Coins
	if key == "Coins" then
		syncLeaderstats(player, profile)
	end

	if key == "inventory" then
		ensureInventory(profile)
	end

	--  ส่งเฉพาะ key ที่เปลี่ยนไปให้ client ทันที
	if key == "inventory" then
		syncClientKey(player, key, cloneInventory(profile.Data.inventory))
	else
		syncClientKey(player, key, value)
	end
	return true
end

function DataManager.UpdatePlayerData(player: Player, updater: (data: {}) -> ()): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end
	if type(updater) ~= "function" then
		return false
	end

	local success = pcall(updater, profile.Data)
	if success then
		ensureInventory(profile)
		syncLeaderstats(player, profile)

		syncClientFull(player, profile)
	end
	return success
end

-- add/remove Coins (atomic)
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
	profile.Data.inventory[itemName] = amount
	syncClientKey(player, "inventory", cloneInventory(profile.Data.inventory))
	return true
end

function DataManager.AddInventoryItem(player: Player, itemName: string, amount: number): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	end

	if type(itemName) ~= "string" or itemName == "" then
		return false
	end

	if type(amount) ~= "number" then
		amount = 1
	end

	ensureInventory(profile)
	local currentAmount = profile.Data.inventory[itemName] or 0
	profile.Data.inventory[itemName] = currentAmount + amount
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

-- Init / Destroy

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
