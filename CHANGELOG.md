# Changelog

Only **v0.8** and **v0.11** are published as releases. The other versions were internal test builds; they're listed because each one taught something about how AC8 handles its cameras.

## v0.11 — 2026-10-04 (pre-release)
**Cutscene/menu fix plus adjustable flight FOV.**
- **New:** per-view flight FOV for third-person, cockpit and HUD-only (`ThirdPersonFOVOffset`, `CockpitFOVOffset`, `FirstPersonFOVOffset`, default +10° each).
- **New:** PageUp/PageDown tune the FOV of the view you're in, and Home resets it. Values are saved to `AC8CutsceneUW_fov.txt` and loaded on the next launch.
- **New:** the aspect cap is also lifted on gameplay cameras (`LiveCameraComponent`) and debriefing cameras (`LiveDebriefingCameraComponent`).
- **Changed:** FOV is now applied to the plane's blueprint **templates** only, once each, starting from their original value. AC8 copies the FOV when the plane spawns and ignores later changes, so this is the only place it sticks.
- **Fixed:** the v0.10 test build applied the FOV twice (template, then the camera copied from it), so cockpit and HUD-only got +20 instead of +10.
- **Fixed:** an `AspectRatioMax` of `0` (meaning "no cap") on gameplay cameras was being turned into a cap. It's now left alone.
- **Changed:** one fresh camera pass per burst of level/player restarts, instead of one per restart (a loading-screen hitch of up to ~40 ms became a single pass of ~5–20 ms).
- **Changed:** `Diagnostics` (view and camera logging) is off by default.
- Note: the FOV feature hasn't yet been confirmed in-game on the final build, which is why this is a pre-release. The cutscene fix is unchanged from v0.8.

## v0.10 — internal
- First FOV build. It set `FieldOfView` on the live cameras, which had no effect on the picture, and the FOV was also applied twice. Both fixed in v0.11.

## v0.9 — internal
- Added FOV discovery. It found the three flight camera classes on the player plane and showed that AC8's gameplay is already Hor+ (61.9° at 16:9 becomes ~100° on 32:9).
- Merged the camera passes after each level/player restart into one.
- Found `LiveDebriefingCameraComponent`.

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
