"""Validate actual GLB bounds, palette, geometry, dimensions and surface budget."""
import json,struct,math
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'assets/characters_v4';REPORT=ROOT/'source_art/characters_v4/export-validation.json'
DT={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1',5122:'<i2',5120:'i1'};NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def read(path):
 data=path.read_bytes();magic,version,ln=struct.unpack_from('<III',data);assert magic==0x46546c67 and version==2 and ln==len(data)
 off=12;js=None;blob=None
 while off<len(data):
  ln,kind=struct.unpack_from('<II',data,off);off+=8;chunk=data[off:off+ln];off+=ln
  if kind==0x4e4f534a:js=json.loads(chunk)
  if kind==0x004e4942:blob=chunk
 return js,blob

def arr(js,b,idx):
 a=js['accessors'][idx];v=js['bufferViews'][a['bufferView']];dt=np.dtype(DT[a['componentType']]);width=NC[a['type']]
 start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',dt.itemsize*width)
 return np.ndarray((a['count'],width),dtype=dt,buffer=b,offset=start,strides=(stride,dt.itemsize)).copy()
def matrix(n):
 if 'matrix' in n:return np.asarray(n['matrix']).reshape(4,4).T
 t=n.get('translation',[0,0,0]);s=n.get('scale',[1,1,1]);x,y,z,w=n.get('rotation',[0,0,0,1]);R=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
 M=np.eye(4);M[:3,:3]=R@np.diag(s);M[:3,3]=t;return M
reports=[]
for fn in ('clerk.glb','customer.glb'):
 js,blob=read(OUT/fn);parents={ch:i for i,n in enumerate(js['nodes']) for ch in n.get('children',[])};world={}
 def wm(i):
  if i not in world:world[i]=(wm(parents[i]) if i in parents else np.eye(4))@matrix(js['nodes'][i])
  return world[i]
 points=[];triangles=0;degenerate=0;inverted_normals=0;surfaces=0;face_surfaces=0
 for i,n in enumerate(js['nodes']):
  if 'mesh' not in n:continue
  for p in js['meshes'][n['mesh']]['primitives']:
   P=arr(js,blob,p['attributes']['POSITION']);N=arr(js,blob,p['attributes']['NORMAL']);I=arr(js,blob,p['indices']).ravel();T=I.reshape(-1,3);surfaces+=1;triangles+=len(T)
   tr=np.c_[P,np.ones(len(P))]@wm(i).T;points.extend(tr[:,:3].tolist())
   V=P[T];cross=np.cross(V[:,1]-V[:,0],V[:,2]-V[:,0]);area=np.linalg.norm(cross,axis=1);degenerate+=int((area<1e-10).sum())
   normal_avg=N[T].mean(axis=1);inverted_normals+=int(((cross*normal_avg).sum(axis=1)<-1e-8).sum())
   assert np.isfinite(P).all() and np.isfinite(N).all()
 pts=np.array(points);lo=pts.min(0);hi=pts.max(0);names=[n.get('name','') for n in js['nodes']];mats=js.get('materials',[])
 assert abs(lo[1])<1e-4,(fn,lo);assert abs((hi-lo)[1]-2.4)<.004,(fn,hi-lo)
 assert degenerate==0,(fn,degenerate);assert inverted_normals==0,(fn,inverted_normals);assert surfaces<=19,(fn,surfaces)
 assert all(m['name'].startswith('V4_') for m in mats);assert all(not m.get('doubleSided',False) for m in mats)
 for prefix in ['HeadPivot','BodyPivot','LeftArmPivot','RightArmPivot','LeftLegPivot','RightLegPivot','FaceLook_Anchor','LeftPalm_Anchor','RightPalm_Anchor']:assert any(n.startswith(prefix) for n in names),(fn,prefix)
 anchors={n['name']:wm(i)[:3,3].round(4).tolist() for i,n in enumerate(js['nodes']) if 'Palm_Anchor' in n.get('name','') or 'FaceLook_' in n.get('name','')}
 reports.append({'file':fn,'bounds_min':lo.round(5).tolist(),'bounds_max':hi.round(5).tolist(),'triangles':triangles,'degenerate_triangles':degenerate,'inverted_triangle_normals':inverted_normals,'material_surfaces':surfaces,'palette_materials':len(mats),'all_palette_names_valid':True,'single_sided_materials':True,'named_pivots_and_face_palm_anchors':True,'anchors':anchors,'spine_data':False})
REPORT.write_text(json.dumps({'pass':True,'actors':reports,'note':'Structural GLB checks and Blender proof inspection do not substitute for in-engine review. Disable Godot generated LODs for layered face meshes on eventual import.'},indent=2));print(REPORT);print(json.dumps(reports,indent=2))
