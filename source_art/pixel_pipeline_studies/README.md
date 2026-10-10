# Star Courier pixel-grid study

## Recommendation

Use a **640×360 logical world** with exact integer nearest-neighbor display. The preferred reference cleanup is **96 fixed colors**, with 12 measured accent colors protected. Keep the unrestricted grid-only version as the minimum-change reference. The original approved image and its earlier 4K enlargement remain untouched.

This study cleans the reference for visual targets and palette selection. It does **not** turn the painting into geometry, reconstruct hidden surfaces, or replace the game scene with a flat background.

### Inspect these files

- `clean_96c_640x360.png`: the actual logical-resolution result.
- `clean_96c_640x360_4k_nearest6x.png`: 3840×2160 preview; every logical texel is exactly 6×6 display pixels.
- `comparison_overview.png`: original, grid-only, 96-color, 64-color, 16-color, and coarser-grid comparison.
- `comparison_clerk.png`, `comparison_craft.png`, `comparison_warm_cool.png`: before/after close-ups. Cleaned crops use exact integer scale; the original crop is separately labeled.
- `palette_96.json` / `.gpl`: fixed reusable palette.
- `palette_anchors.json`: measured source colors for material/art direction.

## What was actually done

Input: `../art_direction_v4/pixel-cel-shop-reference-03.png`, 1672×941, SHA-256 `bd9388bd6cb6784572cabd0eca876bb6fce9a6d7c538438128d22d8367242cae`.

The image contains 461,254 distinct RGB colors. Its apparently pixel-like edges contain many small intermediate color changes; a nearest enlargement alone preserves these. There is insufficient evidence to claim one uniquely recoverable original pixel grid.

1. Select a uniform target grid, testing 640×360, 560×315, and 480×270. Preserve the full composition.
2. Partition the source into matching cells and choose an existing source pixel closest to that cell's channel median. No interpolated or newly generated color is introduced by this step.
3. Compare unrestricted color against 96-, 64-, and 16-color palettes. Fit the palette in Oklab once, weighting the clerk and craft so small accents are not overwhelmed by the sky.
4. For 64/96 colors, keep 12 source-derived accent anchors: navy ink, cobalt hair, coral hair, turquoise eye, two skin tones, yellow/ochre craft, cyan display, cyan sky, blue city, warm cream.
5. Use no added dithering. Export the logical result and the integer-scaled preview separately.

The 1672×941 input is very slightly different from exact 16:9. Source sampling cells alternate between 2 and 3 source pixels at 640×360; the complete boundary map is recorded in `grid_only_640x360_source_cuts.json`. This is input resampling, not variable pixel sizes in the output. The final 4K grid has constant square 6×6 blocks.

## Visual findings

- **640×360 / 96 colors:** retains the clerk's expression, turquoise eyes and coral fringe; separates warm shop lighting from the blue city; preserves the craft's yellow silhouette, white wing and dark canopy.
- **640×360 / 64 colors:** usable, but flattens more skin/steel shading and some sky/light transitions. It is a comparison, not the recommended default.
- **16 colors:** visibly loses the coral fringe and turquoise eye character, and collapses lighting ramps. Do not accept the tool's default count without checking this scene.
- **480×270:** too coarse for the small face, canopy highlights and UI-like marks at this composition scale.
- **Grid-only:** keeps more subtle colors but still contains 123,603 RGB values; useful as a low-intervention art reference rather than a fixed palette.

The concept's tiny lettering is not production UI. It must be recreated as readable native game text rather than accepted as processed image text.

Uniform grid and fixed palette are necessary technical properties, not a substitute for pixel-by-pixel art direction. Fine contour placement, tiny facial marks, isolated pixels and animation silhouettes still deserve manual asset-level review. Do not run this whole-scene image through a converter and call the 3D game finished.

## GitHub code reviewed

All five repositories have MIT license files. Copies are in `licenses/`; repository tree identifiers and reviewed-file blob SHAs are in `github_sources.json` and `reviewed_source_files.json`. No downloaded program or script was installed or executed. `study_reference.py` is bounded project-native processing, informed by the reviewed algorithms; it is not a claim of output parity with the upstream CLI.

