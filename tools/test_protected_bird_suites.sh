#!/usr/bin/env bash
# Source from tools/test.sh after run_godot(), TEST_ROOT and FAILED_RUNS exist.
# No import here. The outer runner owns the single import prerequisite.
protected_bird_run_checked() {
  local label="$1" marker="$2" expected="$3" script="$4" status=0
  shift 4
  if ! run_godot --headless --path . -s "res://tests/$script.gd" "$@"; then status=1; fi
  if ! cp "$TEST_ROOT/last-godot.log" "$TEST_ROOT/protected-bird-logs/$label.log"; then status=1; fi
  local extra=()
  if [[ "$marker" == PROTECTED_BIRD_VALIDATOR_VARIANTS ]]; then extra=(--mutations 7401); fi
  if ! python3 tools/check_protected_bird_run.py "$TEST_ROOT/last-godot.log" "$marker" "$expected" "${extra[@]}"; then status=1; fi
  if (( status )); then FAILED_RUNS+=("protected-bird/$label"); fi
  return 0
}
protected_bird_fresh_context() {
  local label="$1" context
  if ! context=$(mktemp -d "$TEST_ROOT/protected-bird-$label.XXXXXX"); then
    FAILED_RUNS+=("protected-bird/$label/context"); return 1
  fi
  export HOME="$context/home" XDG_CONFIG_HOME="$context/config" XDG_CACHE_HOME="$context/cache" XDG_DATA_HOME="$context/data"
  if ! mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"; then
    FAILED_RUNS+=("protected-bird/$label/context"); return 1
  fi
}
run_protected_bird_suites() {
  local old_home="$HOME" old_config="$XDG_CONFIG_HOME" old_cache="$XDG_CACHE_HOME" old_data="$XDG_DATA_HOME"
  if ! mkdir -p "$TEST_ROOT/protected-bird-logs"; then FAILED_RUNS+=("protected-bird/log-directory"); return 0; fi
  local row label marker expected script
  if ! python3 tools/verify_protected_bird_source.py; then FAILED_RUNS+=("protected-bird/source-before"); fi
  local rows=(
    'fixture-io PROTECTED_BIRD_FIXTURE_IO 15 test_protected_bird_fixture_io'
    'numeric-witness PROTECTED_BIRD_NUMERIC_WITNESS 25 test_protected_bird_numeric_witness'
    'contact WILDLIFE_CONTACT_PREPARED_TEST 16 test_wildlife_contact_v1'
    'foundation PROTECTED_BIRD_FOUNDATION 117 test_protected_bird_foundation'
    'chronology PROTECTED_BIRD_CHRONOLOGY 35 test_protected_bird_chronology'
    'rays PROTECTED_BIRD_RAYS 216 test_protected_bird_rays'
    'legacy-parity PROTECTED_BIRD_LEGACY_PARITY 4203 test_protected_bird_legacy_parity'
    'validator-variants PROTECTED_BIRD_VALIDATOR_VARIANTS 14813 test_protected_bird_validator_variants'
  )
  for row in "${rows[@]}"; do
    read -r label marker expected script <<< "$row"
    if protected_bird_fresh_context "$label"; then
      protected_bird_run_checked "$label" "$marker" "$expected" "$script"
    fi
  done
  # Keep the six real paid negative-root observations as an explicit permanent gate.
  if protected_bird_fresh_context negative-root-paid-repro; then
    protected_bird_run_checked negative-root-paid-repro PROTECTED_BIRD_RAYS 49 test_protected_bird_rays -- --repro
  fi
  for row in 'legacy_1_0 PROTECTED_BIRD_ROUTES test_protected_bird_routes' 'commercial_2_4 PROTECTED_BIRD_COMMERCIAL_ROUTES test_protected_bird_commercial_routes'; do
    read -r label marker script <<< "$row"
    # EXACTLY ONE fresh context per pair. Never reset it before --replay, and
    # never seed it from res:// goldens. Replay runs even if generation fails,
    # so its own missing/partial witness error is collected independently.
    if protected_bird_fresh_context "$label"; then
      protected_bird_run_checked "$label-generate" "$marker" 13 "$script"
      protected_bird_run_checked "$label-replay" "$marker" 17 "$script" -- --replay
      if ! python3 tools/check_protected_bird_evidence.py "$XDG_DATA_HOME" "$label"; then
        FAILED_RUNS+=("protected-bird/$label/golden-bytes")
      fi
    fi
  done
  if ! python3 tools/verify_protected_bird_source.py; then FAILED_RUNS+=("protected-bird/source-after"); fi
  export HOME="$old_home" XDG_CONFIG_HOME="$old_config" XDG_CACHE_HOME="$old_cache" XDG_DATA_HOME="$old_data"
}
