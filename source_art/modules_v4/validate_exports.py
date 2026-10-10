"""Independent binary glTF contract checks for functional V4 craft modules.
Run with ordinary Python 3: python source_art/modules_v4/validate_exports.py
"""
from pathlib import Path
import json, struct, math
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'source_art/modules_v4';OUT=ROOT/'assets/modules_v4'
manifest=json.loads((OUT/'manifest.json').read_text())
locked=json.loads((ROOT/manifest['bounds_locked_to']).read_text())
report=[]
for entry in manifest['modules']:
 raw=(OUT/(entry['id']+'.glb')).read_bytes()
 assert struct.unpack_from('<III',raw)==(0x46546C67,2,len(raw))
 json_length,json_type=struct.unpack_from('<II',raw,12);assert json_type==0x4E4F534A
 g=json.loads(raw[20:20+json_length]);bin_length,bin_type=struct.unpack_from('<II',raw,20+json_length);assert bin_type==0x004E4942
 buffer=raw[28+json_length:28+json_length+bin_length]
 def read_accessor(index):
  acc=g['accessors'][index];view=g['bufferViews'][acc['bufferView']]
  size={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[acc['type']]
  fmt={5126:'f',5125:'I',5123:'H',5121:'B'}[acc['componentType']]
  byte_size=struct.calcsize('<'+fmt*size);stride=view.get('byteStride',byte_size)
  start=view.get('byteOffset',0)+acc.get('byteOffset',0)
  return [struct.unpack_from('<'+fmt*size,buffer,start+i*stride) for i in range(acc['count'])]
 nodes=g['nodes'];names={n.get('name'):n for n in nodes};root=names[entry['id']]
 assert root.get('translation',[0,0,0])==[0,0,0]
 assert root.get('rotation',[0,0,0,1])==[0,0,0,1]
 assert root.get('scale',[1,1,1])==[1,1,1]
 for name,expected in manifest['socket_contract'].items():
  assert all(abs(a-b)<1e-6 for a,b in zip(names[name]['translation'],expected))
 assert not g.get('images') and not g.get('textures')
 assert all(m['name'].startswith('V4_') for m in g['materials'])
 positions=[];surface_count=0;triangle_count=0
 for node in nodes:
  if 'mesh' not in node:continue
  assert not any(k in node for k in ['translation','rotation','scale','matrix'])
  for primitive in g['meshes'][node['mesh']]['primitives']:
   surface_count+=1;pp=read_accessor(primitive['attributes']['POSITION']);nn=read_accessor(primitive['attributes']['NORMAL']);ii=read_accessor(primitive['indices'])
   assert len(pp)==len(nn) and len(ii)%3==0
   assert all(math.isfinite(v) for p in pp for v in p)
   assert all(abs(sum(v*v for v in n)-1)<2e-4 for n in nn)
   positions+=pp;triangle_count+=len(ii)//3
 bounds={'min':[min(v[i] for v in positions) for i in range(3)],'max':[max(v[i] for v in positions) for i in range(3)]}
 for kind in ['min','max']:
  assert all(abs(a-b)<2e-6 for a,b in zip(bounds[kind],entry['bounds_godot_m'][kind]))
 for side in ['min','max']:assert all(abs(a-b)<2e-6 for a,b in zip(bounds[side],locked[entry['id']][side]))
 assert surface_count==entry['surface_count'] and surface_count<=10
 assert triangle_count==entry['triangles']
 assert bounds['min'][0]>=-.585 and bounds['max'][0]<=.585
 assert bounds['min'][1]>=-.585 and bounds['max'][1]<=.585
 assert bounds['min'][2]>=-.585 and bounds['max'][2]<=.585
 report.append({'id':entry['id'],'result':'PASS','surface_count':surface_count,'triangles':triangle_count,'bounds_godot_m':bounds,'bytes':len(raw)})
# Verify the exact current eight-cell composition, including clean gaps between all module AABBs.
actual={e['id']:e['bounds_godot_m'] for e in report};instances=[];occupied=set()
for inst in manifest['starter_layout']:
 x,y=inst['grid'];assert (x,y) not in occupied;occupied.add((x,y));base=actual[inst['module']]
 instances.append({'id':inst['instance'],'min':[base['min'][0]+x,base['min'][1]-y,base['min'][2]],'max':[base['max'][0]+x,base['max'][1]-y,base['max'][2]]})
assert occupied=={(-2,0),(-1,0),(0,0),(1,0),(-2,1),(-1,1),(0,1),(1,1)}
overlaps=[]
for i,a in enumerate(instances):
 for b in instances[i+1:]:
  if all(min(a['max'][k],b['max'][k])-max(a['min'][k],b['min'][k])>1e-6 for k in range(3)):overlaps.append([a['id'],b['id']])
assert not overlaps
assembled={'min':[min(e['min'][k] for e in instances) for k in range(3)],'max':[max(e['max'][k] for e in instances) for k in range(3)]}
for key in ['min','max']:assert all(abs(a-b)<2e-6 for a,b in zip(assembled[key],manifest['assembled_bounds_godot_m'][key]))
result={'result':'PASS','compact_aabb_intersections':overlaps,'assembled_bounds_godot_m':assembled,'module_count':len(report),'starter_module_count':manifest['starter_module_count'],'checks':['GLB 2 binary headers','Identity origin roots','Native metre-space bounds read from binary POSITION accessors','Cardinal socket names and 0.6 m coordinates','Finite geometry and unit normals','Triangle totals','At most 10 material surfaces per module','V4 source albedo material names','No external textures or buffers'],'modules':report}
(SRC/'validation.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
