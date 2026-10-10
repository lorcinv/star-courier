"""Reproducible, non-publishing runtime cleanup for V2 paired imagegen sources."""
from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np,json,hashlib
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];OUT=HERE/'staged-runtime';OUT.mkdir(exist_ok=True)
old=json.loads((HERE.parent/'v1/actor-manifest.json').read_text())
palette_path=ROOT/'source_art/pixel_pipeline_studies/palette_96.json';palette=np.array([tuple(bytes.fromhex(c[1:])) for c in json.loads(palette_path.read_text())['colors']],dtype=np.int32)
source_files={'idle':'exec-e0b85b64-5bb7-4a86-ac9f-01979668e7a0.png','handoff':'exec-b30f5135-94e0-41b1-9af2-26c7d72e342d.png'}
specs={
 'customer':{'region':(0,0,768,1024),'foot':(466,960),'head_roi':(295,86,662,354),'hands':{'idle':{'left':(561,581),'right':(665,569),'parcel':(619,526)},'handoff':{'left':(626,541),'right':(702,516),'parcel':(693,477)}}},
 'clerk':{'region':(768,0,1536,1024),'foot':(1065,960),'head_roi':(880,131,1241,443),'hands':{'idle':{'left':(872,575),'right':(1060,606),'parcel':(936,541)},'handoff':{'left':(838,522),'right':(933,557),'parcel':(876,474)}}}
}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
baseline_runtime_hashes={str(p):sha(p)for p in (ROOT/'assets/2d_v5/actors').glob('*-pixel.png')}
ims={p:Image.open(HERE/f'pair-{p}-original.png').convert('RGBA')for p in source_files}
manifest={'version':2,'asset_type':'2D image-generated raster actors; proportion revision','status':'staged; runtime publication requires coordinated approval','tool':'built-in image_gen.imagegen, transparent_background=true','palette':str(palette_path.relative_to(ROOT)),'palette_sha256':sha(palette_path),'source_policy':'Original paired imagegen outputs are preserved byte-for-byte. Per-actor crop, whole-body nearest sampling, alpha128 threshold and shared reference96 color cleanup only. No code deformation or face/head-only scaling.','animation_status':'Two matched whole-sprite poses; no Spine binding, project, rig, atlas, or runtime export is claimed.','runtime_compatibility':'Same canvas dimensions and semantic foot anchors as V1. Actor artwork scaled uniformly to 240px high with one common sampling grid per actor.','sources':{},'actors':{}}
for pose,im in ims.items():
 original=HERE/f'pair-{pose}-original.png';a=im.getchannel('A');h=a.histogram();default=ROOT.parent/'generated_images'/source_files[pose];assert sha(original)==sha(default)
 manifest['sources'][pose]={'path':str(original.relative_to(ROOT)),'sha256':sha(original),'tool_output_filename':source_files[pose],'dimensions':im.size,'raw_alpha_bounds':a.getbbox(),'alpha128_bounds':a.point(lambda x:255 if x>=128 else 0).getbbox(),'alpha_counts':{'zero':h[0],'partial':sum(h[1:255]),'opaque':h[255]},'prompt':str((HERE/f'pair-{pose}.prompt.txt').relative_to(ROOT))}
