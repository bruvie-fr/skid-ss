local Lexer = require(script.Parent.LuaLexer)
local Parser = require(script.Parent.LuaParser)

local robloxTick = tick

local Interp = {}

local DEFAULTS = {
	MaxLuaSteps = 10000000,
	MaxLuaSeconds = 2,
	MaxLuaDepth = 200,
	MaxWaitSeconds = 30,
}

local BINOPS = {
	["+"] = function(a, b) return a + b end,
	["-"] = function(a, b) return a - b end,
	["*"] = function(a, b) return a * b end,
	["/"] = function(a, b) return a / b end,
	["%"] = function(a, b) return a % b end,
	["^"] = function(a, b) return a ^ b end,
	["//"] = function(a, b) return a // b end,
	[".."] = function(a, b) return a .. b end,
	["=="] = function(a, b) return a == b end,
	["~="] = function(a, b) return a ~= b end,
	["<"] = function(a, b) return a < b end,
	["<="] = function(a, b) return a <= b end,
	[">"] = function(a, b) return a > b end,
	[">="] = function(a, b) return a >= b end,
}

local Scope = {}
Scope.__index = Scope
local function newScope(parent) return setmetatable({ vars = {}, parent = parent }, Scope) end
function Scope:define(name, value) self.vars[name] = { value = value } end
function Scope:lookup(name)
	local s = self
	while s do
		local c = s.vars[name]
		if c then return c end
		s = s.parent
	end
	return nil
end

local function isAbort(e) return type(e) == "table" and e.__skidss_abort == true end
local function abort(message) error({ __skidss_abort = true, message = message }) end

local function tick(state)
	state.steps += 1
	if state.steps > state.maxSteps then
		abort("step budget exceeded (" .. state.maxSteps .. ") — possible infinite loop")
	end
	if state.steps % 4096 == 0 and (os.clock() - state.start) > state.maxSeconds then
		abort("time budget exceeded (" .. state.maxSeconds .. "s) — possible infinite loop")
	end
end

local function rtError(state, msg)
	error("input:" .. tostring(state.line) .. ": " .. msg, 0)
end

local function cleanMessage(err, state)
	if isAbort(err) then return tostring(err.message) end
	if type(err) ~= "string" then return tostring(err) end
	if string.match(err, "^input:%d+:") then return err end
	local rest = string.match(err, "^[%w%._%- ]-:%d+:%s*(.*)$")
	if rest then return "input:" .. tostring(state.line) .. ": " .. rest end
	return "input:" .. tostring(state.line) .. ": " .. err
end

