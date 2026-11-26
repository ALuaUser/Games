--[[
    Egg ESP + Charms  ·  LiteUI
    WorldEggs / WorldEgg tag · per-type toggles · Gold/Void/Meteor/Giant
    Alerts · nearest list · beam · rare timer · hook-range · lock · counts
]]

local LIB_URL = "https://raw.githubusercontent.com/ALuaUser/UIs/refs/heads/main/Grokware/v0.0.7/Source.lua"

local ok, Lite = pcall(function()
    return loadstring(game:HttpGet(LIB_URL))()
end)
if not ok or type(Lite) ~= "table" then
    warn("[EggESP] LiteUI load failed:", Lite)
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()

----------------------------------------------------------------
-- EGG TYPES
----------------------------------------------------------------
local EGGS = {
    ["SwampEgg"] = { on = true, color = Color3.fromRGB(90, 160, 70) },
    ["BearEgg"] = { on = true, color = Color3.fromRGB(160, 110, 70) },
    ["CrystalDemonsEgg"] = { on = true, color = Color3.fromRGB(180, 70, 255) },
    ["CrystalEgg"] = { on = true, color = Color3.fromRGB(120, 220, 255) },
    ["DesertEgg"] = { on = true, color = Color3.fromRGB(230, 190, 90) },
    ["DinosparkEgg"] = { on = true, color = Color3.fromRGB(90, 200, 120) },
    ["ForestEgg"] = { on = true, color = Color3.fromRGB(70, 170, 90) },
    ["FrostbiteEgg"] = { on = true, color = Color3.fromRGB(140, 210, 255) },
    ["HarvestDungeonEgg"] = { on = true, color = Color3.fromRGB(200, 120, 50) },
    ["HarvestMoonEgg"] = { on = true, color = Color3.fromRGB(255, 170, 60) },
    ["HorrorHollowEgg"] = { on = true, color = Color3.fromRGB(180, 50, 50) },
    ["JungleEgg"] = { on = true, color = Color3.fromRGB(50, 180, 80) },
    ["PrehistoricEgg"] = { on = true, color = Color3.fromRGB(170, 140, 90) },
    ["RuinsDungeonEgg"] = { on = true, color = Color3.fromRGB(140, 120, 100) },
    ["SafariEgg"] = { on = true, color = Color3.fromRGB(210, 180, 90) },
    ["SecretEgg"] = { on = true, color = Color3.fromRGB(220, 110, 255) },
    ["SerpentEgg"] = { on = true, color = Color3.fromRGB(80, 200, 150) },
    ["SkyEgg"] = { on = true, color = Color3.fromRGB(100, 180, 255) },
}

----------------------------------------------------------------
-- CONFIG (LiteUI flags drive these)
----------------------------------------------------------------
local CFG = {
    Enabled = true,
    ShowNames = true,
    ShowDistance = true,
    ShowTracers = true,
    ShowBoxes = false,
    ShowCorners = true,
    ShowCharms = true,
    ShowGoldOnly = false,
    ShowSpecialsOnly = false, -- gold/void/meteor/giant/secret/mythic
    MaxDistance = 4000,
    MinDistance = 0,
    TracerFrom = "Bottom",
    TextSize = 14,
    OpacityByDist = false,
    ShowIsle = true,
    ShowCounts = true,
    Alerts = true,
    AlertSound = true,
    NearestList = true,
    NearestMax = 8,
    Beam = true,
    BeamToLocked = true,
    RareTimer = true,
    HookRangeOnly = false,
    HookReach = 48,
    LockEnabled = true,

    GoldColor = Color3.fromRGB(255, 210, 60),
    VoidColor = Color3.fromRGB(170, 90, 255),
    MeteorColor = Color3.fromRGB(255, 120, 40),
}

local H = {
    drawings = {},
    charms = {},
    known = {},      -- [model] = true once seen (for alerts)
    locked = nil,    -- Model
    beam = nil,
    beamAtt0 = nil,
    beamAtt1 = nil,
    beamPart = nil,
    binds = {},
    counts = {},
    nearest = {},
}

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function cam()
    return Workspace.CurrentCamera
end

local function w2s(world)
    local c = cam()
    if not c then
        return Vector2.zero, false, 0
    end
    local v, on = c:WorldToViewportPoint(world)
    return Vector2.new(v.X, v.Y), on and v.Z > 0, v.Z
end

