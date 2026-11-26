--[[
    Thrift&Flip — Stender / Rail Rarity ESP (fixed mapping)
    PlaceId: 94206080514907

    Rarity is Tier ONLY (game map):
      1 Common · 2 Uncommon · 3 Rare · 4 Epic · 5 Legendary
    Prestige / Hype do NOT change rarity label.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local ROOT = workspace:WaitForChild("Map", 15)
local STENDERS = ROOT and ROOT:FindFirstChild("ThriftStore") and ROOT.ThriftStore:FindFirstChild("Stenders")

local CFG = {
    enabled = true,
    showCommon = true,
    showUncommon = true,
    showRare = true,
    showEpic = true,
    showLegendary = true,
    showMythic = true,
    minTier = 1,
    showName = true,
    showTier = true,
    showCategory = true,
    maxDistance = 250,
    fillTransparency = 0.45,
}

-- Exact game map from scripts: Common=1 Uncommon=2 Rare=3 Epic=4 Legendary=5
local TIER_RARITY = {
    [1] = { "Common", Color3.fromRGB(200, 200, 200) },
    [2] = { "Uncommon", Color3.fromRGB(60, 200, 100) },
    [3] = { "Rare", Color3.fromRGB(70, 140, 255) },
    [4] = { "Epic", Color3.fromRGB(180, 70, 255) },
    [5] = { "Legendary", Color3.fromRGB(255, 180, 40) },
}

local function rarityFromTier(tier, name)
    tier = math.clamp(tonumber(tier) or 1, 1, 10)
    -- Mythic only if name / definition hints at it (separate system in game)
    local n = string.lower(tostring(name or ""))
    if n:find("mythic", 1, true) or tier >= 6 then
        return "Mythic", Color3.fromRGB(255, 60, 200), tier
    end
    local row = TIER_RARITY[tier] or TIER_RARITY[1]
    return row[1], row[2], tier
end

local function allowed(rarity)
    if rarity == "Common" then return CFG.showCommon end
    if rarity == "Uncommon" then return CFG.showUncommon end
    if rarity == "Rare" then return CFG.showRare end
    if rarity == "Epic" then return CFG.showEpic end
    if rarity == "Legendary" then return CFG.showLegendary end
    if rarity == "Mythic" then return CFG.showMythic end
    return true
end

local tracked = {}

local function worldPos(inst)
    if inst:IsA("Model") then
        if inst.PrimaryPart then return inst.PrimaryPart.Position end
        local p = inst:FindFirstChild("Root", true) or inst:FindFirstChildWhichIsA("BasePart", true)
        return p and p.Position
    elseif inst:IsA("BasePart") then
        return inst.Position
    end
end

local function clearOne(inst)
    local t = tracked[inst]
    if not t then return end
    if t.hl then t.hl:Destroy() end
    if t.bill then t.bill:Destroy() end
    tracked[inst] = nil
end

local function isStock(inst)
    return inst:IsA("Model") and inst.Name:sub(1, 6) == "Stock_"
end

local function readStock(inst)
    local tier = inst:GetAttribute("Tier") or 1
    local cat = inst:GetAttribute("Category") or ""
    local name = inst:GetAttribute("DisplayName")
        or inst:GetAttribute("BaseName")
        or inst:GetAttribute("DefinitionId")
        or inst.Name:gsub("^Stock_", ""):gsub("_Dirty$", ""):gsub("_Clean$", "")
    local rarity, color, tnum = rarityFromTier(tier, name)
    return {
        tier = tnum,
        category = tostring(cat),
        name = tostring(name),
        rarity = rarity,
        color = color,
        prestige = tonumber(inst:GetAttribute("Prestige")) or 0,
        hype = tonumber(inst:GetAttribute("Hype")) or 0,
    }
end

local function shouldShow(info)
    if not CFG.enabled then return false end
    if info.tier < CFG.minTier then return false end
    return allowed(info.rarity)
end

local function ensure(inst)
    if not isStock(inst) then return end
    local info = readStock(inst)
    if not shouldShow(info) then
        clearOne(inst)
        return
    end

    local t = tracked[inst]
    if t then
        if t.hl then
            t.hl.FillColor = info.color
            t.hl.OutlineColor = info.color
            t.hl.Enabled = true
        end
        if t.label then
            local parts = {}
            if CFG.showName then table.insert(parts, info.name) end
            if CFG.showTier then
                table.insert(parts, string.format("%s · T%d", info.rarity, info.tier))
            end
            if CFG.showCategory and info.category ~= "" then
                table.insert(parts, info.category)
            end
            t.label.Text = table.concat(parts, "\n")
            t.label.TextColor3 = info.color
        end
        t.info = info
        return
    end

    local hl = Instance.new("Highlight")
    hl.Name = "ThriftRarityESP"
    hl.Adornee = inst
    hl.FillColor = info.color
    hl.OutlineColor = info.color
    hl.FillTransparency = CFG.fillTransparency
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = inst

    local bill = Instance.new("BillboardGui")
    bill.Name = "ThriftRarityTag"
    bill.Size = UDim2.fromOffset(150, 52)
    bill.StudsOffset = Vector3.new(0, 2.4, 0)
    bill.AlwaysOnTop = true
    bill.MaxDistance = CFG.maxDistance
    local anchor = inst:FindFirstChild("Root", true) or inst:FindFirstChildWhichIsA("BasePart", true) or inst
    bill.Adornee = anchor
    bill.Parent = inst

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextColor3 = info.color
    label.TextStrokeTransparency = 0.35
    label.TextYAlignment = Enum.TextYAlignment.Bottom
    local parts = {}
    if CFG.showName then table.insert(parts, info.name) end
    if CFG.showTier then
        table.insert(parts, string.format("%s · T%d", info.rarity, info.tier))
    end
    if CFG.showCategory and info.category ~= "" then
        table.insert(parts, info.category)
    end
    label.Text = table.concat(parts, "\n")
    label.Parent = bill

    tracked[inst] = { hl = hl, bill = bill, label = label, info = info }
end

local function scan()
    if not STENDERS then
        STENDERS = workspace:FindFirstChild("Map")
            and workspace.Map:FindFirstChild("ThriftStore")
            and workspace.Map.ThriftStore:FindFirstChild("Stenders")
    end
    if not STENDERS then return end

    for _, stender in ipairs(STENDERS:GetChildren()) do
        for _, slot in ipairs(stender:GetChildren()) do
            if slot.Name:match("^Slot") then
                for _, ch in ipairs(slot:GetChildren()) do
                    if isStock(ch) then ensure(ch) end
                end
            elseif isStock(slot) then
                ensure(slot)
            end
        end
    end

    for inst in pairs(tracked) do
        if not inst.Parent or not isStock(inst) then
            clearOne(inst)
        else
            local info = readStock(inst)
            if not shouldShow(info) then
                clearOne(inst)
            end
        end
    end
end

if STENDERS then
    STENDERS.DescendantAdded:Connect(function(d)
        if isStock(d) then task.defer(ensure, d) end
    end)
    STENDERS.DescendantRemoving:Connect(function(d)
        if tracked[d] then clearOne(d) end
    end)
end

task.spawn(function()
    while true do
        scan()
        task.wait(1.25)
    end
end)

RunService.RenderStepped:Connect(function()
    if not CFG.enabled then return end
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local origin = hrp.Position
    for inst, t in pairs(tracked) do
        local pos = worldPos(inst)
        if pos and t.hl then
            local on = (pos - origin).Magnitude <= CFG.maxDistance
            t.hl.Enabled = on
            if t.bill then t.bill.Enabled = on end
        end
    end
end)

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "ThriftRarityESP"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(220, 300)
frame.Position = UDim2.fromOffset(14, 100)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -10, 0, 24)
title.Position = UDim2.fromOffset(8, 4)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(120, 200, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Thrift Rarity ESP"
title.Parent = frame

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, -10, 0, 18)
status.Position = UDim2.fromOffset(8, 28)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextColor3 = Color3.fromRGB(150, 160, 175)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "…"
status.Parent = frame

local y = 50
local function toggle(name, key, color)
    local on = CFG[key]
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 24)
    b.Position = UDim2.fromOffset(8, y)
    b.BackgroundColor3 = on and (color or Color3.fromRGB(50, 120, 90)) or Color3.fromRGB(45, 48, 55)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 12
    b.Text = name .. ": " .. (on and "ON" or "OFF")
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function()
        CFG[key] = not CFG[key]
        on = CFG[key]
        b.Text = name .. ": " .. (on and "ON" or "OFF")
        b.BackgroundColor3 = on and (color or Color3.fromRGB(50, 120, 90)) or Color3.fromRGB(45, 48, 55)
        scan()
    end)
    y += 28
end

toggle("ESP Enabled", "enabled", Color3.fromRGB(40, 140, 100))
toggle("Common (T1)", "showCommon", Color3.fromRGB(120, 120, 120))
toggle("Uncommon (T2)", "showUncommon", Color3.fromRGB(40, 150, 80))
toggle("Rare (T3)", "showRare", Color3.fromRGB(40, 90, 180))
toggle("Epic (T4)", "showEpic", Color3.fromRGB(120, 50, 180))
toggle("Legendary (T5)", "showLegendary", Color3.fromRGB(180, 130, 30))
toggle("Mythic", "showMythic", Color3.fromRGB(180, 40, 140))

task.spawn(function()
    while gui.Parent do
        local n = 0
        local by = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
        for _, t in pairs(tracked) do
            n += 1
            if t.info and by[t.info.rarity] ~= nil then
                by[t.info.rarity] += 1
            end
        end
        status.Text = string.format(
            "n=%d  C%d U%d R%d E%d L%d M%d",
            n, by.Common, by.Uncommon, by.Rare, by.Epic, by.Legendary, by.Mythic
        )
        task.wait(0.8)
    end
end)

print("[Thrift ESP] loaded — Tier-only rarity map")
scan()
