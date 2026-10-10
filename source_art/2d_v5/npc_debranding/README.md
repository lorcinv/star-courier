# Customer NPC debranding

The ringed-planet PLAYER SHOP identity was copied onto customers. This revision removes it only from customer clothing, personal accessories and their handoff parcels.

## Audited coverage

- Human courier: both world poses, backpack and all three dialogue expressions audited; no copied emblem found. All files unchanged.
- Elf archivist: removed two world shoulder emblems and the handoff parcel emblem; removed shoulder emblem in neutral, pleased and concerned portraits. Both modular accessory cutouts unchanged.
- Alien botanist: removed seed-pod jar label emblem and handoff parcel emblem. Idle body, field vial and all three portraits unchanged.
- Robot machinist customer: removed shoulder and apron emblems in both poses and all three portraits; removed handoff parcel emblem. Tool pack and power cell unchanged.
- Clerk, shop-owned robot, environment and ship-module branding were outside the edit scope and are retained.

## Artwork provenance and preservation

Six built-in imagegen EDIT calls: five surgical debranding sheets and one same-object parcel extraction/occlusion-cleanup edit. Exact generated outputs are preserved under `original_edits/`. Prompts and SHA records are in `provenance.json` and `parcel-provenance.json`. Source originals remain byte-for-byte.

Imagegen incidentally smoothed some unrelated outlines. To prevent identity drift, only the explicitly measured emblem rectangles were crop-registered from each output into the original sheet. No creative pixels were painted with code. Original alpha and every pixel outside those rectangles remain exact. Crop/resampling and shared96 palette cleanup then used the original registration transforms, foot/waist anchors, accessory mounts and canvas sizes.

The standalone neutral parcel is 66×45 pixels, shared96, binary alpha. Imagegen removed the hands and reconstructed the occluded lower corners of the same box; it is not claimed to be a literal untouched extraction. Intended only for external customer-parcel transport, not the branded installed ship cargo casing.

## Runtime publication

The complete NPC directory was atomically exchanged after lead visual approval, preserving existing Godot `.import` metadata. The old exchanged directory remains on disk as temporary `before-runtime-directory/`; it is not needed for rebuild and should be excluded from Git and delivery archives. `staged-runtime/` is also a reproducible temporary output. Only changed pre-edit NPC PNGs needed for exact comparisons are retained under `before-runtime/`. `provenance.json` lists all 24 changed/new PNG paths plus manifest. Human/clerk actor and dialogue directories were not modified.

`tools/test_species_npcs.py`: 240 checks passed. `validate_debranding.py`: source/alpha/face invariants and parcel checks. These are static asset checks, not engine-integration evidence. The lead owns Godot reimport and actual runtime verification.

## Review boards

- `proofs/all-four-identities-after.png`: all four identities and all expressions.
- `proofs/before-after-emblem-crops.png`: all 19 corrected emblem areas.
- `proofs/all-accessory-variants-native.png`: all six accessory variants and both poses at native resolution.
- `proofs/*-portraits-native512.png`: each identity at true native 512px portrait resolution.
- `proofs/shop-background-compositing.png`: native sprites on preserved shop shell; clearly labelled technical composition, not engine screenshot.
- `proofs/customer-parcel-neutral-proof.png`: neutral transfer parcel at native size and nearest 4×.

## Rebuilding

The older `tools/prepare_species_npcs.py` is historical base generation and would restore original branding if run alone. Apply `stage_debranding.py`, followed by `prepare_parcel.py`, to create the corrected candidate under `staged-runtime/`. Review the candidate, then publish via a coordinated atomic directory exchange. This revision does not modify shared build scripts. Rebuild needs only the retained original sheets, generated edit outputs, prompts, scripts and the current runtime manifest/assets; neither temporary directory is an input. Run `build_review_boards.py` after staging to reproduce native-scale/background proofs. `before-runtime/` is used only by validation against the preserved pre-edit NPC PNGs.
