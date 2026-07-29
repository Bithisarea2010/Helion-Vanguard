# Helion Vanguard — hull detail + ambient-occlusion pass (Blender 5.x, headless)
#
#   Blender --background --python blender_src/detail_pass.py -- <out_dir> [ship ...]
#
# Takes the shipped GLBs, adds a deterministic greeble layer (vents, heat-sink
# fins, conduit runs, sensor blisters, hardpoint blocks) welded to the existing
# hull surface, then bakes per-vertex ambient occlusion and re-exports.
#
# WHY VERTEX AO. The ship meshes carry no UVs, so there is nowhere to put a
# baked texture without unwrapping every asset. Vertex AO needs no UVs at all,
# survives GLB export as COLOR_0, costs one extra vertex attribute, and supplies
# exactly the thing a procedural shader cannot invent: real contact darkening in
# the crevices between parts. Combined with `shaders/hull.gdshader` it does most
# of the work of a baked texture set for a fraction of the pipeline.
#
# AO is computed with a BVH raycast rather than a Cycles bake: deterministic,
# no render settings to fight in headless mode, and ~2 s for an 18k-triangle
# ship.

import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

# ------------------------------------------------------------------ arguments
# Usage: -- <out_dir> [--src=<dir>] [ship ...]
#
# The pass is NOT idempotent: greebling an already-greebled mesh roughly doubles
# its triangle count again. Always read from pristine sources — `--src` defaults
# to assets/models_original, which is exactly what those copies are for.
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "/tmp/hv_models"
SRC_OVERRIDE = None
ONLY = set()
for _a in argv[1:]:
    if _a.startswith("--src="):
        SRC_OVERRIDE = _a.split("=", 1)[1]
    else:
        ONLY.add(_a)

SHIPS = [
    # name,             greebles, fins, conduits, blisters, ao_strength
    ("ship_vanguard",   150, 10, 7, 6, 1.0),
    ("ship_wasp",        95,  6, 5, 4, 1.0),
    ("ship_hammer",     185, 14, 9, 8, 1.0),
    ("ship_raptor",     120,  8, 6, 5, 1.0),
    # Enemy fighters are budgeted lower than the player's ship on purpose: up to
    # ~14 of them are alive at once, so their triangle count multiplies while the
    # hero ship's does not. Detail goes where it is actually looked at.
    ("enemy_razor",      34,  3, 2, 2, 1.0),
    ("enemy_jackal",     42,  4, 3, 2, 1.0),
    ("enemy_mauler",     55,  5, 3, 3, 1.0),
    ("enemy_widow",      20,  2, 1, 1, 1.0),
    ("capital_kraken",  260, 18, 14, 12, 1.0),
    ("capital_carrier", 300, 20, 16, 14, 1.0),
    ("base_bastion",    340, 22, 18, 16, 1.0),
    ("turret",           26,  2, 2, 2, 1.0),
]

AO_RAYS = 24
AO_DIST_FRAC = 0.07       # ray length as a fraction of the model's longest axis
AO_STRENGTH = 0.72        # how much full occlusion darkens a corner


def log(msg):
    print("[detail] %s" % msg, flush=True)


def reset_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for pool in (bpy.data.meshes, bpy.data.materials, bpy.data.images,
                 bpy.data.lights, bpy.data.cameras, bpy.data.collections):
        for x in list(pool):
            if x.users == 0:
                try:
                    pool.remove(x)
                except Exception:
                    pass


def import_glb(path):
    """Import and return every mesh object, hierarchy and names INTACT.

    Joining would be simpler, but capitals and the turret wire their gameplay to
    child object names (`SUB_shield`, `MOUNT_3`, `TurretYoke`) — merging them
    would silently delete every subsystem, hardpoint and articulated barrel in
    the game. Nothing here applies transforms either, for the same reason:
    greebles are built in each object's own local space, which is exactly the
    space the shader's procedural detail also runs in.
    """
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


# ---------------------------------------------------------------- slot lookup
def slot_index(obj, *needles):
    """First material slot whose name contains any needle (case-insensitive)."""
    for i, s in enumerate(obj.data.materials):
        if s is None:
            continue
        n = s.name.lower()
        for needle in needles:
            if needle in n:
                return i
    return 0


