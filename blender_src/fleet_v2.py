# Helion Vanguard — fleet expansion (1.2). Requires shipgen.py exec'd first.
#
# Six new hulls covering the classes the game did not have: a fleet supercarrier,
# a dreadnought, a destroyer, an escort frigate, and two new player fighters.
#
# Run headless:
#   blender --background --python blender_src/fleet_v2.py -- <out_dir> [name ...]
#
# Conventions inherited from the existing factory (do not change these — the
# runtime depends on them):
#   * nose is +Y in Blender; `export_yup=True` turns that into -Z in Godot
#   * 1 Blender unit == 1 metre
#   * on a capital, TOP-LEVEL objects named `SUB_<kind>*` become destructible
#     subsystems and `MOUNT_*` empties become turret sockets. Everything else is
#     merged into hull collision. See CapitalShip._load_model().
#   * materials are named `<x>_hull` / `<x>_engine` / `nav_light` etc. because
#     HullMaterial keys its procedural treatment off those suffixes.
import bpy, bmesh, math, random, os, sys
from mathutils import Vector, Matrix

# The factory is a script, not a package: the existing workflow is to exec
# shipgen.py so its helpers land in the caller's globals. Doing the same here
# keeps one definition of `box`, `hull_loft`, `finish` and friends.
_HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_HERE, "shipgen.py")) as _f:
    exec(compile(_f.read(), os.path.join(_HERE, "shipgen.py"), "exec"), globals())


