extends Node
## Audio manager: buses, pooled 2D/3D one-shots, music crossfade.

## User-provided combat playlist. The shuffle bag below guarantees that all six
## tracks are heard before any one of them is selected again.
const RANDOM_MUSIC_TRACKS := [
	{"id": "warp_speed_rush", "title": "Warp Speed Rush",
		"path": "res://assets/audio/music/Warp Speed Rush.mp3"},
	{"id": "neon_dogfight", "title": "Neon Dogfight",
		"path": "res://assets/audio/music/Neon Dogfight.mp3"},
	{"id": "orbit_assassin", "title": "Orbit Assassin",
		"path": "res://assets/audio/music/Orbit Assassin.mp3"},
	{"id": "hyperdrive_conflict", "title": "Hyperdrive Conflict",
		"path": "res://assets/audio/music/Hyperdrive Conflict.mp3"},
	{"id": "frontier_combat_drive", "title": "Frontier Combat Drive",
		"path": "res://assets/audio/music/Frontier Combat Drive.mp3"},
	{"id": "stellar_vanguard", "title": "Stellar Vanguard",
		"path": "res://assets/audio/music/Stellar Vanguard.mp3"},
]

var _sounds := {}                  # name -> AudioStream
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _flight_bed: AudioStreamPlayer
var _music_active_a := true
var _current_track := ""
var _current_track_title := ""
var _music_bag: Array[String] = []
var _last_random_track := ""
var _random_playlist_active := false
var _music_tween: Tween = null
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
const POOL_2D := 12
const POOL_3D := 32
var _radio_duck_until := 0
var _music_trim_db := 0.0
var _ui_last_play := {}
const UI_COOLDOWNS := {"hitmarker": 45, "radio": 220, "alarm_missile": 600,
	"hv_shield": 100, "hv_armor": 100, "hv_transit": 1000, "hv_resupply": 1000}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	_load_sounds()
	_start_flight_bed()
	_music_a = AudioStreamPlayer.new(); _music_a.bus = "Music"; add_child(_music_a)
	_music_b = AudioStreamPlayer.new(); _music_b.bus = "Music"; add_child(_music_b)
	_music_a.finished.connect(func(): _on_music_finished(_music_a))
	_music_b.finished.connect(func(): _on_music_finished(_music_b))
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 1200.0
		p.unit_size = 25.0
		p.attenuation_filter_cutoff_hz = 18000
		add_child(p)
		_pool_3d.append(p)
	apply_volumes()

func _make_buses() -> void:
	for bus_name in ["Music", "SFX", "UI", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

	# Bounded dynamics keep clustered impacts intelligible and prevent digital
	# clipping at the master output. All effects preserve the user's bus gains.
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = -13.0
	compressor.ratio = 2.4
	compressor.attack_us = 6000.0
	compressor.release_ms = 160.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SFX"), compressor)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.release = 0.08
	AudioServer.add_bus_effect(0, limiter)

func duck_music(seconds := 2.0) -> void:
	_radio_duck_until = maxi(_radio_duck_until, Time.get_ticks_msec() + int(seconds * 1000.0))

func _process(delta: float) -> void:
	var target_db := -4.5 if Time.get_ticks_msec() < _radio_duck_until else 0.0
	if get_tree().paused:
		target_db = minf(target_db, -6.0)
	_music_trim_db = move_toward(_music_trim_db, target_db, delta * (18.0 if target_db < _music_trim_db else 3.0))
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(float(Game.settings.vol_music), 0.0001)) + _music_trim_db)

	if is_instance_valid(_flight_bed):
		var scene := get_tree().current_scene
		var in_flight: bool = is_instance_valid(scene) and scene.has_method("loading_in_progress") and not scene.get("over")
		var bed_db := -19.0 if in_flight else -29.0
		if get_tree().paused:
			bed_db = -32.0
		_flight_bed.volume_db = lerpf(_flight_bed.volume_db, bed_db, 1.0 - exp(-delta * 1.5))

