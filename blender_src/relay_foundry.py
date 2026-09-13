"""Original Helion navigation relay. Blender 5.2; meters; +Y exports to -Z.
Run: Blender --background --factory-startup --python blender_src/relay_foundry.py
No downloads. Rebuild replaces only this generator's two named output files.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/models/helion_relay.glb'
BLEND=ROOT/'blender_src/blends/helion_relay.blend'
# This program is run in a fresh background process; no user's open scene is touched.
for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
materials={}
def mat(name, rgb, metal=.65, rough=.42, emission=0):
 m=bpy.data.materials.new(name);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF')
 p.inputs['Base Color'].default_value=(*rgb,1)
 p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 if emission:
  p.inputs['Emission Color'].default_value=(*rgb,1);p.inputs['Emission Strength'].default_value=emission
 materials[name]=m;return m
dark=mat('Relay / forged titanium',(.075,.10,.13))
white=mat('Relay / ceramic armor',(.64,.71,.72),.42,.48)
copper=mat('Relay / helion brass',(.72,.29,.065),.73,.4)
cyan=mat('Relay / navigation cyan',(.10,.64,.83),.1,.32,3)
amber=mat('Relay / caution amber',(.95,.25,.025),.1,.4,2.2)
panel=mat('Relay / radiator',(.022,.040,.055),.65,.55)
parts=[]
def box(name, loc, dims, material, angle=0, bevel=.3):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=dims
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.rotation_euler.y=-angle;o.data.materials.append(material)
 if bevel:
  mod=o.modifiers.new('Machined edges','BEVEL');mod.width=bevel;mod.segments=1
  bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 parts.append(o);return o
def arc(name,r0,r1,depth,a0,a1,material,y=0,steps=3):
 verts=[];faces=[]
 for i in range(steps+1):
  a=a0+(a1-a0)*i/steps
  for r,d in [(r0,-depth/2),(r1,-depth/2),(r1,depth/2),(r0,depth/2)]: verts.append((math.cos(a)*r,y+d,math.sin(a)*r))
 for i in range(steps):
  for j in range(4): faces.append((i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j))
 faces += [(3,2,1,0),tuple(range(steps*4,steps*4+4))]
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.materials.append(material);me.update()
 o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);parts.append(o);return o
# A 180 m clear aperture, twelve armored modules, exposed machinery in seams.
for i in range(12):
 a=math.tau*i/12;half=math.pi/12
 arc('Pressure frame',92,111,16,a-half,a+half,dark)
 arc('Segment ceramic',97,109,18,a-half+.035,a+half-.035,white)
 arc('Navigation inset',91,93,1.2,a-half+.055,a+half-.055,cyan,y=-9.4)
 arc('Aft navigation inset',91,93,1.2,a-half+.055,a+half-.055,cyan,y=9.4)
 arc('Brass outer band',108,112,19,a-half+.12,a+half-.12,copper)
 # Four ribs and recessed radiator slats per segment, sharing six materials.
 for j in range(4):
  aa=a+(j-1.5)*.065
  box('Cooling fin',(math.cos(aa)*116,0,math.sin(aa)*116),(5,23,1.2),dark,aa,.2)
 for aa in (a-half+.048,a+half-.048):
  box('Coupler',(math.cos(aa)*102,-11,math.sin(aa)*102),(9,4,3.4),panel,aa,.3)
  box('Status',(math.cos(aa)*98,-13.2,math.sin(aa)*98),(2,.6,1.3),amber,aa,.05)
# Four navigation pylons outside the opening. They frame the silhouette clearly.
for i in range(4):
 a=math.pi/4+i*math.pi/2
 box('Pylon spine',(math.cos(a)*131,0,math.sin(a)*131),(52,10,9),dark,a,.7)
 box('Pylon cap',(math.cos(a)*151,-1,math.sin(a)*151),(13,17,19),white,a,.65)
 box('Pylon beacon',(math.cos(a)*153,-10,math.sin(a)*153),(8,1,8),cyan,a,.15)
# Lower service module, offset from the flight path.
box('Service habitat',(0,5,-131),(53,26,25),white,0,1)
box('Habitat shield',(0,-10,-128),(61,4,12),dark,0,.7)
for x in range(-20,21,5): box('Habitat window',(x,-12.3,-126),(3.1,.6,2.2),cyan,0,.08)
for side in (-1,1):
 box('Radiator arm',(side*65,7,-129),(76,5,5),copper,0,.35)
 box('Radiator panel',(side*83,7,-142),(57,3,32),panel,0,.35)
 for x in range(6): box('Radiator trace',(side*(59+x*9),5.2,-142),(1,.4,29),copper,0,0)
# Raised, original lettering, converted to geometry. No external font required.
def label(text,loc,size):
 bpy.ops.object.text_add(location=loc,rotation=(math.pi/2,0,0));o=bpy.context.object;o.name='Hull stencil'
 o.data.body=text;o.data.align_x='CENTER';o.data.size=size;o.data.extrude=.012;o.data.materials.append(dark)
 bpy.ops.object.convert(target='MESH');parts.append(bpy.context.object)
label('HELION  /  07',(0,-9.6,98),5.2)
label('TRANSIT RELAY',(0,-10,-134),4)
# Merge by material to cap renderer surfaces/draw calls. Export only those meshes.
merged=[]
groups={m.name:[o for o in parts if o.data.materials and o.data.materials[0]==m] for m in materials.values()}
for m in materials.values():
 obs=groups[m.name]
 if not obs:continue
 bpy.ops.object.select_all(action='DESELECT')
 for o in obs:o.select_set(True)
 bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();o=bpy.context.object;o.name=m.name.replace(' / ','_');merged.append(o)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for poly in o.data.polygons:poly.use_smooth=False
bpy.ops.object.select_all(action='DESELECT')
for o in merged:o.select_set(True)
OUT.parent.mkdir(parents=True,exist_ok=True);BLEND.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(OUT),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in merged)
# Studio view for asset review; excluded from GLB, preserved in Blender source.
bpy.ops.object.camera_add(location=(230,-365,180));cam=bpy.context.object
cam.rotation_euler=(Vector((0,0,-8))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=365;bpy.context.scene.camera=cam
for loc,power,color,size in [((130,-210,280),450000,(.76,.87,1),200),((-170,-100,50),340000,(1,.56,.25),150),((30,140,180),650000,(.20,.65,1),160)]:
 bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=power;light.data.color=color;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=1200;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.world.color=(.055,.055,.055);scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(ROOT/'docs/evidence/quality-2026-09-13/after/relay_blender.png')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps({'asset':str(OUT),'blend':str(BLEND),'triangles':triangles,'surfaces':len(merged),'clear_aperture_m':180}))
bpy.ops.render.render(write_still=True)
