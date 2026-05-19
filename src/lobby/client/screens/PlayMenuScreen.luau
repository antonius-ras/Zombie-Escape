-- ============================================================
-- PlayMenuScreen.luau | ModuleScript
-- วางไว้ใน: src/lobby/client/screens/
-- หน้าที่: จัดการ PlayMenuGui
--          PlayMenu / CloseBtn / InviteBtn / ServerBtn / SoloBtn
--          ServerListFrame / PartyFrame / InvitePromptFrame
-- ============================================================

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local PlayMenuScreen = {}

-- ── References ───────────────────────────────────────────────
local _gui: ScreenGui
local _playMenu: Frame
local _closeBtn: GuiButton
local _inviteBtn: GuiButton
local _serverBtn: GuiButton
local _soloBtn: GuiButton
local _serverListFrame: Frame
local _partyFrame: Frame
local _invitePromptFrame: Frame
local _serverScroll: ScrollingFrame?
local _serverTemplate: Frame?
local _serverNoText: GuiObject?
local _onlineScroll: ScrollingFrame?
local _onlineFriendTemplate: Frame?
local _partyScroll: ScrollingFrame?
local _partyMemberTemplate: Frame?
local _partyLeaveBtn: GuiButton?
local _partyMatchmakingBtn: GuiButton?

-- callbacks
local _onClose:      () -> ()
local _onSolo:       () -> ()
local _onServerPanelOpened: (() -> ())?
local _onJoinServer: ((string) -> ())?
local _onPartyPanelOpened: (() -> ())?
local _onInviteFriend: ((number) -> ())?
local _onPartyMemberAction: ((number, string) -> ())?
local _onPartyMatchmakingAction: ((string) -> ())?
local _onInvitePromptResponse: ((string, boolean) -> ())?

-- state
local _activeSubFrame: Frame? = nil
local _basePositions: {[GuiObject]: UDim2} = {}
local _activeTweens: {[Instance]: Tween} = {}
local _transitionEpoch = 0
local _isInteractive = false
local _currentInviteId: string? = nil
local _isStandalonePromptMode = false
local _serverConnections: {RBXScriptConnection} = {}
local _onlineConnections: {RBXScriptConnection} = {}
local _partyConnections: {RBXScriptConnection} = {}
local _partyMemberConnections: {RBXScriptConnection} = {}
local _promptConnections: {RBXScriptConnection} = {}
local _partyLeaveUserId: number? = nil
local _isLocalPartyLeader = false
local _isInParty = false
local _partyMemberCount = 1
local _isPartyQueueing = false
local _isPartyTeleporting = false
local _partyQueueSecondsLeft = 0
local _avatarThumbByUserId: {[number]: string} = {}
local _soloVisualStates: {[Instance]: {TextColor3: Color3?, ImageColor3: Color3?}} = {}
local _viewportSizeConnection: RBXScriptConnection? = nil
local _currentCameraConnection: RBXScriptConnection? = nil

local FRAME_BG_TRANSPARENCY = 0.65
local BTN_BG_TRANSPARENCY = 1
local SERVER_ENTRY_MIN_HEIGHT = 96
local ONLINE_ENTRY_MIN_HEIGHT = 60
local PARTY_ENTRY_MIN_HEIGHT = 60
local PARTY_START_LABEL = "START MATCHMAKING"
local PHONE_SHORT_SIDE_BREAKPOINT = 540
local TABLET_SHORT_SIDE_BREAKPOINT = 900
local PHONE_UI_SCALE = 0.84
local TABLET_UI_SCALE = 0.92
local PLAY_MENU_MAX_SIZE = Vector2.new(1100, 760)
local SERVER_LIST_MAX_SIZE = Vector2.new(1240, 780)
local PARTY_FRAME_MAX_SIZE = Vector2.new(1400, 820)
local INVITE_PROMPT_MAX_SIZE = Vector2.new(760, 360)
local SOLO_DISABLED_COLOR = Color3.fromRGB(130, 130, 130)
local SERVER_JOIN_DISABLED_COLOR = Color3.fromRGB(130, 130, 130)
local SERVER_LOADING_LABEL = "LOADING SERVERS..."
local SERVER_EMPTY_LABEL = "NO ACTIVE SERVERS"
local DEFAULT_SERVER_MAP_LABEL = "GAMEPLAY"
local MAX_SERVER_PREVIEW_IMAGES = 4

local STATUS_LABELS = {
	LOBBY_SAME = "Lobby (Same Server)",
	LOBBY_OTHER = "Lobby (Other Server)",
	IN_PARTY = "In Party",
	IN_GAMEPLAY = "In Gameplay",
	OFFLINE = "Offline",
}

-- ============================================================
-- Utils (private)
-- ============================================================

local function safeTween(obj, info, goals)
	local g = {}
	for k, v in pairs(goals) do
		if pcall(function()
			return obj[k]
		end) then
			g[k] = v
		end
	end
	if next(g) then
		local prev = _activeTweens[obj]
		if prev then
			prev:Cancel()
		end
		local tween = TweenService:Create(obj, info, g)
		_activeTweens[obj] = tween
		tween.Completed:Connect(function()
			if _activeTweens[obj] == tween then
				_activeTweens[obj] = nil
			end
		end)
		tween:Play()
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

local function getTargetBackgroundTransparency(obj: GuiObject): number
	if obj == _partyFrame then
		return 1
	end

	return FRAME_BG_TRANSPARENCY
