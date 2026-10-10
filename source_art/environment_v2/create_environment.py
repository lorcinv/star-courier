import bpy, math, random, os
from pathlib import Path
from mathutils import Vector
random.seed(41)
ROOT=str(Path(__file__).resolve().parents[2])
OUT=ROOT+'/assets/environment_v2'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
 if c.name!='Collection': bpy.data.collections.remove(c)
P={'Ink':'101c35','Cobalt':'3044aa','Indigo':'242b67','Blue':'3665d2','Cyan':'39d9d1','Pale':'9af5dc','Yellow':'ffdf36','Orange':'ff9748','Coral':'fb6671','Magenta':'be377a','Cream':'fff1cc','Metal':'7598ad','Slate':'486582','Sky':'57ddd1','Cloud':'c9f7e0','Window':'60b3ca','Distant':'83caca','CityBlue':'4389ab','CityMid':'58a6b7','CityInk':'356f91'}
M={}
for n,h in P.items():
 rgb=tuple(int(h[i:i+2],16)/255 for i in (0,2,4))
 rgb=tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb)
 m=bpy.data.materials.new('Env_'+n);m.diffuse_color=(*rgb,1);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*rgb,1);bs.inputs['Roughness'].default_value=.8
 M[n]=m
 if n in ['Cyan','Pale','Yellow']:
  bs.inputs['Emission Color'].default_value=(*rgb,1);bs.inputs['Emission Strength'].default_value=.10
COL=None
def collection(n):
 global COL
 c=bpy.data.collections.new(n);bpy.context.scene.collection.children.link(c);COL=c;return c
def move(o,n,mat=None):
 o.name=n
 for c in list(o.users_collection):c.objects.unlink(o)
 COL.objects.link(o)
 if mat:o.data.materials.append(M[mat])
 return o
def box(n,loc,dim,mat,bevel=.035,rot=0):
 verts=[(x*dim[0]/2,y*dim[1]/2,z*dim[2]/2) for x,y,z in [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]]
 me=bpy.data.meshes.new(n);me.from_pydata(verts,[],[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]);me.materials.append(M[mat]);o=bpy.data.objects.new(n,me);COL.objects.link(o);o.location=loc;o.rotation_euler.z=rot
 if bevel:
  o.data.materials.append(M['Ink']);mod=o.modifiers.new('Graphic edge bevel','BEVEL');mod.width=bevel;mod.segments=1;mod.affect='EDGES';mod.material=1
  mod=o.modifiers.new('Weighted graphic normals','WEIGHTED_NORMAL');mod.keep_sharp=True
 return o
def cyl(n,loc,r,d,mat,vertices=12,axis='Z'):
 verts=[(r*math.cos(2*math.pi*j/vertices),r*math.sin(2*math.pi*j/vertices),z) for z in [-d/2,d/2] for j in range(vertices)]
 faces=[tuple(reversed(range(vertices))),tuple(range(vertices,vertices*2))]+[(j,(j+1)%vertices,(j+1)%vertices+vertices,j+vertices) for j in range(vertices)]
 me=bpy.data.meshes.new(n);me.from_pydata(verts,[],faces);me.materials.append(M[mat]);o=bpy.data.objects.new(n,me);COL.objects.link(o);o.location=loc
 if axis=='Y':o.rotation_euler.x=math.pi/2
 if axis=='X':o.rotation_euler.y=math.pi/2
 return o
def sphere(n,loc,scale,mat,sub=1):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc);o=move(bpy.context.object,n,mat);o.scale=scale;return o
def bar(n,a,b,r,mat,vertices=8):
 a=Vector(a);b=Vector(b);o=cyl(n,(a+b)/2,r,(b-a).length,mat,vertices);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def beam(n,a,b,w,dep,mat):
 a=Vector(a);b=Vector(b);o=box(n,(a+b)/2,(w,dep,(b-a).length),mat,.025);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def text(n,s,loc,size,mat,align='CENTER'):
 cu=bpy.data.curves.new(n,'FONT');cu.body=s;cu.size=size;cu.align_x=align;cu.align_y='CENTER';cu.extrude=.003;cu.bevel_depth=0;cu.resolution_u=3;cu.bevel_resolution=0
 o=bpy.data.objects.new(n,cu);COL.objects.link(o);o.location=loc;o.rotation_euler=(math.pi/2,0,0);cu.materials.append(M[mat]);return o
