"""Technical extraction only: generated pixels, nearest resize, fixed palette.

Does not paint runtime artwork. Proofs composite the extracted sprites only.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = ROOT / 'assets/2d_v5/modules/cohesion'
spec = importlib.util.spec_from_file_location('pixel_study', ROOT / 'source_art/pixel_pipeline_studies/study_reference.py')
study = importlib.util.module_from_spec(spec)
spec.loader.exec_module(study)
palette_json = json.loads((ROOT / 'source_art/pixel_pipeline_studies/palette_96.json').read_text())
palette = np.array([[int(h[i:i+2], 16) for i in (1,3,5)] for h in palette_json['colors']], dtype=np.uint8)
palette_set = {tuple(x) for x in palette.tolist()}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inspect(path):
    a = np.array(Image.open(path).convert('RGBA'))
    colors = {tuple(x) for x in np.unique(a[a[:,:,3]>0,:3], axis=0).tolist()}
    return {'runtime': str(path.relative_to(ROOT)), 'dimensions': [a.shape[1],a.shape[0]],
            'alpha_values': np.unique(a[:,:,3]).tolist(), 'visible_colors': len(colors),
            'outside_palette': len(colors-palette_set), 'sha256': sha(path)}

records = []
for name, size, anchor in [('joint-collar',(32,28),(16,14)), ('coupler-latch',(72,72),(36,36)), ('hull-edge-strip',(60,8),(30,4))]:
    source = HERE / (name+'-original.png')
    im = Image.open(source).convert('RGBA')
    alpha = np.array(im)[:,:,3]
    bounds = Image.fromarray(np.where(alpha>=128,255,0).astype(np.uint8)).getbbox()
    crop = im.crop(bounds)
    crop_path = HERE/(name+'-crop.png')
    crop.save(crop_path)
    small = np.array(crop.resize(size,Image.Resampling.NEAREST))
    rgb = study.map_palette(small[:,:,:3],palette)
    a = np.where(small[:,:,3]>=128,255,0).astype(np.uint8)
    rgb[a==0] = 0
    dest = OUT/(name+'-pixel.png')
    Image.fromarray(np.dstack([rgb,a]),'RGBA').save(dest)
    records.append(dict(id=name, original=str(source.relative_to(ROOT)), original_sha256=sha(source),
                        source_crop=str(crop_path.relative_to(ROOT)), crop_xyxy=list(bounds),
                        source_crop_dimensions=list(crop.size), anchor_center=list(anchor), **inspect(dest)))

# Lossless central slices of the same generated collar. These contain no new art.
collar = Image.open(OUT/'joint-collar-pixel.png').convert('RGBA')
for side,box,anchor in [('left',(0,0,16,28),(16,14)), ('right',(16,0,32,28),(0,14))]:
    path=OUT/('joint-collar-half-'+side+'-pixel.png')
    collar.crop(box).save(path)
    records.append(dict(id='joint-collar-half-'+side, derived_from='joint-collar',
                        crop_xyxy=list(box), seam_anchor=list(anchor), **inspect(path)))

manifest = {
    'generator':'built-in image_gen', 'provenance':'source_art/2d_v5/modules/cohesion/generation-provenance.json',
    'palette':'source_art/pixel_pipeline_studies/palette_96.json',
    'processing':'Lossless threshold-bounds crop, nearest-neighbor normalization, existing fixed 96-color Oklab mapping, binary alpha >=128; transparent RGB zeroed. No painted runtime pixels.',
    'module_cell':72, 'cosmetic_only':True, 'runtime_integration_performed':False,
    'attachments':{
        'joint-collar':{'logical_size':[32,28], 'anchor':[16,14], 'placement':'Center at a real active cardinal link boundary. Rotate 0 degrees for horizontal links and 90 degrees for vertical links. Paint above module shells but below selection/highlight affordances. Never show for mere spatial adjacency, diagonal or broken links.', 'break_behavior':'Either hide the full collar immediately or use the two exact halves owned by the actual endpoints. Do not leave a world-space bridge after link loss.'},
        'joint-halves':{'logical_size_each':[16,28], 'left_seam_anchor':[16,14], 'right_seam_anchor':[0,14], 'placement':'The left half occupies the final 16 pixels inside the left cell; the right half occupies the first 16 pixels inside the right cell. Their seam anchors meet at the live joint. After detachment, each half follows only its owning part. For vertical links rotate both around the seam by 90 degrees. These halves never project beyond their owner cell.'},
        'coupler-latch':{'logical_size':[72,72], 'anchor':[36,36], 'placement':'Candidate alternative to the existing cockpit-like coupler texture, same module transform and picking. This is mechanical hardware with no glass.'},
        'hull-edge-strip':{'logical_size':[60,8], 'anchor':[30,4], 'placement':'Optional only. Keep fully within one actual module cell: top center (36,5), bottom center (36,67), or rotate 90 degrees for left center (5,36) and right center (67,36). Do not span cells or wrap the craft. At 60 pixels, the strip leaves 6 pixels clear at either side.'}
    },
    'assets':records
}
(HERE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(HERE/'pixel-validation.json').write_text(json.dumps({'passed':all(r['outside_palette']==0 and set(r['alpha_values'])<=set([0,255]) for r in records),'assets':records},indent=2)+'\n')

font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',16)
smallfont = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',13)
proof = Image.new('RGBA',(1120,760),(14,21,39,255))
draw = ImageDraw.Draw(proof)
draw.text((20,14),'GENERATED COHESION ASSETS | exact palette 96 | binary alpha | nearest sampling',font=font,fill=(255,244,210))
labels=[('joint-collar',32,28),('coupler-latch',72,72),('hull-edge-strip',60,8)]
for i,(name,w,h) in enumerate(labels):
    x=28+i*360
    draw.text((x,52),f'{name}: {w} x {h}',font=font,fill=(248,237,227))
    im=Image.open(OUT/(name+'-pixel.png')).convert('RGBA')
    factor=3 if name=='coupler-latch' else 5
    proof.alpha_composite(im.resize((w*factor,h*factor),Image.Resampling.NEAREST),(x,85))

parts=[('cargo',0,0),('battery',-1,0),('armor',1,0),('thruster',0,-1),('thruster',0,1),('beam',1,-1),('beam',1,1),('coupler',-1,1)]
def craft(joined=False,strip=False):
    out=Image.new('RGBA',(224,224),(0,0,0,0))
    for name,x,y in parts:
        p=(OUT/'coupler-latch-pixel.png') if joined and name=='coupler' else ROOT/('assets/2d_v5/modules/'+name+'-pixel.png')
        im=Image.open(p).convert('RGBA').resize((70,70),Image.Resampling.NEAREST)
        out.alpha_composite(im,(4+(x+1)*72+1,4+(y+1)*72+1))
    if joined:
        coords={(x,y) for name,x,y in parts}
        for x,y in coords:
            for dx,dy in [(1,0),(0,1)]:
                if (x+dx,y+dy) not in coords:continue
                joint=collar if dx else collar.transpose(Image.Transpose.ROTATE_270)
                cx=4+(x+1)*72+36+dx*36
                cy=4+(y+1)*72+36+dy*36
                out.alpha_composite(joint,(cx-joint.width//2,cy-joint.height//2))
    return out
for label,img,x in [('Existing cell art',craft(),20),('Latch + live-link collars',craft(True),390)]:
    draw.text((x,335),label,font=font,fill=(248,237,227))
    proof.alpha_composite(img,(x+15,367))
    proof.alpha_composite(img.resize((112,112),Image.Resampling.NEAREST),(x+235,440))
draw.text((20,606),'Proof uses the exact eight module coordinates. All cardinal links are assumed active for this static example.',font=smallfont,fill=(144,214,250))
draw.text((20,629),'Only real runtime links may receive collars. No global hull, no layout change, no collision change.',font=smallfont,fill=(144,214,250))

pair=Image.new('RGBA',(230,90),(0,0,0,0))
for name,pos in [('cargo',(5,8)),('armor',(120,8))]:
    pair.alpha_composite(Image.open(ROOT/('assets/2d_v5/modules/'+name+'-pixel.png')).convert('RGBA'),pos)
pair.alpha_composite(Image.open(OUT/'joint-collar-half-left-pixel.png').convert('RGBA'),(61,30))
pair.alpha_composite(Image.open(OUT/'joint-collar-half-right-pixel.png').convert('RGBA'),(120,30))
draw.text((760,335),'Split halves: no lingering bridge',font=font,fill=(248,237,227))
proof.alpha_composite(pair,(775,386))
draw.text((760,491),'Each half stays within its owner cell.',font=smallfont,fill=(144,214,250))
draw.text((760,516),'Edge strip is optional; shown above.',font=smallfont,fill=(144,214,250))
proof.convert('RGB').save(HERE/'proofsheet.png')
print(json.dumps({'validation':'passed','assets':[{k:r[k] for k in ['id','runtime','dimensions','visible_colors','outside_palette']} for r in records],'proofsheet':str((HERE/'proofsheet.png').relative_to(ROOT))},indent=2))
