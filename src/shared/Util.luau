-- Small shared helpers.

local Util = {}

local idCounter = 0

function Util.newId()
	idCounter += 1
	return "n" .. idCounter
end

function Util.deepCopy(value)
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = Util.deepCopy(child)
	end
	return copy
end

return Util
