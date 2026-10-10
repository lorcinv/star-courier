#!/usr/bin/env python3
"""Register the imagegen ground strip on the existing pixel grid, without drawing art.

The ordinary horizontal loop uses a narrow premultiplied edge repair. Originals
are immutable; there is no reflected/reversed tile or generated scene geometry.
"""
import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'source_art/2d_v5/ground/near-city-strip-original.png'
OUTPUT = ROOT / 'assets/2d_v5/ground/near-city-strip.png'
PROOFS = SOURCE.parent
spec = importlib.util.spec_from_file_location('ascent_preparation', ROOT/'tools/prepare_ascent_layers.py')
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    original_hash = sha(SOURCE)
    original = Image.open(SOURCE).convert('RGBA')
    samples = np.array(original.resize((640,320), Image.Resampling.NEAREST))
    before = pipeline.error(samples,1)
    samples = pipeline.bridge(samples,1,8)
    alpha = np.where(samples[...,3] >= 128,255,0).astype(np.uint8)
    rgb = pipeline.study.map_palette(samples[...,:3],pipeline.PALETTE)
    rgb[alpha == 0] = 0
    image = Image.fromarray(np.dstack([rgb,alpha]),'RGBA').resize((1280,640),Image.Resampling.NEAREST)
    pixels = np.array(image)
    after = pipeline.error(pixels,1)
    assert after['max_rgba_error'] == 0
    assert np.array_equal(pixels[::2,::2],pixels[1::2,1::2])
    assert np.array_equal(pixels[::2,::2],pixels[1::2,::2])
    assert np.array_equal(pixels[::2,::2],pixels[::2,1::2])
    assert set(np.unique(pixels[...,3])) == {0,255}
    assert sha(SOURCE) == original_hash
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    image.save(OUTPUT)
    # Actual neighboring end/start strips on source-derived sky, not a mirrored
    # or artistically painted comparison. Labels live in the JSON manifest.
    sky = Image.open(ROOT/'assets/2d_v5/ascent/atmosphere-tall.png').convert('RGBA')
    sky = sky.crop((0,1840,1280,2480))
    proof = Image.new('RGBA',(3840,640))
    for i in range(3):
        proof.alpha_composite(sky,(i*1280,0))
        proof.alpha_composite(image,(i*1280,0))
    proof.convert('RGB').save(PROOFS/'ordinary-loop-three-tiles.png')
    proof.crop((1152,320,1408,640)).resize((768,960),Image.Resampling.NEAREST).save(PROOFS/'ordinary-loop-seam-3x.png')
    manifest = {
        'source':str(SOURCE.relative_to(ROOT)), 'source_sha256':original_hash,
        'runtime':str(OUTPUT.relative_to(ROOT)), 'runtime_sha256':sha(OUTPUT),
        'original_dimensions':list(original.size), 'runtime_dimensions':[1280,640],
        'logical_grid_px':2, 'palette':'source_art/pixel_pipeline_studies/palette_96.json',
        'alpha_values':[0,255], 'horizontal_edge_before':before, 'horizontal_edge_after':after,
        'edge_repair_logical_texels':8, 'ordinary_repeat_x':True, 'repeat_y':False,
        'mirroring':False, 'source_changed':False,
        'method':'Uniform nearest sampling, existing reference96 Oklab mapping, binary alpha128, eight-texel premultiplied periodic edge repair; no procedural illustration.',
        'status':'Asset derivative only; not yet a playable ground route.'}
    (PROOFS/'ground-layer-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(manifest,ensure_ascii=False))


if __name__ == '__main__':
    main()
