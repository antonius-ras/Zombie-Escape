local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function requireModule(moduleScript: ModuleScript, moduleName: string)
	local ok, result = pcall(require, moduleScript)
	if not ok then
		error(
			string.format(
				"[gameplay/init.server] require failed for %s (%s): %s",
				moduleName,
				moduleScript:GetFullName(),
				tostring(result)
			)
		)
	end

	return result
end

local function initModule(moduleTable: any, moduleName: string, ...)
	local ok, result = pcall(moduleTable.Init, ...)
	if not ok then
		error(string.format("[gameplay/init.server] init failed for %s: %s", moduleName, tostring(result)))
	end

	return result
end

local commonServer = (ServerScriptService :: any).common
local dataManager = requireModule(commonServer.DataManager, "DataManager")
local profileZombieEscape = requireModule(commonServer.ProfileZombieEscape.ProfileZombieEscape, "ProfileZombieEscape")
local gameManager = requireModule((ReplicatedStorage :: any).shared.GAMEPLAY.gameManager, "gameManager")

initModule(dataManager, "DataManager")
initModule(profileZombieEscape, "ProfileZombieEscape")
initModule(gameManager, "gameManager")

