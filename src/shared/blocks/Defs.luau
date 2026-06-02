local Util = require(script.Parent.Parent.Util)

local Defs = {}
Defs.list = {}
Defs.byId = {}
Defs.categories = {}
Defs.categoryOrder = {}

local function register(def)
	Defs.byId[def.id] = def
	table.insert(Defs.list, def)
	if not Defs.categories[def.category] then
		Defs.categories[def.category] = {}
		table.insert(Defs.categoryOrder, def.category)
	end
	table.insert(Defs.categories[def.category], def)
end

function Defs.lit(value, vtype)
	return { type = "_literal", fields = { value = value, vtype = vtype or "string" } }
end

function Defs.instantiate(id)
	local def = assert(Defs.byId[id], "unknown block " .. tostring(id))
	local node = { type = id }
	if def.inputs then
		node.inputs = {}
		for _, input in def.inputs do
			node.inputs[input.name] = Util.deepCopy(input.default)
		end
	end
	if def.fields then
		node.fields = {}
		for _, field in def.fields do
			node.fields[field.name] = field.default
		end
	end
	if def.bodies then
		node.bodies = {}
		for _, body in def.bodies do
			node.bodies[body] = {}
		end
	end
	return node
end

local COMPARE = { "==", "~=", "<", ">", "<=", ">=" }

local function applyCompare(a, b, op)
	if op == "==" then return a == b end
	if op == "~=" then return a ~= b end
	a = tonumber(a) or 0
	b = tonumber(b) or 0
	if op == "<" then return a < b end
	if op == ">" then return a > b end
	if op == "<=" then return a <= b end
	if op == ">=" then return a >= b end
	return false
end

local function compareLua(node, c)
	return "(" .. c.in_("a") .. " " .. node.fields.op .. " " .. c.in_("b") .. ")"
end

local function resolveTarget(node, state)
	if node.fields.targetMode == "name" then
		return state.api.findPlayer(node.fields.targetName)
	end
	return state.vars["player"]
end

local function targetLua(node, c)
	if node.fields.targetMode == "name" then
		return "_findPlayer(" .. c.q(node.fields.targetName) .. ")"
	end
	return '_vars["player"]'
end

local function targetFields()
	return {
		{ name = "targetMode", kind = "choice", choices = { "loop", "name" }, default = "loop" },
		{ name = "targetName", kind = "text", default = "" },
	}
end

register({
	id = "_literal", category = "Values", kind = "value", side = "both", hidden = true,
	eval = function(node)
		local value, vtype = node.fields.value, node.fields.vtype
		if vtype == "number" then return tonumber(value) or 0 end
		if vtype == "boolean" then return value == true or value == "true" end
		return tostring(value)
	end,
	toLua = function(node, c)
		local value, vtype = node.fields.value, node.fields.vtype
		if vtype == "number" then return tostring(tonumber(value) or 0) end
		if vtype == "boolean" then return (value == true or value == "true") and "true" or "false" end
		return c.q(tostring(value))
	end,
})

register({
	id = "color_rgb", category = "Values", kind = "value", side = "both",
	label = "color %r %g %b",
	inputs = {
		{ name = "r", default = Defs.lit(124, "number") },
		{ name = "g", default = Defs.lit(92, "number") },
		{ name = "b", default = Defs.lit(255, "number") },
	},
	eval = function(node, ctx)
		return Color3.fromRGB(
			math.clamp(tonumber(ctx.eval(node.inputs.r)) or 0, 0, 255),
			math.clamp(tonumber(ctx.eval(node.inputs.g)) or 0, 0, 255),
			math.clamp(tonumber(ctx.eval(node.inputs.b)) or 0, 0, 255)
		)
	end,
	toLua = function(node, c)
		return "Color3.fromRGB(" .. c.in_("r") .. ", " .. c.in_("g") .. ", " .. c.in_("b") .. ")"
	end,
})

register({
	id = "var_get", category = "Variables", kind = "value", side = "both",
	label = "value of %name",
	fields = { { name = "name", kind = "text", default = "x" } },
	eval = function(node, ctx, state) return state.vars[node.fields.name] end,
	toLua = function(node, c) return "_vars[" .. c.q(node.fields.name) .. "]" end,
})

register({
	id = "set_var", category = "Variables", kind = "statement", side = "both",
	label = "set %name to %value",
	fields = { { name = "name", kind = "text", default = "x" } },
	inputs = { { name = "value", default = Defs.lit(0, "number") } },
	exec = function(node, ctx, state) state.vars[node.fields.name] = ctx.eval(node.inputs.value) end,
	toLua = function(node, c) return c.pad .. "_vars[" .. c.q(node.fields.name) .. "] = " .. c.in_("value") end,
})

