#!/usr/bin/env python3
"""Reproducible technical derivatives of inspected imagegen layer originals.

No source artwork is changed and no illustration is drawn. Crop, nearest sample,
shared reference-derived palette (or a dedicated source-only sky palette), alpha
threshold and narrow periodic edge repair are the complete operation set. See the manifest for measured edge errors.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json
import numpy as np
from PIL import Image
from scipy.ndimage import label, find_objects

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'source_art/2d_v5/ascent'
OUT = ROOT / 'assets/2d_v5/ascent'
spec = importlib.util.spec_from_file_location('pixel_study', ROOT / 'source_art/pixel_pipeline_studies/study_reference.py')
study = importlib.util.module_from_spec(spec)
spec.loader.exec_module(study)
PALETTE_PATH = ROOT / 'source_art/pixel_pipeline_studies/palette_96.json'
PALETTE = np.array([[int(h[i:i+2], 16) for i in (1,3,5)] for h in json.loads(PALETTE_PATH.read_text())['colors']], dtype=np.uint8)
records = []

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def error(a, axis):
    p = a.astype(np.float32)
    p[...,:3] *= p[...,3:] / 255
    edge0, edge1 = np.take(p,0,axis=axis), np.take(p,-1,axis=axis)
    return {'max_rgba_error':float(np.abs(edge0-edge1).max()), 'mean_rgba_error':float(np.abs(edge0-edge1).mean())}

def bridge(a, axis, width):
    """Bring opposite edge strips to the same premultiplied sample profile.

    Direct-side samples only, never reversed/mirrored. The two boundary columns
    become identical; unchanged interior pixels retain all authored orientation.
    """
    p = np.swapaxes(a.astype(np.float32), 0, axis)
    p[...,:3] *= p[...,3:] / 255
    shared = (p[0] + p[-1]) * .5
    first, last = p[0].copy(), p[-1].copy()
    for i in range(width):
        t = 1.0 - i / width
        t = t*t*(3-2*t)
        p[i] += (shared-first)*t
        p[-1-i] += (shared-last)*t
    p[...,:3] = p[...,:3] * 255 / np.maximum(p[...,3:],1)
    return np.rint(np.swapaxes(p,0,axis).clip(0,255)).astype(np.uint8)

def source_palette(rgb, count):
    """Median-cut coverage snapped back to actual colors in this source asset.

    The broad sky needs its own blue ramp: the shared shop-reference palette
    collapses it into very few blue colors. No new dither or gradient is made.
    Source pixel representatives and perceptual mapping reuse the reviewed
    project-local Oklab study, rather than running downloaded programs.
    """
    samples = np.unique(rgb.reshape(-1, 3), axis=0)
    seed = Image.fromarray(rgb, 'RGB').quantize(
        colors=count, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    centers = np.array(seed.getpalette(), dtype=np.uint8).reshape(-1, 3)[:count]
    nearest = study.cdist(study.oklab(centers), study.oklab(samples), 'sqeuclidean').argmin(axis=1)
    palette = np.unique(samples[nearest], axis=0)
    return palette[np.argsort(study.oklab(palette)[:, 0], kind='stable')]

def save(name, source, size, crop=None, seam_x=0, seam_y=0, repeat_y=True,
         logical_grid=1, island_scale=1.0, sky_colors=0, output_dir=OUT):
    original = Image.open(source).convert('RGBA')
    image = original.crop(crop) if crop else original
    a = np.array(image.resize((size[0]//logical_grid,size[1]//logical_grid), Image.Resampling.NEAREST))
    if island_scale < 1.0:
        # Technical nearest reduction of each authored dust island about its
        # existing center. No random placement and no new stars/shapes.
        labels, count = label(a[...,3] >= 128)
        smaller = np.zeros_like(a)
        for index, region in enumerate(find_objects(labels),1):
            if region is None:continue
            ys,xs=region; island=a[ys,xs].copy();island[labels[ys,xs]!=index]=0
            h,w=island.shape[:2]
            nw,nh=max(1,round(w*island_scale)),max(1,round(h*island_scale))
            reduced=np.array(Image.fromarray(island,'RGBA').resize((nw,nh),Image.Resampling.NEAREST))
            x=xs.start+(w-nw)//2;y=ys.start+(h-nh)//2
            area=smaller[y:y+nh,x:x+nw];take=reduced[...,3]>=128;area[take]=reduced[take]
        a=smaller
    palette = source_palette(a[..., :3], sky_colors) if sky_colors else PALETTE
    palette_info = {'mode': 'source-only-adaptive' if sky_colors else 'shared-reference',
                    'requested_colors': sky_colors or len(PALETTE),
                    'actual_palette_colors': len(palette),
                    'new_dither': False}
    output_dir.mkdir(parents=True, exist_ok=True)
    if sky_colors:
        palette_path = output_dir / ('sky-palette-source%d.json' % sky_colors)
        palette_path.write_text(json.dumps({
            'name': 'Ascent source-only sky %d' % sky_colors,
            'source': str(source.relative_to(ROOT)), 'source_sha256': sha(source),
            'method': 'Median-cut seeds; Oklab nearest actual source colors; no added dither.',
            'colors': ['#' + ''.join('%02x' % int(c) for c in color) for color in palette]
        }, indent=2) + '\n')
        palette_info.update({'path': str(palette_path.relative_to(ROOT)),
                             'sha256': sha(palette_path)})
    before = {'x':error(a,1),'y':error(a,0)}
    if seam_x:a=bridge(a,1,seam_x)
    if seam_y:a=bridge(a,0,seam_y)
    alpha = np.where(a[...,3]>=128,255,0).astype(np.uint8)
    rgb=study.map_palette(a[...,:3],palette);rgb[alpha==0]=0
    image = Image.fromarray(np.dstack((rgb,alpha)), 'RGBA')
    if logical_grid != 1:image=image.resize(size,Image.Resampling.NEAREST)
    a=np.array(image)
    path=output_dir/(name+'.png')
    temporary=path.with_name(path.stem+'.staging.png')
    image.save(temporary);temporary.replace(path)  # Publish each finished PNG atomically.
    after={'x':error(a,1),'y':error(a,0)}
    if seam_x or before['x']['max_rgba_error']==0:assert after['x']['max_rgba_error']==0
    if repeat_y:assert after['y']['max_rgba_error']==0
    bbox=Image.fromarray(a[...,3]).getbbox()
    record={'name':name,'source':str(source.relative_to(ROOT)),'source_sha256':sha(source),'runtime':str(path.relative_to(ROOT)),'runtime_sha256':sha(path),'source_dimensions':list(original.size),'dimensions':list(size),'crop':crop,'nearest_grid_px':logical_grid,'palette':palette_info,'authored_island_scale':island_scale,'alpha_threshold':128,'alpha_values':np.unique(a[...,3]).tolist(),'visible_palette_colors':int(len(np.unique(a[...,:3][a[...,3]>0],axis=0))),'alpha_bbox':bbox,'edge_repair_grid_texels':{'x':seam_x,'y':seam_y},'repeat':{'x':name!='planet-limb','y':repeat_y},'edge_before':before,'edge_after':after}
    if name == 'atmosphere-tall':
        proof_dir = SRC if output_dir == OUT else output_dir
        proof_path = proof_dir / 'atmosphere-tall-ordinary-wrap-seam-proof.png'
        seam = Image.new('RGBA', (96, image.height))
        seam.paste(image.crop((image.width-48, 0, image.width, image.height)), (0, 0))
        seam.paste(image.crop((0, 0, 48, image.height)), (48, 0))
        seam.save(proof_path)
        record['seam_proof'] = str(proof_path.relative_to(ROOT))
        record['seam_proof_sha256'] = sha(proof_path)
    records.append(record)
    # Exact runtime edge composite, not just an alpha check: two adjacent tiles.
    # Source-derived sky patch serves as the opaque underlay for alpha layers.
    if name not in ['atmosphere-tall','planet-limb']:
        patch=Image.open(output_dir/'atmosphere-tall.png').convert('RGBA').crop((0,1840,1280,2560))
        band=Image.new('RGBA',(96,min(720,image.height)))
        band.alpha_composite(image.crop((image.width-48,0,image.width,band.height)),(0,0))
        band.alpha_composite(image.crop((0,0,48,band.height)),(48,0))
        under=patch.crop((592,0,688,band.height));under.alpha_composite(band)
        proof_dir = SRC if output_dir == OUT else output_dir
        under.resize((384,band.height*4),Image.Resampling.NEAREST).save(proof_dir/(name+'-ordinary-wrap-seam-proof.png'))
    return image

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sky-only', action='store_true',
                        help='Prepare only the atmosphere; no other layer or seam proof is touched.')
    parser.add_argument('--sky-colors', type=int, choices=(0, 128, 256), default=256,
                        help='Source-only adaptive sky colors. 0 reproduces the old shared palette.')
    parser.add_argument('--output-dir', type=Path, default=OUT,
                        help='Use an isolated directory for unreleased candidates.')
    args = parser.parse_args()
    output_dir = args.output_dir.resolve()
    output_dir.relative_to(ROOT)  # Evidence paths and candidates stay inside the project.
    save('atmosphere-tall', SRC/'atmosphere-tall-original.png', (1280,2560),
         seam_x=8, repeat_y=False, logical_grid=2, sky_colors=args.sky_colors,
         output_dir=output_dir)
    if not args.sky_only:
        save('far-city-band',SRC/'far-city-band-original.png',(1280,640),seam_x=6,repeat_y=False,logical_grid=2,output_dir=output_dir)
        save('cloud-banks',SRC/'cloud-banks-original.png',(1280,640),logical_grid=2,output_dir=output_dir)
        save('cloud-wisps',SRC/'cloud-wisps-original.png',(1280,640),logical_grid=2,output_dir=output_dir)
        save('orbit-dust',SRC/'orbit-dust-original.png',(1280,640),logical_grid=2,island_scale=0.25,output_dir=output_dir)
        # Inspected quiet central upper crop excludes both the planetary arc and the
        # broad nebula ribbons that read as horizontal bands when the full crop tiled.
        # A narrow two-axis edge bridge makes an ordinary tile without mirrored stars.
        save('orbit-stars',ROOT/'source_art/2d_v5/space/orbit-far-panorama.png',(1280,720),crop=(643,8,1191,317),seam_x=16,seam_y=16,logical_grid=2,output_dir=output_dir)
        # This is the already-inspected alpha-extracted original limb, not a new painting.
        # It never repeats in either axis. Keeping a separate file preserves v1 replay.
        planet_source=ROOT/'assets/2d_v5/space/orbit-planet-limb.png'
        planet=Image.open(planet_source).convert('RGBA');planet.save(output_dir/'planet-limb.png')
        records.append({'name':'planet-limb','source':'source_art/2d_v5/space/orbit-far-panorama.png','source_sha256':sha(ROOT/'source_art/2d_v5/space/orbit-far-panorama.png'),'existing_derivative':str(planet_source.relative_to(ROOT)),'existing_derivative_sha256':sha(planet_source),'runtime':str((output_dir/'planet-limb.png').relative_to(ROOT)),'runtime_sha256':sha(output_dir/'planet-limb.png'),'dimensions':list(planet.size),'repeat':{'x':False,'y':False},'operation':'Copy preserved v1 alpha-extracted original; clamp horizontal drift, transparent outside vertical bounds.'})
    manifest_path = SRC/'technical-manifest.json' if output_dir == OUT else output_dir/'technical-manifest.json'
    manifest = json.loads(manifest_path.read_text()) if args.sky_only and manifest_path.exists() else {}
    previous = manifest.get('assets', []) if args.sky_only else []
    names = {r['name'] for r in records}
    all_records = records + [r for r in previous if r['name'] not in names]
    sky_method = 'source-only adaptive sky palette' if args.sky_colors else 'shared reference-derived Oklab96 sky palette'
    manifest.update({
        'method': 'Imagegen originals only; originals unchanged. Nearest sampling onto explicit 2px grid; '+sky_method+' and shared reference-derived Oklab96 palette for other layers; binary alpha128; narrow premultiplied technical edge bridges. No added dithering, generated gradients, mirrored or reversed tiles, or procedural illustration.',
        'palette': str(PALETTE_PATH.relative_to(ROOT)), 'palette_sha256': sha(PALETTE_PATH),
        'sky_palette_colors': args.sky_colors, 'assets': all_records,
        'seam_validation': 'Edge errors measured on final actual RGBA derivatives. Transparent margins alone are sufficient for both cloud layers. City/sky/star edges required repairs; generation was not assumed seamless. Seam proof crops composite actual opposite edges over an authored sky crop.'
    })
    manifest_path.write_text(json.dumps(manifest, indent=2)+'\n')
    print(json.dumps({'assets': len(records), 'output_dir': str(output_dir.relative_to(ROOT)),
                      'exact_x_seams': [r['name'] for r in records if r.get('edge_after',{}).get('x',{}).get('max_rgba_error')==0],
                      'source_hashes': [r['source_sha256'] for r in records]}, indent=2))

if __name__ == '__main__':
    main()
