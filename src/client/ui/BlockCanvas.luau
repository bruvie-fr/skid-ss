local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Defs = require(ReplicatedStorage:WaitForChild("SkidSS").blocks.Defs)
local Theme = require(script.Parent.Parent.Theme)

local BlockCanvas = {}

local CATEGORY_COLORS = {
	Output = Color3.fromRGB(74, 110, 190),
	Control = Color3.fromRGB(206, 146, 56),
	Variables = Color3.fromRGB(196, 104, 66),
	Operators = Color3.fromRGB(86, 166, 106),
	Players = Color3.fromRGB(146, 96, 196),
	Interface = Color3.fromRGB(66, 156, 166),
	Values = Color3.fromRGB(108, 108, 128),
}

local function categoryColor(category)
	return CATEGORY_COLORS[category] or Color3.fromRGB(90, 90, 110)
end

local function parseLabel(label)
	local tokens = {}
	for word in string.gmatch(label or "", "%S+") do
		if string.sub(word, 1, 1) == "%" then
			table.insert(tokens, { slot = string.sub(word, 2) })
		else
			table.insert(tokens, { text = word })
		end
	end
	return tokens
end

local function fieldDef(def, name)
	if def.fields then
		for _, field in def.fields do
			if field.name == name then
				return field
			end
		end
	end
	return nil
end

local function textEditor(width, get, set)
	local box = Theme.create("TextBox", {
		Size = UDim2.fromOffset(width, 22),
		BackgroundColor3 = Theme.colors.panelAlt,
		TextColor3 = Theme.colors.text,
		Font = Enum.Font.Code,
		TextSize = 13,
		Text = get(),
		ClearTextOnFocus = false,
	}, { Theme.corner(4) })
	box.FocusLost:Connect(function()
		set(box.Text)
	end)
	return box
end

