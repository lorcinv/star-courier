"""STAR COURIER / CITY V4 — fresh modeled orbital city study.
Rebuild: blender --background --python source_art/environment_v4/city_build.py
All design coordinates are Godot X horizontal / Y up / Z toward viewer.
No prior assets or image textures are read. Meshes are grouped by material.
"""
import bpy, math, random, json, os, sys
from mathutils import Vector
from collections import defaultdict
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/environment_v4'
SRC=ROOT/'source_art/environment_v4'
random.seed(48171)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for datablocks in [bpy.data.meshes,bpy.data.materials,bpy.data.cameras,bpy.data.lights]:
    for item in list(datablocks): datablocks.remove(item)

PALETTE={
 'V4_CityFarHaze':'a7dcec', 'V4_CityFarLight':'d7edf0',
 'V4_CityMidBlue':'92c8e1', 'V4_CityMidShade':'79b4d4',
 'V4_CityNearCerulean':'71b3d4', 'V4_CityNearShade':'5b9dc6',
 'V4_CityTrimIce':'c4e8ee', 'V4_CityWindowMint':'89e2e2',
 'V4_CityDeckBlue':'98cce1', 'V4_CityDeckShade':'78b4d3',
 'V4_CityTrafficGold':'ffd477', 'V4_CityTrafficInk':'4669a0',
 'V4_SkyCyan':'72d4f0', 'V4_SkyCloudIvory':'fff8de',
 'V4_SkyCloudCream':'f5e6cf', 'V4_SkyCloudShade':'e1d7d4',
}

def srgb_linear(v): return v/12.92 if v<0.04045 else ((v+0.055)/1.055)**2.4
MATS={}
for name,h in PALETTE.items():
    rgb=tuple(int(h[i:i+2],16)/255 for i in (0,2,4))
    m=bpy.data.materials.new(name); m.use_nodes=True
    m.diffuse_color=(*[srgb_linear(c) for c in rgb],1)
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=m.diffuse_color
    p.inputs['Roughness'].default_value=.9
    # Material-only glTF: faceted mesh lighting is handled by the runtime cel shader.
    MATS[name]=m

