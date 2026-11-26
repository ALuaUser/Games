--[[
    R1 Aim Lock + ESP  ·  v6
    Map: 75942174630781

    Reality check (from your tests):
      - Action:FireServer("Fire") rewrite RUNS
      - Hard camDir silent = server rejects the shot (no bullets)
      - ViewportPointToRay hook never hits (rays stayed 0)
      - So true silent is blocked on this build

    v6 does what actually works on R1:
      1) CAMERA AIM LOCK — force Camera.CFrame at target head while LMB
         (same idea as universal "silent" scripts; visible but hits)
      2) Optional SOFT fire nudge — tiny camDir bend (won't kill the shot)
      3) ESP (unchanged, already good)
      4) Bots + players, FOV at screen center
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CFG = {
    -- ESP
    EspPlayers = true,
    EspBots = true,
    EspNames = true,
    EspDistance = true,
    EspBoxes = false,
    EspCorners = true,
    EspTracers = true,
    EspHealth = true,
    EspHeadDot = true,
    MaxDistance = 2500,
    PlayerColor = Color3.fromRGB(80, 200, 255),
    BotColor = Color3.fromRGB(255, 90, 90),
    TracerFrom = "Bottom",

    -- Aim lock (camera) — this is what hits
    AimEnabled = true,
    AimFov = 160,
    AimPart = "Head",
    AimHeadOffset = 0.1,
    AimPredict = 0.1,
    AimSmooth = 1,          -- 1 = instant lock, 0.2–0.5 = softer
    AimTeamCheck = true,
    AimSticky = true,
    AimStickyBoost = 1.35,
    AimLoseTime = 0.45,
    AimOnLMB = true,        -- only lock while shooting
    AimAlways = false,      -- lock whenever target in FOV
    ShowFov = true,
    FovColor = Color3.fromRGB(255, 180, 60),
    MaxAimDist = 1500,

    -- Soft fire packet nudge (optional, won't hard-silent)
    SoftFire = true,
    SoftMaxDeg = 8,
    SoftDebug = false,
}

local H = {
    drawings = {},
    lockModel = nil,
    lockUntil = 0,
    targetPos = nil,
    targetModel = nil,
    targetPart = nil,
    binds = {},
    lmb = false,
    fireCount = 0,
}

----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gpe)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        H.lmb = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        H.lmb = false
    end
end)

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function cam()
    return Workspace.CurrentCamera
end

local function fovCenter()
    local c = cam()
    local vs = c and c.ViewportSize or Vector2.new(1920, 1080)
    return Vector2.new(vs.X * 0.5, vs.Y * 0.5)
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

local function isBotModel(model)
    if not model or not model:IsA("Model") then
        return false
    end
    if model:GetAttribute("TPS_Bot") == true or model:GetAttribute("TPS_BotId") ~= nil or model:GetAttribute("TPS_BotTier") ~= nil then
        return true
    end
    return model.Parent and model.Parent.Name == "TPS_Bots"
end

local function collect()
    local out, seen = {}, {}
    if CFG.EspPlayers or CFG.AimEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character and alive(p.Character) then
                seen[p.Character] = true
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
                if bot:IsA("Model") and alive(bot) and not seen[bot] then
                    seen[bot] = true
                    out[#out + 1] = {
                        model = bot,
                        name = bot.Name,
                        isBot = true,
                        team = getTeam(bot),
                    }
                end
            end
        end
        for _, inst in ipairs(Workspace:GetChildren()) do
            if inst:IsA("Model") and not seen[inst] and isBotModel(inst) and alive(inst) and not Players:GetPlayerFromCharacter(inst) then
                seen[inst] = true
                out[#out + 1] = {
                    model = inst,
                    name = inst.Name,
                    isBot = true,
                    team = getTeam(inst),
                }
            end
        end
    end
    return out
end

local function aimPart(model)
    if not model then
        return nil
    end
    local head = model:FindFirstChild("Head")
    if CFG.AimPart == "Head" and head then
        return head
    end
    return model:FindFirstChild(CFG.AimPart) or head or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function aimPoint(part)
    if not part then
        return nil
    end
    local pos = part.Position
    if part.Name == "Head" then
        pos = pos + Vector3.new(0, CFG.AimHeadOffset or 0, 0)
    end
    if (CFG.AimPredict or 0) > 0 then
        local vel = Vector3.zero
        pcall(function()
            vel = part.AssemblyLinearVelocity
        end)
        if vel.Magnitude < 0.05 then
            local model = part:FindFirstAncestorOfClass("Model")
            local hrp = model and model:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function()
                    vel = hrp.AssemblyLinearVelocity
                end)
            end
        end
        pos = pos + vel * CFG.AimPredict
    end
    return pos
