class_name ExploreWorld
extends Node3D
## Shared universe, isolated exploration simulation. No scene changes between orbit and surface.
const PLANET: PlanetDefinition = preload("res://data/explore/elysian.tres")
const MOON: PlanetDefinition = preload("res://data/explore/selene.tres")
var frame := OriginFrame.new()
var sampler := PlanetSampler.new(PLANET)
var terrain: TerrainStreamer
var moon: TerrainStreamer
var vegetation: VegetationStreamer
var ship: ExploreShip
var director := CinematicDirector.new()
var mission: SurveyMission
var soundscape: ExploreAudio
var weather: WeatherSystem
var effects: FlightEffects
var interior: ShipInterior
var astronaut: AstronautController
var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var cloud_material: ShaderMaterial
var limb_material: ShaderMaterial
var ocean: MeshInstance3D
var clouds: MeshInstance3D
var limb: MeshInstance3D
var roots: Array[Node3D] = []
var moon_world := PackedFloat64Array([145000.0,85000.0,-150000.0])
var survey_direction := Vector3(0.1,1.0,-0.1).normalized()
var initialized := false
var camera_mode := 0
var time_of_day := 0.28
var hud: Control
var info: Label
var objective: Label
var help: Label
var pause_panel: Control
var elapsed := 0.0
var altitude := 0.0
var clearance := 0.0
var biome_name := ""
var _bench_frames := PackedFloat64Array()
var _bench_clock := 0.0
var _bench_previous := 0
var _quit_after := 0.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	Game.apply_video_settings()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	# Authored meadow is blended into the same field used by every terrain tile.
	survey_direction=PLANET.survey_direction.normalized()
	var start := survey_direction*(PLANET.radius+14000.0)
	frame.origin=PackedFloat64Array([float(start.x),float(start.y),float(start.z)])
	terrain=TerrainStreamer.new(); terrain.name="ElysianTerrain"; add_child(terrain); terrain.setup(PLANET)
	terrain.position=frame.to_local(PackedFloat64Array([0,0,0])); roots.append(terrain)
	moon=TerrainStreamer.new(); moon.name="SeleneTerrain"; add_child(moon); moon.setup(MOON)
	moon.position=frame.to_local(moon_world); roots.append(moon)
	vegetation=VegetationStreamer.new(); vegetation.name="BiomeVegetation"; add_child(vegetation); vegetation.setup(PLANET)
	vegetation.position=terrain.position; roots.append(vegetation)
	ship=ExploreShip.new(); ship.name="ExpeditionShip"; add_child(ship)
	ship.setup(str(Game.explore_options.ship)); roots.append(ship)
	interior=ShipInterior.new(); ship.add_child(interior); interior.visible=false
	ship.basis=Basis.looking_at(Vector3.FORWARD.slide(survey_direction).normalized(),survey_direction)
	camera=Camera3D.new(); camera.name="ExpeditionCamera"; add_child(camera)
	camera.near=0.15; camera.far=420000.0; camera.fov=65.0; camera.make_current()
	_build_environment()
	weather=WeatherSystem.new(); add_child(weather)
	weather.set_weather(int(Game.explore_options.weather))
	effects=FlightEffects.new(); ship.add_child(effects)
	soundscape=ExploreAudio.new(); add_child(soundscape)
	_build_hud()
	time_of_day=float(Game.explore_options.time_of_day)
	director.mode=int(Game.explore_options.cinematics)
	mission=SurveyMission.new(); add_child(mission); mission.position=terrain.position; roots.append(mission); mission.setup(self)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quitafter="): _quit_after=float(arg.get_slice("=",1))
	SceneFlow.report(0.4,"ORBITAL REFERENCE FRAME","Preparing Elysian and Selene")
	# Draw the initial orbital meshes before releasing the launch overlay.
	while not terrain.ready_roots or not moon.ready_roots:
		_stream(0.1)
		_update_camera(0.1)
		await get_tree().process_frame
	SceneFlow.report(0.95,"EXPEDITION READY","Surface telemetry online")
	await SceneFlow.finish()
	altitude=(ship.position-terrain.position).length()-PLANET.radius
	clearance=altitude-sampler.height((ship.position-terrain.position).normalized())
	initialized=true
	director.trigger("Planet reveal")
	_bench_previous=Time.get_ticks_usec()
	print("[EXPLORE] ready ship=%s radius=%.0f renderer=%s" % [ship.ship_id,PLANET.radius,RenderingServer.get_current_rendering_method()])

