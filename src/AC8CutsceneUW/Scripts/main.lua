--[[
    AC8 Ultrawide & FOV  v0.16  (UE4SS Lua, ACE COMBAT 8 / UE 5.4)

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
      * (Cutscene part) Never keep UObject references between frames. Objects die on level transitions, and even
        calling IsValid() on a dead one crashes inside UE4SS. Cameras are patched the moment they're
        created (NotifyOnNewObject) or found fresh with FindAllOf, then forgotten.
      * No per-tick loop. Nothing runs during gameplay except when a camera is created.
      * Never read the camera manager's view-target actor, and never read hooked function parameters
        other than the context object (both crashed this UE4SS build).

    Flight FOV (v0.15, hardened in v0.16)
    ------------------
    AC8 ignores writes to the plane's camera components (it caches their FOV at spawn), but the engine's
    PlayerController:FOV(deg) command locks the FINAL view FOV in PlayerCameraManager, and that wins at any
    time - so it works live, no respawn needed. Which flight view is active (third-person / cockpit /
    HUD-only) is read from AC8's LiveCameraViewComponent. The technique comes from the AC8CockpitFOV mod
    (AC8 Three-View FOV), which proved it in this game; this module is an independent implementation.
    A locked FOV replaces the game's dynamic FOV in that view (value 0 gives it back). Offline only: the FOV
    lock is skipped when the world has a net driver (online).
    Unlike the cutscene part, this part keeps object references between frames (purged every frame), the pattern
    the AC8CockpitFOV mod runs with. v0.16: the lists are rebuilt from fresh FindAllOf scans (no NotifyOnNewObject),
    cleared at every PlayerController:ClientRestart, and the loop stays hands-off for ~180 frames after it - v0.15
    crashed (access violation in the frame loop) 50 ms after a mission start.

    Keys: F8 = toggle, F7 = snapshot, PageUp/PageDown = flight FOV of the current view, Home = reset it.
]]

local cfg = require("config")
local UEHelpers = require("UEHelpers")

------------------------------------------------------------------------
-- logging: own file next to the mod (previous run kept as .prev.log), flushed per line
------------------------------------------------------------------------
local TAG = "[AC8CutsceneUW] "
local logFile, logPath = nil, nil
local modDir = nil
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
            if f then logFile, logPath, modDir = f, path, d; break end
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
-- Flight FOV: PlayerController:FOV(deg) per view (see header)
------------------------------------------------------------------------
local FOV_MODES = { "ThirdPerson", "Cockpit", "FirstPerson" }
local FOV_BASE  = { ThirdPerson = 61.9, Cockpit = 73.7, FirstPerson = 73.7 }   -- the game's own 16:9 values
local fovValue = {
    ThirdPerson = cfg.ThirdPersonFOV or 0,    -- 16:9-equivalent degrees; 0 = the game's own FOV
    Cockpit     = cfg.CockpitFOV or 0,
    FirstPerson = cfg.FirstPersonFOV or 0,
}
local fovEnabled = cfg.FlightFOV ~= false
local fovMode = nil            -- current view name (plain string), maintained by the frame loop
local fovFailed = false
local fovHold, fovSeedIn = 0, 0   -- frames to stay hands-off after a level start / frames until the next fresh scan
local FOV_HOLD_FRAMES, FOV_RESEED_FRAMES = 180, 60

local function onScreen(fov16)   -- 16:9-equivalent horizontal FOV -> the same view on this screen (Hor+)
    if not screenAR then return fov16 end
    return math.deg(2 * math.atan(math.tan(math.rad(fov16) / 2) * screenAR / (16 / 9)))
end

local function savedFovPath() return (modDir or "") .. "AC8CutsceneUW_flightfov.txt" end
local function loadSavedFov()
    local f = io.open(savedFovPath(), "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*(%w+)%s*=%s*(-?[%d%.]+)")
        if k and fovValue[k] ~= nil then fovValue[k] = tonumber(v) end
    end
    f:close()
    log("Loaded saved flight FOV from %s: third-person %g, cockpit %g, HUD-only %g (0 = game default)",
        savedFovPath(), fovValue.ThirdPerson, fovValue.Cockpit, fovValue.FirstPerson)
