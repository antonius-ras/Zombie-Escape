-- ============================================================
-- UIManager.client.luau | LocalScript
-- วางไว้ใน: src/lobby/client/
-- หน้าที่: ตัวจัดการ UI กลาง — สั่ง show/hide แต่ละ screen
--          และเชื่อม event ระหว่าง screen ต่างๆ
--
-- โครงสร้างไฟล์:
--   src/lobby/client/
--   ├── UIManager.client.luau      ← ไฟล์นี้
--   └── screens/                   ← Folder ใน Studio
--       ├── IntroScreen.luau
--       ├── MainMenuScreen.luau
--       └── PlayMenuScreen.luau
-- ============================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

-- ── Require Screen Modules ────────────────────────────────────
-- "screens" คือ Folder ใน Studio ที่อยู่ข้างๆ UIManager
local screens        = script.Parent:WaitForChild("screens")
local IntroScreen    = require(screens:WaitForChild("IntroScreen"))
local MainMenuScreen = require(screens:WaitForChild("MainMenuScreen"))
local PlayMenuScreen = require(screens:WaitForChild("PlayMenuScreen"))
local QueueManager   = require(script.Parent:WaitForChild("QueueManager"))
local PartyClientManager = require(script.Parent:WaitForChild("PartyClientManager"))
local ServerListClientManager = require(script.Parent:WaitForChild("ServerListClientManager"))
local QueueConfig    = require((ReplicatedStorage :: any).shared:WaitForChild("QueueConfig"))

-- ── GUI References ────────────────────────────────────────────
local IntroGui    = playerGui:WaitForChild("IntroGui")
local MainMenuGui = playerGui:WaitForChild("MainMenuGui")
local PlayMenuGui = playerGui:WaitForChild("PlayMenuGui")

-- ── IntroCamera ───────────────────────────────────────────────
local IntroCamera = workspace:WaitForChild("IntroCamera")

-- ── ตั้งกล้อง IntroCamera ทันที ──────────────────────────────
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame     = IntroCamera.CFrame

-- ── ซ่อน GUI ทั้งหมดก่อน ─────────────────────────────────────
IntroGui.Enabled    = true  -- Intro เปิดตั้งแต่แรก
MainMenuGui.Enabled = false
PlayMenuGui.Enabled = false
local _isTransitioning = false
local _partyRefreshToken = 0
local _serverRefreshToken = 0
local _isPartyQueueUiActive = false
local _cachedServerEntries: {any} = {}
local _hasLoadedServerList = false

local function getPartyQueueLabel(secondsLeft: number): string
	return string.format("CANCEL MATCH (%ds)", secondsLeft)
end

local function hidePartyQueueTopButtonAndRestoreMainMenu()
	if _isTransitioning then
		return
	end

	_isTransitioning = true
	MainMenuScreen.hideQueueButton(function()
		MainMenuScreen.show(function()
			_isTransitioning = false
		end)
	end)
	_isPartyQueueUiActive = false
end

local function showPartyQueueTopButton(secondsLeft: number)
	if _isTransitioning then
		return
	end

	if PlayMenuGui.Enabled then
		PlayMenuGui.Enabled = false
	end

	if _isPartyQueueUiActive then
		MainMenuScreen.updateQueueButton(getPartyQueueLabel(secondsLeft))
		return
	end

	_isPartyQueueUiActive = true
	MainMenuScreen.showQueueButton(getPartyQueueLabel(secondsLeft), function()
		QueueManager.CancelPartyQueue()
	end)
end

-- ============================================================
-- Camera Transition (ใช้ร่วมกันได้)
-- ============================================================

local function transitionCameraToPlayer()
	task.spawn(function()
		local character = player.Character or player.CharacterAdded:Wait()
		local rootPart  = character:WaitForChild("HumanoidRootPart")

		local targetCF = CFrame.new(
			-- offset กล้องให้สูงขึ้นและถอยหลัง
			rootPart.Position + Vector3.new(0, 2.5, 12)
		)

		-- กล้องยัง Scriptable อยู่ → Tween ได้เลย
		TweenService:Create(camera,
			TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ CFrame = targetCF }
		):Play()

		task.wait(1.5)
		camera.CameraType = Enum.CameraType.Custom
	end)
end

-- ============================================================
-- Screen Flow Callbacks
-- ============================================================

