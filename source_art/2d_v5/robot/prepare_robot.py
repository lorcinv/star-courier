#!/usr/bin/env python3
"""Registered nearest/palette derivatives of the unmodified generated robot sheet.
ROIs isolate authored poses, never independently center their alpha bounds.
A manually matched middle-axle/ground registration preserves the body position
when a parcel, gripper, or alert mark changes the silhouette.
"""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image
ROOT = Path(__file__).resolve().parents[3]
SRC = Path(__file__).with_name('cargo-robot-six-poses.png')
OUT = ROOT/'assets/2d_v5/robot'
OUT.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('pixel_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
palette_json=json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())
palette=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in palette_json['colors']],dtype=np.uint8)
# The fifth pose's raised gripper crosses the nominal 512px cell boundary.
# Explicit authored-pose ROIs retain it while excluding its right-hand neighbour.
POSES = [
 ('idle', (75,100,448,453), (293,447)),
 ('carry-parcel', (552,100,961,453), (772,447)),
 ('offer-parcel', (1027,100,1510,453), (1251,447)),
 ('carry-part', (75,532,452,968), (293,963)),
 ('offer-part', (544,555,1087,968), (772,963)),
 ('alert', (1090,601,1500,968), (1303,962)),
]
source=Image.open(SRC).convert('RGBA')
records=[]
for name,roi,anchor in POSES:
 registered=Image.new('RGBA',(640,576))
 registered.paste(source.crop(roi),(320+roi[0]-anchor[0],544+roi[1]-anchor[1]))
 sampled=np.array(registered.resize((80,72),Image.Resampling.NEAREST))
 rgb=study.map_palette(sampled[:,:,:3],palette)
 alpha=np.where(sampled[:,:,3]>=128,255,0).astype(np.uint8)
 rgb[alpha==0]=0
 logical=Image.fromarray(np.dstack([rgb,alpha]),'RGBA')
 logical.save(OUT/f'{name}-logical.png')
 runtime=logical.resize((160,144),Image.Resampling.NEAREST)
 runtime.save(OUT/f'{name}.png')
 records.append({'name':name,'source_roi':roi,'source_body_foot_anchor':anchor,
  'logical_dimensions':[80,72],'logical_anchor':[40,68],'runtime_dimensions':[160,144],
  'runtime_anchor':[80,136],'visible_alpha_bbox':runtime.getbbox(),
  'alpha_values':np.unique(alpha).tolist(),'rgb_colors':len(np.unique(rgb[alpha>0],axis=0)),
  'sha256':hashlib.sha256((OUT/f'{name}.png').read_bytes()).hexdigest()})
manifest={'source':str(SRC.relative_to(ROOT)),'source_sha256':hashlib.sha256(SRC.read_bytes()).hexdigest(),
 'method':'Manual middle-wheel/body + floor registration; nearest to 80x72; shared96-color Oklab; binary alpha128; nearest2x runtime. No repainted/procedural artwork.',
 'source_spine':False,'runtime_anchor':[80,136],'canvas_size':[160,144],'poses':records}
(Path(__file__).with_name('derivatives.json')).write_text(json.dumps(manifest,indent=2)+'\n')
# Technical compositing proof at the unchanged hub screenshot's 1.5x canvas scale.
proof_path=ROOT/'docs/qa/v4/v5-first-2d/runtime-01-hub.png'
if proof_path.exists():
 proof=Image.open(proof_path).convert('RGBA')
 robot=Image.open(OUT/'idle.png')
 size=tuple(round(v*proof.width/1280) for v in robot.size)
 robot=robot.resize(size,Image.Resampling.NEAREST)
 x,y=round((516-80)*proof.width/1280),round((486-136)*proof.height/720)
 proof.alpha_composite(robot,(x,y))
 proof.save(Path(__file__).with_name('hub-robot-composite-proof.png'))
print(json.dumps(manifest,indent=2))
