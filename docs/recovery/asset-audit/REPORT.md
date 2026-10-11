# Star Courier recovery asset audit

## Bottom line

The newer source subset is fully recovered and SHA-verified: **568/568 files** from commit `491aaffa4241fe1e09bdbb665e5316ba08cdff63`. The source-only package intentionally omitted artwork, editable originals, imports, and videos. It is not a complete game archive.

A preserved, independently hash-addressed art checkpoint inside that source provides stronger evidence than path matching:

- **473 asset files recorded at the October 10 combined-delivery checkpoint:** 388 exact recovered files, 82 missing files, and 3 available same-path files whose hashes are wrong.
- **3 additional protected-bird PNGs explicitly loaded by newer source:** all missing.
- Thus the known asset inventory contains **476 distinct paths: 388 exact earlier-checkpoint matches, 85 missing, 3 wrong-version copies**.
- These counts include historical/unused checkpoint assets. The conservative active-runtime inventory has **242 paths: 156 exact earlier-checkpoint matches, 83 missing, 3 wrong-version copies**. Two additional missing checkpoint files, the investigation registration and old portal ring, are preserved in the recovery request but are not read by the currently traced runtime.
- **16 missing resources are eager `preload` dependencies.** The unchanged newer main scene cannot load simply by avoiding the affected gameplay routes.
- **No complete newer visual gameplay slice can be called restored from these inputs.** No engine, GUI, source rebuild, artwork generation, production edit, or remote write was performed by this audit.

“Exact” here means byte-identical to the preserved `20261010-combined-delivery-06` asset hash receipt, not proof of an undocumented later 491aaff art revision or subsequent user-reviewed visual work. There is no complete art tree/manifest for 491aaff in the recovered source package. An honest recovery percentage can be given for the 568 source files or the 473 earlier-checkpoint assets; it cannot be given for the whole latest game.

## Inputs and source delta

Preserved inputs, read-only:

- `recovery/git-e6121c0`: 1,882 files; exact tree `0e29974828fbbd102731329d8473361af3bdae97`.
- `recovery/unpacked/StarCourier-491aaff-ground-traffic-code/source`: 568 files; its package manifest is fully reverified in this audit; tree recorded by package `2ca12fd7552cc7437685f887e8cd0d6cd1f1a838`.
- `recovery/unpacked/StarCourier-clerk-fullbody-FG01-source`: all 32 manifest-listed files verified. There are **15 runtime asset files, not 16: 14 PNGs and 1 rig registration JSON**. All 15 also match the preserved October 10 checkpoint asset hashes.
- `recovery/unpacked/StarCourier-Clerk-FG01-C2-small-review`: candidate inputs were not promoted or interpreted as a complete pass.

Source path comparison:

| Comparison of the 568 newer files against old tree | Count |
| --- | ---: |
| Added paths | 256 |
| Changed same-path files | 34 |
| Byte-identical same-path files | 278 |
| Old-only paths intentionally omitted from source package, not demonstrated deletions | 1,570 |

`source-path-delta.json` records every path and old/new SHA-256. No deletion is inferred from this subset.

The crucial preserved art receipt is `source/docs/checkpoints/seeded-meteor-human-20261010.json`, field `source_sha256`. It contains 748 total source/resource hashes, including 473 under `assets/`. Its own limits say the checkpoint was not published to the older remote tree and exclude the then-prototype protected bird/readable authoring work. Historical gate statements in that file are provenance, not fresh validation of this recovery.

## Proven wrong-version copies

These three old same-path files are **known mismatches**, stronger evidence than merely unverified versions:

1. `assets/2d_v5/actors/actor-manifest.json`
2. `assets/2d_v5/npcs/npc-manifest.json`
3. `assets/fonts/ChineseSans.otf`

Expected and recovered hashes are in `wrong-version-assets.json`.

