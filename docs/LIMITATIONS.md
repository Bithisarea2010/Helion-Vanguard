# Helion Vanguard — Known Limitations (honest list)

This is a complete, playable vertical slice, not a shipped retail product.
The following limitations remain:

## Content & visuals
- Ship and station models are stylised procedural hard-surface builds.
  They read well in motion but are simpler than hand-sculpted AAA hero
  assets (no baked normal-map panel lines or decals).
- The ship-graveyard, jump-gate and mining-rig set pieces from the original
  wish list are not separate models; environments differentiate through
  layout, nebula palette, planets and asteroid density instead.
- Cockpit instruments show real data via the HUD overlay; the physical
  cockpit screens themselves are static emissive panels.
- Radio chatter is text + blip (no voice acting).
- Damage model: directional shields, per-hit armor/penetration math and
  destructible subsystems on capitals are implemented; fighters do not shed
  visible hull pieces (they emit damage smoke/fire and explode in stages).

## Systems
- Repair drone, decoy drone and ECM from the wish list are not implemented
  (flares, chaff-resistance stats and point-defence turrets are).
- Gamepad is supported with a fixed default layout; remapping UI captures
  keyboard/mouse rebinds (gamepad rebinding accepts button presses too,
  but axes cannot be rebound from the UI).
- The tactical map is a live situational display, not an interactive
  order-issuing map.
- Photo mode is free-fly + game pause; it has no filter/DoF options.

## Platform
- The app is **ad-hoc signed**, not notarised (no Developer ID certificate
  was available on the build machine). It launches normally when copied
  locally; downloaded copies may need right-click → Open once.
- Universal (Intel + Apple Silicon) binary comes from the official Godot
  export template; performance was profiled on Apple Silicon (M1) only.
- Godot 4.7 on macOS renders via Metal (Forward+); no MetalFX upscaling —
  the render-scale slider uses bilinear scaling.

## Performance
- On a base M1 at 5K fullscreen with the High preset, gameplay holds the
  60 fps vsync cap in typical fights (GPU ≈ 24 ms); heavy multi-capital
  scenes can dip. Use Medium or a lower render scale on older Intel Macs.
- Asteroid fields are visual MultiMeshes + a pooled ring of physics
  colliders around the player. Rocks farther than ~700 m are not
  physically collidable (AI avoidance uses the same colliders).