local function buildEnv(state)
	local emit = state.emit
	local maxWait = state.limits.MaxWaitSeconds or DEFAULTS.MaxWaitSeconds

	local function collect(...)
		local parts = {}
		local nargs = select("#", ...)
		for i = 1, nargs do parts[i] = tostring((select(i, ...))) end
		return table.concat(parts, " ")
	end

	local function cappedWait(t)
		t = tonumber(t) or 0
		if t > maxWait then t = maxWait end
		local dt = task.wait(t)
		state.start = os.clock()
		return dt
	end

	local G = {}

	G.print = function(...) emit(collect(...)) end
	G.warn = function(...) emit("[warn] " .. collect(...)) end

	G.pcall = function(f, ...)
		local saved = state.depth
		local res = table.pack(pcall(f, ...))
		state.depth = saved
		if res[1] == false and isAbort(res[2]) then error(res[2]) end
		return table.unpack(res, 1, res.n)
	end
	G.xpcall = function(f, handler, ...)
		local saved = state.depth
		local res = table.pack(xpcall(f, function(e)
			if isAbort(e) then return e end
			return handler(e)
		end, ...))
		state.depth = saved
		if res[1] == false and isAbort(res[2]) then error(res[2]) end
		return table.unpack(res, 1, res.n)
	end

	G.error = function(msg, level)
		if level == nil then level = 1 end
		if level ~= 0 and type(msg) == "string" then
			msg = "input:" .. tostring(state.line) .. ": " .. msg
		end
		error(msg, 0)
	end
	G.assert = function(v, msg, ...)
		if v == nil or v == false then
			return G.error(msg == nil and "assertion failed!" or msg)
		end
		return v, msg, ...
	end

	G.pairs = pairs
	G.ipairs = ipairs
	G.next = next
	G.select = select
	G.type = type
	G.typeof = typeof
	G.tostring = tostring
	G.tonumber = tonumber
	G.setmetatable = setmetatable
	G.getmetatable = getmetatable
	G.rawget = rawget
	G.rawset = rawset
	G.rawequal = rawequal
	G.rawlen = rawlen
	G.unpack = table.unpack

	G.string = string
	G.table = table
	G.math = math
	G.bit32 = bit32
	G.utf8 = utf8
	G.coroutine = coroutine
	G.os = { time = os.time, clock = os.clock, date = os.date, difftime = os.difftime }
	G.task = setmetatable(
		{ wait = cappedWait, spawn = task.spawn, delay = task.delay, defer = task.defer, cancel = task.cancel },
		{ __index = task }
	)
	G.wait = cappedWait
	G.delay = function(t, f) return task.delay(tonumber(t) or 0, f) end
	G.spawn = function(f) return task.spawn(f) end
	G.tick = robloxTick

	G.game = game
	G.workspace = workspace
	G.Enum = Enum
	G.Instance = Instance
	G.Vector2 = Vector2
	G.Vector3 = Vector3
	G.Vector3int16 = Vector3int16
	G.CFrame = CFrame
	G.Color3 = Color3
	G.ColorSequence = ColorSequence
	G.ColorSequenceKeypoint = ColorSequenceKeypoint
	G.NumberSequence = NumberSequence
	G.NumberSequenceKeypoint = NumberSequenceKeypoint
	G.NumberRange = NumberRange
	G.UDim = UDim
	G.UDim2 = UDim2
	G.BrickColor = BrickColor
	G.Ray = Ray
	G.Rect = Rect
	G.Region3 = Region3
	G.TweenInfo = TweenInfo
	G.PhysicalProperties = PhysicalProperties
	G.Random = Random
	G.DateTime = DateTime
	G.Faces = Faces
	G.Axes = Axes
	G.newproxy = newproxy

	G.require = require

	local function unavailable(name)
		return function() error("'" .. name .. "' is not available in the SkidSS interpreter (v1)", 0) end
	end
	G.loadstring = unavailable("loadstring")
	G.getfenv = unavailable("getfenv")
	G.setfenv = unavailable("setfenv")

	G._G = G
	G.shared = {}
	G._VERSION = _VERSION

	return G
end

local evalExpr, evalMulti, evalExprList, evalCall, evalTable, evalBinop
local makeClosure, makeSetter
local execBlock, execStmt, execAssign, execCompound, execNumericFor, execGenericFor

function evalCall(node, scope, state)
	local fn, selfArg
	if node.kind == "MethodCall" then
		local obj = evalExpr(node.obj, scope, state)
		if obj == nil then rtError(state, "attempt to index nil with '" .. node.method .. "'") end
		fn = obj[node.method]
		selfArg = obj
	else
		fn = evalExpr(node.func, scope, state)
	end
	local args = evalExprList(node.args, scope, state)
	state.line = node.line or state.line
	if type(fn) ~= "function" then
		local okmt, mt = pcall(getmetatable, fn)
		local callable = okmt and type(mt) == "table" and rawget(mt, "__call") ~= nil
		if not callable then
			local nm = node.kind == "MethodCall" and (" '" .. node.method .. "'") or ""
			rtError(state, "attempt to call a " .. typeof(fn) .. " value" .. nm)
		end
	end
	if node.kind == "MethodCall" then
		return table.pack(fn(selfArg, table.unpack(args, 1, args.n)))
	end
	return table.pack(fn(table.unpack(args, 1, args.n)))
