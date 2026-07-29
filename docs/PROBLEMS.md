# Helion Vanguard — open problems

A running, honest list of what is still wrong, written for whoever picks this up
next (including me). Anything marked **FIXED** was closed during the 2026-07-29
graphics passes and is kept for context; everything else is genuinely open.

---

## The one bug worth reading first (2026-07-29, second pass)

**`BLEND_MODE_ADD` does not enable an alpha pipeline in Godot 4.** A
`StandardMaterial3D` left at the default `TRANSPARENCY_DISABLED` generates a
shader with `ALPHA = 1.0` hard-coded. Additive blending then adds the full
albedo of every fragment, and any alpha you supply — from a texture, from vertex
colours, from a tween — is computed and silently discarded.

This single mistake was behind four separate "the effects look wrong" symptoms
that had each been attributed to something else:

| symptom | previously blamed on | actually |
|---|---|---|
| sparks / embers / impacts drew as hard opaque squares | additive saturation clipping the soft dot texture | texture alpha discarded |
| engine ribbons drew as solid white slabs | ribbon geometry seen end-on | every per-vertex fade discarded |
| shockwave ring drew as a solid square, never faded | — | ring alpha and the alpha tween both discarded |
| explosion smoke read as bright haze | — | same material path |

Fixed by setting `transparency = TRANSPARENCY_ALPHA` on the ring material, and
by replacing the particle materials with `shaders/spark.gdshader` and
`shaders/smoke.gdshader`, which compute the radial falloff from `UV` and so
cannot be caught by this again. **Opaque additive geometry — cannon tracers,
beam cylinders — is intentional and deliberately left alone.**

If an additive effect ever looks "too solid" in this project, check
`transparency` before touching anything else.

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

## Fixed in the second 2026-07-29 pass

- **FIXED — The chase camera sat inside the ship.** The rig was a fixed
  `+10.4 m` on Z. Every player hull is 15–19 m long with its tail at roughly
  `+10.8`, so the lens was *inside the engine block*: the near plane clipped
  through the hull and only the wingtips ever reached frame. `CameraRig` now
  derives the standoff from `PlayerShip.model_aabb` — measured from the tail,
  not the origin — so "the whole ship is visible" is true for every ship in the
  roster rather than for none of them. Tunable via the new
  `cam_distance` setting (Video tab).
- **FIXED — Twitchy controls.** Raw mouse deltas drove turn rate directly, with
  a linear response and no stick dead-zone rescale. Now: the virtual cursor is
  exponentially filtered, both axes get a cubic expo curve, gamepad axes have
  the dead zone rescaled out (Godot zeroes below it but passes the raw value
  above, so a stick jumped straight to 0.25), and the rotation demand and
  translation wish are each smoothed before reaching the rigid body. Amount is
  tunable via `control_smoothing` (Gameplay tab); 0 restores near-raw response.
- **FIXED — The additive-transparency bug above.**
- **FIXED — Asteroid crater rings drew as hard dark circles.** The crater field
  picked the *nearest* crater per pixel; the winner flips between adjacent
  pixels, and since the bump normal comes from `dFdx/dFdy` of that height, the
  step became an infinite gradient. Summing overlapping bowls instead is
  C0-continuous and the outlines are gone.
- **FIXED — The duplicated asteroid textures are now actually dropped**
  (was open item 1). `AsteroidField` binds
  `assets/textures/asteroid_albedo.png` and then clears the embedded material
  off each variant mesh, so the four copies are released rather than merely
  unused.

---

## Open — correctness

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

5. **FIXED in 1.1 — `HullMaterial.apply()` discarded textures.** Albedo textures
   are now preserved, included in material-cache signatures, and sampled by the
   hull/canopy shaders.

6. **FIXED in 1.1 — Damage response was wired but never driven.** Player,
   enemy, capital, and wreck damage now update the hull shader's scorch/crack
   response as integrity falls.

---

## Open — performance

7. **Absolute fps figures in this file are not comparable across sessions.**
   The 67.4 / 63.5 numbers previously recorded here were re-measured on
   2026-07-29 (second pass) on the same machine and the *same commit* came back
   at **27.7 fps**, i.e. less than half. Nothing in the project changed; the
   host was simply in a different thermal/power state. Treat any number here as
   meaningful only against a baseline measured in the same sitting.

   Second-pass comparison, both measured back to back, 1280×720, uncapped,
   autotest bot, camera locked, 14–16 one-second samples:

   | build | `instant_action` |
   |---|---|
   | `e8378a3` (pre-pass baseline) | 27.7 fps |
   | second pass | 32.6 fps |

   So the second pass is **not** a regression despite adding a fireball shell
   shader, per-instance asteroid variation and a heavier rock surface — most
   likely because fixing the transparency bug removed a great deal of
   full-screen additive overdraw from trails and particle squares. `main` runs
   28.2 and `survival` 33.1 under the same conditions.

