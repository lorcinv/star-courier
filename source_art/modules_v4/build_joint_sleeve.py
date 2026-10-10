"""Small real-link-only structural sleeve. Original editable Blender geometry.
Run: /usr/bin/blender -b -t 4 --python-exit-code 1 --python source_art/modules_v4/build_joint_sleeve.py
Exports only assets/modules_v4/joint_sleeve.glb; existing craft assets are never modified.
"""
import bpy,bmesh,json,struct,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];SRC=ROOT/'source_art/modules_v4';OUT=ROOT/'assets/modules_v4';PROOF=SRC/'proofs'
for p in [SRC,OUT,PROOF]:p.mkdir(parents=True,exist_ok=True)
protected={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('*.glb') if p.stem!='joint_sleeve'}
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def linear(v):return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4
def material(name,h):
 rgb=tuple(linear(int(h[i:i+2],16)/255) for i in (0,2,4));m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*rgb,1);m.use_backface_culling=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*rgb,1);p.inputs['Roughness'].default_value=.87;m['source_srgb_hex']='#'+h;return m
mats=[material('V4_JointOchre','cf982d'),material('V4_InkNavy','18273d')]
def bco(v):return (v[0],-v[2],v[1])
def block(name,size,mat,bevel):
 bpy.ops.mesh.primitive_cube_add(size=1);o=bpy.context.object;o.name=name;o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(mats[mat]);mod=o.modifiers.new('Machined single-cut edge','BEVEL');mod.width=bevel;mod.segments=1;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 return o
parts=[block('Editable ochre structural sleeve',(.32,.462,.66),0,.035),block('Editable narrow central navy gasket',(.024,.48,.68),1,.009)]
verts=[];faces=[];indices=[]
for o in parts:
 bm=bmesh.new();bm.from_mesh(o.data);assert all(e.is_manifold for e in bm.edges);assert bm.calc_volume(signed=True)>0;bm.free()
 offset=len(verts);verts +=[tuple(v.co) for v in o.data.vertices]
 for f in o.data.polygons:faces.append(tuple(offset+i for i in f.vertices));indices.append(o.data.materials[0]==mats[1])
mesh=bpy.data.meshes.new('JointSleeve_Batched_2Surfaces');mesh.from_pydata(verts,[],faces);mesh.update()
for mat in mats:mesh.materials.append(mat)
for face,mat in zip(mesh.polygons,indices):face.material_index=int(mat)
export=bpy.data.objects.new('joint_sleeve',mesh);bpy.context.collection.objects.link(export)
bpy.ops.object.select_all(action='DESELECT');export.select_set(True);bpy.context.view_layer.objects.active=export
bpy.ops.export_scene.gltf(filepath=str(OUT/'joint_sleeve.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
# Godot otherwise inserts a wrapper Node3D even for a single mesh. The documented
# data-free GODOT_single_root flag makes that mesh the native scene root as requested.
# Spec: https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Vendor/GODOT_single_root/README.md
path=OUT/'joint_sleeve.glb';raw=path.read_bytes();n,t=struct.unpack_from('<II',raw,12);g=json.loads(raw[20:20+n])
assert len(g['nodes'])==1 and len(g['scenes'])==1 and g['scenes'][0]['nodes']==[0]
g.setdefault('extensionsUsed',[]).append('GODOT_single_root');g['scene']=0
blob=json.dumps(g,separators=(',',':')).encode();blob+=b' '*((-len(blob))%4)
tail=raw[20+n:];raw=struct.pack('<III',0x46546C67,2,20+len(blob)+len(tail))+struct.pack('<II',len(blob),0x4E4F534A)+blob+tail;path.write_bytes(raw)
assert len(g['nodes'])==1 and len(g['meshes'])==1
node=g['nodes'][0];assert node['name']=='joint_sleeve' and node['mesh']==0;assert not any(k in node for k in ['translation','rotation','scale','matrix','children'])
assert len(g['meshes'][0]['primitives'])==2 and len(g['materials'])==2 and not g.get('images')
bounds=[]
for p in g['meshes'][0]['primitives']:
 a=g['accessors'][p['attributes']['POSITION']];bounds.extend([a['min'],a['max']])
lo=[min(p[k] for p in bounds) for k in range(3)];hi=[max(p[k] for p in bounds) for k in range(3)]
assert all(abs(a-b)<1e-6 for a,b in zip(lo,[-.16,-.24,-.34]));assert all(abs(a-b)<1e-6 for a,b in zip(hi,[.16,.24,.34]))
bpy.data.objects.remove(export,do_unlink=True)
for p in OUT.glob('*.glb'):
 if p.stem!='joint_sleeve':assert hashlib.sha256(p.read_bytes()).hexdigest()==protected[p.name]
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1;scene.render.engine='CYCLES';scene.cycles.samples=96;scene.cycles.use_denoising=False
scene.render.resolution_x=640;scene.render.resolution_y=440;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.033,.051,.081,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.6
scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast';scene.view_settings.exposure=-.65
for name,loc,energy,color,size in [('Warm upper key',(-2,3,4),350,(1,.8,.5),3),('Cool soft fill',(3,1,3),90,(.36,.64,1),3)]:
 bpy.ops.object.light_add(type='AREA',location=bco(loc));o=bpy.context.object;o.name=name;o.data.energy=energy;o.data.color=color;o.data.size=size;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=bco((-1.4,1.2,3.5)));cam=bpy.context.object;cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=1.05;scene.camera=cam
scene.render.filepath=str(PROOF/'joint_sleeve.png');bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'joint_sleeve_source.blend'));bpy.ops.render.render(write_still=True)
record={'result':'PASS','asset':'res://assets/modules_v4/joint_sleeve.glb','source':'source_art/modules_v4/joint_sleeve_source.blend','generator':'source_art/modules_v4/build_joint_sleeve.py','render_use':'Place only at actual cardinal structural edges; remove when sim link breaks. Rotate X axis onto edge axis. No sockets or gameplay changes.','root':'One native MeshInstance3D at origin with identity transform; GODOT_single_root prevents wrapper nodes','axes':'X along structural connection, Y up, Z toward camera','bounds_godot_m':{'min':[-.16,-.24,-.34],'max':[.16,.24,.34]},'surfaces':2,'triangles':sum(len(p.vertices)-2 for o in parts for p in o.data.polygons),'closed_source_components':2,'source_srgb_hex':{'V4_JointOchre':'#cf982d','V4_InkNavy':'#18273d'},'sha256':hashlib.sha256(raw).hexdigest(),'existing_glbs_unchanged_during_joint_build':True}
(SRC/'joint_sleeve_manifest.json').write_text(json.dumps(record,indent=2));print(json.dumps(record))
