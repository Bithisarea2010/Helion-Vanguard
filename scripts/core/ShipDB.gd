class_name ShipDB
## Static data: player ships, enemy ships, weapons, missiles.

# ============================================================ PRIMARY WEAPONS
# kind: bullet | beam    dmg per shot (beam: per second)
# rof shots/s   speed m/s   range m   heat per shot (beam: /s)   energy per shot
# spread deg    pen 0..1 (armor penetration)   sh/hu: damage mult vs shield/hull
const WEAPONS := {
	"pulse": {"label": "Twin Pulse Lasers", "kind": "bullet", "dmg": 9.0, "rof": 8.0,
		"speed": 750.0, "range": 1300.0, "heat": 3.2, "energy": 2.0, "spread": 0.25,
		"pen": 0.1, "sh": 1.3, "hu": 0.85, "color": Color(1.0, 0.25, 0.2), "size": 2.6,
		"sound": "laser1", "desc": "Reliable rapid energy weapon. Strong vs shields."},
	"plasma": {"label": "Plasma Cannons", "kind": "bullet", "dmg": 26.0, "rof": 3.2,
		"speed": 420.0, "range": 1100.0, "heat": 9.0, "energy": 6.0, "spread": 0.6,
		"pen": 0.35, "sh": 1.1, "hu": 1.15, "color": Color(0.35, 0.9, 1.0), "size": 4.0,
		"sound": "plasma", "desc": "Slow searing bolts. Heavy damage, high heat."},
	"autocannon": {"label": "Rapid Autocannon", "kind": "bullet", "dmg": 5.5, "rof": 14.0,
		"speed": 900.0, "range": 1500.0, "heat": 1.6, "energy": 0.0, "spread": 1.1,
		"pen": 0.3, "sh": 0.55, "hu": 1.25, "color": Color(1.0, 0.85, 0.45), "size": 1.8,
		"sound": "cannon", "ammo": 900, "desc": "Ballistic hose. Shreds hulls, weak vs shields."},
	"heavycannon": {"label": "Heavy Cannon", "kind": "bullet", "dmg": 48.0, "rof": 1.4,
		"speed": 800.0, "range": 1700.0, "heat": 7.0, "energy": 0.0, "spread": 0.35,
		"pen": 0.7, "sh": 0.6, "hu": 1.5, "color": Color(1.0, 0.6, 0.25), "size": 3.4,
		"sound": "heavycannon", "ammo": 140, "desc": "Slow, brutal shells that punch through armor."},
	"coilgun": {"label": "Coilgun", "kind": "bullet", "dmg": 70.0, "rof": 0.8,
		"speed": 1600.0, "range": 2600.0, "heat": 11.0, "energy": 8.0, "spread": 0.05,
		"pen": 0.95, "sh": 0.7, "hu": 1.35, "color": Color(0.75, 0.85, 1.0), "size": 3.0,
		"sound": "coil", "ammo": 60, "desc": "Hypervelocity sniper slug. Near-perfect accuracy."},
	"ion": {"label": "Ion Disruptor", "kind": "bullet", "dmg": 14.0, "rof": 5.0,
		"speed": 600.0, "range": 1200.0, "heat": 4.0, "energy": 4.5, "spread": 0.5,
		"pen": 0.0, "sh": 2.2, "hu": 0.25, "color": Color(0.5, 0.6, 1.0), "size": 3.2,
		"sound": "ion", "desc": "Crushes shields and disrupts systems, weak vs hull."},
	"beam": {"label": "Beam Laser", "kind": "beam", "dmg": 55.0, "rof": 0.0,
		"speed": 0.0, "range": 950.0, "heat": 16.0, "energy": 14.0, "spread": 0.0,
		"pen": 0.2, "sh": 1.2, "hu": 0.9, "color": Color(1.0, 0.35, 0.3), "size": 0.35,
		"sound": "beam", "desc": "Continuous cutting beam. Instant hit, heavy heat."},
	"lance": {"label": "Heavy Energy Lance", "kind": "beam", "dmg": 95.0, "rof": 0.0,
		"speed": 0.0, "range": 1400.0, "heat": 26.0, "energy": 22.0, "spread": 0.0,
		"pen": 0.55, "sh": 1.0, "hu": 1.2, "color": Color(0.55, 1.0, 0.75), "size": 0.6,
		"sound": "lance", "desc": "Capital-grade lance. Melts anything, overheats fast."},
}

