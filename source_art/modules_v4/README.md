# Functional courier modules, V4.3 amber single-cab compact

Original solid hard-surface Blender geometry, authored after inspecting the approved `pixel-cel-shop-reference-03.png` pixels. The current asset source shows the exact parent-provided physical eight-module starter. There is no scenery-only craft, static covering shell, copied logo, imported vehicle or SVG. This package does not edit gameplay or scripts.

## Deliverables

- Editable current source: `star_courier_modules_v4.blend`
- Reproducible builder: `build_modules.py`
- Exact metadata: `manifest.json` and `assets/modules_v4/manifest.json`
- Independent binary GLB checker: `validate_exports.py`
- Closed-volume/source-normal checker: `validate_source.py`
- Check results: `validation.json` and `source_validation.json`
- Compact proofs: `proofs/compact_front.png`, `compact_angle.png`, `compact_rear_nozzle.png`, `compact_exploded.png`

## Exact compact composition

All grid positions are one metre apart. Grid Y increases downwards; Godot vertical Y is its negative.

- Upper grid row 0: thruster at X −2, beam at −1, cargo_crate at 0, separator at +1
- Lower grid row 1: thruster at X −2, beam at −1, cell at 0, armor at +1

The separator is the real catalog coupler. Its rounded upper cab contains a broad blue canopy, a recessed mechanical release spine and two cream release latches. The lower armor is a solid tapered yellow chin with a wide cream impact bumper. It has no second window. Both remain separate physical modules with a visible horizontal seam.

The shared beam has full-height yellow load rails and broad service panels. Exterior frames between both beam rows and the cargo/battery are yellow or warm ochre so the vehicle reads before its cell divisions; the real gaps and mechanical panel seams remain. The battery retains twin cylindrical energy cartridges but replaces its old projecting fin with a flush energy roof; it meets the cargo above with a visible 0.0265 m clearance. Upper/lower beam clearance is 0.0165 m. Cab/armor clearance is 0.0325 m. All source geometry remains inside approximately ±0.583 m per cell.

The assembled bounds are X [−2.565, 1.5825], Y [−1.49, 0.529], Z [−0.433507, 0.4955]. The side silhouette is an honest 2.05:1. Exact individual bounds, repeated instance positions, triangle counts and surface counts are in the manifest.

The optional spring is a separate replacement asset and is not in the starter. Its source collection is hidden from hero-proof rendering and placed below the compact assembly for inspection. The duplicated beam and engine instances share their editable source mesh data; edits therefore stay consistent with the single exported model of each type.

## Preserved originals

The complete compact package immediately before this single-cab revision is preserved in `archive/2026-10-10T081615Z/compact_before_single_cab.zip`, with an immediately openable `compact_before_single_cab.blend` beside it. That archive also contains the fixed per-module bounds and original GLB SHA-256 hashes. Current exports are checked against those bounds. Final output hashes are in `release_hashes_sha256.json`.

The original one-row proofs remain at `proofs/assembled_front.png`, `assembled_angle.png`, `assembled_rear_nozzle.png` and `module_seams_exploded.png`. The original spring proof remains `proofs/spring_detail.png`.

The untouched linear source is preserved as `archive/star_courier_modules_linear_v40.blend`. `archive/linear_v40_originals.zip` preserves the complete original source, generator, manifests, proofs, validations and original GLBs, using project-relative paths. Extract that historical package into a separate project directory if rebuilding the old version; do not overwrite the current compact files.

## Build and verify

From the project root:

    /usr/bin/blender -b -t 4 --python-exit-code 1 --python source_art/modules_v4/build_modules.py
    python source_art/modules_v4/validate_exports.py
    /usr/bin/blender -b source_art/modules_v4/star_courier_modules_v4.blend --python-exit-code 1 --python source_art/modules_v4/validate_source.py

Append `-- --skip-render` for an export-only rebuild. The builder regenerates only current compact proofs; original linear proofs are retained. Cycles denoising is disabled because this Blender build lacks OpenImageDenoise.

## Engine and material contract

Every GLB has an identity root at origin. Mesh child transforms are baked. Coordinates are +X forward, +Y up, +Z toward camera, in metres. Cardinal Socket_Right/Left/Top/Bottom empties preserve the existing ±0.6-m socket contract. Assembly spacing is 1 m.

Source meshes remain individually editable. Export geometry is merged by material, yielding 6–7 surfaces per module. V4_* materials retain source albedo from the manifest's sRGB palette; CyanGlow denotes emissive glass/status regions. Runtime supplies the final stepped cel lighting and integer-pixel viewport. No lighting is baked into the GLBs.

Each component is a closed volume. The canopy layers are real 6-mm panels with consistent, parallel front facets and verified outward normals, avoiding both backface disappearance and crossing glass layers. The circular engine opening is a true recessed annular tunnel with a layered rim and small deep ignition core.

The editable scene opens on the exact eight-module assembly with studio lamps and camera. Studio objects are excluded from the exported GLBs. Exploded proof demonstrates eight independently separable modules. The generator modifies only `source_art/modules_v4/` and `assets/modules_v4/`.

## Amber pigment revision

CourierYellow is now #eab32c (previously #ffc431): about 18% lower linear-light luminance, preserving the gold hue. Cream #ffebbe, Ochre #cf8529, all geometry, IDs, sockets, bounds and placement are unchanged. All seven icons are regenerated from the same revised Blender source. The preceding package is preserved in archive/2026-10-10T083631Z/single_cab_before_amber.zip.

## Actual-link joint sleeve

`assets/modules_v4/joint_sleeve.glb` is a small reusable sleeve for real structural links only. Its longitudinal axis is X. Exact bounds are X ±0.16, Y ±0.24, Z ±0.34 m. It has two material surfaces and 88 triangles: quiet #cf982d ochre plus one narrow navy gasket. It has no sockets. The renderer must place it only on actual cardinal workshop connections or sim.links and remove each instance when that edge breaks.

Editable source: `joint_sleeve_source.blend`; generator: `build_joint_sleeve.py`; proof: `proofs/joint_sleeve.png`; contract: `joint_sleeve_manifest.json`. A native Godot 4.6.3 check confirms a MeshInstance3D root with no children, identity transform and two surfaces. The data-free GODOT_single_root glTF flag prevents an importer wrapper, following the [Khronos extension specification](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Vendor/GODOT_single_root/README.md). The native check source is in `joint_validation_project/`; set XDG_DATA_HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME to writable task-local directories before running it.
