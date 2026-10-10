"""Editable decorative maintenance lift and clerk dais. Does not alter shop/city.
blender -b --python source_art/environment_v4/create_mechanisms.py
"""
import bpy,math,json,struct,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[1];OUT=ROOT/'assets/environment_v4'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;M={};parts={};current=None
palette={'Ink':'101C34','FrameNavy':'21375A','Cobalt':'31527D','EdgeBlue':'536F91','Gold':'E8AF30','SunGold':'FFCF4F','LiftWarmMetal':'B9AF95','DaisTread':'51637B'}
def linear(c):return c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4
for key,hex in palette.items():
    m=bpy.data.materials.new('V4_'+key);m.use_nodes=True;rgba=tuple(linear(int(hex[i:i+2],16)/255) for i in [0,2,4])+(1,);m.diffuse_color=rgba
    b=m.node_tree.nodes.get('Principled BSDF');b.inputs['Base Color'].default_value=rgba;b.inputs['Roughness'].default_value=.78;M[key]=m

def p(v):return Vector((v[0],-v[2],v[1]))
def collection(name):
    c=bpy.data.collections.new(name);scene.collection.children.link(c);return c
source_col=collection('SOURCE | Maintenance lift editable pieces')
dais_col=collection('SOURCE | Clerk dais editable pieces')
export_col=collection('EXPORT | Runtime mechanisms')
def empty(name,col,parent=None,pos=(0,0,0)):
    o=bpy.data.objects.new(name,None);col.objects.link(o);o.parent=parent;o.location=p(pos);o.empty_display_type='PLAIN_AXES';o.empty_display_size=.2;return o
lift_src=empty('SourceMaintenanceLift',source_col)
base_src=empty('SourceBaseHousing',source_col,lift_src)
rod_src=empty('SourcePistonRod',source_col,lift_src,(0,.30,0));rod_src.scale.z=1.02
saddle_src=empty('SourceTopSaddle',source_col,lift_src,(0,1.45,0))
dais_src=empty('SourceClerkDais',dais_col)

def add(o,name,mat,parent,col):
    o.name=name
    for c in list(o.users_collection):c.objects.unlink(o)
    col.objects.link(o);o.parent=parent;o.data.materials.append(M[mat]);parts.setdefault(parent,[]).append(o);return o

def box(name,pos,size,mat,parent,col=source_col,bev=.015):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p(pos));o=bpy.context.object;o.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    add(o,name,mat,parent,col)
    if bev:
        m=o.modifiers.new('Machined one-segment bevel','BEVEL');m.width=bev;m.segments=1;m.harden_normals=True
    return o

def cylinder(name,pos,r,d,mat,parent,axis=(0,0,1),col=source_col):
    bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=r,depth=d,location=p(pos));o=bpy.context.object;o.rotation_euler=p(axis).to_track_quat('Z','Y').to_euler();return add(o,name,mat,parent,col)

