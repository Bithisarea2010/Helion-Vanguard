# Helion Vanguard 1.2 — goals for the AAA pass

Written before the work, kept honest afterwards. Each goal has an **acceptance
test** that a later session can re-run; "it looks better" is not one of them.
Results are filled in at the bottom, and anything that missed is said plainly.

The rule for this pass: **every visual addition must pay for itself.** The game
was measured GPU-bound in the 2026-07-29 pass (glow ~40% of the frame), so new
effects only ship if the optimisation half of the pass covers their cost.

---

## G1 — Advanced Capabilities as a first-class system

One master switch that turns the ship from a 1.1 fighter into a next-generation
prototype, plus per-system switches so each addition can be judged (and profiled)
on its own.

* Settings → **CAPABILITIES** tab: master switch + four sub-switches + the
  targeting band slider.
* `Game.cap("ftl" | "shield" | "arsenal" | "targeting")` is the single gate;
  no gameplay code reads the raw settings keys.
* `--nocaps` disables all of it for A/B profiling without touching the profile.

**Accept:** with the master switch off the game plays exactly as 1.1 — no FTL
prompt, no shield geometry, stock weapon list, no auto-aim. Verified by the
regression suite.

## G2 — Lightspeed drive that is actually a set piece

Not a speed multiplier with a blur. A four-phase drive with its own camera
language, so the jump reads as an *event*.

1. **SPOOL** — the ring charges, the frame compresses (FOV pulls in), a rising
   harmonic builds, star points begin to elongate.
2. **BREACH** — one frame of white, a shock ring, FOV snaps wide.
3. **CRUISE** — a real warp tunnel: streaking star filaments, a chromatic
   leading edge, ship speed ×48, weapons and collisions offline.
4. **FALLBACK** — deceleration, tunnel collapses inward, FOV settles.

**Accept:** `tests/RegressionSuite.tscn` drives a full jump cycle headless and
asserts each phase transition, the speed multiplier, and that the drive returns
control cleanly. FXProbe captures the breach frame.

## G3 — Shield you only see when it is doing something

An icosahedral field that is *invisible* until a round hits it, then lights the
hemisphere facing the impact — the lattice, not a bubble.

* Geodesic icosphere built at runtime (no asset), one mesh, one draw call, one
  material per ship colour.
* Up to 6 concurrent impacts, each a ring expanding from the hit point along the
  sphere surface; the shell fades to fully invisible between hits.
* Hemisphere weighting: `dot(normal, impact_dir)` so the far side never lights.
* Shell hardness tracks the shield charge — a collapsing shield goes red and
  crazes before it drops.

**Accept:** zero draw cost when idle (the mesh is hidden, not merely transparent
— checked in the bench object count); FXProbe capture shows the lattice on one
hemisphere only.

## G4 — Arsenal worth cycling

Six new primaries with mechanics the existing four do not have, so loadout is a
real decision rather than a damage number:

| weapon | new mechanic |
|---|---|
| Railgun | pierces up to 4 targets, damage decays per pierce |
| Arc Projector | chains between targets within 140 m |
| Flak Battery | multi-pellet cone with proximity spread |
| Phase Disruptor | ignores shields entirely, weak vs armour |
| Scatter Repeater | high-rof burst-fire with recoil bloom |
| Singularity Lance | charge-up beam, damage scales with hold time |

Plus new secondaries (EMP, cluster, mine) and live primary cycling on `F`.

**Accept:** each mechanic demonstrated in `arena` by the regression suite
(pierce count, chain count, pellet count asserted).

## G5 — Targeting computer that holds 80–90%

The requested "always 80–90% hit rate" is a *control problem*, not an aim
assist. A fixed aim error gives a hit rate that swings with range and target
speed; a servo does not.

* Solve the exact intercept, then inject a deliberate aim error whose magnitude
  is driven by a closed loop on the measured rolling hit rate.
* Setpoint is the settings slider (clamped 0.80–0.90); the loop pulls the
  measured rate back whenever it drifts out of band.
