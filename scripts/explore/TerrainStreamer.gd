class_name TerrainStreamer
extends Node3D
## Cube-sphere quadtree. Workers own noise/arrays; mesh uploads and physics stay on main thread.
## A parent is hidden only when all four child meshes exist. Skirts seal mixed LOD edges.
const GRID := 24
const MAX_LEVEL := 11
const MAX_WORKERS := 2
var planet: PlanetDefinition
var chunks: Dictionary = {}
var wanted: Dictionary = {}
var jobs: Dictionary = {}
var material: ShaderMaterial
var focus := Vector3.ZERO
var refresh := 0.0
var max_upload_ms := 0.0
var ready_roots := false
var generated_count := 0
var collision_count := 0

class TileJob extends RefCounted:
	var planet: PlanetDefinition
	var tile: Vector4i
	var arrays: Array = []
	var center := Vector3.ZERO
	var faces := PackedVector3Array()
	func generate() -> void:
		var sampler := PlanetSampler.new(planet)
		var size := 2.0 / float(1 << tile.y)
		var u := -1.0 + tile.z * size
		var v := -1.0 + tile.w * size
		var middle := PlanetSampler.cube_direction(tile.x, u + size * 0.5, v + size * 0.5)
		center = middle * planet.radius
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for y in GRID + 1:
			for x in GRID + 1:
				var du := u + size * float(x) / GRID
				var dv := v + size * float(y) / GRID
				var direction := PlanetSampler.cube_direction(tile.x, du, dv)
				var h := sampler.height(direction)
				vertices.append(direction * (planet.radius + h) - center)
				var eps := 0.00005
				var da := PlanetSampler.cube_direction(tile.x, du + eps, dv)
				var db := PlanetSampler.cube_direction(tile.x, du, dv + eps)
				var pa := da * (planet.radius + sampler.height(da)) - center
				var pb := db * (planet.radius + sampler.height(db)) - center
				var normal := (pa - vertices[-1]).cross(pb - vertices[-1]).normalized()
				if normal.dot(direction) < 0: normal = -normal
				normals.append(normal)
				colors.append(sampler.surface_color(direction, h))
				uvs.append(Vector2(du, dv) * planet.radius)
		for y in GRID:
			for x in GRID:
				var a := y * (GRID + 1) + x
				# cube_direction face orientations are consistently outward in u cross v.
				for idx in [a, a + GRID + 2, a + 1, a, a + GRID + 1, a + GRID + 2]:
					indices.append(idx)
		# Godot uses clockwise front faces. Correct any face with a flipped basis.
		var cross_n := (vertices[indices[1]] - vertices[indices[0]]).cross(vertices[indices[2]] - vertices[indices[0]])
		if cross_n.dot(middle) > 0:
			for i in range(0, indices.size(), 3):
				var swap := indices[i + 1]
				indices[i + 1] = indices[i + 2]
				indices[i + 2] = swap
		if tile.y >= 9:
			for index in indices: faces.append(vertices[index])
		var edges: Array = [[], [], [], []]
		for i in GRID + 1:
			edges[0].append(i)
			edges[1].append(GRID * (GRID + 1) + i)
			edges[2].append(i * (GRID + 1))
			edges[3].append(i * (GRID + 1) + GRID)
		for edge in edges:
			var start := vertices.size()
			for idx in edge:
				vertices.append(vertices[idx] - (vertices[idx] + center).normalized() * maxf(2.0, size * planet.radius * 0.025))
				normals.append(normals[idx]); colors.append(colors[idx]); uvs.append(uvs[idx])
			for i in GRID:
				indices.append_array(PackedInt32Array([edge[i], start + i, edge[i+1], edge[i+1], start+i, start+i+1]))
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices

func setup(definition: PlanetDefinition) -> void:
	planet = definition
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/explore/terrain.gdshader")
	var texture := NoiseTexture2D.new()
	texture.width=512; texture.height=512; texture.seamless=true; texture.generate_mipmaps=true
	var noise := FastNoiseLite.new(); noise.seed=planet.terrain_seed; noise.frequency=0.035; noise.fractal_octaves=4
	texture.noise=noise
	material.set_shader_parameter("micro_texture",texture)
	material.set_shader_parameter("lunar",planet.is_moon)
	material.set_shader_parameter("ground_albedo",preload("res://assets/textures/explore/forest_ground_04_diff_1k.jpg"))
	material.set_shader_parameter("ground_normal",preload("res://assets/textures/explore/forest_ground_04_nor_gl_1k.jpg"))
	set_process(false)

