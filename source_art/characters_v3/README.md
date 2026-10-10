# Original graphic-cartoon cast

Authoritative editable Blender file: `star_courier_original_cast.blend`.
Rebuild from the project root: `blender -b -t 4 --python-exit-code 1 --python source_art/characters_v3/create_cast.py`. The generator resolves the project root from its own location, so absolute paths work too. Add `-- --skip-render` to rebuild the editable source and four GLBs without starting a proof render.
Proof pass: open the blend in background Blender and execute `render_proofs.py`. Set `STAR_COURIER_PROOF_DIR` to send proof images to a different review directory.

## Direction

Original adult working characters with exaggerated cartoon proportions, geometric hair, confident/skeptical/delighted expressions and visible occupational accessories. The style uses graphic animation’s bold contour and strongly separated color masses rather than realistic skin/hair. No existing character, costume, logo or traced art is used.

- Nova: lean express clerk, rocket-shaped asymmetrical cobalt hair, headset, coral courier jacket, yellow hard satchel, extended open-hand gesture.
- Bram: short/broad freight pilot, block pompadour, square glasses and chevron moustache, broad mustard work parka.
- Kiki: asymmetrical sound technician, magenta geometric bob, angled cyan coat panel, cocked stance, document bag and single yellow earring.
- Orin: tall/narrow field researcher, angular cloud hair, large attentive goggles, coat and twin pencils.

## Runtime contract

Exports replace `assets/environment_v2/courier_clerk.glb` and `customer.glb`; add `customer_2.glb` and `customer_3.glb`. Blender +Z up / -Y front becomes Godot +Y up / +Z front. Floor origin is zero. The visual heights intentionally vary around 2.0–2.5 units.

Six rigid pivot meshes per character: BodyPivot, HeadPivot, LeftArmPivot, RightArmPivot, LeftLegPivot, RightLegPivot. Blender suffixes names on the additional actors, so locate nodes by name prefix. Apply animation deltas relative to imported rest rotations: the courier arm and sound-tech legs already have authored pose rotations. The root remains freely movable for walking and idle bob; swing legs for walk, head for look/nod, arms for gesture. This is a rigid pose rig, not a skinned skeleton and does not contain animation clips.

All ink contours are actual front-border geometry plus dark extrusion sidewalls. Do not add inverted hulls or flip actor scale negative. Faces look best from the front or shallow three-quarter camera. This is purpose-built dimensional graphic art, not a fully rotational realistic character model.

Silhouette input winding is normalized before extrusion. Front caps face Blender -Y, rear caps face +Y, and shared prism edges have opposite orientation. Materials use backface culling in Blender and GLB so proof images cannot hide a reversed face. Keep `meshes/generate_lods=false` in all four Godot import files: these already-low-poly actors use closely layered graphic details that automatic mesh simplification can erase or collapse together.

Palette/materials: `Env_Ink #101c35`, `Env_Cobalt #3044aa`, `Env_Cyan #39d9d1`, `Env_Yellow #ffdf36`, `Env_Coral #fb6671`, `Env_Cream #fff1cc`, `Env_Orange #ff9748`, `Env_Magenta #be377a`. Emission supports flat proof renders; the runtime applies its existing palette material mapping.

Budget: 830–1186 triangles each, 6 mesh nodes each, 21–26 material surfaces summed across the six movable parts. No textures, skinning, hair systems, subdivision or runtime outline pass required. Exact counts are in `manifest.json`.

## QA

`docs/qa/characters-v3/cast-board.png`: composed full-body lineup. `face-closeups.png`: expression detail. `shop-scale-proof.png`: Blender proof using the actual shop GLB and real actor scale; this is not claimed to be a game screenshot. Game integration / live capture is owned by the gameplay implementation pass.

The rebuild validates all 148 silhouette outlines, front/back cap triangles and consistently oriented closed edges; 56 authored outlines require winding normalization. `geometry-validation.json` records those checks. The left sleeve mirrors its shoulder points as well as its cuff so it remains a simple polygon on every actor.

Run `python source_art/characters_v3/validate_exports.py` after export. `export-validation.json` checks the actual binary GLBs: 4,166 nondegenerate consistently oriented triangles, all 359 non-ink color-cap triangles facing Godot +Z, six named pivots per actor, preserved rest quaternions, single-sided materials and generated LODs disabled. Neither geometric audit substitutes for viewing the cast in the actual Godot game.

Run `blender -b source_art/characters_v3/star_courier_original_cast.blend -t 4 --python-exit-code 1 --python source_art/characters_v3/validate_layers.py` to check the saved rest pose for differently colored front caps that overlap at the same depth. `layer-validation.json` records zero coplanar overlaps and a minimum 0.005-unit separation where differently colored caps overlap. Nova's right glove and Kiki's left glove sit 0.04 units in front of their previous depths to clear their respective bags. Same-color joins remain allowed. This geometric test covers the authored rest pose, not every animation frame.