def mount(name, pos):
    """Turret socket. An Empty so it carries no geometry into the hull merge."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.5
    bpy.context.scene.collection.objects.link(e)
    e.location = pos
    return e


def fleet_palette(ship, paint, glow, accent=(0.86, 0.88, 0.92)):
    """Allied warship palette — cool grey armour, bright deck markings."""
    return {
        "hull":   mat(f"{ship}_hull", paint, 0.75, 0.40, coat=0.25),
        "hull2":  mat(f"{ship}_hull2", tuple(c * 0.42 for c in paint), 0.82, 0.52),
        "white":  mat(f"{ship}_acc", accent, 0.65, 0.42),
        "panel":  mat("panel_grey", (0.42, 0.44, 0.47), 0.85, 0.55),
        "dark":   mat("gunmetal", (0.08, 0.085, 0.1), 0.9, 0.45),
        "glass":  mat("canopy_glass", (0.02, 0.05, 0.08), 0.4, 0.08),
        "engine": mat(f"{ship}_engine", (0.02, 0.02, 0.02), 0.2, 0.4, glow, 30.0),
        "light":  mat("nav_light", (1.0, 1.0, 1.0), 0.0, 0.3, (1.0, 1.0, 1.0), 12.0),
        "deck":   mat(f"{ship}_deck", (0.11, 0.115, 0.125), 0.55, 0.72),
        "mark":   mat(f"{ship}_mark", (0.88, 0.72, 0.10), 0.3, 0.6),
        "bay":    mat(f"{ship}_bay", (0.04, 0.08, 0.12), 0.15, 0.4, glow, 7.0),
    }


def hostile_palette(ship, glow=(1.0, 0.14, 0.06)):
    return {
        "hull":   mat("vx_hull", (0.10, 0.105, 0.12), 0.85, 0.42),
        "hull2":  mat("vx_hull2", (0.055, 0.06, 0.07), 0.9, 0.5),
        "white":  mat("vx_accent", (0.52, 0.06, 0.05), 0.7, 0.4),
        "panel":  mat("vx_panel", (0.2, 0.2, 0.23), 0.85, 0.55),
        "dark":   mat("gunmetal", (0.08, 0.085, 0.1), 0.9, 0.45),
        "glass":  mat("vx_glass", (0.06, 0.005, 0.005), 0.4, 0.1),
        "engine": mat(f"{ship}_engine", (0.02, 0.02, 0.02), 0.2, 0.4, glow, 26.0),
        "light":  mat("vx_light", (1.0, 0.1, 0.05), 0.0, 0.3, (1.0, 0.1, 0.05), 14.0),
        "deck":   mat("vx_deck", (0.07, 0.07, 0.08), 0.6, 0.7),
        "mark":   mat("vx_mark", (0.6, 0.08, 0.05), 0.4, 0.6),
        "bay":    mat("vx_bay", (0.09, 0.02, 0.02), 0.15, 0.4, glow, 6.0),
    }


# --------------------------------------------------------------- shared detail
def hull_ribs(pal, x_half, y0, y1, z, count, thick=0.5):
    """Transverse structural ribs — the single cheapest thing that makes a big
    slab-sided hull read as built rather than extruded."""
    out = []
    for i in range(count):
        y = y0 + (y1 - y0) * (i + 0.5) / count
        out.append(box(f"rib{i}", (x_half * 2.05, thick, thick * 1.6), (0, y, z), pal["hull2"]))
    return out


def deck_lights(pal, x, y0, y1, z, count):
    out = []
    for i in range(count):
        y = y0 + (y1 - y0) * i / max(count - 1, 1)
        out.append(box(f"dl{i}", (0.5, 1.6, 0.10), (x, y, z), pal["bay"]))
    return out


def armour_belt(pal, x, y0, y1, z, segs, w=1.4, h=2.2):
    """Segmented armour plating down a flank."""
    out = []
    step = (y1 - y0) / segs
    for i in range(segs):
        y = y0 + step * (i + 0.5)
        out.append(box(f"belt{i}", (w, step * 0.88, h), (x, y, z), pal["hull2"]))
        if i % 3 == 0:
            out.append(box(f"beltacc{i}", (w * 1.06, step * 0.30, h * 0.35),
                           (x, y, z + h * 0.28), pal["white"]))
    return out


def big_finish(parts, name, bevel=0.2):
    """finish() for capital hulls, with a single-segment bevel.

    The default two-segment bevel is right for a 16 m fighter, but a capital is
    assembled from 150-250 primitives and the second segment alone took the
    Leviathan's base mesh to 47k triangles before the detail pass had run — well
    outside the 8-10k the existing capitals sit at. One segment still catches a
    highlight on every edge at the ranges a 420 m ship is actually viewed from.
    """
    obj = finish(parts, name, bevel=bevel)
    bev = obj.modifiers.get("Bevel")
    if bev:
        bev.segments = 1
    return obj


def radiator_fin(pal, pos, span, length, tilt=0.0):
    """Heat radiator panel — capital ships need somewhere to dump reactor heat,
    and a big flat plane breaks up an otherwise solid silhouette."""
    b = box("rad", (span, length, 0.24), pos, pal["panel"], rot=(0, 0, 0))
    b.rotation_euler = (math.radians(tilt), 0, 0)
    return b


# ================================================================= SUPERCARRIER
def build_leviathan():
    """ANV Leviathan — fleet supercarrier, 420 m.

    Angled flight deck with catapult tracks and arrestor strips, an island
    superstructure to starboard, four elevator bays, open hangar mouths fore and
    aft, a defensive turret belt and eight destructible subsystems.
    """
    reset_scene()
    pal = fleet_palette("leviathan", (0.40, 0.44, 0.49), (0.32, 0.72, 1.0))
    L = 210.0                      # half-length
    parts = []

    # --- primary hull: a long, flat-topped box keel -------------------------
    parts.append(hull_loft("hullm", [
        {"y": L, "w": 7.0, "zb": -5.0, "zt": 4.0, "tf": 0.42},
        {"y": L * 0.78, "w": 16.0, "zb": -10.0, "zt": 7.0, "tf": 0.55},
        {"y": L * 0.45, "w": 25.0, "zb": -14.0, "zt": 9.0, "tf": 0.72},
        {"y": 0.0, "w": 29.0, "zb": -16.0, "zt": 10.0, "tf": 0.80},
        {"y": -L * 0.45, "w": 28.0, "zb": -15.5, "zt": 10.0, "tf": 0.80},
        {"y": -L * 0.80, "w": 22.0, "zb": -13.0, "zt": 9.0, "tf": 0.70},
        {"y": -L, "w": 14.0, "zb": -9.0, "zt": 7.0, "tf": 0.55},
    ], pal["hull"], spine=0.0))

    # --- flight deck: a broad overhanging platform, angled to port ----------
    deck = box("deck", (54.0, L * 1.72, 1.8), (2.0, 6.0, 10.6), pal["deck"])
    parts.append(deck)
    # deck lip / catwalk
    for sx in (1, -1):
        parts.append(box("lip", (2.4, L * 1.70, 3.0), (2.0 + sx * 27.0, 6.0, 9.6), pal["hull2"]))
        parts += [box(f"cat{i}", (3.6, 5.0, 0.6),
                      (2.0 + sx * 29.0, -L * 0.8 + i * 34.0, 8.6), pal["panel"])
                  for i in range(9)]
    # angled landing strip, marked in deck yellow
    strip = box("strip_ang", (13.0, L * 1.30, 0.22), (-9.0, -8.0, 11.55), pal["mark"])
    strip.rotation_euler = (0, 0, math.radians(9.0))
    parts.append(strip)
    # two bow catapult tracks
    for cx in (10.0, 22.0):
        parts.append(box("cat_track", (1.5, L * 0.95, 0.30), (cx, 40.0, 11.55), pal["white"]))
        parts.append(box("cat_shuttle", (2.6, 3.0, 0.5), (cx, -30.0, 11.7), pal["hull2"]))
    # arrestor wires across the angled deck
    for i in range(4):
        w = box(f"wire{i}", (12.5, 0.35, 0.12), (-9.0, -70.0 + i * 11.0, 11.6), pal["dark"])
        w.rotation_euler = (0, 0, math.radians(9.0))
        parts.append(w)
    # deck edge lighting
    parts += deck_lights(pal, 27.5, -L * 0.82, L * 0.82, 11.6, 22)
    parts += deck_lights(pal, -23.5, -L * 0.82, L * 0.82, 11.6, 22)

    # --- four aircraft elevators (recessed pads with a bright well) ---------
    for i, (ex, ey) in enumerate([(26.0, 70.0), (26.0, -20.0), (-20.0, 30.0), (-20.0, -80.0)]):
        parts.append(box(f"elev{i}", (13.0, 15.0, 0.55), (ex, ey, 11.35), pal["hull2"]))
        parts.append(box(f"elevw{i}", (11.6, 13.6, 0.24), (ex, ey, 11.05), pal["bay"]))

    # --- island superstructure, starboard ------------------------------------
    parts.append(box("island", (13.0, 40.0, 15.0), (34.0, -18.0, 19.0), pal["hull2"]))
    parts.append(box("island2", (10.0, 22.0, 9.0), (34.0, -8.0, 31.0), pal["hull2"]))
    parts.append(box("bridge_win", (10.6, 9.0, 2.0), (34.0, 1.0, 33.5), pal["light"]))
    parts.append(box("flag_win", (13.4, 5.0, 1.6), (34.0, -2.0, 24.0), pal["light"]))
    parts.append(box("island_acc", (13.2, 3.0, 15.2), (34.0, -34.0, 19.0), pal["white"]))
    # mast + primary sensor array
    parts.append(cyl("mast", 0.9, 0.6, 20.0, (34.0, -14.0, 45.0), pal["dark"], axis='Z'))
    parts.append(box("yard", (14.0, 1.0, 0.8), (34.0, -14.0, 41.0), pal["dark"]))
    parts.append(box("yard2", (9.0, 0.9, 0.7), (34.0, -14.0, 48.0), pal["dark"]))
    parts += aerials(pal, [((34.0, -20.0, 56.0), 7.0), ((34.0, -8.0, 54.0), 5.5),
                           ((30.0, -14.0, 52.0), 4.0)])
    parts += nav_lights([(34.0, -14.0, 57.0), (28.0, L * 1.6 * 0.5, 11.9),
                         (-24.0, L * 1.6 * 0.5, 11.9)], pal)

    # --- hangar mouths, fore and aft ---------------------------------------
    for ny, tag in ((L * 0.86, "fwd"), (-L * 0.86, "aft")):
        parts.append(box(f"hmouth_{tag}", (26.0, 4.0, 9.0), (0, ny, 1.0), pal["hull2"]))
        parts.append(box(f"hglow_{tag}", (22.0, 1.2, 6.5), (0, ny + 1.4, 1.0), pal["bay"]))

    # --- flanks: armour belt, sponsons, ribs --------------------------------
    for sx in (1, -1):
        parts += armour_belt(pal, sx * 28.5, -L * 0.9, L * 0.9, -4.0, 18, w=1.8, h=6.0)
        for i in range(4):
            sy = -110.0 + i * 74.0
            parts.append(box(f"spon{i}", (7.0, 16.0, 5.0), (sx * 31.0, sy, 1.0), pal["hull2"]))
            parts.append(cyl(f"sponb{i}", 0.55, 0.42, 9.0, (sx * 33.0, sy + 9.0, 1.0), pal["dark"]))
    parts += hull_ribs(pal, 26.0, -L * 0.85, L * 0.85, -15.0, 16, thick=1.1)

    # --- radiators, keel detail, greebles ------------------------------------
    for sx in (1, -1):
        parts.append(radiator_fin(pal, (sx * 40.0, -60.0, -6.0), 18.0, 60.0, tilt=18.0))
    parts.append(box("keel", (9.0, L * 1.5, 3.2), (0, 0, -16.5), pal["hull2"]))
    parts += panel_lines(pal, (-24.0, 24.0), (-L * 0.8, L * 0.8), 11.7, count=26, seed=71)
    parts += greebles(((-24.0, 24.0), (-L * 0.8, L * 0.8)), 90,
                      [pal["panel"], pal["hull2"], pal["white"]], seed=83, z_top=11.9)
    for i in range(10):
        parts += rcs_block(pal, (random.uniform(-26, 26), random.uniform(-L * 0.8, L * 0.8), -16.6), s=0.8)

    hull = big_finish(parts, "LeviathanHull", bevel=0.25)

    # --- destructible subsystems --------------------------------------------
    subs = []
    # four main engines in a square block
    for i, (ex, ez) in enumerate([(14.0, 4.0), (-14.0, 4.0), (14.0, -7.0), (-14.0, -7.0)]):
        ep = [cyl(f"ep{i}", 7.0, 6.0, 26.0, (ex, -L * 0.94, ez), pal["hull2"], verts=20)]
        ep += engine_nozzle_v2(f"nz{i}", (ex, -L * 1.06, ez), 5.6, pal, depth=9.0)
        subs.append(finish(ep, f"SUB_engine_{i}", bevel=0.12))
    # reactor spine bulge (underside, the classic soft spot)
    rc = [sphere("rcore", 9.5, (0, -30.0, -18.0), pal["hull2"], sub=3),
          cyl("rring", 11.0, 11.0, 3.0, (0, -30.0, -18.0), pal["dark"], axis='Z'),
          sphere("rglow", 6.4, (0, -30.0, -18.0), pal["bay"], sub=2)]
    subs.append(finish(rc, "SUB_reactor", bevel=0.12))
    # combat information centre inside the island
    cmd = [box("cmdbox", (11.0, 12.0, 7.0), (34.0, -8.0, 31.0), pal["hull2"]),
           box("cmdacc", (11.2, 2.0, 7.2), (34.0, -14.5, 31.0), pal["white"])]
    subs.append(finish(cmd, "SUB_command", bevel=0.1))
    # main radar dish on the mast
    dish = [cyl("dishb", 2.2, 1.6, 1.4, (34.0, -14.0, 38.0), pal["hull2"], axis='Z'),
            box("dishp", (11.0, 0.6, 7.0), (34.0, -14.0, 41.5), pal["panel"])]
    subs.append(finish(dish, "SUB_radar", bevel=0.08))
    # hangar deck (kill it and the carrier stops launching)
    hang = [box("hbox", (24.0, 40.0, 8.0), (0, 60.0, 1.0), pal["hull2"]),
            box("hglow", (21.0, 36.0, 5.0), (0, 60.0, 1.0), pal["bay"])]
    subs.append(finish(hang, "SUB_hangar", bevel=0.12))
    # two shield generator domes on the deck edge
    for i, sx in enumerate((1, -1)):
        dome = [sphere(f"sg{i}", 5.2, (sx * 22.0, -120.0, 13.5), pal["hull2"], sub=2,
                       scale=(1.0, 1.0, 0.62)),
                cyl(f"sgb{i}", 5.4, 4.6, 2.2, (sx * 22.0, -120.0, 11.8), pal["dark"], axis='Z'),
                sphere(f"sgg{i}", 3.6, (sx * 22.0, -120.0, 14.4), pal["bay"], sub=2,
                       scale=(1.0, 1.0, 0.55))]
        subs.append(finish(dome, f"SUB_shieldgen_{i}", bevel=0.1))

    # --- defensive turret belt ------------------------------------------------
    mounts = []
    ring = [(30.0, 130.0, 12.4), (-26.0, 130.0, 12.4), (30.0, 60.0, 12.4),
            (-26.0, 60.0, 12.4), (30.0, -60.0, 12.4), (-26.0, -60.0, 12.4),
            (18.0, -150.0, 12.4), (-18.0, -150.0, 12.4),
            (0.0, 150.0, -17.0), (0.0, -100.0, -17.0)]
    for i, p in enumerate(ring):
        mounts.append(mount(f"MOUNT_t{i}", p))
    return [hull] + subs + mounts


# =================================================================== DREADNOUGHT
def build_sovereign():
    """VEX Sovereign — dreadnought, 300 m, built around a spinal mass driver."""
    reset_scene()
    pal = hostile_palette("sovereign")
    L = 150.0
    parts = []
    parts.append(hull_loft("hullm", [
        {"y": L, "w": 4.0, "zb": -3.0, "zt": 3.0, "tf": 0.4},
        {"y": L * 0.72, "w": 11.0, "zb": -8.0, "zt": 7.0, "tf": 0.5},
        {"y": L * 0.30, "w": 19.0, "zb": -13.0, "zt": 11.0, "tf": 0.6},
        {"y": -L * 0.10, "w": 22.0, "zb": -15.0, "zt": 13.0, "tf": 0.68},
        {"y": -L * 0.55, "w": 20.0, "zb": -14.0, "zt": 12.0, "tf": 0.7},
        {"y": -L, "w": 12.0, "zb": -9.0, "zt": 8.0, "tf": 0.55},
    ], pal["hull"], spine=0.8))
    # the spinal weapon: a long armoured tube running most of the ship
    parts.append(cyl("spine_tube", 4.2, 3.6, L * 1.55, (0, 6.0, 6.0), pal["hull2"], verts=20))
    for i in range(9):
        parts.append(cyl(f"spine_ring{i}", 5.0, 5.0, 2.0,
                         (0, -95.0 + i * 26.0, 6.0), pal["dark"], verts=20))
    parts.append(cyl("muzzle", 4.6, 5.4, 9.0, (0, L * 0.98, 6.0), pal["hull2"], verts=20))
    parts.append(cyl("muzzle_glow", 3.2, 3.2, 1.2, (0, L * 1.02, 6.0), pal["bay"], verts=16))
    # conning tower
    parts.append(box("tower", (9.0, 20.0, 11.0), (0, -34.0, 18.0), pal["hull2"]))
    parts.append(box("tower_win", (7.4, 1.4, 2.0), (0, -24.5, 21.0), pal["light"]))
    parts.append(box("tower2", (6.0, 11.0, 7.0), (0, -38.0, 27.0), pal["hull2"]))
    parts += aerials(pal, [((0, -44.0, 33.0), 8.0), ((4.0, -34.0, 32.0), 5.0)])
    # broadside batteries and armour
    for sx in (1, -1):
        parts += armour_belt(pal, sx * 21.5, -L * 0.85, L * 0.7, 0.0, 14, w=2.0, h=7.0)
        for i in range(5):
            by = -95.0 + i * 44.0
            parts.append(box(f"cas{i}", (5.0, 12.0, 5.0), (sx * 23.0, by, 3.0), pal["hull2"]))
            parts.append(cyl(f"casb{i}", 0.6, 0.45, 11.0, (sx * 25.5, by + 7.0, 3.0), pal["dark"]))
        parts.append(radiator_fin(pal, (sx * 30.0, -70.0, -4.0), 14.0, 52.0, tilt=-22.0))
    parts += hull_ribs(pal, 19.0, -L * 0.8, L * 0.6, -14.0, 14, thick=1.0)
    parts += panel_lines(pal, (-16.0, 16.0), (-L * 0.7, L * 0.7), 12.5, count=22, seed=17)
    parts += greebles(((-16.0, 16.0), (-L * 0.7, L * 0.7)), 70,
                      [pal["panel"], pal["hull2"], pal["white"]], seed=29, z_top=13.0)
    hull = big_finish(parts, "SovereignHull", bevel=0.2)

    subs = []
    for i, (ex, ez) in enumerate([(11.0, 3.0), (-11.0, 3.0), (0.0, -8.0)]):
        ep = [cyl(f"ep{i}", 6.2, 5.2, 22.0, (ex, -L * 0.90, ez), pal["hull2"], verts=20)]
        ep += engine_nozzle_v2(f"nz{i}", (ex, -L * 1.02, ez), 5.0, pal, depth=8.0)
        subs.append(finish(ep, f"SUB_engine_{i}", bevel=0.12))
    # the mass driver's capacitor bank — kill it and the spinal gun is dead
    cap = [box("capb", (11.0, 26.0, 8.0), (0, 30.0, -12.0), pal["hull2"]),
           box("capg", (8.0, 22.0, 5.0), (0, 30.0, -12.0), pal["bay"])]
    subs.append(finish(cap, "SUB_launcher_spinal", bevel=0.1))
    rc = [sphere("rcore", 8.0, (0, -60.0, -13.0), pal["hull2"], sub=3),
          sphere("rglow", 5.4, (0, -60.0, -13.0), pal["bay"], sub=2)]
    subs.append(finish(rc, "SUB_reactor", bevel=0.1))
    dish = [cyl("dishb", 2.0, 1.5, 1.2, (0, -44.0, 30.0), pal["hull2"], axis='Z'),
            box("dishp", (9.0, 0.5, 6.0), (0, -44.0, 33.0), pal["panel"])]
    subs.append(finish(dish, "SUB_radar", bevel=0.08))

    mounts = [mount(f"MOUNT_t{i}", p) for i, p in enumerate([
        (0.0, 96.0, 14.0), (13.0, 40.0, 13.0), (-13.0, 40.0, 13.0),
        (13.0, -20.0, 13.0), (-13.0, -20.0, 13.0), (0.0, -78.0, 13.0),
        (0.0, 20.0, -16.0), (0.0, -60.0, -16.0)])]
    return [hull] + subs + mounts


# ===================================================================== DESTROYER
def build_warden():
    """VEX Warden — destroyer, 150 m, forward missile cell bank."""
    reset_scene()
    pal = hostile_palette("warden")
    L = 75.0
    parts = []
    parts.append(hull_loft("hullm", [
        {"y": L, "w": 2.6, "zb": -2.0, "zt": 2.0, "tf": 0.4},
        {"y": L * 0.66, "w": 7.0, "zb": -5.0, "zt": 4.6, "tf": 0.5},
        {"y": L * 0.16, "w": 11.5, "zb": -8.0, "zt": 7.0, "tf": 0.62},
        {"y": -L * 0.34, "w": 11.0, "zb": -7.6, "zt": 6.8, "tf": 0.68},
        {"y": -L, "w": 6.5, "zb": -5.0, "zt": 4.4, "tf": 0.55},
    ], pal["hull"], spine=0.5))
    # forward VLS: an armoured raft of cell hatches
    parts.append(box("vls", (13.0, 22.0, 2.4), (0, 30.0, 7.0), pal["hull2"]))
    for r in range(6):
        for c in range(4):
            parts.append(box(f"cell{r}{c}", (2.2, 2.6, 0.5),
                             (-4.5 + c * 3.0, 20.0 + r * 3.6, 8.3),
                             pal["mark"] if (r + c) % 4 == 0 else pal["dark"]))
    # prow ram + sensor cluster
    parts.append(box("ram", (2.2, 9.0, 3.2), (0, L * 0.93, 0.0), pal["hull2"], rot=(0, 45, 0)))
    parts.append(box("bridge", (6.0, 11.0, 6.0), (0, -12.0, 10.0), pal["hull2"]))
    parts.append(box("bwin", (5.0, 1.0, 1.4), (0, -6.8, 11.6), pal["light"]))
    parts += aerials(pal, [((0, -18.0, 15.0), 6.0), ((2.5, -12.0, 14.0), 4.0)])
    for sx in (1, -1):
        parts += armour_belt(pal, sx * 11.0, -L * 0.8, L * 0.55, 0.0, 10, w=1.2, h=4.0)
        parts.append(box("fin", (1.0, 20.0, 7.0), (sx * 11.5, -L * 0.55, 2.0), pal["hull2"]))
        parts.append(box("finacc", (1.1, 5.0, 7.2), (sx * 11.5, -L * 0.42, 2.0), pal["white"]))
    parts += hull_ribs(pal, 10.0, -L * 0.7, L * 0.5, -7.5, 9, thick=0.6)
    parts += panel_lines(pal, (-8.0, 8.0), (-L * 0.6, L * 0.6), 7.2, count=14, seed=37)
    parts += greebles(((-8.0, 8.0), (-L * 0.6, L * 0.6)), 44,
                      [pal["panel"], pal["hull2"], pal["white"]], seed=41, z_top=7.4)
    hull = big_finish(parts, "WardenHull", bevel=0.12)

    subs = []
    for i, sx in enumerate((1, -1)):
        ep = [cyl(f"ep{i}", 3.4, 2.9, 13.0, (sx * 5.0, -L * 0.86, 0.0), pal["hull2"], verts=18)]
        ep += engine_nozzle_v2(f"nz{i}", (sx * 5.0, -L * 1.00, 0.0), 2.8, pal, depth=5.0)
        subs.append(finish(ep, f"SUB_engine_{i}", bevel=0.08))
    ln = [box("lnb", (12.0, 20.0, 2.0), (0, 30.0, 7.6), pal["hull2"]),
          box("lng", (9.0, 16.0, 0.8), (0, 30.0, 8.6), pal["bay"])]
    subs.append(finish(ln, "SUB_launcher", bevel=0.08))
    dish = [cyl("dishb", 1.2, 0.9, 0.9, (0, -18.0, 16.0), pal["hull2"], axis='Z'),
            box("dishp", (5.5, 0.4, 3.6), (0, -18.0, 18.0), pal["panel"])]
    subs.append(finish(dish, "SUB_radar", bevel=0.06))

    mounts = [mount(f"MOUNT_t{i}", p) for i, p in enumerate([
        (0.0, 52.0, 8.0), (7.0, 4.0, 8.0), (-7.0, 4.0, 8.0),
        (0.0, -34.0, 8.0), (0.0, 10.0, -8.5)])]
    return [hull] + subs + mounts


# ======================================================================= FRIGATE
def build_talon():
    """ANV Talon — escort frigate, 90 m. Small, fast, point-defence heavy."""
    reset_scene()
    pal = fleet_palette("talon", (0.30, 0.36, 0.42), (0.35, 0.75, 1.0))
    L = 45.0
    parts = []
    parts.append(hull_loft("hullm", [
        {"y": L, "w": 1.6, "zb": -1.2, "zt": 1.3, "tf": 0.4},
        {"y": L * 0.62, "w": 4.4, "zb": -3.0, "zt": 3.0, "tf": 0.5},
        {"y": L * 0.10, "w": 6.8, "zb": -4.6, "zt": 4.2, "tf": 0.62},
        {"y": -L * 0.45, "w": 6.4, "zb": -4.4, "zt": 4.0, "tf": 0.68},
        {"y": -L, "w": 3.8, "zb": -2.8, "zt": 2.6, "tf": 0.55},
    ], pal["hull"], spine=0.3))
    parts.append(box("bridge", (3.6, 7.0, 3.4), (0, -4.0, 5.8), pal["hull2"]))
    parts.append(box("bwin", (3.0, 0.7, 0.9), (0, -0.8, 6.6), pal["light"]))
    parts.append(box("prow", (1.4, 6.0, 1.8), (0, L * 0.90, 0.0), pal["white"], rot=(0, 45, 0)))
    # outrigger sensor/PD pods on struts
    for sx in (1, -1):
        parts.append(box("strut", (5.0, 1.2, 0.7), (sx * 8.0, 4.0, 1.5), pal["hull2"]))
        parts.append(cyl("pod", 1.3, 1.0, 8.0, (sx * 11.0, 2.0, 1.5), pal["hull2"], verts=14))
        parts.append(cyl("podcap", 1.35, 1.35, 0.5, (sx * 11.0, 6.2, 1.5), pal["white"], verts=14))
        parts.append(box("pdgun", (0.5, 2.4, 0.5), (sx * 11.0, 7.6, 1.5), pal["dark"]))
        parts += armour_belt(pal, sx * 6.6, -L * 0.7, L * 0.45, 0.0, 7, w=0.8, h=2.6)
    parts += hull_ribs(pal, 6.0, -L * 0.6, L * 0.4, -4.4, 7, thick=0.4)
    parts += panel_lines(pal, (-5.0, 5.0), (-L * 0.6, L * 0.6), 4.3, count=11, seed=61)
    parts += greebles(((-5.0, 5.0), (-L * 0.6, L * 0.6)), 30,
                      [pal["panel"], pal["hull2"], pal["white"]], seed=67, z_top=4.4)
    parts += nav_lights([(11.0, 6.6, 1.5), (-11.0, 6.6, 1.5), (0, -L * 0.9, 4.2)], pal)
    hull = big_finish(parts, "TalonHull", bevel=0.09)

    subs = []
    for i, sx in enumerate((1, -1)):
        ep = [cyl(f"ep{i}", 2.0, 1.7, 8.0, (sx * 3.0, -L * 0.84, 0.0), pal["hull2"], verts=16)]
        ep += engine_nozzle_v2(f"nz{i}", (sx * 3.0, -L * 0.99, 0.0), 1.7, pal, depth=3.2)
        subs.append(finish(ep, f"SUB_engine_{i}", bevel=0.06))

    mounts = [mount(f"MOUNT_t{i}", p) for i, p in enumerate([
        (0.0, 22.0, 4.6), (0.0, -16.0, 4.6), (0.0, 2.0, -5.0)])]
    return [hull] + subs + mounts


# ================================================================ PLAYER: SPECTER
def build_specter():
    """SR-2 Specter — stealth interceptor. Faceted, blended, almost no glow."""
    reset_scene()
    pal = fleet_palette("specter", (0.16, 0.17, 0.20), (0.55, 0.30, 1.0),
                        accent=(0.55, 0.58, 0.66))
    glowmat = pal["engine"]
    parts = []
    parts.append(hull_loft("hullm", [
        {"y": 8.8, "w": 0.06, "zb": -0.02, "zt": 0.05},
        {"y": 7.4, "w": 0.34, "zb": -0.16, "zt": 0.18, "tf": 0.30},
        {"y": 5.6, "w": 0.66, "zb": -0.30, "zt": 0.32, "tf": 0.34},
        {"y": 3.4, "w": 0.98, "zb": -0.42, "zt": 0.52, "tf": 0.38},
        {"y": 1.0, "w": 1.22, "zb": -0.50, "zt": 0.66, "tf": 0.42},
        {"y": -1.6, "w": 1.30, "zb": -0.52, "zt": 0.62, "tf": 0.46},
        {"y": -4.4, "w": 1.16, "zb": -0.46, "zt": 0.54, "tf": 0.48},
        {"y": -6.8, "w": 0.82, "zb": -0.34, "zt": 0.40, "tf": 0.46},
    ], pal["hull"], spine=0.0))
    # chined blended body — the stealth read comes from flat facets, not curves
    for sx in (1, -1):
        parts.append(box("chine", (0.9, 9.0, 0.16), (sx * 1.05, 1.2, -0.16),
                         pal["hull2"], rot=(0, 24 * (1 if sx > 0 else -1), 0)))
        parts.append(box("chine2", (0.7, 5.0, 0.14), (sx * 0.95, -3.4, 0.30),
                        pal["hull2"], rot=(0, -18 * (1 if sx > 0 else -1), 0)))
    # low-profile canopy, heavily faired
    parts.append(sphere("canopy", 1.0, (0, 2.6, 0.62), pal["glass"], scale=(0.42, 1.7, 0.26)))
    parts.append(box("canfair", (0.9, 3.0, 0.22), (0, 1.4, 0.60), pal["hull2"]))
    # cranked-diamond wings with sharply swept tips
    parts += wing_pair("wing", (0.95, -1.4, -0.10), 3.9, 3.2, 0.85, 2.9, 6, 0.13, pal["hull"])
    parts.append(leading_edge(pal, (0.95, -1.4, -0.10), 3.9, 2.9, 6, 0.13))
    parts.append(leading_edge(pal, (0.95, -1.4, -0.10), 3.9, 2.9, 6, 0.13, mirrored=True))
    # canted twin tails (radar-return killers)
    for sx in (1, -1):
        parts.append(box("tail", (0.12, 2.4, 1.5), (sx * 1.9, -5.2, 0.85),
                         pal["hull2"], rot=(0, 32 * (1 if sx > 0 else -1), 0)))
    # internal weapon bay: doors closed, thin seams only
    parts.append(box("bay_door", (1.5, 3.4, 0.06), (0, 0.6, -0.56), pal["hull2"]))
    parts.append(box("bay_seam", (0.05, 3.4, 0.07), (0, 0.6, -0.58), pal["dark"]))
    # dark, recessed nozzles: a stealth ship should barely glow
    for sx in (1, -1):
        parts.append(box("shroud", (0.85, 2.0, 0.5), (sx * 0.55, -6.2, 0.06), pal["hull2"]))
        parts += engine_nozzle_v2(f"nz{sx}", (sx * 0.55, -7.0, 0.06), 0.34, pal, depth=1.1)
    parts.append(box("strip", (0.05, 4.0, 0.05), (0, -3.0, 0.66), glowmat))
    parts += panel_lines(pal, (-1.2, 1.2), (-5.0, 6.0), 0.68, count=12, seed=13)
    parts += greebles(((-1.1, 1.1), (-4.5, 5.5)), 22,
                      [pal["panel"], pal["hull2"]], seed=19, z_top=0.66)
    parts += rcs_block(pal, (0.9, 5.6, 0.10), s=0.07)
    parts += rcs_block(pal, (-0.9, 5.6, 0.10), s=0.07)
    parts += nav_lights([(3.6, -3.4, -0.10), (-3.6, -3.4, -0.10)], pal)
    return [finish(parts, "Specter", bevel=0.025)]


# ================================================================ PLAYER: PALADIN
def build_paladin():
    """SA-11 Paladin — assault gunship. Slab armour, four engines, gun pods."""
    reset_scene()
    pal = fleet_palette("paladin", (0.52, 0.50, 0.30), (1.0, 0.55, 0.14),
                        accent=(0.90, 0.88, 0.80))
    glowmat = pal["engine"]
    parts = []
    parts.append(hull_loft("hullm", [
        {"y": 9.0, "w": 0.55, "zb": -0.42, "zt": 0.40, "tf": 0.45},
        {"y": 7.0, "w": 1.05, "zb": -0.72, "zt": 0.72, "tf": 0.50},
        {"y": 4.4, "w": 1.62, "zb": -0.96, "zt": 1.02, "tf": 0.55},
        {"y": 1.4, "w": 1.94, "zb": -1.08, "zt": 1.20, "tf": 0.60},
        {"y": -1.8, "w": 2.00, "zb": -1.10, "zt": 1.18, "tf": 0.62},
        {"y": -5.0, "w": 1.86, "zb": -1.02, "zt": 1.08, "tf": 0.62},
        {"y": -8.0, "w": 1.42, "zb": -0.82, "zt": 0.86, "tf": 0.58},
    ], pal["hull"], spine=0.14))
    # dorsal armour spine + reinforced prow
    parts.append(box("spine", (1.4, 9.0, 0.44), (0, -1.0, 1.28), pal["hull2"]))
    parts.append(box("spinecap", (1.0, 4.0, 0.20), (0, 0.5, 1.52), pal["white"]))
    parts.append(box("prow", (1.3, 2.6, 1.0), (0, 8.2, 0.0), pal["hull2"], rot=(0, 45, 0)))
    parts.append(box("prowacc", (1.36, 0.7, 1.05), (0, 7.2, 0.0), pal["mark"], rot=(0, 45, 0)))
    # armoured canopy with a heavy frame
    parts.append(sphere("canopy", 1.0, (0, 3.4, 1.02), pal["glass"], scale=(0.52, 1.4, 0.40)))
    parts.append(box("canframe", (0.66, 0.24, 0.5), (0, 4.6, 0.90), pal["hull2"]))
    for ry in (2.6, 3.5):
        parts.append(box("canrib", (1.14, 0.10, 0.12), (0, ry, 1.34), pal["hull2"]))
    # stub wings carrying big gun pods
    parts += wing_pair("wing", (1.55, -2.0, -0.10), 3.0, 3.4, 1.6, 1.4, 10, 0.30, pal["hull"])
    for mir in (False, True):
        tp = wing_tip((1.55, -2.0, -0.10), 3.0, 1.4, 1.6, 10, mir)
        parts.append(cyl("pod", 0.60, 0.54, 4.2, (tp[0], tp[1] + 0.6, tp[2]), pal["hull2"], verts=16))
        parts.append(cyl("podcap", 0.64, 0.64, 0.4, (tp[0], tp[1] + 2.5, tp[2]), pal["white"], verts=16))
        for bx in (-0.22, 0.22):
            parts.append(cyl("barrel", 0.11, 0.09, 3.0, (tp[0] + bx, tp[1] + 3.6, tp[2]), pal["dark"]))
        parts.append(box("rail", (0.5, 2.2, 0.18), (tp[0], tp[1] - 1.2, tp[2] - 0.55), pal["dark"]))
        parts.append(box("glowstrip", (0.9, 0.10, 0.06), (tp[0], tp[1] - 2.2, tp[2] - 0.10), glowmat))
        parts += nav_lights([(tp[0], tp[1] - 2.6, tp[2])], pal)
    # chin turret housing
    parts.append(box("chin", (1.1, 1.8, 0.6), (0, 5.4, -0.92), pal["hull2"]))
    for bx in (-0.28, 0.28):
        parts.append(cyl("chinb", 0.10, 0.08, 2.6, (bx, 6.8, -0.92), pal["dark"]))
    # missile racks along the belly
    for sx in (1, -1):
        for i in range(3):
            parts.append(cyl("msl", 0.14, 0.12, 1.7, (sx * 0.75, -1.0 + i * 1.9, -1.12), pal["white"]))
            parts.append(cyl("mslc", 0.0, 0.14, 0.4, (sx * 0.75, -0.1 + i * 1.9, -1.12), pal["mark"]))
    # four engines in a stacked block
    for sx in (1, -1):
        for sz in (0.42, -0.42):
            parts.append(box("shroud", (0.9, 2.4, 0.8), (sx * 1.05, -7.2, sz), pal["hull2"]))
            parts += engine_nozzle_v2(f"nz{sx}{sz}", (sx * 1.05, -8.4, sz), 0.42, pal, depth=1.5)
    parts.append(box("striptop", (0.06, 5.0, 0.07), (0, -3.0, 1.50), glowmat))
    for sx in (1, -1):
        parts.append(box("stripside", (0.05, 6.0, 0.09), (sx * 1.95, -1.0, 0.20), glowmat))
    parts += panel_lines(pal, (-1.8, 1.8), (-6.0, 7.0), 1.24, count=16, seed=23)
    parts += greebles(((-1.7, 1.7), (-6.0, 6.5)), 40,
                      [pal["panel"], pal["hull2"], pal["white"]], seed=31, z_top=1.26)
    for p in [(1.6, 6.2, 0.0), (-1.6, 6.2, 0.0), (1.7, -5.6, 0.6), (-1.7, -5.6, 0.6)]:
        parts += rcs_block(pal, p, s=0.10)
    return [finish(parts, "Paladin", bevel=0.035)]


BUILDERS = {
    "capital_leviathan": build_leviathan,
    "capital_sovereign": build_sovereign,
    "capital_warden": build_warden,
    "capital_talon": build_talon,
    "ship_specter": build_specter,
    "ship_paladin": build_paladin,
}


def main():
    global EXPORT_DIR
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "/tmp/hv_fleet"
    only = set(argv[1:])
    os.makedirs(out, exist_ok=True)
    globals()["EXPORT_DIR"] = out
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        random.seed(hash(name) & 0xffff)
        objs = fn()
        tris = 0
        for o in objs:
            if o.type == 'MESH':
                o.data.calc_loop_triangles()
                tris += len(o.data.loop_triangles)
        path = os.path.join(out, name + ".glb")
        for o in bpy.context.selected_objects:
            o.select_set(False)
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                                  export_apply=True, export_yup=True,
                                  export_animations=False, export_skins=False,
                                  export_morph=False)
        print("[fleet] %-20s parts %2d  tris %6d  -> %s" % (name, len(objs), tris, path),
              flush=True)
    print("[fleet] done", flush=True)


main()
