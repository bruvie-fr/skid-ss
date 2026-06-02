local HttpService = game:GetService("HttpService")

local Whitelist = {}

Whitelist.UserIds = {

}

Whitelist.Names = {

}

Whitelist.Url = nil

local live = { userIds = {}, names = {} }
local lastFetch = 0
local CACHE_SECONDS = 15

local function fetch()
	if not Whitelist.Url or Whitelist.Url == "" then return end
	local ok, body = pcall(function() return HttpService:GetAsync(Whitelist.Url) end)
	if not ok then return end
	local decoded
	ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
	if not ok or type(decoded) ~= "table" then return end
	local ids, names = {}, {}
	for _, id in ipairs(decoded.userIds or {}) do
		local n = tonumber(id)
		if n then ids[n] = true end
	end
	for _, nm in ipairs(decoded.names or {}) do
		if type(nm) == "string" then names[string.lower(nm)] = true end
	end
	live = { userIds = ids, names = names }
	lastFetch = os.clock()
end

function Whitelist.refresh()
	fetch()
end

function Whitelist.refreshIfStale()
	if os.clock() - lastFetch > CACHE_SECONDS then fetch() end
end

function Whitelist.isAllowed(player)
	if Whitelist.UserIds[player.UserId] then return true end
	if Whitelist.Names[string.lower(player.Name)] then return true end
	if live.userIds[player.UserId] then return true end
	if live.names[string.lower(player.Name)] then return true end
	return false
end

return Whitelist
