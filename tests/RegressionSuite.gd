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
	_test_background_music_playlist()
	_test_save_validation()
	_test_lead_solution()
	_test_damage_model()
	_test_capital_shield()
	await _test_projectile_pool_and_hit()
	await _test_repeatable_surfaces()
	await _test_missile_single_damage()
	await _test_settings_panel()
	_test_capability_gate()
	_test_extended_arsenal()
	await _test_shield_matrix()
	_test_targeting_servo()
	await _test_quality_regressions()
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
	_check(Game.settings.music_enabled, "music toggle defaults on when absent")
	_check(not Game.settings.bindings.has("not_an_action"), "unknown input action removed")
	_check(Game.settings.bindings.fire_primary.size() == 2, "malformed bindings removed")
	_check(_near(Game.settings.bindings.fire_primary[1].v, -1.0), "axis direction normalized")
	Game.settings = original
	Game._normalize_settings()

func _test_background_music_playlist() -> void:
	var tracks := AudioMgr.background_music_tracks()
	_check(tracks.size() == 6, "background playlist contains six supplied tracks")
	var ids := {}
	for track in tracks:
		ids[track.id] = true
		_check(str(track.path).ends_with(".mp3"), "playlist entry uses an MP3 asset")
	_check(ids.size() == 6, "background playlist track ids are unique")
	var previous_enabled := AudioMgr.music_enabled()
	Game.settings.music_enabled = true
	AudioMgr.play_random_music(0.01)
	_check(AudioMgr.current_music_title() != "", "random playlist loads a playable track")
	_check(AudioMgr.is_music_playing(), "random playlist starts its music player")
	AudioMgr.stop_music(0.01)
	Game.settings.music_enabled = previous_enabled

func _test_save_validation() -> void:
	var original := Game.save.duplicate(true)
	Game.save = {
		"selected_ship": "missing", "unlocked_ships": ["missing"],
		"credits": -900, "missions_done": {"missing": 1},
		"loadouts": {"missing": []}, "training_done": false,
	}
	Game._normalize_save()
	_check(Game.save.selected_ship == "vanguard", "invalid selected ship repaired")
	_check(Game.save.unlocked_ships.size() == ShipDB.SHIPS.size(),
		"save migration unlocks every flyable ship")
	for ship_id in ShipDB.SHIPS:
		_check(ship_id in Game.save.unlocked_ships, "%s is unlocked" % ship_id)
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
	_check(pm.has_bullet_capacity(), "consumed projectile frees pool capacity")
	_check(pm._mm.visible_instance_count == 0, "no tracer instances drawn when idle")
	# --- pierce: a railgun round must survive and keep going ---------------
	var second := Combatant.new()
	second.team = Combatant.TEAM_HOSTILE
	second.freeze = true
	second.combat_setup(100.0, 0.0, 0.0, 0.0)
	second.position = Vector3(0, 0, -12)
	var shape2 := CollisionShape3D.new()
	var sphere2 := SphereShape3D.new()
	sphere2.radius = 1.0
	shape2.shape = sphere2
	second.add_child(shape2)
	add_child(second)
	target.combat_setup(100.0, 0.0, 0.0, 0.0)
	await get_tree().physics_frame
	var rail := weapon.duplicate()
	rail.speed = 2000.0
	rail.pierce = 3
	rail.pierce_falloff = 0.8
	pm.fire_bullet(shooter, Vector3.ZERO, Vector3(0, 0, -1), rail, 0, Vector3.ZERO)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(target.hull < 100.0, "pierce round damages the first hull")
	_check(second.hull < 100.0, "pierce round carries through to the second hull")
	_check(second.hull > target.hull, "pierce damage decays with each pass")
	second.queue_free()
	target.combat_setup(100.0, 0.0, 0.0, 0.0)
	pm.fire_bullet(shooter, Vector3.ZERO, Vector3(0, 0, -1), weapon, 0, Vector3.ZERO)
	shooter.free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(target.hull < 100.0, "a projectile still deals damage after its shooter is freed")

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

