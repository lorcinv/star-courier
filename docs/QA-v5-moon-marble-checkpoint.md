# Moon framing and optional investigation checkpoint

2026-10-10, cloud-only Godot 4.6.3. The reviewed Moon camera and optional black-marble investigation are integrated on top of `e50f0d5`. Seeded routes, ordinary corridor-camera changes, meteors, additional record-integrity fixes, the raster phone casing and human-customer cutout motion are still isolated candidates at this checkpoint.

## Frozen aggregate

- 85 Godot suites passed, plus the normal smoke flight/UI flow, 384 NPC asset checks and 1,080 historical motion-asset checks.
- 675 authored runtime/asset/test/tool files are identical before and after the run. Import metadata and generated caches are not authored-source evidence.
- 87 Godot invocations; exit 0; no engine/FAIL diagnostics or nonzero failed counts. Elapsed wall time: 655.829 s.
- Full log SHA-256: `c0a6db3440b0b9cf413039995e4a992389261d82d9bf89d6fbef32ba65d993b7`.
- Local evidence: `docs/qa/v5/moon-marble-integrated/aggregate-01/`, including before/after hashes and `freeze-result.json`. Generated logs, movies and temporary saves are excluded from source Git.
- Reproduce with `python3 tools/run_regression_gate.py --output docs/qa/<new-empty-directory>`. The wrapper uses the existing isolated test runner and rejects source changes, incomplete smoke output and Godot diagnostics even when the process returns zero.

These are headless/controller/asset checks. They are not hardware FPS, physical-gamepad, human-fairness, or blanket art acceptance.

## Separate actual-renderer evidence

The [Moon report](QA-v5-moon.md) records the independently reviewed 1080p normal-time formal-delivery take, true body/circle registration and warning measurements. The lunar craft is larger; the ascent ship remains small and parts of distant rock bodies/low crags can remain cropped.

The [investigation report](QA-v5-marble.md) records 24 native keyboard/pointer/window checks at 1280×800, 1920×1080 and 3840×2160. The small raster object is on the existing drawer and shows the exact requested optional line. It adds no physical black-hole effect, progression reward or decoration editor.

The bundled Chinese font was regenerated from its retained OFL source: 1,458 glyphs and all 930 runtime non-ASCII characters covered. The original image-generated marble, technical registration and reproducible crop/palette builder are preserved alongside runtime art.
