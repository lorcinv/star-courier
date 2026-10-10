# Star Courier · active V2 actor assets

The active runtime uses the V2 proportion revision generated as a shared pair, approved after the paired preview, then published in one atomic directory exchange. The clerk's head/hair mass is closer to the courier's, with clearer torso/arm proportions. All actor artwork was generated using built-in image generation. No face-only code scaling, vector redraw or old 3D rendering was used.

## Active runtime contract

| Actor | Idle / hand-off files | Shared canvas | Foot anchor | Body height |
|---|---|---|---|---|
| Clerk | `assets/2d_v5/actors/clerk-{idle,handoff}-pixel.png` | 159 × 256 | (85.59, 247.59) | 240 |
| Customer | `assets/2d_v5/actors/customer-{idle,handoff}-pixel.png` | 167 × 256 | (73.19, 247.78) | 240 |

Canvas size and semantic foot registration remain identical to V1. Actual sampled sole position is within half a logical pixel of the semantic anchor. Snap-to-pixel alternatives remain clerk (86,248) and customer (73,248). Both poses of each actor share a single source union, scale and placement; no per-pose automatic trimming.

Use the V2 hand/parcel guides in `assets/2d_v5/actors/actor-manifest.json`. Whole-character scaling is `desired body height / 240`; a 256-high texture includes transparent padding. Filter with nearest-neighbor sampling and no mipmaps. The scene integrator owns placement and foreground-counter occlusion.

## Sources and review

- `v2/pair-idle-original.png`: original shared-pair revised idle generation, 1536 × 1024 RGBA.
- `v2/pair-handoff-original.png`: original shared-pair matching hand-off generation, 1536 × 1024 RGBA.
- `v2/pair-idle.prompt.txt` / `v2/pair-handoff.prompt.txt`: exact prompts.
- `v2/*-extracted.png`: source-region extractions, before runtime cleanup.
- `v2/pair-proportion-preview.png`: V1/V2 paired proportion review.
- `v2/actors-pixel-contact-sheet.png`: final four-pose review.
- `v2/actor-manifest.json`: full generation provenance, source SHA256, alpha bounds, source registration, runtime metrics and pivots.
- `v2/validation.json`: recorded verification and atomic publication result.
- `v1/`: preserved first-version originals, prompts, manifests, review, pipeline code and runtime snapshot.
- `v2/previous-runtime-boundary/`: exact runtime folder preserved at the atomic V2 switch.

The top-level original images/prompts are also preserved V1 sources. Active source work lives under `v2/`.

## Pipeline and publication

V2 was generated using the actual scene plus both prior characters as a shared pair reference. The hand-off edit used the approved revised pair as its identity reference. Built-in `image_gen.imagegen` was called with `transparent_background=true`; no unreported model version is claimed. Every original output remains unchanged in the project and tool output location.

Runtime cleanup is limited to alpha threshold128, per-actor region extraction, uniform whole-body nearest sampling, and the same approved 96-color palette. Faint generated alpha halos are removed only in the runtime derivatives; no original pixels are overwritten.

`python source_art/2d_v5/actors/build_actor_derivatives.py` rebuilds **staged V2 copies only**, without modifying the live actor directory. `python source_art/2d_v5/actors/validate_actor_assets.py` validates the published V2 assets. A future live publication must be coordinated with the scene integrator; `v2/publish_v2.py` records the one completed atomic boundary and deliberately refuses to overwrite its previous-runtime snapshot.

These are two whole-sprite poses per actor. No real Spine binding, Spine project, skeletal limb authoring, Spine atlas, JSON/binary export, or license/editor work was performed. This proportion task did not add NPC races, appearance components, game logic or HUD changes.
