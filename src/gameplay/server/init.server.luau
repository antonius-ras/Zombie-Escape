local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gameManager = require((ReplicatedStorage :: any).shared.GAMEPLAY.gameManager)

gameManager.Init()
