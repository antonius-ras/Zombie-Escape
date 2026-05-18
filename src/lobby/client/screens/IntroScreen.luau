-- ============================================================
-- IntroScreen.luau | ModuleScript
-- วางไว้ใน: src/lobby/client/screens/
-- หน้าที่: จัดการ Loading Bar และ PlayButton
-- ============================================================

local TweenService    = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIAnimationHelper = require(ReplicatedStorage.common.modules.UIAnimationHelper)

local IntroScreen = {}

-- ── References (set ตอน init) ────────────────────────────────
local _gui: ScreenGui
local _background: Frame
local _loadingBarBG: Frame
local _loadingFill: Frame
local _loadingText: TextLabel
local _playButton: TextButton
local _fillSizeY: UDim

local _onPlayPressed: () -> () -- callback ส่งมาจาก UIManager
local _basePositions: {[GuiObject]: UDim2} = {}
local _transitionEpoch = 0
local _pulseEpoch = 0
local _isInteractive = false

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

local function bounceIn(obj: GuiObject, delayTime: number?, epoch: number?)
	task.delay(delayTime or 0, function()
		if not isEpochCurrent(epoch) then
			return
		end
		UIAnimationHelper.bounceIn(obj)
	end)
end

local function bounceOut(obj: GuiObject, delayTime: number?, epoch: number?, callback: (() -> ())?)
	task.delay(delayTime or 0, function()
		if not isEpochCurrent(epoch) then
			return
		end
		UIAnimationHelper.bounceOut(obj, UDim2.fromScale(0, 0.4), callback)
	end)
end

-- ============================================================
-- Loading
-- ============================================================

local function runRealLoading(epoch: number)
	local assetsToLoad = {}
	for _, v in ipairs(game:GetDescendants()) do
		if v:IsA("BasePart") or v:IsA("Decal") or v:IsA("Texture")
			or v:IsA("Sound") or v:IsA("Animation")
			or v:IsA("MeshPart") or v:IsA("SpecialMesh")
		then
			table.insert(assetsToLoad, v)
		end
	end

	local total  = math.max(#assetsToLoad, 1)
	local loaded = 0
	local lastUiUpdate = 0

	local function getText(p: number)
		if p < 0.25 then return "LOADING..."
		elseif p < 0.50 then return "LOADING MAP..."
		elseif p < 0.75 then return "LOADING MODELS..."
		elseif p < 0.95 then return "LOADING SOUNDS..."
		else return "ALMOST DONE..."
		end
	end

	ContentProvider:PreloadAsync(assetsToLoad, function(_id, _status)
		if not isEpochCurrent(epoch) then
			return
		end
		loaded += 1
		local now = os.clock()
		if now - lastUiUpdate < 1 / 30 and loaded < total then
			return
		end
		lastUiUpdate = now
		local progress = loaded / total
		_loadingFill.Size = UDim2.new(progress, 0, _fillSizeY.Scale, _fillSizeY.Offset)
		_loadingText.Text = getText(progress)
	end)

	if not isEpochCurrent(epoch) then
		return
	end

	UIAnimationHelper.tween(_loadingFill,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 0, _fillSizeY.Scale, _fillSizeY.Offset) }
	)
	_loadingText.Text = "READY!"
	task.wait(0.35)
end

local function showPlayButton(epoch: number)
	bounceIn(_playButton, 0, epoch)
	_isInteractive = true
	_playButton.Active = true
	_pulseEpoch += 1
	local pulseEpoch = _pulseEpoch

	-- Pulse loop
	task.spawn(function()
		task.wait(0.65)
		while isEpochCurrent(epoch) and pulseEpoch == _pulseEpoch and _playButton.Visible do
			UIAnimationHelper.tween(_playButton,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ BackgroundTransparency = math.min(BG_TRANSPARENCY + 0.1, 1) }
			)
			task.wait(0.9)
			if not isEpochCurrent(epoch) or pulseEpoch ~= _pulseEpoch or not _playButton.Visible then break end
			UIAnimationHelper.tween(_playButton,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ BackgroundTransparency = BG_TRANSPARENCY }
			)
			task.wait(0.9)
		end
	end)
end

-- ============================================================
-- Public API
-- ============================================================

function IntroScreen.init(gui: ScreenGui, onPlayPressed: () -> ())
	_gui          = gui
	_onPlayPressed = onPlayPressed

	_background   = gui:WaitForChild("Background")
	_loadingBarBG = _background:WaitForChild("LoadingBarBG")
	_loadingFill  = _loadingBarBG:WaitForChild("LoadingFill")
	_loadingText  = _loadingBarBG:WaitForChild("LoadingText")
	_playButton   = _background:WaitForChild("PlayButton")

	-- State เริ่มต้น
	_fillSizeY            = _loadingFill.Size.Y
	_loadingFill.Size     = UDim2.new(0, 0, _fillSizeY.Scale, _fillSizeY.Offset)
	_playButton.Visible   = false
	_playButton.Active    = false

	-- Hover
	UIAnimationHelper.applyHover(_playButton)

	-- Play button
	_playButton.MouseButton1Click:Connect(function()
		if not _isInteractive then return end
		if _onPlayPressed then
			_isInteractive = false
			_playButton.Active = false
			_onPlayPressed()
		end
	end)
end

function IntroScreen.start()
	local epoch = nextEpoch()
	_isInteractive = false
	_playButton.Active = false
	_gui.Enabled = true
	
	UIAnimationHelper.slideIn(_background, "Top")
	
	task.spawn(function()
		runRealLoading(epoch)
		if not isEpochCurrent(epoch) then return end
		UIAnimationHelper.slideOut(_loadingBarBG, "Bottom", function()
			_loadingBarBG.Visible = false
			showPlayButton(epoch)
		end)
	end)
end

function IntroScreen.hide(onHidden: (() -> ())?)
	local epoch = nextEpoch()
	_pulseEpoch += 1
	_isInteractive = false
	_playButton.Active = false
	UIAnimationHelper.slideOut(_background, "Top", onHidden)
end

return IntroScreen
