local ServerScriptService = game:GetService("ServerScriptService")
local commonServer = (ServerScriptService :: any).common

local DataManager = require(commonServer.DataManager)
local PartyManager = require(commonServer.PartyManager)
local ServerListFetcher = require(commonServer.ServerListFetcher)

DataManager.Init()
PartyManager.Init()
ServerListFetcher.Init()