#!/usr/bin/env python3
"""Technical registration/crop-compositing of imagegen painted replacements.
Never draws character artwork. Original alpha, face pixels, silhouettes and mounts stay exact.
"""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np,json,hashlib,importlib.util,shutil
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py');study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
PAL=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())['colors']],dtype=np.uint8)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rel=lambda p:str(p.relative_to(ROOT))
def clean(im):
 a=np.array(im);rgb=study.map_palette(a[:,:,:3],PAL);alpha=np.where(a[:,:,3]>=128,255,0).astype(np.uint8);rgb[alpha==0]=0
 return Image.fromarray(np.dstack([rgb,alpha]),'RGBA')
# All boxes are measured in original-sheet coordinates; output dimensions verified exact before extraction.
JOBS={
 'elf-world':('elf_archivist-world-original.png',[(232,363,302,425),(805,361,858,426),(1168,450,1248,526)]),
 'elf-portraits':('elf_archivist-portraits-original.png',[(71,589,161,678),(585,589,675,678),(1088,589,1180,678)]),
 'robot-world':('robot_machinist-world-v2-original.png',[(143,391,207,449),(339,451,419,517),(698,391,759,451),(873,452,944,519),(1079,513,1175,605)]),
 'robot-portraits':('robot_machinist-portraits-original.png',[(83,483,181,574),(391,581,502,671),(804,483,903,574),(1112,581,1224,671),(1527,483,1626,574),(1836,581,1948,671)]),
 'alien-world':('alien_botanist-world-original.png',[(1072,500,1174,585),(1328,408,1391,475)]),
}
registered={};provenance=[]
for key,(original,boxes) in JOBS.items():
 src=ROOT/'source_art/2d_v5/npcs'/original;edit=HERE/'original_edits'/f'{key}.png';orig=Image.open(src).convert('RGBA');edited=Image.open(edit).convert('RGBA');assert orig.size==edited.size,(key,orig.size,edited.size)
 ar=np.array(orig);ea=np.array(edited);mask=np.zeros(ar.shape[:2],bool)
 for x1,y1,x2,y2 in boxes: ar[y1:y2,x1:x2,:3]=ea[y1:y2,x1:x2,:3];mask[y1:y2,x1:x2]=True
 # Original alpha is deliberately retained: no silhouette/floor/waist drift.
 registered[key]=Image.fromarray(ar,'RGBA');out=HERE/f'{key}-registered.png';registered[key].save(out)
 oa=np.array(orig);assert np.array_equal(ar[~mask],oa[~mask]);assert np.array_equal(ar[:,:,3],oa[:,:,3])
 provenance.append({'key':key,'original':rel(src),'original_sha256':sha(src),'edit':rel(edit),'edit_sha256':sha(edit),'registered_source':rel(out),'registered_sha256':sha(out),'prompt':rel(HERE/f'{key}.prompt.txt'),'tool':'built-in image_gen.imagegen','transparent_background':True,'dimensions':list(orig.size),'replacement_regions_xyxy':boxes,'all_pixels_outside_regions_unchanged':True,'original_alpha_unchanged':True})
# Copy runtime into staging; leave all unaffected originals byte-for-byte, including previews.
stage=HERE/'staged-runtime'/'assets/2d_v5/npcs';shutil.copytree(ROOT/'assets/2d_v5/npcs',stage,dirs_exist_ok=True)
m=json.loads((stage/'npc-manifest.json').read_text());changes=[]
def details(p,old):
 a=np.array(Image.open(p));cs=np.unique(a[:,:,:3][a[:,:,3]>0],axis=0)
 old.update(sha256=sha(p),dimensions=list(Image.open(p).size),alpha_bounds=list(Image.open(p).getbbox()),alpha_values=np.unique(a[:,:,3]).tolist(),palette_used=len(cs),all_colors_in_shared_palette=True)
