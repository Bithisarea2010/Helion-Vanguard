"""Original Helion hero fleet, authored in meters: Blender +Y -> Godot -Z.
Run in a fresh Blender background process. Three bounded, material-batched GLBs,
one editable .blend per hull, and studio review renders. No downloaded assets.
"""
import bpy, math, json
from mathutils import Vector
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models'
EVIDENCE = ROOT / 'docs/evidence/quality-2026-09-13/after/final'
parts = []

def material(name, color, metal=.55, rough=.35, emission=0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    return m

def mesh(name, verts, faces, mat, bevel=.035):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.materials.append(mat)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    if bevel:
        b = ob.modifiers.new('Machined edge radius', 'BEVEL')
        b.width = bevel
        b.segments = 2
        bpy.ops.object.modifier_apply(modifier=b.name)
        n = ob.modifiers.new('Weighted panel normals', 'WEIGHTED_NORMAL')
        n.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=n.name)
    parts.append(ob)
    return ob

def box(name, pos, size, mat, bevel=.035):
    x,y,z = pos; a,b,c = (v/2 for v in size)
    vs = [(x+i*a,y+j*b,z+k*c) for i,j,k in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    return mesh(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat,bevel)

def plate(name, points, depth, mat, bevel=.035):
    vs=[(x,y,z-depth/2) for x,y,z in points]+[(x,y,z+depth/2) for x,y,z in points]
    n=len(points)
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,vs,faces,mat,bevel)

def loft(name, stations, mat, ox=0, oz=0):
    vs=[]
    # Octagonal cross sections make purposeful chines and planar armor breaks.
    for y,w,h,z in stations:
        vs += [(ox+x*w,y,oz+z+zz*h) for x,zz in [(-.65,-1),(.65,-1),(1,-.4),(1,.4),(.58,1),(-.58,1),(-1,.4),(-1,-.4)]]
    faces=[tuple(range(7,-1,-1)),tuple(range((len(stations)-1)*8,len(stations)*8))]
    for i in range(len(stations)-1):
        for j in range(8): faces.append((i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j))
    return mesh(name,vs,faces,mat,.045)

def cylinder(name, pos, radius, length, mat, radius_front=None, segments=24):
    x,y,z=pos; r2=radius if radius_front is None else radius_front
    vs=[]
    for yy,r in [(y-length/2,radius),(y+length/2,r2)]:
        vs += [(x+math.cos(math.tau*i/segments)*r,yy,z+math.sin(math.tau*i/segments)*r) for i in range(segments)]
    faces=[tuple(range(segments-1,-1,-1)),tuple(range(segments,segments*2))]
    faces += [(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)]
    return mesh(name,vs,faces,mat,.018)

def stencil(text, pos, size, mat):
    bpy.ops.object.text_add(location=pos)
    ob=bpy.context.object;ob.name='Permanent hull stencil'
    ob.data.body=text;ob.data.align_x='CENTER';ob.data.size=size;ob.data.extrude=.001
    ob.data.materials.append(mat)
    bpy.ops.object.convert(target='MESH');parts.append(bpy.context.object)