# ============================================================ 1.2 capabilities
func _test_capability_gate() -> void:
	var original := Game.settings.duplicate(true)
	Game.settings.advanced_caps = true
	for s in ["ftl", "shield", "arsenal", "targeting"]:
		Game.settings["cap_" + s] = true
		_check(Game.cap(s), "capability %s enabled by its own switch" % s)
	# the master switch must override every sub-switch
	Game.settings.advanced_caps = false
	for s in ["ftl", "shield", "arsenal", "targeting"]:
		_check(not Game.cap(s), "master switch gates %s" % s)
	Game.settings.advanced_caps = true
	Game.settings.cap_ftl = false
	_check(not Game.cap("ftl"), "sub-switch gates its own system")
	# the band is a product promise, so a hand-edited profile cannot escape it
	Game.settings.targeting_hit_rate = 0.4
	Game._normalize_settings()
	_check(_near(Game.targeting_setpoint(), 0.80), "hit-rate setpoint clamps up to 80%")
	Game.settings.targeting_hit_rate = 0.99
	Game._normalize_settings()
	_check(_near(Game.targeting_setpoint(), 0.90), "hit-rate setpoint clamps down to 90%")
	Game.settings = original
	Game._normalize_settings()

func _test_extended_arsenal() -> void:
	var original := Game.settings.duplicate(true)
	Game.settings.advanced_caps = true
	Game.settings.cap_arsenal = true
	var full := ShipDB.selectable_weapons()
	Game.settings.cap_arsenal = false
	var stock := ShipDB.selectable_weapons()
	_check(full.size() > stock.size(), "extended arsenal adds weapons")
	_check(stock.size() == 8, "stock arsenal is the eight 1.1 weapons")
	for id in stock:
		_check(not ShipDB.WEAPONS[id].get("advanced", false),
			"stock list excludes advanced weapon %s" % id)
	Game.settings.cap_arsenal = true
	# each new weapon must bring a mechanic, not just a damage number
	_check(int(ShipDB.WEAPONS.railgun.pierce) > 1, "railgun pierces")
	_check(int(ShipDB.WEAPONS.arc.chain) > 1, "arc projector chains")
	_check(int(ShipDB.WEAPONS.flak.pellets) > 1, "flak fires pellets")
	_check(bool(ShipDB.WEAPONS.phase.bypass_shield), "phase disruptor bypasses shields")
	_check(float(ShipDB.WEAPONS.repeater.bloom) > 0.0, "repeater blooms")
	_check(float(ShipDB.WEAPONS.singularity.charge_gain) > 1.0, "singularity lance charges")
	_check(int(ShipDB.MISSILES.cluster.cluster) > 1, "cluster munition splits")
	_check(float(ShipDB.MISSILES.emp.emp_radius) > 0.0, "EMP has a burst radius")
	_check(bool(ShipDB.MISSILES.mine.mine), "mine is a mine")
	# a shield-bypassing round must reach hull through a live shield
	var victim := Combatant.new()
	victim.freeze = true
	victim.combat_setup(100.0, 60.0, 0.0, 0.0)
	add_child(victim)
	victim.take_hit(20.0, Vector3(0, 0, -1), Vector3(0, 0, -1), 0.5, 0.0, 1.0)
	_check(_near(victim.shield_front, 60.0), "bypass round leaves the shield untouched")
	_check(victim.hull < 100.0, "bypass round damages hull through a live shield")
	victim.queue_free()
	Game.settings = original
	Game._normalize_settings()

func _test_shield_matrix() -> void:
	var mesh := ShieldBubble.icosphere(2)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	# 20 icosahedron faces x 4^subdiv, three independent vertices each
	_check(verts.size() == 20 * 16 * 3, "icosphere subdivides to the expected face count")
	_check(cols.size() == verts.size(), "every vertex carries a barycentric coordinate")
	var on_sphere := true
	for v in verts:
		if absf(v.length() - 1.0) > 0.001:
			on_sphere = false
			break
	_check(on_sphere, "every icosphere vertex is projected onto the unit sphere")
	_check(cols[0] != cols[1] and cols[1] != cols[2],
		"the three vertices of a face carry different barycentric corners")
	var host := Node3D.new()
	add_child(host)
	var bubble := ShieldBubble.attach(host, AABB(Vector3(-2, -1, -6), Vector3(4, 2, 12)),
		Color(0.4, 0.7, 1.0))
	_check(not bubble.visible, "an unhit shield is hidden, not merely transparent")
	bubble.register_hit(host.global_position + Vector3(0, 0, -40), 0.8)
	_check(bubble.visible, "a hit makes the matrix visible")
	await get_tree().process_frame
	_check(bubble._live > 0, "the impact ring is live after the hit")
	host.queue_free()

