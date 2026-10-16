# 苔光温室：花盆小勺包裹

One project-bound raster parcel: a narrow, shallow kraft-cardboard tray containing a visible silver spoon, bound with green cord. It is intended for the existing 小禾 empty-hand handoff. No actor frame, scene, dialogue, or gameplay system was created or changed by the art worker.

## Selected runtime

- `assets/2d_v5/mosslight/parcel-flowerpot-spoon.png`
- Original resolution: 2172 × 724 RGBA
- SHA-256: `93e0b2fe5943e32b8c35f9d2824ac220ad8a61cafcd9b6a7c9d72275e9924c50`
- Runtime bytes exactly match `originals/parcel-flowerpot-spoon-refined.png`.
- Both creation and refinement used built-in `image_gen.imagegen` with `transparent_background=true`. The complete prompts and both generated original files are preserved here. No programmatic drawing, cropping, resizing, palette remapping, or alpha cleanup was applied.

## Placement recommendation

Read `asset-registration.json` for the machine-readable dimensions, bounds, provenance, and contact registration. The stable visible bounds at alpha ≥ 16 are [512, 206, 1628, 527], with exclusive maximum coordinates, or 1116 × 321 pixels. The parcel contact center is [1070, 366.5] in the original canvas.

A uniform scale of 52 / 1116 gives a 52 × 14.957 world-pixel visible parcel. For a centered Godot Sprite2D retaining the complete original canvas, offset [16, -4.5] aligns that contact center with the existing parcel position. These are integration recommendations; the art worker did not validate an in-game hand contact or write runtime code.

## Editable source

`parcel-flowerpot-spoon.ora` is an editable OpenRaster container with exactly ONE whole-image raster layer. Spoon, tray, and cord are painted together. It does not contain separate object layers, vectors, or a rig. Its layer PNG and merged-image PNG are byte-for-byte copies of the selected original. The ZIP/XML container and raw PNG bytes were verified; GUI opening was not tested.

## Transparency and validation

The selected image was visually inspected. Read-only pixel measurement confirms RGBA transparency and broad transparent margins. The generator also left extremely faint alpha=1 pixels outside the visible item, so raw nonzero-alpha bounds are [168, 23, 1790, 706]. Alpha thresholds in registration are measurements only. Strict binary alpha and perfectly zero alpha outside the visible silhouette are not claimed. No opaque background, text, or new character is present.

Existing mosslight background and receiver files were preserved. No `.import` file was fabricated by the art worker. Import, contact-scale validation, and game tests belong to integration.
