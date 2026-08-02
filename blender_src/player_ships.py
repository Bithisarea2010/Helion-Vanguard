# Helion Vanguard — player ship recipes. Requires shipgen.py exec'd first.
import bpy, math, random

def build_vanguard():
    """SF-7 Vanguard v2 — hero assault fighter. Dense hard-surface detail,
    glowing accent strips, quad engines, panel seams (reference-style)."""
    reset_scene()
    pal = palette("vanguard", (0.85, 0.36, 0.045), (0.25, 0.65, 1.0))
    glowmat = pal["engine"]
    parts = []
    hull = hull_loft("hullm", [
        {"y": 8.4, "w": 0.08, "zb": -0.03, "zt": 0.08},
        {"y": 7.2, "w": 0.26, "zb": -0.14, "zt": 0.22, "tf": 0.38},
        {"y": 6.2, "w": 0.42, "zb": -0.24, "zt": 0.34, "tf": 0.4},
        {"y": 4.8, "w": 0.66, "zb": -0.36, "zt": 0.55, "tf": 0.46},
        {"y": 3.6, "w": 0.85, "zb": -0.46, "zt": 0.72, "tf": 0.5},
        {"y": 2.2, "w": 1.02, "zb": -0.52, "zt": 0.86, "tf": 0.53},
        {"y": 1.0, "w": 1.15, "zb": -0.56, "zt": 0.96, "tf": 0.55},
        {"y": -0.4, "w": 1.24, "zb": -0.58, "zt": 0.9, "tf": 0.58},
        {"y": -1.6, "w": 1.30, "zb": -0.60, "zt": 0.82, "tf": 0.6},
        {"y": -3.1, "w": 1.27, "zb": -0.57, "zt": 0.76, "tf": 0.6},
        {"y": -4.6, "w": 1.22, "zb": -0.54, "zt": 0.70, "tf": 0.6},
        {"y": -6.1, "w": 1.05, "zb": -0.46, "zt": 0.6, "tf": 0.58},
        {"y": -7.6, "w": 0.85, "zb": -0.38, "zt": 0.48, "tf": 0.55},
    ], pal["hull"], spine=0.05)
    parts.append(hull)
    # dark spine插 insert + dorsal hump (two-tone like the reference)
    parts.append(box("spinehump", (0.72, 5.4, 0.3), (0, -1.2, 0.92), pal["hull2"]))
    parts.append(box("spinecap", (0.5, 2.6, 0.16), (0, -0.6, 1.06), pal["panel"]))
    # glowing accent strips along the flanks + spine (bloom feeds on these)
    for sx in (1, -1):
        parts.append(box("strip", (0.05, 6.5, 0.08), (sx * 1.18, -0.8, 0.15), glowmat))
        parts.append(box("strip2", (0.05, 2.6, 0.06), (sx * 0.75, 4.2, 0.28), glowmat))
    parts.append(box("stripT", (0.06, 3.6, 0.05), (0, -3.2, 1.12), glowmat))
    # white belly strake + nose chevron accents
    parts.append(box("strake", (0.7, 5.0, 0.18), (0, 1.0, -0.58), pal["white"]))
    parts.append(box("noseacc", (0.34, 2.2, 0.3), (0, 6.1, 0.02), pal["white"]))
    parts.append(box("nosechv", (0.6, 0.7, 0.26), (0, 5.2, 0.1), pal["hull2"], rot=(0, 0, 45)))
    # canopy: tinted glass + frame ribs
    parts.append(sphere("canopy", 1.0, (0, 2.9, 0.78), pal["glass"], scale=(0.5, 1.55, 0.42)))
    parts.append(box("canframe", (0.56, 0.16, 0.42), (0, 4.05, 0.62), pal["hull2"]))
    for ry in (2.2, 3.0):
        parts.append(box("canrib", (1.02, 0.07, 0.1), (0, ry, 1.02), pal["hull2"]))
    # lower big wings + upper wings
    parts += wing_pair("wingL", (1.05, -2.2, -0.18), 3.5, 2.7, 0.95, 1.9, 16, 0.16, pal["hull"])
    parts += wing_pair("wingU", (0.85, -3.6, 0.42), 2.2, 1.7, 0.6, 1.3, -27, 0.13, pal["white"])
    parts.append(leading_edge(pal, (1.05, -2.2, -0.18), 3.5, 1.9, 16, 0.16))
    parts.append(leading_edge(pal, (1.05, -2.2, -0.18), 3.5, 1.9, 16, 0.16, mirrored=True))
    # wing glow strips (underside accents like the reference art)
    for mir in (False, True):
        tp = wing_tip((1.05, -2.2, -0.18), 3.5, 1.9, 0.95, 16, mir)
        mid = ((tp[0]) * 0.6, tp[1] + 1.1, tp[2] * 0.6 - 0.12)
        parts.append(box("wglow", (1.3, 0.09, 0.05), mid, glowmat, rot=(0, -16 if not mir else 16, 0)))
        parts.append(cyl("pod", 0.17, 0.15, 2.5, (tp[0], tp[1] + 0.5, tp[2]), pal["hull2"]))
        parts.append(cyl("podrim", 0.19, 0.19, 0.25, (tp[0], tp[1] + 1.6, tp[2]), pal["white"]))
        parts.append(cyl("barrel", 0.05, 0.05, 1.9, (tp[0], tp[1] + 2.5, tp[2]), pal["dark"]))
        parts.append(sphere("navw", 0.07, (tp[0], tp[1] - 0.6, tp[2]), pal["light"], sub=1))
    # nose cannons w/ muzzle brakes
    for sx in (1, -1):
        parts.append(cyl("ncan", 0.07, 0.05, 2.0, (sx * 0.42, 6.6, -0.12), pal["dark"]))
        parts.append(cyl("nbrk", 0.09, 0.07, 0.3, (sx * 0.42, 7.5, -0.12), pal["panel"]))
    # intakes with dark inner lip
    for sx in (1, -1):
        parts.append(box("intake", (0.5, 2.2, 0.55), (sx * 1.28, 0.4, -0.05), pal["hull2"], rot=(0, 0, sx * -4)))
        parts.append(box("intakelip", (0.54, 0.3, 0.6), (sx * 1.30, 1.5, -0.05), pal["dark"], rot=(0, 0, sx * -4)))
    # QUAD engines: two big + two small cans, detailed nozzles
    for sx in (1, -1):
        parts.append(cyl("epod", 0.52, 0.46, 3.2, (sx * 0.8, -6.8, 0.02), pal["hull2"]))
        parts.append(cyl("epodrib", 0.55, 0.55, 0.3, (sx * 0.8, -6.0, 0.02), pal["panel"]))
        parts += engine_nozzle_v2("noz", (sx * 0.8, -8.5, 0.02), 0.46, pal)
        parts.append(cyl("epodS", 0.3, 0.27, 2.0, (sx * 1.45, -6.2, -0.28), pal["hull2"]))
        parts += engine_nozzle_v2("nozS", (sx * 1.45, -7.3, -0.28), 0.26, pal, depth=0.9)
    # detail kit: panel seams, RCS clusters, aerials, greebles
    parts += panel_lines(pal, (-0.95, 0.95), (-6.0, 3.0), 0.86, count=14, seed=11)
    parts += rcs_block(pal, (0.35, 7.0, 0.14)) + rcs_block(pal, (-0.35, 7.0, 0.14))
    parts += rcs_block(pal, (1.15, -5.6, 0.6), 0.08) + rcs_block(pal, (-1.15, -5.6, 0.6), 0.08)
    parts += aerials(pal, [((0.2, -5.0, 1.35), 1.0), ((-0.35, -5.6, 1.2), 0.7)])
    parts += greebles(((-0.85, 0.85), (-6.0, 0.0)), 16, [pal["panel"], pal["hull2"], pal["white"]], seed=11, z_top=0.78)
    parts += nav_lights([(0, -7.9, 0.6)], pal)
    ship = finish(parts, "ShipVanguard", bevel=0.035)
    return ship

