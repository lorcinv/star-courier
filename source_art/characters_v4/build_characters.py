"""Star Courier v4: original dimensional Q-proportion character studies.
Blender 4.3.2. No raster tracing, imported character art, or Spine data.
Run: blender -b -t 4 --python-exit-code 1 --python source_art/characters_v4/build_characters.py
"""
import bpy, bmesh, math, json, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'source_art/characters_v4'; OUT=ROOT/'assets/characters_v4'; PROOF=SRC/'proofs'
for p in (SRC,OUT,PROOF): p.mkdir(parents=True,exist_ok=True)
SKIP_RENDER='--skip-render' in sys.argv
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
 if c.name!='Collection': bpy.data.collections.remove(c)
PALETTE={
 'InkNavy':'192438','SkinPeach':'f7c7a4','Cream':'fff1d6',
 'HairBlue':'1668b7','HairCyan':'38b7df','IrisCyan':'48dcd5',
 'CourierYellow':'ffc637','RustOchre':'b77640','HairBrown':'59413a',
 'Coral':'f36f74','Charcoal':'394455','IrisAmber':'bd7837'}
MAT={}
def linear(x): return x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4
for name,h in PALETTE.items():
 rgb=[linear(int(h[i:i+2],16)/255) for i in (0,2,4)]
 m=bpy.data.materials.new('V4_'+name); m.diffuse_color=(*rgb,1); m.use_nodes=True; m.use_backface_culling=True
 m['source_srgb_hex']='#'+h; m['usage']='Original v4 palette; retain base albedo under runtime cel shader.'
 nd=m.node_tree.nodes; nd.clear()
 out=nd.new('ShaderNodeOutputMaterial');out.name='Material Output';out.location=(620,100)
 bs=nd.new('ShaderNodeBsdfPrincipled');bs.name='SOURCE_GLTF';bs.label='SOURCE GLTF BASE ALBEDO';bs.location=(150,-230)
 bs.inputs['Base Color'].default_value=(*rgb,1);bs.inputs['Roughness'].default_value=.88
 # Quantized diffuse studio proof, with a separate clean PBR export path.
 df=nd.new('ShaderNodeBsdfDiffuse');df.location=(-650,120);df.inputs['Color'].default_value=(1,1,1,1)
 sh=nd.new('ShaderNodeShaderToRGB');sh.location=(-450,120)
 ramp=nd.new('ShaderNodeValToRGB');ramp.location=(-250,120);ramp.color_ramp.interpolation='CONSTANT'
 cr=ramp.color_ramp;cr.elements.remove(cr.elements[1]);cr.elements[0].position=.0;cr.elements[0].color=(.37,.45,.64,1)
 for p,c in ((.24,(.68,.73,.82,1)),(.51,(1,1,1,1))):
  e=cr.elements.new(p);e.color=c
 mul=nd.new('ShaderNodeMixRGB');mul.blend_type='MULTIPLY';mul.inputs[0].default_value=1;mul.inputs[2].default_value=(*rgb,1);mul.location=(0,100)
 em=nd.new('ShaderNodeEmission');em.location=(400,100);em.inputs['Strength'].default_value=1
 link=m.node_tree.links;link.new(df.outputs[0],sh.inputs[0]);link.new(sh.outputs[0],ramp.inputs[0]);link.new(ramp.outputs[0],mul.inputs[1]);link.new(mul.outputs[0],em.inputs[0]);link.new(em.outputs[0],out.inputs[0]);MAT[name]=m
COL=None;PARENT=None;CAST=[]
def move_to(o):
 for c in list(o.users_collection):c.objects.unlink(o)
 COL.objects.link(o)
def empty(n,loc=(0,0,0),parent=None):
 o=bpy.data.objects.new(n,None);COL.objects.link(o);o.location=loc;o.parent=parent;return o