# ------------------------------------------------------------------- greebles
def surface_samples(obj, count, rng, avoid_axis_frac=0.55):
    """Area-weighted face samples, skipping faces that face mostly fore/aft.

    Nose and engine faces are left clean: greebles there fight the silhouette
    and sit exactly where the muzzle and thruster sockets are anchored.
    """
    me = obj.data
    me.calc_loop_triangles()
    tris = []
    total = 0.0
    for t in me.loop_triangles:
        n = t.normal
        if abs(n.y) > avoid_axis_frac:      # +/-Y is fore/aft in Blender space
            continue
        a = t.area
        if a <= 1e-7:
            continue
        total += a
        tris.append((total, t))
    if not tris or total <= 0.0:
        return []
    out = []
    for _ in range(count):
        r = rng.random() * total
        lo, hi = 0, len(tris) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if tris[mid][0] < r:
                lo = mid + 1
            else:
                hi = mid
        t = tris[lo][1]
        v = [me.vertices[i].co for i in t.vertices]
        # uniform point in the triangle
        u1, u2 = rng.random(), rng.random()
        if u1 + u2 > 1.0:
            u1, u2 = 1.0 - u1, 1.0 - u2
        p = v[0] + (v[1] - v[0]) * u1 + (v[2] - v[0]) * u2
        out.append((p, t.normal.copy()))
    return out


def frame_from_normal(n):
    """Orthonormal basis with +Z along n."""
    n = n.normalized()
    up = Vector((0, 0, 1)) if abs(n.z) < 0.95 else Vector((1, 0, 0))
    x = up.cross(n).normalized()
    y = n.cross(x)
    return Matrix((x, y, n)).transposed()


def add_greebles(bm, obj, samples, rng, scale, slots):
    """Small blocks, vents and raised panels pressed onto the hull surface."""
    for (p, n) in samples:
        basis = frame_from_normal(n)
        kind = rng.random()
        if kind < 0.42:                       # flat access panel
            sx, sy, sz = rng.uniform(0.5, 1.6), rng.uniform(0.5, 2.2), rng.uniform(0.06, 0.16)
            slot = slots["panel"] if rng.random() < 0.7 else slots["dark"]
        elif kind < 0.68:                     # raised equipment block
            sx, sy, sz = rng.uniform(0.3, 0.8), rng.uniform(0.3, 0.9), rng.uniform(0.2, 0.5)
            slot = slots["dark"]
        elif kind < 0.86:                     # long thin rib
            sx, sy, sz = rng.uniform(0.10, 0.22), rng.uniform(1.2, 3.4), rng.uniform(0.10, 0.22)
            slot = slots["panel"]
        else:                                 # bright marker plate
            sx, sy, sz = rng.uniform(0.25, 0.6), rng.uniform(0.25, 0.6), rng.uniform(0.05, 0.10)
            slot = slots["white"]
        sx *= scale; sy *= scale; sz *= scale
        # sink the block slightly so it never floats off the hull
        origin = p + n.normalized() * (sz * 0.45)
        yaw = rng.uniform(0, math.tau)
        m = Matrix.Translation(origin) @ basis.to_4x4() @ Matrix.Rotation(yaw, 4, 'Z')
        _box(bm, m, Vector((sx, sy, sz)), slot)


def add_fins(bm, obj, samples, rng, scale, slots):
    """Radiator fin stacks: several parallel thin plates, a strong read at
    silhouette distance where individual greebles vanish."""
    for (p, n) in samples:
        basis = frame_from_normal(n)
        count = rng.randint(3, 6)
        gap = rng.uniform(0.22, 0.40) * scale
        h = rng.uniform(0.5, 1.3) * scale
        l = rng.uniform(1.4, 3.2) * scale
        yaw = rng.uniform(0, math.tau)
        for i in range(count):
            off = (i - (count - 1) * 0.5) * gap
            local = Matrix.Translation(Vector((off, 0.0, h * 0.5)))
            m = Matrix.Translation(p) @ basis.to_4x4() @ Matrix.Rotation(yaw, 4, 'Z') @ local
            _box(bm, m, Vector((0.06 * scale, l, h)), slots["panel"])


