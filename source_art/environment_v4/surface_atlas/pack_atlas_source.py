import bpy,hashlib,json
from pathlib import Path
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[2];tex=ROOT/'assets/environment_v4/textures/hero-surface-atlas-01.png';preview=SRC/'shop_textured_editable.blend'
bpy.ops.wm.open_mainfile(filepath=str(preview))
images=[]
for image in bpy.data.images:
    if image.name.startswith('hero-surface-atlas-01'):
        image.filepath=str(tex);image.reload();pixels=list(image.pixels[:4]);assert len(image.pixels)==1254*1254*4;image.pack();assert image.packed_file is not None
        packed_sha=hashlib.sha256(bytes(image.packed_file.data)).hexdigest();assert packed_sha==hashlib.sha256(tex.read_bytes()).hexdigest()
        image.filepath='//../../../assets/environment_v4/textures/hero-surface-atlas-01.png';images.append({'name':image.name,'dimensions':list(image.size),'packed_bytes':len(image.packed_file.data),'packed_sha256':packed_sha,'sample_pixel':pixels})
assert len(images)==1
bpy.ops.wm.save_as_mainfile(filepath=str(preview),relative_remap=False)
(SRC/'packed_source_validation.json').write_text(json.dumps({'images':images,'fresh_reopen_verified':False},indent=2));print('PACKED',json.dumps(images))
