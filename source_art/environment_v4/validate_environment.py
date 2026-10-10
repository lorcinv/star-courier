"""Read-only structural QA for the V4 runtime environment GLBs."""
import json,struct,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
REPORT={}
for name in ['shop_cutaway','orbital_city','sky_backdrop','flight_city']:
    p=ROOT/'assets/environment_v4'/f'{name}.glb';raw=p.read_bytes()
    magic,version,total=struct.unpack_from('<III',raw,0)
    assert magic==0x46546c67 and version==2 and total==len(raw),(name,'invalid GLB header')
    length,kind=struct.unpack_from('<II',raw,12);assert kind==0x4e4f534a
    d=json.loads(raw[20:20+length]);acc=d['accessors'];bounds=[];tris=0
    for mesh in d['meshes']:
        for s in mesh['primitives']:
            assert s.get('mode',4)==4
            a=acc[s['attributes']['POSITION']];bounds.append((a['min'],a['max']))
            tris+=acc[s['indices']]['count']//3
    nonidentity=[]
    for node in d['nodes']:
        for k,identity in [('translation',[0,0,0]),('rotation',[0,0,0,1]),('scale',[1,1,1]),('matrix',[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])]:
            if k in node and any(abs(x-y)>1e-6 for x,y in zip(node[k],identity)):nonidentity.append(node.get('name','node'))
    assert not nonidentity,(name,'nonidentity transforms',nonidentity)
    assert not d.get('images') and not d.get('textures'),(name,'unexpected image dependencies')
    assert not d.get('animations') and not d.get('cameras'),(name,'unexpected animation/camera data')
    assert all(m['name'].startswith('V4_') for m in d['materials'])
    lo=[min(a[i] for a,b in bounds) for i in range(3)];hi=[max(b[i] for a,b in bounds) for i in range(3)]
    surfaces=sum(len(m['primitives']) for m in d['meshes'])
    if name=='shop_cutaway':assert 20<=surfaces<=60
    if name=='orbital_city':assert hi[2]<-9
    REPORT[name]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'mesh_nodes':len(d['nodes']),'material_surfaces':surfaces,'triangles':tris,'godot_bounds':{'min':lo,'max':hi},'identity_transforms':True,'texture_dependencies':0,'valid_glb':True,'materials':[m['name'] for m in d['materials']]}
path=Path(__file__).resolve().parent/'environment_validation.json';path.write_text(json.dumps(REPORT,indent=2));print(json.dumps(REPORT,indent=2))