def add_conduits(bm, obj, samples, rng, scale, slots):
    """Cable/coolant runs: a chain of segments walking across the hull."""
    for (p, n) in samples:
        basis = frame_from_normal(n)
        yaw = rng.uniform(0, math.tau)
        seg_len = rng.uniform(1.6, 3.0) * scale
        rad = rng.uniform(0.06, 0.14) * scale
        cur = p.copy()
        d = (basis @ Vector((math.cos(yaw), math.sin(yaw), 0.0))).normalized()
        for i in range(rng.randint(3, 6)):
            mid = cur + d * (seg_len * 0.5) + n.normalized() * rad
            m = Matrix.Translation(mid) @ _align_to(d).to_4x4()
            _cyl(bm, m, rad, seg_len, slots["dark"])
            cur = cur + d * seg_len
            # gentle random walk so runs curve along the hull
            d = (d + basis @ Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 0.0))).normalized()


def add_blisters(bm, obj, samples, rng, scale, slots):
    """Sensor domes and antenna masts."""
    for (p, n) in samples:
        nn = n.normalized()
        if rng.random() < 0.6:
            r = rng.uniform(0.22, 0.55) * scale
            _sphere(bm, Matrix.Translation(p + nn * r * 0.35), r, slots["white"])
        else:
            h = rng.uniform(1.0, 2.6) * scale
            m = Matrix.Translation(p + nn * h * 0.5) @ _align_to(nn).to_4x4()
            _cyl(bm, m, 0.05 * scale, h, slots["dark"])


def _align_to(d):
    """Rotation taking +Z to d."""
    d = d.normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))
    x = up.cross(d).normalized()
    y = d.cross(x)
    return Matrix((x, y, d)).transposed()


def _tag(faces, slot):
    for f in faces:
        f.material_index = slot
        f.smooth = False


def _box(bm, matrix, size, slot):
    res = bmesh.ops.create_cube(bm, size=1.0,
                                matrix=matrix @ Matrix.Diagonal(size.to_4d()))
    _tag({f for v in res["verts"] for f in v.link_faces}, slot)


def _cyl(bm, matrix, radius, depth, slot):
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=6,
                                radius1=radius, radius2=radius, depth=depth,
                                matrix=matrix)
    _tag({f for v in res["verts"] for f in v.link_faces}, slot)


def _sphere(bm, matrix, radius, slot):
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius,
                                     matrix=matrix)
    _tag({f for v in res["verts"] for f in v.link_faces}, slot)


