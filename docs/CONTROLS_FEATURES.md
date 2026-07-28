# Helion Vanguard — Tested Controls & Features Report

Testing method: headless boots of every mission (script-error sweep),
windowed live runs with screenshot verification, and long `--autotest`
combat-bot soak runs (the bot flies, aims with the real lead solver, fires
guns/missiles and pops flares through the actual input actions).

## Controls (default bindings) — status

| Control | Binding | Status |
|---|---|---|
| Aim (pitch/yaw) | Mouse / trackpad, captured in battle | ✅ verified (bot + live) |
| Thrust / brake | W / S | ✅ verified |
| Strafe | A / D | ✅ verified |
| Roll | Q / E | ✅ verified |
| Vertical | Space / LCtrl | ✅ verified |
| Boost | LShift | ✅ verified (energy drain + FOV kick + audio) |
| Primary fire | LMB | ✅ verified (tracers, heat, energy, hits) |
| Missile | RMB | ✅ verified (lock ring, launch, PN guidance) |
| Cycle target / crosshair target | R / T | ✅ verified |
| Match velocity | X | ✅ implemented, exercised in live run |
| Countermeasures | G | ✅ verified (flares spoof seekers) |
| Weapon group | V | ✅ verified (A / B / linked) |
| Camera cycle | C | ✅ verified (chase/cockpit/orbit/cinematic) |
| Tactical map | B | ✅ verified |
| Flight assist toggle | M | ✅ implemented |
| Photo mode | P | ✅ implemented (pauses world, free-fly) |
| Pause | Esc | ✅ verified incl. unpause while tree paused |
| Gamepad | sticks/triggers/buttons | ✅ mapped (not hardware-tested — no pad on build machine) |
| Full remapping | Settings → Controls | ✅ implemented, persists |

## Mouse capture & fullscreen (macOS-specific care)

- Mouse is captured **only during active flight**; released automatically on
  pause, debrief, menus, and on application focus loss (which also
  auto-pauses). Clicking the window recaptures.
- Esc never leaves you stuck: it exits photo mode → closes tactical map →
  toggles the pause menu, in that priority.
- Fullscreen/windowed switch applies live from Settings → Video and
  persists; windowed mode offers 720p–1440p sizes and re-centres the window.
- UI scales with the window (canvas-items stretch, 1920×1080 design space),
  so HUD/menus stay readable at Retina 5K and small windows alike.

## Features verified in test runs

- Mission flow: title card → objectives → radio comms → staged director →
  victory/failure debrief with score, kills, accuracy, time.
- Instant Action reaches combat in < 10 s from click.
- Enemy AI: pursuit, attack runs, break-off, evasion under fire, flare use,
  missile shots, asteroid avoidance, attack-token group coordination,
  retreat when crippled — observed in soak runs.
- Capitals: corvette with destructible engine pods + turrets; Bastion base
  with shield-generator gating, radar/launcher/hangar/command subsystems and
  reactor kill; staged death explosions.
- Shields are directional (front/rear), regenerate after delay; armor uses
  impact angle + weapon penetration; ricochet-style damage reduction.
- 8 primary weapons, 5 missile types, flares; heat/overheat and energy
  systems; ammo for ballistic guns.
- Radar disc with elevation ticks + fullscreen tactical map; off-screen
  arrows; mathematical lead indicator (quadratic intercept solver, refined
  with target acceleration estimate).
- Environments: procedural nebula sky, planets/moons, sun with halo,
  1300–2000-rock asteroid belts (MultiMesh chunks + physics pool).
- Audio: 40 synthesised SFX + 2 music loops; engine loop follows throttle;
  bus mixer (Master/Music/SFX/UI) with sliders.
- Settings persist across launches (`user://settings.cfg` in
  `~/Library/Application Support/HelionVanguard/`).
- Save/progression: mission best scores, ship unlocks, per-ship loadouts.