func _build_environment() -> void:
	environment=Environment.new()
	environment.background_mode=Environment.BG_SKY
	var sky := Sky.new()
	sky_material=ShaderMaterial.new(); sky_material.shader=preload("res://shaders/explore/atmosphere.gdshader")
	sky.sky_material=sky_material; sky.process_mode=Sky.PROCESS_MODE_REALTIME
	sky.radiance_size=Sky.RADIANCE_SIZE_256
	environment.sky=sky
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color(0.45,0.55,0.72); environment.ambient_light_energy=0.22
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled=int(Game.settings.preset)>0
	environment.fog_enabled=true
	environment.fog_sky_affect=0.0
	environment.fog_light_color=Color(0.46,0.61,0.76)
	var world := WorldEnvironment.new(); world.environment=environment; add_child(world)
	sun=DirectionalLight3D.new(); sun.light_energy=1.0; add_child(sun)
	sun.shadow_enabled=int(Game.settings.preset)>=1
	sun.directional_shadow_max_distance=85.0 if int(Game.settings.preset)<2 else 160.0
	ocean=_sphere(PLANET.radius,preload("res://shaders/explore/water.gdshader"),256,128)
	clouds=_sphere(PLANET.radius+2200.0,preload("res://shaders/explore/clouds.gdshader"),128,64)
	cloud_material=clouds.material_override
	limb=_sphere(PLANET.radius+500.0,preload("res://shaders/explore/limb.gdshader"),128,64)
	limb_material=limb.material_override

func _sphere(radius: float, shader: Shader, segments: int, rings: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new(); sphere.radius=radius; sphere.height=radius*2.0
	sphere.radial_segments=segments; sphere.rings=rings
	node.mesh=sphere
	var mat := ShaderMaterial.new(); mat.shader=shader; node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node); node.position=terrain.position; roots.append(node)
	return node

func _stream(dt: float) -> void:
	var focus_position := astronaut.global_position if astronaut!=null else ship.position
	terrain.update_stream(focus_position-terrain.position,dt)
	moon.update_stream(focus_position-moon.position,dt)
	vegetation.update_stream(focus_position-terrain.position,dt)

func _physics_process(dt: float) -> void:
	if not initialized or get_tree().paused: return
	var relative := ship.position-terrain.position
	ship.simulate(dt,PLANET,sampler,relative,survey_direction,weather.wind)
	if astronaut!=null:
		var foot_relative := astronaut.global_position-terrain.position
		var foot_up := foot_relative.normalized()
		var foot_altitude := foot_relative.length()-PLANET.radius
		astronaut.simulate(dt,ship.basis.y if astronaut.inside else foot_up,
			9.81 if astronaut.inside else PLANET.gravity_at(foot_altitude),foot_altitude,sampler.height(foot_up))
		if astronaut.inside and interior.open and astronaut.position.z>6.5 and astronaut.velocity.dot(ship.basis.z)>0.2:
			astronaut.reparent(self,true); astronaut.inside=false; roots.append(astronaut)
			interior.visible=true
			director.trigger("First step")
		frame.rebase(ship if astronaut.inside else astronaut,roots)
	else:
		frame.rebase(ship,roots)

