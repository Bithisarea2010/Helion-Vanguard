class_name LoadingProgress
extends Control
## Interactive FTL spool instrument used by loading and waiting screens.
##
## Progress is immutable from input: hover, click, keyboard and gamepad create
## harmless energy pulses and expose stage telemetry, but never falsify load.

signal pulse_requested

const SEGMENTS := 30
const CYAN := Color(0.38, 0.85, 1.0)
const ORANGE := Color(1.0, 0.58, 0.15)
const NAVY := Color(0.018, 0.032, 0.060, 0.94)
const DIM := Color(0.55, 0.65, 0.75)

var target_progress := 0.0
var displayed_progress := 0.0
var stage_name := "FTL CORRIDOR"
var stage_detail := "Awaiting flight-control telemetry"
var _time := 0.0
var _pulse := 0.0
var _hover_segment := -1

func _ready() -> void:
	custom_minimum_size = Vector2(760, 210)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Move across the flight path or press Space / Accept to pulse the FTL field"
	accessibility_name = "FTL loading progress"
	accessibility_live = AccessibilityServer.LIVE_POLITE
	_update_accessibility()
	set_process(true)

func set_progress(value: float, stage: String, detail: String) -> void:
	target_progress = maxf(target_progress, clampf(value, 0.0, 1.0))
	if stage != "":
		stage_name = stage
	if detail != "":
		stage_detail = detail
	_update_accessibility()
	queue_redraw()

func reset() -> void:
	target_progress = 0.0
	displayed_progress = 0.0
	stage_name = "FTL CORRIDOR"
	stage_detail = "Awaiting flight-control telemetry"
	_hover_segment = -1
	_pulse = 0.0
	_update_accessibility()
	queue_redraw()

func _accessibility_get_contextual_info() -> String:
	return "%d percent" % int(round(target_progress * 100.0))

func _update_accessibility() -> void:
	accessibility_description = "%s. %s. %d percent complete." % [
		stage_name, stage_detail, int(round(target_progress * 100.0))]
	queue_accessibility_update()

