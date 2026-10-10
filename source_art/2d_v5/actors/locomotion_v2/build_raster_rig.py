#!/usr/bin/env python3
"""Compose generated raster cutouts into measured 2D locomotion samples.
Masks are segmentation only: no character strokes/shapes/colors are drawn.
Source originals remain byte-for-byte intact. This is not a Spine asset.
"""
from pathlib import Path
import json, math, hashlib, importlib.util
import numpy as np
from PIL import Image,ImageDraw
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
OUT=HERE/'prototype';OUT.mkdir(exist_ok=True)
SCALE=240/485
W,H=256,272; ORIGIN=(120,256)
walk=Image.open(HERE/'clerk-walk-original.png').convert('RGBA')
run=Image.open(HERE/'clerk-run-original.png').convert('RGBA')

def part(im,poly,root,tip):
 mask=Image.new('L',im.size);ImageDraw.Draw(mask).polygon(poly,fill=255)
 a=np.array(im);a[:,:,3]=np.where((a[:,:,3]>=128)&(np.array(mask)>0),255,0);a[a[:,:,3]==0,:3]=0
 p=Image.fromarray(a);box=p.getbbox();p=p.crop(box)
 return {'im':p,'root':(root[0]-box[0],root[1]-box[1]),'tip':(tip[0]-box[0],tip[1]-box[1])}
# Near cutouts all from the single complete generated down pose; lower-joint
# overlaps use existing painted skin/boot pixels, never a procedural patch.
near_thigh=part(walk,[(178,279),(226,284),(258,344),(280,392),(250,412),(227,390),(177,351)],(194,294),(260,390))
near_shin=part(walk,[(241,369),(271,370),(296,430),(270,439),(251,409)],(260,390),(281,432))
near_boot=part(walk,[(584,418),(632,416),(638,438),(675,449),(698,471),(692,501),(573,501),(570,474)],(610,428),(662,428))
far_thigh=part(walk,[(177,279),(221,280),(207,325),(158,383),(131,395),(108,380),(148,328)],(192,294),(133,376))
far_shin=part(walk,[(124,364),(153,379),(116,435),(80,418)],(135,380),(101,422))
far_boot=part(walk,[(584,418),(632,416),(638,438),(675,449),(698,471),(692,501),(573,501),(570,474)],(610,428),(662,428))
# Full torso/head/arms are source-pixel cutouts, not reconstructed features.
def torso_from(im,cell,hip):
 x0,y0,x1,y1=cell
 return part(im,[(x0,y0),(x1,y0),(x1,y0+350),(x0+260,y0+350),(x0+255,y0+298),(x0+148,y0+298),(x0+146,y0+350),(x0,y0+350)],hip,(hip[0],hip[1]+100))
walk_body=part(walk,[(0,0),(384,0),(384,282),(258,288),(155,288),(137,316),(110,338),(79,329),(67,309),(111,262),(0,262)],(196,294),(196,394))
run_body=part(run,[(100,0),(444,0),(444,340),(353,340),(335,309),(302,312),(244,305),(208,292),(174,274),(157,294),(134,298),(113,281),(109,231),(100,231)],(205,307),(205,407))
walk_forearm=part(walk,[(107,253),(149,267),(145,292),(126,318),(115,338),(78,330),(72,308),(96,283)],(129,273),(104,318))
# Cut only the forearm from the torso's already segmented pixels; the upper
# sleeve remains in the torso and overlaps the transformed generated forearm.
wp=np.array(walk_body['im']);wr=walk_body['root'];ox=196-wr[0];oy=294-wr[1]
yy,xx=np.mgrid[:wp.shape[0],:wp.shape[1]];erase=(yy+oy>=270)&(xx+ox<148);wp[erase]=0;walk_body['im']=Image.fromarray(wp)
# Source limbs are uniformly sampled once; only rotations and rigid attachment
# move them. The lengths below come from those sampled joint distances.
L1=math.dist(near_thigh['root'],near_thigh['tip'])*SCALE
L2=math.dist(near_shin['root'],near_shin['tip'])*SCALE
# Preserve source limb ratios: pose reach is limited to L1+L2, and heel/sole
# placement comes from the measured boot root rather than per-frame body resize.
BOOT_DROP=(498-428)*SCALE

def draw_part(canvas,p,a,b=None,angle=None,scale=SCALE):
 r=np.array(p['root']); t=np.array(p['tip']);v=t-r
 theta=(math.atan2(b[1]-a[1],b[0]-a[0])-math.atan2(v[1],v[0])) if b is not None else angle
 c,s=math.cos(theta)*scale,math.sin(theta)*scale
 mat=np.array([[c,-s],[s,c]]);inv=np.linalg.inv(mat)
 trans=r-inv@np.array(a)
 coeff=(inv[0,0],inv[0,1],trans[0],inv[1,0],inv[1,1],trans[1])
 out=p['im'].transform((W,H),Image.Transform.AFFINE,coeff,Image.Resampling.NEAREST)
 canvas.alpha_composite(out)
 return out

def knee(hip,ankle,l1,l2):
 v=np.array(ankle)-np.array(hip);d=float(np.linalg.norm(v));d=max(abs(l1-l2)+.4,min(d,l1+l2-.4));u=v/np.linalg.norm(v)
 aa=(l1*l1-l2*l2+d*d)/(2*d);hh=math.sqrt(max(0,l1*l1-aa*aa))
 # Knees flex forward, preserving a consistent joint hinge on either support.
 return np.array(hip)+u*aa+np.array([u[1],-u[0]])*hh

