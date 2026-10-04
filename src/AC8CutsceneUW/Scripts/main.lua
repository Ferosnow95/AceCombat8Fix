--[[
    AC8 Cutscene Ultrawide  v0.8  (UE4SS Lua, ACE COMBAT 8 / UE 5.4)

    What it does
    ------------
    AC8's own camera classes cap the picture with an AspectRatioMax property (~2.4, the "21:9 max"):
      * LiveCinematicsCineCameraComponent  - real-time cutscenes
      * LiveCineCameraComponent            - menus / hangar
    The game rebuilds the camera from that cap every frame, so the only change that sticks is the cap
    itself. This mod raises AspectRatioMax to your screen's aspect ratio and the game builds the
    full-width (Hor+) view on its own.

    Stability rules (learned the hard way in v0.4-v0.7)
    --------------------------------------------------
      * Never keep UObject references between frames. Objects die on level transitions, and even
        calling IsValid() on a dead one crashes inside UE4SS. Cameras are patched the moment they're
        created (NotifyOnNewObject) or found fresh with FindAllOf, then forgotten.
      * No per-tick loop. Nothing runs during gameplay except when a camera is created.
      * Never read the camera manager's view-target actor, and never read hooked function parameters
        other than the context object (both crashed this UE4SS build).

    Keys: F8 = toggle (restores the original cap), F7 = diagnostic snapshot to the log.
]]

local cfg = require("config")
local UEHelpers = require("UEHelpers")