end

function evalMulti(node, scope, state)
	local k = node.kind
	if k == "Call" or k == "MethodCall" then
		return evalCall(node, scope, state)
	elseif k == "Vararg" then
		local cell = scope:lookup("...")
		local v = cell and cell.value
		return v or { n = 0 }
	end
	return { n = 1, [1] = evalExpr(node, scope, state) }
end

function evalExprList(list, scope, state)
	local out = { n = 0 }
	local count = #list
	if count == 0 then return out end
	for i = 1, count - 1 do
		out[i] = evalExpr(list[i], scope, state)
	end
	local last = evalMulti(list[count], scope, state)
	local base = count - 1
	for i = 1, last.n do out[base + i] = last[i] end
	out.n = base + last.n
	return out
end

function evalTable(node, scope, state)
	local t = {}
	local arr = 0
	local fields = node.fields
	local count = #fields
	for i = 1, count do
		local f = fields[i]
		if f.type == "item" then
			if i == count then
				local m = evalMulti(f.value, scope, state)
				for j = 1, m.n do arr += 1; t[arr] = m[j] end
			else
				arr += 1
				t[arr] = evalExpr(f.value, scope, state)
			end
		elseif f.type == "named" then
			t[f.name] = evalExpr(f.value, scope, state)
		else
			local key = evalExpr(f.key, scope, state)
			if key == nil then rtError(state, "table index is nil") end
			t[key] = evalExpr(f.value, scope, state)
		end
	end
	return t
end

function evalBinop(node, scope, state)
	local op = node.op
	if op == "and" then
		local l = evalExpr(node.lhs, scope, state)
		if l == nil or l == false then return l end
		return evalExpr(node.rhs, scope, state)
	elseif op == "or" then
		local l = evalExpr(node.lhs, scope, state)
		if l ~= nil and l ~= false then return l end
		return evalExpr(node.rhs, scope, state)
	end
	local l = evalExpr(node.lhs, scope, state)
	local r = evalExpr(node.rhs, scope, state)
	state.line = node.line or state.line
	return BINOPS[op](l, r)
end

function makeClosure(node, defScope, state)
	local params = node.params
	local nparams = #params
	local isVararg = node.isVararg
	local body = node.body
	return function(...)
		local fnScope = newScope(defScope)
		local argc = select("#", ...)
		local argv = table.pack(...)
		for i = 1, nparams do fnScope:define(params[i], argv[i]) end
		if isVararg then
			local extra = { n = math.max(0, argc - nparams) }
			for i = 1, extra.n do extra[i] = argv[nparams + i] end
			fnScope.vars["..."] = { value = extra }
		end
		state.depth += 1
		if state.depth > state.maxDepth then
			state.depth -= 1
			abort("call stack too deep (" .. state.maxDepth .. ")")
		end
		local sig = execBlock(body, fnScope, state)
		state.depth -= 1
		if type(sig) == "table" and sig.kind == "return" then
			return table.unpack(sig.values, 1, sig.values.n)
		end
		return
	end
end