def finish(o,n,mat,sm=True,parent=None):
 o.name=n;move_to(o)
 if mat:o.data.materials.append(MAT[mat])
 if o.type=='MESH':
  for f in o.data.polygons:f.use_smooth=sm
 par=PARENT if parent is None else parent
 if par:
  bpy.context.view_layer.update();o.parent=par;o.matrix_parent_inverse=par.matrix_world.inverted()
 return o
def uv(n,loc,scale,mat,segments=20,rings=12):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=loc)
 o=bpy.context.object;o.scale=scale
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 return finish(o,n,mat)
def box(n,loc,scale,mat,bevel=.06,rot=(0,0,0)):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc,rotation=rot)
 o=bpy.context.object;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('Soft tailored volume','BEVEL');mod.width=bevel;mod.segments=3
  bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 return finish(o,n,mat)
def mesh(n,verts,faces,mat,sm=True):
 me=bpy.data.meshes.new(n);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(n,me);COL.objects.link(o)
 if mat:me.materials.append(MAT[mat])
 for f in me.polygons:f.use_smooth=sm
 if PARENT:
  bpy.context.view_layer.update();o.parent=PARENT;o.matrix_parent_inverse=PARENT.matrix_world.inverted()
 return o
def tube(n,pts,r,mat):
 cu=bpy.data.curves.new(n,'CURVE');cu.dimensions='3D';cu.resolution_u=8;cu.bevel_depth=r;cu.bevel_resolution=2;cu.use_fill_caps=True
 sp=cu.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for p,co in zip(sp.bezier_points,pts):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
 o=bpy.data.objects.new(n,cu);COL.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True)
 bpy.ops.object.convert(target='MESH');o=bpy.context.object;o.select_set(False)
 return finish(o,n,mat)
def limb(n,a,b,width,depth,mat):
 a=Vector(a);b=Vector(b);mid=(a+b)*.5
 o=uv(n,mid,(width,depth,(b-a).length/2+width*.55),mat,16,10)
 o.rotation_mode='QUATERNION';o.rotation_quaternion=Vector((0,0,1)).rotation_difference(b-a);return o
def tuft(n,centres,widths,depths,mat):
 # Lozenge cross-sections swept along a curved XZ path: a substantial solid lock.
 verts=[];faces=[];seg=10
 for j,(co,w,d) in enumerate(zip(centres,widths,depths)):
  co=Vector(co);tangent=Vector(centres[min(j+1,len(centres)-1)])-Vector(centres[max(0,j-1)])
  tangent.y=0;tangent.normalize();side=Vector((tangent.z,0,-tangent.x))
  for i in range(seg):
   a=i*2*math.pi/seg;v=co+side*(math.cos(a)*w)+Vector((0,math.sin(a)*d,0));verts.append(tuple(v))
 faces.append(tuple(reversed(range(seg))))
 for j in range(len(centres)-1):
  for i in range(seg):q=(i+1)%seg;faces.append((j*seg+i,j*seg+q,(j+1)*seg+q,(j+1)*seg+i))
 faces.append(tuple(range((len(centres)-1)*seg,len(centres)*seg)))
 return mesh(n,verts,faces,mat)
def hair_cap(n,center,radii,mat,front_cut=.98):
 # Hair is a closed, round shell. The front hairline lifts clear of the eyes.
 cx,cy,cz=center;rx,ry,rz=radii;N=32;R=10;verts=[];faces=[]
 for j in range(R+1):
  t=j/R
  for i in range(N):
   ph=2*math.pi*i/N;front=max(0,-math.sin(ph))
   theta=t*(2.18-(2.18-front_cut)*front**2)
   verts.append((cx+rx*math.sin(theta)*math.cos(ph),cy+ry*math.sin(theta)*math.sin(ph),cz+rz*math.cos(theta)))
 for j in range(R):
  for i in range(N):q=(i+1)%N;faces.append((j*N+i,j*N+q,(j+1)*N+q,(j+1)*N+i))
 # The underside is closed, never presented as a face decal.
 v=len(verts);verts.append((cx,cy,cz-.18))
 for i in range(N):faces.append((R*N+i,R*N+(i+1)%N,v))
 return mesh(n,verts,faces,mat)
