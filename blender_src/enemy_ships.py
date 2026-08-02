# Helion Vanguard — hostile fleet, capitals, base, turret. Requires shipgen.py.
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

def enemy_palette(ship, glow=(1.0, 0.12, 0.06)):
    return {
        "hull":   mat("en_hull", (0.10, 0.105, 0.12), 0.85, 0.42),
        "hull2":  mat("en_hull2", (0.055, 0.06, 0.07), 0.9, 0.5),
        "white":  mat("en_accent", (0.55, 0.06, 0.05), 0.7, 0.4),
        "panel":  mat("en_panel", (0.2, 0.2, 0.23), 0.85, 0.55),
        "dark":   mat("gunmetal", (0.08, 0.085, 0.1), 0.9, 0.45),
        "glass":  mat("en_glass", (0.06, 0.005, 0.005), 0.4, 0.1),
        "engine": mat("en_engine", (0.02, 0.02, 0.02), 0.2, 0.4, glow, 26.0),
        "light":  mat("en_light", (1.0, 0.1, 0.05), 0.0, 0.3, (1.0, 0.1, 0.05), 14.0),
    }

def shift_mesh(obj, offset):
    obj.data.transform(Matrix.Translation(Vector(offset)))

def mount(name, pos):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.5
    bpy.context.scene.collection.objects.link(e)
    e.location = pos
    return e

# --------------------------------------------------------------- fighters
def build_razor():
    """Dagger interceptor, forward-swept wings, red slits."""
    reset_scene()
    pal = enemy_palette("razor")
    parts = []
    parts.append(hull_loft("hullm", [
        {"y": 6.5, "w": 0.09, "zb": -0.04, "zt": 0.07},
        {"y": 4.2, "w": 0.4, "zb": -0.2, "zt": 0.3, "tf": 0.3},
        {"y": 1.2, "w": 0.8, "zb": -0.38, "zt": 0.55, "tf": 0.4},
        {"y": -1.8, "w": 0.85, "zb": -0.4, "zt": 0.5, "tf": 0.5},
        {"y": -4.6, "w": 0.55, "zb": -0.3, "zt": 0.36, "tf": 0.5},
    ], pal["hull"], spine=0.05))
    parts.append(sphere("canopy", 1.0, (0, 1.5, 0.5), pal["glass"], scale=(0.4, 1.1, 0.3)))
    # forward-swept wings (negative sweep pushes tips toward nose)
    parts += wing_pair("wing", (0.75, -2.6, 0.0), 3.0, 2.0, 0.7, -1.6, -8, 0.12, pal["hull"])
    # red glow slits on wings
    for mir in (False, True):
        tp = wing_tip((0.75, -2.6, 0.0), 3.0, -1.6, 0.7, -8, mir)
        parts.append(box("slit", (0.5, 0.08, 0.06), (tp[0] * 0.75, tp[1] + 0.35, tp[2] * 0.75 + 0.09), pal["light"]))
        parts.append(cyl("gun", 0.05, 0.04, 1.5, (tp[0], tp[1] + 0.9, tp[2]), pal["dark"]))
    # twin fins down
    for sx in (1, -1):
        parts.append(box("fin", (0.06, 1.2, 0.9), (sx * 0.45, -3.9, -0.55), pal["hull2"], rot=(10, sx * 24, 0)))
    parts.append(cyl("epod", 0.5, 0.42, 2.0, (0, -4.9, 0.03), pal["hull2"]))
    parts += engine_nozzle("noz", (0, -6.0, 0.03), 0.42, pal)
    parts += greebles(((-0.5, 0.5), (-3.5, 0.0)), 7, [pal["panel"], pal["hull2"]], seed=41, z_top=0.45)
    return finish(parts, "EnemyRazor", bevel=0.03)

