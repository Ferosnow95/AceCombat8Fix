# ACE COMBAT 8: Wings of Theve (Ultrawide & FOV Fix)

[![Downloads](https://img.shields.io/github/downloads/Ferosnow95/AceCombat8Fix/total.svg)](https://github.com/Ferosnow95/AceCombat8Fix/releases)
[![Latest release](https://img.shields.io/github/v/release/Ferosnow95/AceCombat8Fix)](https://github.com/Ferosnow95/AceCombat8Fix/releases)

A UE4SS Lua mod that removes the black side bars (pillarboxing) in ACE COMBAT 8 cutscenes and menus on ultrawide and super-ultrawide screens (anything wider than 21:9, such as 32:9), and adds an adjustable flight FOV for the third-person, cockpit and HUD-only views.

Windows only. Single-player / offline only (see [Anti-cheat](#anti-cheat)).

| Before (stock, 32:9) | After (this fix, 32:9) |
|---|---|
| ![Before](docs/before.jpg) | ![After](docs/after.jpg) |

## Features
- **Removes pillarbox** on real-time cutscenes, menus and the hangar.
- **Hor+ framing:** the vertical framing the game was authored with is kept, and you see more on the sides.
- **Adjustable flight FOV**, separately for third-person, cockpit and HUD-only views. Changes show instantly in flight; PageUp/PageDown tune the current view and are saved automatically.
- **Stable cutscene fix:** it runs no per-frame code and keeps no references to game objects. See [How it works](#how-it-works).
- **One-key A/B toggle** (F8) and a log file for troubleshooting.

## Requirements
- ACE COMBAT 8: Wings of Theve (Steam). The game runs on Unreal Engine 5.4.
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) with UE 5.4 support, installed in `ACE COMBAT 8\Game\Binaries\Win64\`. This fix was developed and tested on UE4SS **v3.0.1** (beta build).

## Install
### Release
1. Install UE4SS into `ACE COMBAT 8\Game\Binaries\Win64\` (you should end up with `Win64\ue4ss\UE4SS.dll`).
2. Download the latest zip from [Releases](https://github.com/Ferosnow95/AceCombat8Fix/releases).
3. Extract it into `ACE COMBAT 8\Game\Binaries\Win64\`. You should get `Win64\ue4ss\Mods\AC8CutsceneUW\`.
4. Launch the game. `enabled.txt` is included, so UE4SS loads the mod automatically; `mods.txt` doesn't need editing.

### From source
Copy `src/AC8CutsceneUW` into `ACE COMBAT 8\Game\Binaries\Win64\ue4ss\Mods\`.

## Controls
| Key | Action |
|---|---|
| PageUp / PageDown | Flight FOV +/- 2° (16:9 terms) for the view you're in: third-person, cockpit or HUD-only. Takes effect immediately and is saved. |
| Home | Give the current view's FOV back to the game (its own dynamic FOV) |
| F8 | Toggle the whole fix on/off (restores the game's original cap and FOV) |
| F7 | Write a diagnostic snapshot to the log |

## Configuration
Adjust settings in `ACE COMBAT 8\Game\Binaries\Win64\ue4ss\Mods\AC8CutsceneUW\Scripts\config.lua`.

| Setting | Default | What it does |
|---|---|---|
| `AspectRatioMaxValue` | `0` | `0` = lift AC8's aspect cap to your screen's aspect ratio (auto-detected). Or a fixed value, e.g. `3.5656`. |
| `ForceAspectRatio` | `0` | `0` = auto-detect the screen shape. Set it if detection is wrong: `3.5556` for 32:9, `2.3889` for 3440×1440. |
| `FlightFOV` | `true` | Master switch for the flight FOV part. |
| `ThirdPersonFOV` | `80` | Third-person FOV, in 16:9-equivalent degrees (the game's own is 61.9). `0` = leave it to the game. |
| `CockpitFOV` | `90` | Cockpit FOV, same units (game's own: 73.7). |
| `FirstPersonFOV` | `90` | HUD-only view FOV, same units (game's own: 73.7). |
| `FOVStep` | `2` | Degrees per PageUp/PageDown press. |
| `IgnoreOtherFOVMod` | `false` | The fix switches its FOV off if the AC8CockpitFOV mod is enabled (both would set the FOV every frame). `true` = run anyway. |
| `WriteLogFile` | `true` | Write `AC8CutsceneUW.log` next to the mod. |

FOV values tuned in game are saved to `AC8CutsceneUW_flightfov.txt` and override the config. Delete that file to go back to the config values.

The FOV numbers are **16:9-equivalent**, and the mod widens them for your screen automatically. On 32:9, 80° is about 118° wide, 90° is about 127° wide.

## How it works
ACE COMBAT 8 is built on Unreal Engine 5.4 and uses its own camera classes, all prefixed `Live…`. Most of the work went into finding out which of their settings the game really reads, because it overwrites almost everything else every frame.

AC8's camera classes carry a property called **`AspectRatioMax`**, set to **2.4** on cutscene and menu cameras. Every frame, the game rebuilds the camera's shape from that cap. On a 32:9 screen it draws a 2.4:1 picture with black bars at the sides; that's the "21:9 max" people report. The classes are:
- `LiveCinematicsCineCameraComponent` (real-time cutscenes)
- `LiveCineCameraComponent` (menus and the hangar)

The fix raises `AspectRatioMax` to your screen's aspect ratio, so the game builds the full-width view itself. Because the game does the widening, the result is proper Hor+: same vertical framing, more on the sides (in the boat scene, about 104° wide instead of 82°).

Approaches that did **not** work, kept here because they're useful for other UE5 games:
- Widening the cine camera's filmback (`SensorWidth = SensorHeight × aspect`), or clearing UE5's `CropSettings`, works in stock Unreal. AC8 re-derives the filmback from `AspectRatioMax` about 30 times a second, so it's undone immediately.
- Hooking `CineCameraComponent:SetFilmback` does nothing, because AC8 applies the cap natively and never calls the setter.

### Flight FOV
The player plane has three camera components: `LiveThirdPersonCameraComponent` (the game's own FOV is 61.9°), `LiveCockpitCameraComponent` (73.7°) and `LiveFirstPersonCameraComponent` (the HUD-only view, 73.7°). AC8 already converts these 16:9-equivalent values to your screen (Hor+), so gameplay isn't broken on ultrawide; the views are just narrow (61.9° becomes about 100° wide on 32:9).

The game caches each camera's FOV and ignores later writes to the camera, so the fix doesn't touch the cameras. Instead it calls the engine's own `PlayerController:FOV(degrees)` command, which locks the final FOV on the `PlayerCameraManager` and takes effect at any time. A small per-frame check reads which flight view is active from the game's `LiveCameraViewComponent` (the view target's cached third-person, cockpit and first-person cameras) and applies that view's value. It gives the FOV back to the game in cutscenes and menus, and does nothing when the world has a net driver.

A locked FOV replaces the game's dynamic FOV in that view (for example the small changes with speed and afterburner). Setting a view to `0`, or pressing Home, gives it back.

Approaches that did **not** work:
- Writing `FieldOfView` on the live cameras has no effect on the picture.
- Changing the plane's blueprint templates, or writing to the camera the moment it spawns, was unreliable: the third-person camera reads as the engine default (90°) when created and the game then loads its real value over whatever was written.
- `PlayerCameraManager.LockedFOV` can't be written from Lua directly (it isn't exposed); `PlayerController:FOV` is the way in.

### Stability rules
These were learned from crash reports while building the cutscene fix. They keep it from crashing UE4SS, especially at level transitions:
- **No stored object references.** Cameras are patched the moment the game creates them (`NotifyOnNewObject`), or found fresh with a one-off `FindAllOf` whose results are used immediately and dropped. Even `IsValid()` on an object the game has destroyed (for example at a level fade) reads freed memory and crashes UE4SS.
- **No per-frame code in the cutscene fix.** The only recurring work is one fresh pass about 2 s after each level or player restart (`PlayerController:ClientRestart`), which takes roughly 5–20 ms.
- **Nothing risky is read** by the cutscene fix: no hooked-function parameters, and no reads of the camera manager's view-target actor; both crashed UE4SS on this game.
- **The flight FOV part is different.** It runs a cheap check once per frame on the game thread and keeps its camera-manager and view objects between frames, purging any that have been destroyed. If it ever throws, it hands the FOV back to the game and stops itself while the cutscene fix keeps running.

## Anti-cheat
ACE COMBAT 8 ships with Easy Anti-Cheat. UE4SS mods only load when EAC isn't running. **Use this fix for offline single-player only, and never take a modded game online or into co-op.**

## Known issues
- **A locked FOV replaces the game's dynamic FOV** (speed and afterburner changes) in the views where you set one. Use `0` or Home to give it back.
- The flight FOV is for offline play only: it does nothing when the world has a net driver.
- It can't run together with the AC8CockpitFOV mod. The fix detects that mod and switches its own FOV off; disable one of them.
- Pre-rendered videos (the online-mode MP4s) can't be widened.
- Widening shows more of each scene than the directors framed, so occasionally you may see things at the frame edges they didn't plan for.
- Developed and tested on one PC (32:9, 5120×1440). Reports from 21:9 and 48:9 (triple-screen) setups are welcome.

## Troubleshooting
The mod writes `AC8CutsceneUW.log` next to itself (the previous session is kept as `AC8CutsceneUW.prev.log`). Press F7 in the broken scene and attach the log to an issue. The log also records each FOV change and which flight view was detected.

## Changelog
See [CHANGELOG.md](CHANGELOG.md).

## License
Distributed under the MIT License. See [LICENSE](LICENSE).

## External tools and credits
- [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) — the Lua scripting runtime this mod runs on.
- [Lyall's ultrawide fixes](https://codeberg.org/Lyall) — the reference for Unreal ultrawide techniques (constrained aspect ratio and Hor+ FOV maths).
- [PolarWizard/CodeVeinFix](https://github.com/PolarWizard/CodeVeinFix) — README format.
- The AC8CockpitFOV mod (AC8 Three-View FOV) showed that `PlayerController:FOV` and the `LiveCameraViewComponent` cameras are the working way to set the FOV in this game. This mod's FOV code is an independent implementation of that technique.
- Works alongside the [AC8 Ultrawide UI Fix](https://www.nexusmods.com/acecombat8wingsoftheve/mods/12) (HUD layout), which is a separate mod.
