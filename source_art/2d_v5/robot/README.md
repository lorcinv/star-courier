# Courier robot and committed assembly feedback

The continuous real-parcel transport supersedes the older cosmetic order sequence described below. Its current state/API, empty-handed artwork, connected mechanical arm, and verification are documented in [empty-hands/README.md](empty-hands/README.md). The original six-pose source and derivatives remain preserved for provenance and part-edit gestures.

## Artwork provenance

- Original imagegen sheet: `cargo-robot-six-poses.png`, preserved byte-for-byte.
- Source SHA-256: `4620271793abc1cb5d84f845773e4f58ea85e61eb0836f609701c7c6ffa1917e`.
- Six authored sprite poses: idle, carrying parcel, offering parcel, carrying part, offering part, alert.
- `prepare_robot.py` only isolates existing generated pixels and makes technical derivatives. No robot is procedurally drawn or regenerated.
- Each pose registers the matched central load-bearing wheel and floor, rather than centering its changing silhouette. The fifth pose’s raised gripper extends beyond the nominal sheet cell; its explicit ROI preserves that art.
- Shared 96-color Oklab palette, nearest sampling to 80×72 logical pixels, alpha threshold 128 to binary transparency, nearest 2× to 160×144 runtime pixels.
- Every runtime pose uses foot anchor `(80,136)`. The body is 84–86 canonical pixels tall; held props raise its total silhouette to 106 pixels.
- Whole-root travel flips retain the foot anchor. The source body looks left while its offering arm points right, so a right-hand gesture uses the unflipped offering pose.
- These are generated sprite poses, **not a Spine project, rig, or runtime binding**. Real Spine work remains separate and pending.

## Integration contract

The controller remains the sole owner of gameplay and inventory commits. The component does not load economy/simulation scripts and cannot schedule a delayed gameplay mutation.

1. Instantiate `scripts/assembly_2d.gd` and add it directly to the world as a Node2D child.
2. Call `configure(assembly_origin, CELL)`, with canonical scene values `(728,288)` and `72`.
3. Call `bind_part_root(ship_root)` once. Existing live module sprites must retain `Part{id}` names.
4. **After a successful model commit and after `show_design()`/`render()`,** call `on_committed_edit(kind, committed_part)`. The component reads `id`, `x`, `y`, and `rot` only, then copies scalar values. It keeps no model dictionary reference.
5. Kinds: `place`, `move`, `rotate`, `remove`, `tune`; `add` aliases `place`; parameter/configure/input/target alias `tune`. Unknown kinds do nothing. Removal cancels that part’s pending feedback and acknowledges with the robot; it never draws a removed module or recreates it.
6. `on_order_changed(order_id, stage)` deduplicates repeated snapshots. Stages: accepted, loaded, dispatched (in_flight/flight/launch aliases), settled, failed, cancelled, declined, empty. Order changes interrupt earlier work. Dispatch does not wait for the animation.
7. Set `reduced_motion` from existing accessibility settings. Enabling it immediately restores any animated module and cancels movement/flashes. New events only use brief stationary robot pose changes.
8. Call `set_scene_visible(mode != "flight")`. Hiding clears work; returning does not replay stale actions. Ancestor visibility changes also clear feedback. `reset()` clears all visual/order state; `reset(false)` preserves the most recent order snapshot without resuming its animation.
9. When switching between craft and launcher, undoing, loading blueprints, or replacing the design wholesale, call `reset(false)` before/alongside the redraw. This prevents an old same-ID sprite action from crossing design contexts.
10. The world can tint the component alongside other workshop nodes for night lighting.

## Visual/state behavior

- Idle is static: no invented work, random roaming, or fake assembly loops.
- A committed part uses its **actual existing Sprite2D**: 0.18s restrained alignment, 0.16s latch, exact canonical transform restoration. Generated impact art supplies a 22×20-pixel, 0.12s local spark. Tuning skips translation and sparks.
- A part edit gives the robot one latest replaceable task. It carries a part along the floor, briefly raises it toward the workbench, then returns to the dock.
- Accepted order: counter approach → parcel pickup pose → floor carry → offering pose → dock. The sequence is cosmetic, finite, and interruptible. It never changes the order or moves model inventory.
- Robot root z=4, live modules z=5, latch sparks effective z=6, counter foreground z=8. Feet remain at y=486, with x restricted to 436–818 (dock516, counter444), away from the launch cradle and customer.
- The 1280×720 workshop’s open parts drawer covers y≈487–640, which occludes the floor-level robot. Collapse that drawer to review the assisting pose; do not move the robot off the authored floor to compensate.
- The order parcel displayed by the parent world is independent presentation. If the parent chooses to show a matching carry transfer, it should avoid rendering two copies during that transfer; this component does not mutate the parent parcel node.

## Bounds and ownership

- Maximum four active part actions, keyed by id. Repeated edits cancel/replace the same action. At capacity, the oldest action restores its module immediately and is discarded.
- Exactly four reusable spark nodes and six cached robot textures. One replaceable robot intent, no waiting queue.
- No Tween, timer, callback, input handler, Control, collision body, or deferred mutation.
- Module/root references are weak; redraw can replace sprites without keeping old nodes alive. Completion, reset, hide, order interruption, and tree exit restore valid affected sprites.

## Evidence

- Focused suite: `godot --headless --path . -s res://tests/test_assembly_2d.gd`, with isolated `XDG_DATA_HOME`.
- 35 passing assertions: provenance registration, exact restoration, actual sprite reuse, repeated edits, action/spark budgets, no scene/Tween growth, freed/replaced sprites, removal, order replacement/cancellation/deduplication, hiding, reduced motion, input non-interception, and unchanged model/accounting/physics data.
- `hub-robot-composite-proof.png` is an explicitly labeled technical composite on the earlier hub screenshot, not a runtime capture.
- `runtime-01-hub.png` through `runtime-06-assist-drawer-collapsed.png` are real Godot rendered frames from the live controller with the component reused when integrated, otherwise injected. `runtime_robot_proof.gd`/`run_runtime_proof.py` reproduce them. They are scripted composition proof, not native-input end-to-end QA.
- Pixel validation: `python source_art/2d_v5/robot/validate_robot.py` verifies source hash, all six binary-alpha/shared-palette poses, exact nearest2× derivatives, common foot registration, and chassis overlap ≥0.85.
- Full integration and aggregate regression are the parent task’s responsibility after wiring the hooks.