end

local function bounceIn(obj: GuiObject, delayTime: number?, epoch: number?)
	local targetPos = getBasePosition(obj)
	local targetBackgroundTransparency = getTargetBackgroundTransparency(obj)
	obj.Position    = targetPos + UDim2.fromScale(0, 0.3)
	obj.Visible     = true
	
	if pcall(function() return obj.BackgroundTransparency end) then
		obj.BackgroundTransparency = 1
	end

	-- รีเซ็ตค่า Transparency ของลูกๆ ทันทีเพื่อป้องกันปัญหาตัวหนังสือเทา/จาง
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
		safeTween(obj,
			TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = targetPos, BackgroundTransparency = targetBackgroundTransparency }
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
	local targetPos = basePos + UDim2.fromScale(0, 0.4)
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

local function captureSoloVisualState(instance: Instance)
	local state = {
		TextColor3 = nil :: Color3?,
		ImageColor3 = nil :: Color3?,
		
	}

	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		state.TextColor3 = instance.TextColor3
	end

	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		state.ImageColor3 = instance.ImageColor3
	end

	if state.TextColor3 or state.ImageColor3 then
		_soloVisualStates[instance] = state
	end
end

local function cacheSoloVisualStates(root: Instance)
	table.clear(_soloVisualStates)
	captureSoloVisualState(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		captureSoloVisualState(descendant)
	end
end

local function applySoloButtonVisualState()
	local useDisabledColor = _isInParty
	for instance, state in pairs(_soloVisualStates) do
		if not instance.Parent then
			continue
		end

		if state.TextColor3 and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
			instance.TextColor3 = if useDisabledColor then SOLO_DISABLED_COLOR else state.TextColor3
		end

		if state.ImageColor3 and (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
			instance.ImageColor3 = if useDisabledColor then SOLO_DISABLED_COLOR else state.ImageColor3
		end

		if state.StrokeColor and instance:IsA("UIStroke") then
			instance.Color = if useDisabledColor then SOLO_DISABLED_COLOR else state.StrokeColor
		end
	end
end

local function setMainButtonsInteractive(isInteractive: boolean)
	_isInteractive = isInteractive
	if _closeBtn then
		_closeBtn.Active = isInteractive
	end
	if _inviteBtn then
		_inviteBtn.Active = isInteractive
	end
	if _serverBtn then
		_serverBtn.Active = isInteractive
	end
	if _soloBtn then
		_soloBtn.Active = isInteractive and not _isInParty
		_soloBtn.AutoButtonColor = isInteractive and not _isInParty
	end
	applySoloButtonVisualState()
end

local function disconnectConnections(connections: {RBXScriptConnection})
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
end

local function findFirstDescendantByNames(root: Instance, names: {string}): Instance?
	for _, name in ipairs(names) do
		local found = root:FindFirstChild(name, true)
		if found then
			return found
		end
	end
	return nil
end

local function setTextIfAny(target: Instance?, text: string)
	if not target then
		return
	end
	pcall(function()
		(target :: any).Text = text
	end)
end

local function setVisibleIfAny(target: Instance?, isVisible: boolean)
	if not target then
		return
	end
	if target:IsA("GuiObject") then
		target.Visible = isVisible
	end
end

local function setImageIfAny(target: Instance?, image: string)
	if not target then
		return
	end

	if target:IsA("ImageLabel") or target:IsA("ImageButton") then
		target.Image = image
	end
end

local function getRequiredServerJoinSlots(): number
	if _isInParty then
		return math.max(_partyMemberCount, 1)
	end

	return 1
end

local function canLocalPlayerJoinServer(server: any): boolean
	if type(server) ~= "table" or server.canJoin == false then
		return false
	end

	if _isInParty and not _isLocalPartyLeader then
		return false
	end

	local maxPlayers = math.max(0, tonumber(server.maxPlayers) or 0)
	if maxPlayers <= 0 then
		return true
	end

	local currentPlayers = math.max(0, tonumber(server.playerCount) or 0)
	local availableSlots = math.max(0, maxPlayers - currentPlayers)
	return availableSlots >= getRequiredServerJoinSlots()
end

local function applyJoinButtonVisualState(joinBtn: GuiButton, defaultBackgroundColor: Color3, isEnabled: boolean)
	joinBtn.Visible = true
	joinBtn.Active = isEnabled
	joinBtn.AutoButtonColor = isEnabled
	joinBtn.BackgroundColor3 = if isEnabled then defaultBackgroundColor else SERVER_JOIN_DISABLED_COLOR
end

local function findAvatarImage(root: Instance): Instance?
	local namedAvatar = findFirstDescendantByNames(root, {
		"Avatar",
		"AvatarImage",
		"PlayerAvatar",
		"InviteAvatar",
		"InviterAvatar",
		"ProfileImage",
		"AvatarIcon",
	})
	if namedAvatar and (namedAvatar:IsA("ImageLabel") or namedAvatar:IsA("ImageButton")) then
		return namedAvatar
	end

	for _, child in ipairs(root:GetDescendants()) do
		if child:IsA("ImageLabel") or child:IsA("ImageButton") then
			local lowerName = string.lower(child.Name)
			if string.find(lowerName, "avatar", 1, true)
				or string.find(lowerName, "profile", 1, true)
				or string.find(lowerName, "head", 1, true)
			then
				return child
			end
		end
	end

	return nil
end

local function applyAvatarThumbnail(entry: Instance, userId: number)
	local avatarImage = findAvatarImage(entry)
	if not avatarImage then
		return
	end

	if not (avatarImage:IsA("ImageLabel") or avatarImage:IsA("ImageButton")) then
		return
	end

	avatarImage:SetAttribute("AvatarUserId", userId)

	local cachedThumb = _avatarThumbByUserId[userId]
	if cachedThumb then
		if avatarImage:GetAttribute("AvatarUserId") == userId then
			setImageIfAny(avatarImage, cachedThumb)
		end
		return
	end

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if not ok or type(content) ~= "string" or content == "" then
			return
		end

		_avatarThumbByUserId[userId] = content
		if entry.Parent and avatarImage.Parent and avatarImage:GetAttribute("AvatarUserId") == userId then
			setImageIfAny(avatarImage, content)
		end
	end)
end

local function applyAvatarThumbnailToTarget(target: Instance?, userId: number)
	if not target or not (target:IsA("ImageLabel") or target:IsA("ImageButton")) then
		return
	end

	target:SetAttribute("AvatarUserId", userId)

	local cachedThumb = _avatarThumbByUserId[userId]
	if cachedThumb then
		if target:GetAttribute("AvatarUserId") == userId then
			setImageIfAny(target, cachedThumb)
		end
		return
	end

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if not ok or type(content) ~= "string" or content == "" then
			return
		end

		_avatarThumbByUserId[userId] = content
		if target.Parent and target:GetAttribute("AvatarUserId") == userId then
			setImageIfAny(target, content)
		end
	end)