def curve(n,points,r,mat):
 cu=bpy.data.curves.new(n,'CURVE');cu.dimensions='3D';sp=cu.splines.new('POLY');sp.points.add(len(points)-1)
 for p,co in zip(sp.points,points):p.co=(*co,1)
 cu.bevel_depth=r;cu.bevel_resolution=0;o=bpy.data.objects.new(n,cu);COL.objects.link(o);cu.materials.append(M[mat]);return o
def parcel(n,x,y,z,w=.75,h=.6,mat='Cream'):
 box(n,(x,y,z+h/2),(w,.62,h),mat,.035)
 box(n+'_tape',(x,y-.32,z+h/2),(.12,.018,h-.03),'Coral',.005)
 box(n+'_label',(x+w*.2,y-.333,z+h*.58),(w*.2,.02,h*.28),'Ink',.003)
 for j in range(3):box(n+'_barcode'+str(j),(x+w*.2-.045+j*.043,y-.346,z+h*.58),(.018,.007,h*.20),'Cream',0)
def plant(n,x,y,z,s=1):
 cyl(n+'_pot',(x,y,z+.24*s),.27*s,.48*s,'Coral',8)
 for j in range(5):
  a=j*2.4;top=(x+math.cos(a)*.35*s,y+math.sin(a)*.25*s,z+(1+j%2*.24)*s)
  bar(n+'_stem',(x,y,z+.38*s),top,.025*s,'Indigo')
  sphere(n+'_leaf',top,(.24*s,.13*s,.36*s),'Cyan')
def arrow(n,x,y,z,s,mat):
 # face points toward front
 verts=[(x-s,y,z+s*.35),(x+s*.1,y,z+s*.35),(x+s*.1,y,z+s*.7),(x+s,y,z),(x+s*.1,y,z-s*.7),(x+s*.1,y,z-s*.35),(x-s,y,z-s*.35)]
 me=bpy.data.meshes.new(n);me.from_pydata(verts,[],[list(range(7))]);o=bpy.data.objects.new(n,me);COL.objects.link(o);me.materials.append(M[mat]);return o

shop=collection('Shop_Cutaway')
# sunlit loading pier foundation with visible suspended infrastructure
box('Pier_ink',(0,.2,-.6),(27,7.5,1.2),'Ink',.12)
box('Pier_deck',(0,.2,-.08),(26.8,7.3,.26),'Metal',.05)
box('Pier_front_beam',(0,-3.52,-.6),(27,.22,.75),'Cobalt',.035)
for x in range(-12,13,2):
 box('Deck_seam',(x,.15,.065),(.035,6.8,.014),'Slate',0)
 box('Pier_face_inset',(x,-3.66,-.61),(1.35,.045,.24),'Ink',.02)
 box('Pier_reflector',(x+.48,-3.7,-.58),(.16,.025,.10),'Yellow',0)
for x in [-11,-7,0,7,11]:
 beam('Pier_diagonal',(x,-2.9,-.9),(x+1.7,1.5,-2.6),.4,.5,'Indigo')