# ============================================================ SECONDARY / MISSILES
const MISSILES := {
	"heatseeker": {"label": "Heatseeker Missiles", "dmg": 90.0, "speed": 300.0, "accel": 140.0,
		"turn": 130.0, "lock_time": 1.1, "lock_cone": 22.0, "range": 2300.0, "reload": 1.6,
		"guidance": "heat", "salvo": 1, "cm_resist": 0.35,
		"desc": "Fast lock, agile chase. Easily spoofed by flares."},
	"radar": {"label": "Radar-Guided Missiles", "dmg": 140.0, "speed": 260.0, "accel": 110.0,
		"turn": 90.0, "lock_time": 2.2, "lock_cone": 30.0, "range": 3400.0, "reload": 2.4,
		"guidance": "radar", "salvo": 1, "cm_resist": 0.6,
		"desc": "Long range, heavy warhead. Resists flares, fooled by chaff."},
	"swarm": {"label": "Swarm Missiles", "dmg": 26.0, "speed": 330.0, "accel": 180.0,
		"turn": 170.0, "lock_time": 1.6, "lock_cone": 35.0, "range": 1800.0, "reload": 3.5,
		"guidance": "heat", "salvo": 6, "cm_resist": 0.25,
		"desc": "Six-round volley that saturates countermeasures."},
	"torpedo": {"label": "Anti-Ship Torpedo", "dmg": 520.0, "speed": 170.0, "accel": 60.0,
		"turn": 40.0, "lock_time": 3.0, "lock_cone": 15.0, "range": 4200.0, "reload": 5.0,
		"guidance": "radar", "salvo": 1, "cm_resist": 0.8,
		"desc": "Slow capital-killer. Point defence will target it."},
	"rockets": {"label": "Unguided Rockets", "dmg": 60.0, "speed": 380.0, "accel": 90.0,
		"turn": 0.0, "lock_time": 0.0, "lock_cone": 0.0, "range": 1500.0, "reload": 0.35,
		"guidance": "none", "salvo": 2, "cm_resist": 1.0,
		"desc": "Dumb-fire pods. Devastating up close, no tracking."},
}

