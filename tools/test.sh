#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export XDG_CONFIG_HOME="$TEST_ROOT/config" XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_DATA_HOME="$TEST_ROOT/import"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
"$GODOT" --headless --path . --editor --import --quit
# Retain legacy PHYSICS replay gates. The rejected 3D-art/4x2-starter suites are
# historical, not assertions about the current pure2D pilot presentation.
for suite in test_simulation test_invariants test_day_cycle test_transactions test_integration test_representative_route test_performance test_hud_lifecycle test_launch_flow test_hud_art_frame art_v4/test_pixel_stage test_v4_density_integration test_v4_hud_scale test_v4_settings_contrast test_ground_route test_ground_contracts test_ground_presentation test_pilot_simulation test_pilot_ascent test_pilot_timeline test_pilot_input_lifecycle test_ascent_controller test_assembly_2d test_flight_backdrop_2d test_ascent_backdrop test_v5_presentation test_v5_hud_interactions test_v5_pilot_hud test_ascent_hud test_courier_dialogue test_npc_sprite_2d test_story_economy test_story_controller test_counter_species_integration test_cargo_transport_2d test_cargo_loading_controller test_dialogue_nameplate_fixture test_extreme_builds test_extreme_controller test_extreme_presentation test_drill_shield_build test_grounded_launch test_flight_visibility test_workshop_economy test_workshop_controls test_workshop_input_2d test_workshop_legacy_recovery test_workshop_controller test_workshop_scene test_actor_motion_2d test_actor_locomotion_2d test_loading_scene_overlay test_cooperative_loading_controller test_player_facing_copy test_shop_locomotion_2d test_shop_locomotion_world test_courier_input test_courier_contexts test_courier_input_ownership; do
  export XDG_DATA_HOME="$TEST_ROOT/$suite"
  mkdir -p "$XDG_DATA_HOME"
  "$GODOT" --headless --path . -s "res://tests/$suite.gd"
done
export XDG_DATA_HOME="$TEST_ROOT/smoke"
mkdir -p "$XDG_DATA_HOME"
"$GODOT" --headless --path . -- --smoke-test
python3 tools/test_species_npcs.py
python3 tools/test_actor_motion_assets.py
