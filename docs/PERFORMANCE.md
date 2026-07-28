# Helion Vanguard — macOS Performance Report

**Test machine:** MacBook (Apple M1, 8-core, Apple7 GPU), macOS 26 (Darwin 25.6),
internal display 2880×1800 (Retina 5K-class backing store), Metal renderer
(Godot 4.7 Forward+, "Metal 4.0 Direct" path). macOS Game Mode engaged
automatically in fullscreen.

## Measured results (release export, High preset, render scale 0.85)

| Scene | FPS | GPU frame | App memory | Metal memory |
|---|---|---|---|---|
| Main menu (hangar + belt backdrop) | 60 (vsync cap) | ~30 ms first load → ~25 ms warm | ~0.7 GB | ~0.48 GB |
| Instant Action dogfight (wave 1–2, trails, tracers, missiles) | 60 | 24–26 ms | ~0.7 GB | ~0.48 GB |
| Survival soak with camera cycling (chase/cockpit/orbit) | 60 | 25–26 ms | ~0.7 GB | ~0.48 GB |

- CPU frame interval stayed pinned at 16.67 ms (vsync-bound); no CPU spikes
  observed in soak runs. One transient spike appears at wave-spawn moments
  (ship instantiation) — under one frame of budget headroom at 60 fps.
- First launch spends ~10–14 s on Metal pipeline/shader compilation before
  the menu appears; later launches reuse the shader cache and load in a few
  seconds.
- No leaks observed across mission restarts (App memory returns to ~0.7 GB).
- Logs after full session: 0 crashes, 0 script errors.

## What the presets change

| Preset | MSAA | Glow | Shadows | Asteroid density | Particles | Debris life |
|---|---|---|---|---|---|---|
| Low | off | off | off | 45 % | 50 % | 3 s |
| Medium | off | on | off | 70 % | 75 % | 5 s |
| High (default) | 2× | on | on | 100 % | 100 % | 8 s |
| Ultra | 4× | on | on | 135 % | 130 % | 12 s |

Render scale (0.5–1.0, bilinear) applies to the 3D buffer only; UI stays
native-crisp. VSync and an optional 60/120 fps cap are in Settings → Video.

## Main GPU costs (in order)

1. Procedural sky (nebula fbm + starfields + sun) — fullscreen fragment work.
   Reduced from 5 to 4 fbm octaves during optimisation; render-scale slider
   is the biggest lever on top of that.
2. MSAA at 5K (High uses 2×; Ultra 4×).
3. Glow/bloom chain (soft-dot particles, trails, sun corona feed it).
4. Asteroid MultiMeshes (~1300–2000 instances, chunked for frustum culling,
   auto-LOD from Godot's importer).

## Engineering choices that keep it fast

- Projectiles: 320-slot pooled raycast bullets — zero physics bodies.
- Asteroids: visual MultiMesh chunks + a 26-collider pool that follows the
  player; distant rocks never touch the physics server.
- Explosions capped at 24 concurrent; debris lifetime scales with preset.
- Enemy AI decision tick at 5 Hz (steering stays per-frame); aim refresh
  gated by skill-based reaction time.
- Engine trails are single ImmediateMesh strips (≤ 60 points), no particles.
- One shared soft-dot texture for all additive particles (one material per
  colour, cached).

## v1.1 polish-pass update
- The procedural sky is now BAKED to a 2048×1024 HDR panorama once per
  mission (SubViewport + sky_bake.gdshader) — sky cost dropped from per-pixel
  fbm every frame to one texture fetch. Measured: GPU ~26 ms → ~20-24 ms in
  combat with MORE content on screen (burning wrecks, fire particles, v2
  ships). Noticeably lower sustained GPU load = less fan/heat.
- New content per frame: burning wrecks (15 s lifetime, capped fire emitters
  at 30 fps sim), death spirals, secondary explosion bursts, missile flame
  trails. All pooled/capped; 60 fps vsync held in soak tests.
