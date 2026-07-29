class_name Projectiles
extends Node3D
## Pooled raycast projectiles + beams. One instance lives in the Battle scene.

signal player_hit_confirmed(target: Node, was_shield: bool)
signal player_surface_hit(target: Node, kind: String)

const POOL := 320
var _pool: Array[MeshInstance3D] = []
var _free_pool: Array[int] = []
var _active: Array[Dictionary] = []
var _mat_cache := {}
var _mesh_cache := {}

func _ready() -> void:
	for i in POOL:
		var mi := MeshInstance3D.new()
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_pool.append(mi)
		_free_pool.append(i)

func has_bullet_capacity() -> bool:
	return not _free_pool.is_empty()

func _release_bullet(index: int) -> void:
	if index < 0 or index >= _pool.size():
		return
	_pool[index].visible = false
	if not index in _free_pool:
		_free_pool.append(index)

func _tracer_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color * 0.9
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.5
	m.disable_receive_shadows = true
	_mat_cache[key] = m
	return m

func _tracer_mesh(size: float) -> Mesh:
	var key := snappedf(size, 0.2)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	# capsule: never reads as a square when seen end-on (unlike a box)
	var cm := CapsuleMesh.new()
	cm.radius = 0.06 * size
	cm.height = 1.7 * size
	cm.radial_segments = 6
	cm.rings = 1
	_mesh_cache[key] = cm
	return cm