FACE=(0,0,1.89);RAD=(.438,.346,.402)
def face_y(x,z,offset):
 xx=(x-FACE[0])/RAD[0];zz=(z-FACE[2])/RAD[2]
 return FACE[1]-RAD[1]*math.sqrt(max(.06,1-xx*xx-zz*zz))-offset
def smooth_outline(pts,steps=4):
 out=[]
 for i,p1 in enumerate(pts):
  p0=pts[(i-1)%len(pts)];p2=pts[(i+1)%len(pts)];p3=pts[(i+2)%len(pts)]
  for j in range(steps):
   t=j/steps;t2=t*t;t3=t2*t
   out.append(tuple(.5*((2*p1[k])+(-p0[k]+p2[k])*t+(2*p0[k]-5*p1[k]+4*p2[k]-p3[k])*t2+(-p0[k]+3*p1[k]-3*p2[k]+p3[k])*t3) for k in (0,1)))
 return out

def patch(n,outline,mat,offset=.016,bulge=.0):
 # Four curved radial rings prevent large flat chord triangles from sinking
 # into the head. Each visible layer has at least 0.008m depth separation.
 if 'EyeInkRim' in n or n=='Eye_White' or n in ('Face_SmileInk','Face_SmileTongue'):
  outline=smooth_outline(outline,4)
 cx=sum(v[0] for v in outline)/len(outline);cz=sum(v[1] for v in outline)/len(outline)
 verts=[(cx,face_y(cx,cz,offset+bulge),cz)];faces=[];N=len(outline);R=4
 for ring in range(1,R+1):
  t=ring/R
  for x,z in outline:
   xx=cx+(x-cx)*t;zz=cz+(z-cz)*t
   verts.append((xx,face_y(xx,zz,offset+bulge*(1-t*t)),zz))
 for i in range(N):faces.append((0,1+i,1+(i+1)%N))
 for r in range(R-1):
  st=1+r*N;nx=st+N
  for i in range(N):j=(i+1)%N;faces.append((st+i,nx+i,nx+j,st+j))
 return mesh(n,verts,faces,mat)
def ellipse(n,cx,cz,rx,rz,mat,offset=.02,npts=24,tilt=0):
 outline=[]
 for i in range(npts):
  a=2*math.pi*i/npts;x=math.cos(a)*rx;z=math.sin(a)*rz
  outline.append((cx+x*math.cos(tilt)-z*math.sin(tilt),cz+x*math.sin(tilt)+z*math.cos(tilt)))
 return patch(n,outline,mat,offset)
