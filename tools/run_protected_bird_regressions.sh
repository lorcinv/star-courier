#!/usr/bin/env bash
# Focused standalone entry point. Requires explicit allocated engine lane.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TEST_ROOT=$(mktemp -d)
if [[ "${KEEP_TEST_ROOT:-0}" == 1 ]]; then
  trap 'printf "PROTECTED_BIRD_TEST_ROOT=%s\n" "$TEST_ROOT"' EXIT
else
  trap 'rm -rf "$TEST_ROOT"' EXIT
fi
export HOME="$TEST_ROOT/home" XDG_CONFIG_HOME="$TEST_ROOT/config" XDG_CACHE_HOME="$TEST_ROOT/cache" XDG_DATA_HOME="$TEST_ROOT/import"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
run_godot() {
  if timeout --signal=TERM --kill-after=5s "${TEST_TIMEOUT_SECONDS:-300}" "$GODOT" "$@" 2>&1 | tee "$TEST_ROOT/last-godot.log"; then :; else return 1; fi
  if grep -Eq '^SCRIPT ERROR:|^ERROR:|^FAIL([ :]|$)' "$TEST_ROOT/last-godot.log"; then
    echo "ENGINE_DIAGNOSTIC_FAILURE: $*" >&2; return 1
  fi
}
# Import is a shared prerequisite; independent test failures are accumulated.
run_godot --headless --path . --editor --import --quit
FAILED_RUNS=()
source tools/test_protected_bird_suites.sh
run_protected_bird_suites
if (( ${#FAILED_RUNS[@]} )); then
  printf 'REGRESSION_FAILED_RUN: %s\n' "${FAILED_RUNS[@]}" >&2
  exit 1
fi
