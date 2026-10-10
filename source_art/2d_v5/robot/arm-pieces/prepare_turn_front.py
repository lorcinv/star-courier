#!/usr/bin/env python3
"""Uniform nearest/palette/foot registration of the generated frontal pose."""
from pathlib import Path
from PIL import Image
import argparse,hashlib,importlib.util,json,numpy as np
parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[4]);parser.add_argument('--output',type=Path)
a=parser.parse_args();root=a.root.resolve();out=a.output or root/'assets/2d_v5/robot';out.mkdir(parents=True,exist_ok=True)
source=root/'source_art/2d_v5/robot/empty-hands/front-neutral-original.png'
spec=importlib.util.spec_from_file_location('pixel_study',root/'source_art/pixel_pipeline_studies/study_reference.py');study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
colors=json.loads((root/'source_art/pixel_pipeline_studies/palette_96.json').read_text())['colors'];palette=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in colors],dtype=np.uint8)
roi=(320,348,934,1030);anchor=(627,1026);scale=84.0/674.0
src=Image.open(source).convert('RGBA');crop=src.crop(roi);dims=(round(crop.width*scale/2),round(crop.height*scale/2));sample=crop.resize(dims,Image.Resampling.NEAREST)
canvas=Image.new('RGBA',(80,72));offset=(round(40+(roi[0]-anchor[0])*scale/2),round(68+(roi[1]-anchor[1])*scale/2));canvas.paste(sample,offset)
raw=np.array(canvas);rgb=study.map_palette(raw[:,:,:3],palette);alpha=np.where(raw[:,:,3]>=128,255,0).astype(np.uint8);rgb[alpha==0]=0
logical=Image.fromarray(np.dstack([rgb,alpha]),'RGBA');logical.save(out/'turn-front-logical.png');logical.resize((160,144),Image.Resampling.NEAREST).save(out/'turn-front.png')
record={'source':str(source.relative_to(root)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'method':'Whole-body uniform nearest resampling, shared96 palette, binary alpha128; middle wheel/floor registration. No face/body deformation, repainting, or Spine.','source_roi':roi,'source_body_foot_anchor':anchor,'visible_body_height':674,'target_body_height':84,'uniform_scale':scale,'runtime_anchor':[80,136],'runtime_size':[160,144],'runtime_sha256':hashlib.sha256((out/'turn-front.png').read_bytes()).hexdigest()}
(Path(__file__).resolve().parent/'turn-front-manifest.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2))
