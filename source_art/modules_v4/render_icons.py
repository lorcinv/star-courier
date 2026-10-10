"""Render the locked final Blender modules as 128x128 transparent native-pixel UI icons.
No meshes, GLBs, source .blend or existing model-generation files are modified.
Run from project root:
  /usr/bin/blender -b -t 4 --python-exit-code 1 --python source_art/modules_v4/render_icons.py
  python source_art/modules_v4/render_icons.py --proof-only
"""
from pathlib import Path
import sys,json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'source_art/modules_v4';OUT=ROOT/'assets/icons';PROOF=SRC/'proofs'
SOURCE=SRC/'star_courier_modules_v4.blend'
ARCHIVE=SRC/'archive/2026-10-10T081615Z/icons_before_remodel'
ICONS=[('cargo','cargo_crate'),('beam','beam'),('battery','cell'),('thruster','thruster'),('armor','armor'),('coupler','separator'),('spring','spring')]

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def verify_locked_models():
 record=json.loads((SRC/'release_hashes_sha256.json').read_text());checked={}
 for rel,expected in record['sha256'].items():
  if not (rel.endswith('.glb') or rel=='source_art/modules_v4/star_courier_modules_v4.blend'):continue
  actual=digest(ROOT/rel);assert actual==expected,(rel,actual,expected);checked[rel]=actual
 return checked

def preserve_old_icons():
 ARCHIVE.mkdir(parents=True,exist_ok=True)
 record=ARCHIVE/'preservation.json'
 if record.exists():return
 old={};missing=[]
 for name,model in ICONS:
  path=OUT/(name+'.png')
  if path.exists():
   shutil.copyfile(path,ARCHIVE/path.name);old[path.name]=digest(path);assert digest(ARCHIVE/path.name)==old[path.name]
  else:missing.append(path.name)
 record.write_text(json.dumps({'sha256':old,'not_previously_present':missing},indent=2))

def render_icons():
 import bpy
 from mathutils import Vector
 locked=verify_locked_models();preserve_old_icons()
 bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
 scene=bpy.context.scene
 # Leave source data intact on disk. This transient scene uses its actual component meshes and albedo.
 for o in bpy.context.scene.objects:
  if o.type=='MESH':o.hide_render=True
  if o.type=='LIGHT':o.hide_render=True
 stage=bpy.data.collections.new('ICON / transient review stage');scene.collection.children.link(stage)
 def bco(v):return (v[0],-v[2],v[1])
 def place(o):
  for c in list(o.users_collection):c.objects.unlink(o)
  stage.objects.link(o)
 def lamp(name,p,energy,color,size):
  bpy.ops.object.light_add(type='AREA',location=bco(p));o=bpy.context.object;o.name=name;place(o)
  o.data.energy=energy;o.data.color=color;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
 lamp('Icon warm top-front key',(-2.7,4.5,5),450,(1,.78,.47),4.0)
 lamp('Icon cool front bounce',(2,1.2,2.5),130,(.36,.65,1),3.0)
 lamp('Icon cream rear rim',(-1,3,-3.5),300,(1,.86,.62),3.0)
 bpy.ops.object.camera_add();cam=bpy.context.object;cam.name='Icon consistent three-quarter camera';place(cam);scene.camera=cam
 cam.data.type='ORTHO';cam.data.ortho_scale=1.48
 scene.render.engine='CYCLES';scene.cycles.samples=160;scene.cycles.use_denoising=False
 scene.render.resolution_x=128;scene.render.resolution_y=128;scene.render.resolution_percentage=100
 scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.color_depth='8';scene.render.image_settings.compression=20;scene.render.filter_size=.8
 scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast';scene.view_settings.exposure=-.65;scene.view_settings.gamma=1
 results=[]
 for name,model in ICONS:
  for col in bpy.data.collections:
   if col.name.startswith('SOURCE /') or col.name.startswith('ASSEMBLY /'):col.hide_render=col.name!='SOURCE / '+model
  col=bpy.data.collections['SOURCE / '+model]
  root=bpy.data.objects[model+'_SOURCE'];root.location=(0,0,0)
  parts=[o for o in col.objects if o.type=='MESH']
  for o in parts:o.hide_render=False
  bpy.context.view_layer.update()
  corners=[o.matrix_world@Vector(p) for o in parts for p in o.bound_box]
  center=Vector(tuple((min(p[i] for p in corners)+max(p[i] for p in corners))*.5 for i in range(3)))
  cam.location=center+Vector(bco((-3.0,2.35,7.2)))
  cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
  scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
  results.append({'filename':name+'.png','actual_model':model,'source_components':len(parts),'native_size':[128,128],'sha256':digest(OUT/(name+'.png'))})
  for o in parts:o.hide_render=True
 assert verify_locked_models()==locked
 (SRC/'icons_render_manifest.json').write_text(json.dumps({'result':'PASS','generator':'source_art/modules_v4/render_icons.py','source_blend':str(SOURCE.relative_to(ROOT)),'source_meshes_and_glb_hashes_unchanged':True,'camera_godot_offset':[-3.0,2.35,7.2],'orthographic_size_m':1.48,'native_pixels':128,'alpha':'True transparent film, RGBA PNG; no baked backdrop or shadow plane','icons':results,'locked_model_sha256':locked},indent=2))
 print('SEVEN_NATIVE_MODULE_ICONS_RENDERED')

