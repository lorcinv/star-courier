#!/usr/bin/env python3
"""Extract/register generated customer motion. No artwork is drawn or repainted.
Only component crops, whole-frame reflection, uniform NEAREST sampling,
reference96 mapping, alpha128 threshold, and QA raster compositing are used.
"""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import label, find_objects

ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
OUT=ROOT/'assets/2d_v5/npcs/walk_exit'
PALPATH=ROOT/'source_art/pixel_pipeline_studies/palette_96.json'
spec=importlib.util.spec_from_file_location('pixel_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
PAL=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in json.loads(PALPATH.read_text())['colors']],dtype=np.uint8)
POSES=['walk-contact-a','walk-down','walk-pass','walk-contact-b','farewell','neutral']
# Each measured landmark is in the original, unreflected 1536x1024 sheet.
# root_x is the pelvis ground projection; peg is the compatible accessory mount.
CONFIG={
 'human_customer':{'actor':'human_courier','species':'human','sha':'babf26a193a924a641ad932f9a7e900a0ceb6de964b04b5eaafd1ea9740111c5','generated_file':'exec-add4c6c6-3106-40f7-9276-a5503e40b580.png','facings':['left','left','right','right','right','right'],'root_x':[268,778,1268,273,780,1286],'head':[[254,117],[763,119],[1281,118],[276,623],[779,624],[1275,625]],'peg':[[315,322],[823,326],[1230,329],[219,824],[719,829],[1233,838]]},
 'elf_archivist':{'actor':'elf_archivist','species':'elf','sha':'0170ed3712dad765ad007f4b8d907118fe2c14c62812407bd913075dc4bb1fbb','generated_file':'exec-e9c62bdb-3477-4f3e-8293-eeb4b8f96c6f.png','facings':['left','left','left','left','right','left'],'root_x':[280,766,1278,274,781,1284],'head':[[275,93],[754,94],[1249,93],[272,594],[764,596],[1261,591]],'peg':[[336,306],[827,316],[1339,306],[329,806],[719,811],[1332,829]]},
 'alien_botanist':{'actor':'alien_botanist','species':'alien','sha':'55b5094110400f5df3306d1b8744ac811675f3ff4031e629cf6fc46d54d7463c','generated_file':'exec-d3322d32-7bf0-4063-bb39-37f51411d1ea.png','facings':['left','left','left','left','left','right'],'root_x':[254,750,1265,254,788,1284],'head':[[246,143],[735,147],[1241,143],[241,643],[760,650],[1261,650]],'peg':[[303,320],[800,325],[1321,319],[305,819],[831,811],[1231,830]]},
 'robot_machinist':{'actor':'robot_machinist','species':'robot','source':'robot_machinist-v2','sha':'95c4c8ce85dff8edd9b400114f2cc239495c27a60d72cfbc0d57a7b1fbd68496','generated_file':'exec-4b6dec62-e1d7-4ecb-9a78-3514107a98f3.png','facings':['left','left','left','left','right','left'],'root_x':[264,752,1265,258,780,1275],'head':[[259,106],[750,106],[1266,107],[250,610],[769,613],[1267,612]],'peg':[[321,311],[810,313],[1327,306],[321,811],[711,817],[1330,835]]},
}
def rel(p): return str(p.relative_to(ROOT))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def clean(im):
 a=np.array(im); rgb=study.map_palette(a[:,:,:3],PAL); alpha=np.where(a[:,:,3]>=128,255,0).astype(np.uint8);rgb[alpha==0]=0
 return Image.fromarray(np.dstack([rgb,alpha]),'RGBA')
