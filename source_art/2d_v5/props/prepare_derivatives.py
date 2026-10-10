"""Pixel-grid preparation only; never paints/replaces generated artwork."""
from pathlib import Path
import json, hashlib, importlib.util
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('pixel_study',ROOT/'source_art/pixel_pipeline_studies/study_reference.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
palette_json=json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())
palette=np.array([[int(h[i:i+2],16) for i in (1,3,5)] for h in palette_json['colors']],dtype=np.uint8)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def derivative(im, dest, width=None, size=None):
    a=np.array(im.convert('RGBA'))
    mask=a[:,:,3]>=128
    box=Image.fromarray(mask.astype('uint8')*255).getbbox()
    cropped=im.crop(box)
    if size is None:size=(width,round(cropped.height*width/cropped.width))
    near=np.array(cropped.resize(size,Image.Resampling.NEAREST))
    rgb=study.map_palette(near[:,:,:3],palette)
    alpha=np.where(near[:,:,3]>=128,255,0).astype(np.uint8)
    rgb[alpha==0]=0
    Image.fromarray(np.dstack([rgb,alpha]),'RGBA').save(dest)
    return {'threshold_crop_xyxy':list(box),'runtime_dimensions':list(size),'runtime_alpha_bounds_xyxy':list(Image.fromarray(alpha).getbbox()),'visible_pixels':int(np.count_nonzero(alpha)),'alpha_values':np.unique(alpha).tolist(),'visible_palette_color_count':int(len(np.unique(rgb[alpha>0],axis=0))),'runtime':str(dest.relative_to(ROOT)),'sha256':sha(dest)}
manifest=json.loads((ROOT/'source_art/2d_v5/props/manifest.json').read_text())
for item in manifest['items']:
    src=ROOT/item['runtime'];im=Image.open(src).convert('RGBA')
    width=410 if item['id']=='counter' else 300
    dest=ROOT/f"assets/2d_v5/props/{item['id']}-pixel.png"
    r=derivative(im,dest,width=width)
    r.update(anchor_bottom_center=[r['runtime_dimensions'][0]/2,r['runtime_dimensions'][1]],suggested_scene_bottom_center=[222,486] if item['id']=='counter' else [1115,486])
    item['runtime_derivative']=r
manifest['runtime_derivative_method']='Crop to alpha>=128 bounds; nearest-neighbor to native runtime dimensions; fixed reviewed96-color Oklab mapping without dithering; alpha threshold128; transparent RGB zeroed. Source artwork untouched.'
manifest['palette_source']='source_art/pixel_pipeline_studies/palette_96.json'
(ROOT/'source_art/2d_v5/props/manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('PROPS',[(i['id'],i['runtime_derivative']['runtime_dimensions']) for i in manifest['items']])
# Rectangles are measured from the generated atlas, with gutters, no pixels shared across parts.
regions={'cargo':(0,0,440,440),'beam':(440,0,975,440),'battery':(975,0,1340,440),'thruster':(1340,0,1774,440),'armor':(0,440,440,887),'coupler':(440,440,965,887),'spring':(965,440,1390,887),'connector':(1390,440,1774,887)}
asrc=ROOT/'source_art/2d_v5/modules/courier-kit-atlas-original.png';atlas=Image.open(asrc).convert('RGBA')
records=[]
for name, region in regions.items():
    cell=atlas.crop(region);box=cell.getchannel('A').getbbox();crop=cell.crop(box)
    source_crop=ROOT/f'source_art/2d_v5/modules/{name}-crop.png';crop.save(source_crop)
    lossless_dest=ROOT/f'assets/2d_v5/modules/{name}.png';crop.save(lossless_dest)
    dest=ROOT/f'assets/2d_v5/modules/{name}-pixel.png'
    size=(72,72) if name!='connector' else (20,20)
    r=derivative(crop,dest,size=size)
    r.update(id=name,atlas_region_xyxy=list(region),source_alpha_crop_in_region_xyxy=list(box),source_crop=str(source_crop.relative_to(ROOT)),source_crop_dimensions=list(crop.size),lossless_runtime=str(lossless_dest.relative_to(ROOT)),source_crop_sha256=sha(source_crop),anchor_center=[size[0]/2,size[1]/2],suggested_cardinal_sockets={'left':[0,size[1]/2],'right':[size[0],size[1]/2],'top':[size[0]/2,0],'bottom':[size[0]/2,size[1]]})
    records.append(r)
provenance=json.loads((ROOT/'source_art/2d_v5/modules/generation-provenance.json').read_text())
manifest={'generator':provenance['generator'],'prompt':provenance['prompt'],'references':provenance['references'],'original':str(asrc.relative_to(ROOT)),'original_dimensions':list(atlas.size),'original_sha256':sha(asrc),'source_crops':'Only lossless rectangular crops, no generated pixel changes. Each part is separately placed and independently damageable/detachable.','runtime_derivative_method':'Crop to alpha>=128 bounds; nearest-neighbor cell-fill normalization to72×72 (connector20×20); fixed reviewed96-color Oklab mapping, no dithering; binary alpha threshold128; transparent RGB zeroed. This deliberately normalizes differing atlas component aspect ratios to one square gameplay cell.','palette_source':'source_art/pixel_pipeline_studies/palette_96.json','starter_rows':[['thruster','beam','cargo','coupler'],['thruster','beam','battery','armor']],'starter_cell_px':72,'no_whole_ship_sprite':True,'parts':records}
(ROOT/'source_art/2d_v5/modules/manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('MODULES',[(r['id'],r['source_crop_dimensions'],r['runtime_dimensions']) for r in records])
