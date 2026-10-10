import bpy
from pathlib import Path
from mathutils import Vector
ROOT=str(Path(__file__).resolve().parents[2])
keep=['Courier_Clerk','Customer','Destination_Kiosk','Sky_Backdrop','Presentation_Lighting']
for col in bpy.data.collections:
 for o in col.objects:o.hide_render=col.name not in keep
for name,x in [('Courier_Clerk_Root',-3.5),('Customer_Root',3.4)]:
 o=bpy.data.objects[name];o.location=(x,-.15,0);o.rotation_euler.z=0
scene=bpy.context.scene;cam=scene.camera;cam.location=(1,-20,6);cam.rotation_euler=(Vector((0,0,1.7))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=10.8
scene.render.resolution_x=1400;scene.render.resolution_y=850;scene.cycles.samples=32
scene.render.filepath=ROOT+'/docs/qa/art-v2/characters-and-destination.png'
bpy.ops.render.render(write_still=True)
