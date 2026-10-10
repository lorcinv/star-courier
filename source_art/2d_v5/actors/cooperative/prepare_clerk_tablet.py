#!/usr/bin/env python3
"""Register image-generated tablet poses; no artwork is painted by this script.

Only transparent crop, uniform nearest sampling, shared palette/alpha cleanup
and translation are applied. Existing walk records are preserved verbatim.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
SRC = ROOT / 'source_art/2d_v5/actors/cooperative'
OUT = ROOT / 'assets/2d_v5/actors/cooperative'
SOURCE = SRC / 'clerk-tablet-original.png'
MANIFEST = OUT / 'motion-manifest.json'
PALETTE = ROOT / 'source_art/pixel_pipeline_studies/palette_96.json'
spec = importlib.util.spec_from_file_location('pixel_study', ROOT / 'source_art/pixel_pipeline_studies/study_reference.py')
study = importlib.util.module_from_spec(spec)
spec.loader.exec_module(study)
colors = np.array([[int(h[i:i + 2], 16) for i in (1, 3, 5)] for h in json.loads(PALETTE.read_text())['colors']], dtype=np.uint8)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def relative(path):
    return str(path.relative_to(ROOT))

source = Image.open(SOURCE).convert('RGBA')
scale = 240 / 848
records = {}
# Source pelvis projection sets the ground origin, not the widest pose bounds.
# The final drawing has a different stance, but the same hip and floor anchor.
for key, semantic, cell, pelvis, hip in [
    ('reach', 'tablet_read', (0, 0, 620, 887), 370, (370, 536)),
    ('align', 'tablet_tap', (620, 0, 1160, 887), 904, (904, 536)),
    ('ready', 'tablet_check', (1160, 0, 1774, 887), 1416, (1416, 538)),
]:
    crop = np.array(source.crop(cell))
    y, x = np.where(crop[:, :, 3] >= 128)
    bounds = (int(x.min()) + cell[0], int(y.min()) + cell[1], int(x.max()) + cell[0] + 1, int(y.max()) + cell[1] + 1)
    part = source.crop(bounds)
    size = (round(part.width * scale), round(part.height * scale))
    pixels = np.array(part.resize(size, Image.Resampling.NEAREST))
    rgb = study.map_palette(pixels[:, :, :3], colors)
    alpha = np.where(pixels[:, :, 3] >= 128, 255, 0).astype(np.uint8)
    rgb[alpha == 0] = 0
    raster = Image.fromarray(np.dstack([rgb, alpha]), 'RGBA')
    paste = (round(96 - (pelvis - bounds[0]) * scale), 248 - size[1])
    canvas = Image.new('RGBA', (208, 256))
    canvas.alpha_composite(raster, paste)
    path = OUT / ('clerk-' + semantic.replace('_', '-') + '-pixel.png')
    canvas.save(path)
    assert canvas.getbbox()[3] == 248 and 0 < canvas.getbbox()[0] < canvas.getbbox()[2] < 208
    records[key] = {
        'id': 'clerk-' + semantic.replace('_', '-'), 'runtime': relative(path), 'sha256': sha(path),
        'dimensions': list(canvas.size), 'alpha_bounds': list(canvas.getbbox()),
        'foot_anchor': [paste[0] + (pelvis - bounds[0]) * scale, 248], 'body_height': 240,
        'hip_anchor': [paste[0] + (hip[0] - bounds[0]) * scale, paste[1] + (hip[1] - bounds[1]) * scale],
        'facing': 'right', 'contains_parcel': False, 'held_prop': 'waybill_tablet', 'semantic': semantic,
        'source': relative(SOURCE), 'source_sha256': sha(SOURCE), 'source_cell': list(cell),
        'source_bounds': list(bounds), 'source_foot_anchor': [pelvis, bounds[3]], 'source_hip_anchor': list(hip),
        'uniform_scale': scale, 'sampling_size': list(size), 'paste_offset': list(paste),
        'stance_family': 'tablet_stationary', 'alpha_values': [0, 255],
        'palette_used': len(np.unique(rgb[alpha > 0], axis=0)),
    }

data = json.loads(MANIFEST.read_text())
data['asset_type'] = 'Image-generated whole-raster walk and waybill-tablet poses'
data['actors']['clerk']['gestures'] = records
data['tablet_status'] = 'Read waybill, tap loading confirmation, then look toward cargo. Tablet never moves the parcel. Legacy internal gesture keys are retained for controller compatibility.'
if not any(record['path'] == relative(SOURCE) for record in data['sources']):
    data['sources'].append({'path': relative(SOURCE), 'sha256': sha(SOURCE), 'dimensions': list(source.size)})
MANIFEST.write_text(json.dumps(data, indent=2) + '\n')
board = Image.new('RGBA', (208 * 3, 256), (22, 30, 50, 255))
for i, record in enumerate(records.values()):
    board.alpha_composite(Image.open(ROOT / record['runtime']).convert('RGBA'), (208 * i, 0))
board.convert('RGB').save(SRC / 'clerk-tablet-review.png')
print(json.dumps({'source_sha256': sha(SOURCE), 'gestures': {k: r['runtime'] for k, r in records.items()}, 'walk_records_preserved': len(data['actors']['clerk']['walk'])}, indent=2))