func _start_flight_bed() -> void:
	var bed := stream("hv_flight_bed") as AudioStreamWAV
	if bed == null:
		return
	bed.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bed.loop_begin = 0
	bed.loop_end = int(bed.get_length() * bed.mix_rate)
	_flight_bed = AudioStreamPlayer.new()
	_flight_bed.bus = "Ambience"
	_flight_bed.stream = bed
	_flight_bed.volume_db = -32.0
	add_child(_flight_bed)
	_flight_bed.play()

func _load_sounds() -> void:
	var dir := DirAccess.open("res://assets/audio/sfx")
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var base := ""
		if f.ends_with(".wav") or f.ends_with(".ogg"):
			base = f.get_basename()
		elif f.ends_with(".wav.import") or f.ends_with(".ogg.import"):
			base = f.trim_suffix(".import").get_basename()
		if base != "" and not _sounds.has(base):
			var res_path := "res://assets/audio/sfx/" + f.trim_suffix(".import")
			var s: AudioStream = load(res_path)
			if s:
				_sounds[base] = s
		f = dir.get_next()

func has_sound(sound: String) -> bool:
	return _sounds.has(sound)

## Raw stream for callers that own their own player (looping engine/FTL beds).
## Returns a duplicate so a caller setting `loop_mode` cannot corrupt the shared
## one-shot copy — that bug once made every explosion loop forever.
func stream(sound: String) -> AudioStream:
	if not _sounds.has(sound):
		return null
	return (_sounds[sound] as AudioStream).duplicate()

func apply_volumes() -> void:
	var s: Dictionary = Game.settings
	var levels := {"Master": float(s.vol_master), "Music": float(s.vol_music),
		"SFX": float(s.vol_sfx), "UI": float(s.vol_ui), "Ambience": float(s.vol_ambience)}
	for bus_name in levels:
		var idx := 0 if bus_name == "Master" else AudioServer.get_bus_index(bus_name)
		if idx < 0:
			continue
		var level: float = levels[bus_name]
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(level, 0.0001, 1.0)))
		AudioServer.set_bus_mute(idx, level <= 0.001)

