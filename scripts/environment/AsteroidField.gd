class_name AsteroidField
extends Node3D
## Thousands of instanced asteroids + a pool of physics colliders near the player.

const PHYS_POOL := 26
const PHYS_RANGE := 700.0

var _meshes: Array[Mesh] = []
var _mm_nodes: Array[MultiMeshInstance3D] = []
var _rocks: Array = []              # per rock: {pos, scale, variant}
var _phys: Array[StaticBody3D] = []
var _phys_timer := 0.0
var player: Node3D = null

func _ready() -> void:
	for i in 4:
		var path := "res://assets/models/asteroid_%d.glb" % i
		if ResourceLoader.exists(path):
			var inst: Node3D = (load(path) as PackedScene).instantiate()
			var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true)[0] if not inst.find_children("*", "MeshInstance3D", true).is_empty() else null
			if mi:
				_meshes.append(mi.mesh)
			inst.queue_free()
	if _meshes.is_empty():
		var fallback := SphereMesh.new()
		fallback.radius = 1.0
		_meshes.append(fallback)
	for i in PHYS_POOL:
		var sb := StaticBody3D.new()
		sb.collision_layer = 2
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = SphereShape3D.new()
		sb.add_child(cs)
		add_child(sb)
		sb.position = Vector3(0, -100000 - i * 200, 0)
		sb.add_to_group("asteroid")
		_phys.append(sb)

## Belt: a thick ring of rocks around center in the XZ plane.
func populate_belt(center: Vector3, radius: float, tube: float, count: int, seed_v := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	count = int(count * Game.preset().ast_density)
	for i in count:
		var a := rng.randf() * TAU
		var r := radius + rng.randfn(0.0, tube * 0.45)
		var y := rng.randfn(0.0, tube * 0.35)
		var pos := center + Vector3(cos(a) * r, y, sin(a) * r)
		_rocks.append({"pos": pos, "scale": _rand_scale(rng), "variant": rng.randi() % _meshes.size(),
			"rot": Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU)})

## Cluster: gaussian blob of rocks.
func populate_cluster(center: Vector3, radius: float, count: int, seed_v := 2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	count = int(count * Game.preset().ast_density)
	for i in count:
		var pos := center + Vector3(rng.randfn(0, radius * 0.4), rng.randfn(0, radius * 0.3), rng.randfn(0, radius * 0.4))
		_rocks.append({"pos": pos, "scale": _rand_scale(rng), "variant": rng.randi() % _meshes.size(),
			"rot": Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU)})

func _rand_scale(rng: RandomNumberGenerator) -> float:
	# mostly small rocks, a few giants
	var t := rng.randf()
	if t > 0.985:
		return rng.randf_range(28.0, 60.0)
	if t > 0.9:
		return rng.randf_range(12.0, 26.0)
	return rng.randf_range(2.0, 10.0)

## Call after populate_* to build the MultiMeshes (chunked for culling).
func commit() -> void:
	for n in _mm_nodes:
		n.queue_free()
	_mm_nodes.clear()
	if _rocks.is_empty():
		return
	# bucket rocks by variant and spatial chunk (1.6 km cells)
	var buckets := {}
	for rk in _rocks:
		var cell := Vector3i((rk.pos / 1600.0).floor())
		var key := "%d_%d_%d_%d" % [rk.variant, cell.x, cell.y, cell.z]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(rk)
	for key in buckets:
		var list: Array = buckets[key]
		var variant: int = list[0].variant
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[variant]
		mm.instance_count = list.size()
		var mid := Vector3.ZERO
		for rk in list:
			mid += rk.pos
		mid /= list.size()
		for i in list.size():
			var rk: Dictionary = list[i]
			var xf := Transform3D(rk.rot.scaled(Vector3.ONE * rk.scale), rk.pos - mid)
			mm.set_instance_transform(i, xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 9000.0
		mmi.visibility_range_end_margin = 500.0
		add_child(mmi)
		mmi.position = mid
		var aabb := AABB(Vector3(-900, -900, -900), Vector3(1800, 1800, 1800))
		mm.custom_aabb = aabb
		_mm_nodes.append(mmi)

func _physics_process(delta: float) -> void:
	_phys_timer -= delta
	if _phys_timer > 0.0 or player == null or not is_instance_valid(player):
		return
	_phys_timer = 0.5
	# nearest rocks get physics colliders
	var ppos: Vector3 = player.global_position
	var near: Array = []
	for rk in _rocks:
		var d: float = rk.pos.distance_squared_to(ppos)
		if d < PHYS_RANGE * PHYS_RANGE:
			near.append([d, rk])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var n := mini(near.size(), _phys.size())
	for i in _phys.size():
		var sb := _phys[i]
		if i < n:
			var rk: Dictionary = near[i][1]
			sb.position = rk.pos
			var cs := sb.get_child(0) as CollisionShape3D
			(cs.shape as SphereShape3D).radius = rk.scale * 0.92
		else:
			sb.position = Vector3(0, -100000 - i * 200, 0)

func nearest_rock_distance(pos: Vector3) -> float:
	var best := INF
	for rk in _rocks:
		best = minf(best, rk.pos.distance_to(pos) - rk.scale)
	return best

func is_clear(pos: Vector3, clearance: float) -> bool:
	for rk in _rocks:
		if rk.pos.distance_to(pos) < rk.scale + clearance:
			return false
	return true