def face_line(n,pts,r,mat,offset=.025):return tube(n,[(x,face_y(x,z,offset),z) for x,z in pts],r,mat)
def eyes(kind):
 for s in [-1,1]:
  c=s*.184;z=1.867
  # Upper-lid weighted anime eyes with an open lower half.
  rim=[(c-.128,z+.076),(c-.080,z+.139),(c+.026,z+.139),(c+.126,z+.090),(c+.129,z-.057),(c+.075,z-.121),(c-.035,z-.127),(c-.123,z-.068)]
  patch(('Left' if s<0 else 'Right')+'_EyeInkRim',rim,'InkNavy',.017)
  white=[(c+(x-c)*.83,z+(zz-z)*.84-.005) for x,zz in rim]
  patch('Eye_White',white,'Cream',.026)
  irisx=c+(.012 if kind==0 else -.014);irisy=z-.01
  ellipse('Eye_ColoredIris',irisx,irisy,.057,.093,'IrisCyan' if kind==0 else 'IrisAmber',.037)
  ellipse('Eye_DarkPupil',irisx+.002,irisy+.006,.026,.073,'InkNavy',.045)
  ellipse('Eye_Catchlight',irisx-.021,irisy+.046,.023,.026,'Cream',.054)
  ellipse('Eye_LowerCatchlight',irisx+.021,irisy-.052,.010,.014,'Cream',.052,npts=12)
  # Heavy short upper lid, projected over the actual eye surface.
  face_line('Face_UpperLash',[(c-.116,z+.083),(c-.055,z+.133),(c+.045,z+.131),(c+.126,z+.076)],.014,'InkNavy',.034)
  if kind==0:
   outer=c+s*.13
   face_line('Face_OuterLash',[(outer-s*.022,z+.10),(outer+s*.035,z+.13)],.013,'InkNavy',.026)
  browz=2.062+(s*.014 if kind else 0)
  face_line('Face_Brow',[(c-.082,browz-.010),(c-.018,browz+.021),(c+.057,browz+.006)],.015,'HairBlue' if kind==0 else 'HairBrown',.013)
 # Warm cheek masses remain readable at the 100-pixel runtime scale.
 for s in [-1,1]:ellipse('Face_Cheek',s*.308,1.710,.048,.023,'Coral',.012,npts=16,tilt=s*-.16)
 uv('Face_TinyNose',(0,face_y(0,1.735,.025),1.735),(.028,.025,.032),'SkinPeach',12,8)
 if kind==0:
  ellipse('Face_SmileInk',.003,1.624,.073,.046,'InkNavy',.025,tilt=.10)
  ellipse('Face_SmileTongue',.010,1.603,.041,.017,'Coral',.035)
  patch('Face_SmileTooth',[(-.055,1.653),(.059,1.658),(.038,1.633),(-.033,1.631)],'Cream',.037)
 else:
  face_line('Face_QuietSmile',[(-.055,1.626),(.009,1.614),(.068,1.648)],.013,'InkNavy',.025)

def glove(n,center,mat='Cream',tilt=0,open_palm=False):
 x,y,z=center
 if open_palm:
  uv(n+'_OpenPalm',(x,y,z),(.148,.144,.067),mat,16,10)
  uv(n+'_Thumb',(x-.111 if x>0 else x+.111,y+.016,z+.041),(.063,.084,.057),mat,12,8)
  return
 o=uv(n+'_Palm',(x,y,z),(.13,.115,.14),mat,16,10);o.rotation_euler.y=tilt
 uv(n+'_Thumb',(x-.108 if x>0 else x+.108,y-.022,z+.025),(.061,.074,.082),mat,12,8)

