# Altitude ascent layers

These are independent raster layers derived from the preserved imagegen originals. They are not a concept-scene overlay. `tools/prepare_ascent_layers.py` reproduces the runtime assets and writes source/output hashes, crop coordinates, palette provenance, alpha bounds and measured edge errors to `technical-manifest.json`.

## Layer behavior

| Layer | Screen pixels per camera metre, X / Y | Wrapping |
|---|---:|---|
| Tall atmosphere | 0.6 / 12.5 | Ordinary X; clamped vertical ascent through authored plate |
| City skyline | 4 / 5 | Ordinary X; no vertical repeat; falls below viewport |
| Cloud banks | 8 / 9 | Ordinary X and Y |
| Near wisps | 18 / 20 | Ordinary X and Y |
| Distant stars | 0.5 / 0.6 | Ordinary X and Y; quiet inspected central upper crop |
| Planet limb | 0.025 / 0.12 | Small clamped drift; never repeats |
| Near orbit dust | 16 / 18 | Ordinary X and Y; 0.32 maximum opacity |

Actual negative cargo Y, relative to `background_ground_y_m`, controls the 85–135 m atmosphere-to-orbit interval. Horizontal route progress is diagnostic only. Cloud opacity falls away from 80 to 130 m. Positions of every moving layer follow the supplied camera center in departure-relative simulation metres; omitting that argument uses the cargo position. A camera dead-zone also restrains blur. Identical quantized camera samples retain a stable motion estimate; an explicit zero presentation velocity immediately clears blur for pause. Blur is texture-local, signed in both axes, seven taps maximum, 24 pixels maximum, and disabled by either accessibility setting.

There are exactly seven cached Sprite2D / ShaderMaterial pairs, no clocks or processing in the component, and no per-update resource creation. Source-coordinate modulo happens before multiplication. The city and planet never repeat vertically, and no layer reverses its source orientation.

## Technical cleanup and seams

All generated originals remain unchanged. Runtime layers use nearest sampling, a fixed 2-pixel grid and the common reference-derived 96-color palette. Cloud and wisp alpha thresholds expose their already-transparent margins. The city, atmosphere and star tiles require narrow premultiplied edge corrections; image generation was not assumed to produce seamless tiles. Every declared repeating edge has zero RGBA difference after cleanup, including over an authored sky composite.

Dust uses the original positions and actual pixels of 28 authored visible islands, reduced to 25% of their sampled size about their existing centers. The largest surviving island is 12 pixels and total opaque occupancy is approximately 0.056%. It is decorative background depth, not a collision object.

The first full-width star crop passed edge equality but showed repeated broad nebula ribbons in the native render. Visual review rejected it. The final crop is `(643, 8, 1191, 317)` in the existing orbit original, with quiet edges chosen to avoid clipping bright stars. It retains source-painted sky and stars without synthetic fill, mirrored stars, or generated replacement noise.

## Verification

- `tests/test_ascent_backdrop.gd`: 32 focused checks, including 12,000 updates, no resource growth, finite huge/reverse positions, both-axis periodicity, actual source/composite edge pixels, altitude transitions, camera-held/vertical-only blur, settings and frozen state.
- `runtime_ascent_proof.gd` / `run_native_ascent_proof.py`: actual native Godot GL Compatibility renderer, isolated Xorg and user data. Native Enter starts scripted camera segments for slow ascent, fast ascent, orbit and reverse. This tests the component, not integrated gameplay controls.
- `native-render-validation.json`: frame/wall intervals and engine FPS samples separately from the 30 FPS capture rate, exact paused-frame equality and opaque generated cargo-pixel equality when background blur toggles.
- `native-ascent-layers.mp4`, `runtime-*.png`, `*-ordinary-wrap-seam-proof.png`: visual evidence. The recorded clip must correspond to the current final star crop; check the validation artifact hashes.

This is software llvmpipe evidence, not a Windows or discrete-GPU performance claim. Integrated game camera, hazards, controls, HUD and delivery validation belong to the parent task.
