# v5 ground-delivery checkpoint · 2026-10-10

This is a tested development checkpoint, not final game/art approval. It precedes the newly requested single-speed movement, neutral idle, canonical head-size and hanging-sign revisions. Its historical hold-to-run behavior is superseded and will be removed in the next work stage. Current development is cloud-only; the older Windows 1335935 candidate does not contain these ground changes.

## Integrated behavior

- A new ordinary shop starts with two saved `ground-city-v1` orders, 360 m distance and an 8 m rooftop rise. Three real collider gates, generated city parallax and a rooftop receiver distinguish this from orbit.
- The `pilot-v3` solver and v1/v2/v3 replay source files are unchanged. The content marker selects the new scene only; existing saved contracts retain their complete old route and input interpretation.
- Ground result/return stories retain the actual committed destination after the old contract is removed on the next day. Dialogue and free trials award no money.
- Two intact, timely deliveries give the existing reputation needed for day-two ascent orders, with 520 m distance and -150 m destination Y.

## Automated regression

`tools/test.sh`: all 59 Godot suites, smoke and both static asset checks passed. No `ERROR`, `WARNING` or failed assertions in the successful aggregate. New focused suites: ground route 67, ground contracts 382, ground presentation 71. Static checks: NPC 240, actor motion 1080.

The previous ascent-specific controller fixture now explicitly creates an ascent contract instead of assuming every new shop has one. Its geometry, old replay and cost assertions remain; it passes 128 checks. Aggregate attempt 01 caught this fixture dependency; attempt 02 is the passing full run.

Smoke: 22.6 s, 100% cargo, 2379.065 J on the new default route. The font contains all 846 runtime non-ASCII characters. Frozen runtime hashes stayed unchanged throughout the aggregate and native runs.

## Actual native input

A fresh ordinary 260-credit game was driven by XTest keyboard/mouse. A read-only observer recorded the game state; no injected gameplay calls, save editing, QA endowment, fixed engine frame rate or video speedup was used. The offline guide supplies a tested command schedule, not a human playability finding. The actual recorded command timeline is replayed afterward and checked against real terminal state.

- Separate full-route trial: 11/11 checks. 22.358333 s, 100%, 2372.681023 J; exact position/time/energy replay, both W and S, one launch impulse and complete unchanged business ledger.
- Full business day: 48/48 checks. Free trial, repeated/cancelled dispatch confirmation, two formal deliveries, pause/focus loss, close/restart and exact saved-tick recovery without replaying ignition.
- Formal A: 165 income - 59 energy = 106 net. Formal B: 220 income - 67 energy = 153 net. Both cargoes intact and on time; each unique settlement appears once. Each native input timeline reproduces its own energy bill, including A's pause/recovery commands.
- Earned balance paid 180 for workshop tier 1 and 45 for a battery. A real pointer placed a spare beam in newly unlocked cell (5,0), then Undo restored the exact design, launcher, inventory and free stock.
- Day two genuinely contains the original ascent orders. Purchases, expanded tier, unique receipts and old ground story context survive final native restart. There was no still-pending return dialogue at that final point; actual earlier return copy and persisted context are recorded separately.
- Earlier native attempts stopped at QA-only button locator ambiguities: letterbox hub coordinates, duplicate report Back, duplicate drawer Back. Their artifacts are retained. Explicit visible button targeting fixed the harness; no production failure was hidden or gameplay assertion relaxed.

## Actual visual review and limits

The exact 26.542-second trial clip was independently inspected as a shareable low-altitude city-delivery WIP. Skyline remains, no orbit replacement or mirrored reversal appears, and launch/flight/receipt are continuous. Recognizable upper obstacles are visible about 2.7–3.0 s before each crossing.

Known clarity gaps: this is flight above rooftops, not a street vehicle; the second gate's lower rock is partly below the playfield / HUD, so full-corridor preview is not yet proven. The pale receiver field needs a darker contrasting bracket to make hover capture obvious. The modular ship silhouette remains unfinished. These do not change collision or receipt geometry.

Video is normal wall time at 24 capture fps on cloud llvmpipe; no engine-fps, subjective audio quality or physical gamepad claim. Actual 44.1 kHz stereo Master PCM is captured; the trial has zero clipped samples. Mixer/video timing is logged, not independently measured hardware loopback latency.

## Reproduction and evidence hashes

- Aggregate: `docs/qa/v5/ground-regression/aggregate-02.log`, SHA256 `a0a7c04ff56f26b761e44e1060e51d9c2fd382b994d8a54efa95abf45c9f4547`
- Trial summary: `docs/qa/v5/ground-native/trial-20261010-02/ground-validation-summary.json`, SHA256 `c0d28333ecdc78262c24c177572013cd5bcab22bdb0dec6d9c22883536192b29`
- Reviewed trial MP4: same folder, `01-ground-trial-full-route.mp4`, SHA256 `9dd78604b13dab6704bf6032592f88c2022e7ad73da27cc5eb9847298873037a`
- Business-day summary: `docs/qa/v5/ground-native/day-20261010-03/ground-validation-summary.json`, SHA256 `8cbe2b7ab1f1c3e5be89b3aba0044f3c8bab12b1e233cd00df2d25999409563e`

Generated evidence, test saves and caches are excluded from source Git and retained in dated QA backup. Reproduction sources are `tests/qa_v5_native_ground_day.py`, `tools/qa_ground_observer.gd`, and `tools/pilot_ground_reference.gd`. Use a fresh isolated save and exclusive display; the observer must never mutate game state. The helper explicitly rejects older protocols rather than silently replaying v3 as v1.