def plate(name,poly,z,depth,mat,parent):
    n=len(poly);vv=[p((x,y,z+depth*.5)) for x,y in poly]+[p((x,y,z-depth*.5)) for x,y in poly]
    ff=[tuple(range(n)),tuple(range(2*n-1,n-1,-1))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    me=bpy.data.meshes.new(name);me.from_pydata(vv,[],ff);me.update();return add(bpy.data.objects.new(name,me),name,mat,parent,source_col)

# Wide low cast base, with a substantial sleeve. No transparent/fake collision art.
box('Lift chamfered floor foot',(0,.075,0),(.86,.15,.86),'FrameNavy',base_src,bev=.035)
box('Lift upper base shoulder',(0,.18,0),(.67,.10,.64),'Cobalt',base_src,bev=.026)
box('Lift fixed hydraulic sleeve',(0,.37,0),(.40,.38,.43),'FrameNavy',base_src,bev=.035)
box('Lift sleeve front warm inset',(0,.37,.226),(.22,.27,.035),'LiftWarmMetal',base_src,bev=.012)
box('Lift sleeve gold service flash',(-.155,.37,.229),(.055,.27,.037),'Gold',base_src,bev=.008)
# Square open collar admits the unit-height moving piston.
for x in [-.153,.153]:box('Sleeve collar side',(x,.56,0),(.115,.08,.42),'LiftWarmMetal',base_src,bev=.011)
for z in [-.16,.16]:box('Sleeve collar return',(0,.56,z),(.215,.08,.10),'LiftWarmMetal',base_src,bev=.011)
# Bold hazard cue on the visible edge, just two readable dark inserts.
box('Lift base front hazard rail',(0,.11,.43),(.63,.10,.036),'Gold',base_src,bev=.01)
for x in [-.17,.12]:plate('Lift base navy hazard insert',[(x-.07,.060),(x+.012,.060),(x+.072,.160),(x-.010,.160)],.451,.013,'FrameNavy',base_src)
for x in [-.32,.32]:
    cylinder('Lift foot front bolt',(x,.079,.437),.034,.027,'LiftWarmMetal',base_src)
# A single runtime PistonRod mesh, with exact local Y bounds [0,1].
box('Unit piston warm sliding rod',(0,.5,0),(.20,1.0,.22),'LiftWarmMetal',rod_src,bev=.007)
box('Unit piston dark depth edge',(.097,.5,-.103),(.013,1.0,.012),'Cobalt',rod_src,bev=.002)
# Saddle origin IS the contact plane. No saddle vertex is above local Y=0.
box('Saddle underside socket',(0,-.205,0),(.34,.09,.34),'Cobalt',saddle_src,bev=.020)
box('Saddle broad navy casting',(0,-.115,0),(.82,.15,.78),'FrameNavy',saddle_src,bev=.029)
box('Saddle warm upper metal',(0,-.035,0),(.73,.055,.69),'LiftWarmMetal',saddle_src,bev=.012)
box('Saddle non-slip contact pad',(0,-.0075,0),(.66,.015,.62),'Ink',saddle_src,bev=.004)
box('Saddle golden front band',(0,-.105,.398),(.63,.088,.031),'Gold',saddle_src,bev=.008)
for x in [-.17,.12]:plate('Saddle dark hazard insert',[(x-.07,-.149),(x+.012,-.149),(x+.068,-.061),(x-.012,-.061)],.420,.012,'FrameNavy',saddle_src)
# Small raised dais behind counter. Top face exactly .25, origin on floor.
box('Dais broad beveled structure',(0,.1175,0),(1.10,.235,.85),'FrameNavy',dais_src,dais_col,.035)
box('Dais inset raised tread',(0,.24,0),(1.02,.02,.77),'DaisTread',dais_src,dais_col,.008)
box('Dais short warm front edge',(0,.175,.414),(.71,.065,.020),'Gold',dais_src,dais_col,.008)
for x in [-.35,.35]:box('Dais top grip strip',(x,.2525,0),(.030,.005,.55),'Cobalt',dais_src,dais_col,.001)
# Correct the grip strips to share the exact .25 contact plane.
for o in parts[dais_src]:
    if 'grip strip' in o.name:o.location.z-=.005

# Merge by functional part and retain multiple materials as surfaces.
def merge(name,source_pivot,parent,target_transform=None):
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();vv=[];ff=[];mi=[];mats=[];offset=0
    inv=source_pivot.matrix_world.inverted()
    for o in parts[source_pivot]:
        mat=o.data.materials[0]
        if mat not in mats:mats.append(mat)
        material_index=mats.index(mat);eo=o.evaluated_get(deps);me=eo.to_mesh();mx=inv@o.matrix_world
        vv.extend(tuple(mx@v.co) for v in me.vertices);ff.extend(tuple(offset+i for i in f.vertices) for f in me.polygons);mi.extend([material_index]*len(me.polygons));offset+=len(me.vertices);eo.to_mesh_clear()
    me=bpy.data.meshes.new(name+'Mesh');me.from_pydata(vv,[],ff);me.update()
    for m in mats:me.materials.append(m)
    for f,i in zip(me.polygons,mi):f.material_index=i
    ob=bpy.data.objects.new(name,me);export_col.objects.link(ob);ob.parent=parent
    if target_transform is not None:ob.matrix_basis=target_transform.copy()
    return ob
lift=empty('AssemblyLift',export_col)
base=merge('BaseHousing',base_src,lift)
rod=merge('PistonRod',rod_src,lift,rod_src.matrix_basis)
saddle=empty('TopSaddle',export_col,lift,(0,1.45,0));saddle_mesh=merge('TopSaddleMesh',saddle_src,saddle)
dais=empty('ClerkDais',export_col);dais_mesh=merge('DaisBody',dais_src,dais)

# Runtime exports intentionally retain moving node transforms; base root is identity.
def export(root,name):
    bpy.ops.object.select_all(action='DESELECT');root.select_set(True)
    for o in root.children_recursive:o.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_animations=False,export_lights=False,export_cameras=False,export_yup=True)
