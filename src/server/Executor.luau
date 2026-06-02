local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("SkidSS")
local Config = require(Shared.Config)
local Interpreter = require(Shared.blocks.Interpreter)
local ServerApi = require(script.Parent.ServerApi)
local LuaInterp = require(script.Parent.LuaInterp)

local Executor = {}

local SERVER_ALLOW = { server = true, both = true }

local function runLua(source, emit)

	return LuaInterp.run(source, { emit = emit, limits = Config.Limits })
end

function Executor.run(player, payload, emit, runtime)
	if type(payload) ~= "table" then
		return false, "no payload"
	end
	if payload.mode == "lua" then
		if type(payload.source) ~= "string" then
			return false, "no source"
		end
		return runLua(payload.source, emit)
	elseif payload.mode == "blocks" then
		if type(payload.program) ~= "table" then
			return false, "no program"
		end
		local ok, err = pcall(Interpreter.run, payload.program, ServerApi.new(emit), Config, SERVER_ALLOW)
		if not ok then
			return false, "block error: " .. tostring(err)
		end
		return true, "ran"
	elseif payload.mode == "action" then
		local actions = runtime and runtime.customActions or {}
		local action = actions[payload.name]
		if type(action) ~= "function" then
			return false, "unknown action: " .. tostring(payload.name)
		end
		local ok, err = pcall(action, player, payload.args, emit)
		if not ok then
			return false, "action error: " .. tostring(err)
		end
		return true, "ran"
	end
	return false, "unknown mode"
end

return Executor
