# ACE COMBAT 8: Wings of Theve — Ultrawide & FOV Fix

[![Downloads](https://img.shields.io/github/downloads/Ferosnow95/AceCombat8Fix/total.svg)](https://github.com/Ferosnow95/AceCombat8Fix/releases)
[![Latest release](https://img.shields.io/github/v/release/Ferosnow95/AceCombat8Fix?include_prereleases)](https://github.com/Ferosnow95/AceCombat8Fix/releases)

A UE4SS Lua mod that removes the pillarboxing in ACE COMBAT 8 on ultrawide and super-ultrawide screens (21:9, 32:9 and wider), and adds an adjustable flight FOV.

Windows only. Single-player / offline only (see [Anti-cheat](#anti-cheat)).

| Before (stock, 32:9) | After (this fix, 32:9) |
|---|---|
| ![Before](docs/before.jpg) | ![After](docs/after.jpg) |

## Features
- **Removes pillarbox** on real-time cutscenes, menus, the hangar and mission debriefings.
- **Adjustable flight FOV**, separately for third-person, cockpit and HUD-only views, with live tuning keys that save automatically.
- **Hor+ framing:** the vertical framing the game was authored with is kept, and you see more on the sides.
- **Safe by design:** no per-frame code, and no references to game objects are kept between frames. See [How it works](#how-it-works).
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
| PageUp / PageDown | FOV +/- 2° for the view you're in (third-person, cockpit or HUD-only). Saved automatically. Takes effect from your next spawn (retry, checkpoint or next sortie), because AC8 locks the FOV when the plane spawns. |
| Home | Reset the current view's FOV to the game default |
| F8 | Toggle the whole fix on/off (restores the game's originals) |
| F7 | Write a diagnostic snapshot to the log |

## Configuration
Adjust settings in `ACE COMBAT 8\Game\Binaries\Win64\ue4ss\Mods\AC8CutsceneUW\Scripts\config.lua`.

| Setting | Default | What it does |
|---|---|---|
| `AspectRatioMaxValue` | `0` | `0` = lift AC8's aspect cap to your screen's aspect ratio (auto-detected). Or a fixed value, e.g. `3.5656`. |
| `ForceAspectRatio` | `0` | `0` = auto-detect the screen shape. Set it if detection is wrong: `3.5556` for 32:9, `2.3889` for 3440×1440. |
| `ThirdPersonFOVOffset` | `10` | Degrees added to the third-person FOV (game default 61.9°). |
| `CockpitFOVOffset` | `10` | Degrees added to the cockpit FOV (game default 73.7°). |
| `FirstPersonFOVOffset` | `10` | Degrees added to the HUD-only FOV (game default 73.7°). |
| `FOVStep` | `2` | Degrees per PageUp/PageDown press. |
| `Diagnostics` | `false` | Extra logging of views and cameras, for bug reports. |

FOV values tuned in game are saved to `AC8CutsceneUW\AC8CutsceneUW_fov.txt` and override the config. Delete that file to go back to the config values.

The FOV values are **16:9-equivalent**: AC8 widens them for your screen automatically. On 32:9, third-person 61.9° is about 100° wide on screen, and +10 makes it about 111°.

## How it works
ACE COMBAT 8 is built on Unreal Engine 5.4 and uses its own camera classes, all prefixed `Live…`. Most of the work went into finding out which of their settings the game really reads, because it overwrites almost everything else every frame.

### Pillarbox
AC8's camera classes carry a property called **`AspectRatioMax`**, set to **2.4** on cutscene and menu cameras. Every frame, the game rebuilds the camera's shape from that cap. On a 32:9 screen it draws a 2.4:1 picture with black bars at the sides; that's the "21:9 max" people report. The classes are:
- `LiveCinematicsCineCameraComponent` (real-time cutscenes)
- `LiveCineCameraComponent` (menus and the hangar)
- `LiveDebriefingCameraComponent` (debriefings)
- `LiveCameraComponent` (gameplay; here a `0` means "no cap")

The fix raises `AspectRatioMax` to your screen's aspect ratio, so the game builds the full-width view itself. Because the game does the widening, the result is proper Hor+: same vertical framing, more on the sides (in the boat scene, about 104° wide instead of 82°).

Approaches that did **not** work, kept here because they're useful for other UE5 games:
- Widening the cine camera's filmback (`SensorWidth = SensorHeight × aspect`), or clearing UE5's `CropSettings`, works in stock Unreal. AC8 re-derives the filmback from `AspectRatioMax` about 30 times a second, so it's undone immediately.
- Hooking `CineCameraComponent:SetFilmback` does nothing, because AC8 applies the cap natively and never calls the setter.

### Flight FOV
The player plane (`BP_PlayerPlane_…`) has three camera components:

| View | Component | Game FOV (16:9) | On a 32:9 screen |
|---|---|---|---|
| Third-person | `LiveThirdPersonCameraComponent` | 61.9° | ~100° |
| Cockpit | `LiveCockpitCameraComponent` | 73.7° | ~113° |
| HUD-only | `LiveFirstPersonCameraComponent` | 73.7° | ~113° |

AC8 already converts these 16:9-equivalent values to your screen (Hor+), so gameplay isn't broken on ultrawide; the views are just narrow. The catch is that **the plane copies `FieldOfView` from its blueprint template when it spawns and keeps that value**. Changing the live camera afterwards has no effect on the picture.

So the fix changes the **templates**: each blueprint component template, once, starting from its remembered original value. Every plane that spawns copies the new FOV, and nothing is ever added twice. Templates are found again by their path name, never through a stored reference.

### Stability rules
These were learned from crash reports while building the fix. They keep it from crashing UE4SS, especially at level transitions:
- **No stored object references.** Cameras are patched the moment the game creates them (`NotifyOnNewObject`), or found fresh with a one-off `FindAllOf` whose results are used immediately and dropped. Even `IsValid()` on an object the game has destroyed (for example at a level fade) reads freed memory and crashes UE4SS.
- **No per-frame code.** The only recurring work is one fresh pass about 2 s after each level or player restart (`PlayerController:ClientRestart`), which takes roughly 5–20 ms.
- **Nothing risky is read.** No camera-manager view-target lookups and no hooked-function parameters; both crashed UE4SS on this game.

## Anti-cheat
ACE COMBAT 8 ships with Easy Anti-Cheat. UE4SS mods only load when EAC isn't running. **Use this fix for offline single-player only, and never take a modded game online or into co-op.**

## Known issues
- Pre-rendered videos (the online-mode MP4s) can't be widened.
- Widening shows more of each scene than the directors framed, so occasionally you may see things at the frame edges they didn't plan for.
- FOV changes made with PageUp/PageDown show from your next spawn, not mid-flight.
- Developed and tested on one PC (32:9, 5120×1440). Reports from 21:9 and 48:9 (triple-screen) setups are welcome.

## Troubleshooting
The mod writes `AC8CutsceneUW.log` next to itself (the previous session is kept as `AC8CutsceneUW.prev.log`). Press F7 in the broken scene and attach the log to an issue. Turn on `Diagnostics` for more detail.

## Changelog
See [CHANGELOG.md](CHANGELOG.md).

## License
Distributed under the MIT License. See [LICENSE](LICENSE).

## External tools and credits
- [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) — the Lua scripting runtime this mod runs on.
- [Lyall's ultrawide fixes](https://codeberg.org/Lyall) — the reference for Unreal ultrawide techniques (constrained aspect ratio and Hor+ FOV maths).
- [PolarWizard/CodeVeinFix](https://github.com/PolarWizard/CodeVeinFix) — README format.
- Works alongside the [AC8 Ultrawide UI Fix](https://www.nexusmods.com/acecombat8wingsoftheve/mods/12) (HUD layout), which is a separate mod.
