-- Compiles every EngineC source at server startup.
local EngineC = require(game:GetService("ReplicatedStorage"):WaitForChild("EngineC"))
local seen = {}
local compiled = 0

local function compileContainer(container)
	for _, item in ipairs(container:GetDescendants()) do
		if item:IsA("ModuleScript") or item:IsA("StringValue") then
			local ok, source = pcall(function()
				return if item:IsA("StringValue") then item.Value else item.Source
			end)
			if ok and type(source) == "string" and source:match("^%s*#include%s+EngineC") and not seen[source] then
				seen[source] = true
				local result = EngineC.compile(source)
				if not result.ok then
					error("EngineC startup compile failed for " .. item:GetFullName() .. ": " .. tostring(result.error))
				end
				compiled += 1
				print("[EngineC] compiled " .. item:GetFullName())
			end
		end
	end
end

compileContainer(game:GetService("ReplicatedStorage"))
compileContainer(game:GetService("ServerStorage"))
print("[EngineC] startup compilation complete: " .. compiled .. " source(s)")