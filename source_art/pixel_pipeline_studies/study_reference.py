#!/usr/bin/env python3
"""Bounded, local pixel-grid/palette study. Never modifies the approved source.

Research-informed project code, not an execution of downloaded GitHub programs.
The Oklab formula and cell-reduction comparison follow the reviewed MIT projects
Hugo-Dz/spritefusion-pixel-snapper and kenyonxu/pixel-game-kit. See licenses/ and
github_sources.json. Our study deliberately uses an explicit uniform target grid,
existing-pixel medoids, and fixed scene-derived palettes instead of claiming to
recover one unique grid from the AI image. No creative pixels are regenerated.
"""
from pathlib import Path
import hashlib
import json
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.spatial.distance import cdist

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'art_direction_v4/pixel-cel-shop-reference-03.png'
SOURCE_HASH = 'bd9388bd6cb6784572cabd0eca876bb6fce9a6d7c538438128d22d8367242cae'
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
REGIONS = {
    'clerk': (270, 350, 410, 510),
    'craft': (715, 287, 1140, 520),
    'warm_cool': (1130, 135, 1480, 465),
}
ANCHORS = [
    ('ink', '#111a35', (715,287,1140,520)),
    ('hair_cobalt', '#165da5', (280,350,402,485)),
    ('hair_coral', '#ee807b', (330,375,382,485)),
    ('eye_turquoise', '#23b9d4', (307,407,356,449)),
    ('skin_light', '#f6d1a9', (295,389,369,454)),
    ('skin_shadow', '#df9d7d', (295,389,369,454)),
    ('craft_sunflower', '#f7c526', (840,342,1125,500)),
    ('craft_ochre', '#bb7722', (840,342,1125,500)),
    ('craft_cyan', '#5cdef0', (850,290,1050,401)),
    ('sky_cyan', '#70cfeb', (1390,132,1650,435)),
    ('city_blue', '#8eb8eb', (1260,200,1672,570)),
    ('warm_cream', '#fff5d1', (1280,80,1600,250)),
]


def oklab(rgb):
    x = np.asarray(rgb, dtype=np.float32) / 255
    lin = np.where(x <= .04045, x / 12.92, ((x + .055) / 1.055) ** 2.4)
    a = np.array([[.4122214708, .5363325363, .0514459929],
                  [.2119034982, .6806995451, .1073969566],
                  [.0883024619, .2817188376, .6299787005]], dtype=np.float32)
    b = np.array([[.2104542553, .7936177850, -.0040720468],
                  [1.9779984951, -2.4285922050, .4505937099],
                  [.0259040371, .7827717662, -.8086757660]], dtype=np.float32)
    return np.cbrt(lin @ a.T) @ b.T


def grid_medoid(rgb, wh):
    """One existing source pixel per equal logical cell, no blended colors.

    For a fractional input-to-logical ratio, rounded source cuts alternate in
    width. The OUTPUT grid always has exactly one texel per cell; its enlarged
    version is strictly integer-scaled. The rounding map is recorded separately.
    """
    ih, iw = rgb.shape[:2]
    ow, oh = wh
    xs = np.rint(np.linspace(0, iw, ow + 1)).astype(int)
    ys = np.rint(np.linspace(0, ih, oh + 1)).astype(int)
    samples, valid, center = [], [], []
    for dy in range(int(np.max(np.diff(ys)))):
        for dx in range(int(np.max(np.diff(xs)))):
            gx, gy = xs[:-1] + dx, ys[:-1] + dy
            good = ((gy < ys[1:])[:, None] & (gx < xs[1:])[None, :])
            samples.append(rgb[np.minimum(gy, ih-1)[:, None], np.minimum(gx, iw-1)[None, :]])
            valid.append(good)
            center.append(((dx - (np.diff(xs)-1)*.5)[None, :]**2
                           + (dy - (np.diff(ys)-1)*.5)[:, None]**2))
    s = np.stack(samples, axis=2)
    v = np.stack(valid, axis=2)
    med = np.nanmedian(np.where(v[..., None], s.astype(float), np.nan), axis=2)
    distance = np.sum((s.astype(float) - med[:, :, None]) ** 2, axis=3)
    distance += np.stack(center, axis=2) * .0001
    distance[~v] = np.inf
    winner = np.argmin(distance, axis=2)
    out = np.take_along_axis(s, winner[..., None, None], axis=2)[:, :, 0, :]
    return out, {'columns': xs.tolist(), 'rows': ys.tolist()}


