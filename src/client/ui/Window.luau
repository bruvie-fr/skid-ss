-- The executor window: title bar, tabs (Code / Blocks / Interface), output console
-- and quick-button bar. Window.mount(cfg) applies a config table (from Studio's
-- CustomInterface) before building, so colours / title / tabs / buttons are baked
-- in. Also exposes the api the in-game Interface tab uses to restyle it live.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SkidSS")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Interpreter = require(Shared.blocks.Interpreter)

local Theme = require(script.Parent.Parent.Theme)
local CodeTab = require(script.Parent.CodeTab)
local BlockTab = require(script.Parent.BlockTab)

local Window = {}

local function normalizeAsset(value)
	value = tostring(value or "")
	if value == "" then return "" end
	if string.match(value, "^%d+$") then return "rbxassetid://" .. value end
	return value
end

-- Builds one designer element (panel / label / button / image / codebox) from a
-- spec. Positions and sizes are scales (0..1) so the layout is screen-responsive.
-- env = { codeBoxes = {}, fireAction = fn(name), runCode = fn(source) }.
local function buildElement(el, parent, env)
	local class = el.type == "image" and "ImageLabel"
		or el.type == "button" and "TextButton"
		or el.type == "label" and "TextLabel"
		or el.type == "codebox" and "TextBox"
		or el.type == "output" and "ScrollingFrame"
		or "Frame"

	local inst = Instance.new(class)
	inst.Position = UDim2.fromScale(tonumber(el.x) or 0, tonumber(el.y) or 0)
	inst.Size = UDim2.fromScale(tonumber(el.w) or 0.1, tonumber(el.h) or 0.1)
	inst.BorderSizePixel = 0
	inst.BackgroundColor3 = typeof(el.bg) == "Color3" and el.bg or Color3.fromRGB(28, 28, 36)
	inst.BackgroundTransparency = tonumber(el.bgTransparency) or (class == "ImageLabel" and 1 or 0)

	if tonumber(el.corner) and tonumber(el.corner) > 0 then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, tonumber(el.corner))
		corner.Parent = inst
	end

	if tonumber(el.borderThickness) and tonumber(el.borderThickness) > 0 then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = tonumber(el.borderThickness)
		stroke.Color = typeof(el.borderColor) == "Color3" and el.borderColor or Color3.fromRGB(255, 255, 255)
		stroke.Parent = inst
	end

	if class == "ImageLabel" then
		inst.Image = normalizeAsset(el.image)
		if typeof(el.imageColor) == "Color3" then inst.ImageColor3 = el.imageColor end
	end

	if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
		inst.Text = tostring(el.text or "")
		inst.TextColor3 = typeof(el.textColor) == "Color3" and el.textColor or Color3.fromRGB(255, 255, 255)
		inst.TextSize = tonumber(el.textSize) or 16
		inst.Font = class == "TextBox" and Enum.Font.Code or Enum.Font.GothamMedium
	end

	if class == "TextBox" then
		inst.ClearTextOnFocus = false
		inst.MultiLine = true
		inst.TextWrapped = true
		inst.TextXAlignment = Enum.TextXAlignment.Left
		inst.TextYAlignment = Enum.TextYAlignment.Top
		if env and env.codeBoxes then
			env.codeBoxes[el.name or "main"] = inst
		end
	end

	if class == "ScrollingFrame" then
		inst.ScrollBarThickness = 4
		inst.CanvasSize = UDim2.new()
		inst.AutomaticCanvasSize = Enum.AutomaticSize.Y
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 2)
		layout.Parent = inst
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingRight = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.Parent = inst
		local outColor = typeof(el.textColor) == "Color3" and el.textColor or Color3.fromRGB(212, 212, 226)
		local outSize = tonumber(el.textSize) or 13
		local order = 0
		local function append(line)
			order += 1
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, 0, 0, 0)
			lbl.AutomaticSize = Enum.AutomaticSize.Y
			lbl.BackgroundTransparency = 1
			lbl.Text = tostring(line)
			lbl.TextColor3 = outColor
			lbl.Font = Enum.Font.Code
			lbl.TextSize = outSize
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextWrapped = true
			lbl.LayoutOrder = order
			lbl.Parent = inst
			task.defer(function()
				inst.CanvasPosition = Vector2.new(0, inst.AbsoluteCanvasSize.Y)
			end)
		end
		if env and env.outputs then
			table.insert(env.outputs, append)
		end
	end

	if class == "TextButton" then
		inst.AutoButtonColor = true
		if el.action and env and env.fireAction then
			inst.MouseButton1Click:Connect(function() env.fireAction(el.action) end)
		elseif el.execute and env then
			inst.MouseButton1Click:Connect(function()
				local box = env.codeBoxes and env.codeBoxes[el.execute]
				if box then env.runCode(box.Text) end
			end)
		end
	end

	-- A draggable element moves the whole HUD group (e.g. a background panel
	-- acting as a window you drag by its margins).
	if el.draggable then
		inst.Active = true
		local dragging, dragStart, startPositions
		inst.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPositions = {}
				if env and env.elementInsts then
					for _, other in env.elementInsts do
						startPositions[other] = other.Position
					end
				end
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				local cam = workspace.CurrentCamera
				local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
				local dx, dy = delta.X / vp.X, delta.Y / vp.Y
				for other, startPos in startPositions do
					other.Position = UDim2.new(startPos.X.Scale + dx, startPos.X.Offset, startPos.Y.Scale + dy, startPos.Y.Offset)
				end
			end
		end)
	end

	inst.Parent = parent
	return inst
