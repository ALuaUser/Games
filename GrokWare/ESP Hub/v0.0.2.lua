--[[
    Universal Pro ESP
    LiteUI · pooled drawings · event-driven · distance culling

    Boxes (2D / Corner) · Names · Health · Distance · Skeleton · Tracers
    Team check · Visibility tint · NPC · Items · Rainbow · Max distance
]]

local LIB_URL = "https://raw.githubusercontent.com/ALuaUser/UIs/refs/heads/main/Grokware/v0.0.7/Source.lua"

local ok, Lite = pcall(function()
    return loadstring(game:HttpGet(LIB_URL))()
end)
if not ok or type(Lite) ~= "table" then
    warn("[ProESP] LiteUI failed:", Lite)
    return
end

----------------------------------------------------------------
-- Services
----------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

local LP  = Players.LocalPlayer
local Cam = Workspace.CurrentCamera

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local CFG = {
    master      = true,

    -- players
    boxes       = true,
    boxStyle    = "Corner", -- Full | Corner
    names       = true,
    health      = true,
    distance    = true,
    skeleton    = false,
    tracers     = true,
    tracerFrom  = "Bottom", -- Bottom | Center
    teamCheck   = true,
    visCheck    = true, -- tint when behind wall
    maxDist     = 1500,
    textSize    = 13,

    -- colours
    colEnemy    = Color3.fromRGB(255, 75, 75),
    colAlly     = Color3.fromRGB(80, 180, 255),
    colNpc   = Color3.fromRGB(255, 200, 60),
    colItem     = Color3.fromRGB(180, 100, 255),
    rainbow     = false,

    -- npc / items
    npcEsp      = false,
    itemEsp     = false,
    itemKeywords = { "Tool", "Pickaxe", "Gun", "Key", "Chest", "Crate", "Loot", "Egg", "Coin" },
}

----------------------------------------------------------------
-- Drawing pool
----------------------------------------------------------------
local function dnew(kind)
    if not Drawing then return nil end
    local s, o = pcall(Drawing.new, kind)
    return s and o or nil
end

local pool = { square = {}, line = {}, text = {} }
local function acquire(kind)
    local bucket = pool[kind]
    if bucket and #bucket > 0 then
        return table.remove(bucket)
    end
    if kind == "square" then
        local o = dnew("Square")
        if o then o.Filled = false; o.Thickness = 1; o.Visible = false end
        return o
    elseif kind == "line" then
        local o = dnew("Line")
        if o then o.Thickness = 1.2; o.Visible = false end
        return o
    elseif kind == "text" then
        local o = dnew("Text")
        if o then o.Center = true; o.Outline = true; o.Size = CFG.textSize; o.Visible = false end
        return o
    end
end

local function release(kind, obj)
    if not obj then return end
    pcall(function() obj.Visible = false end)
    pool[kind] = pool[kind] or {}
    table.insert(pool[kind], obj)
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function alive(model)
    if not model then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function isEnemy(pl)
    if not pl or pl == LP then return false end
    if not CFG.teamCheck then return true end
    if pl.Team == nil or LP.Team == nil then return true end
    return pl.Team ~= LP.Team
end

local function rainbowColor(t)
    return Color3.fromHSV((t * 0.15) % 1, 0.9, 1)
end

local function behindWall(from, to, model)
    if not CFG.visCheck then return false end
    rayParams.FilterDescendantsInstances = { LP.Character, model }
    local hit = Workspace:Raycast(from, to - from, rayParams)
    return hit ~= nil
end

