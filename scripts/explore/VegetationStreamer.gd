class_name VegetationStreamer
extends Node3D
## Deterministic biome scatter in 128 m cube-face cells. No per-tree scene nodes.
const CELL := 128.0
var sampler: PlanetSampler
var planet: PlanetDefinition
var patches: Dictionary = {}
var near_tree: ArrayMesh
var far_tree: ArrayMesh
var grass_mesh: ArrayMesh
var rock_mesh: SphereMesh
var material: ShaderMaterial
var rock_material: StandardMaterial3D
var collision_pool: Array[StaticBody3D] = []
var collision_clock := 0.0
var instance_count := 0
var max_build_ms := 0.0

func setup(definition: PlanetDefinition) -> void:
	planet=definition; sampler=PlanetSampler.new(planet)
	material=ShaderMaterial.new(); material.shader=preload("res://shaders/explore/vegetation.gdshader")
	var texture := NoiseTexture2D.new(); texture.width=128; texture.height=128; texture.seamless=true
	var noise := FastNoiseLite.new(); noise.seed=definition.vegetation_seed; noise.frequency=0.18; texture.noise=noise
	material.set_shader_parameter("foliage_noise",texture)
	near_tree=_tree_mesh(9); far_tree=_tree_mesh(4); grass_mesh=_grass_mesh()
	rock_mesh=SphereMesh.new(); rock_mesh.radius=0.8; rock_mesh.height=1.2; rock_mesh.radial_segments=8; rock_mesh.rings=4
	rock_material=StandardMaterial3D.new(); rock_material.albedo_color=Color(0.27,0.29,0.28); rock_material.roughness=0.95
	for i in 12:
		var body := StaticBody3D.new(); body.collision_layer=0; body.collision_mask=4
		var shape := CollisionShape3D.new(); var cylinder := CylinderShape3D.new(); cylinder.radius=0.3; cylinder.height=6.0
		shape.shape=cylinder; shape.position.y=3.0; body.add_child(shape); add_child(body); collision_pool.append(body)

func update_stream(focus: Vector3,dt: float) -> void:
	var altitude := focus.length()-planet.radius
	visible=altitude<1800.0
	if not visible:
		for body in collision_pool: body.collision_layer=0
		return
	var uv := _cube_uv(focus.normalized())
	var cell := Vector2i(floori((uv.y+1.0)*planet.radius/CELL),floori((uv.z+1.0)*planet.radius/CELL))
	var radius := 2 if int(Game.settings.preset)==0 else 3
	var wanted: Dictionary = {}
	var candidates: Array = []
	for y in range(-radius,radius+1):
		for x in range(-radius,radius+1):
			var c := cell+Vector2i(x,y)
			var key := "%d/%d/%d" % [int(uv.x),c.x,c.y]
			wanted[key]=true
			if not patches.has(key): candidates.append({"key":key,"face":int(uv.x),"cell":c,"distance":x*x+y*y})
	for key in patches.keys():
		if not wanted.has(key): patches[key].node.queue_free(); patches.erase(key)
	candidates.sort_custom(func(a,b): return a.distance<b.distance)
	if not candidates.is_empty():
		var started := Time.get_ticks_usec()
		_build_patch(candidates[0].key,candidates[0].face,candidates[0].cell)
		max_build_ms=maxf(max_build_ms,(Time.get_ticks_usec()-started)/1000.0)
	collision_clock-=dt
	if collision_clock<=0:
		collision_clock=0.35
		var nearby: Array[Transform3D] = []
		instance_count=0
		for patch in patches.values():
			instance_count+=patch.count
			for tree: Transform3D in patch.trees:
				if tree.origin.distance_to(focus)<22.0: nearby.append(tree)
		nearby.sort_custom(func(a,b): return a.origin.distance_squared_to(focus)<b.origin.distance_squared_to(focus))
		for i in collision_pool.size():
			collision_pool[i].collision_layer=2 if i<nearby.size() else 0
			if i<nearby.size(): collision_pool[i].transform=Transform3D(nearby[i].basis.orthonormalized(),nearby[i].origin)