local function myRoot()
    local ch = LP.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function eggRoot(model)
    if not model then
        return nil
    end
    return model.PrimaryPart
        or model:FindFirstChild("Body")
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function isNest(model)
    local n = model and model.Name or ""
    return n:find("Nest", 1, true) ~= nil
end

local function eggTypeName(model)
    if not model then
        return nil
    end
    local id = model:GetAttribute("EggId")
        or model:GetAttribute("EggName")
        or model:GetAttribute("Type")
        or model.Name
    id = tostring(id)
    if EGGS[id] then
        return id
    end
    for name in pairs(EGGS) do
        if id:find(name, 1, true) or name:find(id, 1, true) then
            return name
        end
    end
    if EGGS[model.Name] then
        return model.Name
    end
    return id
end

local function eggVariant(model)
    local g = model:GetAttribute("Gold")
        or model:GetAttribute("StashGold")
        or (model:GetAttribute("GoldLook") and true)
    if g == "Void" or model:GetAttribute("VoidLook") then
        return "Void"
    end
    if g == "Meteor" or model:GetAttribute("MeteorLook") then
        return "Meteor"
    end
    if g == true or g == "Gold" or model:GetAttribute("GoldLook") then
        return "Gold"
    end
    local tier = model:GetAttribute("Tier") or model:GetAttribute("Rarity")
    if tier == "Secret" or tier == "Mythic" or tier == "Legendary" then
        return tostring(tier)
    end
    return nil
end

local function eggSizeTag(model)
    local giant = model:GetAttribute("Giant")
    if giant == true or giant == 1 then
        return "GIANT"
    end
    if type(giant) == "string" and giant ~= "" then
        local lower = string.lower(giant)
        if lower:find("titan") then
            return "TITANIC"
        end
        if lower:find("giant") then
            return "GIANT"
        end
        return string.upper(tostring(giant))
    end
    local scale = model:GetAttribute("Scale") or model:GetAttribute("EndScale")
    if type(scale) == "number" then
        if scale >= 1.2 then
            return "TITANIC"
        end
        if scale >= 0.85 then
            return "GIANT"
        end
        if scale >= 0.6 then
            return "LARGE"
        end
        if scale < 0.35 then
            return "SMALL"
        end
    end
    local root = eggRoot(model)
    if root then
        local m = math.max(root.Size.X, root.Size.Y, root.Size.Z)
        if m >= 12 then
            return "TITANIC"
        end
        if m >= 7 then
            return "GIANT"
        end
    end
    return nil
end

local function isSpecial(model)
    local v = eggVariant(model)
    if v == "Gold" or v == "Void" or v == "Meteor" or v == "Secret" or v == "Mythic" then
        return true
    end
    local s = eggSizeTag(model)
    return s == "GIANT" or s == "TITANIC"
end

local function inHeli()
    local ch = LP.Character
    return ch and ch:GetAttribute("InHeli") == true
end

