class_name HUD
extends Control
## Full combat HUD: crosshair, lead, brackets, radar, bars, warnings, comms, tac-map.

var player: PlayerShip
var battle: Node
var show_tacmap := false
var _hitmarker_t := 0.0
var _hit_shield := false
var _hit_surface := false
var _comms: Array = []              # [{text, speaker, t}]
var _objective := ""
var _objective_sub := ""
var _kill_feed: Array = []
var _warn_blink := 0.0
var _obj_marker_pos := Vector3.INF
var score := 0

var _dmg_t := 0.0
var _damage_pos := Vector3.ZERO
var _feedback_t := 0.0
var _feedback_text := ""
var _ui_scale := 1.0
const INK := Color(0.018, 0.034, 0.060, 0.90)
const TEXT := Color(0.89, 0.95, 0.98)
const HOSTILE := Color(1.0, 0.43, 0.32)


func setup(p: PlayerShip, b: Node) -> void:
	player = p
	battle = b
	# ALWAYS: the HUD must keep redrawing while paused, otherwise a stale
	# HUD frame stays plastered over photo mode
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle.projectiles.player_hit_confirmed.connect(_on_hit_confirmed)
	battle.projectiles.player_surface_hit.connect(_on_surface_hit)
	player.damaged.connect(func(_amt, hit_pos, was_shield):
		_damage_pos = hit_pos
		_dmg_t = 0.35 if was_shield else 0.65
		AudioMgr.play_ui("hv_shield" if was_shield else "hv_armor", -9.0))

func _on_hit_confirmed(_t: Node, was_shield: bool) -> void:
	_hitmarker_t = 0.22
	_hit_shield = was_shield
	_hit_surface = false
	AudioMgr.play_ui("hitmarker", -10.0)

func _on_surface_hit(_t: Node, kind: String) -> void:
	_hitmarker_t = 0.16
	_hit_shield = false
	_hit_surface = true
	AudioMgr.play_ui("hitmarker", -15.0, 0.82 if kind == "rock" else 0.92)

func comms(speaker: String, text: String) -> void:
	_comms.append({"speaker": speaker, "text": text, "t": 7.0})
	if _comms.size() > 4:
		_comms.pop_front()
	AudioMgr.play_ui("radio")
	AudioMgr.duck_music(2.5)

func set_objective(main: String, sub := "", marker := Vector3.INF) -> void:
	_objective = main
	_objective_sub = sub
	_obj_marker_pos = marker

func confirm_kill(points: int, streak: int) -> void:
	_feedback_text = "TARGET DESTROYED   +%d" % points
	if streak > 1:
		_feedback_text += "   /   CHAIN %d" % streak
	_feedback_t = 1.8
	AudioMgr.play_ui("ui_ready", -8.0, 1.0 + minf(streak, 5) * 0.04)

func kill_feed(text: String) -> void:
	_kill_feed.append({"text": text, "t": 5.0})
	if _kill_feed.size() > 5:
		_kill_feed.pop_front()

func _process(delta: float) -> void:
	# hard-pin to the full viewport; anchors under a bare CanvasLayer proved unreliable
	var vr := get_viewport_rect().size
	if size != vr:
		position = Vector2.ZERO
		size = vr
	if get_tree().paused:
		queue_redraw()
		return
	_feedback_t = maxf(0.0, _feedback_t - delta)
	_hitmarker_t -= delta
	_dmg_t = maxf(0.0, _dmg_t - delta)
	_warn_blink += delta * 6.0
	for c in _comms:
		c.t -= delta
	_comms = _comms.filter(func(c): return c.t > 0.0)
	for k in _kill_feed:
		k.t -= delta
	_kill_feed = _kill_feed.filter(func(k): return k.t > 0.0)
	if Input.is_action_just_pressed("tactical_map") and not get_tree().paused:
		show_tacmap = not show_tacmap
		AudioMgr.play_ui("ui_click")
	queue_redraw()

func _cam() -> Camera3D:
	return get_viewport().get_camera_3d()

