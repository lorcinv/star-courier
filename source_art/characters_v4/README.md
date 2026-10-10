# Star Courier · dimensional Q character studies v4

Two original Blender-authored character studies for the approved pixel-cel workshop direction. These are rounded, fully dimensional meshes, not extruded silhouettes or traced image layers. The concept reference was inspected at its original 1672 × 941 resolution. The subsequently approved 4K reference is a nearest-neighbor upscale of that same composition, not a source of additional detail.

## Deliverables

- `star_courier_q_cast_v4.blend`: editable Blender 4.3.2 source, neutral authored poses and proof studio
- `build_characters.py`: complete reproducible geometry, palette, export and proof generator
- `../../assets/characters_v4/clerk.glb`: cyan/blue-haired courier clerk in a yellow padded jacket
- `../../assets/characters_v4/customer.glb`: charcoal-capped customer in a cream jacket, large cross-body satchel
- `palette.json`: named V4_* material albedos, source sRGB hex colors
- `export-validation.json`: checks of the actual exported binary GLBs
- `proofs/01-neutral-front.png`: front view, authored rest poses
- `proofs/02-dimensional-three-quarter.png`: shallow three-quarter views exposing depth, boots and satchel
- `proofs/03-exchange-pose.png`: small editable head/arm pose deltas
- `proofs/04-hub-size-proof.png`: 270 × 200 render; actors are approximately 125px tall
- `proofs/05-face-closeups.png`: eye/face and hair-mass inspection

These are art-study Blender renders. They are not game screenshots or evidence of final in-engine acceptance. Runtime scene edits are owned by the integration pass.

## Rebuild and validation

From the project root:

    LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DIR=/tmp/characters-v4-mesa blender -b -t 4 --python-exit-code 1 --python source_art/characters_v4/build_characters.py
    python source_art/characters_v4/validate_glbs.py

Use `-- --skip-render` to regenerate source and GLBs without the five proof images. The proof materials use EEVEE quantized diffuse bands. The exporter temporarily connects a standard Principled BSDF with the exact named source albedo, so custom Blender nodes are not needed at runtime.

## Form and scale

Both exports are exactly 2.4 units high, with floor at 0. The main head/hair mass is approximately 2.7 heads to the total height, with a small courier cowlick outside the main cranial silhouette. Broad hair shapes, large curved anime eyes, compact padded torsos, mitten hands and oversized work boots carry the design at small screen size. Surface details are intentionally sparse.

The clerk has a swept blue/cyan bob, broad collar, bright cropped yellow jacket and open counter-service palms. The customer has a soft charcoal cap, brown fringe, cream parka, warm amber eyes and a large rounded satchel with an ochre flap. Both characters and costumes are original.

## Engine contract

- glTF/Godot +Y is up; +Z faces the camera; Blender equivalents are +Z up and −Y front
- Six rigid editing pivots per actor: BodyPivot, HeadPivot, LeftArmPivot, RightArmPivot, LeftLegPivot, RightLegPivot
- Names on the second actor can receive Blender numeric suffixes; locate by prefix
- FaceLook_Anchor and LeftPalm_Anchor / RightPalm_Anchor are exported editable reference nodes
- Each pivot owns one joined volume mesh. Original part names remain as Blender vertex groups and the `editable_part_names` mesh-object property for selecting eye, hair, clothing and hand parts
- No negative-scale mirroring; all actual GLB triangle winding/vertex-normal checks pass
- Single-sided surfaces; curved facial details have physical separation and radial subdivision to prevent planar patches from sinking into the round face
- On Godot import, set `meshes/generate_lods=false`. Automatic reduction can collapse the small curved eye/mouth layers
- Preserve each V4_* base albedo when assigning the runtime cel shader. Do not replace all actor surfaces with one palette color
- No collision shapes, armature, skinning or animation clips are exported

The courier’s authored rest palm anchors are local Godot Y≈1.12 and Y≈1.10. On the agreed 0.25-high standing dais these become world Y≈1.37 and Y≈1.35, just above the 1.30 worktop. The glove undersides meet the worktop rather than floating at face height. The source retains the complete body for subsequent posing and art preparation.

Per actor: six mesh nodes, with 19 clerk material surfaces and 17 customer material surfaces. Exact triangle counts, bounds and palm coordinates are in the manifest and validation report. Broad, rounded volume is retained rather than aggressively decimated into screen-space polygons.

## Spine boundary

The actual Spine editor is unavailable and licensing is unresolved. This delivery contains no .spine or .skel file and does not claim Spine binding, animation, or export is complete. Named Blender part pivots are only a reversible modeling and pose-preparation convenience. A real Spine authoring/export step remains a separate blocked workflow.
