# FG01: isolated clerk full-body pose sampler contract

## User outcomes and exact scope

- Sentinel_cac27dc6f4088191bc5df0bfcc4242ff: eye-level head, forward gaze while moving, stable identical head size across poses.
- Sentinel_921fcf4e50048191837b25a0d27b82d1: correct pelvis/leg attachment, proportions and weight balance; remove anterior-pelvis-tilt impression.
- Sentinel_84c66d267540819184e0b378ff10e750: coherent moving upper body. Stable head size does not mean a locked torso/head.

Local ownership is pure deterministic pose math and its tests, based on a staged copy of scripts/clerk_rigid_pose_2d.gd. Cloud owns imagegen, all raster registration, renderer integration, actor/gameplay code, visual approval and publication. No new skeleton, source painting, scale warping, root travel changes or hidden second motion owner.

## Frozen inputs

Use candidate-rig-registration-fg01.json unchanged. Its hash is in registration-delta-fg01.json. This is a provisional measurement candidate, not final art acceptance. Freeze it for the entire experiment; report if it cannot meet the test bounds rather than quietly changing geometry.

Confirmed from the installed source:
- Reference height240; actual clerk height210 gives scale0.875.
- Near thigh length44.3816726138; far44.5183467797.
- Near shin length20.0525091946; far20.0300555416. These reach the UPPER BOOT MOUNT, not an anatomical ankle. Preserve legacy ankle field names for API compatibility but do not misinterpret them.
- Near mount-to-sole[5.28,29.92], far[7.04,28.952]. Boots remain the existing rigid full-height pieces, with source scales0.088. Shin source scale0.075 remains fixed.
- Part pixel scales, root/tip registrations, torso/pelvis/head attachment geometry and all raster hashes stay fixed. No stretch-to-fit.
- Head is104×91 source px, old root[55,91], attachment offset[−8,−54.5373665480]. Cloud will separately install the corrected head and measured new head root; local should return a neck target and world head orientation, never choose or rescale textures.

FG01 cloud-proposed changes, frozen but PROVISIONAL:
- Near means cream-pocket/front limb, screen-left in the accepted neutral and read/tap source. Far means the other limb. Mirror their coordinates on facing change; do not swap the identities.
- Near hip socket[−15.71530249,0]; far[10.76156584,0]. These use raw neutral source socket centers[455,900]/[610,900], waist center[547,900] and the existing uniform scale240/1405. Estimated uncertainty±[2.05,1.71] native px. They are visual socket-center measurements, not artist-provided anatomical joints.
- Near neutral sole[−33.48042705,0]; far[12.46975089,0]. These relabel the existing accepted-neutral source shoe centers[351,1453]/[620,1453] by the visible pocket identity. The old metadata's near/far shoe names are reversed relative to that art. Approximate shoe center uncertainty3 native px.
- Tablet-check/ready paints the cream pocket on screen-right; neutral/read/tap paint it on screen-left. This is a separate accepted legacy view constraint. Never flip the walking costume mid-cycle to match it; cloud owns the later gesture solution.

Source/actual comparison: waist-socket-evidence.png. All compared character pixels are existing art or actual recording pixels; cyan/magenta circles only annotate proposed socket centers. registration-delta-fg01.json records exactly what is unchanged versus proposed.

## Ownership and compatibility

Preserve scripts/shop_locomotion_2d.gd as the root-motion owner: MOVE_SPEED155, ACCELERATION700, BRAKING750, REVERSAL_BRAKING1000,120Hz integration and states idle/start/move/inertial_stop/stop. Do not change them. world_view_2d.gd::_apply_shop_motion already supplies the root, cumulative distance, facing, state, owner clock and stop age to the adapter. Cooperative loading feeds actual deltas through _set_clerk_walk_x at its existing transport rate; retain that existing caller compatibility and one displacement-driven gait. No running state or time-driven marching.

Keep configure/reset/freeze/update/snapshot signatures. Retain existing feet,joints,hip,arm_angle,shoulder_offset,head_angle,eye_state and other outputs. Add a documented upper_body dictionary if necessary, with pelvis_world_angle, torso_world_angle, torso_pivot_world, neck_world, shoulder_world per side, arm_world_angle per side, and head_world_angle. Angles must explicitly be WORLD orientations, not ambiguous parent-relative angles. Renderer changes happen in cloud after pose output review.

## Verified failure mechanism

The current source renders pelvis/torso at0 radians and drives moving shoulder_offset to[0,0]; its upper body is locked except arms. head_angle is always0. The upward look is baked into tablet-check source art; eye patches are correctly bounded but are scheduled intermittently independent of travel direction.

