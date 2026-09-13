# Helion Vanguard 1.3.0 — Astra production release

Published 13 September 2026.

Version 1.3.0 is the quality-production update for Helion Vanguard. It keeps
the existing space-combat identity and all ten game modes while making the
game more readable, responsive and authored in motion.

## Release highlights

- Eight selectable playable ships, including the rebuilt SF-7 Vanguard and the
  new SF-12 Peregrine and SA-14 Aegis.
- Relay 07, a modeled navigable objective with physical collision, a scored
  fly-through path and clear encounter-space placement.
- A revised combat HUD, short input-aware flight hints, kill confirmation and
  settings for HUD scale, flash intensity, FOV motion, camera shake and
  transition pacing.
- A new original combat-feedback palette: weapon families, shield and armor
  impacts, relay transit, resupply feedback and a layered flight-deck ambience
  mix.
- Improved encounter sustain, training behavior, target cleanup, pause/photo
  behavior, scene-transition safety and macOS window-mode reliability.

The full implementation, performance measurements, known limits and visual
evidence are in [QUALITY_REPORT.md](QUALITY_REPORT.md). The playable controls
and build steps are in [CONTROLS_FEATURES.md](CONTROLS_FEATURES.md) and
[BUILD.md](BUILD.md).

## macOS download

The GitHub release includes `Helion-Vanguard-macOS-v1.3.0.zip`, an Apple
Silicon macOS 13+ build made with Godot 4.7.2. The application is locally
ad-hoc signed, not notarized; see the build document for the normal macOS
first-launch procedure.

SHA-256:

```text
e504372ca582d687213d5fd24fb01d175d24da2cfd2f2a269ada19e39cef849a
```

## Validation

- Godot 4.7.2 headless deterministic regression suite: **240 passed, 0
  failed** after the final source merge.
- Rendered Metal integration suite recorded in the production evidence:
  **63 passed, 0 failed**.
- The packaged Apple Silicon app was rebuilt for this release. Package-content
  inspection confirms the 1.3.0 version, all eight ships, new hulls, relay and
  audio assets, while excluding the editor MCP add-on and local MCP settings.

## Production history and provenance

At the project owner's request, the repository records the AI-assisted
production sequence: Fable 5, GPT-5.6 Sol, Opus 5 and Astra for version 1.3.0.
The exact credit and ownership statement is in
[AI_PRODUCTION_CREDITS.md](AI_PRODUCTION_CREDITS.md).

No third-party asset or plugin was added during the 1.3.0 production pass.
All third-party sources and licenses already present in the project, including
the project-owner-supplied playlist disclosure, remain listed in
[LICENSES.md](../LICENSES.md).