func _draw() -> void:
	if player == null or not is_instance_valid(player) or not player.alive:
		return
	if player.cam_rig and player.cam_rig.mode == CameraRig.Mode.PHOTO:
		return
	var vp := size
	var f := Styles.title_font()
	var bf := Styles.body_font()
	# damage vignette: red edge flash on hull hits, steady pulse when critical
	var vig := clampf(_dmg_t * 1.6, 0.0, 0.85)
	if player.hull_frac() < 0.3:
		vig = maxf(vig, 0.25 + 0.15 * sin(_warn_blink * 0.8))
	vig *= float(Game.settings.flash_intensity)
	if vig > 0.01:
		for i in 3:
			var inset := 4.0 + i * 14.0
			draw_rect(Rect2(Vector2(inset, inset), vp - Vector2(inset * 2, inset * 2)),
				Color(0.9, 0.05, 0.02, vig * (0.22 - 0.06 * i)), false, 16.0)
	_draw_crosshair(vp)
	_draw_ftl(vp, f, bf)
	_draw_target_elements(vp, f, bf)
	_draw_offscreen_and_markers(vp)
	_draw_relay(vp, bf)
	_draw_warnings(vp, f)
	if _feedback_t > 0.0:
		var a := minf(_feedback_t * 2.0, 1.0)
		_centered(f, _feedback_text, vp, vp.y * 0.40, 15, Color(1.0, 0.75, 0.40, a))
	# Instrument scaling is independent from 3D projection and aim markers.
	_ui_scale = clampf(float(Game.settings.hud_scale), 0.85, minf(1.3, vp.x / 1100.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _ui_scale)
	var uvp := vp / _ui_scale
	_draw_bars(uvp, f, bf)
	_draw_radar(uvp)
	_draw_comms(uvp, f, bf)
	_draw_objective(uvp, f, bf)
	_draw_target_card(uvp, f, bf)
	_draw_killfeed(uvp, bf)
	_draw_hints(uvp, bf)
	draw_set_transform(Vector2.ZERO)
	if show_tacmap:
		_draw_tacmap(vp, f, bf)

func _draw_relay(vp: Vector2, font: Font) -> void:
	if not is_instance_valid(battle.relay) or battle.relay.traversed:
		return
	var relay: NavigationRelay = battle.relay
	var camera: Camera3D = player.cam_rig.cam
	var distance := player.global_position.distance_to(relay.global_position)
	if distance > 2800 or distance < 120 or camera.is_position_behind(relay.global_position):
		return
	var at := camera.unproject_position(relay.global_position)
	if not Rect2(Vector2(370, 160), vp - Vector2(740, 410)).has_point(at):
		return
	var col := Color(1.0, 0.75, 0.42, 0.88)
	draw_arc(at, 17, PI * 0.15, PI * 0.85, 14, col, 1.3, true)
	draw_string(font, at + Vector2(-78, 42), "RELAY 07  /  %d M" % roundi(distance), HORIZONTAL_ALIGNMENT_CENTER, 156, 12, col)
	draw_string(font, at + Vector2(-78, 58), "FLY THROUGH  +150", HORIZONTAL_ALIGNMENT_CENTER, 156, 10, Styles.DIM)

# ------------------------------------------------------------- crosshair
func _draw_crosshair(vp: Vector2) -> void:
	var c := player.crosshair_screen_pos()
	var col := Styles.CYAN
	if player.overheated:
		col = Styles.RED
	# the reticle opens with recoil bloom, so the Scatter Repeater's growing cone
	# is something you can see rather than something you infer from misses
	var bloom: float = player.weapons.last_spread_mult if player.weapons else 1.0
	var r := 14.0 * bloom
	draw_arc(c, r, 0, TAU, 32, col, 1.5, true)
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r + 4.0), c + d * (r + 12.0), col, 1.5, true)
	# boresight dot at screen center
	draw_circle(vp * 0.5, 2.0, Color(col.r, col.g, col.b, 0.5))
	# hit marker
	if _hitmarker_t > 0.0:
		var hc := Color(0.72, 0.68, 0.60) if _hit_surface \
			else (Styles.CYAN if _hit_shield else Styles.ORANGE)
		for a in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * 8.0, c + d * 16.0, hc, 2.0, true)

