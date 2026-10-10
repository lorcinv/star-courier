#!/usr/bin/env python3
"""Only technical derivatives of inspected imagegen originals. No painted pixels."""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image
from scipy.ndimage import median_filter
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'assets/2d_v5/space'
OUT.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('pixel_study', ROOT / 'source_art/pixel_pipeline_studies/study_reference.py')
study = importlib.util.module_from_spec(spec)
spec.loader.exec_module(study)
palette_path = ROOT / 'source_art/pixel_pipeline_studies/palette_96.json'
palette = np.array([[int(h[i:i+2], 16) for i in (1, 3, 5)] for h in json.loads(palette_path.read_text())['colors']], dtype=np.uint8)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
records = []
def save(name, image, source, operation):
    pixels = np.array(image.convert('RGBA'))
    alpha = np.where(pixels[:, :, 3] >= 128, 255, 0).astype(np.uint8)
    rgb = study.map_palette(pixels[:, :, :3], palette)
    rgb[alpha == 0] = 0
    path = OUT / (name + '.png')
    Image.fromarray(np.dstack((rgb, alpha)), 'RGBA').save(path)
    records.append({'name': name, 'source': str(source.relative_to(ROOT)), 'source_sha256': sha(source), 'runtime': str(path.relative_to(ROOT)), 'dimensions': list(image.size), 'operation': operation, 'sha256': sha(path), 'alpha_values': np.unique(alpha).tolist(), 'visible_color_count': len(np.unique(rgb[alpha > 0], axis=0))})
    return path
orbit_path = HERE / 'orbit-far-panorama.png'
orbit = Image.open(orbit_path).convert('RGBA')
save('orbit-far-panorama', orbit.resize((1280, 720), Image.Resampling.NEAREST), orbit_path, 'Nearest 1280x720 full-image derivative; approved Oklab 96-color mapping.')
# The sky is an actual upper painted region, not replacement/generated noise.
star_crop = (0, 0, orbit.width, 450)
star_height = round(450 * 1280 / orbit.width)
save('orbit-starfield', orbit.crop(star_crop).resize((1280, star_height), Image.Resampling.NEAREST), orbit_path, {'crop': star_crop, 'resample': 'nearest; preserve aspect ratio', 'repeat': 'mirrored in both axes, distant plane only'})
# Extract the continuous blue atmospheric limb. Remove pixels above the first
# sustained atmospheric-blue run near the authored horizon; retain all below.
# This only edits alpha. It neither synthesizes replacement sky nor paints land.
native = np.array(orbit)
yy = np.arange(orbit.height)
edge = []
for x in range(orbit.width):
    start = int(480 + 90 * ((x - orbit.width / 2) / (orbit.width / 2)) ** 2)
    column = native[:, x, :3].astype(float)
    atmospheric = (column[:, 2] >= 98) & (column[:, 1] >= 30) & (column[:, 2] >= column[:, 0] * 1.6)
    runs = np.convolve(atmospheric.astype(int), np.ones(8, dtype=int), mode='valid')
    candidates = np.where((runs == 8) & (np.arange(len(runs)) >= start))[0]
    top = int(candidates[0]) if len(candidates) else orbit.height
    edge.append(top)
edge = np.maximum(np.array(edge), median_filter(np.array(edge), size=101, mode="nearest")).astype(int).tolist()
for x, top in enumerate(edge):
    native[:top, x, 3] = 0
planet = Image.fromarray(native, 'RGBA')
save('orbit-planet-limb', planet.resize((1280, 720), Image.Resampling.NEAREST), orbit_path, {'alpha_extraction': 'Keep original pixels below first eight-pixel continuous atmospheric-blue run near the authored curved horizon.', 'original_horizon_y_minmax': [min(edge), max(edge)], 'resample': 'nearest; binary alpha128; median edge cleanup removes isolated nebula protrusions', 'runtime_base_y': 176, 'minimum_visible_limb_y': round(min(edge) * 720 / orbit.height) + 176})
dock_path = HERE / 'orbital-mail-dock.png'
dock = Image.open(dock_path).convert('RGBA')
alpha = np.array(dock)[:, :, 3]
bounds = Image.fromarray(np.where(alpha >= 128, 255, 0).astype(np.uint8)).getbbox()
crop = dock.crop(bounds)
size = (760, round(crop.height * 760 / crop.width))
save('orbital-mail-dock', crop.resize(size, Image.Resampling.NEAREST), dock_path, {'alpha128_crop': bounds, 'resample': 'nearest, proportional', 'cleanup': 'binary alpha128, transparent RGB zero, common 96-color Oklab palette'})
# Measured in the source after visually inspecting the dark, unobscured aperture.
anchor = np.array([704.0, 466.0])
scale = np.array(size) / np.array(crop.size)
runtime_anchor = (anchor - np.array(bounds[:2])) * scale
radius = 42.0
manifest = {'method': 'Imagegen artwork only. Originals preserved. Crops, nearest resampling, alpha isolation and approved fixed96 Oklab palette only. Runtime color/distance treatment and texture-local blur are rendering effects.', 'palette': str(palette_path.relative_to(ROOT)), 'assets': records,
'dock_receiver': {'texture': 'res://assets/2d_v5/space/orbital-mail-dock.png', 'source_anchor_px': anchor.tolist(), 'source_unobscured_radius_px': radius, 'source_aperture_polygon_px': [[512, 417], [881, 416], [878, 511], [525, 521]], 'runtime_anchor_px': np.round(runtime_anchor, 4).tolist(), 'runtime_anchor_snapped_px': np.rint(runtime_anchor).astype(int).tolist(), 'runtime_unobscured_radius_px': round(float(radius * min(scale)), 4), 'runtime_safe_radius_px': 19, 'meaning': 'Center of the visible dark receiving bay above the platform, left of the overall station center. Radius deliberately excludes roof beams, floor rails and solar panels; dark interior remains opaque artwork, not an alpha hole.', 'sprite_alignment': 'Use centered=false and offset=-runtime_anchor_snapped_px, then node.position is the true receiver center. Scale safe radius with the same uniform sprite scale. Do not align the bounding-box center.'}}
(HERE / 'runtime-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(OUT / 'dock-anchors.json').write_text(json.dumps(manifest['dock_receiver'], indent=2) + '\n')
print(json.dumps(manifest['dock_receiver'], indent=2))
