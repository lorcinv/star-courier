"""Read-only checks for the three V4 city GLBs. Run with ordinary Python 3."""
import json,struct,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
results={}
for filename in ['orbital_city.glb','flight_city.glb','sky_backdrop.glb']:
    path=ROOT/'assets/environment_v4'/filename
    b=path.read_bytes();magic,version,length=struct.unpack_from('<4sII',b)
    assert magic==b'glTF' and version==2 and length==len(b)
    jsize,jtype=struct.unpack_from('<II',b,12);g=json.loads(b[20:20+jsize])
    assert not g.get('textures') and not g.get('images'),'Unexpected image dependency'
    assert all(not any(k in n for k in ['matrix','translation','rotation','scale']) for n in g['nodes']),'Nonidentity root/mesh transform'
    meshes=g['meshes'];surfaces=sum(len(m['primitives']) for m in meshes)
    assert surfaces<=25,'Draw surface budget exceeded'
    mats=[m['name'] for m in g['materials']]
    prefix='V4_Sky' if filename=='sky_backdrop.glb' else 'V4_City'
    assert all(m.startswith(prefix) for m in mats),'Material name contract changed'
    pos=[g['accessors'][p['attributes']['POSITION']] for m in meshes for p in m['primitives']]
    bounds={'min':[min(a['min'][i] for a in pos) for i in range(3)],'max':[max(a['max'][i] for a in pos) for i in range(3)]}
    assert bounds['max'][2]<=-9,'City or sky intersects shop depth zone'
    assert all(math.isfinite(v) for v in bounds['min']+bounds['max'])
    results[filename]={'validated':True,'identity_nodes':True,'image_dependencies':0,'materials':mats,'draw_surfaces':surfaces,'godot_bounds':bounds,'bytes':len(b)}
output=ROOT/'source_art/environment_v4/city_validation.json'
output.write_text(json.dumps(results,indent=2))
print(json.dumps({k:{'validated':v['validated'],'draw_surfaces':v['draw_surfaces'],'bytes':v['bytes']} for k,v in results.items()},indent=2))
