class_name AsteroidField
extends Node3D
## Thousands of instanced asteroids + a pool of physics colliders near the player.
##
## Rocks live in a flat array plus a uniform spatial hash. The collider pool only
## ever scans the 27 hash cells around the player, so field size no longer drives
## per-tick cost (the old full-array scan + sort of ~1700 rocks was the source of
## the periodic 13 ms physics spikes).

const PHYS_POOL := 26
const PHYS_RANGE := 700.0
const HASH_CELL := 700.0             # == PHYS_RANGE, so 3x3x3 cells always cover it
const CHUNK_CELL := 2400.0           # MultiMesh chunk size; bigger = fewer draw calls

var _meshes: Array[Mesh] = []
var _mm_nodes: Array[MultiMeshInstance3D] = []
var _rocks: Array = []               # per rock: {pos, scale, variant, rot}
var _grid := {}                      # Vector3i cell -> PackedInt32Array of rock indices
var _phys: Array[AsteroidBody] = []
var _phys_timer := 0.0
var _shader_mat: ShaderMaterial = null
var player: Node3D = null

func _ready() -> void:
	for i in 4:
		var path := "res://assets/models/asteroid_%d.glb" % i
		if ResourceLoader.exists(path):
			var inst: Node3D = (load(path) as PackedScene).instantiate()
			var found := inst.find_children("*", "MeshInstance3D", true)
			if not found.is_empty():
				var mi := found[0] as MeshInstance3D
				_meshes.append(mi.mesh)
				if _shader_mat == null:
					_shader_mat = _build_rock_material(mi.mesh)
				# every chunk binds _shader_mat as material_override, so the
				# embedded material is dead weight — clearing it releases the
				# duplicated 3.9 MB texture set each GLB carries
				for s in mi.mesh.get_surface_count():
					mi.mesh.surface_set_material(s, null)
			inst.queue_free()
	if _meshes.is_empty():
		var fallback := SphereMesh.new()
		fallback.radius = 1.0
		_meshes.append(fallback)
	for i in PHYS_POOL:
		var sb := AsteroidBody.new()
		sb.setup(self)
		var cs := CollisionShape3D.new()
		cs.shape = SphereShape3D.new()
		sb.add_child(cs)
		add_child(sb)
		sb.position = Vector3(0, -100000 - i * 200, 0)
		_phys.append(sb)

## One ShaderMaterial shared by every rock variant: the four source GLBs embed
## byte-identical texture sets, so binding one material for all of them removes
## three redundant copies from VRAM and lets the chunks batch.
##
## The albedo now comes from the standalone `assets/textures/asteroid_albedo.png`
## and the embedded materials are cleared off the meshes afterwards, so the four
## duplicated copies inside the GLBs are dropped rather than merely unused.
func _build_rock_material(src_mesh: Mesh) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/asteroid.gdshader")
	const STANDALONE := "res://assets/textures/asteroid_albedo.png"
	if ResourceLoader.exists(STANDALONE):
		sm.set_shader_parameter("albedo_tex", load(STANDALONE))
	else:
		var base := src_mesh.surface_get_material(0)
		if base is BaseMaterial3D and (base as BaseMaterial3D).albedo_texture:
			sm.set_shader_parameter("albedo_tex", (base as BaseMaterial3D).albedo_texture)
	return sm

## Belt: a thick ring of rocks around center in the XZ plane.
func populate_belt(center: Vector3, radius: float, tube: float, count: int, seed_v := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	count = int(count * Game.preset().ast_density)
	for i in count:
		var a := rng.randf() * TAU
		var r := radius + rng.randfn(0.0, tube * 0.45)
		var y := rng.randfn(0.0, tube * 0.35)
		_push_rock(center + Vector3(cos(a) * r, y, sin(a) * r), rng)

## Cluster: gaussian blob of rocks.
func populate_cluster(center: Vector3, radius: float, count: int, seed_v := 2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	count = int(count * Game.preset().ast_density)
	for i in count:
		_push_rock(center + Vector3(rng.randfn(0, radius * 0.4), rng.randfn(0, radius * 0.3),
			rng.randfn(0, radius * 0.4)), rng)

func _push_rock(pos: Vector3, rng: RandomNumberGenerator) -> void:
	_rocks.append({
		"pos": pos, "scale": _rand_scale(rng), "variant": rng.randi() % _meshes.size(),
		"rot": Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1),
			rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU),
		# INSTANCE_CUSTOM for the shader: mineral mix, brightness, crater seed,
		# ice roll. Four meshes shared across ~1,700 rocks look like four rocks
		# repeated without it.
		"cd": Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())})

