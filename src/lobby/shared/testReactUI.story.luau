local Story = {}

local replicatedStorage = script:FindFirstAncestorOfClass("ReplicatedStorage")

local packages = replicatedStorage:WaitForChild("Packages")
local react = require(packages:WaitForChild("react") :: ModuleScript)

Story.react = react
Story.reactRoblox = require(packages:WaitForChild("react-roblox") :: ModuleScript)

local e = react.createElement

function Story.story()
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		HelloLabel = e("TextLabel", {
			Text = "Hello, world!",
			Size = UDim2.fromScale(1, 0.1),
			Position = UDim2.fromScale(0, 0.45),
			TextColor3 = Color3.new(1, 1, 1),
			TextScaled = true,
			BackgroundTransparency = 1,
		}),
	})
end

return Story
