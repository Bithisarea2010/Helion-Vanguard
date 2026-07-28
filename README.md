# HELION VANGUARD

**Fast, colourful third-person space combat for macOS.**
An original game built with Godot 4.7, Blender and a fully procedural
asset pipeline. Optimised for Apple Silicon.

![icon](assets/icons/icon.png)

## Playing

Double-click **Helion Vanguard.app**. The game opens to the main menu:

- **INSTANT ACTION** — straight into a dogfight in the asteroid belt.
- **MISSIONS** — nine playable operations, from the Flight Academy tutorial
  to the 15–20 minute campaign strike *Operation Sunfall*.
- **HANGAR** — choose between four ships, change weapons, missiles,
  paint and engine glow.
- **SETTINGS** — video (fullscreen/windowed, render scale, presets),
  audio, gameplay and complete control remapping.

### Default controls

| Input | Action |
|---|---|
| Mouse / trackpad | Aim — the ship follows the cursor |
| W / S | Forward thrust / brake & reverse |
| A / D | Strafe left / right |
| Q / E | Roll |
| Space / Left Ctrl | Move up / down |
| Left Shift | Boost |
| Left mouse | Fire primary weapons |
| Right mouse | Fire missile (needs lock for guided types) |
| R | Cycle hostile targets |
| T | Target under crosshair |
| X | Match target velocity |
| G | Countermeasure flares |
| V | Weapon group (A / B / linked) |
| C | Camera: chase → cockpit → orbit → cinematic |
| B | Tactical map |
| M | Toggle flight assist (momentum mode) |
| P | Photo mode |
| Esc | Pause |

Gamepads are supported (left stick pitch/yaw, right stick strafe,
triggers thrust, shoulder buttons fire). Every binding can be changed in
Settings → Controls.

### The ships

| Ship | Role | Character |
|---|---|---|
| SF-3 Wasp | Interceptor | fastest, most agile, fragile |
| SF-7 Vanguard | Assault fighter | the balanced all-rounder |
| SG-9 Hammer | Heavy gunship | slow, armoured, brutal broadside |
| SM-5 Raptor | Strike craft | 18 missiles and a long-range lock |

## Project layout

```
project.godot          Godot 4.7 project (open with the Godot editor)
export_presets.cfg     macOS export preset
scenes/                scene stubs (all content is built in code)
scripts/               all GDScript source
shaders/               sky, planet shaders (original)
assets/                models (GLB), audio (WAV), fonts, icons, textures
blender_src/           Blender generator scripts + saved .blend sources
tools/                 audio synth + icon generator (Python)
docs/                  build notes, controls, performance, limitations
```

## Building from source

See [docs/BUILD.md](docs/BUILD.md). Short version:

```sh
godot --headless --path . --import
godot --headless --path . --export-release "macOS" "build/Helion Vanguard.zip"
```

## Licences

All code, models, audio and missions are original. Third-party items:
one CC0 texture set (Poly Haven) and two SIL-OFL fonts.
Details in [LICENSES.md](LICENSES.md) and [assets/manifest.json](assets/manifest.json).
