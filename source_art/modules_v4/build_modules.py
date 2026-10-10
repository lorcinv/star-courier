"""Original Star Courier V4 functional starter modules, Blender 4.3.2.
Run: /usr/bin/blender -b -t 4 --python-exit-code 1 --python source_art/modules_v4/build_modules.py
Options after --: --skip-render
Authoring uses Godot-space X forward / Y up / Z toward camera. Export rotates to Blender then back to glTF Y-up.
Every export is an independent physical module with identity root and legacy cardinal sockets at 0.6 m.
"""
import bpy, bmesh, math, json, sys, struct
from pathlib import Path
from mathutils import Vector, Matrix
from collections import defaultdict
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'source_art/modules_v4'; OUT=ROOT/'assets/modules_v4'; PROOF=SRC/'proofs'
for p in (SRC,OUT,PROOF):p.mkdir(parents=True,exist_ok=True)
SKIP_RENDER='--skip-render' in sys.argv
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
 if c.name!='Collection':bpy.data.collections.remove(c)
PALETTE={
 'InkNavy':'18273d','Cobalt':'31597d','CourierYellow':'eab32c','Ochre':'cf8529',
 'Cream':'ffebbe','Metal':'8696a5','GlassBlue':'285274','CyanGlow':'53d8e6',
 'WarmGlow':'fff2bf'}
MATS={}
def linear(v):return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4
for name,h in PALETTE.items():
 rgb=tuple(linear(int(h[i:i+2],16)/255) for i in (0,2,4))
 m=bpy.data.materials.new('V4_'+name);m.use_nodes=True;m.diffuse_color=(*rgb,1);m.use_backface_culling=True
 m['source_srgb_hex']='#'+h;m['render_contract']='Retain source albedo; actual runtime lighting supplies cel bands.'
 p=m.node_tree.nodes.get('Principled BSDF');p.name='SOURCE_GLTF';p.inputs['Base Color'].default_value=(*rgb,1);p.inputs['Roughness'].default_value=.78
 if 'Glow' in name:p.inputs['Emission Color'].default_value=(*rgb,1);p.inputs['Emission Strength'].default_value=.45
 MATS[name]=m

def bco(v):x,y,z=v;return (x,-z,y)
def new_mesh(name,verts,faces,mat,col,parent=None):
 me=bpy.data.meshes.new(name);me.from_pydata([bco(v) for v in verts],[],faces);me.update()
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 me.materials.append(MATS[mat]);ob=bpy.data.objects.new(name,me);col.objects.link(ob)
 if parent:ob.parent=parent
 return ob