------------------------------------------------------------------------
-- logging: own file next to the mod (previous run kept as .prev.log), flushed per line
------------------------------------------------------------------------
local TAG = "[AC8CutsceneUW] "
local logFile, logPath = nil, nil
do
    local src = debug and debug.getinfo and debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", "")
    local sep = src:find("\\", 1, true) and "\\" or "/"
    local dir = src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]+$")
    local candidates = {}
    if dir then candidates[#candidates + 1] = dir .. sep end
    candidates[#candidates + 1] = "ue4ss\\Mods\\AC8CutsceneUW\\"
    candidates[#candidates + 1] = "Mods\\AC8CutsceneUW\\"
    candidates[#candidates + 1] = ""
    if cfg.WriteLogFile ~= false then
        for _, d in ipairs(candidates) do
            local path, prev = d .. "AC8CutsceneUW.log", d .. "AC8CutsceneUW.prev.log"
            local old = io.open(path, "r")
            if old then old:close(); os.remove(prev); os.rename(path, prev) end
            local f = io.open(path, "w")
            if f then logFile, logPath = f, path; break end
        end
    end
end

local function log(fmt, ...)
    local msg = string.format(fmt, ...)
    print(TAG .. msg .. "\n")
    if logFile then
        logFile:write(os.date("[%H:%M:%S] "), msg, "\n")
        logFile:flush()
    end
end

local seenErr, errCount = {}, 0
local function try(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    local m = tostring(a)
    if not seenErr[m] and errCount < 40 then
        seenErr[m] = true; errCount = errCount + 1
        log("error: %s", m)
    end
    return nil
end

local function className(o)
    return try(function() return o:GetClass():GetFName():ToString() end) or "?"
end

------------------------------------------------------------------------
-- state (plain values only - no UObject references are ever stored)
------------------------------------------------------------------------
local enabled = cfg.Enabled ~= false
local screenAR = nil                 -- detected viewport aspect ratio
local origByClass = {}               -- class name -> original AspectRatioMax (for F8 restore)
local loggedPatch = {}               -- class name .. original value -> logged once
local patchedTotal = 0

local CAMERA_CLASSES = {
    { short = "LiveCinematicsCineCameraComponent", path = "/Script/LiveCinematics.LiveCinematicsCineCameraComponent" },
    { short = "LiveCineCameraComponent",           path = "/Script/Live.LiveCineCameraComponent" },
}

local function targetValue()
    if cfg.AspectRatioMaxValue and cfg.AspectRatioMaxValue > 0 then return cfg.AspectRatioMaxValue end
    if cfg.ForceAspectRatio and cfg.ForceAspectRatio > 0 then return cfg.ForceAspectRatio + 0.01 end
    if screenAR then return screenAR + 0.01 end
    return nil
end

-- comp must be fresh: handed to us by NotifyOnNewObject or FindAllOf in this same call
local function applyTo(comp, restore)
    local cur = try(function() return comp.AspectRatioMax end)
    if type(cur) ~= "number" then return false end
    local cn = className(comp)
    if restore then
        local o = origByClass[cn]
        if o and math.abs(cur - o) > 0.0001 then comp.AspectRatioMax = o end
        return true
    end
    local want = targetValue()
    if not want or cur >= want - 0.0001 then return false end
    if origByClass[cn] == nil then origByClass[cn] = cur end
    comp.AspectRatioMax = want
    patchedTotal = patchedTotal + 1
    local key = cn .. string.format("%.4f", cur)
    if not loggedPatch[key] then
        loggedPatch[key] = true
        log("AspectRatioMax  %-36s %.4f -> %.4f", cn, cur, want)
    end
    return true
end

-- One-off fresh search; nothing is kept afterwards
local function sweep(restore, why)
    local t0 = os.clock()
    local counts = {}
    for _, c in ipairs(CAMERA_CLASSES) do
        local n = 0
        local list = try(FindAllOf, c.short) or {}
        for i = 1, #list do
            if try(applyTo, list[i], restore) then n = n + 1 end
        end
        counts[#counts + 1] = string.format("%s=%d/%d", c.short, n, #list)
    end
    log("Sweep (%s, %s): %s  [%.0f ms]", why, restore and "restore" or "apply",
        table.concat(counts, " "), (os.clock() - t0) * 1000)
end

------------------------------------------------------------------------
-- screen aspect ratio (read from a player controller we're handed, never cached)
------------------------------------------------------------------------
local function detectAspect(pc)
    if cfg.ForceAspectRatio and cfg.ForceAspectRatio > 0 then
        screenAR = cfg.ForceAspectRatio
        return true
    end
    local ar = try(function()
        local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local s = wll:GetViewportSize(pc)
        if s and s.Y and s.Y > 0 then return s.X / s.Y end
    end)
    if not (ar and ar > 0.5) then
        ar = try(function()
            local eng = FindFirstOf("GameEngine")
            local r = eng.GameUserSettings:GetScreenResolution()
            if r and r.Y and r.Y > 0 then return r.X / r.Y end
        end)
    end
    if ar and ar > 0.5 then
        if not screenAR or math.abs(ar - screenAR) > 0.01 then log("Screen aspect ratio: %.4f", ar) end
        screenAR = ar
        return true
    end
    return false
end

------------------------------------------------------------------------
-- diagnostics (F7): fresh lookups only
------------------------------------------------------------------------
local function snapshot(why)
    log("================ SNAPSHOT (%s) ================", why)
    log("Fix %s | screen AR %s | target AspectRatioMax %s | patched so far %d",
        enabled and "ON" or "OFF", screenAR and string.format("%.4f", screenAR) or "?",
        targetValue() and string.format("%.4f", targetValue()) or "?", patchedTotal)
    for _, c in ipairs(CAMERA_CLASSES) do
        local hist = {}
        local list = try(FindAllOf, c.short) or {}
        for i = 1, #list do
            local v = try(function() return list[i].AspectRatioMax end)
            local k = v and string.format("%.3f", v) or "?"
            hist[k] = (hist[k] or 0) + 1
        end
        local parts = {}
        for k, n in pairs(hist) do parts[#parts + 1] = k .. " x" .. n end
        table.sort(parts)
        log("  %-36s %d cameras, AspectRatioMax: %s", c.short, #list, table.concat(parts, ", "))
    end
    local pc = try(UEHelpers.GetPlayerController)
    local pov = pc and try(function() return pc.PlayerCameraManager.CameraCachePrivate.POV end)
    if pov then
        local ar  = try(function() return pov.AspectRatio end) or -1
        local fov = try(function() return pov.FOV end) or -1
        local con = try(function() return pov.bConstrainAspectRatio end)
        local verdict
        if con ~= true or not screenAR or ar >= screenAR - 0.01 then verdict = "FULL WIDTH"
        else verdict = string.format("BARS (view constrained to %.3f)", ar) end
        log("  Rendered view: AR %.4f FOV %.2f constrained=%s -> %s", ar, fov, tostring(con), verdict)
    else
        log("  Rendered view: not available right now")
    end
    log("==================================================")
end

------------------------------------------------------------------------
-- wiring
------------------------------------------------------------------------
log("Log file: %s", logPath or "(UE4SS.log only)")

-- 1) every AC8 camera, the moment it's created
for _, c in ipairs(CAMERA_CLASSES) do
    local ok, err = pcall(NotifyOnNewObject, c.path, function(comp)
        if enabled then try(applyTo, comp, false) end
    end)
    log("Watching %-58s %s", c.path, ok and "ok" or ("FAILED: " .. tostring(err)))
end

-- 2) new level / player restart: learn the screen shape and patch cameras that already exist
local ok, err = pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function(Context)
    local pc = try(function() return Context:get() end)
    if pc then detectAspect(pc) end
    if enabled then sweep(false, "player restart") end
    -- cameras spawned during the restart itself: one more fresh pass a moment later
    pcall(ExecuteWithDelay, 2000, function()
        ExecuteInGameThread(function() if enabled then sweep(false, "after restart") end end)
    end)
end)
log("Hook PlayerController:ClientRestart %s", ok and "registered" or ("FAILED: " .. tostring(err)))

-- 3) fallback if the hook never fires: look for a player every 5 s until the screen shape is known
LoopAsync(5000, function()
    if screenAR then return true end          -- done, stop looping
    ExecuteInGameThread(function()
        if screenAR then return end
        local pc = try(UEHelpers.GetPlayerController)
        if pc and detectAspect(pc) and enabled then sweep(false, "startup") end
    end)
    return false
end)

RegisterKeyBind(Key[cfg.ToggleKey or "F8"], function()
    ExecuteInGameThread(function()
        enabled = not enabled
        log("Fix %s", enabled and "ENABLED" or "DISABLED")
        sweep(not enabled, "toggle")
    end)
end)

RegisterKeyBind(Key[cfg.DumpKey or "F7"], function()
    ExecuteInGameThread(function() try(snapshot, "F7") end)
end)

log("v0.8 loaded. %s = toggle, %s = snapshot", cfg.ToggleKey or "F8", cfg.DumpKey or "F7")