local function slotEditor(node, def, name)
	local input = node.inputs and node.inputs[name]
	if input then
		if input.type == "_literal" then
			local fields = input.fields
			if fields.vtype == "boolean" then
				local toggle = Theme.create("TextButton", {
					Size = UDim2.fromOffset(56, 22),
					BackgroundColor3 = Theme.colors.panelAlt,
					Text = tostring(fields.value),
					TextColor3 = Theme.colors.text,
					Font = Enum.Font.Code,
					TextSize = 13,
				}, { Theme.corner(4) })
				toggle.MouseButton1Click:Connect(function()
					fields.value = not (fields.value == true or fields.value == "true")
					toggle.Text = tostring(fields.value)
				end)
				return toggle
			end
			local width = fields.vtype == "number" and 56 or 110
			return textEditor(width, function() return tostring(fields.value) end, function(text) fields.value = text end)
		end
		return Theme.create("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			BackgroundTransparency = 1,
			Text = "(expr)",
			TextColor3 = Theme.colors.subText,
			Font = Enum.Font.Code,
			TextSize = 13,
		})
	end

	local field = fieldDef(def, name)
	if field then
		if field.kind == "choice" then
			local button = Theme.create("TextButton", {
				Size = UDim2.fromOffset(54, 22),
				BackgroundColor3 = Theme.colors.panelAlt,
				Text = tostring(node.fields[name]),
				TextColor3 = Theme.colors.accent,
				Font = Enum.Font.GothamBold,
				TextSize = 13,
			}, { Theme.corner(4) })
			button.MouseButton1Click:Connect(function()
				local index = table.find(field.choices, node.fields[name]) or 1
				node.fields[name] = field.choices[(index % #field.choices) + 1]
				button.Text = tostring(node.fields[name])
			end)
			return button
		end
		return textEditor(90, function() return tostring(node.fields[name]) end, function(text) node.fields[name] = text end)
	end

	return nil
end

function BlockCanvas.new(parent, program, allow)
	local controller = {}
	local selection = { list = program, index = #program }

	Theme.listLayout(6).Parent = parent

	local function selectButton(list, index, isAppend)
		return selection.list == list and (isAppend and selection.index >= #list or selection.index == index)
	end

	local function insertButton(list)
		local button = Theme.create("TextButton", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundColor3 = Theme.colors.panel,
			Text = "+ insert here",
			TextColor3 = Theme.colors.subText,
			Font = Enum.Font.Gotham,
			TextSize = 12,
		}, { Theme.corner(4) })
		if selectButton(list, #list, true) then
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.colors.accent
			stroke.Parent = button
		end
		button.MouseButton1Click:Connect(function()
			selection = { list = list, index = #list }
			controller.refresh()
		end)
		return button
	end

	local function header(node, def, list, index)
		local frame = Theme.create("TextButton", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = categoryColor(def.category),
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
		}, { Theme.corner(6) })

		if selectButton(list, index, false) then
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.colors.text
			stroke.Thickness = 2
			stroke.Parent = frame
		end
		frame.MouseButton1Click:Connect(function()
			selection = { list = list, index = index }
			controller.refresh()
		end)

		local left = Theme.create("Frame", {
			Size = UDim2.new(1, -104, 1, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Parent = frame,
		}, { Theme.padding(6) })
		local row = Theme.listLayout(6, Enum.FillDirection.Horizontal)
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.Parent = left

		local order = 0
		for _, token in parseLabel(def.label) do
			order += 1
			local element
			if token.slot then
				element = slotEditor(node, def, token.slot)
			end
			if not element then
				element = Theme.create("TextLabel", {
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 22),
					BackgroundTransparency = 1,
					Text = token.text or token.slot or "",
					TextColor3 = Theme.colors.text,
					Font = Enum.Font.GothamMedium,
					TextSize = 13,
				})
			end
			element.LayoutOrder = order
			element.Parent = left
		end

		local controls = Theme.create("Frame", {
			Size = UDim2.fromOffset(96, 30),
			Position = UDim2.new(1, -96, 0, 0),
			BackgroundTransparency = 1,
			Parent = frame,
		})
		local controlsRow = Theme.listLayout(4, Enum.FillDirection.Horizontal)
		controlsRow.HorizontalAlignment = Enum.HorizontalAlignment.Right
		controlsRow.VerticalAlignment = Enum.VerticalAlignment.Center
		controlsRow.Parent = controls

		local function control(symbol, onClick)
			local button = Theme.create("TextButton", {
				Size = UDim2.fromOffset(26, 22),
				BackgroundColor3 = Theme.colors.panelAlt,
				Text = symbol,
				TextColor3 = Theme.colors.text,
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				Parent = controls,
			}, { Theme.corner(4) })
			button.MouseButton1Click:Connect(onClick)
		end

		control("\u{2191}", function()
			if index > 1 then
				list[index], list[index - 1] = list[index - 1], list[index]
				controller.refresh()
			end
		end)
		control("\u{2193}", function()
			if index < #list then
				list[index], list[index + 1] = list[index + 1], list[index]
				controller.refresh()
			end
		end)
		control("\u{2715}", function()
			table.remove(list, index)
			selection = { list = program, index = #program }
			controller.refresh()
		end)

		return frame
	end

	local function renderBlock(node, list, index, parent)
		local def = Defs.byId[node.type]
		if not def then return end

		local container = Theme.create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = parent,
		})
		Theme.listLayout(4).Parent = container

		local head = header(node, def, list, index)
		head.LayoutOrder = 0
		head.Parent = container

		if def.bodies then
			local bodyOrder = 0
			for _, bodyName in def.bodies do
				bodyOrder += 1
				local bodyBox = Theme.create("Frame", {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Theme.colors.background,
					BorderSizePixel = 0,
					LayoutOrder = bodyOrder,
					Parent = container,
				}, { Theme.corner(6) })
				local pad = Instance.new("UIPadding")
				pad.PaddingLeft = UDim.new(0, 16)
				pad.PaddingTop = UDim.new(0, 4)
				pad.PaddingBottom = UDim.new(0, 4)
				pad.PaddingRight = UDim.new(0, 4)
				pad.Parent = bodyBox
				Theme.listLayout(4).Parent = bodyBox

				local caption = Theme.create("TextLabel", {
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					Text = bodyName,
					TextColor3 = Theme.colors.subText,
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 0,
					Parent = bodyBox,
				})

				local body = node.bodies[bodyName]
				for childIndex, child in body do
					renderBlock(child, body, childIndex, bodyBox)
				end

				local add = insertButton(body)
				add.LayoutOrder = 1e6
				add.Parent = bodyBox
			end
		end
	end

	function controller.refresh()
		for _, child in parent:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for index, node in program do
			renderBlock(node, program, index, parent)
		end
		local tail = insertButton(program)
		tail.LayoutOrder = 1e6
		tail.Parent = parent
	end

	function controller.insert(defId)
		local list = selection.list or program
		local at = (selection.index or #list) + 1
		table.insert(list, at, Defs.instantiate(defId))
		selection = { list = list, index = at }
		controller.refresh()
	end

	controller.refresh()
	return controller
end

return BlockCanvas