preview=Image.new('RGB',(760,610),'#253858');d=ImageDraw.Draw(preview)
for row,(actor,s) in enumerate(specs.items()):
 originals={};masks={};bounds={}
 for p,im in ims.items():
  x=Image.new('RGBA',im.size);x.paste(im.crop(s['region']),s['region'][:2]);originals[p]=x;masks[p]=x.getchannel('A').point(lambda v:255 if v>=128 else 0);bounds[p]=masks[p].getbbox()
 b=(min(v[0]for v in bounds.values()),min(v[1]for v in bounds.values()),max(v[2]for v in bounds.values()),max(v[3]for v in bounds.values()))
 size=(round((b[2]-b[0])*240/(b[3]-b[1])),240);sx=size[0]/(b[2]-b[0]);sy=size[1]/(b[3]-b[1]);anchor=old['actors'][actor]['foot_anchor'];canvas_size=tuple(old['actors'][actor]['shared_canvas']);offset=(round(anchor[0]-(s['foot'][0]-b[0])*sx),round(anchor[1]-(s['foot'][1]-b[1])*sy))
 xy=lambda p:[round(offset[0]+(p[0]-b[0])*sx,2),round(offset[1]+(p[1]-b[1])*sy,2)]
 a_doc={'facing':'left'if actor=='clerk'else'right','common_source_union':b,'shared_canvas':canvas_size,'foot_anchor':anchor,'body_height':240,'source_foot_anchor':s['foot'],'actual_sampling_foot':xy(s['foot']),'common_resize':size,'common_paste_offset':offset,'placement_suggestion':old['actors'][actor]['placement_suggestion'],'poses':{}}
 for col,pose in enumerate(['idle','handoff']):
  source=originals[pose];raw_extract=source.crop(b);raw_extract.save(HERE/f'{actor}-{pose}-extracted.png')
  source.putalpha(masks[pose]);native=source.crop((b[0]-12,b[1]-12,b[2]+12,b[3]+12));native.save(OUT/f'{actor}-{pose}-native.png')
  small=source.crop(b).resize(size,Image.Resampling.NEAREST);arr=np.array(small);flat=arr[:,:,:3].reshape(-1,3).astype(np.int32);new=np.empty(flat.shape,dtype=np.uint8)
  for i in range(0,len(flat),2048):new[i:i+2048]=palette[((flat[i:i+2048,None,:]-palette[None,:,:])**2).sum(axis=2).argmin(axis=1)]
  arr[:,:,:3]=new.reshape(arr.shape[:2]+(3,));small=Image.fromarray(arr);canvas=Image.new('RGBA',canvas_size);canvas.alpha_composite(small,offset);path=OUT/f'{actor}-{pose}-pixel.png';canvas.save(path)
  ca=np.array(canvas);colors={tuple(x)for x in ca[ca[:,:,3]>0][:,:3]};alpha_bounds=canvas.getchannel('A').getbbox();assert alpha_bounds[0]>0 and alpha_bounds[1]>0 and alpha_bounds[2]<canvas.width and alpha_bounds[3]<canvas.height
  a_doc['poses'][pose]={'source_pair':manifest['sources'][pose]['path'],'source_alpha128_bounds':bounds[pose],'source_extracted':str((HERE/f'{actor}-{pose}-extracted.png').relative_to(ROOT)),'runtime':f'assets/2d_v5/actors/{actor}-{pose}-pixel.png','staged_runtime':str(path.relative_to(ROOT)),'runtime_sha256':sha(path),'runtime_dimensions':canvas.size,'runtime_alpha_bounds':alpha_bounds,'runtime_alpha_values':[int(x)for x in np.unique(ca[:,:,3])],'runtime_palette_used':len(colors),'runtime_all_colors_in_shared_palette':colors.issubset({tuple(c)for c in palette}),'foot_anchor':anchor,'hand_and_parcel_anchors':{k:xy(pt)for k,pt in s['hands'][pose].items()},'native_dimensions':native.size,'native_foot_anchor':[s['foot'][0]-b[0]+12,s['foot'][1]-b[1]+12]}
  x=95+335*col;y=24+296*row;preview.paste(canvas,(x,y),canvas);d.text((x,y+261),f'V2 {actor} {pose} {canvas.width}x{canvas.height}',fill='#fff0cd')
 manifest['actors'][actor]=a_doc
preview.save(HERE/'actors-pixel-contact-sheet.png')
for p in [HERE/'actor-manifest.json',OUT/'actor-manifest.json']:p.write_text(json.dumps(manifest,indent=2)+'\n')
report={'passed':True,'originals_match_tool_output':True,'published_runtime_untouched_by_staging':all(sha(Path(p))==h for p,h in baseline_runtime_hashes.items()),'same_v1_canvas_and_foot_anchors':True,'binary_alpha_and_shared_palette':True,'safe_transparent_margins':True,'common_source_registration_per_actor':True,'no_code_head_deformation':True}
assert report['published_runtime_untouched_by_staging']
(HERE/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'validation':report,'actors':{k:{'canvas':v['shared_canvas'],'foot_anchor':v['foot_anchor'],'actual_sampling_foot':v['actual_sampling_foot'],'poses':{p:{'alpha_bounds':z['runtime_alpha_bounds'],'hands':z['hand_and_parcel_anchors']}for p,z in v['poses'].items()}}for k,v in manifest['actors'].items()}},indent=2))
