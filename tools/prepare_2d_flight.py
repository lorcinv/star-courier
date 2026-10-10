#!/usr/bin/env python3
"""Extract user-requested imagegen details; preserve source, shared pixel palette."""
from pathlib import Path
import json,hashlib,importlib.util
import numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('study',R/'source_art/pixel_pipeline_studies/study_reference.py');s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
pal=json.loads((R/'source_art/pixel_pipeline_studies/palette_96.json').read_text())['colors'];pal=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in pal],dtype=np.uint8)
src=R/'source_art/2d_v5/flight/flight-sheet-v2.png';im=Image.open(src).convert('RGBA');out=R/'assets/2d_v5/flight';out.mkdir(parents=True,exist_ok=True)
records=[]
for name,region,target in [('rock-1',(0,0,512,590),(160,160)),('rock-2',(512,0,1024,590),(130,160)),('receiver',(1024,0,1536,590),(280,220)),('exhaust',(0,590,512,1024),(132,88)),('ignition',(512,590,1024,1024),(160,144))]:
 crop=im.crop(region);alpha=np.array(crop)[:,:,3];mask=Image.fromarray(np.where(alpha>=128,255,0).astype(np.uint8));bounds=mask.getbbox();cropped=crop.crop(bounds);native=R/'source_art/2d_v5/flight'/f'{name}-crop.png';cropped.save(native)
 ratio=min(target[0]/cropped.width,target[1]/cropped.height);size=(max(1,round(cropped.width*ratio)),max(1,round(cropped.height*ratio)))
 pixels=np.array(cropped.resize(size,Image.Resampling.NEAREST));a=np.where(pixels[:,:,3]>=128,255,0).astype(np.uint8);rgb=s.map_palette(pixels[:,:,:3],pal);rgb[a==0]=0
 dest=out/f'{name}.png';Image.fromarray(np.dstack([rgb,a]),'RGBA').save(dest)
 records.append({'id':name,'region':region,'source_alpha128_bounds':bounds,'runtime_dimensions':size,'runtime':str(dest.relative_to(R)),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'opaque_pixels':int(np.count_nonzero(a)),'alpha_values':np.unique(a).tolist()})
# Shared generated burst source also supplies the generic impact flash.
(out/'impact.png').write_bytes((out/'ignition.png').read_bytes())
manifest={'source':str(src.relative_to(R)),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'method':'Existing-pixel crops, nearest resample, fixed96-palette, binary alpha128. No painted pixels invented.','exhaust_direction':'points right; flip horizontally for rear exhaust','sprites':records}
(R/'source_art/2d_v5/flight/runtime-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest,indent=2))
