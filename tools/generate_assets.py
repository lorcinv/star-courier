"""Original Star Courier meshes. Blender 4.3. All geometry authored procedurally.
Blender: X forward, Z up, -Y front. glTF: X forward, Y up, Z front.
Run: blender --background --python tools/generate_assets.py
"""
import bpy, math, os, json
from mathutils import Vector
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT=os.path.join(ROOT,'assets','models'); os.makedirs(OUT,exist_ok=True)
PRE=os.path.join(ROOT,'assets','previews'); os.makedirs(PRE,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
COLORS={'ink':(0.023,0.041,0.09),'navy':(.07,.14,.24),'metal':(.18,.27,.37),'cream':(.88,.87,.72),'white':(.96,.97,.91),'orange':(1,.30,.065),'yellow':(1,.70,.12),'cyan':(.09,.80,.87),'glass':(.12,.43,.59),'pink':(.96,.19,.37),'green':(.32,.82,.50),'purple':(.43,.26,.66)}
MAT={}
for name,c in COLORS.items():
 m=bpy.data.materials.new('SC_'+name); m.diffuse_color=(*c,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*c,1); p.inputs['Roughness'].default_value=.82
 if name in ['cyan','yellow']: p.inputs['Emission Color'].default_value=(*c,1); p.inputs['Emission Strength'].default_value=.18
 MAT[name]=m
assets=[]; current=[]
def setup(name):
 global current
 current=[]; return name
def finish(obj,name,mat):
 obj.name=name; obj.data.materials.append(MAT[mat]); current.append(obj); return obj
def box(name,loc,scale,mat='cream',bevel=.05):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.dimensions=scale; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('Machined corners','BEVEL'); mod.width=bevel; mod.segments=1
  bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=mod.name)
 return finish(o,name,mat)
def cylinder(name,loc,r,depth,mat='metal',axis='Y',vertices=12):
 bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,location=loc)
 o=bpy.context.object
 if axis=='Y': o.rotation_euler[0]=math.pi/2
 if axis=='X': o.rotation_euler[1]=math.pi/2
 return finish(o,name,mat)
def sphere(name,loc,scale,mat='cyan',sub=1):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc); o=bpy.context.object; o.scale=scale; return finish(o,name,mat)
def wedge(name,loc,scale,mat='cream'):
 x,y,z=scale; verts=[(-x/2,-y/2,-z/2),(-x/2,y/2,-z/2),(-x/2,-y/2,z/2),(-x/2,y/2,z/2),(x/2,-y/2,-z/2),(x/2,y/2,-z/2)]
 mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],[(0,4,5,1),(0,2,4),(1,5,3),(2,3,5,4),(0,1,3,2)]); mesh.update(); o=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(o); o.location=loc; return finish(o,name,mat)
def ring(name,loc,major,minor,mat='orange',axis='Y'):
 bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=16,minor_segments=4,location=loc); o=bpy.context.object
 if axis=='Y':o.rotation_euler[0]=math.pi/2
 if axis=='X':o.rotation_euler[1]=math.pi/2
 return finish(o,name,mat)
def label(name,text,loc,size=.18,mat='white'):
 bpy.ops.object.text_add(location=loc,rotation=(math.pi/2,0,0)); o=bpy.context.object; o.data.body=text;o.data.align_x='CENTER';o.data.size=size;o.data.extrude=.003
 bpy.ops.object.convert(target='MESH'); return finish(bpy.context.object,name,mat)
def bolts(x=.42,z=.42):
 for xx in [-x,x]:
  for zz in [-z,z]: cylinder('Rivet',(xx,-.377,zz),.033,.027,'metal',vertices=6)
def plate(color='cream'):
 box('Structural core',(0,0,0),(1.06,.6,1.06),'navy',.08);box('Front armor',(0,-.326,0),(.98,.07,.98),color,.07);bolts()
def socket(loc,name):
 bpy.ops.object.empty_add(type='PLAIN_AXES',location=loc); o=bpy.context.object;o.name='Socket_'+name;current.append(o)
def export(name, sockets=False):
 if sockets:
  for pos,n in [((.6,0,0),'Right'),((-.6,0,0),'Left'),((0,0,.6),'Top'),((0,0,-.6),'Bottom')]:socket(pos,n)
 bpy.ops.object.select_all(action='DESELECT')
 for o in current:o.select_set(True)
 bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+'.glb'),export_format='GLB',use_selection=True,export_yup=True)
 for o in current:
  if o.type=='EMPTY':o.name=name+'_'+o.name
 col=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(col)
 for o in current:
  for c in list(o.users_collection):c.objects.unlink(o)
  col.objects.link(o)
 assets.append((name,col,list(current)))
 # Hide previous objects from later preview renders, but leave export originals at origin.
 for o in current:o.hide_render=True

