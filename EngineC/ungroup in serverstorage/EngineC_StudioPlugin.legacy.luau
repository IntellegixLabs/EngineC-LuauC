-- EngineC Script Editor Studio plugin.
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EngineC = require(ReplicatedStorage:WaitForChild("EngineC"))

if not plugin then
	warn("EngineC_StudioPlugin must be exported and installed as a Studio local plugin")
	return
end

local toolbar = plugin:CreateToolbar("EngineC")
local openButton = toolbar:CreateButton("EngineCScriptEditor", "Open EngineC Script Editor", "")
openButton.ClickableWhenViewportHidden = true

local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, true, true, 820, 720, 480, 360)
local widget = plugin:CreateDockWidgetPluginGui("EngineC_ScriptEditor", info)
widget.Title = "EngineC Script Editor"

local colors = {
	background = Color3.fromRGB(30, 30, 30),
	panel = Color3.fromRGB(37, 37, 38),
	gutter = Color3.fromRGB(45, 45, 46),
	input = Color3.fromRGB(30, 30, 30),
	text = Color3.fromRGB(255, 255, 255),
	muted = Color3.fromRGB(133, 133, 133),
	purple = Color3.fromRGB(197, 134, 192),
	blue = Color3.fromRGB(86, 156, 214),
	green = Color3.fromRGB(106, 153, 85),
	orange = Color3.fromRGB(206, 145, 120),
}

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = colors.background
root.BorderSizePixel = 0
root.Parent = widget

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundColor3 = colors.panel
header.BorderSizePixel = 0
header.Parent = root

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.5, -16, 1, 0)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Text = "ENGINEC SCRIPT EDITOR"
title.TextColor3 = colors.text
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local status = Instance.new("TextLabel")
status.Size = UDim2.new(0.5, -16, 1, 0)
status.Position = UDim2.new(0.5, 4, 0, 0)
status.BackgroundTransparency = 1
status.TextColor3 = colors.muted
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Right
status.TextTruncate = Enum.TextTruncate.AtEnd
status.Text = "Select an EngineC script"
status.Parent = header

local codePanel = Instance.new("Frame")
codePanel.Position = UDim2.fromOffset(8, 84)
codePanel.Size = UDim2.new(1, -16, 1, -160)
codePanel.BackgroundColor3 = colors.input
codePanel.BorderSizePixel = 0
codePanel.Parent = root

local lineNumbers = Instance.new("TextLabel")
lineNumbers.Position = UDim2.fromOffset(0, 0)
lineNumbers.Size = UDim2.new(0, 48, 1, 0)
lineNumbers.BackgroundColor3 = colors.gutter
lineNumbers.BorderSizePixel = 0
lineNumbers.TextColor3 = colors.muted
lineNumbers.Font = Enum.Font.Code
lineNumbers.TextSize = 14
lineNumbers.TextXAlignment = Enum.TextXAlignment.Right
lineNumbers.TextYAlignment = Enum.TextYAlignment.Top
lineNumbers.TextWrapped = false
lineNumbers.Text = "1"
lineNumbers.Parent = codePanel

local syntaxHighlight = Instance.new("TextLabel")
syntaxHighlight.Position = UDim2.fromOffset(60, 8)
syntaxHighlight.Size = UDim2.new(1, -68, 1, -16)
syntaxHighlight.BackgroundTransparency = 1
syntaxHighlight.TextColor3 = colors.text
syntaxHighlight.Font = Enum.Font.Code
syntaxHighlight.TextSize = 14
syntaxHighlight.TextXAlignment = Enum.TextXAlignment.Left
syntaxHighlight.TextYAlignment = Enum.TextYAlignment.Top
syntaxHighlight.TextWrapped = false
syntaxHighlight.RichText = true
syntaxHighlight.Active = false
syntaxHighlight.Visible = true
syntaxHighlight.ZIndex = 1
syntaxHighlight.Text = ""
syntaxHighlight.Parent = codePanel

local editor = Instance.new("TextBox")
editor.Position = UDim2.fromOffset(60, 8)
editor.Size = UDim2.new(1, -68, 1, -16)
editor.BackgroundTransparency = 1
editor.TextColor3 = Color3.fromRGB(255, 255, 255)
editor.TextTransparency = 1
editor.Font = Enum.Font.Code
editor.TextSize = 14
editor.TextXAlignment = Enum.TextXAlignment.Left
editor.TextYAlignment = Enum.TextYAlignment.Top
editor.TextWrapped = false
editor.MultiLine = true
editor.ClearTextOnFocus = false
editor.PlaceholderText = "Write EngineC here..."
editor.Text = ""
editor.ZIndex = 2
editor.Parent = codePanel

local syntaxBar = Instance.new("Frame")
syntaxBar.Position = UDim2.fromOffset(8, 50)
syntaxBar.Size = UDim2.new(1, -16, 0, 26)
syntaxBar.BackgroundColor3 = colors.panel
syntaxBar.BorderSizePixel = 0
syntaxBar.Parent = root