class Builder:
    def __init__(self,name):
        self.name=name; self.parts=defaultdict(lambda:[[],[]]); self.components=[]
    def face(self,mat,verts):
        v,f=self.parts[mat]; start=len(v); v.extend(verts); f.append(tuple(range(start,start+len(verts))))
    def poly(self,mat,verts,faces):
        for f in faces: self.face(mat,[verts[i] for i in f])
    def box(self,name,p,s,mat,side=None,top=None):
        x,y,z=p; a,b,c=(v*.5 for v in s)
        v=[(x-a,y-b,z-c),(x+a,y-b,z-c),(x+a,y+b,z-c),(x-a,y+b,z-c),
           (x-a,y-b,z+c),(x+a,y-b,z+c),(x+a,y+b,z+c),(x-a,y+b,z+c)]
        self.face(mat,[v[i] for i in (4,5,6,7)])
        self.face(side or mat,[v[i] for i in (1,0,3,2)])
        for f in ((0,4,7,3),(5,1,2,6),(0,1,5,4)): self.face(side or mat,[v[i] for i in f])
        self.face(top or mat,[v[i] for i in (7,6,2,3)])
        self.components.append({'name':name,'center':list(p)})
    def prism(self,name,c,levels,mat,side=None,n=8,phase=math.pi/8):
        # levels = (height, radius_x, radius_z), local height relative to center.y
        rings=[]
        for h,rx,rz in levels:
            rings.append([(c[0]+rx*math.cos(phase+2*math.pi*j/n),c[1]+h,c[2]+rz*math.sin(phase+2*math.pi*j/n)) for j in range(n)])
        self.face(side or mat,rings[0])
        self.face(mat,list(reversed(rings[-1])))
        for k in range(len(rings)-1):
            for j in range(n):
                face=[rings[k][j],rings[k][(j+1)%n],rings[k+1][(j+1)%n],rings[k+1][j]]
                front=(math.sin(phase+2*math.pi*(j+.5)/n)>-.15)
                self.face(mat if front else side or mat,list(reversed(face)))
        self.components.append({'name':name,'center':list(c)})
    def beam(self,name,a,b,r,mat,n=6):
        d=Vector(b)-Vector(a); axis=d.normalized(); t=axis.cross(Vector((0,0,1)))
        if t.length<.01:t=axis.cross(Vector((1,0,0)))
        t.normalize(); q=axis.cross(t).normalized()
        rings=[]
        for c in (Vector(a),Vector(b)):
            rings.append([tuple(c+r*(math.cos(i*math.tau/n)*t+math.sin(i*math.tau/n)*q)) for i in range(n)])
        self.face(mat,list(reversed(rings[0])));self.face(mat,rings[1])
        for i in range(n):self.face(mat,[rings[0][i],rings[0][(i+1)%n],rings[1][(i+1)%n],rings[1][i]])
    def ellipsoid(self,name,p,s,mat,lower=None,seed=1):
        rng=random.Random(seed); n=16; rings=[]
        # Deliberately low resolution. Irregular longitude offset avoids latitude-band clouds.
        for k in range(1,8):
            phi=-math.pi/2+math.pi*k/8
            phase=.13*(k%2)
            rings.append([(p[0]+s[0]*math.cos(phi)*math.cos(phase+j*math.tau/n),p[1]+s[1]*math.sin(phi),p[2]+s[2]*math.cos(phi)*math.sin(phase+j*math.tau/n)) for j in range(n)])
        bottom=(p[0],p[1]-s[1],p[2]);top=(p[0],p[1]+s[1],p[2])
        for j in range(n):
            self.face(lower or mat,[bottom,rings[0][j],rings[0][(j+1)%n]])
            self.face(mat,[top,rings[-1][(j+1)%n],rings[-1][j]])
        for k in range(6):
            for j in range(n):
                self.face(lower if k==0 and lower else mat,[rings[k+1][j],rings[k+1][(j+1)%n],rings[k][(j+1)%n],rings[k][j]])
        self.components.append({'name':name,'center':list(p)})
    def track(self,name,points,width=.95,thick=.25,posts=True):
        # Swept physical viaduct in X/Z, with a smoothly changing grade in Y.
        edges=[]
        for i,p in enumerate(points):
            a=Vector(points[max(0,i-1)]);b=Vector(points[min(len(points)-1,i+1)])
            tangent=b-a;right=Vector((-tangent.z,0,tangent.x)).normalized()
            edges.append([tuple(Vector(p)+right*width*.5),tuple(Vector(p)-right*width*.5)])
        for i in range(len(points)-1):
            a,b=edges[i];c,d=edges[i+1]
            self.face('V4_CityDeckBlue',[a,c,d,b])
            ab=[(p[0],p[1]-thick,p[2]) for p in (a,b,c,d)]
            self.face('V4_CityDeckShade',[a,ab[0],ab[2],c]);self.face('V4_CityDeckShade',[b,d,ab[3],ab[1]])
            self.face('V4_CityDeckShade',[ab[0],ab[1],ab[3],ab[2]])
            # Solid low parapets, as thick readable ribbons.
            for j in (0,1):
                aa=edges[i][j];bb=edges[i+1][j]
                self.beam(name+' / ice parapet',tuple(Vector(aa)+Vector((0,.10,0))),tuple(Vector(bb)+Vector((0,.10,0))),.055,'V4_CityTrimIce',4)
            if i%3==0:
                # Transverse expansion joints; sparse, subdued.
                self.beam(name+' / joint',tuple(Vector(a)+Vector((0,.012,0))),tuple(Vector(b)+Vector((0,.012,0))),.012,'V4_CityDeckShade',4)
        if posts:
            for i in range(3,len(points)-3,8):
                x,y,z=points[i];bottom=-24
                self.prism(name+' / pier', (x,0,z),[(bottom,.31,.34),(y-1.4,.20,.25),(y-.35,.48,.38)],'V4_CityMidBlue','V4_CityMidShade',6)
                # Forked column capitals are visible from the shop without cluttering the sky.
                for dx in [-.5,.5]:self.beam(name+' / fork',(x,y-1.5,z),(x+dx,y-.24,z),.12,'V4_CityTrimIce',4)
        self.components.append({'name':name,'points':len(points)})
    def create(self):
        col=bpy.data.collections.new(self.name);bpy.context.scene.collection.children.link(col)
        objects=[]
        for mat,(verts,faces) in self.parts.items():
            # Godot-to-Blender is a proper rotation; export restores (x,y,z).
            mesh=bpy.data.meshes.new(self.name+'__'+mat)
            mesh.from_pydata([(x,-z,y) for x,y,z in verts],[],faces);mesh.materials.append(MATS[mat]);mesh.update()
            import bmesh
            bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.remove_doubles(bm,verts=bm.verts,dist=0.000001);bm.to_mesh(mesh);bm.free()
            ob=bpy.data.objects.new(mat,mesh);col.objects.link(ob);objects.append(ob)
        col['design_coordinate_system']='Godot X right / Y up / Z toward camera'
        col['component_count']=len(self.components)
        return col,objects