export(lift,'assembly_lift');export(dais,'clerk_dais')
for o in list(export_col.objects):o.hide_render=True;o.hide_set(True)
# A source camera is convenient when opening the editable file.
proof_col=collection('PROOF | Lighting and camera')
def light(name,pos,target,power,size,color):
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.size=size;d.color=color;o=bpy.data.objects.new(name,d);proof_col.objects.link(o);o.location=p(pos);o.rotation_euler=(p(target)-o.location).to_track_quat('-Z','Y').to_euler()
light('Warm workshop key',(2,6,5),(0,.8,0),550,5,(1,.89,.67));light('Soft cobalt bounce',(-4,3,2),(0,1,0),300,4,(.56,.70,1))
d=bpy.data.cameras.new('Mechanism proof camera');cam=bpy.data.objects.new('Mechanism proof camera',d);proof_col.objects.link(cam);cam.location=p((4.3,3.7,8.0));cam.rotation_euler=(p((.65,1.15,0))-cam.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=7.0;scene.camera=cam
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.11,.16,.23,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.7
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=False;scene.render.resolution_x=1440;scene.render.resolution_y=900;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast'
dais_src.location.x=1.65 # Separate source collections visually; exports retain origin zero.
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'workshop_mechanisms_editable.blend'))
# Validate GLB content and explicit pivot / local-coordinate contract.
def glb_info(path):
    raw=path.read_bytes();assert struct.unpack_from('<I',raw,0)[0]==0x46546c67;n=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+n]);aa=d['accessors'];nodes=d['nodes'];tri=0;surf=0
    for m in d['meshes']:
        for q in m['primitives']:tri+=aa[q['indices']]['count']//3;surf+=1
    result={'file':str(path.relative_to(ROOT)),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'nodes':len(nodes),'surfaces':surf,'triangles':tri,'node_transforms':{x['name']:{k:x[k] for k in ['translation','rotation','scale'] if k in x} for x in nodes},'textures':len(d.get('textures',[]))}
    bounds=[]
    def visit(index,parent_t=(0,0,0),parent_s=(1,1,1)):
        node=nodes[index];nt=node.get('translation',[0,0,0]);ns=node.get('scale',[1,1,1]);t=[parent_t[i]+parent_s[i]*nt[i] for i in range(3)];s=[parent_s[i]*ns[i] for i in range(3)]
        assert node.get('rotation',[0,0,0,1])==[0,0,0,1]
        if 'mesh' in node:
            for q in d['meshes'][node['mesh']]['primitives']:
                a=aa[q['attributes']['POSITION']];bounds.append(([t[i]+s[i]*a['min'][i] for i in range(3)],[t[i]+s[i]*a['max'][i] for i in range(3)]))
        for child in node.get('children',[]):visit(child,t,s)
    for index in d['scenes'][d.get('scene',0)]['nodes']:visit(index)
    result['default_pose_godot_bounds']={'min':[min(a[i] for a,b in bounds) for i in range(3)],'max':[max(b[i] for a,b in bounds) for i in range(3)]}
    byname={x['name']:x for x in nodes}
    if 'PistonRod' in byname:
        node=byname['PistonRod'];a=[aa[q['attributes']['POSITION']] for q in d['meshes'][node['mesh']]['primitives']];lo=[min(v['min'][i] for v in a) for i in range(3)];hi=[max(v['max'][i] for v in a) for i in range(3)];assert abs(lo[1])<1e-5 and abs(hi[1]-1)<1e-5,(lo,hi);result['piston_mesh_local_bounds']={'min':lo,'max':hi};assert all(abs(x-y)<1e-5 for x,y in zip(node.get('translation',[]),[0,.30,0]))
        assert 'TopSaddle' in byname
        sn=byname['TopSaddleMesh'];bounds=[aa[q['attributes']['POSITION']] for q in d['meshes'][sn['mesh']]['primitives']];assert max(v['max'][1] for v in bounds)<1e-5
    return result