box('Lower_service_pipe',(0,-2.8,-1.45),(23,.3,.27),'Coral',.02)
# deep blue side-view interior; open front, ribbed back wall
box('Back_structure',(-.9,2.85,3.65),(24.5,.55,7.3),'Ink',.06)
box('Retail_back',(-7,2.5,3.5),(11,.16,6.75),'Cobalt',.015)
box('Bay_back',(5.2,2.5,3.5),(12.4,.16,6.75),'Indigo',.015)
for x in [-12,-.9,11.5]:box('Structure_pillar',(x,1.95,3.5),(.38,1.15,7),'Ink',.035)
for x in [-11,-9,-7,-5,-3,0,2,4,6,8,10]:box('Wall_seam',(x,2.38,3.5),(.035,.04,6.65),'Blue',0)
# overhead roof edge acting as graphic compositional header
box('Roof_shadow',(-.2,1.7,7.15),(25.6,2.5,.45),'Ink',.08)
box('Roof_blue',(-.2,1.6,7.42),(25.8,2.7,.28),'Cobalt',.07)
box('Roof_coral_trim',(-.2,.20,7.32),(25.6,.11,.14),'Coral',.025)
for x in [-11,-7,-3,1,5,9]:box('Roof_sun_panel',(x,1.7,7.62),(2.7,1.9,.10),'Blue',.025)
# extruded bright fascia on left, typography is original brand
box('Courier_fascia',(-6.9,.03,6.53),(10.1,.32,1.2),'Yellow',.08)
box('Courier_fascia_under',(-6.9,-.15,5.91),(9.9,.04,.09),'Ink',.01)
text('Brand_STARC','STAR / COURIER',(-7,-.155,6.58),.68,'Ink')
text('Brand_sub','ORBITAL DELIVERY SERVICE',(-7,-.176,6.13),.17,'Ink')
# roof turbine and communications mast, creates recognizable silhouette
cyl('Roof_water_tank',(-10,1.6,8.34),.95,1.25,'Cyan',12)
for z in [7.9,8.8]:cyl('Tank_dark_band',(-10,1.6,z),.98,.12,'Ink',12)
bar('Antenna_mast',(-3.6,2,7.5),(-3.6,2,9.1),.055,'Cream')
for z in [8.25,8.6,8.9]:bar('Antenna_crossbar',(-4.25,2,z),(-2.95,2,z),.033,'Coral')
sphere('Antenna_tip',(-3.6,2,9.15),(.11,.11,.11),'Yellow')
# rear shelving, only left wing packed and labeled
for sx in [-9.7,-6.5]:
 for z in [.35,1.5,2.7,3.9,5.1]:box('Shelf_plank',(sx,1.75,z),(2.85,1.1,.16),'Ink',.015)
 for x in [sx-1.36,sx+1.36]:box('Shelf_upright',(x,1.79,2.65),(.12,1,5.45),'Cyan',.015)
 for row,z in enumerate([.45,1.60,2.80,4.00]):
  for j in range(3):
   if random.random()>.12:parcel('Sorted_parcel',sx-1+j*.88,1.48,z,.60+random.random()*.16,.5+random.random()*.30,random.choice(['Cream','Orange','Coral','Cyan']))
 for j in range(4):text('Shelf_index',str(j+1).zfill(2),(sx+1.30,1.19,.75+j*1.2),.13,'Cream')
# Counter and scanner at left foreground
box('Counter_base',(-8,-.45,.86),(5.5,1.38,1.7),'Cobalt',.09)
box('Counter_top',(-8,-.47,1.79),(5.85,1.65,.22),'Cream',.045)
box('Counter_front_recess',(-8,-1.16,.91),(5.15,.06,1.14),'Ink',.035)
box('Counter_front_band',(-8,-1.22,1.1),(4.95,.035,.44),'Yellow',.015)
text('Counter_label','SEND SOMETHING GOOD.',(-8,-1.25,1.12),.27,'Ink')
for x in [-9.9,-6.1]:box('Counter_feet',(x,-.3,.14),(.4,1.1,.28),'Ink',.02)
parcel('Counter_parcel',-8.2,-.5,1.91,.85,.65,'Orange')
box('Scanner_base',(-6.15,-.35,1.98),(.65,.5,.15),'Ink',.03)
monitor=box('Scanner_monitor',(-6.15,-.20,2.34),(.68,.16,.55),'Ink',.045);monitor.rotation_euler.x=-.18
box('Scanner_display',(-6.15,-.30,2.35),(.52,.015,.36),'Cyan',.01)
for j in range(3):box('Scanner_display_row',(-6.19,-.319,2.44-j*.08),(.28,.01,.018),'Cream',0)
cyl('Counter_stamp',(-9.5,-.4,2.1),.11,.26,'Coral',8)
# Lower all retail counter fixtures to a believable human service height.
for o in list(shop.objects):
 if o.name.startswith(('Counter_base','Counter_front_recess')):
  o.location.z*=.69;o.scale.z*=.69
 elif o.name.startswith(('Counter_top','Scanner','Counter_parcel','Counter_stamp')):o.location.z-=.55
 elif o.name.startswith(('Counter_front_band','Counter_label')):o.location.z-=.34
# route board in central partition visible between retail / workshop
box('Routeboard_frame',(-3.3,2.12,4.11),(2.8,.23,2.78),'Ink',.06)
box('Routeboard_face',(-3.3,1.98,4.11),(2.55,.03,2.54),'Cream',.025)
text('Routeboard_title','TODAY / 03',(-3.3,1.95,5.03),.28,'Ink')
for j,(col,x2) in enumerate([('Coral',-.6),('Cobalt',.7),('Cyan',0)]):
 z=4.6-j*.6
 curve('Route_'+str(j),[(-4.2,1.93,z),(-3.8,1.93,z),(-3.4,1.93,z-.22),(-2.65,1.93,z-.22)],.035,col)
 for x in [-4.2,-2.65]:cyl('Route_node',(x,1.90,z if x<-3 else z-.22),.085,.03,col,12,'Y')
