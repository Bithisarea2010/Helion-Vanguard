class_name Projectiles
extends Node3D
## Pooled raycast projectiles + beams. One instance lives in the Battle scene.
##
## Rendering is a SINGLE MultiMesh (see `shaders/tracer.gdshader`). The old pool
## of 320 `MeshInstance3D` nodes with a material per weapon colour meant a heavy
## furball could add hundreds of draw calls; colour and brightness now travel in
## INSTANCE_CUSTOM so the whole pool is one instanced draw.
##
## Bullet mechanics beyond "hit and stop" live here too: pierce (railgun), chain
## (arc projector) and shield bypass (phase disruptor). Pellet spread is applied
## by the caller, which just fires N bullets.

signal player_hit_confirmed(target: Node, was_shield: bool)
signal player_surface_hit(target: Node, kind: String)

const POOL := 320

var _active: Array[Dictionary] = []
var _mmi: MultiMeshInstance3D
var _mm: MultiMesh

func _ready() -> void:
	var cm := CapsuleMesh.new()
	# unit capsule: the per-instance transform carries the real length/radius
	cm.radius = 0.06
	cm.height = 1.7
	cm.radial_segments = 6
	cm.rings = 1
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = cm
	_mm.instance_count = POOL
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/tracer.gdshader")
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# tracers span the whole battle space; a mesh-derived AABB would cull them
	_mmi.custom_aabb = AABB(Vector3.ONE * -20000.0, Vector3.ONE * 40000.0)
	add_child(_mmi)

func has_bullet_capacity() -> bool:
	return _active.size() < POOL

func fire_bullet(shooter: Node3D, muzzle: Vector3, dir: Vector3, wpn: Dictionary,
		team: int, inherit_vel: Vector3, spread_mult := 1.0,
		guide := 0.0, guide_target: Node3D = null) -> bool:
	if _active.size() >= POOL or shooter == null or not is_instance_valid(shooter):
		return false
	if not dir.is_finite() or dir.length_squared() < 0.0001:
		return false
	var spread: float = deg_to_rad(float(wpn.spread) * spread_mult)
	if spread > 0.0:
		dir = dir.rotated(dir.cross(Vector3.UP).normalized() if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT, randf_range(-spread, spread))
		dir = dir.rotated(dir.cross(Vector3.RIGHT).normalized() if absf(dir.dot(Vector3.RIGHT)) < 0.99 else Vector3.UP, randf_range(-spread, spread))
	dir = dir.normalized()
	var vel: Vector3 = dir * float(wpn.speed) + inherit_vel
	var col: Color = wpn.color
	_active.append({
		"pos": muzzle, "vel": vel,
		"size": float(wpn.size),
		"tint": Color(col.r, col.g, col.b, 3.4),
		# a curving round covers more ground than a straight one, so a guided shot
		# gets the extra flight time it needs to actually arrive
		"ttl": wpn.range / maxf(wpn.speed, 1.0) * (1.55 if guide > 0.0 else 1.15),
		"dmg": float(wpn.dmg), "pen": wpn.pen, "sh": wpn.sh, "hu": wpn.hu,
		"team": team, "shooter": shooter,
		# --- extended mechanics; all default to inert -----------------------
		"pierce": int(wpn.get("pierce", 0)),
		"pierce_falloff": float(wpn.get("pierce_falloff", 0.7)),
		"chain": int(wpn.get("chain", 0)),
		"chain_range": float(wpn.get("chain_range", 0.0)),
		"chain_falloff": float(wpn.get("chain_falloff", 0.6)),
		"bypass": bool(wpn.get("bypass_shield", false)),
		# smart rounds: the targeting computer's upper half fires munitions that
		# correct in flight, which is the only way a ballistic weapon can answer a
		# target that accelerates after the trigger was pulled
		"guide": guide,
		"gtarget": guide_target,
		"excl": [shooter.get_rid()] if shooter is CollisionObject3D else [],
	})
	return true