end

local function formatServerUptime(startTime: number?): string
	if type(startTime) ~= "number" or startTime <= 0 then
		return "NEW"
	end

	local elapsed = math.max(0, os.time() - startTime)
	local hours = math.floor(elapsed / 3600)
	local minutes = math.floor((elapsed % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	if minutes > 0 then
		return string.format("%dm", minutes)
	end

	return "<1m"
end

local function updateLayoutForScroll(scroll: ScrollingFrame?)
	if not scroll then
		return
	end
	local layout = scroll:FindFirstChildOfClass("UIListLayout")
	if layout then
		scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
	end
end

local function setServerEmptyState(text: string, isVisible: boolean)
	if not _serverNoText then
		return
	end

	setTextIfAny(_serverNoText, text)
	_serverNoText.Visible = isVisible
end

local function clearGeneratedEntries(scroll: ScrollingFrame?)
	if not scroll then
		return
	end

	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") and child:GetAttribute("GeneratedByScript") == true then
			child:Destroy()
		end
	end
end

local function applyMinimumEntryHeight(entry: GuiObject, minHeight: number)
	local constraint = entry:FindFirstChildOfClass("UISizeConstraint")
	if not constraint then
		constraint = Instance.new("UISizeConstraint")
		constraint.Parent = entry
	end
	if constraint.MinSize.Y < minHeight then
		constraint.MinSize = Vector2.new(constraint.MinSize.X, minHeight)
	end
end

local function getViewportSize(): Vector2
	local camera = workspace.CurrentCamera
	if camera then
		local viewportSize = camera.ViewportSize
		if viewportSize.X > 0 and viewportSize.Y > 0 then
			return viewportSize
		end
	end

	return Vector2.new(1920, 1080)
end

local function getResponsiveScale(viewportSize: Vector2): number
	local shortSide = math.min(viewportSize.X, viewportSize.Y)
	if shortSide <= PHONE_SHORT_SIDE_BREAKPOINT then
		return PHONE_UI_SCALE
	end
	if shortSide <= TABLET_SHORT_SIDE_BREAKPOINT then
		return TABLET_UI_SCALE
	end
	return 1
end

local function ensureResponsiveScale(target: GuiObject): UIScale
	local existingScale = target:FindFirstChild("ResponsiveScale")
	if existingScale and existingScale:IsA("UIScale") then
		return existingScale
	end

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "ResponsiveScale"
	uiScale.Parent = target
	return uiScale
end

local function ensureResponsiveSizeConstraint(target: GuiObject): UISizeConstraint
	local existingConstraint = target:FindFirstChild("ResponsiveSizeConstraint")
	if existingConstraint and existingConstraint:IsA("UISizeConstraint") then
		return existingConstraint
	end

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.Name = "ResponsiveSizeConstraint"
	sizeConstraint.Parent = target
	return sizeConstraint
end

local function applyResponsiveFrameSizing(target: GuiObject?, maxSize: Vector2, scale: number)
	if not target then
		return
	end

	local uiScale = ensureResponsiveScale(target)
	uiScale.Scale = scale

	local sizeConstraint = ensureResponsiveSizeConstraint(target)
	sizeConstraint.MaxSize = maxSize
end

local function applyResponsiveLayout()
	local viewportSize = getViewportSize()
	local scale = getResponsiveScale(viewportSize)

	applyResponsiveFrameSizing(_playMenu, PLAY_MENU_MAX_SIZE, scale)
	applyResponsiveFrameSizing(_serverListFrame, SERVER_LIST_MAX_SIZE, scale)
	applyResponsiveFrameSizing(_partyFrame, PARTY_FRAME_MAX_SIZE, scale)
	applyResponsiveFrameSizing(_invitePromptFrame, INVITE_PROMPT_MAX_SIZE, scale)

	if _serverScroll then
		_serverScroll.ScrollBarThickness = math.max(4, math.floor(8 * scale))
		updateLayoutForScroll(_serverScroll)
	end

	if _onlineScroll then
		_onlineScroll.ScrollBarThickness = math.max(4, math.floor(8 * scale))
		updateLayoutForScroll(_onlineScroll)
	end

	if _partyScroll then
		_partyScroll.ScrollBarThickness = math.max(4, math.floor(8 * scale))
		updateLayoutForScroll(_partyScroll)
	end
end

local function bindResponsiveLayout()
	if _viewportSizeConnection then
		_viewportSizeConnection:Disconnect()
		_viewportSizeConnection = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		_viewportSizeConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			applyResponsiveLayout()
		end)
	end
end

local function refreshPartyMatchmakingButton()
	if not _partyMatchmakingBtn then
		return
	end

	if _isLocalPartyLeader and not _isPartyQueueing and not _isPartyTeleporting then
		_partyMatchmakingBtn.Visible = true
		_partyMatchmakingBtn.Active = true
		setTextIfAny(_partyMatchmakingBtn, PARTY_START_LABEL)
		return
	end

	_partyMatchmakingBtn.Visible = false
	_partyMatchmakingBtn.Active = false
end

-- ============================================================
-- Sub-frame management
-- ============================================================

-- ซ่อน sub-frame ที่เปิดอยู่ก่อน แล้วเปิดอันใหม่
local function switchSubFrame(newFrame: Frame?, epoch: number?)
	if _activeSubFrame == newFrame then
		return
	end

	-- ปิดอันเดิม
	if _activeSubFrame and _activeSubFrame ~= newFrame then
		local old = _activeSubFrame
		_activeSubFrame = nil
		bounceOut(old, 0, epoch, function()
			old.Visible = false
			if not isEpochCurrent(epoch) then
				return
			end
			if newFrame then
				_activeSubFrame = newFrame
				bounceIn(newFrame, 0, epoch)
			end
		end)
		return
	end

	-- เปิดอันใหม่
	if newFrame then
		_activeSubFrame = newFrame
		bounceIn(newFrame, 0, epoch)
	else
		_activeSubFrame = nil
	end
end

local function hideAllSubFrames(epoch: number?)
	for _, frame in ipairs({ _serverListFrame, _partyFrame, _invitePromptFrame }) do
		if frame.Visible then
			local f = frame
			bounceOut(f, 0, epoch, function()
				f.Visible = false
			end)
		end
	end
	_activeSubFrame = nil
end

local function forceHideAllSubFrames()
	for _, frame in ipairs({ _serverListFrame, _partyFrame, _invitePromptFrame }) do
		frame.Visible = false
	end
	_activeSubFrame = nil
end

-- ============================================================
-- Button Highlight (active state)
-- ============================================================

local _activeBtn: GuiButton? = nil

local function setActiveBtn(btn: GuiButton?)
	-- คืนสีปุ่มเดิม
	if _activeBtn and _activeBtn ~= btn then
		TweenService:Create(_activeBtn, TweenInfo.new(0.2), {
			BackgroundTransparency = BTN_BG_TRANSPARENCY,
		}):Play()
	end
	_activeBtn = btn
	-- highlight ปุ่มใหม่
	if btn then
		TweenService:Create(btn, TweenInfo.new(0.2), {
			BackgroundTransparency = BTN_BG_TRANSPARENCY,
		}):Play()
	end
end

local function openSubPage(targetFrame: Frame)
	local epoch = nextEpoch()
	setMainButtonsInteractive(false)
	if _playMenu.Visible then
		bounceOut(_playMenu, 0, epoch, function()
			_playMenu.Visible = false
			switchSubFrame(targetFrame, epoch)
			if isEpochCurrent(epoch) then
				setMainButtonsInteractive(true)
			end
		end)
	else
		switchSubFrame(targetFrame, epoch)
		if isEpochCurrent(epoch) then
			setMainButtonsInteractive(true)
		end
	end
end

local function closeSubPage(restorePlayMenu: boolean?)
	if restorePlayMenu == nil then
		restorePlayMenu = true
	end

	local epoch = nextEpoch()
	setMainButtonsInteractive(false)
	local hadSubFrame = _activeSubFrame ~= nil
	switchSubFrame(nil, epoch)
	setActiveBtn(nil)
	if hadSubFrame then
		task.delay(0.45, function()
			if not isEpochCurrent(epoch) then
				return
			end
			if restorePlayMenu and _gui.Enabled and not _playMenu.Visible then
				bounceIn(_playMenu, 0, epoch)
			end
			setMainButtonsInteractive(true)
		end)
	elseif restorePlayMenu and _gui.Enabled and not _playMenu.Visible then
		bounceIn(_playMenu, 0, epoch)
		setMainButtonsInteractive(true)
	else
		setMainButtonsInteractive(true)
	end
end

-- ============================================================
-- Public API
-- ============================================================

function PlayMenuScreen.init(gui: ScreenGui, onClose: () -> (), onSolo: () -> ())
	_gui     = gui
	_onClose = onClose
	_onSolo  = onSolo

	-- Main frame
	_playMenu         = gui:WaitForChild("PlayMenu")
	_closeBtn         = _playMenu:WaitForChild("CloseBtn")
	_inviteBtn        = _playMenu:WaitForChild("InviteBtn")
	_serverBtn        = _playMenu:WaitForChild("ServerBtn")
	_soloBtn          = _playMenu:WaitForChild("SoloBtn")

	-- Sub frames
	_serverListFrame  = gui:WaitForChild("ServerListFrame")
	_partyFrame       = gui:WaitForChild("PartyFrame")
	_invitePromptFrame = gui:WaitForChild("InvitePromptFrame")
	_serverScroll = _serverListFrame:FindFirstChild("ScrollingFrame", true) :: ScrollingFrame?
	_serverTemplate = _serverListFrame:FindFirstChild("ServerTemplate", true) :: Frame?
	_serverNoText = findFirstDescendantByNames(_serverListFrame, { "NoServerText", "EmptyText", "NoServerLabel" }) :: GuiObject?
	_onlineScroll = _partyFrame:FindFirstChild("OnlineScroll", true) :: ScrollingFrame?
	_onlineFriendTemplate = _partyFrame:FindFirstChild("OnlineFriendTemplate", true) :: Frame?
	_partyScroll = _partyFrame:FindFirstChild("PartyScroll", true) :: ScrollingFrame?
	_partyMemberTemplate = _partyFrame:FindFirstChild("PartyMemberTemplate", true) :: Frame?
	_partyLeaveBtn = findFirstDescendantByNames(_partyFrame, { "DisbandBtn", "LeavePartyBtn", "LeaveBtn" }) :: GuiButton?
	_partyMatchmakingBtn = findFirstDescendantByNames(_partyFrame, { "MatchmakingBtn", "StartMatchmakingBtn", "StartQueueBtn" }) :: GuiButton?
	if _currentCameraConnection then
		_currentCameraConnection:Disconnect()
		_currentCameraConnection = nil
	end
	_currentCameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindResponsiveLayout()
		applyResponsiveLayout()
	end)
	bindResponsiveLayout()

	-- ซ่อนทั้งหมดก่อน
	_basePositions[_playMenu] = _playMenu.Position
	_basePositions[_serverListFrame] = _serverListFrame.Position
	_basePositions[_partyFrame] = _partyFrame.Position
	_basePositions[_invitePromptFrame] = _invitePromptFrame.Position

	_playMenu.Visible          = false
	_serverListFrame.Visible   = false
	_partyFrame.Visible        = false
	_invitePromptFrame.Visible = false
	if _serverTemplate then
		_serverTemplate.Visible = false
	end
	if _serverNoText then
		_serverNoText.Visible = false
	end
	if _onlineFriendTemplate then
		_onlineFriendTemplate.Visible = false
	end
	if _partyMemberTemplate then
		_partyMemberTemplate.Visible = false
	end
	if _partyLeaveBtn then
		_partyLeaveBtn.Visible = false
		_partyLeaveBtn.Active = false
	end
	applyResponsiveLayout()
	setMainButtonsInteractive(false)

	-- Hover effects
	local function addHover(btn: GuiButton)
		local origSize: UDim2
		btn.MouseEnter:Connect(function()
			if not origSize then
				origSize = btn.Size
			end
			TweenService:Create(btn, TweenInfo.new(0.18), {
				Size = origSize + UDim2.fromOffset(8, 4),
			}):Play()
		end)
		btn.MouseLeave:Connect(function()
			if origSize then
				TweenService:Create(btn, TweenInfo.new(0.18), { Size = origSize }):Play()
			end
		end)
	end

	addHover(_closeBtn)
	addHover(_inviteBtn)
	addHover(_serverBtn)
	addHover(_soloBtn)

	-- ให้พื้นหลังปุ่มโปร่งใสตามดีไซน์
	_closeBtn.BackgroundTransparency = BTN_BG_TRANSPARENCY
	_inviteBtn.BackgroundTransparency = BTN_BG_TRANSPARENCY
	_serverBtn.BackgroundTransparency = BTN_BG_TRANSPARENCY
	_soloBtn.BackgroundTransparency = BTN_BG_TRANSPARENCY
	cacheSoloVisualStates(_soloBtn)

	-- ── Button Connections ────────────────────────────────────

	-- ปุ่มปิด → กลับ MainMenu
	_closeBtn.MouseButton1Click:Connect(function()
		if not _isInteractive then
			return
		end
		setMainButtonsInteractive(false)
		PlayMenuScreen.hide(function()
			if _onClose then
				_onClose()
			end
		end)
	end)

	-- ปุ่มกากบาทย่อย (ถ้ามี) ใน Party/Server
	local closeServerBtn = _serverListFrame:FindFirstChild("CloseServerBtn", true)
	if closeServerBtn and closeServerBtn:IsA("GuiButton") then
		closeServerBtn.MouseButton1Click:Connect(function()
			closeSubPage()
		end)
	end

	local closePartyBtn = _partyFrame:FindFirstChild("ClosePartyBtn", true)
	if closePartyBtn and closePartyBtn:IsA("GuiButton") then
		closePartyBtn.MouseButton1Click:Connect(function()
			closeSubPage()
		end)
	end

	if _partyLeaveBtn and _partyLeaveBtn:IsA("GuiButton") then
		table.insert(_partyConnections, _partyLeaveBtn.MouseButton1Click:Connect(function()
			if _partyLeaveUserId and _onPartyMemberAction then
				if _isLocalPartyLeader then
					_onPartyMemberAction(_partyLeaveUserId, "disband")
				else
					_onPartyMemberAction(_partyLeaveUserId, "leave")
				end
			end
		end))
	end

	if _partyMatchmakingBtn and _partyMatchmakingBtn:IsA("GuiButton") then
		table.insert(_partyConnections, _partyMatchmakingBtn.MouseButton1Click:Connect(function()
			if not _onPartyMatchmakingAction then
				return
			end

			if not _isLocalPartyLeader then
				return
			end

			_onPartyMatchmakingAction("start")
		end))
		refreshPartyMatchmakingButton()
	end

	local acceptBtn = findFirstDescendantByNames(_invitePromptFrame, { "AcceptBtn", "Accept", "YesBtn" })
	if acceptBtn and acceptBtn:IsA("GuiButton") then
		table.insert(_promptConnections, acceptBtn.MouseButton1Click:Connect(function()
			local inviteId = _currentInviteId
			PlayMenuScreen.hideIncomingInvitePrompt()
			if inviteId and _onInvitePromptResponse then
				_onInvitePromptResponse(inviteId, true)
			end
		end))
	end

	local declineBtn = findFirstDescendantByNames(_invitePromptFrame, { "DeclineBtn", "Decline", "NoBtn", "RejectBtn" })
	if declineBtn and declineBtn:IsA("GuiButton") then
		table.insert(_promptConnections, declineBtn.MouseButton1Click:Connect(function()
			local inviteId = _currentInviteId
			PlayMenuScreen.hideIncomingInvitePrompt()
			if inviteId and _onInvitePromptResponse then
				_onInvitePromptResponse(inviteId, false)
			end
		end))
	end

	-- ปุ่ม Solo → เล่นคนเดียว (UIManager จัดการต่อ)
	_soloBtn.MouseButton1Click:Connect(function()
		if not _isInteractive or _isInParty then
			return
		end
		setMainButtonsInteractive(false)
		setActiveBtn(_soloBtn)
		hideAllSubFrames(nextEpoch())
		if _onSolo then
			_onSolo()
		end
	end)

	-- ปุ่ม Server → แสดงรายการเซิร์ฟเวอร์
	_serverBtn.MouseButton1Click:Connect(function()
		if not _isInteractive then
			return
		end
		setActiveBtn(_serverBtn)
		openSubPage(_serverListFrame)
		if _onServerPanelOpened then
			_onServerPanelOpened()
		end
	end)

	-- ปุ่ม Invite → แสดง Party Frame + Invite Prompt
	_inviteBtn.MouseButton1Click:Connect(function()
		if not _isInteractive then
			return
		end
		setActiveBtn(_inviteBtn)
		openSubPage(_partyFrame)
		if _onPartyPanelOpened then
			_onPartyPanelOpened()
		end
	end)
