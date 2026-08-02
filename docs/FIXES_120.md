# Helion Vanguard 1.1 — 120-item defect and optimisation ledger

This is the requested finite audit ledger, not a generated warning count. Each
entry identifies one reproducible failure, robustness gap, misleading control,
or avoidable hot path that was changed in this pass. Verification is recorded
at the end.

## Display, persistence, and validation

1. The engine clamped saved 3D render scale to 100%, preventing supersampling; the supported range is now 50–200%.
2. The Video slider itself stopped at 100%, independently preventing any higher internal resolution; it now reaches 200%.
3. The `--renderscale` harness path also capped high-resolution tests at 100%; it now accepts the same 200% ceiling.
4. Window choices stopped at 2560×1440; standard 4K, DCI 4K, 5K, 6K, and 8K modes are now offered.
5. A monitor's native mode could be absent from the hard-coded list; detected native modes are now inserted dynamically.
6. The Window resolution selector always opened on a fixed item rather than the saved size; it now reflects the persisted value.
7. Changing window size changed only the live window and was lost after restart; `window_size` is now stored.
8. Startup forced fullscreen and overrode a user's window selection; the saved display mode is now authoritative.
9. “Fullscreen” conflated macOS borderless and exclusive modes; Windowed, Borderless, and Exclusive are separate settings.
10. Multi-monitor users could not choose an output screen; a validated display selector now moves the window/fullscreen output.
11. Old `fullscreen` saves would lose their meaning under the new enum; they are migrated to the matching display mode.
12. Old boolean `vsync` saves would be ignored by the new setting; they are migrated to the matching V-Sync mode.
13. V-Sync was only On/Off; Adaptive is now available and applied through `DisplayServer`.
14. Frame caps were limited to 60/120; 30, 90, 144, 165, and 240 are now selectable as well.
15. The 3D scaling filter was fixed and invisible to the user; Bilinear, FSR 1, FSR 2, and MetalFX Temporal are selectable.
16. Supersampling could be routed through a temporal upscaler intended for sub-native input; scales above 100% now use direct downsampling.
17. The panel gave no output-resolution feedback after a mode change; it now reports the live output dimensions.
18. The panel gave no internal-resolution feedback after a scale change; it now reports the calculated 3D buffer dimensions.
19. Corrupt display-mode values could index outside the mode list; they are clamped during load and before apply.
20. Corrupt display-screen values could address a missing monitor; they are clamped to connected screens.
21. A malformed persisted window-size type could reach window APIs; only `Vector2`/`Vector2i` values are accepted.
22. Absurd persisted window dimensions could create unusable windows; dimensions are constrained to 960×540–7680×4320.
23. Non-numeric or out-of-range render scales could reach the viewport; they now fall back and clamp safely.
24. Invalid scaling-mode values could index outside the renderer-mode table; they are validated to 0–3.
25. Invalid V-Sync values could index outside the DisplayServer mode table; they are validated to Off–Adaptive.
26. Negative or extreme frame caps could be applied; caps are constrained to Uncapped–500 FPS.
27. Invalid quality-preset values could index outside `PRESETS`; they are clamped to Low–Ultra.
28. Invalid sensitivity and smoothing values could destabilize input filtering; both are type-checked and range-clamped.
29. Invalid camera-shake and chase-distance values could create unusable views; both are range-clamped.
30. Invalid mixer values could exceed linear audio bounds; all four buses are clamped to 0–1.
31. Invalid difficulty values could select no balancing profile; difficulty is constrained to Easy–Hard.
32. A non-dictionary bindings value caused typed input setup to fail; malformed binding containers now become a safe empty override.
33. Unknown action names and non-dictionary binding records remained in saves; both are removed during normalization.
34. Invalid key, mouse, joy-button, joy-axis, and zero-direction axis records could reach InputMap; each record type is validated.
35. Repaired settings were not written back, causing the same migration on every launch; normalization now marks repaired data dirty.

## Quality preset and graphics correctness

