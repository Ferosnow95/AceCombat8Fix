-- AC8 Ultrawide & FOV v0.11 - settings
return {
    -- Master switch (F8 toggles everything at runtime and restores the game's originals)
    Enabled = true,

    -- ===== Ultrawide (cutscenes, menus, hangar, debriefing) =====
    -- AC8's cameras cap the picture with their own AspectRatioMax (~2.4, the "21:9 max").
    -- 0 = raise it to your screen's aspect ratio (auto-detected). Or set a value, e.g. 3.5656 for 32:9.
    AspectRatioMaxValue = 0,
    -- 0 = auto-detect the screen shape. Set it if detection is wrong, e.g. 3.5556 for 32:9, 2.3889 for 21:9.
    ForceAspectRatio = 0,

    -- ===== Flight FOV =====
    -- Degrees ADDED to the game's own FOV for each view (0 = game default).
    -- Game defaults (16:9-equivalent): third-person 61.9, cockpit 73.7, HUD-only 73.7.
    -- The game widens these for your screen automatically, e.g. on 32:9: 61.9 -> ~100 wide, +10 -> ~111.
    -- Tune in game with PageUp / PageDown (affects the view you're in). AC8 locks the FOV when your
    -- plane spawns, so a change shows from the next spawn (retry / checkpoint / next sortie).
    -- Tuned values are saved to AC8CutsceneUW_fov.txt and override these numbers.
    ThirdPersonFOVOffset = 10,
    CockpitFOVOffset     = 10,
    FirstPersonFOVOffset = 10,   -- HUD-only view
    FOVStep = 2,

    -- ===== Diagnostics =====
    -- Logs view/FOV changes and camera details. Useful for testing; turn off for normal play.
    Diagnostics = false,

    -- Write AC8CutsceneUW.log next to this mod (previous run kept as AC8CutsceneUW.prev.log)
    WriteLogFile = true,

    -- Keys (UE4SS Key names)
    ToggleKey   = "F8",        -- everything on/off (A/B compare)
    DumpKey     = "F7",        -- snapshot to the log
    FOVUpKey    = "PAGE_UP",
    FOVDownKey  = "PAGE_DOWN",
    FOVResetKey = "HOME",
}
