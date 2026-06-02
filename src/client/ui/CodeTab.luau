local Theme = require(script.Parent.Parent.Theme)

local CodeTab = {}

local SAMPLE = 'print("hello from the server")\n\nfor _, p in game:GetService("Players"):GetPlayers() do\n\tprint(p.Name)\nend'

function CodeTab.build(parent, ctx)
	local frame = Theme.create("Frame", {
		Name = "CodeTab",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})

	local holder = Theme.create("Frame", {
		Size = UDim2.new(1, 0, 1, -44),
		BackgroundColor3 = Theme.colors.panel,
		BorderSizePixel = 0,
		Parent = frame,
	}, { Theme.corner(8), Theme.padding(8) })

	local box = Theme.create("TextBox", {
		Name = "Source",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextColor3 = Theme.colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Code,
		TextSize = 15,
		MultiLine = true,
		ClearTextOnFocus = false,
		TextWrapped = false,
		Text = SAMPLE,
		Parent = holder,
	})

	local run = Theme.create("TextButton", {
		Size = UDim2.fromOffset(140, 32),
		Position = UDim2.new(1, -140, 1, -34),
		BackgroundColor3 = Theme.colors.accent,
		Text = "Run on server",
		TextColor3 = Theme.colors.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		Parent = frame,
	}, { Theme.corner(8) })

	run.MouseButton1Click:Connect(function()
		ctx.log("> running lua\u{2026}")
		ctx.execute({ mode = "lua", source = box.Text })
	end)

	return { frame = frame }
end

return CodeTab
