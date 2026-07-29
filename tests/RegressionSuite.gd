extends Node3D
## Fast, deterministic checks for settings migration, quality presets, damage,
## projectile pooling and repeatable surface-hit behaviour.

class BattleStub:
	extends Node3D
	var hostile_list: Array = []
	var friendly_list: Array = []
	func hostile_targets() -> Array:
		return hostile_list
	func friendly_targets() -> Array:
		return friendly_list

var _passed := 0
var _failed := 0

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("[TEST] FAIL: %s" % label)

func _near(actual: float, expected: float, epsilon := 0.01) -> bool:
	return absf(actual - expected) <= epsilon

func _ready() -> void:
	await get_tree().process_frame
	_test_presets()
	_test_settings_validation()
	_test_save_validation()
	_test_lead_solution()
	_test_damage_model()
	_test_capital_shield()
	await _test_projectile_pool_and_hit()
	await _test_repeatable_surfaces()
	await _test_missile_single_damage()
	await _test_settings_panel()
	print("[TEST] pass=%d fail=%d" % [_passed, _failed])
	Game.prepare_shutdown()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _failed == 0 else 1)

func _test_presets() -> void:
	_check(Game.PRESET_NAMES.size() == 4, "four named quality presets")
	_check(Game.PRESETS.size() == 4, "four quality definitions")
	var required := ["msaa", "screen_aa", "taa", "glow", "glow_quality",
		"shadows", "shadow_size", "shadow_distance", "ast_density",
		"particles", "debris", "sky_size", "planet_segments", "planet_rings"]
	for preset in Game.PRESETS:
		for key in required:
			_check(preset.has(key), "preset contains %s" % key)
	var high: Dictionary = Game.PRESETS[2]
	var ultra: Dictionary = Game.PRESETS[3]
	_check(int(ultra.msaa) > int(high.msaa), "Ultra increases MSAA")
	_check(bool(ultra.taa), "Ultra enables TAA")
	_check(int(ultra.shadow_size) > int(high.shadow_size), "Ultra increases shadow resolution")
	_check(float(ultra.shadow_distance) > float(high.shadow_distance), "Ultra extends shadow range")
	_check(float(ultra.ast_density) > float(high.ast_density), "Ultra increases asteroid density")
	_check(float(ultra.particles) > float(high.particles), "Ultra increases particle density")
	_check(int(ultra.planet_segments) > int(high.planet_segments), "Ultra increases planet geometry")
	var original := Game.settings.duplicate(true)
	Game.settings.preset = 3
	Game.settings.resolution_scale = 1.5
	Game.settings.scaling_mode = 3
	Game.apply_preset()
	Game.apply_video_settings()
	var viewport := get_viewport()
	_check(viewport.msaa_3d == Viewport.MSAA_4X, "Ultra applies 4x MSAA to viewport")
	_check(viewport.use_taa, "Ultra applies TAA to viewport")
	_check(viewport.anisotropic_filtering_level == Viewport.ANISOTROPY_16X,
		"Ultra applies 16x anisotropy")
	_check(_near(viewport.scaling_3d_scale, 1.5), "150 percent render scale reaches viewport")
	_check(viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR,
		"supersampling bypasses temporal upscaler")
	Game.settings = original
	Game.apply_preset()
	Game.apply_video_settings()

func _test_settings_validation() -> void:
	var original := Game.settings.duplicate(true)
	Game.settings = {
		"display_mode": 99, "display_screen": -8, "window_size": Vector2i(40, 50),
		"resolution_scale": 9.0, "scaling_mode": -4, "vsync_mode": 40,
		"fps_limit": -3, "preset": 19, "mouse_sens": -2.0,
		"control_smoothing": 7.0, "invert_y": false, "aim_assist": true,
		"camera_shake": 9.0, "cam_distance": 20.0,
		"vol_master": -4.0, "vol_music": 4.0, "vol_sfx": 0.5, "vol_ui": 0.5,
		"difficulty": 8, "momentum_mode": false,
		"bindings": {
			"fire_primary": [
				{"t": "mouse", "b": 1},
				{"t": "jaxis", "a": 1, "v": -8.0},
				{"t": "mouse", "b": 99},
				{"bad": true},
			],
			"not_an_action": [{"t": "key", "c": KEY_Z}],
		},
	}
	Game._normalize_settings()
	_check(Game.settings.display_mode == Game.DisplayMode.EXCLUSIVE, "display mode clamps")
	_check(Game.settings.window_size == Vector2i(960, 540), "window size clamps")
	_check(_near(Game.settings.resolution_scale, 2.0), "render scale clamps to 200 percent")
	_check(Game.settings.preset == 3, "quality preset clamps to Ultra")
	_check(Game.settings.fps_limit == 0, "negative fps cap becomes uncapped")
	_check(_near(Game.settings.vol_master, 0.0), "master volume clamps low")
	_check(_near(Game.settings.vol_music, 1.0), "music volume clamps high")
	_check(not Game.settings.bindings.has("not_an_action"), "unknown input action removed")
	_check(Game.settings.bindings.fire_primary.size() == 2, "malformed bindings removed")
	_check(_near(Game.settings.bindings.fire_primary[1].v, -1.0), "axis direction normalized")
	Game.settings = original
	Game._normalize_settings()

