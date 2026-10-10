from PIL import Image,ImageDraw
from pathlib import Path
import numpy as np,json
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
im=Image.open(HERE/'pair-idle-original.png').convert('RGBA')
pal=np.array([tuple(bytes.fromhex(c[1:]))for c in json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())['colors']],dtype=np.int32)
spec={'customer':{'region':(0,0,768,1024),'foot':(466,958),'canvas':(167,256),'anchor':(73.19,247.78)},'clerk':{'region':(768,0,1536,1024),'foot':(1065,958),'canvas':(159,256),'anchor':(85.59,247.59)}}
out={}
for name,s in spec.items():
 source=Image.new('RGBA',im.size);source.paste(im.crop(s['region']),s['region'][:2]);a=source.getchannel('A').point(lambda v:255 if v>=128 else 0);source.putalpha(a);b=a.getbbox();crop=source.crop(b)
 scale=240/(s['foot'][1]-b[1]);size=(round(crop.width*scale),round(crop.height*scale));small=crop.resize(size,Image.Resampling.NEAREST)
 arr=np.array(small);flat=arr[:,:,:3].reshape(-1,3).astype(np.int32);new=np.empty(flat.shape,dtype=np.uint8)
 for i in range(0,len(flat),2048):new[i:i+2048]=pal[((flat[i:i+2048,None,:]-pal[None,:,:])**2).sum(axis=2).argmin(axis=1)]
 arr[:,:,:3]=new.reshape(arr.shape[:2]+(3,));small=Image.fromarray(arr)
 canvas=Image.new('RGBA',s['canvas']);offset=(round(s['anchor'][0]-(s['foot'][0]-b[0])*scale),round(s['anchor'][1]-(s['foot'][1]-b[1])*scale));canvas.alpha_composite(small,offset);canvas.save(HERE/'staged-runtime'/f'{name}-idle-pixel.png')
 out[name]={'source_region':s['region'],'source_bounds':b,'source_foot':s['foot'],'runtime_foot':s['anchor'],'scale':scale,'offset':offset,'runtime_bounds':canvas.getchannel('A').getbbox()}
preview=Image.new('RGB',(800,328),'#253858');d=ImageDraw.Draw(preview)
for col,version in enumerate(['v1','v2']):
 d.text((col*400+22,15),'V1 original'if version=='v1'else'V2 revised shared proportions',fill='#fff0cd')
 for j,name in enumerate(['customer','clerk']):
  path=HERE.parent/'v1/runtime-snapshot'/f'{name}-idle-pixel.png'if version=='v1'else HERE/'staged-runtime'/f'{name}-idle-pixel.png'
  actor=Image.open(path);preview.paste(actor,(col*400+28+j*174,42),actor)
 d.line((col*400+20,290,col*400+370,290),fill='#48678f')
preview.save(HERE/'pair-proportion-preview.png');(HERE/'idle-preview-mapping.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
