class_name SurveyMission
extends Node3D
## A complete peaceful survey loop: land, scan, recover signal, photograph, return to orbit.
var journal: ExplorationJournal
var world: ExploreWorld
var signal_marker: Node3D
var signal_direction := Vector3.ZERO
var scanned := false
var recovered := false
var photographed := false
var landed_once := false
var complete := false
var status := "Land at the survey meadow"

func setup(expedition: ExploreWorld) -> void:
	world=expedition
	journal=ExplorationJournal.new(not Game._hermetic)
	var center := world.survey_direction
	var right := Vector3.RIGHT.slide(center).normalized()
	signal_direction=(center+right*0.00115).normalized()
	var point := signal_direction*(world.PLANET.radius+world.sampler.height(signal_direction))
	signal_marker=Node3D.new(); signal_marker.position=point
	signal_marker.basis=Basis.looking_at(Vector3.FORWARD.slide(signal_direction).normalized(),signal_direction)
	add_child(signal_marker)
	var relay := MeshInstance3D.new(); var mesh := CylinderMesh.new()
	mesh.top_radius=0.12; mesh.bottom_radius=0.38; mesh.height=1.7; mesh.radial_segments=12
	relay.mesh=mesh; relay.position.y=0.85; signal_marker.add_child(relay)
	var mat := StandardMaterial3D.new(); mat.albedo_color=Color(0.08,0.16,0.19); mat.metallic=0.7
	relay.material_override=mat
	var lamp := MeshInstance3D.new(); var cap := SphereMesh.new(); cap.radius=0.20; cap.height=0.40
	lamp.mesh=cap; lamp.position.y=1.8; signal_marker.add_child(lamp)
	var emissive := StandardMaterial3D.new(); emissive.albedo_color=Styles.CYAN
	emissive.emission_enabled=true; emissive.emission=Styles.CYAN; emissive.emission_energy_multiplier=3
	lamp.material_override=emissive
	var label := Label3D.new(); label.text="LOST SURVEY SIGNAL\nR · Scan within 12 m"
	label.position.y=2.6; label.font=Styles.body_font(); label.font_size=38; label.pixel_size=0.006
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.modulate=Styles.CYAN; label.visibility_range_end=140
	signal_marker.add_child(label)

func tick() -> void:
	if world.ship.landed:
		landed_once=true
		journal.record("planets",world.PLANET.id,world.PLANET.display_name,"First landing")
	if landed_once and scanned and recovered and photographed and world.altitude>world.PLANET.atmosphere_height+5000:
		if not complete:
			complete=true
			journal.record("missions","elysian_survey","Elysian survey complete","Surface telemetry returned to orbit")
			AudioMgr.play_ui("mission_win",-8)
	if complete: status="Survey complete · Records secured in the Vanguard Database"
	elif not landed_once: status="Land at the survey meadow · N guided descent"
	elif not scanned: status="Leave the ship and scan the meadow · R scanner"
	elif not recovered:
		var distance := signal_marker.global_position.distance_to(world.astronaut.global_position if world.astronaut!=null else world.ship.position)
		status="Investigate the lost signal · %.0f m · R scanner" % distance
	elif not photographed: status="Record a photograph of the expedition · P camera"
	else: status="Return to the pilot seat and ascend to orbit · N launch"

func scan() -> void:
	if world.astronaut==null or world.astronaut.inside: return
	var relative := world.astronaut.global_position-world.terrain.position
	var d := relative.normalized()
	var biome := world.sampler.biome(d,world.sampler.height(d))
	scanned=true
	journal.record("biomes",world.PLANET.id+"/"+biome,biome,"Elysian surface survey")
	journal.record("geology",biome,"Surface composition", "Water ice" if "snow" in biome or "ice" in biome else "Silicate-rich crust")
	if signal_marker.global_position.distance_to(world.astronaut.global_position)<12:
		recovered=true
		journal.record("signals","survey_01","Survey beacon recovered","Weather telemetry restored")
		world.director.trigger("Discovery")
	AudioMgr.play_ui("radar_ping",-7)

func take_photo() -> void:
	world.hud.visible=false
	await RenderingServer.frame_post_draw
	var path := "user://expedition_photos"
	if Game._hermetic: path="/tmp/helion-v2-evidence/photographs"
	DirAccess.make_dir_recursive_absolute(path)
	path+="/elysian_%d.png" % Time.get_ticks_msec()
	var result := world.get_viewport().get_texture().get_image().save_png(path)
	world.hud.visible=true
	if result==OK:
		photographed=true; journal.photograph(path,"Elysian",world.biome_name)
		AudioMgr.play_ui("objective",-12)
	else: push_error("Photograph could not be saved: "+error_string(result))
