--[[
    FallFx Turkey ESP / Charms
    Targets: workspace.FallFx.Turkey2, workspace.FallFx.Turkey3
    + any other children under FallFx if you enable "All FallFx"
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local CFG = {
    enabled = true,
    turkey2 = true,
    turkey3 = true,
    allFallFx = false, -- highlight every child under FallFx
    maxDistance = 2000,
    showDistance = true,
    showName = true,
    fillTransparency = 0.55,
    outlineTransparency = 0,
}

local COLORS = {
    Turkey2 = Color3.fromRGB(255, 140, 60),
    Turkey3 = Color3.fromRGB(255, 90, 50),
    Default = Color3.fromRGB(255, 200, 80),
}

----------------------------------------------------------------
-- Drawings / Highlights
----------------------------------------------------------------
local folder = workspace:WaitForChild("FallFx", 10)
local tracked = {} -- [instance] = { hl, bill, label, dist }

local function getColor(inst)
    return COLORS[inst.Name] or COLORS.Default
end

local function worldPos(inst)
    if inst:IsA("Model") then
        if inst.PrimaryPart then
            return inst.PrimaryPart.Position
        end
        local p = inst:FindFirstChildWhichIsA("BasePart", true)
        return p and p.Position
    elseif inst:IsA("BasePart") then
        return inst.Position
    end
    return nil
end

local function clearOne(inst)
    local t = tracked[inst]
    if not t then
        return
    end
    if t.hl then
        t.hl:Destroy()
    end
    if t.bill then
        t.bill:Destroy()
    end
    tracked[inst] = nil
end

local function clearAll()
    for inst in pairs(tracked) do
        clearOne(inst)
    end
end

local function shouldTrack(inst)
    if not CFG.enabled then
        return false
    end
    if not folder or not inst:IsDescendantOf(folder) then
        return false
    end
    -- only direct children (or models under FallFx)
    local parent = inst.Parent
    if parent ~= folder then
        return false
    end
    if CFG.allFallFx then
        return true
    end
    if inst.Name == "Turkey2" and CFG.turkey2 then
        return true
    end
    if inst.Name == "Turkey3" and CFG.turkey3 then
        return true
    end
    return false
end

local function ensure(inst)
    if not shouldTrack(inst) then
        clearOne(inst)
        return
    end
    local t = tracked[inst]
    if t then
        return
    end

    local color = getColor(inst)
    local hl = Instance.new("Highlight")
    hl.Name = "FallFxCharm"
    hl.Adornee = inst
    hl.FillColor = color
    hl.OutlineColor = Color3.new(1, 1, 1)
    hl.FillTransparency = CFG.fillTransparency
    hl.OutlineTransparency = CFG.outlineTransparency
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = inst

    local bill = Instance.new("BillboardGui")
    bill.Name = "FallFxTag"
    bill.Size = UDim2.fromOffset(120, 36)
    bill.AlwaysOnTop = true
    bill.StudsOffset = Vector3.new(0, 3, 0)
    bill.MaxDistance = CFG.maxDistance

    local anchor = inst
    if inst:IsA("Model") then
        anchor = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true) or inst
    end
    bill.Adornee = anchor
    bill.Parent = inst

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.4
    label.Text = inst.Name
    label.Parent = bill

    tracked[inst] = { hl = hl, bill = bill, label = label }
end

local function refreshList()
    if not folder then
        return
    end
    for _, ch in ipairs(folder:GetChildren()) do
        ensure(ch)
    end
    -- prune
    for inst in pairs(tracked) do
        if not inst.Parent or not shouldTrack(inst) then
            clearOne(inst)
        end
    end
end

----------------------------------------------------------------
-- Update distance text
----------------------------------------------------------------
RunService.RenderStepped:Connect(function()
    if not CFG.enabled or not CFG.showDistance then
        return
    end
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local origin = hrp and hrp.Position
    if not origin then
        return
    end
    for inst, t in pairs(tracked) do
        local pos = worldPos(inst)
        if pos and t.label then
            local d = math.floor((pos - origin).Magnitude + 0.5)
            if CFG.showName then
                t.label.Text = ("%s  [%dm]"):format(inst.Name, d)
            else
                t.label.Text = ("%dm"):format(d)
            end
            if d > CFG.maxDistance then
                t.hl.Enabled = false
                t.bill.Enabled = false
            else
                t.hl.Enabled = true
                t.bill.Enabled = true
            end
        end
    end
end)

----------------------------------------------------------------
-- Watch FallFx
----------------------------------------------------------------
if folder then
    folder.ChildAdded:Connect(function(ch)
        task.defer(ensure, ch)
    end)
    folder.ChildRemoved:Connect(function(ch)
        clearOne(ch)
    end)
    refreshList()
else
    warn("[FallFx ESP] workspace.FallFx not found")
end

task.spawn(function()
    while true do
        task.wait(1.5)
        refreshList()
    end
end)

----------------------------------------------------------------
-- Simple UI
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "FallFxESP"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(200, 160)
frame.Position = UDim2.fromOffset(14, 120)
frame.BackgroundColor3 = Color3.fromRGB(24, 20, 18)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -10, 0, 24)
title.Position = UDim2.fromOffset(8, 4)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(255, 180, 100)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "FallFx Turkeys"
title.Parent = frame

local y = 32
local function toggle(name, key, defaultOn)
    local on = defaultOn
    CFG[key] = on
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 26)
    b.Position = UDim2.fromOffset(8, y)
    b.BackgroundColor3 = on and Color3.fromRGB(180, 90, 40) or Color3.fromRGB(50, 45, 42)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 12
    b.Text = name .. ": " .. (on and "ON" or "OFF")
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function()
        on = not on
        CFG[key] = on
        b.Text = name .. ": " .. (on and "ON" or "OFF")
        b.BackgroundColor3 = on and Color3.fromRGB(180, 90, 40) or Color3.fromRGB(50, 45, 42)
        refreshList()
    end)
    y += 30
end

toggle("ESP Enabled", "enabled", true)
toggle("Turkey2", "turkey2", true)
toggle("Turkey3", "turkey3", true)
toggle("All FallFx", "allFallFx", false)

print("[FallFx ESP] loaded")
