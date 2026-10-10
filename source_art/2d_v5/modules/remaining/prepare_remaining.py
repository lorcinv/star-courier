#!/usr/bin/env python3
"""Technical crop/palette/alpha derivatives only; never draws module art."""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import label
ROOT=Path(__file__).resolve().parents[4]
SRC=ROOT/'source_art/2d_v5/modules/remaining'
OUT=ROOT/'assets/2d_v5/modules'
spec=importlib.util.spec_from_file_location('pixel_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
palette_json=json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())
palette=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in palette_json['colors']],dtype=np.uint8)
IDS=['valve','rotator','damper','lance','accelerator','arc','bomb','shield','decoy','shrink','enlarge','teleporter','splitter','probe','collision','delay','and_gate','or_gate','not_gate']
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
records=[]
for id in IDS:
 p=SRC/'originals'/f'{id}-original.png'
 if not p.exists(): continue
 im=Image.open(p).convert('RGBA'); a=np.array(im)
 threshold=a[:,:,3]>=128
 ys,xs=np.where(threshold)
 box=[int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)]
 crop=im.crop(box); crop_path=SRC/'crops'/f'{id}-crop.png'; crop.save(crop_path)
 nearest=np.array(crop.resize((72,72),Image.Resampling.NEAREST))
 rgb=study.map_palette(nearest[:,:,:3],palette)
 mask=nearest[:,:,3]>=128
 labels,count=label(mask,structure=np.ones((3,3)))
 sizes=np.bincount(labels.ravel()); sizes[0]=0
 main=int(sizes.argmax()); removed=int(mask.sum()-sizes[main])
 # Only detached sampling fringe is removed. No contour or interior pixels are painted.
 mask=labels==main
 alpha=np.where(mask,255,0).astype(np.uint8); rgb[~mask]=0
 dest=OUT/f'{id}-pixel.png'; Image.fromarray(np.dstack([rgb,alpha]),'RGBA').save(dest)
 palette_set={tuple(c) for c in palette.tolist()}
 actual={tuple(c) for c in rgb[mask].tolist()}
 assert actual<=palette_set
 records.append({'id':id,'original':str(p.relative_to(ROOT)),'original_dimensions':list(im.size),'original_sha256':sha(p),'source_crop':str(crop_path.relative_to(ROOT)),'source_crop_xyxy':box,'source_crop_sha256':sha(crop_path),'runtime':str(dest.relative_to(ROOT)),'runtime_dimensions':[72,72],'sha256':sha(dest),'visible_pixels':int(mask.sum()),'alpha_values':np.unique(alpha).tolist(),'visible_palette_color_count':len(actual),'palette_outliers':0,'connected_components':1,'detached_sampling_fringe_pixels_removed':removed,'anchor_center':[36,36],'suggested_cardinal_sockets':{'left':[0,36],'right':[72,36],'top':[36,0],'bottom':[36,72]}})
manifest={'generator':'built-in image_gen','references':['source_art/art_direction_v4/pixel-cel-shop-reference-03.png','source_art/2d_v5/modules/courier-kit-atlas-original.png'],'palette_source':'source_art/pixel_pipeline_studies/palette_96.json','runtime_derivative_method':'Lossless rectangular crop to source alpha>=128 bounds, nearest-neighbor cell-fill normalization to72x72; fixed reviewed96-color Oklab mapping, no dithering; binary alpha threshold128; remove only disconnected sampling fringe; zero transparent RGB. No artwork drawn by code.','parts':records,'expected_ids':IDS,'remaining_ids':[id for id in IDS if id not in {r['id'] for r in records}]}
(SRC/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(SRC/'pixel-validation.json').write_text(json.dumps({'count':len(records),'expected_count':19,'all_72_square':all(r['runtime_dimensions']==[72,72] for r in records),'all_binary_alpha':all(r['alpha_values']==[0,255] for r in records),'all_fixed_palette':all(r['palette_outliers']==0 for r in records),'all_single_connected_component':all(r['connected_components']==1 for r in records),'total_detached_fringe_pixels_removed':sum(r['detached_sampling_fringe_pixels_removed'] for r in records),'assets':records},ensure_ascii=False,indent=2)+'\n')
cols=5; rows=(len(records)+cols-1)//cols
sheet=Image.new('RGBA',(cols*110,rows*106),(16,24,47,255)); draw=ImageDraw.Draw(sheet)
for i,r in enumerate(records):
 x=(i%cols)*110; y=(i//cols)*106
 spr=Image.open(ROOT/r['runtime']).convert('RGBA'); sheet.alpha_composite(spr,(x+19,y+8));draw.text((x+5,y+85),r['id'],fill=(255,222,135,255))
sheet.save(SRC/'proofsheet-native.png');sheet.resize((sheet.width*4,sheet.height*4),Image.Resampling.NEAREST).save(SRC/'proofsheet-4x.png')
print(json.dumps({'count':len(records),'ids':[r['id'] for r in records],'fringe_removed':{r['id']:r['detached_sampling_fringe_pixels_removed'] for r in records}}))
