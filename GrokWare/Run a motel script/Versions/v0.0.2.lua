--[[
    Run a Motel — Full Helper
    PlaceId: 82046305882496

    From dumps:
      MotelGuestsNet  CheckIn TakeCash AnswerPhone ServeCoffee SetOpen
                      FoldTowel ToggleVacancy Deliver CarryBag DropBag
                      TakeSupply RefusePet GivePoolTowel GuestEvent
      MotelCleanNet   Wipe Report
      MotelChoresNet  Grill Hush Fix WalkStart WalkDone
      MotelYardNet    Repair FillPool BuyToolbox BuyWasher
      MotelLaundryNet Act
      MotelHotelNet   Refill Dishes
      MotelEconomyNet BuyRoom MoneyFx
      MotelStaffNet   Hire
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local function net(folder, name)
    local f = RS:FindFirstChild(folder)
    return f and f:FindFirstChild(name)
end

local R = {
    CheckIn = net("MotelGuestsNet", "CheckIn"),
    TakeCash = net("MotelGuestsNet", "TakeCash"),
    AnswerPhone = net("MotelGuestsNet", "AnswerPhone"),
    ServeCoffee = net("MotelGuestsNet", "ServeCoffee"),
    SetOpen = net("MotelGuestsNet", "SetOpen"),
    FoldTowel = net("MotelGuestsNet", "FoldTowel"),
    ToggleVacancy = net("MotelGuestsNet", "ToggleVacancy"),
    Deliver = net("MotelGuestsNet", "Deliver"),
    CarryBag = net("MotelGuestsNet", "CarryBag"),
    DropBag = net("MotelGuestsNet", "DropBag"),
    TakeSupply = net("MotelGuestsNet", "TakeSupply"),
    RefusePet = net("MotelGuestsNet", "RefusePet"),
    GivePoolTowel = net("MotelGuestsNet", "GivePoolTowel"),
    GuestEvent = net("MotelGuestsNet", "GuestEvent"),
    Wipe = net("MotelCleanNet", "Wipe"),
    CleanReport = net("MotelCleanNet", "Report"),
    Grill = net("MotelChoresNet", "Grill"),
    Hush = net("MotelChoresNet", "Hush"),
    Fix = net("MotelChoresNet", "Fix"),
    WalkStart = net("MotelChoresNet", "WalkStart"),
    WalkDone = net("MotelChoresNet", "WalkDone"),
    Repair = net("MotelYardNet", "Repair"),
    FillPool = net("MotelYardNet", "FillPool"),
    BuyToolbox = net("MotelYardNet", "BuyToolbox"),
    BuyWasher = net("MotelYardNet", "BuyWasher"),
    LaundryAct = net("MotelLaundryNet", "Act"),
    Refill = net("MotelHotelNet", "Refill"),
    Dishes = net("MotelHotelNet", "Dishes"),
    BuyRoom = net("MotelEconomyNet", "BuyRoom"),
    MoneyFx = net("MotelEconomyNet", "MoneyFx"),
    Hire = net("MotelStaffNet", "Hire"),
}

local CFG = {
    autoCheckIn = true,
    autoTakeCash = true,
    autoPhone = true,
    autoCoffee = false,
    autoHush = true,
    autoFix = false,
    autoWipe = false,
    interval = 0.7,
    preferPrefix = "R1",
}

local stats = {
    cash = 0,
    checkins = 0,
    phone = 0,
    lastMsg = "—",
}

local function log(...)
    print("[Motel]", ...)
end

local function inv(rf, ...)
    if not rf then
        return false, "no remote"
    end
    local pack = table.pack(pcall(function(...)
        return rf:InvokeServer(...)
    end, ...))
    local ok = pack[1]
    if not ok then
        return false, tostring(pack[2])
    end
    return table.unpack(pack, 2, pack.n)
end

----------------------------------------------------------------
-- Plot / rooms / guests
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
    for _, p in ipairs(plots:GetChildren()) do
        if p:GetAttribute("IsMotel") and p:FindFirstChild("Rooms") then
            local o = p:GetAttribute("OwnerUserId")
            if o == 0 or o == nil then
                -- unowned, skip
            elseif o == uid then
                return p
            end
        end
    end
    -- last resort: any plot with Guests that has a nearby character match
    for _, p in ipairs(plots:GetChildren()) do
        if p:FindFirstChild("Guests") and p:FindFirstChild("Rooms") and p.Rooms:FindFirstChild("Office") then
            if p:GetAttribute("OwnerUserId") == uid then
                return p
            end
        end
    end
    return nil
end

local function roomIds(plot)
    local out, seen = {}, {}
    local function add(n)
        if type(n) == "string" and n:match("^R%d") and not seen[n] then
            seen[n] = true
            table.insert(out, n)
        end
    end
    if plot then
        local rooms = plot:FindFirstChild("Rooms")
        if rooms then
            for _, ch in ipairs(rooms:GetChildren()) do
                add(ch.Name)
            end
        end
        for _, d in ipairs(plot:GetDescendants()) do
            add(d:GetAttribute("Room"))
        end
    end
    table.sort(out)
    if #out == 0 then
        out = { "R101", "R102", "R103", "R104", "R201", "R202", "R203", "R204" }
    end
    return out
end

local function pickRoom(plot)
    local ids = roomIds(plot)
    table.sort(ids, function(a, b)
        local ap = a:sub(1, #CFG.preferPrefix) == CFG.preferPrefix and 0 or 1
        local bp = b:sub(1, #CFG.preferPrefix) == CFG.preferPrefix and 0 or 1
        if ap ~= bp then
            return ap < bp
        end
        return a < b
    end)
    return ids[1]
end

local function guestWaiting(plot)
    if not plot then
        return false, nil, nil
    end
    local at = plot:GetAttribute("CheckInAt")
    local assigned = plot:GetAttribute("CheckInRoom")
    local guestsFolder = plot:FindFirstChild("Guests")
    local nearest, best = nil, 1e9

    if typeof(at) == "Vector3" and guestsFolder then
        for _, g in ipairs(guestsFolder:GetChildren()) do
            if g:IsA("Model") and not g:GetAttribute("Kid") and not g:GetAttribute("CoffeeGuest") then
                local pp = g.PrimaryPart or g:FindFirstChild("HumanoidRootPart")
                if pp then
                    local mag = ((pp.Position - at) * Vector3.new(1, 0, 1)).Magnitude
                    if mag < best and mag < 18 then
                        best, nearest = mag, g
                    end
                end
            end
        end
        return nearest ~= nil, nearest, assigned
    end
    if guestsFolder then
        for _, g in ipairs(guestsFolder:GetChildren()) do
            if g:IsA("Model") and not g:GetAttribute("Kid") and not g:GetAttribute("CoffeeGuest") then
                return true, g, assigned
            end
        end
    end
    return false, nil, assigned
end

local function dirtyRooms(plot)
    -- rooms with Dirty / NeedsClean attributes or Neglect trash folders
    local list = {}
    if not plot then
        return list
    end
    local rooms = plot:FindFirstChild("Rooms")
    if rooms then
        for _, r in ipairs(rooms:GetChildren()) do
            if r.Name:match("^R%d") then
                local dirty = r:GetAttribute("Dirty")
                    or r:GetAttribute("NeedsClean")
                    or r:GetAttribute("Messy")
                if dirty then
                    table.insert(list, r.Name)
                end
            end
        end
    end
    return list
end

----------------------------------------------------------------
-- Actions
----------------------------------------------------------------
local function doCheckIn(plot)
    local waiting, guest, assigned = guestWaiting(plot)
    if not waiting then
        return false, "no guest"
    end
    local room = (type(assigned) == "string" and assigned ~= "" and assigned) or pickRoom(plot)
    local ok, a, b = inv(R.CheckIn, room)
    if ok == true then
        stats.checkins += 1
        stats.lastMsg = ("CheckIn %s → $%s"):format(tostring(a or room), tostring(b))
        log(stats.lastMsg)
        return true, b
    end
    stats.lastMsg = "CheckIn fail: " .. tostring(ok) .. " " .. tostring(a)
    log(stats.lastMsg)
    return false, a
end

local function doTakeCash()
    local n = inv(R.TakeCash)
    if type(n) == "number" and n > 0 then
        stats.cash += n
        stats.lastMsg = "TakeCash $" .. n
        log(stats.lastMsg)
    end
    return type(n) == "number" and n or 0
end

local function doPhone()
    local ok, a = inv(R.AnswerPhone)
    if ok == true or ok == true then
        stats.phone += 1
        stats.lastMsg = "Phone answered"
        log(stats.lastMsg, a)
        return true
    end
    -- some games return success as first value differently
    if ok then
        stats.phone += 1
        return true
    end
    return false, a
end

local function doCoffee()
    return inv(R.ServeCoffee)
end

local function doHush(room)
    return inv(R.Hush, room)
end

local function doFix(room, family)
    -- Fix often takes room + broken family (TableLamp etc.)
    if family then
        return inv(R.Fix, room, family)
    end
    return inv(R.Fix, room)
end

local function doWipe(room)
    return inv(R.Wipe, room)
end

local function doFoldTowel()
    return inv(R.FoldTowel)
end

local function doVacancy()
    return inv(R.ToggleVacancy)
end

local function doSetOpen(v)
    return inv(R.SetOpen, v == true)
end

local function doFillPool()
    return inv(R.FillPool)
end

local function doBuyToolbox()
    return inv(R.BuyToolbox)
end

local function doHire(who)
    return inv(R.Hire, who)
end

local function doBuyRoom(room)
    return inv(R.BuyRoom, room)
end

local function doLaundry(action)
    return inv(R.LaundryAct, action)
end

local function doRefill()
    return inv(R.Refill)
end

local function doDishes()
    return inv(R.Dishes)
end

----------------------------------------------------------------
-- MoneyFx listener
----------------------------------------------------------------
if R.MoneyFx then
    R.MoneyFx.OnClientEvent:Connect(function(amount, pos, label)
        log("MoneyFx", amount, label)
        if type(amount) == "number" and amount > 0 then
            stats.lastMsg = ("FX $%s %s"):format(amount, tostring(label or ""))
        end
    end)
end

if R.GuestEvent then
    R.GuestEvent.OnClientEvent:Connect(function(...)
        log("GuestEvent", ...)
    end)
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MotelFullHelper"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(300, 420)
frame.Position = UDim2.new(0, 14, 0.5, -210)
frame.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -12, 0, 26)
title.Position = UDim2.fromOffset(8, 6)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(245, 235, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Motel Helper"
title.Parent = frame

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, -12, 0, 90)
status.Position = UDim2.fromOffset(8, 32)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(175, 165, 195)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Text = "…"
status.Parent = frame

local y = 128
local function btn(text, cb, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 26)
    b.Position = UDim2.fromOffset(8, y)
    b.BackgroundColor3 = color or Color3.fromRGB(88, 58, 150)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 12
    b.Text = text
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(cb)
    y += 30
    return b
end

local function toggle(name, key)
    local b
    b = btn(name .. ": ON", function()
        CFG[key] = not CFG[key]
        b.Text = name .. ": " .. (CFG[key] and "ON" or "OFF")
        b.BackgroundColor3 = CFG[key] and Color3.fromRGB(88, 58, 150) or Color3.fromRGB(50, 48, 58)
    end)
    return b
end

btn("CheckIn now", function()
    local p = getMyPlot()
    if p then
        doCheckIn(p)
    else
        stats.lastMsg = "No plot"
    end
end)

btn("TakeCash now", function()
    doTakeCash()
end, Color3.fromRGB(40, 120, 80))

btn("Answer phone", function()
    doPhone()
end)

btn("Serve coffee", function()
    local ok, a = doCoffee()
    stats.lastMsg = "Coffee: " .. tostring(ok) .. " " .. tostring(a)
end)

btn("Fold towel", function()
    local ok, a = doFoldTowel()
    stats.lastMsg = "Towel: " .. tostring(ok) .. " " .. tostring(a)
end)

btn("Toggle vacancy", function()
    local ok, a = doVacancy()
    stats.lastMsg = "Vacancy: " .. tostring(ok) .. " " .. tostring(a)
end)

btn("SetOpen true", function()
    doSetOpen(true)
    stats.lastMsg = "SetOpen true"
end)

btn("Fill pool", function()
    local ok, a = doFillPool()
    stats.lastMsg = "Pool: " .. tostring(ok) .. " " .. tostring(a)
end)

btn("Buy toolbox", function()
    local ok, a = doBuyToolbox()
    stats.lastMsg = "Toolbox: " .. tostring(ok) .. " " .. tostring(a)
end)

btn("Hotel refill / dishes", function()
    doRefill()
    doDishes()
    stats.lastMsg = "Refill + Dishes sent"
end)

y += 4
toggle("Auto CheckIn", "autoCheckIn")
toggle("Auto TakeCash", "autoTakeCash")
toggle("Auto Phone", "autoPhone")

----------------------------------------------------------------
-- Loop
----------------------------------------------------------------
task.spawn(function()
    while gui.Parent do
        local plot = getMyPlot()
        if not plot then
            status.Text = "No plot (OwnerUserId match)…"
        else
            local waiting, guest, roomAttr = guestWaiting(plot)
            local rooms = roomIds(plot)
            local dirty = dirtyRooms(plot)
            status.Text = table.concat({
                "Plot " .. plot.Name,
                "Guest: " .. (waiting and (guest and guest.Name or "yes") or "none"),
                "Rooms: " .. table.concat(rooms, " "),
                "Dirty: " .. (#dirty > 0 and table.concat(dirty, " ") or "—"),
                ("$%d  checkins %d  phone %d"):format(stats.cash, stats.checkins, stats.phone),
                stats.lastMsg,
            }, "\n")

            if CFG.autoCheckIn and waiting then
                doCheckIn(plot)
            end
            if CFG.autoTakeCash then
                doTakeCash()
            end
            if CFG.autoPhone then
                doPhone()
            end
            if CFG.autoCoffee then
                doCoffee()
            end
            if CFG.autoHush and #rooms > 0 then
                -- try hush on first room if noisy attrs exist
                for _, rname in ipairs(rooms) do
                    local r = plot.Rooms and plot.Rooms:FindFirstChild(rname)
                    if r and (r:GetAttribute("Noise") or r:GetAttribute("Party")) then
                        doHush(rname)
                    end
                end
            end
            if CFG.autoWipe then
                for _, rname in ipairs(dirty) do
                    doWipe(rname)
                end
            end
        end
        task.wait(CFG.interval)
    end
end)

log("Full helper loaded")
