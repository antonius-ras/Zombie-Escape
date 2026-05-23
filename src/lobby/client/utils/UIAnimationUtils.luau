local TweenService = game:GetService("TweenService")

local UIAnimationUtils = {}

local _activeTweens: {[Instance]: Tween} = {}

function UIAnimationUtils.safeTween(obj: Instance, info: TweenInfo, goals: {[string]: any}): Tween?
	local g = {}
	
	for k, v in pairs(goals) do
		-- ตรวจสอบว่า Property นี้มีอยู่ใน Object หรือไม่โดยไม่ทำให้เกิด Error
		local success = pcall(function()
			local _ = (obj :: any)[k]
		end)
		
		if success then
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
