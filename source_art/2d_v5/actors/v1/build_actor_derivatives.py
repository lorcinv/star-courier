"""Lossless source preservation; explicit grid/palette/alpha runtime cleanup only.
Rebuild from image-generation originals. Does not synthesize any actor artwork.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np
import json, hashlib

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
OUT=ROOT/'assets/2d_v5/actors'
OUT.mkdir(parents=True,exist_ok=True)
PALETTE_PATH=ROOT/'source_art/pixel_pipeline_studies/palette_96.json'
palette_doc=json.loads(PALETTE_PATH.read_text())
palette=np.array([tuple(bytes.fromhex(c[1:])) for c in palette_doc['colors']],dtype=np.int32)

SPECS={
 'clerk': {
  'facing':'left', 'original_foot':[637,1210],
  'source_hands':{'idle':{'left':[350,764],'right':[697,792],'parcel':[385,721]},'handoff':{'left':[332,711],'right':[538,732],'parcel':[415,668]}},
  'generation_files':{'idle':'exec-35f13f6f-bbf4-43a6-837e-e66aa784cc0a.png','handoff':'exec-6a5eceb2-0c12-4555-a7b2-bb357e816b1c.png'},
  'foot_scene_suggestion':[276,486], 'scene_body_height':210,
 },
 'customer': {
  'facing':'right', 'original_foot':[641,1184],
  'source_hands':{'idle':{'left':[778,705],'right':[885,691],'parcel':[843,650]},'handoff':{'left':[863,677],'right':[966,611],'parcel':[909,571]}},
  'generation_files':{'idle':'exec-3aa11744-fd2f-445d-b0a8-ed0545dc64c2.png','handoff':'exec-d6f1261e-ba8e-49a3-9ca7-665bfd947d66.png'},
  'foot_scene_suggestion':[148,488], 'scene_body_height':215,
 },
}

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def bounds_union(bs):return [min(b[0] for b in bs),min(b[1] for b in bs),max(b[2] for b in bs),max(b[3] for b in bs)]
def quantize(rgb):
 arr=np.asarray(rgb.convert('RGB'),dtype=np.int32)
 flat=arr.reshape(-1,3)
 result=np.empty(flat.shape,dtype=np.uint8)
 for i in range(0,len(flat),2048):
  d=((flat[i:i+2048,None,:]-palette[None,:,:])**2).sum(axis=2)
  result[i:i+2048]=palette[d.argmin(axis=1)]
 return Image.fromarray(result.reshape(arr.shape),'RGB')

def transform_xy(pt,union,size):
 return [round(8+(pt[0]-union[0])*size[0]/(union[2]-union[0]),2),round(8+(pt[1]-union[1])*size[1]/(union[3]-union[1]),2)]

manifest={
 'asset_type':'2D image-generated raster actors',
 'tool':'built-in image_gen.imagegen; transparent_background=true',
 'source_reference':'source_art/art_direction_v4/pixel-cel-shop-reference-03.png',
 'source_reference_sha256':sha(ROOT/'source_art/art_direction_v4/pixel-cel-shop-reference-03.png'),
 'palette':str(PALETTE_PATH.relative_to(ROOT)), 'palette_sha256':sha(PALETTE_PATH),
 'source_policy':'Every original image-generation output is preserved byte-for-byte. Generated images contain low-alpha distant speckle and mostly alpha253 interior pixels. Runtime copies use threshold128 binary alpha, nearest source sampling and palette matching only.',
 'animation_status':'Two independently image-generated, visually matched whole-sprite poses per actor. These are not Spine files, not a Spine rig, and not a claim of actual Spine binding. Full skeletal layering would require separate authoring and QA.',
 'rendering':'Nearest-neighbor filtering; integer scaling when possible; do not use linear filtering or mipmaps. Position the supplied foot_anchor at the scene floor point. Hand anchors are manually estimated interaction guides, not anatomical rig pivots.',
 'actors':{}
}
preview=Image.new('RGB',(760,610),'#253858');draw=ImageDraw.Draw(preview)
for row,(actor,spec) in enumerate(SPECS.items()):
 ims={pose:Image.open(HERE/f'{actor}-{pose}-original.png').convert('RGBA') for pose in ['idle','handoff']}
 masks={p:i.getchannel('A').point(lambda a:255 if a>=128 else 0) for p,i in ims.items()}
 union=bounds_union([a.getbbox() for a in masks.values()])
 size=(round((union[2]-union[0])*240/(union[3]-union[1])),240)
 canvas_size=(size[0]+16,256)
 foot=transform_xy(spec['original_foot'],union,size)
 actor_doc={
  'facing':spec['facing'],'common_source_union':union,'shared_canvas':canvas_size,
  'foot_anchor':foot,'body_height':240,
  'placement_suggestion':{'scene':'1280x720','foot_position':spec['foot_scene_suggestion'],'body_height':spec['scene_body_height'],'scale_from_logical_body':spec['scene_body_height']/240},
  'poses':{}
 }
 for col,(pose,im) in enumerate(ims.items()):
  rawp=HERE/f'{actor}-{pose}-original.png';alpha=im.getchannel('A'); hist=alpha.histogram()
  clean=im.copy();clean.putalpha(masks[pose]); cropped=clean.crop(tuple(union));small=cropped.resize(size,Image.Resampling.NEAREST)
  quant=quantize(small);quant.putalpha(small.getchannel('A'))
  canvas=Image.new('RGBA',canvas_size);canvas.alpha_composite(quant,(8,8))
  runtime=OUT/f'{actor}-{pose}-pixel.png';canvas.save(runtime)
  native_union=(union[0]-12,union[1]-12,union[2]+12,union[3]+12)
  native=clean.crop(native_union);native.save(OUT/f'{actor}-{pose}-native.png')
  rgba=np.asarray(canvas);opaque=rgba[:,:,3]>0;colors={tuple(c) for c in rgba[opaque][:,:3]}
  hand={k:transform_xy(v,union,size) for k,v in spec['source_hands'][pose].items()}
  actor_doc['poses'][pose]={
   'original':str(rawp.relative_to(ROOT)), 'original_sha256':sha(rawp),'generation_output_filename':spec['generation_files'][pose],
   'prompt':str((HERE/f'{actor}-{pose}.prompt.txt').relative_to(ROOT)),
   'original_dimensions':im.size,'original_alpha_bounds_gt0':alpha.getbbox(),'original_alpha_bounds_ge128':masks[pose].getbbox(),
   'original_alpha_counts':{'zero':hist[0],'partial':sum(hist[1:255]),'opaque':hist[255]},
   'native_derivative':str((OUT/f'{actor}-{pose}-native.png').relative_to(ROOT)), 'native_dimensions':native.size, 'native_foot_anchor':[spec['original_foot'][0]-native_union[0],spec['original_foot'][1]-native_union[1]],
   'runtime':str(runtime.relative_to(ROOT)),'runtime_sha256':sha(runtime),'runtime_dimensions':canvas.size,'runtime_alpha_bounds':canvas.getchannel('A').getbbox(),
   'runtime_alpha_values':sorted(set(canvas.getchannel('A').getdata())), 'runtime_palette_used':len(colors),'runtime_all_colors_in_shared_palette':colors.issubset({tuple(c) for c in palette}),
   'foot_anchor':foot,'hand_and_parcel_anchors':hand,
  }
  x=95+col*335;y=25+row*296
  preview.paste(canvas,(x,y),canvas)
  draw.text((x,y+261),f'{actor} {pose}  {canvas.size[0]}x{canvas.size[1]}',fill='#fff0cd')
  draw.line((x+foot[0]-5,y+foot[1],x+foot[0]+5,y+foot[1]),fill='#48dcff')
  draw.line((x+foot[0],y+foot[1]-5,x+foot[0],y+foot[1]+5),fill='#48dcff')
 manifest['actors'][actor]=actor_doc
preview.save(HERE/'actors-pixel-contact-sheet.png')
(HERE/'actor-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(OUT/'actor-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({actor:{'shared_canvas':data['shared_canvas'],'foot_anchor':data['foot_anchor'],'poses':{p:{'file':v['runtime'],'bounds':v['runtime_alpha_bounds'],'hands':v['hand_and_parcel_anchors'],'palette_colors':v['runtime_palette_used']}for p,v in data['poses'].items()}}for actor,data in manifest['actors'].items()},indent=2))