36. Low had no post-process antialiasing, making it unnecessarily jagged; Low now uses FXAA.
37. Medium had no distinct antialiasing path; Medium now uses SMAA.
38. Presets stored only MSAA and could not control screen-space AA; `screen_aa` is now a consumed preset field.
39. Ultra did not enable temporal AA; Ultra now combines 4× MSAA with TAA.
40. Texture anisotropy did not scale with quality; presets now apply 4×, 8×, or 16× filtering.
41. High and Ultra used the same implicit directional-shadow atlas; High now uses 2K and Ultra 4K.
42. Shadow draw distance was not a preset field; High uses 350 m and Ultra 560 m.
43. Changing High↔Ultra did not update an existing sun's shadow state/range; the live environment now reapplies both.
44. Glow was only binary, so Ultra could not improve its response; presets now carry and apply glow intensity quality.
45. Every preset baked the same sky resolution; sky panoramas now range from 2048×1024 to 4096×2048.
46. Planet sphere detail was fixed regardless of preset; radial segments now scale from 48 to 128.
47. Planet ring geometry detail was fixed regardless of preset; ring segments now scale from 24 to 64.
48. Ultra's extra scene/effect density looked inert because the UI gave no summary; the panel now states AA, shadows, rocks, and particles.
49. Users were not told which quality changes require a scene reload; the panel now distinguishes live changes from mission-load density.
50. Quality changes made in the menu did not refresh its live environment; the menu listens for and applies preset updates.
51. Quality changes made while paused did not refresh the battle environment; Battle now reapplies environment settings live.
52. The hull replacement shader discarded imported albedo textures; texture presence and texture data now participate in material caching.
53. The canopy replacement path also discarded imported albedo textures; canopy materials now preserve and sample them.

## Menu, settings, HUD, input, and saves

54. The SettingsPanel full-screen root kept a zero-sized rect after changing anchors; anchors and offsets are now set together.
55. The settings dimmer inherited the same zero-rect failure; it now fills the viewport reliably.
56. The settings centering container collapsed to its child's minimum size; it now expands and centers the panel.
57. The MainMenu UI root could retain a zero rect, distorting fractional anchors; it now fills the design viewport.
58. The HUD root could retain a zero rect, breaking child layout at non-default sizes; it now fills the viewport.
59. Mission title cards could be positioned from a zero-sized center container; they now use full anchors and offsets.
60. Pause-menu roots could be zero-sized; pause overlays now fill the viewport.
61. Pause dimmers and center containers could size independently of the root; both now fill the corrected overlay.
62. Debrief roots could be zero-sized; mission results now fill the viewport.
63. Debrief dimmers and center containers inherited the same layout error; both now use full anchors and offsets.
64. The fixed 760×620 settings panel did not adapt to smaller viewports; its size is now bounded by available space.
65. Video, Audio, Gameplay, and Controls content could overflow horizontally; tabs now use vertical scrolling with horizontal scrolling disabled.
66. Bare label/control rows were difficult to scan over the game; rows now use bordered cards with title and description hierarchy.
67. Sliders did not show exact values, making settings impossible to reproduce; all important sliders now have live numeric labels.
68. There was no safe way to undo a bad video combination; “Restore Recommended Video” resets and reapplies the profile.
69. Gamepad axes could not be captured by the rebinding UI; axis movement past a deliberate threshold is now supported.
70. Esc cancellation checked only one keycode field; both physical and logical Escape are accepted.
71. Rebinding a keyboard input erased the action's gamepad binding (and vice versa); device-family bindings are now preserved.
72. Binding labels omitted joy buttons and axes; readable controller labels are now displayed.
73. The main menu rendered uncapped, wasting GPU/CPU while idle; it now caps itself to 60 FPS or the user's lower cap.
74. Entering a mission could retain the menu's temporary 60 FPS cap; Battle reapplies the user's video/frame settings.
75. The redesigned menu had no deterministic keyboard starting point; the first navigation button now receives focus.

## Repeatable impacts, damage, and physics

