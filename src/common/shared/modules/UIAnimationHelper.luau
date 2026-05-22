--!strict
-- ============================================================
-- UIAnimationHelper.luau | ModuleScript
-- วางไว้ใน: src/common/shared/modules/ (สร้างถ้ายังไม่มี)
-- หน้าที่: ตัวช่วยจัดการอนิเมชั่น UI ให้ลื่นไหลและเป็นมาตรฐาน
-- ============================================================

local TweenService = game:GetService("TweenService")

local UIAnimationHelper = {}

-- ── Configuration ──────────────────────────────────────────
local BOUNCE_INFO = TweenInfo.new(0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CINEMATIC_INFO = TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local FAST_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ── Private State ──────────────────────────────────────────
local activeTweens: {[Instance]: {[string]: Tween}} = {}

-- ── Private Utils ──────────────────────────────────────────
local function cancelExistingTween(instance: Instance, property: string)
	if activeTweens[instance] and activeTweens[instance][property] then
		activeTweens[instance][property]:Cancel()
		activeTweens[instance][property] = nil
	end
end

-- ── Public API ─────────────────────────────────────────────

-- Tween แบบพื้นฐานที่ช่วยจัดการ Cleanup ให้อัตโนมัติ และเช็ค Property ให้ก่อน
function UIAnimationHelper.tween(instance: Instance, info: TweenInfo, goals: {[string]: any})
	local safeGoals = {}
	for property, value in pairs(goals) do
		local success = pcall(function()
			return (instance :: any)[property]
		end)
		
		if success then
			cancelExistingTween(instance, property)
			safeGoals[property] = value
		end
	end

	if not next(safeGoals) then return nil end
	local tween = TweenService:Create(instance, info, safeGoals)
	
	if not activeTweens[instance] then activeTweens[instance] = {} end
	for property, _ in pairs(safeGoals) do activeTweens[instance][property] = tween end

	tween.Completed:Connect(function()
		if activeTweens[instance] then
			for property, t in pairs(activeTweens[instance]) do
				if t == tween then activeTweens[instance][property] = nil end
			end
			if not next(activeTweens[instance]) then activeTweens[instance] = nil end
		end
	end)

	tween:Play()
	return tween
end

-- อนิเมชั่นเลื่อนเข้าจากนอกจอ (Cinematic Slide In)
function UIAnimationHelper.slideIn(obj: GuiObject, direction: "Left" | "Right" | "Top" | "Bottom", delayTime: number?)
	local originalPos = obj:GetAttribute("OriginalPosition") or obj.Position
	if not obj:GetAttribute("OriginalPosition") then
		obj:SetAttribute("OriginalPosition", originalPos)
	end

	local offscreenPos: UDim2
	if direction == "Left" then offscreenPos = UDim2.fromScale(-1.2, originalPos.Y.Scale)
	elseif direction == "Right" then offscreenPos = UDim2.fromScale(1.2, originalPos.Y.Scale)
	elseif direction == "Top" then offscreenPos = UDim2.fromScale(originalPos.X.Scale, -1.2)
	else offscreenPos = UDim2.fromScale(originalPos.X.Scale, 1.2) end

	obj.Position = offscreenPos
	obj.Visible = true
	
	task.delay(delayTime or 0, function()
		UIAnimationHelper.tween(obj, CINEMATIC_INFO, {
			Position = originalPos,
			GroupTransparency = 0,
		})
	end)
end

-- อนิเมชั่นเลื่อนออก (Cinematic Slide Out)
function UIAnimationHelper.slideOut(obj: GuiObject, direction: "Left" | "Right" | "Top" | "Bottom", callback: (() -> ())?)
	local originalPos = obj:GetAttribute("OriginalPosition") or obj.Position
	local offscreenPos: UDim2
	if direction == "Left" then offscreenPos = UDim2.fromScale(-1.2, originalPos.Y.Scale)
	elseif direction == "Right" then offscreenPos = UDim2.fromScale(1.2, originalPos.Y.Scale)
	elseif direction == "Top" then offscreenPos = UDim2.fromScale(originalPos.X.Scale, -1.2)
	else offscreenPos = UDim2.fromScale(originalPos.X.Scale, 1.2) end

	local tween = UIAnimationHelper.tween(obj, CINEMATIC_INFO, {
		Position = offscreenPos,
		GroupTransparency = 1,
	})

	if callback then
		tween.Completed:Connect(function()
			obj.Visible = false
			obj.Position = originalPos
			callback()
		end)
	end
end

-- อนิเมชั่นเด้งเข้า (Bounce In)
function UIAnimationHelper.bounceIn(obj: GuiObject, startPosOffset: UDim2?)
	local originalPos = obj:GetAttribute("OriginalPosition") or obj.Position
	if not obj:GetAttribute("OriginalPosition") then
		obj:SetAttribute("OriginalPosition", originalPos)
	end

	local offset = startPosOffset or UDim2.fromScale(0, 0.1)
	obj.Position = (originalPos :: UDim2) + offset
	obj.Visible = true
	
	UIAnimationHelper.tween(obj, BOUNCE_INFO, {
		Position = originalPos,
	})
end

-- อนิเมชั่นเด้งออก (Bounce Out)
function UIAnimationHelper.bounceOut(obj: GuiObject, endPosOffset: UDim2?, callback: (() -> ())?)
	local originalPos = obj:GetAttribute("OriginalPosition") or obj.Position
	local offset = endPosOffset or UDim2.fromScale(0, 0.1)
	
	local tween = UIAnimationHelper.tween(obj, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Position = (originalPos :: UDim2) + offset,
	})

	if callback then
		tween.Completed:Connect(function()
			obj.Visible = false
			obj.Position = originalPos :: UDim2
			callback()
		end)
	end
end

-- Hover Effect แบบนุ่มนวล (Spring-like)
function UIAnimationHelper.applyHover(btn: GuiButton, scaleMultiplier: number?)
	local mult = scaleMultiplier or 1.05
	local originalSize = btn.Size
	
	btn.MouseEnter:Connect(function()
		UIAnimationHelper.tween(btn, TweenInfo.new(0.3, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, 0, false, 0.1), {
			Size = UDim2.new(originalSize.X.Scale * mult, originalSize.X.Offset * mult, originalSize.Y.Scale * mult, originalSize.Y.Offset * mult)
		})
	end)

	btn.MouseLeave:Connect(function()
		UIAnimationHelper.tween(btn, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = originalSize
		})
	end)
end

return UIAnimationHelper
