# Star Courier · V4 city assets

Freshly modeled, fully dimensional low-poly orbital city from the approved `pixel-cel-shop-reference-03-4k-upscaled.png` direction. No earlier environment geometry, image backdrops, SVGs, or image textures are used.

## Deliverables
- `city_source.blend`: editable orbital-city, flight-city and sky collections with baked identity mesh transforms. Mesh islands are individually editable with Blender linked selection; materials are grouped for lean export.
- `city_build.py`: deterministic generator. Run from the project with `/usr/bin/blender --background --python source_art/environment_v4/city_build.py`.
- `city_manifest.json`: exact bounds, triangles, mesh/surface counts and sRGB palette.
- `city_validate.py`: read-only export checks; output is `city_validation.json`.
- `city_proof_shop_vista.png`, `city_proof_wide.png`, `city_proof_flight.png`: simple clean cel-lighting studies. They intentionally show the background alone; actual foreground occlusion is determined by the shop.
- `assets/environment_v4/{orbital_city,flight_city,sky_backdrop}.glb`: runtime exports.

## Runtime contract
Godot X is horizontal, Y is up, and +Z is toward the camera. All GLB nodes have identity transforms. Orbital city has no geometry forward of Z=-9.762, safely behind the shop back wall at -3.25. Sky is an enormous solid cyan slab with separate opaque, faceted cloud banks. No transparent sort ordering or 2D camera-facing planes are required.

Use orbital city plus sky for the workshop. Flight city is a separate larger district for parallax, not an additional overlay in the shop. Each city has 12 draw surfaces; the sky has 4. All meshes have flat-shaded geometry, with no animations, lights or cameras exported.

Palette names are `V4_City*` and `V4_Sky*`. Hex colors in the manifest are sRGB; Blender/GLB material factors are correctly stored in linear color. Keep the city atmosphere gentle enough that blue/periwinkle depth layers stay distinct. The proof renderer uses a three-value emission cel material only after export; the source blend and GLBs keep standard Principled materials for runtime recoloring.

The modeled composition uses stepped and split-spire districts, deliberately uneven skyline clusters, forked viaduct supports, a broad curving return flyover, sparse original gold skiffs, and warm grouped clouds at both bay and underfloor height.

## Integrated-shop refinement
The integrated Godot proof showed that orthographic city geometry needed a smaller apparent scale. Orbital X/Y is now baked to 40%/42%, with Z left unchanged. Small right-bay landmarks were repositioned across the opening; peripheral districts and extended rail tails preserve the underfloor width. Flight city is also smaller in X/Y. City blue values are softer and closer to cyan haze, and cloud banks use a smaller XY grouping. Export transforms remain identity.
