import bpy, math, os
from pathlib import Path
from mathutils import Vector
ROOT=str(Path(__file__).resolve().parents[2]);QA=os.environ.get('STAR_COURIER_PROOF_DIR',ROOT+'/docs/qa/characters-v3');scene=bpy.context.scene
os.makedirs(QA,exist_ok=True)
# Exact flat colors for review; light baking is not involved.
world=scene.world.node_tree.nodes['Background'];world.inputs[0].default_value=(0.96,0.905,0.75,1);world.inputs[1].default_value=1
scene.render.filepath=QA+'/cast-board.png';bpy.ops.render.render(write_still=True)
# Portrait crop: facial expression / authored depth proof from oblique view.
for c in bpy.data.collections:
 if c.name=='Presentation':
  for o in c.objects:o.hide_render=True
roots=[o for o in bpy.data.objects if o.type=='EMPTY' and o.parent is None and o.name.split('.')[0].endswith('_Root')]
roots=sorted(roots,key=lambda o:o.location.x)
for i,r in enumerate(roots):r.location=(i*1.4,0,0)
cam=scene.camera;cam.location=(2.25,-12,3.2);cam.rotation_euler=(Vector((2.1,0,1.88))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=5.8
scene.render.resolution_x=1600;scene.render.resolution_y=500;scene.render.filepath=QA+'/face-closeups.png';bpy.ops.render.render(write_still=True)
# Import the actual runtime storefront and stage at the actual service-floor scale.
for i,r in enumerate(roots):r.location=(-6.8-i*1.55,-1.9,.1)
bpy.ops.import_scene.gltf(filepath=ROOT+'/assets/environment_v2/shop_cutaway.glb')
for m in bpy.data.materials:
 if not m.use_nodes:continue
 bs=m.node_tree.nodes.get('Principled BSDF')
 if bs:
  color=bs.inputs['Base Color'].default_value;bs.inputs['Emission Color'].default_value=color;bs.inputs['Emission Strength'].default_value=1
cam.location=(-7.4,-20,6.2);cam.rotation_euler=(Vector((-7.4,0,2.4))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=12.0
scene.render.resolution_x=1500;scene.render.resolution_y=900;scene.render.filepath=QA+'/shop-scale-proof.png';bpy.ops.render.render(write_still=True)
