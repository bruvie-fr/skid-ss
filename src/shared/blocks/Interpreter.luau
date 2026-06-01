-- Runs a block program (an array of statement nodes) against a host-supplied api.
-- A step budget makes it impossible for a block script to hang the game, and the
-- `allow` table lets the host reject blocks that aren't meant to run on its side.

local Defs = require(script.Parent.Defs)

local Interpreter = {}

function Interpreter.run(program, api, config, allow)
	assert(type(program) == "table", "program must be a table")

	local state = {
		vars = {},
		api = api,
		config = config,
		allow = allow or { server = true, client = true, both = true },
		steps = 0,
	}

	local ctx = {}

	function ctx.tick()
		state.steps += 1
		if state.steps > config.Limits.MaxSteps then
			error("step limit reached (" .. config.Limits.MaxSteps .. ")", 0)
		end
	end

	local function check(node, want)
		local def = Defs.byId[node and node.type]
		if not def or not def[want] then
			error("expected a " .. want .. " block, got " .. tostring(node and node.type), 0)
		end
		if not state.allow[def.side] then
			error("block '" .. def.id .. "' is not allowed here", 0)
		end
		return def
	end

	function ctx.eval(node)
		ctx.tick()
		return check(node, "eval").eval(node, ctx, state)
	end

	function ctx.exec(node)
		ctx.tick()
		check(node, "exec").exec(node, ctx, state)
	end

	function ctx.execBody(node, name)
		local body = node.bodies and node.bodies[name]
		if not body then return end
		for _, child in body do
			ctx.exec(child)
		end
	end

	for _, node in program do
		ctx.exec(node)
	end

	return state
end

return Interpreter
