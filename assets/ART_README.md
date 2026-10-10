# 星际快递 · Original modular art

32 original Blender-authored low-poly assets: the exact 25 functional parts from the supplied brief, plus a separate cargo crate, landing pad, hangar terminal, hangar arch, and three asteroid variants. No downloaded models or texture assets are used.

## Sources and reproduction

- Editable source: `source/star_courier_assets.blend` (Blender 4.3.2)
- Generator: `../tools/generate_assets.py`
- Runtime meshes: `models/*.glb`
- Material/axis manifest: `models/manifest.json`
- Export validation: `models/validation.json`
- Inspected renders: `previews/asset_catalog.png`, `previews/environment_kit.png`

From the project root, run `blender --background --python tools/generate_assets.py`, then `python tools/validate_assets.py`. The Blender source folder has `.gdignore`; Godot uses exported GLBs, so end users do not need Blender installed.

## Engine contract

One unit is approximately one metre. Each modular part is centered at its origin and fits a nominal 1.2-unit XY grid cell. Godot/glTF +X is forward, +Y is up, +Z faces the camera. The Blender authoring equivalents are +X, +Z and -Y.

Every part exports `Socket_Right`, `Socket_Left`, `Socket_Top`, and `Socket_Bottom` empty nodes at ±0.6 along the corresponding Godot axis. These locate construction connections, not simulated physics constraints. Game logic owns collision, connectivity, durability, signals and functionality. Individual meshes remain separate for visual animation and material replacement.

The `thruster` exhaust points toward -X, giving +X thrust. Weapon and sensor directions are +X. Rotating a complete part in the gameplay plane rotates its functional direction. GLBs have no baked collision shapes.

The landing-pad top is at Y≈0. Its width is 5m. The 8.9m hangar arch and 1.5m terminal use floor origins. Cargo and asteroid pivots are centered.

## Visual language

Cream armor, orange industrial machinery, deep navy structure, cyan energy/status indicators and magenta spatial/volatile details. Material names start `SC_`. Preserve each material’s base color when replacing it with the game’s quantized-light cel shader. Bevelled edges and faceted geometry carry the lighting; no normal maps or texture downloads are necessary.

Preview renders demonstrate asset geometry and material colors. Runtime toon shading and outlines are implemented by Godot rather than embedded in glTF, which does not carry custom Godot shaders.

## Catalogue order

cell, power_valve, thruster, spring, turntable, beam, separator, damper, tachyon_lance, accelerator, arc_emitter, explosive_core, armor, shield, decoy, shrink_ring, enlarge_ring, displacer, splitter, distance_probe, collision_switch, delay, and_gate, or_gate, not_gate.

The cargo crate is an additional payload object and does not replace any of the 25 required parts.