def build_jackal():
    """Mainline fighter: mandible prongs, X wings."""
    reset_scene()
    pal = enemy_palette("jackal")
    parts = []
    parts.append(hull_loft("hullm", [
        {"y": 5.6, "w": 0.35, "zb": -0.18, "zt": 0.22, "tf": 0.4},
        {"y": 3.0, "w": 0.7, "zb": -0.35, "zt": 0.5, "tf": 0.5},
        {"y": 0.0, "w": 1.0, "zb": -0.5, "zt": 0.7, "tf": 0.55},
        {"y": -3.0, "w": 0.95, "zb": -0.45, "zt": 0.6, "tf": 0.6},
        {"y": -5.8, "w": 0.65, "zb": -0.32, "zt": 0.4, "tf": 0.55},
    ], pal["hull"], spine=0.06))
    # mandible prongs
    for sx in (1, -1):
        parts.append(box("prong", (0.22, 3.2, 0.3), (sx * 0.75, 6.2, -0.05), pal["hull2"], rot=(0, 0, sx * 2)))
        parts.append(box("prongtip", (0.16, 0.8, 0.22), (sx * 0.72, 7.9, -0.05), pal["white"]))
        parts.append(cyl("gun", 0.05, 0.04, 1.8, (sx * 0.72, 8.2, -0.05), pal["dark"]))
    parts.append(sphere("canopy", 1.0, (0, 1.6, 0.62), pal["glass"], scale=(0.45, 1.2, 0.34)))
    # X wings
    parts += wing_pair("wingL", (0.9, -2.4, -0.2), 2.9, 2.2, 0.8, 1.7, 22, 0.13, pal["hull"])
    parts += wing_pair("wingU", (0.8, -2.7, 0.35), 2.6, 1.8, 0.7, 1.4, -25, 0.12, pal["hull"])
    for mir in (False, True):
        tp = wing_tip((0.9, -2.4, -0.2), 2.9, 1.7, 0.8, 22, mir)
        parts.append(box("slit", (0.45, 0.1, 0.07), (tp[0] * 0.8, tp[1] + 0.3, tp[2] * 0.8), pal["light"]))
    for sx in (1, -1):
        parts.append(cyl("epod", 0.4, 0.35, 2.0, (sx * 0.5, -5.9, 0.05), pal["hull2"]))
        parts += engine_nozzle("noz", (sx * 0.5, -7.0, 0.05), 0.34, pal, depth=0.8)
    parts += greebles(((-0.7, 0.7), (-4.5, 0.5)), 9, [pal["panel"], pal["hull2"], pal["white"]], seed=43, z_top=0.6)
    return finish(parts, "EnemyJackal", bevel=0.032)

def build_mauler():
    """Bomber: fat beetle hull, side pods, torpedo tubes under belly."""
    reset_scene()
    pal = enemy_palette("mauler", glow=(1.0, 0.25, 0.05))
    parts = []
    parts.append(hull_loft("hullm", [
        {"y": 5.5, "w": 0.6, "zb": -0.4, "zt": 0.5, "tf": 0.55},
        {"y": 3.0, "w": 1.4, "zb": -0.8, "zt": 1.0, "tf": 0.6},
        {"y": 0.0, "w": 1.9, "zb": -1.0, "zt": 1.25, "tf": 0.65},
        {"y": -3.2, "w": 1.7, "zb": -0.9, "zt": 1.05, "tf": 0.7},
        {"y": -6.0, "w": 1.1, "zb": -0.6, "zt": 0.7, "tf": 0.6},
    ], pal["hull"]))
    parts.append(sphere("canopy", 1.0, (0, 3.6, 0.8), pal["glass"], scale=(0.6, 1.1, 0.4)))
    # armored side pods
    for sx in (1, -1):
        parts.append(box("pod", (0.9, 4.6, 1.1), (sx * 2.2, -0.6, 0.0), pal["hull2"]))
        parts.append(box("podacc", (0.95, 1.0, 1.15), (sx * 2.2, 1.4, 0.0), pal["white"]))
        parts += engine_nozzle("noz", (sx * 2.2, -3.2, 0.0), 0.5, pal, depth=1.0)
    # belly torpedo tubes
    for k in range(3):
        parts.append(cyl("tube", 0.22, 0.22, 3.0, ((k - 1) * 0.6, 1.5, -1.15), pal["panel"]))
    # stub wings
    parts += wing_pair("wing", (2.6, -3.6, 0.3), 1.8, 1.6, 0.8, 0.7, -12, 0.16, pal["hull"])
    parts.append(cyl("epodC", 0.55, 0.48, 2.2, (0, -6.6, 0.0), pal["hull2"]))
    parts += engine_nozzle("nozC", (0, -7.8, 0.0), 0.46, pal)
    parts += greebles(((-1.5, 1.5), (-5.0, 2.0)), 18, [pal["panel"], pal["hull2"], pal["white"]], seed=47, z_top=1.1)
    return finish(parts, "EnemyMauler", bevel=0.045)

