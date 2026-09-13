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
		"sound": "hv_pulse", "desc": "Reliable rapid energy weapon. Strong vs shields."},
	"plasma": {"label": "Plasma Cannons", "kind": "bullet", "dmg": 26.0, "rof": 3.2,
		"speed": 420.0, "range": 1100.0, "heat": 9.0, "energy": 6.0, "spread": 0.6,
		"pen": 0.35, "sh": 1.1, "hu": 1.15, "color": Color(0.35, 0.9, 1.0), "size": 4.0,
		"sound": "hv_plasma", "desc": "Slow searing bolts. Heavy damage, high heat."},
	"autocannon": {"label": "Rapid Autocannon", "kind": "bullet", "dmg": 5.5, "rof": 14.0,
		"speed": 900.0, "range": 1500.0, "heat": 1.6, "energy": 0.0, "spread": 1.1,
		"pen": 0.3, "sh": 0.55, "hu": 1.25, "color": Color(1.0, 0.85, 0.45), "size": 1.8,
		"sound": "hv_cannon", "ammo": 900, "desc": "Ballistic hose. Shreds hulls, weak vs shields."},
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

	# ------------------------------------------------------ extended arsenal (1.2)
	# Each of these exists for a MECHANIC the first eight do not have, so the
	# loadout screen is a decision about how you want to fight rather than a
	# damage-per-second ranking. Gated behind the Advanced Capabilities switch.
	"railgun": {"label": "MK-IV Railgun", "kind": "bullet", "dmg": 62.0, "rof": 1.05,
		"speed": 2200.0, "range": 3200.0, "heat": 13.0, "energy": 11.0, "spread": 0.02,
		"pen": 1.0, "sh": 0.8, "hu": 1.45, "color": Color(0.80, 0.72, 1.0), "size": 3.2,
		"sound": "hv_rail", "ammo": 90, "advanced": true,
		"pierce": 4, "pierce_falloff": 0.72,
		"desc": "Punches clean through four hulls. Damage decays with each pass."},
	"arc": {"label": "Arc Projector", "kind": "bullet", "dmg": 17.0, "rof": 4.0,
		"speed": 1400.0, "range": 950.0, "heat": 5.5, "energy": 5.2, "spread": 0.35,
		"pen": 0.05, "sh": 1.9, "hu": 0.65, "color": Color(0.55, 0.85, 1.0), "size": 3.0,
		"sound": "arc", "advanced": true,
		"chain": 3, "chain_range": 160.0, "chain_falloff": 0.65,
		"desc": "Lightning that jumps to three more contacts. Devastating on packs."},
	"flak": {"label": "Flak Battery", "kind": "bullet", "dmg": 8.5, "rof": 1.7,
		"speed": 720.0, "range": 900.0, "heat": 7.0, "energy": 0.0, "spread": 3.4,
		"pen": 0.15, "sh": 0.75, "hu": 1.25, "color": Color(1.0, 0.72, 0.30), "size": 2.2,
		"sound": "flak", "ammo": 240, "advanced": true, "pellets": 7,
		"desc": "Seven-pellet cone. Murderous inside 400 m, useless past 700."},
	"phase": {"label": "Phase Disruptor", "kind": "bullet", "dmg": 21.0, "rof": 4.6,
		"speed": 840.0, "range": 1150.0, "heat": 7.5, "energy": 7.0, "spread": 0.45,
		"pen": 0.5, "sh": 0.0, "hu": 1.0, "color": Color(0.85, 0.40, 1.0), "size": 3.0,
		"sound": "phase", "advanced": true, "bypass_shield": true,
		"desc": "Phases through shields entirely and bites the hull underneath."},
	"repeater": {"label": "Scatter Repeater", "kind": "bullet", "dmg": 4.4, "rof": 22.0,
		"speed": 1000.0, "range": 1150.0, "heat": 1.0, "energy": 0.6, "spread": 0.35,
		"pen": 0.2, "sh": 0.8, "hu": 1.1, "color": Color(1.0, 0.95, 0.65), "size": 1.5,
		"sound": "repeater", "ammo": 1600, "advanced": true,
		"bloom": 2.6, "bloom_recover": 5.0,
		"desc": "Hoses rounds, but the cone opens as you hold. Tap it."},
	"singularity": {"label": "Singularity Lance", "kind": "beam", "dmg": 42.0, "rof": 0.0,
		"speed": 0.0, "range": 1300.0, "heat": 21.0, "energy": 18.0, "spread": 0.0,
		"pen": 0.75, "sh": 1.1, "hu": 1.25, "color": Color(0.95, 0.55, 1.0), "size": 0.5,
		"sound": "singularity", "advanced": true, "charge_gain": 3.2, "charge_time": 2.4,
		"desc": "Beam that keeps building. Held to full it out-damages anything."},
}