FAR=('V4_CityFarHaze','V4_CityFarHaze','V4_CityFarLight')
MID=('V4_CityMidBlue','V4_CityMidShade','V4_CityTrimIce')
NEAR=('V4_CityNearCerulean','V4_CityNearShade','V4_CityTrimIce')

def windows(b,name,x,base,z,w,h,mat,rows=5,cols=2):
    # Window fins read as large graphic strokes, not hundreds of tiny squares.
    for c in range(cols):
        xx=x+(c-(cols-1)*.5)*w*.31
        for r in range(rows):
            yy=base+.65+(h-1.0)*(r+.35)/rows
            b.box(name+' / light strip',(xx,yy,z),(.065,min(.65,h/rows*.6),.035),mat)

def crown_spire(b,name,x,z,base,h,w,pal=MID):
    front,side,trim=pal
    b.prism(name+' / tapered plinth',(x,base,z),[(0,w*.9,w*.58),(.7,w*.75,w*.55),(1.0,w*.64,w*.5)],front,side)
    b.prism(name+' / main fluted shaft',(x,base,z),[(.7,w*.63,w*.49),(h*.65,w*.52,w*.40),(h*.72,w*.43,w*.34)],front,side)
    b.prism(name+' / upper tier',(x,base,z),[(h*.68,w*.46,w*.37),(h*.86,w*.32,w*.27),(h*.9,w*.21,w*.21)],front,side)
    for f in [-1,1]:
        b.box(name+' / vertical side fin',(x+f*w*.49,base+h*.38,z+.12),(w*.13,h*.60,w*.54),trim,front,trim)
        b.box(name+' / floating shoulder',(x+f*w*.59,base+h*.59,z),(w*.20,.23,w*.77),trim,side,trim)
    for factor,scale in [(.3,.7),(.62,.62),(.73,.47),(.89,.25)]:
        b.prism(name+' / belt',(x,base,z),[(h*factor,w*scale,w*scale*.76),(h*factor+.17,w*scale,w*scale*.76)],trim,front)
    b.prism(name+' / crown needle',(x,base,z),[(h*.88,w*.14,w*.14),(h*.96,w*.075,w*.075),(h,.018,.018)],trim,front,6)
    windows(b,name,x,base+1.2,z+w*.49+.024,w,h*.55,trim,5,2)

def step_tower(b,name,x,z,base,h,w,pal=MID):
    front,side,trim=pal
    for i,(frac,width) in enumerate([(0,1),(.39,.78),(.7,.56),(.89,.30)]):
        nextf=[.43,.75,.92,1][i]
        b.box(name+' / setback '+str(i),(x+(.09*w if i%2 else -.05*w),base+h*(frac+nextf)*.5,z),(w*width,h*(nextf-frac),w*.66*width),front,side,trim)
        b.box(name+' / cornice '+str(i),(x,base+h*nextf,z),(w*width+.10,.14,w*.66*width+.1),trim,front,trim)
    for f in [-1,1]:b.box(name+' / flank blade',(x+f*w*.41,base+h*.27,z+.14),(w*.085,h*.5,w*.48),side)
    windows(b,name,x,base,z+w*.34+.022,w,h*.38,trim,3,2)
    b.box(name+' / roof antenna',(x-w*.07,base+h+.45,z),(.045,.9,.045),trim)

