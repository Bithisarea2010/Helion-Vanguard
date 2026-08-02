# Helion Vanguard — asteroids (PolyHaven CC0 rock texture) + cockpit interior.
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

def soft_reset():
    """Remove objects only — keep downloaded materials/images alive."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

def build_asteroid(idx, seed):
    random.seed(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
    # vertex jitter for silhouette variety
    for v in bm.verts:
        v.co *= 1.0 + random.uniform(-0.06, 0.06)
    # random squash
    sx, sy, sz = [random.uniform(0.7, 1.25) for _ in range(3)]
    bmesh.ops.scale(bm, verts=bm.verts, vec=(sx, sy, sz))
    me = bpy.data.meshes.new(f"asteroid{idx}")
    bm.to_mesh(me); bm.free()
    obj = bpy.data.objects.new(f"Asteroid{idx}", me)
    bpy.context.scene.collection.objects.link(obj)
    # displacement stack
    t1 = bpy.data.textures.new(f"ast_clouds{idx}", 'CLOUDS')
    t1.noise_scale = random.uniform(0.6, 1.4)
    t1.noise_depth = 3
    d1 = obj.modifiers.new("disp1", 'DISPLACE')
    d1.texture = t1; d1.strength = random.uniform(0.28, 0.45)
    t2 = bpy.data.textures.new(f"ast_voro{idx}", 'VORONOI')
    t2.noise_scale = random.uniform(0.35, 0.8)
    d2 = obj.modifiers.new("disp2", 'DISPLACE')
    d2.texture = t2; d2.strength = random.uniform(0.15, 0.3)
    # apply modifiers so UVs match final shape
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    # rock material + UV
    rock = bpy.data.materials.get("asteroid_rock") or bpy.data.materials.get("aerial_rocks_02")
    if rock:
        obj.data.materials.append(rock)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.shade_smooth()
    return obj

def build_cockpit():
    """Interior around pilot eye at origin, nose +Y. Exported nose-forward for Godot."""
    soft_reset()
    dk = mat("cp_dark", (0.05, 0.055, 0.065), 0.6, 0.6)
    pn = mat("cp_panel", (0.12, 0.13, 0.15), 0.7, 0.5)
    ac = mat("cp_accent", (0.8, 0.35, 0.06), 0.6, 0.45)
    sc = mat("cp_screen", (0.01, 0.03, 0.04), 0.2, 0.2, (0.15, 0.7, 0.8), 1.6)
    scr = mat("cp_screen_red", (0.04, 0.01, 0.01), 0.2, 0.2, (0.9, 0.25, 0.1), 1.2)
    fr = mat("cp_frame", (0.09, 0.09, 0.1), 0.8, 0.4)
    parts = []
    # main dash
    parts.append(box("dash", (1.5, 0.5, 0.34), (0, 0.72, -0.42), pn, rot=(-12, 0, 0)))
    parts.append(box("dashtop", (1.3, 0.28, 0.1), (0, 0.66, -0.22), dk, rot=(-25, 0, 0)))
    # instrument screens
    parts.append(box("mfd_c", (0.42, 0.02, 0.3), (0, 0.62, -0.35), sc, rot=(-18, 0, 0)))
    parts.append(box("mfd_l", (0.3, 0.02, 0.24), (-0.44, 0.63, -0.37), sc, rot=(-18, 0, 18)))
    parts.append(box("mfd_r", (0.3, 0.02, 0.24), (0.44, 0.63, -0.37), scr, rot=(-18, 0, -18)))
    # coaming rim
    parts.append(box("coamL", (0.09, 1.5, 0.1), (-0.72, 0.1, -0.28), dk, rot=(0, 0, 6)))
    parts.append(box("coamR", (0.09, 1.5, 0.1), (0.72, 0.1, -0.28), dk, rot=(0, 0, -6)))
    parts.append(box("coamF", (1.45, 0.1, 0.1), (0, 0.95, -0.3), dk, rot=(-10, 0, 0)))
    # A-pillars + overhead bow
    parts.append(box("pillL", (0.07, 0.9, 0.08), (-0.68, 0.75, 0.22), fr, rot=(38, 0, 14)))
    parts.append(box("pillR", (0.07, 0.9, 0.08), (0.68, 0.75, 0.22), fr, rot=(38, 0, -14)))
    parts.append(box("bow", (1.5, 0.09, 0.08), (0, 0.28, 0.58), fr, rot=(-14, 0, 0)))
    parts.append(box("bow2", (1.44, 0.09, 0.08), (0, -0.55, 0.62), fr, rot=(6, 0, 0)))
    # side consoles
    parts.append(box("conL", (0.34, 1.1, 0.16), (-0.58, -0.1, -0.52), pn, rot=(0, -7, 4)))
    parts.append(box("conR", (0.34, 1.1, 0.16), (0.58, -0.1, -0.52), pn, rot=(0, 7, -4)))
    parts.append(box("conLs", (0.26, 0.4, 0.03), (-0.58, 0.15, -0.43), sc, rot=(0, -7, 4)))
    parts.append(box("conRs", (0.26, 0.4, 0.03), (0.58, 0.15, -0.43), scr, rot=(0, 7, -4)))
    # throttle + stick
    parts.append(cyl("stick", 0.035, 0.03, 0.3, (0.0, 0.1, -0.5), dk, axis='Z'))
    parts.append(sphere("stickg", 0.05, (0.0, 0.1, -0.35), ac, sub=1))
    parts.append(box("throt", (0.08, 0.18, 0.1), (-0.56, 0.2, -0.38), ac))
    # floor + nose shell (blocks view downward/forward-outside)
    parts.append(box("floor", (1.5, 2.0, 0.08), (0, 0.0, -0.78), dk))
    parts.append(box("nose", (1.6, 0.7, 0.55), (0, 1.25, -0.55), pn, rot=(-24, 0, 0)))
    # seat behind
    parts.append(box("seatb", (0.6, 0.12, 0.9), (0, -0.85, -0.15), pn, rot=(8, 0, 0)))
    parts.append(box("seath", (0.34, 0.1, 0.3), (0, -0.9, 0.35), dk, rot=(8, 0, 0)))
    return finish(parts, "Cockpit", bevel=0.012, smooth_angle=30)

print("props loaded")
