"""Star Courier V4: newly modeled dimensional cutaway workshop study.
Run with Blender 4.3+: blender -b --python source_art/environment_v4/create_shop.py
Godot coordinates: X right, Y up, Z toward camera. No old art is read.
"""
import bpy, math, os, json, random, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/environment_v4'; SRC=Path(__file__).resolve().parent
OUT.mkdir(parents=True,exist_ok=True); SRC.mkdir(parents=True,exist_ok=True)
random.seed(43)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for d in list(bpy.data.materials): bpy.data.materials.remove(d)
scene=bpy.context.scene
M={}; CURRENT=None; objects=[]

def lin(c): return c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4

def material(key,hex,em=0):
    rgb=tuple(int(hex[i:i+2],16)/255 for i in (0,2,4)); rgba=(*[lin(v) for v in rgb],1)
    m=bpy.data.materials.new('V4_'+key); m.diffuse_color=rgba; m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=rgba
    bs.inputs['Roughness'].default_value=.82
    if em: bs.inputs['Emission Color'].default_value=rgba;bs.inputs['Emission Strength'].default_value=em
    M[key]=m; return m
palette={
'Ink':'101C34','DeepNavy':'172948','FrameNavy':'21375A','Cobalt':'31527D','EdgeBlue':'536F91',
'Steel':'7C8CA2','WallBlue':'939DAC','WarmWall':'B9A896','Plaster':'D4C2A8','Cream':'EFD8AD',
'WarmWhite':'FFF0C7','Gold':'E8AF30','SunGold':'FFCF4F','Ochre':'A8752D','BurntGold':'7F532B',
'ParcelKraft':'B58B5F','ParcelLight':'D4AF78','ParcelTan':'CAA183','ParcelDark':'8C684B',
'Tape':'F2D5A0','Paper':'F6E6C2','ScreenDark':'143952','Cyan':'4DCEDC','LeafDark':'416747',
'LeafGreen':'7A9549','LeafLight':'B1B44F','Terracotta':'B8754B','CableOrange':'C46F3D',
'WarmGlow':'FFF1B5','CyanGlow':'75E4EF'}
for k,v in palette.items():material(k,v,2 if k=='WarmGlow' else .7 if k=='CyanGlow' else 0)

def group(name):
    global CURRENT
    CURRENT=bpy.data.collections.new(name);scene.collection.children.link(CURRENT)

def reg(o,name,mat):
    o.name=name
    for c in list(o.users_collection):c.objects.unlink(o)
    CURRENT.objects.link(o);o.data.materials.append(M[mat]);objects.append(o)
    return o

def p(v):return Vector((v[0],-v[2],v[1]))
def bevel(o,width=.035):
    if width>0:
        m=o.modifiers.new('Machined edge bevel','BEVEL');m.width=width;m.segments=1
        m.affect='EDGES';m.harden_normals=True
    return o

def box(name,pos,size,mat,b=.025,rz=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p(pos));o=bpy.context.object
    o.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if rz:o.rotation_euler[1]=-math.radians(rz)
    return bevel(reg(o,name,mat),b)

def prism(name,poly,z,depth,mat,b=0):
    n=len(poly);vv=[p((x,y,z+depth/2)) for x,y in poly]+[p((x,y,z-depth/2)) for x,y in poly]
    ff=[tuple(range(n)),tuple(range(2*n-1,n-1,-1))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vv,[],ff);mesh.update();o=bpy.data.objects.new(name,mesh)
    return bevel(reg(o,name,mat),b)

def cylinder(name,pos,radius,depth,mat,axis=(0,1,0),verts=12,b=.015):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=radius,depth=depth,end_fill_type='NGON',location=p(pos));o=bpy.context.object
    o.rotation_euler=p(axis).to_track_quat('Z','Y').to_euler()
    return bevel(reg(o,name,mat),b)

def rod(name,a,b,r,mat,verts=10):
    a,b=Vector(a),Vector(b);return cylinder(name,(a+b)/2,r,(b-a).length,mat,b-a,verts,0)

def beam(name,a,b,w,d,mat,bev=.02):
    va,vb=p(a),p(b);bpy.ops.mesh.primitive_cube_add(size=1,location=(va+vb)*.5);o=bpy.context.object
    o.scale=(w,d,(vb-va).length);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.rotation_euler=(vb-va).to_track_quat('Z','Y').to_euler();return bevel(reg(o,name,mat),bev)

def tube(name,pts,r,mat):
    for i in range(len(pts)-1):rod(name+f' segment {i+1}',pts[i],pts[i+1],r,mat,10)
    for j,q in enumerate(pts[1:-1]):cylinder(name+f' elbow {j+1}',q,r*1.13,r*2.05,mat,axis=(0,0,1),verts=10,b=0)

def ring(name,pos,rx,ry,thick,mat,segments=24,tilt=0):
    cx,cy,cz=pos;ang=math.radians(tilt);pts=[]
    for i in range(segments+1):
        t=i*math.tau/segments;xx=rx*math.cos(t);yy=ry*math.sin(t);pts.append((cx+xx*math.cos(ang)-yy*math.sin(ang),cy+xx*math.sin(ang)+yy*math.cos(ang),cz))
    for i in range(segments):rod(name+str(i),pts[i],pts[i+1],thick,mat,6)

def fastener(name,pos,r=.055,mat='Ink'):
    return cylinder(name,pos,r,.035,mat,(0,0,1),6,0)

def panel(name,x,y,z,w,h,mat='WallBlue',rim='DeepNavy',depth=.12):
    box(name+' frame',(x,y,z),(w,h,depth),rim,.035)
    box(name+' recessed face',(x,y,z+depth*.55),(w-.12,h-.12,.035),mat,.012)

def parcel(name,x,y,z,w,h,d,mat='ParcelLight',label=True,orientation=0):
    box(name+' corrugated body',(x,y+h/2,z),(w,h,d),mat,.045,orientation)
    # Tape crosses have real thin volume, enough relief to read under sun.
    box(name+' tape over top',(x,y+h+.012,z),(.105,.022,d*.98),'Tape',.007,orientation)
    box(name+' front tape',(x,y+h*.52,z+d/2+.012),(.105,h*.98,.022),'Tape',.005,orientation)
    if label and w>.4:
        lx=x+w*.18;ly=y+h*.43;lz=z+d/2+.028
        box(name+' shipping label',(lx,ly,lz),(min(.31,w*.37),min(.26,h*.4),.025),'Paper',.012,orientation)
        box(name+' route code',(lx-.015,ly+.04,lz+.016),(min(.21,w*.24),.022,.011),'ParcelDark',.002,orientation)
        box(name+' scan mark',(lx-.045,ly-.025,lz+.016),(.055,.05,.011),'Cobalt',.002,orientation)

def leaf(name,a,b,width,mat):
    a,b=Vector(a),Vector(b);mid=a.lerp(b,.55);direction=b-a;side=Vector((-direction.y,direction.x,.07)).normalized()*width
    v=[p(a),p(mid-side),p(b),p(mid+side),p(mid+Vector((0,0,.06)))];faces=[(0,1,4),(1,2,4),(2,3,4),(3,0,4)]
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],faces);me.update();return reg(bpy.data.objects.new(name,me),name,mat)