func _rand_scale(rng: RandomNumberGenerator) -> float:
	# mostly small rocks, a few giants
	var t := rng.randf()
	if t > 0.985:
		return rng.randf_range(28.0, 60.0)
	if t > 0.9:
		return rng.randf_range(12.0, 26.0)
	return rng.randf_range(2.0, 10.0)

## Reserve authored approach lanes before commit, including each rock's radius.
func reserve_sphere(center: Vector3, radius: float) -> void:
	assert(_mm_nodes.is_empty(), "Reserve lanes before committing the asteroid field")
	_rocks = _rocks.filter(func(rock):
		return (rock.pos as Vector3).distance_to(center) > radius + float(rock.scale) * 1.1)

## Call after populate_* to build the MultiMeshes (chunked for culling).
func commit() -> void:
	for n in _mm_nodes:
		n.queue_free()
	_mm_nodes.clear()
	_grid.clear()
	if _rocks.is_empty():
		return
	# spatial hash for the collider pool
	for i in _rocks.size():
		var c := _hash_cell(_rocks[i].pos)
		if not _grid.has(c):
			_grid[c] = PackedInt32Array()
		_grid[c].append(i)
	# bucket rocks by variant and spatial chunk for rendering
	var buckets := {}
	for rk in _rocks:
		var cell := Vector3i((rk.pos / CHUNK_CELL).floor())
		var key := "%d_%d_%d_%d" % [rk.variant, cell.x, cell.y, cell.z]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(rk)
	for key in buckets:
		var list: Array = buckets[key]
		var variant: int = list[0].variant
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[variant]
		mm.instance_count = list.size()
		var mid := Vector3.ZERO
		for rk in list:
			mid += rk.pos
		mid /= list.size()
		# exact chunk bounds beat the old fixed +/-900 m box: tighter culling and
		# no popping when a 60 m giant sits on a chunk edge
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for i in list.size():
			var rk: Dictionary = list[i]
			var local: Vector3 = rk.pos - mid
			var xf := Transform3D(rk.rot.scaled(Vector3.ONE * rk.scale), local)
			mm.set_instance_transform(i, xf)
			mm.set_instance_custom_data(i, rk.get("cd", Color(0.5, 0.5, 0.5, 0.5)))
			var rad: float = rk.scale * 1.05
			lo = lo.min(local - Vector3.ONE * rad)
			hi = hi.max(local + Vector3.ONE * rad)
		mm.custom_aabb = AABB(lo, hi - lo)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 9000.0
		mmi.visibility_range_end_margin = 500.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _shader_mat:
			mmi.material_override = _shader_mat
		add_child(mmi)
		mmi.position = mid
		_mm_nodes.append(mmi)

func _hash_cell(p: Vector3) -> Vector3i:
	return Vector3i((p / HASH_CELL).floor())

func _physics_process(delta: float) -> void:
	_phys_timer -= delta
	if _phys_timer > 0.0 or player == null or not is_instance_valid(player):
		return
	_phys_timer = 0.5
	# only the 27 hash cells around the player can hold a rock within PHYS_RANGE
	var ppos: Vector3 = player.global_position
	var base := _hash_cell(ppos)
	var near: Array = []
	var r2 := PHYS_RANGE * PHYS_RANGE
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var ids: PackedInt32Array = _grid.get(base + Vector3i(dx, dy, dz), PackedInt32Array())
				for idx in ids:
					var rk: Dictionary = _rocks[idx]
					var d: float = (rk.pos as Vector3).distance_squared_to(ppos)
					if d < r2:
						near.append([d, rk, idx])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var n := mini(near.size(), _phys.size())
	for i in _phys.size():
		var sb: AsteroidBody = _phys[i]
		if i < n:
			var rk: Dictionary = near[i][1]
			sb.position = rk.pos
			sb.rock_radius = rk.scale
			sb.rock_index = int(near[i][2])
			var cs := sb.get_child(0) as CollisionShape3D
			(cs.shape as SphereShape3D).radius = rk.scale * 0.92
		else:
			sb.position = Vector3(0, -100000 - i * 200, 0)
			sb.rock_index = -1
