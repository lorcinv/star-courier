#!/usr/bin/env python3
"""Static QA for actual image-generated actor motion art, never mock stand-ins."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
MANIFESTS=['assets/2d_v5/actors/cooperative/motion-manifest.json','assets/2d_v5/npcs/walk_exit/motion-manifest.json']
checks=[];actors={}
def check(ok,label):
 assert ok,label
 checks.append(label)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
palette=json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())['colors']
allowed={tuple(int(s[i:i+2],16) for i in (1,3,5)) for s in palette}
for path in MANIFESTS:
 check((ROOT/path).is_file(),'Actual motion manifest exists: '+path)
 data=json.loads((ROOT/path).read_text());actors.update(data['actors'])
check(set(actors)=={'clerk','human_courier','elf_archivist','alien_botanist','robot_machinist'},'Exactly five supported motion actors')
for actor,data in actors.items():
 check(3<=len(data['walk'])<=32,actor+' bounded actual walk cycle')
 check(0<float(data['walk_cycle_distance'])<1000,actor+' finite logical stride')
 hashes=[]
 for kind,records in [('walk',data['walk']),('run',data.get('run',[])),('gesture',list(data['gestures'].values()))]:
  for n,r in enumerate(records):
   label=actor+' '+kind+' '+str(n)+' '
   path=ROOT/r['runtime'];check(path.is_file(),label+'PNG exists')
   im=Image.open(path).convert('RGBA');a=np.array(im);visible=a[:,:,3]>0
   check(set(np.unique(a[:,:,3]))<={0,255},label+'binary alpha')
   colors={tuple(c) for c in np.unique(a[:,:,:3][visible],axis=0)}
   check(colors<=allowed,label+'approved96 colors only')
   check(np.all(a[:,:,:3][~visible]==0),label+'transparent RGB zero')
   check(r['contains_parcel'] is False,label+'no painted parcel semantic')
   check(r['facing'] in ['left','right'],label+'explicit source facing')
   check(float(r['body_height'])==240,label+'same anatomical body height as original actors')
   for name in ['foot_anchor','hip_anchor']:
    p=r[name];check(len(p)==2 and all(np.isfinite(p)) and 0<=p[0]<=im.width and 0<=p[1]<=im.height,label+name+' is registered inside canvas')
   check((r.get('flight',False) and im.getbbox()[3]<r['foot_anchor'][1]) or abs(r['foot_anchor'][1]-im.getbbox()[3])<=1,label+'painted soles touch floor or explicit run flight clears it')
   if 'sha256' in r:check(sha(path)==r['sha256'],label+'runtime SHA matches')
   if kind=='walk':hashes.append(sha(path))
 check(len(set(hashes))==len(hashes),actor+' walk frames have genuinely distinct raster bytes')
clerk=actors['clerk'];check(set(clerk['gestures'])=={'reach','align','ready'},'Clerk keeps three stable controller gesture keys')
check({r.get('semantic') for r in clerk['gestures'].values()}=={'tablet_read','tablet_tap','tablet_check'},'Clerk uses the generated waybill read, tap and cargo-check poses')
check(all(r.get('held_prop')=='waybill_tablet' for r in clerk['gestures'].values()),'All three helper poses visibly hold a tablet instead of empty-hand gestures')
check(len(clerk.get('run',[]))==32,'Clerk has a separate32-sample run cycle')
check(sum(r.get('flight',False) for r in clerk['run'])==8,'Run has eight airborne samples,25percent of cycle')
check(all(not r.get('flight',False) for r in clerk['walk']),'Walk always has a supporting foot')
check(len({r['sha256'] for r in clerk['run']})==32,'All32 assembled run samples have distinct raster bytes')
for source in {r['source'] for r in clerk['walk']}:
 check(len({r['uniform_scale'] for r in clerk['walk'] if r['source']==source})==1,'Clerk walk uses one whole-body sample scale per source')
check(len({r['uniform_scale'] for r in clerk['gestures'].values()})==1,'Clerk tablet uses one whole-body scale independent of hand extent')
check(len({r['stance_family'] for r in clerk['walk']})==4,'Clerk has contact/down/passing/up silhouettes')
check({r['support_half'] for r in clerk['walk']}=={'near','far'},'Clerk corrected contact supports both half cycles')
for actor,data in actors.items():
 sequence=data['walk_sequence']; weights=data['walk_phase_weights']
 check(3<=len(sequence)<=64 and all(isinstance(i,int) and 0<=i<len(data['walk']) for i in sequence),actor+' bounded valid walk sequence')
 check(len(weights)==len(sequence) and all(np.isfinite(w) and 0<w<=8 for w in weights),actor+' finite positive phase weights')
 check(data['walk_reference_height']==240,actor+' anatomical cadence reference')
for r in clerk['walk']+list(clerk['gestures'].values()):
 check(sha(ROOT/r['source'])==r['source_sha256'],'Clerk source original unchanged: '+r['id'])
result={'status':'pass','checks_passed':len(checks),'scope':'Static actual raster registration/provenance. Runtime is separately checked by tests/test_actor_motion_2d.gd.','checks':checks}
(ROOT/'source_art/2d_v5/actors/cooperative/motion-asset-qa.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS:',len(checks),'actual motion asset checks')
