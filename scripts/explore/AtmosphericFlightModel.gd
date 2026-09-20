class_name AtmosphericFlightModel
extends RefCounted
## Continuous arcade-assisted aerodynamic model; coefficients are explicit SI inputs.
var hull_temperature := 288.0
var dynamic_pressure := 0.0
var mach := 0.0
var heating := 0.0
var structural_stress := 0.0
var density := 0.0

func step(dt: float, planet: PlanetDefinition, altitude: float, velocity: Vector3,
		wind: Vector3, up: Vector3, ship_basis: Basis, mass_kg := 14000.0) -> Vector3:
	density = planet.density_at(altitude)
	var relative := velocity - wind
	var speed := relative.length()
	dynamic_pressure = 0.5 * density * speed * speed
	mach = speed / maxf(295.0, 340.0 - maxf(altitude, 0.0) * 0.004)
	var alignment := absf(relative.normalized().dot(-ship_basis.z)) if speed > 0.1 else 1.0
	var drag := -relative.normalized() * dynamic_pressure * (0.22 + (1.0 - alignment) * 0.9) * 26.0 / mass_kg
	# Substep-independent drag must never reverse relative velocity in one integration.
	drag = drag.limit_length(speed / maxf(dt, 0.001))
	var lift := ship_basis.y * minf(dynamic_pressure * 0.35 * 26.0 / mass_kg, 28.0)
	# Sutton-Graves-shaped density^0.5 * v^3 proxy, art-scaled to the compact world.
	heating = clampf(sqrt(density) * pow(speed / 1100.0, 3.0), 0.0, 4.0)
	hull_temperature += (heating * 650.0 - (hull_temperature - 288.0) * 0.18) * dt
	hull_temperature = clampf(hull_temperature, 180.0, 2800.0)
	structural_stress = clampf(dynamic_pressure / 180000.0, 0.0, 1.0)
	return drag + lift - up * planet.gravity_at(altitude)