func _test_targeting_servo() -> void:
	var fcs := TargetingComputer.new()
	add_child(fcs)
	fcs.enabled = true
	# too accurate: the loop must scatter (assist falls, error appears)
	fcs.assist = 0.5
	for i in 60:
		fcs.note_shot()
		fcs._on_hit(null, false)
	_check(fcs.assist < 0.5, "a 100% hit rate drives the assist down")
	_check(fcs.error_radians() > 0.0, "an over-accurate pilot gets injected scatter")
	_check(fcs.assist <= 0.02, "a sustained 100% rate saturates the scatter side")
	# not accurate enough: the loop must guide
	fcs.assist = 0.5
	fcs._shots = 0.0
	fcs._hits = 0.0
	for i in 60:
		fcs.note_shot()
	_check(fcs.assist > 0.5, "a 0% hit rate drives the assist up")
	_check(fcs.guidance() > 0.0, "an inaccurate pilot gets guided rounds")
	# hits can never outnumber shots, whatever chain lightning reports
	fcs._shots = 10.0
	fcs._hits = 0.0
	for i in 40:
		fcs._on_hit(null, false)
	_check(fcs._hits <= fcs._shots, "confirmed hits are clamped to shots fired")
	# and it must actually SETTLE inside the band rather than oscillate on the
	# rails: drive it with a shooter whose true hit rate depends on the assist
	fcs.assist = 0.5
	fcs._shots = 0.0
	fcs._hits = 0.0
	# seeded: a servo test driven by an unseeded RNG is a coin flip in CI
	var plant := RandomNumberGenerator.new()
	plant.seed = 20260801
	var acc_sum := 0.0
	var acc_n := 0
	for i in 900:
		fcs.note_shot()
		# a plausible plant: more assist really does mean more hits
		if plant.randf() < clampf(0.35 + fcs.assist * 0.62, 0.0, 1.0):
			fcs._on_hit(null, false)
		if i > 500:
			acc_sum += fcs.hit_rate()
			acc_n += 1
	# The MEAN is the property that matters. The rolling estimate is built from a
	# ~42-shot window, so its own sampling noise is about 5.5 points of standard
	# deviation — asserting on the worst single sample would fail on nothing more
	# than a two-sigma excursion, which is guaranteed to happen over 400 samples.
	var mean_rate := acc_sum / maxf(float(acc_n), 1.0)
	_check(absf(mean_rate - fcs.setpoint()) < 0.04,
		"the loop holds the mean measured rate at the setpoint")
	_check(mean_rate >= 0.80 and mean_rate <= 0.90,
		"the settled loop sits inside the 80-90% band")
	_check(fcs.assist > 0.02 and fcs.assist < 0.98,
		"the settled loop sits off both rails")
	fcs.queue_free()

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

