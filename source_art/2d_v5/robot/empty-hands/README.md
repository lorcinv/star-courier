# Continuous real-parcel transport, 2026-10-10

## Generated art and technical derivatives

`carry-offer-original.png` and `raised-gripper-original.png` are preserved imagegen outputs. The parent requested empty grippers because the older carry-parcel/offer-parcel poses contain painted boxes. They remain historical assets; the transport never selects them.

`prepare_empty_hands.py` registers both new whole-body poses by the middle wheel and floor, using one uniform body scale. Nearest sampling, the existing shared 96-color palette and binary alpha produce 160×144 runtime images with foot origin (80,136). The script does not repaint faces, redraw a robot, or deform a head independently.

The long generated arm is alpha-isolated from the raised source, retaining its original shoulder, joints, links and empty gripper pixels. Its runtime shoulder is (17.8,150), and its gripper centre is (92,23.4). A dedicated Sprite2D pivots at the robot's shoulder and uniformly scales/rotates only this mechanical image to keep its gripper on the actual external parcel. The body stays foot-registered and unscaled. It is a simple generated-sprite presentation, not a Spine rig or project.

`derivatives.json` records source SHA-256 values, crop/registration data and runtime geometry. Rerun `python3 source_art/2d_v5/robot/empty-hands/prepare_empty_hands.py` to reproduce derivatives, then import with Godot.

## Ownership and state

- Economy/controller own acceptance, cargo_loaded, dialogue, saving and dispatch. The renderer does not mutate any of them.
- update_shop_state accepts cargo_loaded and handoff_released on the active contract or as top-level overrides. Explicit false handoff_released holds one package at the customer while dialogue is open. The human handoff artwork has empty hands, so it holds the actual external sprite; the three nonhuman handoff poses contain painted parcels. NPC pose_contains_parcel() records this verified art distinction. True starts the continuous chain. Missing keys preserve legacy counter-only adapters.
- begin_loading(order_id="") and pack_parcel() request one idempotent chain. is_loading() and is_parcel_loaded(order_id="") expose progress. fastforward_loading(order_id="") reaches the exact final state and emits loading_complete once. restore_loaded(order_id) applies a durable loaded snapshot without replay or emission.
- Customer handoff (0.12s) → external counter transfer (0.40s) → clerk receipt with empty hands (0.12s) → floor-level robot approach → pickup (0.24s) → turn (0.16s) → carry → connected-arm insertion (0.34s). Default ship completes about2.6s after dialogue release.
- Exactly one external parcel Sprite2D travels from the customer anchor to the ship's actual cargo cell. When a customer pose contains a painted package it disappears at external transfer start; the human's external package remains continuously visible. The external package uses the neutral generated shared cutout from the NPC debranding pass, keeping its authored aspect ratio before entering the larger ship cargo casing. Robot empty poses never introduce a baked box. The installed cargo module stays hidden until the frame the external parcel reaches the bay and hides.
- Cargo exclusively owns the robot intent during pickup/carry/insertion. Part-edit feedback may use existing bounded module/spark effects, but cannot redirect cargo or change its pose. Rebuilds rebind actual module nodes and retain the transport.
- Order cancellation/replacement invalidates old generations and releases the robot. Same-ID reaccept begins a new chain. Accepted snapshots cannot regress locally completed cargo. A saved loaded snapshot restores directly; seen-but-unloaded restarts safely.
- Reduced motion and explicit launch fast-forward settle exactly and do not retain motion. set_focus_active(false), hidden ancestors and scene visibility pause clocks rather than running unseen deliveries or accumulating catch-up.
- Clerk and NPC subtle idle rotations pivot at registered feet. Their head/body art and scale remain unchanged, and handoff poses reset angles. Reduced motion disables these rotations.

## Verification

- tests/test_cargo_transport_2d.gd:97 assertions covering every phase, one-box identity, mechanical grip endpoint, floor registration, under3s default duration, cancellation/reaccept/replacement, restart, reduced motion, fast-forward, rapid redraw/edit, focus/visibility interruption and bounded nodes/tweens.
- tests/test_counter_species_integration.gd:176 assertions for four persisted species, accessories, counter anchors, phase continuity and interruption.
- tests/test_assembly_2d.gd:36 assertions for committed-part feedback isolation and transport ownership.
- tests/test_v5_presentation.gd:113 assertions including unchanged flight camera/presentation gates.
- Controller/save/launch coverage is in tests/test_cargo_loading_controller.gd, owned by main/economy integration.
- tools/cargo_transport_proof.gd produces nine actual Godot-rendered scene-level phase screenshots under /tmp/cargo-transport-proof. They are scripted graphical composition proof, not native-input end-to-end evidence. Native acceptance-to-launch verification remains a separate integration check.