def plant(name,x,y,z,s=1):
    # Tapered octagonal pot and broad faceted leaves, modeled individually.
    bpy.ops.mesh.primitive_cone_add(vertices=8,radius1=.22*s,radius2=.29*s,depth=.44*s,location=p((x,y+.22*s,z)))
    pot=bpy.context.object;pot.rotation_euler[0]=math.pi/2 # correct below: cone local Z points Godot Y, no rotation needed
    pot.rotation_euler=(0,0,0);reg(pot,name+' ceramic pot','Terracotta');bevel(pot,.025*s)
    cylinder(name+' dark soil',(x,y+.445*s,z),.255*s,.04*s,'ParcelDark',(0,1,0),10,0)
    for i in range(9):
        theta=i*2.39996;rx=math.cos(theta);rz=math.sin(theta);height=(.63+.20*((i*3)%5))*s
        a=(x,y+.44*s,z);b=(x+rx*.48*s,y+.46*s+height,z+rz*.28*s)
        rod(name+' stem '+str(i),a,(x+rx*.19*s,y+.45*s+height*.55,z+rz*.12*s),.016*s,'LeafDark',6)
        leaf(name+' leaf '+str(i),(x+rx*.08*s,y+.45*s+height*.27,z+rz*.07*s),b,.13*s,['LeafDark','LeafGreen','LeafLight'][i%3])

def screen(name,x,y,z,w,h):
    box(name+' armored housing',(x,y,z),(w+.16,h+.16,.2),'DeepNavy',.065)
    box(name+' inset glass',(x,y,z+.117),(w,h,.024),'ScreenDark',.02)
    for yy,ww in [(y+h*.3,w*.64),(y+h*.14,w*.78),(y-h*.22,w*.48)]:box(name+' cyan scan line',(x-w*.03,yy,z+.134),(ww,.025,.018),'CyanGlow',.002)
    # Simple original orbital flight schematic in real relief.
    pts=[(x-w*.28,y-h*.1,z+.14),(x-w*.09,y+h*.02,z+.14),(x+w*.08,y-h*.05,z+.14),(x+w*.30,y+h*.19,z+.14)]
    for i in range(3):rod(name+' route trace '+str(i),pts[i],pts[i+1],.017,'Cyan',6)
    for pt in pts:cylinder(name+' route station',pt,.035,.016,'CyanGlow',(0,0,1),8,0)

# ---------------------------------------------------------------------------
# Architecture is deliberately substantial and legible before prop details.
group('01 | Deep cutaway structure')
box('Entire structural deck',(0,-.47,-.25),(26.7,.82,5.8),'DeepNavy',.14)
box('Front fascia broad cobalt plane',(0,-.63,2.73),(26.8,.57,.38),'FrameNavy',.08)
box('Front top exposed edge',(0,-.09,2.76),(26.85,.13,.31),'EdgeBlue',.03)
box('Lower fascia dark shadow lip',(0,-.97,2.55),(26.5,.23,.55),'Ink',.035)
box('Left structural outer wall',(-13.2,3.95,-.05),(.64,8.25,5.48),'DeepNavy',.09)
box('Left cut wall front face',(-13.2,3.95,2.8),(.72,8.25,.24),'FrameNavy',.035)
# Roof breaks into bays rather than one featureless rectangle.
box('Main overhead roof volume',(-3.3,8.25,-.20),(20.6,.82,5.65),'DeepNavy',.11)
box('Roof front heavy beam',(-3.3,7.99,2.6),(20.75,.65,.52),'FrameNavy',.075)
box('Roof beam lower blue arris',(-3.3,7.65,2.73),(20.8,.12,.32),'EdgeBlue',.025)
box('Roof beam upper dark cap',(-3.3,8.70,2.2),(20.85,.20,1.15),'Ink',.045)
box('Upper service parapet',(-3.4,9.02,-2.8),(20.4,.62,.45),'FrameNavy',.055)
for x in [-10.97,-5.87,-.77,4.33]:
    box('Roof broad cover plate '+str(x),(x,8.31,2.91),(4.65,.38,.12),'Cobalt',.025)
    box('Roof inset dark seam '+str(x),(x+2.35,8.28,2.97),(.10,.58,.12),'Ink',.005)
# Inner supporting columns are modeled in depth and inset from the front cut.
for x in [-12.72,-4.08,6.48]:
    box('Bay upright inner web '+str(x),(x,3.74,-2.48),(.40,7.7,.60),'Cobalt',.055)
    box('Bay upright lower foot '+str(x),(x,.45,-2.29),(.71,.95,.83),'FrameNavy',.055)
    box('Bay upright upper capital '+str(x),(x,7.36,-2.32),(.82,.48,.85),'FrameNavy',.055)
    box('Bay upright amber inset '+str(x),(x,4.45,-2.09),(.20,5.2,.12),'Gold',.025)
# Right bay portal with distinctive stepped diagonal knee.
box('Launch portal back upright',(6.72,3.80,-1.92),(.80,7.90,.92),'FrameNavy',.08)
box('Launch portal cream cladding',(6.83,3.74,-1.38),(.54,7.02,.18),'Cream',.03)
box('Launch portal golden inner arris',(7.18,3.88,-1.64),(.13,7.72,.28),'Gold',.02)
prism('Launch top swept knee',[(6.43,6.48),(7.21,6.48),(9.3,8.54),(9.3,9.06),(6.43,9.06)],-.40,2.92,'FrameNavy',.055)
prism('Launch knee pale underside',[(7.12,6.51),(7.44,6.62),(9.55,8.69),(9.29,8.95)],1.08,.21,'Cream',.015)
prism('Launch knee dark bevel',[(6.78,6.23),(7.15,6.46),(9.19,8.50),(9.26,8.87),(6.78,6.49)],1.2,.16,'Ink',.013)
# Roof underside is warm enough to carry light but visibly thick.
box('Inner soffit left',(-8.45,7.64,-.83),(8.45,.16,4.1),'WarmWall',.025)
box('Inner soffit assembly',(.99,7.64,-.83),(10.08,.16,4.1),'WallBlue',.025)

# ---------------------------------------------------------------------------
group('02 | Back walls and floor plates')
box('Counter warm structural backing',(-8.47,3.76,-3.28),(8.6,7.48,.36),'WarmWall',.035)
box('Counter shadow shelf recess',(-8.46,3.67,-3.045),(7.73,5.80,.12),'BurntGold',.018)
box('Assembly broad blue gray wall',(1.12,3.67,-3.31),(9.92,7.34,.38),'WallBlue',.045)
# Large panel hierarchy, minimal trim across the editable volume.
for x,w in [(-2.1,2.9),(1.10,3.20),(4.35,2.65)]:
    box('Assembly broad light wall plate '+str(x),(x,4.15,-3.078),(w,5.77,.06),'WarmWall' if x>3 else 'WallBlue',.025)
    box('Assembly vertical panel seam '+str(x),(x+w/2+.025,4.05,-3.025),(.042,6.2,.04),'Steel',.0)
