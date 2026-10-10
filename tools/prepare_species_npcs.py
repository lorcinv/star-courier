#!/usr/bin/env python3
"""Crop/register imagegen NPCs. Only uniform sampling, palette cleanup and alpha compositing.
No creative shapes or missing artwork are drawn. Original PNGs are never modified.
"""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import label
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'source_art/2d_v5/npcs'; OUT=ROOT/'assets/2d_v5/npcs'
spec=importlib.util.spec_from_file_location('pixel_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
PALPATH=ROOT/'source_art/pixel_pipeline_studies/palette_96.json'
PALJSON=json.loads(PALPATH.read_text()); PAL=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in PALJSON['colors']],dtype=np.uint8)
CONFIG={
 'elf_archivist':{'species':'elf','world':'elf_archivist-world-original.png','accessories':[('book_pouch',48),('map_case',60)],'mounts':{'idle':[290,598],'handoff':[834,598]},'shoulder_y':540},
 'alien_botanist':{'species':'alien','world':'alien_botanist-world-original.png','accessories':[('seed_pod',52),('field_vial',54)],'mounts':{'idle':[172,656],'handoff':[732,656]},'shoulder_y':567},
 'robot_machinist':{'species':'robot','world':'robot_machinist-world-v2-original.png','accessories':[('tool_pack',55),('power_cell',55)],'mounts':{'idle':[203,650],'handoff':[763,650]},'shoulder_y':422},
}
EXPS=['neutral','pleased','concerned']; POSES=['idle','handoff']
def rel(p):return str(p.relative_to(ROOT))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def components(p,minimum=5000):
 im=Image.open(p).convert('RGBA'); ar=np.array(im); lab,n=label(ar[:,:,3]>=128,np.ones((3,3))); count=np.bincount(lab.ravel()); res=[]
 for i in range(1,n+1):
  if count[i]<minimum:continue
  yy,xx=np.where(lab==i);box=[int(xx.min()),int(yy.min()),int(xx.max()+1),int(yy.max()+1)]
  clip=ar[box[1]:box[3],box[0]:box[2]].copy(); clip[:,:,3]=np.where(lab[box[1]:box[3],box[0]:box[2]]==i,clip[:,:,3],0)
  res.append({'box':box,'im':Image.fromarray(clip),'area':int(count[i])})
 return sorted(res,key=lambda r:r['box'][0])
def clean(im):
 a=np.array(im); rgb=study.map_palette(a[:,:,:3],PAL); alpha=np.where(a[:,:,3]>=128,255,0).astype(np.uint8);rgb[alpha==0]=0
 return Image.fromarray(np.dstack([rgb,alpha]),'RGBA')
def details(path):
 im=Image.open(path);a=np.array(im);colors=np.unique(a[:,:,:3][a[:,:,3]>0],axis=0)
 return {'runtime':rel(path),'sha256':sha(path),'dimensions':list(im.size),'alpha_bounds':list(im.getbbox()),'alpha_values':np.unique(a[:,:,3]).tolist(),'palette_used':len(colors),'all_colors_in_shared_palette':all(tuple(c) in set(map(tuple,PAL)) for c in colors)}
def source_record(p,prompt):
 return {'path':rel(p),'sha256':sha(p),'dimensions':list(Image.open(p).size),'prompt':rel(SRC/prompt),'tool':'built-in image_gen.imagegen','transparent_background':True}