def actor(kind):
 global COL,PARENT,FACE,RAD
 label='Courier_Clerk' if kind==0 else 'Customer';fn='clerk' if kind==0 else 'customer'
 COL=bpy.data.collections.new(label+'_V4');bpy.context.scene.collection.children.link(COL)
 root=empty(label+'_Root');piv={}
 for n,co in [('BodyPivot',(0,0,1.07)),('HeadPivot',(0,0,1.53)),('LeftArmPivot',(-.31,0,1.36)),('RightArmPivot',(.31,0,1.36)),('LeftLegPivot',(-.18,0,.73)),('RightLegPivot',(.18,0,.73))]:piv[n]=empty(n,co,root)
 # Tiny barrel torso and cropped padded coat, with genuinely round shoulder/waist volume.
 PARENT=piv['BodyPivot'];shirt='InkNavy';jacket='CourierYellow' if kind==0 else 'Cream'
 uv('Body_TinyTorso',(0,.018,1.105),(.323,.216,.386),jacket,20,12)
 box('Body_CroppedHem',(0,0,.803),(.57,.40,.115),'InkNavy',.048)
 # Open jacket reveals a narrow deep-blue insert without a coplanar overlay.
 box('Body_ShirtInsert',(0,-.209,1.15),(.17,.063,.50),'InkNavy',.04)
 for s in [-1,1]:
  o=box('Body_PuffyJacketFront',(s*.17,-.158,1.133),(.225,.145,.525),jacket,.063);o.rotation_euler.y=s*-.05
  o=box('Body_FoldedCollar',(s*.114,-.155,1.425),(.22,.15,.135),'Cream' if kind==0 else 'InkNavy',.045);o.rotation_euler.y=s*.35
 if kind==0:
  box('Body_CourierBadge',(-.194,-.25,1.269),(.115,.037,.096),'InkNavy',.018)
  box('Body_BadgeStripe',(-.194,-.274,1.269),(.069,.024,.020),'Cream',.008)
  for s in [-1,1]:box('Body_PocketRim',(s*.20,-.235,.995),(.126,.045,.032),'Cream',.010)
 else:
  # A substantial, rounded cross-body parcel satchel; same body palette limits surfaces.
  tube('Body_SatchelStrap',[(-.27,-.02,1.439),(-.09,-.243,1.29),(.18,-.262,1.035),(.34,-.19,.892)],.052,'InkNavy')
  box('Body_ChunkySatchel',(.386,-.020,.874),(.39,.40,.47),'InkNavy',.080,rot=(0,-.10,-.04))
  box('Body_SatchelFlap',(.397,-.241,.948),(.34,.082,.255),'RustOchre',.049,rot=(0,-.10,-.04))
  box('Body_SatchelClasp',(.395,-.294,.908),(.085,.036,.11),'Cream',.020)
  box('Body_ParkaPocket',(-.20,-.226,.966),(.175,.065,.16),'RustOchre',.045)
 # Plump short legs and enlarged boot/toe blocks, standing on Y=0 after export.
 for s in [-1,1]:
  PARENT=piv['LeftLegPivot' if s<0 else 'RightLegPivot'];x=s*.177
  limb('Leg_ChunkyTrouser',(x,0,.76),(x+s*.012,-.005,.26),.122,.132,'InkNavy')
  box('Leg_BootSole',(x,-.103,.049),(.315,.448,.098),'InkNavy',.035)
  box('Leg_BigBootUpper',(x,-.105,.174),(.291,.423,.218),'Cream',.075)
  box('Leg_BootAnkle',(x,.005,.273),(.256,.261,.17),'Cream',.055)
  box('Leg_BootTongue',(x,-.191,.249),(.107,.045,.10),'InkNavy',.020)
 # Each whole bent arm and glove is a rigid editing pivot. No skeleton claim.
 for s in [-1,1]:
  PARENT=piv['LeftArmPivot' if s<0 else 'RightArmPivot']
  if kind==0 and s==1:
   shoulder=(.305,0,1.358);elbow=(.446,-.100,1.035);wrist=(.377,-.418,1.105);hand=(.334,-.585,1.15535)
  elif kind==0 and s==-1:
   shoulder=(-.305,0,1.358);elbow=(-.461,-.105,1.050);wrist=(-.517,-.403,1.122);hand=(-.573,-.605,1.17635)
  elif kind==1 and s==1:
   shoulder=(.316,0,1.349);elbow=(.487,-.022,1.135);wrist=(.605,-.205,1.308);hand=(.652,-.361,1.409)
  else:
   shoulder=(s*.306,0,1.349);elbow=(s*.455,.008,1.151);wrist=(s*.452,-.141,.998);hand=(s*.461,-.162,.887)
  limb('Arm_RoundUpperSleeve',shoulder,elbow,.125,.138,jacket)
  limb('Arm_BentForeSleeve',elbow,wrist,.119,.125,jacket)
  limb('Arm_BroadCuff',Vector(wrist)*.85+Vector(hand)*.15,Vector(wrist)*.55+Vector(hand)*.45,.121,.125,'Cream' if kind==0 else 'InkNavy')
  glove('Hand_Gesture',hand,'Cream',open_palm=(kind==0))
  anchor=empty(('Left' if s<0 else 'Right')+'Palm_Anchor',hand)
  bpy.context.view_layer.update();anchor.parent=PARENT;anchor.matrix_parent_inverse=PARENT.matrix_world.inverted()
 # Oversize head and facial features.
 PARENT=piv['HeadPivot'];FACE=(0,0,1.885);RAD=(.438,.346,.402)
 uv('Head_Neck',(0,0,1.515),(.099,.094,.121),'SkinPeach',16,10)
 uv('Head_RoundedFace',FACE,RAD,'SkinPeach',32,20)
 for s in [-1,1]:
  uv('Head_Ear',(s*.424,.014,1.816),(.084,.080,.108),'SkinPeach',16,10)
 eyes(kind)
 anchor=empty('FaceLook_Anchor',(0,-.39,1.875))
 bpy.context.view_layer.update();anchor.parent=PARENT;anchor.matrix_parent_inverse=PARENT.matrix_world.inverted()
 if kind==0:
  hair_cap('Hair_RoundBob',(0,.027,1.935),(.521,.419,.476),'HairBlue',front_cut=.93)
  # Eight broad sculpted locks read clearly even when the actor is only 110px high.
  tuft('Hair_SweptLeft',[(-.025,-.035,2.33),(-.191,-.201,2.259),(-.353,-.263,2.121),(-.405,-.234,1.989)],[.095,.172,.141,.006],[.065,.106,.087,.004],'HairCyan')
  tuft('Hair_FrontFringe',[(.136,-.055,2.326),(.071,-.283,2.230),(-.010,-.338,2.096),(.035,-.340,1.989)],[.107,.145,.094,.005],[.070,.100,.057,.005],'HairBlue')
  tuft('Hair_RightSweep',[(.201,-.003,2.307),(.354,-.158,2.223),(.477,-.170,2.074),(.607,-.020,2.028)],[.108,.152,.119,.005],[.083,.116,.103,.005],'HairBlue')
  tuft('Hair_RightLightLock',[(.252,.007,2.312),(.394,-.130,2.236),(.494,-.12,2.146)],[.023,.054,.004],[.025,.035,.004],'HairCyan')
  tuft('Hair_LeftSide',[(-.397,.014,2.111),(-.486,-.05,1.980),(-.492,-.045,1.742),(-.414,-.04,1.610)],[.092,.128,.115,.007],[.110,.133,.113,.005],'HairBlue')
  tuft('Hair_RightSide',[(.404,.068,2.093),(.513,.029,1.969),(.535,.045,1.737),(.429,-.026,1.593)],[.089,.140,.135,.006],[.110,.155,.102,.005],'HairBlue')
  tuft('Hair_BackFlick',[(.40,.24,1.922),(.568,.22,1.822),(.635,.18,1.863)],[.07,.085,.004],[.077,.075,.003],'HairCyan')
  tuft('Hair_Cowlick',[(.025,.088,2.302),(.068,.084,2.455),(.213,.10,2.442)],[.064,.082,.004],[.055,.057,.003],'HairBlue')
  box('Hair_YellowClip',(-.421,-.209,2.032),(.159,.061,.045),'CourierYellow',.014,rot=(0,-.62,0))
 else:
  hair_cap('Hair_CustomerBack',(0,.021,1.94),(.474,.382,.414),'HairBrown',front_cut=1.12)
  tuft('Hair_CustomerFringe',[(-.177,-.18,2.200),(-.105,-.328,2.143),(.035,-.338,2.039)],[.093,.116,.005],[.081,.084,.005],'HairBrown')
  for s in [-1,1]:
   tuft('Hair_CustomerSide',[(s*.351,.019,2.066),(s*.427,-.021,1.919),(s*.401,-.015,1.750)],[.098,.091,.006],[.089,.083,.005],'HairBrown')
  uv('Head_SoftCapCrown',(0,.048,2.181),(.505,.403,.267),'InkNavy',24,12)
  # Curved thick bill catches light and casts an honest 3D shadow over the brow.
  box('Head_CapBand',(0,-.080,2.140),(.873,.476,.116),'InkNavy',.055)
  uv('Head_CapBill',(.055,-.312,2.111),(.468,.251,.062),'InkNavy',24,8)
  box('Head_CapCreamPatch',(-.128,-.327,2.253),(.147,.049,.105),'Cream',.019,rot=(.05,-.10,-.07))
  box('Head_CapPatchBar',(-.130,-.359,2.255),(.083,.019,.025),'InkNavy',.004)
 PARENT=None
 # Normalize the exact model height to 2.4m, preserving floor-origin contract.
 bpy.context.view_layer.update(); allmesh=[o for o in COL.objects if o.type=='MESH']
 allpts=[o.matrix_world@Vector(v) for o in allmesh for v in o.bound_box];zmin=min(v.z for v in allpts);zmax=max(v.z for v in allpts)
 sf=2.4/(zmax-zmin)
 root.scale=(sf,sf,sf);root.location.z=-zmin*sf
 root['art_version']='v4 isolated original dimensional Q study';root['height_m']=2.4;root['front_axis']='glTF +Z';root['rig_type']='Named rigid part pivots only; NOT Spine, no skeleton or animation export.'
 CAST.append({'root':root,'collection':COL,'pivots':piv,'filename':fn,'height_m':2.4,'authoring_scale':sf})
 return root