# ------------------------------------------------------------------------ AO
def bake_vertex_ao(obj, strength=1.0):
    """Hemisphere raycast AO written to a CORNER byte-colour layer.

    Corner (rather than vertex) domain means a sharp edge between a greeble and
    the hull gets two different AO values instead of one averaged mush.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bvh = BVHTree.FromBMesh(bm)
    dims = obj.dimensions
    diag = max(dims.x, dims.y, dims.z)
    ray_len = max(diag * AO_DIST_FRAC, 0.05)

    # Deterministic COSINE-weighted hemisphere directions (golden-angle spiral).
    # Cosine weighting matters: a uniform hemisphere over-samples grazing rays,
    # which almost always hit the surface itself, and every vertex comes back
    # ~50% occluded — the first bake turned every hull matte black.
    dirs = []
    ga = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(AO_RAYS):
        z = math.sqrt((i + 0.5) / AO_RAYS)     # cosine distribution about +Z
        r = math.sqrt(max(0.0, 1.0 - z * z))
        a = ga * i
        dirs.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))

    cache = {}
    ao_layer = bm.loops.layers.float_color.get("AO") or \
        bm.loops.layers.float_color.new("AO")
    for face in bm.faces:
        for loop in face.loops:
            v = loop.vert
            n = loop.calc_normal() if face.smooth else face.normal
            if n.length_squared < 1e-9:
                n = v.normal
            key = (v.index, round(n.x, 2), round(n.y, 2), round(n.z, 2))
            if key in cache:
                occ = cache[key]
            else:
                basis = frame_from_normal(n)
                origin = v.co + n.normalized() * (ray_len * 0.012)
                hits = 0
                for d in dirs:
                    wd = basis @ d
                    hit = bvh.ray_cast(origin, wd, ray_len)
                    if hit[0] is not None:
                        hits += 1
                occ = hits / float(AO_RAYS)
                cache[key] = occ
            ao = 1.0 - occ * strength * AO_STRENGTH
            ao = max(0.22, min(1.0, ao))
            loop[ao_layer] = (ao, ao, ao, 1.0)
    bm.to_mesh(me)
    bm.free()
    me.update()
    # glTF exports the ACTIVE colour attribute
    if "AO" in me.color_attributes:
        me.color_attributes.active_color_index = me.color_attributes.find("AO")
        me.color_attributes.render_color_index = me.color_attributes.find("AO")


# ------------------------------------------------------------------ pipeline
def detail_object(obj, budget, rng, ao_strength):
    """Greeble + bevel + AO a single mesh object in place."""
    obj.data.calc_loop_triangles()
    before = len(obj.data.loop_triangles)
    dims = obj.dimensions
    span = max(dims.x, dims.y, dims.z)
    if span < 1e-4 or before < 12:
        return before, before
    scale = span * 0.014                       # detail size follows part size
    slots = {
        "panel": slot_index(obj, "panel", "grey"),
        "dark": slot_index(obj, "gunmetal", "dark"),
        "white": slot_index(obj, "_acc", "acc", "white"),
        "hull": slot_index(obj, "_hull"),
    }
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    add_greebles(bm, obj, surface_samples(obj, budget[0], rng), rng, scale, slots)
    add_fins(bm, obj, surface_samples(obj, budget[1], rng), rng, scale, slots)
    add_conduits(bm, obj, surface_samples(obj, budget[2], rng), rng, scale, slots)
    add_blisters(bm, obj, surface_samples(obj, budget[3], rng), rng, scale, slots)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()

    # a light bevel catches a specular highlight on every new edge, which is
    # what stops greebles reading as untextured cardboard
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bev = obj.modifiers.new("GreebleBevel", 'BEVEL')
    bev.width = scale * 0.06
    bev.segments = 1
    bev.limit_method = 'ANGLE'
    bev.angle_limit = math.radians(50)
    bpy.ops.object.modifier_apply(modifier=bev.name)

    obj.data.calc_loop_triangles()
    after = len(obj.data.loop_triangles)
    bake_vertex_ao(obj, ao_strength)
    return before, after


def process(name, n_greeble, n_fin, n_conduit, n_blister, ao_strength, src_dir):
    src = os.path.join(src_dir, name + ".glb")
    if not os.path.exists(src):
        log("skip %s (missing)" % name)
        return
    reset_scene()
    meshes = import_glb(src)
    if not meshes:
        log("skip %s (no mesh)" % name)
        return
    rng = random.Random(hash(name) & 0xffffffff)
    # share the budget across parts by surface area so a big hull section gets
    # more detail than a small strut
    areas = []
    for o in meshes:
        d = o.dimensions
        areas.append(max(d.x * d.y + d.y * d.z + d.x * d.z, 1e-6))
    total_area = sum(areas)
    total_before = total_after = 0
    for o, a in zip(meshes, areas):
        share = a / total_area
        budget = (max(2, int(n_greeble * share)), max(0, int(n_fin * share)),
                  max(0, int(n_conduit * share)), max(0, int(n_blister * share)))
        b, af = detail_object(o, budget, rng, ao_strength)
        total_before += b
        total_after += af

    out = os.path.join(OUT_DIR, name + ".glb")
    for o in bpy.context.scene.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    kwargs = dict(filepath=out, export_format='GLB', use_selection=True,
                  export_apply=True, export_yup=True, export_animations=False,
                  export_skins=False, export_morph=False)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(**kwargs)
    log("%-18s parts %2d  tris %5d -> %5d  (+%d%%)"
        % (name, len(meshes), total_before, total_after,
           int((total_after / max(total_before, 1) - 1) * 100)))


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src_dir = SRC_OVERRIDE or os.path.join(root, "assets", "models_original")
    if not os.path.isdir(src_dir):
        src_dir = os.path.join(root, "assets", "models")
    os.makedirs(OUT_DIR, exist_ok=True)
    log("source %s" % src_dir)
    for entry in SHIPS:
        if ONLY and entry[0] not in ONLY:
            continue
        try:
            process(entry[0], entry[1], entry[2], entry[3], entry[4], entry[5], src_dir)
        except Exception as exc:
            import traceback
            log("FAILED %s: %s" % (entry[0], exc))
            traceback.print_exc()
    log("done")


main()