def build_widow():
    """Defence drone: spiked pod with red eye."""
    reset_scene()
    pal = enemy_palette("widow")
    parts = []
    parts.append(sphere("core", 1.0, (0, 0, 0), pal["hull"], scale=(0.9, 1.1, 0.9), sub=2))
    parts.append(sphere("eye", 0.34, (0, 1.0, 0.15), pal["light"], sub=2))
    # 6 radial blade spikes in the X-Z plane
    for i in range(6):
        a = math.tau * i / 6.0
        x, z = math.sin(a), math.cos(a)
        parts.append(box(f"spk{i}", (0.16, 0.4, 2.6), (x * 1.5, -0.15, z * 1.5),
                          pal["hull2"], rot=(0, math.degrees(a), 0)))
        parts.append(box(f"spktip{i}", (0.1, 0.2, 0.7), (x * 2.6, -0.15, z * 2.6),
                          pal["light"], rot=(0, math.degrees(a), 0)))
    parts += engine_nozzle("noz", (0, -1.4, 0), 0.3, pal, depth=0.6)
    return finish(parts, "EnemyWidow", bevel=0.03)

# --------------------------------------------------------------- capitals
def build_kraken():
    """Corvette, 60 m. Separate: main hull + SUB_engine_L/R + MOUNT_t0..2."""
    reset_scene()
    pal = enemy_palette("kraken")
    parts = []
    parts.append(hull_loft("hullm", [
        {"y": 30.0, "w": 1.6, "zb": -1.2, "zt": 1.4, "tf": 0.5},
        {"y": 20.0, "w": 3.4, "zb": -2.4, "zt": 2.6, "tf": 0.6},
        {"y": 5.0, "w": 4.6, "zb": -3.0, "zt": 3.2, "tf": 0.65},
        {"y": -12.0, "w": 4.4, "zb": -2.8, "zt": 3.0, "tf": 0.7},
        {"y": -24.0, "w": 3.0, "zb": -2.0, "zt": 2.2, "tf": 0.6},
    ], pal["hull"], spine=0.3))
    # bridge tower
    parts.append(box("bridge", (2.6, 4.5, 2.2), (0, 8.0, 4.0), pal["hull2"]))
    parts.append(box("bridgewin", (2.0, 0.4, 0.7), (0, 10.3, 4.4), pal["light"]))
    # armor chines
    for sx in (1, -1):
        parts.append(box("chine", (1.2, 30.0, 1.6), (sx * 4.4, 0.0, -0.6), pal["hull2"]))
        parts.append(box("chineacc", (1.25, 6.0, 1.65), (sx * 4.4, 14.0, -0.6), pal["white"]))
    # prow ram
    parts.append(box("ram", (1.4, 6.0, 2.4), (0, 32.0, 0.0), pal["hull2"], rot=(0, 45, 0)))
    parts += greebles(((-3.4, 3.4), (-20.0, 16.0)), 30, [pal["panel"], pal["hull2"], pal["white"]], seed=53, z_top=3.0)
    hull = finish(parts, "CorvetteHull", bevel=0.08)
    # destructible engine pods (separate objects)
    subs = []
    for sx, nm in ((1, "SUB_engine_R"), (-1, "SUB_engine_L")):
        ep = []
        ep.append(cyl("ep", 1.6, 1.4, 6.0, (sx * 2.6, -27.0, 0.0), pal["hull2"]))
        ep += engine_nozzle("nz", (sx * 2.6, -30.5, 0.0), 1.3, pal, depth=2.0)
        subs.append(finish(ep, nm, bevel=0.06))
	# turret mounts on spine
    mounts = [mount("MOUNT_t0", (0, 18.0, 3.2)), mount("MOUNT_t1", (0, -2.0, 3.6)),
              mount("MOUNT_t2", (0, -16.0, -3.2))]
    return [hull] + subs + mounts

