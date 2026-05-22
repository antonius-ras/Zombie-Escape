local ServerScriptService = game:GetService("ServerScriptService")
local commonServer = (ServerScriptService :: any).common

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

local DataManager = requireModule(commonServer.DataManager, "DataManager")
local ServerListFetcher = requireModule(commonServer.ServerListFetcher, "ServerListFetcher")
local PresenceService = requireModule(commonServer.PresenceService, "PresenceService")
local PartyInviteService = requireModule(commonServer.PartyInviteService, "PartyInviteService")

initModule(PresenceService, "PresenceService", "lobby")
initModule(DataManager, "DataManager")
initModule(ServerListFetcher, "ServerListFetcher")
initModule(PartyInviteService, "PartyInviteService")
