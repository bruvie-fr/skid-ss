-- Server entry point: builds the remotes, gates every request behind the
-- whitelist, and hands valid requests to the executor on a fresh thread.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- De-dupe: if another SkidSS install already set up the remotes, this is a
-- duplicate copy (e.g. the model was imported twice) — stop so only one runs.
if ReplicatedStorage:FindFirstChild("SkidSS_Net") then
	return
end

local Shared = ReplicatedStorage:WaitForChild("SkidSS")
local Net = require(Shared.Net)

local Whitelist = require(script.Whitelist)
local Executor = require(script.Executor)

-- Customization slots. The bundler strips these markers and injects the user's
-- Studio output in their place before shipping. Rojo dev mode keeps the defaults
-- and loads the client from StarterPlayerScripts.
-- BUNDLE:CUSTOM_RUNTIME_BEGIN
local CustomRuntime = {
	onPlayerAdded = function(_player) end,
	onPlayerRemoving = function(_player) end,
	onRequestReceived = function(_player, _payload) return true end,
	customActions = {},
}
-- BUNDLE:CUSTOM_RUNTIME_END

local folder = Net.build()
local requestAccess = folder:FindFirstChild(Net.RequestAccess)
local execute = folder:FindFirstChild(Net.Execute)
local output = folder:FindFirstChild(Net.Output)

requestAccess.OnServerInvoke = function(player)
	return Whitelist.isAllowed(player)
end

local lastRun = {}

-- BUNDLE:INJECT_BEGIN
-- In Rojo dev mode the client comes from StarterPlayerScripts, so injection
-- is a no-op. The bundler replaces this block with a self-cloning version
-- that flips RunContext to Client and parents the clone to PlayerGui.
local function injectClient(_player) end
-- BUNDLE:INJECT_END

execute.OnServerEvent:Connect(function(player, payload)
	if not Whitelist.isAllowed(player) or type(payload) ~= "table" then
		return
	end

	local now = os.clock()
	if lastRun[player] and now - lastRun[player] < 0.25 then
		return
	end
	lastRun[player] = now

	local allowed = true
	local hookOk, hookRet = pcall(CustomRuntime.onRequestReceived, player, payload)
	if hookOk then allowed = hookRet ~= false end
	if not allowed then
		output:FireClient(player, "\u{2717} rejected by custom runtime")
		return
	end

	local function emit(text)
		output:FireClient(player, tostring(text))
	end

	task.spawn(function()
		local ok, message = Executor.run(player, payload, emit, CustomRuntime)
		emit((ok and "\u{2713} " or "\u{2717} ") .. tostring(message))
	end)
end)

local function onJoin(player)
	if Whitelist.isAllowed(player) then
		injectClient(player)
	end
	pcall(CustomRuntime.onPlayerAdded, player)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(onJoin, player)
end)

for _, player in Players:GetPlayers() do
	task.spawn(onJoin, player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRun[player] = nil
	pcall(CustomRuntime.onPlayerRemoving, player)
end)
