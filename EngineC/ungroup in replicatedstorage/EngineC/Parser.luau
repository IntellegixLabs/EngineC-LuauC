--!strict
--[[
	EngineC.Parser
	Stage 2 of the pipeline: recursive-descent parser that turns the Lexer's
	token stream into an AST.

	Statement shape (block / injection / bare call) is resolved via
	EngineC.Spec's command table for most commands. A few commands are
	"flexible" (used both as a leaf and as a block with children in real
	EngineC code, e.g. physics.body) -- those are resolved by indentation,
	since the grammar has no explicit block-opening delimiter: a following
	statement indented further than the flexible command's own column (and
	eventually closed by a matching 'end') makes it a block.

	Top-level declaration forms (each becomes its own deployed file --
	see EngineC.Compiler):
		public <ns.path> <name>[args] # ... end     -> Node.kind = "Function"
		class <name>[args] ... end                   -> Node.kind = "Class"
		var <name> (':' TYPE)? '=' expr               -> Node.kind = "VarDecl"
]]

local Spec = require(script.Parent.Spec)
local Lexer = require(script.Parent.Lexer)

type Token = Lexer.Token

export type Expr = { kind: string, value: any }

export type ArgNode = {
	key: string?,
	typ: string?,
	value: Expr,
}

export type Node = {
	kind: string,       -- "Block" | "Inject" | "Call" | "Assign" | "Function" | "Class" | "StaticClass" | "Enum" | "Object" | "VarDecl" | "Include" | "Using" | "PublicDataStore" | "PluginCall"
	path: string,
	op: string,
	args: { ArgNode },
	body: { Node }?,
	value: Expr?,
	typ: string?,
	line: number,
}

local Parser = {}

local function newParserState(tokens: { Token })
	local pos = 1
	local function peek(offset: number?): Token
		return tokens[pos + (offset or 0)]
	end
	local function advance(): Token
		local t = tokens[pos]
		pos += 1
		return t
	end
	local function expect(ttype: string): Token
		local t = tokens[pos]
		if t.type ~= ttype then
			error(("EngineC parse error: expected %s but got %s (%q) at line %d")
				:format(ttype, t.type, t.value, t.line))
		end
		pos += 1
		return t
	end
	return { peek = peek, advance = advance, expect = expect }
end

-- Some Lexer keywords (namespace, pipeline, etc.) also occur as ordinary
-- path segments in real EngineC code (e.g. `namespace.Physics::core::static`
-- uses "namespace" as a plain identifier, not as a distinct construct we
-- implement). Path parsing accepts either a true IDENT or one of these.
local PATH_WORD_KEYWORDS = {
	NAMESPACE = true,
	LOCAL = true,
	FUNCTION = true,
	INT = true,
	FLOAT = true,
	BOOL = true,
	STRING = true,
	VECTOR = true,
	VOID = true,
}

local function expectPathWord(s): Token
	local t = s.peek()
	if t.type == "IDENT" or PATH_WORD_KEYWORDS[t.type] then
		return s.advance()
	end
	error(("EngineC parse error: expected identifier but got %s (%q) at line %d")
		:format(t.type, t.value, t.line))
end

-- Consumes a dotted and/or ::-scoped path, e.g. `model3d.sphere`,
-- `namespace.Physics::core::static`. Both separators are accepted anywhere
-- in the chain since EngineC uses '.' for member access and '::' for
-- explicit namespace scoping.
local function parsePath(s): string
	local first = expectPathWord(s)
	local parts = { first.value }
	while s.peek().type == "DOT" or s.peek().type == "DBLCOLON" or s.peek().type == "ARROW" do
		local sepToken = s.advance().type
		local sep = if sepToken == "DOT" then "." elseif sepToken == "ARROW" then "->" else "::"
		if sep == "::" and s.peek().type == "INJECT_OPEN" then
			table.insert(parts, sep)
			break
		end
		local nxt = expectPathWord(s)
		table.insert(parts, sep .. nxt.value)
	end
	return table.concat(parts, "")
end