# ============================================================ PLAYER SHIPS
const SHIPS := {
	"wasp": {
		"label": "SF-3 Wasp", "role": "Interceptor",
		"desc": "Featherweight interceptor. Nothing outturns it; nothing protects it.",
		"model": "res://assets/models/ship_wasp.glb",
		"speed": 155.0, "accel": 78.0, "turn": 1.45, "mass": 9.0,
		"hull": 70.0, "armor": 0.1, "shield": 60.0, "shield_regen": 7.0,
		"energy": 90.0, "energy_regen": 16.0, "heat_cap": 90.0, "cool": 15.0,
		"boost_mult": 1.9, "boost_drain": 22.0,
		"missile_cap": 4, "cm_count": 12,
		"default_primary": "pulse", "default_primary2": "ion", "default_missile": "heatseeker",
		"paint": Color(0.85, 0.55, 0.15), "glow": Color(0.4, 0.8, 1.0),
		"muzzles_a": [Vector3(0.25, -0.1, -5.5), Vector3(-0.25, -0.1, -5.5)],
		"muzzles_b": [Vector3(3.1, -0.45, 1.2), Vector3(-3.1, -0.45, 1.2)],
		"thrusters": [Vector3(0, 0.05, 0)], "eye": Vector3(0, 0.72, -1.8),
	},
	"vanguard": {
		"label": "SF-7 Vanguard", "role": "Assault Fighter",
		"desc": "The fleet workhorse. Balanced speed, shields and firepower.",
		"model": "res://assets/models/ship_vanguard.glb",
		"speed": 128.0, "accel": 60.0, "turn": 1.1, "mass": 14.0,
		"hull": 120.0, "armor": 0.25, "shield": 110.0, "shield_regen": 8.0,
		"energy": 110.0, "energy_regen": 14.0, "heat_cap": 110.0, "cool": 13.0,
		"boost_mult": 1.75, "boost_drain": 18.0,
		"missile_cap": 8, "cm_count": 10,
		"default_primary": "pulse", "default_primary2": "autocannon", "default_missile": "heatseeker",
		"paint": Color(0.9, 0.6, 0.12), "glow": Color(0.35, 0.75, 1.0),
		"muzzles_a": [Vector3(0.42, -0.12, -7.2), Vector3(-0.42, -0.12, -7.2)],
		"muzzles_b": [Vector3(4.35, -1.15, 2.5), Vector3(-4.35, -1.15, 2.5)],
		"thrusters": [Vector3(0.8, 0.02, 0), Vector3(-0.8, 0.02, 0)], "eye": Vector3(0, 0.98, -3.0),
	},
	"hammer": {
		"label": "SG-9 Hammer", "role": "Heavy Gunship",
		"desc": "A flying fortress. Slow to turn, murderous to face.",
		"model": "res://assets/models/ship_hammer.glb",
		"speed": 96.0, "accel": 40.0, "turn": 0.68, "mass": 28.0,
		"hull": 260.0, "armor": 0.5, "shield": 180.0, "shield_regen": 6.0,
		"energy": 150.0, "energy_regen": 12.0, "heat_cap": 160.0, "cool": 16.0,
		"boost_mult": 1.5, "boost_drain": 14.0,
		"missile_cap": 6, "cm_count": 8,
		"default_primary": "plasma", "default_primary2": "heavycannon", "default_missile": "rockets",
		"paint": Color(0.35, 0.4, 0.45), "glow": Color(1.0, 0.45, 0.15),
		"muzzles_a": [Vector3(0.2, -0.9, -7.0), Vector3(-0.2, -0.9, -7.0)],
		"muzzles_b": [Vector3(2.4, 0.15, -6.6), Vector3(-2.4, 0.15, -6.6), Vector3(2.4, -0.25, -6.6), Vector3(-2.4, -0.25, -6.6)],
		"thrusters": [Vector3(1.15, 0.45, 0), Vector3(-1.15, 0.45, 0), Vector3(1.15, -0.45, 0), Vector3(-1.15, -0.45, 0)],
		"eye": Vector3(0, 1.15, -4.8),
	},
	"raptor": {
		"label": "SM-5 Raptor", "role": "Strike Craft",
		"desc": "Missile boat. Locks on from far out and empties the racks.",
		"model": "res://assets/models/ship_raptor.glb",
		"speed": 116.0, "accel": 52.0, "turn": 0.92, "mass": 17.0,
		"hull": 100.0, "armor": 0.2, "shield": 95.0, "shield_regen": 7.0,
		"energy": 100.0, "energy_regen": 13.0, "heat_cap": 95.0, "cool": 12.0,
		"boost_mult": 1.7, "boost_drain": 18.0,
		"missile_cap": 18, "cm_count": 10,
		"default_primary": "autocannon", "default_primary2": "ion", "default_missile": "radar",
		"paint": Color(0.2, 0.5, 0.55), "glow": Color(0.6, 0.4, 1.0),
		"muzzles_a": [Vector3(0.0, -0.14, -7.9)],
		"muzzles_b": [Vector3(0.35, -0.3, -6.5), Vector3(-0.35, -0.3, -6.5)],
		"thrusters": [Vector3(0.55, 0.04, 0), Vector3(-0.55, 0.04, 0)], "eye": Vector3(0, 0.82, -2.7),
	},
}

