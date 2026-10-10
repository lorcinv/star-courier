#!/usr/bin/env python3
"""Reproducible crops and pixel derivatives of generated launcher support.

No repainting, procedural replacement, smoothing, or shape synthesis. Source art
is preserved verbatim; derivatives only crop, nearest-resample, map the approved
palette, and threshold alpha. Proofs only composite existing raster artwork.
"""
from pathlib import Path
import hashlib
import importlib.util
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'assets/2d_v5/launch-support'
SOURCE = HERE / 'launch-support-original.png'
PALETTE = ROOT / 'source_art/pixel_pipeline_studies/palette_96.json'
EXPECTED_SOURCE_SHA256 = '41887bd036f634f05f0683661b4f07d9e4705847520cff7e5c127c222cadaa08'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect(path):
    im = Image.open(path).convert('RGBA')
    pixels = np.array(im)
    opaque = pixels[:, :, 3] > 0
    return {'path': str(path.relative_to(ROOT)), 'dimensions': list(im.size),
            'sha256': sha(path), 'alpha_values': np.unique(pixels[:, :, 3]).tolist(),
            'alpha_bounds_xyxy': list(im.getchannel('A').getbbox()),
            'visible_pixels': int(opaque.sum()),
            'visible_palette_color_count': int(len(np.unique(pixels[:, :, :3][opaque], axis=0)))}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    original = Image.open(SOURCE).convert('RGBA')
    if EXPECTED_SOURCE_SHA256 and sha(SOURCE) != EXPECTED_SOURCE_SHA256:
        raise ValueError('Generated source hash mismatch; restore the unmodified source.')
    alpha = np.array(original.getchannel('A'))
    crop_box = Image.fromarray((alpha >= 128).astype(np.uint8) * 255).getbbox()
    crop = original.crop(crop_box)
    crop.save(HERE / 'launch-support-threshold-crop.png')
    size = (round(crop.width * 100 / crop.height), 100)
    pixels = np.array(crop.resize(size, Image.Resampling.NEAREST))
    spec = importlib.util.spec_from_file_location('courier_pixel_study', ROOT / 'source_art/pixel_pipeline_studies/study_reference.py')
    study = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(study)
    colors = json.loads(PALETTE.read_text())['colors']
    palette = np.array([[int(c[i:i+2], 16) for i in (1, 3, 5)] for c in colors], dtype=np.uint8)
    rgb = study.map_palette(pixels[:, :, :3], palette)
    alpha = np.where(pixels[:, :, 3] >= 128, 255, 0).astype(np.uint8)
    rgb[alpha == 0] = 0
    sprite = Image.fromarray(np.dstack([rgb, alpha]), 'RGBA')
    dest = OUT / 'launch-support-pixel.png'
    sprite.save(dest)
    sprite.resize((size[0] * 8, size[1] * 8), Image.Resampling.NEAREST).save(HERE / 'launch-support-proof-8x.png')
    manifest = {
        'generator': 'built-in image_gen',
        'generated_at_utc': '2026-10-10T12:40:03Z',
        'source': str(SOURCE.relative_to(ROOT)),
        'source_sha256': sha(SOURCE),
        'source_dimensions': list(original.size),
        'prompt': (HERE / 'prompt.txt').read_text(),
        'reviewed_style_references': [
            'source_art/art_direction_v4/pixel-cel-shop-reference-03.png',
            'source_art/2d_v5/props/launch-cradle-original.png',
            'assets/2d_v5/props/launch-cradle-pixel.png',
            'docs/qa/v5/extreme-native/standard-01/01-hub.png'],
        'source_threshold_crop_xyxy': list(crop_box),
        'method': 'Lossless rectangular source crop; NEAREST resize to 100 pixels tall; fixed reviewed 96-color Oklab mapping without dithering; binary alpha threshold128; transparent RGB zeroed; rectangular piece extraction only.',
        'palette_source': str(PALETTE.relative_to(ROOT)),
        'palette_sha256': sha(PALETTE),
        'full_sprite': inspect(dest),
        'registration': {
            'coordinates': 'Native sprite pixels, top-left origin; floor is the exclusive lower canvas edge.',
            'floor_center': [32, 100],
            'saddle_load_contact': [32, 10],
            'top_pivot_center': [34, 16],
            'piston_axis_x': 31,
            'suggested_floor_y': 486,
            'suggested_floor_x': 'Use actual launcher module column x; do not hard-code to a whole-craft center.',
            'full_sprite_top_left_for_floor': '[launcher_column_x - 32, 386]',
            'full_sprite_load_contact_y': 396,
            'layering': 'Place behind actual module artwork; the top saddle may overlap the underside of the launcher. Keep feet grounded on the shop floor or on the existing cradle deck, depending on chosen scene registration.',
            'mechanical_extension': 'For larger gaps keep base at its ground anchor and move saddle upward, filling the gap with only the extracted shaft; use NEAREST for vertical extension. Do not vertically stretch the base or saddle.'},
        'parts': []
    }
    # The complete native derivative is the coordinate authority. Overlap bands
    # preserve all original edge pixels and hide seams during telescoping.
    regions = {
        'saddle': (9, 0, 56, 24),
        'shaft': (26, 22, 37, 46),
        'base': (0, 44, 65, 100),
    }
    for name, box in regions.items():
        part = sprite.crop(box)
        part_path = OUT / f'support-{name}-pixel.png'
        part.save(part_path)
        record = inspect(part_path)
        record['id'] = name
        record['crop_in_full_sprite_xyxy'] = list(box)
        record['reassemble_top_left'] = list(box[:2])
        record['shaft_axis_local_x'] = 31 - box[0]
        record['ground_anchor_local'] = [32 - box[0], 100 - box[1]] if name == 'base' else None
        record['load_contact_local'] = [32 - box[0], 10 - box[1]] if name == 'saddle' else None
        manifest['parts'].append(record)
    reconstruction = Image.new('RGBA', sprite.size)
    for name in ('shaft', 'base', 'saddle'):
        reconstruction.alpha_composite(Image.open(OUT / f'support-{name}-pixel.png'), regions[name][:2])
    if reconstruction.tobytes() != sprite.tobytes():
        raise AssertionError('Registered pieces failed exact full-sprite reconstruction.')
    manifest['validation'] = {
        'registered_piece_reassembly_pixel_identical': True,
        'source_hash_verified': True,
        'all_runtime_alpha_binary': all(p['alpha_values'] == [0, 255] for p in manifest['parts']),
        'fixed_approved_palette_only': True,
        'no_baked_launcher_ship_engine_cargo': True}
    # Native-scale mechanical registration proofs: 100, 130, and 160-pixel full
    # support heights. Only the center shaft is extended; feet/saddle unchanged.
    proof = Image.new('RGBA', (255, 180), (27, 39, 62, 255))
    for index, extension in enumerate((0, 30, 60)):
        left = 10 + index * 80
        top = 170 - (100 + extension)
        shaft = Image.open(OUT / 'support-shaft-pixel.png')
        proof.alpha_composite(shaft.resize((11, 24 + extension), Image.Resampling.NEAREST), (left + 26, top + 22))
        proof.alpha_composite(Image.open(OUT / 'support-base-pixel.png'), (left, 114))
        proof.alpha_composite(Image.open(OUT / 'support-saddle-pixel.png'), (left + 9, top))
    proof.convert('RGB').save(HERE / 'registration-proof-native.png')
    proof.resize((765, 540), Image.Resampling.NEAREST).convert('RGB').save(HERE / 'registration-proof-3x.png')
    (HERE / 'registration-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'native': manifest['full_sprite'], 'parts': manifest['parts']}, indent=2))


if __name__ == '__main__':
    main()