end

----------------------------------------------------------------
-- TARGET
----------------------------------------------------------------
local function pickTarget()
    local team = myTeam()
    local center = fovCenter()
    local fov = CFG.AimFov
    local best, bestModel, bestD = nil, nil, fov
    local c = cam()
    local origin = c and c.CFrame.Position

    if CFG.AimSticky and H.lockModel and alive(H.lockModel) and H.lockModel.Parent then
        local part = aimPart(H.lockModel)
        if part then
            local ap = aimPoint(part)
            local s, on = w2s(ap)
            if on then
                local d = (s - center).Magnitude
                if d < fov * CFG.AimStickyBoost then
                    H.lockUntil = os.clock() + CFG.AimLoseTime
                    return part, H.lockModel, ap
                end
            end
            if os.clock() < H.lockUntil then
                local ap = aimPoint(part)
                local s, on = w2s(ap)
                if on and (s - center).Magnitude < fov * CFG.AimStickyBoost then
                    return part, H.lockModel, ap
                end
            end
        end
        H.lockModel = nil
    end

    for _, t in ipairs(collect()) do
        if CFG.AimTeamCheck and not t.isBot and team and t.team and t.team == team then
            continue
        end
        local part = aimPart(t.model)
        if not part then
            continue
        end
        local ap = aimPoint(part)
        local s, on = w2s(ap)
        if not on then
            continue
        end
        local d = (s - center).Magnitude
        if d >= fov then
            continue
        end
        if origin and (ap - origin).Magnitude > CFG.MaxAimDist then
            continue
        end
        if d < bestD then
            bestD, best, bestModel = d, part, t.model
        end
    end

    if best then
        H.lockModel = bestModel
        H.lockUntil = os.clock() + CFG.AimLoseTime
        return best, bestModel, aimPoint(best)
    end
    H.lockModel = nil
    return nil, nil, nil
end

----------------------------------------------------------------
-- SOFT FIRE (optional tiny packet nudge)
----------------------------------------------------------------
local function rewriteFirePayload(payload)
    if typeof(payload) ~= "table" or not H.targetPos then
        return payload
    end
    pcall(function()
        local origin = payload.camOrigin
        if typeof(origin) ~= "Vector3" then
            local c = cam()
            origin = c and c.CFrame.Position or H.targetPos
        end
        local want = (H.targetPos - origin)
        if want.Magnitude < 0.05 then
            return
        end
        want = want.Unit
        local cur = payload.camDir
        if typeof(cur) ~= "Vector3" or cur.Magnitude < 0.05 then
            payload.camDir = want
        else
            cur = cur.Unit
            local dot = math.clamp(cur:Dot(want), -1, 1)
            local ang = math.deg(math.acos(dot))
            local maxDeg = CFG.SoftMaxDeg or 8
            if ang <= maxDeg then
                payload.camDir = want
            else
                local axis = cur:Cross(want)
                if axis.Magnitude > 1e-4 then
                    local rot = CFrame.fromAxisAngle(axis.Unit, math.rad(maxDeg))
                    payload.camDir = rot:VectorToWorldSpace(cur).Unit
                end
            end
        end
        local head = H.targetModel and H.targetModel:FindFirstChild("Head")
        if head then
            payload.seen = head
            payload.seenPos = head.Position
            payload.seenHead = head.Position + Vector3.new(0, CFG.AimHeadOffset or 0, 0)
            pcall(function()
                payload.seenVel = head.AssemblyLinearVelocity
            end)
        end
    end)
    H.fireCount += 1
    if CFG.SoftDebug then
        print("[R1 SoftFire]", H.fireCount, H.targetModel and H.targetModel.Name)
    end
    return payload
end

task.spawn(function()
    local action
    pcall(function()
        action = ReplicatedStorage:WaitForChild("TPS", 8):WaitForChild("Remotes", 5):WaitForChild("Action", 5)
    end)
    if not action then
        return
    end
    local nc = newcclosure or function(f)
        return f
    end
    pcall(function()
        if not hookfunction then
            return
        end
        local old
        old = hookfunction(action.FireServer, nc(function(self, name, data, ...)
            if name == "Fire" and typeof(data) == "table" and CFG.SoftFire and CFG.AimEnabled and H.targetPos then
                data = rewriteFirePayload(data)
            end
            return old(self, name, data, ...)
        end))
        print("[R1 Aim] SoftFire hook on Action OK")
    end)
    pcall(function()
        if not hookmetamethod then
            return
        end
        local old
        old = hookmetamethod(game, "__namecall", nc(function(self, ...)
            if getnamecallmethod() == "FireServer" and self == action then
                local n, d = ...
                if n == "Fire" and typeof(d) == "table" and CFG.SoftFire and CFG.AimEnabled and H.targetPos then
                    d = rewriteFirePayload(d)
                    return old(self, n, d, select(3, ...))
                end
            end
            return old(self, ...)
        end))
    end)
end)

