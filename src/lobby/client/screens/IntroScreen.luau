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

-- ============================================================
-- Utils (private)
-- ============================================================

local function safeTween(obj, info, goals)
	local g = {}
	for k, v in pairs(goals) do
		if pcall(function() return obj[k] end) then g[k] = v end
	end
	if next(g) then
		local prev = _activeTweens[obj]
		if prev then
			prev:Cancel()
		end
		local t = TweenService:Create(obj, info, g)
		_activeTweens[obj] = t
		t.Completed:Connect(function()
			if _activeTweens[obj] == t then
				_activeTweens[obj] = nil
			end
		end)
		t:Play()
		return t
	end
end

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
	if pcall(function() return obj.BackgroundTransparency end) then
		obj.BackgroundTransparency = 1
	end
	task.delay(delayTime or 0, function()
		if not isEpochCurrent(epoch) then
			return
		end
		safeTween(obj,
			TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = targetPos, BackgroundTransparency = BG_TRANSPARENCY }
		)
		for _, child in ipairs(obj:GetDescendants()) do
			safeTween(child,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0, ImageTransparency = 0 }
			)
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
		safeTween(obj,
			TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Position = targetPos, BackgroundTransparency = 1 }
		)
		for _, child in ipairs(obj:GetDescendants()) do
			safeTween(child,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1, ImageTransparency = 1 }
			)
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

	safeTween(_loadingFill,
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
	local originalSize: UDim2
	_playButton.MouseEnter:Connect(function()
		if not originalSize then originalSize = _playButton.Size end
		TweenService:Create(_playButton, TweenInfo.new(0.18), {
			Size = originalSize + UDim2.new(0, 12, 0, 6),
		}):Play()
	end)
	_playButton.MouseLeave:Connect(function()
		if originalSize then
			TweenService:Create(_playButton, TweenInfo.new(0.18), {
				Size = originalSize,
			}):Play()
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

-- เริ่ม loading และแสดง UI
function IntroScreen.start()
	local epoch = nextEpoch()
	_isInteractive = false
	_playButton.Active = false
	_gui.Enabled = true
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
	bounceOut(_playButton, 0, epoch, function()
		_playButton.Visible = false
		_gui.Enabled = false
		if onHidden then
			onHidden()
		end
	end)
end

return IntroScreen
