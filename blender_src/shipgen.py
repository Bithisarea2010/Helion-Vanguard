# Helion Vanguard — procedural hard-surface ship factory (Blender 4.x/5.x)
# All geometry original. Ships face +Y in Blender => -Z forward in Godot after GLB export.
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

EXPORT_DIR = None  # set by caller

# ----------------------------------------------------------------- scene mgmt
def reset_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for pool in (bpy.data.meshes, bpy.data.materials, bpy.data.images,
                 bpy.data.lights, bpy.data.cameras, bpy.data.textures):
        for x in list(pool):
            if x.users == 0:
                try: pool.remove(x)
                except Exception: pass

def new_obj(name, mesh):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj

# ----------------------------------------------------------------- materials
def mat(name, color, metallic=0.85, rough=0.5, emit=None, emit_str=0.0, alpha=1.0, coat=0.0):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = emit_str
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.blend_method = 'BLEND'
    if coat > 0.0:
        try:
            b.inputs["Coat Weight"].default_value = coat
            b.inputs["Coat Roughness"].default_value = 0.12
        except KeyError:
            pass
    return m

def palette(ship, paint, glow, accent=(0.92, 0.93, 0.95)):
    return {
        "hull":   mat(f"{ship}_hull", paint, 0.75, 0.38, coat=0.4),
        "hull2":  mat(f"{ship}_hull2", tuple(c * 0.45 for c in paint), 0.8, 0.5),
        "white":  mat(f"{ship}_acc", accent, 0.7, 0.38),
        "panel":  mat("panel_grey", (0.42, 0.44, 0.47), 0.85, 0.55),
        "dark":   mat("gunmetal", (0.08, 0.085, 0.1), 0.9, 0.45),
        "glass":  mat("canopy_glass", (0.02, 0.05, 0.08), 0.4, 0.08),
        "engine": mat(f"{ship}_engine", (0.02, 0.02, 0.02), 0.2, 0.4, glow, 30.0),
        "light":  mat("nav_light", (1.0, 1.0, 1.0), 0.0, 0.3, (1.0, 1.0, 1.0), 12.0),
    }

# ----------------------------------------------------------------- geometry
def hull_loft(name, sections, material, spine=0.0):
    """sections: list of dicts {y,w,zb,zt,tf,bf}; 6-point rounded-hex profile."""
    bm = bmesh.new()
    rings = []
    for s in sections:
        w = max(s["w"], 0.02)
        zb, zt = s["zb"], s["zt"]
        tf = s.get("tf", 0.5); bf = s.get("bf", 0.62)
        zm = (zb + zt) * 0.5
        pts = [(-w * tf, zt), (w * tf, zt), (w, zm), (w * bf, zb),
               (-w * bf, zb), (-w, zm)]
        if spine > 0:
            pts.insert(1, (0.0, zt + spine))
        ring = [bm.verts.new((x, s["y"], z)) for (x, z) in pts]
        rings.append(ring)
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            bm.faces.new([a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]])
    try:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    except ValueError:
        pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    me.materials.append(material)
    return new_obj(name, me)