76. Pooled asteroid colliders had no `take_hit`, so shots could not address the actual rock proxy; `AsteroidBody` is now a receiver.
77. Asteroids had no neutral team identity, so generic team handling could misclassify them; reactive surfaces now use team `-1`.
78. Repeated asteroid shots produced only transient fallback sparks; rocks now receive dust, sparks, and bounded fading scars.
79. Continuous beams could create asteroid FX every physics tick; asteroid feedback is rate-limited without suppressing damage rays.
80. Fighter wrecks were non-colliding `Node3D` decorations; wrecks are now `RigidBody3D` objects.
81. Wreck drift was manually integrated outside the physics server; it now uses linear/angular velocity and damping.
82. Wrecks had no shape matching the detached model; a bounded box collider is derived from model AABBs.
83. Wrecks did not occupy a collision layer/mask; they now use layer 8 and interact with ships, rocks, capitals, and other wrecks.
84. Wrecks had no damage receiver; repeated shots now invoke a dedicated non-destructive hit path.
85. Wreck hits had no physical response; damage transfers a bounded linear/off-axis impulse.
86. Wreck hits had no persistent visual response; metal sparks and fading scorch decals are attached to the moving hulk.
87. Subsequent wreck hits could not revive its visual energy; hits now briefly reignite the ember light.
88. Destroyed capital models vanished after the staged blast; they now become shootable drifting hulks.
89. Non-shield hits on living ships used a generic flash only; they now receive surface sparks and scorch marks.
90. Impact marks had no global bound; live marks are capped at 56 and time out.
91. Muzzle flashes could create unlimited short-lived lights; concurrent muzzle lights are capped at 8 and distance-culled.
92. Projectile damage did not receive the raycast surface normal; exact normals now reach the armor and surface-FX paths.
93. Armor angle used an invented radial normal, producing wrong grazing-hit reduction; it now uses collision geometry.
94. Projectiles transferred no momentum to combatants; hits now apply a bounded impulse at the impact offset.
95. Unbounded impact offsets could create extreme torque; offsets are clamped before impulse application.
96. Player collision damage used relative speed alone; it now includes reduced mass.
97. Colliding with a light wreck could hurt like colliding with a massive hull; the reduced-mass model distinguishes them.
98. Collision damage could grow without an arcade-safe ceiling; it is bounded to 2–85 damage.
99. The player did not collide with layer-8 wrecks; the collision mask now includes them.
100. Dead-player collision shapes remained active briefly after death; death now disables collision layer and mask.

## Weapons, combat logic, and hot paths

101. Bullet allocation linearly scanned all 320 mesh slots per shot; allocation now pops from an O(1) free-index stack.
102. Expired/hit bullets did not have an explicit slot-return path; `_release_bullet` now returns every slot exactly once.
103. A saturated bullet pool still charged energy, heat, and ammo for invisible shots; capacity is checked before costs.
104. Removing a hit bullet failed to decrement the reverse-loop index, risking an out-of-range access; the index now advances correctly.
105. Zero or non-finite firing directions could create invalid projectile transforms; such shots are rejected.
106. Shield feedback was sampled after applying damage, so a shield-breaking hit could be reported as armor; state is sampled before damage.
107. Beam team lookup ignored subsystem ownership; beam hits now resolve the owner ship's team.
108. Beam impact construction ran at a high random rate independent of persistent marks; effects and marks now use bounded rates.
109. Missile guidance passed zero as missile velocity to lead prediction; it now uses the missile's actual velocity.
110. A missile hitting a friendly hull detonated and could damage nearby allies; friendly collisions are ignored and their RID is excluded.
111. An armed missile applied collision damage and then splash-damaged the same receiver again; the direct receiver is excluded from splash.
112. Missile splash ignored exposed capital subsystems and could duplicate candidates; it now includes hostile targets and deduplicates them.
113. Turrets could fire while their visual barrel was not aligned; barrel direction must now be within the firing cone.
114. Point defence had no reliable missile registry; missiles join a group and PD prioritizes hostile group members.
115. Turret line-of-sight rays could hit their own capital hull; owner RIDs are excluded and descendant target colliders are accepted.
116. Enemy obstacle avoidance cast a ray every physics frame per fighter; sensing is cached at roughly 12 Hz.
117. Engine trails rebuilt `ImmediateMesh` geometry at the render rate; rebuilds are capped at 60 Hz.
118. Particle simulation followed uncapped render frequency; effects use fixed 60 Hz and smoke/fire use 30 Hz with interpolation.
119. HUD, fighters, turrets, and missiles repeatedly rebuilt identical target arrays; Battle now shares an 80 ms target cache.
120. Abrupt quit retained active WAV playback/resources; audio players are stopped, streams released, caches cleared, and the harness allows an audio-server frame before exit.

## Verification

- Godot 4.7 editor/import parse: clean.
- Automated suite: `113 passed, 0 failed`.
- All nine mission IDs: clean headless smoke runs.
- Instant Action 12-second combat harness: stable at the same-session ~145 FPS headless ceiling, with no script errors or shutdown leaks.
- Deterministic settings and FX captures were rendered with the Metal Forward+ backend and visually inspected.
