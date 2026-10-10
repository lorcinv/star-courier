#!/usr/bin/env python3
"""Deterministic asset checks; no engine-integration claim."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
m=json.loads((ROOT/'assets/2d_v5/npcs/npc-manifest.json').read_text());checks=[]
def check(ok,label):
 assert ok,label
 checks.append(label)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
pal=json.loads((ROOT/m['palette']).read_text())['colors'];palette={tuple(int(h[i:i+2],16) for i in (1,3,5)) for h in pal}
check(len(palette)==96,'Shared palette contains 96 colors')
check(sha(ROOT/m['palette'])==m['palette_sha256'],'Palette SHA matches')
check(set(m['appearances'])=={'elf_archivist','alien_botanist','robot_machinist'},'Bounded three-species roster')
for id,r in m['appearances'].items():
 check(r['foot_anchor']==[96,248] and r['body_height']==240,id+' common world anchor')
 check(r['portrait_anchor']['waist']==[256,512],id+' common portrait waist')
 check(r['facing']=='right',id+' NPC faces right')
 check(set(r['world'])=={'idle','handoff'},id+' two poses')
 check(set(r['portraits'])=={'neutral','pleased','concerned'},id+' three expressions')
 check(len(r['accessory_options'])==2,id+' two accessory options')
 for kind,s in r['sources'].items():
  check((ROOT/s['path']).exists(),id+' '+kind+' source exists')
  check(sha(ROOT/s['path'])==s['sha256'],id+' '+kind+' source unchanged')
  check((ROOT/s['prompt']).exists(),id+' '+kind+' exact prompt exists')
  check(s['transparent_background'] is True,id+' '+kind+' alpha requested')
 for kind,records in [('pose',r['poses']),('accessory',r['accessory_options']),('portrait',r['portrait_metadata'])]:
  for key,a in records.items():
   p=ROOT/a['runtime'];im=Image.open(p).convert('RGBA');ar=np.array(im);visible=ar[:,:,3]>0;colors={tuple(c) for c in np.unique(ar[:,:,:3][visible],axis=0)}
   prefix=f'{id} {kind} {key} '
   check(p.exists(),prefix+'exists');check(sha(p)==a['sha256'],prefix+'SHA');check(set(np.unique(ar[:,:,3]))<={0,255},prefix+'binary alpha');check(colors<=palette,prefix+'shared96');check(np.all(ar[:,:,:3][~visible]==0),prefix+'transparent RGB zero')
   check(0<im.getbbox()[0]<im.width-1 or kind=='accessory',prefix+'left gutter')
   if kind=='pose':
    check(im.size==(192,256),prefix+'shared canvas');check(im.getbbox()[3]==248 and im.getbbox()[1]==8,prefix+'240px height and floor');check(im.getbbox()[2]<192,prefix+'right gutter')
   if kind=='portrait':
    check(im.size==(512,512),prefix+'shared canvas');check(im.getbbox()[3]==512,prefix+'registered waist')
   if kind=='accessory':
    check(a['compatible_species']==[r['species']] and a['compatible_appearance_ids']==[id],prefix+'species compatibility')
    for pose,anchor in a['world_anchors'].items():
     x=anchor[0]-a['local_anchor'][0];y=anchor[1]-a['local_anchor'][1]
     check(x>=0 and y>=0 and x+im.width<=192 and y+im.height<=256,prefix+pose+' composite fits')
 for exp in ['pleased','concerned']:
  a=np.array(Image.open(ROOT/r['portraits']['neutral']));b=np.array(Image.open(ROOT/r['portraits'][exp]));check(np.count_nonzero(np.any(a!=b,axis=2))>100,id+' distinct '+exp+' expression')
 check(len({a['uniform_scale'] for a in r['portrait_metadata'].values()})==1,id+' portrait variants use one uniform scale')
for v in m['appearance_variants']:
 r=m['appearances'][v['appearance_id']];check(v['species']==r['species'] and v['accessory_id'] in r['accessory_options'],v['variant_id']+' valid species-compatible variant')
result={'status':'pass','checks_passed':len(checks),'checks':checks,'scope':'Static assets/provenance/registration/compositing only. Does not claim engine runtime integration.'}
(ROOT/'source_art/2d_v5/npcs/asset-qa.json').write_text(json.dumps(result,indent=2)+'\n')
print(f'PASS: {len(checks)} static NPC asset checks')
