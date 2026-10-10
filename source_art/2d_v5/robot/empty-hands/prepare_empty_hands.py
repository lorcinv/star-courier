"""Technical derivatives of imagegen originals: registered nearest/palette samples.
No new artwork is drawn. The raised mechanical arm is alpha-isolated from its
original pixels so the runtime can rigidly aim/extend it without deforming heads.
"""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
OUT=ROOT/'assets/2d_v5/robot'
spec=importlib.util.spec_from_file_location('pixel_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
colors=json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())['colors']
palette=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in colors],dtype=np.uint8)
def save_registered(source,roi,anchor,scale,size,name):
    crop=source.crop(roi)
    logical_size=(size[0]//2,size[1]//2)
    # One whole-pose uniform resample, then registration on the common foot.
    dims=(round(crop.width*scale/2),round(crop.height*scale/2))
    small=crop.resize(dims,Image.Resampling.NEAREST)
    canvas=Image.new('RGBA',logical_size)
    offset=(round(40+(roi[0]-anchor[0])*scale/2),round(68+(roi[1]-anchor[1])*scale/2))
    canvas.paste(small,offset)
    raw=np.array(canvas);rgb=study.map_palette(raw[:,:,:3],palette)
    alpha=np.where(raw[:,:,3]>=128,255,0).astype(np.uint8);rgb[alpha==0]=0
    out=Image.fromarray(np.dstack([rgb,alpha]),'RGBA')
    out.save(OUT/(name+'-logical.png'));out.resize(size,Image.Resampling.NEAREST).save(OUT/(name+'.png'))
    return {'name':name,'source_roi':roi,'source_foot_anchor':anchor,'uniform_scale':scale,'foot_anchor':[80,136],'canvas':size}
source=Image.open(HERE/'carry-offer-original.png').convert('RGBA')
records=[save_registered(source,(315,265,765,740),(556,732),.188,(160,144),'carry-empty'),save_registered(source,(1120,273,1660,742),(1336,735),.188,(160,144),'offer-empty')]
raised=Image.open(HERE/'raised-gripper-original.png').convert('RGBA')
# Alpha isolation follows the transparent gap between robot head and diagonal
# arm. The circular shoulder and complete empty gripper remain source pixels.
mask=Image.new('L',raised.size)
ImageDraw.Draw(mask).polygon([(552,881),(587,842),(632,812),(701,669),(710,581),(784,556),(801,498),(794,446),(830,388),(823,333),(895,275),(896,210),(956,145),(1037,142),(1047,229),(1128,235),(1130,342),(1028,377),(960,395),(916,410),(876,478),(858,533),(819,594),(825,650),(780,685),(747,775),(735,842),(693,927),(620,965),(570,935)],fill=255)
alpha=np.array(raised.getchannel('A')); alpha[np.array(mask)==0]=0;raised.putalpha(Image.fromarray(alpha))
roi=(550,140,1134,970);arm=raised.crop(roi)
# Runtime arm pixels remain nearest sampled. Shoulder=(638,890), grip=(1006,257).
arm=arm.resize((118,166),Image.Resampling.NEAREST)
a=np.array(arm);rgb=study.map_palette(a[:,:,:3],palette);alpha=np.where(a[:,:,3]>=128,255,0).astype(np.uint8);rgb[alpha==0]=0
arm=Image.fromarray(np.dstack([rgb,alpha]),'RGBA');arm.save(OUT/'lift-arm.png')
manifest={'method':'Imagegen originals preserved; alpha isolation; whole-body uniform nearest sampling; shared96 palette; binary alpha. Lift arm separately transforms authored mechanical pixels only. No Spine.', 'sources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [HERE/'carry-offer-original.png',HERE/'raised-gripper-original.png']},'poses':records,'arm':{'source_roi':roi,'runtime_size':[118,166],'shoulder_anchor':[17.8,150.0],'grip_anchor':[92.0,23.4],'runtime':'assets/2d_v5/robot/lift-arm.png'}}
(HERE/'derivatives.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
