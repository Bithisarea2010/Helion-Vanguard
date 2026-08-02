class_name DeepSky
extends Node3D
## Named deep-sky objects that need more angular resolution than the sky
## panorama can give them.
##
## The panorama bakes the whole celestial sphere into 4096x2048 (~0.09 deg per
## texel). Andromeda spans ~26 deg here, which is ~290 texels across — a smudge.
## Each object in this node instead gets its own square bake at up to 2048², i.e.
## ~0.013 deg per texel, and rides a card that is re-pinned to the camera every
## frame so it behaves like a fixed point on the sky.
##
## Cost: one bake frame per object at mission load, then one additive quad and
## one transform write per frame. The cards are depth-tested, so planets and
## hulls occlude them correctly.

const CARD_DISTANCE := 45000.0     # inside the camera's 60 km far plane

var _cards: Array[MeshInstance3D] = []
var _dirs: Array[Vector3] = []

## `objects` entries: {dir, angular_deg, brightness, inclination, position_angle,
## pitch, core, arm, hii, dust}
func build(objects: Array) -> void:
	# serialised: each bake owns a SubViewport for two frames, and running three
	# at once would triple the peak render-target footprint at load for no gain
	for cfg in objects:
		await _build_one(cfg)

func _build_one(cfg: Dictionary) -> void:
	var res: int = int(cfg.get("res", 2048))
	if int(Game.settings.preset) < 2:
		res /= 2
	var tex := await _bake(cfg, res)
	if tex == null:
		return
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var ang: float = deg_to_rad(float(cfg.get("angular_deg", 26.0)))
	var span := 2.0 * CARD_DISTANCE * tan(ang * 0.5)
	qm.size = Vector2(span, span)
	mi.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/galaxy_card.gdshader")
	m.set_shader_parameter("galaxy_tex", tex)
	m.set_shader_parameter("gain", float(cfg.get("gain", 1.0)))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = span
	add_child(mi)
	_cards.append(mi)
	_dirs.append((cfg.get("dir", Vector3(-0.55, 0.35, -0.75)) as Vector3).normalized())
	_reposition()

func _bake(cfg: Dictionary, res: int) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(res, res)
	vp.disable_3d = true
	vp.use_hdr_2d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cr := ColorRect.new()
	cr.size = Vector2(vp.size)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/galaxy_bake.gdshader")
	m.set_shader_parameter("inclination_deg", float(cfg.get("inclination", 77.0)))
	m.set_shader_parameter("position_angle_deg", float(cfg.get("position_angle", 38.0)))
	m.set_shader_parameter("winding", float(cfg.get("winding", 2.6)))
	m.set_shader_parameter("brightness", float(cfg.get("brightness", 1.0)))
	for key in [["core", "core_color"], ["arm", "arm_color"],
			["hii", "hii_color"], ["dust", "dust_color"]]:
		if cfg.has(key[0]):
			m.set_shader_parameter(key[1], cfg[key[0]])
	cr.material = m
	vp.add_child(cr)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		return null
	# RGBE9995 for the same reason the sky uses it: the core is genuinely over
	# range and has to survive into the bloom pass, at 4 bytes/texel not 8.
	# A 2048² card is 16 MB this way instead of 32.
	img.convert(Image.FORMAT_RGBE9995)
	# mipmaps stop the resolved-star layer aliasing into a crawling glitter field
	# when the card is small on screen; not fatal if the format refuses them
	if img.generate_mipmaps() != OK:
		push_warning("DeepSky: could not build mipmaps for the galaxy card")
	return ImageTexture.create_from_image(img)

func _process(_delta: float) -> void:
	_reposition()

## Pin every card to a fixed direction on the sky. Parenting to the camera would
## make the object rotate with the lens; writing the transform keeps it at a
## fixed bearing while the ship flies, which is what "very far away" looks like.
func _reposition() -> void:
	if _cards.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var origin := cam.global_position
	for i in _cards.size():
		var mi: MeshInstance3D = _cards[i]
		if not is_instance_valid(mi):
			continue
		var dir: Vector3 = _dirs[i]
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.97 else Vector3.RIGHT
		# QuadMesh faces +Z, so look_at(-dir) turns its face back toward the lens
		mi.global_transform = Transform3D(Basis.looking_at(-dir, up),
			origin + dir * CARD_DISTANCE)
