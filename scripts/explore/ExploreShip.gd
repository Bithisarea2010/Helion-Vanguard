class_name ExploreShip
extends CharacterBody3D
## A separate flight controller keeps the proven Fight Mode's Combatant contract unchanged.
var model: Node3D
var flight := AtmosphericFlightModel.new()
var landed := false
var gear_down := false
var piloted := true
var autopilot := 0 # 0 manual, 1 descend to survey point, 2 return to orbit
var ship_id := "vanguard"
var heading := 0.0
var pitch := -0.15
var gear_parts: Array[Node3D] = []

func setup(id: String) -> void:
	ship_id = id
	collision_layer = 1; collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.5, 2.0, 9.0)
	shape.shape = box
	add_child(shape)
	model = (load(ShipDB.SHIPS[id].model) as PackedScene).instantiate()
	add_child(model)
	HullMaterial.apply(model, {"authored": bool(ShipDB.SHIPS[id].get("authored",false)),
		"paint": Game.loadout_for(id).paint, "glow": Game.loadout_for(id).glow, "wear":0.24})
	for side in [-1.0, 1.0]:
		for z in [-3.0, 3.0]:
			var strut := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius=0.13; cylinder.bottom_radius=0.18; cylinder.height=2.0
			strut.mesh=cylinder
			strut.position=Vector3(side*2.0,-2,z)
			add_child(strut); gear_parts.append(strut)
			var foot := MeshInstance3D.new()
			var pad := BoxMesh.new(); pad.size=Vector3(0.7,0.15,1.0)
			foot.mesh=pad; foot.position.y=-1.0
			strut.add_child(foot)

func simulate(dt: float, planet: PlanetDefinition, sampler: PlanetSampler,
		relative: Vector3, target_direction: Vector3, wind: Vector3) -> void:
	var up := relative.normalized()
	var altitude := relative.length()-planet.radius
	var ground := sampler.height(up)
	var clearance := altitude-ground
	for gear in gear_parts: gear.visible=gear_down
	if landed:
		flight.step(dt,planet,altitude,Vector3.ZERO,Vector3.ZERO,up,basis)
		pitch=0.0
		basis=Basis.looking_at((-basis.z).slide(up).normalized(),up)
		velocity=Vector3.ZERO
		if piloted and (Input.is_action_pressed("move_up") or autopilot==2):
			landed=false; position+=up*0.8; velocity=up*8.0
		return
	var tangent := Vector3.FORWARD.slide(up).normalized()
	if tangent.length_squared()<0.1: tangent=Vector3.RIGHT.slide(up).normalized()
	var base := Basis.looking_at(tangent,up)
	var flight_basis := base * Basis(Vector3.UP,heading) * Basis(Vector3.RIGHT,pitch)
	basis=basis.slerp(flight_basis,1.0-exp(-dt*3.0)).orthonormalized()
	var acceleration := flight.step(dt,planet,altitude,velocity,wind,up,basis)
	# Inertial/hover assistance opposes gravity; drag and lift still influence handling.
	acceleration+=up*planet.gravity_at(altitude)
	if autopilot!=0:
		var desired := Vector3.ZERO
		if autopilot==1:
			var lateral := (target_direction * relative.length()-relative).slide(up)
			var horizontal := lateral.limit_length(minf(650.0,maxf(12.0,clearance*0.8)))
			var descent := minf(1100.0,maxf(1.8,clearance*0.30))
			if lateral.length()>maxf(25.0,clearance*0.8): descent=minf(descent,3.0)
			if clearance<100.0: gear_down=true
			desired=horizontal-up*descent
			pitch=lerpf(pitch,-0.1,dt)
		else:
			desired=up*minf(1600.0,maxf(20.0,clearance*0.8))
			if altitude>planet.atmosphere_height+6000.0: autopilot=0
		# Closed-loop thrusters accelerate through real positions, never teleport.
		velocity=velocity.move_toward(desired,dt*(95.0 if clearance>100 else 30.0))
	else:
		if piloted:
			var turn := Input.get_vector("strafe_left","strafe_right","pitch_up","pitch_down")
			heading-=turn.x*dt*0.65
			pitch=clampf(pitch-turn.y*dt*0.6,-1.45,1.45)
			var thrust := Input.get_action_strength("thrust_forward")-Input.get_action_strength("thrust_back")
			var boost := 4.0 if Input.is_action_pressed("boost") else 1.0
			acceleration+=-basis.z*thrust*55.0*boost
			acceleration+=up*(Input.get_action_strength("move_up")-Input.get_action_strength("move_down"))*45.0*boost
		velocity+=acceleration*dt
		velocity=velocity.move_toward(Vector3.ZERO,dt*(2.0 if piloted else 80.0))
	velocity=velocity.limit_length(2000.0)
	var approach_speed := absf(velocity.dot(up))
	var collision := move_and_collide(velocity*dt)
	if collision:
		if gear_down and approach_speed<8.0 and collision.get_normal().dot(up)>0.80:
			landed=true; autopilot=0; velocity=Vector3.ZERO
			return
		velocity=velocity.slide(collision.get_normal())*0.5
	# Analytic clearance also guards against a collision tile still awaiting its budgeted upload.
	if clearance<=3.4 and velocity.dot(up)<=0.0:
		position+=up*(3.4-clearance)
		if gear_down and velocity.length()<9.0 and ground>planet.ocean_level:
			landed=true; autopilot=0
		velocity=velocity.slide(up)*0.5
