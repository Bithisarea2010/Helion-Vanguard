class_name AstronautController
extends CharacterBody3D
var inside := true
var yaw := 0.0
var pitch := 0.0
var third_person := false
var flashlight: SpotLight3D
var avatar: Node3D
var shape_node: CollisionShape3D
var suit_oxygen := 100.0
var crouching := false
var zero_gravity := false
var swimming := false
var eye_height := 1.58
var steps := 0.0
var joints: Array[Node3D] = []

func _ready() -> void:
	name="Astronaut"
	collision_layer=4; collision_mask=2|16
	floor_max_angle=deg_to_rad(48); floor_snap_length=0.45
	shape_node=CollisionShape3D.new()
	var capsule := CapsuleShape3D.new(); capsule.radius=0.28; capsule.height=1.75
	shape_node.shape=capsule; shape_node.position.y=0.88; add_child(shape_node)
	avatar=Node3D.new(); add_child(avatar)
	var model := (preload("res://assets/models/explore/survey_suit.glb") as PackedScene).instantiate()
	avatar.add_child(model)
	for limb_name in ["LeftLeg","RightLeg","LeftArm","RightArm"]:
		var joint := model.find_child(limb_name,true,false) as Node3D
		if joint: joints.append(joint)
	flashlight=SpotLight3D.new(); flashlight.light_energy=2.5; flashlight.spot_range=35.0
	flashlight.spot_angle=32.0; flashlight.position=Vector3(0,1.5,-0.3); flashlight.visible=false; add_child(flashlight)

func _part(size: Vector3,pos: Vector3,material: Material) -> void:
	var mesh := MeshInstance3D.new(); var box := BoxMesh.new(); box.size=size
	mesh.mesh=box; mesh.material_override=material; mesh.position=pos; avatar.add_child(mesh)

func simulate(dt: float,up: Vector3,gravity: float,altitude: float,terrain_height: float) -> void:
	up_direction=up
	zero_gravity=not inside and altitude>9000.0
	swimming=not inside and altitude<-0.6
	var tangent := Vector3.FORWARD.slide(up).normalized()
	if tangent.length_squared()<0.1: tangent=Vector3.RIGHT.slide(up).normalized()
	var base := Basis.looking_at(tangent,up)*Basis(Vector3.UP,yaw)
	global_basis=base
	var speed := 7.0 if Input.is_action_pressed("boost") else 3.5
	var want_crouch := Input.is_action_pressed("move_down") and not zero_gravity
	if crouching and not want_crouch:
		var standing_shape := CapsuleShape3D.new(); standing_shape.height=1.75; standing_shape.radius=0.28
		var query := PhysicsShapeQueryParameters3D.new(); query.shape=standing_shape
		query.transform=Transform3D(global_basis,global_position+up*0.90)
		query.collision_mask=collision_mask; query.exclude=[get_rid()]
		want_crouch=not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
	crouching=want_crouch
	(shape_node.shape as CapsuleShape3D).height=1.1 if crouching else 1.75
	shape_node.position.y=0.56 if crouching else 0.88
	if crouching: speed=1.7
	eye_height=move_toward(eye_height,0.95 if crouching else 1.58,dt*4.0)
	var wish := Input.get_vector("strafe_left","strafe_right","thrust_forward","thrust_back")
	var move := base*Vector3(wish.x,0,wish.y)*speed
	if zero_gravity or swimming:
		move+=up*(Input.get_action_strength("move_up")-Input.get_action_strength("move_down"))*speed
		velocity=velocity.move_toward(move,dt*6.0)
	else:
		var radial_velocity := velocity.dot(up)
		velocity=velocity.slide(up).move_toward(move,dt*25.0)+up*radial_velocity
		velocity-=up*gravity*dt
		if is_on_floor() and Input.is_action_just_pressed("move_up"): velocity+=up*5.2
	var before_move := global_position
	move_and_slide()
	# Step over a small deck seam or rock ledge only when both headroom and forward clearance exist.
	if not zero_gravity and not swimming and is_on_floor() and move.length()>0.1:
		if global_position.distance_to(before_move)<move.length()*dt*0.25:
			var step := up*0.24
			if not test_move(global_transform,step) and not test_move(global_transform.translated(step),move.normalized()*0.32):
				global_position+=step
				move_and_slide()
	avatar.visible=third_person
	steps+=velocity.slide(up).length()*dt
	for i in joints.size():
		joints[i].rotation.x=sin(steps*1.7+(PI if i%2==0 else 0.0))*minf(velocity.slide(up).length()*0.1,0.4)
	if not inside and altitude-terrain_height<0.0 and not swimming:
		# Guard a newly streamed region until its collision tiles are ready.
		global_position+=up*(terrain_height-altitude+0.05)
		velocity=velocity.slide(up)
	suit_oxygen=move_toward(suit_oxygen,100.0,dt*3.0) if inside else maxf(0,suit_oxygen-dt*0.015)

func camera_transform() -> Transform3D:
	var view_basis := global_basis*Basis(Vector3.RIGHT,pitch)
	var eye := global_position+global_basis.y*eye_height
	if third_person: eye+=view_basis.z*3.2+global_basis.y*0.5
	return Transform3D(view_basis,eye)

func mouse_look(relative: Vector2) -> void:
	yaw-=relative.x*0.0022*float(Game.settings.mouse_sens)
	pitch=clampf(pitch-relative.y*0.0022*float(Game.settings.mouse_sens),-1.4,1.4)
