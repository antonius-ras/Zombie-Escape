local GameManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local sharedModules = (ReplicatedStorage :: any).shared.modules
local InfectionScript = require(sharedModules.infectionScript)
local ServerBroadcaster = require(sharedModules.ServerBroadcaster)

local GameStatus = ReplicatedStorage:FindFirstChild("GameStatus")
if not GameStatus then
	GameStatus = Instance.new("StringValue")
	GameStatus.Name = "GameStatus"
	GameStatus.Parent = ReplicatedStorage
end

local LobbyTeam = Teams:WaitForChild("Lobby")
local HumansTeam = Teams:WaitForChild("Humans")
local ZombiesTeam = Teams:WaitForChild("Zombies")
local ZombiesSpawn = Workspace:WaitForChild("ZombiesSpawn")
local HumanSpawn = Workspace:WaitForChild("HumanSpawn")

local MIN_PLAYERS = if RunService:IsStudio() then 1 else 2
local COUNTDOWN_TIME = 10
local ROUND_TIME = 300
local ZOMBIE_RATIO = 0.2

local initialized = false
local playerAddedConn: RBXScriptConnection?

local function setGameStatus(message)
	GameStatus.Value = message
end

local function preparePlayer(player)
	player.Team = LobbyTeam
	player:LoadCharacter()
end

local function shufflePlayers(players)
	for index = #players, 2, -1 do
		local swapIndex = math.random(index)
		players[index], players[swapIndex] = players[swapIndex], players[index]
	end
end

local function countAlivePlayers(team)
	local aliveCount = 0

	for _, player in ipairs(team:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if humanoid and humanoid.Health > 0 then
			aliveCount += 1
		end
	end

	return aliveCount
end

local function teleportCharacter(player, spawnPart)
	local character = player.Character or player.CharacterAdded:Wait()
	character:PivotTo(spawnPart.CFrame + Vector3.new(0, 5, 0))
end

local function resetToLobby()
	for _, player in ipairs(Players:GetPlayers()) do
		preparePlayer(player)
	end
end

local function runGameLoop()
	while true do
		repeat
			task.wait(1)
			local currentPlayers = #Players:GetPlayers()
			setGameStatus(
				"กำลังรอผู้เล่น... (" .. currentPlayers .. "/" .. MIN_PLAYERS .. ")"
			)
		until #Players:GetPlayers() >= MIN_PLAYERS

		local queueCanceled = false
		for secondsLeft = COUNTDOWN_TIME, 0, -1 do
			task.wait(1)

			local currentPlayers = #Players:GetPlayers()
			setGameStatus(
				"เกมจะเริ่มใน: "
					.. secondsLeft
					.. " วินาที ("
					.. currentPlayers
					.. "/"
					.. MIN_PLAYERS
					.. ")"
			)

			if currentPlayers < MIN_PLAYERS then
				queueCanceled = true
				break
			end
		end

		if queueCanceled then
			continue
		end

		local readyPlayers = {}
		for _, player in ipairs(LobbyTeam:GetPlayers()) do
			table.insert(readyPlayers, player)
		end

		if #readyPlayers == 0 then
			continue
		end

		setGameStatus("เกมกำลังจะเริ่ม!!")
		task.wait(2)

		shufflePlayers(readyPlayers)

		local zombieCount = math.floor(#readyPlayers * ZOMBIE_RATIO)
		if zombieCount < 1 then
			zombieCount = 1
		end
		if zombieCount >= #readyPlayers then
			zombieCount = math.max(#readyPlayers - 1, 0)
		end

		local zombiePlayers = {}
		for index = 1, zombieCount do
			local player = readyPlayers[index]
			if player then
				zombiePlayers[player] = true
			end
		end

		for _, player in ipairs(readyPlayers) do
			if zombiePlayers[player] then
				player.Team = ZombiesTeam
			else
				player.Team = HumansTeam
			end

			player:LoadCharacter()
		end

		task.wait(0.5)

		for _, player in ipairs(readyPlayers) do
			if zombiePlayers[player] then
				teleportCharacter(player, ZombiesSpawn)
			else
				teleportCharacter(player, HumanSpawn)
			end
		end

		local timeRemaining = ROUND_TIME
		local winningTeam: Team?

		while timeRemaining > 0 do
			task.wait(1)
			timeRemaining -= 1
			setGameStatus("เวลาเหลือ: " .. timeRemaining .. " วินาที")

			local aliveHumans = countAlivePlayers(HumansTeam)
			local aliveZombies = countAlivePlayers(ZombiesTeam)

			if aliveHumans == 0 then
				winningTeam = ZombiesTeam
				break
			elseif aliveZombies == 0 then
				winningTeam = HumansTeam
				break
			end
		end

		if winningTeam == ZombiesTeam then
			setGameStatus("ซอมบี้ชนะ! มนุษย์สูญพันธุ์")
		elseif winningTeam == HumansTeam then
			setGameStatus("มนุษย์เอาชีวิตรอดสำเร็จ!")
		else
			if countAlivePlayers(ZombiesTeam) > countAlivePlayers(HumansTeam) then
				setGameStatus("ซอมบี้ชนะ! มนุษย์สูญพันธุ์")
			else
				setGameStatus("มนุษย์เอาชีวิตรอดสำเร็จ!")
			end
		end

		task.wait(15)
		resetToLobby()
		task.wait(3)
	end
end

function GameManager.Init()
	if initialized then
		return
	end

	initialized = true

	InfectionScript.Init()
	ServerBroadcaster.Init()

	for _, player in ipairs(Players:GetPlayers()) do
		preparePlayer(player)
	end

	playerAddedConn = Players.PlayerAdded:Connect(preparePlayer)

	task.spawn(runGameLoop)
end

function GameManager.Destroy()
	if playerAddedConn then
		playerAddedConn:Disconnect()
		playerAddedConn = nil
	end

	initialized = false
end

return GameManager
