local ReplicatedStorage = game:GetService("ReplicatedStorage")
local reportEvent = ReplicatedStorage:WaitForChild("EngineC_MetaDistroReport", 30)
if not reportEvent then
	return
end

local counts = { 8, 24, 56, 110, 220 }
local passed = 0
for _, count in ipairs(counts) do
	local folder = Instance.new("Folder")
	folder.Name = "MetaDistroClientBenchmark"
	folder.Parent = workspace
	local started = os.clock()
	for index = 1, count do
		local part = Instance.new("Part")
		part.Size = Vector3.new(2, 2, 2)
		part.Transparency = 1
		part.CastShadow = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Parent = folder
	end
	local elapsed = os.clock() - started
	folder:Destroy()
	if elapsed <= count * 0.0015 then
		passed += 1
	end
end

reportEvent:FireServer(passed / #counts)