-- ── Intro → MainMenu ──────────────────────────────────────────
local function onIntroPlayPressed()
	if _isTransitioning then
		return
	end
	_isTransitioning = true
	-- เด้ง Intro ออก
	IntroScreen.hide(function()
		MainMenuScreen.show(function()
			_isTransitioning = false
		end)
	end)
	-- กล้อง transition ทำงานขนาน
	transitionCameraToPlayer()
end

-- ── MainMenu → PlayMenu ───────────────────────────────────────
local function onMainMenuPlayPressed()
	if _isTransitioning then
		return
	end
	_isTransitioning = true
	MainMenuScreen.hide(function()
		PlayMenuScreen.show()
		_isTransitioning = false
	end)
end

-- ── MainMenu → Menu (placeholder) ────────────────────────────
local function onMainMenuMenuPressed()
	-- TODO: เพิ่ม SettingsScreen หรืออื่นๆ ในอนาคต
	print("[UIManager] MenuBtn pressed — ยังไม่ได้ implement")
end

-- ── MainMenu → Music (placeholder) ───────────────────────────
local function onMainMenuMusicPressed()
	-- TODO: toggle เพลงพื้นหลัง
	print("[UIManager] MusicBtn pressed — ยังไม่ได้ implement")
end

-- ── PlayMenu → กลับ MainMenu ──────────────────────────────────
local function onPlayMenuClose()
	if _isTransitioning then
		return
	end
	_isTransitioning = true
	MainMenuScreen.show(function()
		_isTransitioning = false
	end)
end

-- ── PlayMenu → Solo ───────────────────────────────────────────
local function onPlayMenuSolo()
	if _isTransitioning or QueueManager.IsBusy() then
		return
	end

	_isTransitioning = true
	PlayMenuScreen.hide(function()
		MainMenuScreen.showQueueButton(
			QueueManager.GetQueueLabel(QueueConfig.SoloCountdownSeconds),
			function()
				if not QueueManager.CancelSoloQueue() then
					return
				end
				if _isTransitioning then
					return
				end
				_isTransitioning = true
				MainMenuScreen.hideQueueButton(function()
					PlayMenuScreen.show()
					_isTransitioning = false
				end)
			end
		)
		_isTransitioning = false

		local started = QueueManager.StartSoloQueue({
			seconds = QueueConfig.SoloCountdownSeconds,
			onTick = function(secondsLeft)
				MainMenuScreen.updateQueueButton(QueueManager.GetQueueLabel(secondsLeft))
			end,
			onDispatch = function()
				MainMenuScreen.setQueueTeleporting(QueueManager.GetTeleportingLabel())
			end,
			onTeleportFailed = function(_message)
				if _isTransitioning then
					return
				end
				_isTransitioning = true
				MainMenuScreen.hideQueueButton(function()
					MainMenuScreen.show()
					_isTransitioning = false
				end)
			end,
		})

		if not started then
			_isTransitioning = true
			MainMenuScreen.hideQueueButton(function()
				MainMenuScreen.show()
				_isTransitioning = false
			end)
		end
	end)
end

local function refreshPartyUiAsync()
	_partyRefreshToken += 1
	local token = _partyRefreshToken

	task.spawn(function()
		local partySnapshot = PartyClientManager.GetPartySnapshot()
		if token ~= _partyRefreshToken then
			return
		end
		PlayMenuScreen.renderPartyMembers(partySnapshot, player.UserId)
		if _hasLoadedServerList then
			PlayMenuScreen.renderServerList(_cachedServerEntries)
		end
	end)

	task.spawn(function()
		local onlineFriends = PartyClientManager.GetOnlineFriends()
		if token ~= _partyRefreshToken then
			return
		end
		PlayMenuScreen.renderOnlineFriends(onlineFriends)
	end)
end

local function refreshServerListAsync()
	_serverRefreshToken += 1
	local token = _serverRefreshToken
	PlayMenuScreen.showServerListLoading()

	local pendingResponses = 2
	local partySnapshot = nil
	local servers = {}

	local function finalizeRefresh()
		pendingResponses -= 1
		if pendingResponses > 0 or token ~= _serverRefreshToken then
			return
		end

		PlayMenuScreen.renderPartyMembers(partySnapshot, player.UserId)
		_cachedServerEntries = servers
		_hasLoadedServerList = true
		PlayMenuScreen.renderServerList(_cachedServerEntries)
	end

	task.spawn(function()
		partySnapshot = PartyClientManager.GetPartySnapshot()
		finalizeRefresh()
	end)

	task.spawn(function()
		servers = ServerListClientManager.GetServers()
		finalizeRefresh()
	end)