register({
	id = "change_var", category = "Variables", kind = "statement", side = "both",
	label = "change %name by %by",
	fields = { { name = "name", kind = "text", default = "x" } },
	inputs = { { name = "by", default = Defs.lit(1, "number") } },
	exec = function(node, ctx, state)
		local name = node.fields.name
		state.vars[name] = (tonumber(state.vars[name]) or 0) + (tonumber(ctx.eval(node.inputs.by)) or 0)
	end,
	toLua = function(node, c)
		local name = c.q(node.fields.name)
		return c.pad .. "_vars[" .. name .. "] = (tonumber(_vars[" .. name .. "]) or 0) + (" .. c.in_("by") .. ")"
	end,
})

register({
	id = "op_arith", category = "Operators", kind = "value", side = "both",
	label = "%a %op %b",
	fields = { { name = "op", kind = "choice", choices = { "+", "-", "*", "/", "%" }, default = "+" } },
	inputs = { { name = "a", default = Defs.lit(1, "number") }, { name = "b", default = Defs.lit(1, "number") } },
	eval = function(node, ctx)
		local a = tonumber(ctx.eval(node.inputs.a)) or 0
		local b = tonumber(ctx.eval(node.inputs.b)) or 0
		local op = node.fields.op
		if op == "+" then return a + b end
		if op == "-" then return a - b end
		if op == "*" then return a * b end
		if op == "/" then return b ~= 0 and a / b or 0 end
		if op == "%" then return b ~= 0 and a % b or 0 end
		return 0
	end,
	toLua = function(node, c) return "(" .. c.in_("a") .. " " .. node.fields.op .. " " .. c.in_("b") .. ")" end,
})

register({
	id = "op_concat", category = "Operators", kind = "value", side = "both",
	label = "join %a %b",
	inputs = { { name = "a", default = Defs.lit("", "string") }, { name = "b", default = Defs.lit("", "string") } },
	eval = function(node, ctx) return tostring(ctx.eval(node.inputs.a)) .. tostring(ctx.eval(node.inputs.b)) end,
	toLua = function(node, c) return "(tostring(" .. c.in_("a") .. ") .. tostring(" .. c.in_("b") .. "))" end,
})

register({
	id = "print", category = "Output", kind = "statement", side = "both",
	label = "print %text",
	inputs = { { name = "text", default = Defs.lit("hello", "string") } },
	exec = function(node, ctx, state) state.api.print(tostring(ctx.eval(node.inputs.text))) end,
	toLua = function(node, c) return c.pad .. "print(" .. c.in_("text") .. ")" end,
})

register({
	id = "warn", category = "Output", kind = "statement", side = "both",
	label = "warn %text",
	inputs = { { name = "text", default = Defs.lit("careful", "string") } },
	exec = function(node, ctx, state) state.api.warn(tostring(ctx.eval(node.inputs.text))) end,
	toLua = function(node, c) return c.pad .. "warn(" .. c.in_("text") .. ")" end,
})

register({
	id = "wait", category = "Control", kind = "statement", side = "both",
	label = "wait %seconds seconds",
	inputs = { { name = "seconds", default = Defs.lit(1, "number") } },
	exec = function(node, ctx, state)
		task.wait(math.clamp(tonumber(ctx.eval(node.inputs.seconds)) or 0, 0, state.config.Limits.MaxWaitSeconds))
	end,
	toLua = function(node, c) return c.pad .. "task.wait(" .. c.in_("seconds") .. ")" end,
})

register({
	id = "if_compare", category = "Control", kind = "statement", side = "both",
	label = "if %a %op %b",
	fields = { { name = "op", kind = "choice", choices = COMPARE, default = "==" } },
	inputs = { { name = "a", default = Defs.lit(0, "number") }, { name = "b", default = Defs.lit(0, "number") } },
	bodies = { "do" },
	exec = function(node, ctx, state)
		if applyCompare(ctx.eval(node.inputs.a), ctx.eval(node.inputs.b), node.fields.op) then
			ctx.execBody(node, "do")
		end
	end,
	toLua = function(node, c)
		return c.pad .. "if " .. compareLua(node, c) .. " then\n" .. c.body("do") .. "\n" .. c.pad .. "end"
	end,
})