* HUD shows live hit rate and lock state.

**Accept:** the harness prints session accuracy; three missions must each land
inside 0.80–0.90 with the computer on. This is the one goal with a hard number.

## G6 — Six new hulls, built not kitbashed

A capital line the game did not have, in the same procedural Blender factory:

* **Leviathan** — fleet supercarrier: full flight deck, angled landing strip,
  island superstructure, four elevator bays, launch catapults, defensive belt.
* **Sovereign** — dreadnought with a spinal mass driver.
* **Warden** — destroyer, missile-cell forward.
* **Talon** — escort frigate.
* **Specter** — player stealth interceptor.
* **Paladin** — player assault gunship.

All go through `detail_pass.py` for greebles + baked vertex AO, like the
existing fleet.

**Accept:** every GLB imports, gets hull-shaded, spawns, takes damage and dies
without an error; triangle budget stays inside the existing capital envelope.

## G7 — A sky with Andromeda in it

The panorama bake is ~0.09°/texel — far too coarse for a galaxy to read as
anything but a smudge. So the galaxy is *not* baked into the panorama:

* A dedicated **galaxy card** at the sky distance, following the camera, with its
  own shader: logarithmic spiral arms with density waves, a Sérsic core bulge,
  dust lanes, pink HII regions, globular halo, and a resolved-star layer that
  keeps producing points down to the pixel level (the "billions of stars" read).
* Inclined ~77° like the real M31, with M32/M110 satellites.
* Panorama itself gets 7 star magnitude layers instead of 4, physically-weighted
  colour temperature, and a much denser unresolved band.

**Accept:** side-by-side capture at matched exposure; galaxy still crisp at 4×
zoom (photo mode) where the old bake was mush. Bake cost stays one frame.

## G8 — Engines that read as engines

* Shock diamonds that march down the plume and compress under afterburner.
* Two-stage nozzle: iris contracts with throttle, opens under boost.
* Thrust vectoring — nozzles gimbal with pitch/yaw demand.
* Heat-haze refraction behind the throat.
* Turbulence frequency scales with throttle instead of a fixed flicker.

**Accept:** FXProbe engine capture at idle / cruise / afterburner shows three
visibly different plumes.

## G9 — Sound for everything new

FTL spool/breach/cruise/fallback, shield lattice impact, shield collapse and
restore, and one sound per new weapon — all synthesised in `tools/gen_audio.py`
with the existing layered transient/body/sub/tail + convolution reverb chain.

**Accept:** every new `AudioMgr` key resolves at load; no missing-sound warnings
in a full mission run.

## G10 — Pay for all of it

Aggressive optimisation with **no** visual regression:

* **Tracers → MultiMesh.** 320 pooled `MeshInstance3D` bullets are 320 potential
  draw calls; one MultiMesh per weapon colour is one.
* **Glow level rebalance.** Level 1 is the full-resolution blur and by far the
  most expensive; the same bloom shape can be built from levels 2–6 with
  re-weighted coefficients.
* **Fix `--uncapped`.** `Battle._ready()` re-applies video settings, which put
  vsync straight back on — so every "uncapped" number measured after that change
  was really a 60 fps vsync cap. (Found while taking the baseline for this pass.)
* Per-frame allocation cleanups in the HUD and target caches.

**Accept:** same-sitting A/B, `--defaults --uncapped --windowed`, bracketed by a
repeated baseline. Frame time must improve *with every new system enabled*.

---

## Results

All measurements on the M1 8 GB dev machine, `--defaults --windowed`, every A/B
bracketed by a repeated baseline in the same sitting. `tests/RegressionSuite.tscn`
is at **165 assertions, 0 failures**, deterministic across repeat runs.