end
local function saveFov()
    local f = io.open(savedFovPath(), "w")
    if not f then return end
    f:write("-- Saved by AC8CutsceneUW (PageUp/PageDown in game). 16:9-equivalent degrees per view; 0 = game default.\n")
    for _, k in ipairs(FOV_MODES) do f:write(string.format("%s=%g\n", k, fovValue[k])) end
    f:close()
end

local fovViews, fovManagers = {}, {}     -- live objects; touched only from the game-thread frame loop below
-- Rebuild a list from a FRESH FindAllOf scan, keeping the entry (and its lock state) of objects we already know.
-- Objects are no longer taken from NotifyOnNewObject (they fire while the object is still being built) and
-- v0.15 crashed at a mission start (access violation, uncatchable by pcall); this is the suspected cause.
local function reseedList(list, class)
    local fresh = {}
    for _, object in ipairs(FindAllOf(class) or {}) do
        if object:IsValid() then
            local keep
            for _, entry in ipairs(list) do
                if entry.object == object then keep = entry; break end
            end
            fresh[#fresh + 1] = keep or { object = object }
        end
    end
    for i = #list, 1, -1 do list[i] = nil end
    for i, entry in ipairs(fresh) do list[i] = entry end
end

-- a new level / respawn is starting: forget every stored object and stay hands-off for a while
local function fovLevelStart()
    for _, list in ipairs({ fovViews, fovManagers }) do
        for i = #list, 1, -1 do list[i] = nil end
    end
    fovHold, fovSeedIn, fovMode = FOV_HOLD_FRAMES, 0, nil
end

local function camActive(cam)
    return cam:IsValid() and cam.bIsActive == true
end

-- which flight view does this player's current view target belong to? nil = cutscene / menu / online
local function currentMode(manager)
    local world, controller = manager:GetWorld(), manager.PCOwner
    if not world:IsValid() or world.NetDriver:IsValid() or not controller:IsValid() then return nil end
    local target = controller:GetViewTarget()
    for _, entry in ipairs(fovViews) do
        local view = entry.object
        if view:IsValid() and view:GetOwner() == target then
            if camActive(view.CachedCockpitCamera) then return "Cockpit" end
            if camActive(view.CachedFirstPersonCamera) then return "FirstPerson" end
            if camActive(view.CachedThirdPersonCamera) then return "ThirdPerson" end
        end
    end
    return nil
end

local function fovFrame()
    for _, list in ipairs({ fovViews, fovManagers }) do
        for i = #list, 1, -1 do
            if not list[i].object:IsValid() then table.remove(list, i) end
        end
    end
    for _, entry in ipairs(fovManagers) do
        local manager = entry.object
        if manager.PCOwner:IsValid() then
            local mode = currentMode(manager)
            local want16 = (enabled and fovEnabled and mode) and fovValue[mode] or 0
            local desired = (want16 > 0 and screenAR) and onScreen(want16) or 0
            local need = false
            if desired > 0 then
                need = entry.applied == nil or math.abs(desired - entry.applied) > 0.001
                    or math.abs(manager:GetFOVAngle() - desired) > 0.05          -- the game replaced the lock
            elseif entry.applied ~= nil and entry.applied > 0 then
                need = true                                                       -- hand the FOV back to the game
            end
            if need then manager.PCOwner:FOV(desired) end
            if entry.mode ~= mode or entry.applied ~= desired then
                if desired > 0 then
                    log("FOV  view %-11s locked to %.1f wide on screen (%.1f in 16:9 terms)", mode or "-", desired, want16)
                else
                    log("FOV  view %-11s game default", mode or "other")
                end
            end
            entry.mode, entry.applied = mode, desired
            fovMode = mode
        end
    end
end

-- Another mod that calls PlayerController:FOV every frame (AC8CockpitFOV) would fight this one, so step aside
-- when it is enabled (its Mods\\AC8CockpitFOV\\enabled.txt exists next to this mod's folder).
local function otherFovModEnabled()
    if cfg.IgnoreOtherFOVMod == true or not modDir then return false end
    local sep = modDir:find("\\", 1, true) and "\\" or "/"
    local f = io.open(modDir .. ".." .. sep .. "AC8CockpitFOV" .. sep .. "enabled.txt", "r")
    if f then f:close(); return true end
    return false
end

local function startFlightFov()
    if otherFovModEnabled() then
        fovEnabled = false
        log("Flight FOV is OFF here: the AC8CockpitFOV mod is enabled and already controls it. To use this mod's FOV instead, disable that mod (rename its enabled.txt).")
        return
    end
    loadSavedFov()
    log("Flight FOV loop: fresh scan every %d frames, hands-off for %d frames after each level start", FOV_RESEED_FRAMES, FOV_HOLD_FRAMES)
    local function step()
        if fovHold > 0 then fovHold = fovHold - 1; return end
        if fovSeedIn <= 0 then
            reseedList(fovViews, "LiveCameraViewComponent")
            reseedList(fovManagers, "LivePlayerCameraManager")
            fovSeedIn = FOV_RESEED_FRAMES
        else
            fovSeedIn = fovSeedIn - 1
        end
        fovFrame()
    end
    local function tick()
        if fovFailed then return end
        local ok, err = pcall(step)
        if not ok then
            fovFailed = true
            for _, entry in ipairs(fovManagers) do      -- never leave the game locked
                pcall(function()
                    if entry.object:IsValid() and entry.object.PCOwner:IsValid() and (entry.applied or 0) > 0 then
                        entry.object.PCOwner:FOV(0)
                    end
                end)
            end
            log("FOV STOPPED (the cutscene fix keeps running): %s", tostring(err))
        end
    end
    if LoopInGameThreadAfterFrames then
        LoopInGameThreadAfterFrames(1, tick)
    else
        LoopAsync(16, function() ExecuteInGameThread(tick); return false end)
    end
end

local function bumpFov(delta, reset)
    if not fovEnabled then log("FOV keys: flight FOV is off (see above)"); return end
    local mode = fovMode
    if not mode then log("FOV keys: not in a flight view right now"); return end
    local cur = fovValue[mode]
    local new
    if reset then new = 0
    else
        new = (cur > 0 and cur or FOV_BASE[mode]) + delta
        new = math.max(30, math.min(120, new))
    end
    fovValue[mode] = new
    saveFov()
    if new > 0 then
        log("FOV  %-11s -> %g (16:9 terms) = %.1f wide on screen (saved)", mode, new, onScreen(new))
    else
        log("FOV  %-11s -> game default (saved)", mode)
    end
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
    if fovEnabled then fovLevelStart() end
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

RegisterKeyBind(Key[cfg.FOVUpKey or "PAGE_UP"], function()
    ExecuteInGameThread(function() try(bumpFov, cfg.FOVStep or 2) end)
end)
RegisterKeyBind(Key[cfg.FOVDownKey or "PAGE_DOWN"], function()
    ExecuteInGameThread(function() try(bumpFov, -(cfg.FOVStep or 2)) end)
end)
RegisterKeyBind(Key[cfg.FOVResetKey or "HOME"], function()
    ExecuteInGameThread(function() try(bumpFov, 0, true) end)
end)

RegisterKeyBind(Key[cfg.DumpKey or "F7"], function()
    ExecuteInGameThread(function() try(snapshot, "F7") end)
end)

try(startFlightFov)
log("v0.16 loaded. %s = toggle, %s = snapshot, PageUp/PageDown = flight FOV of the current view, Home = reset", cfg.ToggleKey or "F8", cfg.DumpKey or "F7")