manifest={'purpose':'decorative workshop mechanisms; no colliders, fake craft, or automated motion','palette_srgb_hex':{'V4_'+k:v for k,v in palette.items()},'assembly_lift':glb_info(OUT/'assembly_lift.glb'),'clerk_dais':glb_info(OUT/'clerk_dais.glb'),'contract':{'coordinate_system':'Godot +Y up / +Z toward camera','instantiate_lift_count':2,'lift_root':'floor contact at Y0 and X/Z centered','base_footprint':[.86,.86],'base_fixed_top_y':.60,'piston_node':'PistonRod','piston_origin_y':.30,'piston_mesh_height':1.0,'piston_default_scale_y':1.02,'saddle_node':'TopSaddle','saddle_contact_plane_local_y':0,'saddle_default_position_y':1.45,'saddle_size':[.82,.25,.816],'recommended_minimum_contact_height':.66,'recommended_maximum_contact_height':3.10,'runtime_update':'TopSaddle.position.y = contact_y; PistonRod.scale.y = max(0.02, contact_y - 0.43)','root_runtime_position_y':.46,'dais_size':[1.10,.25,.85],'dais_top_y':.25,'cast_shadows':True,'physics_collision':False,'visibility':'hide lifts before launch; hide or retract when cell geometry reaches their working envelope'}}
(SRC/'mechanisms_manifest.json').write_text(json.dumps(manifest,indent=2));print('V4_MECHANISMS',json.dumps(manifest))
# Produce a simple dimensional proof with three poses, while keeping editable file clean.
source_col.hide_render=True;dais_col.hide_render=True
for i,(x,h) in enumerate([(-1.75,.66),(0,1.45),(1.75,2.30)]):
    before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(OUT/'assembly_lift.glb'));new=set(bpy.context.scene.objects)-before;roots=[o for o in new if o.parent not in new]
    r=roots[0];r.location.x=x
    for o in new:
        if o.name.startswith('TopSaddle') and o.type=='EMPTY':o.location.z=h
        if o.name.startswith('PistonRod'):o.scale.z=max(.02,h-.43)
before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(OUT/'clerk_dais.glb'));new=set(bpy.context.scene.objects)-before
for o in new:
    if o.parent not in new:o.location=p((3.08,0,0))
# Neutral ground is proof-only, excluded from all GLBs and source objects.
ground=box('Proof-only neutral floor',(0,-.075,0),(8.0,.15,3.3),'Ink',None,proof_col,.02)
scene.render.filepath=str(SRC/'workshop_mechanisms_proof.png');bpy.ops.render.render(write_still=True)
