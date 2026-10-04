-- AC8 Ultrawide & FOV v0.16 - settings
return {
    -- Master switch (F8 toggles at runtime and restores the game's original cap and FOV)
    Enabled = true,

    -- ===== Ultrawide (cutscenes, menus, hangar) =====
    -- AC8's cameras cap the picture with their own AspectRatioMax (~2.4, the "21:9 max").
    -- 0 = raise it to your screen's aspect ratio (auto-detected). Or set a value, e.g. 3.5656 for 32:9.
    AspectRatioMaxValue = 0,
    -- 0 = auto-detect the screen shape. Set it if detection is wrong, e.g. 3.5556 for 32:9, 2.3889 for 21:9.
    ForceAspectRatio = 0,

    -- ===== Flight FOV =====
    FlightFOV = true,
    -- Horizontal FOV per view in 16:9-equivalent degrees (the game's own: third-person 61.9, cockpit 73.7,
    -- HUD-only 73.7). The mod widens it for your screen automatically (on 32:9: 80 -> ~119 wide, 90 -> ~127 wide).
    -- 0 = leave that view to the game. A set value replaces the game's dynamic FOV in that view.
    -- Tune live with PageUp / PageDown (current view); values are saved to AC8CutsceneUW_flightfov.txt and
    -- override these numbers. Delete that file to go back to these.
    ThirdPersonFOV = 80,
    CockpitFOV     = 90,
    FirstPersonFOV = 90,    -- HUD-only view
    FOVStep = 2,
    -- This mod steps aside if the AC8CockpitFOV mod is enabled (both would set the FOV every frame).
    -- Set true to run anyway.
    IgnoreOtherFOVMod = false,

    -- Write AC8CutsceneUW.log next to this mod (previous run kept as AC8CutsceneUW.prev.log)
    WriteLogFile = true,

    -- Keys (UE4SS Key names)
    ToggleKey   = "F8",
    DumpKey     = "F7",
    FOVUpKey    = "PAGE_UP",
    FOVDownKey  = "PAGE_DOWN",
    FOVResetKey = "HOME",
}
