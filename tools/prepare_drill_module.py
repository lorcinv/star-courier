#!/usr/bin/env python3
"""Register the supplied drill image on the existing module pixel grid.

Technical derivative only: uniform nearest sampling, the established Oklab
palette mapper, alpha thresholding, and detached-fringe cleanup. No runtime
artwork is painted. Diagnostic circles/labels appear only in proof images.
"""
from pathlib import Path
import hashlib
import importlib.util
import json

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import label

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "source_art/2d_v5/modules/extreme"
ORIGINAL = SRC / "drill-original.png"
OUTPUT = ROOT / "assets/2d_v5/modules/drill-pixel.png"
SOURCE_SHA = "cff828e4d1658c39a448bc8bac63268407b2907af590ec2ae948fc7a59a86a96"
PALETTE_PATH = ROOT / "source_art/pixel_pipeline_studies/palette_96.json"
SCALE = 0.0575
SOURCE_TIP = (1197, 680)
RUNTIME_TIP = (71, 36)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return str(path.relative_to(ROOT))


def bounds(mask):
    box = Image.fromarray(mask.astype(np.uint8)).getbbox()
    return list(box) if box else None


def main():
    assert sha(ORIGINAL) == SOURCE_SHA, "The generated original must stay unchanged."
    original = Image.open(ORIGINAL).convert("RGBA")
    source = np.array(original)
    palette = np.array([
        [int(color[i:i + 2], 16) for i in (1, 3, 5)]
        for color in json.loads(PALETTE_PATH.read_text())["colors"]
    ], dtype=np.uint8)
    spec = importlib.util.spec_from_file_location(
        "pixel_study", ROOT / "source_art/pixel_pipeline_studies/study_reference.py")
    study = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(study)

    # Index-coordinate registration: no asymmetric resize, silhouette reshaping,
    # rotation, or clipping. The chosen source tip maps to texel index (71, 36).
    y, x = np.mgrid[0:72, 0:72]
    sx = np.rint((x - RUNTIME_TIP[0]) / SCALE + SOURCE_TIP[0]).astype(int)
    sy = np.rint((y - RUNTIME_TIP[1]) / SCALE + SOURCE_TIP[1]).astype(int)
    valid = ((sx >= 0) & (sx < original.width) &
             (sy >= 0) & (sy < original.height))
    nearest = np.zeros((72, 72, 4), dtype=np.uint8)
    nearest[valid] = source[sy[valid], sx[valid]]
    mask = nearest[:, :, 3] >= 128
    components, _ = label(mask, structure=np.ones((3, 3)))
    sizes = np.bincount(components.ravel())
    sizes[0] = 0
    removed = int(mask.sum() - sizes.max())
    mask = components == int(sizes.argmax())
    rgb = study.map_palette(nearest[:, :, :3], palette)
    rgb[~mask] = 0
    alpha = np.where(mask, 255, 0).astype(np.uint8)
    sprite = Image.fromarray(np.dstack([rgb, alpha]), "RGBA")
    sprite.save(OUTPUT)

    # Keep established lossless, no-mipmap texture settings. Omit another
    # texture's UID; Godot may assign this new file its own UID at next import.
    template = (ROOT / "assets/2d_v5/modules/battery-pixel.png.import").read_text()
    old_path = "res://assets/2d_v5/modules/battery-pixel.png"
    new_path = "res://assets/2d_v5/modules/drill-pixel.png"
    old_hash = hashlib.md5(old_path.encode()).hexdigest()
    new_hash = hashlib.md5(new_path.encode()).hexdigest()
    import_path = OUTPUT.with_suffix(".png.import")
    existing_uid = None
    if import_path.exists():
        existing_uid = next((line for line in import_path.read_text().splitlines()
                             if line.startswith("uid=")), None)
    template = "\n".join(line for line in template.splitlines()
                         if not line.startswith("uid=")) + "\n"
    if existing_uid:
        template = template.replace('[remap]\n', '[remap]\n' + existing_uid + '\n')
    template = template.replace("battery-pixel.png", "drill-pixel.png")
    template = template.replace(old_hash, new_hash)
    template = template.replace("process/fix_alpha_border=true",
                                "process/fix_alpha_border=false")
    import_path.write_text(template)

    # Quantitative registration checks. Source x>=770 identifies the exposed
    # helical bit for this diagnostic, rather than a runtime segmentation mask.
    housing = mask & (sx < 770)
    bit = mask & (sx >= 770)
    body_distance = np.hypot(x - 36, y - 36)
    cutter_distance = np.hypot(x - 57.6, y - 36)
    in_body = body_distance <= 0.43 * 72
    in_cutter = cutter_distance <= 0.18 * 72
    in_rounded_cutter = np.hypot(x - 58, y - 36) <= 13
    out_union = mask & ~(in_body | in_cutter)
    # Godot draws the texture in a [0,72] rectangle, so geometric texel centers
    # are index+0.5. Report this separately from requested integer pixel indices.
    render_body = np.hypot(x + 0.5 - 36, y + 0.5 - 36) <= 30.96
    render_cutter_distance = np.hypot(x + 0.5 - 57.6, y + 0.5 - 36)
    render_out_union = mask & ~(render_body | (render_cutter_distance <= 12.96))
    colors = {tuple(c) for c in rgb[mask].tolist()}
    palette_set = {tuple(c) for c in palette.tolist()}
    source_y, source_x = np.where(source[:, :, 3] >= 128)
    projected_x = (source_x - SOURCE_TIP[0]) * SCALE + RUNTIME_TIP[0]
    projected_y = (source_y - SOURCE_TIP[1]) * SCALE + RUNTIME_TIP[1]
    # The footprint of texel x=71 extends to 71.5 in this index convention.
    source_clipped = int(np.count_nonzero(
        (projected_x < -0.5) | (projected_x >= 71.5) |
        (projected_y < -0.5) | (projected_y >= 71.5)))
    validation = {
        "runtime_dimensions": list(sprite.size),
        "runtime_alpha_bounds_xyxy": bounds(mask),
        "visible_pixels": int(mask.sum()),
        "alpha_values": np.unique(alpha).tolist(),
        "visible_palette_color_count": len(colors),
        "palette_outliers": len(colors - palette_set),
        "transparent_rgb_zero": bool((rgb[~mask] == 0).all()),
        "pure_black_visible_pixels": int(np.count_nonzero(mask & (rgb == 0).all(axis=2))),
        "connected_components": int(label(mask, structure=np.ones((3, 3)))[1]),
        "detached_sampling_fringe_pixels_removed": removed,
        "opaque_source_pixels_outside_runtime_footprint": source_clipped,
        "housing_alpha_bounds_xyxy": bounds(housing),
        "housing_pixels_outside_body_circle": int((housing & ~in_body).sum()),
        "cutter_alpha_bounds_xyxy": bounds(bit),
        "cutter_visible_pixels": int(bit.sum()),
        "cutter_pixels_outside_exact_cutter_circle": int((bit & ~in_cutter).sum()),
        "visible_pixels_outside_exact_collision_union": int(out_union.sum()),
        "outside_exact_union_xy": np.column_stack(np.where(out_union)[::-1]).tolist(),
        "visible_pixels_outside_rounded_collision_union": int(
            (mask & ~(in_body | in_rounded_cutter)).sum()),
        "tip_outside_exact_cutter_radius_px": round(
            float(cutter_distance[36, 71] - 0.18 * 72), 6),
        "rendered_texel_center_housing_pixels_outside_body": int((housing & ~render_body).sum()),
        "rendered_texel_centers_outside_exact_union": int(render_out_union.sum()),
        "rendered_texel_centers_outside_exact_union_indices_xy":
            np.column_stack(np.where(render_out_union)[::-1]).tolist(),
        "rendered_tip_texel_center_outside_exact_cutter_radius_px": round(
            float(render_cutter_distance[36, 71] - 12.96), 6),
    }
    assert colors <= palette_set
    assert validation["alpha_values"] == [0, 255]
    assert validation["transparent_rgb_zero"]
    assert validation["connected_components"] == 1
    assert source_clipped == 0
    assert validation["housing_pixels_outside_body_circle"] == 0
    assert validation["visible_pixels_outside_rounded_collision_union"] == 0
    bx0, by0, bx1, by1 = validation["cutter_alpha_bounds_xyxy"]
    assert bx0 >= 45 and bx1 <= 72 and by0 >= 23 and by1 <= 50
    assert mask[36, 71]

    proof_records = []
    panels = []
    backgrounds = [
        ("sky", ROOT / "assets/2d_v5/environment/far-city.png", (450, 28, 522, 100)),
        ("shop", ROOT / "assets/2d_v5/environment/shop-shell.png", (660, 230, 732, 302)),
    ]
    for name, path, crop in backgrounds:
        proof = Image.open(path).convert("RGBA").crop(crop)
        proof.alpha_composite(sprite)
        native = SRC / f"drill-{name}-native.png"
        enlarged = SRC / f"drill-{name}-8x.png"
        proof.save(native)
        proof.resize((576, 576), Image.Resampling.NEAREST).save(enlarged)
        panels.append((name, proof))
        proof_records.append({"background": relative(path), "background_crop_xyxy": list(crop),
                              "native": relative(native), "nearest_8x": relative(enlarged)})

    alignment = Image.new("RGBA", (72, 72), (20, 29, 49, 255))
    alignment.alpha_composite(sprite)
    draw = ImageDraw.Draw(alignment)
    draw.ellipse((5.04, 5.04, 66.96, 66.96), outline=(75, 218, 248, 255))
    draw.ellipse((44.64, 23.04, 70.56, 48.96), outline=(248, 105, 148, 255))
    draw.line((33, 36, 39, 36), fill=(75, 218, 248, 255))
    draw.line((36, 33, 36, 39), fill=(75, 218, 248, 255))
    draw.point((58, 36), fill=(248, 105, 148, 255))
    alignment.save(SRC / "drill-alignment-native.png")
    alignment.resize((576, 576), Image.Resampling.NEAREST).save(SRC / "drill-alignment-8x.png")
    panels.append(("circle QA", alignment))

    native_sheet = Image.new("RGBA", (312, 116), (20, 29, 49, 255))
    draw = ImageDraw.Draw(native_sheet)
    for i, (name, panel) in enumerate(panels):
        at = 12 + i * 102
        native_sheet.alpha_composite(panel, (at, 10))
        draw.text((at, 91), name + " 72px", fill=(255, 241, 208, 255))
    native_sheet.save(SRC / "drill-proofsheet-native.png")

    manifest = {
        "id": "drill", "generator": "built-in image_gen (supplied original)",
        "original": relative(ORIGINAL), "original_sha256": SOURCE_SHA,
        "original_dimensions": list(original.size),
        "source_alpha128_bounds_xyxy": bounds(source[:, :, 3] >= 128),
        "runtime": relative(OUTPUT), "sha256": sha(OUTPUT),
        "palette_source": relative(PALETTE_PATH), "palette_sha256": sha(PALETTE_PATH),
        "script": "tools/prepare_drill_module.py",
        "method": "Uniform nearest-neighbor inverse sampling; existing fixed 96-color Oklab mapper; no dithering; binary alpha >=128; largest 8-connected component; transparent RGB zero. No artwork painted, no silhouette reshaping, no nonuniform stretching, no generation.",
        "mapping": {
            "coordinate_convention": "Source and runtime integer coordinates identify texel centers. Nearest ties use numpy.rint (ties-to-even).",
            "scale_xy": [SCALE, SCALE], "rotation_degrees": 0,
            "source_tip_landmark": list(SOURCE_TIP), "runtime_tip_landmark": list(RUNTIME_TIP),
            "forward": "x = (source_x - 1197) * 0.0575 + 71; y = (source_y - 680) * 0.0575 + 36",
            "inverse_sampling": "source_x = rint((x - 71) / 0.0575 + 1197); source_y = rint((y - 36) / 0.0575 + 680)",
            "projected_source_alpha_bounds_center_coordinates": [
                round(float(projected_x.min()), 6), round(float(projected_y.min()), 6),
                round(float(projected_x.max()), 6), round(float(projected_y.max()), 6)],
        },
        "anchors": {
            "cell_dimensions_px": [72, 72], "cell_dimensions_m": [1, 1],
            "module_center_and_rotation_anchor_px": [36, 36],
            "body_circle_center_px": [36, 36], "body_circle_radius_m": 0.43,
            "body_circle_radius_px_exact": 30.96,
            "cutter_offset_m": [0.3, 0], "cutter_center_px_exact": [57.6, 36],
            "cutter_center_px_rounded": [58, 36], "cutter_radius_m": 0.18,
            "cutter_radius_px_exact": 12.96, "cutter_radius_px_rounded": 13,
            "suggested_cardinal_sockets_px": {"left": [0, 36], "right": [72, 36],
                                               "top": [36, 0], "bottom": [36, 72]},
        },
        "collision_notes": [
            "All housing texel centers fit the ordinary 0.43 m body circle.",
            "The helical bit is a taper rather than a circular silhouette. Its rear shoulder has 28 texel indices outside the small exact cutter circle; these lie inside the ordinary body circle.",
            "The tip texel at (71,36) lies 0.44 px (0.006111 m) beyond the exact small-circle radius. It fits the requested rounded center (58,36), radius 13 px. No other visible texel center lies outside the exact union.",
            "The preceding measures use requested integer pixel-index coordinates. In a rendered texture rectangle [0,72], texel centers are index+0.5: indices (71,36) and (70,37) are outside the exact union, with maximum 0.94899 px (0.01318 m) protrusion at the tip center. No housing texel center is outside the body circle. Raster pixel footprints are not exact circular polygons.",
            "The full alpha>=128 source silhouette fits the runtime pixel footprint; rightmost source contour projects to x=71.345. No drill tip was clipped or painted to force collider agreement.",
            "These are texel-center diagnostics, not polygon-perfect collision claims. Runtime physics and texture filtering were not changed by this script.",
        ],
        "texture_import": {"lossless_compression": True, "mipmaps": False,
                           "fix_alpha_border": False, "engine_import_verified": False,
                           "note": "No Godot/GUI process run during simultaneous tests. Parent should import normally before runtime validation."},
        "validation": validation, "proofs": proof_records,
        "alignment_proof": {"native": relative(SRC / "drill-alignment-native.png"),
                            "nearest_8x": relative(SRC / "drill-alignment-8x.png"),
                            "legend": "Cyan: exact body circle and module anchor. Pink: exact cutter circle and rounded center. Proof overlay only."},
        "native_proofsheet": relative(SRC / "drill-proofsheet-native.png"),
    }
    (SRC / "drill-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (SRC / "drill-pixel-validation.json").write_text(
        json.dumps({"passed": True, "sha256": sha(OUTPUT), **validation}, indent=2) + "\n")
    assert sha(ORIGINAL) == SOURCE_SHA
    print(json.dumps({"runtime": relative(OUTPUT), "sha256": sha(OUTPUT), **validation}, indent=2))


if __name__ == "__main__":
    main()
