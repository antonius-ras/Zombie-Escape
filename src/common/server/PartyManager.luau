local partyManager = {}

local initialized = false
local playerParties = {}

local Players = game:GetService("Players")
local playerRemovingConn: RBXScriptConnection?

local function onPlayerRemoving(player)
	playerParties[player.UserId] = nil
end

function partyManager.GetPartyByUserId(userId)
	return playerParties[userId]
end

function partyManager.SetPartyByUserId(userId, partyData)
	playerParties[userId] = partyData
end

function partyManager.Init()
	if initialized then
		return
	end

	initialized = true
	playerRemovingConn = Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function partyManager.Destroy()
	if playerRemovingConn then
		playerRemovingConn:Disconnect()
		playerRemovingConn = nil
	end

	playerParties = {}
	initialized = false
end

return partyManager
