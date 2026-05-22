local ProfileZombieEscape = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require((ServerScriptService :: any).common.DataManager)

local initialized = false
local updateConnection: RBXScriptConnection?

local UPDATE_REMOTE_NAME = "profileZombieEscapeUpdate"

local numericFields = {
	Coins = true,
	TotalWins = true,
	TotalHits = true,
	KillsZombie = true,
	KillsHuman = true,
}

local function isNumericField(key: string): boolean
	return numericFields[key] == true
end

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local commonFolder = ReplicatedStorage:FindFirstChild("common")
	if not commonFolder then
		commonFolder = Instance.new("Folder")
		commonFolder.Name = "common"
		commonFolder.Parent = ReplicatedStorage
	end

	local remotesFolder = commonFolder:FindFirstChild("remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "remotes"
		remotesFolder.Parent = commonFolder
	end

	local existing = remotesFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

local function addValue(player: Player, key: string, amount: number): boolean
	if not isNumericField(key) or type(amount) ~= "number" then
		return false
	end

	return DataManager.AddValue(player, key, amount)
end

local function setValue(player: Player, key: string, value: any): boolean
	if key == "inventory" then
		return DataManager.SetPlayerValue(player, key, value)
	end

	if not isNumericField(key) then
		return false
	end

	if type(value) ~= "number" then
		return false
	end

	return DataManager.SetPlayerValue(player, key, value)
end

local function addInventory(player: Player, itemName: string, amount: number): boolean
	if type(itemName) ~= "string" or itemName == "" then
		return false
	end

	if type(amount) ~= "number" then
		return false
	end

	return DataManager.AddInventoryItem(player, itemName, amount)
end

local function removeInventory(player: Player, itemName: string, amount: number): boolean
	if type(itemName) ~= "string" or itemName == "" then
		return false
	end

	if type(amount) ~= "number" then
		return false
	end

	return DataManager.RemoveInventoryItem(player, itemName, amount)
end

local function setInventory(player: Player, itemName: string, amount: number): boolean
	if type(itemName) ~= "string" or itemName == "" then
		return false
	end

	if type(amount) ~= "number" then
		return false
	end

	return DataManager.SetInventoryItem(player, itemName, amount)
end

function ProfileZombieEscape.AddValue(player: Player, key: string, amount: number): boolean
	return addValue(player, key, amount)
end

function ProfileZombieEscape.SetValue(player: Player, key: string, value: any): boolean
	return setValue(player, key, value)
end

function ProfileZombieEscape.AddInventoryItem(player: Player, itemName: string, amount: number): boolean
	return addInventory(player, itemName, amount)
end

function ProfileZombieEscape.RemoveInventoryItem(player: Player, itemName: string, amount: number): boolean
	return removeInventory(player, itemName, amount)
end

function ProfileZombieEscape.SetInventoryItem(player: Player, itemName: string, amount: number): boolean
	return setInventory(player, itemName, amount)
end

local function onProfileUpdateRequest(
	player: Player,
	requestType: any,
	key: any,
	amountOrValue: any,
	itemNameOrAmount: any
)
	if type(requestType) == "table" then
		local payload = requestType
		local payloadType = payload.type

		if payloadType == "add" then
			addValue(player, payload.key, payload.amount)
		elseif payloadType == "set" then
			setValue(player, payload.key, payload.value)
		elseif payloadType == "inventoryAdd" then
			addInventory(player, payload.itemName, payload.amount)
		elseif payloadType == "inventoryRemove" then
			removeInventory(player, payload.itemName, payload.amount)
		elseif payloadType == "inventorySet" then
			setInventory(player, payload.itemName, payload.amount)
		end

		return
	end

	if type(requestType) ~= "string" then
		return
	end

	if requestType == "add" then
		addValue(player, key, amountOrValue)
	elseif requestType == "set" then
		setValue(player, key, amountOrValue)
	elseif requestType == "inventoryAdd" then
		addInventory(player, key, amountOrValue)
	elseif requestType == "inventoryRemove" then
		removeInventory(player, key, amountOrValue)
	elseif requestType == "inventorySet" then
		setInventory(player, key, amountOrValue)
	elseif requestType == "inventoryAddV2" then
		addInventory(player, key, itemNameOrAmount)
	end
end

function ProfileZombieEscape.Init()
	if initialized then
		return
	end

	initialized = true

	local updateRemote = getOrCreateRemoteEvent(UPDATE_REMOTE_NAME)
	updateConnection = updateRemote.OnServerEvent:Connect(onProfileUpdateRequest)
end

function ProfileZombieEscape.Destroy()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	initialized = false
end

return ProfileZombieEscape