def build_carrier():
    """Friendly carrier ANV Solace, 220 m. Hangar glow, tower, mounts."""
    reset_scene()
    pal = palette("carrier", (0.45, 0.5, 0.55), (0.3, 0.7, 1.0))
    parts = []
    parts.append(hull_loft("hullm", [
        {"y": 110.0, "w": 7.0, "zb": -5.0, "zt": 6.0, "tf": 0.5},
        {"y": 60.0, "w": 13.0, "zb": -9.0, "zt": 10.0, "tf": 0.6},
        {"y": 0.0, "w": 16.0, "zb": -11.0, "zt": 12.0, "tf": 0.65},
        {"y": -60.0, "w": 15.0, "zb": -10.0, "zt": 11.0, "tf": 0.7},
        {"y": -100.0, "w": 10.0, "zb": -7.0, "zt": 8.0, "tf": 0.6},
    ], pal["hull"], spine=1.0))
    # command tower
    parts.append(box("tower", (8.0, 14.0, 10.0), (0, 30.0, 16.0), pal["hull2"]))
    parts.append(box("towerwin", (6.5, 1.2, 2.0), (0, 36.5, 18.0), mat("nav_light", (1, 1, 1), 0, 0.3, (1, 1, 1), 12.0)))
    parts.append(box("tower2", (5.0, 8.0, 6.0), (0, 26.0, 24.0), pal["hull2"]))
    # side hangar bays with glow
    for sx in (1, -1):
        parts.append(box("bay", (4.0, 60.0, 8.0), (sx * 16.5, -10.0, -2.0), pal["hull2"]))
        parts.append(box("baylight", (0.6, 52.0, 5.0), (sx * 18.4, -10.0, -2.0),
                          mat("hangar_glow", (0.05, 0.1, 0.15), 0.1, 0.4, (0.35, 0.75, 1.0), 6.0)))
    # engine block
    for sx, sz in ((1, 3.5), (-1, 3.5), (2.2, -4.0), (-2.2, -4.0)):
        parts.append(cyl("ep", 4.2, 3.6, 14.0, (sx * 5.0, -106.0, sz), pal["hull2"]))
        parts += engine_nozzle("nz", (sx * 5.0, -114.0, sz), 3.2, pal, depth=5.0)
    # runway strip lights
    parts.append(box("strip", (1.0, 180.0, 0.4), (0, 0.0, 12.2), mat("hangar_glow2", (0.05, 0.1, 0.15), 0.1, 0.4, (0.4, 0.8, 1.0), 5.0)))
    parts += greebles(((-12.0, 12.0), (-80.0, 60.0)), 40, [pal["panel"], pal["hull2"], pal["white"]], seed=59, z_top=11.0)
    hull = finish(parts, "CarrierHull", bevel=0.2)
    mounts = [mount("MOUNT_t0", (10.0, 50.0, 12.5)), mount("MOUNT_t1", (-10.0, 50.0, 12.5)),
              mount("MOUNT_t2", (12.0, -40.0, 11.5)), mount("MOUNT_t3", (-12.0, -40.0, 11.5))]
    return [hull] + mounts