The old actor/NPC metadata still selects old idle/handoff records and lacks the newer neutral/front-arm presentation contract. Using it because its path exists would silently revert requested visual behavior. The newer renderer’s fallback from missing conversation to old idle is not a valid recovery of the requested neutral pose.

Read-only font inspection found **99 missing glyphs** among the **945 distinct non-ASCII, non-whitespace characters** used by the newer package’s 77 script files. Details and exact codepoints are in `font-coverage.json`. The newer `tools/subset_font.py` exists, but no full original `NotoSansCJK-Regular.ttc` was found in the preserved inputs; the tool accepts that source as an external CLI argument. Do not claim the old subset meets the newer text contract.

`export_presets.cfg` is a fourth important wrong-version file outside the asset count. The newer source package omits it. The preserved checkpoint expects SHA-256 `f1ffae36fa56a315b300121c728fa9ebbcfd935421a6ebb4bdde5bc9e1c5abe1`; the old recovered file is `51673fbc55250f4bc2da99c1f545878eb43bb5b72f114a5680781f244e9431f4`.

## Exact missing asset groups

Every filename and any known expected SHA-256 is enumerated in `missing-assets.json`. These are actual recorded filenames, not guessed replacements.

| Missing group | Files | Relevant contents |
| --- | ---: | --- |
| `assets/2d_v5/actors/single_walk_v1/` | 36 | `single-walk-registration.json`; neutral, talk-idle, talk-handoff; 32 `clerk-walk-canonical-00-pixel.png` through `31` PNGs |
| `assets/2d_v5/actors/human_rig_motion_v1/` | 19 | `rig-registration.json`; 15 rigid-part PNGs; conversation/handoff/farewell body PNGs |
| `assets/2d_v5/actors/customer-neutral-idle-pixel.png` | 1 | Human neutral initial body |
| `assets/2d_v5/npcs/{elf_archivist,alien_botanist,robot_machinist}/` | 6 | `neutral-idle-pixel.png` and `neutral-front-arm-pixel.png` for each species |
| `assets/2d_v5/events/meteor/` | 4 | `manifest.json`, `meteor.png`, `fragment-a.png`, `fragment-b.png` |
| `assets/2d_v5/investigation/` | 2 | `black-marble-pixel.png`, `registration.json` |
| `assets/2d_v5/moon/` | 4 | `airlock-pixel.png`, `far-sky-clamped.png`, `regolith-decorative-wrap.png`, `moon_background.gdshader` |
| `assets/2d_v5/otherworld/` | 4 | `decorative-island-band.png`, `far-world-wrap.png`, `receiver-pixel.png`, `otherworld_background.gdshader` |
| `assets/2d_v5/wormhole/` | 4 | `portal-bottom-cap.png`, `portal-energy-plane.png`, `portal-ring-pixel.png`, `portal-top-cap.png` |
| `assets/2d_v5/reviews/` | 1 | `customer-review-phone-casing.png` |
| `assets/2d_v5/shop-sign/` | 1 | `hanging-sign-pixel.png` |
| `assets/2d_v5/protected_birds/` | 3 | `mosslight-protected-bird-hurt.png`, `mosslight-protected-bird-wings-down.png`, `mosslight-protected-bird-wings-up.png`; names proven by source, no expected hashes available in the earlier checkpoint |
| **Total** | **85** | |

A SHA-256 search over all recovered baseline/package PNG, JSON, OTF and shader files found **no alternate-path matches** for the 85 known missing/wrong-version historical checkpoint hashes. This is local-input evidence only, not proof that no other backup exists.

## Dynamic and raw JSON closure

Eight raw JSON files are read by the current reachable runtime. They must be supplied as raw files; imported texture presence alone is insufficient.

