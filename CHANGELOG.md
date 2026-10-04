# Changelog

**v0.8 is the latest release** and the only supported version. It fixes cutscenes and menus only; it has no FOV option. The other versions were internal test builds; they're listed because each one taught something about how AC8 handles its cameras.

## FOV experiments (v0.9 – v0.13) — not working, not released
None of these fixed the flight FOV in game, and none is part of the release. The cutscene fix is unchanged from v0.8.

- **v0.13** — Wrote the offset to each plane camera the moment it is created, and left the blueprint templates alone. Reported in game as not changing the FOV.
- **v0.12** — Test build with live-FOV probes. `PlayerCameraManager.LockedFOV` is not exposed in this build, and adding FOV through the afterburner channel (`ABMaxAdditionFOV`, `AfterburnerFOVCurrent`) changed nothing. It also showed that v0.11 read the third-person template while the game was still loading it and recorded the wrong original value (90° instead of 61.9°), so third-person never received the offset.
- **v0.11** — Changed the plane's blueprint templates once each, with PageUp/PageDown tuning keys. Cockpit and HUD-only picked up the offset at spawn; third-person did not (see v0.12). It was published as a pre-release and is superseded: it does not deliver a working FOV option.
- **v0.10** — Wrote `FieldOfView` on the live cameras. No effect on the picture, and the offset was applied twice (template, then the camera copied from it).
- **v0.9** — Added FOV discovery. It found the flight camera classes on the player plane and showed that AC8's gameplay is already Hor+ (61.9° at 16:9 becomes about 100° on 32:9). Also found `LiveDebriefingCameraComponent`.

What this showed: AC8 reads a flight camera's FOV once, when the camera starts up, and ignores later writes to the live camera. A reliable way to change it has not been found.

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