actor(0);actor(1)

# Join by pivot, keeping palette material count modest and animation-friendly names.
for cast in CAST:
 for pn,pivot in cast['pivots'].items():
  obs=[o for o in cast['collection'].objects if o.type=='MESH' and o.parent==pivot]
  if not obs:continue
  bpy.ops.object.select_all(action='DESELECT')
  part_names=[o.name for o in obs]
  for o in obs:
   o.select_set(True);vg=o.vertex_groups.new(name=o.name);vg.add(list(range(len(o.data.vertices))),1.0,'REPLACE')
  bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();o=bpy.context.object;o.name=cast['filename']+'_'+pn.replace('Pivot','')+'_Volume';o['editable_part_names']=part_names
  # Recalculate closed-volume normals, but keep curved face patches front-facing.
  bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000001);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update()
  # Custom face-layer surfaces are open and must face camera, not inside the head.
  # Their original projected winding is outward -Y; connected volume normals are handled above.
  # Deduplicate palette slots left by join.
  unique=[];remap={}
  for i,m in enumerate(o.data.materials):
   if m not in unique:unique.append(m)
   remap[i]=unique.index(m)
  inds=[remap[p.material_index] for p in o.data.polygons];o.data.materials.clear()
  for m in unique:o.data.materials.append(m)
  for p,idx in zip(o.data.polygons,inds):p.material_index=idx

