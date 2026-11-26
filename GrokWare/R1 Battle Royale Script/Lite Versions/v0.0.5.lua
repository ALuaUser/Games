--[[
    R1 Battle Royale · ESP + Aim Assist
    Simple test UI (no external library)
    PlaceIds: 114690486941238 (lobby) · 75942174630781 (match)
]]

----------------------------------------------------------------
-- R1 ESP + Aim Assist  (world-stable ESP + sticky aim)
----------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CFG = {
    EspPlayers = true,
    EspBots = true,
    EspNames = true,
    EspDistance = true,
    EspTracers = true,
    EspBoxes = true,
    EspHealth = true,
    MaxDistance = 2000,
    PlayerColor = Color3.fromRGB(80, 200, 255),
    BotColor = Color3.fromRGB(255, 90, 90),
    TracerFrom = "Bottom", -- Bottom | Center | Mouse

    AimEnabled = false,
    AimFov = 140,
    AimSmooth = 0.32, -- base smooth (higher = slower). Adaptive makes it tighter near head
    AimLockBoost = 0.55, -- extra strength when already close to the head on screen (0-1)
    AimPart = "Head",
    AimHeadOffset = 0.12, -- studs above Head center (better headshot point)
    AimPredict = 0.12, -- seconds of velocity prediction (0 = off)
    AimTeamCheck = true,
    AimSticky = true,
    AimStickyBoost = 2.6, -- FOV multiplier while locked
    AimLoseTime = 0.65, -- seconds off-target before drop
    AimSwitchRatio = 0.55, -- only switch if new target is this much closer
    ShowFov = true,
    FovColor = Color3.fromRGB(0, 255, 200),
}

