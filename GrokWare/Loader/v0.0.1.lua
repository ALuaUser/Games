--[[
    GrokWare Loader
    Repo: https://github.com/ALuaUser/Games/tree/main/GrokWare

    Detects the current PlaceId, lists Versions/ from that game folder,
    lets you pick a version, then loadstrings it.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local REPO = "ALuaUser/Games"
local BRANCH = "main"
local ROOT = "GrokWare"

-- PlaceId -> folder name under GrokWare/
local GAMES = {
    [135415094018012] = {
        name = "Guess the Character Age",
        folder = "Guess the Character Age Script",
    },
    [107430170196919] = {
        name = "Crazy 8 Ball Pool",
        folder = "Crazy 8 ball pool Script",
    },
    [114690486941238] = {
        name = "R1 Battle Royale",
        folder = "R1 Battle Royale Script",
    },
    [75942174630781] = {
        name = "R1 Battle Royale",
        folder = "R1 Battle Royale Script",
    },
}

local placeId = game.PlaceId
local entry = GAMES[placeId]

----------------------------------------------------------------
-- HTTP
----------------------------------------------------------------
local function httpGet(url)
    local req = (syn and syn.request)
        or (http and http.request)
        or http_request
        or request
        or (fluxus and fluxus.request)

    if req then
        local ok, res = pcall(req, {
            Url = url,
            Method = "GET",
        })
        if ok and res then
            local body = res.Body or res.body
            local code = res.StatusCode or res.status_code or res.Status or 200
            if body and (code == 200 or code == 0) then
                return body
            end
            return nil, "HTTP " .. tostring(code)
        end
        return nil, tostring(res)
    end

    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and body and body ~= "" then
        return body
    end
    return nil, tostring(body)
end

local function urlEncode(s)
    return tostring(s):gsub("([^%w%-%.%_%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "%%20")
end

local function apiContents(path)
    local url = ("https://api.github.com/repos/%s/contents/%s?ref=%s"):format(
        REPO,
        urlEncode(path):gsub("%%2F", "/"), -- keep slashes for path segments we encode per segment below
        BRANCH
    )
    -- proper segment encode
    local parts = {}
    for seg in string.gmatch(path, "[^/]+") do
        parts[#parts + 1] = urlEncode(seg)
    end
    url = ("https://api.github.com/repos/%s/contents/%s?ref=%s"):format(
        REPO,
        table.concat(parts, "/"),
        BRANCH
    )

    local body, err = httpGet(url)
    if not body then
        return nil, err
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if not ok or type(data) ~= "table" then
        return nil, "bad JSON"
    end
    return data
end

local function listVersions(folder)
    local data, err = apiContents(ROOT .. "/" .. folder .. "/Versions")
    if not data then
        return nil, err
    end
    local files = {}
    for _, item in ipairs(data) do
        if item.type == "file" and item.name then
            local n = item.name
            if n:match("%.lua$") or n:match("%.txt$") or n:match("%.luau$") then
                files[#files + 1] = {
                    name = n,
                    path = item.path,
                    download = item.download_url
                        or ("https://raw.githubusercontent.com/%s/%s/%s"):format(
                            REPO,
                            BRANCH,
                            item.path:gsub(" ", "%%20")
                        ),
                    size = item.size or 0,
                }
            end
        end
    end
    table.sort(files, function(a, b)
        return a.name > b.name -- newest-looking first (v0.0.4 > v0.0.1)
    end)
    return files
end

local function loadVersion(file)
    local url = file.download
    if not url then
        return false, "no download url"
    end
    -- ensure spaces encoded
    url = url:gsub(" ", "%%20")
    local src, err = httpGet(url)
    if not src or src == "" then
        return false, err or "empty response"
    end
    local fn, cerr = loadstring(src)
    if not fn then
        return false, "compile: " .. tostring(cerr)
    end
    local ok, res = pcall(fn)
    if not ok then
        return false, "runtime: " .. tostring(res)
    end
    return true, res
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local old = PG:FindFirstChild("GrokWareLoader")
if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "GrokWareLoader"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 200
gui.Parent = PG

local card = Instance.new("Frame")
card.Name = "Card"
card.Size = UDim2.fromOffset(340, 420)
card.Position = UDim2.new(0.5, -170, 0.5, -210)
card.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
card.BorderSizePixel = 0
card.Active = true
card.Parent = gui
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 70, 90)
stroke.Thickness = 1
stroke.Transparency = 0.4
stroke.Parent = card

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(16, 12)
title.Size = UDim2.new(1, -50, 0, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(235, 240, 250)
title.Text = "GrokWare Loader"
title.Parent = card

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -36, 0, 10)
closeBtn.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(200, 210, 220)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.Parent = card
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

local sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1
sub.Position = UDim2.fromOffset(16, 36)
sub.Size = UDim2.new(1, -32, 0, 36)
sub.Font = Enum.Font.Gotham
sub.TextSize = 12
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.TextYAlignment = Enum.TextYAlignment.Top
sub.TextWrapped = true
sub.TextColor3 = Color3.fromRGB(140, 150, 165)
sub.Text = "Detecting game…"
sub.Parent = card

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(16, 78)
status.Size = UDim2.new(1, -32, 0, 18)
status.Font = Enum.Font.GothamMedium
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.fromRGB(120, 200, 150)
status.Text = ""
status.Parent = card

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "Versions"
listFrame.Position = UDim2.fromOffset(12, 104)
listFrame.Size = UDim2.new(1, -24, 1, -120)
listFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 4
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.Parent = card
Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 10)

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = listFrame

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.Parent = listFrame

-- drag
do
    local dragging, start, startPos
    card.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            start = input.Position
            startPos = card.Position
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - start
            card.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

local function clearList()
    for _, c in ipairs(listFrame:GetChildren()) do
        if c:IsA("TextButton") then
            c:Destroy()
        end
    end
end

local function addRow(text, tone, onClick)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -4, 0, 36)
    btn.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
    btn.AutoButtonColor = true
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 13
    btn.TextColor3 = tone or Color3.fromRGB(220, 225, 235)
    btn.Text = text
    btn.Parent = listFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    if onClick then
        btn.MouseButton1Click:Connect(onClick)
    end
    return btn
end

local loading = false

local function showUnsupported()
    sub.Text = ("PlaceId %d is not mapped.\nAdd it in GAMES or open a supported game."):format(placeId)
    status.Text = "Unsupported"
    status.TextColor3 = Color3.fromRGB(228, 120, 100)
    clearList()
    addRow("Copy PlaceId", nil, function()
        if setclipboard then
            setclipboard(tostring(placeId))
            status.Text = "PlaceId copied"
        end
    end)
    addRow("Open repo", nil, function()
        if setclipboard then
            setclipboard("https://github.com/ALuaUser/Games/tree/main/GrokWare")
            status.Text = "Repo link copied"
        end
    end)
end

local function showVersions()
    sub.Text = ("%s\nPlaceId %d  ·  folder: %s"):format(entry.name, placeId, entry.folder)
    status.Text = "Fetching Versions…"
    status.TextColor3 = Color3.fromRGB(180, 190, 200)
    clearList()

    task.spawn(function()
        local files, err = listVersions(entry.folder)
        if not files then
            status.Text = "Failed: " .. tostring(err)
            status.TextColor3 = Color3.fromRGB(228, 120, 100)
            addRow("Retry", nil, showVersions)
            return
        end
        if #files == 0 then
            status.Text = "No scripts in Versions/"
            status.TextColor3 = Color3.fromRGB(224, 175, 104)
            return
        end
        status.Text = ("%d version(s) — click to load"):format(#files)
        status.TextColor3 = Color3.fromRGB(120, 200, 150)

        for i, file in ipairs(files) do
            local label = file.name
            if file.size > 0 then
                label = string.format("%s  (%.1f KB)", file.name, file.size / 1024)
            end
            addRow(label, nil, function()
                if loading then
                    return
                end
                loading = true
                status.Text = "Loading " .. file.name .. "…"
                status.TextColor3 = Color3.fromRGB(180, 190, 200)
                task.spawn(function()
                    local ok, res = loadVersion(file)
                    loading = false
                    if ok then
                        status.Text = "Loaded " .. file.name
                        status.TextColor3 = Color3.fromRGB(120, 200, 150)
                        -- close loader after success
                        task.delay(0.8, function()
                            if gui.Parent then
                                gui:Destroy()
                            end
                        end)
                    else
                        status.Text = "Error: " .. tostring(res)
                        status.TextColor3 = Color3.fromRGB(228, 120, 100)
                    end
                end)
            end)
        end
    end)
end

----------------------------------------------------------------
-- boot
----------------------------------------------------------------
if not entry then
    showUnsupported()
else
    showVersions()
end

print(("[GrokWare Loader] PlaceId=%s game=%s"):format(
    tostring(placeId),
    entry and entry.name or "unsupported"
))
