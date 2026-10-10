#!/usr/bin/env python3
"""Rigid claw/joint and stretchable shaft from existing generated arm pixels.
No repainting, generated pixels, vector artwork, or filled geometry. Rotation is
nearest-neighbour technical registration; crops overlap under the rigid joints.
"""
from pathlib import Path
from math import hypot
from PIL import Image
import argparse, hashlib, json
parser=argparse.ArgumentParser()
parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[4])
parser.add_argument('--output',type=Path)
args=parser.parse_args();root=args.root.resolve();out=args.output or root/'assets/2d_v5/robot';out.mkdir(parents=True,exist_ok=True)
source=root/'assets/2d_v5/robot/lift-arm.png'
original=root/'source_art/2d_v5/robot/empty-hands/raised-gripper-original.png'
src=Image.open(source).convert('RGBA')
shoulder=(17.8,150.0);delta=(74.2,-126.6);length=hypot(*delta)
ux,uy=delta[0]/length,delta[1]/length;px,py=-uy,ux
matrix=(ux,px,shoulder[0]-20*ux-40*px,uy,py,shoulder[1]-20*uy-40*py)
aligned=src.transform((196,80),Image.Transform.AFFINE,matrix,resample=Image.Resampling.NEAREST)
records=[]
# The shaft excludes source circles; stretching only its mechanical tube never
# changes claw or shoulder dimensions. Ends overlap their fixed-size housings.
for name,roi,anchor in [('lift-shaft',(41,31,69,53),(0,9)),('lift-joint',(2,21,39,59),(18,19)),('lift-claw',(121,14,193,70),(20+length-121,26))]:
    part=aligned.crop(roi);path=out/(name+'.png');part.save(path)
    records.append({'name':name,'aligned_roi':roi,'anchor':anchor,'size':part.size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
manifest={'source':str(source.relative_to(root)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'preserved_imagegen_original':str(original.relative_to(root)),'original_sha256':hashlib.sha256(original.read_bytes()).hexdigest(),'method':'Affine nearest source-pixel registration then rectangular alpha-preserving crops. No painted pixels. Fixed 0.65 claw/joint scale, shaft length only; overlap under housings. No Spine.','aligned_canvas':[196,80],'inverse_affine':matrix,'source_shoulder':shoulder,'source_grip':[92,23.4],'aligned_grip':[20+length,40],'runtime_rigid_scale':.65,'pieces':records}
(Path(__file__).resolve().parent/'arm-pieces-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