| Runtime JSON | Recovery state |
| --- | --- |
| `assets/2d_v5/actors/actor-manifest.json` | Old file present, known wrong hash |
| `assets/2d_v5/npcs/npc-manifest.json` | Old file present, known wrong hash |
| `assets/2d_v5/actors/cooperative/motion-manifest.json` | Exact earlier-checkpoint bytes recovered |
| `assets/2d_v5/npcs/walk_exit/motion-manifest.json` | Exact earlier-checkpoint bytes recovered |
| `assets/2d_v5/actors/single_walk_v1/single-walk-registration.json` | Missing |
| `assets/2d_v5/actors/rig_motion_v1/rig-registration.json` | Exact earlier-checkpoint bytes recovered from FG01 |
| `assets/2d_v5/actors/human_rig_motion_v1/rig-registration.json` | Missing |
| `assets/2d_v5/events/meteor/manifest.json` | Missing |

The old export includes only the first four. It omits the four newer raw JSONs above, even if those files were later recovered. A future export needs its own verified packing check; no export setting was changed here.

The asset audit expands:

- `main.tscn`/`project.godot` source dependency graph, 75 reachable source/config files
- Literal loads/preloads, including the three newer bird images
- World texture resolution (`-pixel`/`-native`, joint/coupler mappings), the full bounded part catalog, workshop tiers, hazard rocks, parcel, props, launch support
- Robot pose array, front-turn and telescoping-arm pieces
- Clerk/human/species portrait expressions
- Main audio callsites and music loops
- Existing authored JSON references down to exact field paths
- All checkpoint-known single-walk and human-rig target paths despite missing registration bodies

The clerk subclass replaces legacy cooperative walk/run arrays, so the old 64 gait frames are retained as recovery evidence but not falsely treated as the newer clerk’s loaded gait.

`dynamic-manifest-edges.json` labels which available metadata is obsolete. Missing registration bodies and the absent latest actor/NPC manifests prevent claiming unconditional full dynamic closure for 491aaff. No registration fields were invented.

A clerk rig that has all 14 cutouts still does **not** restore the clerk renderer: `clerk_rigid_motion_2d.gd` inherits `clerk_single_walk_2d.gd`, which reads the missing single-walk registration, neutral/dialogue records, 32 gait frames and gesture metadata. Replacing these with historical cooperative art would change the requested visuals.

## Original artwork and reproducibility

The 24-file immutable aggregate support receipt is preserved at `tools/aggregate_source_support.json`:

- **16 exact support files recovered**
- **8 missing support files**: 3 neutral NPC originals, their 3 prompt texts, the sign original, and its manifest

`aggregate-source-support-audit.json` gives exact hashes, bytes and consumer evidence.

The recovered authored registrations/docs identify **10 specific missing original PNG paths**. This list includes provisional FG01 artwork provenance; it does not label those candidates approved or required by every production path:

- `source_art/2d_v5/actors/cooperative/clerk-neutral-original.png`
- `source_art/2d_v5/actors/forward_gaze_staging/generated/clerk-level-forward-head-original.png`
- `source_art/2d_v5/actors/motion_quality_staging/generated/canonical-long-shorts-boots-original.png`
- `source_art/2d_v5/actors/motion_quality_staging/generated/head-expressions-original.png`
- `source_art/2d_v5/actors/motion_quality_staging/generated/leg-pieces-original.png`
- `source_art/2d_v5/actors/motion_quality_staging/generated/relaxed-arms-pelvis-original.png`
- `source_art/2d_v5/npcs/neutral_idle_staging/alien_botanist-neutral-original.png`
- `source_art/2d_v5/npcs/neutral_idle_staging/elf_archivist-neutral-original.png`
- `source_art/2d_v5/npcs/neutral_idle_staging/robot_machinist-neutral-original.png`
- `source_art/2d_v5/shop-sign/hanging-sign-original.png`

Their individual evidence references are in `source-originals-and-recipes.json`, alongside 17 known missing recipe/metadata/prompt/evidence paths. Missing evidence copies are not counted as additional missing original images. For other recovered old source paths without a newer expected hash, that manifest explicitly uses the category `available_old_same_path_version_unverified`.