def extract(im,i):
 x=(i%3)*512;y=(i//3)*512
 region=[x,y,x+512,y+512];cell=im.crop(region);arr=np.array(cell)
 lab,n=label(arr[:,:,3]>=128,np.ones((3,3)));sizes=np.bincount(lab.ravel());sizes[0]=0
 k=int(sizes.argmax());sl=find_objects(lab)[k-1]
 box=[x+sl[1].start,y+sl[0].start,x+sl[1].stop,y+sl[0].stop]
 assert sizes[k]>50000,(i,int(sizes[k]))
 return {'cell':region,'box':box,'image':im.crop(box),'opaque_pixels':int(sizes[k])}
def inspect(p):
 im=Image.open(p).convert('RGBA');a=np.array(im);colors=np.unique(a[:,:,:3][a[:,:,3]>0],axis=0)
 return {'runtime':rel(p),'dimensions':list(im.size),'sha256':sha(p),'alpha_bounds':list(im.getbbox()),'alpha_values':np.unique(a[:,:,3]).tolist(),'palette_used':len(colors),'all_colors_in_shared_palette':all(tuple(c) in set(map(tuple,PAL)) for c in colors)}

def main():
 OUT.mkdir(parents=True,exist_ok=True)
 manifest={'version':1,'generator':'built-in image_gen.imagegen','generated_at_utc':'2026-10-10T13:46:00Z','animation_status':'Four newly generated articulated walk poses per identity, plus farewell and neutral raster frames. No Spine rig, skeleton, atlas or Spine runtime/export is supplied or claimed.','contains_parcel':False,'palette':rel(PALPATH),'palette_sha256':sha(PALPATH),'method':'Original PNG bytes preserved; largest connected component per declared sheet cell; rectangular crop; optional lossless full-image horizontal reflection to normalize semantic direction; one uniform anatomical scale per identity from neutral body height; NEAREST sample; fixed reference96 Oklab mapping without dithering; alpha threshold128; zero transparent RGB; place on 192x256 common canvas. No synthetic or repainted character pixels.','coordinates':'Pixel units from top left. Foot anchor [96,248] is the pelvis ground projection and exclusive sole baseline; actual supporting shoe varies with stride. Hip anchor is a measured accessory attachment peg, not the pelvis center. Head landmark is a measured cranial/face center.','sources':{},'actors':{}}
 for sid,cfg in CONFIG.items():
  source_id=cfg.get('source',sid);p=HERE/f'{source_id}-original.png';assert sha(p)==cfg['sha'],f'Original bytes changed: {sid}'
  im=Image.open(p).convert('RGBA');assert im.size==(1536,1024)
  frames=[extract(im,i) for i in range(6)]
  scale=240/frames[5]['image'].height
  manifest['sources'][sid]={'original':rel(p),'sha256':sha(p),'dimensions':list(im.size),'generated_file':cfg['generated_file'],'prompt':rel(HERE/f'{source_id}.prompt.txt'),'requested_transparent_background':True,'actual_zero_alpha_fraction':float((np.array(im)[:,:,3]==0).mean()),'selected':True}
  dest=OUT/cfg['actor'];dest.mkdir(parents=True,exist_ok=True)
  actor={'species':cfg['species'],'appearance_id':cfg['actor'],'walk_cycle_distance':{'human_courier':164,'elf_archivist':176,'alien_botanist':160,'robot_machinist':148}[cfg['actor']],'walk_reference_height':240,'walk_sequence':[0,1,2,3,2,1],'walk_phase_weights':[1.15,.9,.95,1.15,.95,.9],'shared_canvas':[192,256],'foot_anchor':[96,248],'body_height':240,'uniform_source_scale':scale,'walk':[],'gestures':{}}
  for i,(pose,r) in enumerate(zip(POSES,frames)):
   box=r['box'];crop=r['image'];raw_facing=cfg['facings'][i];facing='right' if pose=='farewell' else 'left';flip=raw_facing!=facing
   sx=round(crop.width*scale);sy=round(crop.height*scale)
   def local_point(point):
    px=point[0]-box[0];py=point[1]-box[1]
    if flip:px=crop.width-px
    return [round(px*scale),round(py*scale)]
   source_foot=[cfg['root_x'][i],box[3]]
   foot_local=local_point(source_foot)
   if flip:crop=crop.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
   scaled=clean(crop.resize((sx,sy),Image.Resampling.NEAREST))
   paste=[96-foot_local[0],248-sy]
   assert paste[0]>=0 and paste[0]+sx<=192,(sid,pose,paste,sx)
   assert paste[1]>=0,(sid,pose,paste)
   canvas=Image.new('RGBA',(192,256));canvas.alpha_composite(scaled,tuple(paste));path=dest/f'{pose}-pixel.png';canvas.save(path)
   point=lambda q:[local_point(q)[0]+paste[0],local_point(q)[1]+paste[1]]
   frame=inspect(path)
   frame.update({'id':pose,'foot_anchor':[96,248],'body_height':240,'hip_anchor':point(cfg['peg'][i]),'head_anchor':point(cfg['head'][i]),'head_top_y':paste[1],'facing':facing,'contains_parcel':False,'source_id':sid,'source_cell_xyxy':r['cell'],'source_crop_xyxy':box,'source_foot_anchor':source_foot,'source_hip_anchor':cfg['peg'][i],'source_head_anchor':cfg['head'][i],'source_head_top_y':box[1],'source_facing':raw_facing,'reflected_x':flip,'uniform_source_scale':scale,'sampled_dimensions':[sx,sy],'paste_offset':paste,'sole_baseline_y':248})
   if pose.startswith('walk'):actor['walk'].append(frame)
   else:actor['gestures'][pose]=frame
  manifest['actors'][cfg['actor']]=actor
 manifest['sources']['robot_machinist-v1-archived']={'original':rel(HERE/'robot_machinist-original.png'),'sha256':sha(HERE/'robot_machinist-original.png'),'dimensions':[1536,1024],'generated_file':'exec-b5043e5b-769e-47df-a4da-a52d670d8b9e.png','prompt':rel(HERE/'robot_machinist.prompt.txt'),'selected':False,'reason':'Replaced by V2 to correct boot direction in left-walking contact poses; untouched original retained.'}
 (OUT/'motion-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 # Labels, floor guides, and neutral background exist only in this QA composite.
 font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',14)
 board=Image.new('RGB',(7*208+16,4*312+16),'#16253b');draw=ImageDraw.Draw(board)
 for row,(aid,actor) in enumerate(manifest['actors'].items()):
  yy=16+row*312;draw.text((16,yy),aid,fill='#fff3cf',font=font)
  ref=ROOT/('assets/2d_v5/actors/customer-idle-pixel.png' if aid=='human_courier' else f'assets/2d_v5/npcs/{aid}/idle-pixel.png')
  refim=Image.open(ref).convert('RGBA');board.paste(refim,(16,yy+28),refim);draw.text((16,yy+289),'existing idle (right)',fill='#b6d1ed',font=font)
  group=actor['walk']+[actor['gestures']['farewell'],actor['gestures']['neutral']]
  for col,frame in enumerate(group,1):
   xx=16+col*208;f=Image.open(ROOT/frame['runtime']);board.paste(f,(xx,yy+28),f)
   draw.line((xx,yy+28+248,xx+191,yy+28+248),fill='#496983')
   draw.text((xx,yy+289),frame['id'],fill='#b6d1ed',font=font)
 board.save(HERE/'contact-sheet-native.png')
 print(json.dumps({'manifest':rel(OUT/'motion-manifest.json'),'actors':list(manifest['actors']),'frames':24,'contact_sheet':rel(HERE/'contact-sheet-native.png')},indent=2))

if __name__=='__main__':main()
