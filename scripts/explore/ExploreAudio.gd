class_name ExploreAudio
extends Node
## Six original synthesized loops; no combat-playlist music is required by an expedition.
var layers: Dictionary = {}
var foot_distance := 0.0
var last_foot := 0.0
func _ready() -> void:
	AudioMgr.stop_music(1.0)
	for id in ["engine","wind","rain","surf","forest","orbit_pad"]:
		var player := AudioStreamPlayer.new(); player.bus="Music" if id=="orbit_pad" else "Ambience"
		var stream := (load("res://assets/audio/explore/%s.wav" % id) as AudioStreamWAV).duplicate() as AudioStreamWAV
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD; stream.loop_end=int(stream.get_length()*stream.mix_rate)
		player.stream=stream; player.volume_db=-60.0; add_child(player); player.play(); layers[id]=player

func tick(dt: float,world: ExploreWorld) -> void:
	var on_foot := world.astronaut!=null
	var inside := on_foot and world.astronaut.inside
	var in_air := world.ship.flight.density>0.01
	var heat := world.ship.flight.heating
	var targets := {"engine":-18.0 if not on_foot and not world.ship.landed else -36.0,
		"wind":lerpf(-38.0,-8.0,clampf(world.ship.velocity.length()/1000.0+heat*0.5,0,1)) if in_air and not inside else -60.0,
		"rain":lerpf(-50.0,-13.0,world.weather.values.y) if in_air and not inside else -60.0,
		"surf":-17.0 if on_foot and not inside and world.biome_name in ["Coast","Ocean"] else -60.0,
		"forest":-15.0 if on_foot and not inside and world.biome_name=="Temperate forest" else -60.0,
		"orbit_pad":-19.0 if AudioMgr.music_enabled() else -80.0}
	for id in layers:
		var player: AudioStreamPlayer=layers[id]
		player.volume_db=move_toward(player.volume_db,targets[id],dt*15.0)
	layers.engine.pitch_scale=0.75+minf(world.ship.velocity.length()/1800.0,0.9)
	if on_foot and world.astronaut.is_on_floor():
		foot_distance+=world.astronaut.velocity.length()*dt
		if foot_distance-last_foot>1.75:
			last_foot=foot_distance
			AudioMgr.play_ui("hit_rock",-24.0,0.75 if inside else 0.5)
