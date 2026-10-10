#!/usr/bin/env python3
"""Register the supplied imagegen hangar, without drawing or stretching art.

Only rectangular crops, uniform nearest resampling, binary alpha and the shared
96-color palette produce the runtime PNGs. The labeled study additionally uses
functional grid/measurement overlays; it is not a gameplay screenshot.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "source_art/2d_v5/workshop-expansion"
SOURCE = SOURCE_DIR / "right-bay-original.png"
SOURCE_SHA256 = "f480461d079ca95b328d4126e93f4b1473f78cfc172c7ecbedb9a4bfabec4ed7"
OUT = ROOT / "assets/2d_v5/workshop"
PALETTE_PATH = ROOT / "source_art/pixel_pipeline_studies/palette_96.json"
CELL = 72
FLOOR_WORLD_Y = 486
SOURCE_FLOOR_Y = 644
CROP_WIDTH = 1200
PADDED_HEIGHT = 944  # Three transparent rows; never stretches the 941-row source.
SOURCE_CLEAR = [400, 236, 1200, 609]  # Half-open, all alpha < 128 in original.
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
spec = importlib.util.spec_from_file_location(
    "reference_pixel_study", ROOT / "source_art/pixel_pipeline_studies/study_reference.py"
)
study = importlib.util.module_from_spec(spec)
spec.loader.exec_module(study)
PALETTE = np.array(
    [[int(c[i:i + 2], 16) for i in (1, 3, 5)]
     for c in json.loads(PALETTE_PATH.read_text())["colors"]], dtype=np.uint8
)


def relative(path):
    return str(path.relative_to(ROOT))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def even(value):
    return round(value / 2) * 2


def derivative(original, width, scale, name):
    padded = Image.new("RGBA", (width, PADDED_HEIGHT))
    padded.paste(original.crop((0, 0, width, original.height)), (0, 0))
    size = (round(width * scale), round(PADDED_HEIGHT * scale))
    assert size[0] % 2 == 0 and size[1] % 2 == 0
    assert size[0] / width == size[1] / PADDED_HEIGHT == scale
    samples = np.array(padded.resize((size[0] // 2, size[1] // 2), Image.Resampling.NEAREST))
    alpha = np.where(samples[..., 3] >= 128, 255, 0).astype(np.uint8)
    rgb = study.map_palette(samples[..., :3], PALETTE)
    rgb[alpha == 0] = 0
    logical = Image.fromarray(np.dstack((rgb, alpha)), "RGBA")
    image = logical.resize(size, Image.Resampling.NEAREST)
    path = OUT / name
    image.save(path)
    pixels = np.array(image)
    color_set = set(map(tuple, PALETTE.tolist()))
    used = np.unique(pixels[..., :3][pixels[..., 3] > 0], axis=0)
    assert all(tuple(c) in color_set for c in used)
    assert set(np.unique(pixels[..., 3])) == {0, 255}
    for dy, dx in [(0, 1), (1, 0), (1, 1)]:
        assert np.array_equal(pixels[::2, ::2], pixels[dy::2, dx::2])
    return image, {
        "runtime": relative(path), "runtime_sha256": sha(path),
        "dimensions": list(size), "source_crop": [0, 0, width, original.height],
        "padded_source_dimensions": [width, PADDED_HEIGHT],
        "uniform_scale_from_source": scale, "logical_grid_px": 2,
        "palette_colors_used": len(used), "all_colors_in_shared_palette": True,
        "alpha_values": [0, 255], "transparent_rgb_is_zero": True,
        "all_2_by_2_blocks_constant": True, "mirror_x": False, "mirror_y": False,
        "alpha_bounds": list(image.getbbox()),
    }


def register(image, record, tier, scale, bounds, center):
    floor_local = even(SOURCE_FLOOR_Y * scale)
    top_left = [1040, FLOOR_WORLD_Y - floor_local]
    # Retain the requested asymmetric logical bounds, while centering their
    # complete physical footprint inside the translated right-side building.
    visual_center = [top_left[0] + even(800 * scale), top_left[1] + even(422 * scale)]
    x0, y0, x1, y1 = bounds
    # Upper rows are unlocked while the legacy bottom row remains y=2.
    # Adjust only the origin; the measured physical footprint stays identical.
    origin = [visual_center[0] - center * CELL,
              visual_center[1] - (y0 + y1) * CELL // 2]
    assert x0 <= -4 and x1 >= 4 and y0 <= -2 and y1 >= 2
    footprint = [origin[0] + (x0 - .5) * CELL,
                 origin[1] + (y0 - .5) * CELL,
                 origin[0] + (x1 + .5) * CELL,
                 origin[1] + (y1 + .5) * CELL]
    local = [int(footprint[i] - top_left[i % 2]) for i in range(4)]
    alpha = np.array(image)[..., 3]
    assert np.count_nonzero(alpha[local[1]:local[3], local[0]:local[2]]) == 0
    corridor = [local[2], local[1], image.width, local[3]]
    assert np.count_nonzero(alpha[corridor[1]:corridor[3], corridor[0]:corridor[2]]) == 0
    # Measure exact resampled vertical aperture for the entire horizontal
    # footprint and launch corridor, rather than estimate from source ratios.
    free_rows = np.flatnonzero(np.all(alpha[:, local[0]:] == 0, axis=1))
    runs = np.split(free_rows, np.flatnonzero(np.diff(free_rows) > 1) + 1)
    run = next(r for r in runs if len(r) and r[0] <= local[1] and r[-1] + 1 >= local[3])
    clearance = {"above_px": local[1] - int(run[0]),
                 "below_px": int(run[-1]) + 1 - local[3],
                 "left_px": local[0] - round(SOURCE_CLEAR[0] * scale),
                 "right_before_open_edge_px": image.width - local[2],
                 "bottom_to_actor_floor_px": FLOOR_WORLD_Y - footprint[3]}
    record.update({
        "tier": tier, "recommended": True,
        "sprite_top_left_world": top_left, "sprite_centered": False,
        "floor_anchor_local": [0, floor_local], "floor_anchor_world": [1040, FLOOR_WORLD_Y],
        "source_floor_anchor": [0, SOURCE_FLOOR_Y],
        "floor_anchor_rounding_error_px": floor_local - SOURCE_FLOOR_Y * scale,
        "grid_cell_px": CELL, "grid_bounds_inclusive": {"x": [x0, x1], "y": [y0, y1]},
        "grid_counts": [x1 - x0 + 1, y1 - y0 + 1],
        "assembly_origin_world": origin, "grid_visual_center_world": visual_center,
        "legacy_grid_cells_preserved": True,
        "vertical_growth_policy": "Add upper rows only; retain bottom logical row y=2.",
        "symmetric_alternative": {"bounds_inclusive": {"x": [-(x1 - x0) // 2, (x1 - x0) // 2], "y": [-(y1 - y0) // 2, (y1 - y0) // 2]}, "assembly_origin_world": visual_center},
        "full_cell_footprint_world": footprint,
        "full_cell_footprint_local": local,
        "full_cell_footprint_dimensions": [footprint[2] - footprint[0], footprint[3] - footprint[1]],
        "footprint_overlapping_art_pixels": 0,
        "launch_corridor_local": corridor, "launch_corridor_overlapping_art_pixels": 0,
        "launch_direction": "right", "launch_corridor_extends_beyond_art_right_edge": True,
        "exact_free_aperture_y_local": [int(run[0]), int(run[-1]) + 1],
        "clearance": clearance,
        "old_shop_transform": {"top_left_world": [0, 0], "scale": [1, 1], "size": [1280, 720]},
        "existing_shop_overlap_x_world": [1040, 1280],
        "actor_floor_y_world": FLOOR_WORLD_Y,
    })
    return record


def study_panel(image, record, title):
    # Neutral technical backing is intentionally not runtime background art.
    world_left, world_top = -80, -870
    world_size = (3920, 2020)
    world = Image.new("RGBA", world_size, "#182137")
    def at(x, y):
        return (round(x - world_left), round(y - world_top))
    old = Image.open(ROOT / "assets/2d_v5/environment/shop-shell.png").convert("RGBA")
    world.alpha_composite(old, at(0, 0))
    world.alpha_composite(image, at(*record["sprite_top_left_world"]))
    counter = Image.open(ROOT / "assets/2d_v5/props/counter-pixel.png").convert("RGBA")
    world.alpha_composite(counter, at(222 - counter.width // 2, FLOOR_WORLD_Y - counter.height))
    clerk = Image.open(ROOT / "assets/2d_v5/actors/clerk-idle-pixel.png").convert("RGBA")
    clerk = clerk.resize((round(clerk.width * 210 / clerk.height), 210), Image.Resampling.NEAREST)
    world.alpha_composite(clerk, at(276 - clerk.width // 2, FLOOR_WORLD_Y - clerk.height))
    draw = ImageDraw.Draw(world)
    draw.line([at(0, FLOOR_WORLD_Y), at(3700, FLOOR_WORLD_Y)], fill="#ffd371", width=3)
    b = record["full_cell_footprint_world"]
    draw.rectangle([at(b[0], b[1]), at(b[2], b[3])], outline="#66ece8", width=4)
    for x in range(int(b[0]), int(b[2]) + 1, CELL):
        draw.line([at(x, b[1]), at(x, b[3])], fill="#457778", width=2)
    for y in range(int(b[1]), int(b[3]) + 1, CELL):
        draw.line([at(b[0], y), at(b[2], y)], fill="#457778", width=2)
    origin = record["assembly_origin_world"]
    draw.ellipse([at(origin[0] - 8, origin[1] - 8), at(origin[0] + 8, origin[1] + 8)], fill="#fff2c6")
    # A functional measurement arrow indicates only the verified clear route.
    y = origin[1]
    draw.line([at(b[2], y), at(3730, y)], fill="#66ece8", width=6)
    draw.line([at(3730, y), at(3695, y - 20)], fill="#66ece8", width=6)
    draw.line([at(3730, y), at(3695, y + 20)], fill="#66ece8", width=6)
    world = world.resize((1568, 808), Image.Resampling.NEAREST).convert("RGB")
    panel = Image.new("RGB", (1600, 1012), "#10182b")
    panel.paste(world, (16, 90))
    draw = ImageDraw.Draw(panel)
    draw.text((20, 12), title, fill="#ffdf97", font=ImageFont.truetype(FONT, 26))
    draw.text((20, 52), "REGISTRATION STUDY ONLY | Source art + technical grid. Not gameplay or final background.",
              fill="#bccbdd", font=ImageFont.truetype(FONT, 17))
    c = record["clearance"]
    lines = [
        f"Unscaled original shop at left. New shell scale {record['uniform_scale_from_source']}x; floor y486 stays aligned.",
        f"Grid {record['grid_counts'][0]} x {record['grid_counts'][1]}, y{record['grid_bounds_inclusive']['y']}; origin {origin}; upper/lower clearance {c['above_px']}/{c['below_px']} px.",
        "Open-right crop removes the right jamb. The cut beam/deck edge needs an imagegen finishing pass for final-quality art.",
        "Large columns read as hangar structure; seam, distant background and actor travel are not runtime-validated here.",
    ]
    small = ImageFont.truetype(FONT, 17)
    for i, line in enumerate(lines):
        draw.text((20, 912 + i * 23), line, fill="#c4d2e7", font=small)
    return panel


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    original_sha = sha(SOURCE)
    assert original_sha == SOURCE_SHA256, "Original changed; inspect new source before changing registration."
    original = Image.open(SOURCE).convert("RGBA")
    assert original.size == (1672, 941)
    alpha = np.array(original)[..., 3]
    x0, y0, x1, y1 = SOURCE_CLEAR
    assert np.count_nonzero(alpha[y0:y1, x0:x1] >= 128) == 0
    _, full = derivative(original, original.width, 1, "right-bay-full-reference-pixel.png")
    full.update({"recommended": False, "reason": "Closed right pillar obstructs horizontal launch; this is a technical source reference, not the proposed runtime bay."})
    records, images = [], []
    for tier, scale, bounds, center in [(1, 1.625, [-4, -4, 8, 2], 2), (2, 2, [-4, -6, 12, 2], 4)]:
        image, record = derivative(original, CROP_WIDTH, scale, f"right-bay-tier{tier}-open-pixel.png")
        records.append(register(image, record, tier, scale, bounds, center))
        images.append(image)
    panels = [study_panel(image, record, f"TIER {record['tier']}: right-side physical expansion, {record['grid_counts'][0]} x {record['grid_counts'][1]} cells")
              for image, record in zip(images, records)]
    board = Image.new("RGB", (1600, 2024))
    for i, panel in enumerate(panels):
        board.paste(panel, (0, i * 1012))
        panel.save(SOURCE_DIR / f"tier{records[i]['tier']}-registration-study.png")
    board.save(SOURCE_DIR / "workshop-registration-study.png")
    manifest = {
        "version": 1, "status": "Technical derivatives and layout study only. No runtime/economy implementation or gameplay claim.",
        "source": relative(SOURCE), "source_sha256": original_sha, "source_dimensions": list(original.size),
        "source_changed": False, "palette": relative(PALETTE_PATH), "palette_sha256": sha(PALETTE_PATH),
        "method": "Rectangular source crop, three transparent bottom padding rows, exact uniform nearest resampling onto a 2px grid, alpha threshold128, shared96 Oklab palette; no drawn runtime geometry, invented illustration, reflection or background mirroring.",
        "source_verified_empty_rectangle": SOURCE_CLEAR,
        "source_verified_empty_rectangle_dimensions": [x1 - x0, y1 - y0],
        "base": {"grid_bounds_inclusive": {"x": [-4, 4], "y": [-2, 2]}, "grid_counts": [9, 5], "assembly_origin_world": [728, 288], "full_cell_footprint_world": [404, 108, 1052, 468]},
        "source_reference": full, "tiers": records,
        "study": relative(SOURCE_DIR / "workshop-registration-study.png"),
        "recommendation": "Relocate assembly origin to the right-side bay on upgrade; preserve every module's logical coordinates and physics. Add rows upward while retaining bottom row y=2 and all legacy cells. Keep original shop at identity transform. Use full cell extents, not merely center dots, for camera-fit and occupancy checks. Pan/zoom only the presentation.",
        "visual_limitations": [
            "The supplied complete artwork is a closed portal. A rectangular crop at source x1200 opens its right side, but exposes an uncapped ceiling/deck cross section.",
            "The tier2 truss and columns are large hangar architecture at 2x source scale; actor-scale detail and the joining floor seam still require a real gameplay-camera review.",
            "Grid bottom has 108/120 world px to the actor floor line, but only 52/50 px to the back-edge art. Do not lower the grid to y486 or it overlaps the painted floor.",
            "The study uses a neutral technical backing; it does not supply extra city art or pretend the original 720px scene fills the expanded world.",
            "The source shares its entire silhouette as one alpha-connected component; isolated-component cleanup would not remove the right pillar.",
        ],
        "additional_imagegen_requirement": "For final-quality open launch art, generate an open-right industrial hangar with a naturally terminated/capped ceiling and deck, no right jamb, and an unobstructed rectangular flight aperture. Keep the same perspective, navy/cream/yellow materials, floor depth and actor-scale props; provide separate tier1/tier2 compositions at 936x504/1224x648 cell footprints plus at least48px top/bottom clearance, floor anchor y486, and a clean left-side connection to the current shop. Do not resize the old shop, stretch beams or add procedural fill.",
    }
    assert sha(SOURCE) == original_sha
    (SOURCE_DIR / "workshop-extension-derivatives.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"manifest": relative(SOURCE_DIR / "workshop-extension-derivatives.json"),
                      "study": manifest["study"], "tiers": records}, indent=2))


if __name__ == "__main__":
    main()