local function parseType(s): string
	local t = s.advance()
	local typ = t.value
	if s.peek().type == "STAR" then
		s.advance()
		typ ..= "*"
	end
	return typ
end

local function parseExpr(s): Expr
	local t = s.peek()
	if t.type == "AMP" then
		s.advance()
		local target = parsePath(s)
		return { kind = "pointer", value = target }
	elseif t.type == "LBRACE" then
		s.advance()
		local items = {}
		if s.peek().type ~= "RBRACE" then
			table.insert(items, parseExpr(s))
			while s.peek().type == "COMMA" do
				s.advance()
				table.insert(items, parseExpr(s))
			end
		end
		s.expect("RBRACE")
		return { kind = "array", value = items }
	elseif t.type == "NIL" then
		s.advance()
		return { kind = "nil", value = nil }
	elseif t.type == "STRING" then
		s.advance()
		return { kind = "string", value = t.value }
	elseif t.type == "NUMBER" then
		s.advance()
		return { kind = "number", value = tonumber(t.value) }
	elseif t.type == "TRUE" then
		s.advance()
		return { kind = "bool", value = true }
	elseif t.type == "FALSE" then
		s.advance()
		return { kind = "bool", value = false }
	elseif t.type == "IDENT" then
		local p = parsePath(s)
		return { kind = "ident", value = p }
	else
		error(("EngineC parse error: unexpected token %s in expression at line %d"):format(t.type, t.line))
	end
end

-- arg := (IDENT (':' TYPE)? '=' expr)   -- e.g. id="bh1", mass: float=5000
--      | expr ':' TYPE                  -- e.g. "solverIterations": int  (bare typed value)
--      | expr                           -- e.g. "space", "bh1", or a positional tuple component
local function parseArg(s): ArgNode
	if (s.peek().type == "IDENT" or PATH_WORD_KEYWORDS[s.peek().type])
		and (s.peek(1).type == "EQUALS" or s.peek(1).type == "COLON") then
		local key = s.advance().value
		local typ: string? = nil
		if s.peek().type == "COLON" then
			s.advance()
			typ = parseType(s)
		end
		s.expect("EQUALS")
		local value = parseExpr(s)
		return { key = key, typ = typ, value = value }
	else
		local value = parseExpr(s)
		local typ: string? = nil
		if s.peek().type == "COLON" then
			s.advance()
			typ = parseType(s)
		end
		return { key = nil, typ = typ, value = value }
	end
end

local function parseArgList(s): { ArgNode }
	s.expect("LBRACKET")
	local args: { ArgNode } = {}
	if s.peek().type ~= "RBRACKET" then
		table.insert(args, parseArg(s))
		while s.peek().type == "COMMA" do
			s.advance()
			table.insert(args, parseArg(s))
		end
	end
	s.expect("RBRACKET")
	return args
end

local parseStatement, parseStatementList

function parseStatementList(s): { Node }
	local nodes: { Node } = {}
	while true do
		local t = s.peek()
		if t.type == "END" or t.type == "EOF" then
			break
		end
		table.insert(nodes, parseStatement(s))
	end
	return nodes
end

-- public DataStore:[key] = value
local function parsePublicDataStore(s, line: number): Node
	s.expect("PUBLIC")
	local store = s.expect("IDENT").value
	s.expect("COLON")
	s.expect("LBRACKET")
	local key = parseExpr(s)
	s.expect("RBRACKET")
	s.expect("EQUALS")
	local value = parseExpr(s)
	return {
		kind = "PublicDataStore",
		path = store,
		op = "public_datastore",
		args = { { key = "key", typ = nil, value = key } },
		value = value,
		line = line,
	}
end

-- public <ns.path> <name>[args]? '#' body 'end'
local function parsePublic(s, line: number): Node
	s.expect("PUBLIC")
	local nsPath = parsePath(s)
	local name = s.expect("IDENT").value
	local args: { ArgNode } = {}
	if s.peek().type == "LBRACKET" then
		args = parseArgList(s)
	end
	s.expect("HASH")
	local body = parseStatementList(s)
	s.expect("END")
	return { kind = "Function", path = nsPath .. "." .. name, op = "function_decl", args = args, body = body, line = line }
