"""Compare the actual untextured and textured GLB vertex positions, read-only."""
from pathlib import Path
import json,struct,hashlib
SRC=Path(__file__).resolve().parent

def read(path):
    raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];j=json.loads(raw[20:20+n]);offset=20+n;binary_length,binary_type=struct.unpack_from('<II',raw,offset);assert binary_type==0x004e4942;b=raw[offset+8:offset+8+binary_length];positions=set();triangles=0;lo=[1e9]*3;hi=[-1e9]*3
    for mesh in j['meshes']:
        for prim in mesh['primitives']:
            acc=j['accessors'][prim['attributes']['POSITION']];view=j['bufferViews'][acc['bufferView']];assert acc['componentType']==5126 and acc['type']=='VEC3';start=view.get('byteOffset',0)+acc.get('byteOffset',0);stride=view.get('byteStride',12)
            for i in range(acc['count']):
                v=struct.unpack_from('<fff',b,start+i*stride);positions.add(tuple(round(x,5) for x in v))
                for axis in range(3):lo[axis]=min(lo[axis],v[axis]);hi[axis]=max(hi[axis],v[axis])
            triangles+=j['accessors'][prim['indices']]['count']//3
    return positions,triangles,{'min':lo,'max':hi},j
old,ot,ob,_=read(SRC/'shop_cutaway_untextured.glb');new,nt,nb,j=read(SRC/'shop_cutaway_textured.glb')
assert old==new,(len(old-new),len(new-old));assert ot==nt;assert ob==nb
report={'passed':True,'actual_glb_positions_identical_1e5':True,'unique_vertex_positions':len(old),'triangles_before':ot,'triangles_after':nt,'world_bounds_exactly_equal':True,'world_bounds':ob,'export_surfaces':sum(len(m['primitives']) for m in j['meshes']),'new_textures':len(j.get('textures',[])),'atlas_material_white':next(m for m in j['materials'] if m['name']=='V4_HeroSurfaceAtlas01')['pbrMetallicRoughness'].get('baseColorFactor',[1,1,1,1])==[1,1,1,1]}
(SRC/'geometry_uv_validation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