func _physics_process(delta: float) -> void:
	if _active.is_empty():
		if _mm.visible_instance_count != 0:
			_mm.visible_instance_count = 0
		return
	var space := get_world_3d().direct_space_state
	var i := _active.size() - 1
	while i >= 0:
		var b: Dictionary = _active[i]
		b.ttl -= delta
		if b.ttl <= 0.0:
			_active.remove_at(i)
			i -= 1
			continue
		_steer(b, delta)
		# A pierced round resolves several hits inside one step, so this loops
		# until the segment is clear rather than testing once per frame.
		var remaining_dt := delta
		var consumed := false
		var guard := 0
		while remaining_dt > 0.0 and guard < 6:
			guard += 1
			var new_pos: Vector3 = b.pos + b.vel * remaining_dt
			var q := PhysicsRayQueryParameters3D.create(b.pos, new_pos)
			q.exclude = b.excl
			q.collision_mask = 0xFFFFFFFF
			var hit := space.intersect_ray(q)
			if not hit:
				b.pos = new_pos
				break
			var travelled: float = (hit.position as Vector3).distance_to(b.pos)
			var seg: float = maxf((b.vel as Vector3).length() * remaining_dt, 0.001)
			remaining_dt *= clampf(1.0 - travelled / seg, 0.0, 1.0)
			if _resolve_hit(b, hit):
				consumed = true
				break
			# survived (pierce): step just past the surface and keep the RID out
			if hit.collider is CollisionObject3D:
				b.excl.append((hit.collider as CollisionObject3D).get_rid())
			b.pos = hit.position + (b.vel as Vector3).normalized() * 0.4
		if consumed:
			_active.remove_at(i)
		i -= 1
	_upload_instances()

## Smart-round correction. Deliberately capped: a round that can turn hard enough
## to reach anything is a homing missile, and it stops reading as gunfire.
func _steer(b: Dictionary, delta: float) -> void:
	var rate: float = b.guide
	if rate <= 0.0:
		return
	# Deliberately UNTYPED. A guided round routinely outlives the ship it was
	# fired at, and `var t: Node3D = <freed>` is itself an error in Godot 4
	# ("Trying to assign invalid previously freed instance") — the typed
	# assignment validates before any `is_instance_valid` check can run.
	var raw = b.gtarget
	if raw == null or not is_instance_valid(raw) or ("alive" in raw and not raw.alive):
		# Re-acquire rather than going ballistic. Rounds are in the air for up to
		# two seconds; in a dense fight the ship they were fired at is often
		# already dead by the time they arrive, and every one of those was
		# counting as a miss against the fire-control loop.
		var s = b.shooter
		var st = s.target if (is_instance_valid(s) and "target" in s) else null
		if st != null and is_instance_valid(st) and (not ("alive" in st) or st.alive):
			b.gtarget = st
			raw = st
		else:
			b.guide = 0.0
			return
	var t := raw as Node3D
	if t == null:
		b.guide = 0.0
		return
	var v: Vector3 = b.vel
	var speed := v.length()
	if speed < 1.0:
		return
	var cur := v / speed
	var lead := lead_point(b.pos, Vector3.ZERO, t.global_position,
		t.get_velocity() if t.has_method("get_velocity") else Vector3.ZERO,
		Vector3.ZERO, speed)
	var want := (lead - (b.pos as Vector3))
	if want.length_squared() < 0.01:
		return
	want = want.normalized()
	var ang := cur.angle_to(want)
	if ang < 0.0001:
		return
	var axis := cur.cross(want)
	if axis.length_squared() < 1e-8:
		return
	b.vel = cur.rotated(axis.normalized(), minf(ang, rate * delta)) * speed

## One MultiMesh write per active bullet, packed at the front of the buffer so
## `visible_instance_count` alone controls how much is drawn.
func _upload_instances() -> void:
	var n := mini(_active.size(), POOL)
	for i in n:
		var b: Dictionary = _active[i]
		var v: Vector3 = b.vel
		var dir := v.normalized() if v.length_squared() > 0.01 else Vector3.FORWARD
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var right := up.cross(dir).normalized()
		var real_up := dir.cross(right).normalized()
		# CapsuleMesh runs along +Y: basis = (right, along, up)
		var s: float = b.size
		var basis := Basis(right * s, dir * s, real_up * s)
		_mm.set_instance_transform(i, Transform3D(basis, b.pos))
		_mm.set_instance_custom_data(i, b.tint)
	_mm.visible_instance_count = n