func update_stream(planet_relative_focus: Vector3, dt: float) -> void:
	focus = planet_relative_focus
	refresh -= dt
	if refresh <= 0.0:
		refresh = 0.4
		wanted.clear()
		for face in 6: _select(Vector4i(face, 0, 0, 0))
		for key in chunks.keys():
			if not wanted.has(key):
				chunks[key].node.queue_free()
				chunks.erase(key)
	_consume_one()
	var candidates: Array = []
	for key in wanted:
		if not chunks.has(key) and not jobs.has(key): candidates.append(wanted[key])
	candidates.sort_custom(func(a, b):
		if a.y != b.y: return a.y < b.y
		return _center(a).distance_squared_to(focus) < _center(b).distance_squared_to(focus))
	for tile: Vector4i in candidates:
		if jobs.size() >= MAX_WORKERS: break
		var job := TileJob.new()
		job.planet = planet; job.tile = tile
		var task := WorkerThreadPool.add_task(job.generate, false, "Planet terrain")
		jobs[_key(tile)] = {"job": job, "task": task}
	ready_roots = true
	for face in 6:
		var root := Vector4i(face, 0, 0, 0)
		ready_roots = ready_roots and chunks.has(_key(root))
		_show_branch(root, true)
	_update_collision()

func _key(tile: Vector4i) -> String:
	return "%d/%d/%d/%d" % [tile.x, tile.y, tile.z, tile.w]

func _center(tile: Vector4i) -> Vector3:
	var size := 2.0 / float(1 << tile.y)
	return PlanetSampler.cube_direction(tile.x, -1.0 + (tile.z + 0.5) * size,
		-1.0 + (tile.w + 0.5) * size) * planet.radius

func _children(tile: Vector4i) -> Array[Vector4i]:
	return [Vector4i(tile.x, tile.y+1, tile.z*2, tile.w*2),
		Vector4i(tile.x, tile.y+1, tile.z*2+1, tile.w*2),
		Vector4i(tile.x, tile.y+1, tile.z*2, tile.w*2+1),
		Vector4i(tile.x, tile.y+1, tile.z*2+1, tile.w*2+1)]

func _select(tile: Vector4i) -> void:
	wanted[_key(tile)] = tile
	var width := planet.radius * 2.0 / float(1 << tile.y)
	if tile.y < MAX_LEVEL and _center(tile).distance_to(focus) < width * 1.5 + planet.terrain_amplitude:
		# Terrain amplitude ceases to influence subdivision once a patch is small;
		# use radial surface clearance to avoid splitting the whole mountain range.
		if tile.y > 4:
			var surface := _center(tile).normalized() * focus.length()
			if surface.distance_to(focus) > width * 2.0: return
			if absf(focus.length() - planet.radius) > width * 3.0 + planet.terrain_amplitude: return
		for child in _children(tile): _select(child)

func _consume_one() -> void:
	for key in jobs.keys():
		var entry: Dictionary = jobs[key]
		if not WorkerThreadPool.is_task_completed(entry.task): continue
		WorkerThreadPool.wait_for_task_completion(entry.task)
		jobs.erase(key)
		if not wanted.has(key): continue
		var started := Time.get_ticks_usec()
		var job: TileJob = entry.job
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.arrays)
		var instance := MeshInstance3D.new()
		instance.name = "Tile_" + key.replace("/", "_")
		instance.mesh = mesh
		instance.material_override = material
		instance.position = job.center
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		chunks[key] = {"node": instance, "tile": job.tile, "faces": job.faces, "body": null}
		generated_count += 1
		max_upload_ms = maxf(max_upload_ms, float(Time.get_ticks_usec() - started) / 1000.0)
		break

func _show_branch(tile: Vector4i, enabled: bool) -> void:
	var key := _key(tile)
	if not chunks.has(key): return
	var children := _children(tile)
	var split := true
	for child in children:
		if not wanted.has(_key(child)) or not chunks.has(_key(child)): split = false
	chunks[key].node.visible = enabled and not split
	for child in children: _show_branch(child, enabled and split)

func _update_collision() -> void:
	var added := false
	collision_count = 0
	for key in chunks:
		var c: Dictionary = chunks[key]
		var near: bool = c.node.visible and c.tile.y >= 9 and c.node.position.distance_to(focus) < 105.0
		if near and c.body == null and not added:
			var body := StaticBody3D.new()
			body.collision_layer = 2; body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var concave := ConcavePolygonShape3D.new()
			concave.set_faces(c.faces)
			concave.backface_collision = true
			shape.shape = concave
			body.add_child(shape)
			c.node.add_child(body)
			c.body = body
			added = true
		elif not near and c.body != null:
			c.body.queue_free(); c.body = null
		if c.body != null: collision_count += 1

func _exit_tree() -> void:
	# Join workers before releasing their resources; completed jobs are never uploaded after exit.
	for entry in jobs.values(): WorkerThreadPool.wait_for_task_completion(entry.task)
	jobs.clear()