def weighted_palette(rgb, count):
    """Deterministic, source-derived shared palette, with face/craft weighting.

    Lloyd clustering in Oklab is standard math. Centers are snapped back to
    actual source colors so this study never invents a new creative color.
    Sampling weights protect small face/eye/craft accents from the large sky.
    """
    h, w = rgb.shape[:2]
    weights = np.ones((h, w), dtype=np.float64)
    for name, box in REGIONS.items():
        x0, y0, x1, y1 = box
        x0, x1 = round(x0*w/1672), round(x1*w/1672)
        y0, y1 = round(y0*h/941), round(y1*h/941)
        weights[y0:y1, x0:x1] += 7 if name == 'clerk' else (2 if name == 'craft' else 0)
    flat = rgb.reshape(-1, 3)
    # Compact 5-bit color buckets, retain an actual representative per bucket.
    key = ((flat[:, 0].astype(int)//8)*1024 + (flat[:, 1].astype(int)//8)*32 + flat[:, 2]//8)
    keys, first, inverse = np.unique(key, return_index=True, return_inverse=True)
    colors = flat[first]
    counts = np.bincount(inverse, weights=weights.ravel())
    lab = oklab(colors)
    # Median-cut offers a deterministic broad coverage seed; all refinement
    # uses the same weighted scene samples and no frame-dependent randomness.
    anchors=[]
    if count>=64:
        for name,hexcolor,box in ANCHORS:
            x0,y0,x1,y1=box
            region=rgb[round(y0*h/941):round(y1*h/941),round(x0*w/1672):round(x1*w/1672)].reshape(-1,3)
            target=np.array([int(hexcolor[i:i+2],16) for i in (1,3,5)],dtype=np.uint8)
            selected=cdist(oklab(region),oklab(target[None]),'sqeuclidean').argmin()
            anchors.append(region[selected])
    fixed=len(anchors)
    seed = Image.fromarray(rgb).quantize(colors=count-fixed, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    centers = oklab(np.array(seed.getpalette(), dtype=np.uint8).reshape(-1, 3)[:count-fixed])
    if fixed: centers=np.concatenate([oklab(np.array(anchors)),centers])
    for _ in range(16):
        labels = cdist(lab, centers, 'sqeuclidean').argmin(axis=1)
        updated = centers.copy()
        for i in range(fixed,count):
            m = labels == i
            if m.any():
                updated[i] = np.average(lab[m], weights=counts[m], axis=0)
        if np.max(abs(updated - centers)) < .00002:
            centers = updated
            break
        centers = updated
    selected = cdist(centers, lab, 'sqeuclidean').argmin(axis=1)
    palette = colors[selected]
    if fixed: palette[:fixed]=np.array(anchors)
    # Stable ordering makes exported palettes practical for pixel editors.
    palette = palette[np.argsort(oklab(palette)[:, 0], kind='stable')]
    return palette


def map_palette(rgb, palette):
    lab = oklab(rgb.reshape(-1, 3))
    plab = oklab(palette)
    labels = np.concatenate([cdist(lab[i:i+8192], plab, 'sqeuclidean').argmin(axis=1)
                             for i in range(0, len(lab), 8192)])
    return palette[labels].reshape(rgb.shape)


def save_palette(palette, count):
    colors = ['#'+''.join(f'{int(c):02x}' for c in p) for p in palette]
    (ROOT / f'palette_{count}.json').write_text(json.dumps({'name': f'Courier reference {count}',
        'source_sha256': SOURCE_HASH, 'colors': colors, 'dither': 'none',
        'method': 'weighted Oklab; source-pixel representatives; 12 measured accent anchors for 64/96; fixed across frames'}, indent=2)+'\n')
    lines = ['GIMP Palette', f'Name: Courier reference {count}', 'Columns: 16', '#']
    lines += ['%3d %3d %3d\t%s' % (*p, colors[i]) for i,p in enumerate(palette)]
    (ROOT / f'palette_{count}.gpl').write_text('\n'.join(lines)+'\n')


def text(canvas, at, string, size=20, fill='#e7eff7'):
    ImageDraw.Draw(canvas).text(at, string, font=ImageFont.truetype(FONT, size), fill=fill)


def fit_nearest(im, wh):
    # Evidence contact-sheet panels have arbitrary display dimensions; the
    # production preview below, in contrast, always uses exact integer scale.
    return im.resize(wh, Image.Resampling.NEAREST)


def compare_sheet(original, variants):
    items = [('Original: 461,254 colors', original)] + variants
    panel_w, panel_h = 640, 360
    c = Image.new('RGB', (2*panel_w+48, 3*(panel_h+48)+64), '#10192b')
    text(c, (20, 10), 'REFERENCE CLEANUP | Same art, uniform output grid', 24)
    for i, (label, im) in enumerate(items):
        x, y = 16+(i%2)*(panel_w+16), 52+(i//2)*(panel_h+48)
        text(c, (x, y), label, 18)
        c.paste(fit_nearest(im, (panel_w, panel_h)), (x, y+30))
    text(c, (20, c.height-28), 'Contact-sheet panels are for composition. Inspect the separate exact-integer crops for pixel QA.', 15)
    c.save(ROOT/'comparison_overview.png')


def crop_sheet(original, variants, name):
    box = REGIONS[name]
    x0,y0,x1,y1=box
    # Use a crop region aligned to the chosen 640x360 output grid for all cells.
    crop = (round(x0*640/1672), round(y0*360/941), round(x1*640/1672), round(y1*360/941))
    scale = 8 if name=='clerk' else 3
    cw,ch=(crop[2]-crop[0])*scale,(crop[3]-crop[1])*scale
    original_crop=original.crop(tuple(round(v*(1672/640 if j%2==0 else 941/360)) for j,v in enumerate(crop)))
    items = [('Original detail (enlarged)', fit_nearest(original_crop,(cw,ch)))]
    for label,im in variants:
        if im.size != (640,360): continue
        items.append((label, im.crop(crop).resize((cw,ch),Image.Resampling.NEAREST)))
    c=Image.new('RGB',(3*cw+64,2*(ch+46)+66),'#10192b')
    text(c,(16,10),f'{name.upper()} | exact {scale}x logical texels on cleaned crops',23)
    for i,(label,im) in enumerate(items):
        x,y=16+(i%3)*(cw+16),50+(i//3)*(ch+46)
        text(c,(x,y),label,15);c.paste(im,(x,y+28))
    c.save(ROOT/f'comparison_{name}.png')


def main():
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_HASH
    original=Image.open(SOURCE).convert('RGB');rgb=np.array(original)
    report={'source':str(SOURCE.relative_to(ROOT.parent.parent)), 'source_sha256':SOURCE_HASH,
            'source_size':list(original.size),'source_unique_rgb':len(np.unique(rgb.reshape(-1,3),axis=0)),
            'generator':'study_reference.py; project-native bounded processing; no downloaded executables',
            'variants':{},'notes':['Source art is never overwritten.',
              '640x360 is a selected production grid, not a claim about the AI image\'s original grid.',
              'Palette fitting is shared once; never fit a new palette independently per animation frame.',
              'No new dithering. Existing art is reduced only.']}
    outputs={}
    for wh in [(640,360),(480,270),(560,315)]:
        a,cuts=grid_medoid(rgb,wh);name=f'grid_only_{wh[0]}x{wh[1]}'
        im=Image.fromarray(a);im.save(ROOT/f'{name}.png');outputs[name]=im
        (ROOT/f'{name}_source_cuts.json').write_text(json.dumps(cuts)+'\n')
        report['variants'][name]={'logical_size':list(wh),'unique_rgb':len(np.unique(a.reshape(-1,3),axis=0))}
    base=np.array(outputs['grid_only_640x360'])
    for count in (96,64,16):
        pal=weighted_palette(base,count);save_palette(pal,count)
        a=map_palette(base,pal);name=f'clean_{count}c_640x360';im=Image.fromarray(a)
        outputs[name]=im;im.save(ROOT/f'{name}.png')
        delta=np.linalg.norm(oklab(a)-oklab(base),axis=2)
        report['variants'][name]={'logical_size':[640,360], 'unique_rgb':len(np.unique(a.reshape(-1,3),axis=0)),
            'palette_colors':len(pal), 'dither':'none','mean_oklab_delta_vs_grid_only':float(delta.mean()),
            'p95_oklab_delta_vs_grid_only':float(np.percentile(delta,95))}
        if count in (64,96):
            large=im.resize((3840,2160),Image.Resampling.NEAREST)
            large.save(ROOT/f'{name}_4k_nearest6x.png')
            # A direct independent pixel equality test, stronger than a filename.
            blocks=np.array(large).reshape(360,6,640,6,3)
            equal=bool(np.all(blocks==a[:,None,:,None,:]))
            report['variants'][name]['4k_blocks_exact_6x6']=equal
            assert equal
    variants=[('Grid only: 640x360',outputs['grid_only_640x360']),
              ('Anchored palette: 96-color budget',outputs['clean_96c_640x360']),
              ('Anchored palette: 64-color budget',outputs['clean_64c_640x360']),
              ('Aggressive control: 16 colors',outputs['clean_16c_640x360']),
              ('Coarser grid only: 480x270',outputs['grid_only_480x270'])]
    compare_sheet(original,variants)
    for name in REGIONS:crop_sheet(original,variants,name)
    # Clearly separate the minimum-change choice from the stricter palette study.
    report['recommended']='clean_96c_640x360 for palette-lock study; grid_only_640x360 if preserving subtle colors is paramount'
    (ROOT/'study_metrics.json').write_text(json.dumps(report,indent=2)+'\n')
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_HASH
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