# ---------------------------------------------------------------- one-shots
func play_ui(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _sounds.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - int(_ui_last_play.get(sound, -10000)) < int(UI_COOLDOWNS.get(sound, 0)):
		return
	_ui_last_play[sound] = now
	# Reserve the last voice for lock/missile warnings: rapid hit confirmations
	# cannot swallow a survival-critical cue.
	var priority := sound in ["alarm_missile", "lock_tone", "mission_fail"]
	if priority and not _pool_2d.is_empty():
		var warning: AudioStreamPlayer = _pool_2d.back()
		warning.stream = _sounds[sound]
		warning.volume_db = volume_db
		warning.pitch_scale = pitch
		warning.play()
		return
	for i in maxi(_pool_2d.size() - 1, 0):
		var p := _pool_2d[i]
		if not p.playing:
			p.stream = _sounds[sound]
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return

func play_3d(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_dist := 1200.0) -> void:
	if not _sounds.has(sound):
		return
	var camera := get_viewport().get_camera_3d()
	if is_instance_valid(camera) and camera.global_position.distance_squared_to(pos) > max_dist * max_dist:
		return
	for p in _pool_3d:
		if not p.playing:
			p.global_position = pos
			p.stream = _sounds[sound]
			p.volume_db = volume_db
			p.pitch_scale = pitch * randf_range(0.94, 1.06)
			p.max_distance = max_dist
			p.play()
			return

# ---------------------------------------------------------------- music
func background_music_tracks() -> Array:
	return RANDOM_MUSIC_TRACKS.duplicate(true)

func music_enabled() -> bool:
	return bool(Game.settings.get("music_enabled", true))

func current_music_title() -> String:
	return _current_track_title

func is_music_playing() -> bool:
	return (
		(is_instance_valid(_music_a) and _music_a.playing)
		or (is_instance_valid(_music_b) and _music_b.playing)
	)

## Keep the playlist alive across menu/mission scene transitions. This does not
## restart an already-playing track; the finished signal advances the bag.
func ensure_background_music(fade := 1.5) -> void:
	if not music_enabled():
		_random_playlist_active = false
		if is_music_playing():
			stop_music(0.35)
		return
	_random_playlist_active = true
	if not is_music_playing():
		play_random_music(fade)

func set_music_enabled(enabled: bool) -> void:
	Game.settings.music_enabled = enabled
	Game.mark_settings_dirty()
	if enabled:
		ensure_background_music(0.6)
	else:
		_random_playlist_active = false
		stop_music(0.35)

func play_random_music(fade := 1.5) -> void:
	if not music_enabled():
		return
	_random_playlist_active = true
	if _music_bag.is_empty():
		_refill_music_bag()
	var track_id: String = str(_music_bag.pop_front())
	var track: Dictionary = _track_by_id(track_id)
	if track.is_empty():
		_refill_music_bag()
		track_id = str(_music_bag.pop_front())
		track = _track_by_id(track_id)
	if not track.is_empty():
		_last_random_track = track_id
		var stream: AudioStream = load(str(track.path))
		if stream == null:
			push_warning("Playlist track not found: %s" % track.path)
			return
		_play_music_stream(stream, str(track.id), str(track.title), fade)

func _refill_music_bag() -> void:
	_music_bag.clear()
	for track in RANDOM_MUSIC_TRACKS:
		_music_bag.append(str(track.id))
	_music_bag.shuffle()
	if _music_bag.size() > 1 and _music_bag[0] == _last_random_track:
		var swap_idx := 1
		_music_bag[0] = _music_bag[swap_idx]
		_music_bag[swap_idx] = _last_random_track

func _track_by_id(track_id: String) -> Dictionary:
	for track in RANDOM_MUSIC_TRACKS:
		if str(track.id) == track_id:
			return track
	return {}

func _on_music_finished(player: AudioStreamPlayer) -> void:
	if not _random_playlist_active or not music_enabled():
		return
	var active := _music_b if _music_active_a else _music_a
	if player == active:
		play_random_music(1.25)

func play_music(track: String, fade := 1.5) -> void:
	# Existing callers use "menu" and "combat" as semantic states. Both now
	# enter the same randomized background playlist, preserving the old API.
	if track == "menu" or track == "combat" or track == "random":
		ensure_background_music(fade)
		return
	if not music_enabled():
		return
	if track == _current_track:
		return
	var stream: AudioStream = null
	for candidate in [
		"res://assets/audio/music/%s.ogg" % track,
		"res://assets/audio/music/%s.wav" % track,
		"res://assets/audio/music/%s.mp3" % track,
	]:
		if ResourceLoader.exists(candidate):
			stream = load(candidate)
			break
	if stream == null:
		push_warning("Music track not found: %s" % track)
		return
	_play_music_stream(stream, track, track.capitalize(), fade)

func _play_music_stream(stream: AudioStream, track: String, title: String, fade: float) -> void:
	if stream == null or track == _current_track:
		return
	_current_track = track
	_current_track_title = title
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int(stream.get_length() * stream.mix_rate)
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	var incoming := _music_b if _music_active_a else _music_a
	var outgoing := _music_a if _music_active_a else _music_b
	_music_active_a = not _music_active_a
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	fade = maxf(fade, 0.01)
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", 0.0, fade)
	if outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", -40.0, fade)
		_music_tween.chain().tween_callback(outgoing.stop)

func stop_music(fade := 1.0) -> void:
	_random_playlist_active = false
	_current_track = ""
	_current_track_title = ""
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	for p in [_music_a, _music_b]:
		if is_instance_valid(p) and p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -40.0, fade)
			tw.tween_callback(p.stop)

func shutdown() -> void:
	# Release active playback objects synchronously. Exported builds normally
	# fade them out, but test harnesses and OS quits can tear the tree down in
	# one frame and would otherwise retain the WAV playback references.
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null
	for p in _pool_2d:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
			p.free()
	for p in _pool_3d:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
			p.free()
	for p in [_music_a, _music_b, _flight_bed]:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
			p.free()
	_pool_2d.clear()
	_pool_3d.clear()
	_music_a = null
	_music_b = null
	_flight_bed = null
	_sounds.clear()
	_current_track = ""
	_current_track_title = ""

func _exit_tree() -> void:
	shutdown()