# Environment kits. Forward-facing signage and landing floor sit in XZ plane.
setup('landing_pad')
box('Foundation',(0,0,-.35),(5,3,.5),'navy',.13)
box('Raised platform',(0,0,-.05),(4.8,2.85,.15),'metal',.06)
for x in [-2.1,2.1]:
 box('Safety edge',(x,-.15,.05),(.18,2.7,.08),'yellow',.01)
 for y in [-1.1,1.1]: cylinder('Beacon footing',(x,y,.15),.13,.22,'navy',axis='Z');sphere('Landing beacon',(x,y,.30),(.12,.12,.1),'cyan')
for x in [-.85,.85]:box('Landing H',(x,0,.045),(.12,1.45,.04),'cream',0)
box('Landing H crossbar',(0,0,.046),(1.7,.12,.04),'cream',0)
for x in [-1.5,-.5,.5,1.5]:box('Front panel',(x,-1.52,-.33),(.7,.04,.17),'orange',.025)
export('landing_pad')
setup('cargo_crate');box('Crate',(0,0,0),(.78,.68,.72),'orange',.08)
for x in [-.28,.28]:box('Cargo strap',(x,0,0),(.08,.73,.77),'cream',.012)
box('Parcel label',(0,-.358,0),(.33,.025,.29),'navy',.012);label('Delivery arrow','>>',(0,-.376,-.047),.17,'cyan');export('cargo_crate')
setup('hangar_terminal')
box('Terminal base',(0,0,.13),(1,.8,.26),'navy',.1);box('Terminal trunk',(0,.12,.65),(.52,.48,1),'metal',.06)
box('Monitor',(0,-.12,1.15),(1.12,.36,.72),'cream',.1);box('Screen',(0,-.31,1.19),(.92,.03,.48),'navy',.04)
for i in range(3):box('Screen route',(-.18,-.333,1.32-i*.11),(.42-i*.06,.015,.03),'cyan',.005)
cylinder('Status',( .32,-.334,1.17),.073,.018,'green');label('Bay number','01',(0,-.32,.69),.17,'orange');export('hangar_terminal')
setup('hangar_arch')
for x in [-4.1,4.1]:
 box('Pillar',(x,.7,2.1),(.65,.9,4.2),'navy',.10);box('Pillar facing',(x,.20,2.3),(.43,.12,3.6),'metal',.06)
 for z in [.65,1,1.35]: box('Hazard tile',(x,-.0,z),(.47,.05,.12),'yellow',.01)
box('Top lintel',(0,.7,4.2),(8.9,.95,.7),'navy',.12);box('Illuminated fascia',(0,.19,4.17),(5.6,.06,.38),'orange',.04);label('Star Courier sign','STAR COURIER',(0,.135,4.04),.28,'cream')
for x in [-2.8,2.8]:box('Work light',(x,.05,3.96),(1,.15,.11),'cyan',.02)
export('hangar_arch')
for k in range(3):
 setup('asteroid_'+str(k));o=sphere('Faceted rock',(0,0,0),(1+k*.12,.7, .85+k*.08),['metal','purple','navy'][k],2)
 for v in o.data.vertices:
  q=1+.15*math.sin(v.co.x*17+v.co.y*11+v.co.z*23+k);v.co*=q
 for i in range(4):sphere('Mineral vein',(.6*math.cos(i*2+k),-.53,.55*math.sin(i*2+k)),(.16,.1,.12),'cyan' if k==1 else 'orange')
 export('asteroid_'+str(k))
