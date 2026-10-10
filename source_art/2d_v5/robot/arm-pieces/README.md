# Registered turn and mechanical loading arm

This pass keeps the generated empty-body and raised-arm originals intact. The new generated `../empty-hands/front-neutral-original.png` supplies one real frontal turn inbetween; it is uniformly scaled by body height and registered to the middle wheel/floor on the existing 160×144 canvas at (80,136). The front silhouette is not squeezed from a side pose. Runtime never crossfades two bodies or mirrors the parcel separately.

`prepare_turn_front.py` performs nearest resampling, shared96 palette mapping and binary alpha. `prepare_arm_pieces.py` reuses only pixels from the existing generated `assets/2d_v5/robot/lift-arm.png`: nearest affine registration aligns its shoulder-to-grip axis, then crops an empty claw, shoulder housing and shaft. Runtime preserves the claw and housing at a fixed 0.65 scale; only the mechanical tube extends, overlapping under those opaque housings. Neither the robot face/body nor the whole gripper is stretched. Both scripts record source SHA-256 values, exact transforms, crop/anchor coordinates and derivative hashes in adjacent manifests.

Reproduce from the project root:

    python3 source_art/2d_v5/robot/arm-pieces/prepare_arm_pieces.py
    python3 source_art/2d_v5/robot/arm-pieces/prepare_turn_front.py

The assembly component keeps its body behind the counter at effective z4; the connected arm uses absolute z9, between counter z8 and single external parcel z13. Pickup spends the first 43% of 0.28 seconds approaching the stationary clerk parcel, then moves that same parcel only after contact. The 0.18-second body turn uses side/front/opposite-side poses and a continuous mechanical shoulder/hand path. Travel integrates a 0.14-second smooth acceleration/braking profile, with at most 2.4 seconds per expanded floor leg. An empty-handed 0.16-second return turn occurs after loading completion, so input and launch do not wait for it.

This is generated raster-sprite presentation, not a Spine rig, authoring project or export. No inventory, cargo identity, model data, economy or deterministic flight physics is changed.

## Verification

Focused headless checks after integration: assembly 48/48, cargo transport104/104, loading controller38/38, counter/species176/176. They cover reach-before-move, fixed grip size and exact endpoints, both far-right cargo bounds, pause/hide/replacement/cancellation, reduced motion, fast-forward, repeated callbacks and unchanged model/accounting state. A first launch with unwritable default HOME aborted before tests; rerunning with isolated writable HOME/XDG directories passed.

These tests and the registered image proof establish geometry/state behavior. They are not a substitute for the pending final real-time visual/native playback of the integrated workshop and launch changes.
