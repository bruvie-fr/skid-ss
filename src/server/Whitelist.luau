-- Who is allowed to open and use the executor. This module lives in
-- ServerScriptService, which never replicates to clients, so the list stays private.
-- UserIds are the safe choice (names can be changed); names are lower-cased.

local Whitelist = {}

-- BUNDLE:WHITELIST_DEFAULTS_BEGIN
Whitelist.UserIds = {
	-- [123456789] = true,
}

Whitelist.Names = {
	-- ["yourusername"] = true,
}
-- BUNDLE:WHITELIST_DEFAULTS_END

function Whitelist.isAllowed(player)
	if Whitelist.UserIds[player.UserId] then
		return true
	end
	if Whitelist.Names[string.lower(player.Name)] then
		return true
	end
	return false
end

return Whitelist