register({
	id = "if_else_compare", category = "Control", kind = "statement", side = "both",
	label = "if %a %op %b",
	fields = { { name = "op", kind = "choice", choices = COMPARE, default = "==" } },
	inputs = { { name = "a", default = Defs.lit(0, "number") }, { name = "b", default = Defs.lit(0, "number") } },
	bodies = { "do", "otherwise" },
	exec = function(node, ctx, state)
		if applyCompare(ctx.eval(node.inputs.a), ctx.eval(node.inputs.b), node.fields.op) then
			ctx.execBody(node, "do")
		else
			ctx.execBody(node, "otherwise")
		end
	end,
	toLua = function(node, c)
		return c.pad .. "if " .. compareLua(node, c) .. " then\n" .. c.body("do")
			.. "\n" .. c.pad .. "else\n" .. c.body("otherwise") .. "\n" .. c.pad .. "end"
	end,
})

register({
	id = "repeat_n", category = "Control", kind = "statement", side = "both",
	label = "repeat %count times",
	inputs = { { name = "count", default = Defs.lit(10, "number") } },
	bodies = { "do" },
	exec = function(node, ctx, state)
		local n = math.min(math.floor(tonumber(ctx.eval(node.inputs.count)) or 0), state.config.Limits.MaxLoopIterations)
		for _ = 1, n do
			ctx.execBody(node, "do")
		end
	end,
	toLua = function(node, c)
		return c.pad .. "for _ = 1, " .. c.in_("count") .. " do\n" .. c.body("do") .. "\n" .. c.pad .. "end"
	end,
})

register({
	id = "while_compare", category = "Control", kind = "statement", side = "both",
	label = "while %a %op %b",
	fields = { { name = "op", kind = "choice", choices = COMPARE, default = "<" } },
	inputs = { { name = "a", default = Defs.lit(0, "number") }, { name = "b", default = Defs.lit(10, "number") } },
	bodies = { "do" },
	exec = function(node, ctx, state)
		while applyCompare(ctx.eval(node.inputs.a), ctx.eval(node.inputs.b), node.fields.op) do
			ctx.execBody(node, "do")
			ctx.tick()
		end
	end,
	toLua = function(node, c)
		return c.pad .. "while " .. compareLua(node, c) .. " do\n" .. c.body("do") .. "\n" .. c.pad .. "end"
	end,
})

register({
	id = "players_count", category = "Players", kind = "value", side = "server",
	label = "player count",
	eval = function(node, ctx, state) return #state.api.players() end,
	toLua = function() return "#Players:GetPlayers()" end,
})

register({
	id = "for_each_player", category = "Players", kind = "statement", side = "server",
	label = "for each player",
	bodies = { "do" },
	exec = function(node, ctx, state)
		for _, player in state.api.players() do
			state.vars["player"] = player
			ctx.execBody(node, "do")
		end
	end,
	toLua = function(node, c)
		return c.pad .. "for _, _p in Players:GetPlayers() do\n"
			.. c.pad .. '\t_vars["player"] = _p\n' .. c.body("do") .. "\n" .. c.pad .. "end"
	end,
})

register({
	id = "kick_player", category = "Players", kind = "statement", side = "server",
	label = "kick %targetMode %targetName reason %reason",
	fields = targetFields(),
	inputs = { { name = "reason", default = Defs.lit("Kicked", "string") } },
	exec = function(node, ctx, state)
		local player = resolveTarget(node, state)
		if player then state.api.kick(player, tostring(ctx.eval(node.inputs.reason))) end
	end,
	toLua = function(node, c)
		return c.pad .. "do local _t = " .. targetLua(node, c) .. "; if _t then _t:Kick(" .. c.in_("reason") .. ") end end"
	end,
})

register({
	id = "set_walkspeed", category = "Players", kind = "statement", side = "server",
	label = "set walkspeed of %targetMode %targetName to %speed",
	fields = targetFields(),
	inputs = { { name = "speed", default = Defs.lit(16, "number") } },
	exec = function(node, ctx, state)
		local player = resolveTarget(node, state)
		if player then state.api.setWalkSpeed(player, tonumber(ctx.eval(node.inputs.speed)) or 16) end
	end,
	toLua = function(node, c)
		return c.pad .. "do local _t = " .. targetLua(node, c)
			.. "; local _c = _t and _t.Character; local _h = _c and _c:FindFirstChildOfClass(\"Humanoid\"); if _h then _h.WalkSpeed = "
			.. c.in_("speed") .. " end end"
	end,
})

register({
	id = "set_health", category = "Players", kind = "statement", side = "server",
	label = "set health of %targetMode %targetName to %amount",
	fields = targetFields(),
	inputs = { { name = "amount", default = Defs.lit(100, "number") } },
	exec = function(node, ctx, state)
		local player = resolveTarget(node, state)
		if player then state.api.setHealth(player, tonumber(ctx.eval(node.inputs.amount)) or 0) end
	end,
	toLua = function(node, c)
		return c.pad .. "do local _t = " .. targetLua(node, c)
			.. "; local _c = _t and _t.Character; local _h = _c and _c:FindFirstChildOfClass(\"Humanoid\"); if _h then _h.Health = "
			.. c.in_("amount") .. " end end"
	end,
})

