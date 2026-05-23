-- ============================================================
-- IntroScreen.luau | ModuleScript
-- วางไว้ใน: src/lobby/client/screens/
-- หน้าที่: จัดการ Loading Bar และ PlayButton
-- ============================================================

local TweenService    = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

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
local _activeTweens: {[Instance]: Tween} = {}
local _transitionEpoch = 0
local _pulseEpoch = 0
local _isInteractive = false
local BG_TRANSPARENCY = 0.8
local LOADING_MESSAGES = {
	LOADING_UI = "LOADING UI...",
	LOADING_ASSETS = "LOADING ASSETS...",
	LOADING_ICONS = "LOADING ICONS...",
	LOADING_SOUNDS = "LOADING SOUNDS...",
	ALMOST_DONE = "ALMOST DONE...",
}

-- ============================================================
-- Utils (private)
-- ============================================================

local UIAnimationUtils = require(script.Parent.Parent.utils.UIAnimationUtils)
local safeTween = UIAnimationUtils.safeTween

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
	local targetPos = getBasePosition(obj)
	obj.Position    = targetPos + UDim2.new(0, 0, 0.3, 0)
	obj.Visible     = true
	obj.BackgroundTransparency = 1
	
	task.delay(delayTime or 0, function()
		if not isEpochCurrent(epoch) then
			return
		end
		safeTween(obj,
			TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = targetPos, BackgroundTransparency = BG_TRANSPARENCY }
		)
		for _, child in ipairs(obj:GetDescendants()) do
			if child:IsA("TextLabel") or child:IsA("TextButton") then
				safeTween(child,
					TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ TextTransparency = 0 }
				)
			elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
				safeTween(child,
					TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ ImageTransparency = 0 }
				)
			end
		end
	end)
end

local function bounceOut(obj: GuiObject, delayTime: number?, epoch: number?, callback: (() -> ())?)
	local basePos = getBasePosition(obj)
	local targetPos = basePos + UDim2.new(0, 0, 0.4, 0)
	task.delay(delayTime or 0, function()
		if not isEpochCurrent(epoch) then
			return
		end
		local t = safeTween(obj,
			TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Position = targetPos, BackgroundTransparency = 1 }
		)
		for _, child in ipairs(obj:GetDescendants()) do
			if child:IsA("TextLabel") or child:IsA("TextButton") then
				safeTween(child,
					TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ TextTransparency = 1 }
				)
			elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
				safeTween(child,
					TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ ImageTransparency = 1 }
				)
			end
		end
		task.delay(0.42, function()
			if not isEpochCurrent(epoch) then
				return
			end
			obj.Position = basePos
			if callback then
				callback()
			end
		end)
	end)
end

-- ============================================================
-- Loading
-- ============================================================

local function runRealLoading(epoch: number)
	local assetsToLoad = {}
	-- โหลดเฉพาะ Asset ใน UI เพื่อป้องกันหน้าค้าง (Infinite Yield) และลดภาระเครื่อง
	for _, v in ipairs(_gui:GetDescendants()) do
		if v:IsA("ImageLabel") or v:IsA("ImageButton") or v:IsA("Sound") then
			table.insert(assetsToLoad, v)
		end
	end

	local total  = math.max(#assetsToLoad, 1)
	local loaded = 0
	local lastUiUpdate = 0
	local isFinished = false

	local function getText(p: number)
		if p < 0.25 then return LOADING_MESSAGES.LOADING_UI
		elseif p < 0.50 then return LOADING_MESSAGES.LOADING_ASSETS
		elseif p < 0.75 then return LOADING_MESSAGES.LOADING_ICONS
		elseif p < 0.95 then return LOADING_MESSAGES.LOADING_SOUNDS
		else return LOADING_MESSAGES.ALMOST_DONE
			end
		end

	-- ระบบ Failsafe: บังคับจบการโหลดถ้าผ่านไป 10 วินาที (กันค้าง)
	task.delay(10, function()
		isFinished = true
	end)

	task.spawn(function()
		ContentProvider:PreloadAsync(assetsToLoad, function(_id, _status)
			if not isEpochCurrent(epoch) or isFinished then return end
			loaded += 1
			local now = os.clock()
			if now - lastUiUpdate < 1 / 30 and loaded < total then return end
			lastUiUpdate = now
			local progress = loaded / total
			_loadingFill.Size = UDim2.new(progress, 0, _fillSizeY.Scale, _fillSizeY.Offset)
			_loadingText.Text = getText(progress)
		end)
		isFinished = true
	end)

	while not isFinished and isEpochCurrent(epoch) do
		task.wait(0.1)
	end

	if not isEpochCurrent(epoch) then return end

	safeTween(_loadingFill,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 0, _fillSizeY.Scale, _fillSizeY.Offset) }
	)
	_loadingText.Text = "READY!"
	task.wait(0.35)