box('Assembly wall low plinth',(1.1,.49,-2.95),(10.1,.87,.3),'FrameNavy',.04)
box('Back horizontal service chase',(.86,6.67,-2.91),(10.12,.36,.33),'DeepNavy',.04)
box('Back horizontal chase blue cap',(.86,6.89,-2.88),(10.18,.10,.38),'EdgeBlue',.02)
# Deck divisions follow station boundaries, so thickness reads instead of wallpaper.
for i,(x,w) in enumerate([(-11.5,3),(-8.35,3.1),(-5.3,2.8),(-2.28,3.05),(.92,3.12),(4.10,3.1),(7.20,2.86),(10.12,2.83),(12.4,1.57)]):
    box('Walkable deck slab '+str(i),(x,.035,-.2),(w,.13,5.18),'Plaster' if i<6 else 'Cream',.025)
    box('Front deck golden rim '+str(i),(x,.075,2.42),(w,.10,.16),'Gold',.018)
    box('Deck inset long seam '+str(i),(x+w/2+.017,.107,-.25),(.035,.018,5.02),'Steel',0)
# Two long shallow fore/aft seams, with broader material regions.
for z in [-1.65,1.50]:box('Deck expansion joint '+str(z),(-3.11,.105,z),(20.2,.022,.05),'Steel',0)
# Receiver lane is an actual inset runway, not a decal.
box('Launch bay inset runway',(9.92,.122,.32),(5.96,.10,2.20),'FrameNavy',.035)
box('Launch bay runway central plate',(9.96,.185,.30),(5.46,.036,1.32),'WarmWall',.012)
for z in [-.80,1.45]:box('Launch runway gold rail '+str(z),(9.95,.201,z),(6.0,.06,.13),'SunGold',.013)
for x in [7.1,7.45,7.80,8.15,8.5,8.85]:
    box('Launch threshold white step '+str(x),(x,.228,.29),(.15,.021,1.95),'Cream',.008)

# ---------------------------------------------------------------------------
group('03 | Warm parcel shelving')
# Shelves have broad warm front edges and deep blue shadow undersides.
for y in [1.88,3.24,4.59,5.95]:
    box('Shelf full deep board '+str(y),(-8.49,y,-2.17),(7.72,.18,1.56),'DeepNavy',.025)
    box('Shelf honey front edge '+str(y),(-8.49,y+.027,-1.337),(7.77,.16,.16),'Ochre',.021)
    box('Shelf top light plane '+str(y),(-8.49,y+.10,-2.16),(7.63,.052,1.45),'ParcelLight',.012)
for x in [-12.28,-9.91,-6.64,-4.66]:
    box('Shelf upright '+str(x),(x,3.95,-2.98),(.13,5.04,.14),'DeepNavy',.017)
    for y in [3.24,4.59,5.95]:
        prism('Shelf triangular bracket',[(x-.14,y-.20),(x+.14,y-.20),(x+.14,y-.52),(x-.14,y-.65)],-1.98,1.45,'FrameNavy',.012)
# Parcel compositions vary by silhouette and mass, avoiding a grid of identical blocks.
layouts=[
(1.995,[(-9.64,.77,.57,.87,'ParcelTan'),(-8.75,.60,.81,.77,'ParcelLight'),(-5.79,1.05,.68,.82,'ParcelKraft'),(-4.98,.41,.44,.78,'ParcelDark')]),
(3.355,[(-11.69,.56,.89,.78,'ParcelKraft'),(-10.77,.90,.64,.81,'ParcelLight'),(-9.57,1.19,.88,.82,'ParcelLight'),(-7.03,.51,.75,.72,'ParcelKraft'),(-5.95,.84,.65,.74,'ParcelTan'),(-5.05,.68,.93,.79,'ParcelLight')]),
(4.705,[(-11.50,1.01,.69,.82,'ParcelLight'),(-10.36,.76,.90,.78,'ParcelDark'),(-9.34,.82,.50,.86,'ParcelKraft'),(-8.18,1.13,.81,.75,'ParcelLight'),(-6.82,.65,.64,.83,'ParcelTan'),]),
(6.065,[(-11.38,1.2,.68,.87,'ParcelKraft'),(-9.04,.49,.68,.73,'ParcelKraft'),(-7.82,.99,.45,.76,'ParcelKraft'),(-6.34,1.29,.74,.80,'ParcelLight'),(-5.12,.67,.67,.70,'ParcelKraft')])]
for row,items in layouts:
    for i,(x,w,h,d,m) in enumerate(items):parcel('Shelf parcel '+str(row)+' '+str(i),x,row,-2.02,w,h,d,m,(i%4!=1))
# Distinct postal storage families break up the rows of corrugated parcels.
# A large hard-sided transit case has a lid, corner guards, inset panel and handle.
box('Oversized blue transit case',(-11.05,2.44,-2.00),(1.75,.87,1.00),'FrameNavy',.08)
box('Blue transit case raised lid',(-11.05,2.93,-2.00),(1.84,.13,1.06),'Cobalt',.028)
box('Blue transit case cream label well',(-11.10,2.43,-1.47),(.66,.38,.044),'Cream',.016)
for x in [-11.78,-10.32]:
    box('Transit case tall corner guard',(x,2.48,-1.45),(.13,.82,.09),'Steel',.013)
    box('Transit case golden latch',(x,2.70,-1.385),(.13,.18,.07),'Gold',.012)
box('Transit case lid handle bridge',(-11.05,3.077,-1.87),(.48,.06,.10),'Ink',.015)
for x in [-11.28,-10.82]:box('Transit case lid handle stem',(x,3.01,-1.87),(.065,.12,.10),'Ink',.011)
# Cinched canvas mail sack, deliberately irregular beveled profile and folded top.
prism('Canvas inter-orbit mail sack',[(-8.98,3.355),(-7.59,3.355),(-7.51,3.61),(-7.63,4.11),(-7.89,4.34),(-7.78,4.48),(-8.43,4.47),(-8.62,4.31),(-8.99,3.93)],-2.08,.87,'Plaster',.06)
prism('Canvas mail sack broad side fold',[(-8.98,3.36),(-8.68,3.36),(-8.56,4.22),(-8.67,4.25),(-8.99,3.93)],-1.618,.035,'ParcelTan',.015)
box('Canvas mail sack cinch strap',(-8.14,4.33,-1.592),(.52,.09,.047),'BurntGold',.013)
box('Canvas mail sack route patch',(-8.04,3.81,-1.614),(.49,.38,.039),'Paper',.011)
box('Canvas sack broad printed route',(-8.04,3.83,-1.589),(.29,.076,.017),'Cobalt',.005)
# Three capped shipping tubes make circular silhouettes against the shelf shadows.
for x,y,r in [(-6.07,4.96,.21),(-5.58,4.96,.23),(-5.84,5.37,.22)]:
    cylinder('Long parcel shipping tube',(x,y,-2.08),r,.89,'ParcelLight',(0,0,1),12,.018)
    cylinder('Shipping tube deep end cap',(x,y,-1.605),r*1.04,.063,'Ochre',(0,0,1),12,.008)
    cylinder('Shipping tube pale end face',(x,y,-1.567),r*.76,.026,'Paper',(0,0,1),12,.005)
box('Mail tube bundle outer strap',(-5.83,5.05,-1.545),(.087,.65,.018),'Tape',.006)
# Low bundles, laced diagonally, present a horizontal rhythm near the upper shelf.
for i in range(3):
    box('Flat bound document packet '+str(i),(-10.42,6.18+i*.19,-2.03),(1.36-.12*(i%2),.16,.83),'Paper' if i==1 else 'ParcelTan',.022)