# ------------------------------------------------------------- FTL drive
## Charge ring around the reticle while spooling, a banner while cruising, and a
## quiet availability prompt otherwise. Everything here is drawn only when the
## drive is actually fitted, so a 1.1-configuration HUD is unchanged.
func _draw_ftl(vp: Vector2, f: Font, bf: Font) -> void:
	var d: FTLDrive = player.ftl
	if d == null:
		return
	var c := vp * 0.5
	match d.phase:
		FTLDrive.Phase.SPOOL:
			var rr := 46.0 - 12.0 * d.charge
			draw_arc(c, rr, -PI / 2.0, -PI / 2.0 + TAU * d.charge, 48,
				Color(0.55, 0.85, 1.0, 0.9), 3.0, true)
			draw_arc(c, rr, 0, TAU, 48, Color(0.3, 0.55, 0.8, 0.22), 1.2, true)
			_centered(f, d.status_text(), vp, vp.y * 0.62, 17, Color(0.6, 0.88, 1.0))
		FTLDrive.Phase.BREACH, FTLDrive.Phase.CRUISE:
			_centered(f, "▶ LIGHTSPEED", vp, vp.y * 0.20, 22, Color(0.75, 0.92, 1.0))
			_centered(bf, "weapons offline — release to fall back", vp,
				vp.y * 0.20 + 24.0, 13, Styles.DIM)
		FTLDrive.Phase.FALLBACK:
			_centered(f, "FALLBACK", vp, vp.y * 0.20, 18, Styles.ORANGE)