def box(name, size, pos, material, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    me.materials.append(material)
    o = new_obj(name, me)
    o.scale = size; o.location = pos
    o.rotation_euler = tuple(math.radians(a) for a in rot)
    return o

def cyl(name, r1, r2, depth, pos, material, axis='Y', verts=16, rot_extra=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts,
                          radius1=r1, radius2=r2, depth=depth)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    me.materials.append(material)
    o = new_obj(name, me)
    if axis == 'Y': o.rotation_euler = (math.radians(-90), 0, 0)
    elif axis == 'X': o.rotation_euler = (0, math.radians(90), 0)
    if rot_extra: o.rotation_euler.rotate_axis('Z', math.radians(rot_extra))
    o.location = pos
    return o

def sphere(name, r, pos, material, scale=(1, 1, 1), sub=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    me.materials.append(material)
    o = new_obj(name, me)
    o.location = pos; o.scale = scale
    return o

def wing(name, root_pos, span, root_chord, tip_chord, sweep, dihedral,
         thick, material, tip_thick_frac=0.4, mirrored=False):
    """Trapezoid wing extending +X from root (or -X if mirrored).
    Positive dihedral tilts the tip DOWN (anhedral); negative tilts up."""
    bm = bmesh.new()
    t2, tt = thick * 0.5, thick * 0.5 * tip_thick_frac
    sx = -1.0 if mirrored else 1.0
    p = [
        (0, 0, -t2), (0, -root_chord, -t2),
        (sx * span, -sweep - tip_chord, -tt), (sx * span, -sweep, -tt),
        (0, 0, t2), (0, -root_chord, t2),
        (sx * span, -sweep - tip_chord, tt), (sx * span, -sweep, tt),
    ]
    v = [bm.verts.new(q) for q in p]
    for idx in [(0, 1, 2, 3), (7, 6, 5, 4), (0, 3, 7, 4), (2, 1, 5, 6),
                (1, 0, 4, 5), (3, 2, 6, 7)]:
        bm.faces.new([v[i] for i in idx])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    me.materials.append(material)
    o = new_obj(name, me)
    o.location = root_pos
    o.rotation_euler = (0, math.radians(dihedral) * sx, 0)
    return o

def wing_pair(name, root_pos, span, root_chord, tip_chord, sweep, dihedral,
              thick, material, tip_thick_frac=0.4):
    """Symmetric pair; root_pos is the +X side root. Returns [right, left]."""
    r = wing(name + "_R", root_pos, span, root_chord, tip_chord, sweep,
             dihedral, thick, material, tip_thick_frac)
    lp = (-root_pos[0], root_pos[1], root_pos[2])
    l = wing(name + "_L", lp, span, root_chord, tip_chord, sweep,
             dihedral, thick, material, tip_thick_frac, mirrored=True)
    return [r, l]

def wing_tip(root_pos, span, sweep, tip_chord, dihedral, mirrored=False, frac=0.97):
    """World position of the wing tip mid-chord for pod placement."""
    sx = -1.0 if mirrored else 1.0
    th = math.radians(dihedral) * sx
    x_local = sx * span * frac
    tx = x_local * math.cos(th)
    tz = -x_local * math.sin(th)
    rx = -root_pos[0] if mirrored else root_pos[0]
    return (rx + tx, root_pos[1] - (sweep + tip_chord * 0.5) * frac, root_pos[2] + tz)

def greebles(parent_bounds, count, mats, seed=7, z_top=None, y_range=None):
    """Scatter flat detail panels on the top deck."""
    random.seed(seed)
    out = []
    (x0, x1), (y0, y1) = parent_bounds
    if y_range: y0, y1 = y_range
    for i in range(count):
        w = random.uniform(0.12, 0.55); l = random.uniform(0.3, 1.4)
        h = random.uniform(0.04, 0.16)
        x = random.uniform(x0, x1); y = random.uniform(y0, y1)
        m = random.choice(mats)
        out.append(box(f"grb{i}", (w, l, h), (x, y, z_top), m))
    return out

def engine_nozzle(name, pos, r, pal, depth=1.2):
    parts = []
    parts.append(cyl(name + "_shroud", r, r * 0.82, depth, pos, pal["dark"]))
    glow_pos = (pos[0], pos[1] - depth * 0.42, pos[2])
    parts.append(cyl(name + "_glow", r * 0.72, r * 0.6, depth * 0.25, glow_pos, pal["engine"]))
    return parts

def nav_lights(positions, pal):
    return [sphere(f"nav{i}", 0.07, p, pal["light"], sub=1)
            for i, p in enumerate(positions)]

# ------------------------------------------------------- detail kit (v2)
def panel_lines(pal, x_range, y_range, z_top, count=10, seed=3):
    """Thin dark seam strips across the top deck — reads as panel lines."""
    random.seed(seed)
    out = []
    for i in range(count):
        y = random.uniform(*y_range)
        w = random.uniform(0.5, 1.0) * (x_range[1] - x_range[0])
        x = random.uniform(x_range[0], x_range[1] - w * 0.5)
        if random.random() < 0.5:
            out.append(box(f"pl{i}", (w, 0.04, 0.02), (x * 0.4, y, z_top), pal["dark"]))
        else:
            l = random.uniform(0.8, 2.4)
            out.append(box(f"pl{i}", (0.04, l, 0.02), (x, y, z_top), pal["dark"]))
    return out

def aerials(pal, positions):
    """Thin antenna whiskers."""
    out = []
    for i, (p, h) in enumerate(positions):
        out.append(cyl(f"ant{i}", 0.015, 0.008, h, p, pal["dark"], axis='Z'))
    return out

def rcs_block(pal, pos, s=0.1):
    """Reaction-control thruster cluster: small block with dark nozzle holes."""
    out = [box("rcs", (s * 2.2, s * 2.2, s * 1.2), pos, pal["panel"])]
    for dx, dz in ((1, 0), (-1, 0), (0, 1)):
        out.append(box("rcsn", (s * 0.7, s * 0.7, s * 0.7),
                        (pos[0] + dx * s * 0.9, pos[1], pos[2] + dz * s * 0.75), pal["dark"]))
    return out

def engine_nozzle_v2(name, pos, r, pal, depth=1.4):
    """Detailed nozzle: shroud, petals, inner cone, hot glow ring + core."""
    parts = []
    parts.append(cyl(name + "_shroud", r * 1.08, r * 0.9, depth, pos, pal["dark"], verts=20))
    # petal fins around the rim
    for k in range(8):
        a = math.tau * k / 8.0
        px = pos[0] + math.cos(a) * r * 0.98
        pz = pos[2] + math.sin(a) * r * 0.98
        p = box(name + f"_pt{k}", (r * 0.22, depth * 0.55, r * 0.1),
                (px, pos[1] - depth * 0.2, pz), pal["panel"])
        p.rotation_euler = (0, a, 0)
        parts.append(p)
    parts.append(cyl(name + "_inner", r * 0.85, r * 0.55, depth * 0.7,
                     (pos[0], pos[1] - depth * 0.1, pos[2]), pal["hull2"], verts=16))
    parts.append(cyl(name + "_ring", r * 0.8, r * 0.78, depth * 0.12,
                     (pos[0], pos[1] - depth * 0.42, pos[2]), pal["engine"], verts=16))
    parts.append(cyl(name + "_core", r * 0.5, r * 0.3, depth * 0.3,
                     (pos[0], pos[1] - depth * 0.35, pos[2]), pal["engine"], verts=12))
    return parts

def leading_edge(pal, root_pos, span, sweep, dihedral, thick, mirrored=False):
    """Bright wing leading-edge strip."""
    sx = -1.0 if mirrored else 1.0
    th = math.radians(dihedral) * sx
    rx = -root_pos[0] if mirrored else root_pos[0]
    mid_x = rx + sx * span * 0.5 * math.cos(th)
    mid_z = root_pos[2] - sx * span * 0.5 * math.sin(th) * sx
    b = box("ledge", (span * 0.96, 0.1, thick * 1.3),
            (mid_x, root_pos[1] - sweep * 0.5 + 0.08, root_pos[2] - span * 0.5 * math.sin(th)),
            pal["white"])
    b.rotation_euler = (0, th, math.atan2(-sweep, span * sx))
    return b

# ----------------------------------------------------------- finishing
def finish(objs, name, bevel=0.03, smooth_angle=38, merge=True):
    """Join into one object, add bevel, auto-smooth."""
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if merge and len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    bev = obj.modifiers.new("Bevel", 'BEVEL')
    bev.width = bevel; bev.segments = 2
    bev.limit_method = 'ANGLE'; bev.angle_limit = math.radians(42)
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle))
    except Exception:
        try: bpy.ops.object.shade_smooth()
        except Exception: pass
    return obj

def export_glb(objs, filename):
    import os
    path = os.path.join(EXPORT_DIR, filename)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True,
        export_apply=True, export_yup=True, export_animations=False,
        export_skins=False, export_morph=False)
    return path

def mirror_x(obj, name=None):
    """Duplicate object mirrored across X (linked new mesh)."""
    me = obj.data.copy()
    o = new_obj(name or (obj.name + "_m"), me)
    o.location = (-obj.location.x, obj.location.y, obj.location.z)
    o.rotation_euler = (obj.rotation_euler.x, -obj.rotation_euler.y, -obj.rotation_euler.z)
    o.scale = (-obj.scale.x, obj.scale.y, obj.scale.z)
    return o

print("shipgen loaded")
