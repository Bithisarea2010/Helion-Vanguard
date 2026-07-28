extends Node
## Audio manager: buses, pooled 2D/3D one-shots, music crossfade.

var _sounds := {}                  # name -> AudioStream
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active_a := true
var _current_track := ""
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

func apply_volumes() -> void:
	var s: Dictionary = Game.settings
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(s.vol_master, 0.0001, 1.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(clampf(s.vol_music, 0.0001, 1.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(clampf(s.vol_sfx, 0.0001, 1.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), linear_to_db(clampf(s.vol_ui, 0.0001, 1.0)))
	AudioServer.set_bus_mute(0, s.vol_master <= 0.001)

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
	_current_track = track
	var stream: AudioStream = null
	var path := "res://assets/audio/music/%s.ogg" % track
	if ResourceLoader.exists(path):
		stream = load(path)
	else:
		path = "res://assets/audio/music/%s.wav" % track
		if ResourceLoader.exists(path):
			stream = load(path)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int(stream.get_length() * stream.mix_rate)
	var incoming := _music_b if _music_active_a else _music_a
	var outgoing := _music_a if _music_active_a else _music_b
	_music_active_a = not _music_active_a
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(incoming, "volume_db", 0.0, fade)
	if outgoing.playing:
		tw.tween_property(outgoing, "volume_db", -40.0, fade)
		tw.chain().tween_callback(outgoing.stop)

func stop_music(fade := 1.0) -> void:
	_current_track = ""
	for p in [_music_a, _music_b]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -40.0, fade)
			tw.tween_callback(p.stop)
