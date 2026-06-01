-- UI construction helpers plus the live, mutable colour table the Interface
-- blocks recolour at runtime.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("SkidSS"):WaitForChild("Config"))

local Theme = {}

Theme.colors = {
	accent = Config.UI.Accent,
	background = Config.UI.Background,
	panel = Config.UI.Panel,
	panelAlt = Config.UI.PanelAlt,
	text = Config.UI.Text,
	subText = Config.UI.SubText,
	good = Config.UI.Good,
	bad = Config.UI.Bad,
}

function Theme.create(className, props, children)
	local instance = Instance.new(className)
	if props then
		for key, value in props do
			if key ~= "Parent" then
				instance[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props and props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function Theme.corner(radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 6)
	return corner
end

function Theme.padding(amount)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, amount)
	pad.PaddingRight = UDim.new(0, amount)
	pad.PaddingTop = UDim.new(0, amount)
	pad.PaddingBottom = UDim.new(0, amount)
	return pad
end

function Theme.listLayout(padding, direction)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding or 4)
	return layout
end

return Theme