func _test_save_validation() -> void:
	var original := Game.save.duplicate(true)
	Game.save = {
		"selected_ship": "missing", "unlocked_ships": ["missing"],
		"credits": -900, "missions_done": {"missing": 1},
		"loadouts": {"missing": []}, "training_done": false,
	}
	Game._normalize_save()
	_check(Game.save.selected_ship == "vanguard", "invalid selected ship repaired")
	_check("vanguard" in Game.save.unlocked_ships, "Vanguard always unlocked")
	_check(Game.save.credits == 0, "negative credits repaired")
	_check(Game.save.missions_done.is_empty(), "invalid mission records removed")
	_check(Game.save.loadouts.is_empty(), "invalid loadouts removed")
	Game.save = original
	Game._normalize_save()
	var fallback := Game.loadout_for("not_a_ship")
	_check(ShipDB.WEAPONS.has(fallback.primary), "invalid ship gets valid primary")
	_check(ShipDB.MISSILES.has(fallback.missile), "invalid ship gets valid missile")

func _test_lead_solution() -> void:
	var stationary := Projectiles.lead_point(Vector3.ZERO, Vector3.ZERO,
		Vector3(0, 0, -100), Vector3.ZERO, Vector3.ZERO, 100.0)
	_check(stationary.is_finite(), "stationary lead is finite")
	_check(stationary.is_equal_approx(Vector3(0, 0, -100)), "stationary lead stays on target")
	var crossing := Projectiles.lead_point(Vector3.ZERO, Vector3.ZERO,
		Vector3(0, 0, -100), Vector3(20, 0, 0), Vector3.ZERO, 100.0)
	_check(crossing.x > 0.0, "crossing lead aims ahead")
	var zero_speed := Projectiles.lead_point(Vector3.ZERO, Vector3.ZERO,
		Vector3(0, 0, -10), Vector3.ZERO, Vector3.ZERO, 0.0)
	_check(zero_speed.is_finite(), "zero projectile speed cannot create NaN")

func _test_damage_model() -> void:
	var c := Combatant.new()
	add_child(c)
	c.freeze = true
	c.combat_setup(100.0, 25.0, 0.0, 0.0)
	c.take_hit(40.0, Vector3(0, 0, -1), Vector3(0, 0, -1))
	_check(_near(c.shield_front, 0.0), "front shield absorbs available damage")
	_check(_near(c.hull, 85.0), "shield overflow reaches hull")
	var before := c.hull
	c.take_hit(NAN, Vector3.ZERO, Vector3.ZERO)
	c.take_hit(-20.0, Vector3.ZERO, Vector3.ZERO)
	_check(_near(c.hull, before), "invalid damage is ignored")
	c.hull_max = 0.0
	_check(c.hull_frac() >= 0.0 and c.hull_frac() <= 1.0, "zero hull max stays finite")
	c.queue_free()

func _test_capital_shield() -> void:
	var cap := CapitalShip.new()
	add_child(cap)
	cap.shield_pool_max = 20.0
	cap.shield_pool = 20.0
	cap.shieldgens_alive = 1
	var overflow := cap.absorb_with_shield(100.0, Vector3.ZERO, 2.0)
	_check(_near(overflow, 90.0), "capital shield multiplier preserves base-damage overflow")
	_check(_near(cap.shield_pool, 0.0), "capital shield pool depletes exactly")
	var attacker := Node3D.new()
	attacker.add_to_group("player")
	add_child(attacker)
	var sub := Subsystem.new()
	add_child(sub)
	cap.shield_pool = 20.0
	sub.setup("reactor", 100.0, cap, "Reactor")
	sub.take_hit(100.0, Vector3.ZERO, Vector3.FORWARD, 0.2, 2.0, 1.0, attacker)
	_check(_near(sub.hp, 10.0), "subsystem receives correct shield overflow")
	_check(sub.last_attacker == attacker, "subsystem retains kill attribution")
	cap.queue_free()
	attacker.queue_free()
	sub.queue_free()