register({
	id = "teleport_to_player", category = "Players", kind = "statement", side = "server",
	label = "teleport %targetMode %targetName to player %destName",
	fields = {
		{ name = "targetMode", kind = "choice", choices = { "loop", "name" }, default = "loop" },
		{ name = "targetName", kind = "text", default = "" },
		{ name = "destName", kind = "text", default = "" },
	},
	exec = function(node, ctx, state)
		local player = resolveTarget(node, state)
		local dest = state.api.findPlayer(node.fields.destName)
		if player and dest then state.api.teleport(player, dest) end
	end,
	toLua = function(node, c)
		return c.pad .. "do local _t = " .. targetLua(node, c) .. "; local _d = _findPlayer(" .. c.q(node.fields.destName)
			.. "); if _t and _d and _t.Character and _d.Character then _t.Character:PivotTo(_d.Character:GetPivot()) end end"
	end,
})

register({
	id = "ui_set_title", category = "Interface", kind = "statement", side = "client",
	label = "set window title to %text",
	inputs = { { name = "text", default = Defs.lit("SkidSS", "string") } },
	exec = function(node, ctx, state) state.api.setTitle(tostring(ctx.eval(node.inputs.text))) end,
	toLua = function(node, c) return c.pad .. "ui.setTitle(" .. c.in_("text") .. ")" end,
})

register({
	id = "ui_set_accent", category = "Interface", kind = "statement", side = "client",
	label = "set accent color %r %g %b",
	inputs = {
		{ name = "r", default = Defs.lit(124, "number") },
		{ name = "g", default = Defs.lit(92, "number") },
		{ name = "b", default = Defs.lit(255, "number") },
	},
	exec = function(node, ctx, state)
		state.api.setAccent(Color3.fromRGB(
			math.clamp(tonumber(ctx.eval(node.inputs.r)) or 0, 0, 255),
			math.clamp(tonumber(ctx.eval(node.inputs.g)) or 0, 0, 255),
			math.clamp(tonumber(ctx.eval(node.inputs.b)) or 0, 0, 255)))
	end,
	toLua = function(node, c)
		return c.pad .. "ui.setAccent(Color3.fromRGB(" .. c.in_("r") .. ", " .. c.in_("g") .. ", " .. c.in_("b") .. "))"
	end,
})

register({
	id = "ui_set_background", category = "Interface", kind = "statement", side = "client",
	label = "set background color %r %g %b",
	inputs = {
		{ name = "r", default = Defs.lit(22, "number") },
		{ name = "g", default = Defs.lit(22, "number") },
		{ name = "b", default = Defs.lit(28, "number") },
	},
	exec = function(node, ctx, state)
		state.api.setBackground(Color3.fromRGB(
			math.clamp(tonumber(ctx.eval(node.inputs.r)) or 0, 0, 255),
			math.clamp(tonumber(ctx.eval(node.inputs.g)) or 0, 0, 255),
			math.clamp(tonumber(ctx.eval(node.inputs.b)) or 0, 0, 255)))
	end,
	toLua = function(node, c)
		return c.pad .. "ui.setBackground(Color3.fromRGB(" .. c.in_("r") .. ", " .. c.in_("g") .. ", " .. c.in_("b") .. "))"
	end,
})

register({
	id = "ui_notify", category = "Interface", kind = "statement", side = "client",
	label = "show toast %text",
	inputs = { { name = "text", default = Defs.lit("hi", "string") } },
	exec = function(node, ctx, state) state.api.notify(tostring(ctx.eval(node.inputs.text))) end,
	toLua = function(node, c) return c.pad .. "ui.notify(" .. c.in_("text") .. ")" end,
})

register({
	id = "ui_log", category = "Interface", kind = "statement", side = "client",
	label = "log %text to console",
	inputs = { { name = "text", default = Defs.lit("hi", "string") } },
	exec = function(node, ctx, state) state.api.log(tostring(ctx.eval(node.inputs.text))) end,
	toLua = function(node, c) return c.pad .. "ui.log(" .. c.in_("text") .. ")" end,
})

register({
	id = "ui_add_button", category = "Interface", kind = "statement", side = "client",
	label = "add quick button %label",
	inputs = { { name = "label", default = Defs.lit("Run", "string") } },
	exec = function(node, ctx, state) state.api.addButton(tostring(ctx.eval(node.inputs.label))) end,
	toLua = function(node, c) return c.pad .. "ui.addButton(" .. c.in_("label") .. ")" end,
})

return Defs
