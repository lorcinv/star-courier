#!/usr/bin/env python3
"""Register pre-reviewed imagegen-derived raster cutout samples; keep tablet intact."""
from pathlib import Path
import json,hashlib,importlib.util
import numpy as np
from PIL import Image,ImageDraw
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=ROOT/'assets/2d_v5/actors/locomotion_v2';OUT.mkdir(parents=True,exist_ok=True)
PALPATH=ROOT/'source_art/pixel_pipeline_studies/palette_96.json'
PAL=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in json.loads(PALPATH.read_text())['colors']],dtype=np.uint8)
spec=importlib.util.spec_from_file_location('palette_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py');study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
NORM=240/234

def rel(p):return str(p.relative_to(ROOT))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def reg(p):return [144+(p[0]-120)*NORM,280+(p[1]-257)*NORM]
def main():
 path=ROOT/'assets/2d_v5/actors/cooperative/motion-manifest.json';manifest=json.loads(path.read_text());actor=manifest['actors']['clerk'];tablet=json.dumps(actor['gestures'],sort_keys=True)
 for kind in ['walk','run']:
  source=HERE/f'clerk-{kind}-original.png';records=[];samples=json.loads((HERE/'prototype'/f'{kind}-metadata.json').read_text())
  for i,m in enumerate(samples):
   im=Image.open(HERE/'prototype'/f'{kind}-{i:02d}.png').convert('RGBA')
   # One exact similarity transform for the entire finished sample, identical
   # across both cycles. No width normalization or separate face scaling.
   a=np.array(im.transform((288,288),Image.Transform.AFFINE,(1/NORM,0,120-144/NORM,0,1/NORM,257-280/NORM),Image.Resampling.NEAREST))
   alpha=np.where(a[:,:,3]>=128,255,0).astype(np.uint8);rgb=study.map_palette(a[:,:,:3],PAL);rgb[alpha==0]=0
   out=Image.fromarray(np.dstack([rgb,alpha]),'RGBA');p=OUT/f'clerk-{kind}-rig-{i:02d}-pixel.png';out.save(p)
   feet=[{'id':side,'point':[reg(v['sole'])[0],280],'grounded':True} for side,v in m['feet'].items() if v['grounded']]
   r={'id':f'clerk-{kind}-rig-{i:02d}','runtime':rel(p),'sha256':sha(p),'dimensions':[288,288],'alpha_bounds':list(out.getbbox()),'foot_anchor':[144,280],'hip_anchor':reg(m['hip']),'body_height':240,'facing':'right','contains_parcel':False,'source':rel(source),'source_sha256':sha(source),'uniform_scale':(240/485)*NORM,'source_parts':['clerk-walk-original.png',f'clerk-{kind}-original.png'],'raster_assembly':'Original generated torso and limb cutouts; per-leg measured 2D joint rotations; one uniform final sample scale. No new painted pixels.','stance_family':(['contact','down','passing','up'] if kind=='walk' else ['contact','compression','toe_off','flight'])[int(m['phase']*8)%4],'support_half':'near' if m['phase']<.5 else 'far','distance_phase':m['phase'],'support_feet':feet,'foot_lock':bool(feet),'flight':not bool(feet),'source_joints':m['joints']}
   records.append(r)
  actor[kind]=records;actor[kind+'_cycle_distance']=(132 if kind=='walk' else 208)*NORM;actor[kind+'_reference_height']=240;actor[kind+'_sequence']=list(range(32));actor[kind+'_phase_weights']=[1.0]*32
 actor['idle_facing']='left';actor['locomotion_raster_samples_per_cycle']=32;actor['locomotion_original_drawings_used']=2
 actor['stance_contract']={'walk_support_intervals':[[0,.625],[.5,1.0],[0,.125]],'run_support_intervals':[[0,.375],[.5,.875]],'run_flight_intervals':[[.375,.5],[.875,1.0]],'phase_input':'actual cumulative absolute world distance','residual_compensation':'Only raster pixels below the pelvis shift; semantic supporting sole cancels caller displacement between adjacent samples. Sprite position is never changed.','turn_behavior':'Mirroring replants current support without retaining an old-world-space anchor. No direction-history spring or delayed correction.'}
 manifest['version']=2
 manifest['animation_status']='Two original imagegen full-character sources are segmented into fixed torso/limb raster cutouts. Each gait has32 distinct assembled raster samples, not32 new imagegen drawings. Run has separate forward-leaning torso, stronger leg recovery and25% airborne samples. Pure2D custom cutout animation, not Spine.'
 manifest['walk_registration_policy']='Exact generated raster parts, measured per-leg joints, stable undeformed head/torso, one uniform final scale and a shared floor. Distance-driven lower-body-only residual compensation locks supporting feet without moving actor nodes.'
 manifest['provenance']='Original built-in imagegen PNGs are preserved. Derivatives use alpha masking/cropping, 2D rigid raster-part transforms, common nearest-neighbor sampling, shared96 palette and bounded stance-only shader sampling. No code-painted character art, SVG or3D.'
 manifest['locomotion_sources']=[{'path':rel(HERE/f'clerk-{k}-original.png'),'sha256':sha(HERE/f'clerk-{k}-original.png')} for k in ['walk','run']]
 assert tablet==json.dumps(actor['gestures'],sort_keys=True),'Tablet records changed'
 path.write_text(json.dumps(manifest,indent=2)+'\n')
 (HERE/'runtime-registration.json').write_text(json.dumps({'uniform_final_scale':NORM,'walk_stride_240':actor['walk_cycle_distance'],'run_stride_240':actor['run_cycle_distance'],'sample_count_each':32,'painted_source_count':2,'tablet_unchanged':True},indent=2)+'\n')
 print('Registered32 walk +32 run raster samples; tablet unchanged.')
if __name__=='__main__':main()
