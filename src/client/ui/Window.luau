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

		local id = string.match(tostring(el.image or ""), "%d+")
		if id then
			task.spawn(function()
				task.wait(2)
				if inst.Parent and not inst.IsLoaded then
					inst.Image = "rbxthumb://type=Asset&id=" .. id .. "&w=420&h=420"
				end
			end)
		end
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

				if not box and env.codeBoxes then
					local only, count = nil, 0
					for _, b in env.codeBoxes do only = b; count += 1 end
					if count == 1 then box = only end
				end
				if box then
					env.runCode(box.Text)
				elseif env.notify then
					env.notify("no code box to run")
				end
			end)
		end
	end

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

	if playerGui:FindFirstChild("SkidSS") then return end

	local executeRemote = Net.get(Net.Execute)
	local outputRemote = Net.get(Net.Output)

	local gui = Instance.new("ScreenGui")
	gui.Name = "SkidSS"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local useCustom = type(cfg.elements) == "table" and #cfg.elements > 0

	local lineOrder = 0
	local quickButtons = {}
	local hudOutputs = {}
	local console, titleLabel, accentStrip, root, quickBar
	local api = {}

	function api.notify(text)
		local toast = Theme.create("TextLabel", {
			Size = UDim2.fromOffset(280, 34),
			Position = UDim2.new(0.5, -140, 0, 50),
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

	function api.log(text)
		text = tostring(text)
		for _, append in hudOutputs do
			append(text)
		end
		if console then
			lineOrder += 1
			Theme.create("TextLabel", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = text,
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
		elseif #hudOutputs == 0 then

			api.notify(text)
		end
	end

	function api.setTitle(text)
		if titleLabel then titleLabel.Text = text end
	end

	function api.setAccent(color)
		Theme.colors.accent = color
		if accentStrip then accentStrip.BackgroundColor3 = color end
		for _, button in quickButtons do
			button.BackgroundColor3 = color
		end
	end

	function api.setBackground(color)
		Theme.colors.background = color
		if root then root.BackgroundColor3 = color end
	end

	local state = { serverProgram = nil }
	local ctx = {
		log = api.log,
		execute = function(payload)
			executeRemote:FireServer(payload)
		end,
		state = state,
		window = api,
	}

	function api.addButton(label, onClick)
		if not quickBar then return end
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

	if useCustom then

		local hud = Theme.create("Frame", {
			Name = "HUD",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.colors.background,

			BackgroundTransparency = tonumber(cfg.backgroundTransparency) or 1,
			BorderSizePixel = 0,
			Parent = gui,
		})

		local elementInsts = {}
		local env = {
			codeBoxes = {},
			outputs = hudOutputs,
			elementInsts = elementInsts,
			notify = api.notify,
			fireAction = function(action)
				ctx.execute({ mode = "action", name = action })
				api.log("> " .. tostring(action))
			end,
			runCode = function(source)
				api.log("> running\u{2026}")
				ctx.execute({ mode = "lua", source = source })
			end,
		}
		for _, el in cfg.elements do
			if type(el) == "table" then
				table.insert(elementInsts, buildElement(el, hud, env))
			end
		end

		UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == toggleKey then
				hud.Visible = not hud.Visible
			end
		end)
	else

		local winW = math.max(420, tonumber(cfg.width) or 760)
		local winH = math.max(300, tonumber(cfg.height) or 480)
		local openOnJoin = cfg.openOnJoin == true

		root = Theme.create("Frame", {
			Size = UDim2.fromOffset(winW, winH),
			Position = UDim2.new(0.5, -winW / 2, 0.5, -winH / 2),
			AnchorPoint = Vector2.new(0, 0),
			BackgroundColor3 = Theme.colors.background,
			BorderSizePixel = 0,
			Active = true,
			Visible = openOnJoin,
			Parent = gui,
		}, { Theme.corner(10) })

		local headerBar = Theme.create("Frame", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = Theme.colors.panel,
			BorderSizePixel = 0,
			Active = true,
			Parent = root,
		}, { Theme.corner(10) })

		accentStrip = Theme.create("Frame", {
			Size = UDim2.new(1, 0, 0, 3),
			Position = UDim2.new(0, 0, 1, -3),
			BackgroundColor3 = Theme.colors.accent,
			BorderSizePixel = 0,
			Parent = headerBar,
		})

		titleLabel = Theme.create("TextLabel", {
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

		local content = Theme.create("Frame", {
			Position = UDim2.fromOffset(12, 84),
			Size = UDim2.new(1, -24, 1, -252),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Parent = root,
		})

		console = Theme.create("ScrollingFrame", {
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

		quickBar = Theme.create("Frame", {
			Position = UDim2.new(0, 12, 1, -42),
			Size = UDim2.new(1, -24, 0, 30),
			BackgroundTransparency = 1,
			Parent = root,
		})
		local quickRow = Theme.listLayout(6, Enum.FillDirection.Horizontal)
		quickRow.Parent = quickBar

		local code = CodeTab.build(content, ctx)
		code.frame.Visible = true

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

		hide.MouseButton1Click:Connect(function()
			root.Visible = false
		end)
		UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == toggleKey then
				root.Visible = not root.Visible
			end
		end)

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

		if not openOnJoin then
			api.notify("Press " .. toggleKey.Name .. " to open SkidSS")
		end
	end

	outputRemote.OnClientEvent:Connect(function(text)
		api.log(text)
	end)
	api.log("SkidSS ready \u{2014} " .. toggleKey.Name .. " toggles.")

	return api
end

return Window
