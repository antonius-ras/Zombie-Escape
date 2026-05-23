local TweenService = game:GetService("TweenService")

local UIAnimationUtils = {}

local _activeTweens: {[Instance]: Tween} = {}

function UIAnimationUtils.safeTween(obj: Instance, info: TweenInfo, goals: {[string]: any}): Tween?
	local g = {}
	for k, v in pairs(goals) do
		if pcall(function() return (obj :: any)[k] end) then g[k] = v end
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