def split_tower(b,name,x,z,base,h,w,pal=NEAR):
    front,side,trim=pal
    b.box(name+' / podium',(x,base+h*.16,z),(w*1.25,h*.32,w*.77),front,side,trim)
    for f in [-1,1]:
        xx=x+f*w*.37;hh=h*(.92 if f==1 else 1)
        b.box(name+' / pylon',(xx,base+hh*.52,z),(w*.29,hh*.91,w*.50),front,side,trim)
        b.box(name+' / fin',(xx+f*w*.10,base+hh*.64,z+.25*w),(.065,hh*.70,.06),trim)
        b.prism(name+' / antenna',(xx,base+hh,z),[(0,.08,.08),(.8,.02,.02)],trim,front,4)
    for t in [.37,.57,.76]:
        b.box(name+' / skybridge',(x,base+h*t,z),(w*.9,.26,w*.56),trim,front,trim)
    b.box(name+' / dark lift shaft',(x,base+h*.4,z-.12),(w*.13,h*.56,w*.34),side)

def observatory(b,name,x,z,base,h,w,pal=MID):
    front,side,trim=pal
    b.prism(name+' / column',(x,base,z),[(0,w*.39,w*.39),(h*.78,w*.22,w*.22)],front,side,8)
    b.prism(name+' / lower saucer',(x,base,z),[(h*.66,w*.28,w*.28),(h*.70,w*.98,w*.69),(h*.75,w*1.07,w*.73),(h*.78,w*.96,w*.67)],front,side,12)
    b.prism(name+' / ivory rim',(x,base,z),[(h*.77,w*.99,w*.68),(h*.80,w*.99,w*.68)],trim,front,12)
    b.prism(name+' / glass gallery',(x,base,z),[(h*.80,w*.77,w*.54),(h*.84,w*.67,w*.49)],side,side,12)
    b.prism(name+' / upper roof',(x,base,z),[(h*.84,w*.8,w*.57),(h*.89,w*.36,w*.27)],trim,front,12)
    b.prism(name+' / antenna',(x,base,z),[(h*.89,.07,.07),(h,.015,.015)],trim,front,6)

def courier(b,name,x,y,z,s=1,direction=1):
    # A wholly original compact cargo-skiff silhouette with swept wing and split tail.
    pts=[(-1.0,-.06,-.08),(-.6,-.17,.23),(.64,-.15,.25),(1.0,.04,.10),(.65,.20,.05),(-.62,.19,-.03)]
    # Extruded polygon seen in X/Y, with half-depth .19.
    aa=[(x+direction*s*a,y+s*c,z+s*(d-.13)) for a,c,d in pts]
    bb=[(a,c,d+s*.26) for a,c,d in aa]
    b.face('V4_CityTrafficGold',bb);b.face('V4_CityTrafficInk',list(reversed(aa)))
    for i in range(len(aa)):b.face('V4_CityTrafficInk',[aa[i],aa[(i+1)%len(aa)],bb[(i+1)%len(aa)],bb[i]])
    b.box(name+' / cockpit',(x+s*.23*direction,y+s*.19,z+s*.27),(.58*s,.17*s,.19*s),'V4_CityTrafficInk')
    b.box(name+' / window',(x+s*.23*direction,y+s*.21,z+s*.38),(.41*s,.09*s,.018*s),'V4_CityWindowMint')
    b.box(name+' / swept wing',(x-s*.2*direction,y-s*.07,z),(.62*s,.075*s,1.08*s),'V4_CityTrafficGold')
    for f in [-1,1]:b.box(name+' / tail stabilizer',(x-s*.70*direction,y+s*.23,z+f*s*.17),(.15*s,.38*s,.075*s),'V4_CityTrafficGold')
    b.box(name+' / quiet contrail',(x-s*1.42*direction,y-s*.03,z),(.60*s,.045*s,.045*s),'V4_CityTrimIce')

def bezier(p0,p1,p2,p3,n=48):
    return [tuple((1-t)**3*p0[j]+3*(1-t)**2*t*p1[j]+3*(1-t)*t*t*p2[j]+t**3*p3[j] for j in range(3)) for t in [i/n for i in range(n+1)]]

