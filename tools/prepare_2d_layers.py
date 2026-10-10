#!/usr/bin/env python3
"""Technical pixel-grid derivatives of imagegen originals; originals never change.
The common palette comes from the user-reviewed GitHub-informed pixel study.
No artwork or missing objects are drawn by this script.
"""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('pixel_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
palette_json=json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())
palette=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in palette_json['colors']],dtype=np.uint8)
out=ROOT/'assets/2d_v5/environment';out.mkdir(parents=True,exist_ok=True)
records=[]
for name in ['far-city','shop-shell']:
 source=ROOT/'source_art/2d_v5/generated'/f'{name}.png'; im=Image.open(source).convert('RGBA')
 nearest=np.array(im.resize((1280,720),Image.Resampling.NEAREST))
 rgb=study.map_palette(nearest[:,:,:3],palette)
 alpha=np.where(nearest[:,:,3]>=128,255,0).astype(np.uint8)
 rgb[alpha==0]=0
 dest=out/f'{name}.png';Image.fromarray(np.dstack([rgb,alpha]),'RGBA').save(dest)
 records.append({'name':name,'source':str(source.relative_to(ROOT)),'source_dimensions':list(im.size),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'runtime':str(dest.relative_to(ROOT)),'runtime_dimensions':[1280,720],'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'visible_pixels':int(np.count_nonzero(alpha)),'alpha_values':np.unique(alpha).tolist(),'rgb_colors':int(len(np.unique(rgb[alpha>0],axis=0)))})
manifest={'method':'Nearest1280x720; fixed reviewed96-color Oklab mapping; binary alpha threshold128; no procedural art','palette_source':'source_art/pixel_pipeline_studies/palette_96.json','assets':records}
(ROOT/'source_art/2d_v5/environment-derivatives.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(manifest,ensure_ascii=False,indent=2))
