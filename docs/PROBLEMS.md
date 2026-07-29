# Helion Vanguard — open problems

A running, honest list of what is still wrong, written for whoever picks this up
next (including me). Anything marked **FIXED** was closed during the 2026-07-29
graphics pass and is kept for context; everything else is genuinely open.

Every performance number here came from the in-game harness, not from feel:

```bash
Godot --path . --resolution 1280x720 -- --mission=instant_action --autotest --uncapped --nocamcycle --quitafter=18
```

---

## Fixed in the 2026-07-29 pass

- **FIXED — Ships rendered as flat untextured plastic.** The GLBs carry
  `POSITION` + `NORMAL` only: no UVs, no textures, just eight solid Principled
  colours per ship. Now handled by `shaders/hull.gdshader`, which generates
  plating, seams, bolts, edge wear and grime procedurally in object space, plus
  `blender_src/detail_pass.py`, which adds real greeble geometry and bakes
  vertex AO into `COLOR_0`.
- **FIXED — Engine plumes were solid white rectangles.** ~22 additive billboard
  quads overlapped per engine; the sum saturated past 1.0 across the whole quad,
  so the soft radial texture clipped into a hard-edged brick. Replaced with
  `ExhaustPlume` — one additive cone shell per engine, no self-overdraw.
- **FIXED — Exhaust ribbons stacked into white slabs.** The chase camera looks
  straight down its own trail; a billboarded ribbon seen end-on keeps full width
  while every segment adds. Fixed with a view-alignment fade in `EngineTrail`.
- **FIXED — Backlit planets rendered as black holes in the sky.** Two causes:
  `render_mode unshaded` discards `EMISSION` (the shader wrote its result there),
  and the forward-scatter term had a sign error. Planets now show a lit
  atmospheric crescent when they eclipse the star.
- **FIXED — Cockpit was an unlit black slab.** Interior materials were multiplied
  down 0.32× with a single 0.22-energy lamp, in a scene with almost no ambient.
  Now runs the hull shader with interior tuning plus three practical lights.
- **FIXED — `get_tree()` assert on every quit.** `Game._notification` called
  `get_tree()` during `NOTIFICATION_EXIT_TREE`, printing
  `Parameter "data.tree" is null` on every run. Guarded with `is_inside_tree()`.
- **FIXED — Asteroid collider scan was O(all rocks) with a sort, every 0.5 s.**
  With 1,700 rocks this produced periodic 13–15 ms physics spikes. `AsteroidField`
  now keeps a uniform spatial hash and only scans the 27 cells around the player.
- **FIXED — Source textures shipped uncompressed.** Every PNG/JPG imported with
  `compress/mode=0` (lossless), i.e. RGBA8 in VRAM. Switching to VRAM-compressed
  cut ~65 MB.

---

## Open — correctness

1. **The four asteroid GLBs still embed byte-identical texture sets.**
   `asteroid_0..3.glb` each carry the same ~3.9 MB of images, so four copies sit
   in VRAM. `AsteroidField` now binds one shared `ShaderMaterial` for all
   variants, so the duplicates are no longer *used* — but they are still loaded.
   The real fix is re-exporting the rocks with no embedded material and pointing
   the shader at `assets/textures/asteroid_albedo.png`, which already exists as a
   standalone file.

2. **`detail_pass.py` is not idempotent.** Running it with `assets/models` as
   both source and destination greebles the already-greebled mesh and roughly
   doubles the triangle count again. Pristine copies live in
   `assets/models_original/`; always restore from there before re-running. A
   `--src` flag would remove the footgun entirely.

3. **Greeble placement is surface-random, not semantic.** Faces pointing mostly
   fore/aft are skipped so the nose and engine bells stay clean, but nothing
   understands "this is a wing leading edge" or "this is a canopy". Occasional
   blisters land somewhere a human artist would not have put one.

4. **The cockpit interior is still the weakest view in the game.** It now lights
   and panels correctly, but the underlying `cockpit.glb` is a crude box: the
   canopy frame ribs are enormous, the dash is one flat slab, and the three
   gauges are the only real instruments. This needs geometry work in
   `blender_src/cockpit_v2.py`, not more shader tuning.

5. **`HullMaterial.apply()` discards textures.** Any surface whose GLB material
   carries an albedo texture loses it — only `cockpit.glb` and the asteroids have
   textures today, and the asteroids bypass the helper, so nothing regresses in
   practice. It will bite the moment a textured asset is added.

6. **Damage response is wired but never driven.** `hull.gdshader` has a `damage`
   uniform (scorch + glowing cracks) and `HullMaterial.set_damage()` exists, but
   no gameplay code calls it. Hooking it to `Combatant.hull_frac()` is a small
   change with a large payoff.

---

## Open — performance

7. **Roughly 5% slower than the pre-pass build, uncapped.** Measured means over
   12–13 one-second samples at 1280×720, uncapped, autotest bot, camera locked:

   | mission | before | after | delta |
   |---|---|---|---|
   | `instant_action` | 67.4 fps | 63.5 fps | −5.8% |
   | `main` | 61.4 fps | 58.8 fps | −4.2% |

   Bought with: ~2–3× hull geometry, full procedural PBR shading with baked AO,
   a 4K nebula bake, rewritten planets, and a new exhaust system. Draw calls
   went the other way, ~350 → ~150. Both figures sit around the 60 fps vsync
   target the game actually ships at, but the claim "no performance cost" would
   be false and is not made.

8. **The game is CPU-bound, and always has been.** Frame time is essentially
   identical at 640×360 and 1920×1080 — the empty-scene floor is ~170 fps
   (5.9 ms), a battle is ~60 fps (16 ms), and dropping resolution by 9× moves it
   by less than one frame. Every remaining GPU-side idea is therefore nearly
   free, and every CPU-side saving is worth more than it looks. Whatever occupies
   that ~10 ms has not been isolated: disabling the HUD, dust, trails and the
   entire asteroid field together only recovers ~2 ms. Next step is a real
   sampling profile, not more guessing.

9. **`main` is the worst case at ~59 fps.** It builds 1,500 belt rocks plus a
   500-rock cluster and two capitals. Not investigated separately.

10. **Wave spawns still hitch.** Occasional 13–19 ms physics frames line up with
    `spawn_wave`, which instantiates `EnemyShip`, loads the GLB and walks every
    surface through `HullMaterial`. A preloaded model + material cache warmed at
    mission start would smooth it.

11. **VRAM is ~555 MB.** Down from 580 MB, but still high for the content. The
    4096×2048 RGBE sky panorama is ~33 MB of that; the duplicated asteroid
    textures are most of the rest (see 1).

---

## Open — content and scope

12. **Only `instant_action` and `main` were visually reviewed frame by frame.**
    The other seven missions were checked for script errors and frame time only.

13. **No automated visual regression.** The harness captures screenshots but
    nothing compares them; a bad shader edit would only be caught by a human
    looking at the output.

14. **Rings are implemented but unused.** `shaders/rings.gdshader` and
    `SpaceEnv._add_rings()` work, but no mission declares `"rings"` on a planet
    yet.

15. **`space_sky.gdshader` is now near-dead code.** It renders for the two frames
    before the panorama bake replaces it. Worth either deleting or keeping
    deliberately as the low-preset path.
