local ServerScriptService = game:GetService("ServerScriptService")

local function requireModule(moduleScript: ModuleScript, moduleName: string)
	local ok, result = pcall(require, moduleScript)
	if not ok then
		error(
			string.format(
				"[lobby/init.server] require failed for %s (%s): %s",
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
		error(string.format("[lobby/init.server] init failed for %s: %s", moduleName, tostring(result)))
	end

	return result
end

local commonServer = (ServerScriptService :: any).common

local dataManager = requireModule(commonServer.DataManager, "DataManager")
local profileZombieEscape = requireModule(commonServer.ProfileZombieEscape.ProfileZombieEscape, "ProfileZombieEscape")
local partyManager = requireModule(commonServer.PartyManager, "PartyManager")
local serverListFetcher = requireModule(commonServer.ServerListFetcher, "ServerListFetcher")

initModule(dataManager, "DataManager")
initModule(profileZombieEscape, "ProfileZombieEscape")
initModule(partyManager, "PartyManager")
initModule(serverListFetcher, "ServerListFetcher")