local function syntaxChip(text, color, x)
	local chip = Instance.new("TextLabel")
	chip.Position = UDim2.fromOffset(x, 0)
	chip.Size = UDim2.fromOffset(92, 28)
	chip.BackgroundTransparency = 1
	chip.Text = text
	chip.TextColor3 = color
	chip.TextSize = 12
	chip.Font = Enum.Font.Code
	chip.TextXAlignment = Enum.TextXAlignment.Left
	chip.Parent = syntaxBar
end

syntaxChip("int  number", colors.purple, 10)
syntaxChip("class  var", colors.blue, 106)
syntaxChip("string", colors.green, 202)
syntaxChip("engine.*", colors.orange, 298)

local suggestionLabel = Instance.new("TextLabel")
suggestionLabel.Position = UDim2.fromOffset(410, 0)
suggestionLabel.Size = UDim2.new(1, -420, 1, 0)
suggestionLabel.BackgroundTransparency = 1
suggestionLabel.TextColor3 = colors.muted
suggestionLabel.TextSize = 12
suggestionLabel.Font = Enum.Font.Code
suggestionLabel.TextXAlignment = Enum.TextXAlignment.Right
suggestionLabel.Text = ""
suggestionLabel.Parent = syntaxBar

local parseButton = Instance.new("TextButton")
parseButton.Text = "Parse"
parseButton.Position = UDim2.new(0, 8, 1, -36)
parseButton.Size = UDim2.fromOffset(82, 28)
parseButton.BackgroundColor3 = colors.blue
parseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
parseButton.BorderSizePixel = 0
parseButton.Parent = root

local exportButton = Instance.new("TextButton")
exportButton.Text = "Export to Luau"
exportButton.Position = UDim2.new(0, 98, 1, -36)
exportButton.Size = UDim2.fromOffset(120, 28)
exportButton.BackgroundColor3 = Color3.fromRGB(78, 122, 78)
exportButton.TextColor3 = Color3.fromRGB(255, 255, 255)
exportButton.BorderSizePixel = 0
exportButton.Parent = root

local keywordColors = {
	class = "#569CD6",
	static = "#569CD6",
	enum = "#569CD6",
	var = "#569CD6",
	public = "#569CD6",
	["function"] = "#569CD6",
	["end"] = "#569CD6",
	["if"] = "#C586C0",
	["else"] = "#C586C0",
	maybe = "#C586C0",
	["nil"] = "#C586C0",
	int = "#C586C0",
	void = "#C586C0",
	["true"] = "#569CD6",
	["false"] = "#569CD6",
	object = "#569CD6",
	on = "#DCDCAA",
	include = "#C586C0",
	using = "#C586C0",
	from = "#C586C0",
	plugin = "#DCDCAA",
	engine = "#DCDCAA",
	physics = "#DCDCAA",
	graphics = "#DCDCAA",
	console = "#DCDCAA",
	impulse = "#DCDCAA",
	setVelocity = "#DCDCAA",
	glow = "#DCDCAA",
	trail = "#DCDCAA",
	window = "#4EC9B0",
	panel = "#4EC9B0",
	text = "#4EC9B0",
	button = "#4EC9B0",
	slider = "#4EC9B0",
}