orb=Builder('Orbital_City_V4')
# Farthest silhouette band: measured clusters, broad quiet gaps between neighborhoods.
for i,(x,h,w) in enumerate([(-31,10,1.0),(-27,15,1.3),(-24,8,1.6),(-20,13,1.2),(-16,18,.9),(-12,11,1.7),(-8,14,1.1),(-4,9,1.6),(0,13,1.0),(3,10,1.5),(6,16,1.15),(10,14,1.2),(14,17,.85),(18,13,1.45),(22,18,1.1),(26,12,1.5),(30,16,1.1)]):
    step_tower(orb,'far district %02d'%i,x,-23.5,-22,h,w,FAR)
# Dense secondary neighborhoods: clustered roof lines and uneven gaps, no window noise.
for ci,cx in enumerate([-28,-19,-10,0,10.5,20,29]):
    roof_heights=([20,23,18,21,19] if ci!=4 else [23,25,21,24,20])
    for j,(dx,h) in enumerate(zip([-2.0,-1.15,-.2,.8,1.85],roof_heights)):
        x=cx+dx;w=[.71,.58,.84,.67,.76][j];z=-23.8+(j%2)*.36
        front,side,trim=FAR
        orb.box('cluster %d %d lower'%(ci,j),(x,-22+h*.36,z),(w,h*.72,w*.74),front,side,trim)
        orb.box('cluster %d %d crown'%(ci,j),(x+w*.06,-22+h*.845,z),(w*.65,h*.25,w*.57),front,side,trim)
        if j in [1,3]:orb.box('cluster %d %d roof fin'%(ci,j),(x-w*.17,-22+h+.35,z),(.07,.9,.07),trim)
        orb.box('cluster %d %d shoulder'%(ci,j),(x,-22+h*.71,z),(w+.11,.13,w*.78),trim)
# Specific near/middle landmark silhouettes, all physically behind the storefront.
step_tower(orb,'west postal terraces',-26,-17,-22,20,2.6,MID)
crown_spire(orb,'west orbital beacon',-20,-18,-23,28,1.5,MID)
split_tower(orb,'canal gate',-13,-15,-21,20,2.0,MID)
observatory(orb,'west exchange observatory',-6,-19,-23,20,2.0,MID)
step_tower(orb,'central ribbon offices',0,-16.5,-23,20,2.7,MID)
crown_spire(orb,'bay navigation spire',10.1,-19,-23,31,1.25,MID)
split_tower(orb,'east twin orbital gate',4.0,-15.2,-22,26,1.7,NEAR)
observatory(orb,'east skyport',16,-17,-23,28,2.1,MID)
crown_spire(orb,'distant high crown',20,-21,-24,36,1.05,MID)
step_tower(orb,'lower right city terraces',19,-10.8,-25,17,2.3,NEAR)
step_tower(orb,'lower left cargo district',-18,-11.5,-25,15,3.0,NEAR)
crown_spire(orb,'underfloor blue needle',-3.8,-12.5,-25,17,1.3,NEAR)
split_tower(orb,'underfloor twin shafts',5.0,-14,-25,18,1.9,MID)
# Layered viaducts. Sweeps are fully modeled solid decks with low parapets.
orb.track('orbital upper ring',bezier((-80,4.5,-20),(-4,5.6,-24),(11,11,-22),(35,10,-15),56),1.35,.32,True)
orb.track('east cloudway',bezier((-80,-7,-18),(0,3,-16),(33,0,-12),(17,-14,-18),76),1.30,.35,True)
orb.track('lower horizon connector',bezier((-80,-16,-19),(-14,-10,-20),(6,-10.5,-23),(33,-14,-15),52),1.0,.26,True)
# Small background courier traffic sits safely behind the shop.
courier(orb,'amber commuter',20,4.7,-11.8,.60,-1)
courier(orb,'high postal shuttle',11.8,8.5,-16.4,.37,1)
courier(orb,'lower freight skiff',8.7,-9.2,-10.0,.44,1)
courier(orb,'far tiny delivery',-5.5,-5.3,-18,.32,-1)