----------------------------------------------------------------
-- AIM LOCK (camera) — runs LATE so it wins vs recoil
----------------------------------------------------------------
RunService:BindToRenderStep("R1AimPick", Enum.RenderPriority.Camera.Value, function()
    H.targetPos, H.targetModel, H.targetPart = nil, nil, nil
    if not CFG.AimEnabled then
        return
    end
    local should = CFG.AimAlways or (CFG.AimOnLMB and H.lmb)
    if not should then
        return
    end
    local part, model, ap = pickTarget()
    if ap then
        H.targetPos = ap
        H.targetModel = model
        H.targetPart = part
    end
end)
table.insert(H.binds, "R1AimPick")

RunService:BindToRenderStep("R1AimApply", Enum.RenderPriority.Last.Value, function()
    if not CFG.AimEnabled or not H.targetPos then
        return
    end
    local should = CFG.AimAlways or (CFG.AimOnLMB and H.lmb)
    if not should then
        return
    end
    local c = cam()
    if not c then
        return
    end
    local goal = CFrame.new(c.CFrame.Position, H.targetPos)
    local a = math.clamp(CFG.AimSmooth or 1, 0.05, 1)
    if a >= 0.99 then
        c.CFrame = goal
    else
        c.CFrame = c.CFrame:Lerp(goal, a)
    end
end)
table.insert(H.binds, "R1AimApply")

----------------------------------------------------------------
-- ESP
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
    local box, corners = {}, {}
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Thickness = 1.4
        l.Color = color
        l.Visible = false
        box[i] = l
    end
    for i = 1, 8 do
        local l = Drawing.new("Line")
        l.Thickness = 2
        l.Color = color
        l.Visible = false
        corners[i] = l
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
    local headDot = Drawing.new("Circle")
    headDot.Thickness = 1
    headDot.NumSides = 12
    headDot.Filled = true
    headDot.Radius = 3.5
    headDot.Color = color
    headDot.Visible = false
    d = { box = box, corners = corners, tracer = tracer, name = name, hp = hp, headDot = headDot }
    H.drawings[model] = d
    return d
end

local function box2d(hrp)
    local pos = hrp.Position
    local half = Vector3.new(1.15, 2.65, 1.15)
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

local function updateESP()
    local c = cam()
    if not c then
        return
    end
    local root = myRoot()
    local seen = {}
    for _, t in ipairs(collect()) do
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
        if H.targetModel == model then
            color = Color3.fromRGB(255, 220, 80)
        end
        local head = model:FindFirstChild("Head") or hrp
        local top, onTop = w2s(head.Position + Vector3.new(0, 1.05, 0))
        local mid, onMid = w2s(hrp.Position)
        local headScreen, onHead = w2s(head.Position)
        local minX, minY, maxX, maxY
        if CFG.EspBoxes or CFG.EspCorners or CFG.EspHealth then
            minX, minY, maxX, maxY = box2d(hrp)
        end

        if CFG.EspBoxes and minX and not CFG.EspCorners then
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

        if CFG.EspCorners and minX then
            drawCorners(d, minX, minY, maxX, maxY, color)
        else
            for i = 1, 8 do
                d.corners[i].Visible = false
            end
        end

        if CFG.EspHealth and minX then
            local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            d.hp.From = Vector2.new(minX - 4, maxY)
            d.hp.To = Vector2.new(minX - 4, maxY - (maxY - minY) * ratio)
            d.hp.Color = Color3.fromRGB(255 * (1 - ratio), 255 * ratio, 50)
            d.hp.Visible = true
        else
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

        if CFG.EspHeadDot and onHead then
            d.headDot.Position = headScreen
            d.headDot.Color = color
            d.headDot.Visible = true
        else
            d.headDot.Visible = false
        end
    end
    for model in pairs(H.drawings) do
        if not seen[model] then
            killDraw(model)
        end
    end
end

local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1.4
fovCircle.NumSides = 64
fovCircle.Filled = false
fovCircle.Transparency = 0.55
fovCircle.Visible = false

RunService:BindToRenderStep("R1ESP", Enum.RenderPriority.Last.Value - 1, function()
    if CFG.ShowFov and CFG.AimEnabled then
        fovCircle.Position = fovCenter()
        fovCircle.Radius = CFG.AimFov
        fovCircle.Color = CFG.FovColor
        fovCircle.Visible = true
    else
        fovCircle.Visible = false
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
    for m in pairs(H.drawings) do
        killDraw(m)
    end
    pcall(function()
        fovCircle:Remove()
    end)
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
    local old = g:FindFirstChild("R1SilentESP")
    if old then
        old:Destroy()
    end
end)