func _process(dt: float) -> void:
	if not initialized or get_tree().paused: return
	elapsed+=dt
	_stream(dt)
	var relative := ship.position-terrain.position
	var up := relative.normalized()
	altitude=relative.length()-PLANET.radius
	clearance=altitude-sampler.height(up)
	biome_name=sampler.biome(up,sampler.height(up))
	time_of_day=fmod(time_of_day+dt/PLANET.rotation_period,1.0)
	var sunlight := Vector3(cos(time_of_day*TAU),sin(time_of_day*TAU),0.28).normalized()
	sun.look_at(sun.position-sunlight,Vector3.FORWARD)
	sky_material.set_shader_parameter("sun_direction",sunlight)
	sky_material.set_shader_parameter("up_direction",up)
	sky_material.set_shader_parameter("altitude",altitude)
	weather.tick(dt,astronaut.global_position if astronaut!=null else ship.position,up,altitude,false,astronaut==null or astronaut.inside)
	cloud_material.set_shader_parameter("sun_direction",sunlight)
	cloud_material.set_shader_parameter("coverage",weather.values.x)
	sky_material.set_shader_parameter("overcast",weather.values.x*smoothstep(0.4,1.0,weather.values.x))
	terrain.material.set_shader_parameter("wetness",weather.wetness)
	vegetation.material.set_shader_parameter("wind_strength",weather.values.w/12.0)
	(ocean.material_override as ShaderMaterial).set_shader_parameter("wind_strength",weather.values.w/12.0)
	sun.light_energy=lerpf(1.25,0.5,weather.values.x*0.7)+weather.lightning*2.0
	effects.tick(ship,clearance,biome_name)
	soundscape.tick(dt,self)
	limb_material.set_shader_parameter("sun_direction",sunlight)
	environment.fog_density=PLANET.density_at(altitude)*0.000025+weather.fog_density(altitude,false)
	var camera_altitude := (camera.position-terrain.position).length()-PLANET.radius
	if camera_altitude<0:
		environment.fog_density=0.14; environment.fog_light_color=Color(0.035,0.19,0.22)
	else: environment.fog_light_color=Color(0.46,0.61,0.76).lerp(Color(0.5,0.32,0.15),0.8 if weather.state==9 else 0.0)
	limb.visible=altitude>4000.0
	_update_camera(dt)
	if ship.flight.heating>0.12: director.trigger("Atmosphere entry")
	if altitude<2400: director.trigger("Cloud penetration")
	if altitude<1000: director.trigger("Surface reveal")
	if ship.landed: director.trigger("Landing")
	director.apply(dt,self)
	mission.tick()
	_update_hud()
	_benchmark()
	if _quit_after>0 and elapsed>_quit_after:
		Game.prepare_shutdown(); get_tree().quit()

func _update_camera(dt: float) -> void:
	if astronaut!=null:
		camera.global_transform=astronaut.camera_transform()
		ship.model.visible=not astronaut.inside
		return
	var up := (ship.position-terrain.position).normalized()
	var target := ship.position+ship.basis*Vector3(0,5,28)
	if camera_mode==1:
		target=ship.position+ship.basis*Vector3(0,0.63,-3.6)
		interior.visible=true
		ship.model.visible=false
	else:
		ship.model.visible=true
		interior.visible=interior.open or ship.landed
	if camera_mode==2:
		target=ship.position+up*22.0+ship.basis.x*30.0+ship.basis.z*30.0
	camera.position=target
	var look := ship.position-ship.basis.z*80.0+up*1.0 if camera_mode<2 else ship.position
	if camera_mode==0:
		look-=up*smoothstep(1500.0,12000.0,altitude)*32.0
	camera.look_at(look,up)
	if effects!=null and effects.stress>0.01:
		camera.position+=camera.basis.x*sin(elapsed*37.0)*effects.stress*0.12+up*cos(elapsed*29.0)*effects.stress*0.08

