-- Runs a request: either raw Luau (loadstring) or a block program (interpreter).
-- Block programs are always safe to run; raw Luau needs the game owner to enable
-- ServerScriptService.LoadStringEnabled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("SkidSS")
local Config = require(Shared.Config)
local Interpreter = require(Shared.blocks.Interpreter)
local ServerApi = require(script.Parent.ServerApi)

local Executor = {}

local SERVER_ALLOW = { server = true, both = true }

local function collect(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	return table.concat(parts, " ")
end

local function runLua(source, emit)
	local sandbox = setmetatable({
		print = function(...) emit(collect(...)) end,
		warn = function(...) emit("[warn] " .. collect(...)) end,
	}, { __index = getfenv() })

	local ok, fn, compileError = pcall(loadstring, source)
	if not ok then
		return false, "loadstring is disabled — enable ServerScriptService.LoadStringEnabled, or use blocks"
	end
	if not fn then
		local message = tostring(compileError)
		if string.find(message, "not available") or string.find(message, "disabled") then
			return false, "loadstring is disabled — enable ServerScriptService.LoadStringEnabled, or use blocks"
		end
		return false, "compile error: " .. message
	end

	setfenv(fn, sandbox)
	local ran, runtimeError = pcall(fn)
	if not ran then
		return false, "runtime error: " .. tostring(runtimeError)
	end
	return true, "ran"
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
