# Star Courier · 2D actor source set

Four original transparent raster drawings created with the built-in `image_gen.imagegen` tool, using the approved shop concept as the identity/style reference. No SVG drawing, procedural actor artwork, old 3D models, or 3D renders were used.

## Runtime files

| Character | Idle | Hand-off | Shared canvas | Foot anchor |
|---|---|---|---|---|
| Blue-haired clerk | `assets/2d_v5/actors/clerk-idle-pixel.png` | `assets/2d_v5/actors/clerk-handoff-pixel.png` | 159 × 256 | (85.59, 247.59), pixel snap (86, 248) |
| Dark-haired customer | `assets/2d_v5/actors/customer-idle-pixel.png` | `assets/2d_v5/actors/customer-handoff-pixel.png` | 167 × 256 | (73.19, 247.78), pixel snap (73, 248) |

Both actor bodies are 240 logical pixels high. The shared frame is 256 high with transparent padding. Per-actor idle and hand-off frames have **one shared source union, nearest sampling scale and registration**, rather than separate auto-trims. The two drawn poses are visually matched; the original generated images are not pixel-identical outside the arms.

At 1280 × 720, the initial integration target is clerk body height 210 at foot (276, 486), behind the foreground counter, and customer body height 215 at foot (148, 488), in front of it. These are placement suggestions, owned by the scene integrator. Apply actor scale `desired body height / 240`, then translate the supplied foot anchor to the floor point. If the adapter scales the whole 256-high texture, a 210-high texture gives a 196.875-high body. Rendering should use nearest texture filtering, no mipmaps, integer positioning after camera transform, and integer scaling wherever scene composition permits.

Both actors have empty hands. Place a separate parcel at the supplied per-frame `hand_and_parcel_anchors.parcel` in `actor-manifest.json`. The hand/parcel points are manually estimated attachment guides, not measured skeletal joints. Clerk faces left; customer faces right. Use hand-off as an interaction state, then return to idle. These two frames are not a walk cycle.

The complete source dimensions, original raw alpha bounds, effective alpha128 bounds, final alpha bounds, per-pose hand guides, and original/runtime SHA256 values are in `actor-manifest.json` (also copied to the runtime folder).

## Preserved originals and exact prompts

- `clerk-idle-original.png` and `clerk-idle.prompt.txt`
- `customer-idle-original.png` and `customer-idle.prompt.txt`
- `clerk-handoff-original.png` and `clerk-handoff.prompt.txt`
- `customer-handoff-original.png` and `customer-handoff.prompt.txt`

All four generated originals are **1254 × 1254 RGBA**; 1024-square was requested in the idle prompts but the tool returned 1254-square images. Actual measured sizes, rather than requested sizes, are authoritative. The original output files remain unmodified at the tool's default generated-images destination as well as in this source folder.

Tool: built-in `image_gen.imagegen`, with `transparent_background=true` on all four calls. Exact model/version is not reported by this tool and is not claimed.

Idle source references:
1. `source_art/art_direction_v4/pixel-cel-shop-reference-03.png`: identity, palette, camera and original pixel-art style.
2. `source_art/2d_v5/generated/shop-shell.png`: palette and scene-camera compatibility.

Each hand-off pose used only its own original idle image as the edit target. Input reference images were inspected before calling image generation. Tool output filenames and source hashes are in the manifest. No Spine runtime or editor was used.

## Runtime cleanup, separate from originals

The generated alpha channel contains very faint distant speckles and an interior mostly at alpha 253 rather than 255. Therefore raw alpha>0 bounds can extend nearly to the source-canvas edge even though the visible character is cleanly inside it. These are explicitly recorded rather than mistaken for character extent.

`build_actor_derivatives.py` performs only:
1. Alpha threshold at 128, producing exactly transparent/opaque output.
2. Per-actor union crop across idle and hand-off, preserving common source registration.
3. Nearest-neighbor sampling to a 240-high body, with 8 logical pixels of canvas padding.
4. Nearest-color matching to the existing 96-color approved-reference palette, without dithering.

No new artwork is synthesized by the cleanup script. The original generated drawings stay byte-for-byte intact. `*-native.png` are additional full-resolution thresholded derivatives on common per-actor native canvases: clerk 717 × 1185 and customer 705 × 1107. Those native copies are not palette-quantized; prefer `*-pixel.png` at runtime.

`actors-pixel-contact-sheet.png` is a labeled neutral-blue review image. Its background is only in the review sheet; actual actor PNGs have real transparent backgrounds.

Rebuild and validate from repository root:

```sh
python source_art/2d_v5/actors/build_actor_derivatives.py
python source_art/2d_v5/actors/validate_actor_assets.py
```

## Scope and limitations

These are original raster source assets and a practical two-pose sprite set. They are **not actual Spine binding**, not `.spine` projects, not exported Spine JSON/binary/atlas assets, and not separated bone-ready limbs. Real Spine editor/license/export remains unresolved and requires its own authorized authoring work. No game controller, scene script or HUD was changed by the actor asset worker.