def build_wasp():
    """SF-3 Wasp — dart interceptor. Needle nose, canards, single big engine."""
    reset_scene()
    pal = palette("wasp", (0.86, 0.58, 0.12), (0.35, 0.85, 1.0))
    parts = []
    hull = hull_loft("hullm", [
        {"y": 6.8, "w": 0.07, "zb": -0.03, "zt": 0.07},
        {"y": 5.0, "w": 0.28, "zb": -0.16, "zt": 0.22, "tf": 0.35},
        {"y": 2.6, "w": 0.62, "zb": -0.34, "zt": 0.52, "tf": 0.45},
        {"y": 0.2, "w": 0.85, "zb": -0.42, "zt": 0.66, "tf": 0.5},
        {"y": -2.4, "w": 0.78, "zb": -0.4, "zt": 0.58, "tf": 0.55},
        {"y": -5.2, "w": 0.55, "zb": -0.32, "zt": 0.42, "tf": 0.5},
    ], pal["hull"], spine=0.04)
    parts.append(hull)
    parts.append(sphere("canopy", 1.0, (0, 1.7, 0.55), pal["glass"], scale=(0.42, 1.3, 0.36)))
    parts.append(box("noseacc", (0.22, 1.8, 0.2), (0, 4.9, 0.0), pal["white"]))
    # canards
    parts += wing_pair("canard", (0.55, 3.2, 0.0), 1.3, 0.9, 0.35, 0.7, -6, 0.09, pal["white"])
    # main delta wings far back
    parts += wing_pair("wing", (0.7, -2.2, -0.05), 3.2, 2.9, 0.6, 2.6, 8, 0.13, pal["hull"])
    # vertical tails
    for sx in (1, -1):
        parts.append(box("vtail", (0.07, 1.5, 1.1), (sx * 0.5, -4.6, 0.75), pal["hull2"], rot=(12, sx * -20, 0)))
    # wingtip guns
    for mir in (False, True):
        tp = wing_tip((0.7, -2.2, -0.05), 3.2, 2.6, 0.6, 8, mir)
        parts.append(cyl("barrel", 0.045, 0.045, 1.6, (tp[0], tp[1] + 1.4, tp[2]), pal["dark"]))
        parts.append(sphere("navw", 0.06, (tp[0], tp[1] - 0.4, tp[2]), pal["light"], sub=1))
    # big single engine
    parts.append(cyl("epod", 0.62, 0.5, 2.6, (0, -5.4, 0.05), pal["hull2"]))
    parts += engine_nozzle_v2("noz", (0, -6.8, 0.05), 0.5, pal)
    for sx in (1, -1):  # tiny aux thrusters
        parts += engine_nozzle_v2("nozaux", (sx * 0.55, -5.9, -0.12), 0.16, pal, depth=0.6)
    parts += greebles(((-0.6, 0.6), (-4.0, -0.5)), 9, [pal["panel"], pal["hull2"]], seed=5, z_top=0.55)
    return finish(parts, "ShipWasp", bevel=0.03)

