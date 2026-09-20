class_name FlightEffects
extends Node3D
## Gameplay telemetry drives plasma and landing exhaust. No cutscene replaces simulation.
var plasma: MeshInstance3D
var plasma_material: ShaderMaterial
var heat_light: OmniLight3D
var dust: CPUParticles3D
var stress := 0.0
var was_landed := false

func _ready() -> void:
	plasma=MeshInstance3D.new(); var mesh := SphereMesh.new()
	mesh.radius=5.0; mesh.height=6.0; mesh.radial_segments=32; mesh.rings=16
	plasma.mesh=mesh; plasma.scale.z=1.6; plasma.position.z=-2.0
	plasma_material=ShaderMaterial.new(); plasma_material.shader=preload("res://shaders/explore/reentry.gdshader")
	plasma.material_override=plasma_material; plasma.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plasma)
	heat_light=OmniLight3D.new(); heat_light.light_color=Color(1,0.24,0.05); heat_light.omni_range=18; add_child(heat_light)
	dust=CPUParticles3D.new(); dust.amount=80 if int(Game.settings.preset)==0 else 180
	dust.lifetime=1.8; dust.emission_shape=CPUParticles3D.EMISSION_SHAPE_SPHERE; dust.emission_sphere_radius=4
	dust.direction=Vector3.DOWN; dust.spread=85; dust.initial_velocity_min=2; dust.initial_velocity_max=7
	dust.gravity=Vector3(0,0.2,0); dust.scale_amount_min=0.2; dust.scale_amount_max=0.7
	var mat := StandardMaterial3D.new(); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; mat.albedo_color=Color(0.5,0.43,0.29,0.14)
	mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	var quad := QuadMesh.new(); quad.size=Vector2.ONE; quad.material=mat; dust.mesh=quad
	dust.position.y=-3.1; dust.emitting=false; add_child(dust)

func tick(ship: ExploreShip,clearance: float,biome: String) -> void:
	var heat := ship.flight.heating
	plasma.visible=heat>0.025
	if ship.velocity.length()>1:
		var flow := ship.global_basis.inverse()*ship.velocity.normalized()
		plasma.basis=Basis.looking_at(flow,Vector3.UP if absf(flow.y)<0.95 else Vector3.RIGHT).scaled(Vector3(1,1,1.6))
	plasma_material.set_shader_parameter("heat",heat)
	heat_light.light_energy=heat*1.7
	stress=ship.flight.structural_stress*heat
	dust.emitting=clearance<18 and clearance>2 and not ship.landed
	var color := Color(0.85,0.91,0.96,0.17) if biome in ["Polar ice","Alpine snow","Tundra"] else Color(0.44,0.37,0.24,0.13)
	(dust.mesh.material as StandardMaterial3D).albedo_color=color
	if ship.landed and not was_landed: AudioMgr.play_ui("hit_rock",-8.0,0.65)
	was_landed=ship.landed