# Export each cast while the clean source albedo node is active.
for m in MAT.values():
 nt=m.node_tree;out=nt.nodes.get('Material Output');nt.links.new(nt.nodes['SOURCE_GLTF'].outputs['BSDF'],out.inputs['Surface'])
for cast in CAST:
 bpy.ops.object.select_all(action='DESELECT')
 for o in cast['collection'].objects:o.select_set(True)
 bpy.context.view_layer.objects.active=cast['root']
 bpy.ops.export_scene.gltf(filepath=str(OUT/(cast['filename']+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_materials='EXPORT',export_extras=True,export_animations=False,export_cameras=False,export_lights=False)
for m in MAT.values():
 nt=m.node_tree;nt.links.new(next(n for n in nt.nodes if n.type=='EMISSION').outputs[0],nt.nodes['Material Output'].inputs['Surface'])

# Metadata from actual evaluated source meshes.
manifest={'direction':'Original dimensional Q cast for approved pixel-cel workshop; isolated studies only','reference_pixels':[1672,941],'runtime_integration':False,'spine_status':'Not exported or bound. Actual editor/license not available. Named Blender pivots are not Spine.', 'coordinate_contract':{'up':'+Y','front':'+Z','floor':0,'height':2.4,'counter_top':1.3,'clerk_dais_height':.25},'palette':{'V4_'+k:'#'+v for k,v in PALETTE.items()},'actors':[]}
for c in CAST:
 obs=[o for o in c['collection'].objects if o.type=='MESH'];tris=0
 for o in obs:o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
 mats=set(m.name for o in obs for m in o.data.materials)
 manifest['actors'].append({'filename':c['filename']+'.glb','height':2.4,'mesh_nodes':len(obs),'triangles':tris,'palette_materials':len(mats),'material_surfaces':sum(len(o.data.materials) for o in obs),'named_pivots':list(c['pivots']),'authoring_scale':c['authoring_scale']})
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
(SRC/'palette.json').write_text(json.dumps({'color_space':'sRGB source hex; Blender/GLB linear factors','materials':manifest['palette']},indent=2))

# Studio used only for proof images, never included in the GLBs.
COL=bpy.data.collections.new('Proof_Studio_NOT_EXPORTED');bpy.context.scene.collection.children.link(COL)
PARENT=None
floor=bpy.data.materials.new('Studio_Floor');floor.diffuse_color=(.079,.10,.16,1);floor.use_nodes=True;bs=floor.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.079,.10,.16,1);bs.inputs['Roughness'].default_value=1
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.013));o=bpy.context.object;o.name='Studio_Floor';move_to(o);o.data.materials.append(floor)
scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE_NEXT';scene.render.resolution_percentage=100
scene.world.color=(.25,.25,.25);scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.30,.38,.5,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.5
scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast';scene.view_settings.exposure=0;scene.view_settings.gamma=1
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.render.image_settings.color_mode='RGBA';scene.render.engine='BLENDER_EEVEE_NEXT';scene.eevee.taa_render_samples=32
scene.render.resolution_x=1200;scene.render.resolution_y=900
for name,loc,power,size in [('Key',(-3,-5,7),650,4.5),('Fill',(4,-2,4),240,4),('Rim',(2,4,5),550,3)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name='Studio_'+name;move_to(o);o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,1.3))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(3,-8,4));cam=bpy.context.object;move_to(cam);cam.name='Proof_Camera';cam.data.type='ORTHO';scene.camera=cam

