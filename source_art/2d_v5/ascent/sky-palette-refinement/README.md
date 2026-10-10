# Source-only atmosphere palette refinement

Status: approved source256 candidate published atomically to runtime after the parent explicitly released the native replay freeze. All other runtime art and all original artwork remain unchanged; see `release-verification.json`. The earlier `validation.log` records the pre-release freeze checks.

## Recommendation

The approved `source256/atmosphere-tall.png` is now installed as `assets/2d_v5/ascent/atmosphere-tall.png`. The image is 1280 × 2560 RGBA, with a strict 2 × 2 pixel grid, fully opaque alpha, and exactly identical left/right boundary pixels. Every one of its 256 palette colors occurs in the sampled imagegen original. No new dithering, gradient painting, illustration, scenery, or mirroring was introduced.

The existing source art already has a smooth vertical blue transition and deliberately textured dither bands. Mapping that sky through the 96-color shop-reference palette retained only 13 colors and introduced broad, unrelated periwinkle/cyan plateaus. The dedicated palette is fitted once to this static asset, with median-cut coverage seeds snapped to actual source colors in Oklab. Runtime frames do not refit the palette.

## Measured evidence

All versions are compared at identical 1280 × 2560 final dimensions. Row deltas use adjacent logical rows rather than counting duplicated 2 px output rows. Metrics exclude only the existing narrow 8-logical-texel horizontal edge repairs.

| Measure | Source / nearest grid | Old shared palette | Dedicated 128 | Dedicated 256 |
| --- | ---: | ---: | ---: | ---: |
| Visible RGB colors | 16,903 | 13 | 128 | 256 |
| Worst adjacent row-mean channel delta | 5.21 | 31.04 | 5.81 | 5.67 |
| Median adjacent row-mean channel delta | 0.526 | 0 | 0.454 | 0.474 |
| 95th-percentile row-mean channel delta | 1.98 | 5.68 | 2.17 | 2.09 |
| Longest region with ≥95% single-color rows, output px | 0 | 464 | 2 | 0 |
| Mean absolute RGB error against source | 0 | 21.05 | 0.851 | 0.660 |
| Mean Oklab distance ×100 against source | 0 | 5.67 | 0.250 | 0.177 |

The 256-color candidate's largest row transition occurs at y = 2272, the same location as the original's largest source transition. Its maximum per-pixel row delta is 42 versus the source's 41; the old mapping reached 111. Source-dither contrast remains, while the artificial broad plateaus disappear.

## Evidence files

- `comparison-overview.png`: source, old derivative, 128 colors, 256 colors, all at the same display scale.
- `comparison-detail-1x.png`: identical exact 1:1 runtime-pixel crops across all four images.
- `source256/atmosphere-tall.png`: inspected selected candidate.
- `source256/exact-horizontal-wrap.png`: true end/start edge strips; no reversed sampling.
- `comparison-metrics.json`: full measurements and protected-file hash checks.
- `protected-before.json`: source, live asset, and live manifest hashes before this work.
- `legacy96-reproduction/atmosphere-tall.png`: preserved old baseline, reproduced byte-for-byte by the revised tool with `--sky-colors 0`.

## Reproduce candidates without changing runtime

From the repository root:

```sh
python tools/prepare_ascent_layers.py --sky-only --sky-colors 0 --output-dir source_art/2d_v5/ascent/sky-palette-refinement/legacy96-reproduction
python tools/prepare_ascent_layers.py --sky-only --sky-colors 128 --output-dir source_art/2d_v5/ascent/sky-palette-refinement/source128
python tools/prepare_ascent_layers.py --sky-only --sky-colors 256 --output-dir source_art/2d_v5/ascent/sky-palette-refinement/source256
python source_art/2d_v5/ascent/sky-palette-refinement/compare_sky.py --assert-live-unchanged
```

After publishing, omit `--assert-live-unchanged` if re-running the comparator: the frozen old baseline is retained, but a changed runtime is then expected. This does not modify any live asset.

The approved single-sky publish command used for this release was:

```sh
python tools/prepare_ascent_layers.py --sky-only --sky-colors 256
```

That command updates only the sky texture, its dedicated palette metadata, and the sky record/method in the existing technical manifest. Other layer pixels and their seam proofs are untouched. The normal full-layer preparation also defaults to the dedicated 256-color sky; `--sky-colors 0` retains legacy reproduction.

## Technical provenance

The bounded Oklab mapping and source-pixel representatives reuse the reviewed project-local `source_art/pixel_pipeline_studies/study_reference.py`. The prior GitHub study documents [spritefusion-pixel-snapper](https://github.com/Hugo-Dz/spritefusion-pixel-snapper) and [pixel-game-kit](https://github.com/kenyonxu/pixel-game-kit), with pinned reviewed tree hashes and MIT licenses in `source_art/pixel_pipeline_studies/github_sources.json`. No downloaded program was executed for this refinement. All visible scene art remains derived from the existing imagegen original, SHA-256 `167e9798c4d769e2c3f0fb40ef048737a4ba266e539120073e59eab80adeee5d`.

Headless import and focused backdrop validation logs are retained here. Native in-game validation remains the parent's responsibility after release; this comparison does not pretend to be a fresh gameplay capture.
