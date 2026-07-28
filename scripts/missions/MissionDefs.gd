class_name MissionDefs
## Mission catalogue: metadata, briefings, environment configs.

const MISSIONS := {
	"training": {
		"title": "FLIGHT ACADEMY", "mode": "Training",
		"desc": "Learn flight, weapons, missiles and countermeasures in a safe range.",
		"briefing": [
			"Welcome to the Academy, pilot. Today you graduate.",
			"Follow instructions on the HUD. Nothing here shoots back — yet.",
		],
		"env": {"neb_a": Color(0.06, 0.12, 0.3), "neb_b": Color(0.02, 0.2, 0.3), "neb_c": Color(0.1, 0.1, 0.3),
			"planets": [{"pos": Vector3(9000, 2500, -16000), "radius": 3400.0,
				"col_a": Color(0.4, 0.55, 0.75), "col_b": Color(0.2, 0.3, 0.5), "atmo": Color(0.4, 0.7, 1.0)}]},
	},
	"instant_action": {
		"title": "INSTANT ACTION", "mode": "Skirmish",
		"desc": "Straight into a furball: hostile fighters and a corvette in the belt.",
		"briefing": [
			"VEX raiders are sweeping the Helion belt. You're the nearest interceptor.",
			"Clear the sector. Watch the rocks — they don't care whose side you're on.",
		],
		"env": {"neb_a": Color(0.16, 0.05, 0.28), "neb_b": Color(0.02, 0.16, 0.30), "neb_c": Color(0.3, 0.1, 0.05),
			"sun_dir": Vector3(0.3, -0.22, 0.85),
			"planets": [{"pos": Vector3(-14000, -1000, -20000), "radius": 5200.0,
				"col_a": Color(0.85, 0.5, 0.25), "col_b": Color(0.5, 0.22, 0.1), "atmo": Color(1.0, 0.6, 0.3)},
				{"pos": Vector3(16000, 5000, 9000), "radius": 1500.0, "rocky": 1.0,
				"col_a": Color(0.5, 0.48, 0.45), "col_b": Color(0.3, 0.28, 0.26), "atmo": Color(0.5, 0.6, 0.8), "atmo_strength": 0.4}]},
	},
	"patrol": {
		"title": "BELT PATROL", "mode": "Patrol",
		"desc": "Sweep the dense asteroid belt and destroy three raider flights.",
		"briefing": [
			"Mining Guild reports raider activity deep in the belt.",
			"Sweep the field. Expect ambushes between the big rocks.",
		],
		"env": {"neb_a": Color(0.05, 0.18, 0.2), "neb_b": Color(0.02, 0.1, 0.25), "neb_c": Color(0.25, 0.12, 0.04),
			"planets": [{"pos": Vector3(0, -8000, -22000), "radius": 6000.0,
				"col_a": Color(0.75, 0.65, 0.5), "col_b": Color(0.45, 0.35, 0.25), "atmo": Color(0.9, 0.8, 0.6)}]},
	},
	"convoy": {
		"title": "IRON CARAVAN", "mode": "Escort",
		"desc": "Protect three ore haulers crossing the mining zone from raider waves.",
		"briefing": [
			"Three haulers are running refined helion ore to the jump gate.",
			"VEX wants that ore vaporised. Keep at least one hauler alive.",
		],
		"env": {"neb_a": Color(0.2, 0.1, 0.05), "neb_b": Color(0.1, 0.08, 0.2), "neb_c": Color(0.3, 0.15, 0.03),
			"planets": [{"pos": Vector3(12000, 3000, -18000), "radius": 4200.0,
				"col_a": Color(0.8, 0.45, 0.2), "col_b": Color(0.5, 0.25, 0.1), "atmo": Color(1.0, 0.55, 0.25)}]},
	},
	"station_defence": {
		"title": "SOLACE STAND", "mode": "Defence",
		"desc": "Bombers are coming for the carrier Solace. Stop every torpedo run.",
		"briefing": [
			"The Solace is our only carrier in the sector — and VEX knows it.",
			"Maulers inbound in waves. Kill the bombers before they launch torpedoes.",
		],
		"env": {"neb_a": Color(0.08, 0.06, 0.25), "neb_b": Color(0.15, 0.05, 0.2), "neb_c": Color(0.25, 0.08, 0.1),
			"planets": [{"pos": Vector3(-10000, 4000, 14000), "radius": 3600.0,
				"col_a": Color(0.35, 0.5, 0.7), "col_b": Color(0.15, 0.25, 0.45), "atmo": Color(0.4, 0.7, 1.0)}]},
	},
	"capital_strike": {
		"title": "KRAKEN HUNT", "mode": "Assault",
		"desc": "Disable and destroy two escorted VEX corvettes. Aim for the engines.",
		"briefing": [
			"Two Kraken corvettes anchor the VEX picket line.",
			"Kill their engines first — a drifting corvette is a dead corvette.",
		],
		"env": {"neb_a": Color(0.22, 0.05, 0.1), "neb_b": Color(0.06, 0.1, 0.25), "neb_c": Color(0.3, 0.1, 0.05),
			"planets": [{"pos": Vector3(0, 6000, -24000), "radius": 7000.0,
				"col_a": Color(0.6, 0.3, 0.45), "col_b": Color(0.3, 0.12, 0.25), "atmo": Color(0.8, 0.4, 0.6)}]},
	},
	"survival": {
		"title": "ENDLESS VOID", "mode": "Survival",
		"desc": "Waves without end. How long can you last? Score attack.",
		"briefing": [
			"Simulation deck: infinite hostiles, one pilot.",
			"Every wave is meaner. Set a record worth bragging about.",
		],
		"env": {"neb_a": Color(0.15, 0.04, 0.2), "neb_b": Color(0.03, 0.12, 0.28), "neb_c": Color(0.28, 0.1, 0.04),
			"planets": []},
	},
	"arena": {
		"title": "PROVING GROUNDS", "mode": "Weapons Test",
		"desc": "Static and drifting targets, unlimited ammo logistics. Test every gun.",
		"briefing": [
			"Weapons range is hot. Targets don't shoot back.",
			"Cycle weapon groups with V, missiles on right mouse. Go loud.",
		],
		"env": {"neb_a": Color(0.05, 0.15, 0.25), "neb_b": Color(0.1, 0.1, 0.3), "neb_c": Color(0.1, 0.2, 0.2),
			"planets": []},
	},
	"main": {
		"title": "OPERATION SUNFALL", "mode": "Campaign",
		"desc": "The full strike: escort, ambush, corvette duel — then burn the VEX Bastion.",
		"briefing": [
			"This is it, Vanguard. Operation SUNFALL — the strike on the Bastion.",
			"Phase one: cross the belt and clear the scouts. Phase two: cover the supply convoy.",
			"Phase three: gut their picket corvette. Phase four: kill the Bastion's shields, guns and reactor.",
			"Then run like hell. Solace will be waiting. Good hunting.",
		],
		"env": {"neb_a": Color(0.18, 0.06, 0.24), "neb_b": Color(0.03, 0.14, 0.3), "neb_c": Color(0.32, 0.12, 0.04),
			"planets": [{"pos": Vector3(-16000, -2000, -26000), "radius": 6500.0,
				"col_a": Color(0.85, 0.5, 0.25), "col_b": Color(0.5, 0.22, 0.1), "atmo": Color(1.0, 0.6, 0.3)},
				{"pos": Vector3(20000, 7000, 6000), "radius": 1800.0, "rocky": 1.0,
				"col_a": Color(0.55, 0.52, 0.5), "col_b": Color(0.3, 0.28, 0.27), "atmo": Color(0.6, 0.7, 0.9), "atmo_strength": 0.35}]},
	},
}

const ORDER := ["training", "instant_action", "patrol", "convoy", "station_defence",
	"capital_strike", "survival", "arena", "main"]

static func get_mission(id: String) -> Dictionary:
	return MISSIONS.get(id, MISSIONS.instant_action)
