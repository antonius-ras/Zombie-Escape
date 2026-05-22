local TweenService = game:GetService("TweenService")

local UIAnimationHelper = {}

local DEFAULT_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function playTween(instance: Instance, tweenInfo: TweenInfo, properties, onComplete)
	local tween = TweenService:Create(instance, tweenInfo, properties)
	if onComplete then
		tween.Completed:Connect(onComplete)
	end
	tween:Play()
	return tween
end

function UIAnimationHelper.tween(instance: Instance, tweenInfo: TweenInfo, properties)
	return playTween(instance, tweenInfo, properties)
end

function UIAnimationHelper.applyHover(button: GuiObject)
	if not button:IsA("GuiButton") then
		return
	end

	local baseSize = button.Size
	local hoverSize = UDim2.new(baseSize.X.Scale * 1.04, baseSize.X.Offset, baseSize.Y.Scale * 1.04, baseSize.Y.Offset)

	button.MouseEnter:Connect(function()
		playTween(button, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = hoverSize,
		})
	end)

	button.MouseLeave:Connect(function()
		playTween(button, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = baseSize,
		})
	end)
end

function UIAnimationHelper.slideIn(obj: GuiObject, direction: string, delayTime: number?)
	local basePos = obj.Position
	local offset = UDim2.new(0, 0, 0, 0)

	if direction == "Left" then
		offset = UDim2.fromOffset(-140, 0)
	elseif direction == "Right" then
		offset = UDim2.fromOffset(140, 0)
	elseif direction == "Top" then
		offset = UDim2.fromOffset(0, -120)
	elseif direction == "Bottom" then
		offset = UDim2.fromOffset(0, 120)
	end

	obj.Visible = true
	obj.Position = basePos + offset
	obj.BackgroundTransparency = 1

	task.delay(delayTime or 0, function()
		playTween(obj, DEFAULT_TWEEN, {
			Position = basePos,
			BackgroundTransparency = 0.8,
		})
	end)
end

function UIAnimationHelper.slideOut(obj: GuiObject, direction: string, onDone: (() -> ())?)
	local targetPos = obj.Position

	if direction == "Left" then
		targetPos += UDim2.fromOffset(-140, 0)
	elseif direction == "Right" then
		targetPos += UDim2.fromOffset(140, 0)
	elseif direction == "Top" then
		targetPos += UDim2.fromOffset(0, -120)
	elseif direction == "Bottom" then
		targetPos += UDim2.fromOffset(0, 120)
	end

	playTween(obj, DEFAULT_TWEEN, {
		Position = targetPos,
		BackgroundTransparency = 1,
	}, onDone)
end

function UIAnimationHelper.bounceIn(obj: GuiObject)
	obj.Visible = true
	obj.AnchorPoint = Vector2.new(0.5, 0.5)
	obj.Size = UDim2.fromScale(0, 0)
	playTween(obj, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(0.32, 0.12),
	})
end

function UIAnimationHelper.bounceOut(obj: GuiObject, targetSize: UDim2?, onDone: (() -> ())?)
	playTween(obj, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = targetSize or UDim2.fromScale(0, 0),
	}, onDone)
end

return UIAnimationHelper
