Implementation approved and completed in the separate textured candidate. This original plan is retained for context; exact applied objects and rectangles are in material_uv_manifest.json.

# Selective hero-atlas UV plan · awaiting visual review

No GLB or pre-existing source has been changed. This plan applies the raster atlas to a handful of existing physical surfaces. It does not replace 3D objects, use a full-scene image, or bake the lighting.

## First proof review

`hero-surface-atlas-01.png` was created with the built-in image-generation tool. It is1254×1254 RGB, rather than the1024-square requested in the prompt. The atlas has the intended quiet cobalt strips, kraft parcel variants and restrained ochre accents. Caveats before approval:

- Some gentle color gradients and mottled paper grain were generated despite the unlit-flat request.
- Thin dark/light tile rims resemble a slight painted bevel. They should be excluded by UV insets, since model bevels already exist.
- Tile boundaries are uneven, so UVs should use measured pixel rectangles rather than assuming a perfect grid.
- The first proof should be checked in the actual close workshop camera before spreading it to more surfaces.

If the surface variation looks like baked illumination under real lights, request a targeted imagegen revision that flattens only the broad fields while preserving the small labels, edge chips and tile layout. Do not manually paint over or silently recolor this generated proof.

## First target set

1. Three existing drawer faces only:
   - `Tool drawer -1.71 0`: deep navy drawer strip01
   - `Tool drawer -1.71 2`: cobalt drawer strip02
   - `Tool drawer 3.84 1`: quiet navy drawer strip03
   Only the front planar polygon gets the atlas. Keep side faces, real bevels, handles and the rest of both cabinets on the existing palette materials.
2. Three parcels in the counter area:
   - `Counter outgoing parcel` body, existing raised shipping label and tape
   - `Shelf parcel 1.995 0` body and existing label
   - `Shelf parcel 3.355 1` body; use the existing unlabelled geometry without adding another physical object
   Sample quiet kraft subregions for box bodies, label subregions for the existing raised paper labels, and tape subregions for the real tape bands. This avoids printing a second label beneath the existing 3D label. Preserve all mesh positions and silhouettes.
3. Leave every other environment surface unchanged for this first application. The ochre service panel is reserved for a later reviewed pass, not an automatic expansion.

## One shared texture/material

- Keep the original generated PNG untouched in this source folder.
- After approval, copy it to `assets/environment_v4/textures/hero-surface-atlas-01.png` and reference that stable project path.
- Add one material, `V4_HeroSurfaceAtlas01`, with white albedo multiplier and the atlas as its albedo texture. White avoids tinting the already-colored pixels a second time.
- Keep the existing roughness and fully opaque rendering. The atlas has no emission, normal map, metallic map or transparency.
- Export textured selected polygons as one material-grouped mesh/surface where possible. Continue merging all remaining surfaces by their existing V4 palette materials.
- Preserve mesh geometry and previous source documents. The first application should be a separate editable textured preview/source and a separate review export, not an overwrite before inspection.

## UV and import details

`atlas_regions_01.json` lists measured top-left-origin pixel bounds and inner sample rectangles for the generated image. Use actual1254px dimensions; do not infer a1024 or power-of-two layout. The suggested inner rectangles exclude tile separators. Final label-only and quiet-kraft subrects should be inspected at source resolution before assignment.

Map drawer fronts with U increasing left-to-right and V increasing bottom-to-top in Blender. Convert the top-origin source rectangles once when assigning Blender UVs; let the glTF exporter handle its standard V conversion. Verify an A2/03 label is upright in Godot to catch a double flip.

Use nearest filtering, clamp/no-repeat, and disabled mipmaps for the small initial pixel-art proof. Keep UVs inset from adjoining tiles so neighboring colors cannot bleed across boundaries. Review at the native workshop zoom rather than only at full atlas resolution.

The runtime cel material should sample the imported albedo texture in its albedo path, then apply the same real-light/cast-shadow treatment as palette-only geometry. Its material-cache key must include texture identity as well as base color; otherwise this white atlas material can collide with a different white material. No texture should bypass world lighting or replace geometry shading.

## Acceptance checks before integration

- Same object count/vertex positions and unchanged module clearance.
- One added shared atlas material at most; no per-parcel image files.
- Drawer handles remain real geometry and labels do not overlap the handles.
- Parcel labels remain single and correctly oriented; tape stays raised.
- No rim lines mistaken for extra 3D bevels, no visible atlas seams, no flicker or texture bleed at actual camera zoom.
- Both day and night retain real directional shadows, and untextured shop surfaces remain untouched.