local H = {
    drawings = {},
    lock = nil,       -- BasePart currently locked
    lockUntil = 0,
    conns = {},
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

local function getTeam(model)
    local plr = Players:GetPlayerFromCharacter(model)
    if plr then
        return plr:GetAttribute("TPS_Team") or plr:GetAttribute("Team") or (plr.Team and plr.Team.Name)
    end
    return model:GetAttribute("TPS_Team") or model:GetAttribute("Team")
end

local function myTeam()
    return LP:GetAttribute("TPS_Team") or LP:GetAttribute("Team") or (LP.Team and LP.Team.Name)
end

local function alive(model)
    if not model or not model.Parent then
        return false
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return false
    end
    if model:GetAttribute("TPS_Down") == true then
        return false
    end
    return true
end


local function collect()
    local out = {}
    if CFG.EspPlayers or CFG.AimEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character and alive(p.Character) then
                out[#out + 1] = {
                    model = p.Character,
                    name = (p.DisplayName ~= "" and p.DisplayName) or p.Name,
                    isBot = false,
                    team = getTeam(p.Character),
                }
            end
        end
    end
    if CFG.EspBots or CFG.AimEnabled then
        local folder = Workspace:FindFirstChild("TPS_Bots")
        if folder then
            for _, bot in ipairs(folder:GetChildren()) do
                if bot:IsA("Model") and alive(bot) then
                    out[#out + 1] = {
                        model = bot,
                        name = bot.Name,
                        isBot = true,
                        team = getTeam(bot),
                    }
                end
            end
        end
    end
    return out
end

----------------------------------------------------------------
-- DRAWING POOL
----------------------------------------------------------------
local function killDraw(model)
    local d = H.drawings[model]
    if not d then
        return
    end
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

local function getDraw(model, isBot)
    local d = H.drawings[model]
    if d then
        return d
    end
    local color = isBot and CFG.BotColor or CFG.PlayerColor
    local box = {}
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Thickness = 1.5
        l.Color = color
        l.Visible = false
        box[i] = l
    end
    local tracer = Drawing.new("Line")
    tracer.Thickness = 1.2
    tracer.Color = color
    tracer.Visible = false
    local name = Drawing.new("Text")
    name.Size = 13
    name.Center = true
    name.Outline = true
    name.Color = color
    name.Visible = false
    local hp = Drawing.new("Line")
    hp.Thickness = 2
    hp.Visible = false
    d = { box = box, tracer = tracer, name = name, hp = hp, isBot = isBot }
    H.drawings[model] = d
    return d
end

-- Pure world AABB projected through the *current* camera.
local function box2d(hrp)
    local pos = hrp.Position
    local half = Vector3.new(1.15, 2.65, 1.15)
    local corners = {
        pos + Vector3.new( half.X,  half.Y,  half.Z),
        pos + Vector3.new( half.X,  half.Y, -half.Z),
        pos + Vector3.new(-half.X,  half.Y, -half.Z),
        pos + Vector3.new(-half.X,  half.Y,  half.Z),
        pos + Vector3.new( half.X, -half.Y,  half.Z),
        pos + Vector3.new( half.X, -half.Y, -half.Z),
        pos + Vector3.new(-half.X, -half.Y, -half.Z),
        pos + Vector3.new(-half.X, -half.Y,  half.Z),
    }
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local any = false
    for i = 1, 8 do
        local s, on = w2s(corners[i])
        if on then
            any = true
            if s.X < minX then minX = s.X end
            if s.Y < minY then minY = s.Y end
            if s.X > maxX then maxX = s.X end
            if s.Y > maxY then maxY = s.Y end
        end
    end
    if not any then
        return nil
    end
    return minX, minY, maxX, maxY
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

local function aimPart(model)
    -- Always prefer Head for locking; fall back only if missing
    local head = model:FindFirstChild("Head")
    if CFG.AimPart == "Head" and head then
        return head
    end
    return model:FindFirstChild(CFG.AimPart)
        or head
        or model:FindFirstChild("HumanoidRootPart")
end

-- Aim point on the part (head slightly raised for better shots)
local function aimPoint(part)
    local pos = part.Position
    if part.Name == "Head" or (part.Parent and part.Parent:FindFirstChild("Head") == part) then
        pos = pos + Vector3.new(0, CFG.AimHeadOffset or 0, 0)
    end
    -- Simple velocity prediction so the lock leads moving targets
    if (CFG.AimPredict or 0) > 0 then
        local vel = Vector3.zero
        if part:IsA("BasePart") then
            vel = part.AssemblyLinearVelocity
        end
        if vel.Magnitude < 0.05 then
            local model = part:FindFirstAncestorOfClass("Model")
            local hrp = model and model:FindFirstChild("HumanoidRootPart")
            if hrp then
                vel = hrp.AssemblyLinearVelocity
            end
        end
        pos = pos + vel * CFG.AimPredict
    end
    return pos
end

----------------------------------------------------------------
-- AIM (tight head lock + sticky + adaptive strength)
----------------------------------------------------------------
local function aimHeld()
    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

local function mouseCenter()
    local inset = GuiService:GetGuiInset()
    return Vector2.new(Mouse.X, Mouse.Y + inset.Y)
end

local function validLock(part)
    if not part or not part.Parent then
        return false
    end
    local model = part:FindFirstAncestorOfClass("Model")
    if not model or not alive(model) then
        return false
    end
    return true
end

local function screenDistToPoint(worldPos)
    local s, on = w2s(worldPos)
    if not on then
        return math.huge, s, false
    end
    return (s - mouseCenter()).Magnitude, s, true
end

local function screenDistTo(part)
    return screenDistToPoint(aimPoint(part))
end

local function pickTarget()
    local team = myTeam()
    local center = mouseCenter()
    local fov = CFG.AimFov
    local best, bestD = nil, fov

    -- Strong sticky: keep current lock unless dead or far outside sticky FOV for a while
    if CFG.AimSticky and H.lock and validLock(H.lock) then
        local d, _, on = screenDistTo(H.lock)
        if on and d < fov * CFG.AimStickyBoost then
            H.lockUntil = os.clock() + CFG.AimLoseTime
            -- hysteresis: only switch if a much closer head appears
            local switchThresh = d * CFG.AimSwitchRatio
            for _, t in ipairs(collect()) do
                if CFG.AimTeamCheck and not t.isBot and team and t.team and t.team == team then
                    continue
                end
                local part = aimPart(t.model)
                if not part or part == H.lock then
                    continue
                end
                local s, on2 = w2s(aimPoint(part))
                if not on2 then
                    continue
                end
                local nd = (s - center).Magnitude
                if nd < switchThresh and nd < bestD then
                    bestD = nd
                    best = part
                end
            end
            if best then
                H.lock = best
                H.lockUntil = os.clock() + CFG.AimLoseTime
                return best
            end
            return H.lock
        end
        if os.clock() < H.lockUntil then
            return H.lock
        end
        H.lock = nil
    end

    -- Fresh pick: closest head to crosshair within FOV
    for _, t in ipairs(collect()) do
        if CFG.AimTeamCheck and not t.isBot and team and t.team and t.team == team then
            continue
        end
        local part = aimPart(t.model)
        if not part then
            continue
        end
        local s, on = w2s(aimPoint(part))
        if not on then
            continue
        end
        local d = (s - center).Magnitude
        if d < bestD then
            bestD = d
            best = part
        end
    end

    if best then
        H.lock = best
        H.lockUntil = os.clock() + CFG.AimLoseTime
    end
    return best
end

local function stepAim(dt)
    if not CFG.AimEnabled or not aimHeld() then
        if not aimHeld() then
            H.lock = nil
        end
        return
    end
    local c = cam()
    if not c then
        return
    end
    local part = pickTarget()
    if not part then
        return
    end

    local origin = c.CFrame.Position
    local targetPos = aimPoint(part)
    local want = targetPos - origin
    if want.Magnitude < 0.05 then
        return
    end
    want = want.Unit
    local cur = c.CFrame.LookVector

    -- How far is the head from the crosshair on screen? (pixels)
    local screenDist = select(1, screenDistToPoint(targetPos))
    local fov = math.max(CFG.AimFov, 1)

    -- Adaptive strength:
    --  - far from crosshair → use base smooth (gentle pull)
    --  - near crosshair → ramp up LockBoost so it actually settles on the head
    local closeness = 1 - math.clamp(screenDist / fov, 0, 1) -- 1 = on head, 0 = at FOV edge
    closeness = closeness * closeness -- bias toward center
    local boost = math.clamp(CFG.AimLockBoost or 0.5, 0, 1)
    local smooth = math.clamp(CFG.AimSmooth, 0.05, 0.85)
    -- Effective smooth is lower (faster) when close
    local effectiveSmooth = smooth * (1 - boost * closeness * 0.85)
    effectiveSmooth = math.clamp(effectiveSmooth, 0.04, 0.85)

    local t = 1 - math.pow(effectiveSmooth, math.clamp(dt * 60, 0.02, 5))
    -- Allow stronger pull when already close so it locks the head
    local maxT = 0.35 + 0.45 * closeness * boost
    t = math.clamp(t, 0.02, maxT)

    local blended = cur:Lerp(want, t)
    if blended.Magnitude < 1e-4 then
        return
    end
    c.CFrame = CFrame.lookAt(origin, origin + blended.Unit)
end

-- ESP (always world positions, fresh camera)
----------------------------------------------------------------
local function updateESP()
    local c = cam()
    if not c then
        return
    end
    local root = myRoot()
    local seen = {}
    local targets = collect()

    for _, t in ipairs(targets) do
        local show = (t.isBot and CFG.EspBots) or (not t.isBot and CFG.EspPlayers)
        if not show then
            continue
        end
        local model = t.model
        local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then
            continue
        end
        local dist = root and (root.Position - hrp.Position).Magnitude or 0
        if dist > CFG.MaxDistance then
            killDraw(model)
            continue
        end
        seen[model] = true
        local d = getDraw(model, t.isBot)
        local color = t.isBot and CFG.BotColor or CFG.PlayerColor
        local head = model:FindFirstChild("Head") or hrp
        local top, onTop = w2s(head.Position + Vector3.new(0, 1.05, 0))
        local mid, onMid = w2s(hrp.Position)

        if CFG.EspBoxes then
            local minX, minY, maxX, maxY = box2d(hrp)
            if minX then
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
                if CFG.EspHealth then
                    local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                    local x = minX - 4
                    d.hp.From = Vector2.new(x, maxY)
                    d.hp.To = Vector2.new(x, maxY - (maxY - minY) * ratio)
                    d.hp.Color = Color3.fromRGB(255 * (1 - ratio), 255 * ratio, 50)
                    d.hp.Visible = true
                else
                    d.hp.Visible = false
                end
            else
                for i = 1, 4 do
                    d.box[i].Visible = false
                end
                d.hp.Visible = false
            end
        else
            for i = 1, 4 do
                d.box[i].Visible = false
            end
            d.hp.Visible = false
        end

        if CFG.EspTracers and onMid then
            d.tracer.From = tracerOrigin()
            d.tracer.To = mid
            d.tracer.Color = color
            d.tracer.Visible = true
        else
            d.tracer.Visible = false
        end

        if (CFG.EspNames or CFG.EspDistance) and onTop then
            local label = ""
            if CFG.EspNames then
                label = (t.isBot and "[BOT] " or "") .. t.name
            end
            if CFG.EspDistance then
                label = label .. string.format(" [%dm]", math.floor(dist))
            end
            d.name.Text = label
            d.name.Position = Vector2.new(top.X, top.Y - 14)
            d.name.Color = color
            d.name.Visible = true
        else
            d.name.Visible = false
        end
    end

    for model in pairs(H.drawings) do
        if not seen[model] then
            killDraw(model)
        end
    end
end

----------------------------------------------------------------
-- FOV circle + render loop (correct priority order)
----------------------------------------------------------------
local fov = Drawing.new("Circle")
fov.Thickness = 1.4
fov.NumSides = 64
fov.Filled = false
fov.Transparency = 0.7
fov.Visible = false

-- Aim runs just after the camera so it can gently override look for this frame.
-- ESP runs after aim so boxes are projected with the final CFrame of the frame.
local AIM_PRIO = Enum.RenderPriority.Camera.Value + 1
local ESP_PRIO = Enum.RenderPriority.Camera.Value + 2

RunService:BindToRenderStep("R1Aim", AIM_PRIO, function(dt)
    pcall(stepAim, dt)
end)
table.insert(H.binds, "R1Aim")

RunService:BindToRenderStep("R1ESP", ESP_PRIO, function()
    local c = cam()
    if not c then
        return
    end
    if CFG.ShowFov and CFG.AimEnabled then
        local inset = GuiService:GetGuiInset()
        fov.Position = Vector2.new(Mouse.X, Mouse.Y + inset.Y)
        fov.Radius = CFG.AimFov
        fov.Color = CFG.FovColor
        fov.Visible = true
    else
        fov.Visible = false
    end
    pcall(updateESP)
end)
table.insert(H.binds, "R1ESP")

Players.PlayerRemoving:Connect(function(p)
    if p.Character then
        killDraw(p.Character)
    end
end)

local function cleanup()
    for _, name in ipairs(H.binds) do
        pcall(function()
            RunService:UnbindFromRenderStep(name)
        end)
    end
    H.binds = {}
    for _, c in ipairs(H.conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    H.conns = {}
    for m in pairs(H.drawings) do
        killDraw(m)
    end
    pcall(function()
        fov:Remove()
    end)
    H.lock = nil
end

----------------------------------------------------------------

----------------------------------------------------------------
-- SIMPLE TEST UI (no library)
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

-- clean previous
pcall(function()
    local old = LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("R1ESPAimSimple")
    if old then old:Destroy() end
    if game:GetService("CoreGui"):FindFirstChild("R1ESPAimSimple") then
        game:GetService("CoreGui").R1ESPAimSimple:Destroy()
    end
end)

local parentGui = (gethui and gethui()) or game:GetService("CoreGui")
local ok, err = pcall(function()
    make("ScreenGui", { Name = "R1ESPAimSimple", ResetOnSpawn = false }, parentGui)
end)
if not ok then
    parentGui = LP:WaitForChild("PlayerGui")
end

local gui = make("ScreenGui", {
    Name = "R1ESPAimSimple",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 100,
}, parentGui)

local main = make("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(280, 420),
    Position = UDim2.fromOffset(24, 120),
    BackgroundColor3 = Color3.fromRGB(22, 22, 26),
    BorderSizePixel = 0,
    Active = true,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
make("UIStroke", { Color = Color3.fromRGB(60, 60, 70), Thickness = 1 }, main)

local title = make("TextLabel", {
    Size = UDim2.new(1, -40, 0, 32),
    Position = UDim2.fromOffset(12, 6),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextColor3 = Color3.fromRGB(240, 240, 245),
    Text = "R1 ESP / Aim  ·  test UI",
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local closeBtn = make("TextButton", {
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.new(1, -34, 0, 6),
    BackgroundColor3 = Color3.fromRGB(40, 40, 48),
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = Color3.fromRGB(220, 100, 100),
    Text = "X",
    AutoButtonColor = false,
}, main)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)

local scroll = make("ScrollingFrame", {
    Size = UDim2.new(1, -16, 1, -48),
    Position = UDim2.fromOffset(8, 40),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    CanvasSize = UDim2.fromOffset(0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, main)
make("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, scroll)
make("UIPadding", {
    PaddingTop = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 8),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
}, scroll)

local order = 0
local function nextOrder()
    order += 1
    return order
end

local function section(text)
    local l = make("TextLabel", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(120, 200, 150),
        Text = text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, scroll)
    return l
end

local function toggle(name, key, default, cb)
    local row = make("Frame", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Color3.fromRGB(32, 32, 38),
        BorderSizePixel = 0,
    }, scroll)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
    make("TextLabel", {
        Size = UDim2.new(1, -56, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = Color3.fromRGB(230, 230, 235),
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local btn = make("TextButton", {
        Size = UDim2.fromOffset(42, 22),
        Position = UDim2.new(1, -48, 0.5, -11),
        BackgroundColor3 = default and Color3.fromRGB(80, 180, 120) or Color3.fromRGB(55, 55, 65),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Color3.fromRGB(255, 255, 255),
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
    return row
end

local function slider(name, key, min, max, default, step, cb)
    step = step or 1
    local row = make("Frame", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundColor3 = Color3.fromRGB(32, 32, 38),
        BorderSizePixel = 0,
    }, scroll)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
    local label = make("TextLabel", {
        Size = UDim2.new(1, -16, 0, 20),
        Position = UDim2.fromOffset(10, 4),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(230, 230, 235),
        Text = name .. ": " .. tostring(default),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local track = make("Frame", {
        Size = UDim2.new(1, -20, 0, 8),
        Position = UDim2.fromOffset(10, 30),
        BackgroundColor3 = Color3.fromRGB(50, 50, 58),
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
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local val = min + rel * (max - min)
        val = math.floor(val / step + 0.5) * step
        val = math.clamp(val, min, max)
        -- format
        local shown = (step < 1) and string.format("%.2f", val) or tostring(math.floor(val + 0.5))
        label.Text = name .. ": " .. shown
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
    return row
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

-- build controls
section("ESP")
toggle("Player ESP", "EspPlayers", CFG.EspPlayers, function(v) CFG.EspPlayers = v end)
toggle("Bot ESP", "EspBots", CFG.EspBots, function(v) CFG.EspBots = v end)
toggle("Names", "EspNames", CFG.EspNames, function(v) CFG.EspNames = v end)
toggle("Distance", "EspDistance", CFG.EspDistance, function(v) CFG.EspDistance = v end)
toggle("Boxes", "EspBoxes", CFG.EspBoxes, function(v) CFG.EspBoxes = v end)
toggle("Tracers", "EspTracers", CFG.EspTracers, function(v) CFG.EspTracers = v end)
toggle("Health bar", "EspHealth", CFG.EspHealth, function(v) CFG.EspHealth = v end)
slider("Max distance", "MaxDistance", 200, 4000, CFG.MaxDistance, 50, function(v) CFG.MaxDistance = v end)

section("AIM ASSIST  (hold RMB)")
toggle("Enable aim", "AimEnabled", CFG.AimEnabled, function(v)
    CFG.AimEnabled = v
    if not v then H.lock = nil end
end)
toggle("Sticky target", "AimSticky", CFG.AimSticky, function(v) CFG.AimSticky = v end)
toggle("Team check", "AimTeamCheck", CFG.AimTeamCheck, function(v) CFG.AimTeamCheck = v end)
toggle("Show FOV", "ShowFov", CFG.ShowFov, function(v) CFG.ShowFov = v end)
slider("FOV", "AimFov", 40, 400, CFG.AimFov, 5, function(v) CFG.AimFov = v end)
slider("Smoothness", "AimSmooth", 0.08, 0.7, CFG.AimSmooth, 0.01, function(v) CFG.AimSmooth = v end)
slider("Lock strength", "AimLockBoost", 0, 1, CFG.AimLockBoost, 0.05, function(v) CFG.AimLockBoost = v end)
slider("Prediction", "AimPredict", 0, 0.35, CFG.AimPredict, 0.01, function(v) CFG.AimPredict = v end)
slider("Head offset", "AimHeadOffset", 0, 0.4, CFG.AimHeadOffset, 0.02, function(v) CFG.AimHeadOffset = v end)

section("MISC")
local unloadRow = make("TextButton", {
    LayoutOrder = nextOrder(),
    Size = UDim2.new(1, 0, 0, 32),
    BackgroundColor3 = Color3.fromRGB(140, 50, 50),
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = Color3.fromRGB(255, 230, 230),
    Text = "Unload",
    AutoButtonColor = true,
}, scroll)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, unloadRow)

local function fullUnload()
    cleanup()
    pcall(function() gui:Destroy() end)
end

unloadRow.MouseButton1Click:Connect(fullUnload)
closeBtn.MouseButton1Click:Connect(function()
    gui.Enabled = not gui.Enabled
end)

-- RightShift toggle UI
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        gui.Enabled = not gui.Enabled
    end
end)

-- extend cleanup to destroy gui
local _oldCleanup = cleanup
cleanup = function()
    _oldCleanup()
    pcall(function() gui:Destroy() end)
end

print("[R1 ESP/Aim] simple test UI loaded · RightShift to hide")