Current hip target is x=0 during movement, y=−94.46 before reach clipping. With full boots, the64.4px thigh+shin chain has essentially no lateral allowance at that height. Actual rightward sample9.031s has hip y=−82.43, approximately12px lower, and opposing thigh/shin bends. Actual join samples7.035→7.179s move hip x+0.64→−12.92 over0.144s while the root is stationary. The relaxed solver intersects two exact equal-flex circles and changes that answer as the recovery foot moves. It can pull the torso sharply backward. This is not evidence that whole-body rotation is required.

## Implementation targets

1. Register both leg chains to the frozen pelvis sockets. Derive their world hip points through the pelvis frame if pelvis angle is introduced; do not rotate the decorative pelvis while leaving the skeleton sockets elsewhere.
2. Solve support/reach without a large phase-dependent pelvis collapse. Prefer a bounded nearest-feasible hip target inside BOTH reach disks; do not force both knees to exactly12° by selecting an unstable circle intersection. Distinguish fixed stance support from a recovering foot. Preserve chain lengths exactly.
3. Foot landing must account for each leg's socket and boot-sole bias. The old shared sole landing_ahead16 with new separated sockets would create asymmetric overreach. Derive each landing from predicted root + side's fixed rest/socket/sole geometry; latch the world target once planted. This is foot/pose math only; never move the actor root.
4. Tune the stride parameters as named candidate outputs, not source geometry. Suggested first sweep: half_step32/34/36 native px, swing_lift5/6/7, comfortable knee-flex band rather than one exact angle. These are starting experiments, not approved values. Report the resulting cadence at the unchanged root speed so shorter stride does not turn into a frantic shuffle.
5. Add small phase-coherent pelvis/torso counter-motion and relaxed arm swing. Initial bounds: pelvis±0.6–1°, torso±1–1.5°, shoulders no more than1 native px independent residual translation, arms roughly±6–9°. Phase comes from actual displacement and support identity. Start/stop transfer can bias torso up to2° before smoothly returning. No default wave, dance-like sway, full-sprite rocking, or standing march.
6. Derive neck and shoulders from the same torso transform. Head follows neck POSITION but counter-rotates most torso pitch, keeping a natural level forward orientation with a small bounded residual rather than being welded immobile. Keep head scale fixed. Blink is independent; while moving and braking choose the forward-gaze semantic, with only half/closed blink overrides. Idle may make an intentional gaze change; remove the unrelated periodic moving side-eye.
7. Capture all upper-body values and feet at interruption/stop. Recover continuously, not by reset. Avoid solving the final hip from the moving recovery foot in a way that causes the measured14px backward pull. No first-frame jumps; freeze/resume remains visually exact; blocked movement does not advance gait.

## Required raw evidence and stopping condition

Return staged pose implementation, CPU/headless test source, machine-readable per-sample snapshots and a compact metrics report. If no engine lane is authorized, do not launch one; pure math diagnostics can run only through permitted tools. Do not return “looks good” without pixel proof; local deliverable is mechanics, cloud does final actual-art proof.

Test both directions and heights120/210/240: idle, accelerating start, steady movement, braking, stop entered at at least16 phases, immediate reversal, obstacle-blocked movement, interrupted recovery, diagonal route connector, hidden freeze/resume, cumulative distance reset and legacy apply_run→walk compatibility. Feed the existing shop locomotion owner or an exact captured root trace rather than a new invented acceleration model.

Record fixed bone-length error, same-landing-id planted-foot drift, at least-one-support condition, socket attachment error, reach feasibility, hip x/y envelope, knee/upper-boot-mount angles, upper-body angle/translation envelope, per-frame discontinuities, foot and hip travel during stationary stop, immutable head scale, and support projection. A simple artist-weighted silhouette center can be diagnostic but must not be described as a measured physical center of mass.

Mechanical invariants: bone length/support drift/socket consistency≤0.001 in parent units; no stretch, no double-air state, finite transforms, same source scale across states, no root movement in sampler. Design-review targets for initial comparison: steady-gait hip vertical peak-to-peak≤4 native px; stationary-stop backward hip excursion≤4 native px; no single60Hz hip/neck/shoulder frame jump above2 native px except an explicit teleport. If current fixed art/geometry cannot reach these targets, return exact failing trace and the missing overlap/source need. Do not loosen the bound silently or promise visual approval.

Stop after one isolated candidate passes the mechanical suite or after reporting a specific fixed-geometry blocker. Cloud then reviews equal-scale actual raster poses and decides whether to integrate. No production changes, engine launch, source repaints or publication are authorized by this contract.
