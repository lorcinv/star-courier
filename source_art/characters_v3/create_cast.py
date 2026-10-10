import bpy, math, os, json, sys
from pathlib import Path
from mathutils import Vector
ROOT=str(Path(__file__).resolve().parents[2])
OUT=ROOT+'/assets/environment_v2'; QA=ROOT+'/docs/qa/characters-v3'
SKIP_RENDER='--skip-render' in sys.argv
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
P={'Ink':'101c35','Cobalt':'3044aa','Cyan':'39d9d1','Yellow':'ffdf36','Coral':'fb6671','Cream':'fff1cc','Orange':'ff9748','Magenta':'be377a'}
M={}
for n,h in P.items():
 rgb=[int(h[i:i+2],16)/255 for i in (0,2,4)]; lin=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
 m=bpy.data.materials.new('Env_'+n);m.diffuse_color=(*lin,1);m.use_nodes=True
 # Proofs and exports must respect the same single-sided front faces as Godot.
 m.use_backface_culling=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*lin,1);bs.inputs['Roughness'].default_value=1;bs.inputs['Emission Color'].default_value=(*lin,1);bs.inputs['Emission Strength'].default_value=1
 M[n]=m
ROOTS=[];COL=None;PART=None;POLY_AUDIT=[]

def empty(n,loc=(0,0,0),parent=None):
 o=bpy.data.objects.new(n,None);COL.objects.link(o);o.location=loc;o.parent=parent;return o

def mesh(n,verts,faces,mats,indices=None):
 me=bpy.data.meshes.new(n);me.from_pydata(verts,[],faces);me.update()
 for ma in mats:me.materials.append(M[ma])
 if indices:
  for f,i in zip(me.polygons,indices):f.material_index=i
 o=bpy.data.objects.new(n,me);COL.objects.link(o)
 if PART:
  bpy.context.view_layer.update();o.parent=PART;o.matrix_parent_inverse=PART.matrix_world.inverted()
 return o

