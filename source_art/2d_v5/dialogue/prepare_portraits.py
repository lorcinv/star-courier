"""Technical extraction only: source pixels, nearest sampling, approved shared palette.
No painted or procedural character art. Original generated sheets remain untouched.
"""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
OUT=ROOT/'assets/2d_v5/dialogue'; OUT.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('pixel_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
pal=json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())
palette=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in pal['colors']],dtype=np.uint8)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
records=[]
for actor, source, regions, emotions in [
 ('clerk','clerk-expressions-original.png',[(0,0,560,512),(560,0,1010,512),(1010,0,1536,512),(0,512,560,1024),(560,512,1010,1024),(1010,512,1536,1024)],['neutral','warm_smile','curious','concerned','surprised','pleased']),
 ('human_courier','human-expressions-original.png',[(0,0,685,688),(685,0,1366,688),(1366,0,2048,688)],['neutral','pleased','concerned'])]:
 source_path=HERE/source; im=Image.open(source_path).convert('RGBA')
 # Largest shared alpha bounds determine one uniform scale for all expressions.
 cells=[]
 for region in regions:
  crop=im.crop(region); a=np.array(crop)[:,:,3]; box=Image.fromarray((a>=128).astype('uint8')*255).getbbox()
  cells.append((region,box,crop.crop(box)))
 height=max(c.height for _,_,c in cells); scale=500/height
 for (region,box,crop),emotion in zip(cells,emotions):
  # Canvas registration: bottom-center waist stays fixed; never scale individual faces differently.
  w,h=round(crop.width*scale),round(crop.height*scale)
  arr=np.array(crop.resize((w,h),Image.Resampling.NEAREST)); rgb=study.map_palette(arr[:,:,:3],palette)
  alpha=np.where(arr[:,:,3]>=128,255,0).astype('uint8');rgb[alpha==0]=0
  pixel=Image.fromarray(np.dstack([rgb,alpha]),'RGBA');canvas=Image.new('RGBA',(512,512));canvas.paste(pixel,((512-w)//2,512-h))
  dest=OUT/f'{actor}-{emotion}.png';canvas.save(dest)
  records.append(dict(actor=actor,expression=emotion,source=source,source_sha256=sha(source_path),region=list(region),alpha_crop_in_region=list(box),runtime=str(dest.relative_to(ROOT)),runtime_sha256=sha(dest),canvas=[512,512],waist_anchor=[256,512],uniform_scale=scale,content_rect=[(512-w)//2,512-h,w,h],alpha_values=[0,255]))
manifest={'generator':'OpenAI image_gen; original generated source sheets preserved','method':'Measured transparent gutters; alpha>=128 crop; one common expression scale per actor; bottom-center registration on 512x512 canvas; nearest-neighbor sampling; reviewed 96-color Oklab palette; no dithering; binary alpha; transparent RGB zeroed.','palette':'source_art/pixel_pipeline_studies/palette_96.json','records':records}
(HERE/'portrait-derivatives.json').write_text(json.dumps(manifest,indent=2)+'\n')
print([(r['actor'],r['expression'],r['content_rect']) for r in records])
