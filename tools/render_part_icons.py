"""Render original GLBs to transparent, cel-shaded workshop thumbnails.
Run from any directory: blender --background --python tools/render_part_icons.py
No external assets or Python packages required (uses Blender's bundled numpy).
Internal part keys are parsed from scripts/parts.gd. GLBs remain untouched.
"""
import bpy, re, os, json
import numpy as np
from mathutils import Vector
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT=os.path.join(ROOT,'assets','icons');os.makedirs(OUT,exist_ok=True)
text=open(os.path.join(ROOT,'scripts','parts.gd')).read().split('static func cargo_spec')[0]
MAPPING=dict(re.findall(r'"(\w+)": _part\([^\n]*, "(\w+)"\)',text))
PALETTE={'ink':(.006,.011,.032),'navy':(.014,.029,.14),'metal':(.035,.12,.38),'cream':(.65,.81,.85),'white':(.88,.96,1),'orange':(1,.60,.018),'yellow':(1,.86,.025),'cyan':(.015,.83,1),'glass':(.035,.30,.66),'pink':(1,.095,.32),'green':(.19,.94,.58),'purple':(.25,.10,.72)}

def cel(material):
    key=material.name.replace('SC_','').split('.')[0]
    color=PALETTE.get(key,tuple(material.diffuse_color[:3]))
    material.use_nodes=True; n=material.node_tree.nodes; n.clear(); l=material.node_tree.links
    out=n.new('ShaderNodeOutputMaterial'); emit=n.new('ShaderNodeEmission'); emit.inputs['Strength'].default_value=1
    geom=n.new('ShaderNodeNewGeometry'); dot=n.new('ShaderNodeVectorMath');dot.operation='DOT_PRODUCT';dot.inputs[1].default_value=Vector((-.4,-.7,.9)).normalized()
    ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.interpolation='CONSTANT'
    ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1]); e=ramp.color_ramp.elements[0]; e.position=0;e.color=(.28,.34,.51,1)
    e=ramp.color_ramp.elements.new(.13);e.color=(.64,.72,.90,1)
    e=ramp.color_ramp.elements.new(.60);e.color=(1,1,1,1)
    mult=n.new('ShaderNodeMixRGB');mult.blend_type='MULTIPLY';mult.inputs[0].default_value=1;mult.inputs[2].default_value=(*color,1)
    l.new(geom.outputs['Normal'],dot.inputs[0]);l.new(dot.outputs['Value'],ramp.inputs[0]);l.new(ramp.outputs[0],mult.inputs[1]);l.new(mult.outputs[0],emit.inputs[0]);l.new(emit.outputs[0],out.inputs[0])

bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=8;s.cycles.use_denoising=False
s.render.resolution_x=256;s.render.resolution_y=256;s.render.resolution_percentage=100;s.render.film_transparent=True
s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.image_settings.color_depth='8';s.render.image_settings.compression=100
s.view_settings.view_transform='Standard';s.view_settings.look='None';s.world.color=(0,0,0)
bpy.ops.object.camera_add();cam=bpy.context.object;cam.data.type='ORTHO';s.camera=cam
manifest={}
for internal,model in MAPPING.items():
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT,'assets','models',model+'.glb'))
    objects=list(bpy.context.selected_objects);meshes=[o for o in objects if o.type=='MESH']
    for o in meshes:
        for mat in o.data.materials:
            if mat:cel(mat)
    corners=[o.matrix_world@Vector(p) for o in meshes for p in o.bound_box]
    center=sum(corners,Vector())/len(corners)
    # Shared front-left/top view exposes horizontal barrels and front-panel details.
    direction=Vector((.90 if internal=='arc' else -.32,-1,.36)).normalized();cam.location=center+direction*6
    cam.rotation_euler=(-direction).to_track_quat('-Z','Y').to_euler()
    inverse=cam.rotation_euler.to_matrix().transposed();proj=[inverse@(p-center) for p in corners]
    minx,maxx=min(p.x for p in proj),max(p.x for p in proj);miny,maxy=min(p.y for p in proj),max(p.y for p in proj)
    offset=cam.rotation_euler.to_matrix()@Vector(((minx+maxx)/2,(miny+maxy)/2,0));cam.location+=offset
    cam.data.ortho_scale=max(maxx-minx,maxy-miny)*1.23
    path=os.path.join(OUT,internal+'.png');s.render.filepath=path;bpy.ops.render.render(write_still=True)
    im=bpy.data.images.load(path,check_existing=False);im.scale(128,128)
    p=np.array(im.pixels[:],dtype=np.float32).reshape((128,128,4));a=p[:,:,3]; expanded=a.copy()
    for dy in range(-2,3):
        for dx in range(-2,3):
            if dx*dx+dy*dy<=5:expanded=np.maximum(expanded,np.roll(np.roll(a,dy,0),dx,1))
    ink=np.array((.008,.018,.05));newalpha=a+expanded*(1-a)
    p[:,:,:3]=(p[:,:,:3]*a[:,:,None]+ink[None,None,:]*expanded[:,:,None]*(1-a[:,:,None]))/np.maximum(newalpha[:,:,None],1e-6)
    p[:,:,3]=newalpha;im.pixels=p.ravel();im.filepath_raw=path;im.save();bpy.data.images.remove(im)
    manifest[internal]={'model':'assets/models/'+model+'.glb','icon':'assets/icons/'+internal+'.png'}
    for o in objects:bpy.data.objects.remove(o,do_unlink=True)
    print('ICON_READY',internal,flush=True)
with open(os.path.join(OUT,'manifest.json'),'w') as f:json.dump(manifest,f,indent=2)
print('ALL_ICONS_READY',len(manifest),flush=True)