end

function PlayMenuScreen.show()
	local epoch = nextEpoch()
	setMainButtonsInteractive(false)
	forceHideAllSubFrames()
	setActiveBtn(nil)
	_playMenu.Visible = false
	_isInteractive = false
	_gui.Enabled = true
	-- PlayMenu เด้งขึ้นก่อน
	bounceIn(_playMenu, 0, epoch)
	task.delay(0.6, function()
		if isEpochCurrent(epoch) then
			setMainButtonsInteractive(true)
		end
	end)
end

function PlayMenuScreen.hide(onHidden: (() -> ())?)
	local epoch = nextEpoch()
	setMainButtonsInteractive(false)
	-- ซ่อน sub frames ก่อน
	hideAllSubFrames(epoch)
	-- แล้วค่อยซ่อน PlayMenu หลัก
	task.delay(0.1, function()
		if not isEpochCurrent(epoch) then
			return
		end
		bounceOut(_playMenu, 0, epoch, function()
			_gui.Enabled = false
			setActiveBtn(nil)
			if onHidden then
				onHidden()
			end
		end)
	end)
end

-- เปิด InvitePromptFrame จากที่อื่น (optional)
function PlayMenuScreen.showInvitePrompt()
	switchSubFrame(_invitePromptFrame, nextEpoch())
