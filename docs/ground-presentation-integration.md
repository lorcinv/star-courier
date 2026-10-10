# Ground-route presentation staging

Integration update, 2026-10-10: the focused changes below are now in the main game. All 59 aggregate suites, the 11-check native trial and the 48-check full native business day passed. See [current evidence and limitations](QA-v5-ground.md). The staging sections remain as provenance of the earlier isolated work, not a claim that integration is still pending.

## Ready-to-integrate scope

Apply only the focused patches in `patches/`, after the separately staged ground profile and contract/story/bootstrap changes. No production file was edited, no Git operation was used, and no GUI or software-GPU renderer was started. All Godot runs were headless, with the successful runs using isolated HOME/XDG directories.

Runtime changes are limited to three files:

- `ascent_backdrop_2d.gd`: an explicit `GroundProfile.is_ground_route(route)` selects the generated near-depot strip and forces city-only atmospheric presentation. Seven existing layers are unchanged; the eighth raster plane is created once on the first ground contract, then cached and hidden on legacy routes. Ordinary one-period modulo, camera-relative parallax, nearest sampling and the existing local-texture blur shader remain in use. No shader changes or reflected tiles.
- `world_view_2d.gd`: only the destination construction branch, three receiver constants and a small receiver helper. Explicit ground contracts get `flight/receiver.png`; other pilot contracts retain their original orbital dock position, offset and scale. The saved destination name labels ground deliveries.
- `game_hud.gd`: a marker-only helper and small flight copy branches. Ground status is `低空配送`, the actual saved destination replaces the long route title, and the final approach shows the saved receiving speed limit. Actual altitude, gate direction/time, charge, funded thrust, overdrive, circuit controls and pause behavior stay intact. Passing the shallow climb end does not advertise final arrival while gates remain.

No main/controller presentation hunk is needed: `main.render()` already sends a copy of the actual `flight_order` as `activeorder`. The staged runtime includes only the other worker's reviewed new-save bootstrap call-order change, not a second implementation. It also imports the supplied economy/story/profile changes solely so the focused test can exercise a genuine new-shop default.

## Exact saved-content boundary

Only `route_profile == "ground-city-v1"` selects these ground branches. `route_kind`, customer, contract ID, distance, height and control version never infer that marker. Unmarked saved v3 routes keep the old orbital receiver and ascent HUD even if their geometry happens to resemble the new ground route. Their stored `background_route` is still respected exactly as before. Unknown future ground markers also keep the existing fallback.

The v3 solver, sparse input history, 60 Hz command ticks, fixed substeps, mounting behavior, source/circuit energy, uncapped mounted-output overdrive, drill and shield are untouched. No profile authoring call occurs in controller launch, trial, checkpoint or resume. Physics source hashes are locked in the manifest.

## Receiver and decorative-plane registration

The physical capture center remains:

`flight_origin + Vector2(saved_distance, saved_destination_y) * CELL`

The existing collision/receipt cue retains the saved radius. The original 279 x 220 kiosk raster's deck anchor is source pixel `(139.5, 149)`. Its uniformly scaled deck is centered 32 world-presentation pixels below the aperture's bottom, with width `max(230, 2 * radius_pixels + 120)`. This avoids the old tiny-prop-under-a-large-aperture mismatch. It does not shift the simulator goal or snap cargo to the deck.

The near-city strip is a decorative background plane under the gameplay canvas, never a street or roof collider. Its first opaque pixels begin at source y=346; the ordinary cruise camera puts those silhouettes below the central craft band. Horizontal parallax is 14 px/m versus the far skyline's 4 px/m, while vertical parallax is restrained to 2 px/m. Generated architecture remains behind every real gate/part and is not used to conceal a 3D scene. No new artwork or asset derivatives were produced.

The PNG's complete RGBA edges match exactly. Godot's existing alpha-border import adds differing RGB to 23 fully transparent edge pixels, so the imported-texture regression correctly compares premultiplied RGBA. All visible edge pixels and alpha match; the existing blur already uses premultiplied taps. No import setting was changed.

Launch transfer functions, shop/right-pad origins, fixed launcher support, full-craft fitting, every cargo/part world-to-canvas mapping, camera/input inverse transforms and old resumed positions are byte-identical outside the receiver branch. Existing source-level 3D base classes are outside this patch; the live flight viewport remains the current pure-2D implementation.

## Cooperative checkpoint and file conflicts

An initial staging snapshot preceded a concurrent Settings cleanup: production HUD removed the obsolete shadow-quality selector and shortened its panel, and main clarified retained save-quality compatibility. These changes do not overlap the flight hunks. Staging was refreshed from the current HUD/main, the focused patch applied cleanly to a fresh current-source scratch copy, and relevant regressions were rerun. `manifest.json` and `base-hashes.json` carry the refreshed exact bases; `base-initial/` is historical scratch scaffolding.

Still check base hashes again at the cooperative checkpoint. Apply individual hunks if any file changed; never copy this staging project's whole `scripts/` directory into production. World customer/loading/actor code is not part of the proposal. Do not use stale copies to overwrite newer tablet, walking, cargo or copy work.

## Verification

Godot 4.6.3, headless, current production assets/import cache copied into the isolated staging project:

- `test_ground_presentation.gd`: 71 passed, 0 failed. New default ground bootstrap/trial; explicit/absent/unknown marker selection; exact JSON resume cargo positions and energy; grounded launch continuity; custom saved destination/radius/speed; actual kiosk/capture geometry; all six visible gate circles; original full-craft mapping; ordinary nonmirrored wrap; bounded cached layers; reduced motion/pause blur; ground HUD across 1280/1920/3840-wide frames.
- Existing `test_ascent_backdrop.gd`: 32 passed, 0 failed.
- Existing `test_ascent_hud.gd`: 65 passed, 0 failed.
- Existing `test_grounded_launch.gd`: 71 passed, 0 failed.
- Current `test_player_facing_copy.gd`: 31 passed, 0 failed.
- Existing `test_extreme_presentation.gd`: 103 passed, 0 failed.
- Existing `test_flight_visibility.gd`: 783 passed, 0 failed; minimum measured top-resource clearance 17.3945 native pixels.
- Total: 1,156 passed, 0 failed. New additions were rerun after the final copy cleanup. The full aggregate and full physics/replay suites were not run in this presentation stage.

Add `test_ground_presentation` to the lead's then-current aggregate test list after integrating the existing ground-contract/bootstrap patch. No competing aggregate-list patch is supplied.

A read-only cmap audit again finds missing `屋`, `顶`, `避` in the existing Chinese font. Rebuild the normal font subset after integration, then rerun coverage. The font was not modified here.

Native GUI/rendered review is intentionally pending. Under the lead's exclusive software-GPU slot, verify the real default ground trial/formal route, all three gates, near-rooftop depth and repeat seams, visible kiosk/capture alignment, W/S/Shift, pause/focus, reduced motion, tall/wide craft and a saved unmarked ascent restart. Headless transform checks are not a claim of native visual quality or playability.

## Integration artifacts

- `patches/backdrop-ground.patch`
- `patches/world-ground-receiver.patch`
- `patches/hud-ground-copy.patch`
- `patches/ground-presentation-test.patch`
- `patches/ground-presentation-doc.patch`
- `manifest.json`, `base-hashes.json`, seven suite logs

Everything else, including `base/`, `base-initial/`, copied assets, `.godot/`, other scripts/scenes/tests, runtime data, seam inspection, and the isolated runner, is validation scaffolding. The supplied profile/economy/story/main bootstrap dependencies remain owned by the earlier stages and must not be re-applied from this runtime copy.
