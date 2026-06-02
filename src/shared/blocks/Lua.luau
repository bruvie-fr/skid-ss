local Defs = require(script.Parent.Defs)

local Lua = {}

local function q(text)
	return string.format("%q", tostring(text))
end

local function compileValue(node)
	if type(node) ~= "table" then return "nil" end
	local def = Defs.byId[node.type]
	if not def or not def.toLua then return "nil" end
	return def.toLua(node, {
		q = q,
		in_ = function(name) return compileValue(node.inputs and node.inputs[name]) end,
		field = function(name) return node.fields and node.fields[name] end,
	})
end

local function compileNode(node, indent)
	local def = Defs.byId[node.type]
	if not def or not def.toLua then
		return string.rep("\t", indent) .. "-- unknown block"
	end
	return def.toLua(node, {
		q = q,
		pad = string.rep("\t", indent),
		in_ = function(name) return compileValue(node.inputs and node.inputs[name]) end,
		field = function(name) return node.fields and node.fields[name] end,
		body = function(name)
			local lines = {}
			local body = node.bodies and node.bodies[name]
			if body then
				for _, child in body do
					table.insert(lines, compileNode(child, indent + 1))
				end
			end
			return table.concat(lines, "\n")
		end,
	})
end

local PREAMBLE = table.concat({
	'local Players = game:GetService("Players")',
	"local _vars = {}",
	"local function _findPlayer(name)",
	"\tfor _, p in Players:GetPlayers() do",
	"\t\tif string.lower(p.Name) == string.lower(name) then return p end",
	"\tend",
	"\treturn nil",
	"end",
	"",
}, "\n")

function Lua.compile(program)
	local lines = {}
	for _, node in program do
		table.insert(lines, compileNode(node, 0))
	end
	return PREAMBLE .. "\n" .. table.concat(lines, "\n")
end

return Lua
