-- The block picker. Lists every statement block allowed on this side, grouped by
-- category; clicking one asks the canvas to insert it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Defs = require(ReplicatedStorage:WaitForChild("SkidSS").blocks.Defs)
local Theme = require(script.Parent.Parent.Theme)

local Palette = {}

local function preview(label)
	return (string.gsub(label or "", "%%(%S+)", "[%1]"))
end

function Palette.build(parent, allow, onPick)
	Theme.listLayout(4).Parent = parent
	local order = 0

	for _, category in Defs.categoryOrder do
		local defs = {}
		for _, def in Defs.categories[category] do
			if def.kind == "statement" and not def.hidden and allow[def.side] then
				table.insert(defs, def)
			end
		end

		if #defs > 0 then
			order += 1
			Theme.create("TextLabel", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text = category,
				TextColor3 = Theme.colors.subText,
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = order,
				Parent = parent,
			})

			for _, def in defs do
				order += 1
				local button = Theme.create("TextButton", {
					Size = UDim2.new(1, 0, 0, 26),
					BackgroundColor3 = Theme.colors.panelAlt,
					Text = " " .. preview(def.label),
					TextColor3 = Theme.colors.text,
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					LayoutOrder = order,
					Parent = parent,
				}, { Theme.corner(4) })
				button.MouseButton1Click:Connect(function()
					onPick(def.id)
				end)
			end
		end
	end
end

return Palette