flight=Builder('Flight_City_V4')
# A larger lateral district supporting camera parallax without repeated wallpaper geometry.
for i in range(38):
    x=-64+i*3.65;h=random.uniform(10,25);w=random.uniform(.8,1.7)
    step_tower(flight,'flight far district %02d'%i,x,-28-random.uniform(0,5),-29,h,w,FAR)
for ci,cx in enumerate([-57,-44,-29,-17,-4,10,22,37,50,65,76]):
    for j,dx in enumerate([-2.1,-.8,.4,1.65]):
        h=[21,26,23,19][(j+ci)%4];w=[.9,.7,1.0,.85][j]
        flight.box('flight clustered roofline %d %d'%(ci,j),(cx+dx,-29+h*.45,-26-(j%2)),(w,h*.9,w*.67),'V4_CityFarHaze','V4_CityFarHaze','V4_CityFarLight')
        flight.box('flight clustered crown %d %d'%(ci,j),(cx+dx,-29+h*.955,-26-(j%2)),(w*.59,h*.16,w*.46),'V4_CityFarHaze','V4_CityFarHaze','V4_CityFarLight')
for i,x in enumerate([-59,-50,-41,-30,-20,-10,-1,12,24,36,47,59,69]):
    h=[28,22,35,26,31,24,30,36,27,31,25,34,30][i];z=-18-(i%3)*3;w=1.6+(i%4)*.35
    [crown_spire,step_tower,split_tower,observatory][i%4](flight,'flight landmark %02d'%i,x,z,-28,h,w,MID if i%3 else NEAR)
for i,x in enumerate([-48,-30,-12,7,26,45,65]):
    step_tower(flight,'flight lower terraces %02d'%i,x,-12-(i%2),-31,15+(i%3)*2,3.0,NEAR)
flight.track('flight sweeping arc',bezier((-75,-11,-16),(-25,2,-20),(20,-5,-11),(85,-10,-23),110),1.65,.38,True)
flight.track('flight upper distant ring',bezier((-75,7,-29),(-18,11,-31),(35,10,-25),(84,15,-29),110),1.40,.30,True)
flight.track('flight bottom connector',bezier((-70,-23,-14),(-20,-15,-16),(35,-17,-21),(84,-16,-13),100),1.25,.30,True)
for i,(x,y,z,s,d) in enumerate([(-35,3,-13,.7,1),(-13,10,-20,.45,-1),(17,4,-12,.62,1),(39,-4,-15,.48,-1),(63,8,-21,.55,1)]):
    courier(flight,'flight distant courier %02d'%i,x,y,z,s,d)

sky=Builder('Sky_Backdrop_V4')
sky.box('enormous volumetric cyan sky',(0,7,-55),(220,130,4),'V4_SkyCyan')
# Purposeful cloud groups: warm open-edged islands, generous clean cyan negative space.
def cloud_cluster(name,x,y,z,s,seed):
    rng=random.Random(seed)
    forms=[(-1.55,-.26,.05,1.48,.48,.7),(-.63,.05,.08,1.05,.84,.76),(.22,.14,-.10,1.15,1.12,.83),(1.12,-.08,.05,1.12,.70,.72),(1.86,-.28,0,.8,.40,.59)]
    for i,(dx,dy,dz,rx,ry,rz) in enumerate(forms):
        sky.ellipsoid(name+' / tuft '+str(i),(x+dx*s,y+dy*s,z+dz*s),(rx*s,ry*s,rz*s),'V4_SkyCloudIvory','V4_SkyCloudCream',seed+i)
    # A broad shallow shaded base unifies the separate convex tufts into one cloud bank.
    sky.ellipsoid(name+' / unified shaded underside',(x,y-.40*s,z-.20*s),(2.75*s,.27*s,.72*s),'V4_SkyCloudCream','V4_SkyCloudShade',seed)

for args in [('east bay cream cumulus',17,0,-32,2.9,10),('right high cloud',34,13,-37,2.7,20),('upper left island',-21,13,-35,3.1,30),('lower east cloud sea',18,-8,-30,3.2,40),('lower central cloud sea',-4,-9,-33,4.0,50),('west lower bank',-28,-7,-32,3.7,60),('bay floor cumulus',8,-4.2,-33,1.7,65),('far right district bank',62,-7,-37,4.2,70),('far left sky bank',-58,2,-38,4.0,80),('distant highest cream cloud',6,23,-42,4.3,90)]:
    cloud_cluster(*args)