box('Document bundle broad strap',(-10.42,6.38,-1.59),(.12,.58,.025),'BurntGold',.005)

# Small stacks create stepped silhouettes rather than more equal cells.
parcel('Stacked slim packet',-10.05,5.255,-2.07,.81,.26,.74,'ParcelTan')
parcel('Stacked narrow priority box',-5.84,5.21,-2.11,.70,.42,.66,'ParcelLight')
parcel('Flat top shelf packet',-7.82,6.53,-2.03,.65,.25,.60,'ParcelTan')
# A perpendicular left rack visibly turns into the depth of the shop.
box('Return rack side support',(-12.58,3.47,-.60),(.28,5.35,2.12),'FrameNavy',.035)
for y in [1.40,2.80,4.20,5.60]:
    box('Side return rack shelf '+str(y),(-12.14,y,-.67),(1.10,.13,2.26),'Ochre',.022)
    parcel('Side return parcel '+str(y),-12.00,y+.09,-.51,.58,.75,.92,'ParcelLight')
    parcel('Side return slim parcel '+str(y),-12.06,y+.09,-1.60,.45,.52,.55,'ParcelTan')
plant('Shelf fern',-11.35,6.10,-1.95,.73)
plant('Counter end plant',-4.82,1.315,-.87,.76)

# ---------------------------------------------------------------------------
group('04 | Counter and receipt kiosk')
# Counter positioned so a 2.4-unit clerk is visible behind it; front path remains clear.
box('Counter substantial body',(-8.30,.575,.10),(6.40,1.05,1.73),'FrameNavy',.10)
box('Counter overhanging worktop',(-8.30,1.165,.10),(6.62,.19,1.95),'Ochre',.045)
box('Counter lit cream top',(-8.30,1.278,.07),(6.60,.044,1.95),'Cream',.02)
box('Counter deep toe shadow',(-8.30,.13,.87),(6.39,.22,.30),'Ink',.025)
box('Counter lower cobalt kick',(-8.30,.29,1.012),(6.30,.17,.14),'Cobalt',.018)
for x,w in [(-10.72,1.27),(-8.85,2.18),(-6.39,2.37)]:
    panel('Counter front raised panel '+str(x),x,.715,1.005,w,.74,'Steel','DeepNavy',.09)
    box('Counter inset upper highlight '+str(x),(x,1.075,1.076),(w-.15,.052,.03),'EdgeBlue',.004)
box('Counter front notice',(-8.65,.69,1.095),(.63,.59,.019),'Paper',.01)
for i in range(5):box('Notice printed line '+str(i),(-8.65,.88-i*.075,1.11),(.43-(i%2)*.08,.019,.014),'ParcelKraft',.001)
# Left service terminal lies below face height.
screen('Counter customer reader',-10.73,1.575,.12,.63,.46)
box('Counter reader stand',(-10.73,1.375,-.025),(.30,.20,.45),'DeepNavy',.02)
box('Counter brass service bell base',(-8.65,1.347,.50),(.46,.06,.29),'Gold',.025)
cylinder('Service bell dome',(-8.65,1.425,.5),.12,.12,'SunGold',(0,1,0),12,.025)
# Kiosk sits at right counter return, with a stepped recognizable silhouette.
box('Receipt kiosk pedestal',(-4.97,.83,.62),(1.04,1.64,1.02),'DeepNavy',.07)
box('Receipt kiosk gold vertical inset',(-5.35,1.13,1.15),(.14,1.43,.055),'Gold',.015)
prism('Receipt kiosk upper angled silhouette',[(-5.45,1.58),(-4.41,1.58),(-4.41,2.76),(-5.26,2.76),(-5.45,2.16)],.51,.85,'FrameNavy',.06)
screen('Receipt kiosk live terminal',-4.89,2.43,.985,.62,.40)
box('Receipt kiosk output lip',(-4.90,1.98,1.10),(.71,.105,.30),'Ink',.02)
box('Receipt kiosk ticket',(-4.90,1.83,1.28),(.39,.28,.016),'Paper',.007)
for i in range(3):box('Kiosk receipt line '+str(i),(-4.9,1.90-i*.055,1.294),(.25,.012,.01),'ParcelDark',.001)
box('Receipt kiosk drawer',(-4.96,.64,1.15),(.68,.51,.045),'Cobalt',.025)
box('Receipt kiosk drawer pull',(-4.96,.77,1.19),(.25,.055,.055),'Cream',.014)
for i in range(3):box('Kiosk button '+str(i),(-5.09+i*.2,2.08,1.019),(.105,.053,.045),['Cyan','Gold','CableOrange'][i],.012)
# One parcel on the back work edge, leaving the clerk's face free.
parcel('Counter outgoing parcel',-9.51,1.308,-.25,.72,.57,.61,'ParcelLight')

# ---------------------------------------------------------------------------
group('05 | Assembly platform and tool wall')
# This is functional scaffolding around an EMPTY live module volume, not a fake ship.
box('Assembly low machine footing',(1.05,.10,-.07),(7.61,.40,2.70),'DeepNavy',.07)
box('Assembly warm machine top',(1.05,.34,-.10),(7.72,.12,2.78),'Ochre',.025)
box('Assembly clean platform face',(1.05,.43,-.12),(7.69,.06,2.70),'Steel',.02)
box('Assembly front rail',(1.05,.30,1.36),(7.54,.37,.15),'FrameNavy',.04)
# Separately fabricated stepped platform endcaps.
for x in [-2.85,4.95]:
    box('Bench end armor '+str(x),(x,.20,-.06),(.33,.60,2.86),'Cobalt',.03)
    box('Bench end gold flash '+str(x),(x,.46,.74),(.37,.07,1.13),'Gold',.02)
# Drawer banks live behind the assembly grid, never in its front interaction plane.
for x,w in [(-1.71,1.27),(3.84,1.33)]:
    box('Rear bench cabinet '+str(x),(x,.92,-2.11),(w,1.72,1.2),'DeepNavy',.065)
    for j in range(3):
        yy=.42+j*.44;box('Tool drawer '+str(x)+' '+str(j),(x,yy,-1.48),(w-.13,.35,.07),'Cobalt',.025)
        box('Tool drawer pull '+str(x)+' '+str(j),(x+.10,yy+.07,-1.414),(w*.44,.052,.047),'Cream',.01)
    box('Rear cabinet top '+str(x),(x,1.83,-2.07),(w+.14,.13,1.38),'WarmWall',.025)
# Broad electronics cabinet at left boundary.
box('Assembly left equipment mast',(-3.47,3.15,-2.66),(.57,5.81,.57),'FrameNavy',.055)
screen('Diagnostic wall monitor',-2.42,4.27,-2.61,1.58,1.06)
box('Monitor bottom button strip',(-2.42,3.61,-2.43),(1.71,.17,.19),'DeepNavy',.025)
for i in range(5):cylinder('Diagnostic monitor control '+str(i),(-3.02+i*.23,3.63,-2.321),.045,.028,'Gold' if i==4 else 'Steel',(0,0,1),10,0)
# Work station tools are grouped to the side and upper region of the panel.
panel('Shadowed tool board',.08,4.45,-2.94,2.58,2.53,'Steel','FrameNavy',.10)
# Tool board's sparse socket holes are geometry, not a texture.
for xx in [-.9,-.4,.1,.6,1.1]:
    for yy in [3.43,4.06,4.69,5.32]:cylinder('Tool wall peg',(xx,yy,-2.86),.022,.025,'FrameNavy',(0,0,1),6,0)