func _centered(font: Font, text: String, vp: Vector2, y: float, sz: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(font, Vector2((vp.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

# ------------------------------------------------------------- target UI
func _draw_target_elements(vp: Vector2, f: Font, bf: Font) -> void:
	var cam := _cam()
	if cam == null:
		return
	var t := player.target
	if t == null or not is_instance_valid(t):
		return
	var tpos: Vector3 = t.global_position
	if cam.is_position_behind(tpos):
		return
	var sp := cam.unproject_position(tpos)
	var dist := player.global_position.distance_to(tpos)
	var bracket := clampf(2200.0 / maxf(dist, 10.0), 14.0, 46.0)
	if "radar_size" in t:
		bracket *= clampf(t.radar_size * 0.6 + 0.4, 1.0, 4.0)
	var col := HOSTILE if ("team" in t and t.team == Combatant.TEAM_HOSTILE) else Styles.GREEN
	# corner brackets
	for sxy: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var corner: Vector2 = sp + sxy * bracket
		draw_line(corner, corner - Vector2(sxy.x, 0) * bracket * 0.45, col, 1.6, true)
		draw_line(corner, corner - Vector2(0, sxy.y) * bracket * 0.45, col, 1.6, true)
	# Keep only range beside the world bracket; telemetry has a stable card.
	var vel: Vector3 = t.get_velocity() if t.has_method("get_velocity") else Vector3.ZERO
	if sp.x > 30 and sp.x < vp.x - 100 and sp.y > 70 and sp.y < vp.y - 230:
		draw_string(bf, sp + Vector2(bracket + 8, 4), "%.0f m" % dist,
			HORIZONTAL_ALIGNMENT_LEFT, 90, 13, TEXT)
	# --- mathematical lead indicator ---
	var w_speed := player.weapons.current_speed()
	if w_speed < 50000.0 and dist < player.weapons.current_range() * 1.4:
		var tacc: Vector3 = t.accel_estimate if "accel_estimate" in t else Vector3.ZERO
		var lead := Projectiles.lead_point(player.global_position, player.linear_velocity,
			tpos, vel, tacc, w_speed)
		if not cam.is_position_behind(lead):
			var lp := cam.unproject_position(lead)
			draw_arc(lp, 7.0, 0, TAU, 20, Styles.ORANGE, 1.8, true)
			draw_circle(lp, 1.6, Styles.ORANGE)
			var cx := player.crosshair_screen_pos()
			if cx.distance_to(lp) < 26.0:
				draw_arc(lp, 11.0, 0, TAU, 20, Styles.GREEN, 1.8, true)
	# missile lock ring
	var mdef: Dictionary = ShipDB.MISSILES[player.loadout.missile]
	if mdef.guidance != "none" and player.missiles_left > 0:
		if player.lock_progress > 0.0:
			var lc := Styles.RED if player.locked else Styles.ORANGE
			draw_arc(sp, bracket + 10.0, -PI / 2.0, -PI / 2.0 + TAU * player.lock_progress, 40, lc, 2.5, true)
			if player.locked and fmod(_warn_blink, 2.0) < 1.2:
				draw_string(f, sp + Vector2(-34, bracket + 26), "LOCK", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Styles.RED)

# ------------------------------------------------------------- offscreen
func _draw_offscreen_and_markers(vp: Vector2) -> void:
	var cam := _cam()
	if cam == null:
		return
	var center := vp * 0.5
	for h in battle.hostile_targets():
		if not is_instance_valid(h):
			continue
		var behind := cam.is_position_behind(h.global_position)
		var sp := cam.unproject_position(h.global_position)
		var onscreen := not behind and sp.x > 0 and sp.x < vp.x and sp.y > 0 and sp.y < vp.y
		if onscreen:
			if h != player.target:
				draw_arc(sp, 9.0, 0, TAU, 4, Color(1, 0.3, 0.2, 0.55), 1.2, true)
		else:
			var dir2 := (sp - center)
			if behind:
				dir2 = -dir2
			if dir2.length_squared() < 1.0:
				dir2 = Vector2(0, -1)
			dir2 = dir2.normalized()
			var edge := center + dir2 * (minf(vp.x, vp.y) * 0.44)
			var perp := Vector2(-dir2.y, dir2.x)
			var colr := Color(1, 0.3, 0.2, 0.8)
			draw_colored_polygon(PackedVector2Array([edge + dir2 * 10.0, edge + perp * 5.0, edge - perp * 5.0]), colr)
	# objective marker
	if _obj_marker_pos != Vector3.INF:
		var behind := cam.is_position_behind(_obj_marker_pos)
		var sp := cam.unproject_position(_obj_marker_pos)
		var onscreen := not behind and sp.x > 0 and sp.x < vp.x and sp.y > 0 and sp.y < vp.y
		if onscreen:
			var s := 12.0
			draw_rect(Rect2(sp - Vector2(s, s), Vector2(s * 2, s * 2)), Styles.CYAN, false, 1.6)
			var d := player.global_position.distance_to(_obj_marker_pos)
			draw_string(Styles.body_font(), sp + Vector2(-30, s + 16), "%0.1f km" % (d / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Styles.CYAN)
		else:
			var dir2 := (sp - vp * 0.5)
			if behind:
				dir2 = -dir2
			dir2 = dir2.normalized()
			var edge := vp * 0.5 + dir2 * (minf(vp.x, vp.y) * 0.47)
			draw_rect(Rect2(edge - Vector2(5, 5), Vector2(10, 10)), Styles.CYAN, false, 1.5)

# ------------------------------------------------------------- bars
func _plate(rect: Rect2, accent := Styles.CYAN) -> void:
	draw_rect(rect, INK)
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.22), false, 1.0)
	draw_line(rect.position, rect.position + Vector2(42, 0), accent, 2.0)
	draw_line(rect.end - Vector2(22, 0), rect.end, accent, 2.0)

func _text(font: Font, at: Vector2, text: String, px: int, width: float, color := TEXT) -> void:
	var fitted := TextLine.new()
	fitted.add_string(text, font, px)
	fitted.width = width
	fitted.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	fitted.draw(get_canvas_item(), at - Vector2(0, fitted.get_line_ascent()), color)

func _meter(at: Vector2, width: float, value: float, color: Color) -> void:
	draw_rect(Rect2(at, Vector2(width, 6)), Color(0.16, 0.22, 0.29, 0.85))
	draw_rect(Rect2(at, Vector2(width * clampf(value, 0.0, 1.0), 6)), color)
	for i in range(1, 10):
		draw_line(at + Vector2(width * i / 10.0, 0), at + Vector2(width * i / 10.0, 6), INK, 2)

func _draw_bars(vp: Vector2, f: Font, bf: Font) -> void:
	var left := Vector2(26, vp.y - 177)
	var right := Vector2(vp.x - 348, vp.y - 211)
	_plate(Rect2(left, Vector2(310, 151)))
	_plate(Rect2(right, Vector2(322, 185)), Styles.ORANGE)
	_text(f, left + Vector2(16, 26), player.display_name.to_upper(), 15, 278)
	_text(bf, left + Vector2(16, 47), "FLIGHT ASSIST  " + ("ON" if player.flight_assist else "OFF / DRIFT"), 12, 278, Styles.CYAN)
	var rows := [["FORE SHIELD", player.shield_front / maxf(player.shield_max, 1.0), Styles.CYAN],
		["AFT SHIELD", player.shield_rear / maxf(player.shield_max, 1.0), Styles.CYAN],
		["HULL INTEGRITY", player.hull_frac(), Styles.GREEN if player.hull_frac() > 0.35 else HOSTILE]]
	for i in rows.size():
		var pt := left + Vector2(16, 70 + i * 26)
		_text(bf, pt, rows[i][0], 11, 165, Styles.DIM)
		_text(bf, pt + Vector2(228, 0), "%d%%" % roundi(rows[i][1] * 100), 12, 52, rows[i][2])
		_meter(pt + Vector2(0, 6), 278, rows[i][1], rows[i][2])
	var weapon: String = ShipDB.WEAPONS[player.weapons.wpn_a].label
	_text(f, right + Vector2(16, 26), weapon.to_upper(), 14, 290)
	_text(bf, right + Vector2(16, 46), "%s  /  %s" % [player.weapons.group_label(), player.weapons.ammo_text()], 12, 290, Styles.DIM)
	var missile: Dictionary = ShipDB.MISSILES[player.loadout.missile]
	_text(bf, right + Vector2(16, 69), "%s  ×%d" % [missile.label, player.missiles_left], 14, 290)
	_text(bf, right + Vector2(16, 89), "FLARES  %02d    FCS  %s" % [player.cm_left, "ON" if player.fcs and player.fcs.enabled else "OFF"], 12, 290, Styles.CYAN)
	_text(bf, right + Vector2(16, 112), "ENERGY", 11, 85, Styles.DIM)
	_meter(right + Vector2(90, 106), 216, player.energy / player.sdef.energy, Styles.CYAN)
	_text(bf, right + Vector2(16, 134), "HEAT", 11, 85, Styles.DIM)
	_meter(right + Vector2(90, 128), 216, player.heat / player.sdef.heat_cap, HOSTILE if player.overheated else Styles.ORANGE)
	_text(f, right + Vector2(16, 169), "%03d  M/S" % roundi(player.linear_velocity.length()), 20, 200)
	_text(bf, right + Vector2(211, 166), "BOOST" if player.boost_on else "CRUISE", 12, 95, Styles.ORANGE if player.boost_on else Styles.DIM)

func _draw_target_card(vp: Vector2, f: Font, bf: Font) -> void:
	var t := player.target
	if not is_instance_valid(t) or ("alive" in t and not t.alive):
		return
	var pos := Vector2(vp.x - 348, 78)
	_plate(Rect2(pos, Vector2(322, 126)), HOSTILE)
	_text(bf, pos + Vector2(16, 22), "TARGET TELEMETRY", 11, 290, HOSTILE)
	_text(f, pos + Vector2(16, 44), t.display_name if "display_name" in t else t.name, 15, 290)
	var dist := player.global_position.distance_to(t.global_position)
	var vel: Vector3 = t.get_velocity() if t.has_method("get_velocity") else Vector3.ZERO
	var closing := (player.linear_velocity - vel).dot((t.global_position - player.global_position).normalized())
	_text(bf, pos + Vector2(16, 65), "%.0f M    /    CLOSURE %+0.0f M/S" % [dist, closing], 12, 290, Styles.DIM)
	var hp: float = t.hull_frac() if t.has_method("hull_frac") else (t.hp_frac() if t.has_method("hp_frac") else 1.0)
	_meter(pos + Vector2(16, 82), 290, hp, HOSTILE)
	if t.has_method("shield_frac"):
		_meter(pos + Vector2(16, 92), 290, t.shield_frac(), Styles.CYAN)
	var status := "MISSILE LOCK" if player.locked else ("ACQUIRING" if player.lock_progress > 0 else "TRACKING")
	_text(bf, pos + Vector2(16, 116), status + "    /    HULL %d%%" % roundi(hp * 100), 12, 290, HOSTILE if player.locked else TEXT)

# ------------------------------------------------------------- radar
func _draw_radar(vp: Vector2) -> void:
	var c := Vector2(vp.x * 0.5, vp.y - 100.0)
	var R := 62.0
	_plate(Rect2(c - Vector2(87, 77), Vector2(174, 151)))
	draw_string(Styles.body_font(), c + Vector2(-40, 69), "RADAR / 2.5 KM", HORIZONTAL_ALIGNMENT_LEFT, 130, 11, Styles.DIM)
	draw_circle(c, R, Color(0.025, 0.05, 0.08, 0.70))
	draw_arc(c, R, 0, TAU, 48, Color(0.3, 0.6, 0.8, 0.5), 1.2, true)
	draw_arc(c, R * 0.5, 0, TAU, 36, Color(0.3, 0.6, 0.8, 0.22), 1.0, true)
	draw_line(c - Vector2(0, R), c + Vector2(0, R), Color(0.3, 0.6, 0.8, 0.15), 1.0)
	draw_line(c - Vector2(R, 0), c + Vector2(R, 0), Color(0.3, 0.6, 0.8, 0.15), 1.0)
	# player wedge
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(-4, 4), c + Vector2(4, 4)]), Styles.CYAN)
	var range_m := 2500.0
	var binv := player.global_transform.basis.inverse()
	var contacts: Array = battle.all_combatants()
	for ct in contacts:
		if not is_instance_valid(ct) or ct == player:
			continue
		var rel: Vector3 = binv * (ct.global_position - player.global_position)
		var d := rel.length()
		if d > range_m:
			continue
		# top-down: x → x, -z → up ; elevation as tick
		var p2 := c + Vector2(rel.x, rel.z) / range_m * R
		var hostile: bool = "team" in ct and ct.team == Combatant.TEAM_HOSTILE
		var col := Styles.RED if hostile else Styles.GREEN
		var sz: float = 2.0 + (ct.radar_size if "radar_size" in ct else 1.0)
		if ct == player.target:
			draw_arc(p2, sz + 3.0, 0, TAU, 12, Color.WHITE, 1.0, true)
		draw_circle(p2, sz, col)
		var ytick := clampf(-rel.y / range_m * R, -14, 14)
		draw_line(p2, p2 + Vector2(0, ytick), Color(col.r, col.g, col.b, 0.4), 1.0)
	# incoming missiles blink
	for m in player.incoming:
		if not is_instance_valid(m):
			continue
		var rel: Vector3 = binv * (m.global_position - player.global_position)
		if rel.length() > range_m:
			continue
		if fmod(_warn_blink, 1.0) < 0.55:
			var p2 := c + Vector2(rel.x, rel.z) / range_m * R
			draw_circle(p2, 2.5, Color(1, 0.9, 0.2))

