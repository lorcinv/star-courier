"""Blender source-object AABB audit of live module envelope; no writes to scene."""
import bpy,json
from mathutils import Vector
from pathlib import Path
SRC=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(SRC/'shop_editable.blend'))
# Full 1x1x1 module extents around the extreme editable cell centers.
lo=Vector((-3.5,.5,0.0));hi=Vector((5.5,5.5,1.0));overlap=[];tested=0
for o in bpy.context.scene.objects:
    if o.type!='MESH' or any(c.name.startswith('EXPORT') for c in o.users_collection):continue
    tested+=1;world=[o.matrix_world@Vector(c) for c in o.bound_box]
    # Blender X/Y/Z -> Godot X/Y/Z.
    game=[Vector((v.x,v.z,-v.y)) for v in world]
    a=Vector([min(v[i] for v in game) for i in range(3)]);b=Vector([max(v[i] for v in game) for i in range(3)])
    if all(min(b[i],hi[i])-max(a[i],lo[i])>.0005 for i in range(3)):
        overlap.append({'object':o.name,'min':list(a),'max':list(b)})
result={'method':'conservative per-source-object world AABBs; excludes merged export duplicates','tested_source_meshes':tested,'module_envelope_godot':{'min':list(lo),'max':list(hi)},'overlapping_objects':overlap,'passed':not overlap}
(SRC/'clearance_validation.json').write_text(json.dumps(result,indent=2));print('V4_CLEARANCE',json.dumps(result))
assert not overlap,overlap
