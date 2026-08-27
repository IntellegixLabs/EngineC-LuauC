--!strict
--[[
	EngineC.Compiler
	Orchestrates the full pipeline: Lexer -> Parser -> IRBuilder -> Optimizer
	-> CodeGen -> Runtime. This is the public entry point for EngineC source.
]]

local Lexer = require(script.Parent.Lexer)
local Parser = require(script.Parent.Parser)
local IRBuilder = require(script.Parent.IRBuilder)
local Optimizer = require(script.Parent.Optimizer)
local CodeGen = require(script.Parent.CodeGen)
local Runtime = require(script.Parent.Runtime)

local Compiler = {}

local function getDependencyFolder(): Instance
	local package = script.Parent.Parent
	return package:FindFirstChild("AdditionalDependencies")
		or game:GetService("ReplicatedStorage"):WaitForChild("AdditionalDependencies")
end

export type CompileResult = {
	ok: boolean,
	tokens: { any }?,
	ast: { any }?,
	ir: { any }?,
	optimizedIr: { any }?,
	luau: string?,
	error: string?,
}

-- Runs stages 1-5, returns every intermediate artifact for inspection/debugging.
function Compiler.compile(source: string): CompileResult
	local ok, result = pcall(function()
		local tokens = Lexer.tokenize(source)
		local ast = Parser.parse(tokens)
		local includes: { [string]: boolean } = {}
		local includeNodes = {}
		local hasEngineC = false
		for _, node in ipairs(ast) do
			if node.kind == "Include" then
				includes[node.path] = true
				table.insert(includeNodes, node)
				if node.path == "EngineC" then
					hasEngineC = true
				elseif not getDependencyFolder():FindFirstChild(node.path) then
					error(("EngineC include error: dependency %s was not found in AdditionalDependencies"):format(node.path))
				end
			elseif node.kind == "Using" then
				if node.path ~= "metadistro" and not includes[node.path] then
					error(("EngineC using error: %s must be included before it is used"):format(node.path))
				end
			end
		end
		if not hasEngineC then
			error("EngineC include error: every script must include EngineC")
		end
		if #includeNodes > 1 then
			local seenLines = {}
			for _, node in ipairs(includeNodes) do
				if seenLines[node.line] then
					error("EngineC include error: each #include must be on its own line")
				end
				seenLines[node.line] = true
				if not node.value or node.value.value ~= true then
					error("EngineC include error: multiple includes require a comma after each library")
				end
			end
		end
		for _, node in ipairs(ast) do
			local allowed = node.kind == "Include" or node.kind == "Using"
				or node.kind == "VarDecl" or node.kind == "Function"
				or node.kind == "Class" or node.kind == "StaticClass" or node.kind == "Enum"
			if not allowed then
				error(("EngineC structure error: top-level %s must be inside a class, variable, or function"):format(node.kind))
			end
		end
		local ir = IRBuilder.build(ast)
		local optimizedIr = Optimizer.optimize(ir)
		local luau = CodeGen.generate(optimizedIr)
		return {
			tokens = tokens,
			ast = ast,
			ir = ir,
			optimizedIr = optimizedIr,
			luau = luau,
		}
	end)

	if not ok then
		return { ok = false, error = tostring(result) }
	end

	return {
		ok = true,
		tokens = result.tokens,
		ast = result.ast,
		ir = result.ir,
		optimizedIr = result.optimizedIr,
		luau = result.luau,
	}
end

