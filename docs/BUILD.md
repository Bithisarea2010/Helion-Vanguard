# Building and running Helion Vanguard 1.3.0

## Tested environment

- Godot **4.7.2.stable.official.ed1daf0bf**, Metal Forward+.
- Blender **5.2.0 LTS**, needed only to regenerate authored assets.
- Verified machine: Apple M1, 8 GB RAM, macOS. The local app targets Apple
  Silicon and macOS 13+. Windows, Linux and Intel builds were not tested.

Authoritative project root:
`/Users/bokkonboldiszar/Desktop/Codex Workspace/05_SHARED_PROJECTS/Games/HelionVanguard`

Open `project.godot` in Godot 4.7.2 and press F6 on a mission or F5 for the main
menu. Select HANGAR to choose all eight unlocked ships. Saves and settings stay
under Godot's custom `HelionVanguard` user-data directory.

## Local app

Open `build/quality-1.3.0/Helion Vanguard.app`. This self-contained local build
uses the exact installed 4.7.2 runtime with an exported game resource pack.
The installed export templates were only 4.7, so the builder deliberately does
not use that mismatched release template. It strips the official universal
runtime to arm64, includes license notices, signs ad-hoc and verifies the app
in temporary staging. No developer account, purchase or notarization is used.

The Desktop FileProvider can attach FinderInfo metadata after copying the app,
which can make `codesign --verify --strict` complain about a resource fork.
The builder verifies before copying; actual packaged gameplay is tested after
copying. A notarized distribution build with matching release templates remains
future release work.

```sh
cd "/Users/bokkonboldiszar/Desktop/Codex Workspace/05_SHARED_PROJECTS/Games/HelionVanguard"
GODOT="/Applications/További programok Boldi/Fejlesztés/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --import
python3 tools/build_local_macos.py
```

Use `--replace` to rebuild an existing **recognized 1.3.0 output**. The script
retains it until the replacement has exported and passed staging verification.
It never replaces an arbitrary folder. Build output is Git-ignored.

## Final verification commands

```sh
"$GODOT" --headless --path . tests/RegressionSuite.tscn -- --defaults
"$GODOT" --path . tests/QualityProbe.tscn -- --defaults --windowed --seed=1309
"$GODOT" --path . -- --mission=instant_action --autotest --defaults \
  --windowed --uncapped --nocamcycle --seed=1309 --quitafter=25
```

QualityProbe has a 240-second watchdog and drives Godot input events through
real rendered gameplay. It captures the changed screens, launches all ten
missions and checks camera/pause, relay geometry/traversal, training, wave
resupply and the three authored hulls. This is automated playtesting, not a
claim of physical-controller or long campaign testing. Use `--defaults` to keep
test activity isolated from both saved settings and campaign data.

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
- Audio: `tools/gen_audio.py` (needs numpy). The system python here has no
  numpy; Blender's bundled interpreter does, and runs the whole set in ~5 s:

  ```sh
  "$BLENDER" --background --python tools/gen_audio.py
  ```

  Rewritten 2026-07-29 (second pass): every sound is layered transient / body /
  sub / tail, with convolution reverb against a synthesised decaying-noise
  impulse. Two things to keep in mind when editing it:
  * convolution pads each one-shot out to the length of the impulse, so
    `write_wav` trims the tail (`DEFAULT_SFX_MAX`, overridden per sound).
    Without that a 0.2 s laser shipped as a 2.5 s file of mostly silence and a
    big explosion held one of the 32 positional voices for twelve seconds.
  * looping assets (`engine_loop`, the original music loops) go through `seamless()`,
    which crossfades the tail into the head. Noise layers never line up at a
    loop boundary, so without it the engine ticks once per cycle. Music is
    stereo; **3D sounds must stay mono** — `AudioStreamPlayer3D` pans them.
- The optional background playlist is stored under `assets/audio/music/` as
  six project-owner-supplied MP3 files. It is controlled directly from the
  first menu and rotates through a no-immediate-repeat shuffle bag.
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
| `--quitafter=<s>` | exit after N mission-seconds (plus watchdog) |
| `--uncapped` | disable vsync and the FPS limit, to see real headroom |
| `--preset=0..3` | force a quality preset |
| `--nocamcycle` | hold one camera, for comparable captures |
| `--cinematicreel` | self-driving third-person capture; cycles cinematic/orbit/chase only (never cockpit/photo) |
| `--noast`, `--nodust`, `--notrails`, `--nohud` | subsystem isolation for profiling |
| `--defaults` | **use for every A/B.** Ignore saved settings and campaign data; never write either |
| `--windowed` | 1280×720 window — Godot's own `--resolution` does NOT work here |
| `--renderscale=0.25..1.0` | force the 3D render scale |

Three traps this harness had, all of which produced confidently wrong numbers:

1. **Legacy window sizing was wrong.** Version 1.3 applies `--windowed` before
   the first macOS mode transition and confirms the real drawable size. Use
   `--windowed` for 1280×720; omit it for native fullscreen.
2. **Runs were not hermetic.** Settings save on quit, so flags leak forward.
   Always pass `--defaults` when comparing.
3. **`--quitafter` used to hang.** `Battle` is `PROCESS_MODE_PAUSABLE`, and both
   mission completion and the photo-mode self-test pause the tree, which stops
   `_process` and with it the deadline check. There is now a `SceneTreeTimer`
   watchdog that fires regardless.

Also: an invalid `--mission=` id boots to the main menu and sits there forever.
The valid ids are `training instant_action patrol convoy station_defence
capital_strike fleet_action survival arena main`.

