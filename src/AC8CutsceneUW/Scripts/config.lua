-- AC8 Cutscene Ultrawide v0.8 - settings
return {
    -- Master switch (F8 toggles at runtime and restores the game's original cap)
    Enabled = true,

    -- AC8's cameras cap the picture with their own AspectRatioMax (~2.4, the "21:9 max").
    -- 0 = raise it to your screen's aspect ratio (auto-detected). Or set a value, e.g. 3.5656 for 32:9.
    AspectRatioMaxValue = 0,

    -- 0 = auto-detect the screen shape. Set it if detection is wrong, e.g. 3.5556 for 32:9, 2.3889 for 21:9.
    ForceAspectRatio = 0,

    -- Write AC8CutsceneUW.log next to this mod (previous run kept as AC8CutsceneUW.prev.log)
    WriteLogFile = true,

    -- Keys (UE4SS Key names)
    ToggleKey = "F8",   -- on/off, A/B compare
    DumpKey   = "F7",   -- snapshot: camera caps + rendered view -> log
}