def show_positions(yaws=(0,0),spread=1.15):
 for i,c in enumerate(CAST):c['root'].location.x=(-spread if i==0 else spread);c['root'].rotation_euler.z=math.radians(yaws[i])

def point_camera(loc,target,scale):
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale

def render(name,loc,target,scale,size=(1200,900)):
 point_camera(loc,target,scale);scene.render.resolution_x,scene.render.resolution_y=size;scene.render.filepath=str(PROOF/name);bpy.ops.render.render(write_still=True)

show_positions((0,0))
point_camera((0,-9,3.1),(0,0,1.20),5.25)
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'star_courier_q_cast_v4.blend'))
if not SKIP_RENDER:
 render('01-neutral-front.png',(0,-9,2.95),(0,0,1.20),5.25)
 show_positions((-20,20))
 render('02-dimensional-three-quarter.png',(0,-9,3.3),(0,0,1.20),5.25)
 # Exchange gestures are only an editable rigid-part pose preview.
 show_positions((-12,12),1.05)
 CAST[0]['pivots']['HeadPivot'].rotation_euler.y=math.radians(-6)
 CAST[0]['pivots']['LeftArmPivot'].rotation_euler.y=math.radians(8)
 CAST[1]['pivots']['HeadPivot'].rotation_euler.y=math.radians(5)
 CAST[1]['pivots']['RightArmPivot'].rotation_euler.y=math.radians(-8)
 render('03-exchange-pose.png',(0,-9,3.1),(0,0,1.20),5.10)
 render('04-hub-size-proof.png',(0,-9,3.1),(0,0,1.20),5.10,(270,200))
 for c in CAST:
  for p in c['pivots'].values():p.rotation_euler=(0,0,0)
 show_positions((0,0))
 render('05-face-closeups.png',(0,-9,2.4),(0,0,1.84),3.94,(1200,560))
 # Restore to the saved neutral source studio, with zero gesture deltas.
 show_positions((0,0));point_camera((0,-9,3.1),(0,0,1.20),5.25)
 scene.render.resolution_x=1200;scene.render.resolution_y=900
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'star_courier_q_cast_v4.blend'))
print('V4_CAST_COMPLETE',json.dumps(manifest['actors']))