end

function PlayMenuScreen.setPartyCallbacks(
	onPartyPanelOpened: (() -> ())?,
	onInviteFriend: ((number) -> ())?,
	onPartyMemberAction: ((number, string) -> ())?,
	onPartyMatchmakingAction: ((string) -> ())?,
	onInvitePromptResponse: ((string, boolean) -> ())?
)
	_onPartyPanelOpened = onPartyPanelOpened
	_onInviteFriend = onInviteFriend
	_onPartyMemberAction = onPartyMemberAction
	_onPartyMatchmakingAction = onPartyMatchmakingAction
	_onInvitePromptResponse = onInvitePromptResponse
end

function PlayMenuScreen.setServerCallbacks(
	onServerPanelOpened: (() -> ())?,
	onJoinServer: ((string) -> ())?
)
	_onServerPanelOpened = onServerPanelOpened
	_onJoinServer = onJoinServer
end

function PlayMenuScreen.showServerListLoading()
	if not _serverScroll or not _serverTemplate then
		return
	end

	disconnectConnections(_serverConnections)
	clearGeneratedEntries(_serverScroll)
	_serverTemplate.Visible = false
	setServerEmptyState(SERVER_LOADING_LABEL, true)
	updateLayoutForScroll(_serverScroll)
end

function PlayMenuScreen.renderServerList(servers: {any})
	if not _serverScroll or not _serverTemplate then
		return
	end

	disconnectConnections(_serverConnections)
	clearGeneratedEntries(_serverScroll)

	local hasServers = false
	for index, server in ipairs(servers) do
		if type(server) ~= "table" then
			continue
		end

		local jobId = tostring(server.jobId or "")
		if jobId == "" then
			continue
		end

		hasServers = true
		local entry = _serverTemplate:Clone()
		entry.Name = string.format("Server_%s", string.gsub(jobId, "[^%w_]", "_"))
		entry:SetAttribute("GeneratedByScript", true)
		entry.LayoutOrder = index
		applyMinimumEntryHeight(entry, SERVER_ENTRY_MIN_HEIGHT)
		entry.Visible = true
		entry.Parent = _serverScroll

		local mapLabel = findFirstDescendantByNames(entry, { "MapName", "ServerName", "Title" })
		local mapName = server.mapName
		if type(mapName) ~= "string" or mapName == "" then
			mapName = DEFAULT_SERVER_MAP_LABEL
		end
		setTextIfAny(mapLabel, mapName)

		local currentPlayers = math.max(0, tonumber(server.playerCount) or 0)
		local maxPlayers = math.max(currentPlayers, tonumber(server.maxPlayers) or 0)
		local playerCountLabel = findFirstDescendantByNames(entry, { "PlayerCount", "Players", "PlayerLabel" })
		if maxPlayers > 0 then
			setTextIfAny(playerCountLabel, string.format("%d/%d", currentPlayers, maxPlayers))
		else
			setTextIfAny(playerCountLabel, string.format("%d", currentPlayers))
		end

		local uptimeLabel = findFirstDescendantByNames(entry, { "TimeServer", "ServerTime", "Uptime", "TimeLabel" })
		setTextIfAny(uptimeLabel, string.format("UP %s", formatServerUptime(tonumber(server.startTime))))

		local previewUserIds = if type(server.previewUserIds) == "table" then server.previewUserIds else {}
		for previewIndex = 1, MAX_SERVER_PREVIEW_IMAGES do
			local previewTarget = findFirstDescendantByNames(entry, {
				string.format("FriendPic%d", previewIndex),
				string.format("PlayerPic%d", previewIndex),
				string.format("Avatar%d", previewIndex),
			})
			local previewUserId = tonumber(previewUserIds[previewIndex])
			local hasPreview = previewUserId ~= nil and previewUserId > 0
			setVisibleIfAny(previewTarget, hasPreview)
			if hasPreview and previewTarget then
				applyAvatarThumbnailToTarget(previewTarget, previewUserId :: number)
			elseif previewTarget and (previewTarget:IsA("ImageLabel") or previewTarget:IsA("ImageButton")) then
				previewTarget.Image = ""
			end
		end

		local joinBtn = findFirstDescendantByNames(entry, { "JoinBtn", "JoinButton" })
		local canJoin = canLocalPlayerJoinServer(server)
		if joinBtn and joinBtn:IsA("GuiButton") then
			local defaultBackgroundColor = joinBtn.BackgroundColor3
			applyJoinButtonVisualState(joinBtn, defaultBackgroundColor, canJoin)
			if canJoin and _onJoinServer then
				table.insert(_serverConnections, joinBtn.MouseButton1Click:Connect(function()
					_onJoinServer(jobId)
				end))
			end
		end
	end

	_serverTemplate.Visible = false
	setServerEmptyState(if hasServers then "" else SERVER_EMPTY_LABEL, not hasServers)
	updateLayoutForScroll(_serverScroll)
