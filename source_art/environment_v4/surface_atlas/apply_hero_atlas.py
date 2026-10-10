"""Apply one approved raster atlas to a small set of existing shop faces.
Preserves the original editable source and an exact untextured GLB backup.
Builds an isolated review export; --publish copies it into the runtime GLB.
"""
import bpy,json,hashlib,struct,shutil,sys
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[2];ENV=SRC.parent
ORIGINAL_SOURCE=ENV/'shop_editable.blend';RUNTIME=ROOT/'assets/environment_v4/shop_cutaway.glb'
BACKUP=SRC/'shop_cutaway_untextured.glb';TEXTURE_SOURCE=SRC/'hero-surface-atlas-01.png';TEXTURE_RUNTIME=ROOT/'assets/environment_v4/textures/hero-surface-atlas-01.png'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
original_source_sha=sha(ORIGINAL_SOURCE)
baseline=json.loads((ENV/'environment_validation.json').read_text())['shop_cutaway']['sha256']
if not BACKUP.exists():
    assert sha(RUNTIME)==baseline,'Refusing to preserve a different GLB as the untextured baseline'
    shutil.copy2(RUNTIME,BACKUP)
assert sha(BACKUP)==baseline
other_assets={p.name:sha(p) for p in RUNTIME.parent.glob('*.glb') if p.name!=RUNTIME.name}
TEXTURE_RUNTIME.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(TEXTURE_SOURCE,TEXTURE_RUNTIME)
bpy.ops.wm.open_mainfile(filepath=str(ORIGINAL_SOURCE));scene=bpy.context.scene
source_objects=[o for o in scene.objects if o.type=='MESH' and not any(c.name.startswith('EXPORT') for c in o.users_collection)]
# Keep geometry checks independent of vertex ordering: sorted evaluated positions
# per named object, quantized only to five decimal places for Blender float noise.
def geometry_snapshot(objects):
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();digest=hashlib.sha256();lo=[1e10]*3;hi=[-1e10]*3;triangles=0;vertices=0;obj_counts={}
    for o in sorted(objects,key=lambda a:a.name):
        eo=o.evaluated_get(deps);me=eo.to_mesh();mw=o.matrix_world;pts=[]
        for v in me.vertices:
            a=mw@v.co;q=(float(a.x),float(a.z),float(-a.y));pts.append(tuple(round(x,5) for x in q))
            for i in range(3):lo[i]=min(lo[i],q[i]);hi[i]=max(hi[i],q[i])
        tris=sum(len(f.vertices)-2 for f in me.polygons);triangles+=tris;vertices+=len(me.vertices);obj_counts[o.name]=[len(me.vertices),tris]
        digest.update(o.name.encode());digest.update(json.dumps(sorted(pts),separators=(',',':')).encode());eo.to_mesh_clear()
    return {'evaluated_vertex_position_sha256_1e5':digest.hexdigest(),'evaluated_vertices':vertices,'triangles':triangles,'source_meshes':len(objects),'world_bounds_godot':{'min':lo,'max':hi},'object_vertex_triangle_counts':obj_counts}