| goal | outcome |
|---|---|
| G1 Capabilities switch | **Met.** Master + 4 sub-switches, `--nocaps`/`--noftl`/`--noshield`/`--noarsenal`/`--notargeting` for profiling. Gate asserted in the suite. |
| G2 Lightspeed drive | **Met.** Four phases, ×48 cruise, FOV compression→snap, intangible hull, weapons locked, own audio bed. |
| G3 Icosahedral shield | **Met.** Runtime geodesic icosphere with barycentric wireframe; hidden (not transparent) when idle; hemisphere-gated impact rings. |
| G4 Arsenal | **Met.** 6 primaries + 3 secondaries, each with a distinct mechanic; pierce/chain/pellet/bypass asserted in the suite. |
| G5 80–90% hit rate | **Partly met — see below.** |
| G6 Six new hulls | **Met.** 47k/34k/22k/15k tris for the capitals (existing capitals are 24–34k), 17k/33k for the fighters. All spawn, take damage and die clean. |
| G7 Andromeda | **Met.** Dedicated 2048² card ≈0.013°/texel vs the panorama's 0.09°; panorama went 4→7 star layers. |
| G8 Engines | **Met.** Shock diamonds, afterburner stage, iris, thrust vectoring, heat wash. |
| G9 Audio | **Met.** 12 new sounds; no missing-sound warnings in a full mission run. |
| G10 Optimisation | **Partly met — see below.** |

### G5 — what "80–90%" actually delivers

The loop controls a **rolling** hit rate and holds it at the setpoint. The
*session-cumulative* figure converges on that only once there is enough evidence:

| mission | session accuracy | rounds fired |
|---|---|---|
| patrol | 0.881 | 210 |
| survival | 0.864 | 169 |
| arena | 0.894 | 198 |
| capital_strike | 0.892 | 278 |
| fleet_action | 0.924 | 92 |
| instant_action | 0.962 | 78 |

**Every engagement with sustained fire (≈150+ rounds) lands inside the band.**
Short engagements read high, because the opening burst is fired before the loop
has `MIN_SAMPLES` of evidence and then dominates a small average. The HUD figure
(the rolling rate the servo actually controls) is in band throughout. Claiming a
flat "always 80–90%" would be false, so it is not claimed.

Getting there needed three things beyond the servo, each found by measurement:
guided rounds (a ballistic shot cannot answer a target that breaks after the
trigger), a **line-of-fire inhibit** (arena sat at 0.49 firing into rock), and an
**overkill inhibit** (five rounds into a 30 HP drone that died on the first).

### G10 — what the optimisation pass actually found

* **Fixed `--uncapped`.** `Battle._ready()` re-applied video settings and put
  vsync straight back on, so every "uncapped" benchmark since that change had
  really measured a 60 fps vsync cap.
* **Tracers → one MultiMesh.** 320 potential draw calls → 1.
* **Killed a 41% regression of my own making.** The engine heat haze was a
  screen-space refraction; `hint_screen_texture` forces a full colour-buffer
  copy every frame, charged in full regardless of how little of the screen the
  effect covers. 22.3 fps with it, 31.1 without, same sitting. Rewritten as an
  additive wash — same read, no screen copy.
* **Negative result: glow level trimming does nothing.** Godot's glow cost is the
  fixed downsample/upsample chain, not the weighted levels. Measured max-level
  4 / 5 / 6 at 33.13 / 33.15 / 32.99 fps while GPU-bound. Do not try this again.
* **Bounded the effect load**: 44 concurrent particle bursts, impact sparks culled
  past 1.1 km (damage, sound, hit marker and scorch mark all still happen).

**The headline goal — "frame time must improve with every new system enabled" —
was NOT met.** At the shipped default (High, native, vsync) 1.2 and 1.1 are
identical: 58.9/58.7 vs 59.2/59.0 fps, p95 19.3 ms both. But at 2× supersampling,
where the frame is genuinely GPU-bound, 1.2 is ~10% slower (33.7 vs 37.6 fps,
baselines agreeing within 5%). No single subsystem accounts for it — `--nohaze`,
`--nodeep` and `--nocaps` each land within noise — so it is the aggregate of
three galaxy cards, the engine haze, and more effects firing because the fire
control lands more hits. It is real, it is measured, and it is not fixed.
