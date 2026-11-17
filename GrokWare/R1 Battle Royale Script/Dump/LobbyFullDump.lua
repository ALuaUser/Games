--[[
    EVOLSDUMPER v2.2 (streamed flat dump, per-game folder)
    Generated: 2026-11-15 21:26:09
    Mode: FULL (flat)
    PlaceId: 114690486941238
--]]

-- Format: [n] ClassName | "Full.Path" | prop=val; attr:x=val; tags="a,b"

------------------------------------------------------------
-- SERVICE: Workspace
------------------------------------------------------------
[1] Workspace | "Workspace" | Name="Workspace"; attr:_mmSrc="--!nocheck\n--[[ ServerScriptService.R1_Matchmaking (ModuleScript) - ONE queue shared by every R1 server, like H1Z1.\n\t(The same module is in R1BR, the Map and Testing R1.)\n\tThe first group to queue reserves a fresh Map server and posts it in a MemoryStore as \"the open lobby\" for their mode.\n\tEveryone who queues in the next OpenWindow seconds - from ANY menu server - is teleported into that same server.\n\tWhen the window is nearly over (JoinMargin) or the lobby is full (Cap), the next group to queue opens a new one.\n\tThe Map server waits out the window (\"WAITING FOR PLAYERS 0:30\"), waits for whoever was sent to arrive, then counts\n\tdown; bots fill the rest.\n\tMemoryStore sorted map \"R1_Matchmaking\", key \"<Live|Studio>_<mode>\":\n\t  { code = reserved-server access code, id = its PrivateServerId, opened, closeAt (server time), seats, cap, mode }\n\n\tMM.Send(players, mode, extra?) -> true, lobby | false, why      (menu servers / the Testing R1 pad; extra = more teleport\n\t                                                          data - Duos: parties = { [\"<userId>\"] = teammate's userId })\n\tMM.Lookup(mode) -> this server's lobby or nil             (the Map: how many were sent here, when it closes)\n\tMM.Close(mode)                                            (the Map: full / starting early - send nobody else) ]]\nlocal MemoryStoreService = game:GetService(\"MemoryStoreService\")\nlocal TeleportService = game:GetService(\"TeleportService\")\nlocal RunService = game:GetService(\"RunService\")\n\nlocal MM = {\n\tPlaceId = 75942174630781, -- the Map\n\tOpenWindow = 30, -- seconds a new match server takes players for\n\tStudioOpenWindow = 5, -- (a Studio play test of the Map: don't make yourself wait 30 s every time)\n\tJoinMargin = 8, -- nobody new is sent this close to the window's end (so they're loaded in before it closes)\n\tArriveGrace = 15, -- the Map waits up to this long after the window for players still on their way\n\tCap = 55, -- real players per match (the Map's Max Players is 60: a little room for stragglers)\n\tExpiry = 600, -- seconds an open-lobby entry lives in the MemoryStore\n}\n\nlocal store = MemoryStoreService:GetSortedMap(\"R1_Matchmaking\")\nlocal function now() return workspace:GetServerTimeNow() end\nfunction MM.Key(mode) return (RunService:IsStudio() and \"Studio_\" or \"Live_\") .. tostring(mode or \"Solo\") end\nfunction MM.Window() return RunService:IsStudio() and MM.StudioOpenWindow or MM.OpenWindow end\n\nlocal function usable(cur, n, t)\n\treturn type(cur) == \"table\" and type(cur.code) == \"string\" and tonumber(cur.closeAt) ~= nil\n\t\tand cur.closeAt - t >= MM.JoinMargin and (tonumber(cur.seats) or 0) + n <= (tonumber(cur.cap) or MM.Cap)\nend\n\n-- take n seats in the open lobby; if there isn't a usable one, `fresh` becomes the open lobby (when given)\nlocal function claim(key, n, fresh)\n\tlocal got\n\tstore:UpdateAsync(key, function(cur)\n\t\tgot = nil\n\t\tif usable(cur, n, now()) then\n\t\t\tcur.seats = (tonumber(cur.seats) or 0) + n\n\t\t\tgot = cur\n\t\t\treturn cur\n\t\tend\n\t\tif fresh then\n\t\t\tgot = fresh\n\t\t\treturn fresh\n\t\tend\n\t\treturn nil -- (nothing open and nothing to post: leave it)\n\tend, MM.Expiry)\n\treturn got\nend\n\nlocal function reserve(mode, n)\n\tlocal ok, code, id = pcall(function() return TeleportService:ReserveServer(MM.PlaceId) end)\n\tif not ok then return nil, tostring(code) end\n\tlocal t = now()\n\treturn { code = code, id = id, opened = t, closeAt = t + MM.OpenWindow, seats = n, cap = MM.Cap, mode = mode }\nend\n\nlocal function teleport(list, lobby, mode, extra)\n\tlocal opts = Instance.new(\"TeleportOptions\")\n\topts.ReservedServerAccessCode = lobby.code\n\tlocal td = { from = \"queue\", mode = mode, closeAt = lobby.closeAt, lobby = lobby.id }\n\tfor k, v in pairs(type(extra) == \"table\" and extra or {}) do\n\t\tif td[k] == nil then td[k] = v end\n\tend\n\topts:SetTeleportData(td)\n\treturn pcall(function() return TeleportService:TeleportAsync(MM.PlaceId, list, opts) end)\nend\n\nfunction MM.Send(list, mode, extra)\n\tmode = mode or \"Solo\"\n\tlocal n = #list\n\tif n == 0 then return false, \"nobody to send\" end\n\tlocal key = MM.Key(mode)\n\tlocal okC, lobby = pcall(claim, key, n, nil)\n\tlocal shared = okC\n\tif okC and not lobby then -- nothing open: open one (and post it - unless someone beat us to it, then join theirs)\n\t\tlocal fresh, why = reserve(mode, n)\n\t\tif not fresh then return false, \"couldn't open a match server: \" .. why end\n\t\tokC, lobby = pcall(claim, key, n, fresh)\n\t\tif not okC then lobby, shared = fresh, false end\n\t\tif lobby == fresh then print(string.format(\"[R1 Matchmaking] opened a new %s lobby (%s), open for %ds\", mode, tostring(fresh.id), MM.OpenWindow)) end\n\telseif not okC then -- the MemoryStore is down: still get them into a match (a private one)\n\t\twarn(\"[R1 Matchmaking] MemoryStore unavailable (\" .. tostring(lobby) .. \") - sending this group to a match of its own\")\n\t\tlocal fresh, why = reserve(mode, n)\n\t\tif not fresh then return false, \"couldn't open a match server: \" .. why end\n\t\tlobby = fresh\n\tend\n\tlocal okT, err = teleport(list, lobby, mode, extra)\n\tif not okT then return false, tostring(err) end\n\tprint(string.format(\"[R1 Matchmaking] sent %d player(s) to %s lobby %s (%d seat(s) taken, closes in %ds)%s\", n, mode, tostring(lobby.id),\n\t\ttonumber(lobby.seats) or n, math.max(0, math.floor(lobby.closeAt - now())), shared and \"\" or \" [not shared]\"))\n\treturn true, lobby\nend\n\n-- the Map: this server's entry, while it's still the open lobby\nfunction MM.Lookup(mode)\n\tlocal id = game.PrivateServerId\n\tif id == \"\" then return nil end\n\tlocal ok, cur = pcall(function() return store:GetAsync(MM.Key(mode)) end)\n\tif ok and type(cur) == \"table\" and cur.id == id then return cur end\n\treturn nil\nend\n\n-- the Map: stop sending players here (only if this server is still the open lobby)\nfunction MM.Close(mode)\n\tlocal id = game.PrivateServerId\n\tif id == \"\" then return end\n\tpcall(function()\n\t\tstore:UpdateAsync(MM.Key(mode), function(cur)\n\t\t\tif type(cur) == \"table\" and cur.id == id then\n\t\t\t\tcur.closeAt = 0\n\t\t\t\treturn cur\n\t\t\tend\n\t\t\treturn nil\n\t\tend, MM.Expiry)\n\tend)\nend\n\nreturn MM\n"
[2] Camera | "Workspace.Camera" | Name="Camera"
[3] AudioListener | "Workspace.Camera.AudioListener" | Name="AudioListener"
[4] Wire | "Workspace.Camera.AudioListener.Wire" | Name="Wire"
[5] AudioDeviceOutput | "Workspace.Camera.AudioListener.Wire.AudioDeviceOutput" | Name="AudioDeviceOutput"
[6] BlurEffect | "Workspace.Blur" | Name="Blur"
[7] BloomEffect | "Workspace.Bloom" | Name="Bloom"
[8] Model | "Workspace.big skeleton head" | Name="big skeleton head"
[9] ViewportCamera | "Workspace.big skeleton head.ThumbnailCamera" | Name="ThumbnailCamera"
[10] ColorCorrectionEffect | "Workspace.ColorCorrection" | Name="ColorCorrection"
[11] SunRaysEffect | "Workspace.SunRays" | Name="SunRays"
[12] Model | "Workspace.MenuScene" | Name="MenuScene"
[13] Model | "Workspace.MenuScene.R1_MenuWasteland" | Name="R1_MenuWasteland"; attr:Yaw=16.484672017616; attr:SkyWallDistance=380
[14] Script | "Workspace.MenuScene.R1_MenuWasteland.R1_SceneGrade" | Name="R1_SceneGrade"
[15] Model | "Workspace.MenuScene.R1_MenuWasteland.SkyWall" | Name="SkyWall"
[16] Part | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid" | Name="SkyMid"
[17] SurfaceGui | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint" | Name="Paint"
[18] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Sky" | Name="Sky"
[19] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Sky.UIGradient" | Name="UIGradient"
[20] ImageLabel | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Glow" | Name="Glow"
[21] ImageLabel | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Glow" | Name="Glow"
[22] ImageLabel | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Glow" | Name="Glow"
[23] ImageLabel | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Glow" | Name="Glow"
[24] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[25] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[26] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[27] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[28] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[29] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[30] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[31] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[32] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[33] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[34] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[35] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[36] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[37] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[38] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[39] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[40] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[41] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[42] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[43] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[44] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[45] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[46] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[47] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[48] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[49] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[50] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[51] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[52] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[53] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[54] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[55] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[56] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[57] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[58] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[59] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[60] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[61] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[62] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[63] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[64] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[65] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[66] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[67] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[68] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[69] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[70] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[71] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[72] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[73] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[74] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[75] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[76] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[77] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[78] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[79] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[80] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[81] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[82] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[83] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[84] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[85] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[86] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[87] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[88] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[89] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[90] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[91] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[92] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[93] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[94] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[95] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[96] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[97] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[98] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[99] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[100] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[101] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[102] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud" | Name="Cloud"
[103] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UICorner" | Name="UICorner"
[104] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.UIGradient" | Name="UIGradient"
[105] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim" | Name="Rim"
[106] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UICorner" | Name="UICorner"
[107] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyMid.Paint.Cloud.Rim.UIGradient" | Name="UIGradient"
[108] Part | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft" | Name="SkyLeft"
[109] SurfaceGui | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint" | Name="Paint"
[110] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Sky" | Name="Sky"
[111] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Sky.UIGradient" | Name="UIGradient"
[112] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud" | Name="Cloud"
[113] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UICorner" | Name="UICorner"
[114] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UIGradient" | Name="UIGradient"
[115] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud" | Name="Cloud"
[116] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UICorner" | Name="UICorner"
[117] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UIGradient" | Name="UIGradient"
[118] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud" | Name="Cloud"
[119] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UICorner" | Name="UICorner"
[120] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UIGradient" | Name="UIGradient"
[121] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud" | Name="Cloud"
[122] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UICorner" | Name="UICorner"
[123] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UIGradient" | Name="UIGradient"
[124] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud" | Name="Cloud"
[125] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UICorner" | Name="UICorner"
[126] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UIGradient" | Name="UIGradient"
[127] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud" | Name="Cloud"
[128] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UICorner" | Name="UICorner"
[129] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyLeft.Paint.Cloud.UIGradient" | Name="UIGradient"
[130] Part | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight" | Name="SkyRight"
[131] SurfaceGui | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint" | Name="Paint"
[132] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Sky" | Name="Sky"
[133] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Sky.UIGradient" | Name="UIGradient"
[134] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud" | Name="Cloud"
[135] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UICorner" | Name="UICorner"
[136] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UIGradient" | Name="UIGradient"
[137] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud" | Name="Cloud"
[138] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UICorner" | Name="UICorner"
[139] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UIGradient" | Name="UIGradient"
[140] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud" | Name="Cloud"
[141] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UICorner" | Name="UICorner"
[142] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UIGradient" | Name="UIGradient"
[143] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud" | Name="Cloud"
[144] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UICorner" | Name="UICorner"
[145] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UIGradient" | Name="UIGradient"
[146] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud" | Name="Cloud"
[147] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UICorner" | Name="UICorner"
[148] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UIGradient" | Name="UIGradient"
[149] Frame | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud" | Name="Cloud"
[150] UICorner | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UICorner" | Name="UICorner"
[151] UIGradient | "Workspace.MenuScene.R1_MenuWasteland.SkyWall.SkyRight.Paint.Cloud.UIGradient" | Name="UIGradient"
[152] Model | "Workspace.MenuScene.R1_MenuWasteland.Ground" | Name="Ground"
[153] Model | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks" | Name="Cracks"
[154] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[155] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[156] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[157] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[158] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[159] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[160] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[161] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[162] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[163] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[164] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[165] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[166] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[167] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[168] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[169] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[170] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[171] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[172] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[173] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[174] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[175] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[176] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[177] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[178] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[179] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[180] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[181] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[182] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[183] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[184] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[185] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[186] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[187] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[188] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[189] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[190] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[191] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[192] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[193] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[194] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[195] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[196] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[197] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[198] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[199] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[200] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[201] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[202] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[203] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[204] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[205] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[206] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[207] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[208] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[209] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[210] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[211] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[212] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[213] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[214] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[215] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[216] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[217] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[218] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[219] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[220] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[221] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Cracks.Part" | Name="Part"
[222] Model | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound" | Name="Mound"
[223] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.TopSlab" | Name="TopSlab"
[224] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[225] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[226] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[227] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[228] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[229] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[230] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[231] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[232] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[233] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[234] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[235] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[236] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[237] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[238] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[239] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[240] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[241] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[242] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[243] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[244] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[245] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[246] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[247] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[248] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[249] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[250] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[251] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[252] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[253] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[254] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[255] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[256] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[257] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[258] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[259] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[260] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[261] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[262] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[263] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[264] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[265] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[266] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[267] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[268] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Part" | Name="Part"
[269] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Mound.Tire" | Name="Tire"
[270] Model | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges" | Name="Ridges"
[271] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[272] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[273] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[274] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[275] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[276] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[277] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[278] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[279] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[280] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[281] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[282] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[283] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[284] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[285] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[286] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Ridges.Part" | Name="Part"
[287] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.Lakebed" | Name="Lakebed"
[288] Part | "Workspace.MenuScene.R1_MenuWasteland.Ground.YardPad" | Name="YardPad"
[289] Model | "Workspace.MenuScene.R1_MenuWasteland.Yard" | Name="Yard"
[290] Model | "Workspace.MenuScene.R1_MenuWasteland.Yard.BurningCar" | Name="BurningCar"
[291] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.BurningCar.Part" | Name="Part"
[292] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.BurningCar.Part" | Name="Part"
[293] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.BurningCar.Part" | Name="Part"
[294] WedgePart | "Workspace.MenuScene.R1_MenuWasteland.Yard.BurningCar.Wedge" | Name="Wedge"
[295] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.BurningCar.Part" | Name="Part"
[296] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.BurningCar.Part" | Name="Part"
[297] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.BurningCar.Part" | Name="Part"
[298] Model | "Workspace.MenuScene.R1_MenuWasteland.Yard.CarWreck" | Name="CarWreck"
[299] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.CarWreck.Part" | Name="Part"
[300] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.CarWreck.Part" | Name="Part"
[301] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.CarWreck.Part" | Name="Part"
[302] Model | "Workspace.MenuScene.R1_MenuWasteland.Yard.CarWreck" | Name="CarWreck"
[303] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.CarWreck.Part" | Name="Part"
[304] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.CarWreck.Part" | Name="Part"
[305] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.CarWreck.Part" | Name="Part"
[306] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.Part" | Name="Part"
[307] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.Part" | Name="Part"
[308] Part | "Workspace.MenuScene.R1_MenuWasteland.Yard.Part" | Name="Part"
[309] Model | "Workspace.MenuScene.R1_MenuWasteland.Far" | Name="Far"
[310] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.Dam" | Name="Dam"
[311] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Dam.Part" | Name="Part"
[312] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Dam.Part" | Name="Part"
[313] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Dam.Part" | Name="Part"
[314] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Dam.Part" | Name="Part"
[315] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Dam.Part" | Name="Part"
[316] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Dam.BreachGlow" | Name="BreachGlow"
[317] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Dam.BreachGlow2" | Name="BreachGlow2"
[318] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.Barn" | Name="Barn"
[319] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Barn.Part" | Name="Part"
[320] WedgePart | "Workspace.MenuScene.R1_MenuWasteland.Far.Barn.Wedge" | Name="Wedge"
[321] WedgePart | "Workspace.MenuScene.R1_MenuWasteland.Far.Barn.Wedge" | Name="Wedge"
[322] WedgePart | "Workspace.MenuScene.R1_MenuWasteland.Far.Barn.Wedge" | Name="Wedge"
[323] WedgePart | "Workspace.MenuScene.R1_MenuWasteland.Far.Barn.Wedge" | Name="Wedge"
[324] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Barn.Part" | Name="Part"
[325] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.WaterTower" | Name="WaterTower"
[326] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.WaterTower.Part" | Name="Part"
[327] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.WaterTower.Part" | Name="Part"
[328] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.WaterTower.Part" | Name="Part"
[329] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.WaterTower.Part" | Name="Part"
[330] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.WaterTower.Part" | Name="Part"
[331] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.WaterTower.Part" | Name="Part"
[332] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.WaterTower.Part" | Name="Part"
[333] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.WaterTower.Part" | Name="Part"
[334] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin" | Name="Ruin"
[335] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[336] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[337] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[338] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[339] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[340] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[341] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[342] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[343] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[344] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[345] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[346] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Ruin.Part" | Name="Part"
[347] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.Warehouse" | Name="Warehouse"
[348] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Warehouse.Part" | Name="Part"
[349] WedgePart | "Workspace.MenuScene.R1_MenuWasteland.Far.Warehouse.Wedge" | Name="Wedge"
[350] WedgePart | "Workspace.MenuScene.R1_MenuWasteland.Far.Warehouse.Wedge" | Name="Wedge"
[351] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane" | Name="Crane"
[352] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[353] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[354] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[355] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[356] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[357] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[358] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[359] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[360] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[361] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[362] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[363] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[364] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[365] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[366] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[367] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[368] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[369] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[370] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[371] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[372] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[373] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[374] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[375] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[376] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[377] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[378] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[379] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[380] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Crane.Part" | Name="Part"
[381] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines" | Name="PowerLines"
[382] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon" | Name="Pylon"; attr:TipL=Vector3.new(-21.009, 20.8076, -202.356); attr:TipT=Vector3.new(-18.7193, 27.172, -203.034); attr:TipR=Vector3.new(-3.61454, 22.7142, -207.504)
[383] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[384] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[385] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[386] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[387] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[388] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[389] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[390] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[391] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[392] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[393] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[394] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon" | Name="Pylon"; attr:TipL=Vector3.new(29.6574, 25.2007, -352.922); attr:TipT=Vector3.new(33.7478, 31.1669, -354.133); attr:TipR=Vector3.new(48.2961, 22.1221, -358.438)
[395] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[396] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[397] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[398] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[399] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[400] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[401] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[402] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[403] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[404] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[405] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[406] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon" | Name="Pylon"; attr:TipL=Vector3.new(128.033, 25.2913, -580.178); attr:TipT=Vector3.new(130.929, 32.5597, -581.035); attr:TipR=Vector3.new(148.235, 26.7645, -586.157)
[407] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[408] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[409] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[410] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[411] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[412] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[413] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[414] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[415] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[416] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[417] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[418] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon" | Name="Pylon"; attr:TipL=Vector3.new(313.37, 28.3442, -885.312); attr:TipT=Vector3.new(317.5, 35.3555, -886.534); attr:TipR=Vector3.new(334.462, 26.4198, -891.553)
[419] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[420] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[421] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[422] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[423] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[424] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[425] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[426] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[427] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[428] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[429] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[430] Model | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon" | Name="Pylon"; attr:TipL=Vector3.new(-456.271, 24.1567, -355.126); attr:TipT=Vector3.new(-452.578, 30.1871, -356.219); attr:TipR=Vector3.new(-437.961, 22.1497, -360.545)
[431] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[432] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[433] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[434] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[435] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[436] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[437] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[438] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[439] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[440] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[441] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Pylon.Part" | Name="Part"
[442] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[443] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[444] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[445] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[446] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[447] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[448] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[449] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[450] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[451] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[452] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[453] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[454] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[455] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[456] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[457] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[458] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[459] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[460] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[461] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[462] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[463] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[464] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[465] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[466] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[467] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[468] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[469] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[470] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[471] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[472] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[473] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[474] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[475] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[476] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[477] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[478] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[479] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[480] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[481] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[482] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[483] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[484] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[485] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[486] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[487] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[488] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[489] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[490] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[491] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[492] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[493] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[494] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[495] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[496] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[497] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[498] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.PowerLines.Part" | Name="Part"
[499] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.FireGlow" | Name="FireGlow"
[500] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.FireGlow" | Name="FireGlow"
[501] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.FireGlow" | Name="FireGlow"
[502] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[503] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[504] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[505] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Quonset" | Name="Quonset"
[506] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[507] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[508] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[509] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[510] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[511] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[512] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[513] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[514] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[515] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[516] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[517] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[518] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[519] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[520] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[521] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[522] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[523] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[524] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[525] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[526] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[527] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[528] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[529] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[530] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[531] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[532] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[533] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[534] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[535] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[536] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[537] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[538] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[539] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[540] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[541] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[542] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[543] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[544] Part | "Workspace.MenuScene.R1_MenuWasteland.Far.Part" | Name="Part"
[545] Model | "Workspace.MenuScene.R1_MenuWasteland.Front" | Name="Front"
[546] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[547] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[548] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[549] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[550] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[551] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[552] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[553] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[554] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[555] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[556] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[557] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[558] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[559] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[560] Part | "Workspace.MenuScene.R1_MenuWasteland.Front.Part" | Name="Part"
[561] Folder | "Workspace.MenuScene.R1_MenuWasteland.FX" | Name="FX"
[562] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.BackLight" | Name="BackLight"
[563] PointLight | "Workspace.MenuScene.R1_MenuWasteland.FX.BackLight.PointLight" | Name="PointLight"
[564] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.BackLight2" | Name="BackLight2"
[565] PointLight | "Workspace.MenuScene.R1_MenuWasteland.FX.BackLight2.PointLight" | Name="PointLight"
[566] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.ClearingLight" | Name="ClearingLight"
[567] PointLight | "Workspace.MenuScene.R1_MenuWasteland.FX.ClearingLight.PointLight" | Name="PointLight"
[568] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.SmokeDam" | Name="SmokeDam"
[569] ParticleEmitter | "Workspace.MenuScene.R1_MenuWasteland.FX.SmokeDam.ParticleEmitter" | Name="ParticleEmitter"
[570] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.SmokeBarn" | Name="SmokeBarn"
[571] ParticleEmitter | "Workspace.MenuScene.R1_MenuWasteland.FX.SmokeBarn.ParticleEmitter" | Name="ParticleEmitter"
[572] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.SmokeTower" | Name="SmokeTower"
[573] ParticleEmitter | "Workspace.MenuScene.R1_MenuWasteland.FX.SmokeTower.ParticleEmitter" | Name="ParticleEmitter"
[574] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.SmokeRight" | Name="SmokeRight"
[575] ParticleEmitter | "Workspace.MenuScene.R1_MenuWasteland.FX.SmokeRight.ParticleEmitter" | Name="ParticleEmitter"
[576] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.SmokeCar" | Name="SmokeCar"
[577] ParticleEmitter | "Workspace.MenuScene.R1_MenuWasteland.FX.SmokeCar.ParticleEmitter" | Name="ParticleEmitter"
[578] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.Embers" | Name="Embers"
[579] ParticleEmitter | "Workspace.MenuScene.R1_MenuWasteland.FX.Embers.ParticleEmitter" | Name="ParticleEmitter"
[580] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.CarFire" | Name="CarFire"
[581] Fire | "Workspace.MenuScene.R1_MenuWasteland.FX.CarFire.Fire" | Name="Fire"
[582] PointLight | "Workspace.MenuScene.R1_MenuWasteland.FX.CarFire.PointLight" | Name="PointLight"
[583] Part | "Workspace.MenuScene.R1_MenuWasteland.FX.FillLight" | Name="FillLight"
[584] SpotLight | "Workspace.MenuScene.R1_MenuWasteland.FX.FillLight.SpotLight" | Name="SpotLight"
[585] Configuration | "Workspace.MenuScene.R1_MenuWasteland.Grade" | Name="Grade"; attr:ClockTime=16.258; attr:ColorShift_Bottom=Color3.new(0.15686, 0.13333, 0.18824); attr:EnvironmentDiffuseScale=0.45; attr:EnvironmentSpecularScale=0.2; attr:GeographicLatitude=-50.45; attr:Ambient=Color3.new(0.36078, 0.31373, 0.31373); attr:OutdoorAmbient=Color3.new(0.58824, 0.47843, 0.42353); attr:Brightness=2.4; attr:ColorShift_Top=Color3.new(1, 0.67451, 0.43137); attr:ExposureCompensation=0
[586] Atmosphere | "Workspace.MenuScene.R1_MenuWasteland.Grade.R1SceneAtmosphere" | Name="R1SceneAtmosphere"
[587] BloomEffect | "Workspace.MenuScene.R1_MenuWasteland.Grade.R1SceneBloom" | Name="R1SceneBloom"
[588] ColorCorrectionEffect | "Workspace.MenuScene.R1_MenuWasteland.Grade.R1SceneGrade" | Name="R1SceneGrade"
[589] Part | "Workspace.MenuScene.R1_MenuWasteland.R1_StageFloor" | Name="R1_StageFloor"
[590] Folder | "Workspace.MenuScene.CrateRange" | Name="CrateRange"; attr:Info="The crate-opening range (Crates tab): Stand = where your avatar stands (its front faces the way it looks), Drop = where the crate lands (its front faces the camera). The camera is MenuScene.Cameras.Crates (FOV attribute = zoom)."
[591] Part | "Workspace.MenuScene.CrateRange.Stand" | Name="Stand"
[592] Part | "Workspace.MenuScene.CrateRange.Drop" | Name="Drop"
[593] Folder | "Workspace.MenuScene.Cameras" | Name="Cameras"
[594] Part | "Workspace.MenuScene.Cameras.Gear" | Name="Gear"; attr:FOV=50
[595] Part | "Workspace.MenuScene.Cameras.Title" | Name="Title"; attr:FOV=55
[596] Part | "Workspace.MenuScene.Cameras.Crates" | Name="Crates"; attr:FOV=55
[597] Part | "Workspace.MenuScene.Cameras.Armory" | Name="Armory"; attr:FOV=70
[598] Part | "Workspace.MenuScene.Cameras.Main" | Name="Main"; attr:OldCFrame=CFrame.new(3.6,4.6,15.5,0.911371,-0.0337665,0.410199,0,0.996629,0.0820398,-0.411587,-0.0747687,0.908298); attr:FOV=51.5; attr:R1Polished=true
[599] Model | "Workspace.MenuScene.Armory" | Name="Armory"
[600] Part | "Workspace.MenuScene.Armory.Lamp" | Name="Lamp"
[601] SpotLight | "Workspace.MenuScene.Armory.Lamp.SpotLight" | Name="SpotLight"
[602] Part | "Workspace.MenuScene.Armory.GunMount" | Name="GunMount"
[603] Part | "Workspace.MenuScene.Armory.Wall" | Name="Wall"
[604] SpawnLocation | "Workspace.MenuScene.MenuSpawn" | Name="MenuSpawn"
[605] Part | "Workspace.MenuScene.Stage" | Name="Stage"; attr:Pitch=-30; attr:HeroLeftElbow=Vector3.new(-0.3, -1, 0.8); attr:HeroLean=0; attr:HeroRoll=3; attr:HeroLeftHand=Vector3.new(0, 0.05, -1); attr:HeroGrip=Vector3.new(0.55, -0.4, -0.72); attr:Yaw=-32; attr:HeroRightElbow=Vector3.new(0.35, -1, 0.9); attr:HeroBarrel=Vector3.new(-0.82, 0.5, -0.2); attr:HeroTwist=14; attr:HeroSpread=8; attr:HeroGunUp=Vector3.new(0.5, 0.82, 0.1)
[606] Model | "Workspace.Lobby" | Name="Lobby"
[607] Folder | "Workspace.Lobby.Deck" | Name="Deck"
[608] Part | "Workspace.Lobby.Deck.Frame" | Name="Frame"
[609] Part | "Workspace.Lobby.Deck.Frame" | Name="Frame"
[610] Part | "Workspace.Lobby.Deck.Deck" | Name="Deck"
[611] Part | "Workspace.Lobby.Deck.Frame" | Name="Frame"
[612] Part | "Workspace.Lobby.Deck.Frame" | Name="Frame"
[613] Folder | "Workspace.Lobby.Walls" | Name="Walls"
[614] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[615] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[616] Part | "Workspace.Lobby.Walls.GlassN" | Name="GlassN"
[617] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[618] Part | "Workspace.Lobby.Walls.BarrierS" | Name="BarrierS"
[619] Part | "Workspace.Lobby.Walls.RailN" | Name="RailN"
[620] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[621] Part | "Workspace.Lobby.Walls.RailS" | Name="RailS"
[622] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[623] Part | "Workspace.Lobby.Walls.GlassS" | Name="GlassS"
[624] Part | "Workspace.Lobby.Walls.BarrierW" | Name="BarrierW"
[625] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[626] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[627] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[628] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[629] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[630] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[631] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[632] Part | "Workspace.Lobby.Walls.BarrierN" | Name="BarrierN"
[633] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[634] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[635] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[636] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[637] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[638] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[639] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[640] Part | "Workspace.Lobby.Walls.BarrierE" | Name="BarrierE"
[641] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[642] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[643] Part | "Workspace.Lobby.Walls.RailE" | Name="RailE"
[644] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[645] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[646] Part | "Workspace.Lobby.Walls.GlassE" | Name="GlassE"
[647] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[648] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[649] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[650] Part | "Workspace.Lobby.Walls.RailW" | Name="RailW"
[651] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[652] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[653] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[654] Part | "Workspace.Lobby.Walls.GlassW" | Name="GlassW"
[655] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[656] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[657] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[658] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[659] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[660] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[661] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[662] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[663] Part | "Workspace.Lobby.Walls.Post" | Name="Post"
[664] Folder | "Workspace.Lobby.Under" | Name="Under"
[665] Part | "Workspace.Lobby.Under.Pod" | Name="Pod"
[666] Part | "Workspace.Lobby.Under.Jet" | Name="Jet"
[667] PointLight | "Workspace.Lobby.Under.Jet.PointLight" | Name="PointLight"
[668] Part | "Workspace.Lobby.Under.Pod" | Name="Pod"
[669] Part | "Workspace.Lobby.Under.Jet" | Name="Jet"
[670] PointLight | "Workspace.Lobby.Under.Jet.PointLight" | Name="PointLight"
[671] Part | "Workspace.Lobby.Under.Beam" | Name="Beam"
[672] Part | "Workspace.Lobby.Under.Beam" | Name="Beam"
[673] Part | "Workspace.Lobby.Under.Beam" | Name="Beam"
[674] Part | "Workspace.Lobby.Under.Beam" | Name="Beam"
[675] Part | "Workspace.Lobby.Under.Beam" | Name="Beam"
[676] Part | "Workspace.Lobby.Under.Beam" | Name="Beam"
[677] Part | "Workspace.Lobby.Under.Beam" | Name="Beam"
[678] Part | "Workspace.Lobby.Under.Pod" | Name="Pod"
[679] Part | "Workspace.Lobby.Under.Jet" | Name="Jet"
[680] PointLight | "Workspace.Lobby.Under.Jet.PointLight" | Name="PointLight"
[681] Part | "Workspace.Lobby.Under.Pod" | Name="Pod"
[682] Part | "Workspace.Lobby.Under.Jet" | Name="Jet"
[683] PointLight | "Workspace.Lobby.Under.Jet.PointLight" | Name="PointLight"
[684] Folder | "Workspace.Lobby.Stripes" | Name="Stripes"
[685] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[686] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[687] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[688] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[689] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[690] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[691] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[692] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[693] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[694] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[695] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[696] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[697] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[698] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[699] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[700] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[701] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[702] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[703] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[704] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[705] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[706] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[707] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[708] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[709] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[710] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[711] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[712] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[713] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[714] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[715] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[716] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[717] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[718] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[719] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[720] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[721] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[722] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[723] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[724] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[725] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[726] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[727] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[728] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[729] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[730] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[731] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[732] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[733] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[734] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[735] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[736] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[737] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[738] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[739] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[740] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[741] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[742] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[743] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[744] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[745] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[746] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[747] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[748] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[749] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[750] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[751] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[752] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[753] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[754] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[755] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[756] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[757] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[758] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[759] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[760] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[761] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[762] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[763] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[764] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[765] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[766] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[767] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[768] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[769] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[770] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[771] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[772] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[773] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[774] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[775] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[776] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[777] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[778] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[779] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[780] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[781] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[782] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[783] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[784] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[785] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[786] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[787] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[788] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[789] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[790] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[791] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[792] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[793] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[794] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[795] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[796] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[797] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[798] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[799] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[800] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[801] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[802] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[803] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[804] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[805] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[806] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[807] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[808] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[809] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[810] Part | "Workspace.Lobby.Stripes.Stripe" | Name="Stripe"
[811] Folder | "Workspace.Lobby.Pad" | Name="Pad"
[812] Part | "Workspace.Lobby.Pad.H" | Name="H"
[813] Part | "Workspace.Lobby.Pad.H" | Name="H"
[814] Part | "Workspace.Lobby.Pad.RingIn" | Name="RingIn"
[815] Part | "Workspace.Lobby.Pad.H" | Name="H"
[816] Part | "Workspace.Lobby.Pad.Ring" | Name="Ring"
[817] Folder | "Workspace.Lobby.Props" | Name="Props"
[818] Model | "Workspace.Lobby.Props.Container" | Name="Container"
[819] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[820] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[821] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[822] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[823] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[824] Part | "Workspace.Lobby.Props.Container.Body" | Name="Body"
[825] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[826] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[827] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[828] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[829] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[830] Model | "Workspace.Lobby.Props.Container" | Name="Container"
[831] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[832] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[833] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[834] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[835] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[836] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[837] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[838] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[839] Part | "Workspace.Lobby.Props.Container.Body" | Name="Body"
[840] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[841] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[842] Model | "Workspace.Lobby.Props.Container" | Name="Container"
[843] Part | "Workspace.Lobby.Props.Container.Body" | Name="Body"
[844] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[845] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[846] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[847] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[848] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[849] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[850] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[851] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[852] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[853] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[854] Model | "Workspace.Lobby.Props.Container" | Name="Container"
[855] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[856] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[857] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[858] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[859] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[860] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[861] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[862] Part | "Workspace.Lobby.Props.Container.Body" | Name="Body"
[863] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[864] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[865] Part | "Workspace.Lobby.Props.Container.Rib" | Name="Rib"
[866] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[867] Part | "Workspace.Lobby.Props.LightPole" | Name="LightPole"
[868] Part | "Workspace.Lobby.Props.Seat" | Name="Seat"
[869] Part | "Workspace.Lobby.Props.LightHead" | Name="LightHead"
[870] SpotLight | "Workspace.Lobby.Props.LightHead.SpotLight" | Name="SpotLight"
[871] Part | "Workspace.Lobby.Props.Seat" | Name="Seat"
[872] Part | "Workspace.Lobby.Props.LightPole" | Name="LightPole"
[873] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[874] Part | "Workspace.Lobby.Props.LightHead" | Name="LightHead"
[875] SpotLight | "Workspace.Lobby.Props.LightHead.SpotLight" | Name="SpotLight"
[876] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[877] Part | "Workspace.Lobby.Props.LightPole" | Name="LightPole"
[878] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[879] Part | "Workspace.Lobby.Props.LightHead" | Name="LightHead"
[880] SpotLight | "Workspace.Lobby.Props.LightHead.SpotLight" | Name="SpotLight"
[881] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[882] Part | "Workspace.Lobby.Props.LightPole" | Name="LightPole"
[883] Part | "Workspace.Lobby.Props.Seat" | Name="Seat"
[884] Part | "Workspace.Lobby.Props.LightHead" | Name="LightHead"
[885] SpotLight | "Workspace.Lobby.Props.LightHead.SpotLight" | Name="SpotLight"
[886] Part | "Workspace.Lobby.Props.Seat" | Name="Seat"
[887] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[888] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[889] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[890] Part | "Workspace.Lobby.Props.Crate" | Name="Crate"
[891] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[892] Part | "Workspace.Lobby.Props.Crate" | Name="Crate"
[893] Part | "Workspace.Lobby.Props.Seat" | Name="Seat"
[894] Part | "Workspace.Lobby.Props.Crate" | Name="Crate"
[895] Part | "Workspace.Lobby.Props.Seat" | Name="Seat"
[896] Part | "Workspace.Lobby.Props.SignPost" | Name="SignPost"
[897] Part | "Workspace.Lobby.Props.Crate" | Name="Crate"
[898] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[899] Part | "Workspace.Lobby.Props.SignPost" | Name="SignPost"
[900] Part | "Workspace.Lobby.Props.Crate" | Name="Crate"
[901] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[902] Part | "Workspace.Lobby.Props.Sign" | Name="Sign"
[903] SurfaceGui | "Workspace.Lobby.Props.Sign.SurfaceGui" | Name="SurfaceGui"
[904] TextLabel | "Workspace.Lobby.Props.Sign.SurfaceGui.TextLabel" | Name="TextLabel"
[905] UIPadding | "Workspace.Lobby.Props.Sign.SurfaceGui.TextLabel.UIPadding" | Name="UIPadding"
[906] Part | "Workspace.Lobby.Props.Crate" | Name="Crate"
[907] Part | "Workspace.Lobby.Props.Leg" | Name="Leg"
[908] SpawnLocation | "Workspace.Lobby.LobbySpawn" | Name="LobbySpawn"
[909] Terrain | "Workspace.Terrain" | Name="Terrain"
[910] Model | "Workspace.skchrs" | Name="skchrs"; attr:TPS_Weapon="AR15"
[911] Script | "Workspace.skchrs.Health" | Name="Health"
[912] LocalScript | "Workspace.skchrs.Animate" | Name="Animate"
[913] StringValue | "Workspace.skchrs.Animate.cheer" | Name="cheer"; Value=""
[914] Animation | "Workspace.skchrs.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[915] StringValue | "Workspace.skchrs.Animate.climb" | Name="climb"; Value=""
[916] Animation | "Workspace.skchrs.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[917] StringValue | "Workspace.skchrs.Animate.dance" | Name="dance"; Value=""
[918] Animation | "Workspace.skchrs.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[919] NumberValue | "Workspace.skchrs.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[920] Animation | "Workspace.skchrs.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[921] NumberValue | "Workspace.skchrs.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[922] Animation | "Workspace.skchrs.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[923] NumberValue | "Workspace.skchrs.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[924] StringValue | "Workspace.skchrs.Animate.dance2" | Name="dance2"; Value=""
[925] Animation | "Workspace.skchrs.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[926] NumberValue | "Workspace.skchrs.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[927] Animation | "Workspace.skchrs.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[928] NumberValue | "Workspace.skchrs.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[929] Animation | "Workspace.skchrs.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[930] NumberValue | "Workspace.skchrs.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[931] StringValue | "Workspace.skchrs.Animate.dance3" | Name="dance3"; Value=""
[932] Animation | "Workspace.skchrs.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[933] NumberValue | "Workspace.skchrs.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[934] Animation | "Workspace.skchrs.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[935] NumberValue | "Workspace.skchrs.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[936] Animation | "Workspace.skchrs.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[937] NumberValue | "Workspace.skchrs.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[938] StringValue | "Workspace.skchrs.Animate.fall" | Name="fall"; Value=""
[939] Animation | "Workspace.skchrs.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[940] StringValue | "Workspace.skchrs.Animate.idle" | Name="idle"; Value=""
[941] Animation | "Workspace.skchrs.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[942] NumberValue | "Workspace.skchrs.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[943] Animation | "Workspace.skchrs.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[944] NumberValue | "Workspace.skchrs.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[945] StringValue | "Workspace.skchrs.Animate.jump" | Name="jump"; Value=""
[946] Animation | "Workspace.skchrs.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[947] StringValue | "Workspace.skchrs.Animate.laugh" | Name="laugh"; Value=""
[948] Animation | "Workspace.skchrs.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[949] StringValue | "Workspace.skchrs.Animate.point" | Name="point"; Value=""
[950] Animation | "Workspace.skchrs.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[951] StringValue | "Workspace.skchrs.Animate.sit" | Name="sit"; Value=""
[952] Animation | "Workspace.skchrs.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[953] StringValue | "Workspace.skchrs.Animate.toollunge" | Name="toollunge"; Value=""
[954] Animation | "Workspace.skchrs.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[955] StringValue | "Workspace.skchrs.Animate.toolnone" | Name="toolnone"; Value=""
[956] Animation | "Workspace.skchrs.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[957] StringValue | "Workspace.skchrs.Animate.toolslash" | Name="toolslash"; Value=""
[958] Animation | "Workspace.skchrs.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[959] StringValue | "Workspace.skchrs.Animate.wave" | Name="wave"; Value=""
[960] Animation | "Workspace.skchrs.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[961] NumberValue | "Workspace.skchrs.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[962] StringValue | "Workspace.skchrs.Animate.run" | Name="run"; Value=""
[963] Animation | "Workspace.skchrs.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[964] StringValue | "Workspace.skchrs.Animate.swim" | Name="swim"; Value=""
[965] Animation | "Workspace.skchrs.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[966] StringValue | "Workspace.skchrs.Animate.swimidle" | Name="swimidle"; Value=""
[967] Animation | "Workspace.skchrs.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[968] StringValue | "Workspace.skchrs.Animate.walk" | Name="walk"; Value=""
[969] Animation | "Workspace.skchrs.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[970] BindableFunction | "Workspace.skchrs.Animate.PlayEmote" | Name="PlayEmote"
[971] StringValue | "Workspace.skchrs.Animate.mood" | Name="mood"; Value=""
[972] Animation | "Workspace.skchrs.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[973] Humanoid | "Workspace.skchrs.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[974] Status | "Workspace.skchrs.Humanoid.Status" | Name="Status"
[975] Animator | "Workspace.skchrs.Humanoid.Animator" | Name="Animator"
[976] AudioEmitter | "Workspace.skchrs.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[977] Wire | "Workspace.skchrs.AudioEmitter.Wire" | Name="Wire"
[978] Model | "Workspace.skchrs.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="PS2Mecha"; attr:TPS_WeaponId="AR15"
[979] Part | "Workspace.skchrs.TPS_HeldWeapon.Handle" | Name="Handle"
[980] Attachment | "Workspace.skchrs.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[981] Attachment | "Workspace.skchrs.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[982] Attachment | "Workspace.skchrs.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[983] Motor6D | "Workspace.skchrs.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[984] Part | "Workspace.skchrs.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"; attr:R1_SkinHidden=true
[985] SpecialMesh | "Workspace.skchrs.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[986] WeldConstraint | "Workspace.skchrs.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[987] Part | "Workspace.skchrs.TPS_HeldWeapon.Magazine" | Name="Magazine"
[988] Weld | "Workspace.skchrs.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[989] Attachment | "Workspace.skchrs.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[990] MeshPart | "Workspace.skchrs.TPS_HeldWeapon.R1_SkinBody" | Name="R1_SkinBody"
[991] WeldConstraint | "Workspace.skchrs.TPS_HeldWeapon.R1_SkinBody.WeldConstraint" | Name="WeldConstraint"
[992] Part | "Workspace.skchrs.HumanoidRootPart" | Name="HumanoidRootPart"
[993] Attachment | "Workspace.skchrs.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[994] Vector3Value | "Workspace.skchrs.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[995] Vector3Value | "Workspace.skchrs.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[996] Attachment | "Workspace.skchrs.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[997] Sound | "Workspace.skchrs.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[998] Sound | "Workspace.skchrs.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[999] Sound | "Workspace.skchrs.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[1000] Sound | "Workspace.skchrs.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[1001] Sound | "Workspace.skchrs.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[1002] Sound | "Workspace.skchrs.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[1003] Sound | "Workspace.skchrs.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[1004] Sound | "Workspace.skchrs.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[1005] Sound | "Workspace.skchrs.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[1006] MeshPart | "Workspace.skchrs.LeftHand" | Name="LeftHand"
[1007] WrapTarget | "Workspace.skchrs.LeftHand.LeftHand" | Name="LeftHand"
[1008] Attachment | "Workspace.skchrs.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[1009] Vector3Value | "Workspace.skchrs.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[1010] Attachment | "Workspace.skchrs.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[1011] Vector3Value | "Workspace.skchrs.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[1012] Vector3Value | "Workspace.skchrs.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[1013] AnimationConstraint | "Workspace.skchrs.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[1014] BallSocketConstraint | "Workspace.skchrs.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[1015] MeshPart | "Workspace.skchrs.RightHand" | Name="RightHand"
[1016] WrapTarget | "Workspace.skchrs.RightHand.RightHand" | Name="RightHand"
[1017] Attachment | "Workspace.skchrs.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[1018] Vector3Value | "Workspace.skchrs.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[1019] Attachment | "Workspace.skchrs.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[1020] Vector3Value | "Workspace.skchrs.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[1021] Vector3Value | "Workspace.skchrs.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[1022] AnimationConstraint | "Workspace.skchrs.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[1023] BallSocketConstraint | "Workspace.skchrs.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[1024] MeshPart | "Workspace.skchrs.LeftLowerArm" | Name="LeftLowerArm"
[1025] WrapTarget | "Workspace.skchrs.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[1026] Attachment | "Workspace.skchrs.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[1027] Vector3Value | "Workspace.skchrs.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[1028] Attachment | "Workspace.skchrs.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[1029] Vector3Value | "Workspace.skchrs.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[1030] Vector3Value | "Workspace.skchrs.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[1031] AnimationConstraint | "Workspace.skchrs.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[1032] BallSocketConstraint | "Workspace.skchrs.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[1033] MeshPart | "Workspace.skchrs.RightLowerArm" | Name="RightLowerArm"
[1034] WrapTarget | "Workspace.skchrs.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[1035] Attachment | "Workspace.skchrs.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[1036] Vector3Value | "Workspace.skchrs.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[1037] Attachment | "Workspace.skchrs.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[1038] Vector3Value | "Workspace.skchrs.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[1039] Vector3Value | "Workspace.skchrs.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[1040] AnimationConstraint | "Workspace.skchrs.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[1041] BallSocketConstraint | "Workspace.skchrs.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[1042] MeshPart | "Workspace.skchrs.LeftUpperArm" | Name="LeftUpperArm"
[1043] WrapTarget | "Workspace.skchrs.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[1044] Attachment | "Workspace.skchrs.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[1045] Vector3Value | "Workspace.skchrs.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[1046] Attachment | "Workspace.skchrs.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1047] Attachment | "Workspace.skchrs.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[1048] Vector3Value | "Workspace.skchrs.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[1049] Attachment | "Workspace.skchrs.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[1050] Vector3Value | "Workspace.skchrs.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[1051] Vector3Value | "Workspace.skchrs.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[1052] NoCollisionConstraint | "Workspace.skchrs.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[1053] AnimationConstraint | "Workspace.skchrs.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1054] BallSocketConstraint | "Workspace.skchrs.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[1055] MeshPart | "Workspace.skchrs.RightUpperArm" | Name="RightUpperArm"
[1056] WrapTarget | "Workspace.skchrs.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[1057] Attachment | "Workspace.skchrs.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[1058] Vector3Value | "Workspace.skchrs.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[1059] Attachment | "Workspace.skchrs.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1060] Attachment | "Workspace.skchrs.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[1061] Vector3Value | "Workspace.skchrs.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[1062] Attachment | "Workspace.skchrs.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[1063] Vector3Value | "Workspace.skchrs.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[1064] Vector3Value | "Workspace.skchrs.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[1065] NoCollisionConstraint | "Workspace.skchrs.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[1066] AnimationConstraint | "Workspace.skchrs.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1067] BallSocketConstraint | "Workspace.skchrs.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[1068] MeshPart | "Workspace.skchrs.LeftFoot" | Name="LeftFoot"
[1069] WrapTarget | "Workspace.skchrs.LeftFoot.LeftFoot" | Name="LeftFoot"
[1070] Attachment | "Workspace.skchrs.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[1071] Vector3Value | "Workspace.skchrs.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[1072] Attachment | "Workspace.skchrs.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[1073] Vector3Value | "Workspace.skchrs.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[1074] Vector3Value | "Workspace.skchrs.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[1075] AnimationConstraint | "Workspace.skchrs.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[1076] BallSocketConstraint | "Workspace.skchrs.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[1077] MeshPart | "Workspace.skchrs.LeftLowerLeg" | Name="LeftLowerLeg"
[1078] WrapTarget | "Workspace.skchrs.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[1079] Attachment | "Workspace.skchrs.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[1080] Vector3Value | "Workspace.skchrs.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[1081] Attachment | "Workspace.skchrs.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[1082] Vector3Value | "Workspace.skchrs.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[1083] Vector3Value | "Workspace.skchrs.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[1084] AnimationConstraint | "Workspace.skchrs.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[1085] BallSocketConstraint | "Workspace.skchrs.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[1086] MeshPart | "Workspace.skchrs.UpperTorso" | Name="UpperTorso"
[1087] WrapTarget | "Workspace.skchrs.UpperTorso.UpperTorso" | Name="UpperTorso"
[1088] Attachment | "Workspace.skchrs.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[1089] Vector3Value | "Workspace.skchrs.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[1090] Attachment | "Workspace.skchrs.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[1091] Vector3Value | "Workspace.skchrs.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[1092] Attachment | "Workspace.skchrs.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[1093] Vector3Value | "Workspace.skchrs.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[1094] Attachment | "Workspace.skchrs.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1095] Attachment | "Workspace.skchrs.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[1096] Vector3Value | "Workspace.skchrs.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[1097] Attachment | "Workspace.skchrs.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1098] Attachment | "Workspace.skchrs.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[1099] Vector3Value | "Workspace.skchrs.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[1100] Attachment | "Workspace.skchrs.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[1101] Vector3Value | "Workspace.skchrs.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[1102] Attachment | "Workspace.skchrs.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[1103] Vector3Value | "Workspace.skchrs.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[1104] Attachment | "Workspace.skchrs.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[1105] Vector3Value | "Workspace.skchrs.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[1106] Attachment | "Workspace.skchrs.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[1107] Vector3Value | "Workspace.skchrs.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[1108] Vector3Value | "Workspace.skchrs.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[1109] NoCollisionConstraint | "Workspace.skchrs.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[1110] NoCollisionConstraint | "Workspace.skchrs.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[1111] NoCollisionConstraint | "Workspace.skchrs.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[1112] NoCollisionConstraint | "Workspace.skchrs.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[1113] NoCollisionConstraint | "Workspace.skchrs.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[1114] NoCollisionConstraint | "Workspace.skchrs.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[1115] NoCollisionConstraint | "Workspace.skchrs.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[1116] AnimationConstraint | "Workspace.skchrs.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[1117] BallSocketConstraint | "Workspace.skchrs.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[1118] MeshPart | "Workspace.skchrs.LeftUpperLeg" | Name="LeftUpperLeg"
[1119] WrapTarget | "Workspace.skchrs.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[1120] Attachment | "Workspace.skchrs.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[1121] Vector3Value | "Workspace.skchrs.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[1122] Attachment | "Workspace.skchrs.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[1123] Vector3Value | "Workspace.skchrs.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[1124] Vector3Value | "Workspace.skchrs.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[1125] NoCollisionConstraint | "Workspace.skchrs.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[1126] NoCollisionConstraint | "Workspace.skchrs.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[1127] AnimationConstraint | "Workspace.skchrs.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[1128] BallSocketConstraint | "Workspace.skchrs.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[1129] MeshPart | "Workspace.skchrs.RightFoot" | Name="RightFoot"
[1130] AnimationConstraint | "Workspace.skchrs.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[1131] BallSocketConstraint | "Workspace.skchrs.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[1132] WrapTarget | "Workspace.skchrs.RightFoot.RightFoot" | Name="RightFoot"
[1133] Attachment | "Workspace.skchrs.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[1134] Vector3Value | "Workspace.skchrs.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[1135] Attachment | "Workspace.skchrs.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[1136] Vector3Value | "Workspace.skchrs.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[1137] Vector3Value | "Workspace.skchrs.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[1138] MeshPart | "Workspace.skchrs.RightLowerLeg" | Name="RightLowerLeg"
[1139] WrapTarget | "Workspace.skchrs.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[1140] Attachment | "Workspace.skchrs.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[1141] Vector3Value | "Workspace.skchrs.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[1142] Attachment | "Workspace.skchrs.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[1143] Vector3Value | "Workspace.skchrs.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[1144] Vector3Value | "Workspace.skchrs.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[1145] AnimationConstraint | "Workspace.skchrs.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[1146] BallSocketConstraint | "Workspace.skchrs.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[1147] MeshPart | "Workspace.skchrs.LowerTorso" | Name="LowerTorso"
[1148] WrapTarget | "Workspace.skchrs.LowerTorso.LowerTorso" | Name="LowerTorso"
[1149] Attachment | "Workspace.skchrs.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[1150] Vector3Value | "Workspace.skchrs.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[1151] Attachment | "Workspace.skchrs.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[1152] Vector3Value | "Workspace.skchrs.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[1153] Attachment | "Workspace.skchrs.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[1154] Vector3Value | "Workspace.skchrs.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[1155] Attachment | "Workspace.skchrs.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[1156] Vector3Value | "Workspace.skchrs.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[1157] Attachment | "Workspace.skchrs.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[1158] Vector3Value | "Workspace.skchrs.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[1159] Attachment | "Workspace.skchrs.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[1160] Vector3Value | "Workspace.skchrs.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[1161] Attachment | "Workspace.skchrs.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[1162] Vector3Value | "Workspace.skchrs.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[1163] Vector3Value | "Workspace.skchrs.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[1164] NoCollisionConstraint | "Workspace.skchrs.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[1165] NoCollisionConstraint | "Workspace.skchrs.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[1166] NoCollisionConstraint | "Workspace.skchrs.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[1167] NoCollisionConstraint | "Workspace.skchrs.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[1168] AnimationConstraint | "Workspace.skchrs.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[1169] MeshPart | "Workspace.skchrs.RightUpperLeg" | Name="RightUpperLeg"
[1170] WrapTarget | "Workspace.skchrs.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[1171] Attachment | "Workspace.skchrs.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[1172] Vector3Value | "Workspace.skchrs.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[1173] Attachment | "Workspace.skchrs.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[1174] Vector3Value | "Workspace.skchrs.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[1175] Vector3Value | "Workspace.skchrs.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[1176] NoCollisionConstraint | "Workspace.skchrs.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[1177] AnimationConstraint | "Workspace.skchrs.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[1178] BallSocketConstraint | "Workspace.skchrs.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[1179] MeshPart | "Workspace.skchrs.Head" | Name="Head"
[1180] Attachment | "Workspace.skchrs.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[1181] Vector3Value | "Workspace.skchrs.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[1182] Attachment | "Workspace.skchrs.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[1183] Vector3Value | "Workspace.skchrs.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[1184] Attachment | "Workspace.skchrs.Head.HairAttachment" | Name="HairAttachment"
[1185] Vector3Value | "Workspace.skchrs.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[1186] Attachment | "Workspace.skchrs.Head.HatAttachment" | Name="HatAttachment"
[1187] Vector3Value | "Workspace.skchrs.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[1188] Attachment | "Workspace.skchrs.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[1189] Vector3Value | "Workspace.skchrs.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[1190] Vector3Value | "Workspace.skchrs.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[1191] WrapTarget | "Workspace.skchrs.Head.Head" | Name="Head"
[1192] FaceControls | "Workspace.skchrs.Head.FaceControls" | Name="FaceControls"
[1193] NoCollisionConstraint | "Workspace.skchrs.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[1194] NoCollisionConstraint | "Workspace.skchrs.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[1195] NoCollisionConstraint | "Workspace.skchrs.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[1196] AnimationConstraint | "Workspace.skchrs.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1197] BallSocketConstraint | "Workspace.skchrs.Head.NeckBallSocket" | Name="NeckBallSocket"
[1198] Model | "Workspace.ThomasMelchior88" | Name="ThomasMelchior88"; attr:TPS_Weapon="AR15"
[1199] Part | "Workspace.ThomasMelchior88.HumanoidRootPart" | Name="HumanoidRootPart"
[1200] Attachment | "Workspace.ThomasMelchior88.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[1201] Vector3Value | "Workspace.ThomasMelchior88.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[1202] Vector3Value | "Workspace.ThomasMelchior88.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[1203] Attachment | "Workspace.ThomasMelchior88.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[1204] Sound | "Workspace.ThomasMelchior88.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[1205] Sound | "Workspace.ThomasMelchior88.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[1206] Sound | "Workspace.ThomasMelchior88.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[1207] Sound | "Workspace.ThomasMelchior88.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[1208] Sound | "Workspace.ThomasMelchior88.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[1209] Sound | "Workspace.ThomasMelchior88.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[1210] Sound | "Workspace.ThomasMelchior88.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[1211] Sound | "Workspace.ThomasMelchior88.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[1212] Sound | "Workspace.ThomasMelchior88.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[1213] MeshPart | "Workspace.ThomasMelchior88.LeftHand" | Name="LeftHand"
[1214] WrapTarget | "Workspace.ThomasMelchior88.LeftHand.LeftHand" | Name="LeftHand"
[1215] Attachment | "Workspace.ThomasMelchior88.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[1216] Vector3Value | "Workspace.ThomasMelchior88.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[1217] Attachment | "Workspace.ThomasMelchior88.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[1218] Vector3Value | "Workspace.ThomasMelchior88.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[1219] Vector3Value | "Workspace.ThomasMelchior88.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[1220] AnimationConstraint | "Workspace.ThomasMelchior88.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[1221] BallSocketConstraint | "Workspace.ThomasMelchior88.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[1222] MeshPart | "Workspace.ThomasMelchior88.RightHand" | Name="RightHand"
[1223] WrapTarget | "Workspace.ThomasMelchior88.RightHand.RightHand" | Name="RightHand"
[1224] Attachment | "Workspace.ThomasMelchior88.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[1225] Vector3Value | "Workspace.ThomasMelchior88.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[1226] Attachment | "Workspace.ThomasMelchior88.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[1227] Vector3Value | "Workspace.ThomasMelchior88.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[1228] Vector3Value | "Workspace.ThomasMelchior88.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[1229] AnimationConstraint | "Workspace.ThomasMelchior88.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[1230] BallSocketConstraint | "Workspace.ThomasMelchior88.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[1231] MeshPart | "Workspace.ThomasMelchior88.LeftLowerArm" | Name="LeftLowerArm"
[1232] WrapTarget | "Workspace.ThomasMelchior88.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[1233] Attachment | "Workspace.ThomasMelchior88.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[1234] Vector3Value | "Workspace.ThomasMelchior88.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[1235] Attachment | "Workspace.ThomasMelchior88.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[1236] Vector3Value | "Workspace.ThomasMelchior88.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[1237] Vector3Value | "Workspace.ThomasMelchior88.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[1238] AnimationConstraint | "Workspace.ThomasMelchior88.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[1239] BallSocketConstraint | "Workspace.ThomasMelchior88.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[1240] MeshPart | "Workspace.ThomasMelchior88.RightLowerArm" | Name="RightLowerArm"
[1241] WrapTarget | "Workspace.ThomasMelchior88.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[1242] Attachment | "Workspace.ThomasMelchior88.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[1243] Vector3Value | "Workspace.ThomasMelchior88.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[1244] Attachment | "Workspace.ThomasMelchior88.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[1245] Vector3Value | "Workspace.ThomasMelchior88.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[1246] Vector3Value | "Workspace.ThomasMelchior88.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[1247] AnimationConstraint | "Workspace.ThomasMelchior88.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[1248] BallSocketConstraint | "Workspace.ThomasMelchior88.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[1249] MeshPart | "Workspace.ThomasMelchior88.LeftUpperArm" | Name="LeftUpperArm"
[1250] WrapTarget | "Workspace.ThomasMelchior88.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[1251] Attachment | "Workspace.ThomasMelchior88.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[1252] Vector3Value | "Workspace.ThomasMelchior88.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[1253] Attachment | "Workspace.ThomasMelchior88.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1254] Attachment | "Workspace.ThomasMelchior88.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[1255] Vector3Value | "Workspace.ThomasMelchior88.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[1256] Attachment | "Workspace.ThomasMelchior88.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[1257] Vector3Value | "Workspace.ThomasMelchior88.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[1258] Vector3Value | "Workspace.ThomasMelchior88.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[1259] NoCollisionConstraint | "Workspace.ThomasMelchior88.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[1260] AnimationConstraint | "Workspace.ThomasMelchior88.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1261] BallSocketConstraint | "Workspace.ThomasMelchior88.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[1262] MeshPart | "Workspace.ThomasMelchior88.RightUpperArm" | Name="RightUpperArm"
[1263] WrapTarget | "Workspace.ThomasMelchior88.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[1264] Attachment | "Workspace.ThomasMelchior88.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[1265] Vector3Value | "Workspace.ThomasMelchior88.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[1266] Attachment | "Workspace.ThomasMelchior88.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1267] Attachment | "Workspace.ThomasMelchior88.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[1268] Vector3Value | "Workspace.ThomasMelchior88.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[1269] Attachment | "Workspace.ThomasMelchior88.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[1270] Vector3Value | "Workspace.ThomasMelchior88.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[1271] Vector3Value | "Workspace.ThomasMelchior88.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[1272] NoCollisionConstraint | "Workspace.ThomasMelchior88.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[1273] AnimationConstraint | "Workspace.ThomasMelchior88.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1274] BallSocketConstraint | "Workspace.ThomasMelchior88.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[1275] MeshPart | "Workspace.ThomasMelchior88.LeftFoot" | Name="LeftFoot"
[1276] WrapTarget | "Workspace.ThomasMelchior88.LeftFoot.LeftFoot" | Name="LeftFoot"
[1277] Attachment | "Workspace.ThomasMelchior88.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[1278] Vector3Value | "Workspace.ThomasMelchior88.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[1279] Attachment | "Workspace.ThomasMelchior88.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[1280] Vector3Value | "Workspace.ThomasMelchior88.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[1281] Vector3Value | "Workspace.ThomasMelchior88.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[1282] AnimationConstraint | "Workspace.ThomasMelchior88.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[1283] BallSocketConstraint | "Workspace.ThomasMelchior88.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[1284] MeshPart | "Workspace.ThomasMelchior88.LeftLowerLeg" | Name="LeftLowerLeg"
[1285] WrapTarget | "Workspace.ThomasMelchior88.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[1286] Attachment | "Workspace.ThomasMelchior88.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[1287] Vector3Value | "Workspace.ThomasMelchior88.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[1288] Attachment | "Workspace.ThomasMelchior88.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[1289] Vector3Value | "Workspace.ThomasMelchior88.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[1290] Vector3Value | "Workspace.ThomasMelchior88.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[1291] AnimationConstraint | "Workspace.ThomasMelchior88.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[1292] BallSocketConstraint | "Workspace.ThomasMelchior88.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[1293] MeshPart | "Workspace.ThomasMelchior88.UpperTorso" | Name="UpperTorso"
[1294] WrapTarget | "Workspace.ThomasMelchior88.UpperTorso.UpperTorso" | Name="UpperTorso"
[1295] Attachment | "Workspace.ThomasMelchior88.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[1296] Vector3Value | "Workspace.ThomasMelchior88.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[1297] Attachment | "Workspace.ThomasMelchior88.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[1298] Vector3Value | "Workspace.ThomasMelchior88.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[1299] Attachment | "Workspace.ThomasMelchior88.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[1300] Vector3Value | "Workspace.ThomasMelchior88.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[1301] Attachment | "Workspace.ThomasMelchior88.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1302] Attachment | "Workspace.ThomasMelchior88.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[1303] Vector3Value | "Workspace.ThomasMelchior88.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[1304] Attachment | "Workspace.ThomasMelchior88.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1305] Attachment | "Workspace.ThomasMelchior88.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[1306] Vector3Value | "Workspace.ThomasMelchior88.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[1307] Attachment | "Workspace.ThomasMelchior88.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[1308] Vector3Value | "Workspace.ThomasMelchior88.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[1309] Attachment | "Workspace.ThomasMelchior88.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[1310] Vector3Value | "Workspace.ThomasMelchior88.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[1311] Attachment | "Workspace.ThomasMelchior88.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[1312] Vector3Value | "Workspace.ThomasMelchior88.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[1313] Attachment | "Workspace.ThomasMelchior88.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[1314] Vector3Value | "Workspace.ThomasMelchior88.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[1315] Vector3Value | "Workspace.ThomasMelchior88.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[1316] NoCollisionConstraint | "Workspace.ThomasMelchior88.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[1317] NoCollisionConstraint | "Workspace.ThomasMelchior88.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[1318] NoCollisionConstraint | "Workspace.ThomasMelchior88.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[1319] NoCollisionConstraint | "Workspace.ThomasMelchior88.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[1320] NoCollisionConstraint | "Workspace.ThomasMelchior88.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[1321] NoCollisionConstraint | "Workspace.ThomasMelchior88.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[1322] NoCollisionConstraint | "Workspace.ThomasMelchior88.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[1323] AnimationConstraint | "Workspace.ThomasMelchior88.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[1324] BallSocketConstraint | "Workspace.ThomasMelchior88.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[1325] MeshPart | "Workspace.ThomasMelchior88.LeftUpperLeg" | Name="LeftUpperLeg"
[1326] WrapTarget | "Workspace.ThomasMelchior88.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[1327] Attachment | "Workspace.ThomasMelchior88.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[1328] Vector3Value | "Workspace.ThomasMelchior88.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[1329] Attachment | "Workspace.ThomasMelchior88.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[1330] Vector3Value | "Workspace.ThomasMelchior88.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[1331] Vector3Value | "Workspace.ThomasMelchior88.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[1332] NoCollisionConstraint | "Workspace.ThomasMelchior88.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[1333] NoCollisionConstraint | "Workspace.ThomasMelchior88.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[1334] AnimationConstraint | "Workspace.ThomasMelchior88.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[1335] BallSocketConstraint | "Workspace.ThomasMelchior88.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[1336] MeshPart | "Workspace.ThomasMelchior88.RightFoot" | Name="RightFoot"
[1337] WrapTarget | "Workspace.ThomasMelchior88.RightFoot.RightFoot" | Name="RightFoot"
[1338] Attachment | "Workspace.ThomasMelchior88.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[1339] Vector3Value | "Workspace.ThomasMelchior88.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[1340] Attachment | "Workspace.ThomasMelchior88.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[1341] Vector3Value | "Workspace.ThomasMelchior88.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[1342] Vector3Value | "Workspace.ThomasMelchior88.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[1343] AnimationConstraint | "Workspace.ThomasMelchior88.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[1344] BallSocketConstraint | "Workspace.ThomasMelchior88.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[1345] MeshPart | "Workspace.ThomasMelchior88.RightLowerLeg" | Name="RightLowerLeg"
[1346] WrapTarget | "Workspace.ThomasMelchior88.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[1347] Attachment | "Workspace.ThomasMelchior88.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[1348] Vector3Value | "Workspace.ThomasMelchior88.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[1349] Attachment | "Workspace.ThomasMelchior88.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[1350] Vector3Value | "Workspace.ThomasMelchior88.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[1351] Vector3Value | "Workspace.ThomasMelchior88.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[1352] AnimationConstraint | "Workspace.ThomasMelchior88.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[1353] BallSocketConstraint | "Workspace.ThomasMelchior88.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[1354] MeshPart | "Workspace.ThomasMelchior88.LowerTorso" | Name="LowerTorso"
[1355] WrapTarget | "Workspace.ThomasMelchior88.LowerTorso.LowerTorso" | Name="LowerTorso"
[1356] Attachment | "Workspace.ThomasMelchior88.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[1357] Vector3Value | "Workspace.ThomasMelchior88.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[1358] Attachment | "Workspace.ThomasMelchior88.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[1359] Vector3Value | "Workspace.ThomasMelchior88.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[1360] Attachment | "Workspace.ThomasMelchior88.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[1361] Vector3Value | "Workspace.ThomasMelchior88.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[1362] Attachment | "Workspace.ThomasMelchior88.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[1363] Vector3Value | "Workspace.ThomasMelchior88.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[1364] Attachment | "Workspace.ThomasMelchior88.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[1365] Vector3Value | "Workspace.ThomasMelchior88.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[1366] Attachment | "Workspace.ThomasMelchior88.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[1367] Vector3Value | "Workspace.ThomasMelchior88.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[1368] Attachment | "Workspace.ThomasMelchior88.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[1369] Vector3Value | "Workspace.ThomasMelchior88.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[1370] Vector3Value | "Workspace.ThomasMelchior88.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[1371] NoCollisionConstraint | "Workspace.ThomasMelchior88.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[1372] NoCollisionConstraint | "Workspace.ThomasMelchior88.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[1373] NoCollisionConstraint | "Workspace.ThomasMelchior88.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[1374] NoCollisionConstraint | "Workspace.ThomasMelchior88.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[1375] AnimationConstraint | "Workspace.ThomasMelchior88.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[1376] MeshPart | "Workspace.ThomasMelchior88.RightUpperLeg" | Name="RightUpperLeg"
[1377] WrapTarget | "Workspace.ThomasMelchior88.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[1378] Attachment | "Workspace.ThomasMelchior88.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[1379] Vector3Value | "Workspace.ThomasMelchior88.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[1380] Attachment | "Workspace.ThomasMelchior88.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[1381] Vector3Value | "Workspace.ThomasMelchior88.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[1382] Vector3Value | "Workspace.ThomasMelchior88.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[1383] NoCollisionConstraint | "Workspace.ThomasMelchior88.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[1384] AnimationConstraint | "Workspace.ThomasMelchior88.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[1385] BallSocketConstraint | "Workspace.ThomasMelchior88.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[1386] Humanoid | "Workspace.ThomasMelchior88.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[1387] Status | "Workspace.ThomasMelchior88.Humanoid.Status" | Name="Status"
[1388] Animator | "Workspace.ThomasMelchior88.Humanoid.Animator" | Name="Animator"
[1389] MeshPart | "Workspace.ThomasMelchior88.Head" | Name="Head"
[1390] Attachment | "Workspace.ThomasMelchior88.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[1391] Vector3Value | "Workspace.ThomasMelchior88.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[1392] Attachment | "Workspace.ThomasMelchior88.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[1393] Vector3Value | "Workspace.ThomasMelchior88.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[1394] Attachment | "Workspace.ThomasMelchior88.Head.HairAttachment" | Name="HairAttachment"
[1395] Vector3Value | "Workspace.ThomasMelchior88.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[1396] Attachment | "Workspace.ThomasMelchior88.Head.HatAttachment" | Name="HatAttachment"
[1397] Vector3Value | "Workspace.ThomasMelchior88.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[1398] Attachment | "Workspace.ThomasMelchior88.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[1399] Vector3Value | "Workspace.ThomasMelchior88.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[1400] Vector3Value | "Workspace.ThomasMelchior88.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[1401] WrapTarget | "Workspace.ThomasMelchior88.Head.Head" | Name="Head"
[1402] FaceControls | "Workspace.ThomasMelchior88.Head.FaceControls" | Name="FaceControls"
[1403] NoCollisionConstraint | "Workspace.ThomasMelchior88.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[1404] NoCollisionConstraint | "Workspace.ThomasMelchior88.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[1405] NoCollisionConstraint | "Workspace.ThomasMelchior88.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[1406] AnimationConstraint | "Workspace.ThomasMelchior88.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1407] BallSocketConstraint | "Workspace.ThomasMelchior88.Head.NeckBallSocket" | Name="NeckBallSocket"
[1408] Script | "Workspace.ThomasMelchior88.Health" | Name="Health"
[1409] LocalScript | "Workspace.ThomasMelchior88.Animate" | Name="Animate"
[1410] StringValue | "Workspace.ThomasMelchior88.Animate.cheer" | Name="cheer"; Value=""
[1411] Animation | "Workspace.ThomasMelchior88.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[1412] StringValue | "Workspace.ThomasMelchior88.Animate.climb" | Name="climb"; Value=""
[1413] Animation | "Workspace.ThomasMelchior88.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[1414] StringValue | "Workspace.ThomasMelchior88.Animate.dance" | Name="dance"; Value=""
[1415] Animation | "Workspace.ThomasMelchior88.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[1416] NumberValue | "Workspace.ThomasMelchior88.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[1417] Animation | "Workspace.ThomasMelchior88.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[1418] NumberValue | "Workspace.ThomasMelchior88.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[1419] Animation | "Workspace.ThomasMelchior88.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[1420] NumberValue | "Workspace.ThomasMelchior88.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[1421] StringValue | "Workspace.ThomasMelchior88.Animate.dance2" | Name="dance2"; Value=""
[1422] Animation | "Workspace.ThomasMelchior88.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[1423] NumberValue | "Workspace.ThomasMelchior88.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[1424] Animation | "Workspace.ThomasMelchior88.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[1425] NumberValue | "Workspace.ThomasMelchior88.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[1426] Animation | "Workspace.ThomasMelchior88.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[1427] NumberValue | "Workspace.ThomasMelchior88.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[1428] StringValue | "Workspace.ThomasMelchior88.Animate.dance3" | Name="dance3"; Value=""
[1429] Animation | "Workspace.ThomasMelchior88.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[1430] NumberValue | "Workspace.ThomasMelchior88.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[1431] Animation | "Workspace.ThomasMelchior88.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[1432] NumberValue | "Workspace.ThomasMelchior88.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[1433] Animation | "Workspace.ThomasMelchior88.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[1434] NumberValue | "Workspace.ThomasMelchior88.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[1435] StringValue | "Workspace.ThomasMelchior88.Animate.fall" | Name="fall"; Value=""
[1436] Animation | "Workspace.ThomasMelchior88.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[1437] StringValue | "Workspace.ThomasMelchior88.Animate.idle" | Name="idle"; Value=""
[1438] Animation | "Workspace.ThomasMelchior88.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[1439] NumberValue | "Workspace.ThomasMelchior88.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[1440] Animation | "Workspace.ThomasMelchior88.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[1441] NumberValue | "Workspace.ThomasMelchior88.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[1442] StringValue | "Workspace.ThomasMelchior88.Animate.jump" | Name="jump"; Value=""
[1443] Animation | "Workspace.ThomasMelchior88.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[1444] StringValue | "Workspace.ThomasMelchior88.Animate.laugh" | Name="laugh"; Value=""
[1445] Animation | "Workspace.ThomasMelchior88.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[1446] StringValue | "Workspace.ThomasMelchior88.Animate.point" | Name="point"; Value=""
[1447] Animation | "Workspace.ThomasMelchior88.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[1448] StringValue | "Workspace.ThomasMelchior88.Animate.sit" | Name="sit"; Value=""
[1449] Animation | "Workspace.ThomasMelchior88.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[1450] StringValue | "Workspace.ThomasMelchior88.Animate.toollunge" | Name="toollunge"; Value=""
[1451] Animation | "Workspace.ThomasMelchior88.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[1452] StringValue | "Workspace.ThomasMelchior88.Animate.toolnone" | Name="toolnone"; Value=""
[1453] Animation | "Workspace.ThomasMelchior88.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[1454] StringValue | "Workspace.ThomasMelchior88.Animate.toolslash" | Name="toolslash"; Value=""
[1455] Animation | "Workspace.ThomasMelchior88.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[1456] StringValue | "Workspace.ThomasMelchior88.Animate.wave" | Name="wave"; Value=""
[1457] Animation | "Workspace.ThomasMelchior88.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[1458] NumberValue | "Workspace.ThomasMelchior88.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[1459] StringValue | "Workspace.ThomasMelchior88.Animate.run" | Name="run"; Value=""
[1460] Animation | "Workspace.ThomasMelchior88.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[1461] StringValue | "Workspace.ThomasMelchior88.Animate.swim" | Name="swim"; Value=""
[1462] Animation | "Workspace.ThomasMelchior88.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[1463] StringValue | "Workspace.ThomasMelchior88.Animate.swimidle" | Name="swimidle"; Value=""
[1464] Animation | "Workspace.ThomasMelchior88.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[1465] StringValue | "Workspace.ThomasMelchior88.Animate.walk" | Name="walk"; Value=""
[1466] Animation | "Workspace.ThomasMelchior88.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[1467] BindableFunction | "Workspace.ThomasMelchior88.Animate.PlayEmote" | Name="PlayEmote"
[1468] StringValue | "Workspace.ThomasMelchior88.Animate.mood" | Name="mood"; Value=""
[1469] Animation | "Workspace.ThomasMelchior88.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[1470] AudioEmitter | "Workspace.ThomasMelchior88.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[1471] Wire | "Workspace.ThomasMelchior88.AudioEmitter.Wire" | Name="Wire"
[1472] Model | "Workspace.ThomasMelchior88.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Radioactive"; attr:TPS_WeaponId="AR15"
[1473] Part | "Workspace.ThomasMelchior88.TPS_HeldWeapon.Handle" | Name="Handle"
[1474] Attachment | "Workspace.ThomasMelchior88.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[1475] Attachment | "Workspace.ThomasMelchior88.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[1476] Attachment | "Workspace.ThomasMelchior88.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[1477] Motor6D | "Workspace.ThomasMelchior88.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[1478] Part | "Workspace.ThomasMelchior88.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"; attr:R1_SkinHidden=true
[1479] SpecialMesh | "Workspace.ThomasMelchior88.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[1480] WeldConstraint | "Workspace.ThomasMelchior88.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[1481] Part | "Workspace.ThomasMelchior88.TPS_HeldWeapon.Magazine" | Name="Magazine"
[1482] Weld | "Workspace.ThomasMelchior88.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[1483] Attachment | "Workspace.ThomasMelchior88.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[1484] MeshPart | "Workspace.ThomasMelchior88.TPS_HeldWeapon.R1_SkinBody" | Name="R1_SkinBody"
[1485] WeldConstraint | "Workspace.ThomasMelchior88.TPS_HeldWeapon.R1_SkinBody.WeldConstraint" | Name="WeldConstraint"
[1486] Model | "Workspace.ASWninjaz" | Name="ASWninjaz"; attr:TPS_Weapon="AR15"
[1487] Script | "Workspace.ASWninjaz.Health" | Name="Health"
[1488] LocalScript | "Workspace.ASWninjaz.Animate" | Name="Animate"
[1489] StringValue | "Workspace.ASWninjaz.Animate.cheer" | Name="cheer"; Value=""
[1490] Animation | "Workspace.ASWninjaz.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[1491] StringValue | "Workspace.ASWninjaz.Animate.climb" | Name="climb"; Value=""
[1492] Animation | "Workspace.ASWninjaz.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[1493] StringValue | "Workspace.ASWninjaz.Animate.dance" | Name="dance"; Value=""
[1494] Animation | "Workspace.ASWninjaz.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[1495] NumberValue | "Workspace.ASWninjaz.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[1496] Animation | "Workspace.ASWninjaz.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[1497] NumberValue | "Workspace.ASWninjaz.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[1498] Animation | "Workspace.ASWninjaz.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[1499] NumberValue | "Workspace.ASWninjaz.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[1500] StringValue | "Workspace.ASWninjaz.Animate.dance2" | Name="dance2"; Value=""
[1501] Animation | "Workspace.ASWninjaz.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[1502] NumberValue | "Workspace.ASWninjaz.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[1503] Animation | "Workspace.ASWninjaz.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[1504] NumberValue | "Workspace.ASWninjaz.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[1505] Animation | "Workspace.ASWninjaz.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[1506] NumberValue | "Workspace.ASWninjaz.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[1507] StringValue | "Workspace.ASWninjaz.Animate.dance3" | Name="dance3"; Value=""
[1508] Animation | "Workspace.ASWninjaz.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[1509] NumberValue | "Workspace.ASWninjaz.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[1510] Animation | "Workspace.ASWninjaz.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[1511] NumberValue | "Workspace.ASWninjaz.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[1512] Animation | "Workspace.ASWninjaz.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[1513] NumberValue | "Workspace.ASWninjaz.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[1514] StringValue | "Workspace.ASWninjaz.Animate.fall" | Name="fall"; Value=""
[1515] Animation | "Workspace.ASWninjaz.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[1516] StringValue | "Workspace.ASWninjaz.Animate.idle" | Name="idle"; Value=""
[1517] Animation | "Workspace.ASWninjaz.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[1518] NumberValue | "Workspace.ASWninjaz.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[1519] Animation | "Workspace.ASWninjaz.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[1520] NumberValue | "Workspace.ASWninjaz.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[1521] StringValue | "Workspace.ASWninjaz.Animate.jump" | Name="jump"; Value=""
[1522] Animation | "Workspace.ASWninjaz.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[1523] StringValue | "Workspace.ASWninjaz.Animate.laugh" | Name="laugh"; Value=""
[1524] Animation | "Workspace.ASWninjaz.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[1525] StringValue | "Workspace.ASWninjaz.Animate.point" | Name="point"; Value=""
[1526] Animation | "Workspace.ASWninjaz.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[1527] StringValue | "Workspace.ASWninjaz.Animate.sit" | Name="sit"; Value=""
[1528] Animation | "Workspace.ASWninjaz.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[1529] StringValue | "Workspace.ASWninjaz.Animate.toollunge" | Name="toollunge"; Value=""
[1530] Animation | "Workspace.ASWninjaz.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[1531] StringValue | "Workspace.ASWninjaz.Animate.toolnone" | Name="toolnone"; Value=""
[1532] Animation | "Workspace.ASWninjaz.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[1533] StringValue | "Workspace.ASWninjaz.Animate.toolslash" | Name="toolslash"; Value=""
[1534] Animation | "Workspace.ASWninjaz.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[1535] StringValue | "Workspace.ASWninjaz.Animate.wave" | Name="wave"; Value=""
[1536] Animation | "Workspace.ASWninjaz.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[1537] NumberValue | "Workspace.ASWninjaz.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[1538] StringValue | "Workspace.ASWninjaz.Animate.run" | Name="run"; Value=""
[1539] Animation | "Workspace.ASWninjaz.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[1540] StringValue | "Workspace.ASWninjaz.Animate.swim" | Name="swim"; Value=""
[1541] Animation | "Workspace.ASWninjaz.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[1542] StringValue | "Workspace.ASWninjaz.Animate.swimidle" | Name="swimidle"; Value=""
[1543] Animation | "Workspace.ASWninjaz.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[1544] StringValue | "Workspace.ASWninjaz.Animate.walk" | Name="walk"; Value=""
[1545] Animation | "Workspace.ASWninjaz.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[1546] BindableFunction | "Workspace.ASWninjaz.Animate.PlayEmote" | Name="PlayEmote"
[1547] StringValue | "Workspace.ASWninjaz.Animate.mood" | Name="mood"; Value=""
[1548] Animation | "Workspace.ASWninjaz.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[1549] Humanoid | "Workspace.ASWninjaz.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[1550] Status | "Workspace.ASWninjaz.Humanoid.Status" | Name="Status"
[1551] Animator | "Workspace.ASWninjaz.Humanoid.Animator" | Name="Animator"
[1552] AudioEmitter | "Workspace.ASWninjaz.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[1553] Wire | "Workspace.ASWninjaz.AudioEmitter.Wire" | Name="Wire"
[1554] Model | "Workspace.ASWninjaz.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Default"; attr:TPS_WeaponId="AR15"
[1555] Part | "Workspace.ASWninjaz.TPS_HeldWeapon.Handle" | Name="Handle"
[1556] Attachment | "Workspace.ASWninjaz.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[1557] Attachment | "Workspace.ASWninjaz.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[1558] Attachment | "Workspace.ASWninjaz.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[1559] Motor6D | "Workspace.ASWninjaz.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[1560] Part | "Workspace.ASWninjaz.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"
[1561] SpecialMesh | "Workspace.ASWninjaz.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[1562] WeldConstraint | "Workspace.ASWninjaz.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[1563] Part | "Workspace.ASWninjaz.TPS_HeldWeapon.Magazine" | Name="Magazine"
[1564] Weld | "Workspace.ASWninjaz.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[1565] Attachment | "Workspace.ASWninjaz.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[1566] Part | "Workspace.ASWninjaz.HumanoidRootPart" | Name="HumanoidRootPart"
[1567] Attachment | "Workspace.ASWninjaz.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[1568] Vector3Value | "Workspace.ASWninjaz.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[1569] Vector3Value | "Workspace.ASWninjaz.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[1570] Attachment | "Workspace.ASWninjaz.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[1571] Sound | "Workspace.ASWninjaz.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[1572] Sound | "Workspace.ASWninjaz.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[1573] Sound | "Workspace.ASWninjaz.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[1574] Sound | "Workspace.ASWninjaz.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[1575] Sound | "Workspace.ASWninjaz.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[1576] Sound | "Workspace.ASWninjaz.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[1577] Sound | "Workspace.ASWninjaz.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[1578] Sound | "Workspace.ASWninjaz.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[1579] Sound | "Workspace.ASWninjaz.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[1580] MeshPart | "Workspace.ASWninjaz.LeftHand" | Name="LeftHand"
[1581] WrapTarget | "Workspace.ASWninjaz.LeftHand.LeftHand" | Name="LeftHand"
[1582] Attachment | "Workspace.ASWninjaz.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[1583] Vector3Value | "Workspace.ASWninjaz.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[1584] Attachment | "Workspace.ASWninjaz.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[1585] Vector3Value | "Workspace.ASWninjaz.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[1586] Vector3Value | "Workspace.ASWninjaz.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[1587] AnimationConstraint | "Workspace.ASWninjaz.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[1588] BallSocketConstraint | "Workspace.ASWninjaz.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[1589] MeshPart | "Workspace.ASWninjaz.RightHand" | Name="RightHand"
[1590] WrapTarget | "Workspace.ASWninjaz.RightHand.RightHand" | Name="RightHand"
[1591] Attachment | "Workspace.ASWninjaz.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[1592] Vector3Value | "Workspace.ASWninjaz.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[1593] Attachment | "Workspace.ASWninjaz.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[1594] Vector3Value | "Workspace.ASWninjaz.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[1595] Vector3Value | "Workspace.ASWninjaz.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[1596] AnimationConstraint | "Workspace.ASWninjaz.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[1597] BallSocketConstraint | "Workspace.ASWninjaz.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[1598] MeshPart | "Workspace.ASWninjaz.LeftLowerArm" | Name="LeftLowerArm"
[1599] WrapTarget | "Workspace.ASWninjaz.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[1600] Attachment | "Workspace.ASWninjaz.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[1601] Vector3Value | "Workspace.ASWninjaz.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[1602] Attachment | "Workspace.ASWninjaz.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[1603] Vector3Value | "Workspace.ASWninjaz.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[1604] Vector3Value | "Workspace.ASWninjaz.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[1605] AnimationConstraint | "Workspace.ASWninjaz.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[1606] BallSocketConstraint | "Workspace.ASWninjaz.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[1607] MeshPart | "Workspace.ASWninjaz.RightLowerArm" | Name="RightLowerArm"
[1608] WrapTarget | "Workspace.ASWninjaz.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[1609] Attachment | "Workspace.ASWninjaz.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[1610] Vector3Value | "Workspace.ASWninjaz.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[1611] Attachment | "Workspace.ASWninjaz.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[1612] Vector3Value | "Workspace.ASWninjaz.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[1613] Vector3Value | "Workspace.ASWninjaz.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[1614] AnimationConstraint | "Workspace.ASWninjaz.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[1615] BallSocketConstraint | "Workspace.ASWninjaz.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[1616] MeshPart | "Workspace.ASWninjaz.LeftUpperArm" | Name="LeftUpperArm"
[1617] WrapTarget | "Workspace.ASWninjaz.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[1618] Attachment | "Workspace.ASWninjaz.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[1619] Vector3Value | "Workspace.ASWninjaz.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[1620] Attachment | "Workspace.ASWninjaz.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1621] Attachment | "Workspace.ASWninjaz.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[1622] Vector3Value | "Workspace.ASWninjaz.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[1623] Attachment | "Workspace.ASWninjaz.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[1624] Vector3Value | "Workspace.ASWninjaz.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[1625] Vector3Value | "Workspace.ASWninjaz.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[1626] NoCollisionConstraint | "Workspace.ASWninjaz.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[1627] AnimationConstraint | "Workspace.ASWninjaz.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1628] BallSocketConstraint | "Workspace.ASWninjaz.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[1629] MeshPart | "Workspace.ASWninjaz.RightUpperArm" | Name="RightUpperArm"
[1630] WrapTarget | "Workspace.ASWninjaz.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[1631] Attachment | "Workspace.ASWninjaz.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[1632] Vector3Value | "Workspace.ASWninjaz.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[1633] Attachment | "Workspace.ASWninjaz.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1634] Attachment | "Workspace.ASWninjaz.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[1635] Vector3Value | "Workspace.ASWninjaz.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[1636] Attachment | "Workspace.ASWninjaz.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[1637] Vector3Value | "Workspace.ASWninjaz.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[1638] Vector3Value | "Workspace.ASWninjaz.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[1639] NoCollisionConstraint | "Workspace.ASWninjaz.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[1640] AnimationConstraint | "Workspace.ASWninjaz.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1641] BallSocketConstraint | "Workspace.ASWninjaz.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[1642] MeshPart | "Workspace.ASWninjaz.LeftFoot" | Name="LeftFoot"
[1643] WrapTarget | "Workspace.ASWninjaz.LeftFoot.LeftFoot" | Name="LeftFoot"
[1644] Attachment | "Workspace.ASWninjaz.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[1645] Vector3Value | "Workspace.ASWninjaz.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[1646] Attachment | "Workspace.ASWninjaz.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[1647] Vector3Value | "Workspace.ASWninjaz.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[1648] Vector3Value | "Workspace.ASWninjaz.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[1649] AnimationConstraint | "Workspace.ASWninjaz.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[1650] BallSocketConstraint | "Workspace.ASWninjaz.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[1651] MeshPart | "Workspace.ASWninjaz.LeftLowerLeg" | Name="LeftLowerLeg"
[1652] WrapTarget | "Workspace.ASWninjaz.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[1653] Attachment | "Workspace.ASWninjaz.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[1654] Vector3Value | "Workspace.ASWninjaz.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[1655] Attachment | "Workspace.ASWninjaz.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[1656] Vector3Value | "Workspace.ASWninjaz.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[1657] Vector3Value | "Workspace.ASWninjaz.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[1658] AnimationConstraint | "Workspace.ASWninjaz.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[1659] BallSocketConstraint | "Workspace.ASWninjaz.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[1660] MeshPart | "Workspace.ASWninjaz.UpperTorso" | Name="UpperTorso"
[1661] WrapTarget | "Workspace.ASWninjaz.UpperTorso.UpperTorso" | Name="UpperTorso"
[1662] Attachment | "Workspace.ASWninjaz.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[1663] Vector3Value | "Workspace.ASWninjaz.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[1664] Attachment | "Workspace.ASWninjaz.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[1665] Vector3Value | "Workspace.ASWninjaz.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[1666] Attachment | "Workspace.ASWninjaz.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[1667] Vector3Value | "Workspace.ASWninjaz.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[1668] Attachment | "Workspace.ASWninjaz.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1669] Attachment | "Workspace.ASWninjaz.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[1670] Vector3Value | "Workspace.ASWninjaz.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[1671] Attachment | "Workspace.ASWninjaz.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1672] Attachment | "Workspace.ASWninjaz.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[1673] Vector3Value | "Workspace.ASWninjaz.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[1674] Attachment | "Workspace.ASWninjaz.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[1675] Vector3Value | "Workspace.ASWninjaz.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[1676] Attachment | "Workspace.ASWninjaz.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[1677] Vector3Value | "Workspace.ASWninjaz.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[1678] Attachment | "Workspace.ASWninjaz.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[1679] Vector3Value | "Workspace.ASWninjaz.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[1680] Attachment | "Workspace.ASWninjaz.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[1681] Vector3Value | "Workspace.ASWninjaz.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[1682] Vector3Value | "Workspace.ASWninjaz.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[1683] NoCollisionConstraint | "Workspace.ASWninjaz.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[1684] NoCollisionConstraint | "Workspace.ASWninjaz.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[1685] NoCollisionConstraint | "Workspace.ASWninjaz.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[1686] NoCollisionConstraint | "Workspace.ASWninjaz.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[1687] NoCollisionConstraint | "Workspace.ASWninjaz.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[1688] NoCollisionConstraint | "Workspace.ASWninjaz.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[1689] NoCollisionConstraint | "Workspace.ASWninjaz.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[1690] AnimationConstraint | "Workspace.ASWninjaz.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[1691] BallSocketConstraint | "Workspace.ASWninjaz.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[1692] MeshPart | "Workspace.ASWninjaz.LeftUpperLeg" | Name="LeftUpperLeg"
[1693] WrapTarget | "Workspace.ASWninjaz.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[1694] Attachment | "Workspace.ASWninjaz.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[1695] Vector3Value | "Workspace.ASWninjaz.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[1696] Attachment | "Workspace.ASWninjaz.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[1697] Vector3Value | "Workspace.ASWninjaz.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[1698] Vector3Value | "Workspace.ASWninjaz.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[1699] NoCollisionConstraint | "Workspace.ASWninjaz.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[1700] NoCollisionConstraint | "Workspace.ASWninjaz.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[1701] AnimationConstraint | "Workspace.ASWninjaz.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[1702] BallSocketConstraint | "Workspace.ASWninjaz.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[1703] MeshPart | "Workspace.ASWninjaz.RightFoot" | Name="RightFoot"
[1704] WrapTarget | "Workspace.ASWninjaz.RightFoot.RightFoot" | Name="RightFoot"
[1705] Attachment | "Workspace.ASWninjaz.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[1706] Vector3Value | "Workspace.ASWninjaz.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[1707] Attachment | "Workspace.ASWninjaz.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[1708] Vector3Value | "Workspace.ASWninjaz.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[1709] Vector3Value | "Workspace.ASWninjaz.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[1710] AnimationConstraint | "Workspace.ASWninjaz.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[1711] BallSocketConstraint | "Workspace.ASWninjaz.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[1712] MeshPart | "Workspace.ASWninjaz.RightLowerLeg" | Name="RightLowerLeg"
[1713] WrapTarget | "Workspace.ASWninjaz.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[1714] Attachment | "Workspace.ASWninjaz.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[1715] Vector3Value | "Workspace.ASWninjaz.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[1716] Attachment | "Workspace.ASWninjaz.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[1717] Vector3Value | "Workspace.ASWninjaz.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[1718] Vector3Value | "Workspace.ASWninjaz.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[1719] AnimationConstraint | "Workspace.ASWninjaz.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[1720] BallSocketConstraint | "Workspace.ASWninjaz.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[1721] MeshPart | "Workspace.ASWninjaz.LowerTorso" | Name="LowerTorso"
[1722] WrapTarget | "Workspace.ASWninjaz.LowerTorso.LowerTorso" | Name="LowerTorso"
[1723] Attachment | "Workspace.ASWninjaz.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[1724] Vector3Value | "Workspace.ASWninjaz.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[1725] Attachment | "Workspace.ASWninjaz.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[1726] Vector3Value | "Workspace.ASWninjaz.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[1727] Attachment | "Workspace.ASWninjaz.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[1728] Vector3Value | "Workspace.ASWninjaz.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[1729] Attachment | "Workspace.ASWninjaz.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[1730] Vector3Value | "Workspace.ASWninjaz.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[1731] Attachment | "Workspace.ASWninjaz.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[1732] Vector3Value | "Workspace.ASWninjaz.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[1733] Attachment | "Workspace.ASWninjaz.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[1734] Vector3Value | "Workspace.ASWninjaz.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[1735] Attachment | "Workspace.ASWninjaz.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[1736] Vector3Value | "Workspace.ASWninjaz.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[1737] Vector3Value | "Workspace.ASWninjaz.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[1738] NoCollisionConstraint | "Workspace.ASWninjaz.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[1739] NoCollisionConstraint | "Workspace.ASWninjaz.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[1740] NoCollisionConstraint | "Workspace.ASWninjaz.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[1741] NoCollisionConstraint | "Workspace.ASWninjaz.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[1742] AnimationConstraint | "Workspace.ASWninjaz.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[1743] MeshPart | "Workspace.ASWninjaz.RightUpperLeg" | Name="RightUpperLeg"
[1744] WrapTarget | "Workspace.ASWninjaz.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[1745] Attachment | "Workspace.ASWninjaz.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[1746] Vector3Value | "Workspace.ASWninjaz.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[1747] Attachment | "Workspace.ASWninjaz.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[1748] Vector3Value | "Workspace.ASWninjaz.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[1749] Vector3Value | "Workspace.ASWninjaz.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[1750] NoCollisionConstraint | "Workspace.ASWninjaz.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[1751] AnimationConstraint | "Workspace.ASWninjaz.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[1752] BallSocketConstraint | "Workspace.ASWninjaz.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[1753] MeshPart | "Workspace.ASWninjaz.Head" | Name="Head"
[1754] Attachment | "Workspace.ASWninjaz.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[1755] Vector3Value | "Workspace.ASWninjaz.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[1756] Attachment | "Workspace.ASWninjaz.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[1757] Vector3Value | "Workspace.ASWninjaz.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[1758] Attachment | "Workspace.ASWninjaz.Head.HairAttachment" | Name="HairAttachment"
[1759] Vector3Value | "Workspace.ASWninjaz.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[1760] Attachment | "Workspace.ASWninjaz.Head.HatAttachment" | Name="HatAttachment"
[1761] Vector3Value | "Workspace.ASWninjaz.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[1762] Attachment | "Workspace.ASWninjaz.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[1763] Vector3Value | "Workspace.ASWninjaz.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[1764] Vector3Value | "Workspace.ASWninjaz.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[1765] WrapTarget | "Workspace.ASWninjaz.Head.Head" | Name="Head"
[1766] FaceControls | "Workspace.ASWninjaz.Head.FaceControls" | Name="FaceControls"
[1767] NoCollisionConstraint | "Workspace.ASWninjaz.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[1768] NoCollisionConstraint | "Workspace.ASWninjaz.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[1769] NoCollisionConstraint | "Workspace.ASWninjaz.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[1770] AnimationConstraint | "Workspace.ASWninjaz.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1771] BallSocketConstraint | "Workspace.ASWninjaz.Head.NeckBallSocket" | Name="NeckBallSocket"
[1772] Model | "Workspace.Finir_Gamecor" | Name="Finir_Gamecor"; attr:TPS_Weapon="AR15"
[1773] Script | "Workspace.Finir_Gamecor.Health" | Name="Health"
[1774] LocalScript | "Workspace.Finir_Gamecor.Animate" | Name="Animate"
[1775] StringValue | "Workspace.Finir_Gamecor.Animate.cheer" | Name="cheer"; Value=""
[1776] Animation | "Workspace.Finir_Gamecor.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[1777] StringValue | "Workspace.Finir_Gamecor.Animate.climb" | Name="climb"; Value=""
[1778] Animation | "Workspace.Finir_Gamecor.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[1779] StringValue | "Workspace.Finir_Gamecor.Animate.dance" | Name="dance"; Value=""
[1780] Animation | "Workspace.Finir_Gamecor.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[1781] NumberValue | "Workspace.Finir_Gamecor.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[1782] Animation | "Workspace.Finir_Gamecor.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[1783] NumberValue | "Workspace.Finir_Gamecor.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[1784] Animation | "Workspace.Finir_Gamecor.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[1785] NumberValue | "Workspace.Finir_Gamecor.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[1786] StringValue | "Workspace.Finir_Gamecor.Animate.dance2" | Name="dance2"; Value=""
[1787] Animation | "Workspace.Finir_Gamecor.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[1788] NumberValue | "Workspace.Finir_Gamecor.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[1789] Animation | "Workspace.Finir_Gamecor.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[1790] NumberValue | "Workspace.Finir_Gamecor.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[1791] Animation | "Workspace.Finir_Gamecor.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[1792] NumberValue | "Workspace.Finir_Gamecor.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[1793] StringValue | "Workspace.Finir_Gamecor.Animate.dance3" | Name="dance3"; Value=""
[1794] Animation | "Workspace.Finir_Gamecor.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[1795] NumberValue | "Workspace.Finir_Gamecor.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[1796] Animation | "Workspace.Finir_Gamecor.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[1797] NumberValue | "Workspace.Finir_Gamecor.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[1798] Animation | "Workspace.Finir_Gamecor.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[1799] NumberValue | "Workspace.Finir_Gamecor.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[1800] StringValue | "Workspace.Finir_Gamecor.Animate.fall" | Name="fall"; Value=""
[1801] Animation | "Workspace.Finir_Gamecor.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[1802] StringValue | "Workspace.Finir_Gamecor.Animate.idle" | Name="idle"; Value=""
[1803] Animation | "Workspace.Finir_Gamecor.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[1804] NumberValue | "Workspace.Finir_Gamecor.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[1805] Animation | "Workspace.Finir_Gamecor.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[1806] NumberValue | "Workspace.Finir_Gamecor.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[1807] StringValue | "Workspace.Finir_Gamecor.Animate.jump" | Name="jump"; Value=""
[1808] Animation | "Workspace.Finir_Gamecor.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[1809] StringValue | "Workspace.Finir_Gamecor.Animate.laugh" | Name="laugh"; Value=""
[1810] Animation | "Workspace.Finir_Gamecor.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[1811] StringValue | "Workspace.Finir_Gamecor.Animate.point" | Name="point"; Value=""
[1812] Animation | "Workspace.Finir_Gamecor.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[1813] StringValue | "Workspace.Finir_Gamecor.Animate.sit" | Name="sit"; Value=""
[1814] Animation | "Workspace.Finir_Gamecor.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[1815] StringValue | "Workspace.Finir_Gamecor.Animate.toollunge" | Name="toollunge"; Value=""
[1816] Animation | "Workspace.Finir_Gamecor.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[1817] StringValue | "Workspace.Finir_Gamecor.Animate.toolnone" | Name="toolnone"; Value=""
[1818] Animation | "Workspace.Finir_Gamecor.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[1819] StringValue | "Workspace.Finir_Gamecor.Animate.toolslash" | Name="toolslash"; Value=""
[1820] Animation | "Workspace.Finir_Gamecor.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[1821] StringValue | "Workspace.Finir_Gamecor.Animate.wave" | Name="wave"; Value=""
[1822] Animation | "Workspace.Finir_Gamecor.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[1823] NumberValue | "Workspace.Finir_Gamecor.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[1824] StringValue | "Workspace.Finir_Gamecor.Animate.run" | Name="run"; Value=""
[1825] Animation | "Workspace.Finir_Gamecor.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[1826] StringValue | "Workspace.Finir_Gamecor.Animate.swim" | Name="swim"; Value=""
[1827] Animation | "Workspace.Finir_Gamecor.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[1828] StringValue | "Workspace.Finir_Gamecor.Animate.swimidle" | Name="swimidle"; Value=""
[1829] Animation | "Workspace.Finir_Gamecor.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[1830] StringValue | "Workspace.Finir_Gamecor.Animate.walk" | Name="walk"; Value=""
[1831] Animation | "Workspace.Finir_Gamecor.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[1832] BindableFunction | "Workspace.Finir_Gamecor.Animate.PlayEmote" | Name="PlayEmote"
[1833] StringValue | "Workspace.Finir_Gamecor.Animate.mood" | Name="mood"; Value=""
[1834] Animation | "Workspace.Finir_Gamecor.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[1835] Humanoid | "Workspace.Finir_Gamecor.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[1836] Status | "Workspace.Finir_Gamecor.Humanoid.Status" | Name="Status"
[1837] Animator | "Workspace.Finir_Gamecor.Humanoid.Animator" | Name="Animator"
[1838] AudioEmitter | "Workspace.Finir_Gamecor.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[1839] Wire | "Workspace.Finir_Gamecor.AudioEmitter.Wire" | Name="Wire"
[1840] Model | "Workspace.Finir_Gamecor.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Hazard"; attr:TPS_WeaponId="AR15"
[1841] Part | "Workspace.Finir_Gamecor.TPS_HeldWeapon.Handle" | Name="Handle"
[1842] Attachment | "Workspace.Finir_Gamecor.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[1843] Attachment | "Workspace.Finir_Gamecor.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[1844] Attachment | "Workspace.Finir_Gamecor.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[1845] Motor6D | "Workspace.Finir_Gamecor.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[1846] Part | "Workspace.Finir_Gamecor.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"; attr:R1_SkinHidden=true
[1847] SpecialMesh | "Workspace.Finir_Gamecor.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[1848] WeldConstraint | "Workspace.Finir_Gamecor.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[1849] Part | "Workspace.Finir_Gamecor.TPS_HeldWeapon.Magazine" | Name="Magazine"
[1850] Weld | "Workspace.Finir_Gamecor.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[1851] Attachment | "Workspace.Finir_Gamecor.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[1852] MeshPart | "Workspace.Finir_Gamecor.TPS_HeldWeapon.R1_SkinBody" | Name="R1_SkinBody"
[1853] WeldConstraint | "Workspace.Finir_Gamecor.TPS_HeldWeapon.R1_SkinBody.WeldConstraint" | Name="WeldConstraint"
[1854] Part | "Workspace.Finir_Gamecor.HumanoidRootPart" | Name="HumanoidRootPart"
[1855] Attachment | "Workspace.Finir_Gamecor.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[1856] Vector3Value | "Workspace.Finir_Gamecor.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[1857] Vector3Value | "Workspace.Finir_Gamecor.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[1858] Attachment | "Workspace.Finir_Gamecor.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[1859] Sound | "Workspace.Finir_Gamecor.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[1860] Sound | "Workspace.Finir_Gamecor.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[1861] Sound | "Workspace.Finir_Gamecor.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[1862] Sound | "Workspace.Finir_Gamecor.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[1863] Sound | "Workspace.Finir_Gamecor.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[1864] Sound | "Workspace.Finir_Gamecor.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[1865] Sound | "Workspace.Finir_Gamecor.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[1866] Sound | "Workspace.Finir_Gamecor.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[1867] Sound | "Workspace.Finir_Gamecor.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[1868] MeshPart | "Workspace.Finir_Gamecor.LeftHand" | Name="LeftHand"
[1869] WrapTarget | "Workspace.Finir_Gamecor.LeftHand.LeftHand" | Name="LeftHand"
[1870] Attachment | "Workspace.Finir_Gamecor.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[1871] Vector3Value | "Workspace.Finir_Gamecor.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[1872] Attachment | "Workspace.Finir_Gamecor.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[1873] Vector3Value | "Workspace.Finir_Gamecor.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[1874] Vector3Value | "Workspace.Finir_Gamecor.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[1875] AnimationConstraint | "Workspace.Finir_Gamecor.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[1876] BallSocketConstraint | "Workspace.Finir_Gamecor.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[1877] MeshPart | "Workspace.Finir_Gamecor.RightHand" | Name="RightHand"
[1878] WrapTarget | "Workspace.Finir_Gamecor.RightHand.RightHand" | Name="RightHand"
[1879] Attachment | "Workspace.Finir_Gamecor.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[1880] Vector3Value | "Workspace.Finir_Gamecor.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[1881] Attachment | "Workspace.Finir_Gamecor.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[1882] Vector3Value | "Workspace.Finir_Gamecor.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[1883] Vector3Value | "Workspace.Finir_Gamecor.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[1884] AnimationConstraint | "Workspace.Finir_Gamecor.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[1885] BallSocketConstraint | "Workspace.Finir_Gamecor.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[1886] MeshPart | "Workspace.Finir_Gamecor.LeftLowerArm" | Name="LeftLowerArm"
[1887] WrapTarget | "Workspace.Finir_Gamecor.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[1888] Attachment | "Workspace.Finir_Gamecor.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[1889] Vector3Value | "Workspace.Finir_Gamecor.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[1890] Attachment | "Workspace.Finir_Gamecor.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[1891] Vector3Value | "Workspace.Finir_Gamecor.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[1892] Vector3Value | "Workspace.Finir_Gamecor.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[1893] AnimationConstraint | "Workspace.Finir_Gamecor.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[1894] BallSocketConstraint | "Workspace.Finir_Gamecor.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[1895] MeshPart | "Workspace.Finir_Gamecor.RightLowerArm" | Name="RightLowerArm"
[1896] WrapTarget | "Workspace.Finir_Gamecor.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[1897] Attachment | "Workspace.Finir_Gamecor.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[1898] Vector3Value | "Workspace.Finir_Gamecor.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[1899] Attachment | "Workspace.Finir_Gamecor.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[1900] Vector3Value | "Workspace.Finir_Gamecor.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[1901] Vector3Value | "Workspace.Finir_Gamecor.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[1902] AnimationConstraint | "Workspace.Finir_Gamecor.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[1903] BallSocketConstraint | "Workspace.Finir_Gamecor.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[1904] MeshPart | "Workspace.Finir_Gamecor.LeftUpperArm" | Name="LeftUpperArm"
[1905] WrapTarget | "Workspace.Finir_Gamecor.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[1906] Attachment | "Workspace.Finir_Gamecor.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[1907] Vector3Value | "Workspace.Finir_Gamecor.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[1908] Attachment | "Workspace.Finir_Gamecor.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1909] Attachment | "Workspace.Finir_Gamecor.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[1910] Vector3Value | "Workspace.Finir_Gamecor.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[1911] Attachment | "Workspace.Finir_Gamecor.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[1912] Vector3Value | "Workspace.Finir_Gamecor.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[1913] Vector3Value | "Workspace.Finir_Gamecor.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[1914] NoCollisionConstraint | "Workspace.Finir_Gamecor.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[1915] AnimationConstraint | "Workspace.Finir_Gamecor.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1916] BallSocketConstraint | "Workspace.Finir_Gamecor.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[1917] MeshPart | "Workspace.Finir_Gamecor.RightUpperArm" | Name="RightUpperArm"
[1918] WrapTarget | "Workspace.Finir_Gamecor.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[1919] Attachment | "Workspace.Finir_Gamecor.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[1920] Vector3Value | "Workspace.Finir_Gamecor.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[1921] Attachment | "Workspace.Finir_Gamecor.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1922] Attachment | "Workspace.Finir_Gamecor.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[1923] Vector3Value | "Workspace.Finir_Gamecor.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[1924] Attachment | "Workspace.Finir_Gamecor.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[1925] Vector3Value | "Workspace.Finir_Gamecor.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[1926] Vector3Value | "Workspace.Finir_Gamecor.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[1927] NoCollisionConstraint | "Workspace.Finir_Gamecor.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[1928] AnimationConstraint | "Workspace.Finir_Gamecor.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[1929] BallSocketConstraint | "Workspace.Finir_Gamecor.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[1930] MeshPart | "Workspace.Finir_Gamecor.LeftFoot" | Name="LeftFoot"
[1931] Vector3Value | "Workspace.Finir_Gamecor.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[1932] AnimationConstraint | "Workspace.Finir_Gamecor.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[1933] BallSocketConstraint | "Workspace.Finir_Gamecor.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[1934] WrapTarget | "Workspace.Finir_Gamecor.LeftFoot.LeftFoot" | Name="LeftFoot"
[1935] Attachment | "Workspace.Finir_Gamecor.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[1936] Vector3Value | "Workspace.Finir_Gamecor.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[1937] Attachment | "Workspace.Finir_Gamecor.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[1938] Vector3Value | "Workspace.Finir_Gamecor.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[1939] MeshPart | "Workspace.Finir_Gamecor.LeftLowerLeg" | Name="LeftLowerLeg"
[1940] WrapTarget | "Workspace.Finir_Gamecor.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[1941] Attachment | "Workspace.Finir_Gamecor.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[1942] Vector3Value | "Workspace.Finir_Gamecor.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[1943] Attachment | "Workspace.Finir_Gamecor.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[1944] Vector3Value | "Workspace.Finir_Gamecor.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[1945] Vector3Value | "Workspace.Finir_Gamecor.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[1946] AnimationConstraint | "Workspace.Finir_Gamecor.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[1947] BallSocketConstraint | "Workspace.Finir_Gamecor.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[1948] MeshPart | "Workspace.Finir_Gamecor.UpperTorso" | Name="UpperTorso"
[1949] WrapTarget | "Workspace.Finir_Gamecor.UpperTorso.UpperTorso" | Name="UpperTorso"
[1950] Attachment | "Workspace.Finir_Gamecor.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[1951] Vector3Value | "Workspace.Finir_Gamecor.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[1952] Attachment | "Workspace.Finir_Gamecor.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[1953] Vector3Value | "Workspace.Finir_Gamecor.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[1954] Attachment | "Workspace.Finir_Gamecor.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[1955] Vector3Value | "Workspace.Finir_Gamecor.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[1956] Attachment | "Workspace.Finir_Gamecor.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1957] Attachment | "Workspace.Finir_Gamecor.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[1958] Vector3Value | "Workspace.Finir_Gamecor.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[1959] Attachment | "Workspace.Finir_Gamecor.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[1960] Vector3Value | "Workspace.Finir_Gamecor.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[1961] Attachment | "Workspace.Finir_Gamecor.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[1962] Vector3Value | "Workspace.Finir_Gamecor.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[1963] Attachment | "Workspace.Finir_Gamecor.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[1964] Vector3Value | "Workspace.Finir_Gamecor.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[1965] Vector3Value | "Workspace.Finir_Gamecor.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[1966] NoCollisionConstraint | "Workspace.Finir_Gamecor.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[1967] NoCollisionConstraint | "Workspace.Finir_Gamecor.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[1968] NoCollisionConstraint | "Workspace.Finir_Gamecor.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[1969] NoCollisionConstraint | "Workspace.Finir_Gamecor.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[1970] NoCollisionConstraint | "Workspace.Finir_Gamecor.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[1971] NoCollisionConstraint | "Workspace.Finir_Gamecor.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[1972] NoCollisionConstraint | "Workspace.Finir_Gamecor.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[1973] AnimationConstraint | "Workspace.Finir_Gamecor.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[1974] BallSocketConstraint | "Workspace.Finir_Gamecor.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[1975] Attachment | "Workspace.Finir_Gamecor.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[1976] Vector3Value | "Workspace.Finir_Gamecor.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[1977] Attachment | "Workspace.Finir_Gamecor.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[1978] Attachment | "Workspace.Finir_Gamecor.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[1979] Vector3Value | "Workspace.Finir_Gamecor.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[1980] MeshPart | "Workspace.Finir_Gamecor.LeftUpperLeg" | Name="LeftUpperLeg"
[1981] Attachment | "Workspace.Finir_Gamecor.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[1982] Vector3Value | "Workspace.Finir_Gamecor.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[1983] Vector3Value | "Workspace.Finir_Gamecor.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[1984] NoCollisionConstraint | "Workspace.Finir_Gamecor.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[1985] NoCollisionConstraint | "Workspace.Finir_Gamecor.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[1986] AnimationConstraint | "Workspace.Finir_Gamecor.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[1987] BallSocketConstraint | "Workspace.Finir_Gamecor.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[1988] WrapTarget | "Workspace.Finir_Gamecor.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[1989] Attachment | "Workspace.Finir_Gamecor.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[1990] Vector3Value | "Workspace.Finir_Gamecor.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[1991] MeshPart | "Workspace.Finir_Gamecor.RightFoot" | Name="RightFoot"
[1992] WrapTarget | "Workspace.Finir_Gamecor.RightFoot.RightFoot" | Name="RightFoot"
[1993] Attachment | "Workspace.Finir_Gamecor.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[1994] Vector3Value | "Workspace.Finir_Gamecor.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[1995] Attachment | "Workspace.Finir_Gamecor.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[1996] Vector3Value | "Workspace.Finir_Gamecor.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[1997] Vector3Value | "Workspace.Finir_Gamecor.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[1998] AnimationConstraint | "Workspace.Finir_Gamecor.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[1999] BallSocketConstraint | "Workspace.Finir_Gamecor.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[2000] MeshPart | "Workspace.Finir_Gamecor.RightLowerLeg" | Name="RightLowerLeg"
[2001] WrapTarget | "Workspace.Finir_Gamecor.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[2002] Attachment | "Workspace.Finir_Gamecor.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[2003] Vector3Value | "Workspace.Finir_Gamecor.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[2004] Attachment | "Workspace.Finir_Gamecor.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[2005] Vector3Value | "Workspace.Finir_Gamecor.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[2006] Vector3Value | "Workspace.Finir_Gamecor.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[2007] AnimationConstraint | "Workspace.Finir_Gamecor.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[2008] BallSocketConstraint | "Workspace.Finir_Gamecor.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[2009] MeshPart | "Workspace.Finir_Gamecor.LowerTorso" | Name="LowerTorso"
[2010] Attachment | "Workspace.Finir_Gamecor.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[2011] Vector3Value | "Workspace.Finir_Gamecor.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[2012] Vector3Value | "Workspace.Finir_Gamecor.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[2013] NoCollisionConstraint | "Workspace.Finir_Gamecor.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[2014] NoCollisionConstraint | "Workspace.Finir_Gamecor.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[2015] NoCollisionConstraint | "Workspace.Finir_Gamecor.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[2016] NoCollisionConstraint | "Workspace.Finir_Gamecor.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[2017] AnimationConstraint | "Workspace.Finir_Gamecor.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[2018] Attachment | "Workspace.Finir_Gamecor.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[2019] Vector3Value | "Workspace.Finir_Gamecor.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[2020] WrapTarget | "Workspace.Finir_Gamecor.LowerTorso.LowerTorso" | Name="LowerTorso"
[2021] Attachment | "Workspace.Finir_Gamecor.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[2022] Vector3Value | "Workspace.Finir_Gamecor.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[2023] Attachment | "Workspace.Finir_Gamecor.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[2024] Vector3Value | "Workspace.Finir_Gamecor.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[2025] Attachment | "Workspace.Finir_Gamecor.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[2026] Vector3Value | "Workspace.Finir_Gamecor.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[2027] Attachment | "Workspace.Finir_Gamecor.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[2028] Vector3Value | "Workspace.Finir_Gamecor.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[2029] Attachment | "Workspace.Finir_Gamecor.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[2030] Vector3Value | "Workspace.Finir_Gamecor.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[2031] MeshPart | "Workspace.Finir_Gamecor.RightUpperLeg" | Name="RightUpperLeg"
[2032] WrapTarget | "Workspace.Finir_Gamecor.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[2033] Attachment | "Workspace.Finir_Gamecor.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[2034] Vector3Value | "Workspace.Finir_Gamecor.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[2035] Attachment | "Workspace.Finir_Gamecor.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[2036] Vector3Value | "Workspace.Finir_Gamecor.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[2037] Vector3Value | "Workspace.Finir_Gamecor.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[2038] NoCollisionConstraint | "Workspace.Finir_Gamecor.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[2039] AnimationConstraint | "Workspace.Finir_Gamecor.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[2040] BallSocketConstraint | "Workspace.Finir_Gamecor.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[2041] MeshPart | "Workspace.Finir_Gamecor.Head" | Name="Head"
[2042] Attachment | "Workspace.Finir_Gamecor.Head.HatAttachment" | Name="HatAttachment"
[2043] Vector3Value | "Workspace.Finir_Gamecor.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[2044] Attachment | "Workspace.Finir_Gamecor.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[2045] Vector3Value | "Workspace.Finir_Gamecor.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[2046] Vector3Value | "Workspace.Finir_Gamecor.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[2047] WrapTarget | "Workspace.Finir_Gamecor.Head.Head" | Name="Head"
[2048] FaceControls | "Workspace.Finir_Gamecor.Head.FaceControls" | Name="FaceControls"
[2049] NoCollisionConstraint | "Workspace.Finir_Gamecor.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[2050] NoCollisionConstraint | "Workspace.Finir_Gamecor.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[2051] NoCollisionConstraint | "Workspace.Finir_Gamecor.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[2052] AnimationConstraint | "Workspace.Finir_Gamecor.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[2053] BallSocketConstraint | "Workspace.Finir_Gamecor.Head.NeckBallSocket" | Name="NeckBallSocket"
[2054] Attachment | "Workspace.Finir_Gamecor.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[2055] Vector3Value | "Workspace.Finir_Gamecor.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[2056] Attachment | "Workspace.Finir_Gamecor.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[2057] Vector3Value | "Workspace.Finir_Gamecor.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[2058] Attachment | "Workspace.Finir_Gamecor.Head.HairAttachment" | Name="HairAttachment"
[2059] Vector3Value | "Workspace.Finir_Gamecor.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[2060] Model | "Workspace.n0ttusg" | Name="n0ttusg"; attr:TPS_Weapon="AR15"
[2061] Script | "Workspace.n0ttusg.Health" | Name="Health"
[2062] LocalScript | "Workspace.n0ttusg.Animate" | Name="Animate"
[2063] StringValue | "Workspace.n0ttusg.Animate.cheer" | Name="cheer"; Value=""
[2064] Animation | "Workspace.n0ttusg.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[2065] StringValue | "Workspace.n0ttusg.Animate.climb" | Name="climb"; Value=""
[2066] Animation | "Workspace.n0ttusg.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[2067] StringValue | "Workspace.n0ttusg.Animate.dance" | Name="dance"; Value=""
[2068] Animation | "Workspace.n0ttusg.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[2069] NumberValue | "Workspace.n0ttusg.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[2070] Animation | "Workspace.n0ttusg.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[2071] NumberValue | "Workspace.n0ttusg.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[2072] Animation | "Workspace.n0ttusg.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[2073] NumberValue | "Workspace.n0ttusg.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[2074] StringValue | "Workspace.n0ttusg.Animate.dance2" | Name="dance2"; Value=""
[2075] Animation | "Workspace.n0ttusg.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[2076] NumberValue | "Workspace.n0ttusg.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[2077] Animation | "Workspace.n0ttusg.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[2078] NumberValue | "Workspace.n0ttusg.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[2079] Animation | "Workspace.n0ttusg.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[2080] NumberValue | "Workspace.n0ttusg.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[2081] StringValue | "Workspace.n0ttusg.Animate.dance3" | Name="dance3"; Value=""
[2082] Animation | "Workspace.n0ttusg.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[2083] NumberValue | "Workspace.n0ttusg.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[2084] Animation | "Workspace.n0ttusg.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[2085] NumberValue | "Workspace.n0ttusg.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[2086] Animation | "Workspace.n0ttusg.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[2087] NumberValue | "Workspace.n0ttusg.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[2088] StringValue | "Workspace.n0ttusg.Animate.fall" | Name="fall"; Value=""
[2089] Animation | "Workspace.n0ttusg.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[2090] StringValue | "Workspace.n0ttusg.Animate.idle" | Name="idle"; Value=""
[2091] Animation | "Workspace.n0ttusg.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[2092] NumberValue | "Workspace.n0ttusg.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[2093] Animation | "Workspace.n0ttusg.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[2094] NumberValue | "Workspace.n0ttusg.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[2095] StringValue | "Workspace.n0ttusg.Animate.jump" | Name="jump"; Value=""
[2096] Animation | "Workspace.n0ttusg.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[2097] StringValue | "Workspace.n0ttusg.Animate.laugh" | Name="laugh"; Value=""
[2098] Animation | "Workspace.n0ttusg.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[2099] StringValue | "Workspace.n0ttusg.Animate.point" | Name="point"; Value=""
[2100] Animation | "Workspace.n0ttusg.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[2101] StringValue | "Workspace.n0ttusg.Animate.sit" | Name="sit"; Value=""
[2102] Animation | "Workspace.n0ttusg.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[2103] StringValue | "Workspace.n0ttusg.Animate.toollunge" | Name="toollunge"; Value=""
[2104] Animation | "Workspace.n0ttusg.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[2105] StringValue | "Workspace.n0ttusg.Animate.toolnone" | Name="toolnone"; Value=""
[2106] Animation | "Workspace.n0ttusg.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[2107] StringValue | "Workspace.n0ttusg.Animate.toolslash" | Name="toolslash"; Value=""
[2108] Animation | "Workspace.n0ttusg.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[2109] StringValue | "Workspace.n0ttusg.Animate.wave" | Name="wave"; Value=""
[2110] Animation | "Workspace.n0ttusg.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[2111] NumberValue | "Workspace.n0ttusg.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[2112] StringValue | "Workspace.n0ttusg.Animate.run" | Name="run"; Value=""
[2113] Animation | "Workspace.n0ttusg.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[2114] StringValue | "Workspace.n0ttusg.Animate.swim" | Name="swim"; Value=""
[2115] Animation | "Workspace.n0ttusg.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[2116] StringValue | "Workspace.n0ttusg.Animate.swimidle" | Name="swimidle"; Value=""
[2117] Animation | "Workspace.n0ttusg.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[2118] StringValue | "Workspace.n0ttusg.Animate.walk" | Name="walk"; Value=""
[2119] Animation | "Workspace.n0ttusg.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[2120] BindableFunction | "Workspace.n0ttusg.Animate.PlayEmote" | Name="PlayEmote"
[2121] StringValue | "Workspace.n0ttusg.Animate.mood" | Name="mood"; Value=""
[2122] Animation | "Workspace.n0ttusg.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[2123] Model | "Workspace.n0ttusg.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="ChallengeShatter"; attr:TPS_WeaponId="AR15"
[2124] Part | "Workspace.n0ttusg.TPS_HeldWeapon.Handle" | Name="Handle"
[2125] Attachment | "Workspace.n0ttusg.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[2126] Attachment | "Workspace.n0ttusg.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[2127] Attachment | "Workspace.n0ttusg.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[2128] Motor6D | "Workspace.n0ttusg.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[2129] Part | "Workspace.n0ttusg.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"; attr:R1_SkinHidden=true
[2130] SpecialMesh | "Workspace.n0ttusg.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[2131] WeldConstraint | "Workspace.n0ttusg.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[2132] Part | "Workspace.n0ttusg.TPS_HeldWeapon.Magazine" | Name="Magazine"
[2133] Weld | "Workspace.n0ttusg.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[2134] Attachment | "Workspace.n0ttusg.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[2135] MeshPart | "Workspace.n0ttusg.TPS_HeldWeapon.R1_SkinBody" | Name="R1_SkinBody"
[2136] WeldConstraint | "Workspace.n0ttusg.TPS_HeldWeapon.R1_SkinBody.WeldConstraint" | Name="WeldConstraint"
[2137] SurfaceAppearance | "Workspace.n0ttusg.TPS_HeldWeapon.R1_SkinBody.AR15_Shatter" | Name="AR15_Shatter"
[2138] Humanoid | "Workspace.n0ttusg.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[2139] Status | "Workspace.n0ttusg.Humanoid.Status" | Name="Status"
[2140] Animator | "Workspace.n0ttusg.Humanoid.Animator" | Name="Animator"
[2141] AudioEmitter | "Workspace.n0ttusg.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[2142] Wire | "Workspace.n0ttusg.AudioEmitter.Wire" | Name="Wire"
[2143] Part | "Workspace.n0ttusg.HumanoidRootPart" | Name="HumanoidRootPart"
[2144] Attachment | "Workspace.n0ttusg.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[2145] Vector3Value | "Workspace.n0ttusg.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[2146] Vector3Value | "Workspace.n0ttusg.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[2147] Attachment | "Workspace.n0ttusg.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[2148] Sound | "Workspace.n0ttusg.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[2149] Sound | "Workspace.n0ttusg.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[2150] Sound | "Workspace.n0ttusg.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[2151] Sound | "Workspace.n0ttusg.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[2152] Sound | "Workspace.n0ttusg.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[2153] Sound | "Workspace.n0ttusg.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[2154] Sound | "Workspace.n0ttusg.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[2155] Sound | "Workspace.n0ttusg.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[2156] Sound | "Workspace.n0ttusg.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[2157] MeshPart | "Workspace.n0ttusg.LeftHand" | Name="LeftHand"
[2158] WrapTarget | "Workspace.n0ttusg.LeftHand.LeftHand" | Name="LeftHand"
[2159] Attachment | "Workspace.n0ttusg.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[2160] Vector3Value | "Workspace.n0ttusg.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[2161] Attachment | "Workspace.n0ttusg.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[2162] Vector3Value | "Workspace.n0ttusg.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[2163] Vector3Value | "Workspace.n0ttusg.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[2164] AnimationConstraint | "Workspace.n0ttusg.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[2165] BallSocketConstraint | "Workspace.n0ttusg.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[2166] MeshPart | "Workspace.n0ttusg.RightHand" | Name="RightHand"
[2167] WrapTarget | "Workspace.n0ttusg.RightHand.RightHand" | Name="RightHand"
[2168] Attachment | "Workspace.n0ttusg.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[2169] Vector3Value | "Workspace.n0ttusg.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[2170] Attachment | "Workspace.n0ttusg.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[2171] Vector3Value | "Workspace.n0ttusg.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[2172] Vector3Value | "Workspace.n0ttusg.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[2173] AnimationConstraint | "Workspace.n0ttusg.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[2174] BallSocketConstraint | "Workspace.n0ttusg.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[2175] MeshPart | "Workspace.n0ttusg.LeftLowerArm" | Name="LeftLowerArm"
[2176] WrapTarget | "Workspace.n0ttusg.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[2177] Attachment | "Workspace.n0ttusg.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[2178] Vector3Value | "Workspace.n0ttusg.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[2179] Attachment | "Workspace.n0ttusg.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[2180] Vector3Value | "Workspace.n0ttusg.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[2181] Vector3Value | "Workspace.n0ttusg.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[2182] AnimationConstraint | "Workspace.n0ttusg.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[2183] BallSocketConstraint | "Workspace.n0ttusg.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[2184] MeshPart | "Workspace.n0ttusg.RightLowerArm" | Name="RightLowerArm"
[2185] WrapTarget | "Workspace.n0ttusg.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[2186] Attachment | "Workspace.n0ttusg.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[2187] Vector3Value | "Workspace.n0ttusg.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[2188] Attachment | "Workspace.n0ttusg.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[2189] Vector3Value | "Workspace.n0ttusg.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[2190] Vector3Value | "Workspace.n0ttusg.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[2191] AnimationConstraint | "Workspace.n0ttusg.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[2192] BallSocketConstraint | "Workspace.n0ttusg.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[2193] MeshPart | "Workspace.n0ttusg.LeftUpperArm" | Name="LeftUpperArm"
[2194] WrapTarget | "Workspace.n0ttusg.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[2195] Attachment | "Workspace.n0ttusg.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[2196] Vector3Value | "Workspace.n0ttusg.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[2197] Attachment | "Workspace.n0ttusg.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2198] Attachment | "Workspace.n0ttusg.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[2199] Vector3Value | "Workspace.n0ttusg.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[2200] Attachment | "Workspace.n0ttusg.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[2201] Vector3Value | "Workspace.n0ttusg.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[2202] Vector3Value | "Workspace.n0ttusg.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[2203] NoCollisionConstraint | "Workspace.n0ttusg.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[2204] AnimationConstraint | "Workspace.n0ttusg.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[2205] BallSocketConstraint | "Workspace.n0ttusg.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[2206] MeshPart | "Workspace.n0ttusg.RightUpperArm" | Name="RightUpperArm"
[2207] WrapTarget | "Workspace.n0ttusg.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[2208] Attachment | "Workspace.n0ttusg.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[2209] Vector3Value | "Workspace.n0ttusg.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[2210] Attachment | "Workspace.n0ttusg.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2211] Attachment | "Workspace.n0ttusg.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[2212] Vector3Value | "Workspace.n0ttusg.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[2213] Attachment | "Workspace.n0ttusg.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[2214] Vector3Value | "Workspace.n0ttusg.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[2215] Vector3Value | "Workspace.n0ttusg.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[2216] NoCollisionConstraint | "Workspace.n0ttusg.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[2217] AnimationConstraint | "Workspace.n0ttusg.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[2218] BallSocketConstraint | "Workspace.n0ttusg.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[2219] MeshPart | "Workspace.n0ttusg.LeftFoot" | Name="LeftFoot"
[2220] WrapTarget | "Workspace.n0ttusg.LeftFoot.LeftFoot" | Name="LeftFoot"
[2221] Attachment | "Workspace.n0ttusg.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[2222] Vector3Value | "Workspace.n0ttusg.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[2223] Attachment | "Workspace.n0ttusg.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[2224] Vector3Value | "Workspace.n0ttusg.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[2225] Vector3Value | "Workspace.n0ttusg.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[2226] AnimationConstraint | "Workspace.n0ttusg.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[2227] BallSocketConstraint | "Workspace.n0ttusg.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[2228] MeshPart | "Workspace.n0ttusg.LeftLowerLeg" | Name="LeftLowerLeg"
[2229] WrapTarget | "Workspace.n0ttusg.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[2230] Attachment | "Workspace.n0ttusg.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[2231] Vector3Value | "Workspace.n0ttusg.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[2232] Attachment | "Workspace.n0ttusg.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[2233] Vector3Value | "Workspace.n0ttusg.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[2234] Vector3Value | "Workspace.n0ttusg.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[2235] AnimationConstraint | "Workspace.n0ttusg.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[2236] BallSocketConstraint | "Workspace.n0ttusg.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[2237] MeshPart | "Workspace.n0ttusg.UpperTorso" | Name="UpperTorso"
[2238] WrapTarget | "Workspace.n0ttusg.UpperTorso.UpperTorso" | Name="UpperTorso"
[2239] Attachment | "Workspace.n0ttusg.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[2240] Vector3Value | "Workspace.n0ttusg.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[2241] Attachment | "Workspace.n0ttusg.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[2242] Vector3Value | "Workspace.n0ttusg.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[2243] Attachment | "Workspace.n0ttusg.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[2244] Vector3Value | "Workspace.n0ttusg.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[2245] Attachment | "Workspace.n0ttusg.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2246] Attachment | "Workspace.n0ttusg.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[2247] Vector3Value | "Workspace.n0ttusg.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[2248] Attachment | "Workspace.n0ttusg.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2249] Attachment | "Workspace.n0ttusg.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[2250] Vector3Value | "Workspace.n0ttusg.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[2251] Attachment | "Workspace.n0ttusg.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[2252] Vector3Value | "Workspace.n0ttusg.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[2253] Attachment | "Workspace.n0ttusg.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[2254] Vector3Value | "Workspace.n0ttusg.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[2255] Attachment | "Workspace.n0ttusg.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[2256] Vector3Value | "Workspace.n0ttusg.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[2257] Attachment | "Workspace.n0ttusg.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[2258] Vector3Value | "Workspace.n0ttusg.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[2259] Vector3Value | "Workspace.n0ttusg.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[2260] NoCollisionConstraint | "Workspace.n0ttusg.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[2261] NoCollisionConstraint | "Workspace.n0ttusg.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[2262] NoCollisionConstraint | "Workspace.n0ttusg.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[2263] NoCollisionConstraint | "Workspace.n0ttusg.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[2264] NoCollisionConstraint | "Workspace.n0ttusg.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[2265] NoCollisionConstraint | "Workspace.n0ttusg.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[2266] NoCollisionConstraint | "Workspace.n0ttusg.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[2267] AnimationConstraint | "Workspace.n0ttusg.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[2268] BallSocketConstraint | "Workspace.n0ttusg.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[2269] MeshPart | "Workspace.n0ttusg.LeftUpperLeg" | Name="LeftUpperLeg"
[2270] WrapTarget | "Workspace.n0ttusg.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[2271] Attachment | "Workspace.n0ttusg.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[2272] Vector3Value | "Workspace.n0ttusg.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[2273] Attachment | "Workspace.n0ttusg.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[2274] Vector3Value | "Workspace.n0ttusg.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[2275] Vector3Value | "Workspace.n0ttusg.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[2276] NoCollisionConstraint | "Workspace.n0ttusg.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[2277] NoCollisionConstraint | "Workspace.n0ttusg.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[2278] AnimationConstraint | "Workspace.n0ttusg.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[2279] BallSocketConstraint | "Workspace.n0ttusg.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[2280] MeshPart | "Workspace.n0ttusg.RightFoot" | Name="RightFoot"
[2281] WrapTarget | "Workspace.n0ttusg.RightFoot.RightFoot" | Name="RightFoot"
[2282] Attachment | "Workspace.n0ttusg.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[2283] Vector3Value | "Workspace.n0ttusg.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[2284] Attachment | "Workspace.n0ttusg.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[2285] Vector3Value | "Workspace.n0ttusg.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[2286] Vector3Value | "Workspace.n0ttusg.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[2287] AnimationConstraint | "Workspace.n0ttusg.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[2288] BallSocketConstraint | "Workspace.n0ttusg.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[2289] MeshPart | "Workspace.n0ttusg.RightLowerLeg" | Name="RightLowerLeg"
[2290] WrapTarget | "Workspace.n0ttusg.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[2291] Attachment | "Workspace.n0ttusg.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[2292] Vector3Value | "Workspace.n0ttusg.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[2293] Attachment | "Workspace.n0ttusg.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[2294] Vector3Value | "Workspace.n0ttusg.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[2295] Vector3Value | "Workspace.n0ttusg.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[2296] AnimationConstraint | "Workspace.n0ttusg.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[2297] BallSocketConstraint | "Workspace.n0ttusg.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[2298] MeshPart | "Workspace.n0ttusg.LowerTorso" | Name="LowerTorso"
[2299] WrapTarget | "Workspace.n0ttusg.LowerTorso.LowerTorso" | Name="LowerTorso"
[2300] Attachment | "Workspace.n0ttusg.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[2301] Vector3Value | "Workspace.n0ttusg.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[2302] Attachment | "Workspace.n0ttusg.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[2303] Vector3Value | "Workspace.n0ttusg.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[2304] Attachment | "Workspace.n0ttusg.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[2305] Vector3Value | "Workspace.n0ttusg.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[2306] Attachment | "Workspace.n0ttusg.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[2307] Vector3Value | "Workspace.n0ttusg.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[2308] Attachment | "Workspace.n0ttusg.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[2309] Vector3Value | "Workspace.n0ttusg.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[2310] Attachment | "Workspace.n0ttusg.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[2311] Vector3Value | "Workspace.n0ttusg.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[2312] Attachment | "Workspace.n0ttusg.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[2313] Vector3Value | "Workspace.n0ttusg.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[2314] Vector3Value | "Workspace.n0ttusg.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[2315] NoCollisionConstraint | "Workspace.n0ttusg.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[2316] NoCollisionConstraint | "Workspace.n0ttusg.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[2317] NoCollisionConstraint | "Workspace.n0ttusg.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[2318] NoCollisionConstraint | "Workspace.n0ttusg.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[2319] AnimationConstraint | "Workspace.n0ttusg.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[2320] MeshPart | "Workspace.n0ttusg.RightUpperLeg" | Name="RightUpperLeg"
[2321] WrapTarget | "Workspace.n0ttusg.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[2322] Attachment | "Workspace.n0ttusg.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[2323] Vector3Value | "Workspace.n0ttusg.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[2324] Attachment | "Workspace.n0ttusg.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[2325] Vector3Value | "Workspace.n0ttusg.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[2326] Vector3Value | "Workspace.n0ttusg.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[2327] NoCollisionConstraint | "Workspace.n0ttusg.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[2328] AnimationConstraint | "Workspace.n0ttusg.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[2329] BallSocketConstraint | "Workspace.n0ttusg.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[2330] MeshPart | "Workspace.n0ttusg.Head" | Name="Head"
[2331] Attachment | "Workspace.n0ttusg.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[2332] Vector3Value | "Workspace.n0ttusg.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[2333] Vector3Value | "Workspace.n0ttusg.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[2334] WrapTarget | "Workspace.n0ttusg.Head.Head" | Name="Head"
[2335] FaceControls | "Workspace.n0ttusg.Head.FaceControls" | Name="FaceControls"
[2336] NoCollisionConstraint | "Workspace.n0ttusg.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[2337] NoCollisionConstraint | "Workspace.n0ttusg.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[2338] NoCollisionConstraint | "Workspace.n0ttusg.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[2339] AnimationConstraint | "Workspace.n0ttusg.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[2340] BallSocketConstraint | "Workspace.n0ttusg.Head.NeckBallSocket" | Name="NeckBallSocket"
[2341] Attachment | "Workspace.n0ttusg.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[2342] Vector3Value | "Workspace.n0ttusg.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[2343] Attachment | "Workspace.n0ttusg.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[2344] Vector3Value | "Workspace.n0ttusg.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[2345] Attachment | "Workspace.n0ttusg.Head.HairAttachment" | Name="HairAttachment"
[2346] Vector3Value | "Workspace.n0ttusg.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[2347] Attachment | "Workspace.n0ttusg.Head.HatAttachment" | Name="HatAttachment"
[2348] Vector3Value | "Workspace.n0ttusg.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[2349] Model | "Workspace.GazaaaMC" | Name="GazaaaMC"; attr:TPS_Weapon="AR15"
[2350] Part | "Workspace.GazaaaMC.HumanoidRootPart" | Name="HumanoidRootPart"
[2351] Attachment | "Workspace.GazaaaMC.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[2352] Vector3Value | "Workspace.GazaaaMC.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[2353] Vector3Value | "Workspace.GazaaaMC.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[2354] Attachment | "Workspace.GazaaaMC.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[2355] Sound | "Workspace.GazaaaMC.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[2356] Sound | "Workspace.GazaaaMC.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[2357] Sound | "Workspace.GazaaaMC.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[2358] Sound | "Workspace.GazaaaMC.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[2359] Sound | "Workspace.GazaaaMC.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[2360] Sound | "Workspace.GazaaaMC.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[2361] Sound | "Workspace.GazaaaMC.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[2362] Sound | "Workspace.GazaaaMC.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[2363] Sound | "Workspace.GazaaaMC.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[2364] MeshPart | "Workspace.GazaaaMC.LeftHand" | Name="LeftHand"
[2365] WrapTarget | "Workspace.GazaaaMC.LeftHand.LeftHand" | Name="LeftHand"
[2366] Attachment | "Workspace.GazaaaMC.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[2367] Vector3Value | "Workspace.GazaaaMC.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[2368] Attachment | "Workspace.GazaaaMC.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[2369] Vector3Value | "Workspace.GazaaaMC.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[2370] Vector3Value | "Workspace.GazaaaMC.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[2371] AnimationConstraint | "Workspace.GazaaaMC.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[2372] BallSocketConstraint | "Workspace.GazaaaMC.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[2373] MeshPart | "Workspace.GazaaaMC.RightHand" | Name="RightHand"
[2374] WrapTarget | "Workspace.GazaaaMC.RightHand.RightHand" | Name="RightHand"
[2375] Attachment | "Workspace.GazaaaMC.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[2376] Vector3Value | "Workspace.GazaaaMC.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[2377] Attachment | "Workspace.GazaaaMC.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[2378] Vector3Value | "Workspace.GazaaaMC.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[2379] Vector3Value | "Workspace.GazaaaMC.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[2380] AnimationConstraint | "Workspace.GazaaaMC.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[2381] BallSocketConstraint | "Workspace.GazaaaMC.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[2382] MeshPart | "Workspace.GazaaaMC.LeftLowerArm" | Name="LeftLowerArm"
[2383] WrapTarget | "Workspace.GazaaaMC.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[2384] Attachment | "Workspace.GazaaaMC.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[2385] Vector3Value | "Workspace.GazaaaMC.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[2386] Attachment | "Workspace.GazaaaMC.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[2387] Vector3Value | "Workspace.GazaaaMC.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[2388] Vector3Value | "Workspace.GazaaaMC.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[2389] AnimationConstraint | "Workspace.GazaaaMC.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[2390] BallSocketConstraint | "Workspace.GazaaaMC.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[2391] MeshPart | "Workspace.GazaaaMC.RightLowerArm" | Name="RightLowerArm"
[2392] WrapTarget | "Workspace.GazaaaMC.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[2393] Attachment | "Workspace.GazaaaMC.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[2394] Vector3Value | "Workspace.GazaaaMC.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[2395] Attachment | "Workspace.GazaaaMC.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[2396] Vector3Value | "Workspace.GazaaaMC.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[2397] Vector3Value | "Workspace.GazaaaMC.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[2398] AnimationConstraint | "Workspace.GazaaaMC.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[2399] BallSocketConstraint | "Workspace.GazaaaMC.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[2400] MeshPart | "Workspace.GazaaaMC.LeftUpperArm" | Name="LeftUpperArm"
[2401] WrapTarget | "Workspace.GazaaaMC.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[2402] Attachment | "Workspace.GazaaaMC.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[2403] Vector3Value | "Workspace.GazaaaMC.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[2404] Attachment | "Workspace.GazaaaMC.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2405] Attachment | "Workspace.GazaaaMC.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[2406] Vector3Value | "Workspace.GazaaaMC.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[2407] Attachment | "Workspace.GazaaaMC.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[2408] Vector3Value | "Workspace.GazaaaMC.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[2409] Vector3Value | "Workspace.GazaaaMC.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[2410] NoCollisionConstraint | "Workspace.GazaaaMC.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[2411] AnimationConstraint | "Workspace.GazaaaMC.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[2412] BallSocketConstraint | "Workspace.GazaaaMC.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[2413] MeshPart | "Workspace.GazaaaMC.RightUpperArm" | Name="RightUpperArm"
[2414] WrapTarget | "Workspace.GazaaaMC.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[2415] Attachment | "Workspace.GazaaaMC.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[2416] Vector3Value | "Workspace.GazaaaMC.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[2417] Attachment | "Workspace.GazaaaMC.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2418] Attachment | "Workspace.GazaaaMC.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[2419] Vector3Value | "Workspace.GazaaaMC.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[2420] Attachment | "Workspace.GazaaaMC.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[2421] Vector3Value | "Workspace.GazaaaMC.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[2422] Vector3Value | "Workspace.GazaaaMC.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[2423] NoCollisionConstraint | "Workspace.GazaaaMC.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[2424] AnimationConstraint | "Workspace.GazaaaMC.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[2425] BallSocketConstraint | "Workspace.GazaaaMC.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[2426] MeshPart | "Workspace.GazaaaMC.LeftFoot" | Name="LeftFoot"
[2427] WrapTarget | "Workspace.GazaaaMC.LeftFoot.LeftFoot" | Name="LeftFoot"
[2428] Attachment | "Workspace.GazaaaMC.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[2429] Vector3Value | "Workspace.GazaaaMC.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[2430] Attachment | "Workspace.GazaaaMC.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[2431] Vector3Value | "Workspace.GazaaaMC.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[2432] Vector3Value | "Workspace.GazaaaMC.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[2433] AnimationConstraint | "Workspace.GazaaaMC.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[2434] BallSocketConstraint | "Workspace.GazaaaMC.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[2435] MeshPart | "Workspace.GazaaaMC.LeftLowerLeg" | Name="LeftLowerLeg"
[2436] WrapTarget | "Workspace.GazaaaMC.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[2437] Attachment | "Workspace.GazaaaMC.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[2438] Vector3Value | "Workspace.GazaaaMC.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[2439] Attachment | "Workspace.GazaaaMC.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[2440] Vector3Value | "Workspace.GazaaaMC.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[2441] Vector3Value | "Workspace.GazaaaMC.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[2442] AnimationConstraint | "Workspace.GazaaaMC.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[2443] BallSocketConstraint | "Workspace.GazaaaMC.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[2444] MeshPart | "Workspace.GazaaaMC.UpperTorso" | Name="UpperTorso"
[2445] WrapTarget | "Workspace.GazaaaMC.UpperTorso.UpperTorso" | Name="UpperTorso"
[2446] Attachment | "Workspace.GazaaaMC.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[2447] Vector3Value | "Workspace.GazaaaMC.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[2448] Attachment | "Workspace.GazaaaMC.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[2449] Vector3Value | "Workspace.GazaaaMC.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[2450] Attachment | "Workspace.GazaaaMC.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[2451] Vector3Value | "Workspace.GazaaaMC.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[2452] Attachment | "Workspace.GazaaaMC.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2453] Attachment | "Workspace.GazaaaMC.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[2454] Vector3Value | "Workspace.GazaaaMC.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[2455] Attachment | "Workspace.GazaaaMC.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2456] Attachment | "Workspace.GazaaaMC.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[2457] Vector3Value | "Workspace.GazaaaMC.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[2458] Attachment | "Workspace.GazaaaMC.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[2459] Vector3Value | "Workspace.GazaaaMC.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[2460] Attachment | "Workspace.GazaaaMC.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[2461] Vector3Value | "Workspace.GazaaaMC.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[2462] Attachment | "Workspace.GazaaaMC.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[2463] Vector3Value | "Workspace.GazaaaMC.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[2464] Attachment | "Workspace.GazaaaMC.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[2465] Vector3Value | "Workspace.GazaaaMC.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[2466] Vector3Value | "Workspace.GazaaaMC.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[2467] NoCollisionConstraint | "Workspace.GazaaaMC.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[2468] NoCollisionConstraint | "Workspace.GazaaaMC.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[2469] NoCollisionConstraint | "Workspace.GazaaaMC.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[2470] NoCollisionConstraint | "Workspace.GazaaaMC.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[2471] NoCollisionConstraint | "Workspace.GazaaaMC.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[2472] NoCollisionConstraint | "Workspace.GazaaaMC.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[2473] NoCollisionConstraint | "Workspace.GazaaaMC.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[2474] AnimationConstraint | "Workspace.GazaaaMC.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[2475] BallSocketConstraint | "Workspace.GazaaaMC.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[2476] MeshPart | "Workspace.GazaaaMC.LeftUpperLeg" | Name="LeftUpperLeg"
[2477] WrapTarget | "Workspace.GazaaaMC.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[2478] Attachment | "Workspace.GazaaaMC.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[2479] Vector3Value | "Workspace.GazaaaMC.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[2480] Attachment | "Workspace.GazaaaMC.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[2481] Vector3Value | "Workspace.GazaaaMC.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[2482] Vector3Value | "Workspace.GazaaaMC.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[2483] NoCollisionConstraint | "Workspace.GazaaaMC.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[2484] NoCollisionConstraint | "Workspace.GazaaaMC.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[2485] AnimationConstraint | "Workspace.GazaaaMC.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[2486] BallSocketConstraint | "Workspace.GazaaaMC.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[2487] MeshPart | "Workspace.GazaaaMC.RightFoot" | Name="RightFoot"
[2488] WrapTarget | "Workspace.GazaaaMC.RightFoot.RightFoot" | Name="RightFoot"
[2489] Attachment | "Workspace.GazaaaMC.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[2490] Vector3Value | "Workspace.GazaaaMC.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[2491] Attachment | "Workspace.GazaaaMC.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[2492] Vector3Value | "Workspace.GazaaaMC.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[2493] Vector3Value | "Workspace.GazaaaMC.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[2494] AnimationConstraint | "Workspace.GazaaaMC.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[2495] BallSocketConstraint | "Workspace.GazaaaMC.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[2496] MeshPart | "Workspace.GazaaaMC.RightLowerLeg" | Name="RightLowerLeg"
[2497] WrapTarget | "Workspace.GazaaaMC.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[2498] Attachment | "Workspace.GazaaaMC.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[2499] Vector3Value | "Workspace.GazaaaMC.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[2500] Attachment | "Workspace.GazaaaMC.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[2501] Vector3Value | "Workspace.GazaaaMC.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[2502] Vector3Value | "Workspace.GazaaaMC.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[2503] AnimationConstraint | "Workspace.GazaaaMC.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[2504] BallSocketConstraint | "Workspace.GazaaaMC.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[2505] MeshPart | "Workspace.GazaaaMC.LowerTorso" | Name="LowerTorso"
[2506] WrapTarget | "Workspace.GazaaaMC.LowerTorso.LowerTorso" | Name="LowerTorso"
[2507] Attachment | "Workspace.GazaaaMC.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[2508] Vector3Value | "Workspace.GazaaaMC.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[2509] Attachment | "Workspace.GazaaaMC.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[2510] Vector3Value | "Workspace.GazaaaMC.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[2511] Attachment | "Workspace.GazaaaMC.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[2512] Vector3Value | "Workspace.GazaaaMC.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[2513] Attachment | "Workspace.GazaaaMC.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[2514] Vector3Value | "Workspace.GazaaaMC.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[2515] Attachment | "Workspace.GazaaaMC.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[2516] Vector3Value | "Workspace.GazaaaMC.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[2517] Attachment | "Workspace.GazaaaMC.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[2518] Vector3Value | "Workspace.GazaaaMC.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[2519] Attachment | "Workspace.GazaaaMC.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[2520] Vector3Value | "Workspace.GazaaaMC.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[2521] Vector3Value | "Workspace.GazaaaMC.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[2522] NoCollisionConstraint | "Workspace.GazaaaMC.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[2523] NoCollisionConstraint | "Workspace.GazaaaMC.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[2524] NoCollisionConstraint | "Workspace.GazaaaMC.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[2525] NoCollisionConstraint | "Workspace.GazaaaMC.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[2526] AnimationConstraint | "Workspace.GazaaaMC.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[2527] MeshPart | "Workspace.GazaaaMC.RightUpperLeg" | Name="RightUpperLeg"
[2528] WrapTarget | "Workspace.GazaaaMC.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[2529] Attachment | "Workspace.GazaaaMC.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[2530] Vector3Value | "Workspace.GazaaaMC.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[2531] Attachment | "Workspace.GazaaaMC.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[2532] Vector3Value | "Workspace.GazaaaMC.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[2533] Vector3Value | "Workspace.GazaaaMC.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[2534] NoCollisionConstraint | "Workspace.GazaaaMC.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[2535] AnimationConstraint | "Workspace.GazaaaMC.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[2536] BallSocketConstraint | "Workspace.GazaaaMC.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[2537] Humanoid | "Workspace.GazaaaMC.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[2538] Status | "Workspace.GazaaaMC.Humanoid.Status" | Name="Status"
[2539] Animator | "Workspace.GazaaaMC.Humanoid.Animator" | Name="Animator"
[2540] MeshPart | "Workspace.GazaaaMC.Head" | Name="Head"
[2541] Attachment | "Workspace.GazaaaMC.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[2542] Vector3Value | "Workspace.GazaaaMC.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[2543] Attachment | "Workspace.GazaaaMC.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[2544] Vector3Value | "Workspace.GazaaaMC.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[2545] Attachment | "Workspace.GazaaaMC.Head.HairAttachment" | Name="HairAttachment"
[2546] Vector3Value | "Workspace.GazaaaMC.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[2547] Attachment | "Workspace.GazaaaMC.Head.HatAttachment" | Name="HatAttachment"
[2548] Vector3Value | "Workspace.GazaaaMC.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[2549] Attachment | "Workspace.GazaaaMC.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[2550] Vector3Value | "Workspace.GazaaaMC.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[2551] Vector3Value | "Workspace.GazaaaMC.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[2552] WrapTarget | "Workspace.GazaaaMC.Head.Head" | Name="Head"
[2553] FaceControls | "Workspace.GazaaaMC.Head.FaceControls" | Name="FaceControls"
[2554] NoCollisionConstraint | "Workspace.GazaaaMC.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[2555] NoCollisionConstraint | "Workspace.GazaaaMC.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[2556] NoCollisionConstraint | "Workspace.GazaaaMC.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[2557] AnimationConstraint | "Workspace.GazaaaMC.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[2558] BallSocketConstraint | "Workspace.GazaaaMC.Head.NeckBallSocket" | Name="NeckBallSocket"
[2559] Script | "Workspace.GazaaaMC.Health" | Name="Health"
[2560] LocalScript | "Workspace.GazaaaMC.Animate" | Name="Animate"
[2561] StringValue | "Workspace.GazaaaMC.Animate.cheer" | Name="cheer"; Value=""
[2562] Animation | "Workspace.GazaaaMC.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[2563] StringValue | "Workspace.GazaaaMC.Animate.climb" | Name="climb"; Value=""
[2564] Animation | "Workspace.GazaaaMC.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[2565] StringValue | "Workspace.GazaaaMC.Animate.dance" | Name="dance"; Value=""
[2566] Animation | "Workspace.GazaaaMC.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[2567] NumberValue | "Workspace.GazaaaMC.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[2568] Animation | "Workspace.GazaaaMC.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[2569] NumberValue | "Workspace.GazaaaMC.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[2570] Animation | "Workspace.GazaaaMC.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[2571] NumberValue | "Workspace.GazaaaMC.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[2572] StringValue | "Workspace.GazaaaMC.Animate.dance2" | Name="dance2"; Value=""
[2573] Animation | "Workspace.GazaaaMC.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[2574] NumberValue | "Workspace.GazaaaMC.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[2575] Animation | "Workspace.GazaaaMC.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[2576] NumberValue | "Workspace.GazaaaMC.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[2577] Animation | "Workspace.GazaaaMC.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[2578] NumberValue | "Workspace.GazaaaMC.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[2579] StringValue | "Workspace.GazaaaMC.Animate.dance3" | Name="dance3"; Value=""
[2580] Animation | "Workspace.GazaaaMC.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[2581] NumberValue | "Workspace.GazaaaMC.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[2582] Animation | "Workspace.GazaaaMC.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[2583] NumberValue | "Workspace.GazaaaMC.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[2584] Animation | "Workspace.GazaaaMC.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[2585] NumberValue | "Workspace.GazaaaMC.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[2586] StringValue | "Workspace.GazaaaMC.Animate.fall" | Name="fall"; Value=""
[2587] Animation | "Workspace.GazaaaMC.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[2588] StringValue | "Workspace.GazaaaMC.Animate.idle" | Name="idle"; Value=""
[2589] Animation | "Workspace.GazaaaMC.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[2590] NumberValue | "Workspace.GazaaaMC.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[2591] Animation | "Workspace.GazaaaMC.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[2592] NumberValue | "Workspace.GazaaaMC.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[2593] StringValue | "Workspace.GazaaaMC.Animate.jump" | Name="jump"; Value=""
[2594] Animation | "Workspace.GazaaaMC.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[2595] StringValue | "Workspace.GazaaaMC.Animate.laugh" | Name="laugh"; Value=""
[2596] Animation | "Workspace.GazaaaMC.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[2597] StringValue | "Workspace.GazaaaMC.Animate.point" | Name="point"; Value=""
[2598] Animation | "Workspace.GazaaaMC.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[2599] StringValue | "Workspace.GazaaaMC.Animate.sit" | Name="sit"; Value=""
[2600] Animation | "Workspace.GazaaaMC.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[2601] StringValue | "Workspace.GazaaaMC.Animate.toollunge" | Name="toollunge"; Value=""
[2602] Animation | "Workspace.GazaaaMC.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[2603] StringValue | "Workspace.GazaaaMC.Animate.toolnone" | Name="toolnone"; Value=""
[2604] Animation | "Workspace.GazaaaMC.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[2605] StringValue | "Workspace.GazaaaMC.Animate.toolslash" | Name="toolslash"; Value=""
[2606] Animation | "Workspace.GazaaaMC.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[2607] StringValue | "Workspace.GazaaaMC.Animate.wave" | Name="wave"; Value=""
[2608] Animation | "Workspace.GazaaaMC.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[2609] NumberValue | "Workspace.GazaaaMC.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[2610] StringValue | "Workspace.GazaaaMC.Animate.run" | Name="run"; Value=""
[2611] Animation | "Workspace.GazaaaMC.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[2612] StringValue | "Workspace.GazaaaMC.Animate.swim" | Name="swim"; Value=""
[2613] Animation | "Workspace.GazaaaMC.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[2614] StringValue | "Workspace.GazaaaMC.Animate.swimidle" | Name="swimidle"; Value=""
[2615] Animation | "Workspace.GazaaaMC.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[2616] StringValue | "Workspace.GazaaaMC.Animate.walk" | Name="walk"; Value=""
[2617] Animation | "Workspace.GazaaaMC.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[2618] BindableFunction | "Workspace.GazaaaMC.Animate.PlayEmote" | Name="PlayEmote"
[2619] StringValue | "Workspace.GazaaaMC.Animate.mood" | Name="mood"; Value=""
[2620] Animation | "Workspace.GazaaaMC.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[2621] AudioEmitter | "Workspace.GazaaaMC.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[2622] Wire | "Workspace.GazaaaMC.AudioEmitter.Wire" | Name="Wire"
[2623] Model | "Workspace.GazaaaMC.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Default"; attr:TPS_WeaponId="AR15"
[2624] Part | "Workspace.GazaaaMC.TPS_HeldWeapon.Handle" | Name="Handle"
[2625] Attachment | "Workspace.GazaaaMC.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[2626] Attachment | "Workspace.GazaaaMC.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[2627] Attachment | "Workspace.GazaaaMC.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[2628] Motor6D | "Workspace.GazaaaMC.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[2629] Part | "Workspace.GazaaaMC.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"
[2630] SpecialMesh | "Workspace.GazaaaMC.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[2631] WeldConstraint | "Workspace.GazaaaMC.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[2632] Part | "Workspace.GazaaaMC.TPS_HeldWeapon.Magazine" | Name="Magazine"
[2633] Weld | "Workspace.GazaaaMC.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[2634] Attachment | "Workspace.GazaaaMC.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[2635] Model | "Workspace.Itzcardosoo" | Name="Itzcardosoo"; attr:TPS_Weapon="AR15"
[2636] Script | "Workspace.Itzcardosoo.Health" | Name="Health"
[2637] LocalScript | "Workspace.Itzcardosoo.Animate" | Name="Animate"
[2638] StringValue | "Workspace.Itzcardosoo.Animate.cheer" | Name="cheer"; Value=""
[2639] Animation | "Workspace.Itzcardosoo.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[2640] StringValue | "Workspace.Itzcardosoo.Animate.climb" | Name="climb"; Value=""
[2641] Animation | "Workspace.Itzcardosoo.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[2642] StringValue | "Workspace.Itzcardosoo.Animate.dance" | Name="dance"; Value=""
[2643] Animation | "Workspace.Itzcardosoo.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[2644] NumberValue | "Workspace.Itzcardosoo.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[2645] Animation | "Workspace.Itzcardosoo.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[2646] NumberValue | "Workspace.Itzcardosoo.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[2647] Animation | "Workspace.Itzcardosoo.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[2648] NumberValue | "Workspace.Itzcardosoo.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[2649] StringValue | "Workspace.Itzcardosoo.Animate.dance2" | Name="dance2"; Value=""
[2650] Animation | "Workspace.Itzcardosoo.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[2651] NumberValue | "Workspace.Itzcardosoo.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[2652] Animation | "Workspace.Itzcardosoo.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[2653] NumberValue | "Workspace.Itzcardosoo.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[2654] Animation | "Workspace.Itzcardosoo.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[2655] NumberValue | "Workspace.Itzcardosoo.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[2656] StringValue | "Workspace.Itzcardosoo.Animate.dance3" | Name="dance3"; Value=""
[2657] Animation | "Workspace.Itzcardosoo.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[2658] NumberValue | "Workspace.Itzcardosoo.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[2659] Animation | "Workspace.Itzcardosoo.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[2660] NumberValue | "Workspace.Itzcardosoo.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[2661] Animation | "Workspace.Itzcardosoo.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[2662] NumberValue | "Workspace.Itzcardosoo.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[2663] StringValue | "Workspace.Itzcardosoo.Animate.fall" | Name="fall"; Value=""
[2664] Animation | "Workspace.Itzcardosoo.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[2665] StringValue | "Workspace.Itzcardosoo.Animate.idle" | Name="idle"; Value=""
[2666] Animation | "Workspace.Itzcardosoo.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[2667] NumberValue | "Workspace.Itzcardosoo.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[2668] Animation | "Workspace.Itzcardosoo.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[2669] NumberValue | "Workspace.Itzcardosoo.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[2670] StringValue | "Workspace.Itzcardosoo.Animate.jump" | Name="jump"; Value=""
[2671] Animation | "Workspace.Itzcardosoo.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[2672] StringValue | "Workspace.Itzcardosoo.Animate.laugh" | Name="laugh"; Value=""
[2673] Animation | "Workspace.Itzcardosoo.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[2674] StringValue | "Workspace.Itzcardosoo.Animate.point" | Name="point"; Value=""
[2675] Animation | "Workspace.Itzcardosoo.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[2676] StringValue | "Workspace.Itzcardosoo.Animate.sit" | Name="sit"; Value=""
[2677] Animation | "Workspace.Itzcardosoo.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[2678] StringValue | "Workspace.Itzcardosoo.Animate.toollunge" | Name="toollunge"; Value=""
[2679] Animation | "Workspace.Itzcardosoo.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[2680] StringValue | "Workspace.Itzcardosoo.Animate.toolnone" | Name="toolnone"; Value=""
[2681] Animation | "Workspace.Itzcardosoo.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[2682] StringValue | "Workspace.Itzcardosoo.Animate.toolslash" | Name="toolslash"; Value=""
[2683] Animation | "Workspace.Itzcardosoo.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[2684] StringValue | "Workspace.Itzcardosoo.Animate.wave" | Name="wave"; Value=""
[2685] Animation | "Workspace.Itzcardosoo.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[2686] NumberValue | "Workspace.Itzcardosoo.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[2687] StringValue | "Workspace.Itzcardosoo.Animate.run" | Name="run"; Value=""
[2688] Animation | "Workspace.Itzcardosoo.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[2689] StringValue | "Workspace.Itzcardosoo.Animate.swim" | Name="swim"; Value=""
[2690] Animation | "Workspace.Itzcardosoo.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[2691] StringValue | "Workspace.Itzcardosoo.Animate.swimidle" | Name="swimidle"; Value=""
[2692] Animation | "Workspace.Itzcardosoo.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[2693] StringValue | "Workspace.Itzcardosoo.Animate.walk" | Name="walk"; Value=""
[2694] Animation | "Workspace.Itzcardosoo.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[2695] BindableFunction | "Workspace.Itzcardosoo.Animate.PlayEmote" | Name="PlayEmote"
[2696] StringValue | "Workspace.Itzcardosoo.Animate.mood" | Name="mood"; Value=""
[2697] Animation | "Workspace.Itzcardosoo.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[2698] Humanoid | "Workspace.Itzcardosoo.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[2699] Status | "Workspace.Itzcardosoo.Humanoid.Status" | Name="Status"
[2700] Animator | "Workspace.Itzcardosoo.Humanoid.Animator" | Name="Animator"
[2701] AudioEmitter | "Workspace.Itzcardosoo.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[2702] Wire | "Workspace.Itzcardosoo.AudioEmitter.Wire" | Name="Wire"
[2703] Model | "Workspace.Itzcardosoo.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Default"; attr:TPS_WeaponId="AR15"
[2704] Part | "Workspace.Itzcardosoo.TPS_HeldWeapon.Handle" | Name="Handle"
[2705] Attachment | "Workspace.Itzcardosoo.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[2706] Attachment | "Workspace.Itzcardosoo.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[2707] Attachment | "Workspace.Itzcardosoo.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[2708] Motor6D | "Workspace.Itzcardosoo.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[2709] Part | "Workspace.Itzcardosoo.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"
[2710] SpecialMesh | "Workspace.Itzcardosoo.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[2711] WeldConstraint | "Workspace.Itzcardosoo.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[2712] Part | "Workspace.Itzcardosoo.TPS_HeldWeapon.Magazine" | Name="Magazine"
[2713] Weld | "Workspace.Itzcardosoo.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[2714] Attachment | "Workspace.Itzcardosoo.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[2715] Part | "Workspace.Itzcardosoo.HumanoidRootPart" | Name="HumanoidRootPart"
[2716] Attachment | "Workspace.Itzcardosoo.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[2717] Vector3Value | "Workspace.Itzcardosoo.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[2718] Vector3Value | "Workspace.Itzcardosoo.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[2719] Attachment | "Workspace.Itzcardosoo.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[2720] Sound | "Workspace.Itzcardosoo.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[2721] Sound | "Workspace.Itzcardosoo.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[2722] Sound | "Workspace.Itzcardosoo.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[2723] Sound | "Workspace.Itzcardosoo.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[2724] Sound | "Workspace.Itzcardosoo.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[2725] Sound | "Workspace.Itzcardosoo.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[2726] Sound | "Workspace.Itzcardosoo.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[2727] Sound | "Workspace.Itzcardosoo.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[2728] Sound | "Workspace.Itzcardosoo.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[2729] MeshPart | "Workspace.Itzcardosoo.LeftHand" | Name="LeftHand"
[2730] WrapTarget | "Workspace.Itzcardosoo.LeftHand.LeftHand" | Name="LeftHand"
[2731] Attachment | "Workspace.Itzcardosoo.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[2732] Vector3Value | "Workspace.Itzcardosoo.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[2733] Attachment | "Workspace.Itzcardosoo.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[2734] Vector3Value | "Workspace.Itzcardosoo.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[2735] Vector3Value | "Workspace.Itzcardosoo.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[2736] AnimationConstraint | "Workspace.Itzcardosoo.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[2737] BallSocketConstraint | "Workspace.Itzcardosoo.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[2738] MeshPart | "Workspace.Itzcardosoo.RightHand" | Name="RightHand"
[2739] WrapTarget | "Workspace.Itzcardosoo.RightHand.RightHand" | Name="RightHand"
[2740] Attachment | "Workspace.Itzcardosoo.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[2741] Vector3Value | "Workspace.Itzcardosoo.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[2742] Attachment | "Workspace.Itzcardosoo.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[2743] Vector3Value | "Workspace.Itzcardosoo.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[2744] Vector3Value | "Workspace.Itzcardosoo.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[2745] AnimationConstraint | "Workspace.Itzcardosoo.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[2746] BallSocketConstraint | "Workspace.Itzcardosoo.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[2747] MeshPart | "Workspace.Itzcardosoo.LeftLowerArm" | Name="LeftLowerArm"
[2748] WrapTarget | "Workspace.Itzcardosoo.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[2749] Attachment | "Workspace.Itzcardosoo.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[2750] Vector3Value | "Workspace.Itzcardosoo.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[2751] Attachment | "Workspace.Itzcardosoo.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[2752] Vector3Value | "Workspace.Itzcardosoo.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[2753] Vector3Value | "Workspace.Itzcardosoo.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[2754] AnimationConstraint | "Workspace.Itzcardosoo.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[2755] BallSocketConstraint | "Workspace.Itzcardosoo.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[2756] MeshPart | "Workspace.Itzcardosoo.RightLowerArm" | Name="RightLowerArm"
[2757] WrapTarget | "Workspace.Itzcardosoo.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[2758] Attachment | "Workspace.Itzcardosoo.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[2759] Vector3Value | "Workspace.Itzcardosoo.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[2760] Attachment | "Workspace.Itzcardosoo.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[2761] Vector3Value | "Workspace.Itzcardosoo.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[2762] Vector3Value | "Workspace.Itzcardosoo.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[2763] AnimationConstraint | "Workspace.Itzcardosoo.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[2764] BallSocketConstraint | "Workspace.Itzcardosoo.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[2765] MeshPart | "Workspace.Itzcardosoo.LeftUpperArm" | Name="LeftUpperArm"
[2766] WrapTarget | "Workspace.Itzcardosoo.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[2767] Attachment | "Workspace.Itzcardosoo.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[2768] Vector3Value | "Workspace.Itzcardosoo.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[2769] Attachment | "Workspace.Itzcardosoo.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2770] Attachment | "Workspace.Itzcardosoo.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[2771] Vector3Value | "Workspace.Itzcardosoo.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[2772] Attachment | "Workspace.Itzcardosoo.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[2773] Vector3Value | "Workspace.Itzcardosoo.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[2774] Vector3Value | "Workspace.Itzcardosoo.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[2775] NoCollisionConstraint | "Workspace.Itzcardosoo.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[2776] AnimationConstraint | "Workspace.Itzcardosoo.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[2777] BallSocketConstraint | "Workspace.Itzcardosoo.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[2778] MeshPart | "Workspace.Itzcardosoo.RightUpperArm" | Name="RightUpperArm"
[2779] WrapTarget | "Workspace.Itzcardosoo.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[2780] Attachment | "Workspace.Itzcardosoo.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[2781] Vector3Value | "Workspace.Itzcardosoo.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[2782] Attachment | "Workspace.Itzcardosoo.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2783] Attachment | "Workspace.Itzcardosoo.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[2784] Vector3Value | "Workspace.Itzcardosoo.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[2785] Attachment | "Workspace.Itzcardosoo.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[2786] Vector3Value | "Workspace.Itzcardosoo.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[2787] Vector3Value | "Workspace.Itzcardosoo.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[2788] NoCollisionConstraint | "Workspace.Itzcardosoo.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[2789] AnimationConstraint | "Workspace.Itzcardosoo.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[2790] BallSocketConstraint | "Workspace.Itzcardosoo.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[2791] MeshPart | "Workspace.Itzcardosoo.LeftFoot" | Name="LeftFoot"
[2792] WrapTarget | "Workspace.Itzcardosoo.LeftFoot.LeftFoot" | Name="LeftFoot"
[2793] Attachment | "Workspace.Itzcardosoo.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[2794] Vector3Value | "Workspace.Itzcardosoo.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[2795] Attachment | "Workspace.Itzcardosoo.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[2796] Vector3Value | "Workspace.Itzcardosoo.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[2797] Vector3Value | "Workspace.Itzcardosoo.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[2798] AnimationConstraint | "Workspace.Itzcardosoo.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[2799] BallSocketConstraint | "Workspace.Itzcardosoo.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[2800] MeshPart | "Workspace.Itzcardosoo.LeftLowerLeg" | Name="LeftLowerLeg"
[2801] WrapTarget | "Workspace.Itzcardosoo.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[2802] Attachment | "Workspace.Itzcardosoo.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[2803] Vector3Value | "Workspace.Itzcardosoo.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[2804] Attachment | "Workspace.Itzcardosoo.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[2805] Vector3Value | "Workspace.Itzcardosoo.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[2806] Vector3Value | "Workspace.Itzcardosoo.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[2807] AnimationConstraint | "Workspace.Itzcardosoo.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[2808] BallSocketConstraint | "Workspace.Itzcardosoo.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[2809] MeshPart | "Workspace.Itzcardosoo.UpperTorso" | Name="UpperTorso"
[2810] WrapTarget | "Workspace.Itzcardosoo.UpperTorso.UpperTorso" | Name="UpperTorso"
[2811] Attachment | "Workspace.Itzcardosoo.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[2812] Vector3Value | "Workspace.Itzcardosoo.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[2813] Attachment | "Workspace.Itzcardosoo.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[2814] Vector3Value | "Workspace.Itzcardosoo.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[2815] Attachment | "Workspace.Itzcardosoo.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[2816] Vector3Value | "Workspace.Itzcardosoo.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[2817] Attachment | "Workspace.Itzcardosoo.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2818] Attachment | "Workspace.Itzcardosoo.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[2819] Vector3Value | "Workspace.Itzcardosoo.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[2820] Attachment | "Workspace.Itzcardosoo.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[2821] Attachment | "Workspace.Itzcardosoo.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[2822] Vector3Value | "Workspace.Itzcardosoo.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[2823] Attachment | "Workspace.Itzcardosoo.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[2824] Vector3Value | "Workspace.Itzcardosoo.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[2825] Attachment | "Workspace.Itzcardosoo.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[2826] Vector3Value | "Workspace.Itzcardosoo.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[2827] Attachment | "Workspace.Itzcardosoo.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[2828] Vector3Value | "Workspace.Itzcardosoo.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[2829] Attachment | "Workspace.Itzcardosoo.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[2830] Vector3Value | "Workspace.Itzcardosoo.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[2831] Vector3Value | "Workspace.Itzcardosoo.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[2832] NoCollisionConstraint | "Workspace.Itzcardosoo.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[2833] NoCollisionConstraint | "Workspace.Itzcardosoo.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[2834] NoCollisionConstraint | "Workspace.Itzcardosoo.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[2835] NoCollisionConstraint | "Workspace.Itzcardosoo.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[2836] NoCollisionConstraint | "Workspace.Itzcardosoo.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[2837] NoCollisionConstraint | "Workspace.Itzcardosoo.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[2838] NoCollisionConstraint | "Workspace.Itzcardosoo.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[2839] AnimationConstraint | "Workspace.Itzcardosoo.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[2840] BallSocketConstraint | "Workspace.Itzcardosoo.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[2841] MeshPart | "Workspace.Itzcardosoo.LeftUpperLeg" | Name="LeftUpperLeg"
[2842] WrapTarget | "Workspace.Itzcardosoo.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[2843] Attachment | "Workspace.Itzcardosoo.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[2844] Vector3Value | "Workspace.Itzcardosoo.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[2845] Attachment | "Workspace.Itzcardosoo.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[2846] Vector3Value | "Workspace.Itzcardosoo.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[2847] Vector3Value | "Workspace.Itzcardosoo.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[2848] NoCollisionConstraint | "Workspace.Itzcardosoo.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[2849] NoCollisionConstraint | "Workspace.Itzcardosoo.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[2850] AnimationConstraint | "Workspace.Itzcardosoo.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[2851] BallSocketConstraint | "Workspace.Itzcardosoo.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[2852] MeshPart | "Workspace.Itzcardosoo.RightFoot" | Name="RightFoot"
[2853] WrapTarget | "Workspace.Itzcardosoo.RightFoot.RightFoot" | Name="RightFoot"
[2854] Attachment | "Workspace.Itzcardosoo.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[2855] Vector3Value | "Workspace.Itzcardosoo.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[2856] Attachment | "Workspace.Itzcardosoo.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[2857] Vector3Value | "Workspace.Itzcardosoo.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[2858] Vector3Value | "Workspace.Itzcardosoo.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[2859] AnimationConstraint | "Workspace.Itzcardosoo.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[2860] BallSocketConstraint | "Workspace.Itzcardosoo.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[2861] MeshPart | "Workspace.Itzcardosoo.RightLowerLeg" | Name="RightLowerLeg"
[2862] WrapTarget | "Workspace.Itzcardosoo.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[2863] Attachment | "Workspace.Itzcardosoo.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[2864] Vector3Value | "Workspace.Itzcardosoo.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[2865] Attachment | "Workspace.Itzcardosoo.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[2866] Vector3Value | "Workspace.Itzcardosoo.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[2867] Vector3Value | "Workspace.Itzcardosoo.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[2868] AnimationConstraint | "Workspace.Itzcardosoo.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[2869] BallSocketConstraint | "Workspace.Itzcardosoo.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[2870] MeshPart | "Workspace.Itzcardosoo.LowerTorso" | Name="LowerTorso"
[2871] WrapTarget | "Workspace.Itzcardosoo.LowerTorso.LowerTorso" | Name="LowerTorso"
[2872] Attachment | "Workspace.Itzcardosoo.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[2873] Vector3Value | "Workspace.Itzcardosoo.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[2874] Attachment | "Workspace.Itzcardosoo.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[2875] Vector3Value | "Workspace.Itzcardosoo.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[2876] Attachment | "Workspace.Itzcardosoo.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[2877] Vector3Value | "Workspace.Itzcardosoo.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[2878] Attachment | "Workspace.Itzcardosoo.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[2879] Vector3Value | "Workspace.Itzcardosoo.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[2880] Attachment | "Workspace.Itzcardosoo.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[2881] Vector3Value | "Workspace.Itzcardosoo.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[2882] Attachment | "Workspace.Itzcardosoo.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[2883] Vector3Value | "Workspace.Itzcardosoo.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[2884] Attachment | "Workspace.Itzcardosoo.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[2885] Vector3Value | "Workspace.Itzcardosoo.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[2886] Vector3Value | "Workspace.Itzcardosoo.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[2887] NoCollisionConstraint | "Workspace.Itzcardosoo.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[2888] NoCollisionConstraint | "Workspace.Itzcardosoo.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[2889] NoCollisionConstraint | "Workspace.Itzcardosoo.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[2890] NoCollisionConstraint | "Workspace.Itzcardosoo.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[2891] AnimationConstraint | "Workspace.Itzcardosoo.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[2892] MeshPart | "Workspace.Itzcardosoo.RightUpperLeg" | Name="RightUpperLeg"
[2893] WrapTarget | "Workspace.Itzcardosoo.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[2894] Attachment | "Workspace.Itzcardosoo.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[2895] Vector3Value | "Workspace.Itzcardosoo.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[2896] Attachment | "Workspace.Itzcardosoo.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[2897] Vector3Value | "Workspace.Itzcardosoo.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[2898] Vector3Value | "Workspace.Itzcardosoo.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[2899] NoCollisionConstraint | "Workspace.Itzcardosoo.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[2900] AnimationConstraint | "Workspace.Itzcardosoo.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[2901] BallSocketConstraint | "Workspace.Itzcardosoo.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[2902] MeshPart | "Workspace.Itzcardosoo.Head" | Name="Head"
[2903] Attachment | "Workspace.Itzcardosoo.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[2904] Vector3Value | "Workspace.Itzcardosoo.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[2905] Attachment | "Workspace.Itzcardosoo.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[2906] Vector3Value | "Workspace.Itzcardosoo.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[2907] Attachment | "Workspace.Itzcardosoo.Head.HairAttachment" | Name="HairAttachment"
[2908] Vector3Value | "Workspace.Itzcardosoo.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[2909] Attachment | "Workspace.Itzcardosoo.Head.HatAttachment" | Name="HatAttachment"
[2910] Vector3Value | "Workspace.Itzcardosoo.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[2911] Attachment | "Workspace.Itzcardosoo.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[2912] Vector3Value | "Workspace.Itzcardosoo.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[2913] Vector3Value | "Workspace.Itzcardosoo.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[2914] WrapTarget | "Workspace.Itzcardosoo.Head.Head" | Name="Head"
[2915] FaceControls | "Workspace.Itzcardosoo.Head.FaceControls" | Name="FaceControls"
[2916] NoCollisionConstraint | "Workspace.Itzcardosoo.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[2917] NoCollisionConstraint | "Workspace.Itzcardosoo.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[2918] NoCollisionConstraint | "Workspace.Itzcardosoo.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[2919] AnimationConstraint | "Workspace.Itzcardosoo.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[2920] BallSocketConstraint | "Workspace.Itzcardosoo.Head.NeckBallSocket" | Name="NeckBallSocket"
[2921] Folder | "Workspace.R1_LockerWorld" | Name="R1_LockerWorld"
[2922] Part | "Workspace.R1_LockerWorld.R1_LockerLight" | Name="R1_LockerLight"
[2923] PointLight | "Workspace.R1_LockerWorld.R1_LockerLight.PointLight" | Name="PointLight"
[2924] Model | "Workspace.R1_LockerWorld.R1_LockerItem" | Name="R1_LockerItem"; attr:R1_RideSkin="Recon"; attr:TPS_Vehicle="Jeep"
[2925] Folder | "Workspace.R1_LockerWorld.R1_LockerItem.Body" | Name="Body"
[2926] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide" | Name="TubSide"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[2927] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide.R1_RideWrap" | Name="R1_RideWrap"
[2928] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide" | Name="TubSide"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[2929] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide.R1_RideWrap" | Name="R1_RideWrap"
[2930] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide" | Name="TubSide"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[2931] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide.R1_RideWrap" | Name="R1_RideWrap"
[2932] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.WheelTub" | Name="WheelTub"
[2933] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.WheelTub" | Name="WheelTub"
[2934] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.BeltCap" | Name="BeltCap"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.31373, 0.10588, 0.090196)
[2935] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.BeltCap.R1_RideWrap" | Name="R1_RideWrap"
[2936] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.BeltCap.R1_RideWrap" | Name="R1_RideWrap"
[2937] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.DoorSeam" | Name="DoorSeam"
[2938] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.DoorSeam" | Name="DoorSeam"
[2939] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.DoorSeam" | Name="DoorSeam"
[2940] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Hinge" | Name="Hinge"
[2941] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Hinge" | Name="Hinge"
[2942] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Handle" | Name="Handle"
[2943] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.RockRail" | Name="RockRail"
[2944] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Mud" | Name="Mud"
[2945] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Mud" | Name="Mud"
[2946] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Rust" | Name="Rust"; attr:R1_RideWasT=0.25
[2947] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Rust" | Name="Rust"; attr:R1_RideWasT=0.30000001192093
[2948] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide" | Name="TubSide"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[2949] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide.R1_RideWrap" | Name="R1_RideWrap"
[2950] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide" | Name="TubSide"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[2951] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide.R1_RideWrap" | Name="R1_RideWrap"
[2952] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide" | Name="TubSide"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[2953] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TubSide.R1_RideWrap" | Name="R1_RideWrap"
[2954] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.WheelTub" | Name="WheelTub"
[2955] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.WheelTub" | Name="WheelTub"
[2956] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.BeltCap" | Name="BeltCap"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.31373, 0.10588, 0.090196)
[2957] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.BeltCap.R1_RideWrap" | Name="R1_RideWrap"
[2958] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.BeltCap.R1_RideWrap" | Name="R1_RideWrap"
[2959] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.DoorSeam" | Name="DoorSeam"
[2960] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.DoorSeam" | Name="DoorSeam"
[2961] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.DoorSeam" | Name="DoorSeam"
[2962] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Hinge" | Name="Hinge"
[2963] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Hinge" | Name="Hinge"
[2964] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Handle" | Name="Handle"
[2965] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.RockRail" | Name="RockRail"
[2966] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Mud" | Name="Mud"
[2967] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Mud" | Name="Mud"
[2968] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Rust" | Name="Rust"; attr:R1_RideWasT=0.25
[2969] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Rust" | Name="Rust"; attr:R1_RideWasT=0.30000001192093
[2970] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Tailgate" | Name="Tailgate"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[2971] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Tailgate.R1_RideWrap" | Name="R1_RideWrap"
[2972] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TailgateSeam" | Name="TailgateSeam"
[2973] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TailgateHandle" | Name="TailgateHandle"
[2974] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Mud" | Name="Mud"
[2975] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Plate" | Name="Plate"; attr:R1_RideWasColor=Color3.new(0.88627, 0.87059, 0.80784)
[2976] SurfaceGui | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Plate.SurfaceGui" | Name="SurfaceGui"
[2977] TextLabel | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Plate.SurfaceGui.TextLabel" | Name="TextLabel"; attr:R1_RideWasTextColor=Color3.new(0.43137, 0.11765, 0.10196); attr:R1_RideWasText="R1 4X4"
[2978] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Underbody" | Name="Underbody"
[2979] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.FrameRail" | Name="FrameRail"
[2980] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.FrameRail" | Name="FrameRail"
[2981] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Axle" | Name="Axle"
[2982] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Axle" | Name="Axle"
[2983] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Diff" | Name="Diff"
[2984] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Cowl" | Name="Cowl"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.31373, 0.10588, 0.090196)
[2985] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Cowl.R1_RideWrap" | Name="R1_RideWrap"
[2986] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Hood" | Name="Hood"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[2987] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Hood.R1_RideWrap" | Name="R1_RideWrap"
[2988] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.HoodBulge" | Name="HoodBulge"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[2989] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.HoodBulge.R1_RideWrap" | Name="R1_RideWrap"
[2990] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Rust" | Name="Rust"; attr:R1_RideWasT=0.25
[2991] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Rust" | Name="Rust"; attr:R1_RideWasT=0.34999999403954
[2992] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.HoodLatch" | Name="HoodLatch"
[2993] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.BaySide" | Name="BaySide"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.31373, 0.10588, 0.090196)
[2994] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.CowlSide" | Name="CowlSide"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.31373, 0.10588, 0.090196)
[2995] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.CowlSide.R1_RideWrap" | Name="R1_RideWrap"
[2996] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.HoodLatch" | Name="HoodLatch"
[2997] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.BaySide" | Name="BaySide"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.31373, 0.10588, 0.090196)
[2998] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.CowlSide" | Name="CowlSide"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.31373, 0.10588, 0.090196)
[2999] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.CowlSide.R1_RideWrap" | Name="R1_RideWrap"
[3000] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Grille" | Name="Grille"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[3001] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Grille.R1_RideWrap" | Name="R1_RideWrap"
[3002] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.GrilleSlot" | Name="GrilleSlot"
[3003] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.GrilleSlot" | Name="GrilleSlot"
[3004] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.GrilleSlot" | Name="GrilleSlot"
[3005] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.GrilleSlot" | Name="GrilleSlot"
[3006] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.GrilleSlot" | Name="GrilleSlot"
[3007] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.GrilleSlot" | Name="GrilleSlot"
[3008] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.GrilleSlot" | Name="GrilleSlot"
[3009] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Mud" | Name="Mud"
[3010] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.HeadlightBezel" | Name="HeadlightBezel"
[3011] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TowHook" | Name="TowHook"
[3012] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.MirrorArm" | Name="MirrorArm"
[3013] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Mirror" | Name="Mirror"
[3014] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.HeadlightBezel" | Name="HeadlightBezel"
[3015] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TowHook" | Name="TowHook"
[3016] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.MirrorArm" | Name="MirrorArm"
[3017] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Mirror" | Name="Mirror"
[3018] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.BumperFront" | Name="BumperFront"
[3019] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.SkidPlate" | Name="SkidPlate"
[3020] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Fender" | Name="Fender"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[3021] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Fender.R1_RideWrap" | Name="R1_RideWrap"
[3022] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Fender.R1_RideWrap" | Name="R1_RideWrap"
[3023] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.FenderLip" | Name="FenderLip"
[3024] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3025] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3026] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3027] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3028] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3029] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3030] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3031] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3032] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Mud" | Name="Mud"
[3033] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.RearFlareTop" | Name="RearFlareTop"
[3034] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3035] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3036] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3037] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3038] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3039] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3040] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3041] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3042] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TaillightFrame" | Name="TaillightFrame"
[3043] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Fender" | Name="Fender"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[3044] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Fender.R1_RideWrap" | Name="R1_RideWrap"
[3045] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Fender.R1_RideWrap" | Name="R1_RideWrap"
[3046] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.FenderLip" | Name="FenderLip"
[3047] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3048] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3049] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3050] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3051] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3052] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3053] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3054] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3055] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Mud" | Name="Mud"
[3056] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.RearFlareTop" | Name="RearFlareTop"
[3057] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3058] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3059] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3060] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3061] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3062] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3063] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3064] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Flare" | Name="Flare"
[3065] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TaillightFrame" | Name="TaillightFrame"
[3066] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.BumperRear" | Name="BumperRear"
[3067] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.SpareMount" | Name="SpareMount"
[3068] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.SpareTire" | Name="SpareTire"
[3069] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.SpareRim" | Name="SpareRim"; attr:R1_RideWasColor=Color3.new(0.21961, 0.22353, 0.23529)
[3070] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.SpareCap" | Name="SpareCap"
[3071] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.SpareSpoke" | Name="SpareSpoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3072] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.SpareSpoke" | Name="SpareSpoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3073] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.SpareSpoke" | Name="SpareSpoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3074] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.SpareSpoke" | Name="SpareSpoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3075] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.SpareSpoke" | Name="SpareSpoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3076] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.WindshieldPillar" | Name="WindshieldPillar"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[3077] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.WindshieldPillar.R1_RideWrap" | Name="R1_RideWrap"
[3078] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.WindshieldPillar" | Name="WindshieldPillar"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[3079] Texture | "Workspace.R1_LockerWorld.R1_LockerItem.Body.WindshieldPillar.R1_RideWrap" | Name="R1_RideWrap"
[3080] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.WindshieldHeader" | Name="WindshieldHeader"; attr:R1_RideWasMaterial="Metal"; attr:R1_RideWasColor=Color3.new(0.40784, 0.13333, 0.1098)
[3081] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Wiper" | Name="Wiper"
[3082] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Wiper" | Name="Wiper"
[3083] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.Roof" | Name="Roof"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.16471, 0.16471, 0.17255)
[3084] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.RoofSeam" | Name="RoofSeam"
[3085] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.RoofSeam" | Name="RoofSeam"
[3086] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.RoofDirt" | Name="RoofDirt"
[3087] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.RoofRail" | Name="RoofRail"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.16471, 0.16471, 0.17255)
[3088] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.PillarB" | Name="PillarB"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.16471, 0.16471, 0.17255)
[3089] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.PillarD" | Name="PillarD"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.16471, 0.16471, 0.17255)
[3090] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.RoofRail" | Name="RoofRail"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.16471, 0.16471, 0.17255)
[3091] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.PillarB" | Name="PillarB"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.16471, 0.16471, 0.17255)
[3092] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.PillarD" | Name="PillarD"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.16471, 0.16471, 0.17255)
[3093] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TopBack" | Name="TopBack"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.16471, 0.16471, 0.17255)
[3094] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Body.TopBackHeader" | Name="TopBackHeader"; attr:R1_RideWasMaterial="SmoothPlastic"; attr:R1_RideWasColor=Color3.new(0.16471, 0.16471, 0.17255)
[3095] Folder | "Workspace.R1_LockerWorld.R1_LockerItem.Glass" | Name="Glass"
[3096] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Glass.Windshield" | Name="Windshield"
[3097] WedgePart | "Workspace.R1_LockerWorld.R1_LockerItem.Glass.SideGlass" | Name="SideGlass"
[3098] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Glass.SideGlass" | Name="SideGlass"
[3099] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Glass.SideGlass" | Name="SideGlass"
[3100] WedgePart | "Workspace.R1_LockerWorld.R1_LockerItem.Glass.SideGlass" | Name="SideGlass"
[3101] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Glass.SideGlass" | Name="SideGlass"
[3102] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Glass.SideGlass" | Name="SideGlass"
[3103] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Glass.RearWindow" | Name="RearWindow"
[3104] Folder | "Workspace.R1_LockerWorld.R1_LockerItem.Interior" | Name="Interior"
[3105] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.Floor" | Name="Floor"
[3106] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.Dashboard" | Name="Dashboard"
[3107] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.DashTop" | Name="DashTop"
[3108] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.Console" | Name="Console"
[3109] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.Shifter" | Name="Shifter"
[3110] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SteeringColumn" | Name="SteeringColumn"
[3111] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SteeringWheel" | Name="SteeringWheel"
[3112] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SeatBase" | Name="SeatBase"
[3113] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SeatCushion" | Name="SeatCushion"
[3114] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SeatBack" | Name="SeatBack"
[3115] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.Headrest" | Name="Headrest"
[3116] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SeatBase" | Name="SeatBase"
[3117] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SeatCushion" | Name="SeatCushion"
[3118] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SeatBack" | Name="SeatBack"
[3119] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.Headrest" | Name="Headrest"
[3120] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.RearBase" | Name="RearBase"
[3121] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.RearCushion" | Name="RearCushion"
[3122] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.RearBack" | Name="RearBack"
[3123] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SportBar" | Name="SportBar"
[3124] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SportBar" | Name="SportBar"
[3125] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Interior.SportBarTop" | Name="SportBarTop"
[3126] Folder | "Workspace.R1_LockerWorld.R1_LockerItem.Lights" | Name="Lights"
[3127] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Lights.Headlight" | Name="Headlight"
[3128] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Lights.Indicator" | Name="Indicator"
[3129] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Lights.Headlight" | Name="Headlight"
[3130] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Lights.Indicator" | Name="Indicator"
[3131] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Lights.Taillight" | Name="Taillight"
[3132] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Lights.Taillight" | Name="Taillight"
[3133] Folder | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels" | Name="Wheels"
[3134] Model | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR" | Name="Wheel_RR"
[3135] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3136] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3137] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3138] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3139] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3140] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3141] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3142] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3143] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Tire" | Name="Tire"
[3144] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Rim" | Name="Rim"; attr:R1_RideWasColor=Color3.new(0.21961, 0.22353, 0.23529)
[3145] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Cap" | Name="Cap"
[3146] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3147] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3148] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3149] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3150] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3151] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3152] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3153] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3154] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3155] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3156] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3157] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3158] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RR.Lug" | Name="Lug"
[3159] Model | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL" | Name="Wheel_RL"
[3160] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Tire" | Name="Tire"
[3161] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Rim" | Name="Rim"; attr:R1_RideWasColor=Color3.new(0.21961, 0.22353, 0.23529)
[3162] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Cap" | Name="Cap"
[3163] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3164] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3165] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3166] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3167] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3168] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3169] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3170] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3171] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3172] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3173] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3174] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3175] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3176] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3177] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3178] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3179] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3180] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3181] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3182] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3183] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_RL.Lug" | Name="Lug"
[3184] Model | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR" | Name="Wheel_FR"
[3185] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Tire" | Name="Tire"
[3186] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Rim" | Name="Rim"; attr:R1_RideWasColor=Color3.new(0.21961, 0.22353, 0.23529)
[3187] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Cap" | Name="Cap"
[3188] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3189] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3190] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3191] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3192] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3193] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3194] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3195] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3196] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3197] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3198] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3199] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3200] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3201] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3202] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3203] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3204] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3205] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3206] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3207] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3208] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FR.Lug" | Name="Lug"
[3209] Model | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL" | Name="Wheel_FL"
[3210] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Tire" | Name="Tire"
[3211] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Rim" | Name="Rim"; attr:R1_RideWasColor=Color3.new(0.21961, 0.22353, 0.23529)
[3212] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Cap" | Name="Cap"
[3213] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3214] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3215] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3216] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3217] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Spoke" | Name="Spoke"; attr:R1_RideWasColor=Color3.new(0.3451, 0.35294, 0.36863)
[3218] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3219] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3220] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3221] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3222] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3223] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3224] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3225] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3226] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3227] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3228] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3229] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3230] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3231] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3232] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3233] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Wheels.Wheel_FL.Lug" | Name="Lug"
[3234] Part | "Workspace.R1_LockerWorld.R1_LockerItem.Chassis" | Name="Chassis"
[3235] Part | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker" | Name="R1_RideSticker"
[3236] Decal | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker.Decal" | Name="Decal"
[3237] WeldConstraint | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker.WeldConstraint" | Name="WeldConstraint"
[3238] Part | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker" | Name="R1_RideSticker"
[3239] Decal | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker.Decal" | Name="Decal"
[3240] WeldConstraint | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker.WeldConstraint" | Name="WeldConstraint"
[3241] Part | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker" | Name="R1_RideSticker"
[3242] Decal | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker.Decal" | Name="Decal"
[3243] WeldConstraint | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker.WeldConstraint" | Name="WeldConstraint"
[3244] Part | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker" | Name="R1_RideSticker"
[3245] Decal | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker.Decal" | Name="Decal"
[3246] WeldConstraint | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker.WeldConstraint" | Name="WeldConstraint"
[3247] Part | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker" | Name="R1_RideSticker"
[3248] Decal | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker.Decal" | Name="Decal"
[3249] WeldConstraint | "Workspace.R1_LockerWorld.R1_LockerItem.R1_RideSticker.WeldConstraint" | Name="WeldConstraint"
[3250] Model | "Workspace.JTjustME34" | Name="JTjustME34"; attr:TPS_Weapon="AR15"
[3251] Part | "Workspace.JTjustME34.HumanoidRootPart" | Name="HumanoidRootPart"
[3252] Attachment | "Workspace.JTjustME34.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[3253] Vector3Value | "Workspace.JTjustME34.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[3254] Vector3Value | "Workspace.JTjustME34.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[3255] Attachment | "Workspace.JTjustME34.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[3256] Sound | "Workspace.JTjustME34.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[3257] Sound | "Workspace.JTjustME34.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[3258] Sound | "Workspace.JTjustME34.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[3259] Sound | "Workspace.JTjustME34.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[3260] Sound | "Workspace.JTjustME34.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[3261] Sound | "Workspace.JTjustME34.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[3262] Sound | "Workspace.JTjustME34.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[3263] Sound | "Workspace.JTjustME34.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[3264] Sound | "Workspace.JTjustME34.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[3265] MeshPart | "Workspace.JTjustME34.LeftHand" | Name="LeftHand"
[3266] WrapTarget | "Workspace.JTjustME34.LeftHand.LeftHand" | Name="LeftHand"
[3267] Attachment | "Workspace.JTjustME34.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[3268] Vector3Value | "Workspace.JTjustME34.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[3269] Attachment | "Workspace.JTjustME34.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[3270] Vector3Value | "Workspace.JTjustME34.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[3271] Vector3Value | "Workspace.JTjustME34.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[3272] AnimationConstraint | "Workspace.JTjustME34.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[3273] BallSocketConstraint | "Workspace.JTjustME34.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[3274] MeshPart | "Workspace.JTjustME34.RightHand" | Name="RightHand"
[3275] WrapTarget | "Workspace.JTjustME34.RightHand.RightHand" | Name="RightHand"
[3276] Attachment | "Workspace.JTjustME34.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[3277] Vector3Value | "Workspace.JTjustME34.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[3278] Attachment | "Workspace.JTjustME34.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[3279] Vector3Value | "Workspace.JTjustME34.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[3280] Vector3Value | "Workspace.JTjustME34.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[3281] AnimationConstraint | "Workspace.JTjustME34.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[3282] BallSocketConstraint | "Workspace.JTjustME34.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[3283] MeshPart | "Workspace.JTjustME34.LeftLowerArm" | Name="LeftLowerArm"
[3284] WrapTarget | "Workspace.JTjustME34.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[3285] Attachment | "Workspace.JTjustME34.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[3286] Vector3Value | "Workspace.JTjustME34.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[3287] Attachment | "Workspace.JTjustME34.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[3288] Vector3Value | "Workspace.JTjustME34.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[3289] Vector3Value | "Workspace.JTjustME34.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[3290] AnimationConstraint | "Workspace.JTjustME34.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[3291] BallSocketConstraint | "Workspace.JTjustME34.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[3292] MeshPart | "Workspace.JTjustME34.RightLowerArm" | Name="RightLowerArm"
[3293] WrapTarget | "Workspace.JTjustME34.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[3294] Attachment | "Workspace.JTjustME34.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[3295] Vector3Value | "Workspace.JTjustME34.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[3296] Attachment | "Workspace.JTjustME34.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[3297] Vector3Value | "Workspace.JTjustME34.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[3298] Vector3Value | "Workspace.JTjustME34.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[3299] AnimationConstraint | "Workspace.JTjustME34.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[3300] BallSocketConstraint | "Workspace.JTjustME34.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[3301] MeshPart | "Workspace.JTjustME34.LeftUpperArm" | Name="LeftUpperArm"
[3302] WrapTarget | "Workspace.JTjustME34.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[3303] Attachment | "Workspace.JTjustME34.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[3304] Vector3Value | "Workspace.JTjustME34.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[3305] Attachment | "Workspace.JTjustME34.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3306] Attachment | "Workspace.JTjustME34.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[3307] Vector3Value | "Workspace.JTjustME34.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[3308] Attachment | "Workspace.JTjustME34.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[3309] Vector3Value | "Workspace.JTjustME34.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[3310] Vector3Value | "Workspace.JTjustME34.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[3311] NoCollisionConstraint | "Workspace.JTjustME34.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[3312] AnimationConstraint | "Workspace.JTjustME34.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[3313] BallSocketConstraint | "Workspace.JTjustME34.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[3314] MeshPart | "Workspace.JTjustME34.RightUpperArm" | Name="RightUpperArm"
[3315] WrapTarget | "Workspace.JTjustME34.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[3316] Attachment | "Workspace.JTjustME34.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[3317] Vector3Value | "Workspace.JTjustME34.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[3318] Attachment | "Workspace.JTjustME34.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3319] Attachment | "Workspace.JTjustME34.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[3320] Vector3Value | "Workspace.JTjustME34.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[3321] Attachment | "Workspace.JTjustME34.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[3322] Vector3Value | "Workspace.JTjustME34.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[3323] Vector3Value | "Workspace.JTjustME34.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[3324] NoCollisionConstraint | "Workspace.JTjustME34.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[3325] AnimationConstraint | "Workspace.JTjustME34.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[3326] BallSocketConstraint | "Workspace.JTjustME34.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[3327] MeshPart | "Workspace.JTjustME34.LeftFoot" | Name="LeftFoot"
[3328] WrapTarget | "Workspace.JTjustME34.LeftFoot.LeftFoot" | Name="LeftFoot"
[3329] Attachment | "Workspace.JTjustME34.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[3330] Vector3Value | "Workspace.JTjustME34.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[3331] Attachment | "Workspace.JTjustME34.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[3332] Vector3Value | "Workspace.JTjustME34.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[3333] Vector3Value | "Workspace.JTjustME34.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[3334] AnimationConstraint | "Workspace.JTjustME34.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[3335] BallSocketConstraint | "Workspace.JTjustME34.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[3336] MeshPart | "Workspace.JTjustME34.LeftLowerLeg" | Name="LeftLowerLeg"
[3337] WrapTarget | "Workspace.JTjustME34.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[3338] Attachment | "Workspace.JTjustME34.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[3339] Vector3Value | "Workspace.JTjustME34.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[3340] Attachment | "Workspace.JTjustME34.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[3341] Vector3Value | "Workspace.JTjustME34.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[3342] Vector3Value | "Workspace.JTjustME34.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[3343] AnimationConstraint | "Workspace.JTjustME34.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[3344] BallSocketConstraint | "Workspace.JTjustME34.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[3345] MeshPart | "Workspace.JTjustME34.UpperTorso" | Name="UpperTorso"
[3346] WrapTarget | "Workspace.JTjustME34.UpperTorso.UpperTorso" | Name="UpperTorso"
[3347] Attachment | "Workspace.JTjustME34.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[3348] Vector3Value | "Workspace.JTjustME34.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[3349] Attachment | "Workspace.JTjustME34.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[3350] Vector3Value | "Workspace.JTjustME34.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[3351] Attachment | "Workspace.JTjustME34.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[3352] Vector3Value | "Workspace.JTjustME34.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[3353] Attachment | "Workspace.JTjustME34.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3354] Attachment | "Workspace.JTjustME34.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[3355] Vector3Value | "Workspace.JTjustME34.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[3356] Attachment | "Workspace.JTjustME34.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3357] Attachment | "Workspace.JTjustME34.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[3358] Vector3Value | "Workspace.JTjustME34.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[3359] Attachment | "Workspace.JTjustME34.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[3360] Vector3Value | "Workspace.JTjustME34.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[3361] Attachment | "Workspace.JTjustME34.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[3362] Vector3Value | "Workspace.JTjustME34.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[3363] Attachment | "Workspace.JTjustME34.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[3364] Vector3Value | "Workspace.JTjustME34.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[3365] Attachment | "Workspace.JTjustME34.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[3366] Vector3Value | "Workspace.JTjustME34.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[3367] Vector3Value | "Workspace.JTjustME34.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[3368] NoCollisionConstraint | "Workspace.JTjustME34.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[3369] NoCollisionConstraint | "Workspace.JTjustME34.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[3370] NoCollisionConstraint | "Workspace.JTjustME34.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[3371] NoCollisionConstraint | "Workspace.JTjustME34.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[3372] NoCollisionConstraint | "Workspace.JTjustME34.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[3373] NoCollisionConstraint | "Workspace.JTjustME34.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[3374] NoCollisionConstraint | "Workspace.JTjustME34.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[3375] AnimationConstraint | "Workspace.JTjustME34.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[3376] BallSocketConstraint | "Workspace.JTjustME34.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[3377] MeshPart | "Workspace.JTjustME34.LeftUpperLeg" | Name="LeftUpperLeg"
[3378] WrapTarget | "Workspace.JTjustME34.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[3379] Attachment | "Workspace.JTjustME34.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[3380] Vector3Value | "Workspace.JTjustME34.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[3381] Attachment | "Workspace.JTjustME34.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[3382] Vector3Value | "Workspace.JTjustME34.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[3383] Vector3Value | "Workspace.JTjustME34.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[3384] NoCollisionConstraint | "Workspace.JTjustME34.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[3385] NoCollisionConstraint | "Workspace.JTjustME34.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[3386] AnimationConstraint | "Workspace.JTjustME34.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[3387] BallSocketConstraint | "Workspace.JTjustME34.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[3388] MeshPart | "Workspace.JTjustME34.RightFoot" | Name="RightFoot"
[3389] WrapTarget | "Workspace.JTjustME34.RightFoot.RightFoot" | Name="RightFoot"
[3390] Attachment | "Workspace.JTjustME34.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[3391] Vector3Value | "Workspace.JTjustME34.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[3392] Attachment | "Workspace.JTjustME34.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[3393] Vector3Value | "Workspace.JTjustME34.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[3394] Vector3Value | "Workspace.JTjustME34.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[3395] AnimationConstraint | "Workspace.JTjustME34.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[3396] BallSocketConstraint | "Workspace.JTjustME34.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[3397] MeshPart | "Workspace.JTjustME34.RightLowerLeg" | Name="RightLowerLeg"
[3398] WrapTarget | "Workspace.JTjustME34.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[3399] Attachment | "Workspace.JTjustME34.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[3400] Vector3Value | "Workspace.JTjustME34.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[3401] Attachment | "Workspace.JTjustME34.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[3402] Vector3Value | "Workspace.JTjustME34.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[3403] Vector3Value | "Workspace.JTjustME34.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[3404] AnimationConstraint | "Workspace.JTjustME34.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[3405] BallSocketConstraint | "Workspace.JTjustME34.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[3406] MeshPart | "Workspace.JTjustME34.LowerTorso" | Name="LowerTorso"
[3407] WrapTarget | "Workspace.JTjustME34.LowerTorso.LowerTorso" | Name="LowerTorso"
[3408] Attachment | "Workspace.JTjustME34.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[3409] Vector3Value | "Workspace.JTjustME34.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[3410] Attachment | "Workspace.JTjustME34.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[3411] Vector3Value | "Workspace.JTjustME34.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[3412] Attachment | "Workspace.JTjustME34.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[3413] Vector3Value | "Workspace.JTjustME34.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[3414] Attachment | "Workspace.JTjustME34.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[3415] Vector3Value | "Workspace.JTjustME34.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[3416] Attachment | "Workspace.JTjustME34.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[3417] Vector3Value | "Workspace.JTjustME34.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[3418] Attachment | "Workspace.JTjustME34.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[3419] Vector3Value | "Workspace.JTjustME34.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[3420] Attachment | "Workspace.JTjustME34.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[3421] Vector3Value | "Workspace.JTjustME34.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[3422] Vector3Value | "Workspace.JTjustME34.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[3423] NoCollisionConstraint | "Workspace.JTjustME34.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[3424] NoCollisionConstraint | "Workspace.JTjustME34.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[3425] NoCollisionConstraint | "Workspace.JTjustME34.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[3426] NoCollisionConstraint | "Workspace.JTjustME34.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[3427] AnimationConstraint | "Workspace.JTjustME34.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[3428] MeshPart | "Workspace.JTjustME34.RightUpperLeg" | Name="RightUpperLeg"
[3429] WrapTarget | "Workspace.JTjustME34.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[3430] Attachment | "Workspace.JTjustME34.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[3431] Vector3Value | "Workspace.JTjustME34.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[3432] Attachment | "Workspace.JTjustME34.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[3433] Vector3Value | "Workspace.JTjustME34.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[3434] Vector3Value | "Workspace.JTjustME34.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[3435] NoCollisionConstraint | "Workspace.JTjustME34.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[3436] AnimationConstraint | "Workspace.JTjustME34.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[3437] BallSocketConstraint | "Workspace.JTjustME34.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[3438] Humanoid | "Workspace.JTjustME34.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[3439] Status | "Workspace.JTjustME34.Humanoid.Status" | Name="Status"
[3440] Animator | "Workspace.JTjustME34.Humanoid.Animator" | Name="Animator"
[3441] MeshPart | "Workspace.JTjustME34.Head" | Name="Head"
[3442] Attachment | "Workspace.JTjustME34.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[3443] Vector3Value | "Workspace.JTjustME34.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[3444] Attachment | "Workspace.JTjustME34.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[3445] Vector3Value | "Workspace.JTjustME34.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[3446] Attachment | "Workspace.JTjustME34.Head.HairAttachment" | Name="HairAttachment"
[3447] Vector3Value | "Workspace.JTjustME34.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[3448] Attachment | "Workspace.JTjustME34.Head.HatAttachment" | Name="HatAttachment"
[3449] Vector3Value | "Workspace.JTjustME34.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[3450] Attachment | "Workspace.JTjustME34.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[3451] Vector3Value | "Workspace.JTjustME34.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[3452] Vector3Value | "Workspace.JTjustME34.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[3453] WrapTarget | "Workspace.JTjustME34.Head.Head" | Name="Head"
[3454] FaceControls | "Workspace.JTjustME34.Head.FaceControls" | Name="FaceControls"
[3455] NoCollisionConstraint | "Workspace.JTjustME34.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[3456] NoCollisionConstraint | "Workspace.JTjustME34.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[3457] NoCollisionConstraint | "Workspace.JTjustME34.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[3458] AnimationConstraint | "Workspace.JTjustME34.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[3459] BallSocketConstraint | "Workspace.JTjustME34.Head.NeckBallSocket" | Name="NeckBallSocket"
[3460] Script | "Workspace.JTjustME34.Health" | Name="Health"
[3461] LocalScript | "Workspace.JTjustME34.Animate" | Name="Animate"
[3462] StringValue | "Workspace.JTjustME34.Animate.cheer" | Name="cheer"; Value=""
[3463] Animation | "Workspace.JTjustME34.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[3464] StringValue | "Workspace.JTjustME34.Animate.climb" | Name="climb"; Value=""
[3465] Animation | "Workspace.JTjustME34.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[3466] StringValue | "Workspace.JTjustME34.Animate.dance" | Name="dance"; Value=""
[3467] Animation | "Workspace.JTjustME34.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[3468] NumberValue | "Workspace.JTjustME34.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[3469] Animation | "Workspace.JTjustME34.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[3470] NumberValue | "Workspace.JTjustME34.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[3471] Animation | "Workspace.JTjustME34.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[3472] NumberValue | "Workspace.JTjustME34.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[3473] StringValue | "Workspace.JTjustME34.Animate.dance2" | Name="dance2"; Value=""
[3474] Animation | "Workspace.JTjustME34.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[3475] NumberValue | "Workspace.JTjustME34.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[3476] Animation | "Workspace.JTjustME34.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[3477] NumberValue | "Workspace.JTjustME34.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[3478] Animation | "Workspace.JTjustME34.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[3479] NumberValue | "Workspace.JTjustME34.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[3480] StringValue | "Workspace.JTjustME34.Animate.dance3" | Name="dance3"; Value=""
[3481] Animation | "Workspace.JTjustME34.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[3482] NumberValue | "Workspace.JTjustME34.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[3483] Animation | "Workspace.JTjustME34.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[3484] NumberValue | "Workspace.JTjustME34.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[3485] Animation | "Workspace.JTjustME34.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[3486] NumberValue | "Workspace.JTjustME34.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[3487] StringValue | "Workspace.JTjustME34.Animate.fall" | Name="fall"; Value=""
[3488] Animation | "Workspace.JTjustME34.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[3489] StringValue | "Workspace.JTjustME34.Animate.idle" | Name="idle"; Value=""
[3490] Animation | "Workspace.JTjustME34.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[3491] NumberValue | "Workspace.JTjustME34.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[3492] Animation | "Workspace.JTjustME34.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[3493] NumberValue | "Workspace.JTjustME34.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[3494] StringValue | "Workspace.JTjustME34.Animate.jump" | Name="jump"; Value=""
[3495] Animation | "Workspace.JTjustME34.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[3496] StringValue | "Workspace.JTjustME34.Animate.laugh" | Name="laugh"; Value=""
[3497] Animation | "Workspace.JTjustME34.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[3498] StringValue | "Workspace.JTjustME34.Animate.point" | Name="point"; Value=""
[3499] Animation | "Workspace.JTjustME34.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[3500] StringValue | "Workspace.JTjustME34.Animate.sit" | Name="sit"; Value=""
[3501] Animation | "Workspace.JTjustME34.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[3502] StringValue | "Workspace.JTjustME34.Animate.toollunge" | Name="toollunge"; Value=""
[3503] Animation | "Workspace.JTjustME34.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[3504] StringValue | "Workspace.JTjustME34.Animate.toolnone" | Name="toolnone"; Value=""
[3505] Animation | "Workspace.JTjustME34.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[3506] StringValue | "Workspace.JTjustME34.Animate.toolslash" | Name="toolslash"; Value=""
[3507] Animation | "Workspace.JTjustME34.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[3508] StringValue | "Workspace.JTjustME34.Animate.wave" | Name="wave"; Value=""
[3509] Animation | "Workspace.JTjustME34.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[3510] NumberValue | "Workspace.JTjustME34.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[3511] StringValue | "Workspace.JTjustME34.Animate.run" | Name="run"; Value=""
[3512] Animation | "Workspace.JTjustME34.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[3513] StringValue | "Workspace.JTjustME34.Animate.swim" | Name="swim"; Value=""
[3514] Animation | "Workspace.JTjustME34.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[3515] StringValue | "Workspace.JTjustME34.Animate.swimidle" | Name="swimidle"; Value=""
[3516] Animation | "Workspace.JTjustME34.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[3517] StringValue | "Workspace.JTjustME34.Animate.walk" | Name="walk"; Value=""
[3518] Animation | "Workspace.JTjustME34.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[3519] BindableFunction | "Workspace.JTjustME34.Animate.PlayEmote" | Name="PlayEmote"
[3520] StringValue | "Workspace.JTjustME34.Animate.mood" | Name="mood"; Value=""
[3521] Animation | "Workspace.JTjustME34.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[3522] AudioEmitter | "Workspace.JTjustME34.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[3523] Wire | "Workspace.JTjustME34.AudioEmitter.Wire" | Name="Wire"
[3524] Model | "Workspace.JTjustME34.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Hazard"; attr:TPS_WeaponId="AR15"
[3525] Part | "Workspace.JTjustME34.TPS_HeldWeapon.Handle" | Name="Handle"
[3526] Attachment | "Workspace.JTjustME34.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[3527] Attachment | "Workspace.JTjustME34.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[3528] Attachment | "Workspace.JTjustME34.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[3529] Motor6D | "Workspace.JTjustME34.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[3530] Part | "Workspace.JTjustME34.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"; attr:R1_SkinHidden=true
[3531] SpecialMesh | "Workspace.JTjustME34.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[3532] WeldConstraint | "Workspace.JTjustME34.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[3533] Part | "Workspace.JTjustME34.TPS_HeldWeapon.Magazine" | Name="Magazine"
[3534] Weld | "Workspace.JTjustME34.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[3535] Attachment | "Workspace.JTjustME34.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[3536] MeshPart | "Workspace.JTjustME34.TPS_HeldWeapon.R1_SkinBody" | Name="R1_SkinBody"
[3537] WeldConstraint | "Workspace.JTjustME34.TPS_HeldWeapon.R1_SkinBody.WeldConstraint" | Name="WeldConstraint"
[3538] Model | "Workspace.KazFLBG" | Name="KazFLBG"; attr:TPS_Weapon="AR15"
[3539] Part | "Workspace.KazFLBG.HumanoidRootPart" | Name="HumanoidRootPart"
[3540] Attachment | "Workspace.KazFLBG.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[3541] Vector3Value | "Workspace.KazFLBG.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[3542] Vector3Value | "Workspace.KazFLBG.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[3543] Attachment | "Workspace.KazFLBG.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[3544] Sound | "Workspace.KazFLBG.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[3545] Sound | "Workspace.KazFLBG.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[3546] Sound | "Workspace.KazFLBG.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[3547] Sound | "Workspace.KazFLBG.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[3548] Sound | "Workspace.KazFLBG.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[3549] Sound | "Workspace.KazFLBG.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[3550] Sound | "Workspace.KazFLBG.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[3551] Sound | "Workspace.KazFLBG.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[3552] Sound | "Workspace.KazFLBG.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[3553] MeshPart | "Workspace.KazFLBG.LeftHand" | Name="LeftHand"
[3554] WrapTarget | "Workspace.KazFLBG.LeftHand.LeftHand" | Name="LeftHand"
[3555] Attachment | "Workspace.KazFLBG.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[3556] Vector3Value | "Workspace.KazFLBG.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[3557] Attachment | "Workspace.KazFLBG.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[3558] Vector3Value | "Workspace.KazFLBG.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[3559] Vector3Value | "Workspace.KazFLBG.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[3560] AnimationConstraint | "Workspace.KazFLBG.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[3561] BallSocketConstraint | "Workspace.KazFLBG.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[3562] MeshPart | "Workspace.KazFLBG.RightHand" | Name="RightHand"
[3563] WrapTarget | "Workspace.KazFLBG.RightHand.RightHand" | Name="RightHand"
[3564] Attachment | "Workspace.KazFLBG.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[3565] Vector3Value | "Workspace.KazFLBG.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[3566] Attachment | "Workspace.KazFLBG.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[3567] Vector3Value | "Workspace.KazFLBG.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[3568] Vector3Value | "Workspace.KazFLBG.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[3569] AnimationConstraint | "Workspace.KazFLBG.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[3570] BallSocketConstraint | "Workspace.KazFLBG.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[3571] MeshPart | "Workspace.KazFLBG.LeftLowerArm" | Name="LeftLowerArm"
[3572] WrapTarget | "Workspace.KazFLBG.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[3573] Attachment | "Workspace.KazFLBG.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[3574] Vector3Value | "Workspace.KazFLBG.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[3575] Attachment | "Workspace.KazFLBG.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[3576] Vector3Value | "Workspace.KazFLBG.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[3577] Vector3Value | "Workspace.KazFLBG.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[3578] AnimationConstraint | "Workspace.KazFLBG.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[3579] BallSocketConstraint | "Workspace.KazFLBG.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[3580] MeshPart | "Workspace.KazFLBG.RightLowerArm" | Name="RightLowerArm"
[3581] WrapTarget | "Workspace.KazFLBG.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[3582] Attachment | "Workspace.KazFLBG.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[3583] Vector3Value | "Workspace.KazFLBG.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[3584] Attachment | "Workspace.KazFLBG.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[3585] Vector3Value | "Workspace.KazFLBG.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[3586] Vector3Value | "Workspace.KazFLBG.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[3587] AnimationConstraint | "Workspace.KazFLBG.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[3588] BallSocketConstraint | "Workspace.KazFLBG.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[3589] MeshPart | "Workspace.KazFLBG.LeftUpperArm" | Name="LeftUpperArm"
[3590] WrapTarget | "Workspace.KazFLBG.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[3591] Attachment | "Workspace.KazFLBG.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[3592] Vector3Value | "Workspace.KazFLBG.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[3593] Attachment | "Workspace.KazFLBG.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3594] Attachment | "Workspace.KazFLBG.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[3595] Vector3Value | "Workspace.KazFLBG.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[3596] Attachment | "Workspace.KazFLBG.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[3597] Vector3Value | "Workspace.KazFLBG.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[3598] Vector3Value | "Workspace.KazFLBG.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[3599] NoCollisionConstraint | "Workspace.KazFLBG.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[3600] AnimationConstraint | "Workspace.KazFLBG.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[3601] BallSocketConstraint | "Workspace.KazFLBG.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[3602] MeshPart | "Workspace.KazFLBG.RightUpperArm" | Name="RightUpperArm"
[3603] WrapTarget | "Workspace.KazFLBG.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[3604] Attachment | "Workspace.KazFLBG.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[3605] Vector3Value | "Workspace.KazFLBG.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[3606] Attachment | "Workspace.KazFLBG.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3607] Attachment | "Workspace.KazFLBG.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[3608] Vector3Value | "Workspace.KazFLBG.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[3609] Attachment | "Workspace.KazFLBG.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[3610] Vector3Value | "Workspace.KazFLBG.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[3611] Vector3Value | "Workspace.KazFLBG.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[3612] NoCollisionConstraint | "Workspace.KazFLBG.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[3613] AnimationConstraint | "Workspace.KazFLBG.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[3614] BallSocketConstraint | "Workspace.KazFLBG.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[3615] MeshPart | "Workspace.KazFLBG.LeftFoot" | Name="LeftFoot"
[3616] WrapTarget | "Workspace.KazFLBG.LeftFoot.LeftFoot" | Name="LeftFoot"
[3617] Attachment | "Workspace.KazFLBG.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[3618] Vector3Value | "Workspace.KazFLBG.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[3619] Attachment | "Workspace.KazFLBG.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[3620] Vector3Value | "Workspace.KazFLBG.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[3621] Vector3Value | "Workspace.KazFLBG.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[3622] AnimationConstraint | "Workspace.KazFLBG.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[3623] BallSocketConstraint | "Workspace.KazFLBG.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[3624] MeshPart | "Workspace.KazFLBG.LeftLowerLeg" | Name="LeftLowerLeg"
[3625] WrapTarget | "Workspace.KazFLBG.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[3626] Attachment | "Workspace.KazFLBG.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[3627] Vector3Value | "Workspace.KazFLBG.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[3628] Attachment | "Workspace.KazFLBG.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[3629] Vector3Value | "Workspace.KazFLBG.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[3630] Vector3Value | "Workspace.KazFLBG.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[3631] AnimationConstraint | "Workspace.KazFLBG.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[3632] BallSocketConstraint | "Workspace.KazFLBG.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[3633] MeshPart | "Workspace.KazFLBG.UpperTorso" | Name="UpperTorso"
[3634] WrapTarget | "Workspace.KazFLBG.UpperTorso.UpperTorso" | Name="UpperTorso"
[3635] Attachment | "Workspace.KazFLBG.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[3636] Vector3Value | "Workspace.KazFLBG.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[3637] Attachment | "Workspace.KazFLBG.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[3638] Vector3Value | "Workspace.KazFLBG.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[3639] Attachment | "Workspace.KazFLBG.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[3640] Vector3Value | "Workspace.KazFLBG.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[3641] Attachment | "Workspace.KazFLBG.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3642] Attachment | "Workspace.KazFLBG.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[3643] Vector3Value | "Workspace.KazFLBG.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[3644] Attachment | "Workspace.KazFLBG.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3645] Attachment | "Workspace.KazFLBG.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[3646] Vector3Value | "Workspace.KazFLBG.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[3647] Attachment | "Workspace.KazFLBG.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[3648] Vector3Value | "Workspace.KazFLBG.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[3649] Attachment | "Workspace.KazFLBG.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[3650] Vector3Value | "Workspace.KazFLBG.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[3651] Attachment | "Workspace.KazFLBG.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[3652] Vector3Value | "Workspace.KazFLBG.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[3653] Attachment | "Workspace.KazFLBG.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[3654] Vector3Value | "Workspace.KazFLBG.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[3655] Vector3Value | "Workspace.KazFLBG.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[3656] NoCollisionConstraint | "Workspace.KazFLBG.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[3657] NoCollisionConstraint | "Workspace.KazFLBG.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[3658] NoCollisionConstraint | "Workspace.KazFLBG.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[3659] NoCollisionConstraint | "Workspace.KazFLBG.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[3660] NoCollisionConstraint | "Workspace.KazFLBG.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[3661] NoCollisionConstraint | "Workspace.KazFLBG.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[3662] NoCollisionConstraint | "Workspace.KazFLBG.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[3663] AnimationConstraint | "Workspace.KazFLBG.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[3664] BallSocketConstraint | "Workspace.KazFLBG.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[3665] MeshPart | "Workspace.KazFLBG.LeftUpperLeg" | Name="LeftUpperLeg"
[3666] WrapTarget | "Workspace.KazFLBG.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[3667] Attachment | "Workspace.KazFLBG.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[3668] Vector3Value | "Workspace.KazFLBG.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[3669] Attachment | "Workspace.KazFLBG.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[3670] Vector3Value | "Workspace.KazFLBG.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[3671] Vector3Value | "Workspace.KazFLBG.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[3672] NoCollisionConstraint | "Workspace.KazFLBG.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[3673] NoCollisionConstraint | "Workspace.KazFLBG.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[3674] AnimationConstraint | "Workspace.KazFLBG.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[3675] BallSocketConstraint | "Workspace.KazFLBG.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[3676] MeshPart | "Workspace.KazFLBG.RightFoot" | Name="RightFoot"
[3677] WrapTarget | "Workspace.KazFLBG.RightFoot.RightFoot" | Name="RightFoot"
[3678] Attachment | "Workspace.KazFLBG.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[3679] Vector3Value | "Workspace.KazFLBG.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[3680] Attachment | "Workspace.KazFLBG.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[3681] Vector3Value | "Workspace.KazFLBG.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[3682] Vector3Value | "Workspace.KazFLBG.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[3683] AnimationConstraint | "Workspace.KazFLBG.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[3684] BallSocketConstraint | "Workspace.KazFLBG.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[3685] MeshPart | "Workspace.KazFLBG.RightLowerLeg" | Name="RightLowerLeg"
[3686] WrapTarget | "Workspace.KazFLBG.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[3687] Attachment | "Workspace.KazFLBG.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[3688] Vector3Value | "Workspace.KazFLBG.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[3689] Attachment | "Workspace.KazFLBG.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[3690] Vector3Value | "Workspace.KazFLBG.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[3691] Vector3Value | "Workspace.KazFLBG.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[3692] AnimationConstraint | "Workspace.KazFLBG.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[3693] BallSocketConstraint | "Workspace.KazFLBG.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[3694] MeshPart | "Workspace.KazFLBG.LowerTorso" | Name="LowerTorso"
[3695] WrapTarget | "Workspace.KazFLBG.LowerTorso.LowerTorso" | Name="LowerTorso"
[3696] Attachment | "Workspace.KazFLBG.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[3697] Vector3Value | "Workspace.KazFLBG.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[3698] Attachment | "Workspace.KazFLBG.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[3699] Vector3Value | "Workspace.KazFLBG.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[3700] Attachment | "Workspace.KazFLBG.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[3701] Vector3Value | "Workspace.KazFLBG.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[3702] Attachment | "Workspace.KazFLBG.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[3703] Vector3Value | "Workspace.KazFLBG.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[3704] Attachment | "Workspace.KazFLBG.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[3705] Vector3Value | "Workspace.KazFLBG.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[3706] Attachment | "Workspace.KazFLBG.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[3707] Vector3Value | "Workspace.KazFLBG.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[3708] Attachment | "Workspace.KazFLBG.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[3709] Vector3Value | "Workspace.KazFLBG.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[3710] Vector3Value | "Workspace.KazFLBG.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[3711] NoCollisionConstraint | "Workspace.KazFLBG.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[3712] NoCollisionConstraint | "Workspace.KazFLBG.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[3713] NoCollisionConstraint | "Workspace.KazFLBG.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[3714] NoCollisionConstraint | "Workspace.KazFLBG.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[3715] AnimationConstraint | "Workspace.KazFLBG.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[3716] MeshPart | "Workspace.KazFLBG.RightUpperLeg" | Name="RightUpperLeg"
[3717] WrapTarget | "Workspace.KazFLBG.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[3718] Attachment | "Workspace.KazFLBG.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[3719] Vector3Value | "Workspace.KazFLBG.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[3720] Attachment | "Workspace.KazFLBG.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[3721] Vector3Value | "Workspace.KazFLBG.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[3722] Vector3Value | "Workspace.KazFLBG.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[3723] NoCollisionConstraint | "Workspace.KazFLBG.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[3724] AnimationConstraint | "Workspace.KazFLBG.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[3725] BallSocketConstraint | "Workspace.KazFLBG.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[3726] Humanoid | "Workspace.KazFLBG.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[3727] Status | "Workspace.KazFLBG.Humanoid.Status" | Name="Status"
[3728] Animator | "Workspace.KazFLBG.Humanoid.Animator" | Name="Animator"
[3729] MeshPart | "Workspace.KazFLBG.Head" | Name="Head"
[3730] Attachment | "Workspace.KazFLBG.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[3731] Vector3Value | "Workspace.KazFLBG.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[3732] Attachment | "Workspace.KazFLBG.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[3733] Vector3Value | "Workspace.KazFLBG.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[3734] Attachment | "Workspace.KazFLBG.Head.HairAttachment" | Name="HairAttachment"
[3735] Vector3Value | "Workspace.KazFLBG.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[3736] Attachment | "Workspace.KazFLBG.Head.HatAttachment" | Name="HatAttachment"
[3737] Vector3Value | "Workspace.KazFLBG.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[3738] Attachment | "Workspace.KazFLBG.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[3739] Vector3Value | "Workspace.KazFLBG.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[3740] Vector3Value | "Workspace.KazFLBG.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[3741] WrapTarget | "Workspace.KazFLBG.Head.Head" | Name="Head"
[3742] FaceControls | "Workspace.KazFLBG.Head.FaceControls" | Name="FaceControls"
[3743] NoCollisionConstraint | "Workspace.KazFLBG.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[3744] NoCollisionConstraint | "Workspace.KazFLBG.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[3745] NoCollisionConstraint | "Workspace.KazFLBG.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[3746] AnimationConstraint | "Workspace.KazFLBG.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[3747] BallSocketConstraint | "Workspace.KazFLBG.Head.NeckBallSocket" | Name="NeckBallSocket"
[3748] Script | "Workspace.KazFLBG.Health" | Name="Health"
[3749] LocalScript | "Workspace.KazFLBG.Animate" | Name="Animate"
[3750] StringValue | "Workspace.KazFLBG.Animate.cheer" | Name="cheer"; Value=""
[3751] Animation | "Workspace.KazFLBG.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[3752] StringValue | "Workspace.KazFLBG.Animate.climb" | Name="climb"; Value=""
[3753] Animation | "Workspace.KazFLBG.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[3754] StringValue | "Workspace.KazFLBG.Animate.dance" | Name="dance"; Value=""
[3755] Animation | "Workspace.KazFLBG.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[3756] NumberValue | "Workspace.KazFLBG.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[3757] Animation | "Workspace.KazFLBG.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[3758] NumberValue | "Workspace.KazFLBG.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[3759] Animation | "Workspace.KazFLBG.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[3760] NumberValue | "Workspace.KazFLBG.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[3761] StringValue | "Workspace.KazFLBG.Animate.dance2" | Name="dance2"; Value=""
[3762] Animation | "Workspace.KazFLBG.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[3763] NumberValue | "Workspace.KazFLBG.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[3764] Animation | "Workspace.KazFLBG.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[3765] NumberValue | "Workspace.KazFLBG.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[3766] Animation | "Workspace.KazFLBG.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[3767] NumberValue | "Workspace.KazFLBG.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[3768] StringValue | "Workspace.KazFLBG.Animate.dance3" | Name="dance3"; Value=""
[3769] Animation | "Workspace.KazFLBG.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[3770] NumberValue | "Workspace.KazFLBG.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[3771] Animation | "Workspace.KazFLBG.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[3772] NumberValue | "Workspace.KazFLBG.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[3773] Animation | "Workspace.KazFLBG.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[3774] NumberValue | "Workspace.KazFLBG.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[3775] StringValue | "Workspace.KazFLBG.Animate.fall" | Name="fall"; Value=""
[3776] Animation | "Workspace.KazFLBG.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[3777] StringValue | "Workspace.KazFLBG.Animate.idle" | Name="idle"; Value=""
[3778] Animation | "Workspace.KazFLBG.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[3779] NumberValue | "Workspace.KazFLBG.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[3780] Animation | "Workspace.KazFLBG.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[3781] NumberValue | "Workspace.KazFLBG.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[3782] StringValue | "Workspace.KazFLBG.Animate.jump" | Name="jump"; Value=""
[3783] Animation | "Workspace.KazFLBG.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[3784] StringValue | "Workspace.KazFLBG.Animate.laugh" | Name="laugh"; Value=""
[3785] Animation | "Workspace.KazFLBG.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[3786] StringValue | "Workspace.KazFLBG.Animate.point" | Name="point"; Value=""
[3787] Animation | "Workspace.KazFLBG.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[3788] StringValue | "Workspace.KazFLBG.Animate.sit" | Name="sit"; Value=""
[3789] Animation | "Workspace.KazFLBG.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[3790] StringValue | "Workspace.KazFLBG.Animate.toollunge" | Name="toollunge"; Value=""
[3791] Animation | "Workspace.KazFLBG.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[3792] StringValue | "Workspace.KazFLBG.Animate.toolnone" | Name="toolnone"; Value=""
[3793] Animation | "Workspace.KazFLBG.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[3794] StringValue | "Workspace.KazFLBG.Animate.toolslash" | Name="toolslash"; Value=""
[3795] Animation | "Workspace.KazFLBG.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[3796] StringValue | "Workspace.KazFLBG.Animate.wave" | Name="wave"; Value=""
[3797] Animation | "Workspace.KazFLBG.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[3798] NumberValue | "Workspace.KazFLBG.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[3799] StringValue | "Workspace.KazFLBG.Animate.run" | Name="run"; Value=""
[3800] Animation | "Workspace.KazFLBG.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[3801] StringValue | "Workspace.KazFLBG.Animate.swim" | Name="swim"; Value=""
[3802] Animation | "Workspace.KazFLBG.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[3803] StringValue | "Workspace.KazFLBG.Animate.swimidle" | Name="swimidle"; Value=""
[3804] Animation | "Workspace.KazFLBG.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[3805] StringValue | "Workspace.KazFLBG.Animate.walk" | Name="walk"; Value=""
[3806] Animation | "Workspace.KazFLBG.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[3807] BindableFunction | "Workspace.KazFLBG.Animate.PlayEmote" | Name="PlayEmote"
[3808] StringValue | "Workspace.KazFLBG.Animate.mood" | Name="mood"; Value=""
[3809] Animation | "Workspace.KazFLBG.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[3810] AudioEmitter | "Workspace.KazFLBG.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[3811] Wire | "Workspace.KazFLBG.AudioEmitter.Wire" | Name="Wire"
[3812] Model | "Workspace.KazFLBG.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="ChallengeBloodsport"; attr:TPS_WeaponId="AR15"
[3813] Part | "Workspace.KazFLBG.TPS_HeldWeapon.Handle" | Name="Handle"
[3814] Attachment | "Workspace.KazFLBG.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[3815] Attachment | "Workspace.KazFLBG.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[3816] Attachment | "Workspace.KazFLBG.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[3817] Motor6D | "Workspace.KazFLBG.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[3818] Part | "Workspace.KazFLBG.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"; attr:R1_SkinHidden=true
[3819] SpecialMesh | "Workspace.KazFLBG.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[3820] WeldConstraint | "Workspace.KazFLBG.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[3821] Part | "Workspace.KazFLBG.TPS_HeldWeapon.Magazine" | Name="Magazine"
[3822] Weld | "Workspace.KazFLBG.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[3823] Attachment | "Workspace.KazFLBG.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[3824] MeshPart | "Workspace.KazFLBG.TPS_HeldWeapon.R1_SkinBody" | Name="R1_SkinBody"
[3825] WeldConstraint | "Workspace.KazFLBG.TPS_HeldWeapon.R1_SkinBody.WeldConstraint" | Name="WeldConstraint"
[3826] SurfaceAppearance | "Workspace.KazFLBG.TPS_HeldWeapon.R1_SkinBody.AR15_Bloodsport" | Name="AR15_Bloodsport"
[3827] Model | "Workspace.KarumuBlox" | Name="KarumuBlox"; attr:TPS_Weapon="AR15"
[3828] Part | "Workspace.KarumuBlox.HumanoidRootPart" | Name="HumanoidRootPart"
[3829] Attachment | "Workspace.KarumuBlox.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[3830] Vector3Value | "Workspace.KarumuBlox.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[3831] Vector3Value | "Workspace.KarumuBlox.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[3832] Attachment | "Workspace.KarumuBlox.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[3833] Sound | "Workspace.KarumuBlox.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[3834] Sound | "Workspace.KarumuBlox.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[3835] Sound | "Workspace.KarumuBlox.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[3836] Sound | "Workspace.KarumuBlox.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[3837] Sound | "Workspace.KarumuBlox.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[3838] Sound | "Workspace.KarumuBlox.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[3839] Sound | "Workspace.KarumuBlox.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[3840] Sound | "Workspace.KarumuBlox.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[3841] Sound | "Workspace.KarumuBlox.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[3842] MeshPart | "Workspace.KarumuBlox.LeftHand" | Name="LeftHand"
[3843] WrapTarget | "Workspace.KarumuBlox.LeftHand.LeftHand" | Name="LeftHand"
[3844] Attachment | "Workspace.KarumuBlox.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[3845] Vector3Value | "Workspace.KarumuBlox.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[3846] Attachment | "Workspace.KarumuBlox.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[3847] Vector3Value | "Workspace.KarumuBlox.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[3848] Vector3Value | "Workspace.KarumuBlox.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[3849] AnimationConstraint | "Workspace.KarumuBlox.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[3850] BallSocketConstraint | "Workspace.KarumuBlox.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[3851] MeshPart | "Workspace.KarumuBlox.RightHand" | Name="RightHand"
[3852] WrapTarget | "Workspace.KarumuBlox.RightHand.RightHand" | Name="RightHand"
[3853] Attachment | "Workspace.KarumuBlox.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[3854] Vector3Value | "Workspace.KarumuBlox.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[3855] Attachment | "Workspace.KarumuBlox.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[3856] Vector3Value | "Workspace.KarumuBlox.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[3857] Vector3Value | "Workspace.KarumuBlox.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[3858] AnimationConstraint | "Workspace.KarumuBlox.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[3859] BallSocketConstraint | "Workspace.KarumuBlox.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[3860] MeshPart | "Workspace.KarumuBlox.LeftLowerArm" | Name="LeftLowerArm"
[3861] WrapTarget | "Workspace.KarumuBlox.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[3862] Attachment | "Workspace.KarumuBlox.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[3863] Vector3Value | "Workspace.KarumuBlox.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[3864] Attachment | "Workspace.KarumuBlox.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[3865] Vector3Value | "Workspace.KarumuBlox.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[3866] Vector3Value | "Workspace.KarumuBlox.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[3867] AnimationConstraint | "Workspace.KarumuBlox.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[3868] BallSocketConstraint | "Workspace.KarumuBlox.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[3869] MeshPart | "Workspace.KarumuBlox.RightLowerArm" | Name="RightLowerArm"
[3870] WrapTarget | "Workspace.KarumuBlox.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[3871] Attachment | "Workspace.KarumuBlox.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[3872] Vector3Value | "Workspace.KarumuBlox.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[3873] Attachment | "Workspace.KarumuBlox.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[3874] Vector3Value | "Workspace.KarumuBlox.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[3875] Vector3Value | "Workspace.KarumuBlox.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[3876] AnimationConstraint | "Workspace.KarumuBlox.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[3877] BallSocketConstraint | "Workspace.KarumuBlox.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[3878] MeshPart | "Workspace.KarumuBlox.LeftUpperArm" | Name="LeftUpperArm"
[3879] WrapTarget | "Workspace.KarumuBlox.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[3880] Attachment | "Workspace.KarumuBlox.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[3881] Vector3Value | "Workspace.KarumuBlox.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[3882] Attachment | "Workspace.KarumuBlox.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3883] Attachment | "Workspace.KarumuBlox.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[3884] Vector3Value | "Workspace.KarumuBlox.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[3885] Attachment | "Workspace.KarumuBlox.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[3886] Vector3Value | "Workspace.KarumuBlox.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[3887] Vector3Value | "Workspace.KarumuBlox.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[3888] NoCollisionConstraint | "Workspace.KarumuBlox.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[3889] AnimationConstraint | "Workspace.KarumuBlox.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[3890] BallSocketConstraint | "Workspace.KarumuBlox.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[3891] MeshPart | "Workspace.KarumuBlox.RightUpperArm" | Name="RightUpperArm"
[3892] WrapTarget | "Workspace.KarumuBlox.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[3893] Attachment | "Workspace.KarumuBlox.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[3894] Vector3Value | "Workspace.KarumuBlox.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[3895] Attachment | "Workspace.KarumuBlox.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3896] Attachment | "Workspace.KarumuBlox.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[3897] Vector3Value | "Workspace.KarumuBlox.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[3898] Attachment | "Workspace.KarumuBlox.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[3899] Vector3Value | "Workspace.KarumuBlox.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[3900] Vector3Value | "Workspace.KarumuBlox.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[3901] NoCollisionConstraint | "Workspace.KarumuBlox.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[3902] AnimationConstraint | "Workspace.KarumuBlox.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[3903] BallSocketConstraint | "Workspace.KarumuBlox.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[3904] MeshPart | "Workspace.KarumuBlox.LeftFoot" | Name="LeftFoot"
[3905] WrapTarget | "Workspace.KarumuBlox.LeftFoot.LeftFoot" | Name="LeftFoot"
[3906] Attachment | "Workspace.KarumuBlox.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[3907] Vector3Value | "Workspace.KarumuBlox.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[3908] Attachment | "Workspace.KarumuBlox.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[3909] Vector3Value | "Workspace.KarumuBlox.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[3910] Vector3Value | "Workspace.KarumuBlox.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[3911] AnimationConstraint | "Workspace.KarumuBlox.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[3912] BallSocketConstraint | "Workspace.KarumuBlox.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[3913] MeshPart | "Workspace.KarumuBlox.LeftLowerLeg" | Name="LeftLowerLeg"
[3914] WrapTarget | "Workspace.KarumuBlox.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[3915] Attachment | "Workspace.KarumuBlox.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[3916] Vector3Value | "Workspace.KarumuBlox.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[3917] Attachment | "Workspace.KarumuBlox.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[3918] Vector3Value | "Workspace.KarumuBlox.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[3919] Vector3Value | "Workspace.KarumuBlox.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[3920] AnimationConstraint | "Workspace.KarumuBlox.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[3921] BallSocketConstraint | "Workspace.KarumuBlox.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[3922] MeshPart | "Workspace.KarumuBlox.UpperTorso" | Name="UpperTorso"
[3923] WrapTarget | "Workspace.KarumuBlox.UpperTorso.UpperTorso" | Name="UpperTorso"
[3924] Attachment | "Workspace.KarumuBlox.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[3925] Vector3Value | "Workspace.KarumuBlox.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[3926] Attachment | "Workspace.KarumuBlox.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[3927] Vector3Value | "Workspace.KarumuBlox.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[3928] Attachment | "Workspace.KarumuBlox.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[3929] Vector3Value | "Workspace.KarumuBlox.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[3930] Attachment | "Workspace.KarumuBlox.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3931] Attachment | "Workspace.KarumuBlox.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[3932] Vector3Value | "Workspace.KarumuBlox.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[3933] Attachment | "Workspace.KarumuBlox.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[3934] Attachment | "Workspace.KarumuBlox.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[3935] Vector3Value | "Workspace.KarumuBlox.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[3936] Attachment | "Workspace.KarumuBlox.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[3937] Vector3Value | "Workspace.KarumuBlox.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[3938] Attachment | "Workspace.KarumuBlox.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[3939] Vector3Value | "Workspace.KarumuBlox.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[3940] Attachment | "Workspace.KarumuBlox.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[3941] Vector3Value | "Workspace.KarumuBlox.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[3942] Attachment | "Workspace.KarumuBlox.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[3943] Vector3Value | "Workspace.KarumuBlox.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[3944] Vector3Value | "Workspace.KarumuBlox.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[3945] NoCollisionConstraint | "Workspace.KarumuBlox.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[3946] NoCollisionConstraint | "Workspace.KarumuBlox.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[3947] NoCollisionConstraint | "Workspace.KarumuBlox.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[3948] NoCollisionConstraint | "Workspace.KarumuBlox.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[3949] NoCollisionConstraint | "Workspace.KarumuBlox.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[3950] NoCollisionConstraint | "Workspace.KarumuBlox.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[3951] NoCollisionConstraint | "Workspace.KarumuBlox.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[3952] AnimationConstraint | "Workspace.KarumuBlox.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[3953] BallSocketConstraint | "Workspace.KarumuBlox.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[3954] MeshPart | "Workspace.KarumuBlox.LeftUpperLeg" | Name="LeftUpperLeg"
[3955] WrapTarget | "Workspace.KarumuBlox.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[3956] Attachment | "Workspace.KarumuBlox.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[3957] Vector3Value | "Workspace.KarumuBlox.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[3958] Attachment | "Workspace.KarumuBlox.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[3959] Vector3Value | "Workspace.KarumuBlox.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[3960] Vector3Value | "Workspace.KarumuBlox.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[3961] NoCollisionConstraint | "Workspace.KarumuBlox.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[3962] NoCollisionConstraint | "Workspace.KarumuBlox.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[3963] AnimationConstraint | "Workspace.KarumuBlox.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[3964] BallSocketConstraint | "Workspace.KarumuBlox.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[3965] MeshPart | "Workspace.KarumuBlox.RightFoot" | Name="RightFoot"
[3966] WrapTarget | "Workspace.KarumuBlox.RightFoot.RightFoot" | Name="RightFoot"
[3967] Attachment | "Workspace.KarumuBlox.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[3968] Vector3Value | "Workspace.KarumuBlox.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[3969] Attachment | "Workspace.KarumuBlox.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[3970] Vector3Value | "Workspace.KarumuBlox.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[3971] Vector3Value | "Workspace.KarumuBlox.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[3972] AnimationConstraint | "Workspace.KarumuBlox.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[3973] BallSocketConstraint | "Workspace.KarumuBlox.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[3974] MeshPart | "Workspace.KarumuBlox.RightLowerLeg" | Name="RightLowerLeg"
[3975] WrapTarget | "Workspace.KarumuBlox.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[3976] Attachment | "Workspace.KarumuBlox.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[3977] Vector3Value | "Workspace.KarumuBlox.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[3978] Attachment | "Workspace.KarumuBlox.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[3979] Vector3Value | "Workspace.KarumuBlox.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[3980] Vector3Value | "Workspace.KarumuBlox.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[3981] AnimationConstraint | "Workspace.KarumuBlox.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[3982] BallSocketConstraint | "Workspace.KarumuBlox.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[3983] MeshPart | "Workspace.KarumuBlox.LowerTorso" | Name="LowerTorso"
[3984] WrapTarget | "Workspace.KarumuBlox.LowerTorso.LowerTorso" | Name="LowerTorso"
[3985] Attachment | "Workspace.KarumuBlox.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[3986] Vector3Value | "Workspace.KarumuBlox.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[3987] Attachment | "Workspace.KarumuBlox.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[3988] Vector3Value | "Workspace.KarumuBlox.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[3989] Attachment | "Workspace.KarumuBlox.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[3990] Vector3Value | "Workspace.KarumuBlox.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[3991] Attachment | "Workspace.KarumuBlox.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[3992] Vector3Value | "Workspace.KarumuBlox.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[3993] Attachment | "Workspace.KarumuBlox.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[3994] Vector3Value | "Workspace.KarumuBlox.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[3995] Attachment | "Workspace.KarumuBlox.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[3996] Vector3Value | "Workspace.KarumuBlox.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[3997] Attachment | "Workspace.KarumuBlox.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[3998] Vector3Value | "Workspace.KarumuBlox.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[3999] Vector3Value | "Workspace.KarumuBlox.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[4000] NoCollisionConstraint | "Workspace.KarumuBlox.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[4001] NoCollisionConstraint | "Workspace.KarumuBlox.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[4002] NoCollisionConstraint | "Workspace.KarumuBlox.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[4003] NoCollisionConstraint | "Workspace.KarumuBlox.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[4004] AnimationConstraint | "Workspace.KarumuBlox.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[4005] MeshPart | "Workspace.KarumuBlox.RightUpperLeg" | Name="RightUpperLeg"
[4006] WrapTarget | "Workspace.KarumuBlox.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[4007] Attachment | "Workspace.KarumuBlox.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[4008] Vector3Value | "Workspace.KarumuBlox.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[4009] Attachment | "Workspace.KarumuBlox.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[4010] Vector3Value | "Workspace.KarumuBlox.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[4011] Vector3Value | "Workspace.KarumuBlox.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[4012] NoCollisionConstraint | "Workspace.KarumuBlox.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[4013] AnimationConstraint | "Workspace.KarumuBlox.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[4014] BallSocketConstraint | "Workspace.KarumuBlox.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[4015] Humanoid | "Workspace.KarumuBlox.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[4016] Status | "Workspace.KarumuBlox.Humanoid.Status" | Name="Status"
[4017] Animator | "Workspace.KarumuBlox.Humanoid.Animator" | Name="Animator"
[4018] MeshPart | "Workspace.KarumuBlox.Head" | Name="Head"
[4019] Attachment | "Workspace.KarumuBlox.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[4020] Vector3Value | "Workspace.KarumuBlox.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[4021] Attachment | "Workspace.KarumuBlox.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[4022] Vector3Value | "Workspace.KarumuBlox.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[4023] Attachment | "Workspace.KarumuBlox.Head.HairAttachment" | Name="HairAttachment"
[4024] Vector3Value | "Workspace.KarumuBlox.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[4025] Attachment | "Workspace.KarumuBlox.Head.HatAttachment" | Name="HatAttachment"
[4026] Vector3Value | "Workspace.KarumuBlox.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[4027] Attachment | "Workspace.KarumuBlox.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[4028] Vector3Value | "Workspace.KarumuBlox.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[4029] Vector3Value | "Workspace.KarumuBlox.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[4030] WrapTarget | "Workspace.KarumuBlox.Head.Head" | Name="Head"
[4031] FaceControls | "Workspace.KarumuBlox.Head.FaceControls" | Name="FaceControls"
[4032] NoCollisionConstraint | "Workspace.KarumuBlox.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[4033] NoCollisionConstraint | "Workspace.KarumuBlox.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[4034] NoCollisionConstraint | "Workspace.KarumuBlox.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[4035] AnimationConstraint | "Workspace.KarumuBlox.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[4036] BallSocketConstraint | "Workspace.KarumuBlox.Head.NeckBallSocket" | Name="NeckBallSocket"
[4037] Script | "Workspace.KarumuBlox.Health" | Name="Health"
[4038] LocalScript | "Workspace.KarumuBlox.Animate" | Name="Animate"
[4039] StringValue | "Workspace.KarumuBlox.Animate.cheer" | Name="cheer"; Value=""
[4040] Animation | "Workspace.KarumuBlox.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[4041] StringValue | "Workspace.KarumuBlox.Animate.climb" | Name="climb"; Value=""
[4042] Animation | "Workspace.KarumuBlox.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[4043] StringValue | "Workspace.KarumuBlox.Animate.dance" | Name="dance"; Value=""
[4044] Animation | "Workspace.KarumuBlox.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[4045] NumberValue | "Workspace.KarumuBlox.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[4046] Animation | "Workspace.KarumuBlox.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[4047] NumberValue | "Workspace.KarumuBlox.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[4048] Animation | "Workspace.KarumuBlox.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[4049] NumberValue | "Workspace.KarumuBlox.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[4050] StringValue | "Workspace.KarumuBlox.Animate.dance2" | Name="dance2"; Value=""
[4051] Animation | "Workspace.KarumuBlox.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[4052] NumberValue | "Workspace.KarumuBlox.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[4053] Animation | "Workspace.KarumuBlox.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[4054] NumberValue | "Workspace.KarumuBlox.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[4055] Animation | "Workspace.KarumuBlox.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[4056] NumberValue | "Workspace.KarumuBlox.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[4057] StringValue | "Workspace.KarumuBlox.Animate.dance3" | Name="dance3"; Value=""
[4058] Animation | "Workspace.KarumuBlox.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[4059] NumberValue | "Workspace.KarumuBlox.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[4060] Animation | "Workspace.KarumuBlox.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[4061] NumberValue | "Workspace.KarumuBlox.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[4062] Animation | "Workspace.KarumuBlox.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[4063] NumberValue | "Workspace.KarumuBlox.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[4064] StringValue | "Workspace.KarumuBlox.Animate.fall" | Name="fall"; Value=""
[4065] Animation | "Workspace.KarumuBlox.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[4066] StringValue | "Workspace.KarumuBlox.Animate.idle" | Name="idle"; Value=""
[4067] Animation | "Workspace.KarumuBlox.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[4068] NumberValue | "Workspace.KarumuBlox.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[4069] Animation | "Workspace.KarumuBlox.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[4070] NumberValue | "Workspace.KarumuBlox.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[4071] StringValue | "Workspace.KarumuBlox.Animate.jump" | Name="jump"; Value=""
[4072] Animation | "Workspace.KarumuBlox.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[4073] StringValue | "Workspace.KarumuBlox.Animate.laugh" | Name="laugh"; Value=""
[4074] Animation | "Workspace.KarumuBlox.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[4075] StringValue | "Workspace.KarumuBlox.Animate.point" | Name="point"; Value=""
[4076] Animation | "Workspace.KarumuBlox.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[4077] StringValue | "Workspace.KarumuBlox.Animate.sit" | Name="sit"; Value=""
[4078] Animation | "Workspace.KarumuBlox.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[4079] StringValue | "Workspace.KarumuBlox.Animate.toollunge" | Name="toollunge"; Value=""
[4080] Animation | "Workspace.KarumuBlox.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[4081] StringValue | "Workspace.KarumuBlox.Animate.toolnone" | Name="toolnone"; Value=""
[4082] Animation | "Workspace.KarumuBlox.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[4083] StringValue | "Workspace.KarumuBlox.Animate.toolslash" | Name="toolslash"; Value=""
[4084] Animation | "Workspace.KarumuBlox.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[4085] StringValue | "Workspace.KarumuBlox.Animate.wave" | Name="wave"; Value=""
[4086] Animation | "Workspace.KarumuBlox.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[4087] NumberValue | "Workspace.KarumuBlox.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[4088] StringValue | "Workspace.KarumuBlox.Animate.run" | Name="run"; Value=""
[4089] Animation | "Workspace.KarumuBlox.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[4090] StringValue | "Workspace.KarumuBlox.Animate.swim" | Name="swim"; Value=""
[4091] Animation | "Workspace.KarumuBlox.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[4092] StringValue | "Workspace.KarumuBlox.Animate.swimidle" | Name="swimidle"; Value=""
[4093] Animation | "Workspace.KarumuBlox.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[4094] StringValue | "Workspace.KarumuBlox.Animate.walk" | Name="walk"; Value=""
[4095] Animation | "Workspace.KarumuBlox.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[4096] BindableFunction | "Workspace.KarumuBlox.Animate.PlayEmote" | Name="PlayEmote"
[4097] StringValue | "Workspace.KarumuBlox.Animate.mood" | Name="mood"; Value=""
[4098] Animation | "Workspace.KarumuBlox.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[4099] Shirt | "Workspace.KarumuBlox.Clothing" | Name="Clothing"
[4100] Model | "Workspace.KarumuBlox.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Default"; attr:TPS_WeaponId="AR15"
[4101] Part | "Workspace.KarumuBlox.TPS_HeldWeapon.Handle" | Name="Handle"
[4102] Attachment | "Workspace.KarumuBlox.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[4103] Attachment | "Workspace.KarumuBlox.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[4104] Attachment | "Workspace.KarumuBlox.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[4105] Motor6D | "Workspace.KarumuBlox.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[4106] Part | "Workspace.KarumuBlox.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"
[4107] SpecialMesh | "Workspace.KarumuBlox.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[4108] WeldConstraint | "Workspace.KarumuBlox.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[4109] Part | "Workspace.KarumuBlox.TPS_HeldWeapon.Magazine" | Name="Magazine"
[4110] Weld | "Workspace.KarumuBlox.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[4111] Attachment | "Workspace.KarumuBlox.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[4112] Pants | "Workspace.KarumuBlox.Clothing" | Name="Clothing"
[4113] Model | "Workspace.KarumuBlox.R1_GearPreview" | Name="R1_GearPreview"
[4114] MeshPart | "Workspace.KarumuBlox.R1_GearPreview.Handle" | Name="Handle"
[4115] WeldConstraint | "Workspace.KarumuBlox.R1_GearPreview.Handle.WeldConstraint" | Name="WeldConstraint"
[4116] Model | "Workspace.TheDucky_Dave" | Name="TheDucky_Dave"; attr:TPS_Weapon="AR15"
[4117] Part | "Workspace.TheDucky_Dave.HumanoidRootPart" | Name="HumanoidRootPart"
[4118] Attachment | "Workspace.TheDucky_Dave.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[4119] Vector3Value | "Workspace.TheDucky_Dave.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[4120] Vector3Value | "Workspace.TheDucky_Dave.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[4121] Attachment | "Workspace.TheDucky_Dave.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[4122] Sound | "Workspace.TheDucky_Dave.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[4123] Sound | "Workspace.TheDucky_Dave.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[4124] Sound | "Workspace.TheDucky_Dave.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[4125] Sound | "Workspace.TheDucky_Dave.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[4126] Sound | "Workspace.TheDucky_Dave.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[4127] Sound | "Workspace.TheDucky_Dave.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[4128] Sound | "Workspace.TheDucky_Dave.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[4129] Sound | "Workspace.TheDucky_Dave.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[4130] Sound | "Workspace.TheDucky_Dave.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[4131] MeshPart | "Workspace.TheDucky_Dave.LeftHand" | Name="LeftHand"
[4132] WrapTarget | "Workspace.TheDucky_Dave.LeftHand.LeftHand" | Name="LeftHand"
[4133] Attachment | "Workspace.TheDucky_Dave.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[4134] Vector3Value | "Workspace.TheDucky_Dave.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[4135] Attachment | "Workspace.TheDucky_Dave.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[4136] Vector3Value | "Workspace.TheDucky_Dave.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[4137] Vector3Value | "Workspace.TheDucky_Dave.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[4138] AnimationConstraint | "Workspace.TheDucky_Dave.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[4139] BallSocketConstraint | "Workspace.TheDucky_Dave.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[4140] MeshPart | "Workspace.TheDucky_Dave.RightHand" | Name="RightHand"
[4141] WrapTarget | "Workspace.TheDucky_Dave.RightHand.RightHand" | Name="RightHand"
[4142] Attachment | "Workspace.TheDucky_Dave.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[4143] Vector3Value | "Workspace.TheDucky_Dave.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[4144] Attachment | "Workspace.TheDucky_Dave.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[4145] Vector3Value | "Workspace.TheDucky_Dave.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[4146] Vector3Value | "Workspace.TheDucky_Dave.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[4147] AnimationConstraint | "Workspace.TheDucky_Dave.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[4148] BallSocketConstraint | "Workspace.TheDucky_Dave.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[4149] MeshPart | "Workspace.TheDucky_Dave.LeftLowerArm" | Name="LeftLowerArm"
[4150] WrapTarget | "Workspace.TheDucky_Dave.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[4151] Attachment | "Workspace.TheDucky_Dave.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[4152] Vector3Value | "Workspace.TheDucky_Dave.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[4153] Attachment | "Workspace.TheDucky_Dave.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[4154] Vector3Value | "Workspace.TheDucky_Dave.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[4155] Vector3Value | "Workspace.TheDucky_Dave.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[4156] AnimationConstraint | "Workspace.TheDucky_Dave.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[4157] BallSocketConstraint | "Workspace.TheDucky_Dave.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[4158] MeshPart | "Workspace.TheDucky_Dave.RightLowerArm" | Name="RightLowerArm"
[4159] WrapTarget | "Workspace.TheDucky_Dave.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[4160] Attachment | "Workspace.TheDucky_Dave.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[4161] Vector3Value | "Workspace.TheDucky_Dave.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[4162] Attachment | "Workspace.TheDucky_Dave.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[4163] Vector3Value | "Workspace.TheDucky_Dave.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[4164] Vector3Value | "Workspace.TheDucky_Dave.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[4165] AnimationConstraint | "Workspace.TheDucky_Dave.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[4166] BallSocketConstraint | "Workspace.TheDucky_Dave.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[4167] MeshPart | "Workspace.TheDucky_Dave.LeftUpperArm" | Name="LeftUpperArm"
[4168] WrapTarget | "Workspace.TheDucky_Dave.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[4169] Attachment | "Workspace.TheDucky_Dave.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[4170] Vector3Value | "Workspace.TheDucky_Dave.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[4171] Attachment | "Workspace.TheDucky_Dave.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4172] Attachment | "Workspace.TheDucky_Dave.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[4173] Vector3Value | "Workspace.TheDucky_Dave.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[4174] Attachment | "Workspace.TheDucky_Dave.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[4175] Vector3Value | "Workspace.TheDucky_Dave.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[4176] Vector3Value | "Workspace.TheDucky_Dave.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[4177] NoCollisionConstraint | "Workspace.TheDucky_Dave.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[4178] AnimationConstraint | "Workspace.TheDucky_Dave.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[4179] BallSocketConstraint | "Workspace.TheDucky_Dave.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[4180] MeshPart | "Workspace.TheDucky_Dave.RightUpperArm" | Name="RightUpperArm"
[4181] WrapTarget | "Workspace.TheDucky_Dave.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[4182] Attachment | "Workspace.TheDucky_Dave.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[4183] Vector3Value | "Workspace.TheDucky_Dave.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[4184] Attachment | "Workspace.TheDucky_Dave.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4185] Attachment | "Workspace.TheDucky_Dave.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[4186] Vector3Value | "Workspace.TheDucky_Dave.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[4187] Attachment | "Workspace.TheDucky_Dave.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[4188] Vector3Value | "Workspace.TheDucky_Dave.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[4189] Vector3Value | "Workspace.TheDucky_Dave.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[4190] NoCollisionConstraint | "Workspace.TheDucky_Dave.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[4191] AnimationConstraint | "Workspace.TheDucky_Dave.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[4192] BallSocketConstraint | "Workspace.TheDucky_Dave.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[4193] MeshPart | "Workspace.TheDucky_Dave.LeftFoot" | Name="LeftFoot"
[4194] WrapTarget | "Workspace.TheDucky_Dave.LeftFoot.LeftFoot" | Name="LeftFoot"
[4195] Attachment | "Workspace.TheDucky_Dave.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[4196] Vector3Value | "Workspace.TheDucky_Dave.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[4197] Attachment | "Workspace.TheDucky_Dave.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[4198] Vector3Value | "Workspace.TheDucky_Dave.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[4199] Vector3Value | "Workspace.TheDucky_Dave.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[4200] AnimationConstraint | "Workspace.TheDucky_Dave.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[4201] BallSocketConstraint | "Workspace.TheDucky_Dave.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[4202] MeshPart | "Workspace.TheDucky_Dave.LeftLowerLeg" | Name="LeftLowerLeg"
[4203] WrapTarget | "Workspace.TheDucky_Dave.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[4204] Attachment | "Workspace.TheDucky_Dave.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[4205] Vector3Value | "Workspace.TheDucky_Dave.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[4206] Attachment | "Workspace.TheDucky_Dave.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[4207] Vector3Value | "Workspace.TheDucky_Dave.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[4208] Vector3Value | "Workspace.TheDucky_Dave.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[4209] AnimationConstraint | "Workspace.TheDucky_Dave.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[4210] BallSocketConstraint | "Workspace.TheDucky_Dave.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[4211] MeshPart | "Workspace.TheDucky_Dave.UpperTorso" | Name="UpperTorso"
[4212] WrapTarget | "Workspace.TheDucky_Dave.UpperTorso.UpperTorso" | Name="UpperTorso"
[4213] Attachment | "Workspace.TheDucky_Dave.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[4214] Vector3Value | "Workspace.TheDucky_Dave.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[4215] Attachment | "Workspace.TheDucky_Dave.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[4216] Vector3Value | "Workspace.TheDucky_Dave.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[4217] Attachment | "Workspace.TheDucky_Dave.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[4218] Vector3Value | "Workspace.TheDucky_Dave.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[4219] Attachment | "Workspace.TheDucky_Dave.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4220] Attachment | "Workspace.TheDucky_Dave.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[4221] Vector3Value | "Workspace.TheDucky_Dave.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[4222] Attachment | "Workspace.TheDucky_Dave.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4223] Attachment | "Workspace.TheDucky_Dave.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[4224] Vector3Value | "Workspace.TheDucky_Dave.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[4225] Attachment | "Workspace.TheDucky_Dave.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[4226] Vector3Value | "Workspace.TheDucky_Dave.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[4227] Attachment | "Workspace.TheDucky_Dave.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[4228] Vector3Value | "Workspace.TheDucky_Dave.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[4229] Attachment | "Workspace.TheDucky_Dave.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[4230] Vector3Value | "Workspace.TheDucky_Dave.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[4231] Attachment | "Workspace.TheDucky_Dave.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[4232] Vector3Value | "Workspace.TheDucky_Dave.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[4233] Vector3Value | "Workspace.TheDucky_Dave.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[4234] NoCollisionConstraint | "Workspace.TheDucky_Dave.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[4235] NoCollisionConstraint | "Workspace.TheDucky_Dave.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[4236] NoCollisionConstraint | "Workspace.TheDucky_Dave.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[4237] NoCollisionConstraint | "Workspace.TheDucky_Dave.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[4238] NoCollisionConstraint | "Workspace.TheDucky_Dave.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[4239] NoCollisionConstraint | "Workspace.TheDucky_Dave.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[4240] NoCollisionConstraint | "Workspace.TheDucky_Dave.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[4241] AnimationConstraint | "Workspace.TheDucky_Dave.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[4242] BallSocketConstraint | "Workspace.TheDucky_Dave.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[4243] MeshPart | "Workspace.TheDucky_Dave.LeftUpperLeg" | Name="LeftUpperLeg"
[4244] WrapTarget | "Workspace.TheDucky_Dave.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[4245] Attachment | "Workspace.TheDucky_Dave.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[4246] Vector3Value | "Workspace.TheDucky_Dave.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[4247] Attachment | "Workspace.TheDucky_Dave.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[4248] Vector3Value | "Workspace.TheDucky_Dave.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[4249] Vector3Value | "Workspace.TheDucky_Dave.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[4250] NoCollisionConstraint | "Workspace.TheDucky_Dave.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[4251] NoCollisionConstraint | "Workspace.TheDucky_Dave.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[4252] AnimationConstraint | "Workspace.TheDucky_Dave.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[4253] BallSocketConstraint | "Workspace.TheDucky_Dave.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[4254] MeshPart | "Workspace.TheDucky_Dave.RightFoot" | Name="RightFoot"
[4255] WrapTarget | "Workspace.TheDucky_Dave.RightFoot.RightFoot" | Name="RightFoot"
[4256] Attachment | "Workspace.TheDucky_Dave.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[4257] Vector3Value | "Workspace.TheDucky_Dave.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[4258] Attachment | "Workspace.TheDucky_Dave.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[4259] Vector3Value | "Workspace.TheDucky_Dave.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[4260] Vector3Value | "Workspace.TheDucky_Dave.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[4261] AnimationConstraint | "Workspace.TheDucky_Dave.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[4262] BallSocketConstraint | "Workspace.TheDucky_Dave.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[4263] MeshPart | "Workspace.TheDucky_Dave.RightLowerLeg" | Name="RightLowerLeg"
[4264] WrapTarget | "Workspace.TheDucky_Dave.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[4265] Attachment | "Workspace.TheDucky_Dave.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[4266] Vector3Value | "Workspace.TheDucky_Dave.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[4267] Attachment | "Workspace.TheDucky_Dave.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[4268] Vector3Value | "Workspace.TheDucky_Dave.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[4269] Vector3Value | "Workspace.TheDucky_Dave.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[4270] AnimationConstraint | "Workspace.TheDucky_Dave.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[4271] BallSocketConstraint | "Workspace.TheDucky_Dave.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[4272] MeshPart | "Workspace.TheDucky_Dave.LowerTorso" | Name="LowerTorso"
[4273] WrapTarget | "Workspace.TheDucky_Dave.LowerTorso.LowerTorso" | Name="LowerTorso"
[4274] Attachment | "Workspace.TheDucky_Dave.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[4275] Vector3Value | "Workspace.TheDucky_Dave.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[4276] Attachment | "Workspace.TheDucky_Dave.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[4277] Vector3Value | "Workspace.TheDucky_Dave.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[4278] Attachment | "Workspace.TheDucky_Dave.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[4279] Vector3Value | "Workspace.TheDucky_Dave.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[4280] Attachment | "Workspace.TheDucky_Dave.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[4281] Vector3Value | "Workspace.TheDucky_Dave.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[4282] Attachment | "Workspace.TheDucky_Dave.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[4283] Vector3Value | "Workspace.TheDucky_Dave.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[4284] Attachment | "Workspace.TheDucky_Dave.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[4285] Vector3Value | "Workspace.TheDucky_Dave.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[4286] Attachment | "Workspace.TheDucky_Dave.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[4287] Vector3Value | "Workspace.TheDucky_Dave.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[4288] Vector3Value | "Workspace.TheDucky_Dave.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[4289] NoCollisionConstraint | "Workspace.TheDucky_Dave.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[4290] NoCollisionConstraint | "Workspace.TheDucky_Dave.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[4291] NoCollisionConstraint | "Workspace.TheDucky_Dave.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[4292] NoCollisionConstraint | "Workspace.TheDucky_Dave.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[4293] AnimationConstraint | "Workspace.TheDucky_Dave.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[4294] MeshPart | "Workspace.TheDucky_Dave.RightUpperLeg" | Name="RightUpperLeg"
[4295] WrapTarget | "Workspace.TheDucky_Dave.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[4296] Attachment | "Workspace.TheDucky_Dave.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[4297] Vector3Value | "Workspace.TheDucky_Dave.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[4298] Attachment | "Workspace.TheDucky_Dave.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[4299] Vector3Value | "Workspace.TheDucky_Dave.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[4300] Vector3Value | "Workspace.TheDucky_Dave.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[4301] NoCollisionConstraint | "Workspace.TheDucky_Dave.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[4302] AnimationConstraint | "Workspace.TheDucky_Dave.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[4303] BallSocketConstraint | "Workspace.TheDucky_Dave.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[4304] Humanoid | "Workspace.TheDucky_Dave.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[4305] Status | "Workspace.TheDucky_Dave.Humanoid.Status" | Name="Status"
[4306] Animator | "Workspace.TheDucky_Dave.Humanoid.Animator" | Name="Animator"
[4307] MeshPart | "Workspace.TheDucky_Dave.Head" | Name="Head"
[4308] Attachment | "Workspace.TheDucky_Dave.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[4309] Vector3Value | "Workspace.TheDucky_Dave.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[4310] Attachment | "Workspace.TheDucky_Dave.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[4311] Vector3Value | "Workspace.TheDucky_Dave.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[4312] Attachment | "Workspace.TheDucky_Dave.Head.HairAttachment" | Name="HairAttachment"
[4313] Vector3Value | "Workspace.TheDucky_Dave.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[4314] Attachment | "Workspace.TheDucky_Dave.Head.HatAttachment" | Name="HatAttachment"
[4315] Vector3Value | "Workspace.TheDucky_Dave.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[4316] Attachment | "Workspace.TheDucky_Dave.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[4317] Vector3Value | "Workspace.TheDucky_Dave.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[4318] Vector3Value | "Workspace.TheDucky_Dave.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[4319] WrapTarget | "Workspace.TheDucky_Dave.Head.Head" | Name="Head"
[4320] FaceControls | "Workspace.TheDucky_Dave.Head.FaceControls" | Name="FaceControls"
[4321] NoCollisionConstraint | "Workspace.TheDucky_Dave.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[4322] NoCollisionConstraint | "Workspace.TheDucky_Dave.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[4323] NoCollisionConstraint | "Workspace.TheDucky_Dave.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[4324] AnimationConstraint | "Workspace.TheDucky_Dave.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[4325] BallSocketConstraint | "Workspace.TheDucky_Dave.Head.NeckBallSocket" | Name="NeckBallSocket"
[4326] Script | "Workspace.TheDucky_Dave.Health" | Name="Health"
[4327] LocalScript | "Workspace.TheDucky_Dave.Animate" | Name="Animate"
[4328] StringValue | "Workspace.TheDucky_Dave.Animate.cheer" | Name="cheer"; Value=""
[4329] Animation | "Workspace.TheDucky_Dave.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[4330] StringValue | "Workspace.TheDucky_Dave.Animate.climb" | Name="climb"; Value=""
[4331] Animation | "Workspace.TheDucky_Dave.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[4332] StringValue | "Workspace.TheDucky_Dave.Animate.dance" | Name="dance"; Value=""
[4333] Animation | "Workspace.TheDucky_Dave.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[4334] NumberValue | "Workspace.TheDucky_Dave.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[4335] Animation | "Workspace.TheDucky_Dave.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[4336] NumberValue | "Workspace.TheDucky_Dave.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[4337] Animation | "Workspace.TheDucky_Dave.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[4338] NumberValue | "Workspace.TheDucky_Dave.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[4339] StringValue | "Workspace.TheDucky_Dave.Animate.dance2" | Name="dance2"; Value=""
[4340] Animation | "Workspace.TheDucky_Dave.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[4341] NumberValue | "Workspace.TheDucky_Dave.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[4342] Animation | "Workspace.TheDucky_Dave.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[4343] NumberValue | "Workspace.TheDucky_Dave.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[4344] Animation | "Workspace.TheDucky_Dave.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[4345] NumberValue | "Workspace.TheDucky_Dave.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[4346] StringValue | "Workspace.TheDucky_Dave.Animate.dance3" | Name="dance3"; Value=""
[4347] Animation | "Workspace.TheDucky_Dave.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[4348] NumberValue | "Workspace.TheDucky_Dave.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[4349] Animation | "Workspace.TheDucky_Dave.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[4350] NumberValue | "Workspace.TheDucky_Dave.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[4351] Animation | "Workspace.TheDucky_Dave.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[4352] NumberValue | "Workspace.TheDucky_Dave.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[4353] StringValue | "Workspace.TheDucky_Dave.Animate.fall" | Name="fall"; Value=""
[4354] Animation | "Workspace.TheDucky_Dave.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[4355] StringValue | "Workspace.TheDucky_Dave.Animate.idle" | Name="idle"; Value=""
[4356] Animation | "Workspace.TheDucky_Dave.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[4357] NumberValue | "Workspace.TheDucky_Dave.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[4358] Animation | "Workspace.TheDucky_Dave.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[4359] NumberValue | "Workspace.TheDucky_Dave.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[4360] StringValue | "Workspace.TheDucky_Dave.Animate.jump" | Name="jump"; Value=""
[4361] Animation | "Workspace.TheDucky_Dave.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[4362] StringValue | "Workspace.TheDucky_Dave.Animate.laugh" | Name="laugh"; Value=""
[4363] Animation | "Workspace.TheDucky_Dave.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[4364] StringValue | "Workspace.TheDucky_Dave.Animate.point" | Name="point"; Value=""
[4365] Animation | "Workspace.TheDucky_Dave.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[4366] StringValue | "Workspace.TheDucky_Dave.Animate.sit" | Name="sit"; Value=""
[4367] Animation | "Workspace.TheDucky_Dave.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[4368] StringValue | "Workspace.TheDucky_Dave.Animate.toollunge" | Name="toollunge"; Value=""
[4369] Animation | "Workspace.TheDucky_Dave.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[4370] StringValue | "Workspace.TheDucky_Dave.Animate.toolnone" | Name="toolnone"; Value=""
[4371] Animation | "Workspace.TheDucky_Dave.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[4372] StringValue | "Workspace.TheDucky_Dave.Animate.toolslash" | Name="toolslash"; Value=""
[4373] Animation | "Workspace.TheDucky_Dave.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[4374] StringValue | "Workspace.TheDucky_Dave.Animate.wave" | Name="wave"; Value=""
[4375] Animation | "Workspace.TheDucky_Dave.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[4376] NumberValue | "Workspace.TheDucky_Dave.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[4377] StringValue | "Workspace.TheDucky_Dave.Animate.run" | Name="run"; Value=""
[4378] Animation | "Workspace.TheDucky_Dave.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[4379] StringValue | "Workspace.TheDucky_Dave.Animate.swim" | Name="swim"; Value=""
[4380] Animation | "Workspace.TheDucky_Dave.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[4381] StringValue | "Workspace.TheDucky_Dave.Animate.swimidle" | Name="swimidle"; Value=""
[4382] Animation | "Workspace.TheDucky_Dave.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[4383] StringValue | "Workspace.TheDucky_Dave.Animate.walk" | Name="walk"; Value=""
[4384] Animation | "Workspace.TheDucky_Dave.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[4385] BindableFunction | "Workspace.TheDucky_Dave.Animate.PlayEmote" | Name="PlayEmote"
[4386] StringValue | "Workspace.TheDucky_Dave.Animate.mood" | Name="mood"; Value=""
[4387] Animation | "Workspace.TheDucky_Dave.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[4388] AudioEmitter | "Workspace.TheDucky_Dave.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[4389] Wire | "Workspace.TheDucky_Dave.AudioEmitter.Wire" | Name="Wire"
[4390] Model | "Workspace.TheDucky_Dave.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Default"; attr:TPS_WeaponId="AR15"
[4391] Part | "Workspace.TheDucky_Dave.TPS_HeldWeapon.Handle" | Name="Handle"
[4392] Attachment | "Workspace.TheDucky_Dave.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[4393] Attachment | "Workspace.TheDucky_Dave.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[4394] Attachment | "Workspace.TheDucky_Dave.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[4395] Motor6D | "Workspace.TheDucky_Dave.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[4396] Part | "Workspace.TheDucky_Dave.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"
[4397] SpecialMesh | "Workspace.TheDucky_Dave.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[4398] WeldConstraint | "Workspace.TheDucky_Dave.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[4399] Part | "Workspace.TheDucky_Dave.TPS_HeldWeapon.Magazine" | Name="Magazine"
[4400] Weld | "Workspace.TheDucky_Dave.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[4401] Attachment | "Workspace.TheDucky_Dave.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[4402] Model | "Workspace.kgk001" | Name="kgk001"; attr:TPS_Weapon="AR15"
[4403] Part | "Workspace.kgk001.HumanoidRootPart" | Name="HumanoidRootPart"
[4404] Attachment | "Workspace.kgk001.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[4405] Vector3Value | "Workspace.kgk001.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[4406] Vector3Value | "Workspace.kgk001.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[4407] Attachment | "Workspace.kgk001.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[4408] Sound | "Workspace.kgk001.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[4409] Sound | "Workspace.kgk001.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[4410] Sound | "Workspace.kgk001.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[4411] Sound | "Workspace.kgk001.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[4412] Sound | "Workspace.kgk001.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[4413] Sound | "Workspace.kgk001.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[4414] Sound | "Workspace.kgk001.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[4415] Sound | "Workspace.kgk001.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[4416] Sound | "Workspace.kgk001.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[4417] MeshPart | "Workspace.kgk001.LeftHand" | Name="LeftHand"
[4418] WrapTarget | "Workspace.kgk001.LeftHand.LeftHand" | Name="LeftHand"
[4419] Attachment | "Workspace.kgk001.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[4420] Vector3Value | "Workspace.kgk001.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[4421] Attachment | "Workspace.kgk001.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[4422] Vector3Value | "Workspace.kgk001.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[4423] Vector3Value | "Workspace.kgk001.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[4424] AnimationConstraint | "Workspace.kgk001.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[4425] BallSocketConstraint | "Workspace.kgk001.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[4426] MeshPart | "Workspace.kgk001.RightHand" | Name="RightHand"
[4427] WrapTarget | "Workspace.kgk001.RightHand.RightHand" | Name="RightHand"
[4428] Attachment | "Workspace.kgk001.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[4429] Vector3Value | "Workspace.kgk001.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[4430] Attachment | "Workspace.kgk001.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[4431] Vector3Value | "Workspace.kgk001.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[4432] Vector3Value | "Workspace.kgk001.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[4433] AnimationConstraint | "Workspace.kgk001.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[4434] BallSocketConstraint | "Workspace.kgk001.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[4435] MeshPart | "Workspace.kgk001.LeftLowerArm" | Name="LeftLowerArm"
[4436] WrapTarget | "Workspace.kgk001.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[4437] Attachment | "Workspace.kgk001.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[4438] Vector3Value | "Workspace.kgk001.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[4439] Attachment | "Workspace.kgk001.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[4440] Vector3Value | "Workspace.kgk001.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[4441] Vector3Value | "Workspace.kgk001.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[4442] AnimationConstraint | "Workspace.kgk001.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[4443] BallSocketConstraint | "Workspace.kgk001.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[4444] MeshPart | "Workspace.kgk001.RightLowerArm" | Name="RightLowerArm"
[4445] WrapTarget | "Workspace.kgk001.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[4446] Attachment | "Workspace.kgk001.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[4447] Vector3Value | "Workspace.kgk001.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[4448] Attachment | "Workspace.kgk001.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[4449] Vector3Value | "Workspace.kgk001.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[4450] Vector3Value | "Workspace.kgk001.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[4451] AnimationConstraint | "Workspace.kgk001.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[4452] BallSocketConstraint | "Workspace.kgk001.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[4453] MeshPart | "Workspace.kgk001.LeftUpperArm" | Name="LeftUpperArm"
[4454] WrapTarget | "Workspace.kgk001.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[4455] Attachment | "Workspace.kgk001.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[4456] Vector3Value | "Workspace.kgk001.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[4457] Attachment | "Workspace.kgk001.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4458] Attachment | "Workspace.kgk001.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[4459] Vector3Value | "Workspace.kgk001.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[4460] Attachment | "Workspace.kgk001.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[4461] Vector3Value | "Workspace.kgk001.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[4462] Vector3Value | "Workspace.kgk001.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[4463] NoCollisionConstraint | "Workspace.kgk001.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[4464] AnimationConstraint | "Workspace.kgk001.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[4465] BallSocketConstraint | "Workspace.kgk001.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[4466] MeshPart | "Workspace.kgk001.RightUpperArm" | Name="RightUpperArm"
[4467] WrapTarget | "Workspace.kgk001.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[4468] Attachment | "Workspace.kgk001.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[4469] Vector3Value | "Workspace.kgk001.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[4470] Attachment | "Workspace.kgk001.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4471] Attachment | "Workspace.kgk001.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[4472] Vector3Value | "Workspace.kgk001.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[4473] Attachment | "Workspace.kgk001.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[4474] Vector3Value | "Workspace.kgk001.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[4475] Vector3Value | "Workspace.kgk001.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[4476] NoCollisionConstraint | "Workspace.kgk001.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[4477] AnimationConstraint | "Workspace.kgk001.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[4478] BallSocketConstraint | "Workspace.kgk001.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[4479] MeshPart | "Workspace.kgk001.LeftFoot" | Name="LeftFoot"
[4480] WrapTarget | "Workspace.kgk001.LeftFoot.LeftFoot" | Name="LeftFoot"
[4481] Attachment | "Workspace.kgk001.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[4482] Vector3Value | "Workspace.kgk001.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[4483] Attachment | "Workspace.kgk001.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[4484] Vector3Value | "Workspace.kgk001.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[4485] Vector3Value | "Workspace.kgk001.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[4486] AnimationConstraint | "Workspace.kgk001.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[4487] BallSocketConstraint | "Workspace.kgk001.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[4488] MeshPart | "Workspace.kgk001.LeftLowerLeg" | Name="LeftLowerLeg"
[4489] WrapTarget | "Workspace.kgk001.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[4490] Attachment | "Workspace.kgk001.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[4491] Vector3Value | "Workspace.kgk001.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[4492] Attachment | "Workspace.kgk001.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[4493] Vector3Value | "Workspace.kgk001.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[4494] Vector3Value | "Workspace.kgk001.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[4495] AnimationConstraint | "Workspace.kgk001.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[4496] BallSocketConstraint | "Workspace.kgk001.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[4497] MeshPart | "Workspace.kgk001.UpperTorso" | Name="UpperTorso"
[4498] WrapTarget | "Workspace.kgk001.UpperTorso.UpperTorso" | Name="UpperTorso"
[4499] Attachment | "Workspace.kgk001.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[4500] Vector3Value | "Workspace.kgk001.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[4501] Attachment | "Workspace.kgk001.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[4502] Vector3Value | "Workspace.kgk001.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[4503] Attachment | "Workspace.kgk001.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[4504] Vector3Value | "Workspace.kgk001.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[4505] Attachment | "Workspace.kgk001.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4506] Attachment | "Workspace.kgk001.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[4507] Vector3Value | "Workspace.kgk001.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[4508] Attachment | "Workspace.kgk001.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4509] Attachment | "Workspace.kgk001.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[4510] Vector3Value | "Workspace.kgk001.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[4511] Attachment | "Workspace.kgk001.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[4512] Vector3Value | "Workspace.kgk001.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[4513] Attachment | "Workspace.kgk001.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[4514] Vector3Value | "Workspace.kgk001.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[4515] Attachment | "Workspace.kgk001.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[4516] Vector3Value | "Workspace.kgk001.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[4517] Attachment | "Workspace.kgk001.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[4518] Vector3Value | "Workspace.kgk001.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[4519] Vector3Value | "Workspace.kgk001.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[4520] NoCollisionConstraint | "Workspace.kgk001.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[4521] NoCollisionConstraint | "Workspace.kgk001.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[4522] NoCollisionConstraint | "Workspace.kgk001.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[4523] NoCollisionConstraint | "Workspace.kgk001.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[4524] NoCollisionConstraint | "Workspace.kgk001.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[4525] NoCollisionConstraint | "Workspace.kgk001.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[4526] NoCollisionConstraint | "Workspace.kgk001.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[4527] AnimationConstraint | "Workspace.kgk001.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[4528] BallSocketConstraint | "Workspace.kgk001.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[4529] MeshPart | "Workspace.kgk001.LeftUpperLeg" | Name="LeftUpperLeg"
[4530] WrapTarget | "Workspace.kgk001.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[4531] Attachment | "Workspace.kgk001.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[4532] Vector3Value | "Workspace.kgk001.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[4533] Attachment | "Workspace.kgk001.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[4534] Vector3Value | "Workspace.kgk001.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[4535] Vector3Value | "Workspace.kgk001.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[4536] NoCollisionConstraint | "Workspace.kgk001.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[4537] NoCollisionConstraint | "Workspace.kgk001.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[4538] AnimationConstraint | "Workspace.kgk001.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[4539] BallSocketConstraint | "Workspace.kgk001.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[4540] MeshPart | "Workspace.kgk001.RightFoot" | Name="RightFoot"
[4541] WrapTarget | "Workspace.kgk001.RightFoot.RightFoot" | Name="RightFoot"
[4542] Attachment | "Workspace.kgk001.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[4543] Vector3Value | "Workspace.kgk001.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[4544] Attachment | "Workspace.kgk001.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[4545] Vector3Value | "Workspace.kgk001.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[4546] Vector3Value | "Workspace.kgk001.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[4547] AnimationConstraint | "Workspace.kgk001.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[4548] BallSocketConstraint | "Workspace.kgk001.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[4549] MeshPart | "Workspace.kgk001.RightLowerLeg" | Name="RightLowerLeg"
[4550] WrapTarget | "Workspace.kgk001.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[4551] Attachment | "Workspace.kgk001.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[4552] Vector3Value | "Workspace.kgk001.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[4553] Attachment | "Workspace.kgk001.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[4554] Vector3Value | "Workspace.kgk001.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[4555] Vector3Value | "Workspace.kgk001.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[4556] AnimationConstraint | "Workspace.kgk001.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[4557] BallSocketConstraint | "Workspace.kgk001.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[4558] MeshPart | "Workspace.kgk001.LowerTorso" | Name="LowerTorso"
[4559] WrapTarget | "Workspace.kgk001.LowerTorso.LowerTorso" | Name="LowerTorso"
[4560] Attachment | "Workspace.kgk001.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[4561] Vector3Value | "Workspace.kgk001.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[4562] Attachment | "Workspace.kgk001.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[4563] Vector3Value | "Workspace.kgk001.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[4564] Attachment | "Workspace.kgk001.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[4565] Vector3Value | "Workspace.kgk001.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[4566] Attachment | "Workspace.kgk001.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[4567] Vector3Value | "Workspace.kgk001.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[4568] Attachment | "Workspace.kgk001.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[4569] Vector3Value | "Workspace.kgk001.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[4570] Attachment | "Workspace.kgk001.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[4571] Vector3Value | "Workspace.kgk001.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[4572] Attachment | "Workspace.kgk001.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[4573] Vector3Value | "Workspace.kgk001.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[4574] Vector3Value | "Workspace.kgk001.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[4575] NoCollisionConstraint | "Workspace.kgk001.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[4576] NoCollisionConstraint | "Workspace.kgk001.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[4577] NoCollisionConstraint | "Workspace.kgk001.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[4578] NoCollisionConstraint | "Workspace.kgk001.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[4579] AnimationConstraint | "Workspace.kgk001.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[4580] MeshPart | "Workspace.kgk001.RightUpperLeg" | Name="RightUpperLeg"
[4581] WrapTarget | "Workspace.kgk001.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[4582] Attachment | "Workspace.kgk001.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[4583] Vector3Value | "Workspace.kgk001.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[4584] Attachment | "Workspace.kgk001.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[4585] Vector3Value | "Workspace.kgk001.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[4586] Vector3Value | "Workspace.kgk001.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[4587] NoCollisionConstraint | "Workspace.kgk001.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[4588] AnimationConstraint | "Workspace.kgk001.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[4589] BallSocketConstraint | "Workspace.kgk001.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[4590] Humanoid | "Workspace.kgk001.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[4591] Status | "Workspace.kgk001.Humanoid.Status" | Name="Status"
[4592] Animator | "Workspace.kgk001.Humanoid.Animator" | Name="Animator"
[4593] MeshPart | "Workspace.kgk001.Head" | Name="Head"
[4594] Attachment | "Workspace.kgk001.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[4595] Vector3Value | "Workspace.kgk001.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[4596] Attachment | "Workspace.kgk001.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[4597] Vector3Value | "Workspace.kgk001.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[4598] Attachment | "Workspace.kgk001.Head.HairAttachment" | Name="HairAttachment"
[4599] Vector3Value | "Workspace.kgk001.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[4600] Attachment | "Workspace.kgk001.Head.HatAttachment" | Name="HatAttachment"
[4601] Vector3Value | "Workspace.kgk001.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[4602] Attachment | "Workspace.kgk001.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[4603] Vector3Value | "Workspace.kgk001.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[4604] Vector3Value | "Workspace.kgk001.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[4605] WrapTarget | "Workspace.kgk001.Head.Head" | Name="Head"
[4606] FaceControls | "Workspace.kgk001.Head.FaceControls" | Name="FaceControls"
[4607] NoCollisionConstraint | "Workspace.kgk001.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[4608] NoCollisionConstraint | "Workspace.kgk001.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[4609] NoCollisionConstraint | "Workspace.kgk001.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[4610] AnimationConstraint | "Workspace.kgk001.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[4611] BallSocketConstraint | "Workspace.kgk001.Head.NeckBallSocket" | Name="NeckBallSocket"
[4612] Script | "Workspace.kgk001.Health" | Name="Health"
[4613] LocalScript | "Workspace.kgk001.Animate" | Name="Animate"
[4614] StringValue | "Workspace.kgk001.Animate.cheer" | Name="cheer"; Value=""
[4615] Animation | "Workspace.kgk001.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[4616] StringValue | "Workspace.kgk001.Animate.climb" | Name="climb"; Value=""
[4617] Animation | "Workspace.kgk001.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[4618] StringValue | "Workspace.kgk001.Animate.dance" | Name="dance"; Value=""
[4619] Animation | "Workspace.kgk001.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[4620] NumberValue | "Workspace.kgk001.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[4621] Animation | "Workspace.kgk001.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[4622] NumberValue | "Workspace.kgk001.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[4623] Animation | "Workspace.kgk001.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[4624] NumberValue | "Workspace.kgk001.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[4625] StringValue | "Workspace.kgk001.Animate.dance2" | Name="dance2"; Value=""
[4626] Animation | "Workspace.kgk001.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[4627] NumberValue | "Workspace.kgk001.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[4628] Animation | "Workspace.kgk001.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[4629] NumberValue | "Workspace.kgk001.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[4630] Animation | "Workspace.kgk001.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[4631] NumberValue | "Workspace.kgk001.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[4632] StringValue | "Workspace.kgk001.Animate.dance3" | Name="dance3"; Value=""
[4633] Animation | "Workspace.kgk001.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[4634] NumberValue | "Workspace.kgk001.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[4635] Animation | "Workspace.kgk001.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[4636] NumberValue | "Workspace.kgk001.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[4637] Animation | "Workspace.kgk001.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[4638] NumberValue | "Workspace.kgk001.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[4639] StringValue | "Workspace.kgk001.Animate.fall" | Name="fall"; Value=""
[4640] Animation | "Workspace.kgk001.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[4641] StringValue | "Workspace.kgk001.Animate.idle" | Name="idle"; Value=""
[4642] Animation | "Workspace.kgk001.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[4643] NumberValue | "Workspace.kgk001.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[4644] Animation | "Workspace.kgk001.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[4645] NumberValue | "Workspace.kgk001.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[4646] StringValue | "Workspace.kgk001.Animate.jump" | Name="jump"; Value=""
[4647] Animation | "Workspace.kgk001.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[4648] StringValue | "Workspace.kgk001.Animate.laugh" | Name="laugh"; Value=""
[4649] Animation | "Workspace.kgk001.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[4650] StringValue | "Workspace.kgk001.Animate.point" | Name="point"; Value=""
[4651] Animation | "Workspace.kgk001.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[4652] StringValue | "Workspace.kgk001.Animate.sit" | Name="sit"; Value=""
[4653] Animation | "Workspace.kgk001.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[4654] StringValue | "Workspace.kgk001.Animate.toollunge" | Name="toollunge"; Value=""
[4655] Animation | "Workspace.kgk001.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[4656] StringValue | "Workspace.kgk001.Animate.toolnone" | Name="toolnone"; Value=""
[4657] Animation | "Workspace.kgk001.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[4658] StringValue | "Workspace.kgk001.Animate.toolslash" | Name="toolslash"; Value=""
[4659] Animation | "Workspace.kgk001.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[4660] StringValue | "Workspace.kgk001.Animate.wave" | Name="wave"; Value=""
[4661] Animation | "Workspace.kgk001.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[4662] NumberValue | "Workspace.kgk001.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[4663] StringValue | "Workspace.kgk001.Animate.run" | Name="run"; Value=""
[4664] Animation | "Workspace.kgk001.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[4665] StringValue | "Workspace.kgk001.Animate.swim" | Name="swim"; Value=""
[4666] Animation | "Workspace.kgk001.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[4667] StringValue | "Workspace.kgk001.Animate.swimidle" | Name="swimidle"; Value=""
[4668] Animation | "Workspace.kgk001.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[4669] StringValue | "Workspace.kgk001.Animate.walk" | Name="walk"; Value=""
[4670] Animation | "Workspace.kgk001.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[4671] BindableFunction | "Workspace.kgk001.Animate.PlayEmote" | Name="PlayEmote"
[4672] StringValue | "Workspace.kgk001.Animate.mood" | Name="mood"; Value=""
[4673] Animation | "Workspace.kgk001.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[4674] AudioEmitter | "Workspace.kgk001.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[4675] Wire | "Workspace.kgk001.AudioEmitter.Wire" | Name="Wire"
[4676] Model | "Workspace.kgk001.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Default"; attr:TPS_WeaponId="AR15"
[4677] Part | "Workspace.kgk001.TPS_HeldWeapon.Handle" | Name="Handle"
[4678] Attachment | "Workspace.kgk001.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[4679] Attachment | "Workspace.kgk001.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[4680] Attachment | "Workspace.kgk001.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[4681] Motor6D | "Workspace.kgk001.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[4682] Part | "Workspace.kgk001.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"
[4683] SpecialMesh | "Workspace.kgk001.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[4684] WeldConstraint | "Workspace.kgk001.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[4685] Part | "Workspace.kgk001.TPS_HeldWeapon.Magazine" | Name="Magazine"
[4686] Weld | "Workspace.kgk001.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[4687] Attachment | "Workspace.kgk001.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[4688] Model | "Workspace.cosmickilla23" | Name="cosmickilla23"; attr:TPS_Weapon="AR15"
[4689] Part | "Workspace.cosmickilla23.HumanoidRootPart" | Name="HumanoidRootPart"
[4690] Attachment | "Workspace.cosmickilla23.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[4691] Vector3Value | "Workspace.cosmickilla23.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[4692] Vector3Value | "Workspace.cosmickilla23.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[4693] Attachment | "Workspace.cosmickilla23.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[4694] Sound | "Workspace.cosmickilla23.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[4695] Sound | "Workspace.cosmickilla23.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[4696] Sound | "Workspace.cosmickilla23.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[4697] Sound | "Workspace.cosmickilla23.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[4698] Sound | "Workspace.cosmickilla23.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[4699] Sound | "Workspace.cosmickilla23.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[4700] Sound | "Workspace.cosmickilla23.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[4701] Sound | "Workspace.cosmickilla23.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[4702] Sound | "Workspace.cosmickilla23.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[4703] MeshPart | "Workspace.cosmickilla23.LeftHand" | Name="LeftHand"
[4704] WrapTarget | "Workspace.cosmickilla23.LeftHand.LeftHand" | Name="LeftHand"
[4705] Attachment | "Workspace.cosmickilla23.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[4706] Vector3Value | "Workspace.cosmickilla23.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[4707] Attachment | "Workspace.cosmickilla23.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[4708] Vector3Value | "Workspace.cosmickilla23.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[4709] Vector3Value | "Workspace.cosmickilla23.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[4710] AnimationConstraint | "Workspace.cosmickilla23.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[4711] BallSocketConstraint | "Workspace.cosmickilla23.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[4712] MeshPart | "Workspace.cosmickilla23.RightHand" | Name="RightHand"
[4713] WrapTarget | "Workspace.cosmickilla23.RightHand.RightHand" | Name="RightHand"
[4714] Attachment | "Workspace.cosmickilla23.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[4715] Vector3Value | "Workspace.cosmickilla23.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[4716] Attachment | "Workspace.cosmickilla23.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[4717] Vector3Value | "Workspace.cosmickilla23.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[4718] Vector3Value | "Workspace.cosmickilla23.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[4719] AnimationConstraint | "Workspace.cosmickilla23.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[4720] BallSocketConstraint | "Workspace.cosmickilla23.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[4721] MeshPart | "Workspace.cosmickilla23.LeftLowerArm" | Name="LeftLowerArm"
[4722] WrapTarget | "Workspace.cosmickilla23.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[4723] Attachment | "Workspace.cosmickilla23.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[4724] Vector3Value | "Workspace.cosmickilla23.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[4725] Attachment | "Workspace.cosmickilla23.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[4726] Vector3Value | "Workspace.cosmickilla23.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[4727] Vector3Value | "Workspace.cosmickilla23.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[4728] AnimationConstraint | "Workspace.cosmickilla23.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[4729] BallSocketConstraint | "Workspace.cosmickilla23.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[4730] MeshPart | "Workspace.cosmickilla23.RightLowerArm" | Name="RightLowerArm"
[4731] WrapTarget | "Workspace.cosmickilla23.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[4732] Attachment | "Workspace.cosmickilla23.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[4733] Vector3Value | "Workspace.cosmickilla23.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[4734] Attachment | "Workspace.cosmickilla23.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[4735] Vector3Value | "Workspace.cosmickilla23.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[4736] Vector3Value | "Workspace.cosmickilla23.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[4737] AnimationConstraint | "Workspace.cosmickilla23.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[4738] BallSocketConstraint | "Workspace.cosmickilla23.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[4739] MeshPart | "Workspace.cosmickilla23.LeftUpperArm" | Name="LeftUpperArm"
[4740] WrapTarget | "Workspace.cosmickilla23.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[4741] Attachment | "Workspace.cosmickilla23.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[4742] Vector3Value | "Workspace.cosmickilla23.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[4743] Attachment | "Workspace.cosmickilla23.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4744] Attachment | "Workspace.cosmickilla23.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[4745] Vector3Value | "Workspace.cosmickilla23.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[4746] Attachment | "Workspace.cosmickilla23.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[4747] Vector3Value | "Workspace.cosmickilla23.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[4748] Vector3Value | "Workspace.cosmickilla23.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[4749] NoCollisionConstraint | "Workspace.cosmickilla23.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[4750] AnimationConstraint | "Workspace.cosmickilla23.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[4751] BallSocketConstraint | "Workspace.cosmickilla23.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[4752] MeshPart | "Workspace.cosmickilla23.RightUpperArm" | Name="RightUpperArm"
[4753] WrapTarget | "Workspace.cosmickilla23.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[4754] Attachment | "Workspace.cosmickilla23.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[4755] Vector3Value | "Workspace.cosmickilla23.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[4756] Attachment | "Workspace.cosmickilla23.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4757] Attachment | "Workspace.cosmickilla23.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[4758] Vector3Value | "Workspace.cosmickilla23.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[4759] Attachment | "Workspace.cosmickilla23.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[4760] Vector3Value | "Workspace.cosmickilla23.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[4761] Vector3Value | "Workspace.cosmickilla23.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[4762] NoCollisionConstraint | "Workspace.cosmickilla23.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[4763] AnimationConstraint | "Workspace.cosmickilla23.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[4764] BallSocketConstraint | "Workspace.cosmickilla23.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[4765] MeshPart | "Workspace.cosmickilla23.LeftFoot" | Name="LeftFoot"
[4766] WrapTarget | "Workspace.cosmickilla23.LeftFoot.LeftFoot" | Name="LeftFoot"
[4767] Attachment | "Workspace.cosmickilla23.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[4768] Vector3Value | "Workspace.cosmickilla23.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[4769] Attachment | "Workspace.cosmickilla23.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[4770] Vector3Value | "Workspace.cosmickilla23.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[4771] Vector3Value | "Workspace.cosmickilla23.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[4772] AnimationConstraint | "Workspace.cosmickilla23.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[4773] BallSocketConstraint | "Workspace.cosmickilla23.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[4774] MeshPart | "Workspace.cosmickilla23.LeftLowerLeg" | Name="LeftLowerLeg"
[4775] WrapTarget | "Workspace.cosmickilla23.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[4776] Attachment | "Workspace.cosmickilla23.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[4777] Vector3Value | "Workspace.cosmickilla23.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[4778] Attachment | "Workspace.cosmickilla23.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[4779] Vector3Value | "Workspace.cosmickilla23.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[4780] Vector3Value | "Workspace.cosmickilla23.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[4781] AnimationConstraint | "Workspace.cosmickilla23.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[4782] BallSocketConstraint | "Workspace.cosmickilla23.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[4783] MeshPart | "Workspace.cosmickilla23.UpperTorso" | Name="UpperTorso"
[4784] WrapTarget | "Workspace.cosmickilla23.UpperTorso.UpperTorso" | Name="UpperTorso"
[4785] Attachment | "Workspace.cosmickilla23.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[4786] Vector3Value | "Workspace.cosmickilla23.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[4787] Attachment | "Workspace.cosmickilla23.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[4788] Vector3Value | "Workspace.cosmickilla23.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[4789] Attachment | "Workspace.cosmickilla23.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[4790] Vector3Value | "Workspace.cosmickilla23.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[4791] Attachment | "Workspace.cosmickilla23.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4792] Attachment | "Workspace.cosmickilla23.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[4793] Vector3Value | "Workspace.cosmickilla23.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[4794] Attachment | "Workspace.cosmickilla23.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[4795] Attachment | "Workspace.cosmickilla23.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[4796] Vector3Value | "Workspace.cosmickilla23.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[4797] Attachment | "Workspace.cosmickilla23.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[4798] Vector3Value | "Workspace.cosmickilla23.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[4799] Attachment | "Workspace.cosmickilla23.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[4800] Vector3Value | "Workspace.cosmickilla23.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[4801] Attachment | "Workspace.cosmickilla23.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[4802] Vector3Value | "Workspace.cosmickilla23.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[4803] Attachment | "Workspace.cosmickilla23.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[4804] Vector3Value | "Workspace.cosmickilla23.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[4805] Vector3Value | "Workspace.cosmickilla23.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[4806] NoCollisionConstraint | "Workspace.cosmickilla23.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[4807] NoCollisionConstraint | "Workspace.cosmickilla23.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[4808] NoCollisionConstraint | "Workspace.cosmickilla23.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[4809] NoCollisionConstraint | "Workspace.cosmickilla23.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[4810] NoCollisionConstraint | "Workspace.cosmickilla23.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[4811] NoCollisionConstraint | "Workspace.cosmickilla23.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[4812] NoCollisionConstraint | "Workspace.cosmickilla23.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[4813] AnimationConstraint | "Workspace.cosmickilla23.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[4814] BallSocketConstraint | "Workspace.cosmickilla23.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[4815] MeshPart | "Workspace.cosmickilla23.LeftUpperLeg" | Name="LeftUpperLeg"
[4816] WrapTarget | "Workspace.cosmickilla23.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[4817] Attachment | "Workspace.cosmickilla23.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[4818] Vector3Value | "Workspace.cosmickilla23.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[4819] Attachment | "Workspace.cosmickilla23.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[4820] Vector3Value | "Workspace.cosmickilla23.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[4821] Vector3Value | "Workspace.cosmickilla23.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[4822] NoCollisionConstraint | "Workspace.cosmickilla23.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[4823] NoCollisionConstraint | "Workspace.cosmickilla23.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[4824] AnimationConstraint | "Workspace.cosmickilla23.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[4825] BallSocketConstraint | "Workspace.cosmickilla23.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[4826] MeshPart | "Workspace.cosmickilla23.RightFoot" | Name="RightFoot"
[4827] WrapTarget | "Workspace.cosmickilla23.RightFoot.RightFoot" | Name="RightFoot"
[4828] Attachment | "Workspace.cosmickilla23.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[4829] Vector3Value | "Workspace.cosmickilla23.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[4830] Attachment | "Workspace.cosmickilla23.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[4831] Vector3Value | "Workspace.cosmickilla23.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[4832] Vector3Value | "Workspace.cosmickilla23.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[4833] AnimationConstraint | "Workspace.cosmickilla23.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[4834] BallSocketConstraint | "Workspace.cosmickilla23.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[4835] MeshPart | "Workspace.cosmickilla23.RightLowerLeg" | Name="RightLowerLeg"
[4836] WrapTarget | "Workspace.cosmickilla23.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[4837] Attachment | "Workspace.cosmickilla23.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[4838] Vector3Value | "Workspace.cosmickilla23.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[4839] Attachment | "Workspace.cosmickilla23.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[4840] Vector3Value | "Workspace.cosmickilla23.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[4841] Vector3Value | "Workspace.cosmickilla23.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[4842] AnimationConstraint | "Workspace.cosmickilla23.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[4843] BallSocketConstraint | "Workspace.cosmickilla23.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[4844] MeshPart | "Workspace.cosmickilla23.LowerTorso" | Name="LowerTorso"
[4845] WrapTarget | "Workspace.cosmickilla23.LowerTorso.LowerTorso" | Name="LowerTorso"
[4846] Attachment | "Workspace.cosmickilla23.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[4847] Vector3Value | "Workspace.cosmickilla23.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[4848] Attachment | "Workspace.cosmickilla23.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[4849] Vector3Value | "Workspace.cosmickilla23.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[4850] Attachment | "Workspace.cosmickilla23.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[4851] Vector3Value | "Workspace.cosmickilla23.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[4852] Attachment | "Workspace.cosmickilla23.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[4853] Vector3Value | "Workspace.cosmickilla23.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[4854] Attachment | "Workspace.cosmickilla23.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[4855] Vector3Value | "Workspace.cosmickilla23.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[4856] Attachment | "Workspace.cosmickilla23.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[4857] Vector3Value | "Workspace.cosmickilla23.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[4858] Attachment | "Workspace.cosmickilla23.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[4859] Vector3Value | "Workspace.cosmickilla23.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[4860] Vector3Value | "Workspace.cosmickilla23.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[4861] NoCollisionConstraint | "Workspace.cosmickilla23.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[4862] NoCollisionConstraint | "Workspace.cosmickilla23.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[4863] NoCollisionConstraint | "Workspace.cosmickilla23.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[4864] NoCollisionConstraint | "Workspace.cosmickilla23.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[4865] AnimationConstraint | "Workspace.cosmickilla23.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[4866] MeshPart | "Workspace.cosmickilla23.RightUpperLeg" | Name="RightUpperLeg"
[4867] WrapTarget | "Workspace.cosmickilla23.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[4868] Attachment | "Workspace.cosmickilla23.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[4869] Vector3Value | "Workspace.cosmickilla23.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[4870] Attachment | "Workspace.cosmickilla23.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[4871] Vector3Value | "Workspace.cosmickilla23.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[4872] Vector3Value | "Workspace.cosmickilla23.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[4873] NoCollisionConstraint | "Workspace.cosmickilla23.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[4874] AnimationConstraint | "Workspace.cosmickilla23.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[4875] BallSocketConstraint | "Workspace.cosmickilla23.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[4876] Humanoid | "Workspace.cosmickilla23.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[4877] Status | "Workspace.cosmickilla23.Humanoid.Status" | Name="Status"
[4878] Animator | "Workspace.cosmickilla23.Humanoid.Animator" | Name="Animator"
[4879] MeshPart | "Workspace.cosmickilla23.Head" | Name="Head"
[4880] Attachment | "Workspace.cosmickilla23.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[4881] Vector3Value | "Workspace.cosmickilla23.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[4882] Attachment | "Workspace.cosmickilla23.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[4883] Vector3Value | "Workspace.cosmickilla23.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[4884] Attachment | "Workspace.cosmickilla23.Head.HairAttachment" | Name="HairAttachment"
[4885] Vector3Value | "Workspace.cosmickilla23.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[4886] Attachment | "Workspace.cosmickilla23.Head.HatAttachment" | Name="HatAttachment"
[4887] Vector3Value | "Workspace.cosmickilla23.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[4888] Attachment | "Workspace.cosmickilla23.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[4889] Vector3Value | "Workspace.cosmickilla23.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[4890] Vector3Value | "Workspace.cosmickilla23.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[4891] WrapTarget | "Workspace.cosmickilla23.Head.Head" | Name="Head"
[4892] FaceControls | "Workspace.cosmickilla23.Head.FaceControls" | Name="FaceControls"
[4893] NoCollisionConstraint | "Workspace.cosmickilla23.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[4894] NoCollisionConstraint | "Workspace.cosmickilla23.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[4895] NoCollisionConstraint | "Workspace.cosmickilla23.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[4896] AnimationConstraint | "Workspace.cosmickilla23.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[4897] BallSocketConstraint | "Workspace.cosmickilla23.Head.NeckBallSocket" | Name="NeckBallSocket"
[4898] Script | "Workspace.cosmickilla23.Health" | Name="Health"
[4899] LocalScript | "Workspace.cosmickilla23.Animate" | Name="Animate"
[4900] StringValue | "Workspace.cosmickilla23.Animate.cheer" | Name="cheer"; Value=""
[4901] Animation | "Workspace.cosmickilla23.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[4902] StringValue | "Workspace.cosmickilla23.Animate.climb" | Name="climb"; Value=""
[4903] Animation | "Workspace.cosmickilla23.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[4904] StringValue | "Workspace.cosmickilla23.Animate.dance" | Name="dance"; Value=""
[4905] Animation | "Workspace.cosmickilla23.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[4906] NumberValue | "Workspace.cosmickilla23.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[4907] Animation | "Workspace.cosmickilla23.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[4908] NumberValue | "Workspace.cosmickilla23.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[4909] Animation | "Workspace.cosmickilla23.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[4910] NumberValue | "Workspace.cosmickilla23.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[4911] StringValue | "Workspace.cosmickilla23.Animate.dance2" | Name="dance2"; Value=""
[4912] Animation | "Workspace.cosmickilla23.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[4913] NumberValue | "Workspace.cosmickilla23.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[4914] Animation | "Workspace.cosmickilla23.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[4915] NumberValue | "Workspace.cosmickilla23.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[4916] Animation | "Workspace.cosmickilla23.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[4917] NumberValue | "Workspace.cosmickilla23.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[4918] StringValue | "Workspace.cosmickilla23.Animate.dance3" | Name="dance3"; Value=""
[4919] Animation | "Workspace.cosmickilla23.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[4920] NumberValue | "Workspace.cosmickilla23.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[4921] Animation | "Workspace.cosmickilla23.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[4922] NumberValue | "Workspace.cosmickilla23.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[4923] Animation | "Workspace.cosmickilla23.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[4924] NumberValue | "Workspace.cosmickilla23.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[4925] StringValue | "Workspace.cosmickilla23.Animate.fall" | Name="fall"; Value=""
[4926] Animation | "Workspace.cosmickilla23.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[4927] StringValue | "Workspace.cosmickilla23.Animate.idle" | Name="idle"; Value=""
[4928] Animation | "Workspace.cosmickilla23.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[4929] NumberValue | "Workspace.cosmickilla23.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[4930] Animation | "Workspace.cosmickilla23.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[4931] NumberValue | "Workspace.cosmickilla23.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[4932] StringValue | "Workspace.cosmickilla23.Animate.jump" | Name="jump"; Value=""
[4933] Animation | "Workspace.cosmickilla23.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[4934] StringValue | "Workspace.cosmickilla23.Animate.laugh" | Name="laugh"; Value=""
[4935] Animation | "Workspace.cosmickilla23.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[4936] StringValue | "Workspace.cosmickilla23.Animate.point" | Name="point"; Value=""
[4937] Animation | "Workspace.cosmickilla23.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[4938] StringValue | "Workspace.cosmickilla23.Animate.sit" | Name="sit"; Value=""
[4939] Animation | "Workspace.cosmickilla23.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[4940] StringValue | "Workspace.cosmickilla23.Animate.toollunge" | Name="toollunge"; Value=""
[4941] Animation | "Workspace.cosmickilla23.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[4942] StringValue | "Workspace.cosmickilla23.Animate.toolnone" | Name="toolnone"; Value=""
[4943] Animation | "Workspace.cosmickilla23.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[4944] StringValue | "Workspace.cosmickilla23.Animate.toolslash" | Name="toolslash"; Value=""
[4945] Animation | "Workspace.cosmickilla23.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[4946] StringValue | "Workspace.cosmickilla23.Animate.wave" | Name="wave"; Value=""
[4947] Animation | "Workspace.cosmickilla23.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[4948] NumberValue | "Workspace.cosmickilla23.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[4949] StringValue | "Workspace.cosmickilla23.Animate.run" | Name="run"; Value=""
[4950] Animation | "Workspace.cosmickilla23.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[4951] StringValue | "Workspace.cosmickilla23.Animate.swim" | Name="swim"; Value=""
[4952] Animation | "Workspace.cosmickilla23.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[4953] StringValue | "Workspace.cosmickilla23.Animate.swimidle" | Name="swimidle"; Value=""
[4954] Animation | "Workspace.cosmickilla23.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[4955] StringValue | "Workspace.cosmickilla23.Animate.walk" | Name="walk"; Value=""
[4956] Animation | "Workspace.cosmickilla23.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[4957] BindableFunction | "Workspace.cosmickilla23.Animate.PlayEmote" | Name="PlayEmote"
[4958] StringValue | "Workspace.cosmickilla23.Animate.mood" | Name="mood"; Value=""
[4959] Animation | "Workspace.cosmickilla23.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[4960] AudioEmitter | "Workspace.cosmickilla23.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[4961] Wire | "Workspace.cosmickilla23.AudioEmitter.Wire" | Name="Wire"
[4962] Model | "Workspace.cosmickilla23.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="ChallengeBloodsport"; attr:TPS_WeaponId="AR15"
[4963] Part | "Workspace.cosmickilla23.TPS_HeldWeapon.Handle" | Name="Handle"
[4964] Attachment | "Workspace.cosmickilla23.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[4965] Attachment | "Workspace.cosmickilla23.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[4966] Attachment | "Workspace.cosmickilla23.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[4967] Motor6D | "Workspace.cosmickilla23.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[4968] Part | "Workspace.cosmickilla23.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"; attr:R1_SkinHidden=true
[4969] SpecialMesh | "Workspace.cosmickilla23.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[4970] WeldConstraint | "Workspace.cosmickilla23.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[4971] Part | "Workspace.cosmickilla23.TPS_HeldWeapon.Magazine" | Name="Magazine"
[4972] Weld | "Workspace.cosmickilla23.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[4973] Attachment | "Workspace.cosmickilla23.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[4974] MeshPart | "Workspace.cosmickilla23.TPS_HeldWeapon.R1_SkinBody" | Name="R1_SkinBody"
[4975] WeldConstraint | "Workspace.cosmickilla23.TPS_HeldWeapon.R1_SkinBody.WeldConstraint" | Name="WeldConstraint"
[4976] SurfaceAppearance | "Workspace.cosmickilla23.TPS_HeldWeapon.R1_SkinBody.AR15_Bloodsport" | Name="AR15_Bloodsport"
[4977] Model | "Workspace.krokodyl820" | Name="krokodyl820"; attr:TPS_Weapon="AR15"
[4978] Part | "Workspace.krokodyl820.HumanoidRootPart" | Name="HumanoidRootPart"
[4979] Attachment | "Workspace.krokodyl820.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[4980] Vector3Value | "Workspace.krokodyl820.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[4981] Vector3Value | "Workspace.krokodyl820.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[4982] Attachment | "Workspace.krokodyl820.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[4983] Sound | "Workspace.krokodyl820.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[4984] Sound | "Workspace.krokodyl820.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[4985] Sound | "Workspace.krokodyl820.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[4986] Sound | "Workspace.krokodyl820.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[4987] Sound | "Workspace.krokodyl820.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[4988] Sound | "Workspace.krokodyl820.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[4989] Sound | "Workspace.krokodyl820.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[4990] Sound | "Workspace.krokodyl820.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[4991] Sound | "Workspace.krokodyl820.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[4992] MeshPart | "Workspace.krokodyl820.LeftHand" | Name="LeftHand"
[4993] WrapTarget | "Workspace.krokodyl820.LeftHand.LeftHand" | Name="LeftHand"
[4994] Attachment | "Workspace.krokodyl820.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[4995] Vector3Value | "Workspace.krokodyl820.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[4996] Attachment | "Workspace.krokodyl820.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[4997] Vector3Value | "Workspace.krokodyl820.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[4998] Vector3Value | "Workspace.krokodyl820.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[4999] AnimationConstraint | "Workspace.krokodyl820.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[5000] BallSocketConstraint | "Workspace.krokodyl820.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[5001] MeshPart | "Workspace.krokodyl820.RightHand" | Name="RightHand"
[5002] WrapTarget | "Workspace.krokodyl820.RightHand.RightHand" | Name="RightHand"
[5003] Attachment | "Workspace.krokodyl820.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[5004] Vector3Value | "Workspace.krokodyl820.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[5005] Attachment | "Workspace.krokodyl820.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[5006] Vector3Value | "Workspace.krokodyl820.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[5007] Vector3Value | "Workspace.krokodyl820.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[5008] AnimationConstraint | "Workspace.krokodyl820.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[5009] BallSocketConstraint | "Workspace.krokodyl820.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[5010] MeshPart | "Workspace.krokodyl820.LeftLowerArm" | Name="LeftLowerArm"
[5011] WrapTarget | "Workspace.krokodyl820.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[5012] Attachment | "Workspace.krokodyl820.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[5013] Vector3Value | "Workspace.krokodyl820.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[5014] Attachment | "Workspace.krokodyl820.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[5015] Vector3Value | "Workspace.krokodyl820.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[5016] Vector3Value | "Workspace.krokodyl820.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[5017] AnimationConstraint | "Workspace.krokodyl820.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[5018] BallSocketConstraint | "Workspace.krokodyl820.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[5019] MeshPart | "Workspace.krokodyl820.RightLowerArm" | Name="RightLowerArm"
[5020] WrapTarget | "Workspace.krokodyl820.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[5021] Attachment | "Workspace.krokodyl820.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[5022] Vector3Value | "Workspace.krokodyl820.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[5023] Attachment | "Workspace.krokodyl820.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[5024] Vector3Value | "Workspace.krokodyl820.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[5025] Vector3Value | "Workspace.krokodyl820.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[5026] AnimationConstraint | "Workspace.krokodyl820.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[5027] BallSocketConstraint | "Workspace.krokodyl820.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[5028] MeshPart | "Workspace.krokodyl820.LeftUpperArm" | Name="LeftUpperArm"
[5029] WrapTarget | "Workspace.krokodyl820.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[5030] Attachment | "Workspace.krokodyl820.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[5031] Vector3Value | "Workspace.krokodyl820.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[5032] Attachment | "Workspace.krokodyl820.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5033] Attachment | "Workspace.krokodyl820.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[5034] Vector3Value | "Workspace.krokodyl820.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[5035] Attachment | "Workspace.krokodyl820.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[5036] Vector3Value | "Workspace.krokodyl820.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[5037] Vector3Value | "Workspace.krokodyl820.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[5038] NoCollisionConstraint | "Workspace.krokodyl820.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[5039] AnimationConstraint | "Workspace.krokodyl820.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[5040] BallSocketConstraint | "Workspace.krokodyl820.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[5041] MeshPart | "Workspace.krokodyl820.RightUpperArm" | Name="RightUpperArm"
[5042] WrapTarget | "Workspace.krokodyl820.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[5043] Attachment | "Workspace.krokodyl820.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[5044] Vector3Value | "Workspace.krokodyl820.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[5045] Attachment | "Workspace.krokodyl820.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5046] Attachment | "Workspace.krokodyl820.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[5047] Vector3Value | "Workspace.krokodyl820.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[5048] Attachment | "Workspace.krokodyl820.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[5049] Vector3Value | "Workspace.krokodyl820.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[5050] Vector3Value | "Workspace.krokodyl820.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[5051] NoCollisionConstraint | "Workspace.krokodyl820.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[5052] AnimationConstraint | "Workspace.krokodyl820.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[5053] BallSocketConstraint | "Workspace.krokodyl820.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[5054] MeshPart | "Workspace.krokodyl820.LeftFoot" | Name="LeftFoot"
[5055] WrapTarget | "Workspace.krokodyl820.LeftFoot.LeftFoot" | Name="LeftFoot"
[5056] Attachment | "Workspace.krokodyl820.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[5057] Vector3Value | "Workspace.krokodyl820.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[5058] Attachment | "Workspace.krokodyl820.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[5059] Vector3Value | "Workspace.krokodyl820.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[5060] Vector3Value | "Workspace.krokodyl820.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[5061] AnimationConstraint | "Workspace.krokodyl820.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[5062] BallSocketConstraint | "Workspace.krokodyl820.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[5063] MeshPart | "Workspace.krokodyl820.LeftLowerLeg" | Name="LeftLowerLeg"
[5064] WrapTarget | "Workspace.krokodyl820.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[5065] Attachment | "Workspace.krokodyl820.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[5066] Vector3Value | "Workspace.krokodyl820.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[5067] Attachment | "Workspace.krokodyl820.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[5068] Vector3Value | "Workspace.krokodyl820.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[5069] Vector3Value | "Workspace.krokodyl820.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[5070] AnimationConstraint | "Workspace.krokodyl820.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[5071] BallSocketConstraint | "Workspace.krokodyl820.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[5072] MeshPart | "Workspace.krokodyl820.UpperTorso" | Name="UpperTorso"
[5073] WrapTarget | "Workspace.krokodyl820.UpperTorso.UpperTorso" | Name="UpperTorso"
[5074] Attachment | "Workspace.krokodyl820.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[5075] Vector3Value | "Workspace.krokodyl820.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[5076] Attachment | "Workspace.krokodyl820.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[5077] Vector3Value | "Workspace.krokodyl820.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[5078] Attachment | "Workspace.krokodyl820.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[5079] Vector3Value | "Workspace.krokodyl820.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[5080] Attachment | "Workspace.krokodyl820.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5081] Attachment | "Workspace.krokodyl820.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[5082] Vector3Value | "Workspace.krokodyl820.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[5083] Attachment | "Workspace.krokodyl820.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5084] Attachment | "Workspace.krokodyl820.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[5085] Vector3Value | "Workspace.krokodyl820.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[5086] Attachment | "Workspace.krokodyl820.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[5087] Vector3Value | "Workspace.krokodyl820.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[5088] Attachment | "Workspace.krokodyl820.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[5089] Vector3Value | "Workspace.krokodyl820.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[5090] Attachment | "Workspace.krokodyl820.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[5091] Vector3Value | "Workspace.krokodyl820.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[5092] Attachment | "Workspace.krokodyl820.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[5093] Vector3Value | "Workspace.krokodyl820.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[5094] Vector3Value | "Workspace.krokodyl820.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[5095] NoCollisionConstraint | "Workspace.krokodyl820.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[5096] NoCollisionConstraint | "Workspace.krokodyl820.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[5097] NoCollisionConstraint | "Workspace.krokodyl820.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[5098] NoCollisionConstraint | "Workspace.krokodyl820.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[5099] NoCollisionConstraint | "Workspace.krokodyl820.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[5100] NoCollisionConstraint | "Workspace.krokodyl820.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[5101] NoCollisionConstraint | "Workspace.krokodyl820.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[5102] AnimationConstraint | "Workspace.krokodyl820.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[5103] BallSocketConstraint | "Workspace.krokodyl820.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[5104] MeshPart | "Workspace.krokodyl820.LeftUpperLeg" | Name="LeftUpperLeg"
[5105] WrapTarget | "Workspace.krokodyl820.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[5106] Attachment | "Workspace.krokodyl820.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[5107] Vector3Value | "Workspace.krokodyl820.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[5108] Attachment | "Workspace.krokodyl820.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[5109] Vector3Value | "Workspace.krokodyl820.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[5110] Vector3Value | "Workspace.krokodyl820.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[5111] NoCollisionConstraint | "Workspace.krokodyl820.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[5112] NoCollisionConstraint | "Workspace.krokodyl820.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[5113] AnimationConstraint | "Workspace.krokodyl820.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[5114] BallSocketConstraint | "Workspace.krokodyl820.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[5115] MeshPart | "Workspace.krokodyl820.RightFoot" | Name="RightFoot"
[5116] WrapTarget | "Workspace.krokodyl820.RightFoot.RightFoot" | Name="RightFoot"
[5117] Attachment | "Workspace.krokodyl820.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[5118] Vector3Value | "Workspace.krokodyl820.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[5119] Attachment | "Workspace.krokodyl820.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[5120] Vector3Value | "Workspace.krokodyl820.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[5121] Vector3Value | "Workspace.krokodyl820.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[5122] AnimationConstraint | "Workspace.krokodyl820.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[5123] BallSocketConstraint | "Workspace.krokodyl820.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[5124] MeshPart | "Workspace.krokodyl820.RightLowerLeg" | Name="RightLowerLeg"
[5125] WrapTarget | "Workspace.krokodyl820.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[5126] Attachment | "Workspace.krokodyl820.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[5127] Vector3Value | "Workspace.krokodyl820.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[5128] Attachment | "Workspace.krokodyl820.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[5129] Vector3Value | "Workspace.krokodyl820.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[5130] Vector3Value | "Workspace.krokodyl820.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[5131] AnimationConstraint | "Workspace.krokodyl820.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[5132] BallSocketConstraint | "Workspace.krokodyl820.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[5133] MeshPart | "Workspace.krokodyl820.LowerTorso" | Name="LowerTorso"
[5134] WrapTarget | "Workspace.krokodyl820.LowerTorso.LowerTorso" | Name="LowerTorso"
[5135] Attachment | "Workspace.krokodyl820.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[5136] Vector3Value | "Workspace.krokodyl820.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[5137] Attachment | "Workspace.krokodyl820.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[5138] Vector3Value | "Workspace.krokodyl820.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[5139] Attachment | "Workspace.krokodyl820.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[5140] Vector3Value | "Workspace.krokodyl820.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[5141] Attachment | "Workspace.krokodyl820.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[5142] Vector3Value | "Workspace.krokodyl820.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[5143] Attachment | "Workspace.krokodyl820.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[5144] Vector3Value | "Workspace.krokodyl820.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[5145] Attachment | "Workspace.krokodyl820.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[5146] Vector3Value | "Workspace.krokodyl820.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[5147] Attachment | "Workspace.krokodyl820.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[5148] Vector3Value | "Workspace.krokodyl820.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[5149] Vector3Value | "Workspace.krokodyl820.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[5150] NoCollisionConstraint | "Workspace.krokodyl820.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[5151] NoCollisionConstraint | "Workspace.krokodyl820.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[5152] NoCollisionConstraint | "Workspace.krokodyl820.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[5153] NoCollisionConstraint | "Workspace.krokodyl820.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[5154] AnimationConstraint | "Workspace.krokodyl820.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[5155] MeshPart | "Workspace.krokodyl820.RightUpperLeg" | Name="RightUpperLeg"
[5156] WrapTarget | "Workspace.krokodyl820.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[5157] Attachment | "Workspace.krokodyl820.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[5158] Vector3Value | "Workspace.krokodyl820.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[5159] Attachment | "Workspace.krokodyl820.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[5160] Vector3Value | "Workspace.krokodyl820.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[5161] Vector3Value | "Workspace.krokodyl820.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[5162] NoCollisionConstraint | "Workspace.krokodyl820.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[5163] AnimationConstraint | "Workspace.krokodyl820.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[5164] BallSocketConstraint | "Workspace.krokodyl820.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[5165] Humanoid | "Workspace.krokodyl820.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[5166] Status | "Workspace.krokodyl820.Humanoid.Status" | Name="Status"
[5167] Animator | "Workspace.krokodyl820.Humanoid.Animator" | Name="Animator"
[5168] MeshPart | "Workspace.krokodyl820.Head" | Name="Head"
[5169] Attachment | "Workspace.krokodyl820.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[5170] Vector3Value | "Workspace.krokodyl820.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[5171] Attachment | "Workspace.krokodyl820.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[5172] Vector3Value | "Workspace.krokodyl820.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[5173] Attachment | "Workspace.krokodyl820.Head.HairAttachment" | Name="HairAttachment"
[5174] Vector3Value | "Workspace.krokodyl820.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[5175] Attachment | "Workspace.krokodyl820.Head.HatAttachment" | Name="HatAttachment"
[5176] Vector3Value | "Workspace.krokodyl820.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[5177] Attachment | "Workspace.krokodyl820.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[5178] Vector3Value | "Workspace.krokodyl820.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[5179] Vector3Value | "Workspace.krokodyl820.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[5180] WrapTarget | "Workspace.krokodyl820.Head.Head" | Name="Head"
[5181] FaceControls | "Workspace.krokodyl820.Head.FaceControls" | Name="FaceControls"
[5182] NoCollisionConstraint | "Workspace.krokodyl820.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[5183] NoCollisionConstraint | "Workspace.krokodyl820.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[5184] NoCollisionConstraint | "Workspace.krokodyl820.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[5185] AnimationConstraint | "Workspace.krokodyl820.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[5186] BallSocketConstraint | "Workspace.krokodyl820.Head.NeckBallSocket" | Name="NeckBallSocket"
[5187] Script | "Workspace.krokodyl820.Health" | Name="Health"
[5188] LocalScript | "Workspace.krokodyl820.Animate" | Name="Animate"
[5189] StringValue | "Workspace.krokodyl820.Animate.cheer" | Name="cheer"; Value=""
[5190] Animation | "Workspace.krokodyl820.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[5191] StringValue | "Workspace.krokodyl820.Animate.climb" | Name="climb"; Value=""
[5192] Animation | "Workspace.krokodyl820.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[5193] StringValue | "Workspace.krokodyl820.Animate.dance" | Name="dance"; Value=""
[5194] Animation | "Workspace.krokodyl820.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[5195] NumberValue | "Workspace.krokodyl820.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[5196] Animation | "Workspace.krokodyl820.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[5197] NumberValue | "Workspace.krokodyl820.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[5198] Animation | "Workspace.krokodyl820.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[5199] NumberValue | "Workspace.krokodyl820.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[5200] StringValue | "Workspace.krokodyl820.Animate.dance2" | Name="dance2"; Value=""
[5201] Animation | "Workspace.krokodyl820.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[5202] NumberValue | "Workspace.krokodyl820.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[5203] Animation | "Workspace.krokodyl820.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[5204] NumberValue | "Workspace.krokodyl820.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[5205] Animation | "Workspace.krokodyl820.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[5206] NumberValue | "Workspace.krokodyl820.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[5207] StringValue | "Workspace.krokodyl820.Animate.dance3" | Name="dance3"; Value=""
[5208] Animation | "Workspace.krokodyl820.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[5209] NumberValue | "Workspace.krokodyl820.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[5210] Animation | "Workspace.krokodyl820.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[5211] NumberValue | "Workspace.krokodyl820.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[5212] Animation | "Workspace.krokodyl820.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[5213] NumberValue | "Workspace.krokodyl820.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[5214] StringValue | "Workspace.krokodyl820.Animate.fall" | Name="fall"; Value=""
[5215] Animation | "Workspace.krokodyl820.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[5216] StringValue | "Workspace.krokodyl820.Animate.idle" | Name="idle"; Value=""
[5217] Animation | "Workspace.krokodyl820.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[5218] NumberValue | "Workspace.krokodyl820.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[5219] Animation | "Workspace.krokodyl820.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[5220] NumberValue | "Workspace.krokodyl820.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[5221] StringValue | "Workspace.krokodyl820.Animate.jump" | Name="jump"; Value=""
[5222] Animation | "Workspace.krokodyl820.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[5223] StringValue | "Workspace.krokodyl820.Animate.laugh" | Name="laugh"; Value=""
[5224] Animation | "Workspace.krokodyl820.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[5225] StringValue | "Workspace.krokodyl820.Animate.point" | Name="point"; Value=""
[5226] Animation | "Workspace.krokodyl820.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[5227] StringValue | "Workspace.krokodyl820.Animate.sit" | Name="sit"; Value=""
[5228] Animation | "Workspace.krokodyl820.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[5229] StringValue | "Workspace.krokodyl820.Animate.toollunge" | Name="toollunge"; Value=""
[5230] Animation | "Workspace.krokodyl820.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[5231] StringValue | "Workspace.krokodyl820.Animate.toolnone" | Name="toolnone"; Value=""
[5232] Animation | "Workspace.krokodyl820.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[5233] StringValue | "Workspace.krokodyl820.Animate.toolslash" | Name="toolslash"; Value=""
[5234] Animation | "Workspace.krokodyl820.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[5235] StringValue | "Workspace.krokodyl820.Animate.wave" | Name="wave"; Value=""
[5236] Animation | "Workspace.krokodyl820.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[5237] NumberValue | "Workspace.krokodyl820.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[5238] StringValue | "Workspace.krokodyl820.Animate.run" | Name="run"; Value=""
[5239] Animation | "Workspace.krokodyl820.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[5240] StringValue | "Workspace.krokodyl820.Animate.swim" | Name="swim"; Value=""
[5241] Animation | "Workspace.krokodyl820.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[5242] StringValue | "Workspace.krokodyl820.Animate.swimidle" | Name="swimidle"; Value=""
[5243] Animation | "Workspace.krokodyl820.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[5244] StringValue | "Workspace.krokodyl820.Animate.walk" | Name="walk"; Value=""
[5245] Animation | "Workspace.krokodyl820.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[5246] BindableFunction | "Workspace.krokodyl820.Animate.PlayEmote" | Name="PlayEmote"
[5247] StringValue | "Workspace.krokodyl820.Animate.mood" | Name="mood"; Value=""
[5248] Animation | "Workspace.krokodyl820.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[5249] AudioEmitter | "Workspace.krokodyl820.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[5250] Wire | "Workspace.krokodyl820.AudioEmitter.Wire" | Name="Wire"
[5251] Model | "Workspace.krokodyl820.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Default"; attr:TPS_WeaponId="AR15"
[5252] Part | "Workspace.krokodyl820.TPS_HeldWeapon.Handle" | Name="Handle"
[5253] Attachment | "Workspace.krokodyl820.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[5254] Attachment | "Workspace.krokodyl820.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[5255] Attachment | "Workspace.krokodyl820.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[5256] Motor6D | "Workspace.krokodyl820.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[5257] Part | "Workspace.krokodyl820.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"
[5258] SpecialMesh | "Workspace.krokodyl820.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[5259] WeldConstraint | "Workspace.krokodyl820.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[5260] Part | "Workspace.krokodyl820.TPS_HeldWeapon.Magazine" | Name="Magazine"
[5261] Weld | "Workspace.krokodyl820.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[5262] Attachment | "Workspace.krokodyl820.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[5263] Model | "Workspace.dkndat123" | Name="dkndat123"; attr:TPS_Weapon="AR15"
[5264] Part | "Workspace.dkndat123.HumanoidRootPart" | Name="HumanoidRootPart"
[5265] Attachment | "Workspace.dkndat123.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[5266] Vector3Value | "Workspace.dkndat123.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[5267] Vector3Value | "Workspace.dkndat123.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[5268] Attachment | "Workspace.dkndat123.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[5269] Sound | "Workspace.dkndat123.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[5270] Sound | "Workspace.dkndat123.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[5271] Sound | "Workspace.dkndat123.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[5272] Sound | "Workspace.dkndat123.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[5273] Sound | "Workspace.dkndat123.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[5274] Sound | "Workspace.dkndat123.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[5275] Sound | "Workspace.dkndat123.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[5276] Sound | "Workspace.dkndat123.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[5277] Sound | "Workspace.dkndat123.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[5278] MeshPart | "Workspace.dkndat123.LeftHand" | Name="LeftHand"
[5279] WrapTarget | "Workspace.dkndat123.LeftHand.LeftHand" | Name="LeftHand"
[5280] Attachment | "Workspace.dkndat123.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[5281] Vector3Value | "Workspace.dkndat123.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[5282] Attachment | "Workspace.dkndat123.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[5283] Vector3Value | "Workspace.dkndat123.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[5284] Vector3Value | "Workspace.dkndat123.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[5285] AnimationConstraint | "Workspace.dkndat123.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[5286] BallSocketConstraint | "Workspace.dkndat123.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[5287] MeshPart | "Workspace.dkndat123.RightHand" | Name="RightHand"
[5288] WrapTarget | "Workspace.dkndat123.RightHand.RightHand" | Name="RightHand"
[5289] Attachment | "Workspace.dkndat123.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[5290] Vector3Value | "Workspace.dkndat123.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[5291] Attachment | "Workspace.dkndat123.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[5292] Vector3Value | "Workspace.dkndat123.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[5293] Vector3Value | "Workspace.dkndat123.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[5294] AnimationConstraint | "Workspace.dkndat123.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[5295] BallSocketConstraint | "Workspace.dkndat123.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[5296] MeshPart | "Workspace.dkndat123.LeftLowerArm" | Name="LeftLowerArm"
[5297] WrapTarget | "Workspace.dkndat123.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[5298] Attachment | "Workspace.dkndat123.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[5299] Vector3Value | "Workspace.dkndat123.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[5300] Attachment | "Workspace.dkndat123.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[5301] Vector3Value | "Workspace.dkndat123.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[5302] Vector3Value | "Workspace.dkndat123.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[5303] AnimationConstraint | "Workspace.dkndat123.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[5304] BallSocketConstraint | "Workspace.dkndat123.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[5305] MeshPart | "Workspace.dkndat123.RightLowerArm" | Name="RightLowerArm"
[5306] WrapTarget | "Workspace.dkndat123.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[5307] Attachment | "Workspace.dkndat123.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[5308] Vector3Value | "Workspace.dkndat123.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[5309] Attachment | "Workspace.dkndat123.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[5310] Vector3Value | "Workspace.dkndat123.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[5311] Vector3Value | "Workspace.dkndat123.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[5312] AnimationConstraint | "Workspace.dkndat123.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[5313] BallSocketConstraint | "Workspace.dkndat123.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[5314] MeshPart | "Workspace.dkndat123.LeftUpperArm" | Name="LeftUpperArm"
[5315] WrapTarget | "Workspace.dkndat123.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[5316] Attachment | "Workspace.dkndat123.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[5317] Vector3Value | "Workspace.dkndat123.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[5318] Attachment | "Workspace.dkndat123.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5319] Attachment | "Workspace.dkndat123.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[5320] Vector3Value | "Workspace.dkndat123.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[5321] Attachment | "Workspace.dkndat123.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[5322] Vector3Value | "Workspace.dkndat123.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[5323] Vector3Value | "Workspace.dkndat123.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[5324] NoCollisionConstraint | "Workspace.dkndat123.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[5325] AnimationConstraint | "Workspace.dkndat123.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[5326] BallSocketConstraint | "Workspace.dkndat123.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[5327] MeshPart | "Workspace.dkndat123.RightUpperArm" | Name="RightUpperArm"
[5328] WrapTarget | "Workspace.dkndat123.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[5329] Attachment | "Workspace.dkndat123.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[5330] Vector3Value | "Workspace.dkndat123.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[5331] Attachment | "Workspace.dkndat123.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5332] Attachment | "Workspace.dkndat123.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[5333] Vector3Value | "Workspace.dkndat123.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[5334] Attachment | "Workspace.dkndat123.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[5335] Vector3Value | "Workspace.dkndat123.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[5336] Vector3Value | "Workspace.dkndat123.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[5337] NoCollisionConstraint | "Workspace.dkndat123.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[5338] AnimationConstraint | "Workspace.dkndat123.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[5339] BallSocketConstraint | "Workspace.dkndat123.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[5340] MeshPart | "Workspace.dkndat123.LeftFoot" | Name="LeftFoot"
[5341] WrapTarget | "Workspace.dkndat123.LeftFoot.LeftFoot" | Name="LeftFoot"
[5342] Attachment | "Workspace.dkndat123.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[5343] Vector3Value | "Workspace.dkndat123.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[5344] Attachment | "Workspace.dkndat123.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[5345] Vector3Value | "Workspace.dkndat123.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[5346] Vector3Value | "Workspace.dkndat123.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[5347] AnimationConstraint | "Workspace.dkndat123.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[5348] BallSocketConstraint | "Workspace.dkndat123.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[5349] MeshPart | "Workspace.dkndat123.LeftLowerLeg" | Name="LeftLowerLeg"
[5350] WrapTarget | "Workspace.dkndat123.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[5351] Attachment | "Workspace.dkndat123.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[5352] Vector3Value | "Workspace.dkndat123.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[5353] Attachment | "Workspace.dkndat123.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[5354] Vector3Value | "Workspace.dkndat123.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[5355] Vector3Value | "Workspace.dkndat123.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[5356] AnimationConstraint | "Workspace.dkndat123.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[5357] BallSocketConstraint | "Workspace.dkndat123.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[5358] MeshPart | "Workspace.dkndat123.UpperTorso" | Name="UpperTorso"
[5359] WrapTarget | "Workspace.dkndat123.UpperTorso.UpperTorso" | Name="UpperTorso"
[5360] Attachment | "Workspace.dkndat123.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[5361] Vector3Value | "Workspace.dkndat123.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[5362] Attachment | "Workspace.dkndat123.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[5363] Vector3Value | "Workspace.dkndat123.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[5364] Attachment | "Workspace.dkndat123.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[5365] Vector3Value | "Workspace.dkndat123.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[5366] Attachment | "Workspace.dkndat123.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5367] Attachment | "Workspace.dkndat123.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[5368] Vector3Value | "Workspace.dkndat123.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[5369] Attachment | "Workspace.dkndat123.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5370] Attachment | "Workspace.dkndat123.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[5371] Vector3Value | "Workspace.dkndat123.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[5372] Attachment | "Workspace.dkndat123.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[5373] Vector3Value | "Workspace.dkndat123.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[5374] Attachment | "Workspace.dkndat123.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[5375] Vector3Value | "Workspace.dkndat123.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[5376] Attachment | "Workspace.dkndat123.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[5377] Vector3Value | "Workspace.dkndat123.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[5378] Attachment | "Workspace.dkndat123.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[5379] Vector3Value | "Workspace.dkndat123.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[5380] Vector3Value | "Workspace.dkndat123.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[5381] NoCollisionConstraint | "Workspace.dkndat123.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[5382] NoCollisionConstraint | "Workspace.dkndat123.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[5383] NoCollisionConstraint | "Workspace.dkndat123.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[5384] NoCollisionConstraint | "Workspace.dkndat123.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[5385] NoCollisionConstraint | "Workspace.dkndat123.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[5386] NoCollisionConstraint | "Workspace.dkndat123.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[5387] NoCollisionConstraint | "Workspace.dkndat123.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[5388] AnimationConstraint | "Workspace.dkndat123.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[5389] BallSocketConstraint | "Workspace.dkndat123.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[5390] MeshPart | "Workspace.dkndat123.LeftUpperLeg" | Name="LeftUpperLeg"
[5391] WrapTarget | "Workspace.dkndat123.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[5392] Attachment | "Workspace.dkndat123.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[5393] Vector3Value | "Workspace.dkndat123.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[5394] Attachment | "Workspace.dkndat123.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[5395] Vector3Value | "Workspace.dkndat123.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[5396] Vector3Value | "Workspace.dkndat123.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[5397] NoCollisionConstraint | "Workspace.dkndat123.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[5398] NoCollisionConstraint | "Workspace.dkndat123.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[5399] AnimationConstraint | "Workspace.dkndat123.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[5400] BallSocketConstraint | "Workspace.dkndat123.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[5401] MeshPart | "Workspace.dkndat123.RightFoot" | Name="RightFoot"
[5402] WrapTarget | "Workspace.dkndat123.RightFoot.RightFoot" | Name="RightFoot"
[5403] Attachment | "Workspace.dkndat123.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[5404] Vector3Value | "Workspace.dkndat123.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[5405] Attachment | "Workspace.dkndat123.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[5406] Vector3Value | "Workspace.dkndat123.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[5407] Vector3Value | "Workspace.dkndat123.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[5408] AnimationConstraint | "Workspace.dkndat123.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[5409] BallSocketConstraint | "Workspace.dkndat123.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[5410] MeshPart | "Workspace.dkndat123.RightLowerLeg" | Name="RightLowerLeg"
[5411] WrapTarget | "Workspace.dkndat123.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[5412] Attachment | "Workspace.dkndat123.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[5413] Vector3Value | "Workspace.dkndat123.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[5414] Attachment | "Workspace.dkndat123.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[5415] Vector3Value | "Workspace.dkndat123.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[5416] Vector3Value | "Workspace.dkndat123.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[5417] AnimationConstraint | "Workspace.dkndat123.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[5418] BallSocketConstraint | "Workspace.dkndat123.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[5419] MeshPart | "Workspace.dkndat123.LowerTorso" | Name="LowerTorso"
[5420] WrapTarget | "Workspace.dkndat123.LowerTorso.LowerTorso" | Name="LowerTorso"
[5421] Attachment | "Workspace.dkndat123.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[5422] Vector3Value | "Workspace.dkndat123.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[5423] Attachment | "Workspace.dkndat123.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[5424] Vector3Value | "Workspace.dkndat123.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[5425] Attachment | "Workspace.dkndat123.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[5426] Vector3Value | "Workspace.dkndat123.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[5427] Attachment | "Workspace.dkndat123.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[5428] Vector3Value | "Workspace.dkndat123.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[5429] Attachment | "Workspace.dkndat123.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[5430] Vector3Value | "Workspace.dkndat123.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[5431] Attachment | "Workspace.dkndat123.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[5432] Vector3Value | "Workspace.dkndat123.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[5433] Attachment | "Workspace.dkndat123.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[5434] Vector3Value | "Workspace.dkndat123.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[5435] Vector3Value | "Workspace.dkndat123.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[5436] NoCollisionConstraint | "Workspace.dkndat123.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[5437] NoCollisionConstraint | "Workspace.dkndat123.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[5438] NoCollisionConstraint | "Workspace.dkndat123.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[5439] NoCollisionConstraint | "Workspace.dkndat123.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[5440] AnimationConstraint | "Workspace.dkndat123.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[5441] MeshPart | "Workspace.dkndat123.RightUpperLeg" | Name="RightUpperLeg"
[5442] WrapTarget | "Workspace.dkndat123.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[5443] Attachment | "Workspace.dkndat123.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[5444] Vector3Value | "Workspace.dkndat123.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[5445] Attachment | "Workspace.dkndat123.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[5446] Vector3Value | "Workspace.dkndat123.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[5447] Vector3Value | "Workspace.dkndat123.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[5448] NoCollisionConstraint | "Workspace.dkndat123.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[5449] AnimationConstraint | "Workspace.dkndat123.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[5450] BallSocketConstraint | "Workspace.dkndat123.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[5451] Humanoid | "Workspace.dkndat123.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[5452] Status | "Workspace.dkndat123.Humanoid.Status" | Name="Status"
[5453] Animator | "Workspace.dkndat123.Humanoid.Animator" | Name="Animator"
[5454] MeshPart | "Workspace.dkndat123.Head" | Name="Head"
[5455] Attachment | "Workspace.dkndat123.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[5456] Vector3Value | "Workspace.dkndat123.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[5457] Attachment | "Workspace.dkndat123.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[5458] Vector3Value | "Workspace.dkndat123.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[5459] Attachment | "Workspace.dkndat123.Head.HairAttachment" | Name="HairAttachment"
[5460] Vector3Value | "Workspace.dkndat123.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[5461] Attachment | "Workspace.dkndat123.Head.HatAttachment" | Name="HatAttachment"
[5462] Vector3Value | "Workspace.dkndat123.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[5463] Attachment | "Workspace.dkndat123.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[5464] Vector3Value | "Workspace.dkndat123.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[5465] Vector3Value | "Workspace.dkndat123.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[5466] WrapTarget | "Workspace.dkndat123.Head.Head" | Name="Head"
[5467] FaceControls | "Workspace.dkndat123.Head.FaceControls" | Name="FaceControls"
[5468] NoCollisionConstraint | "Workspace.dkndat123.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[5469] NoCollisionConstraint | "Workspace.dkndat123.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[5470] NoCollisionConstraint | "Workspace.dkndat123.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[5471] AnimationConstraint | "Workspace.dkndat123.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[5472] BallSocketConstraint | "Workspace.dkndat123.Head.NeckBallSocket" | Name="NeckBallSocket"
[5473] Script | "Workspace.dkndat123.Health" | Name="Health"
[5474] LocalScript | "Workspace.dkndat123.Animate" | Name="Animate"
[5475] StringValue | "Workspace.dkndat123.Animate.cheer" | Name="cheer"; Value=""
[5476] Animation | "Workspace.dkndat123.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[5477] StringValue | "Workspace.dkndat123.Animate.climb" | Name="climb"; Value=""
[5478] Animation | "Workspace.dkndat123.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[5479] StringValue | "Workspace.dkndat123.Animate.dance" | Name="dance"; Value=""
[5480] Animation | "Workspace.dkndat123.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[5481] NumberValue | "Workspace.dkndat123.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[5482] Animation | "Workspace.dkndat123.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[5483] NumberValue | "Workspace.dkndat123.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[5484] Animation | "Workspace.dkndat123.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[5485] NumberValue | "Workspace.dkndat123.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[5486] StringValue | "Workspace.dkndat123.Animate.dance2" | Name="dance2"; Value=""
[5487] Animation | "Workspace.dkndat123.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[5488] NumberValue | "Workspace.dkndat123.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[5489] Animation | "Workspace.dkndat123.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[5490] NumberValue | "Workspace.dkndat123.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[5491] Animation | "Workspace.dkndat123.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[5492] NumberValue | "Workspace.dkndat123.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[5493] StringValue | "Workspace.dkndat123.Animate.dance3" | Name="dance3"; Value=""
[5494] Animation | "Workspace.dkndat123.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[5495] NumberValue | "Workspace.dkndat123.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[5496] Animation | "Workspace.dkndat123.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[5497] NumberValue | "Workspace.dkndat123.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[5498] Animation | "Workspace.dkndat123.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[5499] NumberValue | "Workspace.dkndat123.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[5500] StringValue | "Workspace.dkndat123.Animate.fall" | Name="fall"; Value=""
[5501] Animation | "Workspace.dkndat123.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[5502] StringValue | "Workspace.dkndat123.Animate.idle" | Name="idle"; Value=""
[5503] Animation | "Workspace.dkndat123.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[5504] NumberValue | "Workspace.dkndat123.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[5505] Animation | "Workspace.dkndat123.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[5506] NumberValue | "Workspace.dkndat123.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[5507] StringValue | "Workspace.dkndat123.Animate.jump" | Name="jump"; Value=""
[5508] Animation | "Workspace.dkndat123.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[5509] StringValue | "Workspace.dkndat123.Animate.laugh" | Name="laugh"; Value=""
[5510] Animation | "Workspace.dkndat123.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[5511] StringValue | "Workspace.dkndat123.Animate.point" | Name="point"; Value=""
[5512] Animation | "Workspace.dkndat123.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[5513] StringValue | "Workspace.dkndat123.Animate.sit" | Name="sit"; Value=""
[5514] Animation | "Workspace.dkndat123.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[5515] StringValue | "Workspace.dkndat123.Animate.toollunge" | Name="toollunge"; Value=""
[5516] Animation | "Workspace.dkndat123.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[5517] StringValue | "Workspace.dkndat123.Animate.toolnone" | Name="toolnone"; Value=""
[5518] Animation | "Workspace.dkndat123.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[5519] StringValue | "Workspace.dkndat123.Animate.toolslash" | Name="toolslash"; Value=""
[5520] Animation | "Workspace.dkndat123.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[5521] StringValue | "Workspace.dkndat123.Animate.wave" | Name="wave"; Value=""
[5522] Animation | "Workspace.dkndat123.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[5523] NumberValue | "Workspace.dkndat123.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[5524] StringValue | "Workspace.dkndat123.Animate.run" | Name="run"; Value=""
[5525] Animation | "Workspace.dkndat123.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[5526] StringValue | "Workspace.dkndat123.Animate.swim" | Name="swim"; Value=""
[5527] Animation | "Workspace.dkndat123.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[5528] StringValue | "Workspace.dkndat123.Animate.swimidle" | Name="swimidle"; Value=""
[5529] Animation | "Workspace.dkndat123.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[5530] StringValue | "Workspace.dkndat123.Animate.walk" | Name="walk"; Value=""
[5531] Animation | "Workspace.dkndat123.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[5532] BindableFunction | "Workspace.dkndat123.Animate.PlayEmote" | Name="PlayEmote"
[5533] StringValue | "Workspace.dkndat123.Animate.mood" | Name="mood"; Value=""
[5534] Animation | "Workspace.dkndat123.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[5535] AudioEmitter | "Workspace.dkndat123.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[5536] Wire | "Workspace.dkndat123.AudioEmitter.Wire" | Name="Wire"
[5537] Model | "Workspace.dkndat123.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="PS2Splinter"; attr:TPS_WeaponId="AR15"
[5538] Part | "Workspace.dkndat123.TPS_HeldWeapon.Handle" | Name="Handle"
[5539] Attachment | "Workspace.dkndat123.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[5540] Attachment | "Workspace.dkndat123.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[5541] Attachment | "Workspace.dkndat123.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[5542] Motor6D | "Workspace.dkndat123.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[5543] Part | "Workspace.dkndat123.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"; attr:R1_SkinHidden=true
[5544] SpecialMesh | "Workspace.dkndat123.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[5545] WeldConstraint | "Workspace.dkndat123.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[5546] Part | "Workspace.dkndat123.TPS_HeldWeapon.Magazine" | Name="Magazine"
[5547] Weld | "Workspace.dkndat123.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[5548] Attachment | "Workspace.dkndat123.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
[5549] MeshPart | "Workspace.dkndat123.TPS_HeldWeapon.R1_SkinBody" | Name="R1_SkinBody"
[5550] WeldConstraint | "Workspace.dkndat123.TPS_HeldWeapon.R1_SkinBody.WeldConstraint" | Name="WeldConstraint"
[5551] Model | "Workspace.iluvmoms6092" | Name="iluvmoms6092"; attr:TPS_Weapon="AR15"
[5552] Part | "Workspace.iluvmoms6092.HumanoidRootPart" | Name="HumanoidRootPart"
[5553] Attachment | "Workspace.iluvmoms6092.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[5554] Vector3Value | "Workspace.iluvmoms6092.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[5555] Vector3Value | "Workspace.iluvmoms6092.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[5556] Attachment | "Workspace.iluvmoms6092.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[5557] Sound | "Workspace.iluvmoms6092.HumanoidRootPart.Climbing" | Name="Climbing"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[5558] Sound | "Workspace.iluvmoms6092.HumanoidRootPart.Died" | Name="Died"; SoundId="rbxasset://sounds/uuhhh.mp3"; Volume=0.64999997615814
[5559] Sound | "Workspace.iluvmoms6092.HumanoidRootPart.GettingUp" | Name="GettingUp"; SoundId="rbxasset://sounds/action_get_up.mp3"; Volume=0.64999997615814
[5560] Sound | "Workspace.iluvmoms6092.HumanoidRootPart.Swimming" | Name="Swimming"; SoundId="rbxasset://sounds/action_swim.mp3"; Volume=0.64999997615814
[5561] Sound | "Workspace.iluvmoms6092.HumanoidRootPart.Jumping" | Name="Jumping"; SoundId="rbxasset://sounds/action_jump.mp3"; Volume=0.64999997615814
[5562] Sound | "Workspace.iluvmoms6092.HumanoidRootPart.Landing" | Name="Landing"; SoundId="rbxasset://sounds/action_jump_land.mp3"; Volume=0.64999997615814
[5563] Sound | "Workspace.iluvmoms6092.HumanoidRootPart.Splash" | Name="Splash"; SoundId="rbxasset://sounds/impact_water.mp3"; Volume=0.64999997615814
[5564] Sound | "Workspace.iluvmoms6092.HumanoidRootPart.FreeFalling" | Name="FreeFalling"; SoundId="rbxasset://sounds/action_falling.ogg"; Volume=0.64999997615814
[5565] Sound | "Workspace.iluvmoms6092.HumanoidRootPart.Running" | Name="Running"; SoundId="rbxasset://sounds/action_footsteps_plastic.mp3"; Volume=0.64999997615814
[5566] MeshPart | "Workspace.iluvmoms6092.LeftHand" | Name="LeftHand"
[5567] WrapTarget | "Workspace.iluvmoms6092.LeftHand.LeftHand" | Name="LeftHand"
[5568] Attachment | "Workspace.iluvmoms6092.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[5569] Vector3Value | "Workspace.iluvmoms6092.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[5570] Attachment | "Workspace.iluvmoms6092.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[5571] Vector3Value | "Workspace.iluvmoms6092.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[5572] Vector3Value | "Workspace.iluvmoms6092.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[5573] AnimationConstraint | "Workspace.iluvmoms6092.LeftHand.LeftWrist" | Name="LeftWrist"; attr:TPS_BaseC0=CFrame.new(0.000478625,-0.500929,7.64463e-20,1,0,0,0,1,0,0,0,1)
[5574] BallSocketConstraint | "Workspace.iluvmoms6092.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[5575] MeshPart | "Workspace.iluvmoms6092.RightHand" | Name="RightHand"
[5576] WrapTarget | "Workspace.iluvmoms6092.RightHand.RightHand" | Name="RightHand"
[5577] Attachment | "Workspace.iluvmoms6092.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[5578] Vector3Value | "Workspace.iluvmoms6092.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[5579] Attachment | "Workspace.iluvmoms6092.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[5580] Vector3Value | "Workspace.iluvmoms6092.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[5581] Vector3Value | "Workspace.iluvmoms6092.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[5582] AnimationConstraint | "Workspace.iluvmoms6092.RightHand.RightWrist" | Name="RightWrist"; attr:TPS_BaseC0=CFrame.new(1.19209e-07,-0.500929,-6.86245e-18,1,0,0,0,1,0,0,0,1)
[5583] BallSocketConstraint | "Workspace.iluvmoms6092.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[5584] MeshPart | "Workspace.iluvmoms6092.LeftLowerArm" | Name="LeftLowerArm"
[5585] WrapTarget | "Workspace.iluvmoms6092.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[5586] Attachment | "Workspace.iluvmoms6092.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[5587] Vector3Value | "Workspace.iluvmoms6092.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[5588] Attachment | "Workspace.iluvmoms6092.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[5589] Vector3Value | "Workspace.iluvmoms6092.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[5590] Vector3Value | "Workspace.iluvmoms6092.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[5591] AnimationConstraint | "Workspace.iluvmoms6092.LeftLowerArm.LeftElbow" | Name="LeftElbow"; attr:TPS_BaseC0=CFrame.new(0.000479221,-0.334056,8.9407e-08,1,0,0,0,1,0,0,0,1)
[5592] BallSocketConstraint | "Workspace.iluvmoms6092.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[5593] MeshPart | "Workspace.iluvmoms6092.RightLowerArm" | Name="RightLowerArm"
[5594] WrapTarget | "Workspace.iluvmoms6092.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[5595] Attachment | "Workspace.iluvmoms6092.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[5596] Vector3Value | "Workspace.iluvmoms6092.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[5597] Attachment | "Workspace.iluvmoms6092.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[5598] Vector3Value | "Workspace.iluvmoms6092.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[5599] Vector3Value | "Workspace.iluvmoms6092.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[5600] AnimationConstraint | "Workspace.iluvmoms6092.RightLowerArm.RightElbow" | Name="RightElbow"; attr:TPS_BaseC0=CFrame.new(-5.96046e-07,-0.334165,8.9407e-08,1,0,0,0,1,0,0,0,1)
[5601] BallSocketConstraint | "Workspace.iluvmoms6092.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[5602] MeshPart | "Workspace.iluvmoms6092.LeftUpperArm" | Name="LeftUpperArm"
[5603] WrapTarget | "Workspace.iluvmoms6092.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[5604] Attachment | "Workspace.iluvmoms6092.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[5605] Vector3Value | "Workspace.iluvmoms6092.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[5606] Attachment | "Workspace.iluvmoms6092.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5607] Attachment | "Workspace.iluvmoms6092.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[5608] Vector3Value | "Workspace.iluvmoms6092.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[5609] Attachment | "Workspace.iluvmoms6092.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[5610] Vector3Value | "Workspace.iluvmoms6092.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[5611] Vector3Value | "Workspace.iluvmoms6092.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[5612] NoCollisionConstraint | "Workspace.iluvmoms6092.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[5613] AnimationConstraint | "Workspace.iluvmoms6092.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"; attr:TPS_BaseC0=CFrame.new(-1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[5614] BallSocketConstraint | "Workspace.iluvmoms6092.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[5615] MeshPart | "Workspace.iluvmoms6092.RightUpperArm" | Name="RightUpperArm"
[5616] WrapTarget | "Workspace.iluvmoms6092.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[5617] Attachment | "Workspace.iluvmoms6092.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[5618] Vector3Value | "Workspace.iluvmoms6092.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[5619] Attachment | "Workspace.iluvmoms6092.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5620] Attachment | "Workspace.iluvmoms6092.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[5621] Vector3Value | "Workspace.iluvmoms6092.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[5622] Attachment | "Workspace.iluvmoms6092.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[5623] Vector3Value | "Workspace.iluvmoms6092.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[5624] Vector3Value | "Workspace.iluvmoms6092.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[5625] NoCollisionConstraint | "Workspace.iluvmoms6092.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[5626] AnimationConstraint | "Workspace.iluvmoms6092.RightUpperArm.RightShoulder" | Name="RightShoulder"; attr:TPS_BaseC0=CFrame.new(1,0.563017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[5627] BallSocketConstraint | "Workspace.iluvmoms6092.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[5628] MeshPart | "Workspace.iluvmoms6092.LeftFoot" | Name="LeftFoot"
[5629] WrapTarget | "Workspace.iluvmoms6092.LeftFoot.LeftFoot" | Name="LeftFoot"
[5630] Attachment | "Workspace.iluvmoms6092.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[5631] Vector3Value | "Workspace.iluvmoms6092.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[5632] Attachment | "Workspace.iluvmoms6092.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[5633] Vector3Value | "Workspace.iluvmoms6092.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[5634] Vector3Value | "Workspace.iluvmoms6092.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[5635] AnimationConstraint | "Workspace.iluvmoms6092.LeftFoot.LeftAnkle" | Name="LeftAnkle"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,-0.547157,-2.21402e-06,1,0,0,0,1,0,0,0,1)
[5636] BallSocketConstraint | "Workspace.iluvmoms6092.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[5637] MeshPart | "Workspace.iluvmoms6092.LeftLowerLeg" | Name="LeftLowerLeg"
[5638] WrapTarget | "Workspace.iluvmoms6092.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[5639] Attachment | "Workspace.iluvmoms6092.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[5640] Vector3Value | "Workspace.iluvmoms6092.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[5641] Attachment | "Workspace.iluvmoms6092.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[5642] Vector3Value | "Workspace.iluvmoms6092.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[5643] Vector3Value | "Workspace.iluvmoms6092.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[5644] AnimationConstraint | "Workspace.iluvmoms6092.LeftLowerLeg.LeftKnee" | Name="LeftKnee"; attr:TPS_BaseC0=CFrame.new(8.9407e-08,-0.401102,-4.29081e-07,1,0,0,0,1,0,0,0,1)
[5645] BallSocketConstraint | "Workspace.iluvmoms6092.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[5646] MeshPart | "Workspace.iluvmoms6092.UpperTorso" | Name="UpperTorso"
[5647] WrapTarget | "Workspace.iluvmoms6092.UpperTorso.UpperTorso" | Name="UpperTorso"
[5648] Attachment | "Workspace.iluvmoms6092.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[5649] Vector3Value | "Workspace.iluvmoms6092.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[5650] Attachment | "Workspace.iluvmoms6092.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[5651] Vector3Value | "Workspace.iluvmoms6092.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[5652] Attachment | "Workspace.iluvmoms6092.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[5653] Vector3Value | "Workspace.iluvmoms6092.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[5654] Attachment | "Workspace.iluvmoms6092.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5655] Attachment | "Workspace.iluvmoms6092.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[5656] Vector3Value | "Workspace.iluvmoms6092.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[5657] Attachment | "Workspace.iluvmoms6092.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[5658] Attachment | "Workspace.iluvmoms6092.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[5659] Vector3Value | "Workspace.iluvmoms6092.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[5660] Attachment | "Workspace.iluvmoms6092.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[5661] Vector3Value | "Workspace.iluvmoms6092.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[5662] Attachment | "Workspace.iluvmoms6092.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[5663] Vector3Value | "Workspace.iluvmoms6092.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[5664] Attachment | "Workspace.iluvmoms6092.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[5665] Vector3Value | "Workspace.iluvmoms6092.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[5666] Attachment | "Workspace.iluvmoms6092.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[5667] Vector3Value | "Workspace.iluvmoms6092.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[5668] Vector3Value | "Workspace.iluvmoms6092.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[5669] NoCollisionConstraint | "Workspace.iluvmoms6092.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[5670] NoCollisionConstraint | "Workspace.iluvmoms6092.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[5671] NoCollisionConstraint | "Workspace.iluvmoms6092.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[5672] NoCollisionConstraint | "Workspace.iluvmoms6092.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[5673] NoCollisionConstraint | "Workspace.iluvmoms6092.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[5674] NoCollisionConstraint | "Workspace.iluvmoms6092.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[5675] NoCollisionConstraint | "Workspace.iluvmoms6092.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[5676] AnimationConstraint | "Workspace.iluvmoms6092.UpperTorso.Waist" | Name="Waist"; attr:TPS_BaseC0=CFrame.new(-1.19209e-07,0.200025,7.64463e-20,1,0,0,0,1,0,0,0,1)
[5677] BallSocketConstraint | "Workspace.iluvmoms6092.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[5678] MeshPart | "Workspace.iluvmoms6092.LeftUpperLeg" | Name="LeftUpperLeg"
[5679] WrapTarget | "Workspace.iluvmoms6092.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[5680] Attachment | "Workspace.iluvmoms6092.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[5681] Vector3Value | "Workspace.iluvmoms6092.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[5682] Attachment | "Workspace.iluvmoms6092.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[5683] Vector3Value | "Workspace.iluvmoms6092.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[5684] Vector3Value | "Workspace.iluvmoms6092.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[5685] NoCollisionConstraint | "Workspace.iluvmoms6092.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[5686] NoCollisionConstraint | "Workspace.iluvmoms6092.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[5687] AnimationConstraint | "Workspace.iluvmoms6092.LeftUpperLeg.LeftHip" | Name="LeftHip"; attr:TPS_BaseC0=CFrame.new(-0.5,-0.199972,-0,1,0,0,0,1,0,0,0,1)
[5688] BallSocketConstraint | "Workspace.iluvmoms6092.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[5689] MeshPart | "Workspace.iluvmoms6092.RightFoot" | Name="RightFoot"
[5690] WrapTarget | "Workspace.iluvmoms6092.RightFoot.RightFoot" | Name="RightFoot"
[5691] Attachment | "Workspace.iluvmoms6092.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[5692] Vector3Value | "Workspace.iluvmoms6092.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[5693] Attachment | "Workspace.iluvmoms6092.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[5694] Vector3Value | "Workspace.iluvmoms6092.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[5695] Vector3Value | "Workspace.iluvmoms6092.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[5696] AnimationConstraint | "Workspace.iluvmoms6092.RightFoot.RightAnkle" | Name="RightAnkle"; attr:TPS_BaseC0=CFrame.new(-0,-0.547157,7.6269e-05,1,0,0,0,1,0,0,0,1)
[5697] BallSocketConstraint | "Workspace.iluvmoms6092.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[5698] MeshPart | "Workspace.iluvmoms6092.RightLowerLeg" | Name="RightLowerLeg"
[5699] WrapTarget | "Workspace.iluvmoms6092.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[5700] Attachment | "Workspace.iluvmoms6092.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[5701] Vector3Value | "Workspace.iluvmoms6092.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[5702] Attachment | "Workspace.iluvmoms6092.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[5703] Vector3Value | "Workspace.iluvmoms6092.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[5704] Vector3Value | "Workspace.iluvmoms6092.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[5705] AnimationConstraint | "Workspace.iluvmoms6092.RightLowerLeg.RightKnee" | Name="RightKnee"; attr:TPS_BaseC0=CFrame.new(-0,-0.400946,-2.18768e-05,1,0,0,0,1,0,0,0,1)
[5706] BallSocketConstraint | "Workspace.iluvmoms6092.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[5707] MeshPart | "Workspace.iluvmoms6092.LowerTorso" | Name="LowerTorso"
[5708] WrapTarget | "Workspace.iluvmoms6092.LowerTorso.LowerTorso" | Name="LowerTorso"
[5709] Attachment | "Workspace.iluvmoms6092.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[5710] Vector3Value | "Workspace.iluvmoms6092.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[5711] Attachment | "Workspace.iluvmoms6092.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[5712] Vector3Value | "Workspace.iluvmoms6092.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[5713] Attachment | "Workspace.iluvmoms6092.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[5714] Vector3Value | "Workspace.iluvmoms6092.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[5715] Attachment | "Workspace.iluvmoms6092.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[5716] Vector3Value | "Workspace.iluvmoms6092.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[5717] Attachment | "Workspace.iluvmoms6092.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[5718] Vector3Value | "Workspace.iluvmoms6092.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[5719] Attachment | "Workspace.iluvmoms6092.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[5720] Vector3Value | "Workspace.iluvmoms6092.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[5721] Attachment | "Workspace.iluvmoms6092.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[5722] Vector3Value | "Workspace.iluvmoms6092.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[5723] Vector3Value | "Workspace.iluvmoms6092.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[5724] NoCollisionConstraint | "Workspace.iluvmoms6092.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[5725] NoCollisionConstraint | "Workspace.iluvmoms6092.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[5726] NoCollisionConstraint | "Workspace.iluvmoms6092.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[5727] NoCollisionConstraint | "Workspace.iluvmoms6092.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[5728] AnimationConstraint | "Workspace.iluvmoms6092.LowerTorso.Root" | Name="Root"; attr:TPS_BaseC0=CFrame.new(0,-1,0,1,0,0,0,1,0,0,0,1)
[5729] MeshPart | "Workspace.iluvmoms6092.RightUpperLeg" | Name="RightUpperLeg"
[5730] WrapTarget | "Workspace.iluvmoms6092.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[5731] Attachment | "Workspace.iluvmoms6092.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[5732] Vector3Value | "Workspace.iluvmoms6092.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[5733] Attachment | "Workspace.iluvmoms6092.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[5734] Vector3Value | "Workspace.iluvmoms6092.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[5735] Vector3Value | "Workspace.iluvmoms6092.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[5736] NoCollisionConstraint | "Workspace.iluvmoms6092.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[5737] AnimationConstraint | "Workspace.iluvmoms6092.RightUpperLeg.RightHip" | Name="RightHip"; attr:TPS_BaseC0=CFrame.new(0.5,-0.199972,-1.91209e-05,1,0,0,0,1,0,0,0,1)
[5738] BallSocketConstraint | "Workspace.iluvmoms6092.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[5739] Humanoid | "Workspace.iluvmoms6092.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=0
[5740] Status | "Workspace.iluvmoms6092.Humanoid.Status" | Name="Status"
[5741] Animator | "Workspace.iluvmoms6092.Humanoid.Animator" | Name="Animator"
[5742] MeshPart | "Workspace.iluvmoms6092.Head" | Name="Head"
[5743] Attachment | "Workspace.iluvmoms6092.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[5744] Vector3Value | "Workspace.iluvmoms6092.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[5745] Attachment | "Workspace.iluvmoms6092.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[5746] Vector3Value | "Workspace.iluvmoms6092.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[5747] Attachment | "Workspace.iluvmoms6092.Head.HairAttachment" | Name="HairAttachment"
[5748] Vector3Value | "Workspace.iluvmoms6092.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[5749] Attachment | "Workspace.iluvmoms6092.Head.HatAttachment" | Name="HatAttachment"
[5750] Vector3Value | "Workspace.iluvmoms6092.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[5751] Attachment | "Workspace.iluvmoms6092.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[5752] Vector3Value | "Workspace.iluvmoms6092.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[5753] Vector3Value | "Workspace.iluvmoms6092.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[5754] WrapTarget | "Workspace.iluvmoms6092.Head.Head" | Name="Head"
[5755] FaceControls | "Workspace.iluvmoms6092.Head.FaceControls" | Name="FaceControls"
[5756] NoCollisionConstraint | "Workspace.iluvmoms6092.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[5757] NoCollisionConstraint | "Workspace.iluvmoms6092.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[5758] NoCollisionConstraint | "Workspace.iluvmoms6092.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[5759] AnimationConstraint | "Workspace.iluvmoms6092.Head.Neck" | Name="Neck"; attr:TPS_BaseC0=CFrame.new(-5.96046e-08,0.800017,1.19209e-07,1,0,0,0,1,0,0,0,1)
[5760] BallSocketConstraint | "Workspace.iluvmoms6092.Head.NeckBallSocket" | Name="NeckBallSocket"
[5761] Script | "Workspace.iluvmoms6092.Health" | Name="Health"
[5762] LocalScript | "Workspace.iluvmoms6092.Animate" | Name="Animate"
[5763] StringValue | "Workspace.iluvmoms6092.Animate.cheer" | Name="cheer"; Value=""
[5764] Animation | "Workspace.iluvmoms6092.Animate.cheer.CheerAnim" | Name="CheerAnim"; AnimationId="http://www.roblox.com/asset/?id=507770677"
[5765] StringValue | "Workspace.iluvmoms6092.Animate.climb" | Name="climb"; Value=""
[5766] Animation | "Workspace.iluvmoms6092.Animate.climb.ClimbAnim" | Name="ClimbAnim"; AnimationId="http://www.roblox.com/asset/?id=507765644"
[5767] StringValue | "Workspace.iluvmoms6092.Animate.dance" | Name="dance"; Value=""
[5768] Animation | "Workspace.iluvmoms6092.Animate.dance.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507771019"
[5769] NumberValue | "Workspace.iluvmoms6092.Animate.dance.Animation1.Weight" | Name="Weight"; Value=10
[5770] Animation | "Workspace.iluvmoms6092.Animate.dance.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507771955"
[5771] NumberValue | "Workspace.iluvmoms6092.Animate.dance.Animation2.Weight" | Name="Weight"; Value=10
[5772] Animation | "Workspace.iluvmoms6092.Animate.dance.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507772104"
[5773] NumberValue | "Workspace.iluvmoms6092.Animate.dance.Animation3.Weight" | Name="Weight"; Value=10
[5774] StringValue | "Workspace.iluvmoms6092.Animate.dance2" | Name="dance2"; Value=""
[5775] Animation | "Workspace.iluvmoms6092.Animate.dance2.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507776043"
[5776] NumberValue | "Workspace.iluvmoms6092.Animate.dance2.Animation1.Weight" | Name="Weight"; Value=10
[5777] Animation | "Workspace.iluvmoms6092.Animate.dance2.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507776720"
[5778] NumberValue | "Workspace.iluvmoms6092.Animate.dance2.Animation2.Weight" | Name="Weight"; Value=10
[5779] Animation | "Workspace.iluvmoms6092.Animate.dance2.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507776879"
[5780] NumberValue | "Workspace.iluvmoms6092.Animate.dance2.Animation3.Weight" | Name="Weight"; Value=10
[5781] StringValue | "Workspace.iluvmoms6092.Animate.dance3" | Name="dance3"; Value=""
[5782] Animation | "Workspace.iluvmoms6092.Animate.dance3.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507777268"
[5783] NumberValue | "Workspace.iluvmoms6092.Animate.dance3.Animation1.Weight" | Name="Weight"; Value=10
[5784] Animation | "Workspace.iluvmoms6092.Animate.dance3.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507777451"
[5785] NumberValue | "Workspace.iluvmoms6092.Animate.dance3.Animation2.Weight" | Name="Weight"; Value=10
[5786] Animation | "Workspace.iluvmoms6092.Animate.dance3.Animation3" | Name="Animation3"; AnimationId="http://www.roblox.com/asset/?id=507777623"
[5787] NumberValue | "Workspace.iluvmoms6092.Animate.dance3.Animation3.Weight" | Name="Weight"; Value=10
[5788] StringValue | "Workspace.iluvmoms6092.Animate.fall" | Name="fall"; Value=""
[5789] Animation | "Workspace.iluvmoms6092.Animate.fall.FallAnim" | Name="FallAnim"; AnimationId="http://www.roblox.com/asset/?id=507767968"
[5790] StringValue | "Workspace.iluvmoms6092.Animate.idle" | Name="idle"; Value=""
[5791] Animation | "Workspace.iluvmoms6092.Animate.idle.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=507766388"
[5792] NumberValue | "Workspace.iluvmoms6092.Animate.idle.Animation1.Weight" | Name="Weight"; Value=9
[5793] Animation | "Workspace.iluvmoms6092.Animate.idle.Animation2" | Name="Animation2"; AnimationId="http://www.roblox.com/asset/?id=507766666"
[5794] NumberValue | "Workspace.iluvmoms6092.Animate.idle.Animation2.Weight" | Name="Weight"; Value=1
[5795] StringValue | "Workspace.iluvmoms6092.Animate.jump" | Name="jump"; Value=""
[5796] Animation | "Workspace.iluvmoms6092.Animate.jump.JumpAnim" | Name="JumpAnim"; AnimationId="http://www.roblox.com/asset/?id=507765000"
[5797] StringValue | "Workspace.iluvmoms6092.Animate.laugh" | Name="laugh"; Value=""
[5798] Animation | "Workspace.iluvmoms6092.Animate.laugh.LaughAnim" | Name="LaughAnim"; AnimationId="http://www.roblox.com/asset/?id=507770818"
[5799] StringValue | "Workspace.iluvmoms6092.Animate.point" | Name="point"; Value=""
[5800] Animation | "Workspace.iluvmoms6092.Animate.point.PointAnim" | Name="PointAnim"; AnimationId="http://www.roblox.com/asset/?id=507770453"
[5801] StringValue | "Workspace.iluvmoms6092.Animate.sit" | Name="sit"; Value=""
[5802] Animation | "Workspace.iluvmoms6092.Animate.sit.SitAnim" | Name="SitAnim"; AnimationId="http://www.roblox.com/asset/?id=2506281703"
[5803] StringValue | "Workspace.iluvmoms6092.Animate.toollunge" | Name="toollunge"; Value=""
[5804] Animation | "Workspace.iluvmoms6092.Animate.toollunge.ToolLungeAnim" | Name="ToolLungeAnim"; AnimationId="http://www.roblox.com/asset/?id=522638767"
[5805] StringValue | "Workspace.iluvmoms6092.Animate.toolnone" | Name="toolnone"; Value=""
[5806] Animation | "Workspace.iluvmoms6092.Animate.toolnone.ToolNoneAnim" | Name="ToolNoneAnim"; AnimationId="http://www.roblox.com/asset/?id=507768375"
[5807] StringValue | "Workspace.iluvmoms6092.Animate.toolslash" | Name="toolslash"; Value=""
[5808] Animation | "Workspace.iluvmoms6092.Animate.toolslash.ToolSlashAnim" | Name="ToolSlashAnim"; AnimationId="http://www.roblox.com/asset/?id=522635514"
[5809] StringValue | "Workspace.iluvmoms6092.Animate.wave" | Name="wave"; Value=""
[5810] Animation | "Workspace.iluvmoms6092.Animate.wave.WaveAnim" | Name="WaveAnim"; AnimationId="http://www.roblox.com/asset/?id=507770239"
[5811] NumberValue | "Workspace.iluvmoms6092.Animate.ScaleDampeningPercent" | Name="ScaleDampeningPercent"; Value=1
[5812] StringValue | "Workspace.iluvmoms6092.Animate.run" | Name="run"; Value=""
[5813] Animation | "Workspace.iluvmoms6092.Animate.run.RunAnim" | Name="RunAnim"; AnimationId="http://www.roblox.com/asset/?id=913376220"
[5814] StringValue | "Workspace.iluvmoms6092.Animate.swim" | Name="swim"; Value=""
[5815] Animation | "Workspace.iluvmoms6092.Animate.swim.Swim" | Name="Swim"; AnimationId="http://www.roblox.com/asset/?id=913384386"
[5816] StringValue | "Workspace.iluvmoms6092.Animate.swimidle" | Name="swimidle"; Value=""
[5817] Animation | "Workspace.iluvmoms6092.Animate.swimidle.SwimIdle" | Name="SwimIdle"; AnimationId="http://www.roblox.com/asset/?id=913389285"
[5818] StringValue | "Workspace.iluvmoms6092.Animate.walk" | Name="walk"; Value=""
[5819] Animation | "Workspace.iluvmoms6092.Animate.walk.WalkAnim" | Name="WalkAnim"; AnimationId="http://www.roblox.com/asset/?id=913402848"
[5820] BindableFunction | "Workspace.iluvmoms6092.Animate.PlayEmote" | Name="PlayEmote"
[5821] StringValue | "Workspace.iluvmoms6092.Animate.mood" | Name="mood"; Value=""
[5822] Animation | "Workspace.iluvmoms6092.Animate.mood.Animation1" | Name="Animation1"; AnimationId="http://www.roblox.com/asset/?id=14366558676"
[5823] AudioEmitter | "Workspace.iluvmoms6092.AudioEmitter" | Name="AudioEmitter"; tags="RbxDefaultVoiceEmitter"
[5824] Wire | "Workspace.iluvmoms6092.AudioEmitter.Wire" | Name="Wire"
[5825] Model | "Workspace.iluvmoms6092.TPS_HeldWeapon" | Name="TPS_HeldWeapon"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046; attr:R1_Skin="Default"; attr:TPS_WeaponId="AR15"
[5826] Part | "Workspace.iluvmoms6092.TPS_HeldWeapon.Handle" | Name="Handle"
[5827] Attachment | "Workspace.iluvmoms6092.TPS_HeldWeapon.Handle.Muzzle" | Name="Muzzle"
[5828] Attachment | "Workspace.iluvmoms6092.TPS_HeldWeapon.Handle.RightGrip" | Name="RightGrip"
[5829] Attachment | "Workspace.iluvmoms6092.TPS_HeldWeapon.Handle.LeftGrip" | Name="LeftGrip"
[5830] Motor6D | "Workspace.iluvmoms6092.TPS_HeldWeapon.Handle.TPS_WeaponJoint" | Name="TPS_WeaponJoint"
[5831] Part | "Workspace.iluvmoms6092.TPS_HeldWeapon.HandleMesh" | Name="HandleMesh"
[5832] SpecialMesh | "Workspace.iluvmoms6092.TPS_HeldWeapon.HandleMesh.Mesh" | Name="Mesh"
[5833] WeldConstraint | "Workspace.iluvmoms6092.TPS_HeldWeapon.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[5834] Part | "Workspace.iluvmoms6092.TPS_HeldWeapon.Magazine" | Name="Magazine"
[5835] Weld | "Workspace.iluvmoms6092.TPS_HeldWeapon.Magazine.MagWeld" | Name="MagWeld"; attr:TPS_BaseC0=CFrame.new(0,-0.335294,-1.3,1,0,0,0,1,0,0,0,1)
[5836] Attachment | "Workspace.iluvmoms6092.TPS_HeldWeapon.Magazine.MagGrip" | Name="MagGrip"
------------------------------------------------------------
-- SERVICE: ReplicatedStorage
------------------------------------------------------------
[5837] ReplicatedStorage | "ReplicatedStorage" | Name="ReplicatedStorage"; attr:R1_MergeNAEU=true; attr:R1_PlayBanner="Arcade DUOS, CHAOS and Deathmatch is DISABLED Temporarily to fill more Ranked Matches. [NA & EU SERVERS ARE TEMPORARILY MERGED TO FILL LOBBIES]"; attr:R1_ModesHidden="Duos,Chaos,Deathmatch"; attr:R1_TradingPaused=false
[5838] ModuleScript | "ReplicatedStorage.R1_EventSlide" | Name="R1_EventSlide"
[5839] Folder | "ReplicatedStorage.R1Remotes" | Name="R1Remotes"
[5840] RemoteEvent | "ReplicatedStorage.R1Remotes.ProfileSync" | Name="ProfileSync"
[5841] RemoteFunction | "ReplicatedStorage.R1Remotes.ProfileRequest" | Name="ProfileRequest"
[5842] RemoteEvent | "ReplicatedStorage.R1Remotes.WeaponChallengeCompleted" | Name="WeaponChallengeCompleted"
[5843] RemoteFunction | "ReplicatedStorage.R1Remotes.Menu" | Name="Menu"
[5844] RemoteFunction | "ReplicatedStorage.R1Remotes.Market" | Name="Market"
[5845] RemoteEvent | "ReplicatedStorage.R1Remotes.MarketPush" | Name="MarketPush"
[5846] RemoteFunction | "ReplicatedStorage.R1Remotes.Hosted" | Name="Hosted"
[5847] RemoteEvent | "ReplicatedStorage.R1Remotes.HostedAnnounce" | Name="HostedAnnounce"
[5848] RemoteEvent | "ReplicatedStorage.R1Remotes.HostedReady" | Name="HostedReady"
[5849] RemoteFunction | "ReplicatedStorage.R1Remotes.Trade" | Name="Trade"
[5850] RemoteEvent | "ReplicatedStorage.R1Remotes.TradePush" | Name="TradePush"
[5851] RemoteEvent | "ReplicatedStorage.R1Remotes.ClanPush" | Name="ClanPush"
[5852] RemoteFunction | "ReplicatedStorage.R1Remotes.Clans" | Name="Clans"
[5853] RemoteFunction | "ReplicatedStorage.R1AdminModes" | Name="R1AdminModes"
[5854] RemoteFunction | "ReplicatedStorage.R1Admin" | Name="R1Admin"
[5855] RemoteEvent | "ReplicatedStorage.R1AdminGhost" | Name="R1AdminGhost"
[5856] RemoteFunction | "ReplicatedStorage.R1Codes" | Name="R1Codes"
[5857] RemoteFunction | "ReplicatedStorage.R1AdminTrade" | Name="R1AdminTrade"
[5858] RemoteFunction | "ReplicatedStorage.R1TournamentAdmin" | Name="R1TournamentAdmin"
[5859] StringValue | "ReplicatedStorage.R1_TournamentResults" | Name="R1_TournamentResults"; Value="{\"Display\":{\"8141044705\":\"hyperon990\",\"2842177251\":\"Tweedy\",\"7727107\":\"Jur\",\"1445287273\":\"Yjo\",\"40819268\":\"ProCaks\",\"11811507325\":\"miso_broke\",\"1156765686\":\"nemozicle\",\"5618106078\":\"ava\",\"11817445113\":\"itsgnomz\",\"2777837243\":\"IQ45ny\",\"1550204471\":\"fwogshi\",\"5001592947\":\"Ducfishyx\",\"10714926608\":\"rydrn\",\"7006740144\":\"ColttGG\",\"345564379\":\"T_Glok\",\"106778898\":\"SquidyH1\",\"115193381\":\"PiiSant\",\"7454157149\":\"WFY\",\"292168\":\"Logic\",\"4334619128\":\"Dokkii\",\"298665485\":\"bAker\",\"2636022590\":\"CustomArtz\",\"11814088873\":\"JSLAYER\",\"3916344\":\"MarxistMayushi\",\"884389718\":\"fample\",\"11815673201\":\"lNFEKT\",\"5188829241\":\"Dream\",\"3510025715\":\"TSI\",\"344254946\":\"ASneakyCow\",\"1704682295\":\"R1 Zeus\",\"11851355019\":\"xTheRealSpencer\",\"257755552\":\"Srch\",\"843588\":\"TDUMPs\",\"11817111978\":\"Tunessssz\",\"11399040780\":\"kayzahMACHINE\",\"2508271861\":\"Anthulol\",\"11815385587\":\"PlarthyP\",\"554967147\":\"SainttSFV\",\"238240040\":\"Wardy\",\"110014809\":\"eflawless\",\"4370471629\":\"whoott\",\"8455510706\":\"17BitsX\",\"973085539\":\"redyslav\",\"4233923201\":\"noble\",\"4462947838\":\"Filthy_Ape\",\"78624454\":\"Jumalikato\",\"2270450128\":\"ThatsSoRaven\",\"974853572\":\"BigDogReis\",\"2927851198\":\"BostonianTom\",\"5357756498\":\"El_Caprice\",\"490646305\":\"sesity\",\"301584430\":\"Blessed\",\"11815482686\":\"ZLAYDREN\",\"11813837683\":\"OvenFPS\",\"11820559442\":\"FloWANTIX\",\"7837422285\":\"noohiding\",\"43266506\":\"Surferkia\",\"3401915324\":\"thebigboy2857\",\"518978337\":\"xivors\",\"2688085389\":\"SkyedPlays\",\"11581509532\":\"notZulah\",\"2913603982\":\"izzy\",\"10155982908\":\"m1shkiii12\",\"72563644\":\"nrb\",\"112576686\":\"Abaddon\",\"75193905\":\"asap\",\"3864948723\":\"Navyseal9521\",\"7908174466\":\"ElDeLaPLAzA510\",\"147621098\":\"Extorsionzzzz\",\"9322822538\":\"MadMaxineSadiee\",\"11325721363\":\"ddxrayo33\",\"701016395\":\"Bash\",\"10614387091\":\"realfyte\",\"2262186932\":\"RomDuu\",\"7428115468\":\"ItzKicksTV\",\"170032769\":\"FENCES4FUN\",\"47629839\":\"R_iver\",\"11907413034\":\"nuzz\",\"60366299\":\"CharlesUU\",\"180444517\":\"itsbbd\",\"11813999782\":\"HiisowCS\",\"3902010985\":\"aim\",\"11847302755\":\"TV_RagnarOFICIAL\",\"2363840278\":\"rickyR1\",\"11684110482\":\"DoniG\",\"4727060565\":\"vamp\",\"9455875029\":\"Kronick\",\"4986757010\":\"EgirlSpitbucket\",\"313282186\":\"saku zay\",\"3876117257\":\"iced\",\"11813379341\":\"sLoth\",\"11815790360\":\"SputzBTW\",\"5111900390\":\"slumpyR1\"},\"Matches\":{\"A\":{\"Players\":[{\"h\":4,\"k\":4,\"p\":1,\"id\":3902010985,\"d\":785,\"w\":[],\"n\":\"aimtossers\"},{\"h\":4,\"k\":5,\"p\":2,\"id\":2508271861,\"d\":884,\"w\":[],\"n\":\"Anthulol\"},{\"h\":2,\"k\":4,\"p\":3,\"id\":5618106078,\"d\":550,\"w\":[],\"n\":\"brbgettingHaiiii\"},{\"h\":0,\"k\":0,\"p\":4,\"id\":180444517,\"d\":100,\"w\":[],\"n\":\"IlBBDlI\"},{\"h\":3,\"k\":4,\"p\":5,\"id\":60366299,\"d\":785,\"w\":[],\"n\":\"KwSZombie12\"},{\"h\":0,\"k\":0,\"p\":6,\"id\":5357756498,\"d\":25,\"w\":[],\"n\":\"El_Caprice\"},{\"h\":1,\"k\":1,\"p\":7,\"id\":10155982908,\"d\":150,\"w\":[],\"n\":\"m1shkiii12\"},{\"h\":2,\"k\":3,\"p\":8,\"id\":3510025715,\"d\":475,\"w\":[],\"n\":\"TSI_EFT\"},{\"h\":1,\"k\":1,\"p\":9,\"id\":11907413034,\"d\":225,\"w\":[],\"n\":\"nuzzOT\"},{\"h\":0,\"k\":0,\"p\":10,\"id\":11811507325,\"d\":0,\"w\":[],\"n\":\"miso_broke\"},{\"h\":0,\"k\":1,\"p\":11,\"id\":11813379341,\"d\":185,\"w\":[],\"n\":\"sL0th083\"},{\"h\":1,\"k\":2,\"p\":12,\"id\":72563644,\"d\":375,\"w\":[],\"n\":\"nickftwlul\"},{\"h\":2,\"k\":4,\"p\":13,\"id\":25924233,\"d\":425,\"w\":[],\"n\":\"uuvinureturns\"},{\"h\":0,\"k\":0,\"p\":14,\"id\":147621098,\"d\":0,\"w\":[],\"n\":\"Extorsionzzzz\"},{\"h\":0,\"k\":1,\"p\":15,\"id\":4233923201,\"d\":168,\"w\":[],\"n\":\"monfernoBP\"},{\"h\":0,\"k\":1,\"p\":16,\"id\":5111900390,\"d\":100,\"w\":[],\"n\":\"R1slumpy\"},{\"h\":1,\"k\":2,\"p\":17,\"id\":11820559442,\"d\":328,\"w\":[],\"n\":\"FloWANTIX\"},{\"h\":1,\"k\":4,\"p\":18,\"id\":1156765686,\"d\":435,\"w\":[],\"n\":\"nemozicle\"},{\"h\":0,\"k\":0,\"p\":19,\"id\":884389718,\"d\":25,\"w\":[],\"n\":\"Fxmple\"},{\"h\":0,\"k\":0,\"p\":20,\"id\":9322822538,\"d\":0,\"w\":[],\"n\":\"MadMaxineSadiee\"},{\"h\":1,\"k\":1,\"p\":21,\"id\":7428115468,\"d\":150,\"w\":[],\"n\":\"ItzKicksTV\"},{\"h\":0,\"k\":0,\"p\":22,\"id\":40819268,\"d\":25,\"w\":[],\"n\":\"ProCaks\"},{\"h\":0,\"k\":0,\"p\":23,\"id\":2262186932,\"d\":0,\"w\":[],\"n\":\"RomDuu\"},{\"h\":1,\"k\":1,\"p\":24,\"id\":10614387091,\"d\":275,\"w\":[],\"n\":\"realfyte\"},{\"h\":1,\"k\":1,\"p\":25,\"id\":292168,\"d\":250,\"w\":[],\"n\":\"Logic\"},{\"h\":0,\"k\":0,\"p\":26,\"id\":11581509532,\"d\":25,\"w\":[],\"n\":\"notZulah\"},{\"h\":0,\"k\":0,\"p\":27,\"id\":9874022171,\"d\":0,\"w\":[],\"n\":\"RealBakedSmore\"},{\"h\":0,\"k\":0,\"p\":28,\"id\":115193381,\"d\":0,\"w\":[],\"n\":\"StEnJaN\"},{\"h\":0,\"k\":0,\"p\":29,\"id\":5001592947,\"d\":0,\"w\":[],\"n\":\"Ducfishyx\"},{\"h\":0,\"k\":1,\"p\":30,\"id\":701016395,\"d\":108,\"w\":[],\"n\":\"WindowsProgram\"},{\"h\":0,\"k\":0,\"p\":31,\"id\":313282186,\"d\":0,\"w\":[],\"n\":\"JunglelooYt\"},{\"h\":0,\"k\":0,\"p\":32,\"id\":11325721363,\"d\":0,\"w\":[],\"n\":\"ddxrayo33\"},{\"h\":0,\"k\":0,\"p\":33,\"id\":170032769,\"d\":0,\"w\":[],\"n\":\"FENCES4FUN\"},{\"h\":0,\"k\":1,\"p\":34,\"id\":11815790360,\"d\":108,\"w\":[],\"n\":\"SputzBTW\"},{\"h\":0,\"k\":0,\"p\":35,\"id\":5800794919,\"d\":25,\"w\":[],\"n\":\"R1Jacky\"},{\"h\":0,\"k\":0,\"p\":36,\"id\":5592951828,\"d\":0,\"w\":[],\"n\":\"Rev01337\"},{\"h\":0,\"k\":0,\"p\":37,\"id\":5639882188,\"d\":21,\"w\":[],\"n\":\"toxiicday\"},{\"h\":0,\"k\":0,\"p\":38,\"id\":11813999782,\"d\":25,\"w\":[],\"n\":\"HiisowCS\"},{\"h\":0,\"k\":0,\"p\":39,\"id\":9455875029,\"d\":0,\"w\":[],\"n\":\"IamKronick\"},{\"h\":0,\"k\":0,\"p\":40,\"id\":11847302755,\"d\":0,\"w\":[],\"n\":\"ragnar_oficialo\"},{\"h\":0,\"k\":0,\"p\":41,\"id\":11814624817,\"d\":0,\"w\":[],\"n\":\"M0ZAR_FR\"},{\"h\":0,\"k\":0,\"p\":42,\"id\":106778898,\"d\":0,\"w\":[],\"n\":\"SquidyH1\"},{\"h\":0,\"k\":0,\"p\":43,\"id\":7727107,\"d\":0,\"w\":[],\"n\":\"ScumpUS\"},{\"h\":0,\"k\":0,\"p\":44,\"id\":11815673201,\"d\":0,\"w\":[],\"n\":\"lNFEKTx\"}],\"Winner\":\"aimtossers\",\"Key\":\"A\",\"EndedAt\":1794092567,\"Status\":\"Done\",\"Mode\":\"Solo\",\"StartedAt\":1794091715,\"Name\":\"SOLOS - MATCH A\"},\"Final\":{\"Players\":[{\"h\":2,\"k\":6,\"p\":1,\"id\":47629839,\"d\":731,\"w\":[\"Invitational Solos Champion AR-15\",\"Invitational Solos Contender AK-47\",\"Invitational Solos Contender Shotgun\",\"Invitational Solos Helmet\",\"Invitational Solos Military Backpack\"],\"n\":\"R_iver\"},{\"h\":1,\"k\":4,\"p\":2,\"id\":11815385587,\"d\":382,\"w\":[\"Invitational Solos Contender AK-47\",\"Invitational Solos Contender Shotgun\",\"Invitational Solos Helmet\",\"Invitational Solos Military Backpack\"],\"n\":\"PlarthyP\"},{\"h\":2,\"k\":5,\"p\":3,\"id\":7428115468,\"d\":715,\"w\":[\"Invitational Solos Contender Shotgun\",\"Invitational Solos Helmet\",\"Invitational Solos Military Backpack\"],\"n\":\"ItzKicksTV\"},{\"h\":0,\"k\":1,\"p\":4,\"id\":5111900390,\"d\":175,\"w\":[\"Invitational Solos Helmet\",\"Invitational Solos Military Backpack\"],\"n\":\"R1slumpy\"},{\"h\":1,\"k\":2,\"p\":5,\"id\":301584430,\"d\":215,\"w\":[\"Invitational Solos Helmet\",\"Invitational Solos Military Backpack\"],\"n\":\"PowerRoblox109\"},{\"h\":1,\"k\":1,\"p\":6,\"id\":344254946,\"d\":325,\"w\":[\"Invitational Solos Helmet\",\"Invitational Solos Military Backpack\"],\"n\":\"ASneakyCow\"},{\"h\":0,\"k\":0,\"p\":7,\"id\":3510025715,\"d\":113,\"w\":[\"Invitational Solos Helmet\",\"Invitational Solos Military Backpack\"],\"n\":\"TSI_EFT\"},{\"h\":2,\"k\":2,\"p\":8,\"id\":345564379,\"d\":250,\"w\":[\"Invitational Solos Helmet\",\"Invitational Solos Military Backpack\"],\"n\":\"ElvisEyeBrows\"},{\"h\":2,\"k\":2,\"p\":9,\"id\":9322822538,\"d\":379,\"w\":[\"Invitational Solos Helmet\",\"Invitational Solos Military Backpack\"],\"n\":\"MadMaxineSadiee\"},{\"h\":0,\"k\":2,\"p\":10,\"id\":554967147,\"d\":305,\"w\":[\"Invitational Solos Helmet\",\"Invitational Solos Military Backpack\"],\"n\":\"SainttFFA\"},{\"h\":1,\"k\":1,\"p\":11,\"id\":2508271861,\"d\":175,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"Anthulol\"},{\"h\":3,\"k\":3,\"p\":12,\"id\":238240040,\"d\":425,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"Wardybrick2017\"},{\"h\":0,\"k\":0,\"p\":13,\"id\":40819268,\"d\":25,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"ProCaks\"},{\"h\":1,\"k\":1,\"p\":14,\"id\":43266506,\"d\":125,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"SurferkiaPC\"},{\"h\":2,\"k\":2,\"p\":15,\"id\":5188829241,\"d\":250,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"YourDreamEboy\"},{\"h\":0,\"k\":0,\"p\":16,\"id\":2688085389,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"SkyedPlays\"},{\"h\":1,\"k\":1,\"p\":17,\"id\":11813837683,\"d\":174,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"OvenFPS\"},{\"h\":0,\"k\":1,\"p\":18,\"id\":1156765686,\"d\":175,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"nemozicle\"},{\"h\":0,\"k\":0,\"p\":19,\"id\":180444517,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"IlBBDlI\"},{\"h\":0,\"k\":3,\"p\":20,\"id\":60366299,\"d\":350,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"KwSZombie12\"},{\"h\":0,\"k\":0,\"p\":21,\"id\":75193905,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"asvpJT\"},{\"h\":0,\"k\":0,\"p\":22,\"id\":2636022590,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"CustomArtz\"},{\"h\":2,\"k\":2,\"p\":23,\"id\":1704682295,\"d\":221,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"TrashCanZeus\"},{\"h\":0,\"k\":0,\"p\":24,\"id\":11813379341,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"sL0th083\"},{\"h\":0,\"k\":0,\"p\":25,\"id\":407980034,\"d\":100,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"YeezeeManLikeYeezees\"},{\"h\":0,\"k\":0,\"p\":26,\"id\":7454157149,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"WolfyZ33\"},{\"h\":0,\"k\":0,\"p\":27,\"id\":10614387091,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"realfyte\"},{\"h\":1,\"k\":3,\"p\":28,\"id\":72563644,\"d\":300,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"nickftwlul\"},{\"h\":0,\"k\":0,\"p\":29,\"id\":4986757010,\"d\":50,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"EgirlSpitbucket\"},{\"h\":0,\"k\":0,\"p\":30,\"id\":292168,\"d\":50,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"Logic\"},{\"h\":0,\"k\":0,\"p\":31,\"id\":884389718,\"d\":69,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"Fxmple\"},{\"h\":1,\"k\":1,\"p\":32,\"id\":147621098,\"d\":115,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"Extorsionzzzz\"},{\"h\":0,\"k\":1,\"p\":33,\"id\":5618106078,\"d\":125,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"brbgettingHaiiii\"},{\"h\":1,\"k\":1,\"p\":34,\"id\":973085539,\"d\":180,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"redyslavko\"},{\"h\":0,\"k\":0,\"p\":35,\"id\":11815482686,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"ZLAYDREN\"},{\"h\":1,\"k\":1,\"p\":36,\"id\":10155982908,\"d\":175,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"m1shkiii12\"},{\"h\":0,\"k\":0,\"p\":37,\"id\":1550204471,\"d\":75,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"fwogshi\"},{\"h\":0,\"k\":0,\"p\":38,\"id\":4370471629,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"whoottyboy\"},{\"h\":0,\"k\":0,\"p\":39,\"id\":2262186932,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"RomDuu\"},{\"h\":0,\"k\":0,\"p\":40,\"id\":3902010985,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"aimtossers\"},{\"h\":0,\"k\":0,\"p\":41,\"id\":5357756498,\"d\":64,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"El_Caprice\"},{\"h\":0,\"k\":0,\"p\":42,\"id\":163809813,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"roblox_user_163809813\"},{\"h\":0,\"k\":0,\"p\":43,\"id\":11811507325,\"d\":25,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"miso_broke\"},{\"h\":0,\"k\":0,\"p\":44,\"id\":8141044705,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"hyperon990\"},{\"h\":0,\"k\":0,\"p\":45,\"id\":3916344,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"908dtjyvskljdnf98\"},{\"h\":0,\"k\":0,\"p\":46,\"id\":11907413034,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"nuzzOT\"},{\"h\":0,\"k\":0,\"p\":47,\"id\":4233923201,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"monfernoBP\"},{\"h\":0,\"k\":0,\"p\":48,\"id\":11820559442,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"FloWANTIX\"},{\"h\":0,\"k\":0,\"p\":49,\"id\":25924233,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"uuvinureturns\"},{\"h\":0,\"k\":0,\"p\":50,\"id\":3401915324,\"d\":0,\"w\":[\"Invitational Solos Military Backpack\"],\"n\":\"thebigboy2857\"}],\"Winner\":\"R_iver\",\"Key\":\"Final\",\"EndedAt\":1794095504,\"Status\":\"Done\",\"Mode\":\"Solo\",\"StartedAt\":1794094617,\"Name\":\"SOLOS - GRAND FINAL\"},\"Duos\":{\"Players\":[{\"p\":1,\"h\":1,\"k\":4,\"d\":300,\"id\":11815673201,\"t\":8,\"w\":[\"Invitational Duos Champion AR-15\",\"Invitational Duos Contender AK-47\",\"Invitational Duos Contender Shotgun\",\"Invitational Duos Helmet\",\"Invitational Duos Military Backpack\"],\"n\":\"lNFEKTx\"},{\"p\":1,\"h\":1,\"k\":3,\"d\":450,\"id\":11815790360,\"t\":8,\"w\":[\"Invitational Duos Champion AR-15\",\"Invitational Duos Contender AK-47\",\"Invitational Duos Contender Shotgun\",\"Invitational Duos Helmet\",\"Invitational Duos Military Backpack\"],\"n\":\"SputzBTW\"},{\"p\":2,\"h\":2,\"k\":2,\"d\":610,\"id\":75193905,\"t\":18,\"w\":[\"Invitational Duos Contender AK-47\",\"Invitational Duos Contender Shotgun\",\"Invitational Duos Helmet\",\"Invitational Duos Military Backpack\"],\"n\":\"asvpJT\"},{\"p\":2,\"h\":0,\"k\":1,\"d\":25,\"id\":106778898,\"t\":18,\"w\":[\"Invitational Duos Contender AK-47\",\"Invitational Duos Contender Shotgun\",\"Invitational Duos Helmet\",\"Invitational Duos Military Backpack\"],\"n\":\"SquidyH1\"},{\"p\":3,\"h\":2,\"k\":3,\"d\":369,\"id\":973085539,\"t\":21,\"w\":[\"Invitational Duos Contender Shotgun\",\"Invitational Duos Helmet\",\"Invitational Duos Military Backpack\"],\"n\":\"redyslavko\"},{\"p\":3,\"h\":0,\"k\":0,\"d\":75,\"id\":10155982908,\"t\":21,\"w\":[\"Invitational Duos Contender Shotgun\",\"Invitational Duos Helmet\",\"Invitational Duos Military Backpack\"],\"n\":\"m1shkiii12\"},{\"p\":4,\"h\":0,\"k\":1,\"d\":174,\"id\":2363840278,\"t\":20,\"w\":[\"Invitational Duos Helmet\",\"Invitational Duos Military Backpack\"],\"n\":\"Samrhhrhfhf\"},{\"p\":4,\"h\":0,\"k\":0,\"d\":0,\"id\":313282186,\"t\":20,\"w\":[\"Invitational Duos Helmet\",\"Invitational Duos Military Backpack\"],\"n\":\"JunglelooYt\"},{\"p\":5,\"h\":0,\"k\":0,\"d\":75,\"id\":345564379,\"t\":19,\"w\":[\"Invitational Duos Helmet\",\"Invitational Duos Military Backpack\"],\"n\":\"ElvisEyeBrows\"},{\"p\":5,\"h\":0,\"k\":0,\"d\":125,\"id\":3916344,\"t\":19,\"w\":[\"Invitational Duos Helmet\",\"Invitational Duos Military Backpack\"],\"n\":\"908dtjyvskljdnf98\"},{\"p\":6,\"h\":1,\"k\":4,\"d\":325,\"id\":554967147,\"t\":9,\"w\":[\"Invitational Duos Military Backpack\"],\"n\":\"SainttFFA\"},{\"p\":6,\"h\":0,\"k\":0,\"d\":100,\"id\":7908174466,\"t\":9,\"w\":[\"Invitational Duos Military Backpack\"],\"n\":\"ElDeLaPLAzA510\"},{\"p\":7,\"h\":1,\"k\":4,\"d\":380,\"id\":292168,\"t\":15,\"w\":[\"Invitational Duos Military Backpack\"],\"n\":\"Logic\"},{\"p\":7,\"h\":1,\"k\":1,\"d\":200,\"id\":2508271861,\"t\":15,\"w\":[\"Invitational Duos Military Backpack\"],\"n\":\"Anthulol\"},{\"p\":8,\"h\":7,\"k\":7,\"d\":875,\"id\":9455875029,\"t\":2,\"w\":[\"Invitational Duos Military Backpack\"],\"n\":\"IamKronick\"},{\"p\":8,\"h\":2,\"k\":3,\"d\":574,\"id\":11581509532,\"t\":2,\"w\":[\"Invitational Duos Military Backpack\"],\"n\":\"notZulah\"},{\"p\":9,\"h\":1,\"k\":2,\"d\":275,\"id\":301584430,\"t\":5,\"w\":[\"Invitational Duos Military Backpack\"],\"n\":\"PowerRoblox109\"},{\"p\":9,\"h\":0,\"k\":1,\"d\":241,\"id\":4727060565,\"t\":5,\"w\":[\"Invitational Duos Military Backpack\"],\"n\":\"Vamplxrddd\"},{\"p\":10,\"h\":1,\"k\":1,\"d\":103,\"id\":974853572,\"t\":11,\"w\":[\"Invitational Duos Military Backpack\"],\"n\":\"R1steak\"},{\"p\":10,\"h\":0,\"k\":0,\"d\":75,\"id\":112576686,\"t\":11,\"w\":[\"Invitational Duos Military Backpack\"],\"n\":\"Abaddon1x\"},{\"p\":11,\"h\":2,\"k\":2,\"d\":300,\"id\":11817111978,\"t\":3,\"w\":[],\"n\":\"Tunessssz\"},{\"p\":11,\"h\":0,\"k\":0,\"d\":45,\"id\":11847302755,\"t\":3,\"w\":[],\"n\":\"ragnar_oficialo\"},{\"p\":12,\"h\":2,\"k\":2,\"d\":274,\"id\":8141044705,\"t\":4,\"w\":[],\"n\":\"hyperon990\"},{\"p\":12,\"h\":0,\"k\":0,\"d\":0,\"id\":238240040,\"t\":4,\"w\":[],\"n\":\"Wardybrick2017\"},{\"p\":13,\"h\":0,\"k\":0,\"d\":125,\"id\":490646305,\"t\":12,\"w\":[],\"n\":\"Sesitys\"},{\"p\":13,\"h\":0,\"k\":0,\"d\":0,\"id\":5001592947,\"t\":12,\"w\":[],\"n\":\"Ducfishyx\"},{\"p\":14,\"h\":0,\"k\":0,\"d\":25,\"id\":7454157149,\"t\":10,\"w\":[],\"n\":\"WolfyZ33\"},{\"p\":14,\"h\":0,\"k\":0,\"d\":0,\"id\":3864948723,\"t\":10,\"w\":[],\"n\":\"Navyseal9521\"},{\"p\":15,\"h\":1,\"k\":2,\"d\":449,\"id\":11813379341,\"t\":16,\"w\":[],\"n\":\"sL0th083\"},{\"p\":15,\"h\":1,\"k\":1,\"d\":125,\"id\":1550204471,\"t\":16,\"w\":[],\"n\":\"fwogshi\"},{\"p\":16,\"h\":0,\"k\":0,\"d\":0,\"id\":78624454,\"t\":14,\"w\":[],\"n\":\"marinedu61\"},{\"p\":16,\"h\":0,\"k\":0,\"d\":25,\"id\":4370471629,\"t\":14,\"w\":[],\"n\":\"whoottyboy\"},{\"p\":17,\"h\":0,\"k\":1,\"d\":75,\"id\":5111900390,\"t\":6,\"w\":[],\"n\":\"R1slumpy\"},{\"p\":17,\"h\":0,\"k\":0,\"d\":50,\"id\":3876117257,\"t\":6,\"w\":[],\"n\":\"icedoutgng\"},{\"p\":18,\"h\":0,\"k\":1,\"d\":100,\"id\":11817445113,\"t\":17,\"w\":[],\"n\":\"itsgnomz\"},{\"p\":18,\"h\":0,\"k\":0,\"d\":0,\"id\":2842177251,\"t\":17,\"w\":[],\"n\":\"TooRaspy\"},{\"p\":19,\"h\":0,\"k\":0,\"d\":0,\"id\":4233923201,\"t\":24,\"w\":[],\"n\":\"monfernoBP\"},{\"p\":19,\"h\":0,\"k\":0,\"d\":0,\"id\":147621098,\"t\":24,\"w\":[],\"n\":\"Extorsionzzzz\"},{\"p\":20,\"h\":0,\"k\":0,\"d\":0,\"id\":72563644,\"t\":13,\"w\":[],\"n\":\"nickftwlul\"},{\"p\":20,\"h\":0,\"k\":0,\"d\":0,\"id\":2636022590,\"t\":13,\"w\":[],\"n\":\"CustomArtz\"},{\"p\":21,\"h\":0,\"k\":0,\"d\":75,\"id\":7837422285,\"t\":7,\"w\":[],\"n\":\"noohiding\"},{\"p\":21,\"h\":0,\"k\":0,\"d\":25,\"id\":7006740144,\"t\":7,\"w\":[],\"n\":\"ColttGG\"},{\"p\":22,\"h\":0,\"k\":1,\"d\":176,\"id\":2777837243,\"t\":22,\"w\":[],\"n\":\"Jingliu45\"},{\"p\":22,\"h\":0,\"k\":0,\"d\":0,\"id\":4334619128,\"t\":22,\"w\":[],\"n\":\"DokkiiSensei\"},{\"p\":23,\"h\":0,\"k\":0,\"d\":75,\"id\":11684110482,\"t\":23,\"w\":[],\"n\":\"Juhmakingtings\"},{\"p\":23,\"h\":0,\"k\":0,\"d\":43,\"id\":25924233,\"t\":23,\"w\":[],\"n\":\"uuvinureturns\"},{\"p\":24,\"h\":0,\"k\":0,\"d\":0,\"id\":257755552,\"t\":1,\"w\":[],\"n\":\"IdontplayRoblox0326\"},{\"p\":24,\"h\":0,\"k\":0,\"d\":0,\"id\":344254946,\"t\":1,\"w\":[],\"n\":\"ASneakyCow\"}],\"Winner\":\"SputzBTW & lNFEKTx\",\"Key\":\"Duos\",\"EndedAt\":1794090614,\"Status\":\"Done\",\"Mode\":\"Duos\",\"StartedAt\":1794089940,\"Name\":\"DUOS\"},\"B\":{\"Players\":[{\"h\":3,\"k\":5,\"p\":1,\"id\":301584430,\"d\":565,\"w\":[],\"n\":\"PowerRoblox109\"},{\"h\":0,\"k\":3,\"p\":2,\"id\":4370471629,\"d\":325,\"w\":[],\"n\":\"whoottyboy\"},{\"h\":1,\"k\":1,\"p\":3,\"id\":3401915324,\"d\":225,\"w\":[],\"n\":\"thebigboy2857\"},{\"h\":2,\"k\":5,\"p\":4,\"id\":5188829241,\"d\":526,\"w\":[],\"n\":\"YourDreamEboy\"},{\"h\":0,\"k\":2,\"p\":5,\"id\":11815385587,\"d\":175,\"w\":[],\"n\":\"PlarthyP\"},{\"h\":0,\"k\":2,\"p\":6,\"id\":8141044705,\"d\":253,\"w\":[],\"n\":\"hyperon990\"},{\"h\":3,\"k\":3,\"p\":7,\"id\":4986757010,\"d\":325,\"w\":[],\"n\":\"EgirlSpitbucket\"},{\"h\":1,\"k\":2,\"p\":8,\"id\":7454157149,\"d\":225,\"w\":[],\"n\":\"WolfyZ33\"},{\"h\":1,\"k\":1,\"p\":9,\"id\":973085539,\"d\":150,\"w\":[],\"n\":\"redyslavko\"},{\"h\":0,\"k\":1,\"p\":10,\"id\":2688085389,\"d\":132,\"w\":[],\"n\":\"SkyedPlays\"},{\"h\":2,\"k\":2,\"p\":11,\"id\":238240040,\"d\":200,\"w\":[],\"n\":\"Wardybrick2017\"},{\"h\":0,\"k\":0,\"p\":12,\"id\":11815482686,\"d\":50,\"w\":[],\"n\":\"ZLAYDREN\"},{\"h\":0,\"k\":0,\"p\":13,\"id\":163809813,\"d\":0,\"w\":[],\"n\":\"roblox_user_163809813\"},{\"h\":0,\"k\":0,\"p\":14,\"id\":1550204471,\"d\":0,\"w\":[],\"n\":\"fwogshi\"},{\"h\":1,\"k\":3,\"p\":15,\"id\":43266506,\"d\":250,\"w\":[],\"n\":\"SurferkiaPC\"},{\"h\":1,\"k\":1,\"p\":16,\"id\":344254946,\"d\":250,\"w\":[],\"n\":\"ASneakyCow\"},{\"h\":2,\"k\":2,\"p\":17,\"id\":407980034,\"d\":236,\"w\":[],\"n\":\"YeezeeManLikeYeezees\"},{\"h\":0,\"k\":0,\"p\":18,\"id\":1704682295,\"d\":75,\"w\":[],\"n\":\"TrashCanZeus\"},{\"h\":0,\"k\":1,\"p\":19,\"id\":75193905,\"d\":25,\"w\":[],\"n\":\"asvpJT\"},{\"h\":0,\"k\":0,\"p\":20,\"id\":554967147,\"d\":75,\"w\":[],\"n\":\"SainttFFA\"},{\"h\":0,\"k\":0,\"p\":21,\"id\":2636022590,\"d\":0,\"w\":[],\"n\":\"CustomArtz\"},{\"h\":0,\"k\":0,\"p\":22,\"id\":3916344,\"d\":0,\"w\":[],\"n\":\"908dtjyvskljdnf98\"},{\"h\":0,\"k\":0,\"p\":23,\"id\":47629839,\"d\":0,\"w\":[],\"n\":\"R_iver\"},{\"h\":0,\"k\":1,\"p\":24,\"id\":345564379,\"d\":100,\"w\":[],\"n\":\"ElvisEyeBrows\"},{\"h\":1,\"k\":1,\"p\":25,\"id\":11813837683,\"d\":100,\"w\":[],\"n\":\"OvenFPS\"},{\"h\":0,\"k\":0,\"p\":26,\"id\":518978337,\"d\":25,\"w\":[],\"n\":\"xivorsR1\"},{\"h\":0,\"k\":1,\"p\":27,\"id\":2927851198,\"d\":100,\"w\":[],\"n\":\"BostonianTom\"},{\"h\":2,\"k\":2,\"p\":28,\"id\":2270450128,\"d\":275,\"w\":[],\"n\":\"ASimpleRaven\"},{\"h\":0,\"k\":0,\"p\":29,\"id\":2363840278,\"d\":0,\"w\":[],\"n\":\"Samrhhrhfhf\"},{\"h\":1,\"k\":1,\"p\":30,\"id\":11684110482,\"d\":175,\"w\":[],\"n\":\"Juhmakingtings\"},{\"h\":2,\"k\":2,\"p\":31,\"id\":4462947838,\"d\":300,\"w\":[],\"n\":\"Filthy_Ape\"},{\"h\":0,\"k\":1,\"p\":32,\"id\":2913603982,\"d\":127,\"w\":[],\"n\":\"izzyxttv\"},{\"h\":0,\"k\":0,\"p\":33,\"id\":11817111978,\"d\":0,\"w\":[],\"n\":\"Tunessssz\"},{\"h\":0,\"k\":0,\"p\":34,\"id\":3864948723,\"d\":0,\"w\":[],\"n\":\"Navyseal9521\"},{\"h\":0,\"k\":0,\"p\":35,\"id\":8455510706,\"d\":0,\"w\":[],\"n\":\"L17BitsX\"},{\"h\":0,\"k\":0,\"p\":36,\"id\":11932915334,\"d\":0,\"w\":[],\"n\":\"RaijinCloud04\"},{\"h\":0,\"k\":0,\"p\":37,\"id\":3876117257,\"d\":0,\"w\":[],\"n\":\"icedoutgng\"},{\"h\":0,\"k\":0,\"p\":38,\"id\":1445287273,\"d\":0,\"w\":[],\"n\":\"NiNjAXX3520\"},{\"h\":0,\"k\":0,\"p\":39,\"id\":110014809,\"d\":75,\"w\":[],\"n\":\"eflawless\"},{\"h\":0,\"k\":0,\"p\":40,\"id\":11399040780,\"d\":75,\"w\":[],\"n\":\"kayzahMACHINE\"},{\"h\":0,\"k\":1,\"p\":41,\"id\":843588,\"d\":100,\"w\":[],\"n\":\"TDUMPs\"},{\"h\":0,\"k\":0,\"p\":42,\"id\":10714926608,\"d\":0,\"w\":[],\"n\":\"ryd4rian\"},{\"h\":0,\"k\":0,\"p\":43,\"id\":11851355019,\"d\":50,\"w\":[],\"n\":\"xTheRealSpencer\"},{\"h\":0,\"k\":0,\"p\":44,\"id\":189845384,\"d\":75,\"w\":[],\"n\":\"RedJelly1234554321\"},{\"h\":0,\"k\":0,\"p\":45,\"id\":11814088873,\"d\":0,\"w\":[],\"n\":\"BZK_JSLAYER\"},{\"h\":0,\"k\":0,\"p\":46,\"id\":298665485,\"d\":0,\"w\":[],\"n\":\"IlbAkerll\"}],\"Winner\":\"PowerRoblox109\",\"Key\":\"B\",\"EndedAt\":1794094018,\"Status\":\"Done\",\"Mode\":\"Solo\",\"StartedAt\":1794093232,\"Name\":\"SOLOS - MATCH B\"}}}"
[5860] StringValue | "ReplicatedStorage.R1_TournamentLive" | Name="R1_TournamentLive"; Value=""
[5861] StringValue | "ReplicatedStorage.R1_EventCard" | Name="R1_EventCard"; Value=""
[5862] RemoteFunction | "ReplicatedStorage.R1EventCardAdmin" | Name="R1EventCardAdmin"
[5863] StringValue | "ReplicatedStorage.R1_Tournament" | Name="R1_Tournament"; Value="{\"Sub\":\"\",\"Winners\":{\"Solo\":[false,false,false],\"Duos\":[false,false,false]},\"Display\":{\"8141044705\":\"hyperon990\",\"2842177251\":\"Tweedy\",\"7727107\":\"Jur\",\"422987986\":\"fluated\",\"1445287273\":\"Yjo\",\"40819268\":\"ProCaks\",\"11811507325\":\"miso_broke\",\"843588\":\"TDUMPs\",\"9293462360\":\"TEKH1\",\"5618106078\":\"ava\",\"60366299\":\"CharlesUU\",\"2777837243\":\"IQ45ny\",\"110014809\":\"eflawless\",\"5001592947\":\"Ducfishyx\",\"10714926608\":\"rydrn\",\"490646305\":\"sesity\",\"11399040780\":\"kayzahMACHINE\",\"7837422285\":\"noohiding\",\"112576686\":\"Abaddon\",\"7006740144\":\"ColttGG\",\"2363840278\":\"rickyR1\",\"106778898\":\"SquidyH1\",\"115193381\":\"PiiSant\",\"9455875029\":\"Kronick\",\"292168\":\"Logic\",\"974853572\":\"BigDogReis\",\"158072152\":\"FartHeadJim\",\"4334619128\":\"Dokkii\",\"7428115468\":\"ItzKicksTV\",\"298665485\":\"bAker\",\"2636022590\":\"CustomArtz\",\"2754147261\":\"Opal\",\"8163876703\":\"stey1993\",\"4727060565\":\"vamp\",\"11817445113\":\"itsgnomz\",\"7454157149\":\"WFY\",\"3916344\":\"MarxistMayushi\",\"884389718\":\"fample\",\"78624454\":\"Jumalikato\",\"43266506\":\"Surferkia\",\"11815673201\":\"lNFEKT\",\"10614387091\":\"realfyte\",\"5188829241\":\"Dream\",\"11591056373\":\"OathNoCap\",\"1550204471\":\"fwogshi\",\"2688085389\":\"SkyedPlays\",\"11815482686\":\"ZLAYDREN\",\"3510025715\":\"TSI\",\"344254946\":\"ASneakyCow\",\"1704682295\":\"R1 Zeus\",\"11814088873\":\"JSLAYER\",\"257755552\":\"Srch\",\"5118728343\":\"HessMT\",\"11817111978\":\"Tunessssz\",\"3440795\":\"enemy2009\",\"2508271861\":\"Anthulol\",\"11815385587\":\"PlarthyP\",\"554967147\":\"SainttSFV\",\"238240040\":\"Wardy\",\"11907413034\":\"nuzz\",\"4370471629\":\"whoott\",\"7520502411\":\"rilaric\",\"973085539\":\"redyslav\",\"5185456540\":\"MrWhite\",\"11813837683\":\"OvenFPS\",\"11851355019\":\"xTheRealSpencer\",\"9583497783\":\"ZatonHD\",\"4462947838\":\"Filthy_Ape\",\"1156765686\":\"nemozicle\",\"5357756498\":\"El_Caprice\",\"2270450128\":\"ThatsSoRaven\",\"301584430\":\"Blessed\",\"180444517\":\"itsbbd\",\"5538722221\":\"S4gic\",\"11325721363\":\"ddxrayo33\",\"1158135564\":\"MoZaR_FR\",\"8972434487\":\"Milekrng\",\"3401915324\":\"thebigboy2857\",\"518978337\":\"xivors\",\"701016395\":\"Bash\",\"11581509532\":\"notZulah\",\"2913603982\":\"izzy\",\"11820559442\":\"FloWANTIX\",\"72563644\":\"nrb\",\"3876117257\":\"iced\",\"345564379\":\"T_Glok\",\"3864948723\":\"Navyseal9521\",\"7908174466\":\"ElDeLaPLAzA510\",\"147621098\":\"Extorsionzzzz\",\"9322822538\":\"MadMaxineSadiee\",\"11822077179\":\"NickOLarsOn\",\"10155982908\":\"m1shkiii12\",\"11831012895\":\"Tideskiano\",\"1868465500\":\"iiTzSkozz\",\"75193905\":\"asap\",\"170032769\":\"FENCES4FUN\",\"47629839\":\"R_iver\",\"8455510706\":\"17BitsX\",\"2262186932\":\"RomDuu\",\"11847302755\":\"TV_RagnarOFICIAL\",\"11813999782\":\"HiisowCS\",\"3902010985\":\"aim\",\"5111900390\":\"slumpyR1\",\"2927851198\":\"BostonianTom\",\"11684110482\":\"DoniG\",\"4233923201\":\"noble\",\"999545373\":\"ChrisHansn\",\"4986757010\":\"EgirlSpitbucket\",\"313282186\":\"saku zay\",\"16423209\":\"ZOOM\",\"11813379341\":\"sLoth\",\"11815790360\":\"SputzBTW\",\"2808985797\":\"Grin\"},\"At\":1794198057,\"Prizes\":[{\"Duos\":\"1st\",\"Reward\":{\"Id\":\"InvitationalChampion\",\"Kind\":\"Skin\",\"Slot\":\"AR15\"},\"Solo\":\"1st\",\"Tag\":\"1ST\"},{\"Duos\":\"2nd\",\"Reward\":{\"Id\":\"InvitationalContender\",\"Kind\":\"Skin\",\"Slot\":\"AK47\"},\"Solo\":\"2nd\",\"Tag\":\"2ND\"},{\"Duos\":\"3rd\",\"Reward\":{\"Id\":\"InvitationalContender\",\"Kind\":\"Skin\",\"Slot\":\"Pump\"},\"Solo\":\"3rd\",\"Tag\":\"3RD\"},{\"Duos\":\"4th and 5th\",\"Reward\":{\"Id\":\"GorillaInvitational\",\"Kind\":\"Skin\",\"Slot\":\"Helmet\"},\"Solo\":\"4th to 10th\",\"Tag\":\"4TH - 10TH\"},{\"Duos\":\"6th to 10th\",\"Reward\":{\"Id\":\"InvitationalCrown\",\"Kind\":\"Skin\",\"Slot\":\"MilitaryBackpack\"},\"Solo\":\"11th to 50th\",\"Tag\":\"11TH - 50TH\"},{\"Duos\":\"\",\"Reward\":{\"Id\":\"InvitationalPlayer\",\"Kind\":\"Skin\",\"Slot\":\"AR15\"},\"Solo\":\"\",\"Tag\":\"EVERY PLAYER GETS\"}],\"Title\":\"R1 INVITATIONAL\",\"Version\":12,\"By\":\"SafeGameZ\",\"Status\":\"Hidden\",\"Format\":{\"Duos\":25,\"Solo\":100,\"Final\":25},\"Players\":{\"Solo\":[{\"Id\":973085539,\"Name\":\"redyslavko\",\"Match\":\"B\"},{\"Id\":11817111978,\"Name\":\"Tunessssz\",\"Match\":\"B\"},{\"Id\":554967147,\"Name\":\"SainttFFA\",\"Match\":\"B\"},{\"Id\":2270450128,\"Name\":\"ASimpleRaven\",\"Match\":\"B\"},{\"Id\":10614387091,\"Name\":\"realfyte\",\"Match\":\"A\"},{\"Id\":1704682295,\"Name\":\"TrashCanZeus\",\"Match\":\"B\"},{\"Id\":3902010985,\"Name\":\"aimtossers\",\"Match\":\"A\"},{\"Id\":298665485,\"Name\":\"IlbAkerll\",\"Match\":\"B\"},{\"Id\":7727107,\"Name\":\"ScumpUS\",\"Match\":\"A\"},{\"Id\":4370471629,\"Name\":\"whoottyboy\",\"Match\":\"B\"},{\"Id\":4233923201,\"Name\":\"monfernoBP\",\"Match\":\"A\"},{\"Id\":2842177251,\"Name\":\"TooRaspy\",\"Match\":\"A\"},{\"Id\":5185456540,\"Name\":\"LaloSalamanca1715\",\"Match\":\"B\"},{\"Id\":11822077179,\"Name\":\"NickOLarsOn\",\"Match\":\"B\"},{\"Id\":8455510706,\"Name\":\"L17BitsX\",\"Match\":\"B\"},{\"Id\":518978337,\"Name\":\"xivorsR1\",\"Match\":\"B\"},{\"Id\":72563644,\"Name\":\"nickftwlul\",\"Match\":\"A\"},{\"Id\":5001592947,\"Name\":\"Ducfishyx\",\"Match\":\"A\"},{\"Id\":9455875029,\"Name\":\"IamKronick\",\"Match\":\"A\"},{\"Id\":2913603982,\"Name\":\"izzyxttv\",\"Match\":\"B\"},{\"Id\":11813379341,\"Name\":\"sL0th083\",\"Match\":\"A\"},{\"Id\":843588,\"Name\":\"TDUMPs\",\"Match\":\"B\"},{\"Id\":11581509532,\"Name\":\"notZulah\",\"Match\":\"A\"},{\"Id\":1156765686,\"Name\":\"nemozicle\",\"Match\":\"A\"},{\"Id\":301584430,\"Name\":\"PowerRoblox109\",\"Match\":\"B\"},{\"Id\":170032769,\"Name\":\"FENCES4FUN\",\"Match\":\"A\"},{\"Id\":10714926608,\"Name\":\"ryd4rian\",\"Match\":\"B\"},{\"Id\":11684110482,\"Name\":\"Juhmakingtings\",\"Match\":\"B\"},{\"Id\":8141044705,\"Name\":\"hyperon990\",\"Match\":\"B\"},{\"Id\":60366299,\"Name\":\"KwSZombie12\",\"Match\":\"A\"},{\"Id\":5357756498,\"Name\":\"El_Caprice\",\"Match\":\"A\"},{\"Id\":3876117257,\"Name\":\"icedoutgng\",\"Match\":\"B\"},{\"Id\":4986757010,\"Name\":\"EgirlSpitbucket\",\"Match\":\"B\"},{\"Id\":2927851198,\"Name\":\"BostonianTom\",\"Match\":\"B\"},{\"Id\":2808985797,\"Name\":\"Grin_026\",\"Match\":\"A\"},{\"Id\":4334619128,\"Name\":\"DokkiiSensei\",\"Match\":\"B\"},{\"Id\":5111900390,\"Name\":\"R1slumpy\",\"Match\":\"A\"},{\"Id\":701016395,\"Name\":\"WindowsProgram\",\"Match\":\"A\"},{\"Id\":106778898,\"Name\":\"SquidyH1\",\"Match\":\"A\"},{\"Id\":884389718,\"Name\":\"Fxmple\",\"Match\":\"A\"},{\"Id\":2636022590,\"Name\":\"CustomArtz\",\"Match\":\"B\"},{\"Id\":2363840278,\"Name\":\"Samrhhrhfhf\",\"Match\":\"B\"},{\"Id\":7428115468,\"Name\":\"ItzKicksTV\",\"Match\":\"A\"},{\"Id\":11815673201,\"Name\":\"lNFEKTx\",\"Match\":\"A\"},{\"Id\":147621098,\"Name\":\"Extorsionzzzz\",\"Match\":\"A\"},{\"Id\":5538722221,\"Name\":\"S4gic337\",\"Match\":\"B\"},{\"Id\":9322822538,\"Name\":\"MadMaxineSadiee\",\"Match\":\"A\"},{\"Id\":110014809,\"Name\":\"eflawless\",\"Match\":\"B\"},{\"Id\":40819268,\"Name\":\"ProCaks\",\"Match\":\"A\"},{\"Id\":8972434487,\"Name\":\"Milekrng\",\"Match\":\"B\"},{\"Id\":1868465500,\"Name\":\"AnodizeH1\",\"Match\":\"B\"},{\"Id\":11847302755,\"Name\":\"ragnar_oficialo\",\"Match\":\"A\"},{\"Id\":4462947838,\"Name\":\"Filthy_Ape\",\"Match\":\"B\"},{\"Id\":2262186932,\"Name\":\"RomDuu\",\"Match\":\"A\"},{\"Id\":11815790360,\"Name\":\"SputzBTW\",\"Match\":\"A\"},{\"Id\":9293462360,\"Name\":\"TTTeeeKKH1\",\"Match\":\"A\"},{\"Id\":5618106078,\"Name\":\"brbgettingHaiiii\",\"Match\":\"A\"},{\"Id\":75193905,\"Name\":\"asvpJT\",\"Match\":\"B\"},{\"Id\":11399040780,\"Name\":\"kayzahMACHINE\",\"Match\":\"B\"},{\"Id\":9583497783,\"Name\":\"productmariah37259\",\"Match\":\"A\"},{\"Id\":10155982908,\"Name\":\"m1shkiii12\",\"Match\":\"A\"},{\"Id\":7454157149,\"Name\":\"WolfyZ33\",\"Match\":\"B\"},{\"Id\":115193381,\"Name\":\"StEnJaN\",\"Match\":\"A\"},{\"Id\":3510025715,\"Name\":\"TSI_EFT\",\"Match\":\"A\"},{\"Id\":345564379,\"Name\":\"ElvisEyeBrows\",\"Match\":\"B\"},{\"Id\":11820559442,\"Name\":\"FloWANTIX\",\"Match\":\"A\"},{\"Id\":3916344,\"Name\":\"908dtjyvskljdnf98\",\"Match\":\"B\"},{\"Id\":2754147261,\"Name\":\"smeglapo\",\"Match\":\"A\"},{\"Id\":16423209,\"Name\":\"salsaman55\",\"Match\":\"A\"},{\"Id\":999545373,\"Name\":\"ThreadyWolf\",\"Match\":\"A\"},{\"Id\":11813999782,\"Name\":\"HiisowCS\",\"Match\":\"A\"},{\"Id\":1158135564,\"Name\":\"MoZaR_FR\",\"Match\":\"A\"},{\"Id\":11325721363,\"Name\":\"ddxrayo33\",\"Match\":\"A\"},{\"Id\":3864948723,\"Name\":\"Navyseal9521\",\"Match\":\"B\"},{\"Id\":11811507325,\"Name\":\"miso_broke\",\"Match\":\"A\"},{\"Id\":11815385587,\"Name\":\"PlarthyP\",\"Match\":\"B\"},{\"Id\":344254946,\"Name\":\"ASneakyCow\",\"Match\":\"B\"},{\"Id\":180444517,\"Name\":\"IlBBDlI\",\"Match\":\"A\"},{\"Id\":11851355019,\"Name\":\"xTheRealSpencer\",\"Match\":\"B\"},{\"Id\":47629839,\"Name\":\"R_iver\",\"Match\":\"B\"},{\"Id\":11813837683,\"Name\":\"OvenFPS\",\"Match\":\"B\"},{\"Id\":7520502411,\"Name\":\"DonaldHrENDERSON9\",\"Match\":\"B\"},{\"Id\":11907413034,\"Name\":\"nuzzOT\",\"Match\":\"A\"},{\"Id\":3440795,\"Name\":\"enemy2009\",\"Match\":\"B\"},{\"Id\":2688085389,\"Name\":\"SkyedPlays\",\"Match\":\"B\"},{\"Id\":238240040,\"Name\":\"Wardybrick2017\",\"Match\":\"B\"},{\"Id\":5118728343,\"Name\":\"HessMT\",\"Match\":\"A\"},{\"Id\":5188829241,\"Name\":\"YourDreamEboy\",\"Match\":\"B\"},{\"Id\":158072152,\"Name\":\"FartHeadJim\",\"Match\":\"A\"},{\"Id\":313282186,\"Name\":\"JunglelooYt\",\"Match\":\"A\"},{\"Id\":1445287273,\"Name\":\"NiNjAXX3520\",\"Match\":\"B\"},{\"Id\":11814088873,\"Name\":\"BZK_JSLAYER\",\"Match\":\"B\"},{\"Id\":11815482686,\"Name\":\"ZLAYDREN\",\"Match\":\"B\"},{\"Id\":2508271861,\"Name\":\"Anthulol\",\"Match\":\"A\"},{\"Id\":1550204471,\"Name\":\"fwogshi\",\"Match\":\"B\"},{\"Id\":11591056373,\"Name\":\"OathNoCap\",\"Match\":\"A\"},{\"Id\":422987986,\"Name\":\"f1uated\",\"Match\":\"A\"},{\"Id\":292168,\"Name\":\"Logic\",\"Match\":\"A\"},{\"Id\":3401915324,\"Name\":\"thebigboy2857\",\"Match\":\"B\"},{\"Id\":43266506,\"Name\":\"SurferkiaPC\",\"Match\":\"B\"}],\"Duos\":[[{\"Name\":\"redyslavko\",\"Id\":973085539},{\"Name\":\"m1shkiii12\",\"Id\":10155982908}],[{\"Name\":\"OathNoCap\",\"Id\":11591056373},{\"Name\":\"asvpJT\",\"Id\":75193905}],[{\"Name\":\"whoottyboy\",\"Id\":4370471629},{\"Name\":\"marinedu61\",\"Id\":78624454}],[{\"Name\":\"SainttFFA\",\"Id\":554967147},{\"Name\":\"ElDeLaPLAzA510\",\"Id\":7908174466}],[{\"Name\":\"TooRaspy\",\"Id\":2842177251},{\"Name\":\"itsgnomz\",\"Id\":11817445113}],[{\"Name\":\"notZulah\",\"Id\":11581509532},{\"Name\":\"IamKronick\",\"Id\":9455875029}],[{\"Name\":\"lNFEKTx\",\"Id\":11815673201},{\"Name\":\"SputzBTW\",\"Id\":11815790360}],[{\"Name\":\"Vamplxrddd\",\"Id\":4727060565},{\"Name\":\"PowerRoblox109\",\"Id\":301584430}],[{\"Name\":\"TTTeeeKKH1\",\"Id\":9293462360},{\"Name\":\"stey1993\",\"Id\":8163876703}],[{\"Name\":\"IdontplayRoblox0326\",\"Id\":257755552},{\"Name\":\"ASneakyCow\",\"Id\":344254946}],[{\"Name\":\"ElvisEyeBrows\",\"Id\":345564379},{\"Name\":\"908dtjyvskljdnf98\",\"Id\":3916344}],[{\"Name\":\"salsaman55\",\"Id\":16423209},{\"Name\":\"smeglapo\",\"Id\":2754147261}],[{\"Name\":\"Navyseal9521\",\"Id\":3864948723},{\"Name\":\"WolfyZ33\",\"Id\":7454157149}],[{\"Name\":\"Logic\",\"Id\":292168},{\"Name\":\"Anthulol\",\"Id\":2508271861}],[{\"Name\":\"SteakFlake\",\"Id\":974853572},{\"Name\":\"Abaddon1x\",\"Id\":112576686}],[{\"Name\":\"JunglelooYt\",\"Id\":313282186},{\"Name\":\"Samrhhrhfhf\",\"Id\":2363840278}],[{\"Name\":\"ColttGG\",\"Id\":7006740144},{\"Name\":\"noohiding\",\"Id\":7837422285}],[{\"Name\":\"Juhmakingtings\",\"Id\":11684110482},{\"Name\":\"Tideskiano\",\"Id\":11831012895}],[{\"Name\":\"DokkiiSensei\",\"Id\":4334619128},{\"Name\":\"Jingliu45\",\"Id\":2777837243}],[{\"Name\":\"Wardybrick2017\",\"Id\":238240040},{\"Name\":\"hyperon990\",\"Id\":8141044705}],[{\"Name\":\"fwogshi\",\"Id\":1550204471},{\"Name\":\"sL0th083\",\"Id\":11813379341}],[{\"Name\":\"icedoutgng\",\"Id\":3876117257},{\"Name\":\"R1slumpy\",\"Id\":5111900390}],[{\"Name\":\"ragnar_oficialo\",\"Id\":11847302755},{\"Name\":\"Tunessssz\",\"Id\":11817111978}],[{\"Name\":\"Ducfishyx\",\"Id\":5001592947},{\"Name\":\"Sesitys\",\"Id\":490646305}],[{\"Name\":\"CustomArtz\",\"Id\":2636022590},{\"Name\":\"nickftwlul\",\"Id\":72563644}]]},\"StartsAt\":1794088800}"
[5864] Folder | "ReplicatedStorage.R1QueueState" | Name="R1QueueState"; attr:Message=""; attr:Count=0; attr:StartAt=0; attr:Status="Idle"; attr:ServerRegion="NorthAmerica"
[5865] Folder | "ReplicatedStorage.TPS" | Name="TPS"
[5866] ModuleScript | "ReplicatedStorage.TPS.ChallengeCamos" | Name="ChallengeCamos"
[5867] ModuleScript | "ReplicatedStorage.TPS.ChallengeCamos.Data" | Name="Data"
[5868] ModuleScript | "ReplicatedStorage.TPS.ChallengeCamos.Motion" | Name="Motion"
[5869] Folder | "ReplicatedStorage.TPS.ChallengeCamos.Motion.Materials" | Name="Materials"
[5870] Texture | "ReplicatedStorage.TPS.ChallengeCamos.Motion.Materials.DeepCurrent" | Name="DeepCurrent"
[5871] Texture | "ReplicatedStorage.TPS.ChallengeCamos.Motion.Materials.SolarRupture" | Name="SolarRupture"
[5872] Texture | "ReplicatedStorage.TPS.ChallengeCamos.Motion.Materials.HyperGlitter" | Name="HyperGlitter"
[5873] Texture | "ReplicatedStorage.TPS.ChallengeCamos.Motion.Materials.RetroSwirl" | Name="RetroSwirl"
[5874] Decal | "ReplicatedStorage.TPS.ChallengeCamos.Motion.Materials.DeepCurrentDecal" | Name="DeepCurrentDecal"
[5875] Decal | "ReplicatedStorage.TPS.ChallengeCamos.Motion.Materials.SolarRuptureDecal" | Name="SolarRuptureDecal"
[5876] Folder | "ReplicatedStorage.TPS.ChallengeCamos.Assets" | Name="Assets"
[5877] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AR15_Shatter" | Name="AR15_Shatter"
[5878] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AR15_Bloodsport" | Name="AR15_Bloodsport"
[5879] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AR15_Venomscale" | Name="AR15_Venomscale"
[5880] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AR15_RoyalAlloy" | Name="AR15_RoyalAlloy"
[5881] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AR15_SolarRupture" | Name="AR15_SolarRupture"
[5882] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AR15_DeepCurrent" | Name="AR15_DeepCurrent"
[5883] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AR15_HyperGlitter" | Name="AR15_HyperGlitter"
[5884] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AR15_RetroSwirl" | Name="AR15_RetroSwirl"
[5885] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AK47_Shatter" | Name="AK47_Shatter"
[5886] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AK47_Bloodsport" | Name="AK47_Bloodsport"
[5887] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AK47_Venomscale" | Name="AK47_Venomscale"
[5888] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AK47_RoyalAlloy" | Name="AK47_RoyalAlloy"
[5889] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AK47_DeepCurrent" | Name="AK47_DeepCurrent"
[5890] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AK47_HyperGlitter" | Name="AK47_HyperGlitter"
[5891] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.AK47_RetroSwirl" | Name="AK47_RetroSwirl"
[5892] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Pump_Shatter" | Name="Pump_Shatter"
[5893] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Pump_Bloodsport" | Name="Pump_Bloodsport"
[5894] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Pump_Venomscale" | Name="Pump_Venomscale"
[5895] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Pump_RoyalAlloy" | Name="Pump_RoyalAlloy"
[5896] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Pump_SolarRupture" | Name="Pump_SolarRupture"
[5897] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Pump_DeepCurrent" | Name="Pump_DeepCurrent"
[5898] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Pump_HyperGlitter" | Name="Pump_HyperGlitter"
[5899] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Pump_RetroSwirl" | Name="Pump_RetroSwirl"
[5900] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.C1911_Shatter" | Name="C1911_Shatter"
[5901] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.C1911_Bloodsport" | Name="C1911_Bloodsport"
[5902] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.C1911_Venomscale" | Name="C1911_Venomscale"
[5903] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.C1911_RoyalAlloy" | Name="C1911_RoyalAlloy"
[5904] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.C1911_SolarRupture" | Name="C1911_SolarRupture"
[5905] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.C1911_DeepCurrent" | Name="C1911_DeepCurrent"
[5906] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.C1911_HyperGlitter" | Name="C1911_HyperGlitter"
[5907] SurfaceAppearance | "ReplicatedStorage.TPS.ChallengeCamos.Assets.C1911_RetroSwirl" | Name="C1911_RetroSwirl"
[5908] Texture | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Surface_Shatter" | Name="Surface_Shatter"
[5909] Texture | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Surface_Bloodsport" | Name="Surface_Bloodsport"
[5910] Texture | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Surface_Venomscale" | Name="Surface_Venomscale"
[5911] Texture | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Surface_RoyalAlloy" | Name="Surface_RoyalAlloy"
[5912] Texture | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Surface_SolarRupture" | Name="Surface_SolarRupture"
[5913] Texture | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Surface_DeepCurrent" | Name="Surface_DeepCurrent"
[5914] Decal | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Surface_HyperGlitter" | Name="Surface_HyperGlitter"
[5915] Decal | "ReplicatedStorage.TPS.ChallengeCamos.Assets.Surface_RetroSwirl" | Name="Surface_RetroSwirl"
[5916] ModuleScript | "ReplicatedStorage.TPS.WeaponChallengeEngine" | Name="WeaponChallengeEngine"
[5917] ModuleScript | "ReplicatedStorage.TPS.RankedChallenges" | Name="RankedChallenges"
[5918] ModuleScript | "ReplicatedStorage.TPS.WeaponChallenges" | Name="WeaponChallenges"
[5919] ModuleScript | "ReplicatedStorage.TPS.Config" | Name="Config"
[5920] ModuleScript | "ReplicatedStorage.TPS.Shared" | Name="Shared"
[5921] ModuleScript | "ReplicatedStorage.TPS.VehicleSim" | Name="VehicleSim"
[5922] ModuleScript | "ReplicatedStorage.TPS.Progression" | Name="Progression"
[5923] ModuleScript | "ReplicatedStorage.TPS.Skins" | Name="Skins"
[5924] ModuleScript | "ReplicatedStorage.TPS.Keybinds" | Name="Keybinds"
[5925] ModuleScript | "ReplicatedStorage.TPS.Crosshairs" | Name="Crosshairs"
[5926] ModuleScript | "ReplicatedStorage.TPS.Crates" | Name="Crates"
[5927] ModuleScript | "ReplicatedStorage.TPS.Season" | Name="Season"
[5928] ModuleScript | "ReplicatedStorage.TPS.BattlePass" | Name="BattlePass"
[5929] ModuleScript | "ReplicatedStorage.TPS.Store" | Name="Store"
[5930] ModuleScript | "ReplicatedStorage.TPS.Daily" | Name="Daily"
[5931] ModuleScript | "ReplicatedStorage.TPS.ClothesIcon" | Name="ClothesIcon"
[5932] ModuleScript | "ReplicatedStorage.TPS.Event" | Name="Event"
[5933] ModuleScript | "ReplicatedStorage.TPS.Gamepad" | Name="Gamepad"
[5934] ModuleScript | "ReplicatedStorage.TPS.Market" | Name="Market"
[5935] ModuleScript | "ReplicatedStorage.TPS.Hosted" | Name="Hosted"
[5936] ModuleScript | "ReplicatedStorage.TPS.TouchLayout" | Name="TouchLayout"
[5937] ModuleScript | "ReplicatedStorage.TPS.LiveEvent" | Name="LiveEvent"
[5938] ModuleScript | "ReplicatedStorage.TPS.Features" | Name="Features"
[5939] ModuleScript | "ReplicatedStorage.TPS.Ranks" | Name="Ranks"
[5940] ModuleScript | "ReplicatedStorage.TPS.Cosmetics" | Name="Cosmetics"
[5941] ModuleScript | "ReplicatedStorage.TPS.Clans" | Name="Clans"
[5942] ModuleScript | "ReplicatedStorage.TPS.CosmeticsCard" | Name="CosmeticsCard"
[5943] ModuleScript | "ReplicatedStorage.TPS.BattlePassPS2" | Name="BattlePassPS2"
[5944] Folder | "ReplicatedStorage.TPS.ItemAssets" | Name="ItemAssets"
[5945] Model | "ReplicatedStorage.TPS.ItemAssets.Ammo223" | Name="Ammo223"
[5946] Part | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Root" | Name="Root"
[5947] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_openMechanism1_low" | Name="Meshes/ammoBox_openMechanism1_low"
[5948] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_openMechanism1_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5949] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_lid_low" | Name="Meshes/ammoBox_lid_low"
[5950] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_lid_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5951] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring6_low" | Name="Meshes/ammoBox_ring6_low"
[5952] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring6_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5953] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring1_low" | Name="Meshes/ammoBox_ring1_low"
[5954] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring1_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5955] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_arc_low" | Name="Meshes/ammoBox_arc_low"
[5956] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_arc_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5957] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring3_low" | Name="Meshes/ammoBox_ring3_low"
[5958] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring3_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5959] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring5_low" | Name="Meshes/ammoBox_ring5_low"
[5960] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring5_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5961] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_openMechanism2_low" | Name="Meshes/ammoBox_openMechanism2_low"
[5962] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_openMechanism2_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5963] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring2_low" | Name="Meshes/ammoBox_ring2_low"
[5964] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring2_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5965] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring4_low" | Name="Meshes/ammoBox_ring4_low"
[5966] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_ring4_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5967] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_box_low" | Name="Meshes/ammoBox_box_low"
[5968] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.Ammo223.Meshes/ammoBox_box_low.SurfaceAppearance" | Name="SurfaceAppearance"
[5969] Model | "ReplicatedStorage.TPS.ItemAssets.Ammo762" | Name="Ammo762"
[5970] Part | "ReplicatedStorage.TPS.ItemAssets.Ammo762.Root" | Name="Root"
[5971] MeshPart | "ReplicatedStorage.TPS.ItemAssets.Ammo762.7.62x39 Ammo" | Name="7.62x39 Ammo"
[5972] Model | "ReplicatedStorage.TPS.ItemAssets.Ammo12ga" | Name="Ammo12ga"
[5973] Part | "ReplicatedStorage.TPS.ItemAssets.Ammo12ga.Root" | Name="Root"
[5974] Part | "ReplicatedStorage.TPS.ItemAssets.Ammo12ga.Box" | Name="Box"
[5975] Part | "ReplicatedStorage.TPS.ItemAssets.Ammo12ga.Band" | Name="Band"
[5976] Model | "ReplicatedStorage.TPS.ItemAssets.HEGrenade" | Name="HEGrenade"
[5977] MeshPart | "ReplicatedStorage.TPS.ItemAssets.HEGrenade.Safety Pin" | Name="Safety Pin"
[5978] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.HEGrenade.Safety Pin.SurfaceAppearance" | Name="SurfaceAppearance"
[5979] MeshPart | "ReplicatedStorage.TPS.ItemAssets.HEGrenade.Lever" | Name="Lever"
[5980] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.HEGrenade.Lever.SurfaceAppearance" | Name="SurfaceAppearance"
[5981] MeshPart | "ReplicatedStorage.TPS.ItemAssets.HEGrenade.Pull Ring" | Name="Pull Ring"
[5982] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.HEGrenade.Pull Ring.SurfaceAppearance" | Name="SurfaceAppearance"
[5983] MeshPart | "ReplicatedStorage.TPS.ItemAssets.HEGrenade.Grenade" | Name="Grenade"
[5984] SurfaceAppearance | "ReplicatedStorage.TPS.ItemAssets.HEGrenade.Grenade.SurfaceAppearance" | Name="SurfaceAppearance"
[5985] Part | "ReplicatedStorage.TPS.ItemAssets.LootBag" | Name="LootBag"
[5986] SpecialMesh | "ReplicatedStorage.TPS.ItemAssets.LootBag.Mesh" | Name="Mesh"
[5987] Folder | "ReplicatedStorage.TPS.ArmorAssets" | Name="ArmorAssets"
[5988] Accessory | "ReplicatedStorage.TPS.ArmorAssets.Helmet" | Name="Helmet"
[5989] Model | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle" | Name="Handle"
[5990] Part | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.Middle" | Name="Middle"
[5991] Attachment | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.Middle.HeadAttachment" | Name="HeadAttachment"
[5992] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.Middle.Mesh" | Name="Mesh"
[5993] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[5994] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[5995] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[5996] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[5997] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[5998] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[5999] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6000] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6001] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6002] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6003] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6004] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6005] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6006] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6007] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6008] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6009] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6010] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6011] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6012] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6013] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6014] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6015] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6016] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6017] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6018] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6019] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6020] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6021] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6022] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.Helmet.Handle.MeshPart" | Name="MeshPart"
[6023] Accessory | "ReplicatedStorage.TPS.ArmorAssets.LaminatedBodyArmor" | Name="LaminatedBodyArmor"
[6024] Configuration | "ReplicatedStorage.TPS.ArmorAssets.LaminatedBodyArmor.ThumbnailConfiguration" | Name="ThumbnailConfiguration"
[6025] ObjectValue | "ReplicatedStorage.TPS.ArmorAssets.LaminatedBodyArmor.ThumbnailConfiguration.ThumbnailCameraTarget" | Name="ThumbnailCameraTarget"; Value="ReplicatedStorage.TPS.ArmorAssets.LaminatedBodyArmor.LaminatedBodyArmor"
[6026] CFrameValue | "ReplicatedStorage.TPS.ArmorAssets.LaminatedBodyArmor.ThumbnailConfiguration.ThumbnailCameraValue" | Name="ThumbnailCameraValue"; Value=CFrame.new(0.816074,0.674536,-2.12595,-0.933565,-0.101801,0.343646,-4.70877e-06,0.958817,0.284024,-0.358408,0.265153,-0.895119)
[6027] Part | "ReplicatedStorage.TPS.ArmorAssets.LaminatedBodyArmor.LaminatedBodyArmor" | Name="LaminatedBodyArmor"; attr:TPS_VisualSize=Vector3.new(2.167, 1.454, 1.449)
[6028] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.LaminatedBodyArmor.LaminatedBodyArmor.SpecialMesh" | Name="SpecialMesh"
[6029] StringValue | "ReplicatedStorage.TPS.ArmorAssets.LaminatedBodyArmor.LaminatedBodyArmor.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6030] Attachment | "ReplicatedStorage.TPS.ArmorAssets.LaminatedBodyArmor.LaminatedBodyArmor.BodyFrontAttachment" | Name="BodyFrontAttachment"
[6031] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor" | Name="MakeShiftBodyArmor"
[6032] Configuration | "ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor.ThumbnailConfiguration" | Name="ThumbnailConfiguration"
[6033] ObjectValue | "ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor.ThumbnailConfiguration.ThumbnailCameraTarget" | Name="ThumbnailCameraTarget"; Value="ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor.Handle"
[6034] CFrameValue | "ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor.ThumbnailConfiguration.ThumbnailCameraValue" | Name="ThumbnailCameraValue"; Value=CFrame.new(-0.0694365,0.0502367,2.43513,0.999594,0.000353359,-0.0284817,8.11288e-06,0.999919,0.0126903,0.0284839,-0.0126853,0.999514)
[6035] Part | "ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor.Handle" | Name="Handle"; attr:TPS_VisualSize=Vector3.new(2.107, 1.713, 1.187)
[6036] StringValue | "ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6037] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor.Handle.SpecialMesh" | Name="SpecialMesh"
[6038] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor.Handle.BodyFrontAttachment" | Name="BodyFrontAttachment"
[6039] Vector3Value | "ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor.Handle.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1, 1)
[6040] TouchTransmitter | "ReplicatedStorage.TPS.ArmorAssets.MakeShiftBodyArmor.Handle.TouchInterest" | Name="TouchInterest"
[6041] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlackMilitary" | Name="HelmetSkin_BlackMilitary"; attr:R1_From="Black Military Helmet"
[6042] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlackMilitary.Handle" | Name="Handle"
[6043] Vector3Value | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlackMilitary.Handle.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(0.001, 0.001, 0.001)
[6044] Motor6D | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlackMilitary.Handle.MICH Retention" | Name="MICH Retention"
[6045] Motor6D | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlackMilitary.Handle.Helmet" | Name="Helmet"
[6046] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlackMilitary.Handle.HatAttachment" | Name="HatAttachment"
[6047] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlackMilitary.MICH Retention" | Name="MICH Retention"
[6048] SurfaceAppearance | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlackMilitary.MICH Retention.Navy Blue" | Name="Navy Blue"
[6049] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlackMilitary.Helmet" | Name="Helmet"
[6050] SurfaceAppearance | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlackMilitary.Helmet.SurfaceAppearance" | Name="SurfaceAppearance"
[6051] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Bloxxer" | Name="HelmetSkin_Bloxxer"; attr:R1_From="BloxxerHelmet"
[6052] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Bloxxer.Handle" | Name="Handle"
[6053] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Bloxxer.Handle.SpecialMesh" | Name="SpecialMesh"
[6054] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Bloxxer.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6055] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Bloxxer.Handle.HatAttachment" | Name="HatAttachment"
[6056] Weld | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Bloxxer.Handle.AccessoryWeld" | Name="AccessoryWeld"
[6057] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Knight" | Name="HelmetSkin_Knight"; attr:R1_From="Knight Helmet"; attr:R1_Fit="x1.1, down 0.16, back 0.06"
[6058] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Knight.Handler" | Name="Handler"
[6059] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Knight.Handler.Mesh" | Name="Mesh"
[6060] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Knight.Handler.HatAttachment" | Name="HatAttachment"
[6061] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_DominusAureus" | Name="HelmetSkin_DominusAureus"; attr:R1_From="DominusAureus"; attr:R1_Fit="x1.12, centred"
[6062] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_DominusAureus.Handle" | Name="Handle"
[6063] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_DominusAureus.Handle.Mesh" | Name="Mesh"
[6064] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_DominusAureus.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6065] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_DominusAureus.Handle.HatAttachment" | Name="HatAttachment"
[6066] Vector3Value | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_DominusAureus.Handle.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2.1, 2.6, 2)
[6067] Vector3Value | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_DominusAureus.Handle.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2.1, 2.6, 2)
[6068] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Frankie" | Name="HelmetSkin_Frankie"
[6069] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Frankie.Stitched eyes" | Name="Stitched eyes"
[6070] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Frankie.Stitched eyes" | Name="Stitched eyes"
[6071] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Frankie.Handle" | Name="Handle"
[6072] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Frankie.Handle.Mesh" | Name="Mesh"
[6073] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Frankie.Handle.HatAttachment" | Name="HatAttachment"
[6074] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Frankie.Hat" | Name="Hat"
[6075] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Frankie.Hat.Mesh" | Name="Mesh"
[6076] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Frankie.Stitched eyes" | Name="Stitched eyes"
[6077] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Frankie.Stitched eyes" | Name="Stitched eyes"
[6078] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_CardboardRaider" | Name="HelmetSkin_CardboardRaider"
[6079] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_CardboardRaider.Handle" | Name="Handle"
[6080] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_CardboardRaider.Handle.Mesh" | Name="Mesh"
[6081] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_CardboardRaider.Cube.001" | Name="Cube.001"
[6082] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_CardboardRaider.Cylinder.003" | Name="Cylinder.003"
[6083] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_CardboardRaider.Cylinder.002" | Name="Cylinder.002"
[6084] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_CardboardRaider.Handle" | Name="Handle"
[6085] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_CardboardRaider.Handle.HatAttachment" | Name="HatAttachment"
[6086] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_CardboardRaider.Cube.001" | Name="Cube.001"
[6087] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Redrum" | Name="BackpackSkin_Redrum"
[6088] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Redrum.Handle" | Name="Handle"
[6089] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Redrum.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6090] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Redrum.Badge" | Name="Badge"
[6091] Decal | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Redrum.Badge.Decal" | Name="Decal"
[6092] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SchoolGirl" | Name="BackpackSkin_SchoolGirl"
[6093] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SchoolGirl.Handle" | Name="Handle"
[6094] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SchoolGirl.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6095] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Scooter" | Name="HelmetSkin_Scooter"
[6096] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Scooter.Handle" | Name="Handle"; attr:RBXRefinementScale=Vector3.new(1, 1, 1)
[6097] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Scooter.Handle.HatAttachment" | Name="HatAttachment"
[6098] Vector3Value | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Scooter.Handle.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.000110626, -0.2218, -0.000396729)
[6099] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Scooter.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6100] Vector3Value | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Scooter.Handle.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.63031, 0.898104, 1.73151)
[6101] TouchTransmitter | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Scooter.Handle.TouchInterest" | Name="TouchInterest"
[6102] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_SkullFaceBandana" | Name="MaskSkin_SkullFaceBandana"
[6103] Part | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_SkullFaceBandana.Handle" | Name="Handle"
[6104] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_SkullFaceBandana.Handle.Mesh" | Name="Mesh"
[6105] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_SkullFaceBandana.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6106] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_Default" | Name="MaskSkin_Default"
[6107] Part | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_Default.Handle" | Name="Handle"
[6108] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_Default.Handle.Mesh" | Name="Mesh"
[6109] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_Default.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6110] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_HenrysBox" | Name="HelmetSkin_HenrysBox"
[6111] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_HenrysBox.Handle" | Name="Handle"; attr:RBXRefinementScale=Vector3.new(1, 1, 1)
[6112] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_HenrysBox.Handle.HatAttachment" | Name="HatAttachment"
[6113] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_ReallyUgly" | Name="BackpackSkin_ReallyUgly"
[6114] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_ReallyUgly.Handle" | Name="Handle"
[6115] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_ReallyUgly.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6116] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Guitar" | Name="BackpackSkin_Guitar"
[6117] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Guitar.Handle" | Name="Handle"
[6118] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Guitar.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6119] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_EvilClownFaceBandana" | Name="MaskSkin_EvilClownFaceBandana"
[6120] Part | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_EvilClownFaceBandana.Handle" | Name="Handle"
[6121] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_EvilClownFaceBandana.Handle.Mesh" | Name="Mesh"
[6122] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_EvilClownFaceBandana.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6123] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SpaceHelmet" | Name="HelmetSkin_SpaceHelmet"; attr:R1_From="Space Helmet (Testing R1)"; attr:R1_Fit="x1.1, ring at the neck"
[6124] UnionOperation | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SpaceHelmet.Handle" | Name="Handle"
[6125] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SpaceHelmet.Handle.HatAttachment" | Name="HatAttachment"
[6126] Part | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SpaceHelmet.Glass" | Name="Glass"
[6127] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SpaceHelmet.Light" | Name="Light"
[6128] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SinisterPumpkin" | Name="HelmetSkin_SinisterPumpkin"; attr:R1_From="Sinister Pumpkin Helmet (Testing R1)"; attr:R1_Fit="centred, raised 0.06 (the head showed through the top)"
[6129] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SinisterPumpkin.Handle" | Name="Handle"
[6130] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SinisterPumpkin.Handle.HatAttachment" | Name="HatAttachment"
[6131] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Skelly" | Name="HelmetSkin_Skelly"; attr:R1_From="Skelly Helmet (Testing R1)"; attr:R1_Fit="x1.15 of x2.93, down 0.06"
[6132] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Skelly.Handle" | Name="Handle"
[6133] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Skelly.Handle.HatAttachment" | Name="HatAttachment"
[6134] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_HalloweenBag" | Name="BackpackSkin_HalloweenBag"; attr:R1_From="Halloween Bag (Testing R1)"; attr:R1_Fit="x0.9, flat on the back, up 0.15"
[6135] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_HalloweenBag.Handle" | Name="Handle"
[6136] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_HalloweenBag.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6137] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_HogMask" | Name="HelmetSkin_HogMask"; attr:R1_From="Hog Mask (Testing R1)"; attr:R1_Fit="x1, as made (a regular hat accessory)"
[6138] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_HogMask.Handle" | Name="Handle"
[6139] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_HogMask.Handle.HatAttachment" | Name="HatAttachment"
[6140] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_HogMask.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6141] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlueTac" | Name="HelmetSkin_BlueTac"; attr:R1_From="Blue Tac Helmet (Testing R1)"; attr:R1_Fit="x1, as made (a regular hat accessory)"
[6142] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlueTac.Handle" | Name="Handle"
[6143] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlueTac.Handle.HatAttachment" | Name="HatAttachment"
[6144] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_BlueTac.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6145] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_DeerTotem" | Name="BackpackSkin_DeerTotem"; attr:R1_From="Deer Totem Military Backpack (Testing R1)"; attr:R1_Fit="as placed on the dummy SafeGameZ"
[6146] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_DeerTotem.Handle" | Name="Handle"
[6147] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_DeerTotem.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6148] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_DeerTotem.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6149] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Briefcase" | Name="BackpackSkin_Briefcase"; attr:R1_From="Briefcase Backpack (Testing R1)"; attr:R1_Fit="as placed on the dummy SafeGameZ"
[6150] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Briefcase.Handle" | Name="Handle"
[6151] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Briefcase.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6152] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Briefcase.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6153] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Rasta" | Name="BackpackSkin_Rasta"; attr:R1_From="Military Pack (Testing R1) with the Rasta texture"; attr:R1_Fit="as placed on the dummy SafeGameZ"
[6154] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Rasta.Handle" | Name="Handle"
[6155] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Rasta.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6156] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Rasta.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6157] Accessory | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_EvilClown" | Name="GlassesSkin_EvilClown"
[6158] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_EvilClown.Handle" | Name="Handle"
[6159] Attachment | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_EvilClown.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6160] Accessory | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_Default" | Name="GlassesSkin_Default"
[6161] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_Default.Handle" | Name="Handle"
[6162] Attachment | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_Default.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6163] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Coffin" | Name="BackpackSkin_Coffin"; attr:R1_From="Coffin Pack (Testing R1)"; attr:R1_Fit="x1, as made (a regular back accessory)"
[6164] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Coffin.Handle" | Name="Handle"
[6165] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Coffin.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6166] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Coffin.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6167] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_RastaBandana" | Name="MaskSkin_RastaBandana"; attr:R1_From="MaskSkin_EvilClownFaceBandana (the BandanaModel mesh) with the Rasta texture"
[6168] Part | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_RastaBandana.Handle" | Name="Handle"
[6169] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_RastaBandana.Handle.Mesh" | Name="Mesh"
[6170] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_RastaBandana.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6171] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SprinkleCone" | Name="BackpackSkin_SprinkleCone"; attr:R1_From="RegularBackpack (Testing R1) with the Sprinkle Cone texture"; attr:R1_Fit="as built (the RegularBackpack's own BodyBackAttachment)"
[6172] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SprinkleCone.Handle" | Name="Handle"
[6173] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SprinkleCone.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6174] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SprinkleCone.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6175] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Pot" | Name="HelmetSkin_Pot"
[6176] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Pot.Handle" | Name="Handle"
[6177] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Pot.Handle.HatAttachment" | Name="HatAttachment"
[6178] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Gorilla" | Name="HelmetSkin_Gorilla"
[6179] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Gorilla.Handle" | Name="Handle"
[6180] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Gorilla.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6181] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Gorilla.Handle.HatAttachment" | Name="HatAttachment"
[6182] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_InvitationalCrown" | Name="BackpackSkin_InvitationalCrown"; attr:R1_From="Military Pack (Testing R1) with the Invitational Crown texture"; attr:R1_Fit="as placed on the dummy SafeGameZ"
[6183] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_InvitationalCrown.Handle" | Name="Handle"
[6184] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_InvitationalCrown.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6185] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_InvitationalCrown.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6186] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Unicorn" | Name="HelmetSkin_Unicorn"; attr:R1_From="Unicorn HelmetNEW (Testing R1)"
[6187] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Unicorn.Handle" | Name="Handle"
[6188] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Unicorn.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6189] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Unicorn.Handle.HatAttachment" | Name="HatAttachment"
[6190] Accessory | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_PirateEyePatch" | Name="GlassesSkin_PirateEyePatch"; attr:R1_From="Pirate  Eyepatch (Testing R1)"; attr:R1_Fit="x1, as made (a regular hat accessory)"
[6191] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_PirateEyePatch.Handle" | Name="Handle"
[6192] Attachment | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_PirateEyePatch.Handle.HatAttachment" | Name="HatAttachment"
[6193] StringValue | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_PirateEyePatch.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6194] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_FishBox" | Name="HelmetSkin_FishBox"; attr:R1_From="Fish Box (Testing R1)"; attr:R1_Fit="x1, as made (a regular hat accessory)"
[6195] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_FishBox.Handle" | Name="Handle"
[6196] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_FishBox.Handle.HatAttachment" | Name="HatAttachment"
[6197] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_FishBox.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6198] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Jetpack" | Name="BackpackSkin_Jetpack"; attr:R1_From="Jetpack Backpack (Testing R1)"; attr:R1_Fit="x1, as made (a regular back accessory)"
[6199] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Jetpack.Handle" | Name="Handle"
[6200] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Jetpack.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6201] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Jetpack.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6202] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_GorillaInvitational" | Name="HelmetSkin_GorillaInvitational"
[6203] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_GorillaInvitational.Handle" | Name="Handle"
[6204] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_GorillaInvitational.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6205] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_GorillaInvitational.Handle.HatAttachment" | Name="HatAttachment"
[6206] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_JackOLanternBandana" | Name="MaskSkin_JackOLanternBandana"; attr:R1_From="MaskSkin_EvilClownFaceBandana (the BandanaModel mesh) with the Jack-o'-Lantern texture"
[6207] Part | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_JackOLanternBandana.Handle" | Name="Handle"
[6208] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_JackOLanternBandana.Handle.Mesh" | Name="Mesh"
[6209] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_JackOLanternBandana.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6210] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke" | Name="BackpackSkin_Nuke"; attr:R1_From="The live event's nuke (the Map's ReplicatedStorage.R1_LiveEvent.Nuke) at 0.0175x, with a harness"; attr:R1_Fit="Across the back, nose down to the right, fins up behind the left shoulder - lined up by its BodyBackAttachment"
[6211] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Handle" | Name="Handle"
[6212] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6213] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6214] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Nose" | Name="Nose"
[6215] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Nose.WeldConstraint" | Name="WeldConstraint"
[6216] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Tail" | Name="Tail"
[6217] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Tail.WeldConstraint" | Name="WeldConstraint"
[6218] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.TailCap" | Name="TailCap"
[6219] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.TailCap.WeldConstraint" | Name="WeldConstraint"
[6220] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Stripe1" | Name="Stripe1"
[6221] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Stripe1.WeldConstraint" | Name="WeldConstraint"
[6222] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Stripe2" | Name="Stripe2"
[6223] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Stripe2.WeldConstraint" | Name="WeldConstraint"
[6224] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Band" | Name="Band"
[6225] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Band.WeldConstraint" | Name="WeldConstraint"
[6226] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Fin0" | Name="Fin0"
[6227] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Fin0.WeldConstraint" | Name="WeldConstraint"
[6228] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Fin1" | Name="Fin1"
[6229] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Fin1.WeldConstraint" | Name="WeldConstraint"
[6230] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Fin2" | Name="Fin2"
[6231] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Fin2.WeldConstraint" | Name="WeldConstraint"
[6232] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Fin3" | Name="Fin3"
[6233] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Fin3.WeldConstraint" | Name="WeldConstraint"
[6234] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Lamp" | Name="Lamp"
[6235] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Lamp.WeldConstraint" | Name="WeldConstraint"
[6236] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Harness" | Name="Harness"
[6237] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Harness.WeldConstraint" | Name="WeldConstraint"
[6238] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Strap1" | Name="Strap1"
[6239] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Strap1.WeldConstraint" | Name="WeldConstraint"
[6240] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Buckle1" | Name="Buckle1"
[6241] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Buckle1.WeldConstraint" | Name="WeldConstraint"
[6242] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Strap2" | Name="Strap2"
[6243] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Strap2.WeldConstraint" | Name="WeldConstraint"
[6244] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Buckle2" | Name="Buckle2"
[6245] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Nuke.Buckle2.WeldConstraint" | Name="WeldConstraint"
[6246] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_PinkBandana" | Name="MaskSkin_PinkBandana"; attr:R1_From="MaskSkin_EvilClownFaceBandana (the BandanaModel mesh) with the Pink Bandana texture"
[6247] Part | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_PinkBandana.Handle" | Name="Handle"
[6248] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_PinkBandana.Handle.Mesh" | Name="Mesh"
[6249] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_PinkBandana.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6250] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_PatrioticBandana" | Name="MaskSkin_PatrioticBandana"; attr:R1_From="MaskSkin_EvilClownFaceBandana (the BandanaModel mesh) with the Patriotic Bandana texture"
[6251] Part | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_PatrioticBandana.Handle" | Name="Handle"
[6252] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_PatrioticBandana.Handle.Mesh" | Name="Mesh"
[6253] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_PatrioticBandana.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6254] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_CamoBandana" | Name="MaskSkin_CamoBandana"; attr:R1_From="MaskSkin_EvilClownFaceBandana (the BandanaModel mesh) with the Camo Bandana texture"
[6255] Part | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_CamoBandana.Handle" | Name="Handle"
[6256] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_CamoBandana.Handle.Mesh" | Name="Mesh"
[6257] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_CamoBandana.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6258] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_BlueBandana" | Name="MaskSkin_BlueBandana"; attr:R1_From="MaskSkin_EvilClownFaceBandana (the BandanaModel mesh) with the Blue Bandana texture"
[6259] Part | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_BlueBandana.Handle" | Name="Handle"
[6260] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_BlueBandana.Handle.Mesh" | Name="Mesh"
[6261] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_BlueBandana.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6262] Accessory | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_RedBandana" | Name="MaskSkin_RedBandana"; attr:R1_From="MaskSkin_EvilClownFaceBandana (the BandanaModel mesh) with the Red Bandana texture"
[6263] Part | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_RedBandana.Handle" | Name="Handle"
[6264] SpecialMesh | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_RedBandana.Handle.Mesh" | Name="Mesh"
[6265] Attachment | "ReplicatedStorage.TPS.ArmorAssets.MaskSkin_RedBandana.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6266] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_TV" | Name="HelmetSkin_TV"
[6267] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_TV.Handle" | Name="Handle"
[6268] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_TV.Handle.HatAttachment" | Name="HatAttachment"
[6269] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_TrafficCone" | Name="HelmetSkin_TrafficCone"
[6270] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_TrafficCone.Handle" | Name="Handle"
[6271] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_TrafficCone.Handle.HatAttachment" | Name="HatAttachment"
[6272] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_KnightPlume" | Name="HelmetSkin_KnightPlume"
[6273] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_KnightPlume.Handle" | Name="Handle"
[6274] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_KnightPlume.Handle.HatAttachment" | Name="HatAttachment"
[6275] Accessory | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_NightVision" | Name="GlassesSkin_NightVision"
[6276] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_NightVision.Handle" | Name="Handle"
[6277] Attachment | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_NightVision.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6278] Accessory | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_Brow" | Name="GlassesSkin_Brow"
[6279] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_Brow.Handle" | Name="Handle"
[6280] Attachment | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_Brow.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6281] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_TreasureChest" | Name="BackpackSkin_TreasureChest"
[6282] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_TreasureChest.Handle" | Name="Handle"
[6283] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_TreasureChest.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6284] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Radio" | Name="BackpackSkin_Radio"
[6285] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Radio.Handle" | Name="Handle"
[6286] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Radio.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6287] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Sloth083" | Name="BackpackSkin_Sloth083"; attr:R1_From="Military Pack (Rasta) with sL0th083's texture and patches"; attr:R1_Fit="as placed on the dummy SafeGameZ"
[6288] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Sloth083.Handle" | Name="Handle"
[6289] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Sloth083.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6290] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Sloth083.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6291] Decal | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Sloth083.Handle.R1_Patches" | Name="R1_Patches"
[6292] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz" | Name="BackpackSkin_CustomArtz"; attr:R1_Logo="12 see-through Logo tiles on the upper panel, following its curve - each a slice of the logo (a Decal on the MeshPart follows its UVs and smears)"; attr:R1_From="Regular_Backpack_Model (Sprinkle Cone's mesh) with CustomArtz' texture and logo"; attr:R1_Fit="as built (the RegularBackpack's own BodyBackAttachment)"
[6293] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Handle" | Name="Handle"
[6294] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6295] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6296] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6297] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6298] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6299] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6300] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6301] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6302] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6303] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6304] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6305] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6306] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6307] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6308] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6309] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6310] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6311] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6312] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6313] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6314] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6315] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6316] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6317] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6318] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo" | Name="Logo"
[6319] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_CustomArtz.Logo.R1_Logo" | Name="R1_Logo"
[6320] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_LavaTac" | Name="HelmetSkin_LavaTac"; attr:R1_From="Blue Tac Helmet: its mesh with new UVs (the lava wraps round it) + the original as Trim (band, goggles)"; attr:R1_Fit="x1, as made (a regular hat accessory)"
[6321] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_LavaTac.Trim" | Name="Trim"
[6322] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_LavaTac.Trim.WeldConstraint" | Name="WeldConstraint"
[6323] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_LavaTac.Handle" | Name="Handle"; attr:R1_FX="Lava"; tags="R1_SkinFX"
[6324] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_LavaTac.Handle.HatAttachment" | Name="HatAttachment"
[6325] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_LavaTac.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6326] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SafeGameZ" | Name="HelmetSkin_SafeGameZ"
[6327] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SafeGameZ.Handle" | Name="Handle"
[6328] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SafeGameZ.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6329] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SafeGameZ.Handle.HatAttachment" | Name="HatAttachment"
[6330] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SafeGameZ.Crown" | Name="Crown"
[6331] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_SafeGameZ.Crown.WeldConstraint" | Name="WeldConstraint"
[6332] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick" | Name="BackpackSkin_Kronick"; attr:R1_Logo="12 see-through Logo tiles on the upper panel, following its curve - each a slice of the logo (a Decal on the MeshPart follows its UVs and smears)"; attr:R1_From="Regular_Backpack_Model (Sprinkle Cone's mesh) with CustomArtz' texture and logo"; attr:R1_Fit="as built (the RegularBackpack's own BodyBackAttachment)"
[6333] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Handle" | Name="Handle"
[6334] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6335] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6336] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6337] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6338] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6339] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6340] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6341] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6342] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6343] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6344] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6345] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6346] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6347] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6348] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6349] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6350] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6351] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6352] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6353] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6354] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6355] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6356] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6357] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6358] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo" | Name="Logo"
[6359] Texture | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Kronick.Logo.R1_Logo" | Name="R1_Logo"
[6360] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Hazmat" | Name="HelmetSkin_PS2Hazmat"; attr:R1_From="Blue Tac Helmet's mesh in Pre-Season 2's Hazmat paint (MaterialService.R1Skins.R1Skin_PS2HazmatGear)"; attr:R1_Fit="x1, as made (a regular hat accessory)"
[6361] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Hazmat.Handle" | Name="Handle"
[6362] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Hazmat.Handle.HatAttachment" | Name="HatAttachment"
[6363] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Hazmat.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6364] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2GasMask" | Name="HelmetSkin_PS2GasMask"; attr:R1_From="AI-generated mesh (Pre-Season 2 Battle Pass): a gas mask hood"; attr:R1_Fit="x1.28 of the generated mesh (encloses the head); hood centred on the head, filter forward"
[6365] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2GasMask.Handle" | Name="Handle"
[6366] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2GasMask.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6367] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2GasMask.Handle.HatAttachment" | Name="HatAttachment"
[6368] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger" | Name="BackpackSkin_PS2Geiger"; attr:R1_From="Radio Military Backpack's mesh + two uranium canisters (Pre-Season 2 Battle Pass); the right core runs PS2FX Geiger"
[6369] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.Handle" | Name="Handle"
[6370] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6371] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCapTop" | Name="CanisterCapTop"
[6372] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCapTop.WeldConstraint" | Name="WeldConstraint"
[6373] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCapBottom" | Name="CanisterCapBottom"
[6374] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCapBottom.WeldConstraint" | Name="WeldConstraint"
[6375] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCoreL" | Name="CanisterCoreL"
[6376] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCoreL.WeldConstraint" | Name="WeldConstraint"
[6377] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterBar" | Name="CanisterBar"
[6378] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterBar.WeldConstraint" | Name="WeldConstraint"
[6379] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterBar" | Name="CanisterBar"
[6380] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterBar.WeldConstraint" | Name="WeldConstraint"
[6381] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCapTop" | Name="CanisterCapTop"
[6382] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCapTop.WeldConstraint" | Name="WeldConstraint"
[6383] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCapBottom" | Name="CanisterCapBottom"
[6384] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCapBottom.WeldConstraint" | Name="WeldConstraint"
[6385] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCore" | Name="CanisterCore"; attr:R1_FX="Geiger"; tags="R1_SkinFX"
[6386] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterCore.WeldConstraint" | Name="WeldConstraint"
[6387] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterBar" | Name="CanisterBar"
[6388] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterBar.WeldConstraint" | Name="WeldConstraint"
[6389] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterBar" | Name="CanisterBar"
[6390] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Geiger.CanisterBar.WeldConstraint" | Name="WeldConstraint"
[6391] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Mecha" | Name="HelmetSkin_PS2Mecha"; attr:R1_From="Lava Tac helmet (the Blue Tac mesh with new UVs + the original as Trim) painted as mech armour (Pre-Season 2 Battle Pass)"; attr:R1_Fit="x1, as made (a regular hat accessory)"
[6392] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Mecha.Trim" | Name="Trim"
[6393] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Mecha.Trim.WeldConstraint" | Name="WeldConstraint"
[6394] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Mecha.Handle" | Name="Handle"
[6395] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Mecha.Handle.HatAttachment" | Name="HatAttachment"
[6396] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Mecha.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6397] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Kitsune" | Name="HelmetSkin_PS2Kitsune"; attr:R1_From="AI-generated mesh (Pre-Season 2 Battle Pass): a kitsune fox-spirit mask"; attr:R1_Fit="x1.38 / x1.38 / x1.6 of the generated mesh (encloses the head); the eyes show through its eye holes"
[6398] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Kitsune.Handle" | Name="Handle"
[6399] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Kitsune.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6400] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2Kitsune.Handle.HatAttachment" | Name="HatAttachment"
[6401] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Mainframe" | Name="BackpackSkin_PS2Mainframe"; attr:R1_From="Military Pack (the Rasta pack's mesh) as a circuit board (Pre-Season 2 Battle Pass); its processor's core runs PS2FX Mainframe"; attr:R1_Fit="as placed on the dummy SafeGameZ"
[6402] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Mainframe.Handle" | Name="Handle"
[6403] StringValue | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Mainframe.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6404] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Mainframe.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6405] Part | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Mainframe.ProcessorCore" | Name="ProcessorCore"; attr:R1_FX="Mainframe"; tags="R1_SkinFX"
[6406] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_PS2Mainframe.ProcessorCore.WeldConstraint" | Name="WeldConstraint"
[6407] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2CherryBlossom" | Name="HelmetSkin_PS2CherryBlossom"; attr:R1_From="Lava Tac helmet (the Blue Tac mesh with new UVs + the original as Trim) painted as mech armour (Pre-Season 2 Battle Pass)"; attr:R1_Fit="x1, as made (a regular hat accessory)"
[6408] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2CherryBlossom.Trim" | Name="Trim"
[6409] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2CherryBlossom.Trim.WeldConstraint" | Name="WeldConstraint"
[6410] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2CherryBlossom.Handle" | Name="Handle"
[6411] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2CherryBlossom.Handle.HatAttachment" | Name="HatAttachment"
[6412] StringValue | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2CherryBlossom.Handle.AvatarPartScaleType" | Name="AvatarPartScaleType"; Value="Classic"
[6413] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2CherryBlossom.Lining" | Name="Lining"
[6414] WeldConstraint | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PS2CherryBlossom.Lining.WeldConstraint" | Name="WeldConstraint"
[6415] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Viking" | Name="HelmetSkin_Viking"; attr:R1_From="Viking Helmet (Testing R1: Workspace.Accessories)"; attr:R1_Fit="as built (its own HatAttachment)"
[6416] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Viking.Handle" | Name="Handle"
[6417] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Viking.Handle.HatAttachment" | Name="HatAttachment"
[6418] TouchTransmitter | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Viking.Handle.TouchInterest" | Name="TouchInterest"
[6419] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Samurai" | Name="HelmetSkin_Samurai"; attr:R1_From="Samurai Helmet (Testing R1: Workspace.Accessories)"; attr:R1_Fit="as built (its own HatAttachment)"
[6420] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Samurai.Handle" | Name="Handle"
[6421] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Samurai.Handle.HatAttachment" | Name="HatAttachment"
[6422] TouchTransmitter | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_Samurai.Handle.TouchInterest" | Name="TouchInterest"
[6423] Accessory | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PlagueDoctor" | Name="HelmetSkin_PlagueDoctor"; attr:R1_From="Plague Doctor Helmet (Testing R1: Workspace.Accessories)"; attr:R1_Fit="as built (its own HatAttachment)"
[6424] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PlagueDoctor.Handle" | Name="Handle"
[6425] Attachment | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PlagueDoctor.Handle.HatAttachment" | Name="HatAttachment"
[6426] TouchTransmitter | "ReplicatedStorage.TPS.ArmorAssets.HelmetSkin_PlagueDoctor.Handle.TouchInterest" | Name="TouchInterest"
[6427] Accessory | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_HeartShades" | Name="GlassesSkin_HeartShades"; attr:R1_From="Heart Shades (Testing R1: Workspace.Accessories)"; attr:R1_Fit="as built (its own FaceFrontAttachment)"
[6428] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_HeartShades.Handle" | Name="Handle"
[6429] Attachment | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_HeartShades.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6430] TouchTransmitter | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_HeartShades.Handle.TouchInterest" | Name="TouchInterest"
[6431] Accessory | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_CyberVisor" | Name="GlassesSkin_CyberVisor"; attr:R1_From="Cyber Visor (Testing R1: Workspace.Accessories)"; attr:R1_Fit="as built (its own FaceFrontAttachment)"
[6432] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_CyberVisor.Handle" | Name="Handle"
[6433] Attachment | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_CyberVisor.Handle.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6434] TouchTransmitter | "ReplicatedStorage.TPS.ArmorAssets.GlassesSkin_CyberVisor.Handle.TouchInterest" | Name="TouchInterest"
[6435] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Generator" | Name="BackpackSkin_Generator"; attr:R1_From="Field Generator Military Backpack (Testing R1: Workspace.Accessories)"; attr:R1_Fit="as built (its own BodyBackAttachment)"
[6436] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Generator.Handle" | Name="Handle"
[6437] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Generator.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6438] TouchTransmitter | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_Generator.Handle.TouchInterest" | Name="TouchInterest"
[6439] Accessory | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SteelSafe" | Name="BackpackSkin_SteelSafe"; attr:R1_From="Steel Safe Backpack (Testing R1: Workspace.Accessories)"; attr:R1_Fit="as built (its own BodyBackAttachment)"
[6440] MeshPart | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SteelSafe.Handle" | Name="Handle"
[6441] Attachment | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SteelSafe.Handle.BodyBackAttachment" | Name="BodyBackAttachment"
[6442] TouchTransmitter | "ReplicatedStorage.TPS.ArmorAssets.BackpackSkin_SteelSafe.Handle.TouchInterest" | Name="TouchInterest"
[6443] Folder | "ReplicatedStorage.TPS.SkinAssets" | Name="SkinAssets"
[6444] MeshPart | "ReplicatedStorage.TPS.SkinAssets.AR15" | Name="AR15"
[6445] MeshPart | "ReplicatedStorage.TPS.SkinAssets.C1911" | Name="C1911"
[6446] Model | "ReplicatedStorage.TPS.ClothesMannequin" | Name="ClothesMannequin"
[6447] Humanoid | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid" | Name="Humanoid"; Health=100; MaxHealth=100; WalkSpeed=16
[6448] Animator | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.Animator" | Name="Animator"
[6449] NumberValue | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.BodyTypeScale" | Name="BodyTypeScale"; Value=0.30000001192093
[6450] NumberValue | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.BodyProportionScale" | Name="BodyProportionScale"; Value=1
[6451] NumberValue | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.BodyWidthScale" | Name="BodyWidthScale"; Value=1
[6452] NumberValue | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.BodyHeightScale" | Name="BodyHeightScale"; Value=1
[6453] NumberValue | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.BodyDepthScale" | Name="BodyDepthScale"; Value=1
[6454] NumberValue | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.HeadScale" | Name="HeadScale"; Value=1
[6455] HumanoidDescription | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.HumanoidDescription" | Name="HumanoidDescription"
[6456] BodyPartDescription | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.HumanoidDescription.BodyPartDescription" | Name="BodyPartDescription"
[6457] BodyPartDescription | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.HumanoidDescription.BodyPartDescription" | Name="BodyPartDescription"
[6458] BodyPartDescription | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.HumanoidDescription.BodyPartDescription" | Name="BodyPartDescription"
[6459] BodyPartDescription | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.HumanoidDescription.BodyPartDescription" | Name="BodyPartDescription"
[6460] BodyPartDescription | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.HumanoidDescription.BodyPartDescription" | Name="BodyPartDescription"
[6461] BodyPartDescription | "ReplicatedStorage.TPS.ClothesMannequin.Humanoid.HumanoidDescription.BodyPartDescription" | Name="BodyPartDescription"
[6462] BodyColors | "ReplicatedStorage.TPS.ClothesMannequin.Body Colors" | Name="Body Colors"
[6463] Part | "ReplicatedStorage.TPS.ClothesMannequin.HumanoidRootPart" | Name="HumanoidRootPart"
[6464] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.HumanoidRootPart.RootRigAttachment" | Name="RootRigAttachment"
[6465] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.HumanoidRootPart.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.35, 0)
[6466] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.HumanoidRootPart.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 2, 1)
[6467] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.HumanoidRootPart.RootAttachment" | Name="RootAttachment"
[6468] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.HumanoidRootPart.RootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, 0)
[6469] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.LeftHand" | Name="LeftHand"
[6470] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.LeftHand.LeftHand" | Name="LeftHand"
[6471] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftHand.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[6472] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftHand.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478983, 0.125045, 5.96046e-08)
[6473] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftHand.LeftGripAttachment" | Name="LeftGripAttachment"
[6474] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftHand.LeftGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[6475] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[6476] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftHand.LeftWrist" | Name="LeftWrist"
[6477] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftHand.LeftWristBallSocket" | Name="LeftWristBallSocket"
[6478] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.RightHand" | Name="RightHand"
[6479] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.RightHand.RightHand" | Name="RightHand"
[6480] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightHand.RightWristRigAttachment" | Name="RightWristRigAttachment"
[6481] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightHand.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(3.57628e-07, 0.125045, 5.96046e-08)
[6482] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightHand.RightGripAttachment" | Name="RightGripAttachment"
[6483] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightHand.RightGripAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.149955, -1.46306e-07)
[6484] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightHand.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.3001, 1)
[6485] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightHand.RightWrist" | Name="RightWrist"
[6486] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightHand.RightWristBallSocket" | Name="RightWristBallSocket"
[6487] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerArm" | Name="LeftLowerArm"
[6488] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerArm.LeftLowerArm" | Name="LeftLowerArm"
[6489] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[6490] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, 0.258688, 7.64463e-20)
[6491] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerArm.LeftWristRigAttachment" | Name="LeftWristRigAttachment"
[6492] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerArm.LeftWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000478625, -0.500929, 7.64463e-20)
[6493] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[6494] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerArm.LeftElbow" | Name="LeftElbow"
[6495] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerArm.LeftElbowBallSocket" | Name="LeftElbowBallSocket"
[6496] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerArm" | Name="RightLowerArm"
[6497] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerArm.RightLowerArm" | Name="RightLowerArm"
[6498] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[6499] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, 0.258579, 7.64463e-20)
[6500] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerArm.RightWristRigAttachment" | Name="RightWristRigAttachment"
[6501] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerArm.RightWristRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1.19209e-07, -0.500929, -6.86245e-18)
[6502] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.0519, 1)
[6503] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerArm.RightElbow" | Name="RightElbow"
[6504] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerArm.RightElbowBallSocket" | Name="RightElbowBallSocket"
[6505] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm" | Name="LeftUpperArm"
[6506] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftUpperArm" | Name="LeftUpperArm"
[6507] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[6508] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[6509] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[6510] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftShoulderRigAttachment.JointRotation.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, 0.394327, 8.9407e-08)
[6511] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftElbowRigAttachment" | Name="LeftElbowRigAttachment"
[6512] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.000479221, -0.334056, 8.9407e-08)
[6513] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftShoulderAttachment" | Name="LeftShoulderAttachment"
[6514] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.38419e-07, 0.584327, -2.70968e-08)
[6515] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[6516] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftHandNoCollision" | Name="LeftHandNoCollision"
[6517] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftShoulder" | Name="LeftShoulder"
[6518] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperArm.LeftShoulderBallSocket" | Name="LeftShoulderBallSocket"
[6519] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm" | Name="RightUpperArm"
[6520] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightUpperArm" | Name="RightUpperArm"
[6521] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[6522] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[6523] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[6524] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightShoulderRigAttachment.JointRotation.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.500001, 0.394327, 8.9407e-08)
[6525] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightElbowRigAttachment" | Name="RightElbowRigAttachment"
[6526] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightElbowRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-07, -0.334165, 8.9407e-08)
[6527] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightShoulderAttachment" | Name="RightShoulderAttachment"
[6528] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightShoulderAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-8.34465e-07, 0.584327, -2.70968e-08)
[6529] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1687, 1)
[6530] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightHandNoCollision" | Name="RightHandNoCollision"
[6531] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightShoulder" | Name="RightShoulder"
[6532] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperArm.RightShoulderBallSocket" | Name="RightShoulderBallSocket"
[6533] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.LeftFoot" | Name="LeftFoot"
[6534] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.LeftFoot.LeftFoot" | Name="LeftFoot"
[6535] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftFoot.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[6536] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftFoot.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.78814e-07, 0.10194, -1.72228e-06)
[6537] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftFoot.LeftFootAttachment" | Name="LeftFootAttachment"
[6538] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftFoot.LeftFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.0182774, -0.15346, -0.0502639)
[6539] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[6540] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftFoot.LeftAnkle" | Name="LeftAnkle"
[6541] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftFoot.LeftAnkleBallSocket" | Name="LeftAnkleBallSocket"
[6542] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerLeg" | Name="LeftLowerLeg"
[6543] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerLeg.LeftLowerLeg" | Name="LeftLowerLeg"
[6544] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[6545] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(2.98023e-08, 0.379018, -1.60861e-07)
[6546] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerLeg.LeftAnkleRigAttachment" | Name="LeftAnkleRigAttachment"
[6547] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerLeg.LeftAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.547157, -2.21402e-06)
[6548] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[6549] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerLeg.LeftKnee" | Name="LeftKnee"
[6550] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftLowerLeg.LeftKneeBallSocket" | Name="LeftKneeBallSocket"
[6551] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso" | Name="UpperTorso"
[6552] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.UpperTorso" | Name="UpperTorso"
[6553] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[6554] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.799986, 1.19209e-07)
[6555] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.NeckRigAttachment" | Name="NeckRigAttachment"
[6556] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, 0.800017, 1.19209e-07)
[6557] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.LeftShoulderRigAttachment" | Name="LeftShoulderRigAttachment"
[6558] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.LeftShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[6559] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.LeftShoulderRigAttachment.JointRotation" | Name="JointRotation"
[6560] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.LeftShoulderRigAttachment.JointRotation.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.563017, 1.19209e-07)
[6561] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.RightShoulderRigAttachment" | Name="RightShoulderRigAttachment"
[6562] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.RightShoulderRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[6563] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.RightShoulderRigAttachment.JointRotation" | Name="JointRotation"
[6564] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.RightShoulderRigAttachment.JointRotation.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.563017, 1.19209e-07)
[6565] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.BodyFrontAttachment" | Name="BodyFrontAttachment"
[6566] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.BodyFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, -0.5)
[6567] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.BodyBackAttachment" | Name="BodyBackAttachment"
[6568] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.BodyBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.96046e-08, -0.199986, 0.5)
[6569] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.LeftCollarAttachment" | Name="LeftCollarAttachment"
[6570] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.LeftCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1, 0.800017, -7.27397e-08)
[6571] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.NeckAttachment" | Name="NeckAttachment"
[6572] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.NeckAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-5.05859e-08, 0.800017, 7.11172e-08)
[6573] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.RightCollarAttachment" | Name="RightCollarAttachment"
[6574] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.RightCollarAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(1, 0.800017, 4.61296e-08)
[6575] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 1.6, 1)
[6576] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[6577] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[6578] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.LeftUpperLegNoCollision" | Name="LeftUpperLegNoCollision"
[6579] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[6580] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[6581] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.LeftLowerArmNoCollision" | Name="LeftLowerArmNoCollision"
[6582] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.RightLowerArmNoCollision" | Name="RightLowerArmNoCollision"
[6583] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.Waist" | Name="Waist"
[6584] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.UpperTorso.WaistBallSocket" | Name="WaistBallSocket"
[6585] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg" | Name="LeftUpperLeg"
[6586] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg.LeftUpperLeg" | Name="LeftUpperLeg"
[6587] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[6588] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(5.96046e-08, 0.420782, -1.63913e-07)
[6589] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg.LeftKneeRigAttachment" | Name="LeftKneeRigAttachment"
[6590] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg.LeftKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(8.9407e-08, -0.401102, -4.29081e-07)
[6591] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[6592] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg.RightUpperLegNoCollision" | Name="RightUpperLegNoCollision"
[6593] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg.LeftFootNoCollision" | Name="LeftFootNoCollision"
[6594] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg.LeftHip" | Name="LeftHip"
[6595] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LeftUpperLeg.LeftHipBallSocket" | Name="LeftHipBallSocket"
[6596] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.RightFoot" | Name="RightFoot"
[6597] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.RightFoot.RightFoot" | Name="RightFoot"
[6598] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightFoot.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[6599] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightFoot.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.10194, 7.64478e-05)
[6600] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightFoot.RightFootAttachment" | Name="RightFootAttachment"
[6601] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightFoot.RightFootAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.0182774, -0.15346, -0.0502639)
[6602] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightFoot.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 0.299999, 1)
[6603] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightFoot.RightAnkle" | Name="RightAnkle"
[6604] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightFoot.RightAnkleBallSocket" | Name="RightAnkleBallSocket"
[6605] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerLeg" | Name="RightLowerLeg"
[6606] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerLeg.RightLowerLeg" | Name="RightLowerLeg"
[6607] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[6608] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.379174, 2.55536e-05)
[6609] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerLeg.RightAnkleRigAttachment" | Name="RightAnkleRigAttachment"
[6610] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerLeg.RightAnkleRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.547157, 7.6269e-05)
[6611] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.1931, 1)
[6612] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerLeg.RightKnee" | Name="RightKnee"
[6613] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightLowerLeg.RightKneeBallSocket" | Name="RightKneeBallSocket"
[6614] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso" | Name="LowerTorso"
[6615] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.LowerTorso" | Name="LowerTorso"
[6616] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.RootRigAttachment" | Name="RootRigAttachment"
[6617] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.RootRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, -0.199972, -0)
[6618] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.WaistRigAttachment" | Name="WaistRigAttachment"
[6619] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.WaistRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.19209e-07, 0.200025, 7.64463e-20)
[6620] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.LeftHipRigAttachment" | Name="LeftHipRigAttachment"
[6621] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.LeftHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0.5, -0.199972, -0)
[6622] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.RightHipRigAttachment" | Name="RightHipRigAttachment"
[6623] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0.5, -0.199972, -1.91209e-05)
[6624] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.WaistBackAttachment" | Name="WaistBackAttachment"
[6625] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.WaistBackAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.46413e-07, -0.199972, 0.5)
[6626] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.WaistCenterAttachment" | Name="WaistCenterAttachment"
[6627] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.WaistCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-4.22001e-07, -0.199972, -1.65436e-24)
[6628] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.WaistFrontAttachment" | Name="WaistFrontAttachment"
[6629] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.WaistFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-1.3222e-07, -0.199972, -0.5)
[6630] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(2, 0.400101, 1)
[6631] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[6632] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[6633] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.LeftLowerLegNoCollision" | Name="LeftLowerLegNoCollision"
[6634] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.RightLowerLegNoCollision" | Name="RightLowerLegNoCollision"
[6635] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.LowerTorso.Root" | Name="Root"
[6636] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperLeg" | Name="RightUpperLeg"
[6637] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperLeg.RightUpperLeg" | Name="RightUpperLeg"
[6638] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperLeg.RightHipRigAttachment" | Name="RightHipRigAttachment"
[6639] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperLeg.RightHipRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, 0.420782, -6.67301e-05)
[6640] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperLeg.RightKneeRigAttachment" | Name="RightKneeRigAttachment"
[6641] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperLeg.RightKneeRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(-0, -0.400946, -2.18768e-05)
[6642] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperLeg.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1, 1.2166, 0.999899)
[6643] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperLeg.RightFootNoCollision" | Name="RightFootNoCollision"
[6644] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperLeg.RightHip" | Name="RightHip"
[6645] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.RightUpperLeg.RightHipBallSocket" | Name="RightHipBallSocket"
[6646] MeshPart | "ReplicatedStorage.TPS.ClothesMannequin.Head" | Name="Head"
[6647] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.Head.FaceCenterAttachment" | Name="FaceCenterAttachment"
[6648] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.Head.FaceCenterAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.094, 0)
[6649] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.Head.FaceFrontAttachment" | Name="FaceFrontAttachment"
[6650] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.Head.FaceFrontAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0, -0.6)
[6651] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.Head.HairAttachment" | Name="HairAttachment"
[6652] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.Head.HairAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[6653] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.Head.HatAttachment" | Name="HatAttachment"
[6654] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.Head.HatAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, 0.6, 0)
[6655] Attachment | "ReplicatedStorage.TPS.ClothesMannequin.Head.NeckRigAttachment" | Name="NeckRigAttachment"
[6656] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.Head.NeckRigAttachment.OriginalPosition" | Name="OriginalPosition"; Value=Vector3.new(0, -0.586, 0)
[6657] Vector3Value | "ReplicatedStorage.TPS.ClothesMannequin.Head.OriginalSize" | Name="OriginalSize"; Value=Vector3.new(1.1962, 1.20294, 1.19791)
[6658] WrapTarget | "ReplicatedStorage.TPS.ClothesMannequin.Head.Head" | Name="Head"
[6659] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.Head.HumanoidRootPartNoCollision" | Name="HumanoidRootPartNoCollision"
[6660] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.Head.LeftUpperArmNoCollision" | Name="LeftUpperArmNoCollision"
[6661] NoCollisionConstraint | "ReplicatedStorage.TPS.ClothesMannequin.Head.RightUpperArmNoCollision" | Name="RightUpperArmNoCollision"
[6662] AnimationConstraint | "ReplicatedStorage.TPS.ClothesMannequin.Head.Neck" | Name="Neck"
[6663] BallSocketConstraint | "ReplicatedStorage.TPS.ClothesMannequin.Head.NeckBallSocket" | Name="NeckBallSocket"
[6664] Folder | "ReplicatedStorage.TPS.RideAssets" | Name="RideAssets"
[6665] Model | "ReplicatedStorage.TPS.RideAssets.Jeep" | Name="Jeep"; attr:TPS_Vehicle="Jeep"
[6666] Folder | "ReplicatedStorage.TPS.RideAssets.Jeep.Body" | Name="Body"
[6667] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TubSide" | Name="TubSide"
[6668] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TubSide" | Name="TubSide"
[6669] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TubSide" | Name="TubSide"
[6670] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.WheelTub" | Name="WheelTub"
[6671] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.WheelTub" | Name="WheelTub"
[6672] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.BeltCap" | Name="BeltCap"
[6673] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.DoorSeam" | Name="DoorSeam"
[6674] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.DoorSeam" | Name="DoorSeam"
[6675] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.DoorSeam" | Name="DoorSeam"
[6676] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Hinge" | Name="Hinge"
[6677] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Hinge" | Name="Hinge"
[6678] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Handle" | Name="Handle"
[6679] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.RockRail" | Name="RockRail"
[6680] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Mud" | Name="Mud"
[6681] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Mud" | Name="Mud"
[6682] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Rust" | Name="Rust"
[6683] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Rust" | Name="Rust"
[6684] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TubSide" | Name="TubSide"
[6685] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TubSide" | Name="TubSide"
[6686] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TubSide" | Name="TubSide"
[6687] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.WheelTub" | Name="WheelTub"
[6688] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.WheelTub" | Name="WheelTub"
[6689] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.BeltCap" | Name="BeltCap"
[6690] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.DoorSeam" | Name="DoorSeam"
[6691] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.DoorSeam" | Name="DoorSeam"
[6692] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.DoorSeam" | Name="DoorSeam"
[6693] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Hinge" | Name="Hinge"
[6694] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Hinge" | Name="Hinge"
[6695] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Handle" | Name="Handle"
[6696] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.RockRail" | Name="RockRail"
[6697] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Mud" | Name="Mud"
[6698] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Mud" | Name="Mud"
[6699] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Rust" | Name="Rust"
[6700] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Rust" | Name="Rust"
[6701] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Tailgate" | Name="Tailgate"
[6702] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TailgateSeam" | Name="TailgateSeam"
[6703] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TailgateHandle" | Name="TailgateHandle"
[6704] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Mud" | Name="Mud"
[6705] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Plate" | Name="Plate"
[6706] SurfaceGui | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Plate.SurfaceGui" | Name="SurfaceGui"
[6707] TextLabel | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Plate.SurfaceGui.TextLabel" | Name="TextLabel"
[6708] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Underbody" | Name="Underbody"
[6709] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.FrameRail" | Name="FrameRail"
[6710] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.FrameRail" | Name="FrameRail"
[6711] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Axle" | Name="Axle"
[6712] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Axle" | Name="Axle"
[6713] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Diff" | Name="Diff"
[6714] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Cowl" | Name="Cowl"
[6715] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Hood" | Name="Hood"
[6716] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.HoodBulge" | Name="HoodBulge"
[6717] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Rust" | Name="Rust"
[6718] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Rust" | Name="Rust"
[6719] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.HoodLatch" | Name="HoodLatch"
[6720] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.BaySide" | Name="BaySide"
[6721] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.CowlSide" | Name="CowlSide"
[6722] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.HoodLatch" | Name="HoodLatch"
[6723] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.BaySide" | Name="BaySide"
[6724] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.CowlSide" | Name="CowlSide"
[6725] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Grille" | Name="Grille"
[6726] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.GrilleSlot" | Name="GrilleSlot"
[6727] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.GrilleSlot" | Name="GrilleSlot"
[6728] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.GrilleSlot" | Name="GrilleSlot"
[6729] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.GrilleSlot" | Name="GrilleSlot"
[6730] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.GrilleSlot" | Name="GrilleSlot"
[6731] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.GrilleSlot" | Name="GrilleSlot"
[6732] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.GrilleSlot" | Name="GrilleSlot"
[6733] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Mud" | Name="Mud"
[6734] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.HeadlightBezel" | Name="HeadlightBezel"
[6735] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TowHook" | Name="TowHook"
[6736] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.MirrorArm" | Name="MirrorArm"
[6737] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Mirror" | Name="Mirror"
[6738] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.HeadlightBezel" | Name="HeadlightBezel"
[6739] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TowHook" | Name="TowHook"
[6740] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.MirrorArm" | Name="MirrorArm"
[6741] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Mirror" | Name="Mirror"
[6742] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.BumperFront" | Name="BumperFront"
[6743] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.SkidPlate" | Name="SkidPlate"
[6744] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Fender" | Name="Fender"
[6745] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.FenderLip" | Name="FenderLip"
[6746] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6747] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6748] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6749] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6750] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6751] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6752] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6753] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6754] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Mud" | Name="Mud"
[6755] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.RearFlareTop" | Name="RearFlareTop"
[6756] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6757] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6758] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6759] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6760] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6761] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6762] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6763] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6764] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TaillightFrame" | Name="TaillightFrame"
[6765] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Fender" | Name="Fender"
[6766] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.FenderLip" | Name="FenderLip"
[6767] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6768] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6769] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6770] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6771] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6772] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6773] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6774] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6775] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Mud" | Name="Mud"
[6776] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.RearFlareTop" | Name="RearFlareTop"
[6777] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6778] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6779] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6780] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6781] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6782] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6783] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6784] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Flare" | Name="Flare"
[6785] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TaillightFrame" | Name="TaillightFrame"
[6786] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.BumperRear" | Name="BumperRear"
[6787] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.SpareMount" | Name="SpareMount"
[6788] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.SpareTire" | Name="SpareTire"
[6789] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.SpareRim" | Name="SpareRim"
[6790] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.SpareCap" | Name="SpareCap"
[6791] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.SpareSpoke" | Name="SpareSpoke"
[6792] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.SpareSpoke" | Name="SpareSpoke"
[6793] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.SpareSpoke" | Name="SpareSpoke"
[6794] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.SpareSpoke" | Name="SpareSpoke"
[6795] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.SpareSpoke" | Name="SpareSpoke"
[6796] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.WindshieldPillar" | Name="WindshieldPillar"
[6797] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.WindshieldPillar" | Name="WindshieldPillar"
[6798] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.WindshieldHeader" | Name="WindshieldHeader"
[6799] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Wiper" | Name="Wiper"
[6800] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Wiper" | Name="Wiper"
[6801] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.Roof" | Name="Roof"
[6802] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.RoofSeam" | Name="RoofSeam"
[6803] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.RoofSeam" | Name="RoofSeam"
[6804] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.RoofDirt" | Name="RoofDirt"
[6805] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.RoofRail" | Name="RoofRail"
[6806] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.PillarB" | Name="PillarB"
[6807] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.PillarD" | Name="PillarD"
[6808] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.RoofRail" | Name="RoofRail"
[6809] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.PillarB" | Name="PillarB"
[6810] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.PillarD" | Name="PillarD"
[6811] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TopBack" | Name="TopBack"
[6812] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Body.TopBackHeader" | Name="TopBackHeader"
[6813] Folder | "ReplicatedStorage.TPS.RideAssets.Jeep.Glass" | Name="Glass"
[6814] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Glass.Windshield" | Name="Windshield"
[6815] WedgePart | "ReplicatedStorage.TPS.RideAssets.Jeep.Glass.SideGlass" | Name="SideGlass"
[6816] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Glass.SideGlass" | Name="SideGlass"
[6817] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Glass.SideGlass" | Name="SideGlass"
[6818] WedgePart | "ReplicatedStorage.TPS.RideAssets.Jeep.Glass.SideGlass" | Name="SideGlass"
[6819] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Glass.SideGlass" | Name="SideGlass"
[6820] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Glass.SideGlass" | Name="SideGlass"
[6821] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Glass.RearWindow" | Name="RearWindow"
[6822] Folder | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior" | Name="Interior"
[6823] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.Floor" | Name="Floor"
[6824] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.Dashboard" | Name="Dashboard"
[6825] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.DashTop" | Name="DashTop"
[6826] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.Console" | Name="Console"
[6827] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.Shifter" | Name="Shifter"
[6828] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SteeringColumn" | Name="SteeringColumn"
[6829] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SteeringWheel" | Name="SteeringWheel"
[6830] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SeatBase" | Name="SeatBase"
[6831] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SeatCushion" | Name="SeatCushion"
[6832] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SeatBack" | Name="SeatBack"
[6833] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.Headrest" | Name="Headrest"
[6834] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SeatBase" | Name="SeatBase"
[6835] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SeatCushion" | Name="SeatCushion"
[6836] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SeatBack" | Name="SeatBack"
[6837] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.Headrest" | Name="Headrest"
[6838] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.RearBase" | Name="RearBase"
[6839] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.RearCushion" | Name="RearCushion"
[6840] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.RearBack" | Name="RearBack"
[6841] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SportBar" | Name="SportBar"
[6842] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SportBar" | Name="SportBar"
[6843] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Interior.SportBarTop" | Name="SportBarTop"
[6844] Folder | "ReplicatedStorage.TPS.RideAssets.Jeep.Lights" | Name="Lights"
[6845] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Lights.Headlight" | Name="Headlight"
[6846] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Lights.Indicator" | Name="Indicator"
[6847] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Lights.Headlight" | Name="Headlight"
[6848] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Lights.Indicator" | Name="Indicator"
[6849] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Lights.Taillight" | Name="Taillight"
[6850] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Lights.Taillight" | Name="Taillight"
[6851] Folder | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels" | Name="Wheels"
[6852] Model | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR" | Name="Wheel_RR"
[6853] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6854] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6855] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6856] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6857] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6858] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6859] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6860] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6861] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Tire" | Name="Tire"
[6862] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Rim" | Name="Rim"
[6863] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Cap" | Name="Cap"
[6864] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Spoke" | Name="Spoke"
[6865] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Spoke" | Name="Spoke"
[6866] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Spoke" | Name="Spoke"
[6867] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Spoke" | Name="Spoke"
[6868] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Spoke" | Name="Spoke"
[6869] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6870] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6871] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6872] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6873] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6874] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6875] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6876] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RR.Lug" | Name="Lug"
[6877] Model | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL" | Name="Wheel_RL"
[6878] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Tire" | Name="Tire"
[6879] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Rim" | Name="Rim"
[6880] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Cap" | Name="Cap"
[6881] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[6882] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[6883] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[6884] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[6885] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[6886] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6887] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6888] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6889] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6890] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6891] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6892] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6893] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6894] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6895] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6896] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6897] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6898] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6899] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6900] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6901] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_RL.Lug" | Name="Lug"
[6902] Model | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR" | Name="Wheel_FR"
[6903] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Tire" | Name="Tire"
[6904] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Rim" | Name="Rim"
[6905] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Cap" | Name="Cap"
[6906] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Spoke" | Name="Spoke"
[6907] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Spoke" | Name="Spoke"
[6908] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Spoke" | Name="Spoke"
[6909] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Spoke" | Name="Spoke"
[6910] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Spoke" | Name="Spoke"
[6911] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6912] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6913] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6914] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6915] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6916] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6917] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6918] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6919] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6920] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6921] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6922] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6923] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6924] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6925] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6926] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FR.Lug" | Name="Lug"
[6927] Model | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL" | Name="Wheel_FL"
[6928] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Tire" | Name="Tire"
[6929] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Rim" | Name="Rim"
[6930] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Cap" | Name="Cap"
[6931] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[6932] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[6933] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[6934] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[6935] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[6936] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6937] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6938] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6939] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6940] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6941] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6942] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6943] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6944] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6945] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6946] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6947] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6948] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6949] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6950] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6951] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Wheels.Wheel_FL.Lug" | Name="Lug"
[6952] Part | "ReplicatedStorage.TPS.RideAssets.Jeep.Chassis" | Name="Chassis"
[6953] Model | "ReplicatedStorage.TPS.RideAssets.PoliceCar" | Name="PoliceCar"; attr:TPS_Vehicle="PoliceCar"
[6954] Folder | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body" | Name="Body"
[6955] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.GrilleSlat" | Name="GrilleSlat"
[6956] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Grille" | Name="Grille"
[6957] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.HeadlightBezel" | Name="HeadlightBezel"
[6958] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Nose" | Name="Nose"
[6959] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.NoseSlope" | Name="NoseSlope"
[6960] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.FenderFront" | Name="FenderFront"
[6961] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.FenderRear" | Name="FenderRear"
[6962] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Tail" | Name="Tail"
[6963] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.WellFront" | Name="WellFront"
[6964] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.WellRear" | Name="WellRear"
[6965] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.MirrorArm" | Name="MirrorArm"
[6966] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Mirror" | Name="Mirror"
[6967] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.DoorFront" | Name="DoorFront"
[6968] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.DoorRear" | Name="DoorRear"
[6969] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PoliceDecal" | Name="PoliceDecal"
[6970] SurfaceGui | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PoliceDecal.SurfaceGui" | Name="SurfaceGui"
[6971] TextLabel | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PoliceDecal.SurfaceGui.TextLabel" | Name="TextLabel"
[6972] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.UnitDecal" | Name="UnitDecal"
[6973] SurfaceGui | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.UnitDecal.SurfaceGui" | Name="SurfaceGui"
[6974] TextLabel | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.UnitDecal.SurfaceGui.TextLabel" | Name="TextLabel"
[6975] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.DoorSeam" | Name="DoorSeam"
[6976] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Handle" | Name="Handle"
[6977] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Handle" | Name="Handle"
[6978] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.BeltSeal" | Name="BeltSeal"
[6979] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.MirrorArm" | Name="MirrorArm"
[6980] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Mirror" | Name="Mirror"
[6981] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PillarA" | Name="PillarA"
[6982] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PillarC" | Name="PillarC"
[6983] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PillarB" | Name="PillarB"
[6984] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.RoofRail" | Name="RoofRail"
[6985] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PillarA" | Name="PillarA"
[6986] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PillarC" | Name="PillarC"
[6987] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PillarB" | Name="PillarB"
[6988] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.RoofRail" | Name="RoofRail"
[6989] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Roof" | Name="Roof"
[6990] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.WindshieldHeader" | Name="WindshieldHeader"
[6991] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Cowl" | Name="Cowl"
[6992] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.BumperFront" | Name="BumperFront"
[6993] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Grille" | Name="Grille"
[6994] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.GrilleFrame" | Name="GrilleFrame"
[6995] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.GrilleSlat" | Name="GrilleSlat"
[6996] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchCornerF" | Name="ArchCornerF"
[6997] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchCornerR" | Name="ArchCornerR"
[6998] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchLip" | Name="ArchLip"
[6999] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchCornerF" | Name="ArchCornerF"
[7000] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchCornerR" | Name="ArchCornerR"
[7001] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Side" | Name="Side"
[7002] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PushPost" | Name="PushPost"
[7003] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PushMount" | Name="PushMount"
[7004] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.HeadlightBezel" | Name="HeadlightBezel"
[7005] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PushPost" | Name="PushPost"
[7006] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PushMount" | Name="PushMount"
[7007] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PushTop" | Name="PushTop"
[7008] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PushMid" | Name="PushMid"
[7009] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PushPlate" | Name="PushPlate"
[7010] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchLip" | Name="ArchLip"
[7011] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchCornerF" | Name="ArchCornerF"
[7012] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchCornerR" | Name="ArchCornerR"
[7013] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.CabinFloor" | Name="CabinFloor"
[7014] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Firewall" | Name="Firewall"
[7015] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.RearBulkhead" | Name="RearBulkhead"
[7016] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.HoodLine" | Name="HoodLine"
[7017] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.TrunkLine" | Name="TrunkLine"
[7018] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.TrunkLip" | Name="TrunkLip"
[7019] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.SpoilerPost" | Name="SpoilerPost"
[7020] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.SpoilerPost" | Name="SpoilerPost"
[7021] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Spoiler" | Name="Spoiler"
[7022] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.DoorFront" | Name="DoorFront"
[7023] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.DoorRear" | Name="DoorRear"
[7024] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PoliceDecal" | Name="PoliceDecal"
[7025] SurfaceGui | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PoliceDecal.SurfaceGui" | Name="SurfaceGui"
[7026] TextLabel | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.PoliceDecal.SurfaceGui.TextLabel" | Name="TextLabel"
[7027] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.GrilleSlat" | Name="GrilleSlat"
[7028] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Side" | Name="Side"
[7029] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Rocker" | Name="Rocker"
[7030] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchLip" | Name="ArchLip"
[7031] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.UnitDecal" | Name="UnitDecal"
[7032] SurfaceGui | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.UnitDecal.SurfaceGui" | Name="SurfaceGui"
[7033] TextLabel | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.UnitDecal.SurfaceGui.TextLabel" | Name="TextLabel"
[7034] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.DoorSeam" | Name="DoorSeam"
[7035] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Handle" | Name="Handle"
[7036] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Handle" | Name="Handle"
[7037] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.BeltSeal" | Name="BeltSeal"
[7038] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.BumperRear" | Name="BumperRear"
[7039] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Plate" | Name="Plate"
[7040] SurfaceGui | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Plate.SurfaceGui" | Name="SurfaceGui"
[7041] TextLabel | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Plate.SurfaceGui.TextLabel" | Name="TextLabel"
[7042] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.LightbarBase" | Name="LightbarBase"
[7043] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.LightbarDivider" | Name="LightbarDivider"
[7044] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.Rocker" | Name="Rocker"
[7045] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchLip" | Name="ArchLip"
[7046] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchCornerF" | Name="ArchCornerF"
[7047] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Body.ArchCornerR" | Name="ArchCornerR"
[7048] Folder | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass" | Name="Glass"
[7049] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass.SideGlass" | Name="SideGlass"
[7050] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass.SideGlass" | Name="SideGlass"
[7051] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass.SideGlass" | Name="SideGlass"
[7052] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass.SideGlass" | Name="SideGlass"
[7053] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass.SideGlass" | Name="SideGlass"
[7054] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass.SideGlass" | Name="SideGlass"
[7055] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass.SideGlass" | Name="SideGlass"
[7056] WedgePart | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass.SideGlass" | Name="SideGlass"
[7057] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass.Windshield" | Name="Windshield"
[7058] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Glass.RearWindow" | Name="RearWindow"
[7059] Folder | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior" | Name="Interior"
[7060] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.SteeringColumn" | Name="SteeringColumn"
[7061] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.SteeringWheel" | Name="SteeringWheel"
[7062] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.SeatCushion" | Name="SeatCushion"
[7063] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.SeatBack" | Name="SeatBack"
[7064] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.Headrest" | Name="Headrest"
[7065] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.SeatCushion" | Name="SeatCushion"
[7066] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.SeatBack" | Name="SeatBack"
[7067] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.Headrest" | Name="Headrest"
[7068] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.RearCushion" | Name="RearCushion"
[7069] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.RearBack" | Name="RearBack"
[7070] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.Partition" | Name="Partition"
[7071] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.Dashboard" | Name="Dashboard"
[7072] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.DashTop" | Name="DashTop"
[7073] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.Console" | Name="Console"
[7074] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Interior.Laptop" | Name="Laptop"
[7075] Folder | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights" | Name="Lights"
[7076] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights.Headlight" | Name="Headlight"
[7077] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights.Indicator" | Name="Indicator"
[7078] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights.Headlight" | Name="Headlight"
[7079] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights.Indicator" | Name="Indicator"
[7080] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights.Taillight" | Name="Taillight"
[7081] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights.Reverse" | Name="Reverse"
[7082] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights.Taillight" | Name="Taillight"
[7083] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights.Reverse" | Name="Reverse"
[7084] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights.Lightbar_Red" | Name="Lightbar_Red"
[7085] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Lights.Lightbar_Blue" | Name="Lightbar_Blue"
[7086] Folder | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels" | Name="Wheels"
[7087] Model | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RR" | Name="Wheel_RR"
[7088] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RR.Spoke" | Name="Spoke"
[7089] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RR.Spoke" | Name="Spoke"
[7090] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RR.Spoke" | Name="Spoke"
[7091] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RR.Spoke" | Name="Spoke"
[7092] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RR.Tire" | Name="Tire"
[7093] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RR.Rim" | Name="Rim"
[7094] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RR.Cap" | Name="Cap"
[7095] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RR.Spoke" | Name="Spoke"
[7096] Model | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RL" | Name="Wheel_RL"
[7097] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RL.Tire" | Name="Tire"
[7098] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RL.Rim" | Name="Rim"
[7099] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RL.Cap" | Name="Cap"
[7100] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7101] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7102] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7103] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7104] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7105] Model | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FR" | Name="Wheel_FR"
[7106] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FR.Tire" | Name="Tire"
[7107] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FR.Rim" | Name="Rim"
[7108] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FR.Cap" | Name="Cap"
[7109] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FR.Spoke" | Name="Spoke"
[7110] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FR.Spoke" | Name="Spoke"
[7111] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FR.Spoke" | Name="Spoke"
[7112] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FR.Spoke" | Name="Spoke"
[7113] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FR.Spoke" | Name="Spoke"
[7114] Model | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FL" | Name="Wheel_FL"
[7115] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FL.Tire" | Name="Tire"
[7116] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FL.Rim" | Name="Rim"
[7117] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FL.Cap" | Name="Cap"
[7118] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7119] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7120] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7121] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7122] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7123] Part | "ReplicatedStorage.TPS.RideAssets.PoliceCar.Chassis" | Name="Chassis"
[7124] Model | "ReplicatedStorage.TPS.RideAssets.Motorcycle" | Name="Motorcycle"; attr:TPS_Vehicle="Motorcycle"
[7125] Folder | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body" | Name="Body"
[7126] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Clamp" | Name="Clamp"
[7127] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Handlebar" | Name="Handlebar"
[7128] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Shroud" | Name="Shroud"
[7129] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.SideCover" | Name="SideCover"
[7130] SurfaceGui | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.SideCover.SurfaceGui" | Name="SurfaceGui"
[7131] TextLabel | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.SideCover.SurfaceGui.TextLabel" | Name="TextLabel"
[7132] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.SeatBase" | Name="SeatBase"
[7133] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Seat" | Name="Seat"
[7134] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Seat" | Name="Seat"
[7135] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.FenderRear" | Name="FenderRear"
[7136] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Mud" | Name="Mud"
[7137] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Rack" | Name="Rack"
[7138] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Rack" | Name="Rack"
[7139] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Rack" | Name="Rack"
[7140] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Rack" | Name="Rack"
[7141] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Rack" | Name="Rack"
[7142] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Rack" | Name="Rack"
[7143] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Rack" | Name="Rack"
[7144] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.JerryCan" | Name="JerryCan"
[7145] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.JerryCan" | Name="JerryCan"
[7146] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.JerryCan" | Name="JerryCan"
[7147] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.JerryCan" | Name="JerryCan"
[7148] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.JerryCan" | Name="JerryCan"
[7149] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.JerryCan" | Name="JerryCan"
[7150] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Strap" | Name="Strap"
[7151] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Strap" | Name="Strap"
[7152] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Shock" | Name="Shock"
[7153] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Shock" | Name="Shock"
[7154] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Fork" | Name="Fork"
[7155] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.ForkLeg" | Name="ForkLeg"
[7156] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.ForkLeg" | Name="ForkLeg"
[7157] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Fork" | Name="Fork"
[7158] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.ForkLeg" | Name="ForkLeg"
[7159] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.ForkLeg" | Name="ForkLeg"
[7160] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Clamp" | Name="Clamp"
[7161] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Clamp" | Name="Clamp"
[7162] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.NumberPlate" | Name="NumberPlate"
[7163] SurfaceGui | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.NumberPlate.SurfaceGui" | Name="SurfaceGui"
[7164] TextLabel | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.NumberPlate.SurfaceGui.TextLabel" | Name="TextLabel"
[7165] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.HeadlightBezel" | Name="HeadlightBezel"
[7166] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.FenderFront" | Name="FenderFront"
[7167] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.FenderFront" | Name="FenderFront"
[7168] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Mud" | Name="Mud"
[7169] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Clamp" | Name="Clamp"
[7170] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Handlebar" | Name="Handlebar"
[7171] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Handlebar" | Name="Handlebar"
[7172] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Grip" | Name="Grip"
[7173] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Lever" | Name="Lever"
[7174] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Swingarm" | Name="Swingarm"
[7175] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Swingarm" | Name="Swingarm"
[7176] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Chain" | Name="Chain"
[7177] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Chain" | Name="Chain"
[7178] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Mud" | Name="Mud"
[7179] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Handlebar" | Name="Handlebar"
[7180] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Grip" | Name="Grip"
[7181] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Lever" | Name="Lever"
[7182] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.BarPad" | Name="BarPad"
[7183] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Swingarm" | Name="Swingarm"
[7184] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7185] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7186] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7187] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7188] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7189] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Peg" | Name="Peg"
[7190] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7191] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7192] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7193] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7194] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7195] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7196] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7197] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7198] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Peg" | Name="Peg"
[7199] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7200] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Peg" | Name="Peg"
[7201] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7202] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Engine" | Name="Engine"
[7203] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Engine" | Name="Engine"
[7204] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Fins" | Name="Fins"
[7205] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Fins" | Name="Fins"
[7206] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Fins" | Name="Fins"
[7207] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Fins" | Name="Fins"
[7208] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Engine" | Name="Engine"
[7209] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Engine" | Name="Engine"
[7210] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Engine" | Name="Engine"
[7211] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Engine" | Name="Engine"
[7212] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Engine" | Name="Engine"
[7213] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Engine" | Name="Engine"
[7214] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Exhaust" | Name="Exhaust"
[7215] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Exhaust" | Name="Exhaust"
[7216] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Exhaust" | Name="Exhaust"
[7217] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Exhaust" | Name="Exhaust"
[7218] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7219] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Muffler" | Name="Muffler"
[7220] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Exhaust" | Name="Exhaust"
[7221] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Rust" | Name="Rust"
[7222] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Tank" | Name="Tank"
[7223] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.TankTop" | Name="TankTop"
[7224] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.TankStripe" | Name="TankStripe"
[7225] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.TankCap" | Name="TankCap"
[7226] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Rust" | Name="Rust"
[7227] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Shroud" | Name="Shroud"
[7228] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Shroud" | Name="Shroud"
[7229] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.SideCover" | Name="SideCover"
[7230] SurfaceGui | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.SideCover.SurfaceGui" | Name="SurfaceGui"
[7231] TextLabel | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.SideCover.SurfaceGui.TextLabel" | Name="TextLabel"
[7232] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Rust" | Name="Rust"
[7233] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Shroud" | Name="Shroud"
[7234] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7235] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7236] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7237] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7238] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Frame" | Name="Frame"
[7239] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Body.Peg" | Name="Peg"
[7240] Folder | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Lights" | Name="Lights"
[7241] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Lights.Taillight" | Name="Taillight"
[7242] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Lights.Headlight" | Name="Headlight"
[7243] Folder | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels" | Name="Wheels"
[7244] Model | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL" | Name="Wheel_RL"
[7245] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Tire" | Name="Tire"
[7246] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Rim" | Name="Rim"
[7247] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Hub" | Name="Hub"
[7248] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7249] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7250] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7251] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7252] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7253] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7254] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7255] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7256] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7257] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7258] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7259] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7260] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7261] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7262] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7263] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Spoke" | Name="Spoke"
[7264] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Sprocket" | Name="Sprocket"
[7265] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7266] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7267] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7268] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7269] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7270] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7271] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7272] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7273] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7274] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7275] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7276] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7277] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7278] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7279] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7280] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_RL.Lug" | Name="Lug"
[7281] Model | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL" | Name="Wheel_FL"
[7282] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Tire" | Name="Tire"
[7283] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Rim" | Name="Rim"
[7284] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Hub" | Name="Hub"
[7285] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7286] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7287] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7288] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7289] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7290] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7291] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7292] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7293] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7294] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7295] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7296] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7297] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7298] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7299] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7300] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Spoke" | Name="Spoke"
[7301] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Disc" | Name="Disc"
[7302] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7303] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7304] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7305] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7306] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7307] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7308] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7309] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7310] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7311] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7312] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7313] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7314] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7315] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7316] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7317] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Wheels.Wheel_FL.Lug" | Name="Lug"
[7318] Part | "ReplicatedStorage.TPS.RideAssets.Motorcycle.Chassis" | Name="Chassis"
[7319] Folder | "ReplicatedStorage.TPS.SkinPBR" | Name="SkinPBR"
[7320] SurfaceAppearance | "ReplicatedStorage.TPS.SkinPBR.AK47_Patriotic" | Name="AK47_Patriotic"
[7321] SurfaceAppearance | "ReplicatedStorage.TPS.SkinPBR.AR15_Avalynn" | Name="AR15_Avalynn"
[7322] SurfaceAppearance | "ReplicatedStorage.TPS.SkinPBR.AR15_InvitationalChampion" | Name="AR15_InvitationalChampion"
[7323] SurfaceAppearance | "ReplicatedStorage.TPS.SkinPBR.AK47_InvitationalContender" | Name="AK47_InvitationalContender"
[7324] SurfaceAppearance | "ReplicatedStorage.TPS.SkinPBR.Pump_InvitationalContender" | Name="Pump_InvitationalContender"
[7325] SurfaceAppearance | "ReplicatedStorage.TPS.SkinPBR.AR15_Swashbuckler" | Name="AR15_Swashbuckler"
[7326] SurfaceAppearance | "ReplicatedStorage.TPS.SkinPBR.Pump_Aydren" | Name="Pump_Aydren"
[7327] SurfaceAppearance | "ReplicatedStorage.TPS.SkinPBR.AR15_Cyclops" | Name="AR15_Cyclops"
[7328] SurfaceAppearance | "ReplicatedStorage.TPS.SkinPBR.AK47_PreSeason2Golden" | Name="AK47_PreSeason2Golden"
[7329] Folder | "ReplicatedStorage.TPS.WeaponAssets" | Name="WeaponAssets"
[7330] Model | "ReplicatedStorage.TPS.WeaponAssets.AK47" | Name="AK47"; attr:ScaleApplied=0.82734427796332; attr:NativeLength=3.6260600090027
[7331] Part | "ReplicatedStorage.TPS.WeaponAssets.AK47.Handle" | Name="Handle"
[7332] Attachment | "ReplicatedStorage.TPS.WeaponAssets.AK47.Handle.Muzzle" | Name="Muzzle"
[7333] Attachment | "ReplicatedStorage.TPS.WeaponAssets.AK47.Handle.RightGrip" | Name="RightGrip"
[7334] Attachment | "ReplicatedStorage.TPS.WeaponAssets.AK47.Handle.LeftGrip" | Name="LeftGrip"
[7335] MeshPart | "ReplicatedStorage.TPS.WeaponAssets.AK47.AKMesh" | Name="AKMesh"
[7336] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.AK47.AKMesh.WeldConstraint" | Name="WeldConstraint"
[7337] Model | "ReplicatedStorage.TPS.WeaponAssets.C1911" | Name="C1911"; attr:ScaleApplied=0.625; attr:NativeLength=1.6
[7338] Part | "ReplicatedStorage.TPS.WeaponAssets.C1911.Handle" | Name="Handle"
[7339] Attachment | "ReplicatedStorage.TPS.WeaponAssets.C1911.Handle.Muzzle" | Name="Muzzle"
[7340] Attachment | "ReplicatedStorage.TPS.WeaponAssets.C1911.Handle.RightGrip" | Name="RightGrip"
[7341] Attachment | "ReplicatedStorage.TPS.WeaponAssets.C1911.Handle.LeftGrip" | Name="LeftGrip"
[7342] Part | "ReplicatedStorage.TPS.WeaponAssets.C1911.Pistol" | Name="Pistol"
[7343] SpecialMesh | "ReplicatedStorage.TPS.WeaponAssets.C1911.Pistol.Mesh" | Name="Mesh"
[7344] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.C1911.Pistol.WeldConstraint" | Name="WeldConstraint"
[7345] Model | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle" | Name="HuntingRifle"; attr:ScaleApplied=0.43; attr:NativeLength=9.3
[7346] Part | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Handle" | Name="Handle"
[7347] Attachment | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Handle.Muzzle" | Name="Muzzle"
[7348] Attachment | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Handle.LeftGrip" | Name="LeftGrip"
[7349] Attachment | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Handle.RightGrip" | Name="RightGrip"
[7350] Attachment | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Handle.ScopeEye" | Name="ScopeEye"
[7351] Attachment | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Handle.Bolt" | Name="Bolt"
[7352] UnionOperation | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Stock" | Name="Stock"
[7353] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Stock.WeldConstraint" | Name="WeldConstraint"
[7354] UnionOperation | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Mag" | Name="Mag"
[7355] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Mag.WeldConstraint" | Name="WeldConstraint"
[7356] UnionOperation | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Stock" | Name="Stock"
[7357] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Stock.WeldConstraint" | Name="WeldConstraint"
[7358] UnionOperation | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Stock" | Name="Stock"
[7359] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Stock.WeldConstraint" | Name="WeldConstraint"
[7360] Part | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs" | Name="Crosshairs"
[7361] BlockMesh | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs.Mesh" | Name="Mesh"
[7362] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs.WeldConstraint" | Name="WeldConstraint"
[7363] Part | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs" | Name="Crosshairs"
[7364] BlockMesh | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs.Mesh" | Name="Mesh"
[7365] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs.WeldConstraint" | Name="WeldConstraint"
[7366] Part | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs" | Name="Crosshairs"
[7367] BlockMesh | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs.Mesh" | Name="Mesh"
[7368] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs.WeldConstraint" | Name="WeldConstraint"
[7369] Part | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Center dot" | Name="Center dot"
[7370] BlockMesh | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Center dot.Mesh" | Name="Mesh"
[7371] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Center dot.WeldConstraint" | Name="WeldConstraint"
[7372] Part | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs" | Name="Crosshairs"
[7373] BlockMesh | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs.Mesh" | Name="Mesh"
[7374] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs.WeldConstraint" | Name="WeldConstraint"
[7375] Part | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs" | Name="Crosshairs"
[7376] BlockMesh | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs.Mesh" | Name="Mesh"
[7377] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Crosshairs.WeldConstraint" | Name="WeldConstraint"
[7378] Part | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Part" | Name="Part"
[7379] BlockMesh | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Part.Mesh" | Name="Mesh"
[7380] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Part.WeldConstraint" | Name="WeldConstraint"
[7381] UnionOperation | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Lenses" | Name="Lenses"
[7382] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Lenses.WeldConstraint" | Name="WeldConstraint"
[7383] UnionOperation | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Housing" | Name="Housing"
[7384] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Housing.WeldConstraint" | Name="WeldConstraint"
[7385] UnionOperation | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Union" | Name="Union"
[7386] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.HuntingRifle.Union.WeldConstraint" | Name="WeldConstraint"
[7387] Model | "ReplicatedStorage.TPS.WeaponAssets.Pump" | Name="Pump"; attr:ScaleApplied=1.1390362670127; attr:NativeLength=2.633805513382
[7388] Part | "ReplicatedStorage.TPS.WeaponAssets.Pump.Handle" | Name="Handle"
[7389] Attachment | "ReplicatedStorage.TPS.WeaponAssets.Pump.Handle.Muzzle" | Name="Muzzle"
[7390] Attachment | "ReplicatedStorage.TPS.WeaponAssets.Pump.Handle.RightGrip" | Name="RightGrip"
[7391] Attachment | "ReplicatedStorage.TPS.WeaponAssets.Pump.Handle.LeftGrip" | Name="LeftGrip"
[7392] Attachment | "ReplicatedStorage.TPS.WeaponAssets.Pump.Handle.LoadPort" | Name="LoadPort"
[7393] MeshPart | "ReplicatedStorage.TPS.WeaponAssets.Pump.Shotgun" | Name="Shotgun"
[7394] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.Pump.Shotgun.WeldConstraint" | Name="WeldConstraint"
[7395] Model | "ReplicatedStorage.TPS.WeaponAssets.AR15" | Name="AR15"; attr:ScaleApplied=0.88235279268049; attr:NativeLength=3.4000005722046
[7396] Part | "ReplicatedStorage.TPS.WeaponAssets.AR15.Handle" | Name="Handle"
[7397] Attachment | "ReplicatedStorage.TPS.WeaponAssets.AR15.Handle.RightGrip" | Name="RightGrip"
[7398] Attachment | "ReplicatedStorage.TPS.WeaponAssets.AR15.Handle.LeftGrip" | Name="LeftGrip"
[7399] Attachment | "ReplicatedStorage.TPS.WeaponAssets.AR15.Handle.Muzzle" | Name="Muzzle"
[7400] Part | "ReplicatedStorage.TPS.WeaponAssets.AR15.HandleMesh" | Name="HandleMesh"
[7401] SpecialMesh | "ReplicatedStorage.TPS.WeaponAssets.AR15.HandleMesh.Mesh" | Name="Mesh"
[7402] WeldConstraint | "ReplicatedStorage.TPS.WeaponAssets.AR15.HandleMesh.WeldConstraint" | Name="WeldConstraint"
[7403] Folder | "ReplicatedStorage.R1_Limited" | Name="R1_Limited"; attr:AK47_Witchfire=150; attr:Mask_EvilClownFaceBandana=150; attr:Pump_EventHorizon=400; attr:AR15_Constellation=100; attr:Mask_PatrioticBandana=500; attr:Glasses_PirateEyePatch=400; attr:Mask_JackOLanternBandana=263; attr:Mask_PinkBandana=300; attr:Helmet_SafeGameZ=100; attr:Helmet_LavaTac=174; attr:AK47_Glitch=250; attr:Glasses_EvilClownGlasses=350
------------------------------------------------------------
-- SERVICE: Lighting
------------------------------------------------------------
[7404] Lighting | "Lighting" | Name="Lighting"; attr:RBX_LightingTechnologyUnifiedMigration=true
[7405] DepthOfFieldEffect | "Lighting.DepthOfField" | Name="DepthOfField"
[7406] ColorCorrectionEffect | "Lighting.R1MenuMood" | Name="R1MenuMood"
[7407] Atmosphere | "Lighting.R1SceneAtmosphere" | Name="R1SceneAtmosphere"
[7408] BloomEffect | "Lighting.R1SceneBloom" | Name="R1SceneBloom"
[7409] ColorCorrectionEffect | "Lighting.R1SceneGrade" | Name="R1SceneGrade"
------------------------------------------------------------
-- SERVICE: StarterGui
------------------------------------------------------------
[7410] StarterGui | "StarterGui" | Name="StarterGui"
------------------------------------------------------------
-- SERVICE: StarterPack
------------------------------------------------------------
[7411] StarterPack | "StarterPack" | Name="StarterPack"
------------------------------------------------------------
-- SERVICE: StarterPlayer
------------------------------------------------------------
[7412] StarterPlayer | "StarterPlayer" | Name="StarterPlayer"
[7413] ModuleScript | "StarterPlayer.PlayerModule" | Name="PlayerModule"
[7414] ModuleScript | "StarterPlayer.PlayerModule.CommonUtils" | Name="CommonUtils"
[7415] ModuleScript | "StarterPlayer.PlayerModule.CommonUtils.EventBus" | Name="EventBus"
[7416] ModuleScript | "StarterPlayer.PlayerModule.CommonUtils.PlayerModuleEventBus" | Name="PlayerModuleEventBus"
[7417] ModuleScript | "StarterPlayer.PlayerModule.CommonUtils.CameraWrapper" | Name="CameraWrapper"
[7418] ModuleScript | "StarterPlayer.PlayerModule.CommonUtils.VRFirstPersonState" | Name="VRFirstPersonState"
[7419] ModuleScript | "StarterPlayer.PlayerModule.CommonUtils.CameraWrapper.spec" | Name="CameraWrapper.spec"
[7420] ModuleScript | "StarterPlayer.PlayerModule.CommonUtils.CharacterUtil" | Name="CharacterUtil"
[7421] ModuleScript | "StarterPlayer.PlayerModule.CommonUtils.FlagUtil" | Name="FlagUtil"
[7422] ModuleScript | "StarterPlayer.PlayerModule.CommonUtils.ConnectionUtil" | Name="ConnectionUtil"
[7423] ModuleScript | "StarterPlayer.PlayerModule.CommonUtils.ConnectionUtil.spec" | Name="ConnectionUtil.spec"
[7424] Script | "StarterPlayer.PlayerModule.InputSetup" | Name="InputSetup"
[7425] ModuleScript | "StarterPlayer.PlayerModule.Types" | Name="Types"
[7426] ModuleScript | "StarterPlayer.PlayerModule.Types.ControlModuleData" | Name="ControlModuleData"
[7427] ModuleScript | "StarterPlayer.PlayerModule.Types.PlayerModuleInternalData" | Name="PlayerModuleInternalData"
[7428] ModuleScript | "StarterPlayer.PlayerModule.ServerAuthority" | Name="ServerAuthority"
[7429] Script | "StarterPlayer.PlayerModule.ServerAuthority.ServerAuthorityClient" | Name="ServerAuthorityClient"
[7430] Script | "StarterPlayer.PlayerModule.ServerAuthority.ServerAuthorityServer" | Name="ServerAuthorityServer"
[7431] ModuleScript | "StarterPlayer.PlayerModule.CameraModule" | Name="CameraModule"
[7432] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.VRCameraTeleportDetector.spec" | Name="VRCameraTeleportDetector.spec"
[7433] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.LegacyCamera" | Name="LegacyCamera"
[7434] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.CameraUI" | Name="CameraUI"
[7435] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.CameraInput" | Name="CameraInput"
[7436] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.OrbitalCamera" | Name="OrbitalCamera"
[7437] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.MouseLockController" | Name="MouseLockController"
[7438] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.CameraUtils" | Name="CameraUtils"
[7439] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.VehicleCamera" | Name="VehicleCamera"
[7440] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.VehicleCamera.VehicleCameraConfig" | Name="VehicleCameraConfig"
[7441] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.VehicleCamera.VehicleCameraCore" | Name="VehicleCameraCore"
[7442] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.Poppercam" | Name="Poppercam"
[7443] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.BaseOcclusion" | Name="BaseOcclusion"
[7444] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.VRVehicleCamera" | Name="VRVehicleCamera"
[7445] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.Invisicam" | Name="Invisicam"
[7446] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.BaseCamera" | Name="BaseCamera"
[7447] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.ZoomController" | Name="ZoomController"
[7448] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.ZoomController.Popper" | Name="Popper"
[7449] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.VRCameraTeleportDetector" | Name="VRCameraTeleportDetector"
[7450] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.ClassicCamera" | Name="ClassicCamera"
[7451] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.VRBaseCamera" | Name="VRBaseCamera"
[7452] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.VRCamera" | Name="VRCamera"
[7453] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.CameraToggleStateController" | Name="CameraToggleStateController"
[7454] ModuleScript | "StarterPlayer.PlayerModule.CameraModule.TransparencyController" | Name="TransparencyController"
[7455] ModuleScript | "StarterPlayer.PlayerModule.ControlModule" | Name="ControlModule"
[7456] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.TouchJump" | Name="TouchJump"
[7457] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.ClassicThumbstick" | Name="ClassicThumbstick"
[7458] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.TouchAbilities" | Name="TouchAbilities"
[7459] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.DynamicThumbstick" | Name="DynamicThumbstick"
[7460] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.VehicleController" | Name="VehicleController"
[7461] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.AvatarAbilitiesInterface" | Name="AvatarAbilitiesInterface"
[7462] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.ActionController" | Name="ActionController"
[7463] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.InputReplication" | Name="InputReplication"
[7464] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.ClickToMoveController" | Name="ClickToMoveController"
[7465] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.InputSlots" | Name="InputSlots"
[7466] ModuleScript | "StarterPlayer.PlayerModule.ControlModule.ClickToMoveDisplay" | Name="ClickToMoveDisplay"
[7467] Script | "StarterPlayer.PlayerModule.PlayerScriptsLoader" | Name="PlayerScriptsLoader"
[7468] ModuleScript | "StarterPlayer.PlayerModule.InputSampler" | Name="InputSampler"
[7469] ModuleScript | "StarterPlayer.PlayerModule.PlayerModuleInternal" | Name="PlayerModuleInternal"
[7470] Folder | "StarterPlayer.PlayerModule.InputContexts" | Name="InputContexts"
[7471] InputContext | "StarterPlayer.PlayerModule.InputContexts.CameraContext" | Name="CameraContext"
[7472] InputAction | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraZoomAction" | Name="CameraZoomAction"
[7473] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraZoomAction.KeyboardBinding" | Name="KeyboardBinding"
[7474] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraZoomAction.MouseBinding" | Name="MouseBinding"
[7475] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraZoomAction.TrackpadBinding" | Name="TrackpadBinding"
[7476] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraZoomAction.TouchBinding" | Name="TouchBinding"
[7477] InputAction | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraGamepadZoomAction" | Name="CameraGamepadZoomAction"
[7478] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraGamepadZoomAction.GamepadBinding" | Name="GamepadBinding"
[7479] InputAction | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraAction" | Name="CameraAction"
[7480] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraAction.CameraScriptableBinding" | Name="CameraScriptableBinding"
[7481] InputAction | "StarterPlayer.PlayerModule.InputContexts.CameraContext.MouseLockSwitchAction" | Name="MouseLockSwitchAction"
[7482] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.MouseLockSwitchAction.KeyboardPrimaryBinding" | Name="KeyboardPrimaryBinding"
[7483] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.MouseLockSwitchAction.KeyboardSecondaryBinding" | Name="KeyboardSecondaryBinding"
[7484] InputAction | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraToggleAction" | Name="CameraToggleAction"
[7485] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraToggleAction.MouseBinding" | Name="MouseBinding"
[7486] InputAction | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraGamepadResetAction" | Name="CameraGamepadResetAction"
[7487] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraGamepadResetAction.GamepadBinding" | Name="GamepadBinding"
[7488] InputAction | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraPanActiveAction" | Name="CameraPanActiveAction"
[7489] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraPanActiveAction.TouchBinding" | Name="TouchBinding"
[7490] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraPanActiveAction.MouseBinding" | Name="MouseBinding"
[7491] InputAction | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraRotationAction" | Name="CameraRotationAction"
[7492] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraRotationAction.MicroGamepadBinding" | Name="MicroGamepadBinding"
[7493] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraRotationAction.TouchBinding" | Name="TouchBinding"
[7494] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraRotationAction.TrackpadBinding" | Name="TrackpadBinding"
[7495] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraRotationAction.MouseBinding" | Name="MouseBinding"
[7496] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraRotationAction.GamepadBinding" | Name="GamepadBinding"
[7497] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CameraContext.CameraRotationAction.KeyboardBinding" | Name="KeyboardBinding"
[7498] InputContext | "StarterPlayer.PlayerModule.InputContexts.CharacterContext" | Name="CharacterContext"
[7499] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.JumpAction" | Name="JumpAction"
[7500] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.JumpAction.MicroGamepadBinding" | Name="MicroGamepadBinding"
[7501] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.JumpAction.KeyboardBinding" | Name="KeyboardBinding"
[7502] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.JumpAction.GamepadBinding" | Name="GamepadBinding"
[7503] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.JumpAction.TouchBinding" | Name="TouchBinding"
[7504] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.JumpAction.ClickToMoveScriptableBinding" | Name="ClickToMoveScriptableBinding"
[7505] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction7" | Name="AbilityAction7"
[7506] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction7.KeyboardBinding" | Name="KeyboardBinding"
[7507] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction7.GamepadBinding" | Name="GamepadBinding"
[7508] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction7.TouchBinding" | Name="TouchBinding"
[7509] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction8" | Name="AbilityAction8"
[7510] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction8.KeyboardBinding" | Name="KeyboardBinding"
[7511] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction8.GamepadBinding" | Name="GamepadBinding"
[7512] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction8.TouchBinding" | Name="TouchBinding"
[7513] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.RotationAction" | Name="RotationAction"
[7514] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.RotationAction.RotationScriptableBinding" | Name="RotationScriptableBinding"
[7515] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.MoveAction" | Name="MoveAction"
[7516] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.MoveAction.MicroGamepadBinding" | Name="MicroGamepadBinding"
[7517] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.MoveAction.GamepadBinding" | Name="GamepadBinding"
[7518] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.MoveAction.DynamicThumbstickScriptableBinding" | Name="DynamicThumbstickScriptableBinding"
[7519] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.MoveAction.ClassicThumbstickScriptableBinding" | Name="ClassicThumbstickScriptableBinding"
[7520] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.MoveAction.ClickToMoveScriptableBinding" | Name="ClickToMoveScriptableBinding"
[7521] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.MoveAction.KeyboardSecondaryBinding" | Name="KeyboardSecondaryBinding"
[7522] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.MoveAction.KeyboardPrimaryBinding" | Name="KeyboardPrimaryBinding"
[7523] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.ClickToMovePositionAction" | Name="ClickToMovePositionAction"
[7524] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.ClickToMovePositionAction.TouchBinding" | Name="TouchBinding"
[7525] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.ClickToMovePositionAction.MouseBinding" | Name="MouseBinding"
[7526] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.ClickToMoveAction" | Name="ClickToMoveAction"
[7527] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.ClickToMoveAction.TouchBinding" | Name="TouchBinding"
[7528] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.ClickToMoveAction.MouseBinding" | Name="MouseBinding"
[7529] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction1" | Name="AbilityAction1"
[7530] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction1.MicroGamepadBinding" | Name="MicroGamepadBinding"
[7531] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction1.KeyboardBinding" | Name="KeyboardBinding"
[7532] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction1.GamepadBinding" | Name="GamepadBinding"
[7533] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction1.TouchBinding" | Name="TouchBinding"
[7534] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction2" | Name="AbilityAction2"
[7535] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction2.KeyboardBinding" | Name="KeyboardBinding"
[7536] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction2.TouchBinding" | Name="TouchBinding"
[7537] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction2.GamepadBinding" | Name="GamepadBinding"
[7538] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction3" | Name="AbilityAction3"
[7539] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction3.TouchBinding" | Name="TouchBinding"
[7540] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction3.KeyboardBinding" | Name="KeyboardBinding"
[7541] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction3.GamepadBinding" | Name="GamepadBinding"
[7542] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction6" | Name="AbilityAction6"
[7543] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction6.GamepadBinding" | Name="GamepadBinding"
[7544] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction6.KeyboardBinding" | Name="KeyboardBinding"
[7545] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction6.TouchBinding" | Name="TouchBinding"
[7546] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction5" | Name="AbilityAction5"
[7547] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction5.TouchBinding" | Name="TouchBinding"
[7548] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction5.GamepadBinding" | Name="GamepadBinding"
[7549] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction5.KeyboardBinding" | Name="KeyboardBinding"
[7550] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction4" | Name="AbilityAction4"
[7551] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction4.TouchBinding" | Name="TouchBinding"
[7552] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction4.GamepadBinding" | Name="GamepadBinding"
[7553] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction4.KeyboardBinding" | Name="KeyboardBinding"
[7554] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.OverflowAction3" | Name="OverflowAction3"
[7555] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.OverflowAction3.TouchBinding" | Name="TouchBinding"
[7556] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.OverflowAction2" | Name="OverflowAction2"
[7557] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.OverflowAction2.TouchBinding" | Name="TouchBinding"
[7558] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.OverflowAction1" | Name="OverflowAction1"
[7559] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.OverflowAction1.TouchBinding" | Name="TouchBinding"
[7560] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction11" | Name="AbilityAction11"
[7561] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction11.TouchBinding" | Name="TouchBinding"
[7562] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction11.GamepadBinding" | Name="GamepadBinding"
[7563] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction11.KeyboardBinding" | Name="KeyboardBinding"
[7564] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction10" | Name="AbilityAction10"
[7565] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction10.TouchBinding" | Name="TouchBinding"
[7566] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction10.GamepadBinding" | Name="GamepadBinding"
[7567] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction10.KeyboardBinding" | Name="KeyboardBinding"
[7568] InputAction | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction9" | Name="AbilityAction9"
[7569] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction9.TouchBinding" | Name="TouchBinding"
[7570] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction9.GamepadBinding" | Name="GamepadBinding"
[7571] InputBinding | "StarterPlayer.PlayerModule.InputContexts.CharacterContext.AbilityAction9.KeyboardBinding" | Name="KeyboardBinding"
[7572] InputContext | "StarterPlayer.PlayerModule.InputContexts.TransformerContext" | Name="TransformerContext"
[7573] InputAction | "StarterPlayer.PlayerModule.InputContexts.TransformerContext.ThumbstickAction" | Name="ThumbstickAction"
[7574] InputContext | "StarterPlayer.PlayerModule.InputContexts.VehicleContext" | Name="VehicleContext"
[7575] InputAction | "StarterPlayer.PlayerModule.InputContexts.VehicleContext.ThrottleAction" | Name="ThrottleAction"
[7576] InputBinding | "StarterPlayer.PlayerModule.InputContexts.VehicleContext.ThrottleAction.GamepadBinding" | Name="GamepadBinding"
[7577] InputAction | "StarterPlayer.PlayerModule.InputContexts.VehicleContext.SteerAction" | Name="SteerAction"
[7578] InputBinding | "StarterPlayer.PlayerModule.InputContexts.VehicleContext.SteerAction.KeyboardBinding" | Name="KeyboardBinding"
[7579] StarterPlayerScripts | "StarterPlayer.StarterPlayerScripts" | Name="StarterPlayerScripts"
[7580] LocalScript | "StarterPlayer.StarterPlayerScripts.R1_SkinFX" | Name="R1_SkinFX"
[7581] LocalScript | "StarterPlayer.StarterPlayerScripts.R1_Menu" | Name="R1_Menu"
[7582] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.UI" | Name="UI"
[7583] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Presentation" | Name="Presentation"
[7584] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Art" | Name="Art"
[7585] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.BattlePass" | Name="BattlePass"
[7586] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Intro" | Name="Intro"
[7587] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Store" | Name="Store"
[7588] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Daily" | Name="Daily"
[7589] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Launch" | Name="Launch"
[7590] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Halloween" | Name="Halloween"
[7591] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Pad" | Name="Pad"
[7592] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Rides" | Name="Rides"
[7593] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Market" | Name="Market"
[7594] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Scrap" | Name="Scrap"
[7595] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Hosted" | Name="Hosted"
[7596] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.TouchEditor" | Name="TouchEditor"
[7597] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Tournament" | Name="Tournament"
[7598] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Showcase" | Name="Showcase"
[7599] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Stats" | Name="Stats"
[7600] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Trade" | Name="Trade"
[7601] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.SeasonMenu" | Name="SeasonMenu"
[7602] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Clans" | Name="Clans"
[7603] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Cosmetics" | Name="Cosmetics"
[7604] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.Polish" | Name="Polish"
[7605] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.PS2Play" | Name="PS2Play"
[7606] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.PS2Pass" | Name="PS2Pass"
[7607] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.PS2Boards" | Name="PS2Boards"
[7608] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.PS2Locker" | Name="PS2Locker"
[7609] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.PS2Locker.ChallengeLocker" | Name="ChallengeLocker"
[7610] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.PS2Clan" | Name="PS2Clan"
[7611] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.PS2Daily" | Name="PS2Daily"
[7612] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_Menu.BundleSpin" | Name="BundleSpin"
[7613] LocalScript | "StarterPlayer.StarterPlayerScripts.R1_Audio" | Name="R1_Audio"
[7614] LocalScript | "StarterPlayer.StarterPlayerScripts.R1_MenuSFX" | Name="R1_MenuSFX"
[7615] LocalScript | "StarterPlayer.StarterPlayerScripts.R1_AdminGifts" | Name="R1_AdminGifts"
[7616] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_AdminGifts.Tabs" | Name="Tabs"
[7617] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_AdminGifts.Tournament" | Name="Tournament"
[7618] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_AdminGifts.EventCard" | Name="EventCard"
[7619] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_AdminGifts.TradeSwitch" | Name="TradeSwitch"
[7620] ModuleScript | "StarterPlayer.StarterPlayerScripts.R1_AdminGifts.Modes" | Name="Modes"
[7621] LocalScript | "StarterPlayer.StarterPlayerScripts.R1_LiveEventBanner" | Name="R1_LiveEventBanner"
[7622] LocalScript | "StarterPlayer.StarterPlayerScripts.RbxCharacterSounds" | Name="RbxCharacterSounds"
[7623] ModuleScript | "StarterPlayer.StarterPlayerScripts.RbxCharacterSounds.AtomicBinding" | Name="AtomicBinding"
[7624] StarterCharacterScripts | "StarterPlayer.StarterCharacterScripts" | Name="StarterCharacterScripts"
------------------------------------------------------------
-- SERVICE: Teams
------------------------------------------------------------
[7625] Teams | "Teams" | Name="Teams"

-- END FLAT DUMP
