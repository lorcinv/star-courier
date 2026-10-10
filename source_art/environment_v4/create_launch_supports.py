"""Separate decorative launch rail and pier. Existing GLBs are hash-protected.
Run: blender -b --python source_art/environment_v4/create_launch_supports.py
"""
import bpy,math,json,struct,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[1];OUT=ROOT/'assets/environment_v4'
PRESERVED={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('*.glb') if p.stem not in ['launch_rail','launch_pier']}
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;palette={'FrameNavy':'21375A','Cobalt':'31527D','Cream':'EFD8AD','Gold':'E8AF30'};M={};parts={}
def lin(c):return c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4
for key,h in palette.items():
    m=bpy.data.materials.new('V4_'+key);m.use_nodes=True;rgba=tuple(lin(int(h[i:i+2],16)/255) for i in [0,2,4])+(1,);m.diffuse_color=rgba;b=m.node_tree.nodes.get('Principled BSDF');b.inputs['Base Color'].default_value=rgba;b.inputs['Roughness'].default_value=.82;M[key]=m

def p(v):return Vector((v[0],-v[2],v[1]))
def col(name):c=bpy.data.collections.new(name);scene.collection.children.link(c);return c
rail_col=col('SOURCE | Unit launch rail editable pieces');pier_col=col('SOURCE | Launch pier editable pieces');export_col=col('EXPORT | Material-grouped supports');proof_col=col('PROOF | Lights camera and display')
def empty(name,c):o=bpy.data.objects.new(name,None);c.objects.link(o);o.empty_display_type='PLAIN_AXES';o.empty_display_size=.15;return o
rail_src=empty('SourceLaunchRail',rail_col);pier_src=empty('SourceLaunchPier',pier_col)
def add(o,name,mat,parent,c,bev=0):
    o.name=name
    for old in list(o.users_collection):old.objects.unlink(o)
    c.objects.link(o);o.parent=parent;o.data.materials.append(M[mat]);parts.setdefault(parent,[]).append(o)
    if bev:
        b=o.modifiers.new('Real one-segment bevel','BEVEL');b.width=bev;b.segments=1;b.harden_normals=True
    return o

def box(name,pos,size,mat,parent,c,bev=.012):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p(pos));o=bpy.context.object;o.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);return add(o,name,mat,parent,c,bev)
def plate(name,poly,z,d,mat,parent,c):
    n=len(poly);vv=[p((x,y,z+d/2)) for x,y in poly]+[p((x,y,z-d/2)) for x,y in poly];ff=[tuple(range(n)),tuple(range(2*n-1,n-1,-1))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)];me=bpy.data.meshes.new(name);me.from_pydata(vv,[],ff);me.update();return add(bpy.data.objects.new(name,me),name,mat,parent,c)
def beam(name,a,b,w,d,mat,parent,c):
    va,vb=p(a),p(b);bpy.ops.mesh.primitive_cube_add(size=1,location=(va+vb)*.5);o=bpy.context.object;o.scale=(w,d,(vb-va).length);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);direction=(vb-va).normalized();depth_axis=Vector((0,1,0));width_axis=depth_axis.cross(direction).normalized();o.rotation_euler=Matrix((width_axis,depth_axis,direction)).transposed().to_euler();return add(o,name,mat,parent,c,.015)

# Unit rail: all long features run along X, so stretching does not turn bolts or
# little repeating trim into visual artifacts. Top contact plane is exactly Y=0.
box('Rail full-depth structural lower beam',(0,-.2575,0),(1,.185,1.25),'FrameNavy',rail_src,rail_col,.027)
box('Rail recessed center deck',(0,-.108,0),(1,.094,.64),'Cobalt',rail_src,rail_col,.010)
# Raised flank beams and warm narrow bearing edges form a real channel profile.
for z in [-.5075,.5075]:
    box('Rail raised blue shoulder '+str(z),(0,-.0975,z),(1,.155,.235),'Cobalt',rail_src,rail_col,.015)
    box('Rail warm contact edge '+str(z),(0,-.014,z),(1,.028,.16),'Cream',rail_src,rail_col,.007)