# ------------------------------------------------------------- warnings
func _draw_warnings(vp: Vector2, f: Font) -> void:
	var y := vp.y * 0.30
	if not player.incoming.is_empty():
		var txt := "MISSILE INBOUND  /  %s  FLARES" % Game.action_hint("countermeasure")
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(f, Vector2((vp.x - w) / 2.0, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Styles.RED)
	# the guns going quiet needs an explanation, or it reads as a bug
	if player.fcs:
		var reason := player.fcs.inhibit_reason()
		if reason != "":
			_centered(f, reason, vp, y - 26.0, 15, Styles.ORANGE)
	if player.overheated:
		var txt2 := "WEAPONS OVERHEAT"
		var w2 := f.get_string_size(txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(f, Vector2((vp.x - w2) / 2.0, y + 26), txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Styles.ORANGE)
	if player.hull_frac() < 0.25:
		var txt3 := "HULL CRITICAL"
		var w3 := f.get_string_size(txt3, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(f, Vector2((vp.x - w3) / 2.0, y + 50), txt3, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Styles.RED)

# ------------------------------------------------------------- comms & objectives
func _draw_comms(vp: Vector2, f: Font, bf: Font) -> void:
	# Two readable radio subtitles, wrapped inside a stable contrast plate.
	var first := maxi(_comms.size() - 2, 0)
	var y := vp.y - 209.0
	for i in range(_comms.size() - 1, first - 1, -1):
		var c: Dictionary = _comms[i]
		var para := TextParagraph.new()
		para.add_string(c.text, bf, 14)
		para.width = 390
		para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
		var height := maxf(para.get_size().y, 18) + 44
		y -= height + 6
		_plate(Rect2(Vector2(26, y), Vector2(422, height)))
		_text(f, Vector2(42, y + 22), c.speaker + " / COMMS", 11, 390, Styles.CYAN)
		para.draw(get_canvas_item(), Vector2(42, y + 31), TEXT)

func _draw_objective(vp: Vector2, f: Font, bf: Font) -> void:
	if _objective == "":
		return
	var w := minf(570, vp.x - 424)
	_plate(Rect2(Vector2(26, 26), Vector2(w, 90)))
	_text(bf, Vector2(42, 48), "HELION COMMAND  /  ACTIVE OBJECTIVE", 11, w - 32, Styles.DIM)
	_text(f, Vector2(42, 76), _objective, 17, w - 32, Styles.CYAN)
	_text(bf, Vector2(42, 99), _objective_sub, 13, w - 32)
	_plate(Rect2(Vector2(vp.x - 222, 26), Vector2(196, 38)), Styles.ORANGE)
	_text(f, Vector2(vp.x - 206, 51), "%06d  /  SCORE" % score, 14, 168)

func _draw_killfeed(vp: Vector2, bf: Font) -> void:
	var y := 232.0
	for k in _kill_feed:
		var a := clampf(k.t, 0.0, 1.0)
		_text(bf, Vector2(vp.x - 348, y), k.text, 13, 322, Color(0.88, 0.92, 1.0, a))
		y += 20

func _draw_hints(vp: Vector2, bf: Font) -> void:
	if not bool(Game.settings.flight_hints) or battle.mission_time > 28.0:
		return
	var txt := "%s THRUST   %s TARGET   %s FIRE   %s PAUSE" % [Game.action_hint("thrust_forward"), Game.action_hint("cycle_target"), Game.action_hint("fire_primary"), Game.action_hint("pause")]
	var w := minf(600, vp.x - 760)
	if w < 340:
		return
	var pos := Vector2((vp.x - w) * 0.5, vp.y - 219)
	_plate(Rect2(pos, Vector2(w, 30)))
	_text(bf, pos + Vector2(12, 20), txt, 12, w - 24, Styles.DIM)

# ------------------------------------------------------------- tactical map
func _draw_tacmap(vp: Vector2, f: Font, bf: Font) -> void:
	var c := vp * 0.5
	var R := minf(vp.x, vp.y) * 0.38
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.01, 0.02, 0.04, 0.82))
	draw_circle(c, R, Color(0.02, 0.05, 0.09, 0.9))
	for ring in [0.33, 0.66, 1.0]:
		draw_arc(c, R * ring, 0, TAU, 64, Color(0.3, 0.6, 0.8, 0.3), 1.0, true)
	draw_string(f, c + Vector2(-70, -R - 16), "TACTICAL — 6 KM", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Styles.CYAN)
	var range_m := 6000.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(-5, 6), c + Vector2(5, 6)]), Styles.CYAN)
	var binv := player.global_transform.basis.inverse()
	for ct in battle.all_combatants():
		if not is_instance_valid(ct) or ct == player:
			continue
		var rel: Vector3 = binv * (ct.global_position - player.global_position)
		if rel.length() > range_m:
			continue
		var p2 := c + Vector2(rel.x, rel.z) / range_m * R
		var hostile: bool = "team" in ct and ct.team == Combatant.TEAM_HOSTILE
		var col := Styles.RED if hostile else Styles.GREEN
		var sz: float = 2.5 + (ct.radar_size if "radar_size" in ct else 1.0) * 1.4
		draw_circle(p2, sz, col)
		if "display_name" in ct and (ct.radar_size if "radar_size" in ct else 1.0) > 2.0:
			draw_string(bf, p2 + Vector2(8, 4), ct.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col.r, col.g, col.b, 0.8))
	if _obj_marker_pos != Vector3.INF:
		var rel: Vector3 = binv * (_obj_marker_pos - player.global_position)
		if rel.length() < range_m:
			var p2 := c + Vector2(rel.x, rel.z) / range_m * R
			draw_rect(Rect2(p2 - Vector2(5, 5), Vector2(10, 10)), Styles.CYAN, false, 1.5)