def proof_sheet():
 from PIL import Image,ImageDraw,ImageFont
 manifest=json.loads((SRC/'icons_render_manifest.json').read_text());assert verify_locked_models()==manifest['locked_model_sha256']
 # Two quiet UI-like surfaces on one proof show both the silhouette and real alpha edge.
 pad=18;cell=140;header=45;row_h=158;w=pad*2+cell*7;h=header+row_h*2+26
 sheet=Image.new('RGBA',(w,h),(239,232,212,255));draw=ImageDraw.Draw(sheet)
 font_path='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
 try:font=ImageFont.truetype(font_path,13);head=ImageFont.truetype(font_path,16)
 except OSError:font=ImageFont.load_default();head=font
 draw.text((pad,13),'FINAL MODULE ICONS  /  ACTUAL BLENDER MESHES  /  NATIVE 128 × 128',font=head,fill=(24,39,61,255))
 checks=[]
 for index,(name,model) in enumerate(ICONS):
  p=OUT/(name+'.png');im=Image.open(p).convert('RGBA');assert im.size==(128,128)
  alpha=im.getchannel('A');bounds=alpha.getbbox();assert bounds is not None
  # Leave a clear transparent border: no cropping and no solid backdrop.
  assert bounds[0]>=3 and bounds[1]>=3 and bounds[2]<=125 and bounds[3]<=125,(name,bounds)
  assert alpha.getextrema()==(0,255),(name,alpha.getextrema())
  assert all(alpha.getpixel(q)==0 for q in [(0,0),(127,0),(0,127),(127,127)])
  x=pad+index*cell
  for row in range(2):
   y=header+row*row_h
   pair=((255,246,223,255),(245,233,207,255)) if row==0 else ((28,44,65,255),(35,53,76,255))
   for yy in range(0,128,16):
    for xx in range(0,128,16):draw.rectangle((x+xx,y+yy,x+xx+15,y+yy+15),fill=pair[(xx//16+yy//16)%2])
   sheet.alpha_composite(im,(x,y))
   draw.text((x,y+133),name+'.png',font=font,fill=(24,39,61,255))
  checks.append({'filename':p.name,'actual_model':model,'size':[128,128],'mode':'RGBA','alpha_bounds_ltrb_exclusive':list(bounds),'fully_transparent_corners':True,'sha256':digest(p)})
 PROOF.mkdir(exist_ok=True);sheet.convert('RGB').save(PROOF/'module_icons_sheet.png')
 result={'result':'PASS','icon_count':7,'all_source_and_glb_hashes_unchanged':True,'proof':'source_art/modules_v4/proofs/module_icons_sheet.png','alpha_bounds_convention':'left, top, right-exclusive, bottom-exclusive; alpha > 0','icons':checks}
 (SRC/'icons_validation.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))

if __name__=='__main__':
 if '--proof-only' in sys.argv:proof_sheet()
 else:render_icons()
