"""Verify original glTF exports and their engine-space modular socket contract."""
import json,struct,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
EXTRAS={'landing_pad','cargo_crate','hangar_terminal','hangar_arch','asteroid_0','asteroid_1','asteroid_2'}
report=[]
for f in sorted((ROOT/'assets/models').glob('*.glb')):
 b=f.read_bytes();magic,version,total=struct.unpack('<III',b[:12]);length,typ=struct.unpack('<II',b[12:20]);j=json.loads(b[20:20+length])
 assert magic==0x46546c67 and version==2 and total==len(b),f
 names={n.get('name'):n for n in j['nodes']}
 if f.stem not in EXTRAS:
  for n,p in [('Right',[.6,0,0]),('Left',[-.6,0,0]),('Top',[0,.6,0]),('Bottom',[0,-.6,0])]:
   v=names['Socket_'+n]['translation'];assert all(abs(a-c)<1e-5 for a,c in zip(v,p)),(f,n,v)
 assert len(j['meshes'])>0;assert not j.get('images')
 report.append({'asset':f.stem,'mesh_count':len(j['meshes']),'bytes':len(b),'sockets_verified':f.stem not in EXTRAS})
assert len(report)==32
result={'result':'PASS','count':len(report),'part_count':sum(x['sockets_verified'] for x in report),'checks':['glTF 2 binary structure','self-contained materials; no external texture dependencies','all 100 cardinal socket names and Godot-space coordinates'],'assets':report}
(ROOT/'assets/models/validation.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k!='assets'},indent=2))
