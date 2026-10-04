# Changelog

**v0.16 is the latest release.** v0.8 (cutscene/menu fix only) is also published. The other versions were internal test builds, and v0.11 is a superseded pre-release; they're listed because each one taught something about how AC8 handles its cameras.

## v0.16 — 2026-10-04 (release)
**Crash hardening for the flight FOV part. Same features as v0.15; the cutscene/menu fix is unchanged.**
- **Why:** with v0.15 the game crashed once, 50 ms after gameplay resumed from a mid-mission cutscene (access violation on the game thread, inside the mod's per-frame FOV code, the same class of crash as the old v0.4–v0.7 builds). The exact object read is not known.
- **Changed:** the FOV part no longer takes objects from `NotifyOnNewObject` (they fire while the object is still being built). It rebuilds its list of camera managers and views from a fresh `FindAllOf` scan once per second.
- **Changed:** at every `PlayerController:ClientRestart` (level start, return from a cutscene, respawn) it forgets all stored objects and does nothing for about 180 frames. The FOV lock therefore comes back about 1–3 seconds after gameplay resumes.
- If you still crash, set `FlightFOV = false` in `Scripts\config.lua`: that leaves only the cutscene/menu fix, which has not crashed. Crash reports are in `%LOCALAPPDATA%\BANDAI NAMCO Entertainment\ACE COMBAT 8\Saved\Crashes`.

## v0.15 — 2026-10-04 (superseded by v0.16)
**Cutscene/menu fix plus a working, live flight FOV.**
- **New:** flight FOV for third-person, cockpit and HUD-only views (`ThirdPersonFOV`, `CockpitFOV`, `FirstPersonFOV`, in 16:9-equivalent degrees; `0` = the game's own). The mod widens them for your screen.
- **New:** PageUp/PageDown change the FOV of the view you're in, live, with no respawn. Home gives the view back to the game. Values are saved to `AC8CutsceneUW_flightfov.txt`.
- **How:** the FOV is set with the engine's `PlayerController:FOV(degrees)` command, and the active view is read from the game's `LiveCameraViewComponent`. Earlier attempts that wrote to the cameras never worked (see below).
- **New:** the FOV is released in cutscenes and menus, and is not applied when the world has a net driver.
- **New:** `IgnoreOtherFOVMod`: the FOV part switches itself off if the AC8CockpitFOV mod is enabled.
- **Changed:** F8 also hands the FOV back to the game.
- **Changed:** the cutscene part is unchanged from v0.8. The flight FOV part runs a cheap per-frame check and keeps its camera-manager and view objects (purged when destroyed); if it ever throws, it releases the FOV and stops itself.
- Confirmed in-game on 32:9: the FOV changes live in all three views. v0.15 then crashed once after a mid-mission cutscene, which led to v0.16.

## Internal FOV test builds (v0.9 – v0.14)
None of these shipped. They tried to change the FOV by writing to the plane's cameras, which never worked reliably.

- **v0.14** — Patched the third-person blueprint template again after its real value had loaded. Superseded by v0.15, then v0.16.
- **v0.13** — Wrote the offset to each plane camera the moment it was created. Cockpit and HUD-only took the offset at spawn, but third-person did not: its camera reads 90° (the engine default) at creation and the game then loads its real value over the write.
- **v0.12** — Live-FOV probes. `PlayerCameraManager.LockedFOV` isn't exposed to Lua in this build, and the afterburner FOV channel (`ABMaxAdditionFOV`, `AfterburnerFOVCurrent`) changed nothing. It also showed that v0.11 read the third-person template before the game finished loading it.
- **v0.11** — Changed the plane's blueprint templates, with PageUp/PageDown. Cockpit and HUD-only worked at spawn; third-person did not. Published as a pre-release and superseded by v0.16.
- **v0.10** — Wrote `FieldOfView` on the live cameras. No effect on the picture, and the offset was applied twice (template, then the camera copied from it).
- **v0.9** — Added FOV discovery. It found the flight camera classes on the player plane and showed that AC8's gameplay is already Hor+ (61.9° at 16:9 becomes about 100° on 32:9). Also found `LiveDebriefingCameraComponent`.

What this showed: AC8 reads a flight camera's FOV once, when the camera starts up, and ignores later writes to the live camera. `PlayerController:FOV` locks the final FOV and wins.

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
