class_name ShipInterior
extends Node3D
## Walkable survey compartment in ship-local metres. Its collision follows one bounded frame.
var door: Node3D
var open := false
var seat := Vector3(0,-0.95,-3.6)
var airlock := Vector3(0,-0.95,5.6)
var light_material: StandardMaterial3D

func _ready() -> void:
	name="SurveyCompartment"
	light_material=StandardMaterial3D.new()
	light_material.albedo_color=Color(0.15,0.8,0.9)
	light_material.emission_enabled=true; light_material.emission=Color(0.08,0.8,1.0); light_material.emission_energy_multiplier=2.0
	var dark := StandardMaterial3D.new(); dark.albedo_color=Color(0.035,0.048,0.07); dark.metallic=0.6; dark.roughness=0.48
	var panel := StandardMaterial3D.new(); panel.albedo_color=Color(0.16,0.19,0.22); panel.metallic=0.5; panel.roughness=0.38
	_box("Deck",Vector3(3.2,0.18,11.5),Vector3(0,-1.12,0.4),dark,true)
	_box("PortHull",Vector3(0.15,2.7,11.5),Vector3(-1.7,0.2,0.4),panel,true)
	_box("StarboardHull",Vector3(0.15,2.7,11.5),Vector3(1.7,0.2,0.4),panel,true)
	_box("Ceiling",Vector3(3.5,0.15,11.5),Vector3(0,1.6,0.4),dark,true)
	_box("FlightLowerHull",Vector3(3.5,0.9,0.15),Vector3(0,-0.6,-5.4),panel,true)
	_box("WindowHeader",Vector3(3.5,0.18,0.15),Vector3(0,1.45,-5.4),panel,true)
	var glass := StandardMaterial3D.new(); glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color=Color(0.14,0.27,0.36,0.08); glass.metallic=0.2; glass.roughness=0.12
	_box("FlightWindow",Vector3(3.25,1.6,0.035),Vector3(0,0.62,-5.4),glass,true)
	for x in [-1.62,0.0,1.62]:
		_box("WindowMullion",Vector3(0.075,1.6,0.12),Vector3(x,0.62,-5.4),dark,false)
	for z in range(-4,6,2):
		_box("LightStrip",Vector3(2.8,0.025,0.045),Vector3(0,1.49,z),light_material,false)
		for x in [-1.58,1.58]:
			_box("Frame",Vector3(0.06,2.4,0.08),Vector3(x,0.2,z),dark,false)
			_box("DeckLight",Vector3(0.025,0.025,1.25),Vector3(x,-0.98,z),light_material,false)
	# Cockpit and service modules reuse the original project materials/mesh vocabulary.
	if ResourceLoader.exists("res://assets/models/cockpit.glb"):
		var cockpit := (load("res://assets/models/cockpit.glb") as PackedScene).instantiate()
		cockpit.position=Vector3(0,0.62,-3.8); add_child(cockpit)
	for z in [0.0,2.0]:
		_box("EngineeringCabinet",Vector3(0.38,1.3,1.25),Vector3(-1.4,-0.25,z),dark,true)
		_box("DiagnosticDisplay",Vector3(0.02,0.45,0.65),Vector3(-1.19,0.05,z),light_material,false)
	_box("CargoLocker",Vector3(0.45,1.3,1.8),Vector3(1.4,-0.25,1.0),dark,true)
	door=Node3D.new(); door.name="AirlockDoor"; add_child(door)
	var slab := _box("PressureDoor",Vector3(1.52,2.5,0.16),Vector3(-0.775,0.2,5.95),panel,true)
	slab.reparent(door)
	var right_door := _box("StarboardDoor",Vector3(1.52,2.5,0.16),Vector3(0.775,0.2,5.95),panel,true)
	right_door.reparent(door)
	for x in [-1.66,1.66]:
		_box("AirlockHousing",Vector3(0.22,2.7,0.32),Vector3(x,0.2,5.95),dark,false)
	var ramp := _box("BoardingRamp",Vector3(2.3,0.16,7.4),Vector3(0,-2.235,9.65),panel,true)
	ramp.rotation.x=0.31
	for z in [-3.0,1.5,4.8]:
		var lamp := OmniLight3D.new(); lamp.light_color=Color(0.45,0.72,1.0); lamp.light_energy=0.55
		lamp.omni_range=5.0; lamp.position=Vector3(0,1.15,z); add_child(lamp)
	_label("FLIGHT SYSTEMS",Vector3(0,1.35,-5.26))
	_label("AIRLOCK  /  02",Vector3(0,1.22,5.82),PI)

func _label(text: String,pos: Vector3,yaw := 0.0) -> void:
	var label := Label3D.new(); label.text=text; label.font=Styles.title_font(); label.font_size=40
	label.pixel_size=0.0038; label.double_sided=false; label.position=pos; label.rotation.y=yaw; label.modulate=Styles.CYAN
	add_child(label)

func _box(label: String,size: Vector3,pos: Vector3,mat: Material,solid: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.name=label
	var mesh := BoxMesh.new(); mesh.size=size; node.mesh=mesh; node.material_override=mat; node.position=pos
	add_child(node)
	if solid:
		var body := StaticBody3D.new(); body.collision_layer=16; body.collision_mask=4
		var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size=size; shape.shape=box
		body.add_child(shape); node.add_child(body)
	return node

func set_airlock(value: bool) -> void:
	open=value
	var tween := create_tween()
	tween.set_parallel(true)
	for i in door.get_child_count():
		var side := -1.0 if i==0 else 1.0
		tween.tween_property(door.get_child(i),"position:x",side*(2.35 if open else 0.775),0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	AudioMgr.play_ui("hv_transit",-15.0,0.72)
