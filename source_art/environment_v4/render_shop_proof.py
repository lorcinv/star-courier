import bpy, math
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[1]
bpy.ops.wm.open_mainfile(filepath=str(SRC/'shop_editable.blend'))
scene=bpy.context.scene
for fname in ['sky_backdrop.glb','orbital_city.glb']:
    p=ROOT/'assets/environment_v4'/fname
    if p.exists():bpy.ops.import_scene.gltf(filepath=str(p))
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=False
scene.render.resolution_x=1600;scene.render.resolution_y=900
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(SRC/'shop_city_proof.png')
scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast'
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'shop_city_preview.blend'))
bpy.ops.render.render(write_still=True)
