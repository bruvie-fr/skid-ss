local Players = game:GetService("Players")

local ServerApi = {}

function ServerApi.new(emit)
	local api = {}

	function api.print(text)
		emit(text)
		print("[SkidSS] " .. text)
	end

	function api.warn(text)
		emit("[warn] " .. text)
		warn("[SkidSS] " .. text)
	end

	function api.players()
		return Players:GetPlayers()
	end

	function api.findPlayer(name)
		name = string.lower(tostring(name))
		for _, player in Players:GetPlayers() do
			if string.lower(player.Name) == name then
				return player
			end
		end
		return nil
	end

	function api.kick(player, reason)
		player:Kick(reason)
	end

	local function humanoidOf(player)
		local character = player.Character
		return character and character:FindFirstChildOfClass("Humanoid")
	end

	function api.setWalkSpeed(player, value)
		local humanoid = humanoidOf(player)
		if humanoid then humanoid.WalkSpeed = value end
	end

	function api.setHealth(player, value)
		local humanoid = humanoidOf(player)
		if humanoid then humanoid.Health = value end
	end

	function api.teleport(player, dest)
		local character = player.Character
		local destCharacter = dest.Character
		if character and destCharacter then
			character:PivotTo(destCharacter:GetPivot())
		end
	end

	return api
end

return ServerApi
