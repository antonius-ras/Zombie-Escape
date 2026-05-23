local TweenService = game:GetService("TweenService")

local UIAnimationUtils = {}

local _activeTweens = setmetatable({}, { __mode = "k" })

-- ตารางอ้างอิง Property ที่อนุญาตให้ทำ Tween ได้ตาม ClassName
local PROPERTY_WHITELIST = {
	GuiObject = {
		Position = true, Size = true, Rotation = true, Visible = true,
		BackgroundTransparency = true, BackgroundColor3 = true,
	},
	TextLabel = {
		TextTransparency = true, TextColor3 = true,
	},
	TextButton = {
		TextTransparency = true, TextColor3 = true,
	},
	ImageLabel = {
		ImageTransparency = true, ImageColor3 = true,
	},
	ImageButton = {
		ImageTransparency = true, ImageColor3 = true,
	},
	CanvasGroup = {
		GroupTransparency = true,
	}
}

-- ฟังก์ชันตรวจสอบว่า Object นี้รองรับ Property หรือไม่
local function isPropertyValid(obj: Instance, propName: string): boolean
	-- ตรวจสอบจาก Whitelist พื้นฐานก่อน
	for className, props in pairs(PROPERTY_WHITELIST) do
		if obj:IsA(className) and props[propName] then
			return true
		end
	end
	return false
end

function UIAnimationUtils.safeTween(obj: Instance, info: TweenInfo, goals: {[string]: any}): Tween?
	local g = {}
	
	for k, v in pairs(goals) do
		-- ตรวจสอบ Property ว่ารองรับหรือไม่
		if isPropertyValid(obj, k) then
			g[k] = v
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