func _build_patch(key: String,face: int,cell: Vector2i) -> void:
	var random := RandomNumberGenerator.new(); random.seed=planet.vegetation_seed+face*193939+cell.x*17713+cell.y*37217
	var center_dir := PlanetSampler.cube_direction(face,(cell.x+0.5)*CELL/planet.radius-1.0,(cell.y+0.5)*CELL/planet.radius-1.0)
	var center := center_dir*planet.radius
	var root := Node3D.new(); root.position=center; add_child(root)
	var trees: Array[Transform3D] = []
	var local_trees: Array[Transform3D] = []
	var grasses: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var count: int = [14,24,32,42][int(Game.settings.preset)]
	for i in count+120:
		var d := PlanetSampler.cube_direction(face,(cell.x+random.randf())*CELL/planet.radius-1.0,(cell.y+random.randf())*CELL/planet.radius-1.0)
		var height := sampler.height(d)
		if height<3.0: continue
		var biome := sampler.biome(d,height)
		var point := d*(planet.radius+height)
		var tangent := Vector3.FORWARD.slide(d).normalized()
		var orientation := Basis.looking_at(tangent,d).rotated(d,random.randf()*TAU)
		var clearing_distance := d.distance_to(planet.survey_direction.normalized())*planet.radius
		if i<count:
			if biome=="Temperate forest" and clearing_distance>34.0:
				var size := random.randf_range(0.8,1.65)
				var t := Transform3D(orientation.scaled(Vector3.ONE*size),point)
				trees.append(t); t.origin-=center; local_trees.append(t)
			elif clearing_distance>18.0:
				rocks.append(Transform3D(orientation.scaled(Vector3(random.randf_range(0.4,2.5),random.randf_range(0.4,1.7),random.randf_range(0.5,2.0))),point-center))
		elif biome in ["Temperate forest","Tundra","Coast"] and clearing_distance>16.0:
			grasses.append(Transform3D(orientation.scaled(Vector3.ONE*random.randf_range(0.45,1.1)),point-center))
	_add_batch(root,near_tree,local_trees,0,170,material)
	_add_batch(root,far_tree,local_trees,145,850,material)
	_add_batch(root,grass_mesh,grasses,0,130,material)
	_add_batch(root,rock_mesh,rocks,0,600,rock_material)
	patches[key]={"node":root,"trees":trees,"count":trees.size()+grasses.size()+rocks.size()}

func _add_batch(root: Node3D,mesh: Mesh,transforms: Array[Transform3D],begin: float,end: float,mat: Material) -> void:
	if transforms.is_empty(): return
	var multi := MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D; multi.mesh=mesh; multi.instance_count=transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i,transforms[i])
	var node := MultiMeshInstance3D.new(); node.multimesh=multi; node.material_override=mat
	node.visibility_range_begin=begin; node.visibility_range_end=end
	node.visibility_range_begin_margin=20.0; node.visibility_range_end_margin=20.0
	node.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if begin==0 and int(Game.settings.preset)>=1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)

func _tree_mesh(tiers: int) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new(); trunk.top_radius=0.06; trunk.bottom_radius=0.24; trunk.height=10.0; trunk.radial_segments=7
	_append(st,trunk,Vector3(0,5,0),Color(0.16,0.095,0.04,0.0))
	var rng := RandomNumberGenerator.new(); rng.seed=72034
	for i in tiers:
		var y := 1.6+float(i)/tiers*8.8
		var reach := (11.2-y)*0.28
		var branches := 7 if tiers<5 else 10
		for j in branches:
			var angle := j*TAU/branches+i*2.399+ rng.randf_range(-0.15,0.15)
			var length := reach*rng.randf_range(0.65,1.15)
			var out := Vector3(cos(angle),0,sin(angle))
			var cross := Vector3(-out.z,0,out.x)
			var color := Color(0.04,0.10,0.04)*rng.randf_range(0.8,1.35); color.a=1.0
			# Several irregular solid needle tufts give the crown volume without alpha overdraw.
			for k in (2 if tiers<5 else 4):
				var fraction := float(k+1)/(3.0 if tiers<5 else 5.0)
				var center := out*length*fraction+Vector3(0,y-length*fraction*0.22,0)
				var halfwidth := (1.0-fraction*0.6)*length*0.25
				var tip := center+out*length*0.34+Vector3(0,0.28,0)
				var points := [center-cross*halfwidth,center+cross*halfwidth,center+Vector3(0,halfwidth*0.8,0),center-Vector3(0,halfwidth*0.6,0),tip]
				for tri in [[0,2,4],[2,1,4],[1,3,4],[3,0,4],[0,3,2],[1,2,3]]:
					var normal: Vector3=(points[tri[1]]-points[tri[0]]).cross(points[tri[2]]-points[tri[0]]).normalized()
					for index in tri:
						st.set_color(color); st.set_normal(normal); st.set_uv(Vector2.ZERO); st.add_vertex(points[index])
	st.index(); return st.commit()

func _append(st: SurfaceTool,mesh: Mesh,offset: Vector3,color: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		st.set_color(color); st.set_normal(normals[index]); st.set_uv(uv[index]); st.add_vertex(vertices[index]+offset)

func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var direction := Vector3(cos(i*2.4),0,sin(i*2.4))*0.14
		for vertex in [-direction,direction,Vector3(0.12,0.7+i*0.06,0.04)]:
			st.set_color(Color(0.13,0.23,0.065,1.0)); st.set_normal(Vector3.UP); st.set_uv(Vector2(vertex.x,vertex.y)); st.add_vertex(vertex)
	return st.commit()

func _cube_uv(d: Vector3) -> Vector3:
	var a := d.abs()
	if a.x>=a.y and a.x>=a.z:
		return Vector3(0,-d.z/a.x,d.y/a.x) if d.x>0 else Vector3(1,d.z/a.x,d.y/a.x)
	if a.y>=a.z:
		return Vector3(2,d.x/a.y,-d.z/a.y) if d.y>0 else Vector3(3,d.x/a.y,d.z/a.y)
	return Vector3(4,d.x/a.z,d.y/a.z) if d.z>0 else Vector3(5,-d.x/a.z,d.y/a.z)