local parentGui = (gethui and gethui()) or game:GetService("CoreGui")
if not pcall(function()
    make("ScreenGui", { Name = "R1SilentESP", ResetOnSpawn = false }, parentGui)
end) then
    parentGui = LP:WaitForChild("PlayerGui")
end

local gui = make("ScreenGui", {
    Name = "R1SilentESP",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 100,
}, parentGui)

local main = make("Frame", {
    Size = UDim2.fromOffset(300, 520),
    Position = UDim2.fromOffset(20, 90),
    BackgroundColor3 = Color3.fromRGB(20, 21, 26),
    BorderSizePixel = 0,
    Active = true,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
make("UIStroke", { Color = Color3.fromRGB(55, 55, 65), Thickness = 1 }, main)

local title = make("TextLabel", {
    Size = UDim2.new(1, -40, 0, 28),
    Position = UDim2.fromOffset(12, 6),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = Color3.fromRGB(240, 240, 245),
    Text = "R1 Aim Lock + ESP  ·  v6",
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local closeBtn = make("TextButton", {
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.new(1, -34, 0, 5),
    BackgroundColor3 = Color3.fromRGB(40, 40, 48),
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
    TextColor3 = Color3.fromRGB(140, 145, 155),
    Text = "Aim: off",
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
make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
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
        BackgroundColor3 = Color3.fromRGB(30, 31, 38),
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
end

local function slider(name, min, max, default, step, cb)
    local row = make("Frame", {
        LayoutOrder = nextOrder(),
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Color3.fromRGB(30, 31, 38),
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
end

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
    if H.targetModel then
        local tag = isBotModel(H.targetModel) and "BOT" or "PLR"
        status.Text = string.format("LOCK [%s] %s", tag, H.targetModel.Name)
        status.TextColor3 = Color3.fromRGB(100, 255, 140)
    else
        status.Text = CFG.AimEnabled and (H.lmb and "No target in FOV" or "Hold LMB to lock") or "Aim off"
        status.TextColor3 = Color3.fromRGB(140, 145, 155)
    end
end)

section("AIM LOCK (camera)")
toggle("Enable", CFG.AimEnabled, function(v)
    CFG.AimEnabled = v
    if not v then
        H.targetPos, H.targetModel, H.lockModel = nil, nil, nil
    end
end)
toggle("Only while shooting (LMB)", CFG.AimOnLMB, function(v)
    CFG.AimOnLMB = v
end)
toggle("Always (when in FOV)", CFG.AimAlways, function(v)
    CFG.AimAlways = v
end)
toggle("Sticky", CFG.AimSticky, function(v)
    CFG.AimSticky = v
end)
toggle("Team check", CFG.AimTeamCheck, function(v)
    CFG.AimTeamCheck = v
end)
toggle("Show FOV", CFG.ShowFov, function(v)
    CFG.ShowFov = v
end)
slider("FOV (px)", 40, 400, CFG.AimFov, 5, function(v)
    CFG.AimFov = v
end)
slider("Smooth (1=snap)", 0.15, 1, CFG.AimSmooth, 0.05, function(v)
    CFG.AimSmooth = v
end)
slider("Prediction", 0, 0.4, CFG.AimPredict, 0.01, function(v)
    CFG.AimPredict = v
end)

section("SOFT FIRE (packet nudge)")
toggle("Soft fire assist", CFG.SoftFire, function(v)
    CFG.SoftFire = v
end)
slider("Soft max degrees", 2, 20, CFG.SoftMaxDeg, 1, function(v)
    CFG.SoftMaxDeg = v
end)

section("ESP")
toggle("Players", CFG.EspPlayers, function(v)
    CFG.EspPlayers = v
end)
toggle("Bots", CFG.EspBots, function(v)
    CFG.EspBots = v
end)
toggle("Names", CFG.EspNames, function(v)
    CFG.EspNames = v
end)
toggle("Distance", CFG.EspDistance, function(v)
    CFG.EspDistance = v
end)
toggle("Corner boxes", CFG.EspCorners, function(v)
    CFG.EspCorners = v
end)
toggle("Tracers", CFG.EspTracers, function(v)
    CFG.EspTracers = v
end)
toggle("Health", CFG.EspHealth, function(v)
    CFG.EspHealth = v
end)
toggle("Head dot", CFG.EspHeadDot, function(v)
    CFG.EspHeadDot = v
end)

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

print("[R1 Aim Lock v6] Camera lock on LMB · Soft fire optional · RightShift UI")
print("[R1] True silent is blocked by this game — use Aim Lock")
