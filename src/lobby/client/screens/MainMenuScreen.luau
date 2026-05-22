-- ============================================================
-- MainMenuScreen.luau | ModuleScript
-- วางไว้ใน: src/lobby/client/screens/
-- หน้าที่: จัดการ MainMenuGui (MenuBtn, MusicBtn, PlayBtn)
-- ============================================================

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIAnimationHelper = require(ReplicatedStorage.common.modules.UIAnimationHelper)

local MainMenuScreen = {}

-- ── References ───────────────────────────────────────────────
local _gui: ScreenGui
local _background: Frame
local _menuBtn: GuiButton
local _musicBtn: GuiButton
local _playBtn: GuiButton

-- callbacks จาก UIManager
local _onMenuPressed:  () -> ()
local _onMusicPressed: () -> ()
local _onPlayPressed:  () -> ()

local _basePositions: {[GuiObject]: UDim2} = {}
local _transitionEpoch = 0
local _isInteractive = false
local _isQueueMode = false
local _onQueueCancelPressed: (() -> ())?
local _defaultPlayText = "PLAY!"
local BG_TRANSPARENCY = 0.8

-- ============================================================
-- Utils (private)
-- ============================================================

local function nextEpoch(): number
	_transitionEpoch += 1
	return _transitionEpoch
end

local function isEpochCurrent(epoch: number?): boolean
	if epoch == nil then
		return true
	end
	return epoch == _transitionEpoch
end

local function getBasePosition(obj: GuiObject): UDim2
	local saved = _basePositions[obj]
	if saved then
		return saved
	end
	_basePositions[obj] = obj.Position
	return obj.Position
end

local function setInteractive(isInteractive: boolean)
	_isInteractive = isInteractive
	if _menuBtn then _menuBtn.Active = isInteractive end
	if _musicBtn then _musicBtn.Active = isInteractive end
	if _playBtn then _playBtn.Active = isInteractive end
end

local function setPlayButtonText(text: string)
	pcall(function()
		(_playBtn :: any).Text = text
	end)
end

-- ============================================================
-- Public API
-- ============================================================

function MainMenuScreen.init(
	gui: ScreenGui,
	onMenuPressed:  () -> (),
	onMusicPressed: () -> (),
	onPlayPressed:  () -> ()
)
	_gui   = gui
	_onMenuPressed  = onMenuPressed
	_onMusicPressed = onMusicPressed
	_onPlayPressed  = onPlayPressed

	_background = gui:WaitForChild("Background")
	_menuBtn    = _background:WaitForChild("MenuBtn")
	_musicBtn   = _background:WaitForChild("MusicBtn")
	_playBtn    = _background:WaitForChild("PlayBtn")
	pcall(function()
		_defaultPlayText = (_playBtn :: any).Text
	end)

	_basePositions[_menuBtn] = _menuBtn.Position
	_basePositions[_musicBtn] = _musicBtn.Position
	_basePositions[_playBtn] = _playBtn.Position

	-- Initial State
	_menuBtn.Visible  = false
	_musicBtn.Visible = false
	_playBtn.Visible  = false

	-- Hover
	UIAnimationHelper.applyHover(_menuBtn)
	UIAnimationHelper.applyHover(_musicBtn)
	UIAnimationHelper.applyHover(_playBtn)

	-- Connections
	_menuBtn.MouseButton1Click:Connect(function()
		if not _isInteractive then return end
		if _onMenuPressed then _onMenuPressed() end
	end)
	_musicBtn.MouseButton1Click:Connect(function()
		if not _isInteractive then return end
		if _onMusicPressed then _onMusicPressed() end
	end)
	_playBtn.MouseButton1Click:Connect(function()
		if not _isInteractive then return end
		if _isQueueMode then
			if _onQueueCancelPressed then _onQueueCancelPressed() end
			return
		end
		setInteractive(false)
		if _onPlayPressed then _onPlayPressed() end
	end)
end

function MainMenuScreen.show(onShown: (() -> ())?)
	local epoch = nextEpoch()
	_isQueueMode = false
	_onQueueCancelPressed = nil
	setPlayButtonText(_defaultPlayText)
	setInteractive(false)
	_gui.Enabled = true
	
	UIAnimationHelper.slideIn(_menuBtn,  "Left", 0)
	UIAnimationHelper.slideIn(_musicBtn, "Left", 0.1)
	UIAnimationHelper.slideIn(_playBtn,  "Right", 0.2)
	
	task.delay(0.8, function()
		if not isEpochCurrent(epoch) then return end
		setInteractive(true)
		if onShown then onShown() end
	end)
end

function MainMenuScreen.hide(onHidden: (() -> ())?)
	local epoch = nextEpoch()
	_isQueueMode = false
	_onQueueCancelPressed = nil
	setInteractive(false)
	
	UIAnimationHelper.slideOut(_playBtn,  "Right")
	UIAnimationHelper.slideOut(_musicBtn, "Left")
	UIAnimationHelper.slideOut(_menuBtn,  "Left")
	
	task.delay(0.8, function()
		if not isEpochCurrent(epoch) then return end
		_gui.Enabled = false
		if onHidden then onHidden() end
	end)
end

function MainMenuScreen.showQueueButton(initialText: string, onCancelPressed: () -> ())
	local epoch = nextEpoch()
	_isQueueMode = true
	_onQueueCancelPressed = onCancelPressed
	setInteractive(false)
	_gui.Enabled = true

	_menuBtn.Visible = false
	_musicBtn.Visible = false

	_playBtn.Visible = true
	_playBtn.Position = getBasePosition(_playBtn)
	setPlayButtonText(initialText)

	UIAnimationHelper.slideIn(_playBtn, "Right")
	task.delay(0.8, function()
		if not isEpochCurrent(epoch) then return end
		setInteractive(true)
	end)
end

function MainMenuScreen.updateQueueButton(text: string)
	if not _isQueueMode then return end
	setPlayButtonText(text)
end

function MainMenuScreen.setQueueTeleporting(text: string)
	if not _isQueueMode then return end
	setPlayButtonText(text)
	setInteractive(false)
end

function MainMenuScreen.hideQueueButton(onHidden: (() -> ())?)
	local epoch = nextEpoch()
	setInteractive(false)
	UIAnimationHelper.slideOut(_playBtn, "Right", function()
		_playBtn.Visible = false
		setPlayButtonText(_defaultPlayText)
		_isQueueMode = false
		_onQueueCancelPressed = nil
		_gui.Enabled = false
		if onHidden then onHidden() end
	end)
end

return MainMenuScreen
