import bpy
from pathlib import Path
P=Path(__file__).resolve().parent/'shop_textured_editable.blend'
bpy.ops.wm.open_mainfile(filepath=str(P))
for image in bpy.data.images:
    if image.name.startswith('hero-surface-atlas-01'):image.filepath='//../../../assets/environment_v4/textures/hero-surface-atlas-01.png'
bpy.ops.wm.save_as_mainfile(filepath=str(P))
