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

-- 1. Database & Profiles
local dataManager = requireModule(commonServer.DataManager, "DataManager")
local profileZombieEscape = requireModule(commonServer.ProfileZombieEscape.ProfileZombieEscape, "ProfileZombieEscape")

-- 2. Social & Party
local presenceService = requireModule(commonServer.PresenceService, "PresenceService")
local partyInviteService = requireModule(commonServer.PartyInviteService, "PartyInviteService")

-- 3. Matchmaking & Queues
local serverListFetcher = requireModule(commonServer.ServerListFetcher, "ServerListFetcher")
local queueTeleportService = requireModule(script:WaitForChild("QueueTeleportService"), "QueueTeleportService")

-- Init Database
initModule(dataManager, "DataManager")
initModule(profileZombieEscape, "ProfileZombieEscape")

-- Init Social (Lobby)
initModule(presenceService, "PresenceService", "lobby")
initModule(partyInviteService, "PartyInviteService")

-- Init Matchmaking
initModule(serverListFetcher, "ServerListFetcher")
initModule(queueTeleportService, "QueueTeleportService")