func _test_quality_regressions() -> void:
	var settings_before := Game.settings.duplicate(true)
	Game.settings.fov_motion = 8.0
	Game.settings.flash_intensity = -3.0
	Game.settings.hud_scale = 10.0
	Game._normalize_settings()
	_check(_near(Game.settings.fov_motion, 1.0), "FOV comfort clamps to one")
	_check(_near(Game.settings.flash_intensity, 0.0), "flash comfort supports zero")
	_check(_near(Game.settings.hud_scale, 1.3), "HUD scale clamps for readability")
	Game.settings = settings_before.duplicate(true)
	_check(Game.action_hint("fire_primary") == "LMB", "input hint names real mouse binding")
	_check(AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter, "master has verified hard limiter")
	_check(AudioServer.get_bus_effect(AudioServer.get_bus_index("SFX"), 0) is AudioEffectCompressor,
		"combat mix has compressor")
	var ambience := AudioServer.get_bus_index("Ambience")
	_check(ambience > 0, "ambience has independent bus")
	Game.settings.vol_ambience = 0.0
	AudioMgr.apply_volumes()
	_check(AudioServer.is_bus_mute(ambience), "ambience can be fully muted")
	Game.settings = settings_before.duplicate(true)
	AudioMgr.apply_volumes()
	_check(not AudioServer.is_bus_mute(ambience), "ambience volume restores after mute")
	var bed := AudioMgr.stream("hv_flight_bed") as AudioStreamWAV
	_check(bed != null and bed.get_length() >= 15.9, "flight bed imports full loop duration")
	_check(bed.loop_mode == AudioStreamWAV.LOOP_DISABLED, "loop setup cannot mutate shared one shots")
	for name in ["hv_pulse", "hv_cannon", "hv_rail", "hv_plasma", "hv_shield", "hv_armor", "hv_transit", "hv_resupply"]:
		_check(AudioMgr.has_sound(name), "authored cue loads: " + name)
	var prior_progress: float = SceneFlow._reported_progress
	var prior_started: int = SceneFlow._started_msec
	SceneFlow._reported_progress = 0.60
	SceneFlow._started_msec = Time.get_ticks_msec() - 36000
	_check(SceneFlow._watchdog_grace_seconds() > 0.0, "initializing scene gets bounded renderer warmup grace")
	SceneFlow._started_msec = Time.get_ticks_msec() - 121000
	_check(SceneFlow._watchdog_grace_seconds() == 0.0, "renderer warmup cannot extend beyond 120 seconds")
	SceneFlow._reported_progress = 0.0
	SceneFlow._started_msec = Time.get_ticks_msec() - 36000
	_check(SceneFlow._watchdog_grace_seconds() == 0.0, "missing scene cannot receive initialization grace")
	SceneFlow._reported_progress = prior_progress
	SceneFlow._started_msec = prior_started
	var pilot := PlayerShip.new()
	add_child(pilot)
	pilot.set_physics_process(false)
	pilot.sdef = ShipDB.SHIPS.values()[0]
	pilot.hull_max = 100.0
	pilot.hull = 30.0
	pilot.missiles_left = 0
	pilot.cm_left = 0
	pilot.weapons = WeaponSystem.new()
	pilot.add_child(pilot.weapons)
	pilot.weapons.ammo = {"autocannon": 0}
	pilot.resupply(0.30, 2, 0.12)
	_check(_near(pilot.hull, 42.0), "survival supplies repair twelve percent")
	_check(pilot.missiles_left == 2 and pilot.cm_left == 2, "survival restores bounded ordnance")
	_check(pilot.weapons.ammo.autocannon == ceili(ShipDB.weapon("autocannon").ammo * 0.3),
		"wave completion replenishes a fraction of ballistic capacity")
	pilot.resupply(5.0, 999, 5.0)
	_check(_near(pilot.hull, 100.0) and pilot.missiles_left == int(pilot.sdef.missile_cap),
		"repeated resupply never exceeds hull or missile capacity")
	_check(pilot.weapons.ammo.autocannon == int(ShipDB.weapon("autocannon").ammo),
		"arena unlimited ammo remains bounded")
	var dying := Combatant.new()
	add_child(dying)
	dying.targetable = false
	pilot.loadout = {"missile": ShipDB.MISSILES.keys()[0]}
	pilot.set_target(dying)
	pilot._lock_update(0.016)
	_check(pilot.target == null, "burning untargetable fighters release missile lock")
	var camera := CameraRig.new()
	add_child(camera)
	camera.set_process(false)
	camera.ship = pilot
	pilot.model_root = Node3D.new()
	pilot.add_child(pilot.model_root)
	camera.mode = CameraRig.Mode.COCKPIT
	pilot.model_root.visible = false
	camera.toggle_photo()
	_check(get_tree().paused and pilot.model_root.visible, "photo from cockpit reveals exterior hull")
	camera.toggle_photo()
	_check(not get_tree().paused and not pilot.model_root.visible, "photo exit restores cockpit visibility")
	for ship_id in ShipDB.SHIPS:
		var ship: Dictionary = ShipDB.SHIPS[ship_id]
		_check(ResourceLoader.exists(ship.model), "ship model exists: " + ship_id)
		_check(ShipDB.WEAPONS.has(ship.default_primary) and ShipDB.WEAPONS.has(ship.default_primary2),
			"ship has real weapon definitions: " + ship_id)
		_check(ShipDB.MISSILES.has(ship.default_missile), "ship has valid ordnance: " + ship_id)
	var rocks := AsteroidField.new()
	rocks._rocks = [{"pos": Vector3(0, 0, 0), "scale": 2.0},
		{"pos": Vector3(240, 0, 0), "scale": 20.0},
		{"pos": Vector3(400, 0, 0), "scale": 10.0}]
	rocks.reserve_sphere(Vector3.ZERO, 230)
	_check(rocks._rocks.size() == 1, "relay lane excludes overlapping large rocks too")
	rocks.free()
	camera.queue_free()
	dying.queue_free()
	pilot.queue_free()
	await get_tree().process_frame