end

local function showPlayButton(epoch: number)
	_playButton.Visible = true
	bounceIn(_playButton, 0, epoch)
	
	task.delay(0.6, function()
		if not isEpochCurrent(epoch) then return end
		_isInteractive = true
		_playButton.Active = true
	end)
	
	_pulseEpoch += 1
	local pulseEpoch = _pulseEpoch

	-- Pulse loop
	task.spawn(function()
		task.wait(0.65)
		while isEpochCurrent(epoch) and pulseEpoch == _pulseEpoch and _playButton.Visible do
			safeTween(_playButton,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ BackgroundTransparency = math.min(BG_TRANSPARENCY + 0.1, 1) }
			)
			task.wait(0.9)
			if not isEpochCurrent(epoch) or pulseEpoch ~= _pulseEpoch or not _playButton.Visible then break end
			safeTween(_playButton,
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

	_basePositions[_loadingBarBG] = _loadingBarBG.Position
	_basePositions[_playButton] = _playButton.Position

	-- Hover
	local origSize: UDim2
	_playButton.MouseEnter:Connect(function()
		if not _isInteractive then return end
		if not origSize then origSize = _playButton.Size end
		safeTween(_playButton, TweenInfo.new(0.2), {
			Size = origSize + UDim2.fromOffset(12, 6)
		})
	end)
	_playButton.MouseLeave:Connect(function()
		if not _isInteractive then return end
		if origSize then
			safeTween(_playButton, TweenInfo.new(0.2), { Size = origSize })
		end
	end)

	-- Play button
	_playButton.MouseButton1Click:Connect(function()
		
		if not _isInteractive then
			return
		end
		if _onPlayPressed then
			_isInteractive = false
			_playButton.Active = false
			_onPlayPressed()
		end
	end)
end

local Lighting = game:GetService("Lighting")
local _spookyCC: ColorCorrectionEffect? = nil

-- เริ่ม loading และแสดง UI
function IntroScreen.start()
	local epoch = nextEpoch()
	_isInteractive = false
	_playButton.Active = false
	_gui.Enabled = true
	
	-- สร้างเอฟเฟกต์แสงหน้ากลัว (Spooky Lighting)
	if not _spookyCC then
		_spookyCC = Instance.new("ColorCorrectionEffect")
		_spookyCC.Name = "IntroSpookyEffect"
		_spookyCC.Brightness = 0
		_spookyCC.Contrast = 0.2
		_spookyCC.Saturation = -0.4
		_spookyCC.TintColor = Color3.fromRGB(215, 250, 255) -- โทนเขียวมืดๆ
		_spookyCC.Parent = Lighting
	end
	
	task.spawn(function()
		runRealLoading(epoch)
		if not isEpochCurrent(epoch) then
			return
		end
		-- ซ่อน loading bar
		bounceOut(_loadingBarBG, 0, epoch, function()
			_loadingBarBG.Visible = false
			-- แสดงปุ่ม
			showPlayButton(epoch)
		end)
	end)
end

-- เด้งออกทั้งหมด แล้ว disable
function IntroScreen.hide(onHidden: (() -> ())?)
	local epoch = nextEpoch()
	_pulseEpoch += 1
	_isInteractive = false
	_playButton.Active = false
	
	-- ค่อยๆ ปิดเอฟเฟกต์แสงน่ากลัว (Fade out spooky lighting)
	if _spookyCC then
		local ccTween = TweenService:Create(_spookyCC, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Brightness = 0,
			Contrast = 0,
			Saturation = 0,
			TintColor = Color3.fromRGB(255, 255, 255)
		})
		ccTween.Completed:Connect(function()
			if _spookyCC then
				_spookyCC:Destroy()
				_spookyCC = nil
			end
		end)
		ccTween:Play()
	end

	bounceOut(_playButton, 0, epoch, function()
		_playButton.Visible = false
		_gui.Enabled = false
		if onHidden then
			onHidden()
		end
	end)
end

return IntroScreen