before=geometry_snapshot(source_objects)
# Source atlas is a project-relative image in the editable preview and embedded in GLB.
img=bpy.data.images.load(str(TEXTURE_RUNTIME),check_existing=True);assert tuple(img.size)==(1254,1254);img.colorspace_settings.name='sRGB';img.pack()
mat=bpy.data.materials.new('V4_HeroSurfaceAtlas01');mat.use_nodes=True;mat.diffuse_color=(1,1,1,1)
bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(1,1,1,1);bs.inputs['Roughness'].default_value=.82
tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.name='Approved hero raster atlas 01';tex.image=img;tex.interpolation='Closest';tex.extension='CLIP';mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
# Rectangles are source pixels, top-origin. Quiet body samples do not double-print
# the labels already present as thin three-dimensional paper objects.
targets=[
('Tool drawer -1.71 0',[8,8,617,148],'drawer_01: quiet navy front'),
('Tool drawer -1.71 2',[8,166,617,302],'drawer_02: quiet cobalt front'),
('Tool drawer 3.84 1',[8,321,617,461],'drawer_03: navy front'),
('Counter outgoing parcel corrugated body',[796,145,928,293],'kraft_a: quiet body with sparse lower edge wear'),
('Counter outgoing parcel shipping label',[802,50,908,124],'kraft_a: existing raised A2 postage label'),
('Counter outgoing parcel front tape',[764,12,784,63],'kraft_a: quiet tape on existing tape geometry'),
('Shelf parcel 1.995 0 corrugated body',[956,444,1117,605],'kraft_d: quiet dark kraft body'),
('Shelf parcel 1.995 0 shipping label',[991,355,1088,424],'kraft_d: existing raised A2 label'),
('Shelf parcel 1.995 0 front tape',[764,12,784,63],'quiet tape on existing tape geometry'),
('Shelf parcel 3.355 1 corrugated body',[952,8,1243,298],'kraft_b: single printed03 label on previously unlabelled face'),
('Shelf parcel 3.355 1 front tape',[1078,12,1100,41],'kraft_b: tape on existing tape geometry')]
selected=[]
for name,rect,purpose in targets:
    o=bpy.data.objects.get(name);assert o is not None,name
    # Bake only the existing evaluated bevel into the preview object. Geometry is
    # verified before/after; original editable source remains untouched.
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
    for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
    me=o.data;idx=len(me.materials);me.materials.append(mat);uv=me.uv_layers.get('HeroSurfaceUV') or me.uv_layers.new(name='HeroSurfaceUV');me.uv_layers.active=uv;uv.active_render=True
    xs=[v.co.x for v in me.vertices];ys=[v.co.z for v in me.vertices];xmin,xmax=min(xs),max(xs);ymin,ymax=min(ys),max(ys);count=0
    l,t,r,b=rect
    for poly in me.polygons:
        # Cube front is local -BlenderY, equivalent to Godot +Z. Excludes all bevels.
        if poly.normal.y>-.9999:continue
        poly.material_index=idx;count+=1
        for loopindex in poly.loop_indices:
            v=me.vertices[me.loops[loopindex].vertex_index].co;u=(v.x-xmin)/max(1e-8,xmax-xmin);vv=(v.z-ymin)/max(1e-8,ymax-ymin)
            uv.data[loopindex].uv=((l+.5+u*(r-l-1))/1254,1-(b-.5-vv*(b-t-1))/1254)
    assert count>0,(name,'no front polygon selected')
    selected.append({'object':name,'front_polygons':count,'pixel_rect_top_origin':rect,'purpose':purpose})
after=geometry_snapshot(source_objects)
assert before==after,'Evaluated source geometry changed during UV assignment'
# Remove only old material-merged export copies in the in-memory preview.
for collection in list(scene.collection.children):
    if collection.name.startswith('EXPORT'):
        for o in list(collection.objects):bpy.data.objects.remove(o,do_unlink=True)
        bpy.data.collections.remove(collection)
export_col=bpy.data.collections.new('EXPORT | Shared atlas and V4 palette');scene.collection.children.link(export_col)
# One evaluated pass, grouping polygons by material. Source vertex coordinates and
# polygon order are preserved; UV data travels only with the one atlas material.
groups={};deps=bpy.context.evaluated_depsgraph_get()
for o in source_objects:
    eo=o.evaluated_get(deps);me=eo.to_mesh();mw=o.matrix_world;vertex_cache={};uv_active=me.uv_layers.active
    for poly in me.polygons:
        m=bpy.data.materials[me.materials[poly.material_index].name];key=m.name
        if key not in groups:groups[key]={'mat':m,'vertices':[],'faces':[],'uv_faces':[]}
        group=groups[key]
        if key not in vertex_cache:
            vertex_cache[key]=len(group['vertices']);group['vertices'].extend(tuple(mw@v.co) for v in me.vertices)
        offset=vertex_cache[key];group['faces'].append(tuple(offset+i for i in poly.vertices))
        if m==mat:
            assert uv_active is not None;group['uv_faces'].append([tuple(uv_active.data[i].uv) for i in poly.loop_indices])
    eo.to_mesh_clear()
merged=[]
for key,g in groups.items():
    mesh=bpy.data.meshes.new('V4_Shop_'+key.removeprefix('V4_'));mesh.from_pydata(g['vertices'],[],g['faces']);mesh.materials.append(g['mat']);mesh.update()
    if g['mat']==mat:
        uv=mesh.uv_layers.new(name='UVMap')
        for face,coords in zip(mesh.polygons,g['uv_faces']):
            for li,q in zip(face.loop_indices,coords):uv.data[li].uv=q
    o=bpy.data.objects.new(mesh.name,mesh);export_col.objects.link(o);merged.append(o)
bpy.ops.object.select_all(action='DESELECT')
for o in merged:o.select_set(True)
bpy.context.view_layer.objects.active=merged[0]
review=SRC/'shop_cutaway_textured.glb'
bpy.ops.export_scene.gltf(filepath=str(review),export_format='GLB',use_selection=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True)
print('EXPORT_FINISHED_HIDE_BEGIN',flush=True)
bpy.context.view_layer.update()
for o in merged:o.hide_render=True;o.hide_set(True)
print('EXPORT_HIDDEN_SAVE_BEGIN',flush=True)
preview=SRC/'shop_textured_editable.blend';img.filepath='//../../../assets/environment_v4/textures/hero-surface-atlas-01.png';bpy.ops.wm.save_as_mainfile(filepath=str(preview),relative_remap=False);print('PREVIEW_SAVED',flush=True)
# Inspect exported material and bounds without relying on import side effects.
raw=review.read_bytes();n=struct.unpack_from('<I',raw,12)[0];gltf=json.loads(raw[20:20+n]);acc=gltf['accessors'];bounds=[];triangles=0;surfaces=0;uv_surfaces=0
for mesh in gltf['meshes']:
    for q in mesh['primitives']:
        a=acc[q['attributes']['POSITION']];bounds.append((a['min'],a['max']));triangles+=acc[q['indices']]['count']//3;surfaces+=1
        if 'TEXCOORD_0' in q['attributes']:uv_surfaces+=1