local function escapeRichText(value)
	return value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function highlightSource(source)
	local output = {}
	local index = 1
	while index <= #source do
		local character = source:sub(index, index)
		if character == '"' or character == "'" then
			local quote = character
			local finish = index + 1
			while finish <= #source do
				if source:sub(finish, finish) == quote and source:sub(finish - 1, finish - 1) ~= "\\" then
					break
				end
				finish += 1
			end
			table.insert(output, '<font color="#CE9178">' .. escapeRichText(source:sub(index, math.min(finish, #source))) .. "</font>")
			index = math.min(finish + 1, #source + 1)
		else
			local word = source:sub(index):match("^[%a_][%w_]*")
			if word then
				local color = keywordColors[word]
				if color then
					table.insert(output, '<font color="' .. color .. '">' .. word .. "</font>")
				else
					table.insert(output, escapeRichText(word))
				end
				index += #word
			else
				table.insert(output, escapeRichText(character))
				index += 1
			end
		end
	end
	return table.concat(output)
end

local suggestionWords = {
	"class", "static", "enum", "var", "public", "function", "end", "if", "else", "maybe", "nil", "int", "void", "true", "false", "object", "on", "physics", "graphics", "console.log", "engine.physics.gravityDirection", "engine.graphics.quality"
}

local function currentPrefix()
	local cursor = editor.CursorPosition
	if cursor < 1 then return "" end
	return editor.Text:sub(1, cursor - 1):match("([%a_][%w_%.]*)$") or ""
end

local function suggestionFor(prefix)
	if prefix == "" then return nil end
	local lowered = prefix:lower()
	local best
	local bestScore
	for _, candidate in ipairs(suggestionWords) do
		local candidateLower = candidate:lower()
		local score
		if candidateLower:sub(1, #lowered) == lowered then
			score = #candidateLower - #lowered
		else
			local common = 0
			while common < #lowered and common < #candidateLower and lowered:sub(common + 1, common + 1) == candidateLower:sub(common + 1, common + 1) do
				common += 1
			end
			if common > 0 then
				score = 1000 - common
			end
		end
		if score and (not bestScore or score < bestScore) then
			best = candidate
			bestScore = score
		end
	end
	if best and best:lower() ~= lowered then
		return best
	end
	return nil
end

local function updateSuggestion()
	local prefix = currentPrefix()
	local suggestion = suggestionFor(prefix)
	if suggestion then
		suggestionLabel.Text = "Tab  " .. suggestion
	else
		suggestionLabel.Text = ""
	end
end

local function acceptSuggestion()
	local prefix = currentPrefix()
	local suggestion = suggestionFor(prefix)
	if not suggestion then return false end
	local cursor = editor.CursorPosition
	local before = editor.Text:sub(1, cursor - 1 - #prefix)
	local after = editor.Text:sub(cursor)
	editor.Text = before .. suggestion .. after
	editor.CursorPosition = #before + #suggestion + 1
	return true
end

local function updateHighlight()
	syntaxHighlight.Text = highlightSource(editor.Text)
end

local function updateLineNumbers()
	local count = 1
	for _ in editor.Text:gmatch("\n") do
		count += 1
	end
	local lines = table.create(count)
	for index = 1, count do
		lines[index] = tostring(index)
	end
	lineNumbers.Text = table.concat(lines, "\n")
end

local selectedScript
local function sourceFor(instance)
	local paired = instance.Parent:FindFirstChild(instance.Name .. ".enginec")
	if paired and paired:IsA("StringValue") then
		return paired.Value
	end
	return instance.Source
end

local function selectedSource()
	local selected = Selection:Get()
	if #selected == 1 and selected[1]:IsA("LuaSourceContainer") then
		selectedScript = selected[1]
		editor.Text = sourceFor(selectedScript)
		status.Text = selectedScript:GetFullName()
		updateLineNumbers()
		updateHighlight()
		updateSuggestion()
		return selectedScript
	end
	status.Text = "Select a Script, LocalScript, or ModuleScript"
	return nil
end

local function makeWrapper(rawSource)
	local equals = "="
	while rawSource:find("]" .. equals .. "]", 1, true) do
		equals ..= "="
	end
	local openDelimiter = "[" .. equals .. "["
	local closeDelimiter = "]" .. equals .. "]"
	return table.concat({
		'local EngineC = require(game:GetService("ReplicatedStorage"):WaitForChild("EngineC"))',
		"local source = " .. openDelimiter,
		rawSource,
		closeDelimiter,
		"local result, ranOk, runErr = EngineC.run(source)",
		"if not result.ok or not ranOk then error(runErr or result.error) end",
	}, string.char(10))
end

local function parseCurrent()
	local result = EngineC.compile(editor.Text)
	if result.ok then
		status.Text = "Parsed successfully"
	else
		status.Text = "Parse error: " .. tostring(result.error)
	end
	return result
end

local function exportCurrent()
	if not selectedScript then
		status.Text = "Select a source before exporting"
		return
	end
	local result = parseCurrent()
	if not result.ok then return end
	local paired = selectedScript.Parent:FindFirstChild(selectedScript.Name .. ".enginec")
	if not paired then
		paired = Instance.new("StringValue")
		paired.Name = selectedScript.Name .. ".enginec"
		paired.Parent = selectedScript.Parent
	end
	paired.Value = editor.Text
	paired:SetAttribute("EngineCSource", true)
	paired:SetAttribute("EngineCVersion", "v0.1")
	paired:SetAttribute("EngineCWatermark", "EngineC v0.1 | powered by EngineC")
	selectedScript.Source = makeWrapper(editor.Text)
	status.Text = "Exported to Luau wrapper"
end

editor:GetPropertyChangedSignal("Text"):Connect(function()
	updateLineNumbers()
	updateHighlight()
	updateSuggestion()
end)
editor:GetPropertyChangedSignal("CursorPosition"):Connect(updateSuggestion)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not editor:IsFocused() or input.KeyCode ~= Enum.KeyCode.Tab then return end
	if acceptSuggestion() then return end
	local cursor = editor.CursorPosition
	if cursor < 1 then return end
	local before = editor.Text:sub(1, cursor - 1)
	local after = editor.Text:sub(cursor)
	editor.Text = before .. "    " .. after
	editor.CursorPosition = cursor + 4
end)
parseButton.Activated:Connect(parseCurrent)
exportButton.Activated:Connect(exportCurrent)
Selection.SelectionChanged:Connect(selectedSource)
openButton.Click:Connect(function()
	widget.Enabled = true
	selectedSource()
end)

widget.Enabled = true
selectedSource()