Important absent recipe records:

- `source_art/2d_v5/actors/rig_motion_staging/build_matched_runtime_parts.py`
- `source_art/2d_v5/routes/combined_delivery_staging/source_curation/source-promotion-manifest.json`
- `source_art/2d_v5/routes/combined_delivery_staging/portable_rebuild/README.md`
- `source_art/2d_v5/routes/combined_delivery_staging/source_rebuild/verification.json`
- `source_art/2d_v5/routes/bird_checkpoint_sources_staging/README.md`

The preserved docs describe an earlier 62-input / 24-runtime-target portable recipe and a later 27-target bird/font recipe. The exact recipes and expanded original names are absent. Their historical success claims do not make these recipes executable now. Missing moon/otherworld/meteor/phone/bird original names cannot safely be inferred from runtime filenames; recover their genuine source manifests and original bytes together. No art was regenerated and no derivative was substituted for an editable original.

## Smallest useful newer behavior slice

The smallest fully closed newer behavior package is the **single-speed root-motion model**, without constructing a renderer:

- `scripts/shop_locomotion_2d.gd`
- `tests/test_shop_locomotion_2d.gd`

Both are exact newer source. The test imports only that model. The model owns the five states (`idle`, `start`, `move`, `inertial_stop`, `stop`), 155 px/s cap, acceleration/braking, counter/aisle route and root displacement. It has no artwork/manifest dependency. It can be separately engine-checked by the owner without restoring old idle/running visuals or mixing C2. **It was not engine-run by this audit.** Do not simply drop it into old renderer/controller callsites, which have different state expectations.

If a visible new gameplay slice is required, there is currently no defensible complete one using only recovered art: the latest renderer has missing eager art and mandatory neutral/rig metadata. Preserve the exact old game separately as an explicitly older checkpoint. Recover artwork before representing the assembled newer-source/older-art tree as runnable or visually restored. Ground simulation/profile code is already byte-identical between these two inputs, so an old ground-route run would not demonstrate recovery of a new ground-traffic feature.

## Recommended next recovery requests

1. Recover the current actor/NPC manifests, single-walk folder, human-rig folder and seven neutral-body/arm PNGs as exact authored assets. This is the principal character closure.
2. Recover the 16 eager missing PNG/shader resources and the current font, then remaining meteor/marble assets and raw manifests. Use expected hashes from this report where available.
3. Recover the newer export preset, genuine portable source-promotion/rebuild manifests, original images and full font source. Retain staged FG01/C2 inputs as staged.
4. After exact recovery, the owner can import/parse, verify raw JSON export inclusion, run focused and aggregate gates, then assess actual visuals. Source hashes and historical receipts do not replace these steps.

## Deliverables

- `summary.json`: concise counts
- `source-path-delta.json`: exact 256 added / 34 modified / 278 identical path records
- `asset-inventory.json`: all 476 known asset paths with evidence, hashes and local provenance
- `known-runtime-assets.json`: conservative 242-path runtime set and consumers
- `missing-assets.json`: exact 85 missing paths
- `wrong-version-assets.json`: three asset hash mismatches
- `runtime-raw-json.json`: eight raw JSON dependencies
- `dynamic-manifest-edges.json`: authored metadata field-to-resource edges
- `runtime-source-graph.json`: traced source reachability
- `eager-preload-blockers.json`: 16 missing eager resources plus the wrong font, with consumers
- `aggregate-source-support-audit.json`: 24 required source-support files
- `source-originals-and-recipes.json`: known exact original/recipe paths, status, and evidence
- `font-coverage.json`: glyph evidence
- `alternate-path-hash-search.json`: no matching bytes found at another recovered path
- `input-verification.json`: both package manifest verifications
- `audit_recovery.py`: reproducible, read-only audit code; writes only in this audit directory