for id,short in [('elf_archivist','elf'),('robot_machinist','robot'),('alien_botanist','alien')]:
 r=m['appearances'][id]
 for pose,info in r['poses'].items():
  if id=='alien_botanist' and pose=='idle':continue
  im=registered[short+'-world'].crop(tuple(info['source_bounds']));ext=HERE/f'{id}-{pose}-extracted.png';im.save(ext)
  canvas=Image.new('RGBA',tuple(r['shared_canvas']));canvas.alpha_composite(clean(im.resize(tuple(info['sampling_size']),Image.Resampling.NEAREST)),tuple(info['paste_offset']))
  p=stage/id/f'{pose}-pixel.png';canvas.save(p);details(p,info);info['source_extracted']=rel(ext);info['debranding_source']=rel(HERE/f'{short}-world-registered.png');changes.append(str(p.relative_to(HERE/'staged-runtime')))
 if id!='alien_botanist':
  for exp,info in r['portrait_metadata'].items():
   im=registered[short+'-portraits'].crop(tuple(info['source_bounds']));ext=HERE/f'{id}-portrait-{exp}-extracted.png';im.save(ext)
   sc=info['uniform_scale'];size=(round(im.width*sc),round(im.height*sc));canvas=Image.new('RGBA',tuple(r['portrait_canvas']));canvas.alpha_composite(clean(im.resize(size,Image.Resampling.NEAREST)),tuple(info['paste_offset']))
   p=stage/id/'portraits'/f'{exp}.png';canvas.save(p);details(p,info);info['source_extracted']=rel(ext);info['debranding_source']=rel(HERE/f'{short}-portraits-registered.png');changes.append(str(p.relative_to(HERE/'staged-runtime')))
 if id=='alien_botanist':
  info=r['accessory_options']['seed_pod'];im=registered['alien-world'].crop(tuple(info['source_bounds']));p=stage/id/'accessories'/'seed_pod-pixel.png';clean(im.resize(tuple(info['dimensions']),Image.Resampling.NEAREST)).save(p);details(p,info);info['debranding_source']=rel(HERE/'alien-world-registered.png');changes.append(str(p.relative_to(HERE/'staged-runtime')))
 for aid,info in r['accessory_options'].items():
  for pose in ['idle','handoff']:
   # Only previews whose body or accessory changed need replacement.
   if id=='alien_botanist' and pose=='idle' and aid=='field_vial':continue
   canvas=Image.open(stage/id/f'{pose}-pixel.png').convert('RGBA');part=Image.open(stage/id/'accessories'/f'{aid}-pixel.png').convert('RGBA');mount=info['world_anchors'][pose];anchor=info['local_anchor'];canvas.alpha_composite(part,(mount[0]-anchor[0],mount[1]-anchor[1]));p=stage/id/f'{pose}--{aid}-preview.png';canvas.save(p);changes.append(str(p.relative_to(HERE/'staged-runtime')))
 r['debranding']={'audit':'Clothing, personal accessories and customer-owned parcel are unbranded; unaffected originals retained.','provenance':'source_art/2d_v5/npc_debranding/provenance.json'}
m['version']=2;m['debranding']={'provenance':rel(HERE/'provenance.json'),'method':'Only bounded imagegen replacement regions were registered into original sheets; original alpha and all pixels outside regions preserved. Runtime identity and anchors unchanged.'}
(stage/'npc-manifest.json').write_text(json.dumps(m,indent=2)+'\n');changes.append('assets/2d_v5/npcs/npc-manifest.json')
(HERE/'provenance.json').write_text(json.dumps({'scope':'Customer NPC emblem removal only; clerk, shop robot and environment unchanged.','sources':provenance,'runtime_changes':changes,'unaffected':'Human courier world + all expressions; alien idle + all expressions; elf and robot accessory cutouts remain original.'},indent=2)+'\n')
# Review-only factual contact sheet. Labels/backing do not enter runtime art.
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',20);small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',15)
board=Image.new('RGB',(1550,1450),(18,28,52));draw=ImageDraw.Draw(board)
for row,(id,title) in enumerate([('human_courier','Human: audited clear / unchanged'),('elf_archivist','Elf: plain shoulders / parcels'),('alien_botanist','Alien: plain seed jar / parcel'),('robot_machinist','Robot customer: plain shoulders / apron / parcel')]):
 y=20+row*355;draw.text((20,y),title,font=font,fill='#ffe6b0')
 for pi,pose in enumerate(['idle','handoff']):
  p=ROOT/f'assets/2d_v5/actors/customer-{pose}-pixel.png' if id=='human_courier' else stage/id/f'{pose}--{m["appearances"][id]["default_accessory"]}-preview.png'
  im=Image.open(p);board.paste(im,(25+pi*202,y+40),im);draw.text((25+pi*202,y+307),pose,font=small,fill='#92c6e9')
 for ei,exp in enumerate(['neutral','pleased','concerned']):
  p=ROOT/f'assets/2d_v5/dialogue/human_courier-{exp}.png' if id=='human_courier' else stage/id/'portraits'/f'{exp}.png'
  im=Image.open(p).resize((300,300),Image.Resampling.NEAREST);x=540+ei*328;board.paste(im,(x,y+20),im);draw.text((x+80,y+320),exp,font=small,fill='#92c6e9')
board.save(HERE/'proofs/all-four-identities-after.png')
# Per-source logo crops shown BEFORE / AFTER at nearest-native scale.
rows=sum(len(x[1]) for x in JOBS.values());board=Image.new('RGB',(720,rows*155+40),(18,28,52));d=ImageDraw.Draw(board);d.text((20,8),'Imagegen-only replacement crops: BEFORE / AFTER',font=font,fill='#ffe6b0');row=0
for key,(original,boxes) in JOBS.items():
 before=Image.open(ROOT/'source_art/2d_v5/npcs'/original)
 for i,b in enumerate(boxes):
  y=45+row*155;d.text((10,y),f'{key} {i+1}',font=small,fill='#92c6e9')
  for col,im in enumerate([before,registered[key]]):
   c=im.crop(b);c.thumbnail((145,120),Image.Resampling.NEAREST);board.paste(c,(285+col*200,y+10),c)
  row+=1
board.save(HERE/'proofs/before-after-emblem-crops.png')
print('Staged',len(changes),'runtime files; originals retained')
