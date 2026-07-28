class_name Styles
## Shared visual identity: fonts, colors, panels, buttons.

const CYAN := Color(0.38, 0.85, 1.0)
const ORANGE := Color(1.0, 0.58, 0.15)
const RED := Color(1.0, 0.25, 0.18)
const GREEN := Color(0.35, 1.0, 0.55)
const DIM := Color(0.55, 0.65, 0.75)
const BG := Color(0.03, 0.05, 0.09, 0.82)
const BG_SOLID := Color(0.035, 0.055, 0.095, 1.0)

static var _title_font: FontFile = null
static var _body_font: FontFile = null

static func title_font() -> Font:
	if _title_font == null:
		_title_font = load("res://assets/fonts/Orbitron.ttf")
	return _title_font

static func body_font() -> Font:
	if _body_font == null:
		_body_font = load("res://assets/fonts/Exo2.ttf")
	return _body_font

static func label(text: String, size: int, color := Color.WHITE, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font() if title else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func panel(color := BG, corner := 6, border := Color(0.3, 0.6, 0.8, 0.35)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(corner)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_content_margin_all(12)
	return sb

static func button(text: String, size := 22, accent := CYAN) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", title_font())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", ORANGE)
	b.add_theme_color_override("font_focus_color", accent)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.09, 0.14, 0.85)
	normal.set_corner_radius_all(4)
	normal.set_border_width_all(1)
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.25)
	normal.content_margin_left = 26; normal.content_margin_right = 26
	normal.content_margin_top = 10; normal.content_margin_bottom = 10
	var hover := normal.duplicate()
	hover.bg_color = Color(0.08, 0.14, 0.2, 0.9)
	hover.border_color = accent
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.1, 0.08, 0.05, 0.95)
	pressed.border_color = ORANGE
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): AudioMgr.play_ui("ui_click"))
	b.mouse_entered.connect(func(): AudioMgr.play_ui("ui_hover", -12.0))
	return b

static func hslider(minv: float, maxv: float, val: float, step := 0.05) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(220, 24)
	return s