end

-- plugin Library.member[args] invokes a function from AdditionalDependencies.
local function parsePlugin(s, line: number): Node
	s.expect("PLUGIN")
	local path = parsePath(s)
	local args: { ArgNode } = {}
	if s.peek().type == "LBRACKET" then
		args = parseArgList(s)
	end
	return { kind = "PluginCall", path = path, op = "plugin_call", args = args, line = line }
end

-- object Type [args]? property body 'end'
local function parseObject(s, line: number): Node
	s.expect("OBJECT")
	local typeName = s.expect("IDENT").value
	local args: { ArgNode } = {}
	if s.peek().type == "LBRACKET" then
		args = parseArgList(s)
	end
	local body = parseStatementList(s)
	s.expect("END")
	return { kind = "Object", path = "object." .. typeName, op = "object_create", args = args, body = body, line = line }
end

-- static class Name [args]? body 'end'
local function parseStaticClass(s, line: number): Node
	s.expect("STATIC")
	s.expect("CLASS")
	local name = s.expect("IDENT").value
	local args: { ArgNode } = {}
	if s.peek().type == "LBRACKET" then
		args = parseArgList(s)
	end
	local body = parseStatementList(s)
	s.expect("END")
	return { kind = "StaticClass", path = name, op = "static_class_decl", args = args, body = body, line = line }
end

-- enum Name [Member = value, ...]
local function parseEnum(s, line: number): Node
	s.expect("ENUM")
	local name = s.expect("IDENT").value
	local args = parseArgList(s)
	return { kind = "Enum", path = name, op = "enum_decl", args = args, line = line }
end

-- class <name>? [args]? body 'end'. Anonymous classes are only valid
-- when nested under a named class or function; IRBuilder enforces that scope.
local function parseClass(s, line: number): Node
	s.expect("CLASS")
	local name = "__anonymous_class"
	if s.peek().type == "IDENT" then
		name = s.advance().value
	end
	local args: { ArgNode } = {}
	if s.peek().type == "LBRACKET" then
		args = parseArgList(s)
	end
	local body = parseStatementList(s)
	s.expect("END")
	return { kind = "Class", path = name, op = "class_decl", args = args, body = body, line = line }
end

-- var <name> (':' TYPE)? '=' expr, or C++-style `var TYPE* <name> = expr`
local function parseVar(s, line: number): Node
	s.expect("VAR")
	local name: string
	local typ: string? = nil
	if PATH_WORD_KEYWORDS[s.peek().type] and (s.peek(1).type == "STAR" or s.peek(1).type == "IDENT") then
		typ = parseType(s)
		name = s.expect("IDENT").value
	else
		name = s.expect("IDENT").value
		if s.peek().type == "COLON" then
			s.advance()
			typ = parseType(s)
		end
	end
	s.expect("EQUALS")
	local value = parseExpr(s)
	return { kind = "VarDecl", path = name, op = "var_decl", args = {}, value = value, typ = typ, line = line }
end

-- #include Library,?
local function parseInclude(s, line: number): Node
	s.expect("HASH")
	local directive = s.expect("IDENT")
	if directive.value ~= "include" then
		error(("EngineC parse error: unknown directive #%s at line %d"):format(directive.value, line))
	end
	local library = parsePath(s)
	local hasComma = false
	if s.peek().type == "COMMA" then
		s.advance()
		hasComma = true
	end
	return {
		kind = "Include",
		path = library,
		op = "include",
		args = {},
		value = { kind = "bool", value = hasComma },
		line = line,
	}
end

-- using symbol from Library, or the built-in `using metadistro` profiler.
local function parseUsing(s, line: number): Node
	s.expect("USING")
	local symbol = parsePath(s)
	local library = symbol
	if s.peek().type == "FROM" then
		s.advance()
		library = parsePath(s)
	end
	if s.peek().type == "COMMA" then
		s.advance()
	end
	return {
		kind = "Using",
		path = library,
		op = "using",
		args = {},
		value = { kind = "ident", value = symbol },
		line = line,
	}
end