For effects specifically, use the deterministic probe instead — the battle
harness screenshots on a fixed 4 s cadence and almost never lands on a blast:

```sh
Godot --path . --resolution 1280x720 tests/FXProbe.tscn -- --shotdir=/abs/path
```

**Always measure a baseline in the same sitting.** Absolute fps on this machine
varies by more than 2× with thermal state: commit `e8378a3` measured 63.5 fps in
one session and 27.7 fps in another with no code change at all. Comparing
against a number written down on a previous day is worthless.

`[BENCH]` lines print fps, p95/worst frame time, objects, primitives, draw calls,
VRAM and node count once a second. `tests/PerfFloor.tscn` measures the
empty-scene ceiling on the machine so battle numbers can be read against a real
floor rather than an assumed one.

---

## 1.2 additions

### New harness flags

| flag | effect |
|---|---|
| `--nocaps` | disable all four Advanced Capabilities (FTL, shield, arsenal, targeting) |
| `--noftl`, `--noshield`, `--noarsenal`, `--notargeting` | disable one system |
| `--nohaze` | disable the engine heat wash |
| `--nodeep` | disable the deep-sky galaxy cards |

### Regenerating the loading-screen gameplay reel

The loading screen automatically uses
`assets/loading/combat_reel.ogv` when that file exists. Capture from the real
game with the dedicated no-person camera route, then encode a short muted
Theora loop (the live loading UI owns the FTL soundscape):

```sh
Godot --write-movie /tmp/helion_reel.avi --fixed-fps 30 --path . -- \
      --mission=instant_action --cinematicreel --nohud --defaults --windowed \
      --quitafter=12
```

Trim away the title and debrief frames, then encode a short muted Theora/Ogg
loop. The shipped cut is 5.60 seconds at 1280x720/30 fps. The static corridor
wallpaper is always the instant first-frame fallback while the video decoder
warms up.

### Loading-screen presentation windows

`SceneFlow` deliberately keeps the cinematic screen visible for a minimum of
8 seconds at cold boot, 9 seconds for mission insertion, 7 seconds on return to
the flight deck, and 7.5 seconds for the post-combat recorder uplink. These are
total presentation windows measured from the beginning of the transition, not
extra time added after loading. If initialization finishes early, the progress
instrument holds below 100% and shows a truthful launch/debrief countdown; real
loading that exceeds the minimum is never delayed further.

`[BENCH]` now also prints `acc=` (session accuracy), `fcs=` (the fire-control
loop's rolling hit rate), `shots=`, `assist=` (servo position), `hostiles=` and
`stage=`.

**Vsync cannot be disabled on this Metal build**, so `--uncapped` alone will not
get you above 60 fps. To profile, put the GPU under real load:

```sh
Godot --path . -- --mission=instant_action --autotest --defaults --windowed \
      --uncapped --renderscale=2.0 --nocamcycle --quitafter=20
```

To compare against 1.1, use a worktree rather than `--nocaps` (which only gates
the capability systems):

```sh
git worktree add /tmp/hv_base 825a709
```

### Regenerating the 1.2 fleet

`blender_src/fleet_v2.py` builds the supercarrier, dreadnought, destroyer,
frigate and the two new fighters. It execs `shipgen.py` into its own globals, so
it runs standalone:

```sh
BLENDER="/Applications/További programok Boldi/Fejlesztés/Blender.app/Contents/MacOS/Blender"
"$BLENDER" --background --python blender_src/fleet_v2.py -- /tmp/hv_fleet
cp /tmp/hv_fleet/*.glb assets/models_original/
"$BLENDER" --background --python blender_src/detail_pass.py -- /tmp/hv_models \
    capital_leviathan capital_sovereign capital_warden capital_talon \
    ship_specter ship_paladin
cp /tmp/hv_models/*.glb assets/models/
Godot --headless --path . --import      # REQUIRED after any new class_name
```

Capital hulls use `big_finish()` (a single-segment bevel) rather than `finish()`.
The default two-segment bevel is right for a 16 m fighter but put the Leviathan's
base mesh at 47k triangles before the detail pass had even run.

### Audio

`tools/gen_audio.py` gained twelve sounds: `ftl_spool`, `ftl_breach`,
`ftl_cruise` (looping, seamless), `ftl_exit`, `shield_down`, `railgun`, `arc`,
`flak`, `phase`, `repeater`, `singularity`, `emp`. Same command as before.

## Regenerating the 1.3 assets

Run `blender_src/hero_fleet.py` and `blender_src/relay_foundry.py` using Blender
5.2 in background mode. They export the original merged-material GLBs and
editable source scenes. `tools/quality_audio.py` uses Blender's bundled NumPy
and only regenerates the new `hv_*.wav` bank, preserving older sounds and music.
After regeneration, run the import and relevant verification commands above.
Studio renders are explicitly separate from Godot runtime evidence.

## Inspecting the local resource pack

```sh
APP="$PWD/build/quality-1.3.0/Helion Vanguard.app"
"$APP/Contents/MacOS/HelionVanguard" --headless --path /tmp \
  --main-pack "$APP/Contents/Resources/HelionVanguard.pck" \
  --script "$PWD/tools/inspect_local_pack.gd" -- --defaults
```

Use absolute pack/script paths because `--path` changes resource resolution.
The inspector confirms eight ships, new models/audio, game version, and exclusion
of editor bridge/configuration. The final packaged smoke log is separate from
its screenshot log, whose readback stalls must not be used as a benchmark.
