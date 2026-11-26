--[[
    Universal Pro ESP — Full
    LiteUI · 6 tabs · pooled drawings · event cache · nested world scan

    Player · World · Filters · Visuals · Perf · Settings
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
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local LP = Players.LocalPlayer

local function cam()
    return Workspace.CurrentCamera
end

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local CFG = {
    master = true,

    -- Player
    boxes        = true,
    boxStyle     = "Corner", -- Full | Corner | Filled
    boxFillTrans = 0.75,
    names        = true,
    useDisplay   = true,
    healthBar    = true,
    healthNum    = true,
    distance     = true,
    skeleton     = false,
    headCircle   = false,
    headDot      = true,
    tracers      = true,
    tracerFrom   = "Bottom", -- Top | Center | Bottom
    chams        = true,
    weapon       = true,
    statusIcons  = true,
    showRig      = false,
    closestMark  = true,

    -- World
    npcEsp       = false,
    bossEsp      = true,
    itemEsp      = false,
    weaponDrop   = true,
    chestEsp     = true,
    vehicleEsp   = false,
    objectiveEsp = false,

    -- Filters
    teamCheck    = true,
    friendCheck  = true,
    visCheck     = true,
    maxDist      = 1500,
    entityLimit  = 80,
    onlyEnemies  = false,

    -- Visuals
    colEnemy     = Color3.fromRGB(255, 75, 75),
    colAlly      = Color3.fromRGB(80, 180, 255),
    colFriend    = Color3.fromRGB(80, 255, 140),
    colNpc      = Color3.fromRGB(255, 200, 60),
    colBoss      = Color3.fromRGB(255, 80, 200),
    colItem      = Color3.fromRGB(180, 100, 255),
    colWeapon    = Color3.fromRGB(255, 160, 60),
    colChest     = Color3.fromRGB(255, 220, 100),
    colVehicle   = Color3.fromRGB(140, 120, 255),
    colObjective = Color3.fromRGB(100, 255, 220),
    rainbow      = false,
    distFade     = true,
    boxThick     = 1,
    skelThick    = 1.2,
    tracerThick  = 1,
    textSize     = 13,
    textOutline  = true,

    -- Performance
    updateEvery    = 0,
    worldScanEvery = 1.5,
}

local ITEM_KEYWORDS = {
    "tool", "pickaxe", "gun", "rifle", "pistol", "key", "chest", "crate",
    "loot", "egg", "coin", "gem", "ore", "resource", "bag", "backpack",
    "medkit", "ammo", "weapon", "sword", "bow", "staff",
}
local CHEST_KEYWORDS = { "chest", "crate", "lootbox", "loot_box", "supply", "cache" }
local OBJECTIVE_KEYWORDS = { "objective", "flag", "point", "capture", "payload", "bomb", "site", "extract" }
local BOSS_KEYWORDS = { "boss", "raidboss", "miniboss", "elite" }

----------------------------------------------------------------
-- Drawing pool
----------------------------------------------------------------
local function dnew(kind)
    if not Drawing then return nil end
    local s, o = pcall(Drawing.new, kind)
    return s and o or nil
end

local pool = { square = {}, line = {}, text = {}, circle = {} }

local function acquire(kind)
    local b = pool[kind]
    if b and #b > 0 then return table.remove(b) end
    if kind == "square" then
        local o = dnew("Square")
        if o then o.Filled = false; o.Thickness = 1; o.Visible = false end
        return o
    elseif kind == "line" then
        local o = dnew("Line")
        if o then o.Thickness = 1; o.Visible = false end
        return o
    elseif kind == "text" then
        local o = dnew("Text")
        if o then o.Center = true; o.Outline = true; o.Size = 13; o.Visible = false end
        return o
    elseif kind == "circle" then
        local o = dnew("Circle")
        if o then o.Filled = false; o.Thickness = 1; o.NumSides = 24; o.Visible = false end
        return o
    end
end

local function release(kind, obj)
    if not obj then return end
    pcall(function() obj.Visible = false end)
    pool[kind] = pool[kind] or {}
    if #pool[kind] < 400 then
        table.insert(pool[kind], obj)
    else
        pcall(function() obj:Remove() end)
    end
end

local function releaseList(kind, list)
    if not list then return end
    for i = #list, 1, -1 do
        release(kind, list[i])
        list[i] = nil
    end
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function alive(model)
    if not model then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function isFriend(pl)
    local s, fr = pcall(function() return LP:IsFriendsWith(pl.UserId) end)
    return s and fr == true
end

local function isEnemy(pl)
    if not pl or pl == LP then return false end
    if not CFG.teamCheck then return true end
    if pl.Team == nil or LP.Team == nil then return true end
    return pl.Team ~= LP.Team
end

local function playerColor(pl)
    if CFG.friendCheck and isFriend(pl) then return CFG.colFriend, "friend" end
    if isEnemy(pl) then return CFG.colEnemy, "enemy" end
    return CFG.colAlly, "ally"
end

local function rainbowColor(t)
    return Color3.fromHSV((t * 0.12) % 1, 0.85, 1)
end

local function fadeColor(col, dist)
    if not CFG.distFade then return col end
    local k = 1 - math.clamp(dist / math.max(CFG.maxDist, 1), 0, 1) * 0.55
    return Color3.new(col.R * k, col.G * k, col.B * k)
end

local function behindWall(from, to, model)
    if not CFG.visCheck then return false end
    rayParams.FilterDescendantsInstances = { LP.Character, model }
    return Workspace:Raycast(from, to - from, rayParams) ~= nil
end

local function nameHas(name, list)
    local lower = string.lower(name)
    for _, kw in ipairs(list) do
        if string.find(lower, kw, 1, true) then return true end
    end
    return false
end

local function getToolName(model)
    local t = model:FindFirstChildOfClass("Tool")
    return t and t.Name or nil
end

local function rigType(model)
    if model:FindFirstChild("UpperTorso") then return "R15" end
    if model:FindFirstChild("Torso") then return "R6" end
    return "?"
end

local R15_BONES = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local R6_BONES = {
    { "Head", "Torso" },
    { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

----------------------------------------------------------------
-- Player cache
----------------------------------------------------------------
local playerCache = {}

local function unbindPlayer(pl)
    playerCache[pl] = nil
end

local function bindCharacter(pl, char)
    if not char then return end
    task.defer(function()
        for _ = 1, 25 do
            if not char.Parent then return end
            local root = char:FindFirstChild("HumanoidRootPart")
                or char:FindFirstChild("UpperTorso")
                or char:FindFirstChild("Torso")
            local head = char:FindFirstChild("Head")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if root and hum then
                playerCache[pl] = { model = char, hum = hum, root = root, head = head or root }
                return
            end
            task.wait(0.1)
        end
    end)
end

local function trackPlayer(pl)
    if pl == LP then return end
    if pl.Character then bindCharacter(pl, pl.Character) end
    pl.CharacterAdded:Connect(function(c) bindCharacter(pl, c) end)
    pl.CharacterRemoving:Connect(function() unbindPlayer(pl) end)
end

for _, pl in ipairs(Players:GetPlayers()) do trackPlayer(pl) end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(function(pl) unbindPlayer(pl) end)

----------------------------------------------------------------
-- Nested world scan
----------------------------------------------------------------
local worldCache = {
    npcs = {}, bosses = {}, items = {}, weapons = {},
    chests = {}, vehicles = {}, objectives = {},
}
local lastWorldScan = 0

local function clearWorld()
    for k in pairs(worldCache) do worldCache[k] = {} end
end

local function scanWorld()
    local need = CFG.npcEsp or CFG.bossEsp or CFG.itemEsp or CFG.weaponDrop
        or CFG.chestEsp or CFG.vehicleEsp or CFG.objectiveEsp
    if not need then clearWorld() return end

    local now = os.clock()
    if now - lastWorldScan < CFG.worldScanEvery then return end
    lastWorldScan = now

    local origin = cam().CFrame.Position
    local maxD = CFG.maxDist * 1.25
    local npcs, bosses, items, weapons, chests, vehicles, objectives =
        {}, {}, {}, {}, {}, {}, {}

    local function considerModel(m)
        if not m:IsA("Model") then return end
        if Players:GetPlayerFromCharacter(m) then return end

        local hum = m:FindFirstChildOfClass("Humanoid")
        local root = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head")
        if hum and root and hum.Health > 0 then
            if (root.Position - origin).Magnitude <= maxD then
                local entry = { model = m, root = root, hum = hum, name = m.Name }
                if nameHas(m.Name, BOSS_KEYWORDS) then
                    table.insert(bosses, entry)
                else
                    table.insert(npcs, entry)
                end
            end
            return
        end

        local seat = m:FindFirstChildWhichIsA("VehicleSeat", true)
        if seat and (seat.Position - origin).Magnitude <= maxD then
            table.insert(vehicles, { model = m, part = seat, name = m.Name })
        end
    end

    local function considerPartish(inst)
        local part = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
        if not part then return end
        if (part.Position - origin).Magnitude > maxD then return end
        local n = inst.Name
        if CFG.chestEsp and nameHas(n, CHEST_KEYWORDS) then
            table.insert(chests, { inst = inst, part = part, name = n })
        elseif CFG.objectiveEsp and nameHas(n, OBJECTIVE_KEYWORDS) then
            table.insert(objectives, { inst = inst, part = part, name = n })
        elseif inst:IsA("Tool") or nameHas(n, { "gun", "rifle", "pistol", "weapon", "sword" }) then
            if CFG.weaponDrop then
                table.insert(weapons, { inst = inst, part = part, name = n })
            end
        elseif CFG.itemEsp and nameHas(n, ITEM_KEYWORDS) then
            table.insert(items, { inst = inst, part = part, name = n })
        end
    end

    local function walk(parent, depth)
        if depth > 4 then return end
        for _, ch in ipairs(parent:GetChildren()) do
            if ch:IsA("Model") then
                considerModel(ch)
                walk(ch, depth + 1)
            elseif ch:IsA("Folder") or ch:IsA("Configuration") then
                walk(ch, depth + 1)
            else
                considerPartish(ch)
            end
        end
    end

    walk(Workspace, 0)
    worldCache.npcs = npcs
    worldCache.bosses = bosses
    worldCache.items = items
    worldCache.weapons = weapons
    worldCache.chests = chests
    worldCache.vehicles = vehicles
    worldCache.objectives = objectives
end

----------------------------------------------------------------
-- Draw state
----------------------------------------------------------------
local drawState = {}

local function freeEntry(key)
    local e = drawState[key]
    if not e then return end
    release("square", e.box)
    release("square", e.boxFill)
    releaseList("line", e.corners)
    release("text", e.name)
    release("line", e.health)
    release("line", e.tracer)
    release("circle", e.headCircle)
    release("circle", e.headDot)
    releaseList("line", e.bones)
    if e.chams then pcall(function() e.chams:Destroy() end) end
    drawState[key] = nil
end

local function ensureEntry(key)
    if drawState[key] then return drawState[key] end
    drawState[key] = { corners = {}, bones = {} }
    return drawState[key]
end

----------------------------------------------------------------
-- Geometry
----------------------------------------------------------------
local function worldBox(model)
    local C = cam()
    local parts = {}
    for _, p in ipairs(model:GetChildren()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            table.insert(parts, p)
        end
    end
    if #parts == 0 then
        local r = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
        if not r then return nil end
        local sp, on = C:WorldToViewportPoint(r.Position)
        if sp.Z <= 0 then return nil end
        return Vector2.new(sp.X - 18, sp.Y - 28), Vector2.new(36, 56)
    end

    local minV = Vector3.new(1e9, 1e9, 1e9)
    local maxV = Vector3.new(-1e9, -1e9, -1e9)
    for _, p in ipairs(parts) do
        local cf, sz = p.CFrame, p.Size * 0.5
        for _, sx in ipairs({ -1, 1 }) do
            for _, sy in ipairs({ -1, 1 }) do
                for _, szz in ipairs({ -1, 1 }) do
                    local w = cf * Vector3.new(sx * sz.X, sy * sz.Y, szz * sz.Z)
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
        local sp = C:WorldToViewportPoint(c)
        if sp.Z > 0 then
            any = true
            min2 = Vector2.new(math.min(min2.X, sp.X), math.min(min2.Y, sp.Y))
            max2 = Vector2.new(math.max(max2.X, sp.X), math.max(max2.Y, sp.Y))
        end
    end
    if not any then return nil end
    local vs = C.ViewportSize
    min2 = Vector2.new(math.clamp(min2.X, -80, vs.X + 80), math.clamp(min2.Y, -80, vs.Y + 80))
    max2 = Vector2.new(math.clamp(max2.X, -80, vs.X + 80), math.clamp(max2.Y, -80, vs.Y + 80))
    local size = max2 - min2
    if size.X < 2 or size.Y < 2 then return nil end
    return min2, size
end

local function hideBoxes(e)
    if e.box then e.box.Visible = false end
    if e.boxFill then e.boxFill.Visible = false end
    if e.corners then
        for _, ln in ipairs(e.corners) do if ln then ln.Visible = false end end
    end
end

local function drawCornerBox(e, topLeft, size, color)
    local x, y, w, h = topLeft.X, topLeft.Y, size.X, size.Y
    local len = math.clamp(math.min(w, h) * 0.25, 4, 16)
    while #e.corners < 8 do table.insert(e.corners, acquire("line")) end
    local pts = {
        { Vector2.new(x, y), Vector2.new(x + len, y) },
        { Vector2.new(x, y), Vector2.new(x, y + len) },
        { Vector2.new(x + w, y), Vector2.new(x + w - len, y) },
        { Vector2.new(x + w, y), Vector2.new(x + w, y + len) },
        { Vector2.new(x, y + h), Vector2.new(x + len, y + h) },
        { Vector2.new(x, y + h), Vector2.new(x, y + h - len) },
        { Vector2.new(x + w, y + h), Vector2.new(x + w - len, y + h) },
        { Vector2.new(x + w, y + h), Vector2.new(x + w, y + h - len) },
    }
    for i = 1, 8 do
        local ln = e.corners[i]
        if ln then
            ln.From = pts[i][1]; ln.To = pts[i][2]
            ln.Color = color; ln.Thickness = CFG.boxThick; ln.Visible = true
        end
    end
    if e.box then e.box.Visible = false end
    if e.boxFill then e.boxFill.Visible = false end
end

local function drawFullBox(e, topLeft, size, color, filled)
    if e.corners then
        for _, ln in ipairs(e.corners) do if ln then ln.Visible = false end end
    end
    if filled then
        if not e.boxFill then e.boxFill = acquire("square") end
        if e.boxFill then
            e.boxFill.Filled = true
            e.boxFill.Position = topLeft
            e.boxFill.Size = size
            e.boxFill.Color = color
            e.boxFill.Transparency = CFG.boxFillTrans
            e.boxFill.Visible = true
        end
    elseif e.boxFill then
        e.boxFill.Visible = false
    end
    if not e.box then e.box = acquire("square") end
    if e.box then
        e.box.Filled = false
        e.box.Position = topLeft
        e.box.Size = size
        e.box.Color = color
        e.box.Thickness = CFG.boxThick
        e.box.Visible = true
    end
end

local function renderSkeleton(e, model, color)
    local bones = model:FindFirstChild("UpperTorso") and R15_BONES or R6_BONES
    while #e.bones < #bones do table.insert(e.bones, acquire("line")) end
    local C = cam()
    for i, pair in ipairs(bones) do
        local ln = e.bones[i]
        if not ln then continue end
        local a = model:FindFirstChild(pair[1])
        local b = model:FindFirstChild(pair[2])
        if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
            local sa = C:WorldToViewportPoint(a.Position)
            local sb = C:WorldToViewportPoint(b.Position)
            if sa.Z > 0 and sb.Z > 0 then
                ln.From = Vector2.new(sa.X, sa.Y)
                ln.To = Vector2.new(sb.X, sb.Y)
                ln.Color = color
                ln.Thickness = CFG.skelThick
                ln.Visible = true
            else
                ln.Visible = false
            end
        else
            ln.Visible = false
        end
    end
    for i = #bones + 1, #e.bones do
        if e.bones[i] then e.bones[i].Visible = false end
    end
end

----------------------------------------------------------------
-- Render model / world label
----------------------------------------------------------------
local function renderModelESP(key, model, label, color, hum, root, head, extra)
    if not model or not root then return false end
    local isAlive = hum and hum.Health > 0
    if not isAlive and not CFG.statusIcons then return false end

    local C = cam()
    local origin = C.CFrame.Position
    local dist = (root.Position - origin).Magnitude
    if dist > CFG.maxDist then return false end

    local e = ensureEntry(key)
    if CFG.rainbow then color = rainbowColor(os.clock() + dist * 0.01) end
    color = fadeColor(color, dist)

    local blocked = behindWall(origin, root.Position, model)
    if blocked then
        color = Color3.new(color.R * 0.4, color.G * 0.4, color.B * 0.4)
    end

    local topLeft, size = worldBox(model)
    if not topLeft then
        hideBoxes(e)
        if e.name then e.name.Visible = false end
        if e.health then e.health.Visible = false end
        if e.tracer then e.tracer.Visible = false end
        if e.headCircle then e.headCircle.Visible = false end
        if e.headDot then e.headDot.Visible = false end
        if e.bones then for _, ln in ipairs(e.bones) do if ln then ln.Visible = false end end end
        return true
    end

    if CFG.boxes then
        if CFG.boxStyle == "Corner" then
            drawCornerBox(e, topLeft, size, color)
        elseif CFG.boxStyle == "Filled" then
            drawFullBox(e, topLeft, size, color, true)
        else
            drawFullBox(e, topLeft, size, color, false)
        end
    else
        hideBoxes(e)
    end

    local bits = {}
    if CFG.names then table.insert(bits, label) end
    if CFG.distance then table.insert(bits, string.format("%dm", math.floor(dist))) end
    if CFG.healthNum and hum then
        table.insert(bits, string.format("%d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth)))
    end
    if CFG.weapon and extra and extra.weapon then table.insert(bits, extra.weapon) end
    if CFG.showRig and extra and extra.rig then table.insert(bits, extra.rig) end
    if CFG.statusIcons then
        if not isAlive then table.insert(bits, "DEAD") end
        if blocked and CFG.visCheck then table.insert(bits, "WALL") end
        if extra and extra.friend then table.insert(bits, "FRIEND") end
        if extra and extra.closest then table.insert(bits, "★") end
    end

    if #bits > 0 then
        if not e.name then e.name = acquire("text") end
        if e.name then
            e.name.Text = table.concat(bits, " · ")
            e.name.Size = CFG.textSize
            e.name.Outline = CFG.textOutline
            e.name.Color = color
            e.name.Position = Vector2.new(topLeft.X + size.X * 0.5, topLeft.Y - 14)
            e.name.Visible = true
        end
    elseif e.name then
        e.name.Visible = false
    end

    if CFG.healthBar and hum and isAlive then
        if not e.health then e.health = acquire("line") end
        if e.health then
            local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            local h = size.Y * hp
            e.health.From = Vector2.new(topLeft.X - 5, topLeft.Y + size.Y)
            e.health.To   = Vector2.new(topLeft.X - 5, topLeft.Y + size.Y - h)
            e.health.Color = Color3.fromRGB(255 * (1 - hp), 255 * hp, 40)
            e.health.Thickness = 2
            e.health.Visible = true
        end
    elseif e.health then
        e.health.Visible = false
    end

    if CFG.tracers then
        if not e.tracer then e.tracer = acquire("line") end
        if e.tracer then
            local vs = C.ViewportSize
            local from
            if CFG.tracerFrom == "Top" then
                from = Vector2.new(vs.X * 0.5, 0)
            elseif CFG.tracerFrom == "Center" then
                from = vs * 0.5
            else
                from = Vector2.new(vs.X * 0.5, vs.Y)
            end
            e.tracer.From = from
            e.tracer.To = Vector2.new(topLeft.X + size.X * 0.5, topLeft.Y + size.Y)
            e.tracer.Color = color
            e.tracer.Thickness = CFG.tracerThick
            e.tracer.Visible = true
        end
    elseif e.tracer then
        e.tracer.Visible = false
    end

    local headPart = head or model:FindFirstChild("Head")
    if headPart then
        local sp = C:WorldToViewportPoint(headPart.Position)
        if sp.Z > 0 then
            if CFG.headCircle then
                if not e.headCircle then e.headCircle = acquire("circle") end
                if e.headCircle then
                    e.headCircle.Position = Vector2.new(sp.X, sp.Y)
                    e.headCircle.Radius = math.clamp(size.X * 0.15, 4, 18)
                    e.headCircle.Filled = false
                    e.headCircle.Color = color
                    e.headCircle.Visible = true
                end
            elseif e.headCircle then
                e.headCircle.Visible = false
            end
            if CFG.headDot then
                if not e.headDot then e.headDot = acquire("circle") end
                if e.headDot then
                    e.headDot.Position = Vector2.new(sp.X, sp.Y)
                    e.headDot.Radius = 2.5
                    e.headDot.Filled = true
                    e.headDot.Color = color
                    e.headDot.Visible = true
                end
            elseif e.headDot then
                e.headDot.Visible = false
            end
        else
            if e.headCircle then e.headCircle.Visible = false end
            if e.headDot then e.headDot.Visible = false end
        end
    end

    if CFG.skeleton then
        renderSkeleton(e, model, color)
    elseif e.bones then
        for _, ln in ipairs(e.bones) do if ln then ln.Visible = false end end
    end

    if CFG.chams then
        if not e.chams or not e.chams.Parent then
            local hl = Instance.new("Highlight")
            hl.Name = "ProESP_Chams"
            hl.FillTransparency = 0.62
            hl.OutlineTransparency = 0.3
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = model
            e.chams = hl
        end
        e.chams.FillColor = color
        e.chams.OutlineColor = color
        e.chams.Enabled = true
    elseif e.chams then
        e.chams.Enabled = false
    end

    return true
end

local function renderWorldLabel(key, part, text, color)
    local C = cam()
    local dist = (part.Position - C.CFrame.Position).Magnitude
    if dist > CFG.maxDist then return false end
    if CFG.rainbow then color = rainbowColor(os.clock()) end
    color = fadeColor(color, dist)

    local sp = C:WorldToViewportPoint(part.Position)
    if sp.Z <= 0 then return false end

    local e = ensureEntry(key)
    if not e.name then e.name = acquire("text") end
    if e.name then
        e.name.Text = string.format("%s · %dm", text, math.floor(dist))
        e.name.Size = CFG.textSize
        e.name.Outline = CFG.textOutline
        e.name.Color = color
        e.name.Position = Vector2.new(sp.X, sp.Y - 8)
        e.name.Visible = true
    end
    hideBoxes(e)
    if e.health then e.health.Visible = false end
    if e.tracer then e.tracer.Visible = false end
    if e.headCircle then e.headCircle.Visible = false end
    if e.headDot then e.headDot.Visible = false end
    if e.bones then for _, ln in ipairs(e.bones) do if ln then ln.Visible = false end end end
    if e.chams then e.chams.Enabled = false end
    return true
end

----------------------------------------------------------------
-- Main loop
----------------------------------------------------------------
local lastFrame = 0

RunService.RenderStepped:Connect(function()
    if not CFG.master then
        for k in pairs(drawState) do freeEntry(k) end
        return
    end

    if CFG.updateEvery > 0 then
        local now = os.clock()
        if now - lastFrame < CFG.updateEvery then return end
        lastFrame = now
    end

    pcall(scanWorld)

    local keep = {}
    local rendered = 0
    local limit = CFG.entityLimit
    local origin = cam().CFrame.Position

    local closestPl, closestDist = nil, math.huge
    for pl, data in pairs(playerCache) do
        if data.root and data.model and alive(data.model) and isEnemy(pl) then
            local d = (data.root.Position - origin).Magnitude
            if d < closestDist then closestDist = d; closestPl = pl end
        end
    end

    for pl, data in pairs(playerCache) do
        if rendered >= limit then break end
        if not data.model or not data.root then continue end
        if CFG.onlyEnemies and not isEnemy(pl) and not (CFG.friendCheck and isFriend(pl)) then
            continue
        end
        local col, kind = playerColor(pl)
        local label = (CFG.useDisplay and pl.DisplayName ~= "" and pl.DisplayName) or pl.Name
        local extra = {
            weapon = CFG.weapon and getToolName(data.model) or nil,
            rig = CFG.showRig and rigType(data.model) or nil,
            friend = kind == "friend",
            closest = CFG.closestMark and pl == closestPl,
        }
        if renderModelESP(pl, data.model, label, col, data.hum, data.root, data.head, extra) then
            keep[pl] = true
            rendered += 1
        end
    end

    local function batch(list, enabled, color, useModel)
        if not enabled then return end
        for _, entry in ipairs(list) do
            if rendered >= limit then return end
            if useModel then
                if renderModelESP(entry.model, entry.model, entry.name, color, entry.hum, entry.root, nil, nil) then
                    keep[entry.model] = true
                    rendered += 1
                end
            else
                local key = entry.inst or entry.model
                if renderWorldLabel(key, entry.part, entry.name, color) then
                    keep[key] = true
                    rendered += 1
                end
            end
        end
    end

    batch(worldCache.bosses, CFG.bossEsp, CFG.colBoss, true)
    batch(worldCache.npcs, CFG.npcEsp, CFG.colNpc, true)
    batch(worldCache.items, CFG.itemEsp, CFG.colItem, false)
    batch(worldCache.weapons, CFG.weaponDrop, CFG.colWeapon, false)
    batch(worldCache.chests, CFG.chestEsp, CFG.colChest, false)
    batch(worldCache.vehicles, CFG.vehicleEsp, CFG.colVehicle, false)
    batch(worldCache.objectives, CFG.objectiveEsp, CFG.colObjective, false)

    for k in pairs(drawState) do
        if not keep[k] then freeEntry(k) end
    end
end)

----------------------------------------------------------------
-- LiteUI — 6 tabs
----------------------------------------------------------------
Lite.Themes.proesp = {
    bg = Color3.fromRGB(12, 14, 18), line = Color3.fromRGB(36, 42, 52),
    text = Color3.fromRGB(235, 240, 245), sub = Color3.fromRGB(130, 140, 155),
    accent = Color3.fromRGB(100, 170, 255), warn = Color3.fromRGB(255, 190, 60),
    danger = Color3.fromRGB(255, 80, 80), track = Color3.fromRGB(26, 30, 38),
}

local ui = Lite.new({
    Title = "Pro ESP",
    Subtitle = "Full · Universal",
    Width = 380,
    Theme = "proesp",
})

local tab = ui:Tabs(
    { "Player", "World", "Filters", "Visuals", "Perf", "Settings" },
    { MaxHeight = 340 }
)

local PRESETS = {
    Red = Color3.fromRGB(255, 75, 75), Orange = Color3.fromRGB(255, 160, 40),
    Yellow = Color3.fromRGB(255, 220, 60), Green = Color3.fromRGB(70, 220, 100),
    Cyan = Color3.fromRGB(60, 200, 255), Blue = Color3.fromRGB(80, 140, 255),
    Purple = Color3.fromRGB(180, 100, 255), Pink = Color3.fromRGB(255, 100, 180),
    White = Color3.fromRGB(240, 240, 240),
}
local cnames = { "Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Purple", "Pink", "White" }

-- Player
local p = tab.Player
p:Section("Master")
p:Toggle({ Name = "Enable ESP", Flag = "master", Default = CFG.master, Callback = function(v)
    CFG.master = v
    if not v then for k in pairs(drawState) do freeEntry(k) end end
end })
p:Section("Boxes")
p:Toggle({ Name = "Boxes", Flag = "boxes", Default = CFG.boxes, Callback = function(v) CFG.boxes = v end })
p:Dropdown({ Name = "Box style", Flag = "boxStyle", Options = { "Full", "Corner", "Filled" }, Default = CFG.boxStyle, Callback = function(v) CFG.boxStyle = v end })
p:Slider({ Name = "Fill transparency", Flag = "boxFillTrans", Min = 0.3, Max = 0.95, Default = CFG.boxFillTrans, Step = 0.05, Callback = function(v) CFG.boxFillTrans = v end })
p:Section("Info")
p:Toggle({ Name = "Names", Flag = "names", Default = CFG.names, Callback = function(v) CFG.names = v end })
p:Toggle({ Name = "Use display name", Flag = "useDisplay", Default = CFG.useDisplay, Callback = function(v) CFG.useDisplay = v end })
p:Toggle({ Name = "Health bar", Flag = "healthBar", Default = CFG.healthBar, Callback = function(v) CFG.healthBar = v end })
p:Toggle({ Name = "Health numbers", Flag = "healthNum", Default = CFG.healthNum, Callback = function(v) CFG.healthNum = v end })
p:Toggle({ Name = "Distance", Flag = "distance", Default = CFG.distance, Callback = function(v) CFG.distance = v end })
p:Toggle({ Name = "Weapon / tool", Flag = "weapon", Default = CFG.weapon, Callback = function(v) CFG.weapon = v end })
p:Toggle({ Name = "Rig type R6/R15", Flag = "showRig", Default = CFG.showRig, Callback = function(v) CFG.showRig = v end })
p:Toggle({ Name = "Status tags", Flag = "statusIcons", Default = CFG.statusIcons, Callback = function(v) CFG.statusIcons = v end })
p:Toggle({ Name = "Closest marker ★", Flag = "closestMark", Default = CFG.closestMark, Callback = function(v) CFG.closestMark = v end })
p:Section("Body")
p:Toggle({ Name = "Skeleton", Flag = "skeleton", Default = CFG.skeleton, Callback = function(v) CFG.skeleton = v end })
p:Toggle({ Name = "Head circle", Flag = "headCircle", Default = CFG.headCircle, Callback = function(v) CFG.headCircle = v end })
p:Toggle({ Name = "Head dot", Flag = "headDot", Default = CFG.headDot, Callback = function(v) CFG.headDot = v end })
p:Toggle({ Name = "Tracers", Flag = "tracers", Default = CFG.tracers, Callback = function(v) CFG.tracers = v end })
p:Dropdown({ Name = "Tracer from", Flag = "tracerFrom", Options = { "Top", "Center", "Bottom" }, Default = CFG.tracerFrom, Callback = function(v) CFG.tracerFrom = v end })
p:Toggle({ Name = "Chams / highlight", Flag = "chams", Default = CFG.chams, Callback = function(v) CFG.chams = v end })

-- World
local w = tab.World
w:Section("Entities")
w:Toggle({ Name = "NPC ESP", Flag = "npcEsp", Default = CFG.npcEsp, Callback = function(v) CFG.npcEsp = v end })
w:Toggle({ Name = "Boss ESP", Flag = "bossEsp", Default = CFG.bossEsp, Callback = function(v) CFG.bossEsp = v end })
w:Toggle({ Name = "Item ESP", Flag = "itemEsp", Default = CFG.itemEsp, Callback = function(v) CFG.itemEsp = v end })
w:Toggle({ Name = "Dropped weapons", Flag = "weaponDrop", Default = CFG.weaponDrop, Callback = function(v) CFG.weaponDrop = v end })
w:Toggle({ Name = "Chests / crates", Flag = "chestEsp", Default = CFG.chestEsp, Callback = function(v) CFG.chestEsp = v end })
w:Toggle({ Name = "Vehicles", Flag = "vehicleEsp", Default = CFG.vehicleEsp, Callback = function(v) CFG.vehicleEsp = v end })
w:Toggle({ Name = "Objectives", Flag = "objectiveEsp", Default = CFG.objectiveEsp, Callback = function(v) CFG.objectiveEsp = v end })
w:Label({ Text = "Nested workspace scan (depth 4)" })

-- Filters
local f = tab.Filters
f:Section("Players")
f:Toggle({ Name = "Team check", Flag = "teamCheck", Default = CFG.teamCheck, Callback = function(v) CFG.teamCheck = v end })
f:Toggle({ Name = "Friend colour", Flag = "friendCheck", Default = CFG.friendCheck, Callback = function(v) CFG.friendCheck = v end })
f:Toggle({ Name = "Only enemies", Flag = "onlyEnemies", Default = CFG.onlyEnemies, Callback = function(v) CFG.onlyEnemies = v end })
f:Toggle({ Name = "Visibility dim", Flag = "visCheck", Default = CFG.visCheck, Callback = function(v) CFG.visCheck = v end })
f:Section("Range")
f:Slider({ Name = "Max distance", Flag = "maxDist", Min = 50, Max = 5000, Default = CFG.maxDist, Step = 50, Callback = function(v) CFG.maxDist = v end })
f:Slider({ Name = "Entity limit", Flag = "entityLimit", Min = 10, Max = 200, Default = CFG.entityLimit, Step = 5, Callback = function(v) CFG.entityLimit = v end })

-- Visuals
local v = tab.Visuals
v:Section("Colours")
v:Dropdown({ Name = "Enemy", Flag = "colEnemy", Options = cnames, Default = "Red", Callback = function(x) CFG.colEnemy = PRESETS[x] or CFG.colEnemy end })
v:Dropdown({ Name = "Ally", Flag = "colAlly", Options = cnames, Default = "Cyan", Callback = function(x) CFG.colAlly = PRESETS[x] or CFG.colAlly end })
v:Dropdown({ Name = "Friend", Flag = "colFriend", Options = cnames, Default = "Green", Callback = function(x) CFG.colFriend = PRESETS[x] or CFG.colFriend end })
v:Dropdown({ Name = "NPC", Flag = "colNpc", Options = cnames, Default = "Yellow", Callback = function(x) CFG.colNpc = PRESETS[x] or CFG.colNpc end })
v:Dropdown({ Name = "Boss", Flag = "colBoss", Options = cnames, Default = "Pink", Callback = function(x) CFG.colBoss = PRESETS[x] or CFG.colBoss end })
v:Dropdown({ Name = "Item", Flag = "colItem", Options = cnames, Default = "Purple", Callback = function(x) CFG.colItem = PRESETS[x] or CFG.colItem end })
v:Dropdown({ Name = "Weapon drop", Flag = "colWeapon", Options = cnames, Default = "Orange", Callback = function(x) CFG.colWeapon = PRESETS[x] or CFG.colWeapon end })
v:Dropdown({ Name = "Chest", Flag = "colChest", Options = cnames, Default = "Yellow", Callback = function(x) CFG.colChest = PRESETS[x] or CFG.colChest end })
v:Dropdown({ Name = "Vehicle", Flag = "colVehicle", Options = cnames, Default = "Purple", Callback = function(x) CFG.colVehicle = PRESETS[x] or CFG.colVehicle end })
v:Dropdown({ Name = "Objective", Flag = "colObjective", Options = cnames, Default = "Cyan", Callback = function(x) CFG.colObjective = PRESETS[x] or CFG.colObjective end })
v:Section("Effects")
v:Toggle({ Name = "Rainbow", Flag = "rainbow", Default = CFG.rainbow, Callback = function(x) CFG.rainbow = x end })
v:Toggle({ Name = "Distance fade", Flag = "distFade", Default = CFG.distFade, Callback = function(x) CFG.distFade = x end })
v:Section("Thickness / text")
v:Slider({ Name = "Box thickness", Flag = "boxThick", Min = 1, Max = 4, Default = CFG.boxThick, Step = 0.5, Callback = function(x) CFG.boxThick = x end })
v:Slider({ Name = "Skeleton thickness", Flag = "skelThick", Min = 1, Max = 4, Default = CFG.skelThick, Step = 0.1, Callback = function(x) CFG.skelThick = x end })
v:Slider({ Name = "Tracer thickness", Flag = "tracerThick", Min = 1, Max = 4, Default = CFG.tracerThick, Step = 0.1, Callback = function(x) CFG.tracerThick = x end })
v:Slider({ Name = "Text size", Flag = "textSize", Min = 10, Max = 22, Default = CFG.textSize, Step = 1, Callback = function(x) CFG.textSize = x end })
v:Toggle({ Name = "Text outline", Flag = "textOutline", Default = CFG.textOutline, Callback = function(x) CFG.textOutline = x end })

-- Perf
local pf = tab.Perf
pf:Section("Update rates")
pf:Slider({ Name = "ESP interval (0=frame)", Flag = "updateEvery", Min = 0, Max = 0.2, Default = CFG.updateEvery, Step = 0.01, Callback = function(x) CFG.updateEvery = x end })
pf:Slider({ Name = "World scan interval", Flag = "worldScanEvery", Min = 0.5, Max = 5, Default = CFG.worldScanEvery, Step = 0.25, Callback = function(x) CFG.worldScanEvery = x end })
pf:Label({ Text = "Pooling + event player cache on" })
pf:Section("Limits")
pf:Slider({ Name = "Entity limit", Flag = "entityLimit2", Min = 10, Max = 200, Default = CFG.entityLimit, Step = 5, Callback = function(x) CFG.entityLimit = x end })

-- Settings
local s = tab.Settings
s:Section("UI")
ui:Settings({ Panel = s })
s:Separator()
s:Section("Profiles")
ui:Profiles({ Panel = s })
s:Separator()
s:Button({
    Name = "Unload",
    Callback = function()
        CFG.master = false
        for k in pairs(drawState) do freeEntry(k) end
        clearWorld()
        ui:Destroy()
    end,
})

----------------------------------------------------------------
ui:Show()
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Pro ESP Full",
        Text = "6 tabs · RightShift to toggle",
        Duration = 4,
    })
end)
print("[ProESP Full] loaded")