end

function PlayMenuScreen.renderOnlineFriends(friends: {any})
	if not _onlineScroll or not _onlineFriendTemplate then
		return
	end

	disconnectConnections(_onlineConnections)
	clearGeneratedEntries(_onlineScroll)

	for _, friend in ipairs(friends) do
		local entry = _onlineFriendTemplate:Clone()
		entry.Name = string.format("Friend_%d", friend.userId)
		entry:SetAttribute("GeneratedByScript", true)
		applyMinimumEntryHeight(entry, ONLINE_ENTRY_MIN_HEIGHT)
		entry.Visible = true
		entry.Parent = _onlineScroll

		local nameLabel = findFirstDescendantByNames(entry, { "FriendName", "PlayerName", "NameLabel" })
		setTextIfAny(nameLabel, tostring(friend.name or friend.userId))
		applyAvatarThumbnail(entry, friend.userId)

		local statusLabel = findFirstDescendantByNames(entry, { "StatusText", "StatusLabel" })
		local statusText = STATUS_LABELS[friend.status] or tostring(friend.status or "Unknown")
		setTextIfAny(statusLabel, statusText)

		local inviteBtn = findFirstDescendantByNames(entry, { "InviteBtn", "InviteButton" })
		if inviteBtn and inviteBtn:IsA("GuiButton") then
			inviteBtn.Visible = friend.canInvite == true
			inviteBtn.Active = friend.canInvite == true
			if friend.canInvite then
				table.insert(_onlineConnections, inviteBtn.MouseButton1Click:Connect(function()
					if _onInviteFriend then
						_onInviteFriend(friend.userId)
					end
				end))
			end
		end
	end

	updateLayoutForScroll(_onlineScroll)