local function collectEggs()
    local out, seen = {}, {}
    local function add(model)
        if not model or not model:IsA("Model") or seen[model] then
            return
        end
        if isNest(model) then
            return
        end
        if model:GetAttribute("ChuteEnd") then
            return
        end
        if not eggRoot(model) then
            return
        end
        seen[model] = true
        out[#out + 1] = model
    end
    local folder = Workspace:FindFirstChild("WorldEggs")
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            add(child)
        end
    end
    pcall(function()
        for _, m in ipairs(CollectionService:GetTagged("WorldEgg")) do
            if m:IsA("Model") and not isNest(m) then
                add(m)
            end
        end
    end)
    return out
end

----------------------------------------------------------------
-- ALERTS
----------------------------------------------------------------
local function playAlert()
    if not CFG.AlertSound then
        return
    end
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://9116632805"
    s.Volume = 0.45
    s.PlaybackSpeed = 1.4
    s.Parent = SoundService
    s:Play()
    Debris:AddItem(s, 2)
end

local notifyFn -- set after UI

local function alertSpecial(model, typeName, tagStr)
    if not CFG.Alerts then
        return
    end
    if H.known[model] then
        return
    end
    H.known[model] = true
    if not isSpecial(model) then
        return
    end
    local pretty = (typeName or "?"):gsub("Egg$", "")
    local msg = (tagStr and (tagStr .. " ") or "") .. pretty
    playAlert()
    if notifyFn then
        notifyFn("Special egg", msg)
    end
end

----------------------------------------------------------------
-- DRAWINGS / CHARMS / BEAM
----------------------------------------------------------------
local function kill(model)
    local d = H.drawings[model]
    if d then
        for _, v in pairs(d) do
            if typeof(v) == "table" then
                for _, line in pairs(v) do
                    pcall(function()
                        line:Remove()
                    end)
                end
            else
                pcall(function()
                    v:Remove()
                end)
            end
        end
        H.drawings[model] = nil
    end
    local hl = H.charms[model]
    if hl then
        pcall(function()
            hl:Destroy()
        end)
        H.charms[model] = nil
    end
end

local function getDraw(model)
    local d = H.drawings[model]
    if d then
        return d
    end
    local box, corners = {}, {}
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Thickness = 1.5
        l.Visible = false
        box[i] = l
    end
    for i = 1, 8 do
        local l = Drawing.new("Line")
        l.Thickness = 2
        l.Visible = false
        corners[i] = l
    end
    local tracer = Drawing.new("Line")
    tracer.Thickness = 1.3
    tracer.Visible = false
    local name = Drawing.new("Text")
    name.Size = CFG.TextSize
    name.Center = true
    name.Outline = true
    name.Visible = false
    d = { box = box, corners = corners, tracer = tracer, name = name }
    H.drawings[model] = d
    return d
end

local function getCharm(model, color)
    local hl = H.charms[model]
    if hl and hl.Parent then
        hl.FillColor = color
        hl.OutlineColor = color
        return hl
    end
    hl = Instance.new("Highlight")
    hl.Name = "EggCharm"
    hl.Adornee = model
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = 0.55
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = model
    H.charms[model] = hl
    return hl
end

local function ensureBeam()
    if H.beam then
        return
    end
    local p = Instance.new("Part")
    p.Name = "EggESPBeamAnchor"
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Transparency = 1
    p.Size = Vector3.new(0.2, 0.2, 0.2)
    p.Parent = Workspace
    local a0 = Instance.new("Attachment")
    a0.Parent = p
    local a1 = Instance.new("Attachment")
    a1.Parent = p
    local b = Instance.new("Beam")
    b.Attachment0 = a0
    b.Attachment1 = a1
    b.Width0 = 0.35
    b.Width1 = 0.15
    b.FaceCamera = true
    b.LightEmission = 1
    b.Transparency = NumberSequence.new(0.25)
    b.Color = ColorSequence.new(Color3.fromRGB(255, 220, 100))
    b.Enabled = false
    b.Parent = p
    H.beamPart, H.beamAtt0, H.beamAtt1, H.beam = p, a0, a1, b
end

local function setBeam(fromPos, toPos, color, on)
    ensureBeam()
    if not on or not fromPos or not toPos then
        H.beam.Enabled = false
        return
    end
    H.beamPart.CFrame = CFrame.new(fromPos)
    H.beamAtt0.WorldPosition = fromPos
    H.beamAtt1.WorldPosition = toPos
    if color then
        H.beam.Color = ColorSequence.new(color)
    end
    H.beam.Enabled = true
end

local function box2d(part)
    local pos = part.Position
    local size = part.Size
    local half = Vector3.new(
        math.max(size.X * 0.55, 1.2),
        math.max(size.Y * 0.55, 1.5),
        math.max(size.Z * 0.55, 1.2)
    )
    local corners = {
        pos + Vector3.new(half.X, half.Y, half.Z),
        pos + Vector3.new(half.X, half.Y, -half.Z),
        pos + Vector3.new(-half.X, half.Y, -half.Z),
        pos + Vector3.new(-half.X, half.Y, half.Z),
        pos + Vector3.new(half.X, -half.Y, half.Z),
        pos + Vector3.new(half.X, -half.Y, -half.Z),
        pos + Vector3.new(-half.X, -half.Y, -half.Z),
        pos + Vector3.new(-half.X, -half.Y, half.Z),
    }
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local any = false
    for i = 1, 8 do
        local s, on = w2s(corners[i])
        if on then
            any = true
            minX, minY = math.min(minX, s.X), math.min(minY, s.Y)
            maxX, maxY = math.max(maxX, s.X), math.max(maxY, s.Y)
        end
    end
    if not any then
        return nil
    end
    return minX, minY, maxX, maxY
end

local function drawCorners(d, minX, minY, maxX, maxY, color, alpha)
    local w = (maxX - minX) * 0.28
    local h = (maxY - minY) * 0.28
    local pts = {
        { Vector2.new(minX, minY), Vector2.new(minX + w, minY) },
        { Vector2.new(minX, minY), Vector2.new(minX, minY + h) },
        { Vector2.new(maxX, minY), Vector2.new(maxX - w, minY) },
        { Vector2.new(maxX, minY), Vector2.new(maxX, minY + h) },
        { Vector2.new(minX, maxY), Vector2.new(minX + w, maxY) },
        { Vector2.new(minX, maxY), Vector2.new(minX, maxY - h) },
        { Vector2.new(maxX, maxY), Vector2.new(maxX - w, maxY) },
        { Vector2.new(maxX, maxY), Vector2.new(maxX, maxY - h) },
    }
    for i = 1, 8 do
        d.corners[i].From = pts[i][1]
        d.corners[i].To = pts[i][2]
        d.corners[i].Color = color
        d.corners[i].Transparency = alpha or 0
        d.corners[i].Visible = true
    end
end

local function tracerOrigin()
    local c = cam()
    local vs = c and c.ViewportSize or Vector2.new(1920, 1080)
    if CFG.TracerFrom == "Center" then
        return Vector2.new(vs.X / 2, vs.Y / 2)
    elseif CFG.TracerFrom == "Mouse" then
        local inset = GuiService:GetGuiInset()
        return Vector2.new(Mouse.X, Mouse.Y + inset.Y)
    end
    return Vector2.new(vs.X / 2, vs.Y)
end

local function colorFor(model, typeName)
    local tags = {}
    local sizeTag = eggSizeTag(model)
    if sizeTag then
        tags[#tags + 1] = sizeTag
    end
    local variant = eggVariant(model)
    local color
    if variant == "Gold" then
        color = CFG.GoldColor
        tags[#tags + 1] = "GOLD"
    elseif variant == "Void" then
        color = CFG.VoidColor
        tags[#tags + 1] = "VOID"
    elseif variant == "Meteor" then
        color = CFG.MeteorColor
        tags[#tags + 1] = "METEOR"
    elseif variant == "Secret" then
        color = Color3.fromRGB(220, 110, 255)
        tags[#tags + 1] = "SECRET"
    elseif variant == "Mythic" then
        color = Color3.fromRGB(255, 80, 160)
        tags[#tags + 1] = "MYTHIC"
    elseif variant == "Legendary" then
        color = Color3.fromRGB(255, 200, 60)
        tags[#tags + 1] = "LEGENDARY"
    else
        local def = EGGS[typeName]
        color = def and def.color or Color3.fromRGB(200, 200, 210)
    end
    local tagStr = #tags > 0 and table.concat(tags, " ") or nil
    return color, tagStr
end

local function shouldShow(typeName, model, dist)
    if not CFG.Enabled then
        return false
    end
    if isNest(model) or (typeName and tostring(typeName):find("Nest", 1, true)) then
        return false
    end
    if dist and dist > CFG.MaxDistance then
        return false
    end
    if dist and dist < CFG.MinDistance then
        return false
    end
    if CFG.ShowGoldOnly then
        local v = eggVariant(model)
        if not (v == "Gold" or v == "Void" or v == "Meteor") then
            return false
        end
    end
    if CFG.ShowSpecialsOnly and not isSpecial(model) then
        return false
    end
    if CFG.HookRangeOnly and inHeli() then
        if dist and dist > CFG.HookReach then
            return false
        end
    end
    local def = EGGS[typeName]
    if def and def.on == false then
        return false
    end
    return true
end

local function distAlpha(dist)
    if not CFG.OpacityByDist then
        return 0
    end
    local t = math.clamp(dist / math.max(CFG.MaxDistance, 1), 0, 1)
    return t * 0.65
end

----------------------------------------------------------------
-- UPDATE
----------------------------------------------------------------
local rareLabelFn, countsLabelFn, nearestListFn, lockLabelFn

local function update()
    if not CFG.Enabled then
        for m in pairs(H.drawings) do
            kill(m)
        end
        for m in pairs(H.charms) do
            kill(m)
        end
        setBeam(nil, nil, nil, false)
        return
    end

    local root = myRoot()
    local origin = root and root.Position
    local seen = {}
    local eggs = collectEggs()
    local counts = {}
    local nearest = {}

    -- validate lock
    if H.locked and (not H.locked.Parent or isNest(H.locked)) then
        H.locked = nil
    end

    for _, model in ipairs(eggs) do
        local typeName = eggTypeName(model)
        local part = eggRoot(model)
        if not part then
            kill(model)
            continue
        end
        local dist = origin and (origin - part.Position).Magnitude or 0
        if not shouldShow(typeName, model, dist) then
            kill(model)
            continue
        end

        seen[model] = true
        local color, tagStr = colorFor(model, typeName)
        alertSpecial(model, typeName, tagStr)

        local pretty = (typeName or "?"):gsub("Egg$", "")
        counts[pretty] = (counts[pretty] or 0) + 1
        if isSpecial(model) then
            counts["_special"] = (counts["_special"] or 0) + 1
        end

        nearest[#nearest + 1] = {
            model = model,
            name = pretty,
            tag = tagStr,
            dist = dist,
            color = color,
            part = part,
        }

        local d = getDraw(model)
        local alpha = distAlpha(dist)
        local mid, onMid = w2s(part.Position)
        local top, onTop = w2s(part.Position + Vector3.new(0, math.max(part.Size.Y * 0.6, 2), 0))

        local minX, minY, maxX, maxY
        if CFG.ShowBoxes or CFG.ShowCorners then
            minX, minY, maxX, maxY = box2d(part)
        end

        if CFG.ShowBoxes and minX and not CFG.ShowCorners then
            local pts = {
                Vector2.new(minX, minY),
                Vector2.new(maxX, minY),
                Vector2.new(maxX, maxY),
                Vector2.new(minX, maxY),
            }
            for i = 1, 4 do
                d.box[i].From = pts[i]
                d.box[i].To = pts[i % 4 + 1]
                d.box[i].Color = color
                d.box[i].Transparency = alpha
                d.box[i].Visible = true
            end
        else
            for i = 1, 4 do
                d.box[i].Visible = false
            end
        end

        if CFG.ShowCorners and minX then
            drawCorners(d, minX, minY, maxX, maxY, color, alpha)
        else
            for i = 1, 8 do
                d.corners[i].Visible = false
            end
        end

        local showTracer = CFG.ShowTracers
        if H.locked == model then
            showTracer = true
        end
        if showTracer and onMid then
            d.tracer.From = tracerOrigin()
            d.tracer.To = mid
            d.tracer.Color = H.locked == model and Color3.fromRGB(255, 255, 120) or color
            d.tracer.Transparency = alpha
            d.tracer.Thickness = H.locked == model and 2.2 or 1.3
            d.tracer.Visible = true
        else
            d.tracer.Visible = false
        end

        if (CFG.ShowNames or CFG.ShowDistance or CFG.ShowIsle) and onTop then
            local label = ""
            if CFG.ShowNames then
                if tagStr then
                    label = "[" .. tagStr .. "] " .. pretty
                else
                    label = pretty
                end
            end
            if CFG.ShowIsle then
                local isle = model:GetAttribute("Isle")
                if isle then
                    label = label .. " @" .. tostring(isle)
                end
            end
            if CFG.ShowDistance then
                label = label .. string.format(" [%dm]", math.floor(dist))
            end
            if H.locked == model then
                label = "★ " .. label
            end
            d.name.Text = label
            d.name.Position = Vector2.new(top.X, top.Y - 12)
            d.name.Color = color
            d.name.Size = CFG.TextSize
            d.name.Transparency = alpha
            d.name.Visible = true
        else
            d.name.Visible = false
        end

        if CFG.ShowCharms then
            local hl = getCharm(model, color)
            hl.Enabled = true
            hl.FillColor = color
            hl.OutlineColor = H.locked == model and Color3.fromRGB(255, 255, 120) or color
            hl.FillTransparency = 0.55 + alpha * 0.3
        else
            local hl = H.charms[model]
            if hl then
                hl.Enabled = false
            end
        end
    end

    for model in pairs(H.drawings) do
        if not seen[model] then
            kill(model)
        end
    end
    for model in pairs(H.charms) do
        if not seen[model] then
            kill(model)
        end
    end
    for model in pairs(H.known) do
        if not model.Parent then
            H.known[model] = nil
        end
    end

    table.sort(nearest, function(a, b)
        return a.dist < b.dist
    end)
    H.nearest = nearest
    H.counts = counts

    -- beam to locked or nearest special / nearest overall
    if CFG.Beam and origin then
        local targetPart, targetColor
        if CFG.BeamToLocked and H.locked and H.locked.Parent then
            targetPart = eggRoot(H.locked)
            local tn = eggTypeName(H.locked)
            targetColor = select(1, colorFor(H.locked, tn))
        elseif nearest[1] then
            targetPart = nearest[1].part
            targetColor = nearest[1].color
        end
        if targetPart then
            setBeam(origin, targetPart.Position, targetColor, true)
        else
            setBeam(nil, nil, nil, false)
        end
    else
        setBeam(nil, nil, nil, false)
    end

    -- UI refresh (throttled via external labels)
    if countsLabelFn and CFG.ShowCounts then
        local parts = {}
        local specials = counts["_special"] or 0
        if specials > 0 then
            parts[#parts + 1] = "Special " .. specials
        end
        local keys = {}
        for k in pairs(counts) do
            if k ~= "_special" then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            parts[#parts + 1] = k .. " " .. counts[k]
        end
        countsLabelFn(#parts > 0 and table.concat(parts, " · ") or "None")
    end

    if nearestListFn and CFG.NearestList then
        local lines = {}
        local maxn = math.min(CFG.NearestMax, #nearest)
        for i = 1, maxn do
            local e = nearest[i]
            local t = e.tag and ("[" .. e.tag .. "] ") or ""
            lines[#lines + 1] = string.format("%s%s  %dm", t, e.name, math.floor(e.dist))
        end
        nearestListFn(#lines > 0 and table.concat(lines, "\n") or "No eggs")
    end

    if lockLabelFn then
        if H.locked and H.locked.Parent then
            local tn = eggTypeName(H.locked)
            local _, tag = colorFor(H.locked, tn)
            lockLabelFn((tag and ("[" .. tag .. "] ") or "") .. (tn or "?"):gsub("Egg$", ""))
        else
            lockLabelFn("None")
        end
    end
end

-- Rare timer
local function rareText()
    if not CFG.RareTimer then
        return "Off"
    end
    local at = Workspace:GetAttribute("RareEggAt")
    local tier = Workspace:GetAttribute("RareEggTier")
    if type(at) ~= "number" then
        return "—"
    end
    local left = math.max(0, math.ceil(at - Workspace:GetServerTimeNow()))
    local t = tier and tostring(tier) or "?"
    if left <= 0 then
        return t .. " NOW!"
    end
    return string.format("%s  %d:%02d", t, left // 60, left % 60)
end

RunService:BindToRenderStep("EggESP", Enum.RenderPriority.Last.Value, function()
    pcall(update)
    if rareLabelFn then
        rareLabelFn(rareText())
    end
end)
table.insert(H.binds, "EggESP")

Workspace.DescendantRemoving:Connect(function(inst)
    if H.drawings[inst] or H.charms[inst] then
        kill(inst)
    end
    if H.locked == inst then
        H.locked = nil
    end
    H.known[inst] = nil
end)

local function cleanup()
    for _, name in ipairs(H.binds) do
        pcall(function()
            RunService:UnbindFromRenderStep(name)
        end)
    end
    H.binds = {}
    for m in pairs(H.drawings) do
        kill(m)
    end
    for m in pairs(H.charms) do
        kill(m)
    end
    if H.beamPart then
        pcall(function()
            H.beamPart:Destroy()
        end)
        H.beam, H.beamPart = nil, nil
    end
end

-- Lock nearest special / under mouse-ish: key T
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or not CFG.LockEnabled then
        return
    end
    if input.KeyCode == Enum.KeyCode.T then
        -- lock nearest special, else nearest
        local pick
        for _, e in ipairs(H.nearest) do
            if isSpecial(e.model) then
                pick = e.model
                break
            end
        end
        if not pick and H.nearest[1] then
            pick = H.nearest[1].model
        end
        if H.locked == pick then
            H.locked = nil
        else
            H.locked = pick
        end
    elseif input.KeyCode == Enum.KeyCode.Y then
        H.locked = nil
    end
end)

----------------------------------------------------------------
-- LITEUI
----------------------------------------------------------------
Lite.Themes.egg = {
    bg = Color3.fromRGB(22, 24, 30),
    line = Color3.fromRGB(200, 210, 230),
    text = Color3.fromRGB(240, 242, 248),
    sub = Color3.fromRGB(140, 148, 160),
    accent = Color3.fromRGB(120, 200, 150),
    warn = Color3.fromRGB(255, 200, 100),
    danger = Color3.fromRGB(240, 100, 100),
    track = Color3.fromRGB(45, 48, 58),
}

local ui = Lite.new({
    Name = "EggESP",
    Key = Enum.KeyCode.RightShift,
})
ui:Watermark({ Text = "Egg ESP + Charms" })

local card = ui:Card({
    Title = "Egg ESP",
    Subtitle = "WorldEggs · Charms · Alerts",
    Value = "0",
    Tone = "accent",
})

local tab = ui:Tabs({ "ESP", "Filters", "Eggs", "Alerts", "Settings" }, { MaxHeight = 280 })

notifyFn = function(title, text)
    ui:Notify({ Title = title, Text = text, Tone = "warn" })
end

----------------------------------------------------------------
-- ESP tab
----------------------------------------------------------------
local esp = tab.ESP
esp:Section("Display")
esp:Toggle({
    Name = "ESP Enabled",
    Flag = "esp_on",
    Default = true,
    Callback = function(v)
        CFG.Enabled = v
        card:Set({ Value = v and "ON" or "OFF" })
    end,
})
esp:Toggle({ Name = "Names", Flag = "names", Default = true, Callback = function(v) CFG.ShowNames = v end })
esp:Toggle({ Name = "Distance", Flag = "dist", Default = true, Callback = function(v) CFG.ShowDistance = v end })
esp:Toggle({ Name = "Isle tag", Flag = "isle", Default = true, Callback = function(v) CFG.ShowIsle = v end })
esp:Toggle({ Name = "Tracers", Flag = "tracers", Default = true, Callback = function(v) CFG.ShowTracers = v end })
esp:Toggle({ Name = "Corner boxes", Flag = "corners", Default = true, Callback = function(v) CFG.ShowCorners = v end })
esp:Toggle({ Name = "Full boxes", Flag = "boxes", Default = false, Callback = function(v) CFG.ShowBoxes = v end })
esp:Toggle({ Name = "Charms (Highlight)", Flag = "charms", Default = true, Callback = function(v) CFG.ShowCharms = v end })
esp:Toggle({ Name = "Opacity by distance", Flag = "fade", Default = false, Callback = function(v) CFG.OpacityByDist = v end })
esp:Toggle({ Name = "3D beam to target", Flag = "beam", Default = true, Callback = function(v) CFG.Beam = v end })
esp:Dropdown({
    Name = "Tracer origin",
    Options = { "Bottom", "Center", "Mouse" },
    Default = "Bottom",
    Flag = "tracer_from",
    Callback = function(v)
        CFG.TracerFrom = v
    end,
})
esp:Slider({
    Name = "Max distance",
    Min = 200,
    Max = 8000,
    Step = 100,
    Default = 4000,
    Suffix = "m",
    Flag = "maxd",
    Callback = function(v)
        CFG.MaxDistance = v
    end,
})
esp:Slider({
    Name = "Min distance",
    Min = 0,
    Max = 200,
    Step = 5,
    Default = 0,
    Suffix = "m",
    Flag = "mind",
    Callback = function(v)
        CFG.MinDistance = v
    end,
})

esp:Separator()
esp:Section("Live")
local rareStat = esp:Stat({ Name = "Rare egg", Value = "—" })
rareLabelFn = function(t)
    rareStat:Set(t)
end
local countsStat = esp:Paragraph("Counts: —")
countsLabelFn = function(t)
    -- Paragraph may not have Set; try safe update
    pcall(function()
        countsStat:Set(t)
    end)
    pcall(function()
        if countsStat.SetText then
            countsStat:SetText(t)
        end
    end)
end
local nearestPara = esp:Paragraph("Nearest:\n—")
nearestListFn = function(t)
    pcall(function()
        nearestPara:Set("Nearest:\n" .. t)
    end)
    pcall(function()
        if nearestPara.SetText then
            nearestPara:SetText("Nearest:\n" .. t)
        end
    end)
end
local lockStat = esp:Stat({ Name = "Locked", Value = "None" })
lockLabelFn = function(t)
    lockStat:Set(t)
end

esp:Button({
    Name = "Lock nearest special (T)",
    Callback = function()
        local pick
        for _, e in ipairs(H.nearest) do
            if isSpecial(e.model) then
                pick = e.model
                break
            end
        end
        if not pick and H.nearest[1] then
            pick = H.nearest[1].model
        end
        H.locked = pick
    end,
})
esp:Button({
    Name = "Clear lock (Y)",
    Tone = "danger",
    Callback = function()
        H.locked = nil
    end,
})

----------------------------------------------------------------
-- Filters
----------------------------------------------------------------
local fil = tab.Filters
fil:Section("Filters")
fil:Toggle({
    Name = "Gold / Void / Meteor only",
    Flag = "gold_only",
    Default = false,
    Callback = function(v)
        CFG.ShowGoldOnly = v
    end,
})
fil:Toggle({
    Name = "Specials only (Gold+Giant+Secret…)",
    Flag = "specials_only",
    Default = false,
    Callback = function(v)
        CFG.ShowSpecialsOnly = v
    end,
})
fil:Toggle({
    Name = "Hook-range only (in heli)",
    Flag = "hook_range",
    Default = false,
    Tooltip = "When flying, only show eggs within reach",
    Callback = function(v)
        CFG.HookRangeOnly = v
    end,
})
fil:Slider({
    Name = "Hook reach",
    Min = 20,
    Max = 80,
    Step = 2,
    Default = 48,
    Suffix = "m",
    Flag = "hook_reach",
    Callback = function(v)
        CFG.HookReach = v
    end,
})
fil:Toggle({
    Name = "Nearest list",
    Flag = "nearest_list",
    Default = true,
    Callback = function(v)
        CFG.NearestList = v
    end,
})
fil:Slider({
    Name = "Nearest list size",
    Min = 3,
    Max = 15,
    Step = 1,
    Default = 8,
    Flag = "nearest_max",
    Callback = function(v)
        CFG.NearestMax = v
    end,
})
fil:Toggle({
    Name = "Show counts",
    Flag = "counts",
    Default = true,
    Callback = function(v)
        CFG.ShowCounts = v
    end,
})
fil:Toggle({
    Name = "Rare spawn timer",
    Flag = "rare_timer",
    Default = true,
    Callback = function(v)
        CFG.RareTimer = v
    end,
})

----------------------------------------------------------------
-- Eggs tab — per type
----------------------------------------------------------------
local eggsTab = tab.Eggs
eggsTab:Search({ Placeholder = "Search eggs…" })
eggsTab:Section("Types")
eggsTab:ButtonRow({
    {
        Name = "All ON",
        Callback = function()
            for _, def in pairs(EGGS) do
                def.on = true
            end
            ui:Notify({ Title = "Eggs", Text = "All types enabled", Tone = "accent" })
        end,
    },
    {
        Name = "All OFF",
        Tone = "danger",
        Callback = function()
            for _, def in pairs(EGGS) do
                def.on = false
            end
            ui:Notify({ Title = "Eggs", Text = "All types disabled", Tone = "danger" })
        end,
    },
})

local sorted = {}
for name in pairs(EGGS) do
    sorted[#sorted + 1] = name
end
table.sort(sorted)
for _, name in ipairs(sorted) do
    local def = EGGS[name]
    local pretty = name:gsub("Egg$", "")
    eggsTab:Toggle({
        Name = pretty,
        Flag = "egg_" .. name,
        Default = true,
        Callback = function(v)
            def.on = v
        end,
    })
end

----------------------------------------------------------------
-- Alerts
----------------------------------------------------------------
local al = tab.Alerts
al:Section("Spawn alerts")
al:Toggle({
    Name = "Alert on specials",
    Flag = "alerts",
    Default = true,
    Tooltip = "Gold, Void, Meteor, Giant, Secret, Mythic",
    Callback = function(v)
        CFG.Alerts = v
    end,
})
al:Toggle({
    Name = "Alert sound",
    Flag = "alert_snd",
    Default = true,
    Callback = function(v)
        CFG.AlertSound = v
    end,
})
al:Button({
    Name = "Test alert",
    Callback = function()
        playAlert()
        ui:Notify({ Title = "Test", Text = "Special egg alert", Tone = "warn" })
    end,
})
al:Paragraph("Press T to lock nearest special · Y to clear lock · RightShift hides UI")

----------------------------------------------------------------
-- Settings
----------------------------------------------------------------
ui:Settings({ Panel = tab.Settings })
tab.Settings:Separator()
tab.Settings:Section("Profiles")
ui:Profiles({ Panel = tab.Settings })
tab.Settings:Separator()
tab.Settings:Button({
    Name = "Unload",
    Tone = "danger",
    Callback = function()
        cleanup()
        ui:Destroy()
    end,
})

ui:OnDestroy(function()
    cleanup()
end)

ui:Show()
ui:Notify({ Title = "Egg ESP loaded", Text = "RightShift toggle · T lock special · Y clear", Tone = "accent" })
print("[EggESP] LiteUI · WorldEggs · all features")