local BONES = {
    { "Head", "UpperTorso" },
    { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" },
    { "LeftUpperArm", "LeftLowerArm" },
    { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" },
    { "RightUpperArm", "RightLowerArm" },
    { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" },
    { "LeftUpperLeg", "LeftLowerLeg" },
    { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" },
    { "RightUpperLeg", "RightLowerLeg" },
    { "RightLowerLeg", "RightFoot" },
    -- R6 fallbacks handled by missing parts simply skipping
    { "Head", "Torso" },
    { "Torso", "Left Arm" },
    { "Torso", "Right Arm" },
    { "Torso", "Left Leg" },
    { "Torso", "Right Leg" },
}

----------------------------------------------------------------
-- Entity cache (event-driven)
----------------------------------------------------------------
-- players: [Player] = { model, hum, root, hl }
local playerCache = {}
local npcList = {}      -- { model, root, hum }
local itemList = {}     -- { inst, posPart }

local function unbindPlayer(pl)
    local e = playerCache[pl]
    if not e then return end
    if e.hl then pcall(function() e.hl:Destroy() end) end
    playerCache[pl] = nil
end

local function bindCharacter(pl, char)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("Head")
    local e = playerCache[pl] or {}
    if e.hl then pcall(function() e.hl:Destroy() end) end
    e.model = char
    e.hum = hum
    e.root = root
    e.hl = nil
    playerCache[pl] = e

    if hum then
        hum.Destroying:Connect(function()
            if playerCache[pl] and playerCache[pl].model == char then
                unbindPlayer(pl)
            end
        end)
    end
end

local function trackPlayer(pl)
    if pl == LP then return end
    if pl.Character then bindCharacter(pl, pl.Character) end
    pl.CharacterAdded:Connect(function(char)
        task.wait(0.15)
        bindCharacter(pl, char)
    end)
    pl.CharacterRemoving:Connect(function()
        unbindPlayer(pl)
    end)
end

for _, pl in ipairs(Players:GetPlayers()) do trackPlayer(pl) end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(function(pl)
    unbindPlayer(pl)
end)

-- NPC / item scan (throttled)
local function isNpcModel(m)
    if not m:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    local hum = m:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local root = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head")
    return root ~= nil
end

local function nameLooksLikeItem(name)
    local lower = string.lower(name)
    for _, kw in ipairs(CFG.itemKeywords) do
        if string.find(lower, string.lower(kw), 1, true) then return true end
    end
    return false
end

local lastScan = 0
local function scanWorld()
    if not CFG.npcEsp and not CFG.itemEsp then
        table.clear(npcList)
        table.clear(itemList)
        return
    end
    local now = os.clock()
    if now - lastScan < 1.25 then return end -- throttle
    lastScan = now

    local npcs, items = {}, {}
    local origin = Cam.CFrame.Position

    for _, inst in ipairs(Workspace:GetChildren()) do
        if CFG.npcEsp and isNpcModel(inst) then
            local root = inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChild("Head")
            if root and (root.Position - origin).Magnitude <= CFG.maxDist * 1.2 then
                table.insert(npcs, {
                    model = inst,
                    root = root,
                    hum = inst:FindFirstChildOfClass("Humanoid"),
                })
            end
        end
        if CFG.itemEsp then
            if inst:IsA("Tool") or inst:IsA("Model") or inst:IsA("BasePart") then
                if nameLooksLikeItem(inst.Name) then
                    local part = inst:IsA("BasePart") and inst
                        or inst:FindFirstChildWhichIsA("BasePart", true)
                    if part and (part.Position - origin).Magnitude <= CFG.maxDist then
                        table.insert(items, { inst = inst, part = part })
                    end
                end
            end
        end
    end
    npcList = npcs
    itemList = items
end

----------------------------------------------------------------
-- Per-entity drawing state
----------------------------------------------------------------
--[[
    entry = {
        boxL, boxR, boxT, boxB,          -- corner pieces OR
        box,                              -- full square
        name, health, tracer,
        bones = { lines... },
        chams,
    }
]]
local drawState = {} -- key = player|model|item

local function freeEntry(key)
    local e = drawState[key]
    if not e then return end
    release("square", e.box)
    release("line", e.boxL); release("line", e.boxR)
    release("line", e.boxT); release("line", e.boxB)
    release("text", e.name)
    release("line", e.health)
    release("line", e.tracer)
    if e.bones then
        for _, ln in ipairs(e.bones) do release("line", ln) end
    end
    if e.chams then pcall(function() e.chams:Destroy() end) end
    drawState[key] = nil
end

local function ensureEntry(key)
    if drawState[key] then return drawState[key] end
    local e = { bones = {} }
    for _ = 1, #BONES do
        table.insert(e.bones, acquire("line"))
    end
    drawState[key] = e
    return e
end

----------------------------------------------------------------
-- Geometry
----------------------------------------------------------------
local function worldBox(model)
    local parts = {}
    for _, p in ipairs(model:GetChildren()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            table.insert(parts, p)
        end
    end
    if #parts == 0 then
        local r = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
        if not r then return nil end
        local sp, on = Cam:WorldToViewportPoint(r.Position)
        if not on or sp.Z <= 0 then return nil end
        return Vector2.new(sp.X - 18, sp.Y - 28), Vector2.new(36, 56)
    end

    local minV = Vector3.new(1e9, 1e9, 1e9)
    local maxV = Vector3.new(-1e9, -1e9, -1e9)
    for _, p in ipairs(parts) do
        local cf, sz = p.CFrame, p.Size * 0.5
        for _, sx in ipairs({ -1, 1 }) do
            for _, sy in ipairs({ -1, 1 }) do
                for _, szz in ipairs({ -1, 1 }) do
                    local w = (cf * Vector3.new(sx * sz.X, sy * sz.Y, szz * sz.Z))
                    minV = Vector3.new(math.min(minV.X, w.X), math.min(minV.Y, w.Y), math.min(minV.Z, w.Z))
                    maxV = Vector3.new(math.max(maxV.X, w.X), math.max(maxV.Y, w.Y), math.max(maxV.Z, w.Z))
                end
            end
        end
    end

    local corners = {
        Vector3.new(minV.X, minV.Y, minV.Z), Vector3.new(maxV.X, minV.Y, minV.Z),
        Vector3.new(minV.X, maxV.Y, minV.Z), Vector3.new(maxV.X, maxV.Y, minV.Z),
        Vector3.new(minV.X, minV.Y, maxV.Z), Vector3.new(maxV.X, minV.Y, maxV.Z),
        Vector3.new(minV.X, maxV.Y, maxV.Z), Vector3.new(maxV.X, maxV.Y, maxV.Z),
    }
    local min2, max2 = Vector2.new(1e9, 1e9), Vector2.new(-1e9, -1e9)
    local any = false
    for _, c in ipairs(corners) do
        local sp, on = Cam:WorldToViewportPoint(c)
        if on and sp.Z > 0 then
            any = true
            min2 = Vector2.new(math.min(min2.X, sp.X), math.min(min2.Y, sp.Y))
            max2 = Vector2.new(math.max(max2.X, sp.X), math.max(max2.Y, sp.Y))
        end
    end
    if not any then return nil end
    return min2, max2 - min2
end

local function setCornerBox(e, topLeft, size, color)
    local x, y, w, h = topLeft.X, topLeft.Y, size.X, size.Y
    local len = math.clamp(math.min(w, h) * 0.25, 4, 14)

    local function arm(obj, a, b)
        if not obj then return end
        obj.From = a; obj.To = b; obj.Color = color; obj.Visible = true
    end

    if not e.boxL then e.boxL = acquire("line") end
    if not e.boxR then e.boxR = acquire("line") end
    if not e.boxT then e.boxT = acquire("line") end
    if not e.boxB then e.boxB = acquire("line") end
    -- use 4 lines as TL-horizontal, TL-vertical, TR-h, TR-v, etc — pack into 4 by drawing pairs
    -- Simpler: 8 corners via reusing 4 lines each frame is messy; draw 4 L-shapes with 2 lines each
    -- Allocate 8 lines lazily
    e.corners = e.corners or {}
    while #e.corners < 8 do table.insert(e.corners, acquire("line")) end
    local c = e.corners
    local pts = {
        -- top-left
        { Vector2.new(x, y), Vector2.new(x + len, y) },
        { Vector2.new(x, y), Vector2.new(x, y + len) },
        -- top-right
        { Vector2.new(x + w, y), Vector2.new(x + w - len, y) },
        { Vector2.new(x + w, y), Vector2.new(x + w, y + len) },
        -- bottom-left
        { Vector2.new(x, y + h), Vector2.new(x + len, y + h) },
        { Vector2.new(x, y + h), Vector2.new(x, y + h - len) },
        -- bottom-right
        { Vector2.new(x + w, y + h), Vector2.new(x + w - len, y + h) },
        { Vector2.new(x + w, y + h), Vector2.new(x + w, y + h - len) },
    }
    for i = 1, 8 do
        arm(c[i], pts[i][1], pts[i][2])
    end
    if e.box then e.box.Visible = false end
end

local function setFullBox(e, topLeft, size, color)
    if e.corners then
        for _, ln in ipairs(e.corners) do if ln then ln.Visible = false end end
    end
    if not e.box then e.box = acquire("square") end
    if e.box then
        e.box.Position = topLeft
        e.box.Size = size
        e.box.Color = color
        e.box.Visible = true
    end
end

local function hideBoxes(e)
    if e.box then e.box.Visible = false end
    if e.corners then
        for _, ln in ipairs(e.corners) do if ln then ln.Visible = false end end
    end
end

----------------------------------------------------------------
-- Render one model
----------------------------------------------------------------
local function renderModel(key, model, label, color, hum, root)
    if not alive(model) and not (hum and hum.Health > 0) then return false end
    if not root then return false end

    local origin = Cam.CFrame.Position
    local dist = (root.Position - origin).Magnitude
    if dist > CFG.maxDist then return false end

    local e = ensureEntry(key)
    local blocked = behindWall(origin, root.Position, model)
    if CFG.rainbow then
        color = rainbowColor(os.clock() + dist * 0.01)
    end
    if blocked then
        color = Color3.new(color.R * 0.45, color.G * 0.45, color.B * 0.45)
    end

    local topLeft, size = worldBox(model)
    if not topLeft then
        hideBoxes(e)
        if e.name then e.name.Visible = false end
        if e.health then e.health.Visible = false end
        if e.tracer then e.tracer.Visible = false end
        if e.bones then for _, ln in ipairs(e.bones) do if ln then ln.Visible = false end end end
        return true
    end

    if CFG.boxes then
        if CFG.boxStyle == "Corner" then
            setCornerBox(e, topLeft, size, color)
        else
            setFullBox(e, topLeft, size, color)
        end
    else
        hideBoxes(e)
    end

    -- name / distance
    if CFG.names or CFG.distance then
        if not e.name then e.name = acquire("text") end
        if e.name then
            local bits = {}
            if CFG.names then table.insert(bits, label) end
            if CFG.distance then table.insert(bits, string.format("%dm", math.floor(dist))) end
            e.name.Text = table.concat(bits, " · ")
            e.name.Size = CFG.textSize
            e.name.Color = color
            e.name.Position = Vector2.new(topLeft.X + size.X * 0.5, topLeft.Y - 14)
            e.name.Visible = true
        end
    elseif e.name then
        e.name.Visible = false
    end

    -- health
    if CFG.health and hum then
        if not e.health then e.health = acquire("line") end
        if e.health then
            local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            local h = size.Y * hp
            e.health.From = Vector2.new(topLeft.X - 4, topLeft.Y + size.Y)
            e.health.To   = Vector2.new(topLeft.X - 4, topLeft.Y + size.Y - h)
            e.health.Color = Color3.fromRGB(255 * (1 - hp), 255 * hp, 40)
            e.health.Thickness = 2
            e.health.Visible = true
        end
    elseif e.health then
        e.health.Visible = false
    end

    -- tracer
    if CFG.tracers then
        if not e.tracer then e.tracer = acquire("line") end
        if e.tracer then
            local from = CFG.tracerFrom == "Center"
                and (Cam.ViewportSize * 0.5)
                or Vector2.new(Cam.ViewportSize.X * 0.5, Cam.ViewportSize.Y)
            e.tracer.From = from
            e.tracer.To = Vector2.new(topLeft.X + size.X * 0.5, topLeft.Y + size.Y)
            e.tracer.Color = color
            e.tracer.Visible = true
        end
    elseif e.tracer then
        e.tracer.Visible = false
    end

    -- skeleton
    if CFG.skeleton and e.bones then
        for i, pair in ipairs(BONES) do
            local ln = e.bones[i]
            if not ln then continue end
            local a = model:FindFirstChild(pair[1])
            local b = model:FindFirstChild(pair[2])
            if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
                local sa, oa = Cam:WorldToViewportPoint(a.Position)
                local sb, ob = Cam:WorldToViewportPoint(b.Position)
                if oa and ob and sa.Z > 0 and sb.Z > 0 then
                    ln.From = Vector2.new(sa.X, sa.Y)
                    ln.To = Vector2.new(sb.X, sb.Y)
                    ln.Color = color
                    ln.Visible = true
                else
                    ln.Visible = false
                end
            else
                ln.Visible = false
            end
        end
    elseif e.bones then
        for _, ln in ipairs(e.bones) do if ln then ln.Visible = false end end
    end

    -- chams (Highlight — cheap, built-in)
    if not e.chams or not e.chams.Parent then
        local hl = Instance.new("Highlight")
        hl.Name = "ProESP_Chams"
        hl.FillTransparency = 0.6
        hl.OutlineTransparency = 0.25
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = model
        e.chams = hl
    end
    e.chams.FillColor = color
    e.chams.OutlineColor = color
    e.chams.Enabled = CFG.master

    return true
end

local function renderItem(key, inst, part, color)
    local origin = Cam.CFrame.Position
    local dist = (part.Position - origin).Magnitude
    if dist > CFG.maxDist then return false end

    local e = ensureEntry(key)
    if CFG.rainbow then color = rainbowColor(os.clock()) end

    local sp, on = Cam:WorldToViewportPoint(part.Position)
    if not on or sp.Z <= 0 then
        if e.name then e.name.Visible = false end
        return true
    end

    if not e.name then e.name = acquire("text") end
    if e.name then
        e.name.Text = string.format("%s · %dm", inst.Name, math.floor(dist))
        e.name.Size = CFG.textSize
        e.name.Color = color
        e.name.Position = Vector2.new(sp.X, sp.Y - 10)
        e.name.Visible = true
    end
    hideBoxes(e)
    if e.health then e.health.Visible = false end
    if e.tracer then e.tracer.Visible = false end
    if e.bones then for _, ln in ipairs(e.bones) do if ln then ln.Visible = false end end end
    return true
end

----------------------------------------------------------------
-- Main render
----------------------------------------------------------------
RunService.RenderStepped:Connect(function()
    if not CFG.master then
        for k in pairs(drawState) do freeEntry(k) end
        return
    end

    pcall(scanWorld)

    local keep = {}

    -- players
    for pl, data in pairs(playerCache) do
        if data.model and data.root and alive(data.model) then
            local enemy = isEnemy(pl)
            local col = enemy and CFG.colEnemy or CFG.colAlly
            local key = pl
            if renderModel(key, data.model, pl.DisplayName ~= "" and pl.DisplayName or pl.Name, col, data.hum, data.root) then
                keep[key] = true
            end
        end
    end

    -- npcs
    if CFG.npcEsp then
        for i, n in ipairs(npcList) do
            local key = n.model
            if renderModel(key, n.model, n.model.Name, CFG.colNpc, n.hum, n.root) then
                keep[key] = true
            end
        end
    end

    -- items
    if CFG.itemEsp then
        for _, it in ipairs(itemList) do
            local key = it.inst
            if renderItem(key, it.inst, it.part, CFG.colItem) then
                keep[key] = true
            end
        end
    end

    for k in pairs(drawState) do
        if not keep[k] then freeEntry(k) end
    end
end)

----------------------------------------------------------------
-- LiteUI
----------------------------------------------------------------
Lite.Themes.proesp = {
    bg     = Color3.fromRGB(12, 14, 18),
    line   = Color3.fromRGB(36, 42, 52),
    text   = Color3.fromRGB(235, 240, 245),
    sub    = Color3.fromRGB(130, 140, 155),
    accent = Color3.fromRGB(100, 170, 255),
    warn   = Color3.fromRGB(255, 190, 60),
    danger = Color3.fromRGB(255, 80, 80),
    track  = Color3.fromRGB(26, 30, 38),
}

local ui = Lite.new({
    Title = "Pro ESP",
    Subtitle = "Universal · pooled · optimised",
    Width = 360,
    Theme = "proesp",
})

local tab = ui:Tabs({ "ESP", "Filters", "Style", "Settings" }, { MaxHeight = 320 })

----------------------------------------------------------------
-- ESP
----------------------------------------------------------------
local esp = tab.ESP
esp:Section("Master")
esp:Toggle({
    Name = "Enable ESP",
    Flag = "master",
    Default = CFG.master,
    Callback = function(v)
        CFG.master = v
        if not v then for k in pairs(drawState) do freeEntry(k) end end
    end,
})

esp:Section("Elements")
esp:Toggle({ Name = "Boxes", Flag = "boxes", Default = CFG.boxes, Callback = function(v) CFG.boxes = v end })
esp:Dropdown({
    Name = "Box style",
    Flag = "boxStyle",
    Options = { "Full", "Corner" },
    Default = CFG.boxStyle,
    Callback = function(v) CFG.boxStyle = v end,
})
esp:Toggle({ Name = "Names", Flag = "names", Default = CFG.names, Callback = function(v) CFG.names = v end })
esp:Toggle({ Name = "Health bar", Flag = "health", Default = CFG.health, Callback = function(v) CFG.health = v end })
esp:Toggle({ Name = "Distance", Flag = "distance", Default = CFG.distance, Callback = function(v) CFG.distance = v end })
esp:Toggle({ Name = "Skeleton", Flag = "skeleton", Default = CFG.skeleton, Callback = function(v) CFG.skeleton = v end })
esp:Toggle({ Name = "Tracers", Flag = "tracers", Default = CFG.tracers, Callback = function(v) CFG.tracers = v end })
esp:Dropdown({
    Name = "Tracer origin",
    Flag = "tracerFrom",
    Options = { "Bottom", "Center" },
    Default = CFG.tracerFrom,
    Callback = function(v) CFG.tracerFrom = v end,
})
esp:Slider({
    Name = "Max distance",
    Flag = "maxDist",
    Min = 50,
    Max = 4000,
    Default = CFG.maxDist,
    Step = 50,
    Callback = function(v) CFG.maxDist = v end,
})
esp:Slider({
    Name = "Text size",
    Flag = "textSize",
    Min = 10,
    Max = 20,
    Default = CFG.textSize,
    Step = 1,
    Callback = function(v) CFG.textSize = v end,
})

----------------------------------------------------------------
-- Filters
----------------------------------------------------------------
local fil = tab.Filters
fil:Section("Players")
fil:Toggle({ Name = "Team check", Flag = "teamCheck", Default = CFG.teamCheck, Callback = function(v) CFG.teamCheck = v end })
fil:Toggle({ Name = "Visibility dim", Flag = "visCheck", Default = CFG.visCheck, Callback = function(v) CFG.visCheck = v end })

fil:Section("World")
fil:Toggle({ Name = "NPC ESP", Flag = "npcEsp", Default = CFG.npcEsp, Callback = function(v) CFG.npcEsp = v end })
fil:Toggle({ Name = "Item ESP", Flag = "itemEsp", Default = CFG.itemEsp, Callback = function(v) CFG.itemEsp = v end })
fil:Label({ Text = "Items match name keywords (Tool, Chest, Egg…)" })

----------------------------------------------------------------
-- Style
----------------------------------------------------------------
local sty = tab.Style
sty:Section("Colours")
local PRESETS = {
    Red = Color3.fromRGB(255, 75, 75),
    Orange = Color3.fromRGB(255, 160, 40),
    Yellow = Color3.fromRGB(255, 220, 60),
    Green = Color3.fromRGB(70, 220, 100),
    Cyan = Color3.fromRGB(60, 200, 255),
    Blue = Color3.fromRGB(80, 140, 255),
    Purple = Color3.fromRGB(180, 100, 255),
    White = Color3.fromRGB(240, 240, 240),
}
local cnames = { "Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Purple", "White" }
sty:Dropdown({ Name = "Enemy", Flag = "colEnemy", Options = cnames, Default = "Red",
    Callback = function(v) CFG.colEnemy = PRESETS[v] or CFG.colEnemy end })
sty:Dropdown({ Name = "Ally", Flag = "colAlly", Options = cnames, Default = "Cyan",
    Callback = function(v) CFG.colAlly = PRESETS[v] or CFG.colAlly end })
sty:Dropdown({ Name = "NPC", Flag = "colNpc", Options = cnames, Default = "Yellow",
    Callback = function(v) CFG.colNpc = PRESETS[v] or CFG.colNpc end })
sty:Dropdown({ Name = "Item", Flag = "colItem", Options = cnames, Default = "Purple",
    Callback = function(v) CFG.colItem = PRESETS[v] or CFG.colItem end })
sty:Toggle({ Name = "Rainbow mode", Flag = "rainbow", Default = CFG.rainbow, Callback = function(v) CFG.rainbow = v end })

----------------------------------------------------------------
-- Settings
----------------------------------------------------------------
local set = tab.Settings
set:Section("UI")
ui:Settings({ Panel = set })
set:Separator()
set:Section("Profiles")
ui:Profiles({ Panel = set })
set:Separator()
set:Button({
    Name = "Unload",
    Callback = function()
        CFG.master = false
        for k in pairs(drawState) do freeEntry(k) end
        for pl in pairs(playerCache) do unbindPlayer(pl) end
        ui:Destroy()
    end,
})

----------------------------------------------------------------
-- Boot
----------------------------------------------------------------
ui:Show()
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Pro ESP",
        Text = "Loaded — RightShift to toggle UI",
        Duration = 4,
    })
end)
print("[ProESP] loaded")
