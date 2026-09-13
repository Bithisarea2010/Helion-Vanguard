class_name HullMaterial
## Converts the flat Principled-BSDF materials baked into the ship GLBs into
## procedural hard-surface `hull.gdshader` materials.
##
## Legacy meshes have no UVs or textures. The authored 1.3 fleet retains UVs
## and uses a restrained shader profile over its modeled panel detail. This walks every MeshInstance3D surface once at spawn,
## reads whatever the GLB material declared (albedo / metallic / roughness /
## emission) and installs a shader material that adds plating, seams, bolts,
## edge wear and grime procedurally in object space.
##
## Materials are cached and shared by signature so a fleet of identical fighters
## still batches — creating one material per surface per ship would trade the
## GPU win for a CPU state-change loss, which this CPU-bound game cannot afford.

static var _cache := {}

const GLASS_SHADER := "res://shaders/canopy.gdshader"
const HULL_SHADER := "res://shaders/hull.gdshader"

static func clear_cache() -> void:
	_cache.clear()

## opts:
##   paint      Color  — override for materials named "*_hull"
##   glow       Color  — override for materials named "*_engine" / emissive
##   stripe     Color  — accent band colour (0 amount disables)
##   stripe_amount float
##   wear, grime, plate_scale  floats
##   rim        Color
static func apply(root: Node, opts := {}) -> AABB:
	var aabb := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var ab: AABB = mi.transform * mi.get_aabb()
		aabb = ab if first else aabb.merge(ab)
		first = false
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src is BaseMaterial3D:
				mi.set_surface_override_material(s, _material_for(src as BaseMaterial3D, opts))
	return aabb

static func _material_for(src: BaseMaterial3D, opts: Dictionary) -> Material:
	var name := src.resource_name.to_lower()
	var albedo := src.albedo_color
	var metal := src.metallic
	var rough := src.roughness
	var albedo_tex: Texture2D = src.albedo_texture
	var emit_col := src.emission if src.emission_enabled else Color(0, 0, 0)
	var emit_e := src.emission_energy_multiplier if src.emission_enabled else 0.0

	# transparent surfaces are canopies — they get their own shader
	var transparent: bool = src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
		or albedo.a < 0.99
	if transparent:
		return _glass_material(src, opts)

	# named-slot overrides keep the existing loadout paint/glow behaviour
	if name.ends_with("_hull") and not name.ends_with("2_hull"):
		albedo = opts.get("paint", albedo)
		# The Blender palette gave painted hull metallic 0.75. Paint is not bare
		# metal: at that value the diffuse term nearly vanishes, the surface just
		# mirrors the blue nebula, and the ship's livery colour disappears.
		metal = 0.30
		rough = 0.44
	if name.find("_engine") != -1 or name.find("nav_light") != -1 or emit_e > 0.5:
		emit_col = opts.get("glow", emit_col) if name.find("_engine") != -1 else emit_col
		# Blender exported emission strength 30, which blooms into a featureless
		# white blob; 3.5 still reads as hot without eating the nozzle geometry
		var trim_e: float = clampf(emit_e, 2.0, 3.5)
		return _hull_material(albedo, metal, rough, emit_col, trim_e, albedo_tex, opts, true)
	return _hull_material(albedo, metal, rough, emit_col, emit_e, albedo_tex, opts, false)