func _unhandled_input(event: InputEvent) -> void:
	if not initialized: return
	if event.is_action_pressed("pause"):
		_toggle_pause(); get_viewport().set_input_as_handled(); return
	if get_tree().paused: return
	if astronaut!=null and event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		astronaut.mouse_look(event.relative)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_TAB: _show_database(); return
		if event.physical_keycode==KEY_R: mission.scan(); return
		if event.physical_keycode==KEY_P: mission.take_photo(); return
		director.skip()
		if event.physical_keycode==KEY_V:
			weather.set_weather((weather.state+1)%WeatherSystem.NAMES.size()); return
		if astronaut!=null:
			match event.physical_keycode:
				KEY_F: _interact()
				KEY_C: astronaut.third_person=not astronaut.third_person
				KEY_L: astronaut.flashlight.visible=not astronaut.flashlight.visible
			return
		match event.physical_keycode:
			KEY_H: _leave_seat()
			KEY_N: ship.autopilot=2 if ship.landed or altitude<200 else 1
			KEY_G: ship.gear_down=not ship.gear_down
			KEY_C: camera_mode=(camera_mode+1)%3
			KEY_UP: ship.pitch=clampf(ship.pitch+0.12,-1.45,1.45)
			KEY_DOWN: ship.pitch=clampf(ship.pitch-0.12,-1.45,1.45)
			KEY_X: ship.autopilot=0; ship.velocity*=0.25

func _leave_seat() -> void:
	if not ship.landed and (ship.velocity.length()>2.0 or altitude<PLANET.atmosphere_height):
		objective.text="Stabilize in orbit or land before leaving the pilot seat."
		return
	ship.piloted=false; ship.autopilot=0; ship.velocity=Vector3.ZERO
	interior.visible=true
	astronaut=AstronautController.new(); ship.add_child(astronaut)
	astronaut.position=interior.seat+Vector3(0,0,1.5)
	astronaut.yaw=ship.heading
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func _interact() -> void:
	var local := ship.to_local(astronaut.global_position)
	if astronaut.inside:
		if local.distance_to(interior.seat)<2.5:
			astronaut.queue_free(); astronaut=null; ship.piloted=true; interior.visible=false
			Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		elif local.distance_to(interior.airlock)<3.0:
			interior.set_airlock(not interior.open)
	else:
		if local.distance_to(interior.airlock)<6.0 or local.distance_to(Vector3(0,-3.2,13.2))<3.5:
			roots.erase(astronaut); astronaut.reparent(ship,true); astronaut.inside=true
			interior.set_airlock(true)

func _build_hud() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	hud=Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(hud)
	var top := PanelContainer.new()
	top.position=Vector2(32,24); top.custom_minimum_size=Vector2(560,90)
	top.add_theme_stylebox_override("panel",Styles.panel(Color(0.01,0.025,0.045,0.80),4))
	hud.add_child(top)
	var column := VBoxContainer.new(); top.add_child(column)
	column.add_child(Styles.label("ELYSIAN  /  VANGUARD SURVEY CORPS",22,Styles.CYAN,true))
	objective=Styles.label("EXPEDITION 01  ·  Land and survey the wilderness",17)
	column.add_child(objective)
	info=Styles.label("",18,Color(0.85,0.94,1.0),true)
	info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info.position=Vector2(-490,30); info.size=Vector2(450,180)
	info.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; hud.add_child(info)
	info.add_theme_color_override("font_shadow_color",Color(0.0,0.01,0.03,0.95))
	info.add_theme_constant_override("shadow_offset_x",2); info.add_theme_constant_override("shadow_offset_y",2)
	help=Styles.label("",16,Color(0.78,0.87,0.94))
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT); help.position=Vector2(32,-110)
	hud.add_child(help)
	help.add_theme_color_override("font_shadow_color",Color(0.0,0.01,0.03,0.95))
	help.add_theme_constant_override("shadow_offset_x",2); help.add_theme_constant_override("shadow_offset_y",2)

