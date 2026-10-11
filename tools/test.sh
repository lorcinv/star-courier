#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TEST_ROOT=$(mktemp -d)
if [[ "${KEEP_TEST_ROOT:-1}" == 1 ]]; then
  trap 'printf "COMBINED_TEST_ROOT=%s\n" "$TEST_ROOT"' EXIT
else
  trap 'rm -rf "$TEST_ROOT"' EXIT
fi
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"
export XDG_CONFIG_HOME="$TEST_ROOT/config" XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_DATA_HOME="$TEST_ROOT/import"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
run_godot() {
  # Some GDScript runtime errors leave a zero process status. Preserve the
  # output and reject diagnostics as well as a nonzero engine return code.
  # This function is called inside a conditional so it must explicitly retain
  # a failing process/pipe status rather than relying on shell errexit.
  # A SceneTree script can emit an error and never reach its quit(). Bound
  # each owned test process so a broken fixture cannot suppress later suites.
  if timeout --signal=TERM --kill-after=5s "${TEST_TIMEOUT_SECONDS:-300}" "$GODOT" "$@" 2>&1 | tee "$TEST_ROOT/last-godot.log"; then
    :
  else
    return 1
  fi
  if grep -Eq '^SCRIPT ERROR:|^ERROR:|^FAIL([ :]|$)' "$TEST_ROOT/last-godot.log"; then
    echo "ENGINE_DIAGNOSTIC_FAILURE: $*" >&2
    return 1
  fi
}
# Import failure is a shared prerequisite failure. Independent suite failures
# below are collected so one stale fixture cannot hide later regressions.
run_godot --headless --path . --editor --import --quit
FAILED_RUNS=()
# Retain legacy PHYSICS replay gates. The rejected 3D-art/4x2-starter suites are
# historical, not assertions about the current pure2D pilot presentation.
for suite in test_simulation test_invariants test_day_cycle test_transactions test_replay_seed_integrity test_review_ledger_integrity test_recovery_integrity_lifecycle test_recovery_integrity_fixtures test_customer_reviews test_review_controller test_review_hud test_review_recovery_lifecycle test_customer_review_phone_integration test_customer_review_phone_publication test_integration test_representative_route test_performance test_hud_lifecycle test_flight_receipt test_flight_feedback_hud test_launch_flow test_hud_art_frame art_v4/test_pixel_stage test_v4_density_integration test_v4_hud_scale test_v4_settings_contrast test_moon_route test_moon_contracts test_moon_presentation test_readable_moon_lifecycle test_readable_moon_ascent_lifecycle test_readable_moon_framing test_ground_route test_ground_contracts test_ground_presentation test_wormhole test_wormhole_contracts test_wormhole_controller test_wormhole_hud test_otherworld_presentation test_wormhole_world test_three_day_progression test_pilot_simulation test_pilot_ascent test_pilot_timeline test_pilot_input_lifecycle test_ascent_controller test_assembly_2d test_flight_backdrop_2d test_ascent_backdrop test_v5_presentation test_v5_hud_interactions test_v5_pilot_hud test_ascent_hud test_courier_dialogue test_human_rigid_motion test_human_npc_lifecycle test_counter_parcel_support test_npc_sprite_2d test_neutral_actor_lifecycle test_story_economy test_story_controller test_counter_species_integration test_cargo_transport_2d test_cargo_loading_controller test_dialogue_nameplate_fixture test_extreme_builds test_extreme_controller test_extreme_presentation test_drill_shield_build test_grounded_launch test_flight_visibility test_workshop_economy test_workshop_controls test_workshop_input_2d test_workshop_legacy_recovery test_workshop_controller test_workshop_scene test_actor_motion_2d test_actor_locomotion_2d test_clerk_single_walk test_clerk_rigid_motion test_shop_sign_2d test_loading_scene_overlay test_cooperative_loading_controller test_player_facing_copy test_shop_locomotion_2d test_shop_locomotion_world test_shop_investigation test_courier_input test_courier_contexts test_courier_input_ownership test_customer_review_phone_skin test_seeded_offers test_seeded_review_transactions test_seeded_startup_recovery test_seeded_integrity_seam test_meteor_offer_integration test_meteor_variant_validation test_orbital_meteor test_corridor_framing test_corridor_framing_matrix test_flight_destination_copy test_protected_bird_reviews test_protected_bird_controller test_protected_bird_copy_context test_protected_bird_presentation test_protected_bird_hud_bounds test_readable_offer_adapter test_combined_authoring_policy test_readable_camera_applicability test_protected_bird_cue_lifecycle test_protected_bird_cue_controller; do
  export XDG_DATA_HOME="$TEST_ROOT/$suite"
  mkdir -p "$XDG_DATA_HOME"
  if ! run_godot --headless --path . -s "res://tests/$suite.gd"; then
    FAILED_RUNS+=("$suite")
  fi
done
export XDG_DATA_HOME="$TEST_ROOT/protected-bird-world"
mkdir -p "$XDG_DATA_HOME"
if ! run_godot --headless --path . -s res://fixtures/repro_protected_bird_world.gd -- --output=user://protected-bird-world; then
  FAILED_RUNS+=("protected-bird/world")
fi
source tools/test_protected_bird_suites.sh
run_protected_bird_suites
export XDG_DATA_HOME="$TEST_ROOT/smoke"
mkdir -p "$XDG_DATA_HOME"
if ! run_godot --headless --path . -- --smoke-test; then
  FAILED_RUNS+=("smoke")
fi
if ! python3 tools/test_species_npcs.py; then FAILED_RUNS+=("npc-assets"); fi
if ! python3 tools/test_actor_motion_assets.py; then FAILED_RUNS+=("motion-assets"); fi
if (( ${#FAILED_RUNS[@]} )); then
  printf 'REGRESSION_FAILED_RUN: %s\n' "${FAILED_RUNS[@]}" >&2
  exit 1
fi