function evalExpr(node, scope, state)
	if node.line then state.line = node.line end
	tick(state)
	local k = node.kind
	if k == "Number" or k == "String" then
		return node.value
	elseif k == "Name" then
		local cell = scope:lookup(node.name)
		if cell then return cell.value end
		return state.G[node.name]
	elseif k == "Binop" then
		return evalBinop(node, scope, state)
	elseif k == "Call" or k == "MethodCall" then
		return (evalCall(node, scope, state))[1]
	elseif k == "Index" then
		local obj = evalExpr(node.obj, scope, state)
		if obj == nil then
			rtError(state, "attempt to index nil" .. (node.field and (" with '" .. node.field .. "'") or ""))
		end
		return obj[evalExpr(node.index, scope, state)]
	elseif k == "Nil" then
		return nil
	elseif k == "True" then
		return true
	elseif k == "False" then
		return false
	elseif k == "Unop" then
		local v = evalExpr(node.operand, scope, state)
		state.line = node.line or state.line
		if node.op == "not" then return not v
		elseif node.op == "-" then return -v
		else return #v end
	elseif k == "Table" then
		return evalTable(node, scope, state)
	elseif k == "Function" then
		return makeClosure(node, scope, state)
	elseif k == "Paren" then
		return evalExpr(node.expr, scope, state)
	elseif k == "Vararg" then
		local cell = scope:lookup("...")
		local v = cell and cell.value
		return v and v[1] or nil
	end
	rtError(state, "cannot evaluate '" .. tostring(k) .. "'")
end

function makeSetter(target, scope, state)
	if target.kind == "Name" then
		local name = target.name
		return function(v)
			local cell = scope:lookup(name)
			if cell then cell.value = v else state.G[name] = v end
		end
	end
	local obj = evalExpr(target.obj, scope, state)
	if obj == nil then
		rtError(state, "attempt to index nil" .. (target.field and (" with '" .. target.field .. "'") or ""))
	end
	local key = evalExpr(target.index, scope, state)
	return function(v) obj[key] = v end
end

function execAssign(node, scope, state)
	local setters = {}
	for i = 1, #node.targets do setters[i] = makeSetter(node.targets[i], scope, state) end
	local vals = evalExprList(node.exprs, scope, state)
	for i = 1, #setters do setters[i](vals[i]) end
end

function execCompound(node, scope, state)
	local target = node.target
	local rhs
	if target.kind == "Name" then
		local cell = scope:lookup(target.name)
		local cur
		if cell then cur = cell.value else cur = state.G[target.name] end
		rhs = evalExpr(node.expr, scope, state)
		state.line = node.line or state.line
		local res = BINOPS[node.op](cur, rhs)
		if cell then cell.value = res else state.G[target.name] = res end
	else
		local obj = evalExpr(target.obj, scope, state)
		if obj == nil then
			rtError(state, "attempt to index nil" .. (target.field and (" with '" .. target.field .. "'") or ""))
		end
		local key = evalExpr(target.index, scope, state)
		local cur = obj[key]
		rhs = evalExpr(node.expr, scope, state)
		state.line = node.line or state.line
		obj[key] = BINOPS[node.op](cur, rhs)
	end
end

function execNumericFor(node, scope, state)
	local a = tonumber(evalExpr(node.start, scope, state))
	local b = tonumber(evalExpr(node.stop, scope, state))
	local st = node.step and tonumber(evalExpr(node.step, scope, state)) or 1
	if a == nil then rtError(state, "'for' initial value must be a number") end
	if b == nil then rtError(state, "'for' limit must be a number") end
	if st == nil then rtError(state, "'for' step must be a number") end
	if st == 0 then rtError(state, "'for' step is zero") end
	local i = a
	while (st > 0 and i <= b) or (st < 0 and i >= b) do
		tick(state)
		local s2 = newScope(scope)
		s2:define(node.var, i)
		local sig = execBlock(node.body, s2, state)
		if sig then
			if sig.kind == "break" then break
			elseif sig.kind == "return" then return sig end
		end
		i += st
	end
	return nil
end

function execGenericFor(node, scope, state)
	local vals = evalExprList(node.exprs, scope, state)
	local f, s, ctrl = vals[1], vals[2], vals[3]
	if type(f) ~= "function" then
		local okmt, mt = pcall(getmetatable, f)
		local callable = okmt and type(mt) == "table" and rawget(mt, "__call") ~= nil
		if not callable then rtError(state, "attempt to iterate with a " .. typeof(f) .. " value") end
	end
	while true do
		tick(state)
		local r = table.pack(f(s, ctrl))
		if r[1] == nil then break end
		ctrl = r[1]
		local s2 = newScope(scope)
		for i = 1, #node.names do s2:define(node.names[i], r[i]) end
		local sig = execBlock(node.body, s2, state)
		if sig then
			if sig.kind == "break" then break
			elseif sig.kind == "return" then return sig end
		end
	end
	return nil