func fire_bullet(shooter: Node3D, muzzle: Vector3, dir: Vector3, wpn: Dictionary,
		team: int, inherit_vel: Vector3) -> bool:
	if _free_pool.is_empty() or shooter == null or not is_instance_valid(shooter):
		return false
	if not dir.is_finite() or dir.length_squared() < 0.0001:
		return false
	var pool_index: int = int(_free_pool.pop_back())
	var mi: MeshInstance3D = _pool[pool_index]
	var spread: float = deg_to_rad(wpn.spread)
	if spread > 0.0:
		dir = dir.rotated(dir.cross(Vector3.UP).normalized() if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT, randf_range(-spread, spread))
		dir = dir.rotated(dir.cross(Vector3.RIGHT).normalized() if absf(dir.dot(Vector3.RIGHT)) < 0.99 else Vector3.UP, randf_range(-spread, spread))
	dir = dir.normalized()
	var vel: Vector3 = dir * float(wpn.speed) + inherit_vel
	mi.mesh = _tracer_mesh(wpn.size)
	mi.material_override = _tracer_mat(wpn.color)
	mi.visible = true
	mi.global_position = muzzle
	if vel.length() > 0.1:
		mi.look_at(muzzle + vel.normalized(), Vector3.UP if absf(vel.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
		mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)  # capsule length axis is Y
	_active.append({
		"mi": mi, "pos": muzzle, "vel": vel,
		"pool_index": pool_index,
		"ttl": wpn.range / maxf(wpn.speed, 1.0) * 1.15,
		"dmg": wpn.dmg, "pen": wpn.pen, "sh": wpn.sh, "hu": wpn.hu,
		"team": team, "shooter": shooter,
		"excl": [shooter.get_rid()] if shooter is CollisionObject3D else [],
	})
	return true

func _physics_process(delta: float) -> void:
	if _active.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var i := _active.size() - 1
	while i >= 0:
		var b: Dictionary = _active[i]
		var mi: MeshInstance3D = b.mi
		b.ttl -= delta
		if b.ttl <= 0.0:
			_release_bullet(int(b.pool_index))
			_active.remove_at(i)
			i -= 1
			continue
		var new_pos: Vector3 = b.pos + b.vel * delta
		var q := PhysicsRayQueryParameters3D.create(b.pos, new_pos)
		q.exclude = b.excl
		q.collision_mask = 0xFFFFFFFF
		var hit := space.intersect_ray(q)
		if hit and _resolve_hit(b, hit):
			_release_bullet(int(b.pool_index))
			_active.remove_at(i)
			i -= 1
		else:
			b.pos = new_pos
			mi.global_position = new_pos
			i -= 1

func _resolve_hit(b: Dictionary, hit: Dictionary) -> bool:
	var col: Object = hit.collider
	var target: Node = col as Node
	# find damage receiver
	var recv: Node = null
	var n := target
	while n:
		if n.has_method("take_hit"):
			recv = n
			break
		n = n.get_parent()
	if recv:
		var rteam := _receiver_team(recv)
		if rteam >= 0 and rteam == int(b.team):
			return false   # pass through friendlies
		var was_shield: bool = "shield_front" in recv \
			and (recv.shield_front > 0.0 or recv.shield_rear > 0.0)
		recv.take_hit(b.dmg, hit.position, b.vel.normalized(), b.pen, b.sh, b.hu,
			b.shooter, hit.get("normal", Vector3.ZERO))
		var reactive := recv.is_in_group("reactive_surface")
		var kind: String = str(recv.get_meta("surface_kind", "metal"))
		if reactive:
			# AsteroidBody/Wreck owns its rate-limited repeated-hit response.
			pass
		elif was_shield:
			FX.shield_hit(self, hit.position)
		else:
			FX.surface_impact(self, recv as Node3D, hit.position,
				hit.get("normal", Vector3.ZERO), "metal", float(b.dmg), true)
		if is_instance_valid(b.shooter) and b.shooter.is_in_group("player"):
			if rteam >= 0:
				player_hit_confirmed.emit(recv, was_shield)
			else:
				player_surface_hit.emit(recv, kind)
		AudioMgr.play_3d("hit_rock" if kind == "rock" else (
			"hit_shield" if was_shield else "hit_armor"), hit.position, -6.0)
	else:
		FX.surface_impact(self, self, hit.position, hit.get("normal", Vector3.ZERO),
			"rock", float(b.dmg), true)
		AudioMgr.play_3d("hit_rock", hit.position, -8.0)
	return true

func _receiver_team(recv: Node) -> int:
	if "team" in recv:
		return int(recv.team)
	if "owner_ship" in recv and recv.owner_ship and "team" in recv.owner_ship:
		return int(recv.owner_ship.team)
	return -1

## Continuous beam: damages and returns end point for rendering.
func beam_tick(shooter: Node3D, muzzle: Vector3, dir: Vector3, wpn: Dictionary,
		team: int, delta: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	var to: Vector3 = muzzle + dir * wpn.range
	var q := PhysicsRayQueryParameters3D.create(muzzle, to)
	if shooter is CollisionObject3D:
		q.exclude = [shooter.get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		var recv: Node = null
		var n: Node = hit.collider
		while n:
			if n.has_method("take_hit"):
				recv = n
				break
			n = n.get_parent()
		if recv:
			var rteam := _receiver_team(recv)
			if rteam != team:
				var was_shield: bool = "shield_front" in recv \
					and (recv.shield_front > 0.0 or recv.shield_rear > 0.0)
				recv.take_hit(wpn.dmg * delta, hit.position, dir, wpn.pen, wpn.sh,
					wpn.hu, shooter, hit.get("normal", Vector3.ZERO))
				var reactive := recv.is_in_group("reactive_surface")
				if reactive:
					if is_instance_valid(shooter) and shooter.is_in_group("player") \
							and randf() < delta * 6.0:
						player_surface_hit.emit(recv, str(recv.get_meta("surface_kind", "metal")))
				elif randf() < delta * 8.0:
					if was_shield:
						FX.shield_hit(self, hit.position)
					else:
						FX.surface_impact(self, recv as Node3D, hit.position,
							hit.get("normal", Vector3.ZERO), "metal",
							float(wpn.dmg) * delta, randf() < 0.35)
				if is_instance_valid(shooter) and shooter.is_in_group("player") \
						and rteam >= 0 and randf() < delta * 6.0:
					player_hit_confirmed.emit(recv, was_shield)
		elif randf() < delta * 8.0:
			FX.surface_impact(self, self, hit.position, hit.get("normal", Vector3.ZERO),
				"rock", float(wpn.dmg) * delta, randf() < 0.25)
		return hit.position
	return to

## Mathematical lead solution: where to aim so a projectile at speed s hits the target.
static func lead_point(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3,
		target_vel: Vector3, target_acc: Vector3, proj_speed: float) -> Vector3:
	proj_speed = maxf(proj_speed, 1.0)
	var rel_pos := target_pos - shooter_pos
	var rel_vel := target_vel - shooter_vel
	# solve |rel_pos + rel_vel*t + 0.5*acc*t^2| = s*t  (iterate twice for acc)
	var a := rel_vel.dot(rel_vel) - proj_speed * proj_speed
	var bq := 2.0 * rel_pos.dot(rel_vel)
	var c := rel_pos.dot(rel_pos)
	var t := 0.0
	if absf(a) < 0.001:
		t = -c / bq if absf(bq) > 0.001 else 0.0
	else:
		var disc := bq * bq - 4.0 * a * c
		if disc < 0.0:
			t = rel_pos.length() / proj_speed
		else:
			var sq := sqrt(disc)
			var t1 := (-bq - sq) / (2.0 * a)
			var t2 := (-bq + sq) / (2.0 * a)
			t = minf(t1, t2) if minf(t1, t2) > 0.0 else maxf(t1, t2)
	t = clampf(t, 0.0, 6.0)
	# one refinement step including estimated acceleration
	var predicted := target_pos + target_vel * t + target_acc * (0.5 * t * t) - shooter_vel * t
	return predicted