func _test_projectile_pool_and_hit() -> void:
	var pm := Projectiles.new()
	add_child(pm)
	var shooter := Combatant.new()
	shooter.team = Combatant.TEAM_FRIEND
	shooter.freeze = true
	add_child(shooter)
	var target := Combatant.new()
	target.team = Combatant.TEAM_HOSTILE
	target.freeze = true
	target.combat_setup(100.0, 0.0, 0.0, 0.0)
	target.position = Vector3(0, 0, -5)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	target.add_child(shape)
	add_child(target)
	await get_tree().physics_frame
	var weapon := {
		"spread": 0.0, "speed": 600.0, "range": 100.0, "size": 1.0,
		"color": Color.WHITE, "dmg": 20.0, "pen": 1.0, "sh": 1.0, "hu": 1.0,
	}
	_check(not pm.fire_bullet(shooter, Vector3.ZERO, Vector3.ZERO, weapon, 0, Vector3.ZERO),
		"zero-direction projectile rejected")
	_check(pm.fire_bullet(shooter, Vector3.ZERO, Vector3(0, 0, -1), weapon, 0, Vector3.ZERO),
		"valid projectile enters pool")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(target.hull < 100.0, "projectile ray reaches target")
	_check(pm._active.is_empty(), "hit projectile removed without index overrun")
	_check(pm._free_pool.size() == Projectiles.POOL, "hit projectile slot returned to pool")

func _test_repeatable_surfaces() -> void:
	var field := AsteroidField.new()
	add_child(field)
	await get_tree().process_frame
	var rock := field._phys[0] as AsteroidBody
	rock.position = Vector3.ZERO
	rock.take_hit(12.0, Vector3(0, 0, -1), Vector3(0, 0, 1))
	rock.take_hit(12.0, Vector3(0, 0, -1), Vector3(0, 0, 1))
	_check(rock.alive, "repeated asteroid hits never destroy the rock")
	_check(rock.is_in_group("reactive_surface"), "asteroid is a reactive surface")
	var wreck := Wreck.new()
	add_child(wreck)
	wreck.freeze = true
	wreck.take_hit(20.0, Vector3(0, 0, -1), Vector3(0, 0, 1))
	wreck.take_hit(20.0, Vector3(0, 0, -1), Vector3(0, 0, 1))
	_check(is_instance_valid(wreck), "repeated wreck hits do not break the hulk")
	_check(wreck._hit_glow > 0.0, "repeated wreck hits reignite visible glow")

func _test_missile_single_damage() -> void:
	var battle := BattleStub.new()
	add_child(battle)
	var target := Combatant.new()
	target.team = Combatant.TEAM_HOSTILE
	target.freeze = true
	target.combat_setup(200.0, 0.0, 0.0, 0.0)
	battle.add_child(target)
	battle.hostile_list = [target]
	var missile := Missile.new()
	missile.mdef = {"dmg": 100.0}
	missile.team = Combatant.TEAM_FRIEND
	missile._battle = battle
	missile.target = target
	missile._armed = true
	battle.add_child(missile)
	missile._detonate(true)
	_check(_near(target.hull, 100.0), "direct missile target is not damaged again by splash")
	await get_tree().process_frame

func _test_settings_panel() -> void:
	var panel := SettingsPanel.new()
	add_child(panel)
	await get_tree().process_frame
	_check(panel.is_in_group("settings_panel"), "settings panel registers for pause routing")
	_check(panel._available_window_sizes().has(Vector2i(5120, 2880)), "5K output choice exists")
	_check(panel._available_window_sizes().has(Vector2i(7680, 4320)), "8K output choice exists")
	_check(SettingsPanel.QUALITY_SUMMARIES[3].find("4× MSAA + TAA") >= 0,
		"settings explains the real Ultra profile")
	panel.queue_free()
