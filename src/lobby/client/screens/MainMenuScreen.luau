-- ============================================================
-- MainMenuScreen.luau | ModuleScript
-- วางไว้ใน: src/lobby/client/screens/
-- หน้าที่: จัดการ MainMenuGui (MenuBtn, MusicBtn, PlayBtn)
-- ============================================================

local TweenService = game:GetService("TweenService")

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
local _activeTweens: {[Instance]: Tween} = {}
local _transitionEpoch = 0
local _isInteractive = false
local _isQueueMode = false
local _onQueueCancelPressed: (() -> ())?
local _defaultPlayText = "PLAY!"
local BG_TRANSPARENCY = 0.8
-- ประกาศค่าคงที่ไว้ด้านบนสุดของไฟล์
local OFF_SCREEN_OFFSET_X = 1.5


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
	
	-- คำนวณจุดเริ่มต้นให้อยู่นอกจอ (ถ้าอยู่ครึ่งซ้ายให้มาจากซ้าย ถ้าอยู่ครึ่งขวาให้มาจากขวา)
	local isLeft = targetPos.X.Scale < 0.5
	local startXOffset = isLeft and -OFF_SCREEN_OFFSET_X or OFF_SCREEN_OFFSET_X
	local startPos = UDim2.new(targetPos.X.Scale + startXOffset, targetPos.X.Offset, targetPos.Y.Scale, targetPos.Y.Offset)
	
	obj.Position    = startPos
	obj.Visible     = true
	obj.BackgroundTransparency = 1
	
	-- เริ่มต้นให้โปร่งใสทั้งหมด
	for _, child in ipairs(obj:GetDescendants()) do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			child.TextTransparency = 1
		elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
			child.ImageTransparency = 1
		end
	end
	
	task.delay(delayTime or 0, function()
		if not isEpochCurrent(epoch) then
			return
		end
		-- เลื่อนเข้ามาแบบสมูท (Exponential)
		safeTween(obj,
			TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
			{ Position = targetPos, BackgroundTransparency = BG_TRANSPARENCY }
		)
		-- ค่อยๆ จางตัวอักษรขึ้นมา
		for _, child in ipairs(obj:GetDescendants()) do
			safeTween(child,
				TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0, ImageTransparency = 0 }
			)
		end
	end)
end

local function bounceOut(obj: GuiObject, delayTime: number?, epoch: number?, callback: (() -> ())?)
	local basePos = getBasePosition(obj)
	
	-- คำนวณจุดที่จะเลื่อนออกไป (ออกทางเดิมที่เข้ามา)
	local isLeft = basePos.X.Scale < 0.5
	local endXOffset = isLeft and -OFF_SCREEN_OFFSET_X or OFF_SCREEN_OFFSET_X
	local targetPos = UDim2.new(basePos.X.Scale + endXOffset, basePos.X.Offset, basePos.Y.Scale, basePos.Y.Offset)
	
	task.delay(delayTime or 0, function()
		if not isEpochCurrent(epoch) then
			return
		end
		-- เลื่อนออกแบบพุ่งตัว (Exponential In)
		local t = safeTween(obj,
			TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.In),
			{ Position = targetPos, BackgroundTransparency = 1 }
		)
		for _, child in ipairs(obj:GetDescendants()) do
			safeTween(child,
				TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1, ImageTransparency = 1 }
			)
		end
		task.delay(0.65, function()
            if not isEpochCurrent(epoch) or obj.Visible then
                return
            end
            obj.Position = basePos
            obj.Visible = false
            if callback then
                callback()
            end
        end)
	end)
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

	-- ซ่อนไว้ก่อน (show() จะเปิด)
	_menuBtn.Visible  = false
	_musicBtn.Visible = false
	_playBtn.Visible  = false

	-- Hover effects
	local function addHover(btn: GuiButton)
		local origSize: UDim2
		btn.MouseEnter:Connect(function()
			if not _isInteractive then return end
			if not origSize then origSize = btn.Size end
			safeTween(btn, TweenInfo.new(0.18), {
				Size = origSize + UDim2.new(0, 10, 0, 4),
			})
		end)
		btn.MouseLeave:Connect(function()
			if not _isInteractive then return end
			if origSize then
				safeTween(btn, TweenInfo.new(0.18), { Size = origSize })
			end
		end)
	end
	addHover(_menuBtn)
	addHover(_musicBtn)
	addHover(_playBtn)

	-- Connections
	_menuBtn.MouseButton1Click:Connect(function()
		if not _isInteractive then
			return
		end
		if _onMenuPressed then _onMenuPressed() end
	end)

	_musicBtn.MouseButton1Click:Connect(function()
		if not _isInteractive then
			return
		end
		if _onMusicPressed then _onMusicPressed() end
	end)

	_playBtn.MouseButton1Click:Connect(function()
		if not _isInteractive then
			return
		end
		if _isQueueMode then
			if _onQueueCancelPressed then
				_onQueueCancelPressed()
			end
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
	bounceIn(_menuBtn,  0, epoch)
	bounceIn(_musicBtn, 0.1, epoch)
	bounceIn(_playBtn,  0.2, epoch)
	task.delay(1.1, function()
		if not isEpochCurrent(epoch) then
			return
		end
		setInteractive(true)
		if onShown then
			onShown()
		end
	end)
end

function MainMenuScreen.hide(onHidden: (() -> ())?)
	local epoch = nextEpoch()
	_isQueueMode = false
	_onQueueCancelPressed = nil
	setInteractive(false)
	bounceOut(_playBtn,  0, epoch)
	bounceOut(_musicBtn, 0.08, epoch)
	bounceOut(_menuBtn,  0.16, epoch)
	task.delay(0.5, function()
		if not isEpochCurrent(epoch) then
			return
		end
		_gui.Enabled = false
		if onHidden then
			onHidden()
		end
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

	bounceIn(_playBtn, 0, epoch)
	task.delay(0.6, function()
		if not isEpochCurrent(epoch) then
			return
		end
		setInteractive(true)
	end)
end

function MainMenuScreen.updateQueueButton(text: string)
	if not _isQueueMode then
		return
	end
	setPlayButtonText(text)
end

function MainMenuScreen.setQueueTeleporting(text: string)
	if not _isQueueMode then
		return
	end
	setPlayButtonText(text)
	setInteractive(false)
end

function MainMenuScreen.hideQueueButton(onHidden: (() -> ())?)
	local epoch = nextEpoch()
	setInteractive(false)
	bounceOut(_playBtn, 0, epoch, function()
		if not isEpochCurrent(epoch) then
			return
		end
		_playBtn.Visible = false
		setPlayButtonText(_defaultPlayText)
		_isQueueMode = false
		_onQueueCancelPressed = nil
		_gui.Enabled = false
		if onHidden then
			onHidden()
		end
	end)
end

return MainMenuScreen