end

function PlayMenuScreen.renderPartyMembers(partySnapshot: any, localUserId: number)
	if not _partyScroll or not _partyMemberTemplate then
		return
	end

	disconnectConnections(_partyMemberConnections)
	_partyLeaveUserId = nil
	_isLocalPartyLeader = false
	_isInParty = false
	_partyMemberCount = 1
	clearGeneratedEntries(_partyScroll)

	if not partySnapshot or type(partySnapshot.members) ~= "table" then
		_isPartyQueueing = false
		_isPartyTeleporting = false
		_partyQueueSecondsLeft = 0
		if _partyLeaveBtn then
			_partyLeaveBtn.Visible = false
			_partyLeaveBtn.Active = false
		end
		if _partyMatchmakingBtn then
			_partyMatchmakingBtn.Visible = false
			_partyMatchmakingBtn.Active = false
		end
		setMainButtonsInteractive(_isInteractive)
		updateLayoutForScroll(_partyScroll)
		return
	end

	local partyMembers = partySnapshot.members
	_partyMemberCount = math.max(1, #partyMembers)
	local isLeader = partySnapshot.leaderUserId == localUserId
	for _, member in ipairs(partyMembers) do
		if member.userId == localUserId then
			_isInParty = true
			break
		end
	end
	_partyLeaveUserId = localUserId
	_isLocalPartyLeader = isLeader
	setMainButtonsInteractive(_isInteractive)

	if _partyLeaveBtn then
		_partyLeaveBtn.Visible = true
		_partyLeaveBtn.Active = true
		if isLeader then
			setTextIfAny(_partyLeaveBtn, "DISBAND THE PARTY")
		else
			setTextIfAny(_partyLeaveBtn, "LEAVE PARTY")
		end
	end

	if _partyMatchmakingBtn then
		refreshPartyMatchmakingButton()
	end

	for _, member in ipairs(partyMembers) do
		local entry = _partyMemberTemplate:Clone()
		entry.Name = string.format("Party_%d", member.userId)
		entry:SetAttribute("GeneratedByScript", true)
		applyMinimumEntryHeight(entry, PARTY_ENTRY_MIN_HEIGHT)
		entry.Visible = true
		entry.Parent = _partyScroll

		local nameLabel = findFirstDescendantByNames(entry, { "PlayerName", "FriendName", "NameLabel" })
		setTextIfAny(nameLabel, tostring(member.name or member.userId))
		applyAvatarThumbnail(entry, member.userId)

		local leaderMark = findFirstDescendantByNames(entry, { "LeaderStar", "LeaderIcon" })
		setVisibleIfAny(leaderMark, member.userId == partySnapshot.leaderUserId)

		local kickOrLeaveBtn = findFirstDescendantByNames(entry, { "KickFriend", "KickBtn", "ActionBtn" })
		if kickOrLeaveBtn and kickOrLeaveBtn:IsA("GuiButton") then
			if isLeader and member.userId ~= localUserId then
				setTextIfAny(kickOrLeaveBtn, "KICK")
				kickOrLeaveBtn.Visible = true
				table.insert(_partyMemberConnections, kickOrLeaveBtn.MouseButton1Click:Connect(function()
					if _onPartyMemberAction then
						_onPartyMemberAction(member.userId, "kick")
					end
				end))
			else
				kickOrLeaveBtn.Visible = false
			end
		end
	end

	updateLayoutForScroll(_partyScroll)
end

function PlayMenuScreen.updatePartyQueueStatus(status: string, secondsLeft: number?)
	if status == "started" or status == "tick" then
		_isPartyQueueing = true
		_isPartyTeleporting = false
		_partyQueueSecondsLeft = math.max(0, secondsLeft or 0)
	elseif status == "teleporting" then
		_isPartyQueueing = false
		_isPartyTeleporting = true
		_partyQueueSecondsLeft = 0
	elseif status == "cancelled" or status == "failed" then
		_isPartyQueueing = false
		_isPartyTeleporting = false
		_partyQueueSecondsLeft = 0
	end

	refreshPartyMatchmakingButton()
end

function PlayMenuScreen.showIncomingInvitePrompt(inviteData: any)
	_currentInviteId = inviteData and inviteData.inviteId or nil

	if not _gui.Enabled then
		_isStandalonePromptMode = true
		_gui.Enabled = true
		_playMenu.Visible = false
		_serverListFrame.Visible = false
		_partyFrame.Visible = false
	end

	local promptLabel = findFirstDescendantByNames(_invitePromptFrame, { "PromptText", "InviteText", "TextLabel", "Title" })
	if promptLabel then
		local fromName = inviteData and inviteData.fromName or "Unknown"
		setTextIfAny(promptLabel, string.format("%s invited you to party", fromName))
	end

	local fromUserId = inviteData and inviteData.fromUserId or nil
	if type(fromUserId) == "number" and fromUserId > 0 then
		applyAvatarThumbnail(_invitePromptFrame, fromUserId)
	end

	switchSubFrame(_invitePromptFrame, nextEpoch())
end

function PlayMenuScreen.hideIncomingInvitePrompt()
	_currentInviteId = nil
	if _activeSubFrame == _invitePromptFrame then
		closeSubPage(false)
		if _isStandalonePromptMode then
			task.delay(0.5, function()
				if _activeSubFrame == nil and _gui.Enabled and not _playMenu.Visible and not _partyFrame.Visible and not _serverListFrame.Visible then
					_gui.Enabled = false
				end
			end)
			_isStandalonePromptMode = false
		end
	else
		_invitePromptFrame.Visible = false
		if _isStandalonePromptMode then
			_gui.Enabled = false
			_isStandalonePromptMode = false
		end
	end
end

function PlayMenuScreen.showPartyPanel()
	setActiveBtn(_inviteBtn)
	openSubPage(_partyFrame)
end

return PlayMenuScreen
