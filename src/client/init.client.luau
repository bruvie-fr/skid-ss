local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("SkidSS")
local Net = require(Shared.Net)

local CustomInterface = function() return {} end

local allowed = Net.get(Net.RequestAccess):InvokeServer()
if not allowed then
	return
end

local cfg = {}
local ok, result = pcall(CustomInterface)
if ok and type(result) == "table" then
	cfg = result
end

local Window = require(script.ui.Window)
Window.mount(cfg)