class Module:
 def __init__(self,name,x,description):
  self.name=name;self.x=x;self.description=description;self.parts=[]
  self.col=bpy.data.collections.new('SOURCE / '+name);bpy.context.scene.collection.children.link(self.col)
  self.root=bpy.data.objects.new(name+'_SOURCE',None);self.col.objects.link(self.root);self.root.empty_display_size=.18
  self.root['functional_module']=name;self.root['grid_position']=[x,0];self.root['grid_spacing_m']=1.0
  for side,pos in [('Right',(.6,0,0)),('Left',(-.6,0,0)),('Top',(0,.6,0)),('Bottom',(0,-.6,0))]:
   socket=bpy.data.objects.new(name+'__Socket_'+side,None);self.col.objects.link(socket);socket.parent=self.root;socket.location=bco(pos);socket.empty_display_size=.045;socket['export_name']='Socket_'+side
 def mesh(self,name,verts,faces,mat):
  o=new_mesh(name,verts,faces,mat,self.col,self.root);self.parts.append(o);return o
 def box(self,name,p,s,mat,bevel=.035):
  x,y,z=p;a,b,c=[v*.5 for v in s]
  v=[(x-a,y-b,z-c),(x+a,y-b,z-c),(x+a,y+b,z-c),(x-a,y+b,z-c),(x-a,y-b,z+c),(x+a,y-b,z+c),(x+a,y+b,z+c),(x-a,y+b,z+c)]
  o=self.mesh(name,v,[(0,3,2,1),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5),(4,5,6,7)],mat)
  if bevel:
   mod=o.modifiers.new('One-cut machined edge','BEVEL');mod.width=bevel;mod.segments=1
   bpy.context.view_layer.objects.active=o; o.select_set(True);bpy.ops.object.modifier_apply(modifier=mod.name);o.select_set(False)
  return o
 def profile(self,name,points,z0,z1,mat,bevel=0):
  n=len(points);v=[(x,y,z) for z in (z0,z1) for x,y in points]
  f=[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
  o=self.mesh(name,v,f,mat)
  if bevel:
   mod=o.modifiers.new('Chamfered plate edges','BEVEL');mod.width=bevel;mod.segments=1
   bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.modifier_apply(modifier=mod.name);o.select_set(False)
  return o
 def cylinder(self,name,p,r,depth,mat,axis='X',sides=12):
  rings=[]
  for d in [-depth*.5,depth*.5]:
   ring=[]
   for i in range(sides):
    a=math.tau*(i+.5)/sides;u=math.cos(a)*r;v=math.sin(a)*r
    q=(d,u,v) if axis=='X' else ((u,d,v) if axis=='Y' else (u,v,d))
    ring.append(tuple(p[j]+q[j] for j in range(3)))
   rings.append(ring)
  verts=rings[0]+rings[1];faces=[tuple(reversed(range(sides))),tuple(range(sides,sides*2))]
  faces +=[(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
  return self.mesh(name,verts,faces,mat)
 def annulus(self,name,x0,x1,r0,r1,inner0,inner1,mat,cy=-.04,sides=16):
  rings=[]
  for x,r in [(x0,r0),(x1,r1),(x1,inner1),(x0,inner0)]:
   rings.extend([(x,cy+math.cos(math.tau*(i+.5)/sides)*r,math.sin(math.tau*(i+.5)/sides)*r) for i in range(sides)])
  faces=[]
  for k in range(4):
   for j in range(sides):faces.append((k*sides+j,k*sides+(j+1)%sides,((k+1)%4)*sides+(j+1)%sides,((k+1)%4)*sides+j))
  return self.mesh(name,rings,faces,mat)
 def beam(self,name,a,b,w,d,mat):
  # Ribbon strut in the front-facing X/Y plane with a real box cross-section.
  aa=Vector(a);bb=Vector(b);dr=bb-aa;cross=Vector((-dr.y,dr.x,0)).normalized()*w/2
  pts=[aa-cross,bb-cross,bb+cross,aa+cross]
  return self.profile(name,[(v.x,v.y) for v in pts],a[2]-d/2,a[2]+d/2,mat,.008)
 def panel(self,name,verts,faces,mat,normal=(0,0,1)):
  # Adjacent glazing layers use parallel, planar facets. This prevents polygon triangulation from
  # crossing a shallower neighboring layer and creating accidental dark triangles in the glass.
  front_planes={'Deep canopy perimeter':.368,'Broad dark canopy pane':.379,'Canopy dark lower facet':.387,
   'Broad cyan sky reflection':.396,'Cream chin shoulder trim':.378,'Upper cab deep canopy perimeter':.358,
   'Upper cab broad blue glazing':.371,'Upper cab darker lower facet':.381,'Upper cab cyan reflection':.391,
   'Upper cab cream roof brow':.371}
  if name in front_planes:verts=[(x,y,front_planes[name]-.18*x) for x,y,z in verts]
  # Closed, 6 mm-thick inset panel. Explicit volume guarantees correct outward normals with backface culling.
  n=len(verts);nv=Vector(normal)*.006
  v=list(verts)+[tuple(Vector(p)-nv) for p in verts]
  f=[tuple(range(n)),tuple(reversed(range(n,n*2)))]+[(i,i+n,(i+1)%n+n,(i+1)%n) for i in range(n)]
  return self.mesh(name,v,f,mat)
 def panel_bolt(self,x,y,z,mat='Metal',r=.026):return self.cylinder('Captured hex fastener',(x,y,z),r,.018,mat,'Z',6)
 def export(self):
  # Keep component-level source meshes editable; only the export copies are batched by material.
  data=defaultdict(lambda:[[],[]]);bounds=[]
  for o in self.parts:
   mat=o.data.materials[0].name[3:];verts,faces=data[mat];offset=len(verts)
   for v in o.data.vertices:
    p=o.matrix_local@v.co;verts.append((p.x,p.z,-p.y));bounds.append((p.x,p.z,-p.y))
   faces.extend([tuple(offset+i for i in p.vertices) for p in o.data.polygons])
  col=bpy.data.collections.new('EXPORT / '+self.name);bpy.context.scene.collection.children.link(col)
  root=bpy.data.objects.new(self.name,None);col.objects.link(root);root['module_id']=self.name;root['cell_size_m']=1.0
  objs=[root]
  for mat,(v,f) in data.items():objs.append(new_mesh(self.name+'__'+mat,v,f,mat,col,root))
  for name,pos in [('Right',(.6,0,0)),('Left',(-.6,0,0)),('Top',(0,.6,0)),('Bottom',(0,-.6,0))]:
   o=bpy.data.objects.new('Socket_'+name,None);col.objects.link(o);o.location=bco(pos);o.parent=root;o.empty_display_size=.06;objs.append(o)
  bpy.ops.object.select_all(action='DESELECT')
  for o in objs:o.select_set(True)
  bpy.ops.export_scene.gltf(filepath=str(OUT/(self.name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_extras=True,export_apply=True,export_materials='EXPORT')
  for o in objs:bpy.data.objects.remove(o,do_unlink=True)
  bpy.data.collections.remove(col)
  lo=[min(p[i] for p in bounds) for i in range(3)];hi=[max(p[i] for p in bounds) for i in range(3)]
  triangles=sum(sum(max(0,len(f)-2) for f in d[1]) for d in data.values())
  self.root.location.x=self.x
  return {'id':self.name,'path':'res://assets/modules_v4/'+self.name+'.glb','role':self.description,'starter_grid':[self.x,0],
   'bounds_godot_m':{'min':[round(n,6) for n in lo],'max':[round(n,6) for n in hi]},'materials':['V4_'+n for n in data],
   'surface_count':len(data),'source_component_count':len(self.parts),'triangles':triangles,'root_transform':'identity','sockets_m':.6}

MODULES=[]
# The cargo is the front half of the fuselage, visibly a separate lockable postal hold.
m=Module('cargo_crate',0,'Yellow postal hold; independent cargo module with deep inset storage door');MODULES.append(m)
m.box('Dark lower load-bearing chassis',(0,-.245,0),(.96,.39,.73),'Ochre',.085)
m.box('Beveled yellow parcel fuselage',(0,.035,0),(.97,.90,.75),'CourierYellow',.085)
m.box('Cream raised roof cap',(0,.465,-.01),(.87,.095,.66),'Cream',.025)
m.box('Rear roof rail',(-.01,.508,-.205),(.75,.042,.075),'CourierYellow',.012)
m.box('Front roof rail',(-.01,.508,.205),(.75,.042,.075),'CourierYellow',.012)
m.box('Deep door seal',(0,.015,.374),(.79,.73,.065),'Ochre',.036)
m.box('Postal loading door',(-.012,.025,.410),(.697,.622,.036),'Ochre',.022)
m.box('Broad yellow door skin',(-.028,.060,.437),(.641,.518,.022),'CourierYellow',.020)
m.box('Door lower cream sill',(-.021,-.264,.443),(.681,.075,.028),'Cream',.012)
for yy in [-.16,.20]:m.box('Cream lift hinge',(-.363,yy,.435),(.071,.136,.055),'Cream',.01)
m.box('Inset latch surround',(.30,.026,.451),(.113,.19,.026),'InkNavy',.012)
m.box('Door lock',( .301,.036,.471),(.071,.091,.028),'Cream',.009)
m.box('Lock status',(.301,.102,.489),(.047,.033,.013),'CyanGlow',.002)
# Original geometric envelope marker; part of the door, not a copied carrier logo.
m.box('Cream shipping envelope badge',(-.069,.085,.454),(.282,.195,.015),'Cream',.007)
m.beam('Envelope flap left',(-.189,.147,.466),(-.066,.052,.466),.025,.010,'Cobalt')
m.beam('Envelope flap right',(-.066,.052,.466),(.055,.147,.466),.025,.010,'Cobalt')
m.box('Door recessed grip',(-.105,-.122,.455),(.24,.049,.021),'InkNavy',.007)
for x in [-.395,.395]:
 m.box('Cargo lower bumper',(x,-.409,.018),(.145,.114,.68),'CourierYellow',.018)
 m.panel_bolt(x,.382,.391)
m.box('Forward seam gasket',(.480,-.004,0),(.027,.79,.646),'Ochre',.007)

# A full-height shared midbody, with broad rails and quiet service recesses rather than a badge.
m=Module('beam',-1,'Full-height structural midbody; stackable yellow load rails and flush service plate');MODULES.append(m)
m.box('Structural midbody core',(0,-.014,0),(.97,.942,.652),'Ochre',.050)
m.box('Continuous yellow side body',(0,.008,.277),(.966,.924,.170),'CourierYellow',.035)
m.box('Rear structural yellow rail',(-.399,.002,.358),(.153,.882,.130),'CourierYellow',.020)
m.box('Front structural yellow rail',(.399,.002,.358),(.153,.882,.130),'CourierYellow',.020)
m.box('Lower cobalt load keel',(0,-.443,.001),(.969,.094,.652),'Ochre',.017)
m.box('Warm top structural spine',(0,.470,-.009),(.949,.047,.646),'Cream',.012)
m.box('Lower thin cream guard',(0,-.420,.376),(.921,.052,.071),'Cream',.009)
m.box('Recessed longitudinal service slot',(-.024,.018,.369),(.635,.367,.037),'Ochre',.018)
m.box('Broad body service panel',(-.024,.005,.395),(.565,.289,.025),'CourierYellow',.010)
for yy in [-.051,.045]:m.box('Long recessed structural channel',(-.071,yy,.414),(.415,.031,.016),'Cobalt',.003)
m.box('Small flush cyan status',(.236,.013,.416),(.041,.094,.018),'CyanGlow',.004)
m.box('Upper shoulder flat',(.014,.280,.377),(.675,.130,.055),'CourierYellow',.012)
for x in [-.399,.399]:
 for y in [-.358,.367]:m.panel_bolt(x,y,.432,'Metal',.024)
m.box('Forward honest module seam',(.484,-.004,0),(.028,.829,.588),'Ochre',.004)

# Two substantial energy canisters and a shallow raked tail fin, all still inside one physical cell.
m=Module('cell',-2,'Energy pack and tail-fin base; two exposed cartridge cells');MODULES.append(m)
m.box('Energy pack main shell',(0,-.044,0),(.949,.656,.624),'Ochre',.065)
m.box('Battery underside keel',(0,-.35,.005),(.86,.092,.59),'Cobalt',.027)
m.box('Cream energy enclosure',(0,.006,-.018),(.911,.590,.570),'Cream',.047)
m.box('Recessed power-cell bay',(0,-.024,.287),(.641,.458,.073),'Cobalt',.023)
for x in [-.166,.166]:
 m.cylinder('Octagonal energy cartridge',(x,-.016,.316),.119,.34,'Ochre','Y',10)
 m.cylinder('Cream upper terminal',(x,.162,.316),.122,.071,'Cream','Y',10)
 m.cylinder('Cream lower terminal',(x,-.193,.316),.122,.071,'Cream','Y',10)
 m.box('Cyan charge window',(x,-.01,.434),(.061,.21,.026),'CyanGlow',.006)
for x in [-.386,.386]:m.box('Yellow battery side shield',(x,-.018,.306),(.146,.554,.130),'CourierYellow',.018)
m.box('Yellow roof saddle',(0,.313,-.003),(.905,.116,.640),'CourierYellow',.025)
m.box('Cream roof leading strip',(.28,.372,-.002),(.18,.031,.58),'Cream',.008)
# Revised flush roof allows a cargo module immediately above it without a protruding fin.
m.box('Stackable yellow energy roof bridge',(0,.409,-.005),(.942,.196,.640),'CourierYellow',.022)
m.box('Flush cream energy roof saddle',(0,.488,-.005),(.872,.039,.582),'Cream',.009)
m.box('Upper recessed cooling slot',(0,.426,.326),(.574,.046,.023),'Cobalt',.006)
m.box('Battery underside continuous keel',(0,-.434,.006),(.917,.091,.651),'Cobalt',.018)
m.box('Battery seam to midbody',(.481,-.035,0),(.019,.518,.504),'Ochre',.003)
for x in [-.382,.382]:m.panel_bolt(x,-.242,.381,'Metal',.024)

# Hollow, layered 16-sided exhaust opens along negative X. No front cap cheats the cavity.
m=Module('thruster',-3,'Large recessed circular nozzle opening left, with layered rim and engine mount');MODULES.append(m)
m.box('Dark engine mounting backbone',(.246,-.011,0),(.447,.606,.568),'InkNavy',.04)
m.box('Yellow engine housing',(.273,.016,0),(.400,.570,.576),'CourierYellow',.038)
m.box('Cream coupling ring block',(.435,-.009,0),(.126,.685,.66),'Cream',.032)
m.cylinder('Rear turbine housing',(.033,-.04,0),.294,.40,'Cobalt','X',16)
m.annulus('Yellow shoulder collar',-.198,-.102,.346,.302,.205,.193,'CourierYellow')
m.annulus('Flared cobalt engine bell',-.481,-.176,.432,.345,.318,.207,'Cobalt')
m.annulus('Thick dark outer mouth',-.550,-.464,.420,.442,.322,.329,'InkNavy')
m.annulus('Cream machined mouth lip',-.565,-.528,.400,.420,.325,.322,'Cream')
m.annulus('Recessed inner dark tunnel',-.547,-.075,.319,.169,.292,.144,'InkNavy')
m.annulus('Inner bronze turbine ring',-.093,-.021,.173,.165,.115,.111,'Ochre')
m.cylinder('Deep turbine floor',(.027,-.04,0),.143,.033,'InkNavy','X',16)
m.cylinder('Small recessed ignition core',(.006,-.04,0),.068,.020,'CyanGlow','X',12)
m.box('Top engine spine',(.109,.300,-.006),(.594,.112,.43),'CourierYellow',.025)
m.box('Upper heat-shield highlight',(.148,.362,.003),(.41,.032,.33),'Cream',.010)
m.box('Engine service access',(.270,.025,.300),(.243,.309,.049),'Ochre',.015)
m.box('Service frame inset',(.270,.036,.333),(.166,.216,.019),'InkNavy',.010)
m.box('Engine cyan monitor',(.270,.061,.348),(.091,.087,.015),'CyanGlow',.004)
m.box('Lower cooling blade',(.210,-.325,.002),(.449,.073,.558),'Cobalt',.014)
m.panel_bolt(.282,-.192,.345,'Metal',.024)

# The lower forward armor shares the cab's outline and adds a broad cream impact bumper.
m=Module('armor',1,'Solid tapered lower nose and cream impact chin; no lower cockpit or second window');MODULES.append(m)
rings=[(-.486,-.442,.480,.351),(-.235,-.450,.480,.365),(.082,-.433,.477,.350),(.333,-.315,.468,.305),(.532,-.174,.441,.244)]
verts=[]
for x,lo,hi,w in rings:
 c=.033;verts.extend([(x,lo,-w+c),(x,lo+c,-w),(x,hi-c,-w),(x,hi,-w+c),(x,hi,w-c),(x,hi-c,w),(x,lo+c,w),(x,lo,w-c)])
faces=[tuple(reversed(range(8))),tuple(range((len(rings)-1)*8,len(rings)*8))]
for i in range(len(rings)-1):
 for j in range(8):faces.append((i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j))
m.mesh('Swept full lower nose volume',verts,faces,'CourierYellow')
m.profile('Dark continuous lower nose chassis',[(-.474,-.339),(-.460,-.467),(.190,-.427),(.489,-.201),(.345,-.210)],-.289,.291,'InkNavy',.025)
m.panel('Cream chin shoulder trim',[(-.385,.468,.387),(.263,.457,.346),(.469,.400,.294),(.463,.376,.304),(.262,.430,.358),(-.383,.440,.398)],[tuple(range(6))],'Cream')
m.profile('Cream broad lower nose bumper',[(-.464,.039),(-.142,.023),(.145,-.004),(.469,.092),(.529,.054),(.522,-.152),(.224,-.304),(-.444,-.275)],.308,.374,'Cream',.016)
m.box('Forward cream impact bumper',(.527,-.053,0),(.108,.268,.484),'Cream',.024)
m.box('Forward dark impact face',(.574,-.044,0),(.017,.112,.310),'InkNavy',.009)
m.box('Broad cyan nose lamp',(.493,.015,.261),(.075,.093,.021),'CyanGlow',.004)
m.box('Lower side impact insert',(-.288,-.152,.392),(.139,.107,.030),'Cobalt',.010)
m.box('Side yellow bumper catch',(.208,-.193,.389),(.136,.064,.035),'CourierYellow',.007)
m.box('Armor rear seam gasket',(-.482,-.025,0),(.023,.853,.612),'Ochre',.004)
m.panel_bolt(-.430,-.360,.313,'Metal',.022)

# A true release coupler doubling as the upper cab: a detachable front volume and exposed release spine.
m=Module('separator',1,'Upper rounded cab and quick-release coupling; broad canopy, recessed release seam and mechanical latches');MODULES.append(m)
rings=[(-.353,-.481,.473,.348),(-.206,-.485,.490,.358),(.090,-.485,.403,.345),(.316,-.483,.213,.302),(.510,-.480,.013,.238)]
verts=[]
for x,lo,hi,w in rings:
 c=.033;verts.extend([(x,lo,-w+c),(x,lo+c,-w),(x,hi-c,-w),(x,hi,-w+c),(x,hi,w-c),(x,hi-c,w),(x,lo+c,w),(x,lo,w-c)])
faces=[tuple(reversed(range(8))),tuple(range((len(rings)-1)*8,len(rings)*8))]
for i in range(len(rings)-1):
 for j in range(8):faces.append((i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j))
m.mesh('Rounded detachable upper cab',verts,faces,'CourierYellow')
m.box('Release flange rear half',(-.469,-.008,.004),(.058,.936,.701),'CourierYellow',.018)
m.box('Recessed coupling spine',(-.391,-.023,-.016),(.072,.834,.548),'InkNavy',.012)
m.box('Dark lower cab rim',(.064,-.466,.018),(.798,.043,.622),'Cobalt',.008)
upper=[(-.287,-.343,.382),(-.282,.314,.380),(-.203,.356,.385),(.071,.287,.367),(.279,.108,.324),(.451,-.066,.271),(.455,-.380,.279),(.136,-.404,.374)]
m.panel('Upper cab deep canopy perimeter',upper,[tuple(range(len(upper)))],'InkNavy')
glass=[(-.250,-.317,.395),(-.245,.290,.393),(-.201,.315,.400),(.059,.250,.381),(.252,.083,.340),(.411,-.088,.288),(.415,-.345,.295),(.132,-.367,.389)]
m.panel('Upper cab broad blue glazing',glass,[tuple(range(len(glass)))],'GlassBlue')
m.panel('Upper cab darker lower facet',[(-.250,-.196,.402),(.016,-.236,.401),(.415,-.345,.302),(.132,-.367,.396),(-.250,-.317,.402)],[tuple(range(5))],'Cobalt')
m.panel('Upper cab cyan reflection',[(-.155,.295,.408),(-.075,.278,.405),(.169,-.044,.391),(.089,-.079,.399)],[tuple(range(4))],'CyanGlow')
m.panel('Upper cab cream roof brow',[(-.326,.420,.382),(-.207,.456,.390),(.085,.368,.378),(.336,.164,.326),(.470,.005,.273),(.460,-.033,.286),(.311,.121,.341),(.064,.327,.391),(-.207,.414,.402),(-.326,.381,.396)],[tuple(range(10))],'Cream')
m.panel('Upper cab sloping top glass',[(-.188,.496,-.289),(-.188,.496,.289),(.086,.414,.290),(.300,.230,.247),(.469,.059,.183),(.469,.059,-.183),(.300,.230,-.247),(.086,.414,-.290)],[tuple(range(8))],'InkNavy',normal=(0,1,0))
m.panel('Upper cab top blue facet',[(-.133,.485,-.221),(-.133,.485,-.108),(.342,.193,-.084),(.298,.238,-.181)],[tuple(range(4))],'GlassBlue',normal=(0,1,0))
for yy in [-.328,.316]:
 m.box('Cream release latch bridge',(-.402,yy,.389),(.181,.093,.059),'Cream',.010)
 m.box('Dark latch pivot',(-.463,yy,.427),(.042,.054,.019),'InkNavy',.005)
 m.panel_bolt(-.331,yy,.431,'Metal',.022)
m.box('Guarded release control',(-.389,-.054,.363),(.091,.229,.047),'InkNavy',.009)
m.box('Yellow release lever',(-.389,-.083,.397),(.051,.119,.022),'CourierYellow',.006)
m.box('Release ready indicator',(-.390,.027,.393),(.040,.043,.023),'CyanGlow',.004)

# Optional replacement spring: real continuous mechanical coil, separate from starter layout.
AUXILIARY=[]
spring=Module('spring',0,'Independent mechanical spring cartridge; optional palette replacement, not in starter assembly');AUXILIARY.append(spring)
for x in [-.417,.417]:
 spring.box('Cream squared piston end',(x,0,0),(.158,.668,.574),'Cream',.035)
 spring.box('Inner cobalt spring seat',(x + (.09 if x<0 else -.09),0,0),(.07,.529,.459),'Cobalt',.018)
 spring.box('Yellow warning cap',(x,.276,.003),(.171,.086,.531),'CourierYellow',.014)
 spring.box('End plate recess',(x,.012,.292),(.087,.257,.023),'InkNavy',.009)
 spring.box('Cyan compression sensor',(x,.021,.307),(.037,.083,.015),'CyanGlow',.003)
 for yy in [-.24,.24]:spring.panel_bolt(x,yy,.309,'Metal',.022)
spring.cylinder('Central telescoping rod',(0,0,0),.067,.76,'Metal','X',12)
spring.cylinder('Central black piston barrel',(-.160,0,0),.102,.32,'InkNavy','X',12)
vv=[];ff=[];steps=112;wire_sides=6;turns=4.0
for i in range(steps+1):
 t=i/steps;ang=t*math.tau*turns
 center=Vector((-.315+t*.63,.225*math.cos(ang),.225*math.sin(ang)))
 radial=Vector((0,math.cos(ang),math.sin(ang)))
 tangent=Vector((.63, -math.tau*turns*.225*math.sin(ang), math.tau*turns*.225*math.cos(ang))).normalized()
 cross=tangent.cross(radial).normalized()
 for j in range(wire_sides):
  a=j*math.tau/wire_sides;vv.append(tuple(center + .044*(math.cos(a)*radial+math.sin(a)*cross)))
for i in range(steps):
 for j in range(wire_sides):ff.append((i*wire_sides+j,i*wire_sides+(j+1)%wire_sides,(i+1)*wire_sides+(j+1)%wire_sides,(i+1)*wire_sides+j))
ff +=[tuple(reversed(range(wire_sides))),tuple(range(steps*wire_sides,(steps+1)*wire_sides))]
spring.mesh('Single continuous six-sided helical coil',vv,ff,'CourierYellow')
module_entries=[m.export() for m in MODULES]+[m.export() for m in AUXILIARY]
# Visual cohesion revision is prohibited from changing the established physical bounds.
LOCKED_MODULE_BOUNDS={'cargo_crate': {'min': [-0.485, -0.466, -0.375], 'max': [0.4935, 0.529, 0.4955]}, 'beam': {'min': [-0.485, -0.49, -0.332], 'max': [0.498, 0.4935, 0.441]}, 'cell': {'min': [-0.4745, -0.4795, -0.325], 'max': [0.4905, 0.5075, 0.447]}, 'thruster': {'min': [-0.565, -0.473507, -0.433507], 'max': [0.498, 0.393507, 0.433507]}, 'armor': {'min': [-0.4935, -0.465464, -0.365], 'max': [0.5825, 0.48, 0.4473]}, 'separator': {'min': [-0.498, -0.4875, -0.358], 'max': [0.51, 0.496, 0.44]}, 'spring': {'min': [-0.5025, -0.334, -0.287], 'max': [0.5025, 0.334, 0.318]}}
for e in module_entries:
 for side in ['min','max']:
  assert all(abs(a-b)<1e-6 for a,b in zip(e['bounds_godot_m'][side],LOCKED_MODULE_BOUNDS[e['id']][side])),(e['id'],side,e['bounds_godot_m'],LOCKED_MODULE_BOUNDS[e['id']])

COMPACT_LAYOUT=[
 {'instance':'engine_upper','module':'thruster','grid':[-2,0]},
 {'instance':'midbody_upper','module':'beam','grid':[-1,0]},
 {'instance':'postal_hold','module':'cargo_crate','grid':[0,0]},
 {'instance':'upper_cab','module':'separator','grid':[1,0]},
 {'instance':'engine_lower','module':'thruster','grid':[-2,1]},
 {'instance':'midbody_lower','module':'beam','grid':[-1,1]},
 {'instance':'energy_pack','module':'cell','grid':[0,1]},
 {'instance':'lower_nose','module':'armor','grid':[1,1]},
]
for e in module_entries:
 e['starter_grid_positions']=[i['grid'] for i in COMPACT_LAYOUT if i['module']==e['id']]
 e['starter_grid']=e['starter_grid_positions'][0] if e['starter_grid_positions'] else None
for m in AUXILIARY:
 m.col.hide_render=True;m.root.location=bco((-.5,-3,0));m.root['grid_position']='Not in starter craft; standalone optional module'
by_module={m.name:m for m in MODULES};used=set();ASSEMBLY=[]
for inst in COMPACT_LAYOUT:
 m=by_module[inst['module']];gx,gy=inst['grid']
 if m.name not in used:
  root=m.root;used.add(m.name)
 else:
  col=bpy.data.collections.new('ASSEMBLY / '+inst['instance']);bpy.context.scene.collection.children.link(col)
  root=bpy.data.objects.new(inst['instance'],None);col.objects.link(root)
  root['assembly_linked_source']=m.name;root['functional_module']=m.name
  for original in m.col.objects:
   if original==m.root:continue
   duplicate=original.copy();duplicate.data=original.data;duplicate.name=inst['instance']+'__'+original.name;col.objects.link(duplicate);duplicate.parent=root
 root.location=bco((gx,-gy,0));root['grid_position']=[gx,gy];root['assembly_role']=inst['instance'];ASSEMBLY.append((root,inst))
entry_by_id={e['id']:e for e in module_entries}
assembled={'min':[float('inf')]*3,'max':[float('-inf')]*3}
for inst in COMPACT_LAYOUT:
 e=entry_by_id[inst['module']];offset=[inst['grid'][0],-inst['grid'][1],0]
 for axis in range(3):
  assembled['min'][axis]=min(assembled['min'][axis],e['bounds_godot_m']['min'][axis]+offset[axis])
  assembled['max'][axis]=max(assembled['max'][axis],e['bounds_godot_m']['max'][axis]+offset[axis])
assembled={k:[round(v,6) for v in vv] for k,vv in assembled.items()}
MANIFEST={'version':'4.3-amber-single-cab','license':'Original procedural artwork created for Star Courier; no third-party meshes, logo, textures, SVG, or external dependencies.',
 'reference_reviewed':'source_art/art_direction_v4/pixel-cel-shop-reference-03.png; dimensional yellow/cream/cobalt postal craft, hard-surface warm planes/cool recesses',
 'generator':'source_art/modules_v4/build_modules.py','editable_source':'source_art/modules_v4/star_courier_modules_v4.blend',
 'pre_single_cab_archive':'source_art/modules_v4/archive/2026-10-10T081615Z/compact_before_single_cab.zip',
 'bounds_locked_to':'source_art/modules_v4/archive/2026-10-10T081615Z/locked_bounds.json',
 'visual_revision':'One upper canopy; solid lower chin and warm shared body framing. No changes to bounds, sockets, IDs, physics, or grid.',
 'original_linear_source':'source_art/modules_v4/archive/star_courier_modules_linear_v40.blend',
 'original_linear_package':'source_art/modules_v4/archive/linear_v40_originals.zip',
 'axes':'glTF/Godot +X forward, +Y up, +Z toward camera','units':'metres','cell_spacing_m':1.0,'root_contract':'Every GLB has identity root at origin.',
 'socket_contract':{'Socket_Right':[.6,0,0],'Socket_Left':[-.6,0,0],'Socket_Top':[0,.6,0],'Socket_Bottom':[0,-.6,0]},
 'material_contract':'V4_* source albedo; CyanGlow and WarmGlow names indicate emissive regions. Nonmoving parts merged per material.',
 'palette_srgb':PALETTE,'starter_layout':COMPACT_LAYOUT,'starter_module_count':8,'proof_grid_mapping':'grid y 0/1 maps to Godot Y 0/-1; exact x positions and 1 metre spacing',
 'assembled_bounds_godot_m':assembled,'layout_scope':'Asset proof of parent-provided compact physics layout only; no gameplay or scripts changed here.',
 'original_linear_starter_layout':{'cargo_crate':[0,0],'beam':[-1,0],'cell':[-2,0],'thruster':[-3,0],'armor':[1,0]},
 'modules':module_entries}
# Export validation independently reads generated GLB node/accessor data.
def validate_glb(entry):
 path=OUT/(entry['id']+'.glb');raw=path.read_bytes();magic,ver,total=struct.unpack('<III',raw[:12]);length,typ=struct.unpack('<II',raw[12:20]);g=json.loads(raw[20:20+length])
 assert magic==0x46546c67 and ver==2 and total==len(raw)
 assert not g.get('images');nodes=g['nodes'];byname={n.get('name'):n for n in nodes}
 root=byname[entry['id']];assert all(abs(v)<1e-7 for v in root.get('translation',[0,0,0]));assert root.get('rotation',[0,0,0,1])==[0,0,0,1];assert root.get('scale',[1,1,1])==[1,1,1]
 for n,p in MANIFEST['socket_contract'].items():assert all(abs(a-b)<1e-6 for a,b in zip(byname[n]['translation'],p)),(n,byname[n])
 mats=[m['name'] for m in g['materials']];assert all(n.startswith('V4_') for n in mats)
 surfaces=sum(len(m['primitives']) for m in g['meshes']);assert surfaces<=10
 # Child mesh transforms are identities, so accessor extents are already model-local engine coordinates.
 bounds=[]
 for nd in nodes:
  if 'mesh' not in nd:continue
  assert 'translation' not in nd and 'rotation' not in nd and 'scale' not in nd
  for p in g['meshes'][nd['mesh']]['primitives']:
   ac=g['accessors'][p['attributes']['POSITION']];bounds.extend([ac['min'],ac['max']])
 lo=[min(v[i] for v in bounds) for i in range(3)];hi=[max(v[i] for v in bounds) for i in range(3)]
 for i in range(3):
  assert abs(lo[i]-entry['bounds_godot_m']['min'][i])<2e-6
  assert abs(hi[i]-entry['bounds_godot_m']['max'][i])<2e-6
 # All geometry now fits the honest cell silhouette; the battery fin has been revised to a flat roof.
 assert lo[0]>=-.585 and hi[0]<=.585 and lo[1]>=-.585 and hi[1]<=.585
 assert lo[2]>=-.585 and hi[2]<=.585
 return {'id':entry['id'],'result':'PASS','bytes':len(raw),'surfaces':surfaces,'root_identity':True,'all_four_sockets_verified':True,'bounds_verified_from_glb_accessors':True}
MANIFEST['validation']=[validate_glb(e) for e in MANIFEST['modules']]
(OUT/'manifest.json').write_text(json.dumps(MANIFEST,indent=2));(SRC/'manifest.json').write_text(json.dumps(MANIFEST,indent=2))
# The editable source scene opens on the exact parent-provided eight-module physical layout.
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene.render.engine='CYCLES';scene.cycles.samples=72;scene.cycles.use_denoising=False
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.033,.051,.081,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.6
scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast';scene.view_settings.exposure=-.65;scene.view_settings.gamma=1
review=bpy.data.collections.new('PROOF / cameras and studio');scene.collection.children.link(review)
def move_review(o):
 for c in list(o.users_collection):c.objects.unlink(o)
 review.objects.link(o)
def light(n,p,energy,color,size):
 bpy.ops.object.light_add(type='AREA',location=bco(p));o=bpy.context.object;o.name=n;move_review(o);o.data.energy=energy;o.data.color=color;o.data.shape='DISK';o.data.size=size
 o.rotation_euler=(Vector(bco((-.5,-.4,0)))-o.location).to_track_quat('-Z','Y').to_euler();return o
light('Warm large overhead key',(-2.7,4.5,5),450,(1,.78,.47),4.0)
light('Cool underside bounce',(2,1.2,2.5),130,(.36,.65,1),3)
light('Cream top rim',(-1,3,-3.5),300,(1,.86,.62),3)
bpy.ops.object.camera_add(location=bco((-.5,1.25,11)));cam=bpy.context.object;cam.name='Compact courier front camera';move_review(cam);cam.data.type='ORTHO';scene.camera=cam
scene.render.resolution_x=1008;scene.render.resolution_y=600;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.render.image_settings.color_mode='RGBA'
def camera_at(p,target,scale):
 cam.location=bco(p);cam.rotation_euler=(Vector(bco(target))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
camera_at((-.5,1.25,11),(-.5,-.47,0),4.85)
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'star_courier_modules_v4.blend'))
if not SKIP_RENDER:
 for name,p,t,s in [('compact_front',(-.5,1.25,11),(-.5,-.47,0),4.85),('compact_angle',(-4.1,1.25,9),(-.5,-.47,0),4.95),('compact_rear_nozzle',(-6,1.35,5.5),(-.5,-.47,0),4.95)]:
  camera_at(p,t,s);scene.render.filepath=str(PROOF/(name+'.png'));bpy.ops.render.render(write_still=True)
 # Physical modules are separated in both grid directions, without any static craft shell.
 for root,inst in ASSEMBLY:
  gx,gy=inst['grid'];root.location=bco((gx*1.23,-gy*1.26,0))
 camera_at((-.615,1.25,11),(-.615,-.6,0),5.65);scene.render.filepath=str(PROOF/'compact_exploded.png');bpy.ops.render.render(write_still=True)
 for root,inst in ASSEMBLY:
  gx,gy=inst['grid'];root.location=bco((gx,-gy,0))
 camera_at((-.5,1.25,11),(-.5,-.47,0),4.85)
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'star_courier_modules_v4.blend'))
print('V4_COMPACT_MODULES_COMPLETE '+json.dumps({'assembled_bounds':assembled,'modules':{e['id']:{'bounds':e['bounds_godot_m'],'surfaces':e['surface_count']} for e in MANIFEST['modules']}}))
