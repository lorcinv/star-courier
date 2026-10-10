# Customer walk and farewell raster art

Four established customer identities now have six image-generated, full-body action frames each:

- `human_courier`: the brown-haired human traveler in the navy/yellow cap and backpack, not the clerk.
- `elf_archivist`: pointed ears, ash-blond hair, long navy/mustard coat.
- `alien_botanist`: broad turquoise head, yellow eyes and two antennae.
- `robot_machinist`: cream/yellow customer robot with cyan face screen, not the cargo robot.

Each identity has four distinct articulated walk poses, an empty-hand farewell, and a settled neutral. Runtime walk and neutral face left; farewell faces right toward the shop. The original generation occasionally changed orientation, so whole-frame horizontal reflection normalizes the human and alien frames; those transforms are explicit in the manifest. Robot V1 had inconsistent boot direction and was replaced by V2. Both untouched originals remain here.

## Runtime contract

`assets/2d_v5/npcs/walk_exit/motion-manifest.json` is the integration contract. Its `actors` object contains `walk`, `gestures.farewell`, `gestures.neutral`, and `walk_cycle_distance` (120 logical pixels).

Every frame is on a 192 × 256 canvas, uses logical `body_height: 240`, and is registered at `foot_anchor: [96,248]`. The foot anchor is the pelvis ground projection on the exclusive sole baseline, not the changing center of the stride. `hip_anchor` is the visible belt/upper-hip attachment peg for the identity's existing compatible accessory. The source crop, cell, foot, head and hip landmarks, source-facing direction, reflection flag, scale, sampled dimensions and paste offset are all recorded per frame.

The neutral body establishes one uniform scale for all six frames of that identity. Gait compression/extension stays visible; frames are not independently stretched to equal height. Runtime alpha is binary. All visible colors belong to the existing approved 96-color palette. No parcel is baked into the poses, and no shop branding was added.

## Provenance and rebuild

All painted sprite content was created with the built-in `image_gen.imagegen` tool. Five original 1536 × 1024 RGBA PNG outputs are retained byte-for-byte, including the archived first robot attempt. The exact prompts, original generated filenames and SHA256 checksums are retained. All outputs have actual transparent alpha; no painted checkerboard background is relied on.

Run:

- `python source_art/2d_v5/npcs/walk_exit/prepare_derivatives.py`
- `python source_art/2d_v5/npcs/walk_exit/test_derivatives.py`

The preparation script only extracts rectangular source components, optionally reflects complete sprites, uniformly resamples with NEAREST, maps the fixed reference96 palette, thresholds alpha at 128, registers the sprite on a common canvas and makes QA composites. It never draws or repaints sprite artwork. Source hashes are verified before rebuilding.

`contact-sheet-native.png` presents the existing idle beside all six new poses at native scale. `asset-qa.json` records checks and the completed visual review. The first successful automated run passed 399 checks across all 24 runtime frames. The exact current count is in that JSON.

These are raster frame animations. No Spine skeleton, rig, atlas, project, runtime or export is included or claimed. Engine integration and cutscene validation belong to the consuming scene.