end

function execStmt(node, scope, state)
	tick(state)
	state.line = node.line or state.line
	local k = node.kind
	if k == "CallStat" then
		evalCall(node.call, scope, state)
		return nil
	elseif k == "Local" then
		local vals = evalExprList(node.exprs, scope, state)
		for i = 1, #node.names do scope:define(node.names[i], vals[i]) end
		return nil
	elseif k == "Assign" then
		execAssign(node, scope, state)
		return nil
	elseif k == "CompoundAssign" then
		execCompound(node, scope, state)
		return nil
	elseif k == "If" then
		for _, clause in ipairs(node.clauses) do
			local c = evalExpr(clause.cond, scope, state)
			if c ~= nil and c ~= false then
				return execBlock(clause.body, newScope(scope), state)
			end
		end
		if node.elseBody then return execBlock(node.elseBody, newScope(scope), state) end
		return nil
	elseif k == "While" then
		while true do
			tick(state)
			local c = evalExpr(node.cond, scope, state)
			if c == nil or c == false then break end
			local sig = execBlock(node.body, newScope(scope), state)
			if sig then
				if sig.kind == "break" then break
				elseif sig.kind == "return" then return sig end
			end
		end
		return nil
	elseif k == "Repeat" then
		while true do
			tick(state)
			local s2 = newScope(scope)
			local sig = execBlock(node.body, s2, state)
			if sig then
				if sig.kind == "break" then break
				elseif sig.kind == "return" then return sig end
			end
			local c = evalExpr(node.cond, s2, state)
			if c ~= nil and c ~= false then break end
		end
		return nil
	elseif k == "NumericFor" then
		return execNumericFor(node, scope, state)
	elseif k == "GenericFor" then
		return execGenericFor(node, scope, state)
	elseif k == "Do" then
		return execBlock(node.body, newScope(scope), state)
	elseif k == "LocalFunction" then
		scope:define(node.name, nil)
		scope:lookup(node.name).value = makeClosure(node.func, scope, state)
		return nil
	elseif k == "Return" then
		return { kind = "return", values = evalExprList(node.exprs, scope, state) }
	elseif k == "Break" then
		return { kind = "break" }
	elseif k == "Continue" then
		return { kind = "continue" }
	end
	rtError(state, "cannot execute '" .. tostring(k) .. "'")
end

function execBlock(stmts, scope, state)
	for i = 1, #stmts do
		local sig = execStmt(stmts[i], scope, state)
		if sig then return sig end
	end
	return nil
end

function Interp.run(source, opts)
	opts = opts or {}
	local emit = opts.emit or function() end
	local limits = opts.limits or {}

	local tokens, lerr = Lexer.safeTokenize(source)
	if not tokens then return false, "compile error: " .. lerr end
	local ast, perr = Parser.parse(tokens)
	if not ast then return false, "compile error: " .. perr end

	local state = {
		emit = emit,
		limits = limits,
		steps = 0,
		depth = 0,
		line = 0,
		start = os.clock(),
		maxSteps = limits.MaxLuaSteps or DEFAULTS.MaxLuaSteps,
		maxSeconds = limits.MaxLuaSeconds or DEFAULTS.MaxLuaSeconds,
		maxDepth = limits.MaxLuaDepth or DEFAULTS.MaxLuaDepth,
	}
	state.G = buildEnv(state)

	local top = newScope(nil)
	top.vars["..."] = { value = { n = 0 } }

	local ok, err = pcall(execBlock, ast, top, state)
	if ok then return true, "ran" end
	return false, "runtime error: " .. cleanMessage(err, state)
end

return Interp
