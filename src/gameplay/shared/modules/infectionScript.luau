local InfectionScript = {}

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Teams = game:GetService("Teams")

local initialized = false
local playerAddedConn: RBXScriptConnection?

local function applyZombieSkin(character)
	local bodyColors = character:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	bodyColors.Parent = character

	local zombieColor = BrickColor.new("Slime green")
	bodyColors.HeadColor = zombieColor
	bodyColors.LeftArmColor = zombieColor
	bodyColors.RightArmColor = zombieColor
	bodyColors.LeftLegColor = zombieColor
	bodyColors.RightLegColor = zombieColor
	bodyColors.TorsoColor = zombieColor

	local outfitsFolder = ServerStorage:FindFirstChild("ZombieOutfits")
	if not outfitsFolder then
		return
	end

	for _, obj in ipairs(character:GetChildren()) do
		if obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") then
			obj:Destroy()
		end
	end

	local randomNumber = math.random(1, 3)
	local shirt = outfitsFolder:FindFirstChild("Shirt" .. randomNumber)
	local pants = outfitsFolder:FindFirstChild("Pants" .. randomNumber)

	if shirt then
		shirt:Clone().Parent = character
	end

	if pants then
		pants:Clone().Parent = character
	end
end

local function onPlayerAdded(player)
	local savedDeathCFrame: CFrame?

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		repeat
			task.wait()
		until character.Parent == workspace
		task.wait(0.2)

		if savedDeathCFrame then
			character:PivotTo(savedDeathCFrame + Vector3.new(0, 3, 0))
			savedDeathCFrame = nil
		end

		if player.Team == Teams.Humans then
			local gun = ServerStorage:FindFirstChild("Gun")
			if gun then
				gun:Clone().Parent = player.Backpack
			end
		elseif player.Team == Teams.Zombies then
			local zombieHands = ServerStorage:FindFirstChild("ZombieHands")
			if zombieHands then
				zombieHands:Clone().Parent = player.Backpack
			end

			applyZombieSkin(character)
		end

		humanoid.Died:Connect(function()
			if player.Team == Teams.Humans then
				local rootPart = character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					savedDeathCFrame = rootPart.CFrame
				end

				player.Team = Teams.Zombies
			end
		end)
	end)
end

function InfectionScript.Init()
	if initialized then
		return
	end

	initialized = true
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	playerAddedConn = Players.PlayerAdded:Connect(onPlayerAdded)
end

function InfectionScript.Destroy()
	if playerAddedConn then
		playerAddedConn:Disconnect()
		playerAddedConn = nil
	end

	initialized = false
end

return InfectionScript
