--!strict
--[[
	EngineC_Demo
	Shows the require()-style workflow: EngineC is imported like any other
	Roblox module, and the .EngineC/.ec source file is pulled in the same way
	you'd require a ModuleScript -- except EngineC.require() reads the file's
	raw text as EngineC source instead of running it as Luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EngineC = require(ReplicatedStorage.EngineC)

print("[EngineC] loading ReplicatedStorage.BlackHoleMerger ...")

local ok, resultOrErr = pcall(function()
	return EngineC.require(ReplicatedStorage.BlackHoleMerger)
end)

if not ok then
	warn("[EngineC] failed: " .. tostring(resultOrErr))
	return
end

local result = resultOrErr
print(("[EngineC] compiled + running: %d IR ops, %d bytes of generated Luau")
	:format(#result.optimizedIr, #result.luau))
print("[EngineC] live in Workspace.EngineC_Sim")
