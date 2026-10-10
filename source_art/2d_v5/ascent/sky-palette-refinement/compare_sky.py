#!/usr/bin/env python3
"""Read-only runtime verification and evidence for source-only sky quantization."""
from pathlib import Path
import argparse, importlib.util, json, hashlib
import numpy as np
from PIL import Image, ImageDraw, ImageFont

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--assert-live-unchanged',action='store_true',help='Use before runtime release to enforce the live-asset freeze.')
args=parser.parse_args()
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
spec=importlib.util.spec_from_file_location('ascent_layers', ROOT/'tools/prepare_ascent_layers.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
source=Image.open(HERE.parent/'atmosphere-tall-original.png').convert('RGBA')
logical=np.array(source.resize((640,1280), Image.Resampling.NEAREST))
reference=Image.fromarray(logical,'RGBA').resize((1280,2560),Image.Resampling.NEAREST)
reference.save(HERE/'source-nearest-same-size.png')
items=[('Source / nearest 2 px grid',reference),
       ('Old / shared 96 palette',Image.open(HERE/'legacy96-reproduction/atmosphere-tall.png').convert('RGBA')),
       ('Source-only 128 palette',Image.open(HERE/'source128/atmosphere-tall.png').convert('RGBA')),
       ('Source-only 256 palette',Image.open(HERE/'source256/atmosphere-tall.png').convert('RGBA'))]
source_colors=set(map(tuple,np.unique(logical[...,:3].reshape(-1,3),axis=0)))
base=logical[:,8:-8,:3].astype(float)
report={'source_sha256':mod.sha(HERE.parent/'atmosphere-tall-original.png'),
        'selected':'source256/atmosphere-tall.png',
        'comparison_dimensions':[1280,2560], 'logical_grid_px':2,
        'method':'All images measured at the same final dimensions. Adjacent rows use logical 2 px cells, so repeated output rows do not hide jumps. Color error excludes only the existing 8-logical-texel edge bridges. No image blur, added dithering, resampling interpolation, generated gradients, or new scenery. Only the existing narrow edge repair blends seam samples.',
        'variants':{}}
for name,image in items:
    a=np.array(image); rgb=a[::2,::2,:3]; center=rgb[:,8:-8].astype(float)
    row_mean=center.mean(axis=1)
    jumps=np.abs(np.diff(row_mean,axis=0)).max(axis=1)
    # Row-mean motion identifies broad bands; per-pixel jumps also include authored dither.
    pixel_jumps=np.abs(np.diff(center,axis=0)).max(axis=2)
    colors=np.unique(rgb.reshape(-1,3),axis=0)
    coverage=[]
    for row in rgb:
        _, counts=np.unique(row,axis=0,return_counts=True);coverage.append(counts.max()/len(row))
    longest=run=0
    for cover in coverage:
        run=run+1 if cover>=.95 else 0;longest=max(longest,run)
    lab=mod.study.oklab(center);lab0=mod.study.oklab(base)
    de=np.linalg.norm(lab-lab0,axis=2)*100
    top=np.argsort(jumps)[-5:][::-1]
    report['variants'][name]={
       'unique_rgb':int(len(colors)), 'palette_colors_present_in_original':int(sum(tuple(c) in source_colors for c in colors)),
       'dimensions':list(image.size), 'alpha_values':np.unique(a[...,3]).tolist(),
       'strict_2px_grid':bool(np.array_equal(a[::2],a[1::2]) and np.array_equal(a[:,::2],a[:,1::2])),
       'exact_x_seam':bool(np.array_equal(a[:,0],a[:,-1])),
       'x_edge_max_channel_delta':int(np.max(np.abs(a[:,0].astype(int)-a[:,-1].astype(int)))),
       'row_mean_adjacent_max_channel_delta':{'max':float(jumps.max()),'median':float(np.median(jumps)),'p95':float(np.quantile(jumps,.95)),'p99':float(np.quantile(jumps,.99)), 'rows_over_2':int((jumps>2).sum()), 'rows_over_4':int((jumps>4).sum()),'largest_steps':[{'final_y':int((i+1)*2),'delta':float(jumps[i])} for i in top]},
       'per_pixel_adjacent_row_max_channel_delta':{'max':float(pixel_jumps.max()),'median':float(np.median(pixel_jumps)),'p95':float(np.quantile(pixel_jumps,.95)), 'p99':float(np.quantile(pixel_jumps,.99))},
       'longest_95_percent_single_color_row_region_final_px':int(longest*2),
       'source_error_excluding_seam':{'mean_abs_rgb':float(np.abs(center-base).mean()),'rmse_rgb':float(np.sqrt(np.square(center-base).mean())),'mean_oklab_x100':float(de.mean()),'p95_oklab_x100':float(np.quantile(de,.95))}}
font='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
smallfont=ImageFont.truetype(font,15);titlefont=ImageFont.truetype(font,22)
canvas=Image.new('RGB',(1320,720),'#10192b');draw=ImageDraw.Draw(canvas)
draw.text((12,8),'ATMOSPHERE PALETTE | Identical art, grid, final size; no new scenery',font=titlefont,fill='#e7eff7')
for i,(name,im) in enumerate(items):
    x=12+i*328; draw.text((x,44),name,font=smallfont,fill='#e7eff7')
    canvas.paste(im.convert('RGB').resize((320,640),Image.Resampling.NEAREST),(x,67))
canvas.save(HERE/'comparison-overview.png')
canvas=Image.new('RGB',(1320,380),'#10192b');draw=ImageDraw.Draw(canvas)
draw.text((12,8),'EXACT 1:1 DETAIL | x480..800, y1180..1500; final runtime pixels',font=titlefont,fill='#e7eff7')
for i,(name,im) in enumerate(items):
    x=12+i*328;draw.text((x,40),name,font=smallfont,fill='#e7eff7')
    canvas.paste(im.convert('RGB').crop((480,1180,800,1500)),(x,60))
canvas.save(HERE/'comparison-detail-1x.png')
# Exact ordinary-wrap proof uses only cropped source-derived pixels.
im=items[-1][1];seam=Image.new('RGBA',(64,2560))
seam.paste(im.crop((1248,0,1280,2560)),(0,0));seam.paste(im.crop((0,0,32,2560)),(32,0))
seam.save(HERE/'source256/exact-horizontal-wrap.png')
protected=json.loads((HERE/'protected-before.json').read_text())
report['protected_files_unchanged']={p:mod.sha(ROOT/p)==h for p,h in protected.items()}
if args.assert_live_unchanged:
    assert all(report['protected_files_unchanged'].values()),'Live asset or source unexpectedly changed'
assert all(report['variants'][n]['exact_x_seam'] for n in ['Source-only 128 palette','Source-only 256 palette'])
for n in ['Source-only 128 palette','Source-only 256 palette']:
    v=report['variants'][n];assert v['unique_rgb']==v['palette_colors_present_in_original'];assert v['strict_2px_grid'];assert v['alpha_values']==[255]
(HERE/'comparison-metrics.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
