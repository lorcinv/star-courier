# V4 launch rail and fixed pier

Separate editable decorative support assets for the actual launcher modules. These do not include a spring, battery, beam module, fake vehicle, collider, or animation. The game positions the supports under the real simulation assembly and leaves them behind at ignition.

## Source and proof

- `launch_supports_editable.blend`: named individual rail/pier pieces and hidden merged runtime meshes. Source roots are spaced apart for editing; exported roots are identity and zero-centered.
- `create_launch_supports.py`: deterministic build, export, bounds checks, original-asset hash checks and proof render.
- `launch_supports_manifest.json`: exact bounds, triangle/surface counts, pivots, palette and hashes.
- `launch_supports_proof.png`: a unit rail on one pier beside a3.7m stretched rail on two piers. The floor is proof-only.

Rebuild from the project root:

```sh
blender -b --python source_art/environment_v4/create_launch_supports.py
```

## Runtime contracts

Godot X is horizontal, +Y is up, +Z is toward the camera. Both assets use identity transforms and have one mesh beneath a named root.

### launch_rail.glb

- Root `LaunchRail`; mesh `LaunchRailMesh`.
- Exact local bounds: X=-.5..+.5, Y=-.35..0, Z=-.625..+.625.
- Root Y=0 is the top contact plane. All geometry is at or below that plane.
- Unit X length is1m. Set only `scale.x` to the desired length in meters. Keep Y/Z scale at1.
- Deep navy lower beam, cobalt shoulders and recessed deck, real longitudinal grooves, warm cream bearing edges and one broad yellow hazard inset.
- All features run continuously along X. There are no small repeated bolts or units to become stretched patterns.

### launch_pier.glb

- Root `LaunchPier`; mesh `LaunchPierMesh`.
- Exact bounds: X/Z=-.45..+.45, Y=0..1.20.
- Root Y=0 is floor contact; top bearing plate is atY1.20.
- Broad beveled foot, splayed structural legs, recessed shear web, crosspiece and a solid upper capital.
- Use2–3 fixed piers under the stretched rail. Keep the pier scale unchanged.

For piers resting at worldY0, the rail root/contact plane is atY1.55: pier height1.20 plus rail depth.35. More generally, rail contactY = pier rootY +1.55, so the rail underside rests on the pier bearing plates.

Both meshes share only four existing V4 materials: FrameNavy, Cobalt, Cream and Gold. Each asset has four surfaces, eight combined. No textures, emissive surfaces, cameras, lights, animation or physics are exported.

The generator verifies every pre-existing environment GLB hash before/after its work. Shop, city, maintenance lifts and clerk dais remain unchanged.