end

function Window.mount(cfg)
	cfg = cfg or {}

	-- Apply the theme overrides into the shared colour table before anything is
	-- built, so every instance (including the tabs) picks them up.
	if typeof(cfg.accent) == "Color3" then Theme.colors.accent = cfg.accent end
	if typeof(cfg.background) == "Color3" then Theme.colors.background = cfg.background end
	if typeof(cfg.panel) == "Color3" then Theme.colors.panel = cfg.panel end
	if typeof(cfg.panelAlt) == "Color3" then Theme.colors.panelAlt = cfg.panelAlt end
	if typeof(cfg.text) == "Color3" then Theme.colors.text = cfg.text end

	local toggleKey = Config.UI.ToggleKey
	if type(cfg.toggleKey) == "string" then
		local ok, key = pcall(function() return Enum.KeyCode[cfg.toggleKey] end)
		if ok and key then toggleKey = key end
	end

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	-- De-dupe: never build a second copy of the UI.
	if playerGui:FindFirstChild("SkidSS") then return end

	local executeRemote = Net.get(Net.Execute)
	local outputRemote = Net.get(Net.Output)

	local gui = Instance.new("ScreenGui")
	gui.Name = "SkidSS"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local winW = math.max(420, tonumber(cfg.width) or 760)
	local winH = math.max(300, tonumber(cfg.height) or 480)
	-- The built-in executor window is hidden on join by default (toggle key opens
	-- it), so a custom HUD isn't competing with a second window on screen.
	local openOnJoin = cfg.openOnJoin == true
	local root = Theme.create("Frame", {
		Size = UDim2.fromOffset(winW, winH),
		Position = UDim2.new(0.5, -winW / 2, 0.5, -winH / 2),
		AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = Theme.colors.background,
		BorderSizePixel = 0,
		Active = true,
		Visible = openOnJoin,
		Parent = gui,
	}, { Theme.corner(10) })

	-- Header / drag bar
	local headerBar = Theme.create("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.colors.panel,
		BorderSizePixel = 0,
		Active = true,
		Parent = root,
	}, { Theme.corner(10) })

	local accentStrip = Theme.create("Frame", {
		Size = UDim2.new(1, 0, 0, 3),
		Position = UDim2.new(0, 0, 1, -3),
		BackgroundColor3 = Theme.colors.accent,
		BorderSizePixel = 0,
		Parent = headerBar,
	})

	local title = Theme.create("TextLabel", {
		Size = UDim2.new(1, -120, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		BackgroundTransparency = 1,
		Text = type(cfg.title) == "string" and cfg.title or "SkidSS",
		TextColor3 = Theme.colors.text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = headerBar,
	})

	Theme.create("TextLabel", {
		Size = UDim2.fromOffset(60, 40),
		Position = UDim2.new(1, -100, 0, 0),
		BackgroundTransparency = 1,
		Text = "v" .. Config.Version,
		TextColor3 = Theme.colors.subText,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = headerBar,
	})

	local hide = Theme.create("TextButton", {
		Size = UDim2.fromOffset(30, 24),
		Position = UDim2.new(1, -36, 0, 8),
		BackgroundColor3 = Theme.colors.panelAlt,
		Text = "\u{2013}",
		TextColor3 = Theme.colors.text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Parent = headerBar,
	}, { Theme.corner(6) })

	-- Content + bottom regions
	local content = Theme.create("Frame", {
		Position = UDim2.fromOffset(12, 84),
		Size = UDim2.new(1, -24, 1, -252),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = root,
	})

	local console = Theme.create("ScrollingFrame", {
		Position = UDim2.new(0, 12, 1, -160),
		Size = UDim2.new(1, -24, 0, 110),
		BackgroundColor3 = Theme.colors.panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = root,
	}, { Theme.corner(8), Theme.padding(8) })
	local consoleLayout = Theme.listLayout(2)
	consoleLayout.Parent = console

	local quickBar = Theme.create("Frame", {
		Position = UDim2.new(0, 12, 1, -42),
		Size = UDim2.new(1, -24, 0, 30),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local quickRow = Theme.listLayout(6, Enum.FillDirection.Horizontal)
	quickRow.Parent = quickBar

	-- UI api used by the live console and by Interface blocks ------------------
	local lineOrder = 0
	local quickButtons = {}
	local hudOutputs = {} -- append functions for any Output elements on the HUD
	local api = {}

	function api.log(text)
		for _, append in hudOutputs do
			append(tostring(text))
		end
		lineOrder += 1
		local label = Theme.create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = tostring(text),
			TextColor3 = Theme.colors.text,
			Font = Enum.Font.Code,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			LayoutOrder = lineOrder,
			Parent = console,
		})
		task.defer(function()
			console.CanvasPosition = Vector2.new(0, console.AbsoluteCanvasSize.Y)
		end)
		return label
	end

	function api.setTitle(text)
		title.Text = text
	end

	function api.setAccent(color)
		Theme.colors.accent = color
		accentStrip.BackgroundColor3 = color
		for _, button in quickButtons do
			button.BackgroundColor3 = color
		end
	end

	function api.setBackground(color)
		Theme.colors.background = color
		root.BackgroundColor3 = color
	end

	function api.notify(text)
		local toast = Theme.create("TextLabel", {
			Size = UDim2.fromOffset(260, 34),
			Position = UDim2.new(0.5, -130, 0, 50),
			BackgroundColor3 = Theme.colors.panelAlt,
			Text = tostring(text),
			TextColor3 = Theme.colors.text,
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			Parent = gui,
		}, { Theme.corner(8) })
		task.delay(2.5, function()
			toast:Destroy()
		end)
	end

	-- ctx shared with the tabs
	local state = { serverProgram = nil }
	local ctx = {
		log = api.log,
		execute = function(payload)
			executeRemote:FireServer(payload)
		end,
		state = state,
		window = api,
	}

	-- addButton(label[, onClick]). Without onClick it re-runs the saved block
	-- program; with one it does whatever the caller wants (e.g. fire an action).
	function api.addButton(label, onClick)
		local button = Theme.create("TextButton", {
			Size = UDim2.fromOffset(110, 30),
			BackgroundColor3 = Theme.colors.accent,
			Text = label,
			TextColor3 = Theme.colors.text,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			Parent = quickBar,
		}, { Theme.corner(6) })
		table.insert(quickButtons, button)
		button.MouseButton1Click:Connect(function()
			if onClick then
				onClick()
			elseif state.serverProgram then
				ctx.execute({ mode = "blocks", program = state.serverProgram })
				api.log("> running blocks\u{2026}")
			end
		end)
	end

	-- The executor has a single Code tab.
	local code = CodeTab.build(content, ctx)
	code.frame.Visible = true

	-- Buttons baked in by Studio fire named runtime actions.
	if type(cfg.buttons) == "table" then
		for _, button in cfg.buttons do
			if type(button) == "table" and type(button.label) == "string" then
				local action = button.action
				local args = button.args
				if action then
					api.addButton(button.label, function()
						ctx.execute({ mode = "action", name = action, args = args })
						api.log("> " .. button.label)
					end)
				else
					api.addButton(button.label)
				end
			end
		end
	end

	local tabBar = Theme.create("Frame", {
		Position = UDim2.fromOffset(12, 48),
		Size = UDim2.new(1, -24, 0, 30),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local tabRow = Theme.listLayout(6, Enum.FillDirection.Horizontal)
	tabRow.Parent = tabBar

	Theme.create("TextButton", {
		Size = UDim2.fromOffset(110, 30),
		BackgroundColor3 = Theme.colors.accent,
		Text = "Code",
		TextColor3 = Theme.colors.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		Parent = tabBar,
	}, { Theme.corner(6) })

	-- Custom designer elements (always-visible HUD, sibling to the window)
	if type(cfg.elements) == "table" then
		local elementInsts = {}
		local env = {
			codeBoxes = {},
			outputs = hudOutputs,
			elementInsts = elementInsts,
			fireAction = function(action)
				ctx.execute({ mode = "action", name = action })
				api.log("> " .. tostring(action))
			end,
			runCode = function(source)
				ctx.execute({ mode = "lua", source = source })
			end,
		}
		for _, el in cfg.elements do
			if type(el) == "table" then
				table.insert(elementInsts, buildElement(el, gui, env))
			end
		end
	end

	-- Output from the server
	outputRemote.OnClientEvent:Connect(function(text)
		api.log(text)
	end)
	api.log("SkidSS ready. " .. toggleKey.Name .. " toggles this window.")
	-- If nothing else is on screen (no custom HUD), tell the player how to open it.
	if not openOnJoin and (type(cfg.elements) ~= "table" or #cfg.elements == 0) then
		api.notify("Press " .. toggleKey.Name .. " to open SkidSS")
	end

	-- Hide / toggle
	hide.MouseButton1Click:Connect(function()
		root.Visible = false
	end)
	-- Toggle works even while a TextBox is focused (the key isn't a typing key).
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == toggleKey then
			root.Visible = not root.Visible
		end
	end)

	-- Dragging
	local dragging, dragStart, startPos
	headerBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = root.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			root.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)

	-- Resize grip (bottom-right corner). The window's regions are anchored
	-- relative to root, so changing root size reflows everything.
	local grip = Theme.create("TextButton", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(1, -22, 1, -22),
		BackgroundColor3 = Theme.colors.panelAlt,
		Text = "\u{2921}",
		TextColor3 = Theme.colors.subText,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Active = true,
		Parent = root,
	}, { Theme.corner(4) })

	local resizing, resizeStart, resizeStartSize
	grip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			resizeStart = input.Position
			resizeStartSize = root.AbsoluteSize
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - resizeStart
			root.Size = UDim2.fromOffset(
				math.max(420, resizeStartSize.X + delta.X),
				math.max(300, resizeStartSize.Y + delta.Y)
			)
		end
	end)

	return api
end

return Window
