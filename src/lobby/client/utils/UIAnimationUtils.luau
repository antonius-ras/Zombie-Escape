local TweenService = game:GetService("TweenService")

local UIAnimationUtils = {}

local _activeTweens: {[Instance]: Tween} = {}

-- รายการ Property พื้นฐานที่มักใช้ทำ Tween
local VALID_PROPERTIES = {
	Position = true,
	Size = true,
	Transparency = true,
	ImageTransparency = true,
	TextTransparency = true,
	BackgroundTransparency = true,
	Rotation = true,
	Visible = true,
}

function UIAnimationUtils.safeTween(obj: Instance, info: TweenInfo, goals: {[string]: any}): Tween?
	local g = {}
	
	-- ตรวจสอบอย่างรวดเร็วว่าเป็น GuiObject หรือไม่
	if obj:IsA("GuiObject") then
		for k, v in pairs(goals) do
			-- ตรวจสอบแค่ชื่อ Property ที่อนุญาต
			if VALID_PROPERTIES[k] then
				g[k] = v
			end
		end
	else
		-- กรณีเป็น Instance อื่น ให้ใช้การตรวจสอบที่ยืดหยุ่นกว่า
		for k, v in pairs(goals) do
			if (obj :: any)[k] ~= nil then
				g[k] = v
			end
		end
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
	
	return nil
end

return UIAnimationUtils