-- pipeline[ <statement list> 'end' ]   -- note: 'end' closes the body,
-- THEN ']' closes the pipeline itself, per the language spec.
local function parsePipeline(s, line: number): Node
	s.expect("PIPELINE")
	s.expect("LBRACKET")
	local body = parseStatementList(s)
	s.expect("END")
	s.expect("RBRACKET")
	return { kind = "Pipeline", path = "pipeline", op = "pipeline", args = {}, body = body, line = line }
end

-- statement := 'public' ...                                    -- Function decl
--            | 'class' ...                                     -- Class decl
--            | 'var' ...                                       -- Var decl
--            | path (':' TYPE)? '=' expr                       -- Assign
--            | path arglist? '>>' expr '<<'                    -- Inject
--            | path arglist? <indented body> 'end'             -- Block (or flexible-as-block)
--            | path arglist?                                   -- Call (or flexible-as-leaf)
function parseStatement(s): Node
	local line = s.peek().line

	if s.peek().type == "HASH" then
		return parseInclude(s, line)
	elseif s.peek().type == "USING" then
		return parseUsing(s, line)
	elseif s.peek().type == "PUBLIC" then
		if s.peek(1).type == "IDENT" and s.peek(2).type == "COLON" then
			return parsePublicDataStore(s, line)
		end
		return parsePublic(s, line)
	elseif s.peek().type == "PLUGIN" then
		return parsePlugin(s, line)
	elseif s.peek().type == "STATIC" then
		return parseStaticClass(s, line)
	elseif s.peek().type == "ENUM" then
		return parseEnum(s, line)
	elseif s.peek().type == "OBJECT" then
		return parseObject(s, line)
	elseif s.peek().type == "CLASS" then
		return parseClass(s, line)
	elseif s.peek().type == "VAR" then
		return parseVar(s, line)
	elseif s.peek().type == "PIPELINE" then
		return parsePipeline(s, line)
	end

	local startColumn = s.peek().column
	local path = parsePath(s)

	-- bare assignment form, e.g. `strength: float = 9000`
	if s.peek().type == "COLON" or s.peek().type == "EQUALS" then
		local typ: string? = nil
		if s.peek().type == "COLON" then
			s.advance()
			typ = parseType(s)
		end
		s.expect("EQUALS")
		local value = parseExpr(s)
		return { kind = "Assign", path = path, op = path, args = {}, value = value, typ = typ, line = line }
	end

	local args: { ArgNode } = {}
	if s.peek().type == "LBRACKET" then
		args = parseArgList(s)
	end

	local spec = Spec.resolve(path)
	local shape = spec.shape

	if s.peek().type == "INJECT_OPEN" then
		shape = "inject"
	end

	if shape == "inject" then
		s.expect("INJECT_OPEN")
		local value = parseExpr(s)
		s.expect("INJECT_CLOSE")
		local opName = spec.op
		if path:sub(1, 7) == "engine." then
			opName = "engine_control"
		end
		if path:match("::vector::$") then
			if value.kind ~= "array" or #value.value ~= 3 then
				error(("EngineC vector error: expected three values at line %d"):format(line))
			end
			value = { kind = "vector", value = value.value }
		end
		return { kind = "Inject", path = path, op = opName, args = args, value = value, line = line }
	elseif shape == "block" then
		local body = parseStatementList(s)
		s.expect("END")
		return { kind = "Block", path = path, op = spec.op, args = args, body = body, line = line }
	elseif shape == "flexible" then
		local nxt = s.peek()
		if nxt.type ~= "END" and nxt.type ~= "EOF" and nxt.line > line and nxt.column > startColumn then
			local body = parseStatementList(s)
			s.expect("END")
			return { kind = "Block", path = path, op = spec.op, args = args, body = body, line = line }
		else
			return { kind = "Call", path = path, op = spec.op, args = args, line = line }
		end
	else
		return { kind = "Call", path = path, op = spec.op, args = args, line = line }
	end
end

function Parser.parse(tokens: { Token }): { Node }
	local s = newParserState(tokens)
	local nodes = parseStatementList(s)
	s.expect("EOF")
	return nodes
end

return Parser
