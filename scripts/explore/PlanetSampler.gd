class_name PlanetSampler
extends RefCounted
## One sampler per worker. Continuous 3D noise avoids longitude and cube-face seams.
var definition: PlanetDefinition
var terrain := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var climate := FastNoiseLite.new()
var clearing_height := 0.0

func _init(planet: PlanetDefinition) -> void:
	definition = planet
	terrain.seed = planet.terrain_seed
	terrain.frequency = 1.0
	terrain.fractal_octaves = 5
	detail.seed = planet.biome_seed
	detail.frequency = 1.0
	detail.fractal_octaves = 3
	climate.seed = planet.climate_seed
	climate.frequency = 1.0
	climate.fractal_octaves = 3
	clearing_height=_raw_height(planet.survey_direction.normalized())

func height(direction: Vector3) -> float:
	var h := _raw_height(direction)
	if definition.is_moon: return h
	var distance := direction.distance_to(definition.survey_direction.normalized())*definition.radius
	return lerpf(clearing_height,h,smoothstep(definition.survey_clearing_radius,definition.survey_clearing_radius*2.0,distance))

func _raw_height(direction: Vector3) -> float:
	var continental := terrain.get_noise_3dv(direction * 3.8)
	var ridge := 1.0 - absf(detail.get_noise_3dv(direction * 19.0))
	var mountains := pow(ridge, 5.0) * smoothstep(-0.04, 0.32, continental)
	var fine := detail.get_noise_3dv(direction * 390.0) * 0.008
	var h := (continental * 1.25 + mountains * 0.55 - 0.045 + fine) * definition.terrain_amplitude
	if definition.is_moon:
		return (continental * 0.8 + mountains * 0.35) * definition.terrain_amplitude
	# Narrow channels follow one continuous field across the entire planet.
	var channel := absf(climate.get_noise_3dv(direction * 8.0))
	h -= (1.0 - smoothstep(0.008, 0.025, channel)) * maxf(h, 0.0) * 0.28
	return h

func climate_at(direction: Vector3, elevation: float) -> Vector2:
	var temperature := 32.0 - absf(direction.z) * 78.0 - maxf(elevation, 0.0) * 0.016
	var humidity := clampf(0.5 + climate.get_noise_3dv(direction * 4.0) * 1.7, 0, 1)
	return Vector2(temperature, humidity)

func biome(direction: Vector3, elevation: float) -> String:
	if definition.is_moon: return "Lunar highlands"
	if elevation < -3.0: return "Ocean"
	if elevation < 14.0: return "Coast"
	var c := climate_at(direction, elevation)
	if c.x < -20.0: return "Polar ice"
	if c.x < -5.0: return "Alpine snow" if elevation > 600 else "Tundra"
	if elevation > 650.0: return "Mountains"
	if c.y < 0.30 and c.x > 12.0: return "Desert"
	return "Temperate forest"

func surface_color(direction: Vector3, elevation: float) -> Color:
	if definition.is_moon:
		return Color(0.29, 0.30, 0.32).lerp(Color(0.55, 0.53, 0.49), clampf(elevation / 900.0 + 0.5, 0, 1))
	var c := climate_at(direction, elevation)
	var forest := Color(0.09, 0.19, 0.105).lerp(Color(0.25, 0.29, 0.13), 1.0 - c.y)
	var land := forest.lerp(Color(0.64, 0.43, 0.23), (1.0 - smoothstep(0.22, 0.40, c.y)) * smoothstep(5, 18, c.x))
	land = land.lerp(Color(0.31, 0.32, 0.30), smoothstep(450, 1000, elevation))
	land = land.lerp(Color(0.78, 0.86, 0.89), 1.0 - smoothstep(-10, -1, c.x))
	land = Color(0.55, 0.48, 0.33).lerp(land, smoothstep(5, 27, elevation))
	return Color(0.025, 0.10, 0.13).lerp(land, smoothstep(-8, 3, elevation))

static func cube_direction(face: int, u: float, v: float) -> Vector3:
	match face:
		0: return Vector3(1, v, -u).normalized()
		1: return Vector3(-1, v, u).normalized()
		2: return Vector3(u, 1, -v).normalized()
		3: return Vector3(u, -1, v).normalized()
		4: return Vector3(u, v, 1).normalized()
		_: return Vector3(-u, v, -1).normalized()