-- Compiles and immediately executes the generated Luau (stage 6: runtime layer
-- picks it up from there). Returns the compile result plus execution status.
function Compiler.run(source: string): (CompileResult, boolean, string?)
	local result = Compiler.compile(source)
	if not result.ok then
		return result, false, result.error
	end

	local function executeOp(op)
		if op.op == "sim_loop" then
			Runtime.startLoop(op.id or "anonymous", function()
				for _, child in ipairs(op.sub or {}) do
					Runtime.exec(child.op, child.id, child.parent, child.args)
				end
			end)
		elseif op.op == "engine_override" then
			Runtime.engineOverride(op.id, op.mods or {})
		elseif op.op == "event_handler" then
			Runtime.bindEvent(op.id or "event", op.args, function()
				for _, child in ipairs(op.sub or {}) do
					Runtime.exec(child.op, child.id, child.parent, child.args)
				end
			end)
		else
			Runtime.exec(op.op, op.id, op.parent, op.args)
		end
	end

	local ok, err = pcall(function()
		for _, op in ipairs(result.optimizedIr or {}) do
			executeOp(op)
		end
	end)
	if not ok then
		return result, false, "Runtime execution error: " .. tostring(err)
	end

	return result, true, nil
end

-- ===== deploy: one ServerScriptService file per top-level declaration =====
--
-- Every top-level `public ... # ... end` (Function), `class ... end` (Class),
-- and `var ... = ...` (VarDecl) compiles to its OWN Script instance under
-- ServerScriptService.ApplicationSupport, named `<name>_<kind>` (e.g.
-- "bootstrap_function", "flare_gun_function", "PlayerState_class",
-- "maxSpeed_var"). Each Script requires EngineC.Runtime itself and runs
-- immediately once parented -- that's what makes it "compiled", as opposed
-- to Compiler.run's single in-memory loadstring.
local KIND_SUFFIX = { Function = "function", Class = "class", VarDecl = "var" }

local function lastSegment(path: string): string
	return path:match("([^%.]+)$") or path
end

local function getAppSupportFolder(): Folder
	local ServerScriptService = game:GetService("ServerScriptService")
	local folder = ServerScriptService:FindFirstChild("ApplicationSupport")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ApplicationSupport"
		folder.Parent = ServerScriptService
	end
	return folder :: Folder
end

export type DeployedFile = { name: string, ok: boolean, error: string? }

-- Compiles `source` and writes one Script per top-level declaration into
-- ServerScriptService.ApplicationSupport. Returns the list of files written
-- (each already parented and, since it's a real Script, already running).
function Compiler.deploy(source: string): { DeployedFile }
	local okTok, tokensOrErr = pcall(Lexer.tokenize, source)
	if not okTok then
		return { { name = "<lex error>", ok = false, error = tostring(tokensOrErr) } }
	end
	local okAst, astOrErr = pcall(Parser.parse, tokensOrErr)
	if not okAst then
		return { { name = "<parse error>", ok = false, error = tostring(astOrErr) } }
	end

	local ast = astOrErr :: { any }
	local folder = getAppSupportFolder()
	local results: { DeployedFile } = {}

	for i, node in ipairs(ast) do
		local suffix = KIND_SUFFIX[node.kind] or "script"
		local baseName = lastSegment(node.path) .. "_" .. suffix
		local fileName = baseName

		-- Remove existing script with same name to avoid duplicates on re-deploy
		local existing = folder:FindFirstChild(fileName)
		if existing then
			existing:Destroy()
		end

		local ok, err = pcall(function()
			local ir = IRBuilder.build({ node })
			local optimized = Optimizer.optimize(ir)
			local luau = CodeGen.generateScript(optimized, baseName)

			local scr = Instance.new("Script")
			scr.Name = fileName
			scr.Parent = folder

			-- Try to set Source (works in Studio edit mode, fails at runtime)
			local srcOk = pcall(function()
				(scr :: any).Source = luau
			end)

			if not srcOk then
				-- Runtime: Source not writable, execute directly via loadstring
				scr:Destroy()
				local chunk = loadstring(luau)
				assert(chunk, "Failed to load generated Luau for " .. fileName)
				chunk()
			end
		end)

		table.insert(results, { name = fileName, ok = ok, error = if ok then nil else tostring(err) })
	end

	return results
end

return Compiler