# Wrench recognizable open-jaw contour, forged flat volume.
for x,y,s in [(-.64,4.42,1),(.08,4.5,.78),(.78,4.38,.88)]:
    prism('Tool wall hanging spanner',[(x-.07*s,y-.49*s),(x+.07*s,y-.49*s),(x+.07*s,y+.26*s),(x+.19*s,y+.40*s),(x+.18*s,y+.65*s),(x+.08*s,y+.70*s),(x+.08*s,y+.47*s),(x-.08*s,y+.47*s),(x-.08*s,y+.70*s),(x-.18*s,y+.65*s),(x-.19*s,y+.40*s),(x-.07*s,y+.26*s)],-2.785,.06,'DeepNavy',.012)
    cylinder('Spanner handle hole',(x,y-.38*s,-2.746),.038*s,.012,'Steel',(0,0,1),10,0)
# Paper job cards on side of equipment board, ample blank surface remains.
for x,y,w,h in [(1.82,4.24,.48,.68),(2.50,3.85,.58,.74),(2.95,4.95,.65,.85)]:
    box('Assembly job card',(x,y,-2.962),(w,h,.027),'Paper',.01)
    box('Assembly job card clip',(x,y+h*.48,-2.929),(.18,.055,.038),'Ochre',.009)
    for j in range(3):box('Assembly job card line',(x,y+.11-j*.13,-2.942),(w*.64,.022,.013),'ParcelKraft',.001)
# Slender utility cart kept off the live build surface left edge.
box('Tool cart frame',(-3.95,.78,.58),(.65,1.34,.90),'FrameNavy',.055)
box('Tool cart top lip',(-3.95,1.51,.59),(.76,.15,1.06),'Gold',.025)
for j in range(3):
    box('Cart drawer '+str(j),(-3.95,.47+j*.32,1.06),(.60,.27,.07),'Cobalt',.017)
    box('Cart drawer pull '+str(j),(-3.95,.55+j*.32,1.113),(.23,.037,.029),'Cream',.006)
for x in [-4.16,-3.74]:cylinder('Tool cart wheel',(x,.14,.66),.13,.12,'Ink',(1,0,0),12,0)

# Vise sits on the side cart outside the complete module-cell envelope.
box('Bench vise bolted base',(-4.0,1.65,.77),(.58,.17,.51),'FrameNavy',.045)
box('Bench vise sliding body',(-3.97,1.79,.77),(.64,.14,.31),'Steel',.025)
for x in [-4.22,-3.72]:box('Bench vise open jaw',(x,1.89,.77),(.11,.13,.35),'Cobalt',.017)
rod('Bench vise horizontal leadscrew',(-4.49,1.79,.77),(-3.59,1.79,.77),.032,'DeepNavy',10)
rod('Bench vise crank handle',(-4.49,1.63,.77),(-4.49,1.90,.77),.025,'Gold',8)
# Shallow maintenance tray with a broad rim and two large tool silhouettes.
box('Side maintenance case',(6.03,.37,1.00),(.99,.70,.81),'FrameNavy',.05)
box('Bench maintenance tray',(6.03,.767,1.00),(.95,.08,.45),'Ochre',.022)
box('Bench tray dark basin',(6.03,.816,1.00),(.84,.026,.33),'DeepNavy',.012)
rod('Bench tray spare torque driver',(5.70,.86,.93),(6.20,.86,.93),.044,'Gold',8)
box('Bench tray spare grip',(6.31,.858,.94),(.20,.10,.12),'CableOrange',.018)
rod('Bench tray silver flat tool',(5.80,.849,1.11),(6.38,.849,1.09),.031,'Steel',8)
# Short repair stool lies below the assembly envelope, close to the floor edge.
cylinder('Repair stool broad padded seat',(-4.58,.78,1.97),.29,.15,'BurntGold',(0,1,0),12,.025)
cylinder('Repair stool golden seat seam',(-4.58,.70,1.97),.275,.045,'Gold',(0,1,0),12,.006)
for a in [0,2.094,4.189]:
    xa=math.cos(a);za=math.sin(a)
    beam('Repair stool splayed leg',(-4.58+xa*.16,.69,1.97+za*.16),(-4.58+xa*.30,.13,1.97+za*.30),.075,.075,'FrameNavy',.011)
# A rear pressure canister is outside the right edge of the editable module grid.
cylinder('Workshop refill canister',(5.69,.73,-.76),.29,1.27,'Cobalt',(0,1,0),12,.065)
cylinder('Refill canister gold shoulder',(5.69,1.33,-.76),.26,.16,'Gold',(0,1,0),12,.025)
box('Refill canister valve block',(5.69,1.49,-.76),(.15,.19,.15),'DeepNavy',.013)
rod('Refill valve handle',(5.47,1.58,-.76),(5.91,1.58,-.76),.035,'CableOrange',8)
box('Refill canister pale route strip',(5.69,.87,-.451),(.14,.72,.021),'Cream',.008)

# ---------------------------------------------------------------------------
group('06 | Overhead gantry and service pipes')
# Substantial overhead bridge establishes scale; the working envelope below stays free.
box('Gantry roof mount',(1.27,7.32,-1.12),(8.51,.39,1.07),'DeepNavy',.04)
box('Gantry main golden rail',(1.27,7.09,-.87),(8.35,.32,.64),'Gold',.04)
box('Gantry top sun lip',(1.27,7.29,-.79),(8.43,.10,.85),'SunGold',.025)
box('Gantry rail dark inner channel',(1.26,6.96,-.493),(7.91,.12,.1),'BurntGold',.012)
for x in [-2.65,5.19]:
    box('Gantry blue clamp '+str(x),(x,7.18,-.79),(.40,.61,.96),'FrameNavy',.03)
    fastener('Gantry clamp bolt '+str(x),(x,7.16,-.288),.07,'Steel')
# Trolley resides high at right edge, so no tool is mistaken for a ship component.
box('Overhead hoist trolley',(4.53,6.75,-.75),(1.53,.52,.93),'Ochre',.055)
box('Hoist trolley gold facing',(4.53,6.77,-.215),(1.37,.39,.15),'Gold',.032)
for x in [4.0,5.0]:cylinder('Hoist trolley wheel',(x,7.10,-.77),.16,.33,'DeepNavy',(0,0,1),12,.012)
beam('Raised articulated hoist link',(4.93,6.55,-.79),(5.33,5.92,-.69),.30,.33,'Gold',.032)
beam('Raised articulated hoist forearm',(5.33,5.92,-.69),(5.57,5.36,-.60),.24,.27,'Gold',.025)
for q in [(4.93,6.55,-.51),(5.33,5.92,-.43),(5.57,5.36,-.38)]:
    cylinder('Hoist dark circular hinge',q,.19,.14,'DeepNavy',(0,0,1),12,.015)
    cylinder('Hoist hinge inner cap',(q[0],q[1],q[2]+.08),.088,.04,'Steel',(0,0,1),12,.008)
