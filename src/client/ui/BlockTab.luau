-- A block-editing tab: palette on the left, canvas on the right, plus Run and
-- View Lua. Reused for both the server "Blocks" tab and the client "Interface" tab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lua = require(ReplicatedStorage:WaitForChild("SkidSS").blocks.Lua)
local Theme = require(script.Parent.Parent.Theme)
local Palette = require(script.Parent.Palette)
local BlockCanvas = require(script.Parent.BlockCanvas)

local BlockTab = {}

function BlockTab.build(parent, ctx, opts)
	local program = {}

	local frame = Theme.create("Frame", {
		Name = opts.name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})

	local paletteFrame = Theme.create("ScrollingFrame", {
		Size = UDim2.new(0, 184, 1, -44),
		BackgroundColor3 = Theme.colors.panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = frame,
	}, { Theme.corner(8), Theme.padding(6) })

	local canvasFrame = Theme.create("ScrollingFrame", {
		Size = UDim2.new(1, -192, 1, -44),
		Position = UDim2.fromOffset(192, 0),
		BackgroundColor3 = Theme.colors.panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = frame,
	}, { Theme.corner(8), Theme.padding(8) })

	local canvas = BlockCanvas.new(canvasFrame, program, opts.allow)
	Palette.build(paletteFrame, opts.allow, function(defId)
		canvas.insert(defId)
	end)

	local run = Theme.create("TextButton", {
		Size = UDim2.fromOffset(140, 32),
		Position = UDim2.new(1, -140, 1, -34),
		BackgroundColor3 = Theme.colors.accent,
		Text = opts.runText or "Run",
		TextColor3 = Theme.colors.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		Parent = frame,
	}, { Theme.corner(8) })
	run.MouseButton1Click:Connect(function()
		opts.onRun(program)
	end)

	local view = Theme.create("TextButton", {
		Size = UDim2.fromOffset(110, 32),
		Position = UDim2.new(1, -260, 1, -34),
		BackgroundColor3 = Theme.colors.panelAlt,
		Text = "View Lua",
		TextColor3 = Theme.colors.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		Parent = frame,
	}, { Theme.corner(8) })
	view.MouseButton1Click:Connect(function()
		for line in string.gmatch(Lua.compile(program), "[^\n]+") do
			ctx.log(line)
		end
	end)

	return { frame = frame, program = program }
end

return BlockTab