def build_bastion():
    """Enemy command base VEX BASTION, ~320 m. Named destructible subsystems."""
    reset_scene()
    pal = enemy_palette("bastion", glow=(1.0, 0.15, 0.05))
    core_glow = mat("core_glow", (0.1, 0.02, 0.02), 0.2, 0.3, (1.0, 0.2, 0.08), 18.0)
    parts = []
    # central armored sphere + equator ring
    parts.append(sphere("core_armor", 42.0, (0, 0, 0), pal["hull"], sub=3))
    # ring (torus via cylinder ring of boxes)
    for i in range(16):
        a = math.tau * i / 16
        x, y = math.cos(a) * 78.0, math.sin(a) * 78.0
        parts.append(box(f"ring{i}", (24.0, 18.0, 8.0), (x, y, 0), pal["hull2"], rot=(0, 0, math.degrees(a))))
    # spokes
    for i in range(4):
        a = math.tau * i / 4 + math.pi / 4
        x, y = math.cos(a) * 55.0, math.sin(a) * 55.0
        parts.append(box(f"spoke{i}", (44.0, 7.0, 5.0), (x, y, 0), pal["panel"], rot=(0, 0, math.degrees(a))))
    # comm spires
    parts.append(cyl("spire", 2.4, 0.4, 60.0, (0, 0, 48.0), pal["hull2"], axis='Z'))
    parts.append(cyl("spire2", 2.0, 0.3, 40.0, (0, 0, -40.0), pal["hull2"], axis='Z'))
    # red warning bands
    for z in (18.0, -18.0):
        parts.append(box("band", (10.0, 10.0, 3.0), (0, -40.0, z), pal["light"]))
    parts += greebles(((-30.0, 30.0), (-30.0, 30.0)), 26, [pal["panel"], pal["hull2"]], seed=61, z_top=40.0)
    hull = finish(parts, "BastionHull", bevel=0.3)
    subs = []
    # 4 shield generator domes on the ring
    for i in range(4):
        a = math.tau * i / 4
        x, y = math.cos(a) * 78.0, math.sin(a) * 78.0
        dome = [sphere(f"dm", 9.0, (x, y, 10.0), mat("shield_dome", (0.2, 0.5, 0.9), 0.6, 0.25, (0.3, 0.7, 1.0), 4.0), sub=2),
                cyl("dmb", 10.0, 10.5, 4.0, (x, y, 3.0), pal["hull2"], axis='Z')]
        subs.append(finish(dome, f"SUB_shield_{i}", bevel=0.1))
    # radar dish
    dish = [cyl("dishpole", 1.2, 1.0, 16.0, (0, 60.0, 30.0), pal["hull2"], axis='Z'),
            cyl("dish", 12.0, 1.0, 5.0, (0, 60.0, 42.0), pal["panel"], axis='Z')]
    subs.append(finish(dish, "SUB_radar", bevel=0.1))
    # missile launchers
    for i, (x, y) in enumerate([(55.0, 55.0), (-55.0, -55.0)]):
        ln = [box("lnch", (10.0, 10.0, 6.0), (x, y, 14.0), pal["hull2"]),
              *[cyl(f"lt{k}", 1.1, 1.1, 5.0, (x - 3 + k * 3, y, 17.5), pal["dark"], axis='Z') for k in range(3)]]
        subs.append(finish(ln, f"SUB_launcher_{i}", bevel=0.08))
    # hangar block
    hang = [box("hangar", (30.0, 16.0, 12.0), (0, -78.0, 0.0), pal["hull2"]),
            box("hangarglow", (22.0, 1.5, 8.0), (0, -86.5, 0.0), core_glow)]
    subs.append(finish(hang, "SUB_hangar", bevel=0.15))
    # command tower
    cmd = [box("cmdt", (12.0, 12.0, 22.0), (0, 30.0, 52.0), pal["hull2"]),
           box("cmdwin", (9.0, 9.5, 2.5), (0, 30.0, 60.0), pal["light"])]
    subs.append(finish(cmd, "SUB_command", bevel=0.12))
    # exposed reactor core (revealed target) — glowing sphere at south pole
    rc = [sphere("reactor", 14.0, (0, 0, -52.0), core_glow, sub=3),
          cyl("rcage1", 15.5, 15.5, 6.0, (0, 0, -52.0), pal["hull2"], axis='Z')]
    subs.append(finish(rc, "SUB_reactor", bevel=0.1))
    # turret mounts around the ring
    mounts = []
    for i in range(8):
        a = math.tau * i / 8 + math.pi / 8
        x, y = math.cos(a) * 82.0, math.sin(a) * 82.0
        mounts.append(mount(f"MOUNT_t{i}", (x, y, 6.0)))
    return [hull] + subs + mounts

def _local_cyl(name, r1, r2, depth, offset, material, axis='Y', segs=16):
    """Cylinder with orientation+offset baked into the MESH (object stays at origin)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    if axis == 'Y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                         matrix=Matrix.Rotation(math.radians(-90), 3, 'X'))
    elif axis == 'X':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                         matrix=Matrix.Rotation(math.radians(90), 3, 'Y'))
    bmesh.ops.translate(bm, verts=bm.verts, vec=offset)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.append(material)
    return new_obj(name, me)

def _local_box(name, size, offset, material):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts, vec=size)
    bmesh.ops.translate(bm, verts=bm.verts, vec=offset)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.append(material)
    return new_obj(name, me)

def build_turret():
    """Articulated turret: Base > Yoke (yaw) > Barrels (pitch), clean pivots."""
    reset_scene()
    pal = enemy_palette("turret")
    base = _local_cyl("TurretBase", 1.5, 1.25, 1.2, (0, 0, 0.6), pal["hull2"], axis='Z')
    yk = _local_box("yk", (1.6, 1.6, 0.9), (0, 0, 0.45), pal["hull"])
    ya = _local_box("ykacc", (1.65, 0.5, 0.5), (0, 0.6, 0.6), pal["white"])
    yoke = finish([yk, ya], "TurretYoke", bevel=0.04)
    barrs = [_local_cyl("brR", 0.14, 0.11, 3.2, (0.45, 1.6, 0), pal["dark"]),
             _local_cyl("brL", 0.14, 0.11, 3.2, (-0.45, 1.6, 0), pal["dark"]),
             _local_box("breach", (1.3, 1.0, 0.7), (0, 0.2, 0), pal["hull2"])]
    barr = finish(barrs, "TurretBarrels", bevel=0.03)
    yoke.parent = base
    yoke.location = (0, 0, 1.2)
    barr.parent = yoke
    barr.location = (0, 0, 0.6)
    return [base, yoke, barr]

print("enemy_ships loaded")