text('Notice_small','LOADING  •  GATE 02',(-3.3,1.935,3.08),.15,'Ink')
# workbench at rear; open floor in center for real craft assembly
box('Workbench_base',(3.8,1.75,.80),(6.8,1.05,1.55),'Cobalt',.05)
box('Workbench_top',(3.8,1.62,1.66),(7.05,1.34,.18),'Yellow',.035)
for x in [1,2.4,3.8,5.2,6.6]:
 box('Tool_drawer',(x,1.19,.92),(1.16,.055,.78),'Indigo',.02)
 box('Drawer_handle',(x,1.12,1.14),(.42,.09,.08),'Cyan',.015)
box('Pegboard',(3.8,2.22,3.54),(6.9,.10,2.64),'Slate',.02)
for x in [1,1.6,2.2,2.8,3.4,4,4.6,5.2,5.8,6.4]:
 for z in [2.5,3,3.5,4,4.5]:cyl('Peg_hole',(x,2.15,z),.028,.016,'Ink',8,'Y')
for x,z in [(1.1,3.6),(2,3.5),(2.9,3.7),(4.3,3.5),(5.5,3.7)]:
 bar('Hanging_tool',(x,2.09,z-.45),(x+.18,2.09,z+.35),.055,'Cream')
 cyl('Tool_ring',(x+.18,2.09,z+.35),.16,.07,'Ink',8,'Y')
 cyl('Tool_ring_center',(x+.18,2.04,z+.35),.085,.02,'Yellow',8,'Y')
# spare engine, vise, work light
cyl('Spare_engine',(5.8,1.5,2.16),.37,.74,'Ink',12,'X');cyl('Spare_engine_band',(5.8,1.5,2.16),.39,.18,'Coral',12,'X')
box('Vise',(1.6,1.40,1.92),(.6,.44,.36),'Metal',.035)
bar('Bench_lamp_arm',(3,2,1.8),(3,1.5,2.5),.035,'Ink');box('Bench_lamp',(3,1.35,2.5),(.6,.45,.13),'Cream',.025)
# gantry hoist arch, large acid-yellow industrial focal structure
for x in [-.95,10.1]:
 box('Gantry_foot',(x,-.05,.22),(1.0,2.0,.44),'Ink',.06)
 beam('Gantry_outer',(x,-.0,.44),(x+(.6 if x<0 else -.6),.05,6.2),.42,.55,'Yellow')
 for z in [1,1.35,1.7]:box('Gantry_warning',(x,-.32,z),(.42,.025,.12),'Ink',.005)
box('Gantry_top',(4.57,.06,6.1),(11,.63,.58),'Yellow',.065)
box('Gantry_track',(4.57,-.32,6.10),(9.7,.06,.14),'Ink',.01)
text('Gantry_id','ASSEMBLY / 02',(4.5,-.29,6.51),.35,'Cream')
box('Hoist_trolley',(4.6,1.0,5.8),(1.45,.87,.42),'Ink',.04)
box('Hoist_trolley_face',(4.6,.53,5.8),(1.15,.06,.26),'Coral',.02)
for x in [4.2,5.0]:bar('Hoist_cable',(x,1,5.60),(x,1,4.52),.022,'Cream')
box('Hoist_hook',(4.6,1,4.46),(1.15,.28,.18),'Ink',.035)
# launch floor cradle clear central dynamic object area
box('Craft_lift',(4.5,-.48,.20),(7.6,2.8,.4),'Ink',.06)
box('Craft_lift_surface',(4.5,-.48,.43),(7.25,2.55,.12),'Cobalt',.035)
for x in [1.5,7.5]:
 box('Lift_stripe',(x,-.48,.505),(.14,2.24,.017),'Yellow',0)
 box('Lift_block',(x,-.4,.64),(.42,.7,.23),'Metal',.025)