lo=[min(a[i] for a,b in bounds) for i in range(3)];hi=[max(b[i] for a,b in bounds) for i in range(3)]
assert triangles==before['triangles'];assert surfaces==31;assert uv_surfaces==1
for i in range(3):assert abs(lo[i]-before['world_bounds_godot']['min'][i])<1e-4 and abs(hi[i]-before['world_bounds_godot']['max'][i])<1e-4
for node in gltf['nodes']:assert not any(k in node for k in ['translation','rotation','scale','matrix'])
atlas_export=[m for m in gltf['materials'] if m['name']=='V4_HeroSurfaceAtlas01'];assert len(atlas_export)==1
pbr=atlas_export[0]['pbrMetallicRoughness'];assert pbr.get('baseColorFactor',[1,1,1,1])==[1,1,1,1] and 'baseColorTexture' in pbr
assert len(gltf.get('images',[]))==1 and len(gltf.get('textures',[]))==1
assert sha(ORIGINAL_SOURCE)==original_source_sha and sha(BACKUP)==baseline
for name,h in other_assets.items():assert sha(RUNTIME.parent/name)==h,name+' changed'
# Save concise geometry evidence instead of a huge per-object data dump.
geometry_evidence={k:v for k,v in before.items() if k!='object_vertex_triangle_counts'}
manifest={'status':'selective textured proof; no widespread material replacement','atlas_source':str(TEXTURE_SOURCE.relative_to(ROOT)),'atlas_runtime':str(TEXTURE_RUNTIME.relative_to(ROOT)),'atlas_dimensions':[1254,1254],'atlas_sha256':sha(TEXTURE_SOURCE),'generation_tool':'built-in image_gen','original_source':str(ORIGINAL_SOURCE.relative_to(ROOT)),'original_source_sha256':original_source_sha,'untextured_glb_backup':str(BACKUP.relative_to(ROOT)),'untextured_glb_sha256':baseline,'textured_source':str(preview.relative_to(ROOT)),'review_export':str(review.relative_to(ROOT)),'textured_export_sha256':sha(review),'material':'V4_HeroSurfaceAtlas01','albedo_multiplier':[1,1,1,1],'texture_filter':'nearest','texture_repeat':False,'emissive':False,'applied_source_objects':selected,'textured_front_polygons':sum(t['front_polygons'] for t in selected),'source_geometry_unchanged':True,'geometry_evidence':geometry_evidence,'export_surfaces':surfaces,'added_surfaces':1,'textured_surfaces':uv_surfaces,'export_triangles':triangles,'identity_export_nodes':True,'export_images':1,'existing_other_asset_sha256':other_assets}
# Actual module-space clearance is unchanged because evaluated positions are identical.
clearance=json.loads((ENV/'clearance_validation.json').read_text());assert clearance['passed'];manifest['inherited_unchanged_clearance']=clearance
manifest['runtime_export_closed']=False
(SRC/'material_uv_manifest.json').write_text(json.dumps(manifest,indent=2));print('ATLAS_APPLICATION_RESULT',json.dumps({k:v for k,v in manifest.items() if k not in ['applied_source_objects','existing_other_asset_sha256','inherited_unchanged_clearance']}))
# First proof uses actual dimensional source objects and original real lights.
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=False;scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.image_settings.file_format='PNG'
cam=scene.camera
def proof(file,position,target,scale):
    cam.location=Vector((position[0],-position[2],position[1]));point=Vector((target[0],-target[2],target[1]));cam.rotation_euler=(point-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;scene.render.filepath=str(SRC/file);bpy.ops.render.render(write_still=True)
proof('hero-drawer-proof-01.png',(-1.7,2.35,8),(-1.7,1.05,-1.3),4.3)
proof('hero-parcel-proof-01.png',(-9.6,3.70,9),(-9.6,2.27,-1.1),5.25)

if '--publish' in sys.argv:
    assert img.packed_file is not None
    shutil.copy2(review,RUNTIME)
    manifest['runtime_export_closed']=True
    manifest['runtime_export']=str(RUNTIME.relative_to(ROOT))
    (SRC/'material_uv_manifest.json').write_text(json.dumps(manifest,indent=2))