# ============================================================ ENEMY SHIPS
# ai: acc = accuracy (0..1 base), turn mult, brave (0..1 retreat threshold inverse)
const ENEMIES := {
	"razor": {"label": "Razor Interceptor", "model": "res://assets/models/enemy_razor.glb",
		"speed": 125.0, "accel": 52.0, "turn": 1.25, "hull": 45.0, "shield": 30.0,
		"shield_regen": 4.0, "weapon": "e_laser", "missile": "", "cm_count": 4,
		"score": 100, "acc": 0.55, "brave": 0.5, "scale": 1.0,
		"muzzles": [Vector3(2.9, 0.1, 1.0), Vector3(-2.9, 0.1, 1.0)]},
	"jackal": {"label": "Jackal Fighter", "model": "res://assets/models/enemy_jackal.glb",
		"speed": 105.0, "accel": 42.0, "turn": 1.0, "hull": 80.0, "shield": 55.0,
		"shield_regen": 5.0, "weapon": "e_laser", "missile": "heatseeker", "cm_count": 6,
		"score": 150, "acc": 0.65, "brave": 0.65, "scale": 1.1,
		"muzzles": [Vector3(0.72, -0.05, -8.3), Vector3(-0.72, -0.05, -8.3)]},
	"brute": {"label": "Brute Heavy Fighter", "model": "res://assets/models/enemy_jackal.glb",
		"speed": 88.0, "accel": 32.0, "turn": 0.7, "hull": 170.0, "shield": 110.0,
		"shield_regen": 6.0, "weapon": "e_plasma", "missile": "", "cm_count": 6,
		"score": 250, "acc": 0.7, "brave": 0.85, "scale": 1.45},
	"stinger": {"label": "Stinger Missile Fighter", "model": "res://assets/models/enemy_razor.glb",
		"speed": 95.0, "accel": 38.0, "turn": 0.85, "hull": 70.0, "shield": 60.0,
		"shield_regen": 5.0, "weapon": "e_laser", "missile": "radar", "cm_count": 8,
		"score": 220, "acc": 0.6, "brave": 0.6, "scale": 1.15},
	"mauler": {"label": "Mauler Bomber", "model": "res://assets/models/enemy_mauler.glb",
		"speed": 70.0, "accel": 24.0, "turn": 0.45, "hull": 240.0, "shield": 140.0,
		"shield_regen": 7.0, "weapon": "e_plasma", "missile": "torpedo", "cm_count": 10,
		"score": 350, "acc": 0.55, "brave": 0.95, "scale": 1.0},
	"widow": {"label": "Widow Defence Drone", "model": "res://assets/models/enemy_widow.glb",
		"speed": 80.0, "accel": 55.0, "turn": 1.5, "hull": 30.0, "shield": 0.0,
		"shield_regen": 0.0, "weapon": "e_light", "missile": "", "cm_count": 0,
		"score": 60, "acc": 0.5, "brave": 1.0, "scale": 1.0},
}

# enemy weapon defs (subset of WEAPONS format)
const ENEMY_WEAPONS := {
	"e_laser": {"label": "Hostile Laser", "kind": "bullet", "dmg": 7.0, "rof": 5.0,
		"speed": 620.0, "range": 1200.0, "heat": 0.0, "energy": 0.0, "spread": 0.4,
		"pen": 0.1, "sh": 1.2, "hu": 0.9, "color": Color(1.0, 0.15, 0.1), "size": 2.8,
		"sound": "elaser"},
	"e_plasma": {"label": "Hostile Plasma", "kind": "bullet", "dmg": 20.0, "rof": 2.2,
		"speed": 380.0, "range": 1000.0, "heat": 0.0, "energy": 0.0, "spread": 0.8,
		"pen": 0.3, "sh": 1.0, "hu": 1.1, "color": Color(1.0, 0.45, 0.1), "size": 4.2,
		"sound": "plasma"},
	"e_light": {"label": "Drone Blaster", "kind": "bullet", "dmg": 4.0, "rof": 7.0,
		"speed": 550.0, "range": 900.0, "heat": 0.0, "energy": 0.0, "spread": 1.2,
		"pen": 0.0, "sh": 1.0, "hu": 1.0, "color": Color(1.0, 0.3, 0.5), "size": 2.0,
		"sound": "elaser"},
	"e_turret": {"label": "Base Turret", "kind": "bullet", "dmg": 16.0, "rof": 1.8,
		"speed": 500.0, "range": 1600.0, "heat": 0.0, "energy": 0.0, "spread": 0.9,
		"pen": 0.2, "sh": 1.0, "hu": 1.0, "color": Color(1.0, 0.2, 0.1), "size": 4.5,
		"sound": "eturret"},
	"e_flak": {"label": "Capital Flak", "kind": "bullet", "dmg": 30.0, "rof": 0.9,
		"speed": 420.0, "range": 2000.0, "heat": 0.0, "energy": 0.0, "spread": 2.0,
		"pen": 0.1, "sh": 1.0, "hu": 1.0, "color": Color(1.0, 0.55, 0.15), "size": 5.0,
		"sound": "eturret"},
}

static func weapon(id: String) -> Dictionary:
	if WEAPONS.has(id):
		return WEAPONS[id]
	return ENEMY_WEAPONS.get(id, WEAPONS.pulse)

static func primary_ids() -> Array:
	return WEAPONS.keys()

static func missile_ids() -> Array:
	return MISSILES.keys()