# Cel-shaded art preview setup. Runtime supplies the quantized light shader.
def preview_and_save():
 source=os.path.join(ROOT,'assets','source');os.makedirs(source,exist_ok=True)
 open(os.path.join(source,'.gdignore'),'w').write('')
 labels=[]
 for i,(name,col,objs) in enumerate(assets):
  j=i-7;x=(j%5-2)*2.35;z=(2-j//5)*2.05
  if i<7:x=-14+(i%3)*7;z=12+(i//3)*5
  for o in objs:o.hide_render=i<7;o.location.x+=x;o.location.z+=z
  if i>=7:
   bpy.ops.object.text_add(location=(x,-.4,z-.81),rotation=(math.pi/2,0,0));o=bpy.context.object;o.name='Asset label '+name;o.data.body=name.upper();o.data.align_x='CENTER';o.data.size=.12;o.data.materials.append(MAT['cream']);labels.append(o)
 bpy.ops.object.text_add(location=(0,0,6.0),rotation=(math.pi/2,0,0));o=bpy.context.object;o.data.body='STAR COURIER  /  MODULE ATLAS';o.data.align_x='CENTER';o.data.size=.36;o.data.materials.append(MAT['cream']);labels.append(o)
 bpy.ops.object.text_add(location=(0,0,5.48),rotation=(math.pi/2,0,0));o=bpy.context.object;o.data.body='25 ORIGINAL PARTS  /  BLENDER TO GODOT  /  1.2 M GRID';o.data.align_x='CENTER';o.data.size=.15;o.data.materials.append(MAT['cyan']);labels.append(o)
 bpy.ops.object.camera_add(location=(7,-30,10));cam=bpy.context.object;direction=Vector((0,0,.5))-cam.location;cam.rotation_euler=direction.to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=13.8;bpy.context.scene.camera=cam
 bpy.ops.object.light_add(type='AREA',location=(-4,-6,10));key=bpy.context.object;key.data.energy=2500;key.data.shape='DISK';key.data.size=8
 bpy.ops.object.light_add(type='AREA',location=(7,-3,1));fill=bpy.context.object;fill.data.energy=1100;fill.data.size=7
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=96;scene.cycles.use_denoising=False;scene.render.resolution_x=1450;scene.render.resolution_y=1450;scene.render.resolution_percentage=100
 scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.025,.037,.066,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.5
 scene.view_settings.view_transform='Standard';scene.render.image_settings.file_format='PNG';scene.render.filepath=os.path.join(PRE,'asset_catalog.png')
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(source,'star_courier_assets.blend'));bpy.ops.render.render(write_still=True)
 for n,c,objs in assets:
  for o in objs:o.hide_render=True
 for o in labels:o.hide_render=True
 for i,(name,col,objs) in enumerate(assets[:7]):
  oldx=-14+(i%3)*7;oldz=12+(i//3)*5
  pos=[(-3,0),(1.1,1.2),(3.5,0),(0,0),(-4,5),(3.7,5),(5.4,2)][i]
  for o in objs:o.location.x+=pos[0]-oldx;o.location.z+=pos[1]-oldz;o.hide_render=False
 cam.location=(10,-24,12);cam.rotation_euler=(Vector((0,0,2.4))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=14.6;scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.filepath=os.path.join(PRE,'environment_kit.png');bpy.ops.render.render(write_still=True)
 manifest={'license':'Original procedural artwork created for this game. No external asset dependencies.','generator':'tools/generate_assets.py','blend_source':'assets/source/star_courier_assets.blend','units':'metres','axes':'glTF/Godot X forward, Y up, Z toward camera','part_cell_size':1.2,'socket_names':['Socket_Right','Socket_Left','Socket_Top','Socket_Bottom'],'materials':COLORS,'assets':[{'id':n,'path':'res://assets/models/'+n+'.glb'} for n,c,o in assets]}
 with open(os.path.join(OUT,'manifest.json'),'w') as f:json.dump(manifest,f,indent=2)
# Exact 25 authored modular parts, matching the supplied catalogue.
setup('cell');plate('cream')
for x in [-.24,.24]:
 cylinder('Energy cartridge',(x,-.43,0),.16,.66,'orange',axis='Z');cylinder('Terminal',(x,-.43,.35),.10,.07,'yellow',axis='Z')
box('Charge window',(0,-.61,0),(.10,.03,.42),'cyan',.02);export('cell',True)
setup('power_valve');plate('cream');cylinder('Valve housing',(0,-.47,0),.34,.21,'navy');ring('Limiter dial',(0,-.60,0),.23,.043,'orange');box('Dial pointer',(0,-.65,.16),(.045,.04,.20),'cyan',.01)
for x in [-.44,.44]:cylinder('Power coupling',(x,0,0),.16,.27,'yellow',axis='X')
export('power_valve',True)
setup('thruster')
box('Engine mount',(.20,0,0),(.65,.65,.80),'cream',.08);cylinder('Fuel core',(-.15,0,0),.28,.75,'metal',axis='X')
for x,r in [(-.25,.32),(-.46,.39),(-.57,.43)]:cylinder('Nozzle segment',(x,0,0),r,.13,'navy',axis='X')
cylinder('Exhaust aperture',(-.644,0,0),.32,.02,'orange',axis='X');cylinder('Hot core',(-.662,0,0),.22,.024,'cyan',axis='X')
box('Engine band',(.17,-.355,0),(.15,.04,.65),'orange',.015);label('Thrust arrow','>',(.31,-.386,-.10),.32,'navy');export('thruster',True)
setup('spring')
for x in [-.46,.46]:box('Spring piston',(x,0,0),(.17,.75,.75),'cream',.04)
cylinder('Piston rod',(0,0,0),.09,.83,'metal',axis='X')
# Square-section helical spring, one continuous mesh tube.
verts=[];faces=[];turns=5;steps=120
for i in range(steps+1):
 t=i/steps;ang=t*math.tau*turns;x=-.37+t*.74
 for j in range(4):
  q=j*math.pi/2;rr=.26+.044*math.cos(q);verts.append((x+.044*math.sin(q),rr*math.cos(ang),rr*math.sin(ang)))
for i in range(steps):
 for j in range(4):a=i*4+j;b=i*4+(j+1)%4;faces.append((a,b,b+4,a+4))
mesh=bpy.data.meshes.new('Helix');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('Mechanical spring',mesh);bpy.context.collection.objects.link(o);finish(o,'Mechanical spring','orange');export('spring',True)
setup('turntable');plate('metal');cylinder('Rotating hub',(0,-.42,0),.42,.17,'cream');ring('Rotation ring',(0,-.53,0),.30,.045,'orange');box('Hub bar',(0,-.57,0),(.64,.08,.13),'navy',.03);cylinder('Axle',(0,-.64,0),.09,.11,'cyan');export('turntable',True)
setup('beam')
for z in [-.42,.42]:box('Structural rail',(0,0,z),(1.15,.38,.15),'cream',.025)
for x in [-.47,0,.47]:
 o=box('Cross brace',(x,0,0),(.12,.30,.94),'orange',.015);o.rotation_euler[1]=.50 if x<=0 else -.50
for x in [-.48,.48]:
 for z in [-.42,.42]:cylinder('Rivet',(x,-.22,z),.07,.035,'navy',vertices=6)
export('beam',True)
setup('separator')
for x in [-.3,.3]:box('Split coupling',(x,0,0),(.45,.60,.91),'cream',.05);box('Separation stripe',(x,-.325,0),(.15,.045,.77),'orange',.015)
for z in [-.24,.24]:box('Release latch',(0,-.12,z),(.29,.32,.10),'yellow',.01)
box('Seam',(0,-.10,0),(.05,.18,.85),'pink',.01);export('separator',True)
setup('damper')
for x in [-.48,.48]:box('Bumper mount',(x,0,0),(.16,.65,.78),'navy',.04)
cylinder('Hydraulic cylinder',(-.18,0,0),.25,.52,'orange',axis='X');cylinder('Damper shaft',(.22,0,0),.13,.60,'cream',axis='X')
for x in [-.32,-.18,-.04]:ring('Cylinder rib',(x,0,0),.26,.035,'navy',axis='X')
export('damper',True)
setup('tachyon_lance');box('Lance base',(-.29,0,0),(.51,.68,.75),'cream',.07);cylinder('Energy barrel',(.10,0,0),.20,.77,'navy',axis='X')
for x in [-.1,.12,.34]:ring('Focus coil',(x,0,0),.25,.07,'cyan',axis='X')
cylinder('Lance tip',(.57,0,0),.15,.12,'pink',axis='X');export('tachyon_lance',True)
setup('accelerator');box('Breech',(-.35,0,0),(.40,.72,.75),'navy',.06)
for z in [-.24,.24]:box('Magnetic rail',(.12,0,z),(.95,.36,.13),'cream',.025);box('Rail conductor',(.15,-.20,z),(.87,.04,.055),'cyan',.01)
for x in [-.1,.2,.5]:box('Coil brace',(x,.16,0),(.10,.18,.65),'orange',.025)
cylinder('Loaded slug',(.0,0,0),.09,.34,'yellow',axis='X');export('accelerator',True)
setup('arc_emitter');plate('purple')
for z in [-.28,.28]:
 cylinder('Insulator',(.1,0,z),.11,.70,'cream',axis='X');sphere('Electrode',(.49,0,z),(.15,.15,.15),'cyan',2)
box('Arc transformer',(-.15,-.43,0),(.34,.22,.42),'navy',.04);export('arc_emitter',True)
setup('explosive_core');plate('navy');sphere('Volatile core',(0,-.43,0),(.36,.23,.36),'pink',2);ring('Containment',(0,-.49,0),.35,.07,'orange')
for a in range(3):
 o=box('Blast warning',(math.cos(a*math.tau/3)*.16,-.71,math.sin(a*math.tau/3)*.16),(.12,.03,.10),'yellow',.01);o.rotation_euler[1]=-a*math.tau/3
export('explosive_core',True)
setup('armor');box('Armor structure',(0,0,0),(1.12,.45,1.10),'navy',.09);box('Outer armor',(0,-.28,0),(1.12,.23,1.08),'cream',.13);box('Armor stripe',(0,-.405,0),(.20,.025,.83),'orange',.015);bolts(.39,.37);export('armor',True)
setup('shield');plate('cream');cylinder('Shield projector',(0,-.44,0),.34,.15,'navy');sphere('Shield crystal',(0,-.55,0),(.24,.18,.28),'cyan',2)
for a in range(6):sphere('Emitter',(.39*math.cos(a*math.pi/3),-.44,.39*math.sin(a*math.pi/3)),(.06,.04,.06),'cyan')
export('shield',True)
setup('decoy');plate('orange');cylinder('Beacon pedestal',(0,-.44,-.10),.22,.17,'navy');cylinder('Signal mast',(0,0,.28),.045,.62,'cream',axis='Z');sphere('Beacon light',(0,0,.59),(.15,.15,.15),'pink',2);ring('Signal antenna',(0,-.42,.1),.31,.035,'cream');export('decoy',True)
for name,color,marks in [('shrink_ring','cyan',-1),('enlarge_ring','pink',1)]:
 setup(name);ring('Space gate',(0,0,0),.40,.13,'navy');ring('Active rim',(0,-.12,0),.40,.042,color)
 for a in range(4):
  xx=.40*math.cos(a*math.pi/2);zz=.40*math.sin(a*math.pi/2);box('Field coil',(xx,0,zz),(.20,.45,.20),'cream',.035)
 label('Space glyph','-' if marks<0 else '+',(0,-.23,-.13),.42,color);export(name,True)
setup('displacer');plate('purple')
for x in [-.28,.28]:sphere('Phase crystal',(x,-.49,0),(.15,.13,.36),'cyan',1)
label('Phase direction','>>',(0,-.67,-.07),.23,'white');export('displacer',True)
setup('splitter');plate('navy')
for x,z in [(-.23,.22),(.23,.22),(0,-.23)]:sphere('Split nucleus',(x,-.47,z),(.21,.15,.21),'orange',1)
ring('Conservation ring',(0,-.49,0),.36,.035,'cyan');export('splitter',True)
setup('distance_probe');plate('cream');cylinder('Sensor trunk',(.27,0,0),.17,.55,'metal',axis='X');cylinder('Sensor face',(.57,0,0),.26,.10,'navy',axis='X');sphere('Range lens',(.64,0,0),(.06,.18,.18),'cyan',2)
box('Display',(-.1,-.39,0),(.48,.09,.45),'navy',.035);label('Range label',')))',(-.09,-.45,-.065),.23,'cyan');export('distance_probe',True)
setup('collision_switch');plate('yellow');box('Pressure bumper',(.46,0,0),(.22,.76,.90),'pink',.08);cylinder('Contact switch',(-.10,-.44,0),.24,.15,'navy');cylinder('Indicator',(-.10,-.54,0),.14,.08,'green');export('collision_switch',True)
setup('delay');plate('cream');cylinder('Timer face',(0,-.43,0),.35,.15,'navy');ring('Timer bezel',(0,-.54,0),.32,.035,'orange');box('Timer hand',(0,-.57,.12),(.035,.025,.26),'cyan',.01);box('Timer short hand',(.095,-.57,0),(.20,.025,.035),'cream',.01);export('delay',True)
for name,glyph,color in [('and_gate','&','cyan'),('or_gate','OR','yellow'),('not_gate','!','pink')]:
 setup(name);plate('navy');box('Logic chip',(0,-.43,0),(.66,.15,.64),'cream',.06);box('Chip inset',(0,-.52,0),(.49,.04,.48),'navy',.03);label('Logic glyph',glyph,(0,-.551,-.13),.32,color)
 for z in [-.22,.22]:cylinder('Input signal',(-.53,0,z),.085,.16,'cyan',axis='X')
 cylinder('Output signal',(.53,0,0),.10,.16,color,axis='X');export(name,True)

preview_and_save()