for x in [1.2,2.2,3.2,4.2,5.2,6.2,7.2]:box('Lift_front_tick',(x,-1.88,.19),(.47,.025,.12),'Yellow',.015)
# large door continuation at right edge
box('Launch_door_pier',(11.8,1.18,3.1),(1,2.0,6.2),'Cobalt',.06)
for z in [1,2,3,4,5]:box('Door_shutter_rib',(11.25,1.08,z),(.08,1.7,.11),'Cyan',.01)
arrow('Launch_arrow',11.72,.12,3.58,.42,'Yellow')
text('Gate_text','OUT',(11.7,.10,4.35),.33,'Cream')
# lived-in details placed in non-interactive margins
plant('Counter_plant',-11.4,-.65,.09,.9)
box('Floor_mat',(-7.4,-2.2,.09),(4,1.1,.055),'Coral',.015)
for j in range(8):box('Mat_line',(-8.8+j*.4,-2.2,.122),(.07,.9,.01),'Cream',0)
cyl('Stool_seat',(-3.25,.1,.96),.45,.16,'Coral',12)
for x,y in [(-.28,-.2),(.28,-.2),(0,.25)]:bar('Stool_leg',(-3.25+x,.1+y,.1),(-3.25+x*.6,.1+y*.6,.90),.045,'Ink')
box('Shipping_cart',(-12,-1.5,.38),(1.05,.95,.17),'Cream',.03)
for x in [-12.35,-11.65]:cyl('Cart_wheel',(x,-1.5,.16),.16,.12,'Ink',12,'Y')
bar('Cart_handle',(-12.4,-1.4,.4),(-12.4,-1.4,1.62),.045,'Ink')
parcel('Waiting_parcel',-11.95,-1.48,.50,.62,.65,'Cyan')
# foreground pipe guard and safety lamps, deliberately absent across focal center
for x in [-12.7,12.7]:
 bar('Safety_bollard',(x,-3.2,.1),(x,-3.2,1.1),.095,'Ink')
 cyl('Safety_light',(x,-3.2,1.05),.13,.20,'Yellow',8)
bar('Left_foreground_rail',(-13,-3.15,.9),(-10.2,-3.15,.9),.05,'Cream')

# Original flag, cable bundle and indoor strip accents enrich the working port.
for xx in [-11.65,-11.35]:
 curve('Service_cable',[(xx,2.08,6),(xx,2.08,5.7),(xx+.25,2.08,5.35),(xx+.25,2.08,1.2)],.045,'Coral')
box('Retail_lamp',(-7,1.25,5.66),(6.8,.24,.10),'Cream',.02)
bar('Flag_pole',(-11.4,1.4,7.5),(-11.4,1.4,9.7),.045,'Ink')
# small coral pennant solid triangle
me=bpy.data.meshes.new('Post_flag');me.from_pydata([(-11.4,1.4,9.55),(-9.7,1.4,9.28),(-11.4,1.4,8.86)],[],[(0,1,2)]);ob=bpy.data.objects.new('Post_flag',me);shop.objects.link(ob);me.materials.append(M['Coral'])
print('SHOP BUILT',flush=True)
city=collection('Orbital_City')
curve('Sky_Transit_Main',[(x,8,10+.006*(x+2)**2) for x in range(-35,36)],.30,'Cobalt')
curve('Sky_Transit_Top',[(x,8,10.35+.006*(x+2)**2) for x in range(-35,36)],.065,'Yellow')
curve('Sky_Transit_Lower',[(x,8,9.7+.006*(x+2)**2) for x in range(-35,36)],.065,'Ink')
# handmade stepped silhouettes, modular city spans x ±70; depth bands are physically distinct
for layer,y,scale in [(0,29,1.05),(1,20,.94),(2,13,.88)]:
 for i in range(-9,10):
  x=i*6.9+random.uniform(-1,1);w=random.uniform(3.4,6.0);h=random.uniform(6,15)*scale;z0=-5-y*.29
  col='Distant' if layer==0 else ('CityMid' if layer==1 else 'CityBlue')
  box('City_L%d_Tower_%d'%(layer,i),(x,y,z0+h/2),(w,3,h),col,.06)
  # set-back roof and crown
  box('City_crown',(x+.3,y,z0+h+.7),(w*.64,2.4,1.4),col,.035)
  if i%3==0:bar('City_aerial',(x+.4,y,z0+h+1.3),(x+.4,y,z0+h+3),.045,'Coral' if layer==2 else 'Pale')
  if layer:
   for f in range(int(h/1.5)-1):
    for c in range(3):
     if random.random()>.34:
      box('City_window',(x-w*.3+c*w*.3,y-1.52,z0+1+f*1.5),(.25 if layer==2 else .38,.025,.35),random.choice(['Cyan','Yellow','Window','Coral']) if layer==2 else 'Window',0)
   if i%3==0:
    box('City_billboard',(x-w*.45,y-1.63,z0+h*.65),(.65,.16,3),'Coral',.025)
    text('City_sign','P\nO\nS\nT',(x-w*.45,y-1.74,z0+h*.65),.39,'Cream')