# Empty clamp at far right is visibly mechanical and above editing grid.
box('Raised empty hoist clamp',(5.64,5.12,-.65),(.41,.32,.44),'DeepNavy',.035)
for x in [5.43,5.85]:box('Raised empty clamp jaw',(x,4.93,-.63),(.12,.35,.41),'Steel',.013)
# Curving hoses with broad arc contour.
tube('Gantry copper hose',[(2.95,7.0,-1.9),(2.95,6.15,-1.9),(3.06,5.92,-1.9),(3.40,5.88,-1.9),(3.63,6.08,-1.9),(3.65,6.58,-1.9)],.058,'CableOrange')
tube('Gantry thick dark power hose',[(4.52,6.55,-2.37),(4.52,5.60,-2.37),(4.70,5.30,-2.37),(5.06,5.17,-2.37),(5.49,5.24,-2.37),(5.78,5.55,-2.37),(5.78,6.82,-2.37)],.090,'DeepNavy')
tube('Right copper service riser',[(5.81,.52,-2.18),(5.81,2.40,-2.18),(6.01,2.60,-2.18),(6.01,6.43,-2.18)],.10,'CableOrange')
tube('Left ceiling utility pipe',[(-4.02,8.39,1.52),(-4.02,6.52,1.52),(-3.87,6.35,1.52),(-3.30,6.35,1.52),(-3.14,6.55,1.52),(-3.14,7.51,1.52)],.14,'Ink')
tube('Left ceiling steel inset pipe',[(-3.98,8.34,1.65),(-3.98,6.52,1.65),(-3.82,6.42,1.65),(-3.32,6.42,1.65),(-3.22,6.55,1.65),(-3.22,7.49,1.65)],.060,'Cobalt')
# Vertical cable junctions.
for x,y in [(-3.43,2.30),(5.91,3.31),(6.01,5.49)]:
    box('Utility electrical junction',(x,y,-2.21),(.36,.48,.32),'DeepNavy',.04)
    box('Junction status light',(x,y+.05,-2.032),(.11,.12,.023),'CyanGlow',.008)

# ---------------------------------------------------------------------------
group('07 | Warm practical lights and orbital sign')
# Long warm fixtures illuminate zones; their housings are dimensional.
for name,x,y,z,w in [('Counter top strip',-8.35,7.20,-1.30,6.20),('Assembly left strip',-1.53,5.93,-2.49,2.47),('Assembly right strip',3.77,5.93,-2.51,2.28)]:
    box(name+' dark housing',(x,y,z),(w+.20,.26,.39),'DeepNavy',.035)
    box(name+' amber bezel',(x,y-.019,z+.213),(w+.05,.15,.062),'Gold',.015)
    box(name+' glowing diffuser',(x,y-.018,z+.252),(w,.089,.027),'WarmGlow',.007)
# Pendant silhouettes stay far from the clerk head.
for x,y in [(-10.68,5.43),(-5.07,5.81)]:
    rod('Pendant cable',(x,7.45,.16),(x,y+.42,.16),.035,'Ink',8)
    cylinder('Pendant top collar',(x,y+.39,.16),.105,.24,'DeepNavy',(0,1,0),10,.012)
    # Wide industrial cone with faceted shade.
    bpy.ops.mesh.primitive_cone_add(vertices=12,radius1=.39,radius2=.17,depth=.28,location=p((x,y+.18,.16)))
    reg(bpy.context.object,'Pendant steel faceted shade','FrameNavy')
    cylinder('Pendant warm underside',(x,y+.025,.16),.36,.036,'WarmGlow',(0,1,0),12,.006)
# Wall orbital sign: original ellipse/circle geometry, no imported logo.
box('Tall orbital service banner',(-4.66,4.65,-2.28),(.84,2.42,.13),'Cream',.02)
box('Banner golden border',(-4.98,4.65,-2.197),(.11,2.42,.026),'Gold',.006)
cylinder('Original orbital emblem center',(-4.61,4.64,-2.185),.17,.035,'Cobalt',(0,0,1),14,.007)
ring('Original orbital emblem orbit',(-4.61,4.64,-2.153),.33,.12,.023,'Cobalt',24,32)
box('Orbital bay portal gold panel',(6.82,5.62,-1.246),(.52,1.22,.043),'Gold',.01)
cylinder('Bay orbital emblem center',(6.82,5.64,-1.21),.105,.025,'FrameNavy',(0,0,1),12,.004)
ring('Bay original orbital orbit',(6.82,5.64,-1.19),.22,.08,.020,'FrameNavy',20,40)
for y in [1.08,3.86,6.75]:
    box('Launch portal light armor',(7.05,y,-.985),(.21,.60,.33),'DeepNavy',.03)
    box('Launch portal glowing slot',(7.054,y,-.797),(.088,.40,.028),'WarmGlow',.009)

# ---------------------------------------------------------------------------
group('08 | Launch cradle and rear guard rail')
# Cradle stays on right, separated from build plane and runtime launcher parts.
box('Launch cradle broad base',(10.15,.33,-1.12),(5.24,.43,2.00),'DeepNavy',.065)
box('Launch cradle light upper deck',(10.15,.575,-1.14),(4.96,.16,1.82),'Cream',.025)
box('Launch cradle rear crosspiece',(10.15,.87,-1.94),(4.22,.42,.41),'Cobalt',.04)
# Two angular outriggers make a wide low silhouette instead of more tall boxes.
for x,sgn in [(8.01,-1),(12.27,1)]:
    prism('Launch cradle splayed foot',[(x-.61,.21),(x+.61,.21),(x+.42,.46),(x+.19,.92),(x-.17,.92),(x-.40,.48)],-.72,1.63,'FrameNavy',.04)
    prism('Launch cradle golden outside plate',[(x-.48,.26),(x+.48,.26),(x+.24,.49),(x+.11,.76),(x-.13,.76),(x-.30,.44)],.135,.11,'Gold',.02)
    box('Launch cradle upright hinge',(x,.93,-.66),(.51,.61,.64),'Cobalt',.035)
    cylinder('Launch cradle pivot cap',(x,.94,-.291),.22,.11,'DeepNavy',(0,0,1),12,.015)
    cylinder('Launch cradle pivot center',(x,.94,-.22),.09,.03,'Steel',(0,0,1),10,.006)
    # Jaws lift behind actual modules and open toward the sky.
    beam('Open cradle upper jaw',(x+sgn*.09,1.13,-1.50),(x+sgn*.31,1.78,-1.48),.17,.26,'Gold',.024)
    beam('Open cradle bent lip',(x+sgn*.31,1.78,-1.48),(x+sgn*.06,1.90,-1.45),.15,.26,'SunGold',.02)
# Remote ignition terminal at portal foot.
box('Bay terminal blue pedestal',(7.03,.76,.00),(.51,1.46,.67),'FrameNavy',.045)
box('Bay terminal golden side',(7.29,.88,.0),(.115,1.61,.73),'Gold',.022)
screen('Bay terminal ready display',7.02,1.71,.32,.48,.56)
# Behind the cradle a thin perimeter rail keeps the skyline open.
for x in [7.37,9.75,12.93]:
    box('Rear bay rail post '+str(x),(x,.72,-2.66),(.13,1.44,.16),'Gold',.022)
    box('Rear rail foot '+str(x),(x,.15,-2.66),(.35,.17,.32),'FrameNavy',.018)