def build_hammer():
    """SG-9 Hammer — heavy gunship. Broad armored slab, quad engines, chin guns."""
    reset_scene()
    pal = palette("hammer", (0.30, 0.34, 0.38), (1.0, 0.45, 0.15), accent=(0.75, 0.2, 0.1))
    parts = []
    hull = hull_loft("hullm", [
        {"y": 8.5, "w": 0.5, "zb": -0.3, "zt": 0.4, "tf": 0.5},
        {"y": 6.0, "w": 1.3, "zb": -0.7, "zt": 0.9, "tf": 0.6},
        {"y": 2.5, "w": 2.0, "zb": -0.95, "zt": 1.25, "tf": 0.65},
        {"y": -1.5, "w": 2.2, "zb": -1.0, "zt": 1.3, "tf": 0.7},
        {"y": -5.5, "w": 2.0, "zb": -0.9, "zt": 1.1, "tf": 0.7},
        {"y": -8.8, "w": 1.5, "zb": -0.7, "zt": 0.85, "tf": 0.6},
    ], pal["hull"], spine=0.0)
    parts.append(hull)
    parts.append(sphere("canopy", 1.0, (0, 4.6, 0.75), pal["glass"], scale=(0.75, 1.6, 0.5)))
    # armored side sponsons
    for sx in (1, -1):
        parts.append(box("sponson", (1.0, 7.0, 1.4), (sx * 2.4, -1.0, 0.0), pal["hull2"]))
        parts.append(box("sponson_tip", (0.9, 1.6, 1.2), (sx * 2.4, 3.2, 0.0), pal["white"]))
        # sponson heavy cannon
        parts.append(cyl("scan", 0.14, 0.11, 3.6, (sx * 2.4, 4.6, 0.15), pal["dark"]))
        parts.append(cyl("scan2", 0.14, 0.11, 3.6, (sx * 2.4, 4.6, -0.25), pal["dark"]))
    # chin turret ball + twin barrels
    parts.append(sphere("chin", 0.55, (0, 4.5, -0.85), pal["dark"], sub=2))
    for sx in (1, -1):
        parts.append(cyl("chinb", 0.08, 0.06, 2.4, (sx * 0.2, 5.6, -0.9), pal["dark"]))
    # stub wings w/ pylons
    parts += wing_pair("wing", (2.6, -4.0, 0.1), 2.2, 2.0, 1.0, 0.9, 6, 0.22, pal["hull"])
    for mir in (False, True):
        tp = wing_tip((2.6, -4.0, 0.1), 2.2, 0.9, 1.0, 6, mir)
        parts.append(box("pylon", (0.18, 1.6, 0.5), (tp[0], tp[1], tp[2] - 0.3), pal["hull2"]))
        parts.append(sphere("navw", 0.08, (tp[0], tp[1] - 0.9, tp[2]), pal["light"], sub=1))
    # quad engines
    for sx, sz in ((1, 0.45), (-1, 0.45), (1, -0.45), (-1, -0.45)):
        parts.append(cyl("epod", 0.42, 0.38, 2.4, (sx * 1.15, -8.6, sz), pal["hull2"]))
        parts += engine_nozzle_v2("noz", (sx * 1.15, -9.9, sz), 0.36, pal, depth=0.9)
    # heavy top armor plates
    parts += greebles(((-1.7, 1.7), (-7.0, 1.5)), 22, [pal["panel"], pal["hull2"], pal["white"]], seed=23, z_top=1.15)
    parts += nav_lights([(0, 8.3, 0.35)], pal)
    return finish(parts, "ShipHammer", bevel=0.05)

