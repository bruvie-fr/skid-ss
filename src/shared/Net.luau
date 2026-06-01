-- Remote object names, plus build (server) and get (client) helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Config)

local Net = {}

Net.RequestAccess = "RequestAccess"
Net.Execute = "Execute"
Net.Output = "Output"

function Net.build()
	local folder = Instance.new("Folder")
	folder.Name = Config.NetFolder

	local request = Instance.new("RemoteFunction")
	request.Name = Net.RequestAccess
	request.Parent = folder

	local execute = Instance.new("RemoteEvent")
	execute.Name = Net.Execute
	execute.Parent = folder

	local output = Instance.new("RemoteEvent")
	output.Name = Net.Output
	output.Parent = folder

	folder.Parent = ReplicatedStorage
	return folder
end

function Net.get(name)
	local folder = ReplicatedStorage:WaitForChild(Config.NetFolder)
	return folder:WaitForChild(name)
end

return Net
