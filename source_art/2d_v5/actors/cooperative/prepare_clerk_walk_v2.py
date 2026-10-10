#!/usr/bin/env python3
"""Select/register imagegen walk drawings; never draws or deforms character art.
Merges only walk-specific manifest fields, preserving tablet gestures exactly.
"""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent; OUT=ROOT/'assets/2d_v5/actors/cooperative'
PALPATH=ROOT/'source_art/pixel_pipeline_studies/palette_96.json'
PAL=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in json.loads(PALPATH.read_text())['colors']],dtype=np.uint8)
spec=importlib.util.spec_from_file_location('pixel_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py'); study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
def rel(p):return str(p.relative_to(ROOT))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
# Deliberate anatomical order, not source sheet order. The broad sheet repeated
# its first-half leg lead; the explicit opposite-contact edit supplies that beat.
# Exact source pixels only: crop, uniform nearest sample, palette/alpha, translate.
FRAMES=[
 ('clerk-walk-v2-original.png',(125,11,448,497),(297,299),240/486,'contact','near'),
 ('clerk-walk-v2-original.png',(508,12,752,496),(627,303),240/486,'down','near'),
 ('clerk-walk-support-original.png',(193,59,728,949),(440,598),240/890,'passing','near'),
 ('clerk-walk-support-original.png',(845,67,1429,944),(1118,596),240/890,'up','near'),
 ('clerk-walk-opposite-original.png',(172,79,778,919),(450,592),240/840,'contact','far'),
 ('clerk-walk-opposite-original.png',(870,79,1340,919),(1110,597),240/840,'down','far'),
 ('clerk-walk-v2-original.png',(831,11,1070,496),(944,308),240/486,'passing','far'),
 ('clerk-walk-v2-original.png',(1120,12,1434,494),(1270,303),240/486,'up','far'),
]
def main():
 path=OUT/'motion-manifest.json'; manifest=json.loads(path.read_text()); gestures_before=json.dumps(manifest['actors']['clerk']['gestures'],sort_keys=True)
 walk=[]
 for i,(source,box,hip,scale,family,support) in enumerate(FRAMES):
  src=SRC/source;clip=Image.open(src).convert('RGBA').crop(box); size=(round(clip.width*scale),round(clip.height*scale))
  a=np.array(clip.resize(size,Image.Resampling.NEAREST));rgb=study.map_palette(a[:,:,:3],PAL);alpha=np.where(a[:,:,3]>=128,255,0).astype(np.uint8);rgb[alpha==0]=0
  px=round(96-(hip[0]-box[0])*scale);py=248-size[1];canvas=Image.new('RGBA',(208,256));canvas.alpha_composite(Image.fromarray(np.dstack([rgb,alpha]),'RGBA'),(px,py))
  p=OUT/f'clerk-walk-v2-{i:02d}-pixel.png';canvas.save(p)
  rootx=px+(hip[0]-box[0])*scale;bounds=canvas.getbbox();assert bounds[0]>0 and bounds[2]<208 and bounds[3]==248
  walk.append({'id':f'clerk-walk-v2-{i:02d}','runtime':rel(p),'sha256':sha(p),'dimensions':[208,256],'alpha_bounds':list(bounds),'foot_anchor':[rootx,248],'body_height':240,'hip_anchor':[rootx,py+(hip[1]-box[1])*scale],'facing':'right','contains_parcel':False,'source':rel(src),'source_sha256':sha(src),'source_bounds':list(box),'source_foot_anchor':[hip[0],box[3]],'source_hip_anchor':list(hip),'uniform_scale':scale,'sampling_size':list(size),'paste_offset':[px,py],'stance_family':family,'support_half':support})
 actor=manifest['actors']['clerk'];actor['walk']=walk;actor['walk_cycle_distance']=176;actor['walk_reference_height']=240;actor['walk_sequence']=list(range(8));actor['walk_phase_weights']=[1.15,0.95,0.9,1.0,1.15,0.95,0.9,1.0]
 manifest['animation_status']='Eight selected image-generated raster drawings include a newly corrected opposite-leg contact. Four gait silhouette families with two support halves; pose-to-pose artwork, not interpolated limbs or a Spine rig.'
 manifest['walk_registration_policy']='Whole-body uniform scale per generated source; pelvis-projected horizontal origin is also the measured hip X. Every painted support sole remains on the same floor. Cadence scales with displayed anatomical height; no body bob, opacity blend or skeletal deformation.'
 manifest['walk_sources']=[{'path':rel(SRC/s),'sha256':sha(SRC/s),'dimensions':list(Image.open(SRC/s).size)} for s in sorted(set(f[0] for f in FRAMES))]
 assert gestures_before==json.dumps(manifest['actors']['clerk']['gestures'],sort_keys=True)
 path.write_text(json.dumps(manifest,indent=2)+'\n')
 board=Image.new('RGBA',(208*8,300),'#172339');d=ImageDraw.Draw(board)
 for i,r in enumerate(walk):
  board.alpha_composite(Image.open(ROOT/r['runtime']),(208*i,8));d.line((208*i,256,208*(i+1),256),fill='#567181');d.text((208*i+6,270),f"{i} {r['stance_family']} {r['support_half']}",fill='white')
 board.convert('RGB').save(SRC/'clerk-walk-v2-review.png')
 print('Selected and registered 8 walk drawings; existing gestures preserved byte-for-byte in value.')
if __name__=='__main__':main()
