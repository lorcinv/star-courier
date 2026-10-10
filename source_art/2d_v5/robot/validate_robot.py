#!/usr/bin/env python3
"""Validate unchanged source, registration, palette, alpha and grid derivatives."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
m=json.loads((HERE/'derivatives.json').read_text())
assert hashlib.sha256((ROOT/m['source']).read_bytes()).hexdigest()==m['source_sha256']
palette=set(json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())['colors'])
idle=np.array(Image.open(ROOT/'assets/2d_v5/robot/idle.png'))[100:136,46:112,3]>0
rows=[]
for pose in m['poses']:
 name=pose['name'];runtime=Image.open(ROOT/f'assets/2d_v5/robot/{name}.png').convert('RGBA');logical=Image.open(ROOT/f'assets/2d_v5/robot/{name}-logical.png').convert('RGBA')
 pixels=np.array(runtime);assert runtime.size==(160,144) and logical.size==(80,72)
 assert pose['runtime_anchor']==[80,136]
 assert np.array_equal(pixels,np.array(logical.resize((160,144),Image.Resampling.NEAREST)))
 assert set(np.unique(pixels[:,:,3]).tolist())=={0,255}
 colors=set('#%02x%02x%02x'%tuple(c) for c in np.unique(pixels[:,:,:3][pixels[:,:,3]>0],axis=0))
 assert colors<=set(c.lower() for c in palette)
 assert runtime.getbbox()[3]==136
 chassis=pixels[100:136,46:112,3]>0
 overlap=float((idle&chassis).sum()/(idle|chassis).sum());assert overlap>=.85
 assert hashlib.sha256((ROOT/f'assets/2d_v5/robot/{name}.png').read_bytes()).hexdigest()==pose['sha256']
 rows.append({'pose':name,'binary_alpha':True,'palette_colors':len(colors),'runtime_dimensions':runtime.size,'foot_y':136,'registered_chassis_iou_vs_idle':round(overlap,4),'nearest2x':True})
report={'source_preserved':True,'poses':rows,'all_passed':True}
(HERE/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
