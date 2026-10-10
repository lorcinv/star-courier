"""Run Blender with this script against the editable source to verify watertight components."""
import bpy,bmesh,json
from pathlib import Path
SRC=Path(__file__).resolve().parent
manifest=json.loads((SRC/'manifest.json').read_text())
bad=[];inverted=[];count=0
for o in bpy.context.scene.objects:
 if o.type!='MESH':continue
 count+=1;bm=bmesh.new();bm.from_mesh(o.data)
 boundary=sum(1 for e in bm.edges if e.is_boundary);nonmanifold=sum(1 for e in bm.edges if not e.is_manifold)
 volume=bm.calc_volume(signed=True);bm.free()
 if boundary or nonmanifold:bad.append({'name':o.name,'boundary_edges':boundary,'nonmanifold_edges':nonmanifold})
 if volume<=0:inverted.append({'name':o.name,'signed_volume':volume})
front_names=['Cream chin shoulder trim','Upper cab deep canopy perimeter','Upper cab broad blue glazing','Upper cab darker lower facet','Upper cab cyan reflection','Upper cab cream roof brow']
top_names=['Upper cab sloping top glass','Upper cab top blue facet']
normal_failures=[n for n in front_names if bpy.data.objects[n].data.polygons[0].normal.y>=0]+[n for n in top_names if bpy.data.objects[n].data.polygons[0].normal.z<=0]
sockets=[o for o in bpy.context.scene.objects if o.type=='EMPTY' and 'export_name' in o]
layout_errors=[]
roles={o.get('assembly_role'):o for o in bpy.context.scene.objects if o.get('assembly_role')}
for instance in manifest['starter_layout']:
 o=roles.get(instance['instance']);gx,gy=instance['grid']
 if o is None or any(abs(a-b)>1e-6 for a,b in zip(o.location,(gx,0,-gy))):layout_errors.append(instance['instance'])
valid=not bad and not inverted and not normal_failures and not layout_errors and len(sockets)==36
result={'result':'PASS' if valid else 'FAIL','editable_source_mesh_components':count,'source_socket_empties':len(sockets),'nonmanifold_components':bad,'nonpositive_volume_components':inverted,'normal_direction_failures':normal_failures,'exact_compact_grid_verified':not layout_errors,'layout_errors':layout_errors}
(SRC/'source_validation.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));assert valid