for i,(x,y,z,s) in enumerate([(-4,10,-39,6),(30,21,-41,7),(-40,21,-42,9),(51,3,-38,5),(-19,-2,-39,6),(57,21,-43,9)]):
    sky.ellipsoid('quiet atmospheric wisp '+str(i),(x,y,z),(s,.26,s*.20),'V4_SkyCloudIvory','V4_SkyCloudCream',100+i)

# Composition refinement from the integrated Godot shop proof:
# orthographic distance alone cannot reduce apparent size, so bake a deliberately
# smaller XY skyline into the mesh while retaining all safe background Z values.
def distant_xy(builder,sx,sy,dx,dy,exclude=()):
    for mat,(verts,faces) in builder.parts.items():
        if mat not in exclude:builder.parts[mat][0]=[(x*sx+dx,y*sy+dy,z) for x,y,z in verts]
    for component in builder.components:
        if 'center' in component:
            x,y,z=component['center'];component['center']=[x*sx+dx,y*sy+dy,z]
distant_xy(orb,.40,.42,5.0,.20)
distant_xy(flight,.52,.45,8.0,.20)
distant_xy(sky,.68,.65,3.2,-1.0,('V4_SkyCyan',))
# Small outer neighborhoods preserve width beneath the whole storefront without
# stretching the central bay landmarks back up to foreground scale.
for ci,cx in enumerate([-26,-21,-16,-11,-6,21,27]):
    for j,dx in enumerate([-.95,0,.88]):
        h=[8.3,11.5,9.6][(j+ci)%3];w=[.58,.73,.64][j]
        step_tower(orb,'distant peripheral block %d %d'%(ci,j),cx+dx,-23.8+(j%2)*.5,-13,h,w,FAR)
collections={};objects={};builders={'orbital_city':orb,'flight_city':flight,'sky_backdrop':sky}
for name,b in builders.items():collections[name],objects[name]=b.create()

# Editable source retains logical asset collections and physically independent mesh islands.
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=False
scene.world.color=(.8,.8,.8)
world=scene.world;world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.79,.86,1,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.7
sun_data=bpy.data.lights.new('City proof / soft directional sun','SUN');sun_data.energy=2;sun_data.angle=.12
sun=bpy.data.objects.new('City proof / soft directional sun',sun_data);scene.collection.objects.link(sun);sun.rotation_euler=(math.radians(35),math.radians(-30),math.radians(-30))
cam_data=bpy.data.cameras.new('City proof / shop vista');cam=bpy.data.objects.new('City proof / shop vista',cam_data);scene.collection.objects.link(cam);scene.camera=cam
cam_data.type='ORTHO';cam_data.ortho_scale=43
# Godot camera position translated into Blender axes.
def camera_at(position,target,scale):
    cam.location=(position[0],-position[2],position[1]);t=Vector((target[0],-target[2],target[1]));cam.rotation_euler=(t-cam.location).to_track_quat('-Z','Y').to_euler();cam_data.ortho_scale=scale
camera_at((0,6,42),(0,-2,-13),43)
scene.render.resolution_x=1440;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast';scene.view_settings.exposure=0;scene.view_settings.gamma=1
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
collections['flight_city'].hide_render=True;collections['flight_city'].hide_viewport=True
scene['V4_ART_STATUS']='Fresh V4 modeled assets, approved 4K upscaled reference baseline.'
scene['Design coordinates']='Godot X horizontal / Y up / Z toward camera; export roots identity.'
scene['Palette sRGB']=json.dumps(PALETTE)
for obj in bpy.context.selected_objects:obj.select_set(False)
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'city_source.blend'))