func trigger_pulse() -> void:
	_pulse = 1.0
	pulse_requested.emit()
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	displayed_progress = lerpf(displayed_progress, target_progress,
		1.0 - exp(-7.5 * delta))
	# Do not let cosmetic easing lag more than one small stage behind truth.
	# Warm loads can publish several real checkpoints in consecutive frames.
	displayed_progress = maxf(displayed_progress, target_progress - 0.12)
	if target_progress >= 1.0 and displayed_progress > 0.997:
		displayed_progress = 1.0
	_pulse = maxf(0.0, _pulse - delta * 1.45)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hover_segment = _segment_at(mm.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			trigger_pulse()
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			trigger_pulse()
			accept_event()
	elif event.is_action_pressed("ui_accept"):
		trigger_pulse()
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_segment = -1
		queue_redraw()

func _segment_at(p: Vector2) -> int:
	var left := 30.0
	var right := maxf(left + 1.0, size.x - 236.0)
	var rail_y := size.y - 43.0
	if p.x < left or p.x > right or absf(p.y - rail_y) > 25.0:
		return -1
	return clampi(int((p.x - left) / (right - left) * SEGMENTS), 0, SEGMENTS - 1)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 1.0 or h < 1.0:
		return
	# Avionics glass with clipped technical corners.
	var cut := 18.0
	var panel := PackedVector2Array([
		Vector2(cut, 0), Vector2(w - cut, 0), Vector2(w, cut),
		Vector2(w, h - cut), Vector2(w - cut, h), Vector2(cut, h),
		Vector2(0, h - cut), Vector2(0, cut),
	])
	draw_colored_polygon(panel, NAVY)
	draw_polyline(PackedVector2Array(Array(panel) + [panel[0]]),
		Color(CYAN.r, CYAN.g, CYAN.b, 0.34), 1.2, true)
	# Stage telemetry.
	draw_string(Styles.title_font(), Vector2(30, 38), stage_name,
		HORIZONTAL_ALIGNMENT_LEFT, w - 280.0, 17, CYAN)
	draw_string(Styles.body_font(), Vector2(30, 67), stage_detail,
		HORIZONTAL_ALIGNMENT_LEFT, w - 280.0, 15, Color(0.84, 0.90, 0.97))
	draw_string(Styles.body_font(), Vector2(30, 94),
		"LIVE LOAD VECTOR  //  POINTER FIELD INTERACTIVE",
		HORIZONTAL_ALIGNMENT_LEFT, w - 280.0, 11, DIM)

	# Circular FTL spool. Completed sectors burn from cyan into Helion orange.
	var center := Vector2(w - 114.0, 96.0)
	var radius := minf(72.0, h * 0.34)
	for i in SEGMENTS:
		var a0 := -PI * 0.5 + TAU * float(i) / float(SEGMENTS)
		var a1 := -PI * 0.5 + TAU * (float(i) + 0.70) / float(SEGMENTS)
		var done := float(i + 1) / float(SEGMENTS) <= displayed_progress + 0.001
		var active := i == clampi(int(displayed_progress * SEGMENTS), 0, SEGMENTS - 1)
		var col := Color(0.28, 0.42, 0.55, 0.26)
		if done:
			col = CYAN.lerp(ORANGE, float(i) / float(SEGMENTS) * 0.48)
		elif active:
			var breathe := 0.55 + sin(_time * 7.0) * 0.25
			col = Color(CYAN.r, CYAN.g, CYAN.b, breathe)
		var points := PackedVector2Array()
		for j in 4:
			var a := lerpf(a0, a1, float(j) / 3.0)
			points.append(center + Vector2(cos(a), sin(a)) * radius)
		draw_polyline(points, col, 4.0 if active else 2.5, true)
	# Orbit crosshair and interactive pulse.
	draw_arc(center, radius - 13.0, 0, TAU, 72,
		Color(CYAN.r, CYAN.g, CYAN.b, 0.16), 1.0, true)
	var tracer_a := -PI * 0.5 + TAU * displayed_progress
	var tracer := center + Vector2(cos(tracer_a), sin(tracer_a)) * radius
	draw_circle(tracer, 4.5 + sin(_time * 9.0) * 1.2, Color.WHITE)
	draw_circle(tracer, 11.0, Color(CYAN.r, CYAN.g, CYAN.b, 0.15), false, 2.0)
	if _pulse > 0.0:
		for ring in 3:
			var pr := radius + (1.0 - _pulse) * 52.0 + float(ring) * 11.0
			draw_arc(center, pr, 0, TAU, 80,
				Color(CYAN.r, CYAN.g, CYAN.b, _pulse * (0.34 - ring * 0.07)),
				1.4, true)
	var pct := "%03d" % int(round(displayed_progress * 100.0))
	draw_string(Styles.title_font(), center + Vector2(-46, 10), pct,
		HORIZONTAL_ALIGNMENT_CENTER, 92, 30, Color.WHITE)
	draw_string(Styles.body_font(), center + Vector2(-46, 31), "PERCENT",
		HORIZONTAL_ALIGNMENT_CENTER, 92, 10, DIM)

	# Precise segmented accessibility rail.
	var left := 30.0
	var right := w - 236.0
	var rail_y := h - 43.0
	var gap := 3.0
	var seg_w := (right - left - gap * float(SEGMENTS - 1)) / float(SEGMENTS)
	for i in SEGMENTS:
		var x := left + float(i) * (seg_w + gap)
		var frac := float(i + 1) / float(SEGMENTS)
		var col := Color(0.22, 0.36, 0.48, 0.30)
		if frac <= displayed_progress + 0.001:
			col = CYAN.lerp(ORANGE, float(i) / float(SEGMENTS) * 0.36)
		if i == _hover_segment:
			col = Color.WHITE
			draw_rect(Rect2(x - 2, rail_y - 9, seg_w + 4, 18),
				Color(CYAN.r, CYAN.g, CYAN.b, 0.12), true)
		draw_rect(Rect2(x, rail_y - 4, maxf(seg_w, 1.0), 8), col, true)
	# Focus indicator is deliberately technical, not a default consumer outline.
	if has_focus():
		draw_line(Vector2(18, h - 18), Vector2(58, h - 18), ORANGE, 2.0)
		draw_string(Styles.body_font(), Vector2(66, h - 14), "FTL FIELD ARMED",
			HORIZONTAL_ALIGNMENT_LEFT, 170, 10, ORANGE)
