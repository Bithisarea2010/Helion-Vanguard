# Helion Vanguard — Codex and Astra operating contract

## Project identity

- Engine: Godot `4.7.2.stable`, Forward+ renderer, macOS/Apple Silicon target.
- Main scene: `res://scenes/Boot.tscn`.
- Source layout: `scripts/`, `scenes/`, `shaders/`, `assets/`, and procedural Blender sources in `blender_src/`.
- The game is an original, premium-quality third-person space-combat project. Preserve its readable, colourful combat identity while raising quality.

## MCP setup

1. Open this exact project in Godot 4.7.2. The checked-in `Godot MCP Toolkit` add-on must be enabled; its **MCP** dock should report a local listening port and a connected peer before editor-tool claims are made.
2. For Godot work, use the lean `jungle-godot` MCP group. Discover only the domain groups needed for the immediate change (maximum five).
3. For Blender-only work, use `jungle-blender`. For a Blender-to-Godot asset handoff, complete and document the Blender export before importing or wiring it in Godot.
4. Do not use a broad, competing MCP set merely because it is available. Prefer the smallest tool surface that proves the result.

## Non-negotiable workflow

1. Inspect the target scene, nodes, scripts, settings, assets, and current Git diff before an edit. Never invent scene-node paths.
2. Make one coherent, reversible change at a time. Do not rewrite unrelated systems or overwrite user work.
3. After GDScript/shader/scene edits, refresh or validate imports and read the editor/debugger output. Resolve newly introduced errors before continuing.
4. For player-visible work, run a real windowed playtest and capture a runtime or editor screenshot. Headless validation alone cannot prove visual quality.
5. For regressions, run the appropriate deterministic suite or a scoped harness. Use the project's documented commands in `docs/BUILD.md`.
6. Report evidence, not intention: changed paths, validation command and exit status, console result, test output, visual-capture path, and any remaining limitation.

## Codex and Astra coordination

- **Astra owns an active implementation slice.** Codex must not edit the same `.gd`, `.tscn`, `.gdshader`, `.blend`, import setting, or asset while Astra is working on it.
- **Codex is the integration, audit, and verification counterpart** unless a handoff explicitly assigns it an isolated implementation slice. It should review Astra's diff, run independent regression/performance checks, inspect third-party license/provenance, and fix only agreed, non-overlapping defects.
- Hand off Blender work sequentially: Blender source and export first; Godot import, material setup, scene integration, and runtime verification second.
- Use Git status and the handoff ledger before taking ownership. Do not discard, reset, checkout over, rebase, force-push, or clean another agent's work.
- No paid purchase, account login, publishing, telemetry upload, or private-project upload without the user's explicit approval. Free third-party assets/plugins require compatible licenses and a provenance entry.

## Quality and acceptance gates

- Quality beats superficial scope. A change should improve readability, visual cohesion, responsiveness, performance, stability, or player satisfaction in an observable way.
- Preserve quality scalability. High-end visuals must have sensible graphics settings rather than making the game attractive only at one device configuration.
- Check both gameplay behavior and presentation for any combat, camera, effects, UI, animation, lighting, shader, or asset change.
- New external assets and plugins require source URL, license, author/publisher where available, and in-project use documented in `LICENSES.md` or `assets/manifest.json`.

## Useful verification paths

```sh
# Import/rebuild Godot resource metadata after source or asset changes.
/Applications/További programok Boldi/Fejlesztés/Godot.app/Contents/MacOS/Godot \
  --headless --path . --import

# Deterministic runtime regression suite.
/Applications/További programok Boldi/Fejlesztés/Godot.app/Contents/MacOS/Godot \
  --headless --path . tests/RegressionSuite.tscn

# Real gameplay visual/performance harness; use a fresh, explicitly named shot folder.
/Applications/További programok Boldi/Fejlesztés/Godot.app/Contents/MacOS/Godot \
  --path . --resolution 1280x720 -- --mission=instant_action --autotest \
  --defaults --windowed --uncapped --nocamcycle --shotdir=/absolute/output/path --quitafter=18
```

Do not assert that a test, build, editor connection, or visual improvement succeeded until its corresponding tool result exists.
