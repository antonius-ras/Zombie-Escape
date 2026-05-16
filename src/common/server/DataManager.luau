-- ============================================================
-- DataManager.luau | ModuleScript
-- หน้าที่: จัดการโหลด/เซฟข้อมูลผู้เล่นด้วย ProfileService อย่างปลอดภัย
-- ============================================================

local DataManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileService = require((ReplicatedStorage :: any).common.modules.ProfileService)

local ProfileTemplate = {
	Coins = 0,
	TotalWins = 0,
}

local ProfileStore = ProfileService.GetProfileStore("PlayerData_v1", ProfileTemplate)
local Profiles = {}

local initialized = false
local playerAddedConn: RBXScriptConnection?
local playerRemovingConn: RBXScriptConnection?

local function PlayerAdded(player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile:ListenToRelease(function()
			Profiles[player] = nil
			player:Kick(
				"ข้อมูลกำลังโหลดซ้อนทับกัน กรุณาเข้าเกมใหม่อีกครั้ง"
			)
		end)

		if player:IsDescendantOf(Players) then
			Profiles[player] = profile

			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then
				leaderstats = Instance.new("Folder")
				leaderstats.Name = "leaderstats"
				leaderstats.Parent = player
			end

			local coinsValue = leaderstats:FindFirstChild("Coins")
			if not coinsValue then
				coinsValue = Instance.new("IntValue")
				coinsValue.Name = "Coins"
				coinsValue.Parent = leaderstats
			end

			coinsValue.Value = profile.Data.Coins

			task.spawn(function()
				while task.wait(1) do
					if Profiles[player] and coinsValue.Parent then
						coinsValue.Value = Profiles[player].Data.Coins
					else
						break
					end
				end
			end)

			print(
				"โหลดข้อมูลของ",
				player.Name,
				"สำเร็จ! มีเหรียญ:",
				profile.Data.Coins
			)
		else
			profile:Release()
		end
	else
		player:Kick(
			"เซิร์ฟเวอร์ฐานข้อมูลขัดข้อง ไม่สามารถโหลดข้อมูลได้"
		)
	end
end

local function PlayerRemoving(player)
	local profile = Profiles[player]
	if profile ~= nil then
		profile:Release()
		Profiles[player] = nil
	end
end

function DataManager.GetPlayerProfile(player)
	return Profiles[player]
end

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