### Sprite Fusion Pixel Snapper

[Source](https://github.com/Hugo-Dz/spritefusion-pixel-snapper/blob/main/src/lib.rs) · [license](https://github.com/Hugo-Dz/spritefusion-pixel-snapper/blob/main/LICENSE)

Actual code quantizes in RGB before computing edge profiles, estimates peak spacing, walks/stabilizes cell cuts, then votes for a whole RGBA color per cell. The default palette is 16. The profile filter ignores closely spaced peaks, so automatic results should not be treated as artistic ground truth for this mixed-scale image. Its published Cargo installation route is documented, but Cargo was not installed in this environment and no upstream binary was run. Explicit target-grid and palette testing were used instead.

### Pixel Game Kit

[Pipeline](https://github.com/kenyonxu/pixel-game-kit/blob/main/src/lib.rs) · [Oklab](https://github.com/kenyonxu/pixel-game-kit/blob/main/src/quantize/oklab.rs) · [cell vote](https://github.com/kenyonxu/pixel-game-kit/blob/main/src/resample/majority.rs) · [license](https://github.com/kenyonxu/pixel-game-kit/blob/main/LICENSE)

The fork adds Oklab quantization, multiple detector heuristics and reference-palette locking. The implementation still performs analysis quantization before cell resampling. Whole-pixel majority preserves a palette; the separate per-channel median method can mix channels from different colors, so exact palette membership still needs testing. This study adopts perceptual color comparison and one shared palette, uses an existing-pixel representative instead of blended cell colors, and protects measured scene accents. Detector confidence is a heuristic, not proof of a uniquely correct grid.

### Robert K's 3D pixel-art camera

[Camera](https://github.com/Robert-K/godot-3d-pixel-art/blob/main/scripts/rendering/camera_3d_texel_snapped.gd) · [display](https://github.com/Robert-K/godot-3d-pixel-art/blob/main/scripts/rendering/display.gd) · [license](https://github.com/Robert-K/godot-3d-pixel-art/blob/main/LICENSE)

The camera converts orthographic size to world units per logical texel and snaps in camera space. It retains a subpixel error for display correction. Object snapping is temporary and reverted after rendering. Reuse the presentation-only separation, not the entire example: it contains a debug-draw dependency and an optional smoothing upscaler, whereas this game's strict reference requires nearest sampling and a constant logical grid. Continuous rotation and zoom still change rasterized silhouettes.

### Astrellon's Godot experiment

[Camera](https://github.com/astrellon/godot-3d-pixel-art/blob/main/camera/main_camera.gd) · [outline shader](https://github.com/astrellon/godot-3d-pixel-art/blob/main/materials/outline.gdshader) · [license](https://github.com/astrellon/godot-3d-pixel-art/blob/main/LICENSE.md)

Its camera-space snapping is relevant. Its outline shader reads the normal-roughness buffer and reconstructs depth with Vulkan-style NDC, so that shader is not a drop-in for this project's Godot 4.6.3 GL Compatibility renderer. Camera ideas and render-backend-specific shaders must be evaluated separately.

### Leo Peltola's pixel-art shader

[Shader](https://github.com/leopeltola/Godot-3d-pixelart-demo/blob/master/pixelart_stylizer.gdshader) · [license](https://github.com/leopeltola/Godot-3d-pixelart-demo/blob/master/LICENSE)

This shader explicitly samples a normal-roughness texture and screen/depth buffers. Its normal-based highlights require Forward+. It also writes ALPHA; screen-reading transparency has ordering/coverage limits. Do not import it as a general fix for a GL Compatibility scene, and do not change the renderer solely to adopt this shader.

## Godot 4.6.3 integration decisions

The current project declares GL Compatibility. Keep the low-resolution SubViewport, nearest TextureRect, disabled MSAA and screen-space AA. Fix the logical world at 640×360 instead of deriving its resolution independently for each window. 1280×720, 1920×1080, 2560×1440 and 3840×2160 then use 2×, 3×, 4× and 6× display scales. At 1440×900, use a centered 1280×720 art frame and map picking/HUD labels through that frame.

For an orthographic KEEP_HEIGHT camera, one logical vertical texel is camera size divided by 360 world units. Snap the rendered camera in its right/up basis while retaining the unsnapped smoothing state. Snap shake offsets too; offsets applied afterward can restore subpixel crawl. Do not modify simulation, collision or save-state positions to satisfy the art grid.

Keep authored outline geometry and the existing material light ramp on the Compatibility path. A depth-only postprocess would require the correct Compatibility NDC conversion; normal-buffer edge effects are unavailable here. Screen-reading effects also omit the transparent pass from their captured screen texture. These restrictions are explicit in [Godot's screen-reading documentation](https://docs.godotengine.org/en/4.6/tutorials/shaders/screen-reading_shaders.html) and [advanced postprocessing documentation](https://docs.godotengine.org/en/4.6/tutorials/shaders/advanced_postprocessing.html).

Use fixed color ramps or a fixed shared palette across animation frames. Do not independently refit colors per frame. Start without dithering. If later needed, anchor ordered dithering to integer logical texels, or to a deliberately quantized object/world coordinate system; never use time-varying random noise. A shadow threshold alone does not establish stability: camera motion, light/caster motion and shadow-map sampling must be tested separately.

Godot's [multiple-resolution guide](https://docs.godotengine.org/en/4.6/tutorials/rendering/multiple_resolutions.html) recommends integer scaling and identifies 640×360 as a useful baseline. [Camera3D documentation](https://docs.godotengine.org/en/4.6/classes/class_camera3d.html) defines orthographic size and camera offsets.

## Independent acceptance criteria

Artifact checks already run: **19 passed, 0 failed** in `validation_results.json`.
An additional full regeneration reproduced all 19 compared PNG/palette artifacts byte-for-byte (`reproducibility.json`).

- Original checksum unchanged.
- All source cells covered once with monotonic boundaries; every grid-only output color comes from its corresponding source cell.
- Logical dimensions correct; 96/64/16 outputs use only their recorded palettes.
- Both 4K previews exactly equal a 6× nearest repetition of the logical image, with no new colors.

Limited runtime evidence has also been independently recounted from the integration lead's actual GPU PNGs: frozen scene **0** changed pixels, a horizontal 0.24-texel step **0**, and a one-texel step **5 / 230,040** differences versus exact one-pixel translation. Two residuals differ by only one channel value; three are genuine edge changes. See `runtime_independent_recount.json` and `../../docs/qa/v4/stability-*.png`. This covers the tested horizontal view, not the full motion/shadow/resize suite below. The integration lead received these criteria:

1. Freeze camera, animation, lights, particles and shader time; consecutive logical scene captures must be identical.
2. Move an orthographic camera by quarter-texel increments along its local right/up axes. While the snapped cell is unchanged, a static reference mask must not crawl. At the boundary, it should shift by one whole logical pixel.
3. Check world picking and projected UI labels at 1280×720, 1440×900, 1920×1080, 2560×1440 and 3840×2160. Letterbox coordinates must never be treated as world coordinates.
4. Keep a static caster/light test and pan the camera slowly. Compare shadow-edge masks separately; shimmering, split-boundary jumps and self-shadow stripes fail even if the silhouette grid is correct.
5. Play character idle/walk/talk and move the craft. Face accents, contour width and color ramps should persist without per-frame palette reclassification. Animated changes are expected; unrelated static regions should remain stable.
6. Review transitions, shakes and zooms separately. Intentional movement is not a static-stability failure, but after settling the image must stop drifting.
7. If dithering is added, verify the pattern phase repeats identically at the same pose/camera/time. Test moving surfaces to decide whether the chosen screen-space or object-space anchor is appropriate.

## Reproduce

Use the already available Python, Pillow, NumPy and SciPy environment:

`OPENBLAS_NUM_THREADS=1 python source_art/pixel_pipeline_studies/study_reference.py`

`python source_art/pixel_pipeline_studies/validate_study.py`

All outputs remain under this study directory, which is already excluded from runtime imports by `source_art/.gdignore`.
