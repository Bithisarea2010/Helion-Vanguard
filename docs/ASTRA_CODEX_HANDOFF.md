# Astra ↔ Codex handoff ledger

This file is the compact coordination record for quality work on Helion Vanguard. It prevents two capable agents from silently overwriting each other and makes verification reproducible.

## Ownership rule

Only one agent may own a specific scene, script, shader, Blender file, imported asset, or project-setting slice at a time.

| Phase | Owner | Required handoff evidence |
| --- | --- | --- |
| Baseline and quality audit | Astra | Current branch/commit, Git status, observed strengths/weaknesses, baseline screenshots, known errors, and representative performance notes. |
| Asset or Blender creation | Astra | Source `.blend` path, exported asset path, import assumptions, source URL/license if external, and a screenshot of the asset. |
| Godot integration | Astra | Changed resource/scene/script paths, import result, scene inspection, and playtest screenshot. |
| Independent integration review | Codex | Diff review, non-overlap check, regression command/output, screenshot inspection, and license/provenance review. |
| Defect correction | Assigned explicitly | Root cause, exact files owned, fix evidence, and regression result. |
| Final release-quality gate | Codex with Astra evidence | Clean or explicitly listed console state, deterministic suite result, live combat harness evidence, performance comparison, and unresolved-risk list. |

## Handoff template

Copy this block into a task message or append it below for each substantial slice:

```text
SLICE: <short name>
OWNER: Astra | Codex
STATUS: planned | active | ready-for-review | accepted | blocked
FILES OWNED: <exact paths>
PLAYER-VISIBLE GOAL: <one sentence>
BASELINE: <screenshots / test command / performance data>
CHANGES: <concise summary>
VALIDATION: <commands, exit codes, test output, editor or runtime logs>
VISUAL EVIDENCE: <absolute screenshot paths>
ASSET PROVENANCE: <none, or source + license + intended use>
REMAINING RISKS: <specific items, or none known>
NEXT OWNER: <agent and exact next action>
```

## Baseline commands

Run from the repository root. Keep output folders separate from tracked project assets.

```sh
GODOT='/Applications/További programok Boldi/Fejlesztés/Godot.app/Contents/MacOS/Godot'

"$GODOT" --headless --path . --import
"$GODOT" --headless --path . tests/RegressionSuite.tscn
"$GODOT" --path . --resolution 1280x720 -- --mission=instant_action --autotest \
  --defaults --windowed --uncapped --nocamcycle --shotdir=/absolute/output/path --quitafter=18
```

## Review stop conditions

- Do not merge or overwrite an active owner’s files.
- Do not accept visual work without a real screenshot or runtime capture.
- Do not accept code work without a relevant import/parse/test result.
- Do not accept an external asset or plugin without license and provenance information.
- Do not mark the work complete if warnings, errors, performance regressions, broken controls, missing files, or untested visual claims remain unexplained.