for y in [.57,1.25]:box('Rear bay guard rail '+str(y),(10.13,y,-2.66),(5.77,.12,.15),'SunGold',.02)

# ---------------------------------------------------------------------------
group('09 | Cutaway underfloor machinery')
# Big dark foreground masses give the reference its depth and shadow weight.
for x,w in [(-11.26,3.75),(-6.79,4.41),(-1.85,4.62),(3.32,4.37)]:
    box('Underfloor main girders '+str(x),(x,-1.50,-.15),(w,.74,4.17),'FrameNavy',.075)
    box('Underfloor front beam face '+str(x),(x,-1.48,2.09),(w-.10,.53,.19),'Cobalt',.035)
    box('Underfloor deep inset '+str(x),(x,-1.39,2.203),(w-.5,.21,.06),'DeepNavy',.01)
for x in [-11.80,-6.25,-.75,5.18]:
    box('Floor supporting drop column '+str(x),(x,-2.17,-.49),(.57,2.75,3.58),'DeepNavy',.065)
    box('Drop column pale edge '+str(x),(x-.18,-2.12,1.39),(.11,2.57,.21),'Cobalt',.017)
    beam('Underfloor diagonal crossbrace '+str(x),(x-.17,-3.35,.23),(x+1.65,-1.66,.23),.32,.37,'FrameNavy',.033)
# Front flange caps and grouped bolt pairs are sparse and intentional.
for x in [-12.76,-9.75,-6.38,-2.17,2.95,5.81,9.01,12.30]:
    box('Front structural splice plate '+str(x),(x,-.64,2.987),(.49,.72,.14),'Cobalt',.025)
    for xx in [x-.13,x+.13]:fastener('Structural splice bolt',(xx,-.57,3.069),.065,'Ink')
# Thick copper and navy conduits follow the structure with clear silhouettes.
tube('Underfloor copper return',[(-11.47,-.95,1.64),(-11.47,-2.18,1.64),(-11.13,-2.51,1.64),(-8.74,-2.51,1.64),(-8.41,-2.19,1.64),(-8.41,-1.53,1.64)],.17,'Ochre')
tube('Underfloor broad coolant loop',[(-5.72,-.90,1.76),(-5.72,-2.05,1.76),(-5.48,-2.35,1.76),(-4.82,-2.35,1.76),(-4.49,-2.06,1.76),(-4.49,-1.11,1.76)],.20,'DeepNavy')
tube('Underfloor copper service line',[(-12.48,-3.01,.76),(-9.83,-3.01,.76),(-9.53,-2.68,.76),(-9.53,-1.61,.76)],.145,'BurntGold')
tube('Long underfloor segmented service',[(-3.49,-1.81,1.24),(-3.49,-2.73,1.24),(-3.16,-2.97,1.24),(.96,-2.97,1.24),(1.32,-2.63,1.24),(1.32,-1.84,1.24)],.13,'Cobalt')
# Under-bay cable hangs in an asymmetric shallow U against bright city.
tube('Launch hanging power loop',[(5.86,-.69,1.26),(5.86,-2.13,1.26),(6.25,-2.68,1.26),(7.13,-2.80,1.26),(7.75,-2.44,1.26),(8.09,-1.70,1.26),(8.09,-.80,1.26)],.15,'DeepNavy')
box('Underbay front diagonal beam',(11.19,-1.18,-.09),(4.16,.60,3.88),'FrameNavy',.065)
beam('Underbay angled leg',(8.42,-2.11,-.24),(10.25,-.81,-.24),.53,1.24,'FrameNavy',.06)
# Fabric-like hanging panel is a tapered actual plate with original orbital emblem.
prism('Underfloor hanging service pennant',[(2.33,-1.1),(3.63,-1.1),(3.63,-3.77),(2.33,-3.62)],1.76,.05,'WarmWall',.008)
box('Pennant top dark fastening bar',(2.98,-1.12,1.82),(1.44,.15,.10),'DeepNavy',.02)
cylinder('Pennant orbital emblem center',(2.98,-2.23,1.81),.21,.019,'Cobalt',(0,0,1),14,0)
ring('Pennant original orbital orbit',(2.98,-2.23,1.832),.45,.15,.032,'Cobalt',24,32)

# ---------------------------------------------------------------------------
group('10 | Large hazard inserts')
# Hazard plates are confined to structural edges. No stripes wallpapering the walls.
for cx,cy,cz,w in [(3.83,.32,1.452,1.60),(-2.28,.31,1.452,.90),(6.05,-.07,2.86,.71)]:
    box('Hazard base',(cx,cy,cz),(w,.25,.065),'Gold',.012)
    for dx in [-.52,0,.52]:
        if abs(dx)<w*.5-.15:
            prism('Hazard navy diagonal',[(cx+dx-.17,cy-.125),(cx+dx+.02,cy-.125),(cx+dx+.18,cy+.125),(cx+dx-.01,cy+.125)],cz+.04,.018,'DeepNavy')
# Deck landing guide arrow in thick pale geometry.
prism('Launch deck forward chevron',[(10.77,.0),(11.21,.0),(11.79,.43),(11.21,.86),(10.77,.86),(11.29,.43)],0,.028,'WarmWhite')
o=objects[-1];# relocate flat arrow from XY to XZ walking plane
# Rebuild arrow as a horizontal six-point extruded profile through a direct transform.
o.rotation_euler[0]=math.pi/2;o.location=p((0,.28,-.15))

# ---------------------------------------------------------------------------
group('11 | Embedded upper station and shadow machinery')
# The cutaway belongs to a larger inhabited station. Broad roof equipment extends
# past the top framing, rather than ending in a detached dollhouse outline.
box('Upper station dark backing',(-4.14,10.64,-2.47),(18.99,4.07,1.18),'DeepNavy',.055)
for x,w,h in [(-11.80,2.53,2.94),(-8.83,2.84,3.66),(-5.70,2.91,2.70),(-2.58,2.64,3.95),(.39,2.82,3.29),(3.72,2.63,2.60)]:
    box('Upper station facade volume '+str(x),(x,8.65+h/2,-1.71),(w,h,1.04),'FrameNavy',.04)
    box('Upper facade stepped edge '+str(x),(x-w*.40,8.82+h/2,-1.10),(.12,h-.20,.18),'Cobalt',.013)
    box('Upper facade inset well '+str(x),(x+.18,8.92+h*.44,-1.12),(w*.53,h*.49,.10),'Ink',.018)
    box('Upper facade utility panel '+str(x),(x+.14,8.95+h*.44,-1.055),(w*.38,h*.37,.026),'Cobalt',.012)
    box('Upper facade horizontal cover '+str(x),(x,8.84,-.89),(w-.15,.22,.52),'EdgeBlue',.027)
# Fine silhouette accents only where they reinforce service construction.
for x,y in [(-10.93,10.8),(-7.31,11.58),(-.57,11.05),(4.74,10.66)]:
    box('Roof electrical vertical conduit '+str(x),(x,y,-.85),(.10,2.56,.18),'Ink',.016)
    box('Roof electrical termination '+str(x),(x,y+.67,-.69),(.34,.42,.16),'Cobalt',.025)