# Let the skyline recede with blue atmospheric contours instead of hero black edges.
for ob in city.objects:
 if ob.type=='MESH' and 'Transit' not in ob.name:
  for idx,mt in enumerate(ob.data.materials):
   if mt==M['Ink']:ob.data.materials[idx]=M['CityInk']
# elevated orbital transit guideway behind scene
for y,z in [(16,7.8),(28,18)]:
 box('Transit_track',(0,y,z),(145,1.5,.50),'Indigo',.04)
 box('Transit_lightline',(0,y-.79,z+.10),(145,.06,.1),'Cyan',0)
 for x in range(-60,65,12):
  beam('Transit_support',(x,y,-5),(x+3,y,z-.3),.48,.8,'Blue')
# supporting floating terraces and delivery neighborhoods
for x in [-35,-20,20,38,53]:
 box('Neighborhood_platform',(x,7,-1.2),(8,5,.8),'Indigo',.09)
 box('Neighborhood_rim',(x,4.45,-.96),(8.2,.13,.18),'Coral',.02)
 for j in range(3):
  box('Satellite_shop',(x-2.5+j*2.4,7,1.1),(2,2.8,3.8),'Blue',.04)
  box('Satellite_canopy',(x-2.5+j*2.4,5.6,2.4),(2.2,1.3,.25),'Cream',.025)
# distant airships in negative sky spaces
for x,z,s in [(-26,23,1),(19,25,.65),(41,21,.8)]:
 sphere('Commuter_airship',(x,24,z),(2.2*s,.6*s,.48*s),'Cream',2)
 box('Airship_fin',(x-1.6*s,24,z+.45*s),(.6*s,.15*s,.7*s),'Coral',.02)
# sky plate and clouds exported separately for reliable ambient background
sky=collection('Sky_Backdrop')
box('Turquoise_sky',(0,45,25),(240,.1,110),'Sky',0)
sphere('Warm_sun',(-12,43,1.4),(5,.18,5),'Cream',3)
for x,z,w in [(-41,0,11),(-13,2.5,9),(10,1.2,12),(39,0,9),(1,4.0,6),(57,1.2,8)]:
 # graphic horizontal angular cream cloud ribbons
 box('Cloud_ribbon',(x,42,z),(w,.13,.55),'Cloud',.12)
 box('Cloud_crown',(x-w*.16,42,z+.45),(w*.60,.13,.55),'Cloud',.12)
# diagonals in upper sky, orbital rail no copied design
curve('Orbital_arc',[(x,39,26+.007*(x+5)**2) for x in range(-70,71,2)],.16,'Pale')
curve('Orbital_arc_shadow',[(x,39.3,25.5+.007*(x+5)**2) for x in range(-70,71,2)],.06,'Blue')

print('CITY BUILT',flush=True)
kiosk=collection('Destination_Kiosk')
box('Destination_base',(0,0,.12),(4.6,3,.25),'Ink',.04)
box('Destination_floor',(0,0,.3),(4.3,2.7,.14),'Cobalt',.03)
for x in [-1.9,1.9]:beam('Kiosk_post',(x,.9,.35),(x*.9,.9,3.7),.2,.25,'Ink')
box('Kiosk_canopy',(0,.45,3.76),(4.5,2.3,.3),'Yellow',.055)
box('Kiosk_lockers',(0,.9,1.6),(3.25,.9,2.5),'Cobalt',.045)
for x in [-1.03,0,1.03]:
 for z in [.9,1.95]:
  box('Locker_door',(x,.41,z),(.94,.075,.93),'Cyan',.025)
  box('Locker_handle',(x+.27,.35,z),(.065,.06,.24),'Ink',.01)
box('Kiosk_header',(0,-.76,3.55),(3.45,.09,.52),'Ink',.02)
text('Kiosk_label','PARCEL PORT / 07',(0,-.82,3.55),.28,'Cream')
box('Kiosk_terminal',(2.1,-.4,1.3),(.5,.45,1.6),'Coral',.035)
box('Kiosk_terminal_screen',(2.1,-.64,1.7),(.35,.035,.42),'Ink',.01)
plant('Destination_plant',-1.75,-.75,.37,.64)

