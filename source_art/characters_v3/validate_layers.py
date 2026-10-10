"""Audit overlapping front caps in the saved Blender rest pose.

Run: blender -b source_art/characters_v3/star_courier_original_cast.blend \
    --python source_art/characters_v3/validate_layers.py

Caps of different colors may overlap in projection, but must not share a depth.
Same-color overlaps are intentionally allowed at connected stroke joints.
"""
import bpy,json
from pathlib import Path

def area(p):
 return sum(x*z2-x2*z for (x,z),(x2,z2) in zip(p,p[1:]+p[:1]))/2 if len(p)>=3 else 0

def clip(subject,mask):
 if area(mask)<0:mask=mask[::-1]
 output=subject[:]
 for a,b in zip(mask,mask[1:]+mask[:1]):
  points=output;output=[]
  if not points:return []
  def orient(v):return (b[0]-a[0])*(v[1]-a[1])-(b[1]-a[1])*(v[0]-a[0])
  previous=points[-1];pd=orient(previous)
  for current in points:
   cd=orient(current)
   if (cd>=0)!=(pd>=0):
    factor=pd/(pd-cd)
    output.append((previous[0]+(current[0]-previous[0])*factor,previous[1]+(current[1]-previous[1])*factor))
   if cd>=0:output.append(current)
   previous=current;pd=cd
 return output

reports=[]
for col in bpy.data.collections:
 if not col.name[:2] in ['01','02','03','04']:continue
 caps=[]
 for o in col.objects:
  if o.type!='MESH':continue
  o.data.calc_loop_triangles()
  for t in o.data.loop_triangles:
   vs=[o.matrix_world@o.data.vertices[i].co for i in t.vertices]
   n=(vs[1]-vs[0]).cross(vs[2]-vs[0]).normalized()
   if n.y>-.9999999:continue
   points=[(v.x,v.z) for v in vs]
   caps.append((sum(v.y for v in vs)/3,points,o.data.materials[t.material_index].name,o.name))
 coincident=[];min_gap=100;closest=None
 for i,(y,pts,ma,on) in enumerate(caps):
  for yy,other,mb,othername in caps[i+1:]:
   if ma==mb:continue
   if max(p[0] for p in pts)<min(p[0] for p in other) or max(p[0] for p in other)<min(p[0] for p in pts):continue
   if max(p[1] for p in pts)<min(p[1] for p in other) or max(p[1] for p in other)<min(p[1] for p in pts):continue
   overlap=abs(area(clip(pts,other)))
   if overlap<1e-10:continue
   gap=abs(y-yy)
   if gap<1e-7:coincident.append((ma,mb,on,othername,overlap))
   elif gap<min_gap:min_gap=gap;closest=(ma,mb,on,othername)
 reports.append({'actor':col.name,'flat_front_triangles':len(caps),'different_material_coplanar_overlaps':coincident,'minimum_positive_gap':round(min_gap,6),'closest_materials_and_parts':closest})
report={'status':'PASS' if all(not r['different_material_coplanar_overlaps'] for r in reports) else 'FAIL','actors':reports}
print('DEPTH_LAYER_AUDIT',json.dumps(report))
(Path(__file__).resolve().parent/'layer-validation.json').write_text(json.dumps(report,indent=2))

if report["status"] != "PASS":
 raise AssertionError("Coplanar front caps: see layer-validation.json")