## Weapons available for a loadout, filtered by the Advanced Capabilities switch.
static func selectable_weapons() -> Array:
	var out: Array = []
	var extended := Game.cap("arsenal")
	for id in WEAPONS:
		if WEAPONS[id].get("advanced", false) and not extended:
			continue
		out.append(id)
	return out

static func selectable_missiles() -> Array:
	var out: Array = []
	var extended := Game.cap("arsenal")
	for id in MISSILES:
		if MISSILES[id].get("advanced", false) and not extended:
			continue
		out.append(id)
	return out

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

	# ------------------------------------------------------ extended arsenal (1.2)
	"emp": {"label": "EMP Warhead", "dmg": 40.0, "speed": 290.0, "accel": 130.0,
		"turn": 120.0, "lock_time": 1.4, "lock_cone": 26.0, "range": 2600.0, "reload": 4.0,
		"guidance": "radar", "salvo": 1, "cm_resist": 0.5, "advanced": true,
		"emp_radius": 220.0, "emp_time": 4.5, "shield_mult": 6.0,
		"desc": "Strips shields in a 220 m bubble and blinds every seeker in it."},
	"cluster": {"label": "Cluster Munition", "dmg": 55.0, "speed": 260.0, "accel": 110.0,
		"turn": 95.0, "lock_time": 1.8, "lock_cone": 28.0, "range": 2800.0, "reload": 4.5,
		"guidance": "radar", "salvo": 1, "cm_resist": 0.55, "advanced": true,
		"cluster": 6, "cluster_dmg": 48.0,
		"desc": "Splits into six submunitions on approach. Clears a formation."},
	"mine": {"label": "Proximity Mines", "dmg": 190.0, "speed": 34.0, "accel": 0.0,
		"turn": 0.0, "lock_time": 0.0, "lock_cone": 0.0, "range": 400.0, "reload": 1.1,
		"guidance": "none", "salvo": 2, "cm_resist": 1.0, "advanced": true,
		"mine": true, "mine_radius": 46.0, "mine_life": 26.0,
		"desc": "Drop behind you and let the chase fly into it."},
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
		"model": "res://assets/models/ship_vanguard_mk3.glb", "authored": true,
		"speed": 128.0, "accel": 60.0, "turn": 1.1, "mass": 14.0,
		"hull": 120.0, "armor": 0.25, "shield": 110.0, "shield_regen": 8.0,
		"energy": 110.0, "energy_regen": 14.0, "heat_cap": 110.0, "cool": 13.0,
		"boost_mult": 1.75, "boost_drain": 18.0,
		"missile_cap": 8, "cm_count": 10,
		"default_primary": "pulse", "default_primary2": "autocannon", "default_missile": "heatseeker",
		"paint": Color(0.9, 0.6, 0.12), "glow": Color(0.35, 0.75, 1.0),
		"muzzles_a": [Vector3(0.52, -0.27, -8.4), Vector3(-0.52, -0.27, -8.4)],
		"muzzles_b": [Vector3(4.4, -0.30, -2.9), Vector3(-4.4, -0.30, -2.9)],
		"thrusters": [Vector3(2.3, 0.10, 0), Vector3(-2.3, 0.10, 0)], "eye": Vector3(0, 0.98, -3.0),
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
	# --------------------------------------------------------- 1.2 additions
	"specter": {
		"label": "SR-2 Specter", "role": "Stealth Interceptor",
		"desc": "Faceted, cold and quiet. They shoot at you late, and by then you are past.",
		"model": "res://assets/models/ship_specter.glb",
		"speed": 148.0, "accel": 74.0, "turn": 1.32, "mass": 11.0,
		"hull": 85.0, "armor": 0.15, "shield": 75.0, "shield_regen": 9.0,
		"energy": 130.0, "energy_regen": 18.0, "heat_cap": 95.0, "cool": 17.0,
		"boost_mult": 1.85, "boost_drain": 16.0,
		"missile_cap": 6, "cm_count": 14,
		# `stealth` shrinks the range at which the AI will pick you as a target.
		# It is the one stat in the roster that changes how the fight STARTS
		# rather than how it is won, which is what makes the hull worth flying.
		"stealth": 0.55,
		"default_primary": "pulse", "default_primary2": "phase", "default_missile": "heatseeker",
		"paint": Color(0.16, 0.17, 0.20), "glow": Color(0.55, 0.30, 1.0),
		"muzzles_a": [Vector3(0.30, -0.10, -7.6), Vector3(-0.30, -0.10, -7.6)],
		"muzzles_b": [Vector3(2.60, -0.10, 1.0), Vector3(-2.60, -0.10, 1.0)],
		"thrusters": [Vector3(0.55, 0.06, 0), Vector3(-0.55, 0.06, 0)],
		"eye": Vector3(0, 0.66, -2.2),
	},
	"paladin": {
		"label": "SA-11 Paladin", "role": "Assault Gunship",
		"desc": "Four engines, six racks and a chin gun. It does not dodge; it arrives.",
		"model": "res://assets/models/ship_paladin.glb",
		"speed": 104.0, "accel": 46.0, "turn": 0.78, "mass": 24.0,
		"hull": 240.0, "armor": 0.46, "shield": 165.0, "shield_regen": 7.0,
		"energy": 160.0, "energy_regen": 15.0, "heat_cap": 175.0, "cool": 18.0,
		"boost_mult": 1.55, "boost_drain": 15.0,
		"missile_cap": 14, "cm_count": 10,
		"default_primary": "repeater", "default_primary2": "flak", "default_missile": "cluster",
		"paint": Color(0.52, 0.50, 0.30), "glow": Color(1.0, 0.55, 0.14),
		"muzzles_a": [Vector3(0.28, -0.92, -6.8), Vector3(-0.28, -0.92, -6.8)],
		"muzzles_b": [Vector3(4.05, -0.15, -3.4), Vector3(-4.05, -0.15, -3.4)],
		"thrusters": [Vector3(1.05, 0.42, 0), Vector3(-1.05, 0.42, 0),
			Vector3(1.05, -0.42, 0), Vector3(-1.05, -0.42, 0)],
		"eye": Vector3(0, 1.05, -3.0),
	},
	"peregrine": {
		"label": "SF-12 Peregrine", "role": "Precision Interceptor",
		"desc": "Long canards, swept wings and twin vector drives. Fast surgical passes; light armor rewards a clean exit.",
		"model": "res://assets/models/ship_peregrine.glb", "authored": true,
		"speed": 148.0, "accel": 74.0, "turn": 1.32, "mass": 10.5,
		"hull": 90.0, "armor": 0.14, "shield": 82.0, "shield_regen": 8.5,
		"energy": 105.0, "energy_regen": 17.0, "heat_cap": 105.0, "cool": 17.0,
		"boost_mult": 1.86, "boost_drain": 23.0,
		"missile_cap": 6, "cm_count": 14,
		"default_primary": "railgun", "default_primary2": "ion", "default_missile": "heatseeker",
		"paint": Color(0.08, 0.22, 0.34), "glow": Color(0.18, 0.73, 1.0),
		"muzzles_a": [Vector3(0.52, -0.27, -8.4), Vector3(-0.52, -0.27, -8.4)],
		"muzzles_b": [Vector3(4.8, -0.30, -2.1), Vector3(-4.8, -0.30, -2.1)],
		"thrusters": [Vector3(1.8, 0.10, 0), Vector3(-1.8, 0.10, 0)],
		"eye": Vector3(0, 1.1, -3.0),
	},
	"aegis": {
		"label": "SA-14 Aegis", "role": "Escort Strike Fighter",
		"desc": "A broad armored wing, four drives and recessed missile racks. Holds the line while lighter fighters circle.",
		"model": "res://assets/models/ship_aegis.glb", "authored": true,
		"speed": 110.0, "accel": 49.0, "turn": 0.87, "mass": 22.0,
		"hull": 205.0, "armor": 0.38, "shield": 150.0, "shield_regen": 7.2,
		"energy": 145.0, "energy_regen": 14.0, "heat_cap": 152.0, "cool": 16.0,
		"boost_mult": 1.60, "boost_drain": 17.0,
		"missile_cap": 12, "cm_count": 10,
		"default_primary": "plasma", "default_primary2": "autocannon", "default_missile": "radar",
		"paint": Color(0.62, 0.13, 0.045), "glow": Color(0.35, 0.75, 1.0),
		"muzzles_a": [Vector3(0.52, -0.27, -8.4), Vector3(-0.52, -0.27, -8.4)],
		"muzzles_b": [Vector3(5.5, -0.30, -3.9), Vector3(-5.5, -0.30, -3.9)],
		"thrusters": [Vector3(2.05, 0.15, 0), Vector3(-2.05, 0.15, 0),
			Vector3(4.20, 0.15, 0), Vector3(-4.20, 0.15, 0)],
		"eye": Vector3(0, 1.1, -3.0),
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
