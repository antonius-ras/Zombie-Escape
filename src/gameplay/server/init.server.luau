local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function requireModule(moduleScript: ModuleScript, moduleName: string)
	local ok, result = pcall(require, moduleScript)
	if not ok then
		error(string.format("[gameplay/init.server] require failed for %s (%s): %s", moduleName, moduleScript:GetFullName(), tostring(result)))
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

local gameManager = requireModule((ReplicatedStorage :: any).shared.GAMEPLAY.gameManager, "gameManager")
local PresenceService = requireModule((ServerScriptService :: any).common.PresenceService, "PresenceService")

initModule(PresenceService, "PresenceService", "gameplay")
initModule(gameManager, "gameManager")
