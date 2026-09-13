# Helion Vanguard quality production — 13 September 2026

Authoritative root: `Desktop/Codex Workspace/05_SHARED_PROJECTS/Games/HelionVanguard`.
Working branch: `codex/quality-production-2026-09-13`.
Initial source: `52d1322`; existing local tooling checkpoint: `891f267`.

The user's current instruction assigns this task full implementation ownership.
The prior handoff ledger contains a template but no active implementation slice.
Existing local MCP setup is preserved in the checkpoint. No remote upload occurs.

## Baseline

- Godot 4.7.2 official, Metal Forward+, Apple M1, 8 GB memory.
- Blender 5.2.0 LTS installed; Blender MCP unavailable because Blender is closed.
- Lean Godot MCP 0.6.0 is reachable but has no editor connection. The project
  instead contains NPGameDev Toolkit 1.0.0. Use the installed engine CLI and
  real windowed tests while retaining this setup.
- Existing deterministic regression suite: **182 passed, 0 failed**.
- Initial import exits 0 but toolkit registry emits a macOS PID-query error.
- Live Instant Action reaches wave two with no gameplay script errors.
- Initial `before/instant_action_*.png` are 2880×1800 despite `--windowed`:
  video settings raced the initial macOS fullscreen transition. Original FPS
  counters used engine delta and are unsuitable for before/after comparison.

## Ranked production priorities

1. Correct launch/test isolation and window sizing; measure actual wall time.
2. Combat interface: bounded text, contrast, target information away from aim,
   meaningful kill/damage feedback and readable, remapping-aware guidance.
3. Authored belt landmarks and practical navigation geometry, supported by a
   more restrained sky that leaves ships and threats readable.
4. Pacing and repeat play: faster optional transitions, survival sustain,
   safe training behavior, tactile flight and accessible presentation settings.
5. Audio mixing and performance verification, release packaging and evidence.

Evidence lives under `docs/evidence/quality-2026-09-13/`. Captures are excluded
from Godot import and exports. Keep one baseline, one final set and one current
build. Git commits provide recovery without duplicating the entire project.

## Final status

Quality production is implemented as version 1.3.0. The full changes, provenance,
limits, measurements and run instructions are in `QUALITY_REPORT.md`.
Final regression: 240/0; rendered integration: 63/0; packaged resource checks:
eight true; direct capture-free app combat completed. The cold Ultra loading
fault was fixed with bounded initialization grace; first-use pipeline hitches
remain recorded. Old build 1.2.3 and redundant captures were removed after the
replacement passed its gates (347.1 MiB allocated output removed).
