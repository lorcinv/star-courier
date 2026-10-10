# Selective hero surface atlas · V4

The original imagegen atlas is `hero-surface-atlas-01.png`, exactly1254×1254 RGB. Prompt, built-in generation provenance and original SHA-256 are in `generation-01.json` and `atlas_regions_01.json`. The image is original raster surface art, not a full-scene background. Its subtle grain is being judged in actual Godot sampling.

## Applied scope

One shared `V4_HeroSurfaceAtlas01` material, white albedo multiplier, nearest sampling, no emission. Applied only to three drawer fronts and three counter/shelf parcel fronts, including their existing raised label/tape fronts where relevant. Eleven frontal polygons total. Bevels, handles, other object sides and all other shop surfaces remain on their original palette materials.

The atlas is stored at `assets/environment_v4/textures/hero-surface-atlas-01.png` and embedded once in the textured GLB. The editable preview packs the original PNG and retains a project-relative fallback path; fresh-process reopening and rendering are verified. Labels are not double-printed under existing raised paper geometry. Real lighting and shadows remain runtime-controlled.

## Source preservation

- Original `../shop_editable.blend` is untouched.
- `shop_cutaway_untextured.glb` is an exact backup of the original shop export.
- `shop_textured_editable.blend` is the separate textured editable source.
- `shop_cutaway_textured.glb` is the validated textured candidate.
- `material_uv_manifest.json` lists source object names, pixel rectangles, original hashes, export hash and publication state.
- `geometry_uv_validation.json` verifies20,532 unique exported vertex positions, world bounds and37,412 triangles match the untextured export. The new shop has31 surfaces, only one more than before.
- `hero-drawer-proof-01.png` and `hero-parcel-proof-01.png` are Blender close-ups. CPU sample noise in these proofs is not part of the atlas image.

## Rebuild and validate

From the project root:

```sh
blender -b --python source_art/environment_v4/surface_atlas/apply_hero_atlas.py
python source_art/environment_v4/surface_atlas/verify_textured_geometry.py
```

The first command generates a separate candidate and preserves the runtime shop. Add `-- --publish` only when the reviewed candidate should replace the runtime shop GLB. The original source is the build input, so a repeated pass does not layer UV edits onto prior edits.

Use `material_uv_manifest.json` and `verify_textured_geometry.py` for this textured stage. The earlier environment validation JSON is retained as the untextured baseline; its no-texture expectation is historical, not a failure of this approved material pass.

The corrected close-up proofs were rendered from a fresh reopened packed source and visually checked before the runtime GLB was atomically replaced. `packed_source_validation.json` records the packed PNG hash and successful fresh reopen.
