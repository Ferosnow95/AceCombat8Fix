# Changelog

Only **v0.8** is published as a release. The other versions were internal test builds; they're listed because each one taught something about how AC8 handles its cameras.

## v0.8 — 2026-10-04 (release)
**Stable cutscene/menu fix.**
- Raises AC8's `AspectRatioMax` cap (2.4) to the screen's aspect ratio on `LiveCinematicsCineCameraComponent` (cutscenes) and `LiveCineCameraComponent` (menus and hangar).
- Rewritten for stability: cameras are patched when the game creates them, plus one fresh pass after each level/player restart. No object references are kept and nothing runs per frame.
- F8 toggles the fix and restores the game's originals; F7 writes a snapshot to the log.
- Confirmed in-game: full width in cutscenes and menus, and a 37-minute session with no crashes and no errors.

## v0.7 — internal
- Found the cause: AC8's own `AspectRatioMax` cap. Cutscenes rendered full width for the first time (3.556:1, ~104° wide).
- It crashed at a level fade, because the per-tick loop touched camera objects the game had destroyed. Fixed by the v0.8 rewrite.

## v0.6 — internal
- Removed the view-target lookup that crashed UE4SS a few seconds after the menu loaded.
- A reset counter proved the game rewrote the camera ~30 times a second. A reflection dump of AC8's camera classes then revealed `AspectRatioMax`.

## v0.5 — internal
- Setter hooks rewritten to never read function parameters. It still crashed, from the view-target lookup (found in v0.6).

## v0.4 — internal
- Tried hooking `CineCameraComponent:SetFilmback` / `SetCropSettings`. The hooks never fired: AC8 applies its cap natively.
- Added reflection of the game's camera classes.

## v0.3 — internal
- The UE4SS log showed the engine is **UE 5.4**, not UE4. Added handling for UE5's plate crop (`CropSettings.AspectRatio`).
- Replaced per-tick `FindAllOf` scans (expensive on this UE4SS build) with object registries.

## v0.2 — internal
- Automatic logging: detects cutscenes by itself and writes a `RESULT` verdict per cutscene to `AC8CutsceneUW.log`.

## v0.1 — internal
- First attempt: widened the cine camera filmback and converted the FOV to Hor+. Correct in stock Unreal, but AC8 undid it every frame.
