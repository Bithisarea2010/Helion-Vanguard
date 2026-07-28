class_name WeaponSystem
extends Node3D
## Primary weapon groups + heat/energy/ammo, for players and AI ships.

var ship: Node3D                    # owner (must expose team, linear_velocity)
var pm: Projectiles
var wpn_a := "pulse"
var wpn_b := "autocannon"
var group := 2                      # 0 = A only, 1 = B only, 2 = linked
var muzzles_a: Array[Vector3] = []  # local offsets
var muzzles_b: Array[Vector3] = []
var _cd_a := 0.0
var _cd_b := 0.0
var _alt_a := 0
var _alt_b := 0
var ammo := {}                      # weapon id -> remaining (only ballistic)
var _beam_meshes := {}              # weapon id -> MeshInstance3D
var beam_active := false

func setup(owner_ship: Node3D, proj: Projectiles, a: String, b: String,
		ma: Array[Vector3], mb: Array[Vector3]) -> void:
	ship = owner_ship
	pm = proj
	wpn_a = a; wpn_b = b
	muzzles_a = ma; muzzles_b = mb
	for id in [a, b]:
		var w := ShipDB.weapon(id)
		if w.has("ammo"):
			ammo[id] = int(w.ammo)

func cycle_group() -> int:
	group = (group + 1) % 3
	return group

func group_label() -> String:
	match group:
		0: return ShipDB.weapon(wpn_a).label
		1: return ShipDB.weapon(wpn_b).label
		_: return "LINKED"

func current_speed() -> float:
	# representative projectile speed for lead computation
	var ids := _firing_ids()
	if ids.is_empty():
		return 700.0
	var w := ShipDB.weapon(ids[0])
	return maxf(w.speed, 100.0) if w.kind == "bullet" else 100000.0

func current_range() -> float:
	var ids := _firing_ids()
	var r := 0.0
	for id in ids:
		r = maxf(r, ShipDB.weapon(id).range)
	return r if r > 0.0 else 1200.0

func _firing_ids() -> Array:
	match group:
		0: return [wpn_a]
		1: return [wpn_b]
		_: return [wpn_a, wpn_b]

## Called each physics frame. aim_dir must be normalized world direction.
func process_fire(delta: float, want_fire: bool, aim_dir: Vector3) -> void:
	_cd_a = maxf(0.0, _cd_a - delta)
	_cd_b = maxf(0.0, _cd_b - delta)
	beam_active = false
	if want_fire:
		var ids := _firing_ids()
		if wpn_a in ids:
			_try_fire(wpn_a, delta, aim_dir, true)
		if wpn_b in ids:
			_try_fire(wpn_b, delta, aim_dir, false)
	# hide beams when not firing
	for id in _beam_meshes:
		if not beam_active or not (id in _firing_ids()) or not want_fire:
			_beam_meshes[id].visible = false

func _try_fire(id: String, delta: float, aim_dir: Vector3, is_a: bool) -> void:
	var w := ShipDB.weapon(id)
	var muzzles := muzzles_a if is_a else muzzles_b
	if muzzles.is_empty():
		muzzles = [Vector3.ZERO]
	if w.kind == "beam":
		# continuous: consume per second
		if not ship.consume_fire_cost(w.energy * delta, w.heat * delta):
			return
		beam_active = true
		var mzl: Vector3 = ship.to_global(muzzles[0])
		var endp: Vector3 = pm.beam_tick(ship, mzl, aim_dir, w, ship.team, delta)
		_draw_beam(id, mzl, endp, w)
		if randf() < delta * 3.0:
			AudioMgr.play_3d(w.sound, ship.global_position, -4.0)
		return
	# projectile weapons
	var cd := _cd_a if is_a else _cd_b
	if cd > 0.0:
		return
	if ammo.has(id) and ammo[id] <= 0:
		return
	if not ship.consume_fire_cost(w.energy, w.heat):
		return
	var alt := _alt_a if is_a else _alt_b
	var mzl: Vector3 = ship.to_global(muzzles[alt % muzzles.size()])
	if is_a:
		_alt_a += 1
		_cd_a = 1.0 / w.rof
	else:
		_alt_b += 1
		_cd_b = 1.0 / w.rof
	if ammo.has(id):
		ammo[id] -= 1
	var inherit: Vector3 = ship.get_velocity() if ship.has_method("get_velocity") else Vector3.ZERO
	pm.fire_bullet(ship, mzl, aim_dir, w, ship.team, inherit)
	FX.muzzle_flash(pm, mzl, w.color)
	AudioMgr.play_3d(w.sound, mzl, -2.0)
	if ship.is_in_group("player") and "battle" in ship and ship.battle:
		ship.battle.shots_fired += 1

func _draw_beam(id: String, from: Vector3, to: Vector3, w: Dictionary) -> void:
	var mi: MeshInstance3D
	if _beam_meshes.has(id):
		mi = _beam_meshes[id]
	else:
		mi = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = w.size * 0.5
		cm.bottom_radius = w.size * 0.5
		cm.height = 1.0
		cm.radial_segments = 8
		mi.mesh = cm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = w.color
		m.emission_enabled = true
		m.emission = w.color
		m.emission_energy_multiplier = 4.0
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pm.add_child(mi)
		_beam_meshes[id] = mi
	mi.visible = true
	var mid := (from + to) * 0.5
	var len := from.distance_to(to)
	mi.global_position = mid
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.look_at(mid + dir, up)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	mi.scale = Vector3(1, len, 1)

func ammo_text() -> String:
	var parts: PackedStringArray = []
	for id in _firing_ids():
		if ammo.has(id):
			parts.append("%d" % ammo[id])
	return " | ".join(parts)
