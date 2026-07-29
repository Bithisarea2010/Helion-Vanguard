extends Node3D
## Empty-scene frame-rate floor probe. Establishes what the machine/driver can
## do with essentially nothing on screen, so battle numbers can be read against
## a real ceiling instead of an assumed one.
##   Godot --path . tests/PerfFloor.tscn -- --uncapped

var _t := 0.0
var _frames := 0
var _total := 0.0

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.06)
	env.environment = e
	add_child(env)

func _process(delta: float) -> void:
	_t += delta
	_total += delta
	_frames += 1
	if _t >= 1.0:
		print("[FLOOR] fps=%.1f frame=%.2fms" % [float(_frames) / _t, _t / float(_frames) * 1000.0])
		_t = 0.0
		_frames = 0
	if _total > 6.0:
		get_tree().quit()