8. **CORRECTED — the game is GPU-bound, not CPU-bound.** This file previously
   claimed the opposite, on the evidence that "frame time is identical at
   640×360 and 1920×1080". That evidence was an artefact: `apply_video_settings()`
   forces `Window.MODE_FULLSCREEN`, and it runs *before* the command line is
   parsed, so Godot's `--resolution` flag was silently overridden. **Every
   resolution test this project ever ran measured the same native 2880×1800
   buffer.** Both sides of the comparison were the same picture.

   A `sample` profile settled it: **8,766 of 10,799 main-thread samples (81%)
   sit in `-[IOSurfaceSharedEvent waitUntilSignaledValue:timeoutMS:]`** — the
   CPU blocked waiting on the GPU. Only ~400 samples are in command encoding.

   With the new `--windowed` / `--renderscale=` flags, which actually work:

   | render scale (fullscreen) | fps |
   |---|---|
   | 0.85 (shipping, ~2448×1530) | 83.3 |
   | 0.30 | 146.2 |

   Cost breakdown, each measured alone against a same-batch baseline:
   **glow ~40%**, MSAA 2× ~9%, the whole asteroid field ~3.5%, shadows ~3.5%.
   Glow is by far the most expensive thing this game draws.

9. **Machine state swings results by more than 2×, so only same-batch numbers
   mean anything.** The identical build and configuration measured 83 fps and
   165 fps in two batches an hour apart on the same Mac, purely from thermal
   state. When cool the game becomes CPU-bound around 165 fps and GPU savings
   stop showing; when hot it is firmly GPU-bound and they show fully. Always
   bracket an A/B with a repeated baseline, and discard the batch if the two
   baselines disagree.

10. **The harness was not hermetic until `--defaults` was added.** Settings are
    written to `user://settings.cfg` on quit, so `--preset=0` or `--windowed`
    leaked into every later run and an A/B series silently measured whatever the
    previous run left behind. One full benchmark batch was invalidated this way
    before it was caught. Pass `--defaults` for anything you intend to compare.

9. **`main` is the worst case at ~59 fps.** It builds 1,500 belt rocks plus a
   500-rock cluster and two capitals. Not investigated separately.

11. **PARTLY FIXED — wave spawn hitches.** Building 3–4 fighters in one frame
    cost a 31–39 ms spike on every wave. `Battle._prewarm_enemy_hulls()` now
    loads each enemy GLB and warms the shared `HullMaterial` cache during
    mission load, and `spawn_wave()` spawns the leader immediately then trickles
    wingmen in one per frame. Per-wave spikes are gone; one ~35 ms spike remains
    at the *first* wave of a mission (other first-use costs — tracer materials,
    FX shaders — still land there). Waves arrive 2+ km out, so the stagger is
    invisible.

11. **VRAM remains high for the content.** The 4096×2048 RGBE sky panorama is a
    material part of it. The duplicated embedded asteroid textures were removed
    in the second pass; a current release-build capture should replace the old
    555 MB estimate before further conclusions are drawn.

---

## Open — content and scope

12. **Only `instant_action` and `main` were visually reviewed frame by frame.**
    The other seven missions were checked for script errors and frame time only.

13. **No automated visual regression.** The harness captures screenshots but
    nothing compares them; a bad shader edit would only be caught by a human
    looking at the output. `tests/FXProbe.tscn` narrows the gap for effects
    specifically — it parks a static camera, fires one effect at a known time
    and grabs the frame at a known offset, so explosion/missile/asteroid shots
    are reproducible run to run instead of depending on the battle harness
    happening to screenshot during a blast:

    ```sh
    Godot --path . --resolution 1280x720 tests/FXProbe.tscn -- --shotdir=/abs/dir
    ```

    Two cautions learned the hard way while writing it: keep the probe camera
    **outside** the asteroid cluster (`populate_cluster` spreads rocks by
    `radius * 0.4` sigma, so a radius of 70 reaches ~60 m and swallows a camera
    at 56 m), and keep its ambient light near-neutral — a saturated blue fill
    made the rocks look like blue glass and sent me hunting a shader bug that
    was the probe's own lighting.

14. **Rings are implemented but unused.** `shaders/rings.gdshader` and
    `SpaceEnv._add_rings()` work, but no mission declares `"rings"` on a planet
    yet.

15. **`space_sky.gdshader` is now near-dead code.** It renders for the two frames
    before the panorama bake replaces it. Worth either deleting or keeping
    deliberately as the low-preset path.
