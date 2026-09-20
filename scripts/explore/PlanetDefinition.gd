class_name PlanetDefinition
extends Resource
## SI units. The showcase deliberately uses a compact 60 km radius; no custom engine build.
@export var id := "elysian"
@export var display_name := "ELYSIAN"
@export var radius := 60000.0
@export var mass := 5.29e20
@export var surface_gravity := 9.81
@export var rotation_period := 1800.0
@export var atmosphere_height := 9000.0
@export var atmosphere_density := 1.225
@export var atmosphere_composition := "N₂ / O₂"
@export var temperature_range := Vector2(-55, 42)
@export var ocean_level := 0.0
@export var cloud_coverage := 0.55
@export var precipitation := 0.0
@export var wind_strength := 12.0
@export var terrain_seed := 27013
@export var climate_seed := 903
@export var biome_seed := 511
@export var vegetation_seed := 193
@export var wildlife_seed := 78
@export var civilization_level := 0.0
@export var hazard_level := 0.15
@export var terrain_amplitude := 1800.0
@export var is_moon := false
@export var survey_direction := Vector3(-0.081,1.0,-0.14)
@export var survey_clearing_radius := 40.0

func density_at(altitude: float) -> float:
	if atmosphere_height <= 0.0:
		return 0.0
	var edge := 1.0 - smoothstep(atmosphere_height * 0.72, atmosphere_height, altitude)
	return atmosphere_density * exp(-maxf(altitude, 0.0) / (atmosphere_height * 0.16)) * edge

func gravity_at(altitude: float) -> float:
	return surface_gravity * pow(radius / maxf(radius + altitude, radius * 0.5), 2.0)
