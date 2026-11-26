--[[
    World Egg ESP + Charms
    Scans workspace.WorldEggs (and CollectionService tag "WorldEgg")
    Per-egg toggles · Gold / Void / Meteor detection · Highlights (charms)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()

----------------------------------------------------------------
-- CONFIG
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

local CFG = {
    Enabled = true,
    ShowNames = true,
    ShowDistance = true,
    ShowTracers = true,
    ShowBoxes = false,
    ShowCorners = true,
    ShowCharms = true,       -- Highlight on the egg model
    ShowGoldOnly = false,    -- if true, only gold/void/meteor
    MaxDistance = 4000,
    TracerFrom = "Bottom",   -- Bottom | Center | Mouse
    TextSize = 14,
    -- special variant colors (override type color when shown)
    GoldColor = Color3.fromRGB(255, 210, 60),
    VoidColor = Color3.fromRGB(170, 90, 255),
    MeteorColor = Color3.fromRGB(255, 120, 40),
}

local H = {
    drawings = {},   -- [model] = drawing pack
    charms = {},     -- [model] = Highlight
    binds = {},
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

-- resolve egg type name from model
local function eggTypeName(model)
    if not model then
        return nil
    end
    -- common attributes from dumps
    local id = model:GetAttribute("EggId")
        or model:GetAttribute("EggName")
        or model:GetAttribute("Type")
        or model.Name
    -- strip common suffixes / normalize
    id = tostring(id)
    if EGGS[id] then
        return id
    end
    -- try matching known names as substring
    for name in pairs(EGGS) do
        if id:find(name, 1, true) or name:find(id, 1, true) then
            return name
        end
    end
    -- model name itself
    if EGGS[model.Name] then
        return model.Name
    end
    return id -- unknown still shown if master enabled
end

local function eggVariant(model)
    -- Gold attribute can be true, "Void", "Meteor"
    local g = model:GetAttribute("Gold")
        or model:GetAttribute("StashGold")
        or model:GetAttribute("GoldLook") and true
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

local function collectEggs()
    local out, seen = {}, {}

    local function add(model)
        if not model or not model:IsA("Model") or seen[model] then
            return
        end
        if model:GetAttribute("ChuteEnd") then
            return -- falling/despawning
        end
        local root = eggRoot(model)
        if not root then
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

    -- also tag-based (game uses CollectionService tag "WorldEgg")
    pcall(function()
        for _, m in ipairs(CollectionService:GetTagged("WorldEgg")) do
            add(m)
        end
    end)

    return out
end

----------------------------------------------------------------
-- DRAWINGS / CHARMS
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

local function box2d(part)
    local pos = part.Position
    local size = part.Size
    local half = size * 0.55
    -- if very small, use a minimum box
    half = Vector3.new(
        math.max(half.X, 1.2),
        math.max(half.Y, 1.5),
        math.max(half.Z, 1.2)
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

local function drawCorners(d, minX, minY, maxX, maxY, color)
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
        d.corners[i].Visible = true
    end
end

local function tracerOrigin()
    local c = cam()
    local vs = c and c.ViewportSize or Vector2.new(1920, 1080)
    if CFG.TracerFrom == "Center" then
        return Vector2.new(vs.X / 2, vs.Y / 2)
    elseif CFG.TracerFrom == "Mouse" then
        local inset = game:GetService("GuiService"):GetGuiInset()
        return Vector2.new(Mouse.X, Mouse.Y + inset.Y)
    end
    return Vector2.new(vs.X / 2, vs.Y)
end

local function colorFor(model, typeName)
    local variant = eggVariant(model)
    if variant == "Gold" then
        return CFG.GoldColor, "GOLD"
    elseif variant == "Void" then
        return CFG.VoidColor, "VOID"
    elseif variant == "Meteor" then
        return CFG.MeteorColor, "METEOR"
    elseif variant == "Secret" then
        return Color3.fromRGB(220, 110, 255), "SECRET"
    elseif variant == "Mythic" then
        return Color3.fromRGB(255, 80, 160), "MYTHIC"
    elseif variant == "Legendary" then
        return Color3.fromRGB(255, 200, 60), "LEGENDARY"
    end
    local def = EGGS[typeName]
    if def then
        return def.color, nil
    end
    return Color3.fromRGB(200, 200, 210), nil
end

local function shouldShow(typeName, model)
    if not CFG.Enabled then
        return false
    end
    if CFG.ShowGoldOnly then
        local v = eggVariant(model)
        if not (v == "Gold" or v == "Void" or v == "Meteor") then
            return false
        end
    end
    local def = EGGS[typeName]
    if def and def.on == false then
        return false
    end
    -- unknown types still show if master on
    return true
end

local function update()
    if not CFG.Enabled then
        for m in pairs(H.drawings) do
            kill(m)
        end
        for m in pairs(H.charms) do
            kill(m)
        end
        return
    end

    local root = myRoot()
    local seen = {}
    local eggs = collectEggs()

    for _, model in ipairs(eggs) do
        local typeName = eggTypeName(model)
        if not shouldShow(typeName, model) then
            kill(model)
            continue
        end

        local part = eggRoot(model)
        if not part then
            kill(model)
            continue
        end

        local dist = root and (root.Position - part.Position).Magnitude or 0
        if dist > CFG.MaxDistance then
            kill(model)
            continue
        end

        seen[model] = true
        local color, variantTag = colorFor(model, typeName)
        local d = getDraw(model)
        local mid, onMid = w2s(part.Position)
        local top, onTop = w2s(part.Position + Vector3.new(0, math.max(part.Size.Y * 0.6, 2), 0))

        -- boxes
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
                d.box[i].Visible = true
            end
        else
            for i = 1, 4 do
                d.box[i].Visible = false
            end
        end

        if CFG.ShowCorners and minX then
            drawCorners(d, minX, minY, maxX, maxY, color)
        else
            for i = 1, 8 do
                d.corners[i].Visible = false
            end
        end

        if CFG.ShowTracers and onMid then
            d.tracer.From = tracerOrigin()
            d.tracer.To = mid
            d.tracer.Color = color
            d.tracer.Visible = true
        else
            d.tracer.Visible = false
        end

        if (CFG.ShowNames or CFG.ShowDistance) and onTop then
            local label = ""
            if CFG.ShowNames then
                local pretty = typeName:gsub("Egg$", "")
                if variantTag then
                    label = "[" .. variantTag .. "] " .. pretty
                else
                    label = pretty
                end
            end
            if CFG.ShowDistance then
                label = label .. string.format(" [%dm]", math.floor(dist))
            end
            d.name.Text = label
            d.name.Position = Vector2.new(top.X, top.Y - 12)
            d.name.Color = color
            d.name.Size = CFG.TextSize
            d.name.Visible = true
        else
            d.name.Visible = false
        end

        if CFG.ShowCharms then
            local hl = getCharm(model, color)
            hl.Enabled = true
            hl.FillColor = color
            hl.OutlineColor = color
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
end

RunService:BindToRenderStep("EggESP", Enum.RenderPriority.Last.Value, function()
    pcall(update)
end)
table.insert(H.binds, "EggESP")

-- cleanup removed eggs
Workspace.DescendantRemoving:Connect(function(inst)
    if H.drawings[inst] or H.charms[inst] then
        kill(inst)
    end
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
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local function make(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do
        o[k] = v
    end
    if parent then
        o.Parent = parent
    end
    return o
end

pcall(function()
    local g = (gethui and gethui()) or game:GetService("CoreGui")
    local old = g:FindFirstChild("EggESPGui")
    if old then
        old:Destroy()
    end
end)

local parentGui = (gethui and gethui()) or game:GetService("CoreGui")
if not pcall(function()
    make("ScreenGui", { Name = "EggESPGui", ResetOnSpawn = false }, parentGui)
end) then
    parentGui = LP:WaitForChild("PlayerGui")
end

local gui = make("ScreenGui", {
    Name = "EggESPGui",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 100,
}, parentGui)

local main = make("Frame", {
    Size = UDim2.fromOffset(310, 540),
    Position = UDim2.fromOffset(18, 80),
    BackgroundColor3 = Color3.fromRGB(18, 20, 26),
    BorderSizePixel = 0,
    Active = true,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
make("UIStroke", { Color = Color3.fromRGB(55, 55, 70), Thickness = 1 }, main)

local title = make("TextLabel", {
    Size = UDim2.new(1, -40, 0, 28),
    Position = UDim2.fromOffset(12, 6),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = Color3.fromRGB(240, 240, 245),
    Text = "Egg ESP + Charms",
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local closeBtn = make("TextButton", {
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.new(1, -34, 0, 5),
    BackgroundColor3 = Color3.fromRGB(40, 40, 50),
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = Color3.fromRGB(220, 100, 100),
    Text = "X",
    AutoButtonColor = false,
}, main)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)

local status = make("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16),
    Position = UDim2.fromOffset(12, 32),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = Color3.fromRGB(140, 150, 160),
    Text = "Scanning WorldEggs...",
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local scroll = make("ScrollingFrame", {
    Size = UDim2.new(1, -16, 1, -54),
    Position = UDim2.fromOffset(8, 50),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    CanvasSize = UDim2.fromOffset(0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, main)
make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
make("UIPadding", {
    PaddingTop = UDim.new(0, 2),
    PaddingBottom = UDim.new(0, 8),
    PaddingLeft = UDim.new(0, 2),
    PaddingRight = UDim.new(0, 2),
}, scroll)

local order = 0
local function nextOrder()
    order += 1
    return order
end

local function section(text)
    make("TextLabel", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(120, 200, 150),
        Text = text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, scroll)
end

local function toggle(name, default, cb)
    local row = make("Frame", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = Color3.fromRGB(28, 30, 38),
        BorderSizePixel = 0,
    }, scroll)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
    make("TextLabel", {
        Size = UDim2.new(1, -54, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(230, 230, 235),
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local btn = make("TextButton", {
        Size = UDim2.fromOffset(40, 20),
        Position = UDim2.new(1, -46, 0.5, -10),
        BackgroundColor3 = default and Color3.fromRGB(80, 180, 120) or Color3.fromRGB(55, 55, 65),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Color3.new(1, 1, 1),
        Text = default and "ON" or "OFF",
        AutoButtonColor = false,
    }, row)
    make("UICorner", { CornerRadius = UDim.new(0, 5) }, btn)
    local state = default
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.Text = state and "ON" or "OFF"
        btn.BackgroundColor3 = state and Color3.fromRGB(80, 180, 120) or Color3.fromRGB(55, 55, 65)
        if cb then
            cb(state)
        end
    end)
    return function(v)
        state = v
        btn.Text = state and "ON" or "OFF"
        btn.BackgroundColor3 = state and Color3.fromRGB(80, 180, 120) or Color3.fromRGB(55, 55, 65)
    end
end

local function slider(name, min, max, default, step, cb)
    local row = make("Frame", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Color3.fromRGB(28, 30, 38),
        BorderSizePixel = 0,
    }, scroll)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
    local label = make("TextLabel", {
        Size = UDim2.new(1, -14, 0, 18),
        Position = UDim2.fromOffset(10, 3),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(230, 230, 235),
        Text = name .. ": " .. tostring(default),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local track = make("Frame", {
        Size = UDim2.new(1, -20, 0, 7),
        Position = UDim2.fromOffset(10, 28),
        BackgroundColor3 = Color3.fromRGB(48, 48, 56),
        BorderSizePixel = 0,
    }, row)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
    local fill = make("Frame", {
        Size = UDim2.new(math.clamp((default - min) / (max - min), 0, 1), 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(100, 190, 150),
        BorderSizePixel = 0,
    }, track)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
    local dragging = false
    local function setFromX(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        local val = math.clamp(math.floor((min + rel * (max - min)) / step + 0.5) * step, min, max)
        label.Text = name .. ": " .. tostring(math.floor(val + 0.5))
        fill.Size = UDim2.new((val - min) / (max - min), 0, 1, 0)
        if cb then
            cb(val)
        end
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- drag window
do
    local dragging, dragStart, startPos
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    title.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.fromOffset(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
        end
    end)
end

RunService.RenderStepped:Connect(function()
    local n = 0
    for _ in pairs(H.drawings) do
        n += 1
    end
    status.Text = CFG.Enabled and ("Eggs shown: " .. n) or "ESP off"
end)

section("MASTER")
toggle("ESP Enabled", CFG.Enabled, function(v)
    CFG.Enabled = v
end)
toggle("Names", CFG.ShowNames, function(v)
    CFG.ShowNames = v
end)
toggle("Distance", CFG.ShowDistance, function(v)
    CFG.ShowDistance = v
end)
toggle("Tracers", CFG.ShowTracers, function(v)
    CFG.ShowTracers = v
end)
toggle("Corner boxes", CFG.ShowCorners, function(v)
    CFG.ShowCorners = v
end)
toggle("Full boxes", CFG.ShowBoxes, function(v)
    CFG.ShowBoxes = v
end)
toggle("Charms (Highlight)", CFG.ShowCharms, function(v)
    CFG.ShowCharms = v
end)
toggle("Gold / Void / Meteor only", CFG.ShowGoldOnly, function(v)
    CFG.ShowGoldOnly = v
end)
slider("Max distance", 200, 8000, CFG.MaxDistance, 100, function(v)
    CFG.MaxDistance = v
end)

section("EGG TYPES")
-- All on / All off
do
    local row = make("Frame", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = Color3.fromRGB(28, 30, 38),
        BorderSizePixel = 0,
    }, scroll)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
    local allOn = make("TextButton", {
        Size = UDim2.new(0.48, -4, 1, -6),
        Position = UDim2.fromOffset(4, 3),
        BackgroundColor3 = Color3.fromRGB(60, 140, 100),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Color3.new(1, 1, 1),
        Text = "All ON",
        AutoButtonColor = true,
    }, row)
    make("UICorner", { CornerRadius = UDim.new(0, 5) }, allOn)
    local allOff = make("TextButton", {
        Size = UDim2.new(0.48, -4, 1, -6),
        Position = UDim2.new(0.52, 0, 0, 3),
        BackgroundColor3 = Color3.fromRGB(120, 60, 60),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Color3.new(1, 1, 1),
        Text = "All OFF",
        AutoButtonColor = true,
    }, row)
    make("UICorner", { CornerRadius = UDim.new(0, 5) }, allOff)
    allOn.MouseButton1Click:Connect(function()
        for _, def in pairs(EGGS) do
            def.on = true
        end
        -- refresh toggles by forcing rebuild is heavy; user can flip one to sync visually
        -- store refs instead:
        for name, setFn in pairs(eggToggleSetters or {}) do
            setFn(true)
        end
    end)
    allOff.MouseButton1Click:Connect(function()
        for _, def in pairs(EGGS) do
            def.on = false
        end
        for name, setFn in pairs(eggToggleSetters or {}) do
            setFn(false)
        end
    end)
end

eggToggleSetters = {}
local sorted = {}
for name in pairs(EGGS) do
    sorted[#sorted + 1] = name
end
table.sort(sorted)

for _, name in ipairs(sorted) do
    local def = EGGS[name]
    local pretty = name:gsub("Egg$", "")
    local setFn = toggle(pretty, def.on, function(v)
        def.on = v
    end)
    eggToggleSetters[name] = setFn
end

section("MISC")
local unload = make("TextButton", {
    LayoutOrder = nextOrder(),
    Size = UDim2.new(1, 0, 0, 30),
    BackgroundColor3 = Color3.fromRGB(140, 50, 50),
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = Color3.fromRGB(255, 230, 230),
    Text = "Unload",
    AutoButtonColor = true,
}, scroll)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, unload)
unload.MouseButton1Click:Connect(function()
    cleanup()
    pcall(function()
        gui:Destroy()
    end)
end)

closeBtn.MouseButton1Click:Connect(function()
    gui.Enabled = not gui.Enabled
end)
UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.RightShift then
        gui.Enabled = not gui.Enabled
    end
end)

print("[Egg ESP] WorldEggs + WorldEgg tag · per-type toggles · charms · RightShift")