static func _hull_material(albedo: Color, metal: float, rough: float,
		emit_col: Color, emit_e: float, albedo_tex: Texture2D,
		opts: Dictionary, is_trim: bool) -> ShaderMaterial:
	var plate: float = opts.get("plate_scale", 2.6)
	var wear: float = opts.get("wear", 0.45)
	var grime: float = opts.get("grime", 0.40)
	var stripe: Color = opts.get("stripe", Color(0.95, 0.55, 0.10))
	var stripe_amt: float = 0.0 if is_trim or bool(opts.get("authored", false)) else float(opts.get("stripe_amount", 0.0))
	var rim: Color = opts.get("rim", Color(0.32, 0.46, 0.80))
	var rim_s: float = 0.12 if bool(opts.get("authored", false)) else float(opts.get("rim_strength", 1.0))
	var fade_a: float = opts.get("detail_fade_start", 90.0)
	var fade_b: float = opts.get("detail_fade_end", 320.0)
	var tex_key := "none" if albedo_tex == null else (
		albedo_tex.resource_path if albedo_tex.resource_path != "" else str(albedo_tex.get_instance_id()))
	var key := "%s|%.2f|%.2f|%s|%.1f|%s|%.2f|%.2f|%.2f|%s|%.2f|%s|%.2f|%.0f|%.0f|%d" % [
		albedo.to_html(), metal, rough, emit_col.to_html(), emit_e,
		tex_key, plate, wear, grime, stripe.to_html(), stripe_amt, rim.to_html(), rim_s,
		fade_a, fade_b, 1 if is_trim else 0]
	key += "|authored=" + str(bool(opts.get("authored", false)))
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load(HULL_SHADER)
	m.set_shader_parameter("base_color", albedo)
	m.set_shader_parameter("use_albedo_tex", albedo_tex != null)
	if albedo_tex:
		m.set_shader_parameter("albedo_tex", albedo_tex)
	m.set_shader_parameter("metallic_amt", metal)
	m.set_shader_parameter("roughness_amt", rough)
	m.set_shader_parameter("emission_color", emit_col)
	m.set_shader_parameter("emission_energy", emit_e)
	m.set_shader_parameter("plate_scale", plate * (0.4 if is_trim else 1.0))
	m.set_shader_parameter("panel_detail", 0.0 if bool(opts.get("authored", false)) else 1.0)
	m.set_shader_parameter("seam_depth", 0.15 if is_trim else 0.55)
	m.set_shader_parameter("plate_variation", 0.10 if is_trim else 0.35)
	m.set_shader_parameter("wear", 0.0 if is_trim else wear)
	m.set_shader_parameter("grime", 0.0 if is_trim else grime)
	m.set_shader_parameter("bolts", 0.0 if is_trim else float(opts.get("bolts", 0.6)))
	m.set_shader_parameter("stripe_color", stripe)
	m.set_shader_parameter("stripe_amount", stripe_amt)
	m.set_shader_parameter("rim_color", rim)
	m.set_shader_parameter("rim_strength", rim_s)
	m.set_shader_parameter("detail_fade_start", fade_a)
	m.set_shader_parameter("detail_fade_end", fade_b)
	m.set_shader_parameter("damage", 0.0)
	_cache[key] = m
	return m

static func _glass_material(src: BaseMaterial3D, opts: Dictionary) -> ShaderMaterial:
	var tint: Color = opts.get("glass_tint", Color(0.10, 0.16, 0.22))
	var tex: Texture2D = src.albedo_texture
	var tex_key := "none" if tex == null else (
		tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id()))
	var key := "glass|%s|%s" % [tint.to_html(), tex_key]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load(GLASS_SHADER)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("use_albedo_tex", tex != null)
	if tex:
		m.set_shader_parameter("albedo_tex", tex)
	m.render_priority = 1
	_cache[key] = m
	return m

## Push a 0..1 battle-damage value onto every hull surface of a ship. Shader
## materials are shared, so this duplicates lazily the first time a given ship
## actually takes damage — pristine fleets keep sharing one material each.
static func set_damage(root: Node, amount: float) -> void:
	for node in root.find_children("*", "MeshInstance3D", true):
		var mi := node as MeshInstance3D
		for s in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(s)
			if m is ShaderMaterial and (m as ShaderMaterial).shader \
					and (m as ShaderMaterial).shader.resource_path == HULL_SHADER:
				var sm := m as ShaderMaterial
				if not sm.has_meta("owned"):
					sm = sm.duplicate() as ShaderMaterial
					sm.set_meta("owned", true)
					mi.set_surface_override_material(s, sm)
				sm.set_shader_parameter("damage", amount)
