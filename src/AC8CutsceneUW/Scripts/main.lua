--[[
    AC8 Ultrawide & FOV  v0.11  (UE4SS Lua, ACE COMBAT 8 / UE 5.4)

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

    FOV (v0.10): the flight cameras are AC8's own components on the player plane:
      * LiveThirdPersonCameraComponent  (ThirdPersonCamera, base 61.9)
      * LiveCockpitCameraComponent      (CockpitCamera,     base 73.7)
      * LiveFirstPersonCameraComponent  (FirstPersonCamera / HUD-only, base 73.7)
    Their FieldOfView is a 16:9-equivalent horizontal FOV; the game converts it Hor+ to the screen
    (61.9 -> 100.4 on 32:9). The plane copies FieldOfView from its blueprint TEMPLATE when it spawns
    and caches it - later changes to the live camera are ignored (v0.10 test). So the mod changes the
    templates only (once, from their remembered original - no compounding) and every plane that
    spawns picks it up. Templates are found again by path name (StaticFindObject), never by stored
    reference. PageUp/PageDown change the offset for the view you're in; it applies from the next
    spawn (retry / checkpoint / next sortie) and is saved to AC8CutsceneUW_fov.txt.

    Keys: F8 = toggle everything (restores originals), F7 = snapshot, PageUp/PageDown = FOV +/- for the
    current view, Home = reset that view's FOV.
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
    { short = "LiveCameraComponent",               path = "/Script/Live.LiveCameraComponent" },   -- gameplay cams
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
    if cur <= 0 then return false end                  -- 0 = no cap (gameplay cameras): leave it
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
-- FOV for the flight cameras (values only; objects come fresh from Notify/FindAllOf)
------------------------------------------------------------------------
local FOV_VIEWS = {
    { key = "ThirdPerson", short = "LiveThirdPersonCameraComponent", path = "/Script/Live.LiveThirdPersonCameraComponent" },
    { key = "Cockpit",     short = "LiveCockpitCameraComponent",     path = "/Script/Live.LiveCockpitCameraComponent" },
    { key = "FirstPerson", short = "LiveFirstPersonCameraComponent", path = "/Script/Live.LiveFirstPersonCameraComponent" },
}
local fovOffset = {
    ThirdPerson = cfg.ThirdPersonFOVOffset or 0,
    Cockpit     = cfg.CockpitFOVOffset or 0,
    FirstPerson = cfg.FirstPersonFOVOffset or 0,
}
local fovLogged = {}
local fovTemplates = {}    -- [object path string] = { key = view key, orig = original FOV }  (strings/numbers only)

local function savedFovPath() return (modDir or "") .. "AC8CutsceneUW_fov.txt" end
local function loadSavedFov()
    local f = io.open(savedFovPath(), "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*(%w+)%s*=%s*(-?[%d%.]+)")
        if k and fovOffset[k] ~= nil then fovOffset[k] = tonumber(v) end
    end
    f:close()
    log("Loaded tuned FOV offsets from %s: third-person %+.0f, cockpit %+.0f, HUD-only %+.0f",
        savedFovPath(), fovOffset.ThirdPerson, fovOffset.Cockpit, fovOffset.FirstPerson)
end
local function saveFov()
    local f = io.open(savedFovPath(), "w")
    if not f then return end
    f:write("-- Saved by AC8CutsceneUW (PageUp/PageDown in game). Degrees added to the game's FOV per view.\n")
    for _, v in ipairs(FOV_VIEWS) do f:write(string.format("%s=%g\n", v.key, fovOffset[v.key])) end
    f:close()
end

local function onScreen(fov)   -- what a 16:9-equivalent FOV becomes on this screen (the game is Hor+)
    if not screenAR then return fov end
    return math.deg(2 * math.atan(math.tan(math.rad(fov) / 2) * screenAR / (16 / 9)))
end

local function objPath(o)
    local full = try(function() return o:GetFullName() end)
    return full and full:match("^%S+%s+(.+)$") or nil
end
-- live cameras sit in a level; templates live in the blueprint (…_GEN_VARIABLE or Default__BP_…)
local function isTemplatePath(path)
    if path:find("PersistentLevel", 1, true) then return false end      -- a spawned plane's camera
    if path:find("Default__Live", 1, true) then return false end        -- native class default: not used by planes
    return true
end

local function fovWanted(t, restore)
    if restore or not enabled then return t.orig end
    return math.max(20, math.min(150, t.orig + (fovOffset[t.key] or 0)))
end

local function setTemplate(o, path, t, restore)
    local cur = try(function() return o.FieldOfView end)
    if type(cur) ~= "number" then return end
    local want = fovWanted(t, restore)
    if math.abs(cur - want) < 0.01 then return end
    o.FieldOfView = want
    local k = path .. string.format("%.1f", want)
    if not fovLogged[k] then
        fovLogged[k] = true
        log("FOV  %-12s %.1f -> %.1f  (on your screen %.1f -> %.1f wide)  template %s",
            t.key, t.orig, want, onScreen(t.orig), onScreen(want), path:match("([^/]+)$") or path)
    end
end

-- called with a fresh object from NotifyOnNewObject
local function onFovCamera(o, view)
    local path = objPath(o)
    if not path or not isTemplatePath(path) then return end
    local t = fovTemplates[path]
    if not t then
        local cur = try(function() return o.FieldOfView end)
        if type(cur) ~= "number" then return end
        t = { key = view.key, orig = cur }
        fovTemplates[path] = t
    end
    setTemplate(o, path, t, false)
end

-- re-apply to every known template, found again by path (no stored references)
local function reapplyTemplates(restore, onlyKey)
    local n = 0
    for path, t in pairs(fovTemplates) do
        if not onlyKey or t.key == onlyKey then
            local o = try(StaticFindObject, path)
            if o and try(function() return o:IsValid() end) then
                setTemplate(o, path, t, restore)
                n = n + 1
            end
        end
    end
    return n
end

-- which view is the player in right now? (fresh lookup; bIsActive is a plain bool)
local function activeView()
    for _, v in ipairs(FOV_VIEWS) do
        local list = try(FindAllOf, v.short) or {}
        for i = 1, #list do
            if try(function() return list[i].bIsActive end) == true then return v end
        end
    end
    return nil
end

local function bumpFov(delta, reset)
    local v = activeView()
    if not v then log("FOV keys: no flight camera active right now"); return end
    fovOffset[v.key] = reset and 0 or math.max(-40, math.min(60, fovOffset[v.key] + delta))
    local n = reapplyTemplates(false, v.key)
    saveFov()
    local base = nil
    for _, t in pairs(fovTemplates) do if t.key == v.key then base = t.orig end end
    log("FOV  %-12s offset %+.0f (saved) -> %s; applies from your next spawn (retry / checkpoint / next sortie) [%d template(s)]",
        v.key, fovOffset[v.key], base and string.format("%.1f wide on screen", onScreen(base + fovOffset[v.key])) or "?", n)
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

-- 1b) flight cameras: FOV on creation
loadSavedFov()
for _, v in ipairs(FOV_VIEWS) do
    local okN, errN = pcall(NotifyOnNewObject, v.path, function(comp)
        try(onFovCamera, comp, v)
    end)
    log("Watching %-58s %s", v.path, okN and "ok" or ("FAILED: " .. tostring(errN)))
end

-- 2) new level / player restart: learn the screen shape, then ONE fresh sweep per burst of restarts.
--    (v0.8 swept on every restart: 5-19 ms each, up to 3 at once during a load. Cameras created after
--    load are already patched by (1), so a single delayed pass is enough insurance.)
local restartToken = 0
local discoveryPending = nil   -- forward: set below when FOV discovery is on
local ok, err = pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function(Context)
    local pc = try(function() return Context:get() end)
    if pc then detectAspect(pc) end
    restartToken = restartToken + 1
    local mine = restartToken
    pcall(ExecuteWithDelay, 2000, function()
        ExecuteInGameThread(function()
            if mine ~= restartToken then return end      -- a newer restart is pending; let it sweep
            if enabled then sweep(false, "after restart") end
            if discoveryPending then discoveryPending("level start") end

        end)
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

------------------------------------------------------------------------
-- FOV discovery (temporary, diagnostics only). Fresh lookups, nothing stored but plain values.
------------------------------------------------------------------------
local FOV_WORDS = { "fov", "fieldofview", "angle", "zoom", "focal", "lens", "view", "cockpit", "thirdperson", "distance" }
local function interesting(name)
    local l = name:lower()
    for _, w in ipairs(FOV_WORDS) do if l:find(w, 1, true) then return true end end
    return false
end
local function isGameClassPath(full)
    return full:find("/Script/Live", 1, true) or full:find("/Game/", 1, true)
end

local reflected = {}   -- class full name -> list of interesting property names (strings only)
local function reflectGame(obj)
    local found = {}
    local cls = try(function() return obj:GetClass() end)
    local depth = 0
    while cls and depth < 8 do
        local full = try(function() return cls:GetFullName() end) or "?"
        if not isGameClassPath(full) then break end
        if reflected[full] == nil then
            local props, funcs, picks = {}, {}, {}
            try(function()
                cls:ForEachProperty(function(prop)
                    local n = try(function() return prop:GetFName():ToString() end) or "?"
                    local t = try(function() return prop:GetClass():GetFName():ToString() end) or "?"
                    props[#props + 1] = n .. ":" .. t
                    -- only plain scalars are ever read back (object/struct reads were crash-prone)
                    local scalar = t == "FloatProperty" or t == "DoubleProperty" or t == "IntProperty"
                                   or t == "BoolProperty" or t == "ByteProperty"
                    if scalar and interesting(n) then picks[#picks + 1] = n end
                end)
            end)
            try(function()
                cls:ForEachFunction(function(fn)
                    funcs[#funcs + 1] = try(function() return fn:GetFName():ToString() end) or "?"
                end)
            end)
            log("  CLASS %s", full)
            log("     props(%d): %s", #props, table.concat(props, ", "))
            if #funcs > 0 then log("     funcs(%d): %s", #funcs, table.concat(funcs, ", ")) end
            reflected[full] = picks
        end
        for _, n in ipairs(reflected[full]) do found[#found + 1] = n end
        cls = try(function() return cls:GetSuperStruct() end)
        depth = depth + 1
    end
    return found
end

local function fmtVal(v)
    if type(v) == "number" then return string.format("%.3f", v) end
    if type(v) == "boolean" then return tostring(v) end
    return nil   -- structs / objects: skipped (reading them is where UE4SS gets fragile)
end

local function renderedView()
    local pc = try(UEHelpers.GetPlayerController)
    local pov = pc and try(function() return pc.PlayerCameraManager.CameraCachePrivate.POV end)
    if not pov then return nil end
    return try(function() return pov.FOV end), try(function() return pov.AspectRatio end),
           try(function() return pov.bConstrainAspectRatio end)
end

local discoveredFov = {}   -- rendered FOV values (rounded) already examined
local function discover(why)
    local t0 = os.clock()
    local fov, ar, con = renderedView()
    log("================ FOV DISCOVERY (%s) ================", why)
    log("Rendered view: FOV %s  AR %s  constrained=%s", fov and string.format("%.2f", fov) or "?",
        ar and string.format("%.4f", ar) or "?", tostring(con))
    for _, base in ipairs({ "CameraComponent", "SpringArmComponent", "CameraModifier" }) do
        local list = try(FindAllOf, base) or {}
        local byClass, order = {}, {}
        for i = 1, #list do
            local o = list[i]
            local cn = className(o)
            local g = byClass[cn]
            if not g then g = { n = 0, active = 0, fovs = {}, samples = {}, first = o }; byClass[cn] = g; order[#order + 1] = cn end
            g.n = g.n + 1
            local act = try(function() return o.bIsActive end)
            if act == true then g.active = g.active + 1 end
            if base == "CameraComponent" then
                local f = try(function() return o.FieldOfView end)
                if type(f) == "number" then g.fovs[string.format("%.1f", f)] = true end
            end
            if #g.samples < 3 and (act == true or base ~= "CameraComponent") then
                g.samples[#g.samples + 1] = o
            end
        end
        log("[%s] %d objects, %d classes", base, #list, #order)
        for _, cn in ipairs(order) do
            local g = byClass[cn]
            local fl = {}
            for k in pairs(g.fovs) do fl[#fl + 1] = k end
            table.sort(fl)
            log("  %-44s x%-3d active %-3d %s", cn, g.n, g.active, #fl > 0 and ("FOV: " .. table.concat(fl, " ")) or "")
            local picks = reflectGame(g.first)
            local show = (#g.samples > 0) and g.samples or { g.first }
            for _, o in ipairs(show) do
                local vals = {}
                for _, n in ipairs(picks) do
                    local v = fmtVal(try(function() return o[n] end))
                    if v then vals[#vals + 1] = n .. "=" .. v end
                end
                local nm = try(function() return o:GetFullName() end) or "?"
                log("     %s%s", nm:sub(-110), #vals > 0 and ("  | " .. table.concat(vals, " ")) or "")
            end
        end
    end
    log("============ (discovery took %.0f ms) ============", (os.clock() - t0) * 1000)
end

if cfg.Diagnostics == true or cfg.FovDiscovery == true then
    discoveryPending = function(why) try(discover, why) end
    -- watch the rendered FOV every 2 s (fresh lookup each time); when it changes, the player
    -- switched views (third-person / cockpit / HUD) -> log it and run a discovery pass
    local lastFov = nil
    LoopAsync(2000, function()
        ExecuteInGameThread(function()
            local fov, ar, con = renderedView()
            if type(fov) ~= "number" then return end
            if lastFov == nil or math.abs(fov - lastFov) > 0.5 then
                log("View FOV %s -> %.2f  (AR %.4f, constrained=%s)", lastFov and string.format("%.2f", lastFov) or "?",
                    fov, ar or -1, tostring(con))
                lastFov = fov
                -- gameplay views only (cutscenes are constrained); once per distinct FOV value
                local key = string.format("%.0f", fov)
                if con ~= true and not discoveredFov[key] then
                    discoveredFov[key] = true
                    try(discover, "view changed to FOV " .. key)
                end
            end
        end)
        return false
    end)
    log("Diagnostics ON (view/FOV watcher + discovery) - turn off for normal play")
end

RegisterKeyBind(Key[cfg.ToggleKey or "F8"], function()
    ExecuteInGameThread(function()
        enabled = not enabled
        log("Fix %s", enabled and "ENABLED" or "DISABLED")
        sweep(not enabled, "toggle")
        local n = reapplyTemplates(not enabled)
        log("FOV templates %s (%d) - takes effect from your next spawn", enabled and "re-applied" or "restored", n)
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
    ExecuteInGameThread(function() try(snapshot, "F7"); try(discover, "F7") end)
end)

log("v0.11 loaded. F8 = toggle, F7 = snapshot, PageUp/PageDown = FOV of current view (next spawn), Home = reset it")
