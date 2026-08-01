extends Node
## Audio manager: buses, pooled 2D/3D one-shots, music crossfade.

var _sounds := {}                  # name -> AudioStream
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active_a := true
var _current_track := ""
var _music_tween: Tween = null
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
const POOL_2D := 12
const POOL_3D := 32

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	_load_sounds()
	_music_a = AudioStreamPlayer.new(); _music_a.bus = "Music"; add_child(_music_a)
	_music_b = AudioStreamPlayer.new(); _music_b.bus = "Music"; add_child(_music_b)
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
	for bus_name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

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
		"SFX": float(s.vol_sfx), "UI": float(s.vol_ui)}
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
	for p in _pool_2d:
		if not p.playing:
			p.stream = _sounds[sound]
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return

func play_3d(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_dist := 1200.0) -> void:
	if not _sounds.has(sound):
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
func play_music(track: String, fade := 1.5) -> void:
	if track == _current_track:
		return
	var stream: AudioStream = null
	var path := "res://assets/audio/music/%s.ogg" % track
	if ResourceLoader.exists(path):
		stream = load(path)
	else:
		path = "res://assets/audio/music/%s.wav" % track
		if ResourceLoader.exists(path):
			stream = load(path)
	if stream == null:
		push_warning("Music track not found: %s" % track)
		return
	_current_track = track
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int(stream.get_length() * stream.mix_rate)
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
	_current_track = ""
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	for p in [_music_a, _music_b]:
		if p.playing:
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
	for p in [_music_a, _music_b]:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
			p.free()
	_pool_2d.clear()
	_pool_3d.clear()
	_music_a = null
	_music_b = null
	_sounds.clear()
	_current_track = ""

func _exit_tree() -> void:
	shutdown()