for x in [-9.25,-1.97,3.65]:
    box('Upper warm apartment recess '+str(x),(x,10.22,-1.038),(.47,.82,.047),'BurntGold',.012)
    box('Upper amber window slit '+str(x),(x,10.29,-1.002),(.16,.51,.026),'Gold',.004)
# Heavier underfloor mass at left. The right bay retains its open hanging cables.
box('Underfloor left shadow enclosure',(-8.62,-2.38,-.68),(9.04,2.97,2.48),'DeepNavy',.055)
box('Underfloor middle machine enclosure',(-2.33,-2.02,-.89),(3.85,1.76,2.18),'Ink',.035)
for x,w in [(-11.59,1.91),(-8.99,2.31),(-6.39,2.18)]:
    box('Underfloor large service cabinet '+str(x),(x,-2.44,.645),(w,2.25,.28),'FrameNavy',.044)
    box('Underfloor cabinet inset '+str(x),(x-.07,-2.40,.812),(w-.43,1.77,.09),'DeepNavy',.022)
    box('Underfloor cabinet light side '+str(x),(x-w*.44,-2.47,.844),(.08,2.13,.06),'Cobalt',.012)
    box('Underfloor cabinet hinge '+str(x),(x+w*.40,-2.35,.869),(.13,.34,.10),'Cobalt',.015)
# Uneven grouped vertical vent bars produce texture in deep shadow without noise.
for i,x in enumerate([-12.38,-12.13,-11.88,-7.32,-7.07,-6.82]):
    box('Underfloor cabinet vent '+str(i),(x,-2.76,.889),(.09,1.06,.065),'Ink',.009)
box('Underfloor warm service junction',(-11.03,-3.38,.91),(1.12,.48,.31),'Ochre',.025)
box('Underfloor copper distribution pipe',(-8.11,-3.55,1.07),(6.93,.14,.20),'BurntGold',.015)
box('Underfloor status light housing',(5.81,-1.56,2.36),(.46,.23,.28),'Ink',.025)
box('Underfloor warm status slot',(5.81,-1.56,2.52),(.30,.084,.024),'WarmGlow',.006)

# ---------------------------------------------------------------------------
# Reproducible export: preserve named editable source objects; exported meshes merge
# evaluated bevel geometry by material. No hundreds of runtime nodes.
source_collections=[c for c in scene.collection.children]
export_col=bpy.data.collections.new('EXPORT | shop merged palette');scene.collection.children.link(export_col)
deps=bpy.context.evaluated_depsgraph_get();merged=[]
for key,mat in M.items():
    verts=[];faces=[];offset=0
    for o in objects:
        if not o.data.materials or o.data.materials[0]!=mat:continue
        eo=o.evaluated_get(deps);me=eo.to_mesh();mw=o.matrix_world
        verts.extend(tuple(mw@v.co) for v in me.vertices)
        faces.extend(tuple(offset+i for i in poly.vertices) for poly in me.polygons);offset+=len(me.vertices);eo.to_mesh_clear()
    if not verts:continue
    me=bpy.data.meshes.new('V4_Shop_'+key);me.from_pydata(verts,[],faces);me.materials.append(mat);me.update()
    ob=bpy.data.objects.new('V4_Shop_'+key,me);export_col.objects.link(ob);merged.append(ob)
bpy.ops.object.select_all(action='DESELECT')
for ob in merged:ob.select_set(True)
bpy.context.view_layer.objects.active=merged[0]
bpy.ops.export_scene.gltf(filepath=str(OUT/'shop_cutaway.glb'),export_format='GLB',use_selection=True,export_apply=True,export_animations=False,export_lights=False,export_cameras=False,export_yup=True)
for ob in merged:ob.hide_render=True;ob.hide_set(True)
# Camera / lighting for visual study. Final approval belongs to actual Godot.
group('PROOF | camera and lighting')
def area(name,pos,target,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    o=bpy.data.objects.new(name,data);CURRENT.objects.link(o);o.location=p(pos);o.rotation_euler=(p(target)-o.location).to_track_quat('-Z','Y').to_euler()
    return o
area('Warm sunlit bay key',(10,13,12),(-2,2,-2),2800,6.0,(1.0,.83,.56))
area('Cobalt reflected sky',(-7,6,6),(-4,2,-2),700,8.0,(.48,.65,1))
area('Warm counter practical',(-8.3,6.8,-.5),(-8.3,1,-1),210,5.0,(1,.57,.23))
area('Warm assembly practical',(.8,6.3,-1.5),(.8,1,-1),130,5.0,(1,.72,.36))
sun=bpy.data.lights.new('Directional warm orbital sun','SUN');sun.energy=2.3;sun.angle=math.radians(2.0);sun.color=(1,.91,.73)
so=bpy.data.objects.new('Directional warm orbital sun',sun);CURRENT.objects.link(so);so.rotation_euler=(p((-7,-10,-6))).to_track_quat('-Z','Y').to_euler()
camdata=bpy.data.cameras.new('Composition camera');cam=bpy.data.objects.new('Composition camera',camdata);CURRENT.objects.link(cam)
cam.location=p((0.1,6.7,35));target=p((.1,3.0,0));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=30.1;camdata.lens=50;scene.camera=cam
world=bpy.data.worlds.new('Orbital ambient') if not bpy.data.worlds else bpy.data.worlds[0];scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.23,.50,.67,1);world.node_tree.nodes['Background'].inputs[1].default_value=.45
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=False;scene.render.resolution_x=1920;scene.render.resolution_y=1080;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast';scene.view_settings.exposure=0;scene.view_settings.gamma=1
scene.render.image_settings.color_mode='RGBA';scene.render.filepath=str(SRC/'shop_composition_study.png')
# Set source object viewport color/material previews for editability.
for screenarea in bpy.context.screen.areas if bpy.context.screen else []:
    if screenarea.type=='VIEW_3D':screenarea.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'shop_editable.blend'))
manifest={'stage':'rebuilt from approved 4K-upscaled reference; actual Godot visual review pending','source':'new procedural geometry only; no previous environment or raster backdrop imported','coordinate_system':'Godot X right, Y up, Z toward camera; GLB roots identity','floor_y':0,'back_wall_z':-3.25,'front_edge_z':2.8,'ceiling_y':8.5,'assembly_clear_region':{'x':[-3,5],'y':[1,5],'z':[-1.3,2]},'main_platform_top_y':.46,'clerk_suggested_position':[-7.8,.25,-.3],'counter_top_y':1.3,'shop_export_meshes':len(merged),'shop_source_objects':len(objects),'shop_triangles':sum(sum(len(f.vertices)-2 for f in ob.data.polygons) for ob in merged),'materials':{k:{'name':m.name,'srgb_hex':palette[k],'emissive':k in ['WarmGlow','CyanGlow']} for k,m in M.items()}}
(SRC/'shop_manifest.json').write_text(json.dumps(manifest,indent=2))
if '--no-render' not in sys.argv:bpy.ops.render.render(write_still=True)
print('V4_SHOP_RESULT',json.dumps(manifest))
