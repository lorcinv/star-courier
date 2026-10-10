import bpy
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(SRC/'shop_textured_editable.blend'))
import hashlib,json
validation=json.loads((SRC/'packed_source_validation.json').read_text())
for image in bpy.data.images:
    if image.name.startswith('hero-surface-atlas-01'):
        assert image.packed_file is not None
        assert hashlib.sha256(bytes(image.packed_file.data)).hexdigest()==validation['images'][0]['packed_sha256']
        assert len(image.pixels)==1254*1254*4
        assert list(image.pixels[:4])!=[1.0,0.0,1.0,1.0]
        print('FRESH_PACKED_IMAGE_OK',image.name,list(image.size),len(image.packed_file.data),flush=True)
validation['fresh_reopen_verified']=True
(SRC/'packed_source_validation.json').write_text(json.dumps(validation,indent=2))
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=False;scene.render.resolution_x=1280;scene.render.resolution_y=800;scene.render.image_settings.file_format='PNG';cam=scene.camera
for name,pos,tar,scale in [('hero-drawer-proof-01.png',(-1.7,2.35,8),(-1.7,1.05,-1.3),4.3),('hero-parcel-proof-01.png',(-9.6,3.70,9),(-9.6,2.27,-1.1),5.25)]:
    cam.location=Vector((pos[0],-pos[2],pos[1]));target=Vector((tar[0],-tar[2],tar[1]));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;scene.render.filepath=str(SRC/name);bpy.ops.render.render(write_still=True)