def poly(n,p,mat,y=-.20,dep=.24,rim=.025):
 # Extruded silhouette with a real, explicit front ink border; no outline shader.
 # +XZ signed area points toward Blender -Y (Godot +Z after export). Authored
 # silhouettes include both winding orders, especially the hair and lapels.
 def orient(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
 for i in range(len(p)):
  a,b=p[i],p[(i+1)%len(p)]
  for j in range(i+2,len(p)):
   if (j+1)%len(p)==i:continue
   c,d=p[j],p[(j+1)%len(p)]
   if orient(a,b,c)*orient(a,b,d)<-1e-12 and orient(c,d,a)*orient(c,d,b)<-1e-12:
    raise ValueError('Self-crossing silhouette: '+n)
 area=sum(x*zz-xx*z for (x,z),(xx,zz) in zip(p,p[1:]+p[:1]))*.5
 if abs(area)<1e-9:raise ValueError('Degenerate silhouette: '+n)
 p=list(reversed(p)) if area<0 else list(p)
 cx=sum(v[0] for v in p)/len(p);cz=sum(v[1] for v in p)/len(p)
 mi=min(max(v[0] for v in p)-min(v[0] for v in p),max(v[1] for v in p)-min(v[1] for v in p))
 s=max(.3,1-rim*2/max(mi,.02)); inner=[(cx+(x-cx)*s,cz+(z-cz)*s) for x,z in p]
 v=[(x,y,z) for x,z in p]+[(x,y+dep,z) for x,z in p]+[(x,y-.002,z) for x,z in inner]
 # Reverse the rear cap and use outward sidewall / front-border winding too.
 k=len(p);f=[tuple(reversed(range(k,2*k)))];idx=[0]
 for j in range(k):q=(j+1)%k;f.extend([(j,j+k,q+k,q),(j,q,2*k+q,2*k+j)]);idx.extend([0,0])
 f.append(tuple(range(2*k,3*k)));idx.append(1)
 o=mesh(n,v,f,['Ink',mat],idx)
 front=o.data.polygons[-1];back=o.data.polygons[0]
 if front.normal.y>-.99999 or back.normal.y<.99999:
  raise ValueError('Wrong cap normal: '+n)
 o.data.calc_loop_triangles()
 for tri in o.data.loop_triangles:
  if tri.polygon_index in (0,len(o.data.polygons)-1):
   expected=1.0 if tri.polygon_index==0 else -1.0
   if tri.normal.y*expected<.99999:raise ValueError('Reversed cap triangle: '+n)
 # A closed prism must use every edge exactly twice, in opposite directions.
 edges={}
 for face in f:
  for a,b in zip(face,face[1:]+face[:1]):
   key=tuple(sorted((a,b)));edges.setdefault(key,[]).append((a,b))
 if any(len(e)!=2 or e[0]!=e[1][::-1] for e in edges.values()):
  raise ValueError('Non-manifold prism winding: '+n)
 POLY_AUDIT.append({'name':n,'collection':COL.name,'source_winding_reversed':area<0,
                    'front_normal_y':round(front.normal.y,6),'back_normal_y':round(back.normal.y,6),
                    'closed_oriented_edges':True,'simple_outline_and_cap_triangles':True})
 return o

def rect(n,x,z,w,h,mat,y=-.2,dep=.24,rim=.018):return poly(n,[(x-w/2,z-h/2),(x+w/2,z-h/2),(x+w/2,z+h/2),(x-w/2,z+h/2)],mat,y,dep,rim)
def oval(n,x,z,w,h,mat,y=-.25,dep=.12,rim=.02,steps=10):return poly(n,[(x+math.cos(i*2*math.pi/steps)*w/2,z+math.sin(i*2*math.pi/steps)*h/2) for i in range(steps)],mat,y,dep,rim)
def line(n,pts,w,mat,y=-.35):
 for i,((x,z),(xx,zz)) in enumerate(zip(pts,pts[1:])):
  dx=xx-x;dz=zz-z;le=math.hypot(dx,dz);a=-dz/le*w/2;b=dx/le*w/2
  poly(n+str(i),[(x+a,z+b),(xx+a,zz+b),(xx-a,zz-b),(x-a,z-b)],mat,y,.012,0)
def glove(n,x,z,flip=1,y=-.23):
 pp=[(-.10,.12),(.07,.13),(.15,.045),(.12,-.10),(-.015,-.16),(-.13,-.085),(-.15,.015)]
 poly(n,[(x+a*flip,z+b) for a,b in pp],'Cream',y,.22,.022)
 line(n+'knuckles',[(x-.055,z-.02),(x+.055,z-.03)],.015,'Ink',y-.02)

def character(kind,fn,title):
 global COL,PART
 COL=bpy.data.collections.new(title);bpy.context.scene.collection.children.link(COL)
 r=empty(('Courier_Clerk' if kind==0 else 'Customer')+'_Root');ROOTS.append((r,COL,fn,title))
 piv={}
 for name,loc in [('BodyPivot',(0,0,1.0)),('HeadPivot',(0,0,1.55)),('LeftArmPivot',(-.31,0,1.35)),('RightArmPivot',(.31,0,1.35)),('LeftLegPivot',(-.15,0,.76)),('RightLegPivot',(.15,0,.76))]:piv[name]=empty(name,loc,r)
 # Long legs and exaggerated flat-soled work shoes; grown-up fashion silhouette.
 for side in [-1,1]:
  PART=piv[('Left' if side<0 else 'Right')+'LegPivot'];x=side*.17
  if kind==1:
   poly('Wide_work_trouser',[(x-.145,.75),(x+.14,.75),(x+.115,.16),(x-.12,.16)],'Cobalt',-.08,.30,.024)
  else:
   poly('Tapered_work_trouser',[(x-.12,.82),(x+.12,.82),(x+.065,.20),(x-.085,.20)],'Ink',-.08,.27,.012)
   rect('Trouser_light_seam',x+side*.055,.43,.025,.39,'Cyan' if kind==2 else 'Cobalt',-.091,.01,.0)
  poly('Oversize_sneaker',[(x-.15,.04),(x+.18,.04),(x+.18,.16),(x+.07,.23),(x-.12,.23),(x-.20,.12)],'Cream',-.32,.53,.025)
  rect('Shoe_color_tab',x,.13,.19,.06,['Cyan','Orange','Magenta','Cobalt'][kind],-.325,.013,.007)
  rect('Dark_rubber_sole',x-.005,.047,.35,.047,'Ink',-.34,.54,.0)
 PART=piv['BodyPivot']
 if kind==0:
  poly('Angular_courier_jacket',[(-.26,.73),(.28,.73),(.36,1.36),(.16,1.51),(-.16,1.49),(-.34,1.30)],'Coral',-.13,.34,.028)
  poly('Oversize_white_lapel',[(-.19,1.48),(.03,1.22),(.19,1.49),(.20,1.28),(.035,1.08),(-.15,1.29)],'Cream',-.16,.025,.008)
  rect('Heavy_jacket_hem',0,.79,.56,.12,'Ink',-.18,.035,.0)
  line('Slant_satchel_strap',[(-.23,1.42),(.25,.88)],.095,'Ink',-.21)
  poly('Yellow_hard_satchel',[(.17,.71),(.48,.70),(.51,1.00),(.19,1.02)],'Yellow',-.24,.30,.024)
  rect('Satchel_latch',.34,.90,.11,.06,'Ink',-.252,.018,0)
  poly('Express_badge',[(-.21,1.25),(-.07,1.29),(-.10,1.15),(-.23,1.13)],'Yellow',-.24,.02,.01)
 elif kind==1:
  poly('Block_parka',[(-.39,.72),(.36,.72),(.44,1.33),(.24,1.52),(-.23,1.50),(-.43,1.32)],'Yellow',-.15,.46,.03)
  poly('Large_standing_collar',[(-.29,1.48),(0,1.24),(.30,1.47),(.24,1.29),(0,1.16),(-.27,1.32)],'Cream',-.20,.10,.015)
  line('Center_zip',[(0,.77),(0,1.23)],.026,'Ink',-.22)
  for x in [-.23,.23]:rect('Oversize_pocket',x,.99,.22,.18,'Orange',-.23,.05,.021)
 elif kind==2:
  poly('Cropped_cobalt_workcoat',[(-.22,.81),(.25,.81),(.32,1.32),(.14,1.51),(-.17,1.48),(-.30,1.30)],'Cobalt',-.15,.35,.025)
  poly('Cyan_diagonal_panel',[(-.25,1.32),(.21,1.44),(.25,1.27),(-.26,1.12)],'Cyan',-.18,.018,.007)
  rect('Work_belt',0,.86,.50,.10,'Magenta',-.22,.04,.015)
  rect('Square_belt_buckle',.06,.86,.11,.09,'Yellow',-.25,.02,.015)
  poly('Messenger_document_bag',[(-.50,.67),(-.22,.68),(-.19,1.07),(-.49,1.05)],'Coral',-.12,.25,.025)
  line('Messenger_strap',[(-.12,1.43),(-.37,.89)],.06,'Cream',-.23)
 else:
  poly('Oversize_research_coat',[(-.36,.65),(.34,.65),(.25,1.41),(.09,1.51),(-.13,1.48),(-.31,1.37)],'Cobalt',-.15,.4,.028)
  poly('Coat_lapel',[(-.16,1.47),(0,1.21),(.13,1.45),(.16,1.13),(0,1.04),(-.17,1.18)],'Cream',-.19,.035,.015)
  for z in [.81,.99]:oval('Button',.02,z,.052,.052,'Yellow',-.22,.01,.002,6)
  rect('Field_pouch',.24,.95,.22,.27,'Cyan',-.23,.12,.018)
 # Arms: separate named rigid pivots.
 for side in [-1,1]:
  PART=piv[('Left' if side<0 else 'Right')+'ArmPivot'];x=side*(.44 if kind==1 else .33);col=['Coral','Yellow','Cobalt','Cobalt'][kind]
  if side==1 and kind in [0,2]:
   poly('Bent_sleeve',[(x-.055,1.34),(x+.12,1.31),(x+.25,1.10),(x+.07,.99),(x-.03,1.10)],col,-.04,.25,.02)
   # Nova's glove sits in front of her hard satchel instead of sharing its cap.
   glove('Hip_glove',x+.07,1.02,side,-.28 if kind==0 else -.24)
  else:
   # Mirror the shoulder as well as the cuff; mixing the two orders crossed
   # the left outline and made the exporter flip a cap triangle on every actor.
   poly('Long_sleeve',[(x-side*.11,1.35),(x+side*.10,1.37),(x+side*.17,.94),(x+side*.05,.85),(x-side*.08,.94)],col,-.04,.25,.02)
   rect('Broad_cuff',x+side*.08,.95,.22,.12,'Cream' if kind!=2 else 'Cyan',-.09,.27,.014)
   if kind==0 and side<0:
    gx=x+side*.09
    poly('Open_courier_hand',[(gx-.13,.87),(gx+.10,.88),(gx+.16,.77),(gx+.09,.73),(gx+.035,.78),(gx+.05,.61),(gx-.015,.59),(gx-.03,.72),(gx-.055,.59),(gx-.115,.61),(gx-.09,.74),(gx-.15,.65),(gx-.19,.69)],'Cream',-.10,.20,.015)
   # Kiki's hand and knuckle stroke must clear the document-bag face.
   else:glove('Expressive_glove',x+side*.09,.80,side,-.14 if kind==2 and side<0 else -.10)
 PART=piv['HeadPivot']
 rect('Neck',0,1.53,.20,.22,'Cream',-.035,.23,.016)
 if kind==0:
  poly('Angular_face',[(-.29,1.94),(-.25,1.65),(-.06,1.54),(.21,1.65),(.29,1.95),(.07,2.11)],'Cream',-.18,.33,.025)
  poly('Asymmetric_rocket_hair',[(-.34,1.71),(-.43,1.96),(-.26,2.15),(-.02,2.24),(.43,2.32),(.28,2.14),(.52,2.14),(.31,1.99),(.12,1.96),(-.03,2.04),(-.16,1.95),(-.20,1.74)],'Cobalt',-.205,.35,.022)
  poly('Cyan_hair_streak',[(-.28,2.07),(.31,2.24),(.16,2.11),(-.08,2.06)],'Cyan',-.213,.012,.0)
  eye(-.13,1.83,.18,.13,0);eye(.12,1.84,.18,.14,.025)
  line('Confident_brow_L',[(-.24,1.94),(-.065,1.91)],.035,'Ink',-.243)
  line('Confident_brow_R',[(.045,1.94),(.22,1.97)],.034,'Ink',-.243)
  poly('Side_smirk',[(-.035,1.68),(.17,1.73),(.12,1.65)],'Ink',-.244,.012,0)
  poly('Smirk_tooth',[(-.005,1.686),(.13,1.72),(.105,1.68)],'Cream',-.25,.008,0)
  oval('Headset_ear',-.28,1.79,.13,.19,'Ink',-.08,.15,.006)
  oval('Headset_teal_disc',-.285,1.79,.075,.11,'Cyan',-.087,.01,.005)
  line('Headset_mic',[(-.30,1.77),(-.33,1.65),(-.15,1.63)],.025,'Ink',-.252)
 elif kind==1:
  poly('Square_face',[(-.30,2.02),(-.29,1.67),(-.18,1.54),(.22,1.56),(.33,1.75),(.28,2.04)],'Orange',-.18,.38,.024)
  poly('High_block_pompadour',[(-.34,1.88),(-.35,2.13),(-.22,2.26),(.33,2.23),(.40,2.09),(.21,2.03),(-.16,2.06),(-.23,1.85)],'Ink',-.20,.39,.015)
  poly('Pompadour_cream_slash',[(-.20,2.18),(.30,2.18),(.24,2.12),(-.24,2.12)],'Cream',-.21,.01,0)
  for x in [-.14,.15]:
   rect('Chunky_square_glasses',x,1.88,.25,.18,'Ink',-.238,.035,.0);rect('Lens',x,1.89,.18,.105,'Cream',-.245,.008,.0);rect('Pupil',x+.025,1.875,.048,.068,'Ink',-.255,.008,0)
  rect('Glasses_bridge',.005,1.89,.07,.03,'Ink',-.252,.01,0)
  poly('Chevrons_moustache',[(-.18,1.72),(-.06,1.78),(0,1.74),(.07,1.77),(.21,1.71),(.05,1.67),(-.04,1.70)],'Ink',-.25,.025,0)
  line('Small_grin',[(-.05,1.625),(.105,1.64)],.022,'Cream',-.25)
 elif kind==2:
  # High double mass cropped hair silhouette with a one-sided swept tail.
  poly('Graphic_bob_back',[(-.37,1.55),(-.42,2.05),(-.21,2.25),(.12,2.28),(.35,2.10),(.43,1.55),(.15,1.64),(-.13,1.62)],'Magenta',-.03,.39,.023)
  poly('Diamond_face',[(-.27,1.98),(-.24,1.72),(.02,1.55),(.25,1.73),(.27,2.02),(0,2.15)],'Cream',-.22,.25,.024)
  poly('Heavy_diagonal_fringe',[(-.34,2.04),(-.19,2.25),(.13,2.26),(.33,2.09),(.20,1.90),(.03,2.02),(-.06,1.89),(-.13,2.00),(-.26,1.90)],'Magenta',-.242,.12,.02)
  eye(-.13,1.83,.18,.12,-.02);eye(.125,1.825,.18,.12,-.02)
  line('Wry_eyelid',[(-.235,1.86),(-.035,1.87)],.025,'Ink',-.273);line('Wry_right_eyelid',[(.02,1.875),(.23,1.85)],.026,'Ink',-.273)
  poly('Open_laugh',[(-.085,1.695),(.14,1.70),(.085,1.61),(-.015,1.62)],'Ink',-.271,.012,0)
  rect('Laugh_tooth',.027,1.686,.15,.035,'Cream',-.277,.008,0)
  oval('Round_earring',.27,1.68,.10,.15,'Yellow',-.25,.025,.024)
  poly('Yellow_hair_pin',[(-.28,2.07),(-.11,2.16),(-.08,2.11),(-.25,2.02)],'Yellow',-.26,.012,0)
 else:
  poly('Long_face',[(-.23,2.04),(-.27,1.76),(-.12,1.53),(.14,1.54),(.25,1.79),(.24,2.08)],'Cream',-.19,.33,.023)
  poly('Cloud_hair',[(-.34,1.94),(-.43,2.09),(-.29,2.18),(-.26,2.29),(-.08,2.26),(.04,2.37),(.18,2.26),(.34,2.25),(.36,2.10),(.26,1.99),(.08,2.09),(-.08,2.04),(-.22,2.08)],'Cream',-.225,.36,.021)
  for x in [-.14,.145]:
   oval('Round_goggles',x,1.86,.26,.26,'Cyan',-.24,.035,.025,12);oval('Goggle_lens',x,1.865,.18,.18,'Cream',-.247,.012,.003,12);oval('Tiny_attentive_pupil',x+.02,1.86,.045,.085,'Ink',-.263,.01,0,8)
  rect('Goggle_bridge',0,1.86,.08,.04,'Ink',-.263,.01,0)
  line('Delighted_smile',[(-.10,1.69),(-.04,1.64),(.08,1.65),(.13,1.70)],.024,'Ink',-.245)
  # Two pencil accessories protrude above ear.
  line('Yellow_pencil',[(.30,1.85),(.43,2.23)],.036,'Yellow',-.04)
  line('Coral_pencil',[(.32,1.85),(.51,2.13)],.034,'Coral',-.025)
 # Merge all authored components per rigid part; preserve named animation empties.
 for p in piv.values():
  objs=[o for o in COL.objects if o.type=='MESH' and o.parent==p]
  if not objs:continue
  bpy.ops.object.select_all(action='DESELECT')
  for o in objs:o.select_set(True)
  bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();objs[0].name=p.name.split('.')[0]+'_Art'
  # Remove duplicate material slots after join.
  me=objs[0].data;old=list(me.materials);unique=[];mapping={}
  for i,m in enumerate(old):
   if m not in unique:unique.append(m)
   mapping[i]=unique.index(m)
  ids=[mapping[f.material_index] for f in me.polygons];me.materials.clear()
  for m in unique:me.materials.append(m)
  for f,i in zip(me.polygons,ids):f.material_index=i
 # Deliberate silhouette / posture diversity, kept in authored mesh coordinates.
 bpy.context.view_layer.update()
 saved={o:[o.matrix_world @ v.co for v in o.data.vertices] for o in COL.objects if o.type=='MESH'}
 def deform(v):
  v=v.copy()
  if kind==0:v.x += .095*max(0,v.z-.60)
  elif kind==1:v.x*=1.15;v.z*=.87
  elif kind==2:v.x += .09*math.sin(min(1,v.z/1.65)*math.pi)
  else:v.x*=.82;v.z*=1.065
  return v
 for p in piv.values():p.location=deform(p.location)
 bpy.context.view_layer.update()
 for o,coords in saved.items():
  inv=o.matrix_world.inverted()
  for v,world in zip(o.data.vertices,coords):v.co=inv @ deform(world)
 if kind==0:
  piv['LeftArmPivot'].rotation_euler.y=.94
  piv['HeadPivot'].rotation_euler.y=-.08
 elif kind==1:
  piv['LeftArmPivot'].rotation_euler.y=-.10;piv['RightArmPivot'].rotation_euler.y=.10
 elif kind==2:
  piv['RightLegPivot'].rotation_euler.y=-.14;piv['LeftLegPivot'].rotation_euler.y=.08
  piv['HeadPivot'].rotation_euler.y=.06
 else:
  piv['RightArmPivot'].rotation_euler.y=-.14
 return r

def eye(x,z,w,h,look=0):
 oval('Expressive_eye_white',x,z,w,h,'Cream',-.254,.012,.018,8)
 oval('Tall_ink_pupil',x+look,z,.055,h*.77,'Ink',-.270,.008,0,8)

for i,(fn,title) in enumerate([('courier_clerk','01 • NOVA / EXPRESS CLERK'),('customer','02 • BRAM / FREIGHT PILOT'),('customer_2','03 • KIKI / SOUND TECH'),('customer_3','04 • ORIN / FIELD RESEARCHER')]):character(i,fn,title)
metrics=[]
for r,c,fn,title in ROOTS:
 bpy.ops.object.select_all(action='DESELECT')
 for o in c.objects:o.select_set(True)
 bpy.ops.export_scene.gltf(filepath=OUT+'/'+fn+'.glb',export_format='GLB',use_selection=True,export_apply=True,export_cameras=False,export_lights=False)
 metrics.append({'file':fn+'.glb','title':title,'vertices':sum(len(o.data.vertices) for o in c.objects if o.type=='MESH'),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in c.objects if o.type=='MESH'),'mesh_count':sum(o.type=='MESH' for o in c.objects),'surfaces':sum(len(o.data.materials) for o in c.objects if o.type=='MESH')})