def build_raptor():
    """SM-5 Raptor — missile strike craft. Chined stealth hull, canted tails, racks."""
    reset_scene()
    pal = palette("raptor", (0.13, 0.38, 0.42), (0.55, 0.35, 1.0))
    parts = []
    hull = hull_loft("hullm", [
        {"y": 7.6, "w": 0.14, "zb": -0.05, "zt": 0.09},
        {"y": 5.2, "w": 0.6, "zb": -0.22, "zt": 0.3, "tf": 0.9, "bf": 0.85},
        {"y": 2.4, "w": 1.15, "zb": -0.4, "zt": 0.58, "tf": 0.88, "bf": 0.8},
        {"y": -0.6, "w": 1.45, "zb": -0.48, "zt": 0.7, "tf": 0.85, "bf": 0.8},
        {"y": -3.8, "w": 1.3, "zb": -0.44, "zt": 0.6, "tf": 0.8},
        {"y": -6.8, "w": 0.9, "zb": -0.34, "zt": 0.44, "tf": 0.7},
    ], pal["hull"], spine=0.0)
    parts.append(hull)
    parts.append(sphere("canopy", 1.0, (0, 2.6, 0.62), pal["glass"], scale=(0.48, 1.5, 0.34)))
    parts.append(box("noseacc", (0.5, 1.4, 0.16), (0, 5.9, 0.12), pal["white"]))
    # main wings
    parts += wing_pair("wing", (1.3, -1.6, -0.1), 3.0, 2.4, 0.8, 2.2, 10, 0.14, pal["hull"])
    # canted twin tails
    for sx in (1, -1):
        parts.append(box("vtail", (0.08, 1.8, 1.3), (sx * 0.85, -5.6, 0.8), pal["hull2"], rot=(14, sx * -35, 0)))
    # missile racks under wings: pylon + 3 tubes each
    for mir in (False, True):
        tp = wing_tip((1.3, -1.6, -0.1), 3.0, 2.2, 0.8, 10, mir)
        px = tp[0] * 0.72
        pz = tp[2] * 0.72 - 0.35
        parts.append(box("pylon", (0.14, 1.9, 0.4), (px, tp[1] + 0.3, pz + 0.15), pal["hull2"]))
        for k in range(3):
            off = (k - 1) * 0.26
            parts.append(cyl("mtube", 0.11, 0.11, 2.1, (px + off, tp[1] + 0.3, pz - 0.12), pal["panel"]))
            parts.append(cyl("mtip", 0.1, 0.02, 0.3, (px + off, tp[1] + 1.5, pz - 0.12), pal["white"]))
    # nose gun
    parts.append(cyl("ncan", 0.08, 0.06, 2.2, (0.0, 6.7, -0.14), pal["dark"]))
    # twin engines close-set
    for sx in (1, -1):
        parts.append(cyl("epod", 0.44, 0.4, 2.6, (sx * 0.55, -6.4, 0.04), pal["hull2"]))
        parts += engine_nozzle_v2("noz", (sx * 0.55, -7.8, 0.04), 0.38, pal)
    parts += greebles(((-1.0, 1.0), (-5.0, 0.5)), 12, [pal["panel"], pal["hull2"]], seed=31, z_top=0.6)
    return finish(parts, "ShipRaptor", bevel=0.032)

def build_all_players(export_dir, blend_dir):
    import os
    global EXPORT_DIR
    EXPORT_DIR = export_dir
    results = []
    for fn, name in [(build_vanguard, "ship_vanguard"), (build_wasp, "ship_wasp"),
                     (build_hammer, "ship_hammer"), (build_raptor, "ship_raptor")]:
        ship = fn()
        globals()["EXPORT_DIR"] = export_dir
        path = export_glb([ship], name + ".glb")
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(blend_dir, name + ".blend"))
        results.append(path)
    return results

print("player_ships loaded")
