"""Original Helion survey suit. Blender background: --python this_file -- /absolute/project.
No external art. Z-up / +Y-forward source becomes Y-up / -Z-forward glTF.
"""
import bpy, math, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(sys.argv[sys.argv.index('--')+1])
scene=bpy.data.scenes.new('HelionSurveySuit'); bpy.context.window.scene=scene

def mat(name,color,metal=0.0,rough=.5,emit=0):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
 p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
 if emit: p.inputs['Emission Color'].default_value=(*color,1); p.inputs['Emission Strength'].default_value=emit
 return m
ivory=mat('Suit ceramic',(.56,.63,.67),.22,.48)
dark=mat('Pressure fabric',(.025,.04,.052),.05,.86)
orange=mat('Vanguard rescue orange',(.75,.16,.025),.12,.45)
visor=mat('Visor gold coating',(.38,.19,.042),.94,.14)
light=mat('Suit telemetry',(.04,.72,.88),.3,.3,2.3)
steel=mat('Titanium fittings',(.17,.23,.27),.8,.32)

def empty(name,pos=(0,0,0)):
 o=bpy.data.objects.new(name,None); scene.collection.objects.link(o); o.location=pos; return o

def shape(name,pos,size,material,parent=None,kind='box',bevel=.04):
 if kind=='sphere': bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=pos)
 else: bpy.ops.mesh.primitive_cube_add(size=1,location=pos)
 o=bpy.context.object; o.name=name; o.scale=size if kind=='box' else tuple(v*.5 for v in size)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if kind=='box' and bevel:
  mod=o.modifiers.new('Machined edges','BEVEL'); mod.width=bevel; mod.segments=3
  bpy.ops.object.modifier_apply(modifier=mod.name)
 if kind=='sphere':
  for face in o.data.polygons: face.use_smooth=True
 o.data.materials.append(material)
 if parent: o.parent=parent
 return o
# Objects under each joint use local coordinates; the mesh origin is the joint pivot.
body=empty('Torso')
shape('Pressure torso',(0,0,1.15),(.49,.31,.65),dark,body,kind='sphere')
shape('Ceramic chest',(0,.08,1.29),(.48,.28,.40),ivory,body,bevel=.09)
shape('Belt',(0,0,.91),(.48,.33,.12),steel,body)
shape('Orange shoulder yoke',(0,.035,1.46),(.52,.31,.11),orange,body)
shape('Mission computer',(.03,.237,1.30),(.20,.065,.18),steel,body)
for i in range(3): shape('Telemetry strip',(0.03,.273,1.34-i*.045),(.13,.015,.012),light,body,bevel=.003)
shape('Life support',(0,-.25,1.24),(.38,.23,.54),ivory,body,bevel=.06)
for x in [-.13,.13]:
 shape('Oxygen vessel',(x,-.30,1.23),(.15,.17,.44),steel,body,kind='sphere')
 shape('Tank end band',(x,-.39,1.15),(.13,.04,.07),orange,body,bevel=.014)
shape('Neck collar',(0,0,1.51),(.31,.30,.095),steel,body,kind='sphere')
shape('Helmet',(0,0,1.70),(.37,.38,.40),ivory,body,kind='sphere')
shape('Visor',(0,.136,1.715),(.325,.18,.24),visor,body,kind='sphere')
for x in [-.197,.197]:
 shape('Helmet comms',(x,0,1.70),(.055,.15,.17),steel,body,kind='sphere')
 shape('Lamp',(x,.06,1.78),(.045,.07,.04),light,body,bevel=.009)
for side in [-1,1]:
 leg=empty('LeftLeg' if side<0 else 'RightLeg',(side*.14,0,.91))
 shape('Hip joint',(0,0,-.045),(.23,.26,.21),dark,leg,kind='sphere')
 shape('Thigh plate',(0,.018,-.24),(.22,.26,.38),ivory,leg,kind='sphere')
 shape('Knee joint',(0,0,-.43),(.185,.22,.15),dark,leg,kind='sphere')
 shape('Knee cap',(0,.108,-.43),(.19,.08,.17),steel,leg)
 shape('Shin shell',(0,0,-.62),(.19,.23,.31),ivory,leg,kind='sphere')
 shape('Shin stripe',(0,.12,-.61),(.07,.022,.19),orange,leg,bevel=.008)
 shape('Boot',(0,.05,-.82),(.235,.37,.18),dark,leg)
 shape('Boot sole',(0,.05,-.89),(.24,.38,.047),steel,leg,bevel=.012)
 arm=empty('LeftArm' if side<0 else 'RightArm',(side*.32,0,1.43))
 shape('Shoulder',(0,0,-.01),(.25,.28,.27),ivory,arm,kind='sphere')
 shape('Upper sleeve',(0,0,-.20),(.20,.22,.32),dark,arm,kind='sphere')
 shape('Bicep armor',(side*.035,.02,-.15),(.20,.23,.21),orange,arm,kind='sphere')
 shape('Elbow',(0,0,-.35),(.20,.21,.15),steel,arm,kind='sphere')
 shape('Forearm',(0,.015,-.46),(.20,.23,.24),ivory,arm,kind='sphere')
 shape('Wrist',(0,.02,-.59),(.19,.21,.07),steel,arm)
 shape('Glove',(0,.04,-.68),(.17,.23,.16),dark,arm,kind='sphere')
# Join each joint's meshes to six render surfaces instead of dozens of independent objects.
for pivot in [o for o in list(scene.objects) if o.type=='EMPTY']:
 children=[o for o in list(scene.objects) if o.parent==pivot and o.type=='MESH']
 bpy.ops.object.select_all(action='DESELECT')
 for o in children: o.select_set(True)
 bpy.context.view_layer.objects.active=children[0]; bpy.ops.object.join()
 children[0].name=pivot.name+'Mesh'
output=ROOT/'assets/models/explore'; output.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'blender_src/exploration_suit.blend'))
bpy.ops.export_scene.gltf(filepath=str(output/'survey_suit.glb'),export_format='GLB',use_visible=True,use_active_scene=True,export_yup=True)
print('[ASSET] survey_suit.glb exported',sum(len(o.data.polygons) for o in scene.objects if o.type=='MESH'),'polygons')
