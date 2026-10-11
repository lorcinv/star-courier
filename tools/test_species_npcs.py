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
 check(set(r['world'])=={'idle','conversation','handoff'},id+' exactly three explicit world poses')
 check(set(r['poses'])=={'idle','conversation','handoff'},id+' exactly three registered poses')
 check(len({a['runtime'] for a in r['poses'].values()})==3,id+' each semantic pose has distinct cached raster')
 check(r['poses']['idle'].get('gesture') is False and r['poses']['idle'].get('held_parcel') is False,id+' neutral has relaxed empty hands')
 check(r['poses']['conversation'].get('gesture') is True,id+' original gesture is explicitly conversation-only')
 check(r['poses']['idle']['runtime']==f'assets/2d_v5/npcs/{id}/neutral-idle-pixel.png',id+' exact neutral raster path')
 check(r['poses']['conversation']['runtime']==f'assets/2d_v5/npcs/{id}/idle-pixel.png',id+' original idle raster retained as conversation')
 check(r['poses']['handoff']['runtime']==f'assets/2d_v5/npcs/{id}/handoff-pixel.png',id+' original handoff raster retained')
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
    check(im.size==(192,256),prefix+'shared canvas')
    expected_top=({'elf_archivist':8,'alien_botanist':7,'robot_machinist':7}[id] if key=='idle' else 8)
    check(im.getbbox()[3]==248 and im.getbbox()[1]==expected_top,prefix+'exact anatomical top and unchanged sole floor')
    check(im.getbbox()[2]<192,prefix+'right gutter')
    check(r['world'][key]==a['runtime'],prefix+'world and pose raster agree')
    check(a['foot_anchor']==r['foot_anchor'],prefix+'unchanged semantic foot registration')
    check(a['dimensions']==list(im.size) and a['alpha_bounds']==list(im.getbbox()),prefix+'declared canvas and alpha bounds match pixels')
    check(a['alpha_values']==[0,255] and a['all_colors_in_shared_palette'] is True and a['palette_used']==len(colors),prefix+'declared alpha and palette statistics match pixels')
    check(np.isfinite(a['uniform_scale']) and a['uniform_scale']>0,prefix+'one finite positive anatomical scale')
   if kind=='portrait':
    check(im.size==(512,512),prefix+'shared canvas');check(im.getbbox()[3]==512,prefix+'registered waist')
   if kind=='accessory':
    check(a['compatible_species']==[r['species']] and a['compatible_appearance_ids']==[id],prefix+'species compatibility')
    for pose,anchor in a['world_anchors'].items():
     x=anchor[0]-a['local_anchor'][0];y=anchor[1]-a['local_anchor'][1]
     check(x>=0 and y>=0 and x+im.width<=192 and y+im.height<=256,prefix+pose+' composite fits')
 neutral=r['poses']['idle'];prefix=id+' neutral foreground '
 check(sha(ROOT/neutral['source_original'])==neutral['source_sha256'],id+' neutral generation source unchanged')
 check((ROOT/neutral['source_prompt']).exists(),id+' neutral generation prompt retained')
 check(neutral['front_arm_runtime']==f'assets/2d_v5/npcs/{id}/neutral-front-arm-pixel.png',prefix+'one canonical reusable PNG path')
 check(neutral['front_arm_canvas']==r['shared_canvas']==[192,256],prefix+'same registered canvas as body')
 check(neutral['front_arm_foot_anchor']==r['foot_anchor'],prefix+'same semantic foot anchor as body')
 check(neutral['front_arm_draw_order']=='after_accessory',prefix+'explicitly occludes compatible accessory')
 check(all('front_arm_runtime' not in r['poses'][pose] for pose in ['conversation','handoff']),prefix+'not declared on conversation or handoff')
 arm_path=ROOT/neutral['front_arm_runtime'];arm=np.array(Image.open(arm_path).convert('RGBA'));base=np.array(Image.open(ROOT/neutral['runtime']).convert('RGBA'));visible=arm[:,:,3]>0
 check(sha(arm_path)==neutral['front_arm_sha256'],prefix+'SHA')
 check(arm.shape==base.shape==(256,192,4),prefix+'canvas dimensions match actual neutral pixels')
 check(set(np.unique(arm[:,:,3]))=={0,255},prefix+'nonempty binary-alpha mask')
 check(0<np.count_nonzero(visible)<192*256/4,prefix+'bounded partial arm mask')
 check(np.array_equal(arm[visible],base[visible]),prefix+'opaque pixels are an exact subset of neutral body')
 check(np.all(arm[:,:,:3][~visible]==0),prefix+'transparent RGB zero')
 check({tuple(c) for c in np.unique(arm[:,:,:3][visible],axis=0)}<=palette,prefix+'shared96')
 runtime_paths={a['runtime'] for a in r['poses'].values()}|{a['runtime'] for a in r['accessory_options'].values()}|{neutral['front_arm_runtime']}
 check(len(runtime_paths)==6 and all(Path(path).suffix=='.png' and '..' not in Path(path).parts and (ROOT/path).is_file() for path in runtime_paths),id+' fixed six-file body/accessory/foreground resource set')
 for exp in ['pleased','concerned']:
  a=np.array(Image.open(ROOT/r['portraits']['neutral']));b=np.array(Image.open(ROOT/r['portraits'][exp]));check(np.count_nonzero(np.any(a!=b,axis=2))>100,id+' distinct '+exp+' expression')
 check(len({a['uniform_scale'] for a in r['portrait_metadata'].values()})==1,id+' portrait variants use one uniform scale')
for v in m['appearance_variants']:
 r=m['appearances'][v['appearance_id']];check(v['species']==r['species'] and v['accessory_id'] in r['accessory_options'],v['variant_id']+' valid species-compatible variant')
result={'status':'pass','checks_passed':len(checks),'checks':checks,'scope':'Static assets/provenance/registration/compositing only. Does not claim engine runtime integration.','generator':'tools/test_species_npcs.py','manifest':'assets/2d_v5/npcs/npc-manifest.json','manifest_sha256':sha(ROOT/'assets/2d_v5/npcs/npc-manifest.json')}
(ROOT/'source_art/2d_v5/npcs/asset-qa.json').write_text(json.dumps(result,indent=2)+'\n')
print(f'PASS: {len(checks)} static NPC asset checks')