# Two deeper grooves are actual negative gaps between surfaces, with dark floors.
for z in [-.355,.355]:box('Rail dark recessed groove floor '+str(z),(0,-.188,z),(1,.038,.07),'FrameNavy',rail_src,rail_col,.006)
# Continuous front warning strip: no repeated tiny pieces along the scalable axis.
box('Rail continuous yellow hazard inset',(0,-.216,.617),(.82,.086,.015),'Gold',rail_src,rail_col,.006)
for sign in [-1,1]:
    if sign<0:poly=[(-.41,-.259),(-.29,-.259),(-.23,-.173),(-.35,-.173)]
    else:poly=[(.23,-.259),(.35,-.259),(.41,-.173),(.29,-.173)]
    plate('Rail large navy hazard end wedge',poly,.622,.004,'FrameNavy',rail_src,rail_col)
# The underside has a thick central mounting spine, within the -0.35 bound.
box('Rail underside central mounting spine',(0,-.3175,0),(.94,.065,.58),'FrameNavy',rail_src,rail_col,.016)

# Fixed pier: broad chamfered footing and an honest braced support frame.
box('Pier grounded chamfered footing',(0,.075,0),(.9,.15,.9),'FrameNavy',pier_src,pier_col,.040)
box('Pier wide raised base shoulder',(0,.193,0),(.73,.086,.73),'Cobalt',pier_src,pier_col,.022)
# Twin dimensional A-frame legs have a broad depth web, rather than thin flat art.
for sign in [-1,1]:
    beam('Pier splayed primary brace '+str(sign),(sign*.275,.21,0),(sign*.135,1.078,0),.19,.55,'FrameNavy',pier_src,pier_col)
    beam('Pier front cobalt brace face '+str(sign),(sign*.277,.239,.290),(sign*.136,1.055,.290),.087,.040,'Cobalt',pier_src,pier_col)
# A recessed center web and mid-height crosspiece tie the legs together.
box('Pier recessed shear web',(0,.622,-.13),(.16,.757,.17),'Cobalt',pier_src,pier_col,.015)
box('Pier middle broad tie beam',(0,.56,.015),(.49,.13,.56),'Cobalt',pier_src,pier_col,.019)
box('Pier upper load-bearing capital',(0,1.105,0),(.69,.15,.77),'FrameNavy',pier_src,pier_col,.027)
box('Pier warm bearing plate',(0,1.19,0),(.62,.02,.70),'Cream',pier_src,pier_col,.006)
# A single broad cue on the front base gives the fixed footing a workshop identity.
box('Pier front golden inset',(0,.159,.439),(.53,.061,.012),'Gold',pier_src,pier_col,.006)
plate('Pier modest front hazard wedge',[(-.17,.129),(-.095,.129),(-.051,.190),(-.126,.190)],.446,.004,'FrameNavy',pier_src,pier_col)

# Keep source components editable; export one material-grouped mesh per asset.
def merge(name,source,parent):
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();inv=source.matrix_world.inverted();vv=[];ff=[];mi=[];mats=[];offset=0
    for o in parts[source]:
        mat=o.data.materials[0]
        if mat not in mats:mats.append(mat)
        idx=mats.index(mat);eo=o.evaluated_get(deps);me=eo.to_mesh();mx=inv@o.matrix_world
        vv.extend(tuple(mx@v.co) for v in me.vertices);ff.extend(tuple(offset+i for i in f.vertices) for f in me.polygons);mi.extend([idx]*len(me.polygons));offset+=len(me.vertices);eo.to_mesh_clear()
    me=bpy.data.meshes.new(name);me.from_pydata(vv,[],ff);me.update()
    for m in mats:me.materials.append(m)
    for f,i in zip(me.polygons,mi):f.material_index=i
    ob=bpy.data.objects.new(name,me);export_col.objects.link(ob);ob.parent=parent;return ob
rail=empty('LaunchRail',export_col);rail_mesh=merge('LaunchRailMesh',rail_src,rail)
pier=empty('LaunchPier',export_col);pier_mesh=merge('LaunchPierMesh',pier_src,pier)
def export(root,name):
    bpy.ops.object.select_all(action='DESELECT');root.select_set(True)
    for o in root.children_recursive:o.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True)
export(rail,'launch_rail');export(pier,'launch_pier')
for o in list(export_col.objects):o.hide_render=True;o.hide_set(True)
# Source presentation is separated; these positions are not in runtime exports.
rail_src.location=p((-1.0,1.4,0));pier_src.location=p((.8,0,0))
def light(name,pos,target,energy,size,color):
    d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.size=size;d.color=color;o=bpy.data.objects.new(name,d);proof_col.objects.link(o);o.location=p(pos);o.rotation_euler=(p(target)-o.location).to_track_quat('-Z','Y').to_euler()