def build(kind):
    global parts
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    parts=[]
    heavy=kind=='aegis'; fast=kind=='peregrine'
    paint_rgb=(.90,.32,.035) if kind=='vanguard' else ((.08,.22,.34) if fast else (.62,.13,.045))
    mats={
        'paint':material(kind+'_hull',paint_rgb,.3,.39),
        'ceramic':material(kind+'_ceramic',(.68,.74,.75),.35,.33),
        'dark':material(kind+'_titanium',(.042,.055,.068),.76,.30),
        'panel':material(kind+'_graphite',(.014,.024,.034),.30,.44),
        'metal':material(kind+'_machinery',(.25,.30,.33),.85,.28),
        'glass':material(kind+'_canopy',(.015,.10,.16),.82,.12),
        'glow':material(kind+'_engine',(.12,.66,1),.15,.24,2.8),
        'amber':material(kind+'_nav_light',(.95,.25,.035),.1,.4,2),
    }
    p,c,d,pan,m,g,gl,am=[mats[k] for k in ['paint','ceramic','dark','panel','metal','glass','glow','amber']]
    length=10.8 if fast else (9.4 if heavy else 10)
    width=1.7 if heavy else (1.03 if fast else 1.3)
    loft('Primary pressure hull',[(length,.10,.12,-.08),(7.7,width*.45,.32,0),(5.0,width*.8,.55,0),(1.7,width,.75,0),(-3.8,width*1.1,.62,0),(-7.7,width*.78,.40,0)],c)
    # Dorsal saddle, inset cockpit, armored windscreen frame and pressure hatch.
    loft('Dorsal spine',[(6.1,.18,.10,.50),(3.0,.66,.40,.74),(-1.8,.62,.45,.72),(-5.8,.47,.14,.67)],d)
    loft('Faceted canopy',[(5.8,.08,.07,.67),(4.9,.40,.16,.87),(2.4,.51,.20,1.16),(1.2,.43,.16,1.02)],g)
    for y in [1.25,2.3,4.85]: box('Canopy cross frame',(0,y,1.2 if y<3 else .99),(.95,.085,.07),m,.014)
    box('Maintenance spine',(0,-3.5,.99),(.62,3.2,.13),p)
    for i in range(5):
        box('Spine vent',(0,-2.3-i*.42,1.07),(.51,.12,.035),pan,.007)
    for side in [-1,1]:
        # Nose armor is split into discrete plates with intentional dark gaps.
        for i,(front,back) in enumerate([(9.0,7.6),(7.5,6.1),(6.0,4.9)]):
            w=width*(.22+i*.16)
            plate('Nose livery',[(side*.12,front,.23+i*.12),(side*w,back,.40+i*.09),(side*.10,back,.54+i*.06)],.06,p,.025)
        box('Cockpit sill',(side*.69,2.45,.72),(.12,3.5,.12),c)
        box('Cockpit service light',(side*.755,2.1,.77),(.035,.8,.035),gl,.006)
        if fast:
            pts=[(side*.9,3.3,.0),(side*6.7,-4.9,-.25),(side*6.45,-7.6,-.27),(side*1.1,-4.8,0)]
        elif heavy:
            pts=[(side*1.15,2.9,-.15),(side*7.7,.4,-.35),(side*7.2,-6.1,-.30),(side*1.25,-6.5,-.1)]
        else:
            pts=[(side*1.0,3.0,-.05),(side*7.7,-2.6,-.15),(side*6.4,-5.7,-.17),(side*1.0,-4.2,-.05)]
        plate('Monocoque wing',pts,.38 if heavy else .25,d,.07)
        center=sum((Vector(v) for v in pts),Vector())/4
        inset=[tuple(center+(Vector(v)-center)*.90+Vector((0,0,.19 if heavy else .14))) for v in pts]
        plate('Wing ceramic armor',inset,.09,c,.025)
        # Inlaid stripe follows the wing's leading edge, not arbitrary noise.
        a=Vector(inset[0]);b=Vector(inset[1]);v=(b-a).normalized()
        stripe=[a+Vector((0,-.12,.06)),b-v*.25+Vector((0,-.12,.06)),b-v*.45+Vector((0,-.45,.06)),a+Vector((0,-.45,.06))]
        plate('Wing identification stripe',[tuple(v) for v in stripe],.024,p,.005)
        for k in range(3):
            xx=side*(2.0+k*1.20); yy=-2.4-k*.32 if not heavy else -2.0
            box('Recessed wing equipment',(xx,yy,.13),(0.65,1.3,.09),pan,.018)
            for j in range(5):box('Heat exchanger fin',(xx,yy-.5+j*.21,.205),(.56,.05,.055),m,.006)
        # Active control surfaces and a canard split give each profile a role.
        if fast:
            plate('Forward canard',[(side*.72,6.1,-.05),(side*3.6,5.0,-.25),(side*3.0,3.6,-.25),(side*.9,3.6,0)],.14,p)
        elif heavy:
            box('Armored missile rack',(side*6.0,-.6,-.8),(1.10,4.7,.85),d,.1)
            for j in [-.24,.24]:
                cylinder('Missile cell',(side*6+j,.2,-.8),.17,3.4,c)
                cylinder('Warhead',(side*6+j,2.0,-.8),.17,.4,p,0)
        else:
            plate('Split trailing flap',[(side*1.2,-4.6,.25),(side*5.0,-5.8,.30),(side*4.2,-7.3,.45),(side*1.0,-6.7,.30)],.18,p)
        # Engine pods are independent volumes, with layered nozzles and visible
        # titanium turbine rings. Broad upper nacelles keep the rear readable.
        engines=[side*2.05,side*4.20] if heavy else [side*(1.8 if fast else 2.3)]
        for ex in engines:
            ez=.15 if heavy else .1
            loft('Engine nacelle',[(2.1,.20,.28,ez),(.8,.65,.58,ez),(-4.8,.70,.57,ez),(-7.6,.54,.43,ez)],d,ox=ex)
            box('Nacelle upper armor',(ex,-2.7,ez+.57),(.87,5.8,.18),p,.085)
            box('Nacelle thermal inset',(ex,-2.45,ez+.69),(.48,2.9,.055),pan,.012)
            for j in range(9):box('Nacelle cooling vane',(ex,-1.2-j*.29,ez+.74),(.46,.075,.055),m,.008)
            cylinder('Nozzle throat',(ex,-7.55,ez),.49,1.0,m)
            cylinder('Nozzle outer rim',(ex,-8.15,ez),.65,.55,d)
            cylinder('Nozzle silver lip',(ex,-8.43,ez),.62,.10,m)
            cylinder('Recessed plasma',(ex,-8.50,ez),.48,.025,gl)
            cylinder('Turbine hub',(ex,-8.57,ez),.17,.14,pan)
            for j in range(12):
                a=math.tau*j/12
                box('Nozzle petal',(ex+math.cos(a)*.56,-8.50,ez+math.sin(a)*.56),(.09,.24,.09),m,.01)
        # Gun pods have a recessed bore and vents. Muzzle coordinates below
        # match the ShipDB definition instead of firing from empty space.
        gx=side*(5.5 if heavy else (4.8 if fast else 4.4))
        gy=1.8 if heavy else (0.0 if fast else .8)
        cylinder('Wing weapon pod',(gx,gy,-.30),.24,3.1,d)
        cylinder('Wing gun shroud',(gx,gy+1.7,-.30),.17,.65,m)
        cylinder('Wing gun bore',(gx,gy+2.04,-.30),.10,.012,pan)
        for y in [gy+.7,gy+1.0,gy+1.3]:box('Gun vent',(gx,y,-.065),(.18,.09,.025),pan,.005)
        cylinder('Nose cannon',(side*.52,7.0,-.27),.09,2.6,m)
        cylinder('Nose gun bore',(side*.52,8.32,-.27),.066,.016,pan)
        # Tall fins are tapered and canted, not flat vertical rectangles.
        fx=side*(4.2 if heavy else (1.8 if fast else 2.3))
        plate('Canted stabilizer',[(fx,-3.7,.50),(fx+side*.75,-6.0,2.30 if fast else 1.8),(fx+side*.7,-7.5,1.9),(fx,-7.5,.50)],.12,c,.025)
        box('Position beacon',(side*(6.85 if heavy else 6.3),-4.5,.22),(.20,.36,.10),am,.02)
        # Legible livery marks, panel fasteners, and maintenance hatch bolts.
        stencil('07' if kind=='vanguard' else ('12' if fast else '14'),(side*3.75,-3.4,.31),.62,pan)
        for y in [-4.8,-3.1,-1.4]:
            for x in [side*.94,side*1.16]:
                box('Deck fastener',(x,y,.68),(.075,.075,.028),m,.008)
    stencil('H E L I O N',(0,-.3,1.17),.15,c)
    # UVs are retained for later authored/baked texture work; current surfaces
    # use PBR constants and the shared game shader. Merge by material: 8 draws.
    groups={m.name:[ob for ob in parts if ob.data.materials[0]==m] for m in mats.values()}
    merged=[]
    for mat in mats.values():
        obs=groups[mat.name]
        if not obs:continue
        bpy.ops.object.select_all(action='DESELECT')
        for ob in obs:ob.select_set(True)
        bpy.context.view_layer.objects.active=obs[0]
        bpy.ops.object.join();ob=bpy.context.object;ob.name=mat.name
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=.02)
        bpy.ops.object.mode_set(mode='OBJECT');merged.append(ob)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in merged:ob.select_set(True)
    filename='ship_vanguard_mk3' if kind=='vanguard' else 'ship_'+kind
    bpy.ops.export_scene.gltf(filepath=str(OUT/(filename+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
    count=sum(sum(len(p.vertices)-2 for p in ob.data.polygons) for ob in merged)
    print('FLEET_ASSET '+json.dumps({'ship':kind,'triangles':count,'surfaces':len(merged),'bytes':(OUT/(filename+'.glb')).stat().st_size}),flush=True)
    # Studio presentation is only a review aid; game screenshots are separate.
    bpy.ops.object.camera_add(location=(22,28,24));cam=bpy.context.object
    cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO';cam.data.ortho_scale=28;bpy.context.scene.camera=cam
    for loc,power,col,size in [((6,8,18),4200,(.85,.92,1),12),((-12,4,5),2600,(1,.65,.35),10),((0,-14,8),5500,(.25,.62,1),10)]:
        bpy.ops.object.light_add(type='AREA',location=loc);li=bpy.context.object
        li.data.energy=power;li.data.color=col;li.data.shape='DISK';li.data.size=size
        li.rotation_euler=(-li.location).to_track_quat('-Z','Y').to_euler()
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32
    scene.cycles.use_denoising=True
    scene.world.color=(.035,.045,.065)
    scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(EVIDENCE/(kind+'-blender.png'))
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'blender_src/blends'/(filename+'.blend')))
    bpy.ops.render.render(write_still=True)

for variant in ['vanguard','peregrine','aegis']:
    build(variant)