manifest={'version':1,'status':'asset delivery only; runtime integration must be verified separately','palette':rel(PALPATH),'palette_sha256':sha(PALPATH),'provenance':'All character, parcel, expression and accessory pixels were generated with built-in imagegen. Original files preserved byte-for-byte. Derivatives only crop, uniformly nearest-resample, threshold alpha128 and map to the common approved 96-color palette in Oklab. No face-only scaling or procedural painted artwork.','animation_status':'Two matched whole-sprite poses. These are not Spine-bound assets and no Spine rig/export is claimed.','randomization_policy':'Choose one appearance_id, then one of its compatible accessory options. Never mix parts across species. Portrait identity is stable because every removable accessory mounts below the portrait crop.','appearances':{},'appearance_variants':[]}
for id,cfg in CONFIG.items():
 d=OUT/id;(d/'accessories').mkdir(parents=True,exist_ok=True);(d/'portraits').mkdir(exist_ok=True)
 source=SRC/cfg['world'];c=components(source);world=c[:2];acc=sorted(c[2:],key=lambda r:r['box'][1]);assert len(c)==4,(id,len(c))
 body_h=max(r['box'][3]-r['box'][1] for r in world); scale=240/body_h
 record={'appearance_id':id,'species':cfg['species'],'facing':'right','shared_canvas':[192,256],'foot_anchor':[96,248],'body_height':240,'default_accessory':cfg['accessories'][0][0],'world':{},'poses':{},'accessory_options':{},'portrait_canvas':[512,512],'portrait_anchor':{'waist':[256,512]},'portraits':{},'portrait_metadata':{},'sources':{'world':source_record(source,cfg['world'].replace('-original.png','.prompt.txt')),'portraits':source_record(SRC/f'{id}-portraits-original.png',f'{id}-portraits.prompt.txt')}}
 transforms={}
 for pose,r in zip(POSES,world):
  im=r['im'];box=r['box'];aa=np.array(im)[:,:,3]>=128; y0=max(0,aa.shape[0]-100);yy,xx=np.where(aa[y0:]); foot_x=(int(xx.min())+int(xx.max())+1)/2; foot=[box[0]+foot_x,box[3]]
  size=[round(im.width*scale),240];scaled=clean(im.resize(tuple(size),Image.Resampling.NEAREST));x=round(96-foot_x*scale);y=8
  canvas=Image.new('RGBA',(192,256));canvas.alpha_composite(scaled,(x,y));path=d/f'{pose}-pixel.png';canvas.save(path)
  extr=SRC/f'{id}-{pose}-extracted.png';im.save(extr)
  info=details(path);info.update({'source_bounds':box,'source_extracted':rel(extr),'source_foot_anchor':foot,'foot_anchor':[96,248],'uniform_scale':scale,'paste_offset':[x,y],'sampling_size':size})
  # Coordinates represent the component's visible attachment peg, rather than its bounding-box corner.
  mx,my=cfg['mounts'][pose];mount=[round(x+(mx-box[0])*scale),round(y+(my-box[1])*scale)]
  transforms[pose]={'mount':mount};record['world'][pose]=rel(path);record['poses'][pose]=info
 for (aid,target_h),r in zip(cfg['accessories'],acc):
  im=r['im'];size=[round(im.width*target_h/im.height),target_h];part=clean(im.resize(tuple(size),Image.Resampling.NEAREST));path=d/'accessories'/f'{aid}-pixel.png';part.save(path)
  # Robot hangers extend horizontally; organic-species belt loops project upward.
  local_anchor=[4,round(target_h*.26)] if id=='robot_machinist' else [round(size[0]*.37),3]
  info=details(path);info.update({'accessory_id':aid,'compatible_species':[cfg['species']],'compatible_appearance_ids':[id],'local_anchor':local_anchor,'world_anchors':{pose:transforms[pose]['mount'] for pose in POSES},'portrait_visibility':'below upper-waist portrait crop; no portrait overlay required','source_bounds':r['box']})
  record['accessory_options'][aid]=info
  manifest['appearance_variants'].append({'appearance_id':id,'variant_id':f'{id}__{aid}','species':cfg['species'],'accessory_id':aid})
  for pose in POSES:
   composite=Image.open(d/f'{pose}-pixel.png').convert('RGBA');m=info['world_anchors'][pose];composite.alpha_composite(part,(m[0]-local_anchor[0],m[1]-local_anchor[1]));cp=d/f'{pose}--{aid}-preview.png';composite.save(cp)
 # One uniform scale for all expressions; foot/waist registration only translates the full cropped portrait.
 pc=components(SRC/f'{id}-portraits-original.png');assert len(pc)==3,(id,'portraits',len(pc));ph=max(r['im'].height for r in pc);pw=max(r['im'].width for r in pc);ps=min(480/ph,472/pw)
 for exp,r in zip(EXPS,pc):
  im=r['im'];b=r['box'];aa=np.array(im)[:,:,3]>=128;yy,xx=np.where(aa[max(0,im.height-5):]);waistx=(int(xx.min())+int(xx.max())+1)/2
  size=[round(im.width*ps),round(im.height*ps)];px=round(256-waistx*ps);py=512-size[1];scaled=clean(im.resize(tuple(size),Image.Resampling.NEAREST));canvas=Image.new('RGBA',(512,512));canvas.alpha_composite(scaled,(px,py));path=d/'portraits'/f'{exp}.png';canvas.save(path)
  extr=SRC/f'{id}-portrait-{exp}-extracted.png';im.save(extr)
  inf=details(path);inf.update({'expression_id':exp,'source_bounds':b,'source_extracted':rel(extr),'uniform_scale':ps,'paste_offset':[px,py],'waist_anchor':[256,512],'shoulder_anchor':[256,round(py+(cfg['shoulder_y']-b[1])*ps)]})
  record['portraits'][exp]=rel(path);record['portrait_metadata'][exp]=inf
 record['portrait_anchor']['shoulder']=record['portrait_metadata']['neutral']['shoulder_anchor'];manifest['appearances'][id]=record
OUT.mkdir(parents=True,exist_ok=True);(OUT/'npc-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
# Review-only board: labels and flat backing are technical layout, never runtime character art.
board=Image.new('RGB',(1680,1230),(18,28,52));draw=ImageDraw.Draw(board);font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',22);small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',15)
for row,(id,cfg) in enumerate(CONFIG.items()):
 y=20+row*400;draw.text((24,y),id,fill='#ffe6b0',font=font)
 for col,aid in enumerate([a[0] for a in cfg['accessories']]):
  for pi,pose in enumerate(POSES):
   im=Image.open(OUT/id/f'{pose}--{aid}-preview.png');x=20+(col*2+pi)*176;board.paste(im,(x,y+55),im);draw.text((x,y+318),f'{pose}: {aid}',fill='#92c6e9',font=small)
 for ei,exp in enumerate(EXPS):
  im=Image.open(OUT/id/'portraits'/f'{exp}.png').resize((300,300),Image.Resampling.NEAREST);x=738+ei*307;board.paste(im,(x,y+42),im);draw.text((x+65,y+350),exp,fill='#92c6e9',font=small)
board.save(SRC/'npc-cast-board.png')
print(json.dumps({'manifest':rel(OUT/'npc-manifest.json'),'appearances':list(manifest['appearances']),'variants':len(manifest['appearance_variants']),'cast_board':rel(SRC/'npc-cast-board.png')},indent=2))
