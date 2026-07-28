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
