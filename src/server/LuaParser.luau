local Lexer = require(script.Parent.LuaLexer)

local Parser = {}

local COMPOUND = {
	["+="] = "+", ["-="] = "-", ["*="] = "*", ["/="] = "/", ["//="] = "//",
	["%="] = "%", ["^="] = "^", ["..="] = "..",
}

local BINPRI = {
	["or"] = { 1, 1 }, ["and"] = { 2, 2 },
	["<"] = { 3, 3 }, [">"] = { 3, 3 }, ["<="] = { 3, 3 }, [">="] = { 3, 3 },
	["~="] = { 3, 3 }, ["=="] = { 3, 3 },
	[".."] = { 9, 8 },
	["+"] = { 10, 10 }, ["-"] = { 10, 10 },
	["*"] = { 11, 11 }, ["/"] = { 11, 11 }, ["//"] = { 11, 11 }, ["%"] = { 11, 11 },
	["^"] = { 14, 13 },
}
local UNARY_PRI = 12

function Parser.parse(tokens)
	local pos = 1

	local function cur() return tokens[pos] end
	local function peek(off) return tokens[pos + off] end
	local function advance() local t = tokens[pos]; pos += 1; return t end

	local function isSym(t, v) return t ~= nil and t.type == "Symbol" and t.value == v end
	local function isKw(t, v) return t ~= nil and t.type == "Keyword" and t.value == v end
	local function checkSym(v) return isSym(cur(), v) end
	local function checkKw(v) return isKw(cur(), v) end
	local function acceptSym(v) if checkSym(v) then return advance() end return nil end
	local function acceptKw(v) if checkKw(v) then return advance() end return nil end

	local function perror(msg, tok)
		tok = tok or cur()
		error({ __skidss_parse = true, message = "input:" .. (tok and tok.line or 0) .. ": " .. msg }, 0)
	end
	local function expectSym(v) if not checkSym(v) then perror("'" .. v .. "' expected") end return advance() end
	local function expectKw(v) if not checkKw(v) then perror("'" .. v .. "' expected") end return advance() end
	local function expectName()
		local t = cur()
		if t.type ~= "Name" then perror("<name> expected") end
		pos += 1
		return t.value
	end

	local parseExpr, parseBlock, parseStatement, parseFuncBody, skipType

	local function skipBalanced()
		local matching = { ["("] = ")", ["{"] = "}", ["["] = "]", ["<"] = ">" }
		local stack = {}
		repeat
			local t = advance()
			if t.type == "Eof" then perror("unfinished type annotation") end
			if t.type == "Symbol" then
				if matching[t.value] then
					stack[#stack + 1] = matching[t.value]
				elseif t.value == stack[#stack] then
					stack[#stack] = nil
				end
			end
		until #stack == 0
	end

	local function skipTypePrimary()
		local t = cur()
		if isSym(t, "(") or isSym(t, "{") then
			skipBalanced()
		elseif t.type == "Name" then
			advance()
			while acceptSym(".") do expectName() end
			if checkSym("<") then skipBalanced() end
		elseif t.type == "String" or t.type == "Number" then
			advance()
		elseif isKw(t, "nil") or isKw(t, "true") or isKw(t, "false") then
			advance()
		elseif isKw(t, "function") then
			advance()
			if checkSym("<") then skipBalanced() end
			if checkSym("(") then skipBalanced() end
			if acceptSym("->") then skipType() end
		else
			perror("type annotation not supported in this interpreter (v1)")
		end
	end

	function skipType()
		skipTypePrimary()
		while acceptSym("?") do end
		while checkSym("|") or checkSym("&") do
			advance(); skipTypePrimary(); while acceptSym("?") do end
		end
		if acceptSym("->") then skipType() end
	end

	local function parseExprList()
		local list = { parseExpr() }
		while acceptSym(",") do list[#list + 1] = parseExpr() end
		return list
	end

	local function parseTableConstructor()
		local line = cur().line
		expectSym("{")
		local fields = {}
		while not checkSym("}") do
			if checkSym("[") then
				advance()
				local k = parseExpr()
				expectSym("]"); expectSym("=")
				fields[#fields + 1] = { type = "rec", key = k, value = parseExpr() }
			elseif cur().type == "Name" and isSym(peek(1), "=") then
				local name = advance().value
				advance()
				fields[#fields + 1] = { type = "named", name = name, value = parseExpr() }
			else
				fields[#fields + 1] = { type = "item", value = parseExpr() }
			end
			if not (acceptSym(",") or acceptSym(";")) then break end
		end
		expectSym("}")
		return { kind = "Table", fields = fields, line = line }
	end

	local function parseArgs()
		if checkSym("(") then
			advance()
			local args = {}
			if not checkSym(")") then args = parseExprList() end
			expectSym(")")
			return args
		elseif cur().type == "String" then
			local t = advance()
			return { { kind = "String", value = t.value, line = t.line } }
		elseif checkSym("{") then
			return { parseTableConstructor() }
		end
		perror("function arguments expected")
	end

	local function parsePrimary()
		local t = cur()
		if isSym(t, "(") then
			advance()
			local e = parseExpr()
			expectSym(")")
			return { kind = "Paren", expr = e, line = t.line }
		elseif t.type == "Name" then
			advance()
			return { kind = "Name", name = t.value, line = t.line }
		end
		perror("unexpected symbol near '" .. tostring(t.value) .. "'")
	end

	local function parseSuffixed()
		local e = parsePrimary()
		while true do
			local t = cur()
			if isSym(t, ".") then
				advance()
				local name = expectName()
				e = { kind = "Index", obj = e, index = { kind = "String", value = name, line = t.line }, field = name, line = t.line }
			elseif isSym(t, "[") then
				advance()
				local k = parseExpr()
				expectSym("]")
				e = { kind = "Index", obj = e, index = k, line = t.line }
			elseif isSym(t, ":") then
				advance()
				local m = expectName()
				e = { kind = "MethodCall", obj = e, method = m, args = parseArgs(), line = t.line }
			elseif isSym(t, "(") or isSym(t, "{") or t.type == "String" then
				e = { kind = "Call", func = e, args = parseArgs(), line = t.line }
			else
				break
			end
		end
		return e
	end

	local function parseSimple()
		local t = cur()
		if t.type == "Number" then advance(); return { kind = "Number", value = t.value, line = t.line }
		elseif t.type == "String" then advance(); return { kind = "String", value = t.value, line = t.line }
		elseif isKw(t, "nil") then advance(); return { kind = "Nil", line = t.line }
		elseif isKw(t, "true") then advance(); return { kind = "True", line = t.line }
		elseif isKw(t, "false") then advance(); return { kind = "False", line = t.line }
		elseif isSym(t, "...") then advance(); return { kind = "Vararg", line = t.line }
		elseif isSym(t, "{") then return parseTableConstructor()
		elseif isKw(t, "function") then
			advance()
			local fb = parseFuncBody()
			return { kind = "Function", params = fb.params, isVararg = fb.isVararg, body = fb.body, line = t.line }
		end
		return parseSuffixed()
	end

	local function binOpOf(t)
		if t.type == "Symbol" and BINPRI[t.value] then return t.value end
		if t.type == "Keyword" and (t.value == "and" or t.value == "or") then return t.value end
		return nil
	end

	local function parseSubExpr(limit)
		local e
		local t = cur()
		if (t.type == "Symbol" and (t.value == "-" or t.value == "#")) or isKw(t, "not") then
			advance()
			e = { kind = "Unop", op = t.value, operand = parseSubExpr(UNARY_PRI), line = t.line }
		else
			e = parseSimple()
		end
		while true do
			local op = binOpOf(cur())
			if not op then break end
			local pri = BINPRI[op]
			if pri[1] <= limit then break end
			local opTok = advance()
			e = { kind = "Binop", op = op, lhs = e, rhs = parseSubExpr(pri[2]), line = opTok.line }
		end
		return e
	end

	function parseExpr()
		local e = parseSubExpr(0)
		while acceptSym("::") do skipType() end
		return e
	end

	function parseFuncBody()
		if checkSym("<") then skipBalanced() end
		expectSym("(")
		local params = {}
		local isVararg = false
		if not checkSym(")") then
			while true do
				if checkSym("...") then
					advance(); isVararg = true
					if acceptSym(":") then skipType() end
					break
				end
				local nm = expectName()
				if acceptSym(":") then skipType() end
				params[#params + 1] = nm
				if not acceptSym(",") then break end
			end
		end
		expectSym(")")
		if acceptSym(":") then skipType() end
		local body = parseBlock()
		expectKw("end")
		return { params = params, isVararg = isVararg, body = body }
	end

	local function parseLocal()
		local line = cur().line
		expectKw("local")
		if acceptKw("function") then
			local name = expectName()
			local fb = parseFuncBody()
			return {
				kind = "LocalFunction",
				name = name,
				func = { kind = "Function", params = fb.params, isVararg = fb.isVararg, body = fb.body, line = line },
				line = line,
			}
		end
		local names = {}
		while true do
			names[#names + 1] = expectName()
			if acceptSym("<") then expectName(); expectSym(">") end
			if acceptSym(":") then skipType() end
			if not acceptSym(",") then break end
		end
		local exprs = {}
		if acceptSym("=") then exprs = parseExprList() end
		return { kind = "Local", names = names, exprs = exprs, line = line }
	end

	local function parseIf()
		local line = cur().line
		expectKw("if")
		local clauses = {}
		local cond = parseExpr()
		expectKw("then")
		clauses[#clauses + 1] = { cond = cond, body = parseBlock() }
		while checkKw("elseif") do
			advance()
			local c = parseExpr()
			expectKw("then")
			clauses[#clauses + 1] = { cond = c, body = parseBlock() }
		end
		local elseBody = nil
		if acceptKw("else") then elseBody = parseBlock() end
		expectKw("end")
		return { kind = "If", clauses = clauses, elseBody = elseBody, line = line }
	end

	local function parseWhile()
		local line = cur().line
		expectKw("while")
		local cond = parseExpr()
		expectKw("do")
		local body = parseBlock()
		expectKw("end")
		return { kind = "While", cond = cond, body = body, line = line }
	end

	local function parseRepeat()
		local line = cur().line
		expectKw("repeat")
		local body = parseBlock()
		expectKw("until")
		return { kind = "Repeat", body = body, cond = parseExpr(), line = line }
	end

	local function parseFor()
		local line = cur().line
		expectKw("for")
		local n1 = expectName()
		if acceptSym(":") then skipType() end
		if acceptSym("=") then
			local startE = parseExpr()
			expectSym(",")
			local stopE = parseExpr()
			local stepE = nil
			if acceptSym(",") then stepE = parseExpr() end
			expectKw("do")
			local body = parseBlock()
			expectKw("end")
			return { kind = "NumericFor", var = n1, start = startE, stop = stopE, step = stepE, body = body, line = line }
		end
		local names = { n1 }
		while acceptSym(",") do
			names[#names + 1] = expectName()
			if acceptSym(":") then skipType() end
		end
		expectKw("in")
		local exprs = parseExprList()
		expectKw("do")
		local body = parseBlock()
		expectKw("end")
		return { kind = "GenericFor", names = names, exprs = exprs, body = body, line = line }
	end

	local function parseFunctionStat()
		local line = cur().line
		expectKw("function")
		local target = { kind = "Name", name = expectName(), line = line }
		while acceptSym(".") do
			local f = expectName()
			target = { kind = "Index", obj = target, index = { kind = "String", value = f, line = line }, field = f, line = line }
		end
		local isMethod = false
		if acceptSym(":") then
			local m = expectName()
			target = { kind = "Index", obj = target, index = { kind = "String", value = m, line = line }, field = m, line = line }
			isMethod = true
		end
		local fb = parseFuncBody()
		if isMethod then table.insert(fb.params, 1, "self") end
		return {
			kind = "Assign",
			targets = { target },
			exprs = { { kind = "Function", params = fb.params, isVararg = fb.isVararg, body = fb.body, line = line } },
			line = line,
		}
	end

	local function parseExprStatement()
		local first = parseSuffixed()
		local t = cur()
		if isSym(t, "=") or isSym(t, ",") then
			local targets = { first }
			while acceptSym(",") do targets[#targets + 1] = parseSuffixed() end
			expectSym("=")
			local exprs = parseExprList()
			for _, tg in ipairs(targets) do
				if tg.kind ~= "Name" and tg.kind ~= "Index" then perror("cannot assign to this expression", tg) end
			end
			return { kind = "Assign", targets = targets, exprs = exprs, line = first.line }
		elseif t.type == "Symbol" and COMPOUND[t.value] then
			advance()
			if first.kind ~= "Name" and first.kind ~= "Index" then perror("cannot assign to this expression", first) end
			return { kind = "CompoundAssign", op = COMPOUND[t.value], target = first, expr = parseExpr(), line = t.line }
		end
		if first.kind ~= "Call" and first.kind ~= "MethodCall" then
			perror("syntax error near '" .. tostring(t.value) .. "'")
		end
		return { kind = "CallStat", call = first, line = first.line }
	end

	local function continueIsStatement()
		local nxt = peek(1)
		if nxt == nil or nxt.type == "Eof" then return true end
		if nxt.type == "String" then return false end
		if nxt.type == "Symbol" then
			local v = nxt.value
			if v == "=" or v == "," or v == "." or v == "[" or v == "(" or v == "{"
				or v == ":" or COMPOUND[v] then
				return false
			end
		end
		return true
	end

	function parseStatement()
		local t = cur()
		if isSym(t, ";") then advance(); return nil end
		if t.type == "Keyword" then
			local kw = t.value
			if kw == "local" then return parseLocal()
			elseif kw == "if" then return parseIf()
			elseif kw == "while" then return parseWhile()
			elseif kw == "for" then return parseFor()
			elseif kw == "repeat" then return parseRepeat()
			elseif kw == "do" then
				advance()
				local body = parseBlock()
				expectKw("end")
				return { kind = "Do", body = body, line = t.line }
			elseif kw == "function" then return parseFunctionStat()
			elseif kw == "break" then advance(); return { kind = "Break", line = t.line }
			end
			perror("unexpected keyword '" .. kw .. "'")
		end
		if t.type == "Name" and t.value == "continue" and continueIsStatement() then
			advance()
			return { kind = "Continue", line = t.line }
		end
		return parseExprStatement()
	end

	local function isBlockEnd(t)
		return t.type == "Eof" or isKw(t, "end") or isKw(t, "else")
			or isKw(t, "elseif") or isKw(t, "until")
	end

	function parseBlock()
		local stmts = {}
		while not isBlockEnd(cur()) do
			local t = cur()
			if isKw(t, "return") then
				advance()
				local exprs = {}
				if not (isBlockEnd(cur()) or checkSym(";")) then exprs = parseExprList() end
				acceptSym(";")
				stmts[#stmts + 1] = { kind = "Return", exprs = exprs, line = t.line }
				break
			end
			local s = parseStatement()
			if s then stmts[#stmts + 1] = s end
		end
		return stmts
	end

	local ok, result = pcall(function()
		local body = parseBlock()
		if cur().type ~= "Eof" then
			perror("'<eof>' expected near '" .. tostring(cur().value) .. "'")
		end
		return body
	end)
	if ok then return result end
	if type(result) == "table" and result.__skidss_parse then return nil, result.message end
	return nil, tostring(result)
end

return Parser
