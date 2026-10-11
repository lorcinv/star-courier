# Moon delivery integration gate

Date: 2026-10-10. Status: functional integration passed; the bounded readable-camera correction has passed independent native review and focused production integration. Final all-game presentation acceptance remains open. This is a content/presentation addition using the unchanged `pilot-v3` solver, not an astronomical simulation.

## Route and persistence

- Only newly authored offers can select `moon-surface-v1`: day 4 or later, reputation at least 10, route ID 4. Existing offers and in-flight route snapshots are not regenerated.
- The route is 900 arcade meters: existing ascent gates, two avoidable lunar outcrops, then a left-opening airlock. A drill is optional; the upper path remains traversable without one.
- Receiver radius, source registration, ingress band, hardware samples, and saved hazards are cross-validated. Changing both route and receiver radii cannot bypass the fixed source-art scale.
- The 14 airlock collision circles are source-inscribed cores, not a complete alpha silhouette. The capture circle is wider than the straight ingress band. Decorative regolith is not a hidden floor.
- Existing solver, force, energy, input timeline, and collision code are unchanged. Trial/formal consistency and unique settlement remain separate acceptance gates.

## Raster presentation

The original image-generated source PNGs are preserved under `source_art/2d_v5/moon/`. The reproducible preparation code, registration measurements, and palette data are in `pipeline/`. The active derivatives are under `assets/2d_v5/moon/`.

- A single clamped far plate contains one Earth; it never tiles.
- A subdued regolith layer uses ordinary horizontal wrapping with verified matching edges. No mirrored tiles.
- The airlock is uniformly registered to the saved capture anchor. Gameplay hardware remains solid; known registered hardware circles are not redundantly drawn as rocks.
- The revised camera prioritizes the actual cargo-connected craft and required inward gate faces. Lunar cruise uses a larger .24–.30 zoom; ascent temporarily fits the next required aperture with explicit edge cues for geometry outside the view. It no longer claims every complete obstacle circle is visible. Receipt framing keeps the actual opening, roof underside, deck and back wall.
- Background-only blur can be disabled and is zero while paused or in reduced-motion mode. Ship, collisions and UI remain crisp.

## Evidence so far

Integrated focused tests: `test_moon_route` 195/195, `test_moon_contracts` 1460/1460, and `test_moon_presentation` 86/86. The contract suite includes a headless four-day progression with eight unique receipts. This is not native-input evidence.

The frozen presentation staging package also contains 19 inspected real-renderer frames across the route, heavy cargo, pause/restore and 1280×800 / 1920×1080 / 3840×2160. Those scripted composition frames do not establish controller restart, native steering, performance or human fairness.

The native gate continued the exact already-earned Day 3 night checkpoint from the prior 84-check natural business run. Its source save SHA-256 is `3ca6146396dda2eb56f0f6bc97157c3bb750cb0062e35f6cdb606cd267740fe3`. The harness copied those bytes before startup, then used actual keyboard/pointer input for next morning, acceptance, loading, trial, formal confirmation, two in-flight process restarts and receipt. No money, reputation, inventory or contract fields are edited.

Native artifacts are in `docs/qa/v5/moon-native/earned-continuation-01/`. Automated W/S guidance demonstrates an achievable recorded input sequence, not a human playability verdict. No physical gamepad, Windows, subjective audio or hardware-frame-rate approval is implied.

## Completed integrated gates

- All **74 Godot suites**, smoke run, 384 static NPC checks and 1080 existing motion-asset checks passed. All 1192 frozen source/art hashes were unchanged; no headless warnings/errors. Log SHA-256: `f8863b1388508a5b0f30ed99d99928a50028b6d4a36c2f2f743ca88a7a9b21ef`.
- Native earned-save continuation: **26/26 checks**, four real game processes, 4073 read-only samples, no capped capture. Trial took 58.4417 s, 100% cargo and 637.3298 J remaining; its actual input replay matched exactly and changed no business ledger.
- Formal heavy delivery took 58.5167 s, 100% cargo, 793.2869 J remaining. Income 465 minus energy fee 131 yielded **334 profit**. Final balance 1477, reputation 14, seven unique receipts. Inventory, blueprint and all six previous receipts were unchanged.
- Paused process restarts at input ticks 1135 and 2973 restored exact position, energy, route and input timeline. No second ignition. A final paid-receipt restart produced no duplicate income.
- Native summary SHA-256: `21f657f53737816dfd3700610c8f8aebf2e35df8fd486ca9ced846945077cd51`. Source video is 20 s, 1920×1080, normal wall time with actual game audio: `earned-moon-trial.mp4`, SHA-256 `8d2979780279a58b9a40b5726bb1a5851e977e8b66c0e5d6552484af5279ce8f`. Its 24 fps capture setting is not an engine-FPS result. The cloud driver emitted its known unsupported V-Sync warning; no game error was found.

## Player-readable framing correction

The actual 1080p clip exposes an important tradeoff: fitting every complete nearby hardware circle makes the craft only about 25–35 pixels across. The assembled design is too small to read well next to the rocks and airlock. This functional checkpoint is **not final visual acceptance**.

That original framing was replaced after an independently reviewed normal-speed full-route take. Exact movie SHA-256: `2a0b23788d1e9162cdcbba3cf7601b940f95f603705006e24c9b792888553f63`; 62.042 s, 1920×1080, actual XTest and Godot Master audio. The driver copied the already-earned formal-ready archive, confirmed normally, flew all four gates and delivered intact at 58.3416667 simulation seconds. Seven checks preserve all six prior receipts and one new settlement. Automated input is still not human difficulty testing.

- Actual minimum connected-craft height: 45.08 pixels during ascent and 77.27 during lunar cruise. It is not an enlarged fake sprite; art and collision scale remain unchanged.
- The required physical inward quarter-arcs are continuously readable at least 3.19 wall seconds before the first horizontal craft/circle overlap in that recorded take. This is not a predicted impact time or a claim that the entire rock is visible.
- Independent dense-frame review confirmed gate 2’s upper inward face clears the HUD before approach, the 39–44 s return to lunar scale is progressive, and the final receiver mouth contains craft and capture field.
- Across 1280×800 / 1080p / 4K recorded-input replays, minimum ascent body heights are 30.04 / 45.06 / 90.12 pixels, and lunar heights 51.49 / 77.24 / 154.48 pixels. The supported warning/legibility compromise remains explicit.

The exact reviewed helper and narrow world/HUD changes are now integrated with the reviewed clerk and phone. Eight focused suites pass: Moon presentation 86, lifecycle 103, ascent lifecycle 1,275, geometry/input replay 2,860, receipt 80, HUD feedback 105, phone integration 70 and rigid mechanics 425,161 sampled assertions. Three camera suites and a small recorded-input fixture are now permanent. The fixture contains route/design/commands only; the historical pre-framing helper lives under tests, never runtime. The combined 85-suite aggregate, smoke flow, 384 NPC and 1,080 historical motion-asset checks passed with all 675 frozen source/art/test files unchanged. See [the checkpoint gate](QA-v5-moon-marble-checkpoint.md).

Remaining presentation limits: the ascent ship is still small, outer portions of gate rocks may pass behind the HUD, and low lunar crags are partly cropped with small down-distance cues. These are not hidden full-corridor acceptance. The camera reads current rotated body bounds and freezes during pause/focus loss; it does not change energy, route, replay or collider bytes.

Historical 74-suite/business evidence above belongs to `3ba8aab`. The separate review/rig checkpoint is `e50f0d5`; seeded variation remains staged until its own native gate.
