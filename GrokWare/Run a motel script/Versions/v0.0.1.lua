--[[
    Run a Motel — Auto Reception Helper
    PlaceId: 82046305882496

    - Finds your plot (OwnerUserId)
    - Detects guest at counter (CheckInAt / Guests)
    - Lists room ids on the plot
    - Auto CheckIn(room) when guest waiting
    - Auto TakeCash
    - Optional SetOpen(true) vacancy
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local GuestsNet = RS:WaitForChild("MotelGuestsNet", 10)
local CheckIn = GuestsNet and GuestsNet:WaitForChild("CheckIn", 5)
local TakeCash = GuestsNet and GuestsNet:WaitForChild("TakeCash", 5)
local SetOpen = GuestsNet and GuestsNet:FindFirstChild("SetOpen")
local GuestEvent = GuestsNet and GuestsNet:FindFirstChild("GuestEvent")

local CFG = {
    autoCheckIn = true,
    autoTakeCash = true,
    interval = 0.75,
    preferPrefix = "R1", -- try R101.. first
    openVacancy = false,
}

local function log(...)
    print("[MotelAuto]", ...)
end

local function inv(rf, ...)
    if not rf then
        return false, "missing remote"
    end
    local ok, a, b, c, d = pcall(function(...)
        return rf:InvokeServer(...)
    end, ...)
    if not ok then
        return false, tostring(a)
    end
    return a, b, c, d
end

----------------------------------------------------------------
-- Plot helpers
----------------------------------------------------------------
local function getMyPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then
        return nil
    end
    local uid = LP.UserId
    for _, p in ipairs(plots:GetChildren()) do
        if p:GetAttribute("OwnerUserId") == uid then
            return p
        end
    end
    -- fallback: plot with Guests + Office under Rooms
    for _, p in ipairs(plots:GetChildren()) do
        if p:FindFirstChild("Guests") and p:FindFirstChild("Rooms") then
            local office = p.Rooms:FindFirstChild("Office")
            if office then
                return p
            end
        end
    end
    return nil
end

local function roomIds(plot)
    local out = {}
    if not plot then
        return out
    end
    local rooms = plot:FindFirstChild("Rooms")
    if rooms then
        for _, ch in ipairs(rooms:GetChildren()) do
            local n = ch.Name
            if n:match("^R%d") then
                table.insert(out, n)
            end
        end
    end
    -- also scan neglect boards / signs for attr Room
    local neglect = plot:FindFirstChild("Neglect")
    if neglect then
        for _, d in ipairs(neglect:GetDescendants()) do
            local r = d:GetAttribute("Room")
            if type(r) == "string" and r:match("^R%d") then
                local seen = false
                for _, x in ipairs(out) do
                    if x == r then
                        seen = true
                        break
                    end
                end
                if not seen then
                    table.insert(out, r)
                end
            end
        end
    end
    table.sort(out)
    return out
end

local function guestWaiting(plot)
    if not plot then
        return false, nil
    end
    -- Server sets CheckInAt (Vector3) when someone is at the desk
    local at = plot:GetAttribute("CheckInAt")
    local already = plot:GetAttribute("CheckInRoom") -- room already chosen?

    local guestsFolder = plot:FindFirstChild("Guests")
    local nearest = nil
    local best = 1e9

    if typeof(at) == "Vector3" and guestsFolder then
        for _, g in ipairs(guestsFolder:GetChildren()) do
            if g:IsA("Model") and not g:GetAttribute("Kid") and not g:GetAttribute("CoffeeGuest") then
                local pp = g.PrimaryPart or g:FindFirstChild("HumanoidRootPart")
                if pp then
                    local d = (pp.Position - at) * Vector3.new(1, 0, 1)
                    local mag = d.Magnitude
                    if mag < best and mag < 16 then
                        best = mag
                        nearest = g
                    end
                end
            end
        end
        return nearest ~= nil, nearest, already
    end

    -- fallback: any non-kid guest in Guests
    if guestsFolder then
        for _, g in ipairs(guestsFolder:GetChildren()) do
            if g:IsA("Model") and not g:GetAttribute("Kid") and not g:GetAttribute("CoffeeGuest") then
                return true, g, already
            end
        end
    end
    return false, nil, already
end

local function pickRoom(plot)
    local ids = roomIds(plot)
    if #ids == 0 then
        -- sensible defaults from dump
        ids = { "R101", "R102", "R103", "R104", "R201", "R202", "R203", "R204" }
    end
    -- prefer lower floor / CFG.preferPrefix
    table.sort(ids, function(a, b)
        local ap = a:sub(1, #CFG.preferPrefix) == CFG.preferPrefix and 0 or 1
        local bp = b:sub(1, #CFG.preferPrefix) == CFG.preferPrefix and 0 or 1
        if ap ~= bp then
            return ap < bp
        end
        return a < b
    end)
    return ids[1], ids
end

----------------------------------------------------------------
-- Actions
----------------------------------------------------------------
local lastCheckInAt = 0
local lastCash = 0

local function doCheckIn(plot)
    local waiting, guest, alreadyRoom = guestWaiting(plot)
    if not waiting then
        return false, "no guest at counter"
    end
    -- if server already assigned a room attribute, use it
    local room = alreadyRoom
    if type(room) ~= "string" or room == "" then
        room = pickRoom(plot)
    end
    if type(room) ~= "string" then
        return false, "no room id"
    end

    local ok, msg, cash, extra = inv(CheckIn, room)
    -- returns: success, roomOrReason, cash, ?
    if ok == true then
        log(("CheckIn OK room=%s cash=%s guest=%s"):format(
            tostring(msg or room),
            tostring(cash),
            guest and guest.Name or "?"
        ))
        lastCheckInAt = os.clock()
        return true, cash
    end
    log("CheckIn fail:", tostring(ok), tostring(msg))
    return false, msg
end

local function doTakeCash()
    local amount = inv(TakeCash)
    if type(amount) == "number" then
        if amount > 0 then
            log("TakeCash:", amount)
            lastCash = amount
        end
        return amount
    end
    return 0
end

local function doSetOpen(open)
    if not SetOpen then
        return
    end
    inv(SetOpen, open == true)
end

----------------------------------------------------------------
-- Simple UI
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MotelAutoReception"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(280, 210)
frame.Position = UDim2.new(0, 16, 0.5, -105)
frame.BackgroundColor3 = Color3.fromRGB(22, 20, 28)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -12, 0, 28)
title.Position = UDim2.fromOffset(6, 4)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(240, 230, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Motel Auto Reception"
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -12, 0, 72)
status.Position = UDim2.fromOffset(6, 34)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(180, 170, 200)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Text = "Starting…"
status.Parent = frame

local function mkBtn(text, y, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -12, 0, 28)
    b.Position = UDim2.fromOffset(6, y)
    b.BackgroundColor3 = Color3.fromRGB(90, 60, 160)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 13
    b.Text = text
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(cb)
    return b
end

mkBtn("CheckIn now", 112, function()
    local plot = getMyPlot()
    if not plot then
        status.Text = "No plot found"
        return
    end
    local ok, info = doCheckIn(plot)
    status.Text = ok and ("Checked in · $" .. tostring(info or "?")) or ("Fail: " .. tostring(info))
end)

mkBtn("TakeCash now", 144, function()
    local n = doTakeCash()
    status.Text = "TakeCash → " .. tostring(n)
end)

mkBtn("Toggle auto", 176, function()
    CFG.autoCheckIn = not CFG.autoCheckIn
    CFG.autoTakeCash = CFG.autoCheckIn
    status.Text = "Auto: " .. (CFG.autoCheckIn and "ON" or "OFF")
end)

----------------------------------------------------------------
-- Main loop
----------------------------------------------------------------
task.spawn(function()
    while gui.Parent do
        local plot = getMyPlot()
        if not plot then
            status.Text = "Waiting for your plot…"
        else
            local waiting, guest, roomAttr = guestWaiting(plot)
            local rooms = roomIds(plot)
            local line = {
                "Plot: " .. plot.Name,
                "Rooms: " .. (#rooms > 0 and table.concat(rooms, ", ") or "?"),
                "Guest: " .. (waiting and (guest and guest.Name or "yes") or "none"),
                "CheckInRoom attr: " .. tostring(roomAttr or "—"),
                "Auto: " .. (CFG.autoCheckIn and "ON" or "OFF"),
                "Last cash: " .. tostring(lastCash),
            }
            status.Text = table.concat(line, "\n")

            if CFG.openVacancy and SetOpen then
                pcall(doSetOpen, true)
                CFG.openVacancy = false -- once
            end

            if CFG.autoCheckIn and waiting then
                doCheckIn(plot)
            end
            if CFG.autoTakeCash then
                doTakeCash()
            end
        end
        task.wait(CFG.interval)
    end
end)

if GuestEvent then
    GuestEvent.OnClientEvent:Connect(function(...)
        log("GuestEvent", ...)
    end)
end

log("loaded — stand behind desk when a guest arrives, or leave Auto ON")
