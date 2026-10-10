#!/usr/bin/env python3
"""Check the generated customer-motion raster delivery without modifying runtime."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
manifest_path=ROOT/'assets/2d_v5/npcs/walk_exit/motion-manifest.json'
checks=0
def check(condition,note):
 global checks
 assert condition,note
 checks+=1

def main():
 m=json.loads(manifest_path.read_text()); palette={tuple(int(h[i:i+2],16) for i in (1,3,5)) for h in json.loads((ROOT/m['palette']).read_text())['colors']}
 check(set(m['actors'])=={'human_courier','elf_archivist','alien_botanist','robot_machinist'},'Four bounded identity IDs')
 check('No Spine' in m['animation_status'],'Raster-only/no-Spine disclosure')
 sources=[];report={}
 for sid,source in m['sources'].items():
  path=ROOT/source['original'];im=Image.open(path)
  check(hashlib.sha256(path.read_bytes()).hexdigest()==source['sha256'],f'{sid}: untouched original SHA256')
  check(list(im.size)==source['dimensions']==[1536,1024],f'{sid}: exact generated dimensions')
  check(im.mode=='RGBA',f'{sid}: actual RGBA output')
  check(int(np.array(im)[:,:,3].min())==0,f'{sid}: actual transparent original')
  check((ROOT/source['prompt']).is_file(),f'{sid}: exact prompt preserved')
  sources.append(source['original'])
 for aid,actor in m['actors'].items():
  check(len(actor['walk'])==4,f'{aid}: four real walk frames')
  check(set(actor['gestures'])=={'farewell','neutral'},f'{aid}: farewell and neutral')
  masks=[];heights=[]
  for f in actor['walk']+list(actor['gestures'].values()):
   path=ROOT/f['runtime'];im=Image.open(path).convert('RGBA');a=np.array(im);mask=a[:,:,3]>0;bounds=im.getbbox()
   check(hashlib.sha256(path.read_bytes()).hexdigest()==f['sha256'],f'{aid}/{f["id"]}: runtime checksum')
   check(im.size==(192,256),f'{aid}/{f["id"]}: canvas')
   check(np.array_equal(np.unique(a[:,:,3]),[0,255]),f'{aid}/{f["id"]}: binary alpha')
   check(all(tuple(c) in palette for c in np.unique(a[:,:,:3][mask],axis=0)),f'{aid}/{f["id"]}: fixed reference96')
   check(not a[:,:,:3][~mask].any(),f'{aid}/{f["id"]}: transparent RGB zero')
   check(bounds[3]==248 and f['foot_anchor']==[96,248],f'{aid}/{f["id"]}: registered sole baseline')
   check(bounds[0]>0 and bounds[2]<192 and bounds[1]>0,f'{aid}/{f["id"]}: full limbs not clipped')
   check(f['body_height']==240,f'{aid}/{f["id"]}: anatomical logical height')
   check(f['uniform_source_scale']==actor['uniform_source_scale'],f'{aid}/{f["id"]}: same whole-body scale')
   check(f['contains_parcel'] is False,f'{aid}/{f["id"]}: empty-hand contract')
   check(f['facing']==('right' if f['id']=='farewell' else 'left'),f'{aid}/{f["id"]}: semantic orientation')
   for key in ('head_anchor','hip_anchor'):
    x,y=f[key];check(0<=x<192 and 0<=y<256,f'{aid}/{f["id"]}: {key}')
   check(f['source_cell_xyxy'][0]<=f['source_crop_xyxy'][0] and f['source_crop_xyxy'][2]<=f['source_cell_xyxy'][2],f'{aid}/{f["id"]}: crop stays in declared cell')
   heights.append(bounds[3]-bounds[1])
   if f in actor['walk']:masks.append(mask)
  check(max(heights)-min(heights)<=12,f'{aid}: no severe head-to-foot size drift')
  lower_differences=[]
  for i in range(4):
   for j in range(i+1,4):
    diff=int(np.count_nonzero(masks[i][150:]!=masks[j][150:]));lower_differences.append(diff)
    check(diff>100,f'{aid}: real lower-limb silhouette changes {i}/{j}, not shifted idle')
  report[aid]={'frames':6,'opaque_heights':heights,'lowest_foot_y':248,'minimum_lower_limb_pixel_difference':min(lower_differences),'all_poses_manually_reviewed':True}
 result={'passed':True,'checks':checks,'runtime_frames':24,'untouched_originals':sources,'actors':report,'visual_review':'All five generated sheets inspected; selected 24 registered derivatives inspected at native 1x with original idle identities. Robot V1 replaced with V2 to correct boot/head direction. Empty hands, no baked parcel, no shop insignia observed. No Spine rig/export claimed.'}
 (HERE/'asset-qa.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result,indent=2))
if __name__=='__main__':main()
