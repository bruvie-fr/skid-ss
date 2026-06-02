local Lexer = {}

local KEYWORDS = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
	["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
	["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
	["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
	["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
	["while"] = true,
}

local SYM3 = { ["..."] = true, ["//="] = true, ["..="] = true }
local SYM2 = {
	[".."] = true, ["=="] = true, ["~="] = true, ["<="] = true, [">="] = true,
	["//"] = true, ["::"] = true, ["->"] = true, ["+="] = true, ["-="] = true,
	["*="] = true, ["/="] = true, ["%="] = true, ["^="] = true,
}
local SYM1 = {
	["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["%"] = true,
	["^"] = true, ["#"] = true, ["<"] = true, [">"] = true, ["="] = true,
	["("] = true, [")"] = true, ["{"] = true, ["}"] = true, ["["] = true,
	["]"] = true, [";"] = true, [":"] = true, [","] = true, ["."] = true,
	["?"] = true, ["|"] = true, ["&"] = true,
}

local ESCAPES = {
	["n"] = "\n", ["t"] = "\t", ["r"] = "\r", ["a"] = "\a", ["b"] = "\b",
	["f"] = "\f", ["v"] = "\v", ["\\"] = "\\", ['"'] = '"', ["'"] = "'",
	["\n"] = "\n",
}

local function isDigit(c) return c >= "0" and c <= "9" end
local function isHex(c)
	return (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
end
local function isAlpha(c)
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")
end
local function isAlphaNum(c) return isAlpha(c) or isDigit(c) end

function Lexer.tokenize(src)
	local tokens = {}
	local i = 1
	local n = #src
	local line = 1

	local function err(msg)
		error({ __skidss_lex = true, message = "input:" .. line .. ": " .. msg }, 0)
	end
	local function at(k) return string.sub(src, k, k) end

	local function readLong()
		local j = i + 1
		local level = 0
		while at(j) == "=" do level += 1; j += 1 end
		if at(j) ~= "[" then return nil end
		j += 1

		if at(j) == "\r" then j += 1 end
		if at(j) == "\n" then line += 1; j += 1 end
		local closer = "]" .. string.rep("=", level) .. "]"
		local startLine = line
		local from = j
		while true do
			if j > n then line = startLine; err("unfinished long bracket") end
			local c = at(j)
			if c == "]" and string.sub(src, j, j + level + 1) == closer then
				local text = string.sub(src, from, j - 1)
				i = j + level + 2
				return text
			end
			if c == "\n" then line += 1 end
			j += 1
		end
	end

	local function readString(quote)
		local parts = {}
		i += 1
		while true do
			local c = at(i)
			if c == "" or c == "\n" then err("unfinished string") end
			if c == quote then i += 1; break end
			if c == "\\" then
				local e = at(i + 1)
				if e == "x" then
					local hex = string.sub(src, i + 2, i + 3)
					local b = tonumber(hex, 16)
					if not b then err("hexadecimal digit expected") end
					parts[#parts + 1] = string.char(b)
					i += 4
				elseif e == "z" then
					i += 2
					while at(i):match("%s") do
						if at(i) == "\n" then line += 1 end
						i += 1
					end
				elseif e == "u" then
					if at(i + 2) ~= "{" then err("missing '{' in \\u{xxxx}") end
					local j = i + 3
					while at(j) ~= "}" do
						if at(j) == "" then err("unfinished string") end
						j += 1
					end
					local cp = tonumber(string.sub(src, i + 3, j - 1), 16)
					if not cp then err("hexadecimal digit expected") end
					parts[#parts + 1] = utf8.char(cp)
					i = j + 1
				elseif isDigit(e) then
					local d = e
					local j = i + 2
					for _ = 1, 2 do
						if isDigit(at(j)) then d ..= at(j); j += 1 else break end
					end
					local b = tonumber(d)
					if b > 255 then err("decimal escape too large") end
					parts[#parts + 1] = string.char(b)
					i = j
				else
					local rep = ESCAPES[e]
					if not rep then err("invalid escape sequence '\\" .. e .. "'") end
					if e == "\n" then line += 1 end
					parts[#parts + 1] = rep
					i += 2
				end
			else
				parts[#parts + 1] = c
				i += 1
			end
		end
		return table.concat(parts)
	end

	local function readNumber()
		local start = i
		local two = string.sub(src, i, i + 1)
		if two == "0x" or two == "0X" then
			i += 2
			while i <= n and (isHex(at(i)) or at(i) == "_") do i += 1 end
		elseif two == "0b" or two == "0B" then
			i += 2
			while i <= n and (at(i) == "0" or at(i) == "1" or at(i) == "_") do i += 1 end
		else
			while i <= n and (isDigit(at(i)) or at(i) == "_") do i += 1 end
			if at(i) == "." then
				i += 1
				while i <= n and (isDigit(at(i)) or at(i) == "_") do i += 1 end
			end
			local e = at(i)
			if e == "e" or e == "E" then
				i += 1
				if at(i) == "+" or at(i) == "-" then i += 1 end
				while i <= n and isDigit(at(i)) do i += 1 end
			end
		end
		local text = string.sub(src, start, i - 1)
		local clean = string.gsub(text, "_", "")
		local value
		local prefix = string.sub(clean, 1, 2)
		if prefix == "0b" or prefix == "0B" then
			value = tonumber(string.sub(clean, 3), 2)
		else
			value = tonumber(clean)
		end
		if not value then err("malformed number near '" .. text .. "'") end
		return value
	end

	while i <= n do
		local c = at(i)
		if c == "\n" then
			line += 1; i += 1
		elseif c == " " or c == "\t" or c == "\r" or c == "\v" or c == "\f" then
			i += 1
		elseif c == "-" and at(i + 1) == "-" then

			i += 2
			if at(i) == "[" then
				local saved = i
				local text = readLong()
				if not text then i = saved; while i <= n and at(i) ~= "\n" do i += 1 end end
			else
				while i <= n and at(i) ~= "\n" do i += 1 end
			end
		elseif isAlpha(c) then
			local start = i
			while i <= n and isAlphaNum(at(i)) do i += 1 end
			local word = string.sub(src, start, i - 1)
			tokens[#tokens + 1] = {
				type = KEYWORDS[word] and "Keyword" or "Name",
				value = word,
				line = line,
			}
		elseif isDigit(c) or (c == "." and isDigit(at(i + 1))) then
			local ln = line
			tokens[#tokens + 1] = { type = "Number", value = readNumber(), line = ln }
		elseif c == '"' or c == "'" then
			local ln = line
			tokens[#tokens + 1] = { type = "String", value = readString(c), line = ln }
		elseif c == "[" and (at(i + 1) == "[" or at(i + 1) == "=") then
			local saved = i
			local ln = line
			local text = readLong()
			if text then
				tokens[#tokens + 1] = { type = "String", value = text, line = ln }
			else

				i = saved
				tokens[#tokens + 1] = { type = "Symbol", value = "[", line = line }
				i += 1
			end
		else
			local s3 = string.sub(src, i, i + 2)
			local s2 = string.sub(src, i, i + 1)
			if SYM3[s3] then
				tokens[#tokens + 1] = { type = "Symbol", value = s3, line = line }; i += 3
			elseif SYM2[s2] then
				tokens[#tokens + 1] = { type = "Symbol", value = s2, line = line }; i += 2
			elseif SYM1[c] then
				tokens[#tokens + 1] = { type = "Symbol", value = c, line = line }; i += 1
			else
				err("unexpected symbol '" .. c .. "'")
			end
		end
	end

	tokens[#tokens + 1] = { type = "Eof", value = "<eof>", line = line }
	return tokens
end

function Lexer.safeTokenize(src)
	local ok, result = pcall(Lexer.tokenize, src)
	if ok then return result end
	if type(result) == "table" and result.__skidss_lex then
		return nil, result.message
	end
	return nil, tostring(result)
end

return Lexer