manifest={'version':4,'status':'fresh V4 modeled assets from approved 4K upscaled reference baseline','reference':'source_art/art_direction_v4/pixel-cel-shop-reference-03-4k-upscaled.png','coordinate_system':'Godot X horizontal, Y up, Z toward camera','root_transform':'identity','fresh_geometry':True,'composition_revision':'Smaller distant skyline after integrated Godot shop proof; orbital XY scale baked .40/.42, depth retained.','image_textures':0,'source':'source_art/environment_v4/city_source.blend','generator':'source_art/environment_v4/city_build.py','palette_srgb_hex':PALETTE,'assets':{}}
for name,obs in objects.items():
    for col in collections.values():col.hide_viewport=False
    bpy.ops.object.select_all(action='DESELECT')
    for obj in obs:obj.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False,export_extras=True)
    points=[v.co for obj in obs for v in obj.data.vertices]
    bounds={'min':[round(min(p[i] for p in points),3) for i in range(3)],'max':[round(max(p[i] for p in points),3) for i in range(3)]}
    # Blender (x,y,z) → Godot (x,z,-y)
    gd_bounds={'min':[bounds['min'][0],bounds['min'][2],-bounds['max'][1]],'max':[bounds['max'][0],bounds['max'][2],-bounds['min'][1]]}
    manifest['assets'][name]={'file':'assets/environment_v4/'+name+'.glb','material_surfaces':len(obs),'mesh_nodes':len(obs),'triangles':sum(sum(max(0,len(p.vertices)-2) for p in obj.data.polygons) for obj in obs),'godot_bounds':gd_bounds,'logical_components':len(builders[name].components),'bytes':(OUT/(name+'.glb')).stat().st_size}
# Proof-only clean three-value cel material. GLBs and editable source above retain
# regular Principled materials with correct linear glTF baseColor factors.
for name,m in MATS.items():
    nodes=m.node_tree.nodes;nodes.clear();links=m.node_tree.links
    out=nodes.new('ShaderNodeOutputMaterial');emit=nodes.new('ShaderNodeEmission');links.new(emit.outputs[0],out.inputs['Surface'])
    rgb=m.diffuse_color
    if name=='V4_SkyCyan':emit.inputs[0].default_value=rgb;continue
    geo=nodes.new('ShaderNodeNewGeometry');dot=nodes.new('ShaderNodeVectorMath');dot.operation='DOT_PRODUCT';dot.inputs[1].default_value=(-.42,-.66,.75);links.new(geo.outputs['Normal'],dot.inputs[0])
    ramp=nodes.new('ShaderNodeValToRGB');ramp.color_ramp.interpolation='CONSTANT'
    factor=.89 if 'Far' in name or 'Cloud' in name else (.73 if 'Near' in name or 'Traffic' in name else .83)
    ramp.color_ramp.elements[0].position=0;ramp.color_ramp.elements[0].color=(rgb[0]*factor,rgb[1]*factor,rgb[2]*factor,1)
    ramp.color_ramp.elements[1].position=.60;ramp.color_ramp.elements[1].color=rgb
    mid=ramp.color_ramp.elements.new(.10);mid.color=(rgb[0]*(factor+1)*.5,rgb[1]*(factor+1)*.5,rgb[2]*(factor+1)*.5,1)
    links.new(dot.outputs['Value'],ramp.inputs['Fac']);links.new(ramp.outputs[0],emit.inputs[0])
scene.cycles.samples=4
scene.view_settings.look='Medium High Contrast'
for name in ['orbital_city','sky_backdrop']:collections[name].hide_render=False
collections['flight_city'].hide_render=True
scene.render.filepath=str(SRC/'city_proof_wide.png');bpy.ops.render.render(write_still=True)
camera_at((0,7.5,32),(0,3.5,0),32.5)
scene.render.resolution_x=1440;scene.render.resolution_y=810
scene.render.filepath=str(SRC/'city_proof_shop_vista.png');bpy.ops.render.render(write_still=True)
collections['orbital_city'].hide_render=True;collections['flight_city'].hide_render=False
camera_at((15,6,45),(15,-2,-15),60)
scene.render.filepath=str(SRC/'city_proof_flight.png');bpy.ops.render.render(write_still=True)
manifest['proofs']=['source_art/environment_v4/city_proof_wide.png','source_art/environment_v4/city_proof_shop_vista.png','source_art/environment_v4/city_proof_flight.png']
(SRC/'city_manifest.json').write_text(json.dumps(manifest,indent=2))
print('CITY_V4_COMPLETE '+json.dumps(manifest['assets']))