light('Warm launch service key',(2,6,5),(0,.7,0),650,4,(1,.88,.66));light('Cool support fill',(-4,3,1),(0,.6,0),250,3,(.60,.74,1))
d=bpy.data.cameras.new('Launch support proof camera');cam=bpy.data.objects.new('Launch support proof camera',d);proof_col.objects.link(cam);cam.location=p((4.5,4.3,8));cam.rotation_euler=(p((.1,.75,0))-cam.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=6.7;scene.camera=cam
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.10,.15,.22,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.55
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=False;scene.render.resolution_x=1440;scene.render.resolution_y=900;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast'
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'launch_supports_editable.blend'))

def validate(name,expected_lo,expected_hi):
    path=OUT/(name+'.glb');raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+n]);acc=d['accessors'];bounds=[];surf=0;tri=0
    for node in d['nodes']:assert not any(k in node for k in ['translation','scale','rotation','matrix']),node
    for m in d['meshes']:
        for q in m['primitives']:
            a=acc[q['attributes']['POSITION']];bounds.append((a['min'],a['max']));surf+=1;tri+=acc[q['indices']]['count']//3
    lo=[min(a[i] for a,b in bounds) for i in range(3)];hi=[max(b[i] for a,b in bounds) for i in range(3)]
    assert all(abs(lo[i]-expected_lo[i])<1e-4 and abs(hi[i]-expected_hi[i])<1e-4 for i in range(3)),(name,lo,hi)
    assert not d.get('textures') and not d.get('animations')
    return {'file':str(path.relative_to(ROOT)),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'nodes':len(d['nodes']),'surfaces':surf,'triangles':tri,'godot_bounds':{'min':lo,'max':hi},'identity_transforms':True,'textures':0,'materials':[m['name'] for m in d['materials']]}
manifest={'purpose':'decorative supports left behind at ignition; actual launcher simulation modules stay separate','coordinate_system':'Godot X horizontal / +Y up / +Z front','palette_srgb_hex':{'V4_'+k:v for k,v in palette.items()},'launch_rail':validate('launch_rail',[-.5,-.35,-.625],[.5,0,.625]),'launch_pier':validate('launch_pier',[-.45,0,-.45],[.45,1.2,.45]),'contract':{'rail_root':'X/Z centered; Y0 is top contact plane','rail_unit_x_length':1.0,'rail_x_scale':'set scale.x to desired rail length in meters; keep scale.y=scale.z=1','rail_depth':1.25,'rail_geometry_below_contact':.35,'pier_root':'X/Z centered; Y0 is floor contact','pier_height':1.2,'pier_footprint':[.9,.9],'support_relation':'rail contact Y = pier floor Y + 1.2 + .35; pier top meets rail underside','recommended_pier_count':'2 or 3 under the real variable-width launcher','runtime_behavior':'remain static behind at ignition; no collider or simulated module in either GLB'},'preserved_asset_sha256':PRESERVED}
assert manifest['launch_rail']['surfaces']+manifest['launch_pier']['surfaces']<=8
for name,h in PRESERVED.items():assert hashlib.sha256((OUT/name).read_bytes()).hexdigest()==h,name+' was changed'
(SRC/'launch_supports_manifest.json').write_text(json.dumps(manifest,indent=2));print('V4_LAUNCH_SUPPORTS',json.dumps(manifest))
# Proof: unit rail on one pier, then a 3.7m stretched rail on two fixed piers.
rail_col.hide_render=True;pier_col.hide_render=True
def place(file,pos,scale=(1,1,1)):
    before=set(scene.objects);bpy.ops.import_scene.gltf(filepath=str(OUT/(file+'.glb')));new=set(scene.objects)-before
    for o in new:
        if o.parent not in new:o.location=p(pos);o.scale=(scale[0],scale[2],scale[1])
place('launch_rail',(-2.25,1.55,0));place('launch_pier',(-2.25,0,0))
place('launch_rail',(.85,1.55,0),(3.7,1,1))
for x in [-.48,2.18]:place('launch_pier',(x,0,0))
box('Proof only ground',(0,-.07,0),(7.2,.14,3.3),'FrameNavy',None,proof_col,.03)
scene.render.filepath=str(SRC/'launch_supports_proof.png');bpy.ops.render.render(write_still=True)
