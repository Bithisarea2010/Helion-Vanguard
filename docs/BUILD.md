# Building Helion Vanguard for macOS

## Requirements

- Godot **4.7 stable** (official build) — `/Applications/Godot.app`
- Godot 4.7 export templates installed
  (`~/Library/Application Support/Godot/export_templates/4.7.stable/`)
- macOS 11+ (Apple Silicon or Intel; the export is a universal binary)

## Steps

```sh
cd HelionVanguard

# 1. import all assets
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import

# 2. export (uses export_presets.cfg, preset "macOS")
mkdir -p build
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    --export-release "macOS" "build/Helion Vanguard.zip"

# 3. unpack the app bundle
cd build && unzip -o "Helion Vanguard.zip"

# 4. (re)sign for local execution — ad-hoc:
codesign --force --deep -s - "Helion Vanguard.app"

# 5. install
cp -R "Helion Vanguard.app" ~/Desktop/
```

## Code-signing status

- The bundled build is **ad-hoc signed** (`codesign -s -`). It runs locally.
- It is **not notarised** — a Developer ID certificate was not available on
  the build machine (only an *Apple Development* certificate was present,
  which cannot be used for notarised distribution).
- If you download the app (rather than build/copy it locally), macOS
  Gatekeeper may quarantine it; right-click → Open, or run
  `xattr -dr com.apple.quarantine "Helion Vanguard.app"`.

## Automated test hooks

```sh
# boot straight into a mission:
Godot --path . -- --mission=instant_action
# add a combat bot that flies and fights by itself (demo / soak test):
Godot --path . -- --mission=survival --autotest
```

## Regenerating assets

- Ships/stations: open Blender ≥ 4.x, run `blender_src/shipgen.py`,
  then `player_ships.py` / `enemy_ships.py` / `props.py` build functions.
- Audio: `python3 tools/gen_audio.py` (needs numpy).
- Icon: `python3 tools/gen_icon.py`, then `iconutil` (see tools file).

---

## Detail / AO asset pass (2026-07-29)

The shipped GLBs are generated, not hand-modelled. `blender_src/detail_pass.py`
takes the pristine sources in `assets/models_original/`, adds a deterministic
greeble layer and bakes per-vertex ambient occlusion into `COLOR_0`:

```sh
BLENDER="/Applications/További programok Boldi/Fejlesztés/Blender.app/Contents/MacOS/Blender"
"$BLENDER" --background --python blender_src/detail_pass.py -- /tmp/hv_models
cp /tmp/hv_models/*.glb assets/models/
```

**The pass is not idempotent.** It defaults to reading `assets/models_original/`
for exactly this reason — running it over its own output greebles the greebles
and roughly doubles the triangle count again. Pass `--src=<dir>` to override.

Add ship names after the output directory to process a subset:

```sh
"$BLENDER" --background --python blender_src/detail_pass.py -- /tmp/hv_models enemy_razor enemy_jackal
```

After any asset change, refresh Godot's import cache before running from the CLI
(new `class_name` scripts need this too, or the global class cache is stale):

```sh
Godot --headless --path . --import
```

## Verification harness

Every performance and visual claim in `docs/PROBLEMS.md` came from this:

```sh
Godot --path . --resolution 1280x720 -- --mission=instant_action --autotest \
      --uncapped --nocamcycle --shotdir=/abs/path --quitafter=18
```

| flag | effect |
|---|---|
| `--mission=<id>` | boot straight into a mission |
| `--autotest` | self-driving combat bot |
| `--shotdir=<abs>` | PNG capture every 4 s |
| `--quitafter=<s>` | exit after N mission-seconds |
| `--uncapped` | disable vsync and the FPS limit, to see real headroom |
| `--preset=0..3` | force a quality preset |
| `--nocamcycle` | hold one camera, for comparable captures |
| `--noast`, `--nodust`, `--notrails`, `--nohud` | subsystem isolation for profiling |

`[BENCH]` lines print fps, p95/worst frame time, objects, primitives, draw calls,
VRAM and node count once a second. `tests/PerfFloor.tscn` measures the
empty-scene ceiling on the machine so battle numbers can be read against a real
floor rather than an assumed one.