def foot_spec(t,kind):
 t%=1
 if kind=='walk':
  stance=.60;stride=132;front=36;back=front-stride*stance
  if t<stance:return (front-stride*t,0,True,0)
  u=(t-stance)/(1-stance)
  # Smooth recovery arc, toe trails, knee rises while the support stays planted.
  return (back+(front-back)*(u*u*(3-2*u)),-26*math.sin(math.pi*u),False,-.18*math.sin(math.pi*u))
 stance=.36;stride=208;front=31;back=front-stride*stance
 if t<stance:return (front-stride*t,0,True,0)
 u=(t-stance)/(1-stance)
 # Run has 28% cycle with neither shoe planted. Heel lifts strongly behind.
 return (back+(front-back)*(u*u*(3-2*u)),-50*math.sin(math.pi*u),False,-.55*math.sin(math.pi*u))

def make_frame(kind,t):
 canvas=Image.new('RGBA',(W,H)); support=Image.new('RGBA',(W,H))
 # Hip compression/lift is actual articulation, never translation of the whole
 # actor or a bob added to the controller's grounded origin.
 hipy=159+(1.4*math.sin(t*4*math.pi)) if kind=='walk' else 163+2.0*math.sin(t*4*math.pi)
 hip=(120,hipy)
 feet={};legimgs={};joints={}
 for side,offset in [('far',.5),('near',0)]:
  fx,fy,grounded,bootang=foot_spec(t+offset,kind)
  sole=(120+fx,256+fy)
  ankle=(sole[0],sole[1]-BOOT_DROP)
  hi=(hip[0]+(-3 if side=='far' else 3),hip[1])
  parts=[near_thigh,near_shin,near_boot] if side=='near' else [far_thigh,far_shin,far_boot]
  l1=math.dist(parts[0]['root'],parts[0]['tip'])*SCALE;l2=math.dist(parts[1]['root'],parts[1]['tip'])*SCALE
  v=np.array(ankle)-np.array(hi);dist=float(np.linalg.norm(v));valid=max(abs(l1-l2)+1,min(dist,l1+l2-1))
  if not grounded and abs(valid-dist)>.001:
   ankle=tuple(np.array(hi)+v/max(dist,.001)*valid);sole=(ankle[0],ankle[1]+BOOT_DROP)
  kn=knee(hi,ankle,l1,l2)
  im=Image.new('RGBA',(W,H)); parts=[near_thigh,near_shin,near_boot] if side=='near' else [far_thigh,far_shin,far_boot]
  draw_part(im,parts[0],hi,kn)
  draw_part(im,parts[1],kn,ankle)
  draw_part(im,parts[2],ankle,angle=bootang)
  legimgs[side]=im
  feet[side]={'sole':[float(x) for x in sole],'grounded':grounded}
  joints[side]={'hip':list(hi),'knee':[float(x) for x in kn],'ankle':list(ankle)}
 canvas.alpha_composite(legimgs['far']);canvas.alpha_composite(legimgs['near'])
 # Keep a coherent face/hair drawing across the cycle. Arm poses vary at the
 # contact halves, selected from the same generated source at one uniform scale.
 body_idx=[0,0,1,1,2,2,1,1][int(t*8)%8]
 body=walk_body if kind=='walk' else run_body
 if kind=='walk':
  elbow=(hip[0]+(129-196)*SCALE,hip[1]+(273-294)*SCALE)
  draw_part(canvas,walk_forearm,elbow,angle=-.9*(.5-.5*math.cos(t*2*math.pi)))
 draw_part(canvas,body,hip,angle=0)
 # Support-only layer is the exact visible source pixels under the torso.
 support_sides=[s for s in ['far','near'] if feet[s]['grounded']]
 support_side=('near' if feet['near']['grounded'] else 'far') if support_sides else ''
 if support_side:
  support=legimgs[support_side].copy()
  # Remove upper torso occlusion and near-leg occlusion of far support pixels.
  bodymask=Image.new('RGBA',(W,H));draw_part(bodymask,body,hip,angle=0)
  ar=np.array(support); ar[np.array(bodymask)[:,:,3]>0]=0
  if support_side=='far':ar[np.array(legimgs['near'])[:,:,3]>0]=0
  support=Image.fromarray(ar)
 return canvas,support,{'hip':list(hip),'feet':feet,'support_side':support_side,'joints':joints,'phase':t,'body_source_index':body_idx}

def main():
 for name,p in [('near-thigh',near_thigh),('near-shin',near_shin),('near-boot',near_boot),('far-thigh',far_thigh),('far-shin',far_shin)]:p['im'].save(OUT/(name+'.png'))
 for kind in ['walk','run']:
  frames=[];metadata=[]
  for i in range(32):
   t=i/32;im,sup,meta=make_frame(kind,t);im.save(OUT/f'{kind}-{i:02d}.png');sup.save(OUT/f'{kind}-{i:02d}-support.png');frames.append(im);metadata.append(meta)
  (OUT/(kind+'-metadata.json')).write_text(json.dumps(metadata,indent=2))
  board=Image.new('RGBA',(W*8,H*4),(25,32,46,255))
  for i,im in enumerate(frames):board.alpha_composite(im,((i%8)*W,(i//8)*H))
  board.convert('RGB').save(OUT/(kind+'-review.png'))
  # Preview timing at target 210px size and155/300 logical pixels per second.
  duration=1000*((132 if kind=='walk' else 208)*210/240)/(155 if kind=='walk' else 300)/32
  frames[0].save(OUT/(kind+'.gif'),save_all=True,append_images=frames[1:],duration=duration,loop=0,disposal=2)
 print('Raster-only prototype composed; limb lengths',L1,L2,'shoe drop',BOOT_DROP)
if __name__=='__main__':main()