end

local function onServerPanelOpened()
	refreshServerListAsync()
end

local function onJoinServerRequested(jobId: string)
	if _isTransitioning or QueueManager.IsBusy() then
		return
	end

	local ok, message = ServerListClientManager.JoinServer(jobId)
	if ok then
		return
	end

	if message == "server_unavailable"
		or message == "server_full"
		or message == "party_too_large"
		or message == "party_member_missing"
		or message == "not_party_leader"
		or message == "studio_teleport_unsupported"
		or message == "join_request_failed"
		or message == "join_failed"
	then
		refreshServerListAsync()
	end

	warn("[UIManager] Join server failed", message)
end

local function onPartyPanelOpened()
	refreshPartyUiAsync()
end

local function onInviteFriendPressed(targetUserId: number)
	local ok = PartyClientManager.SendInvite(targetUserId)
	if ok then
		refreshPartyUiAsync()
	end
end

local function onInvitePromptResponse(inviteId: string, accept: boolean)
	local ok, _msg = PartyClientManager.RespondInvite(inviteId, accept)
	if ok then
		if accept then
			PlayMenuScreen.showPartyPanel()
		end
		refreshPartyUiAsync()
	end
end

local function onPartyMemberAction(targetUserId: number, action: string)
	if action == "leave" then
		local ok = PartyClientManager.LeaveParty()
		if ok then
			refreshPartyUiAsync()
		end
		return
	end

	if action == "disband" then
		local ok = PartyClientManager.DisbandParty()
		if ok then
			refreshPartyUiAsync()
		end
		return
	end

	if action == "kick" then
		local ok = PartyClientManager.KickMember(targetUserId)
		if ok then
			refreshPartyUiAsync()
		end
	end
end

local function onPartyMatchmakingAction(action: string)
	if action == "start" then
		QueueManager.StartPartyQueue()
		return
	end
end

-- ============================================================
-- Init ทุก Screen (ส่ง callback ให้แต่ละ screen)
-- ============================================================

QueueManager.Init()
PartyClientManager.Init()
ServerListClientManager.Init()

PartyClientManager.OnInviteReceived(function(inviteData)
	PlayMenuScreen.showIncomingInvitePrompt(inviteData)
end)

PartyClientManager.OnPartyUpdated(function(snapshot)
	PlayMenuScreen.renderPartyMembers(snapshot, player.UserId)
	if _hasLoadedServerList then
		PlayMenuScreen.renderServerList(_cachedServerEntries)
	end
	refreshPartyUiAsync()
end)

PartyClientManager.OnInviteDeclined(function(_data)
	refreshPartyUiAsync()
end)

QueueManager.OnPartyQueueStatus(function(status, secondsLeft, _message)
	PlayMenuScreen.updatePartyQueueStatus(status, secondsLeft)

	if status == "started" or status == "tick" then
		showPartyQueueTopButton(secondsLeft or 0)
		return
	end

	if status == "teleporting" then
		if _isPartyQueueUiActive then
			MainMenuScreen.setQueueTeleporting(QueueManager.GetTeleportingLabel())
		end
		return
	end

	if status == "cancelled" or status == "failed" then
		if _isPartyQueueUiActive then
			hidePartyQueueTopButtonAndRestoreMainMenu()
		end
		refreshPartyUiAsync()
	end
end)

IntroScreen.init(IntroGui, onIntroPlayPressed)

MainMenuScreen.init(
	MainMenuGui,
	onMainMenuMenuPressed,
	onMainMenuMusicPressed,
	onMainMenuPlayPressed
)

PlayMenuScreen.init(
	PlayMenuGui,
	onPlayMenuClose,
	onPlayMenuSolo
)

PlayMenuScreen.setPartyCallbacks(
	onPartyPanelOpened,
	onInviteFriendPressed,
	onPartyMemberAction,
	onPartyMatchmakingAction,
	onInvitePromptResponse
)

PlayMenuScreen.setServerCallbacks(
	onServerPanelOpened,
	onJoinServerRequested
)

-- ============================================================
-- START — เริ่มที่ IntroScreen
-- ============================================================

IntroScreen.start()
