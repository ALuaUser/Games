--[[
    Thrift&Flip — Full Store Rarity ESP
    PlaceId: 94206080514907

    Scans all thrift displays:
      Stenders, HatDisplays, ShoeDisplays, JewelryDisplays,
      WatchDisplays, PhoneDisplays, MusicRecordDisplays,
      ClothingDisplays, PremiumPicks, PerfumeAuction, etc.

    Rarity = Tier only (game map):
      1 Common · 2 Uncommon · 3 Rare · 4 Epic · 5 Legendary
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local function getThriftRoot()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("ThriftStore")
end

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local CFG = {
    enabled = true,
    showCommon = false,
    showUncommon = true,
    showRare = true,
    showEpic = true,
    showLegendary = true,
    showMythic = true,
    minTier = 2,
    showName = true,
    showTier = true,
    showCategory = true,
    maxDistance = 300,
    fillTransparency = 0.45,
}

local TIER_RARITY = {
    [1] = { "Common", Color3.fromRGB(200, 200, 200) },
    [2] = { "Uncommon", Color3.fromRGB(60, 200, 100) },
    [3] = { "Rare", Color3.fromRGB(70, 140, 255) },
    [4] = { "Epic", Color3.fromRGB(180, 70, 255) },
    [5] = { "Legendary", Color3.fromRGB(255, 180, 40) },
}

local function rarityFromTier(tier, name)
    tier = math.clamp(tonumber(tier) or 1, 1, 10)
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

----------------------------------------------------------------
-- Detect stock / sellable display items
----------------------------------------------------------------
local function looksLikeStock(inst)
    if not inst:IsA("Model") then return false end
    local n = inst.Name
    if n:sub(1, 6) == "Stock_" then return true end
    -- attribute-based (some displays use different names)
    if inst:GetAttribute("Tier") ~= nil and (
        inst:GetAttribute("DefinitionId") ~= nil
        or inst:GetAttribute("BaseName") ~= nil
        or inst:GetAttribute("Category") ~= nil
    ) then
        return true
    end
    return false
end

local function readItem(inst)
    local tier = inst:GetAttribute("Tier") or 1
    local cat = inst:GetAttribute("Category") or ""
    local name = inst:GetAttribute("DisplayName")
        or inst:GetAttribute("BaseName")
        or inst:GetAttribute("DefinitionId")
        or inst.Name:gsub("^Stock_", ""):gsub("_Dirty$", ""):gsub("_Clean$", ""):gsub("_Display$", "")
    local rarity, color, tnum = rarityFromTier(tier, name)
    return {
        tier = tnum,
        category = tostring(cat),
        name = tostring(name),
        rarity = rarity,
        color = color,
        area = inst:GetAttribute("StenderId") or (inst.Parent and inst.Parent.Parent and inst.Parent.Parent.Name) or "",
    }
end

----------------------------------------------------------------
-- ESP tracking
----------------------------------------------------------------
local tracked = {} -- [Model] = { hl, bill, label, info }

local function clearOne(inst)
    local t = tracked[inst]
    if not t then return end
    if t.hl then pcall(function() t.hl:Destroy() end) end
    if t.bill then pcall(function() t.bill:Destroy() end) end
    tracked[inst] = nil
end

local function clearAll()
    for inst in pairs(tracked) do clearOne(inst) end
end

local function shouldShow(info)
    if not CFG.enabled then return false end
    if info.tier < CFG.minTier then return false end
    return allowed(info.rarity)
end

local function makeLabelText(info)
    local parts = {}
    if CFG.showName then table.insert(parts, info.name) end
    if CFG.showTier then table.insert(parts, string.format("%s · T%d", info.rarity, info.tier)) end
    if CFG.showCategory and info.category ~= "" then table.insert(parts, info.category) end
    return table.concat(parts, "\n")
end

local function ensure(inst)
    if not looksLikeStock(inst) then return end
    local info = readItem(inst)
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
            t.label.Text = makeLabelText(info)
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
    bill.Size = UDim2.fromOffset(150, 54)
    bill.StudsOffset = Vector3.new(0, 2.2, 0)
    bill.AlwaysOnTop = true
    bill.MaxDistance = CFG.maxDistance
    local anchor = inst:FindFirstChild("Root", true)
        or inst.PrimaryPart
        or inst:FindFirstChildWhichIsA("BasePart", true)
        or inst
    bill.Adornee = anchor
    bill.Parent = inst

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextColor3 = info.color
    label.TextStrokeTransparency = 0.35
    label.TextYAlignment = Enum.TextYAlignment.Bottom
    label.Text = makeLabelText(info)
    label.Parent = bill

    tracked[inst] = { hl = hl, bill = bill, label = label, info = info }
end

local function scan()
    local root = getThriftRoot()
    if not root then return end

    local keep = {}
    for _, d in ipairs(root:GetDescendants()) do
        if looksLikeStock(d) then
            ensure(d)
            keep[d] = true
        end
    end
    for inst in pairs(tracked) do
        if not keep[inst] or not inst.Parent then
            clearOne(inst)
        end
    end
end

-- live updates under whole ThriftStore
task.defer(function()
    local root = getThriftRoot()
    if not root then return end
    root.DescendantAdded:Connect(function(d)
        if looksLikeStock(d) then
            task.defer(ensure, d)
        end
    end)
    root.DescendantRemoving:Connect(function(d)
        if tracked[d] then clearOne(d) end
    end)
end)

task.spawn(function()
    while true do
        if CFG.enabled then scan() end
        task.wait(1.2)
    end
end)

RunService.RenderStepped:Connect(function()
    if not CFG.enabled then return end
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local origin = hrp.Position
    for inst, t in pairs(tracked) do
        local pos
        if inst.PrimaryPart then
            pos = inst.PrimaryPart.Position
        else
            local p = inst:FindFirstChild("Root", true) or inst:FindFirstChildWhichIsA("BasePart", true)
            pos = p and p.Position
        end
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
frame.Size = UDim2.fromOffset(230, 320)
frame.Position = UDim2.fromOffset(14, 90)
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
title.Text = "Thrift Store ESP"
title.Parent = frame

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, -10, 0, 32)
status.Position = UDim2.fromOffset(8, 28)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextColor3 = Color3.fromRGB(150, 160, 175)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Text = "…"
status.Parent = frame

local y = 64
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
        if key == "enabled" and not on then clearAll() end
        scan()
    end)
    y += 28
    return b
end

toggle("ESP Enabled", "enabled", Color3.fromRGB(40, 140, 100))
toggle("Common (T1)", "showCommon", Color3.fromRGB(120, 120, 120))
toggle("Uncommon (T2)", "showUncommon", Color3.fromRGB(40, 150, 80))
toggle("Rare (T3)", "showRare", Color3.fromRGB(40, 90, 180))
toggle("Epic (T4)", "showEpic", Color3.fromRGB(120, 50, 180))
toggle("Legendary (T5)", "showLegendary", Color3.fromRGB(180, 130, 30))
toggle("Mythic", "showMythic", Color3.fromRGB(180, 40, 140))

local rescan = Instance.new("TextButton")
rescan.Size = UDim2.new(1, -16, 0, 24)
rescan.Position = UDim2.fromOffset(8, y)
rescan.BackgroundColor3 = Color3.fromRGB(40, 70, 110)
rescan.TextColor3 = Color3.new(1, 1, 1)
rescan.Font = Enum.Font.GothamMedium
rescan.TextSize = 12
rescan.Text = "Rescan Store"
rescan.Parent = frame
Instance.new("UICorner", rescan).CornerRadius = UDim.new(0, 6)
rescan.MouseButton1Click:Connect(function()
    scan()
end)

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
            "items %d\nC%d U%d R%d E%d L%d M%d",
            n, by.Common, by.Uncommon, by.Rare, by.Epic, by.Legendary, by.Mythic
        )
        task.wait(0.8)
    end
end)

print("[Thrift ESP] full store scan enabled")
scan()