# Low-poly original courier figures; separate named pivots ready for Godot animation.
def character(name,coat,helmet):
 c=collection(name)
 def empty(n,loc,parent=None):
  o=bpy.data.objects.new(n,None);COL.objects.link(o);o.location=loc;o.parent=parent;return o
 root=empty(name+'_Root',(0,0,0))
 body=empty('BodyPivot',(0,0,1.0),root)
 def parent_keep(o,p):
  bpy.context.view_layer.update();world=o.matrix_world.copy();o.parent=p;o.matrix_world=world;return o
 parent_keep(box('Torso',(0,0,1.1),(.6,.40,.68),coat,.10),body)
 parent_keep(box('Jacket_zip',(0,-.217,1.16),(.045,.025,.5),'Cream',.005),body)
 parent_keep(box('Badge',(.15,-.233,1.28),(.13,.018,.13),'Yellow',.01),body)
 head=empty('HeadPivot',(0,0,1.52),root)
 parent_keep(sphere('Face',(0,-.035,1.69),(.25,.22,.29),'Cream',2),head)
 parent_keep(sphere('HairHelmet',(0,-.015,1.85),(.30,.28,.21),helmet,1),head)
 parent_keep(box('Helmet_brim',(0,-.18,1.79),(.54,.30,.07),helmet,.025),head)
 if name=='Courier_Clerk':
  parent_keep(box('Visor',(0,-.241,1.69),(.38,.03,.13),'Ink',.03),head)
  parent_keep(cyl('Headset',(.28,0,1.69),.11,.08,'Cyan',12,'X'),head)
  parent_keep(box('Scarf',(0,-.1,1.46),(.58,.36,.13),'Yellow',.045),body)
  parent_keep(beam('Scarf_tail',(.17,.02,1.46),(.50,.10,1.12),.17,.065,'Yellow'),body)
 else:
  for eye in [-.075,.075]:parent_keep(box('Customer_eye',(eye,-.246,1.70),(.028,.015,.045),'Ink',.006),head)
  parent_keep(box('Customer_glasses',(0,-.258,1.7),(.27,.015,.02),'Ink',.002),head)
 for side in [-1,1]:
  leg=empty(('Left' if side<0 else 'Right')+'LegPivot',(side*.16,0,.77),root)
  parent_keep(box('Trouser',(side*.16,0,.49),(.22,.3,.62),'Indigo',.04),leg)
  parent_keep(box('Shoe',(side*.16,-.10,.14),(.29,.49,.20),'Ink',.05),leg)
  parent_keep(box('Shoe_sole',(side*.16,-.12,.055),(.30,.51,.055),'Cream',.014),leg)
  arm=empty(('Left' if side<0 else 'Right')+'ArmPivot',(side*.32,0,1.31),root)
  if name=='Courier_Clerk':
   parent_keep(beam('Sleeve',(side*.34,0,1.28),(side*.48,-.24,1.02),.23,.27,coat),arm)
   parent_keep(beam('Forearm',(side*.48,-.24,1.02),(side*.33,-.58,1.08),.18,.22,coat),arm)
   parent_keep(sphere('Glove',(side*.32,-.64,1.08),(.12,.14,.11),'Cream',1),arm)
  else:
   parent_keep(beam('Sleeve',(side*.34,0,1.28),(side*.43,-.015,.91),.23,.28,coat),arm)
   parent_keep(sphere('Glove',(side*.44,-.03,.82),(.13,.13,.16),'Cream',1),arm)
 parent_keep(box('Courier_satchel',(.32,.13,1.02),(.29,.4,.38),'Yellow',.04),body)
 if name=='Courier_Clerk':
  parcel('Held_parcel',0,-.43,.99,.54,.43,'Cream')
  for o in list(c.objects):
   if o.name.startswith('Held_parcel'):parent_keep(o,body)
  for o in c.objects:
   if 'ArmPivot' in o.name:o.rotation_euler.x=0
 else:
  parent_keep(box('Customer_shoulder_bag',(-.43,.05,.73),(.40,.39,.55),'Magenta',.06),body)
  parent_keep(bar('Customer_bag_strap',(-.29,.05,1.36),(-.44,.05,.93),.035,'Coral'),body)
 root.scale=(1.14,1.14,1.14)
 return c,root