func _update_hud() -> void:
	objective.text=mission.status
	var phase := "ORBIT" if altitude>PLANET.atmosphere_height else "ATMOSPHERIC FLIGHT"
	if ship.flight.heating>0.2: phase="RE-ENTRY"
	if ship.landed: phase="LANDED"
	info.text="%s\nALT  %07.0f m    AGL  %06.0f m\nVEL  %04.0f m/s    MACH  %.1f\nHULL  %04.0f K    %s" % [phase,altitude,clearance,ship.velocity.length(),ship.flight.mach,ship.flight.hull_temperature,biome_name.to_upper()]
	help.text="N  %s   ·   X  Cancel / brake   ·   C  Camera   ·   G  Gear %s\nW/S  Thrust / brake   ·   A/D  Turn   ·   ↑/↓  Pitch   ·   Space/Ctrl  Climb / descend\nESC  Flight menu" % ["Return to orbit" if ship.landed or altitude<200 else "Guided descent", "DOWN" if ship.gear_down else "UP"]
	help.text+="   ·   H  Leave pilot seat   ·   V  Weather: "+WeatherSystem.NAMES[weather.state]
	if astronaut!=null:
		info.text="%s\nSUIT O₂  %.0f%%\n%s" % ["SHIP INTERIOR" if astronaut.inside else "EVA" if astronaut.zero_gravity else "ON FOOT",astronaut.suit_oxygen,biome_name.to_upper()]
		help.text="WASD  Walk   ·   Shift  Run   ·   Space  Jump / EVA up   ·   Ctrl  Crouch / EVA down\nMouse  Look   ·   C  First / third person   ·   L  Flashlight   ·   F  Interact\nF near pilot seat / airlock   ·   R Scanner   ·   P Photograph   ·   Tab Database"

func _show_database() -> void:
	_toggle_pause()
	if pause_panel==null: return
	var vb := pause_panel.get_child(0) as VBoxContainer
	(vb.get_child(0) as Label).text="VANGUARD DATABASE"
	pause_panel.position=Vector2(-360,-250); pause_panel.custom_minimum_size=Vector2(720,500)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size=Vector2(680,340)
	vb.add_child(scroll); vb.move_child(scroll,1)
	var text := Styles.label(mission.journal.describe(),17)
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; text.custom_minimum_size.x=640
	scroll.add_child(text)

func _toggle_pause() -> void:
	if pause_panel!=null:
		pause_panel.queue_free(); pause_panel=null; get_tree().paused=false
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if astronaut!=null else Input.MOUSE_MODE_VISIBLE
		return
	get_tree().paused=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	pause_panel=PanelContainer.new(); pause_panel.process_mode=Node.PROCESS_MODE_ALWAYS
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position=Vector2(-220,-140); pause_panel.custom_minimum_size=Vector2(440,280)
	hud.add_child(pause_panel)
	var vb := VBoxContainer.new(); pause_panel.add_child(vb)
	vb.add_child(Styles.label("EXPEDITION PAUSED",22,Styles.CYAN,true))
	for entry in [["RESUME",_toggle_pause],["FLIGHT DECK",func(): Game.goto_menu()]]:
		var button := Styles.button(entry[0],18); button.pressed.connect(entry[1]); vb.add_child(button)
	(vb.get_child(1) as Button).grab_focus()

func _benchmark() -> void:
	var now := Time.get_ticks_usec()
	var ms := float(now-_bench_previous)/1000.0; _bench_previous=now
	_bench_frames.append(ms); _bench_clock+=ms
	if _bench_clock<2000.0: return
	_bench_frames.sort()
	print("[EXPLORE_BENCH] t=%.1f fps=%.1f p95=%.2f worst=%.2f nodes=%d tiles=%d jobs=%d colliders=%d upload_max=%.2f static_mb=%.1f vram_mb=%.1f rebases=%d" % [elapsed,1000.0/(_bench_clock/_bench_frames.size()),_bench_frames[int(_bench_frames.size()*0.95)],_bench_frames[-1],get_tree().get_node_count(),terrain.chunks.size(),terrain.jobs.size(),terrain.collision_count,terrain.max_upload_ms,OS.get_static_memory_usage()/1048576.0,Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,frame.rebase_count])
	_bench_frames.clear(); _bench_clock=0.0
