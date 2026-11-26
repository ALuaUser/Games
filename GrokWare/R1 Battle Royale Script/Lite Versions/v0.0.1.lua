--[[
    R1 Battle Royale  ·  Simple ESP + Aim Assist
    PlaceIds: 114690486941238 (lobby)  ·  75942174630781 (match)

    Players + Workspace.TPS_Bots
    Drawing ESP  ·  FOV circle  ·  smooth head aim
    RightShift = toggle menu
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LP:GetMouse()

----------------------------------------------------------------
-- CONFIG (edit defaults here)
----------------------------------------------------------------
local CFG = {
    -- ESP
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

    -- Aim assist
    AimEnabled = false,
    AimKey = Enum.UserInputType.MouseButton2, -- hold RMB
    AimFov = 120,
    AimSmooth = 0.18, -- 0 = snap, 1 = very slow
    AimPart = "Head", -- Head | HumanoidRootPart
    AimTeamCheck = true, -- skip same TPS_Team / team attribute if present
    ShowFov = true,
    FovColor = Color3.fromRGB(0, 255, 200),
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local drawings = {} -- [model] = { box={}, tracer, name, hp }
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1.5
fovCircle.NumSides = 64
fovCircle.Filled = false
fovCircle.Transparency = 0.75
fovCircle.Visible = false

local function clearDraw(model)
    local d = drawings[model]
    if not d then
        return
    end
    for _, obj in pairs(d) do
        if typeof(obj) == "table" then
            for _, line in pairs(obj) do
                pcall(function()
                    line:Remove()
                end)
            end
        else
            pcall(function()
                obj:Remove()
            end)
        end
    end
    drawings[model] = nil
end

local function ensureDraw(model, isBot)
    if drawings[model] then
        return drawings[model]
    end
    local color = isBot and CFG.BotColor or CFG.PlayerColor
    local box = {}
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Thickness = 1.5
        l.Color = color
        l.Transparency = 1
        l.Visible = false
        box[i] = l
    end
    local tracer = Drawing.new("Line")
    tracer.Thickness = 1.2
    tracer.Color = color
    tracer.Transparency = 1
    tracer.Visible = false

    local name = Drawing.new("Text")
    name.Size = 14
    name.Center = true
    name.Outline = true
    name.Color = color
    name.Visible = false

    local hp = Drawing.new("Line")
    hp.Thickness = 2
    hp.Color = Color3.fromRGB(80, 255, 120)
    hp.Visible = false

    drawings[model] = {
        box = box,
        tracer = tracer,
        name = name,
        hp = hp,
        isBot = isBot,
        color = color,
    }
    return drawings[model]
end

----------------------------------------------------------------
-- TARGET COLLECTION
----------------------------------------------------------------
local function getTeam(model)
    local plr = Players:GetPlayerFromCharacter(model)
    if plr then
        return plr:GetAttribute("TPS_Team") or plr:GetAttribute("Team") or plr.Team
    end
    return model:GetAttribute("TPS_Team") or model:GetAttribute("Team")
end

local function myTeam()
    return LP:GetAttribute("TPS_Team") or LP:GetAttribute("Team") or LP.Team
end

local function isAlive(model)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return false
    end
    if model:GetAttribute("TPS_Down") == true then
        return false
    end
    return true
end

local function collectTargets()
    local list = {}
    local myChar = LP.Character

    if CFG.EspPlayers or CFG.AimEnabled then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character and isAlive(plr.Character) then
                list[#list + 1] = {
                    model = plr.Character,
                    name = plr.DisplayName ~= "" and plr.DisplayName or plr.Name,
                    isBot = false,
                    team = getTeam(plr.Character),
                }
            end
        end
    end

    if CFG.EspBots or CFG.AimEnabled then
        local bots = Workspace:FindFirstChild("TPS_Bots")
        if bots then
            for _, bot in ipairs(bots:GetChildren()) do
                if bot:IsA("Model") and isAlive(bot) then
                    list[#list + 1] = {
                        model = bot,
                        name = bot.Name,
                        isBot = true,
                        team = getTeam(bot),
                    }
                end
            end
        end
    end

    return list
end

local function worldToScreen(pos)
    local v, on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), on, v.Z
end

local function getCorners(cf, size)
    local sx, sy, sz = size.X / 2, size.Y / 2, size.Z / 2
    local corners = {
        cf * Vector3.new(sx, sy, sz),
        cf * Vector3.new(sx, sy, -sz),
        cf * Vector3.new(-sx, sy, -sz),
        cf * Vector3.new(-sx, sy, sz),
        cf * Vector3.new(sx, -sy, sz),
        cf * Vector3.new(sx, -sy, -sz),
        cf * Vector3.new(-sx, -sy, -sz),
        cf * Vector3.new(-sx, -sy, sz),
    }
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local any = false
    for i = 1, 8 do
        local s, on = worldToScreen(corners[i])
        if on then
            any = true
            minX = math.min(minX, s.X)
            minY = math.min(minY, s.Y)
            maxX = math.max(maxX, s.X)
            maxY = math.max(maxY, s.Y)
        end
    end
    if not any then
        return nil
    end
    return minX, minY, maxX, maxY
end

----------------------------------------------------------------
-- AIM ASSIST
----------------------------------------------------------------
local function aimKeyDown()
    if typeof(CFG.AimKey) == "EnumItem" and CFG.AimKey.EnumType == Enum.UserInputType then
        return UserInputService:IsMouseButtonPressed(CFG.AimKey)
    end
    if typeof(CFG.AimKey) == "EnumItem" and CFG.AimKey.EnumType == Enum.KeyCode then
        return UserInputService:IsKeyDown(CFG.AimKey)
    end
    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

local function getAimPart(model)
    return model:FindFirstChild(CFG.AimPart) or model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
end

local function pickAimTarget()
    if not CFG.AimEnabled then
        return nil
    end
    local inset = GuiService:GetGuiInset()
    local center = Vector2.new(Mouse.X, Mouse.Y + inset.Y)
    local best, bestDist = nil, CFG.AimFov
    local team = myTeam()

    for _, t in ipairs(collectTargets()) do
        if CFG.AimTeamCheck and team and t.team and t.team == team and not t.isBot then
            continue
        end
        if t.isBot and not CFG.EspBots and not CFG.AimEnabled then
            continue
        end
        local part = getAimPart(t.model)
        if not part then
            continue
        end
        local screen, on, depth = worldToScreen(part.Position)
        if not on or depth < 0 then
            continue
        end
        local d = (screen - center).Magnitude
        if d < bestDist then
            bestDist = d
            best = part
        end
    end
    return best
end

local function stepAim(dt)
    if not CFG.AimEnabled or not aimKeyDown() then
        return
    end
    local part = pickAimTarget()
    if not part then
        return
    end
    local cam = Workspace.CurrentCamera
    if not cam then
        return
    end
    local goal = CFrame.lookAt(cam.CFrame.Position, part.Position)
    local alpha = math.clamp(1 - CFG.AimSmooth, 0.05, 1)
    -- frame-rate independent-ish blend
    alpha = 1 - math.pow(1 - alpha, math.clamp(dt * 60, 0.1, 3))
    cam.CFrame = cam.CFrame:Lerp(goal, alpha)
end

----------------------------------------------------------------
-- ESP RENDER
----------------------------------------------------------------
local function tracerOrigin()
    local vs = Camera.ViewportSize
    if CFG.TracerFrom == "Center" then
        return Vector2.new(vs.X / 2, vs.Y / 2)
    elseif CFG.TracerFrom == "Mouse" then
        local inset = GuiService:GetGuiInset()
        return Vector2.new(Mouse.X, Mouse.Y + inset.Y)
    end
    return Vector2.new(vs.X / 2, vs.Y)
end

local function updateESP()
    Camera = Workspace.CurrentCamera
    if not Camera then
        return
    end

    local seen = {}
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local targets = collectTargets()

    for _, t in ipairs(targets) do
        local showEsp = (t.isBot and CFG.EspBots) or (not t.isBot and CFG.EspPlayers)
        if not showEsp then
            continue
        end

        local model = t.model
        local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then
            continue
        end

        local dist = myRoot and (myRoot.Position - hrp.Position).Magnitude or 0
        if dist > CFG.MaxDistance then
            clearDraw(model)
            continue
        end

        seen[model] = true
        local d = ensureDraw(model, t.isBot)
        local color = t.isBot and CFG.BotColor or CFG.PlayerColor
        d.color = color

        local head = model:FindFirstChild("Head") or hrp
        local topPos = head.Position + Vector3.new(0, 0.9, 0)
        local bottomPos = hrp.Position - Vector3.new(0, 2.5, 0)
        local top, onTop = worldToScreen(topPos)
        local mid, onMid, depth = worldToScreen(hrp.Position)

        -- box from bounding corners
        if CFG.EspBoxes then
            local cf = hrp.CFrame
            local size = Vector3.new(2.2, 5.2, 2.2)
            local minX, minY, maxX, maxY = getCorners(cf, size)
            if minX then
                local pts = {
                    Vector2.new(minX, minY),
                    Vector2.new(maxX, minY),
                    Vector2.new(maxX, maxY),
                    Vector2.new(minX, maxY),
                }
                for i = 1, 4 do
                    local a, b = pts[i], pts[i % 4 + 1]
                    d.box[i].From = a
                    d.box[i].To = b
                    d.box[i].Color = color
                    d.box[i].Visible = true
                end
            else
                for i = 1, 4 do
                    d.box[i].Visible = false
                end
            end
        else
            for i = 1, 4 do
                d.box[i].Visible = false
            end
        end

        -- tracer
        if CFG.EspTracers and onMid and depth > 0 then
            d.tracer.From = tracerOrigin()
            d.tracer.To = mid
            d.tracer.Color = color
            d.tracer.Visible = true
        else
            d.tracer.Visible = false
        end

        -- name + distance
        if (CFG.EspNames or CFG.EspDistance) and onTop then
            local label = ""
            if CFG.EspNames then
                label = (t.isBot and "[BOT] " or "") .. t.name
            end
            if CFG.EspDistance then
                label = label .. string.format(" [%dm]", math.floor(dist))
            end
            d.name.Text = label
            d.name.Position = Vector2.new(top.X, top.Y - 16)
            d.name.Color = color
            d.name.Visible = true
        else
            d.name.Visible = false
        end

        -- health bar (left of box)
        if CFG.EspHealth and CFG.EspBoxes then
            local minX, minY, maxX, maxY = getCorners(hrp.CFrame, Vector3.new(2.2, 5.2, 2.2))
            if minX then
                local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                local barX = minX - 4
                d.hp.From = Vector2.new(barX, maxY)
                d.hp.To = Vector2.new(barX, maxY - (maxY - minY) * ratio)
                d.hp.Color = Color3.fromRGB(255 * (1 - ratio), 255 * ratio, 60)
                d.hp.Visible = true
            else
                d.hp.Visible = false
            end
        else
            d.hp.Visible = false
        end
    end

    for model in pairs(drawings) do
        if not seen[model] then
            clearDraw(model)
        end
    end
end

----------------------------------------------------------------
-- FOV + MAIN LOOP
----------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
    Camera = Workspace.CurrentCamera
    if not Camera then
        return
    end

    -- FOV
    if CFG.ShowFov and CFG.AimEnabled then
        local inset = GuiService:GetGuiInset()
        fovCircle.Position = Vector2.new(Mouse.X, Mouse.Y + inset.Y)
        fovCircle.Radius = CFG.AimFov
        fovCircle.Color = CFG.FovColor
        fovCircle.Visible = true
    else
        fovCircle.Visible = false
    end

    pcall(updateESP)
    pcall(stepAim, dt)
end)

Players.PlayerRemoving:Connect(function(plr)
    if plr.Character then
        clearDraw(plr.Character)
    end
end)

----------------------------------------------------------------
-- MINI TOGGLE UI
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "R1_ESP_Aim"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = LP:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(220, 260)
frame.Position = UDim2.new(0, 20, 0.4, 0)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -12, 0, 28)
title.Position = UDim2.fromOffset(10, 4)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(230, 235, 245)
title.Text = "R1 ESP / Aim"
title.Parent = frame

