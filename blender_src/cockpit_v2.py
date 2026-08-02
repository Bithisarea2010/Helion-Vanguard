# Helion Vanguard — cockpit v2: flight-sim style. Yoke, throttle, gauges with
# animatable needles (named nodes driven from Godot). Eye at origin, nose +Y.
import bpy, bmesh, math
from mathutils import Vector, Matrix

def _lbox(name, size, offset, material):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts, vec=size)
    bmesh.ops.translate(bm, verts=bm.verts, vec=offset)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o

def _lcyl(name, r1, r2, depth, offset, material, axis='Y', segs=20):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    if axis == 'Y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, 'X'))
    elif axis == 'X':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'Y'))
    bmesh.ops.translate(bm, verts=bm.verts, vec=offset)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o

def build_cockpit_v2():
    soft_reset()
    dk = mat("cp_dark", (0.045, 0.05, 0.06), 0.55, 0.6)
    pn = mat("cp_panel", (0.10, 0.11, 0.13), 0.65, 0.5)
    fr = mat("cp_frame", (0.07, 0.075, 0.085), 0.75, 0.42)
    ac = mat("cp_accent", (0.8, 0.35, 0.06), 0.5, 0.4)
    acg = mat("cp_glowamber", (0.25, 0.1, 0.01), 0.2, 0.4, (1.0, 0.5, 0.1), 0.45)
    sc = mat("cp_screen", (0.008, 0.02, 0.03), 0.2, 0.25, (0.12, 0.6, 0.75), 1.5)
    scr = mat("cp_screen_red", (0.03, 0.008, 0.008), 0.2, 0.25, (0.85, 0.2, 0.1), 1.1)
    wl_r = mat("cp_lamp_r", (0.2, 0.02, 0.02), 0.2, 0.4, (1.0, 0.12, 0.08), 3.0)
    wl_a = mat("cp_lamp_a", (0.2, 0.12, 0.02), 0.2, 0.4, (1.0, 0.65, 0.1), 2.4)
    gm = mat("cp_gauge_face", (0.012, 0.015, 0.02), 0.3, 0.4, (0.1, 0.4, 0.5), 0.7)
    nd = mat("cp_needle", (0.9, 0.4, 0.05), 0.3, 0.3, (1.0, 0.5, 0.1), 2.5)

    body = []
    # ---- main dash: lower slab + vertical instrument wall
    body.append(box("dashL", (1.6, 0.5, 0.3), (0, 0.80, -0.57), pn, rot=(-14, 0, 0)))
    body.append(box("instwall", (1.34, 0.06, 0.42), (0, 0.66, -0.33), dk, rot=(-6, 0, 0)))
    body.append(box("dashtop", (1.45, 0.3, 0.07), (0, 0.62, -0.125), fr, rot=(-22, 0, 0)))
    # glare shield lip with amber underglow strip
    body.append(box("glarelip", (1.4, 0.16, 0.045), (0, 0.56, -0.095), dk, rot=(-24, 0, 0)))
    body.append(box("uglow", (1.2, 0.02, 0.02), (0, 0.56, -0.15), acg, rot=(-24, 0, 0)))
    # ---- MFDs: bezels + screens + button rows
    for mx, mmat in ((-0.47, sc), (0.0, sc), (0.47, scr)):
        body.append(box("bez", (0.4, 0.05, 0.32), (mx, 0.655, -0.34), fr, rot=(-6, 0, 0)))
        body.append(box("scrn", (0.34, 0.02, 0.26), (mx, 0.64, -0.34), mmat, rot=(-6, 0, 0)))
        for bi in range(5):
            body.append(box("btn", (0.03, 0.025, 0.018),
                             (mx - 0.12 + bi * 0.06, 0.665, -0.515), acg if bi == 2 else dk, rot=(-6, 0, 0)))
    # ---- warning lamp strip on the coaming
    for li in range(6):
        body.append(box("lamp", (0.045, 0.02, 0.025),
                         (-0.30 + li * 0.12, 0.585, -0.08), wl_r if li % 3 == 0 else wl_a, rot=(-24, 0, 0)))
    # ---- gauge cluster: vertical strip above MFD row (3 round dials)
    gauge_pos = [(-0.36, "Needle_spd"), (0.0, "Needle_pwr"), (0.36, "Needle_heat")]
    needles = []
    for gx, nname in gauge_pos:
        body.append(_lcyl("gbez", 0.06, 0.06, 0.014, (gx, 0.615, -0.155), fr))
        body.append(_lcyl("gface", 0.052, 0.052, 0.01, (gx, 0.608, -0.155), gm))
        for tk in range(8):  # tick marks
            a = math.radians(-210 + tk * 30)
            body.append(box("tick", (0.006, 0.006, 0.014),
                             (gx + math.cos(a) * 0.042, 0.603, -0.155 + math.sin(a) * 0.042), ac))
        n = _lbox(nname, (0.008, 0.006, 0.046), (0, -0.004, 0.021), nd)
        n.location = (gx, 0.600, -0.155)
        needles.append(n)
    # ---- center console between knees
    body.append(box("ccon", (0.34, 0.7, 0.2), (0, 0.35, -0.72), pn, rot=(-8, 0, 0)))
    body.append(box("cconk", (0.28, 0.3, 0.03), (0, 0.3, -0.60), dk, rot=(-8, 0, 0)))
    for ki in range(6):
        body.append(box("knob", (0.03, 0.03, 0.03), (-0.1 + (ki % 3) * 0.1, 0.28 + (ki // 3) * 0.14, -0.585), ac if ki == 4 else dk, rot=(-8, 0, 0)))
    # ---- side consoles + switch banks
    for sx in (1, -1):
        body.append(box("scon", (0.36, 1.15, 0.16), (sx * 0.60, -0.05, -0.56), pn, rot=(0, sx * -7, sx * 4)))
        body.append(box("scont", (0.3, 0.5, 0.02), (sx * 0.58, 0.12, -0.47), dk, rot=(0, sx * -7, sx * 4)))
        for swi in range(8):
            body.append(box("sw", (0.02, 0.04, 0.03),
                             (sx * (0.48 + 0.06 * (swi % 3)), 0.02 + (swi // 3) * 0.14, -0.46),
                             wl_a if swi == 5 else dk))
    # ---- WINDSHIELD: three angled glass panes + thin frame struts
    gl = mat("cp_glass", (0.45, 0.6, 0.75), 0.15, 0.06, alpha=0.08)
    for sx in (1, -1):
        body.append(box("wsStrut", (0.035, 0.02, 0.62), (sx * 0.53, 0.86, 0.24), fr, rot=(-38, sx * -12, 0)))
    # ---- coaming rim + A-pillars (slimmer than v1) + bows
    body.append(box("coamL", (0.08, 1.5, 0.09), (-0.74, 0.1, -0.26), fr, rot=(0, 0, 6)))
    body.append(box("coamR", (0.08, 1.5, 0.09), (0.74, 0.1, -0.26), fr, rot=(0, 0, -6)))
    body.append(box("coamF", (1.5, 0.09, 0.09), (0, 0.98, -0.28), fr, rot=(-10, 0, 0)))
    body.append(box("pillL", (0.05, 0.95, 0.06), (-0.7, 0.78, 0.24), fr, rot=(38, 0, 14)))
    body.append(box("pillR", (0.05, 0.95, 0.06), (0.7, 0.78, 0.24), fr, rot=(38, 0, -14)))
    body.append(box("bow", (1.52, 0.07, 0.06), (0, 0.28, 0.6), fr, rot=(-14, 0, 0)))
    body.append(box("bow2", (1.46, 0.07, 0.06), (0, -0.55, 0.64), fr, rot=(6, 0, 0)))
    # ---- shell: floor, nose, seat
    body.append(box("floor", (1.5, 2.0, 0.08), (0, 0.0, -0.8), dk))
    body.append(box("nose", (1.7, 0.75, 0.6), (0, 1.3, -0.55), pn, rot=(-24, 0, 0)))
    body.append(box("seatb", (0.6, 0.12, 0.9), (0, -0.88, -0.15), pn, rot=(8, 0, 0)))
    body.append(box("seath", (0.34, 0.1, 0.3), (0, -0.93, 0.35), dk, rot=(8, 0, 0)))
    cock = finish(body, "Cockpit", bevel=0.01, smooth_angle=30)

    # ---- YOKE (separate, animated from Godot): column pivot at base
    col = _lbox("yokecol", (0.07, 0.08, 0.36), (0, 0.03, 0.18), fr)
    yoke = col
    yoke.name = "Yoke"
    yoke.location = (0, 0.46, -0.70)
    yoke.rotation_euler = (math.radians(14), 0, 0)
    # wheel (child): hub + crossbar + grips, pivot at column top
    hub = _lbox("hub", (0.15, 0.055, 0.1), (0, -0.01, 0), dk)
    bar = _lbox("bar", (0.44, 0.045, 0.05), (0, -0.01, 0.01), fr)
    gripL = _lbox("gripL", (0.055, 0.05, 0.17), (-0.235, -0.01, 0.09), ac)
    gripR = _lbox("gripR", (0.055, 0.05, 0.17), (0.235, -0.01, 0.09), ac)
    spokeL = _lbox("spkL", (0.12, 0.04, 0.04), (-0.10, -0.01, 0.045), dk)
    spokeR = _lbox("spkR", (0.12, 0.04, 0.04), (0.10, -0.01, 0.045), dk)
    padc = _lbox("pad", (0.09, 0.03, 0.06), (0, -0.035, 0.0), wl_a)
    wheel = finish([hub, bar, gripL, gripR, spokeL, spokeR, padc], "YokeWheel", bevel=0.008)
    wheel.parent = yoke
    wheel.location = (0, -0.02, 0.34)
    # ---- THROTTLE (separate): hinge pivot on left console
    tarm = _lbox("tarm", (0.045, 0.05, 0.24), (0, 0.02, 0.12), fr)
    tknob = _lbox("tknob", (0.10, 0.075, 0.07), (0, 0.02, 0.27), ac)
    thr = finish([tarm, tknob], "Throttle", bevel=0.008)
    thr.location = (-0.56, 0.14, -0.5)
    thr.rotation_euler = (math.radians(-20), 0, 0)
    # throttle slot base joins the static body visually
    slot = box("tslot", (0.16, 0.34, 0.05), (-0.56, 0.16, -0.5), dk)

    return [cock, slot, yoke, wheel, thr] + needles

print("cockpit_v2 loaded")
