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
## Sustained-fire state for the extended arsenal.
var _bloom := 0.0                   # Scatter Repeater cone growth, 0..1
var beam_charge := 0.0              # Singularity Lance charge, 0..1
var last_spread_mult := 1.0         # what the HUD crosshair should open to
## Written by the owner each frame when a targeting computer is fitted.
var guide_rate := 0.0               # rad/s of in-flight correction for new rounds
var guide_target: Node3D = null

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

## Swap the A-group weapon for the next selectable one. Live weapon swapping is
## the single biggest quality-of-life gain from the extended arsenal — the rack
## is only interesting if you can reach for the right tool mid-fight.
func cycle_primary() -> String:
	var ids := ShipDB.selectable_weapons()
	if ids.is_empty():
		return wpn_a
	var idx := ids.find(wpn_a)
	wpn_a = ids[(idx + 1) % ids.size()]
	var w := ShipDB.weapon(wpn_a)
	if w.has("ammo") and not ammo.has(wpn_a):
		ammo[wpn_a] = int(w.ammo)
	_bloom = 0.0
	beam_charge = 0.0
	_cd_a = 0.0
	return wpn_a

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
	if not want_fire:
		# recoil bloom and beam charge both bleed off the instant the trigger is
		# released, which is what makes tap-firing the Repeater the correct play
		var rec := 5.0
		for id in _firing_ids():
			rec = maxf(rec, float(ShipDB.weapon(id).get("bloom_recover", 5.0)))
		_bloom = maxf(0.0, _bloom - rec * delta)
		beam_charge = maxf(0.0, beam_charge - delta * 1.6)
	last_spread_mult = 1.0 + _bloom
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
		var charge_time: float = float(w.get("charge_time", 0.0))
		var scale := 1.0
		if charge_time > 0.0:
			beam_charge = minf(beam_charge + delta / charge_time, 1.0)
			scale = lerpf(1.0, float(w.get("charge_gain", 1.0)), beam_charge)
		if not ship.consume_fire_cost(w.energy * delta * scale, w.heat * delta * scale):
			return
		beam_active = true
		var mzl: Vector3 = ship.to_global(muzzles[0])
		var endp: Vector3 = pm.beam_tick(ship, mzl, aim_dir, w, ship.team, delta, scale)
		_draw_beam(id, mzl, endp, w, scale)
		if randf() < delta * 3.0:
			AudioMgr.play_3d(w.sound, ship.global_position, -4.0)
		return
	# projectile weapons
	var cd := _cd_a if is_a else _cd_b
	if cd > 0.0:
		return
	# Do not charge energy/heat/ammo for a shot the visual/raycast pool cannot
	# represent. The old linear scan silently dropped those shots under load.
	if not pm.has_bullet_capacity():
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
	# Recoil bloom: the cone opens while the trigger is held and recovers when it
	# is not, so a Repeater rewards controlled bursts instead of a held button.
	var bloom_gain: float = float(w.get("bloom", 0.0))
	if bloom_gain > 0.0:
		_bloom = minf(_bloom + bloom_gain / maxf(float(w.rof), 1.0), 1.6)
	var spread_mult := 1.0 + _bloom
	# Pellet weapons are one trigger pull, N rounds. Firing them through the same
	# path keeps pierce/chain/bypass working for a shotgun too.
	var pellets := maxi(int(w.get("pellets", 1)), 1)
	var launched := false
	for p in pellets:
		if pm.fire_bullet(ship, mzl, aim_dir, w, ship.team, inherit, spread_mult,
				guide_rate, guide_target):
			launched = true
		elif p == 0:
			return
	if not launched:
		return
	FX.muzzle_flash(pm, mzl, w.color)
	AudioMgr.play_3d(w.sound, mzl, -2.0)
	if ship.is_in_group("player") and "battle" in ship and ship.battle:
		# A shotgun blast is ONE shot for accuracy purposes; counting seven pellets
		# as seven shots would put the hit-rate servo permanently below its band.
		ship.battle.shots_fired += 1
		ship.battle.note_shot(id, pellets)

func _draw_beam(id: String, from: Vector3, to: Vector3, w: Dictionary, scale := 1.0) -> void:
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
	# a charging lance visibly thickens, which is the only cue the player has
	# that holding the trigger is doing something
	mi.scale = Vector3(scale, len, scale)
	var bm := mi.material_override as StandardMaterial3D
	if bm:
		bm.emission_energy_multiplier = 4.0 * scale

func ammo_text() -> String:
	var parts: PackedStringArray = []
	for id in _firing_ids():
		if ammo.has(id):
			parts.append("%d" % ammo[id])
	return " | ".join(parts)