local y = 36
local function addToggle(name, key, default)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 26)
    btn.Position = UDim2.fromOffset(10, y)
    btn.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
    btn.TextColor3 = Color3.fromRGB(220, 225, 235)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 12
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = frame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local function paint()
        local on = CFG[key]
        btn.Text = "  " .. name .. (on and "  [ON]" or "  [OFF]")
        btn.BackgroundColor3 = on and Color3.fromRGB(40, 70, 55) or Color3.fromRGB(32, 36, 46)
    end
    paint()
    btn.MouseButton1Click:Connect(function()
        CFG[key] = not CFG[key]
        paint()
        if key == "EspPlayers" or key == "EspBots" then
            for m in pairs(drawings) do
                clearDraw(m)
            end
        end
    end)
    y = y + 30
end

addToggle("Player ESP", "EspPlayers", CFG.EspPlayers)
addToggle("Bot ESP", "EspBots", CFG.EspBots)
addToggle("Names", "EspNames", CFG.EspNames)
addToggle("Distance", "EspDistance", CFG.EspDistance)
addToggle("Boxes", "EspBoxes", CFG.EspBoxes)
addToggle("Tracers", "EspTracers", CFG.EspTracers)
addToggle("Health bar", "EspHealth", CFG.EspHealth)
addToggle("Aim Assist (hold RMB)", "AimEnabled", CFG.AimEnabled)
addToggle("Show FOV", "ShowFov", CFG.ShowFov)

-- hide / show
local visible = true
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then
        return
    end
    if input.KeyCode == Enum.KeyCode.RightShift then
        visible = not visible
        frame.Visible = visible
    end
end)

print("[R1 ESP/Aim] loaded · RightShift toggles menu · hold RMB for aim assist when enabled")