validation={'silhouettes':len(POLY_AUDIT),'normalized_source_windings':sum(p['source_winding_reversed'] for p in POLY_AUDIT),'all_front_caps_face_negative_y':True,'all_back_caps_face_positive_y':True,'all_prisms_closed_and_consistently_oriented':True,'all_outlines_simple_and_cap_triangles_oriented':True,'backface_culling_in_blender_proofs':True,'godot_generated_lods':False}
json.dump({'palette':P,'front':'Blender -Y / Godot +Z','up':'Blender +Z / Godot +Y','rig':'Six rigid named pivots. Rotate HeadPivot / arms / legs relative to imported rest rotations. No skinning cost.','assets':metrics,'geometry_validation':validation},open(ROOT+'/source_art/characters_v3/manifest.json','w'),indent=2)
json.dump({'summary':validation,'silhouettes':POLY_AUDIT},open(ROOT+'/source_art/characters_v3/geometry-validation.json','w'),indent=2)
# Cast board is deliberately front-on, with slight elevated camera to expose extrusion.
COL=bpy.data.collections.new('Presentation');bpy.context.scene.collection.children.link(COL);PART=None
for i,(r,c,fn,title) in enumerate(ROOTS):r.location.x=(i-1.5)*1.75
# Text belongs only to proof, never runtime.
def text(n,s,x,z,size,mat):
 cu=bpy.data.curves.new(n,'FONT');cu.body=s;cu.size=size;cu.align_x='CENTER';cu.align_y='CENTER';o=bpy.data.objects.new(n,cu);COL.objects.link(o);o.location=(x,-.38,z);o.rotation_euler=(math.pi/2,0,0);cu.materials.append(M[mat]);return o
for i,(r,c,fn,title) in enumerate(ROOTS):
 x=r.location.x;rect('Ground_shadow',x,-.08,1.16,.04,'Cobalt',.12,.01,0)
 text('Name',title.split(' / ')[0].replace(' • ','  '),x,-.30,.14,'Ink');text('Role',title.split(' / ')[1],x,-.48,.084,'Cobalt')
text('Main_title','STAR / COURIER',0,3.02,.31,'Cobalt');text('Subtitle','ORIGINAL CAST  /  GRAPHIC 3D  /  RIGID ANIMATION READY',0,2.72,.10,'Ink')
scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE_NEXT';scene.world.color=(.8,.8,.8)
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.96,.905,.75,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=1
bpy.ops.object.camera_add(location=(0,-15,3.9));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,1.16))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=7.65;scene.camera=cam
scene.render.resolution_x=1600;scene.render.resolution_y=900;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
scene.render.film_transparent=False
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/source_art/characters_v3/star_courier_original_cast.blend')
if not SKIP_RENDER:
 scene.render.filepath=QA+'/cast-board.png';bpy.ops.render.render(write_still=True)
print('CAST_METRICS',json.dumps(metrics))
print('CAST_GEOMETRY_VALIDATION',json.dumps(validation))
