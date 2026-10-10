#!/usr/bin/env python3
"""Reproducible registration of inspected imagegen art; never draws artwork.
Allowed derivatives: cell crop, whole-body uniform nearest sampling, alpha128,
shared96 palette conversion, and translation onto transparent canvases.
"""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[4]
SRC=ROOT/'source_art/2d_v5/actors/cooperative'
OUT=ROOT/'assets/2d_v5/actors/cooperative'; OUT.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('pixel_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
PALPATH=ROOT/'source_art/pixel_pipeline_studies/palette_96.json'
PAL=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in json.loads(PALPATH.read_text())['colors']],dtype=np.uint8)
def rel(p):return str(p.relative_to(ROOT))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def frame(source,cell,name,scale,foot_x,hip,family):
 im=Image.open(source).convert('RGBA'); a=np.array(im.crop(cell)); mask=a[:,:,3]>=128
 yy,xx=np.where(mask); box=(int(xx.min()),int(yy.min()),int(xx.max()+1),int(yy.max()+1))
 clip=Image.fromarray(a).crop(box); size=(round(clip.width*scale),round(clip.height*scale))
 ar=np.array(clip.resize(size,Image.Resampling.NEAREST)); rgb=study.map_palette(ar[:,:,:3],PAL);alpha=np.where(ar[:,:,3]>=128,255,0).astype(np.uint8);rgb[alpha==0]=0
 part=Image.fromarray(np.dstack([rgb,alpha]),'RGBA')
 foot_source=(foot_x,cell[1]+box[3]); fullbox=(cell[0]+box[0],cell[1]+box[1],cell[0]+box[2],cell[1]+box[3])
 # A pelvis-projected ground origin stays under the body when the leading shoe
 # lifts. Source floor is the actual lowest opaque boot; no grounded foot floats.
 paste=(round(96-(foot_x-fullbox[0])*scale),248-size[1])
 canvas=Image.new('RGBA',(208,256));canvas.alpha_composite(part,paste)
 path=OUT/(name+'-pixel.png');canvas.save(path)
 arr=np.array(canvas); colors=np.unique(arr[:,:,:3][arr[:,:,3]>0],axis=0)
 assert len(colors)<=96 and canvas.getbbox()[3]==248
 assert canvas.getbbox()[0]>0 and canvas.getbbox()[2]<208
 actual_foot=[paste[0]+(foot_x-fullbox[0])*scale,248]
 record={'id':name,'runtime':rel(path),'sha256':sha(path),'dimensions':list(canvas.size),'alpha_bounds':list(canvas.getbbox()),'foot_anchor':actual_foot,'body_height':240,'hip_anchor':[paste[0]+(hip[0]-fullbox[0])*scale,paste[1]+(hip[1]-fullbox[1])*scale],'facing':'right','contains_parcel':False,'source':rel(source),'source_sha256':sha(source),'source_cell':list(cell),'source_bounds':list(fullbox),'source_foot_anchor':list(foot_source),'source_hip_anchor':list(hip),'uniform_scale':scale,'sampling_size':list(size),'paste_offset':list(paste),'stance_family':family,'alpha_values':np.unique(arr[:,:,3]).tolist(),'palette_used':len(colors)}
 return record
walksource=SRC/'clerk-walk-original.png';helpsource=SRC/'clerk-help-original.png'
# Six drawings, approximately THREE stance families. Do not claim six unique
# contact phases or a skeletal rig. Source row2 repeats similar leg shapes.
walk=[]
xs=[338,786,1225,344,786,1230]
hips=[(310,290),(752,290),(1188,286),(312,792),(751,794),(1190,793)]
for i,(x,hip) in enumerate(zip(xs,hips)):
 row,col=divmod(i,3);cell=(col*512,row*512,(col+1)*512,(row+1)*512)
 walk.append(frame(walksource,cell,f'clerk-walk-{i:02d}',240/488,x,hip,['contact','passing','lift'][col]))
gestures={}
for name,cell,x,hip in [('reach',(0,0,720,836),390,(328,466)),('align',(720,0,1260,836),955,(875,474)),('ready',(1260,0,1881,836),1510,(1417,483))]:
 gestures[name]=frame(helpsource,cell,'clerk-'+name,240/781,x,hip,name)
manifest={'version':1,'asset_type':'Image-generated whole-raster walk and empty-handed cooperative poses','provenance':'Original imagegen outputs preserved byte-for-byte. Crop, whole-body uniform nearest sampling, alpha128, shared96 Oklab palette map and transparent registration only. No code-drawn, vector, deformed or synthesized character pixels.','palette':rel(PALPATH),'palette_sha256':sha(PALPATH),'animation_status':'Six distinct raster drawings repeat about three gait stance families. This is a simple distance-driven walk cycle, not six unique anatomical phases and not a Spine rig.','registration_policy':'One common whole-body scale per source sheet; no face/head scaling and no gesture-width normalization. Pelvis-projected foot origin, measured boot baseline and per-frame hip anchor.','actors':{'clerk':{'appearance_id':'clerk','walk_cycle_distance':120,'walk':walk,'gestures':gestures}},'sources':[{'path':rel(p),'sha256':sha(p),'dimensions':list(Image.open(p).size)} for p in [walksource,helpsource]]}
(OUT/'motion-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
board=Image.new('RGBA',(208*6,310),(22,30,50,255)); d=ImageDraw.Draw(board)
for i,rec in enumerate(walk):
 im=Image.open(ROOT/rec['runtime']);board.alpha_composite(im,(208*i,20));d.text((208*i+6,278),f"{i}: {rec['stance_family']}",fill='white')
board.convert('RGB').save(SRC/'clerk-walk-review.png')
board=Image.new('RGBA',(208*4,290),(22,30,50,255));d=ImageDraw.Draw(board)
for i,(name,path) in enumerate([('original idle',ROOT/'assets/2d_v5/actors/clerk-idle-pixel.png')]+[(name,ROOT/r['runtime']) for name,r in gestures.items()]):
 board.alpha_composite(Image.open(path).convert('RGBA'),(i*208,8));d.text((i*208+5,267),name,fill='white')
board.convert('RGB').save(SRC/'clerk-help-review.png')
print(json.dumps({'manifest':rel(OUT/'motion-manifest.json'),'walk_drawings':len(walk),'stance_families':3,'gestures':list(gestures)},indent=2))