## Returns true when the bullet is consumed by the hit.
func _resolve_hit(b: Dictionary, hit: Dictionary) -> bool:
	var col: Object = hit.collider
	var target: Node = col as Node
	var recv: Node = null
	var n := target
	while n:
		if n.has_method("take_hit"):
			recv = n
			break
		n = n.get_parent()
	if recv == null:
		FX.surface_impact(self, self, hit.position, hit.get("normal", Vector3.ZERO),
			"rock", float(b.dmg), true)
		AudioMgr.play_3d("hit_rock", hit.position, -8.0)
		return true
	var rteam := _receiver_team(recv)
	if rteam >= 0 and rteam == int(b.team):
		return false   # pass through friendlies (and do not spend a pierce)
	var bypass: bool = b.bypass
	var sh_mult: float = 0.0 if bypass else float(b.sh)
	var was_shield: bool = not bypass and "shield_front" in recv \
		and (recv.shield_front > 0.0 or recv.shield_rear > 0.0)
	recv.take_hit(b.dmg, hit.position, (b.vel as Vector3).normalized(), b.pen, sh_mult,
		b.hu, b.shooter, hit.get("normal", Vector3.ZERO))
	var reactive := recv.is_in_group("reactive_surface")
	var kind: String = str(recv.get_meta("surface_kind", "metal"))
	if reactive:
		pass   # AsteroidBody/Wreck own their rate-limited repeated-hit response
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
	if int(b.chain) > 0:
		_chain_from(b, recv, hit.position)
	if int(b.pierce) > 0:
		b.pierce = int(b.pierce) - 1
		b.dmg = float(b.dmg) * float(b.pierce_falloff)
		return false
	return true

## Arc projector: jump to nearby hostiles, each jump weaker than the last.
func _chain_from(b: Dictionary, first: Node, from: Vector3) -> void:
	var battle := get_parent()
	if battle == null or not battle.has_method("hostile_targets"):
		return
	var pool: Array = battle.hostile_targets() if int(b.team) == Combatant.TEAM_FRIEND \
		else battle.friendly_targets()
	var seen := {first.get_instance_id(): true}
	var src := from
	var dmg := float(b.dmg) * float(b.chain_falloff)
	var r2: float = float(b.chain_range) * float(b.chain_range)
	for _j in int(b.chain):
		var best: Node = null
		var best_d := r2
		for c in pool:
			if not is_instance_valid(c) or seen.has(c.get_instance_id()):
				continue
			if "alive" in c and not c.alive:
				continue
			var d: float = src.distance_squared_to(c.global_position)
			if d < best_d:
				best_d = d
				best = c
		if best == null:
			return
		seen[best.get_instance_id()] = true
		var to: Vector3 = best.global_position
		FX.arc_bolt(self, src, to, b.tint)
		best.take_hit(dmg, to, (to - src).normalized(), float(b.pen), float(b.sh),
			float(b.hu), b.shooter, (src - to).normalized())
		if is_instance_valid(b.shooter) and b.shooter.is_in_group("player"):
			player_hit_confirmed.emit(best, false)
		src = to
		dmg *= float(b.chain_falloff)

## Total damage already in the air aimed at `t`. Used by the fire-control
## computer to stop pouring rounds into a target that is already dead — the
## flight time of a 750 m/s round across 400 m is half a second, which at 8
## rounds a second is four more shots into a drone the first one killed.
func pending_damage_to(t: Node3D) -> float:
	if t == null or _active.is_empty():
		return 0.0
	var total := 0.0
	for b in _active:
		if b.gtarget == t:
			total += float(b.dmg)
	return total

func _receiver_team(recv: Node) -> int:
	if "team" in recv:
		return int(recv.team)
	if "owner_ship" in recv and recv.owner_ship and "team" in recv.owner_ship:
		return int(recv.owner_ship.team)
	return -1

## Continuous beam: damages and returns end point for rendering.
## `dmg_scale` is how the Singularity Lance's charge-up is applied without
## allocating a mutated weapon dictionary every physics frame.
func beam_tick(shooter: Node3D, muzzle: Vector3, dir: Vector3, wpn: Dictionary,
		team: int, delta: float, dmg_scale := 1.0) -> Vector3:
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
				recv.take_hit(wpn.dmg * delta * dmg_scale, hit.position, dir, wpn.pen,
					wpn.sh, wpn.hu, shooter, hit.get("normal", Vector3.ZERO))
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
