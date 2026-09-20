class_name WeatherSystem
extends Node3D
## Gradual local weather. The atmosphere, water, vegetation and flight all consume one state.
const NAMES := ["Clear","Partly cloudy","Overcast","Fog","Rain","Heavy rain","Thunderstorm","Snow","Blizzard","Sandstorm"]
# coverage, precipitation, fog density, wind m/s
const PROFILES := [Vector4(0.25,0,0,5),Vector4(0.55,0,0,9),Vector4(0.94,0,0.0004,14),
	Vector4(0.65,0,0.009,3),Vector4(0.85,0.5,0.001,16),Vector4(1,1,0.003,24),
	Vector4(1,1,0.004,35),Vector4(0.85,0.5,0.002,8),Vector4(1,1,0.012,30),Vector4(0.9,0.7,0.015,40)]
var state := 0
var values := Vector4(0.25,0,0,5)
var wetness := 0.0
var wind := Vector3.ZERO
var cloud_immersion := 0.0
var lightning := 0.0
var clock := 0.0
var precipitation: CPUParticles3D
var precipitation_material: StandardMaterial3D

func _ready() -> void:
	precipitation=CPUParticles3D.new(); precipitation.name="LocalPrecipitation"
	precipitation.amount=180 if int(Game.settings.preset)==0 else 500
	precipitation.lifetime=1.5; precipitation.local_coords=false
	precipitation.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
	precipitation.emission_box_extents=Vector3(14,9,14)
	precipitation.direction=Vector3.DOWN; precipitation.spread=4
	precipitation.initial_velocity_min=18; precipitation.initial_velocity_max=25
	precipitation_material=StandardMaterial3D.new(); precipitation_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	precipitation_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	precipitation_material.albedo_color=Color(0.7,0.83,0.9,0.3)
	precipitation_material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	var mesh := QuadMesh.new(); mesh.size=Vector2(0.025,0.65); mesh.material=precipitation_material
	precipitation.mesh=mesh; precipitation.emitting=false; add_child(precipitation)

func set_weather(index: int) -> void:
	state=clampi(index,0,NAMES.size()-1)
	var snow := state in [7,8]
	precipitation.lifetime=7.0 if snow else 1.5
	precipitation.initial_velocity_min=1.5 if snow else 18.0
	precipitation.initial_velocity_max=3.5 if snow else 25.0
	(precipitation.mesh as QuadMesh).size=Vector2(0.055,0.055) if snow else Vector2(0.025,0.65)

func tick(dt: float,focus: Vector3,up: Vector3,altitude: float,airless: bool,sheltered: bool) -> void:
	clock+=dt
	values=values.lerp(PROFILES[state],1.0-exp(-dt/8.0))
	var surface := 1.0-smoothstep(1800.0,4000.0,altitude)
	if airless: surface=0.0
	wetness=move_toward(wetness,values.y if state in [4,5,6] else 0.0,dt*0.025)
	var tangent := Vector3(0.7,0.1,0.3).slide(up).normalized()
	wind=tangent*values.w*(0.8+sin(clock*0.6)*0.2)*surface
	cloud_immersion=(1.0-smoothstep(120.0,540.0,absf(altitude-2200.0)))*values.x
	if airless: cloud_immersion=0.0
	precipitation.position=focus+up*7.0
	precipitation.basis=Basis.looking_at(Vector3.FORWARD.slide(up).normalized(),up)
	precipitation.gravity=-up*(0.6 if state in [7,8] else 9.8)+wind*0.15
	precipitation.emitting=values.y*surface>0.08 and not sheltered and state!=9
	lightning=move_toward(lightning,0.0,dt*7.0)
	if state==6 and surface>0 and fmod(clock,13.0)<dt:
		lightning=1.0
		AudioMgr.play_ui("explosion_big",-15.0,0.35)

func fog_density(altitude: float,airless: bool) -> float:
	if airless: return 0.0
	return values.z*(1.0-smoothstep(1600.0,4200.0,altitude))+cloud_immersion*0.014