clerk,clerkroot=character('Courier_Clerk','Coral','Indigo')
customer,customerroot=character('Customer','Cream','Cobalt')
# Retain fully separated editable original mesh hierarchy as well as optimized runtime exports.
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/source_art/environment_v2/orbital_post_office_editable.blend')
# export individual assets while authored at origin
for col,fn in [(shop,'shop_cutaway'),(city,'orbital_city'),(sky,'sky_backdrop'),(kiosk,'destination_kiosk'),(clerk,'courier_clerk'),(customer,'customer')]:
 bpy.ops.object.select_all(action='DESELECT')
 for o in col.objects:o.select_set(True)
 if col not in [clerk,customer]:
  bpy.context.view_layer.objects.active=next(o for o in col.objects if o.type=='MESH')
  bpy.ops.object.convert(target='MESH');bpy.ops.object.join();bpy.context.object.name=fn+'_Static'
  bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
 else:
  for o in col.objects:
   if o.type in ['CURVE','FONT']:
    bpy.context.view_layer.objects.active=o
 bpy.ops.export_scene.gltf(filepath=OUT+'/'+fn+'.glb',export_format='GLB',use_selection=True,export_apply=True,export_cameras=False,export_lights=False)
# arrange presentation scene, exported assets unchanged
clerkroot.location=(-7.0,.55,0)
customerroot.location=(-8.8,-2.3,.1);customerroot.rotation_euler.z=-.18
for o in kiosk.objects:o.hide_render=True
# film / rendering
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=False;scene.render.resolution_x=1600;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.world.color=(.45,.65,.7);scene.world.use_nodes=True
bg=scene.world.node_tree.nodes.get('Background');bg.inputs[0].default_value=(.35,.63,.70,1);bg.inputs[1].default_value=.8
scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast';scene.view_settings.exposure=0;scene.view_settings.gamma=1
collection('Presentation_Lighting')
bpy.ops.object.light_add(type='SUN',location=(-10,-12,18));sun=move(bpy.context.object,'Late_morning_sun');sun.rotation_euler=(math.radians(28),math.radians(-25),math.radians(-30));sun.data.energy=2.0;sun.data.angle=.06
bpy.ops.object.light_add(type='AREA',location=(0,-10,8));light=move(bpy.context.object,'Open_sky_fill');light.data.energy=1400;light.data.shape='DISK';light.data.size=18;light.rotation_euler=(Vector((0,0,3))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(1.0,-31,12.6));camera=move(bpy.context.object,'Shop_composition_camera');camera.rotation_euler=(Vector((0,0,3.5))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=33.5;scene.camera=camera
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/source_art/environment_v2/orbital_post_office.blend')
# Deliberate three-value cel proof approximates game shader without Cycles sampling noise.
for name,mat in M.items():
 nt=mat.node_tree;nodes=nt.nodes;bs=nodes.get('Principled BSDF');base=tuple(bs.inputs['Base Color'].default_value)
 geom=nodes.new('ShaderNodeNewGeometry');dot=nodes.new('ShaderNodeVectorMath');dot.operation='DOT_PRODUCT';dot.inputs[1].default_value=(-.35,-.5,.8);nt.links.new(geom.outputs['Normal'],dot.inputs[0])
 ramp=nodes.new('ShaderNodeValToRGB');ramp.color_ramp.interpolation='CONSTANT';ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
 for idx,(p,f) in enumerate([(0,.34),(.08,.66),(.60,1.0)]):
  e=ramp.color_ramp.elements[0] if idx==0 else ramp.color_ramp.elements.new(p);e.position=p;e.color=(f,f,f,1)
 nt.links.new(dot.outputs['Value'],ramp.inputs[0]);mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[1].default_value=base;nt.links.new(ramp.outputs[0],mix.inputs[2])
 emit=nodes.new('ShaderNodeEmission');nt.links.new(mix.outputs[0],emit.inputs[0]);nt.links.new(emit.outputs[0],nodes.get('Material Output').inputs[0])
 if name in ['Sky','Cloud','Distant']:emit.inputs[0].default_value=base;nt.links.remove(emit.inputs[0].links[0])
scene.cycles.samples=32;scene.view_settings.look='Medium High Contrast'
scene.render.filepath=ROOT+'/docs/qa/art-v2/shop-environment-v2-final-proof.png';bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/source_art/environment_v2/orbital_post_office_cel_preview.blend');bpy.ops.render.render(write_still=True)
print('ENVIRONMENT_V2_COMPLETE')
