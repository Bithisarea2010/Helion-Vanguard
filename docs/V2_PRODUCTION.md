# Helion Vanguard V2 Beta production record

Branch: `codex/helion-v2-beta`, based on `ed82472`. Existing checkout was clean before work.
Engine verified locally: Godot 4.7.2.stable.official.ed1daf0bf, Metal Forward+, Apple M1.

## Contract

Fight Mode retains `Battle.tscn`, its eight ships, ten missions, weapons, directional shields,
AI, cameras and combat UI. Explore Mode lives in `Explore.tscn` and uses a separate flight
controller. Shared assets, settings, input bindings, scene transitions and audio remain in
the existing architecture. Combat save data must remain compatible.

The development version string is not a statement that the V2 Beta acceptance target is
complete. Each feature needs a reproducible runtime gate before it is accepted.

## Spatial model

- `PlanetDefinition`: SI units and deterministic seeds; Elysian and Selene are resources.
- Elysian has a deliberately compact 60,000 m radius, Selene 12,000 m. This is a scale
  decision for the vertical slice, not a claim of Earth-sized simulation.
- `OriginFrame` keeps absolute positions in three float64 scalars, with bounded Vector3
  differences for physics/rendering. Rebase translation leaves velocity and orientation intact.
- Terrain is a cube-sphere quadtree with continuous 3D noise across face boundaries.
  Each worker owns its sampler and packed numerical arrays. GPU meshes and collision shapes
  are created on the main thread. Parent coverage remains until all four children are ready.
- Ship interiors use the ship's local coordinate frame. An astronaut crossing the airlock
  changes parent with the global transform preserved; it remains in the same scene.
- Collision bits: 1 spacecraft, 2 terrain (existing world layer), 4 astronaut,
  16 ship-interior collision. Cabin geometry cannot collide with its parent spacecraft.

## Verification

Existing baseline after a fresh import: `[TEST] pass=240 fail=0`.
The initial no-import attempt failed because `.godot`'s generated class cache was absent;
it is not accepted baseline evidence. A concurrent-game benchmark was also discarded.

`tests/ExploreMath.tscn` exercises numerical invariants, seam continuity, reproducibility,
atmosphere, gravity and re-entry heat. `tests/ExploreProbe.tscn` drives actual Godot input
through orbit, descent, landing, interior, airlock, on-foot, boarding, takeoff and return.
Its screenshots deliberately stall readback; its frame times must not be sold as clean
performance measurements. Separate runs without screenshots are required for profiling.

The installed NPGameDev Godot MCP Toolkit is the active editor/runtime bridge. The
machine's exposed Jungle Godot group currently targets a different bridge, so the existing
installed Toolkit npm package is used through its MCP SDK client; no competing addon was
installed. Editor inspection, parser checks, playtest launch and runtime screenshot capture
have succeeded through that Toolkit. Only one editor and one runtime may register this
project at a time. A separate headless import editor overwrites/deregisters the shared
project registry, so use editor refresh or stop/restart the editor around CLI imports.

## Extension policy

No new production extension is required for the current native terrain/instancing path.
Terrain3D remains unaccepted until an isolated Godot 4.7.2 compatibility test. Voxel Tools
is reserved for a future bounded cave/destruction region. ProtonScatter is optional because
the current vegetation integration can use MultiMesh directly. No compatibility or license
claim is made for an extension that has not been inspected and tested.

Threading/reference-frame design references:
[Godot thread-safe APIs](https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html),
[Godot large world coordinates](https://docs.godotengine.org/en/4.3/tutorials/physics/large_world_coordinates.html).
The local 4.7.2 engine's parser and runtime are the compatibility gate.

## Acceptance remaining

Track visual polish and missing behavior explicitly: forest/ground cover, desert/polar
presentation, cloud penetration and shadows, weather, water depth/shoreline behavior,
re-entry VFX, cinematic direction, survey/photography persistence, meaningful optional
hostility, exploration audio, UI refinement and the final M1 profile. A visible moon alone
does not prove a playable moon expedition. No public release or publication is part of
this local implementation task.
