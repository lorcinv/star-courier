# Decorative workshop mechanisms

These are separate runtime-decorative Blender assets. They do not change the shop/city exports or the shop's verified empty module envelope. They contain no colliders, vehicle parts, or animations.

## Files

- `workshop_mechanisms_editable.blend`: separate named source pieces, moving source pivots, and a hidden merged export collection. Source dais is offset to the right for easy editing; exported roots remain centered at zero.
- `create_mechanisms.py`: reproducible generator, export validation and pose proof.
- `mechanisms_manifest.json`: exact names, pivots, local/default bounds, palette, triangles, surfaces and SHA-256.
- `workshop_mechanisms_proof.png`: retracted, medium and extended lift states, plus the separate dais. The large dark ground is proof-only.
- `assets/environment_v4/assembly_lift.glb`: one reusable stand, intended to be instantiated twice.
- `assets/environment_v4/clerk_dais.glb`: the clerk's separate step behind the service counter.

Rebuild from the project root:

```sh
blender -b --python source_art/environment_v4/create_mechanisms.py
```

## Lift anchors

Godot axes: +Y up, +Z toward camera. Root `AssemblyLift` is centered in X/Z, with floor contact at Y=0. Instantiate roots on the assembly platform at world Y=.46; choose X positions inside the actual craft bounds. Suggested Z≈-.3 places stands behind the module plane.

- `BaseHousing`: fixed geometry, 0..0.60 high. Main foot is .86×.86; front hazard trim makes total depth approximately .89.
- `PistonRod`: a MeshInstance with origin at local (0,.30,0). Its actual mesh Y bounds are exactly 0..1. Scale only its Y component.
- `TopSaddle`: an empty parent whose origin is the top contact plane. Every saddle vertex is at or below local Y=0; its child is `TopSaddleMesh`.
- Default saddle contact height is local Y=1.45. Default rod Y scale is1.02.

Update each instance using the desired world contact just below the lowest installed part:

```gdscript
var contact_y = desired_world_contact_y - lift_root.global_position.y
saddle.position.y = contact_y
rod.scale.y = maxf(0.02, contact_y - 0.43)
```

A contact height of .66..3.10 above the stand root is the intended visible range. Hide/retract the stand if the design's underside is below that range or a lower-row edit would occupy it. Hide both stands before launch. Their placement and visibility are controlled by the game; the GLB contains no automatic motion or collision.

Find `PistonRod` and `TopSaddle` recursively by name under the imported scene root. Do not stretch the whole lift or the saddle when adjusting height.

## Clerk dais

Root `ClerkDais` is floor-centered. The source verifies overall size1.10×.25×.85, with contact top at Y=.25. Runtime can place it directly behind the counter beneath the clerk's .25-high feet origin. It has no collider; it is an honest visual step supporting the actor placement.

Lift export: 852 triangles, 11 material surfaces, 5 nodes. Dais: 220 triangles, 4 material surfaces, 2 nodes. No image textures, emissive surfaces, lights, cameras, animations or physics are exported.
