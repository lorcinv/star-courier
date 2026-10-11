#!/usr/bin/env bash
# Use only in a currently allocated exclusive renderer window.
set -euo pipefail
if [[ $# -ne 4 ]]; then echo 'Usage: run_native_session.sh DISPLAY_NUMBER CANDIDATE_PROJECT FRESH_OUTPUT EXACT_PERMISSION_NOTE' >&2; exit 2; fi
DISPLAY_NUMBER=$1; CANDIDATE=$2; OUTPUT=$3; PERMISSION=$4
[[ "$DISPLAY_NUMBER" =~ ^[0-9]+$ ]] || exit 2
STAGE=$(cd "$(dirname "$0")" && pwd);ROOT=$(cd "$STAGE/.." && pwd)
# Cloud execution namespaces support the established same-process TCP route.
# Do not split Xorg and the driver into different exec_command calls.
/usr/lib/xorg/Xorg ":$DISPLAY_NUMBER" -noreset -nolisten unix -nolisten local -listen tcp -ac -config "$ROOT/tests/xorg_v5_hud_4k.conf" -logfile "/tmp/courier-marble-xorg$DISPLAY_NUMBER.log" >"/tmp/courier-marble-xorg$DISPLAY_NUMBER.stdout" 2>&1 & XPID=$!
trap 'kill "$XPID" 2>/dev/null || true; wait "$XPID" 2>/dev/null || true; echo "MARBLE_RENDERER_CLEANED display=$DISPLAY_NUMBER"' EXIT
sleep 1
export DISPLAY="localhost:$DISPLAY_NUMBER"
python3 "$STAGE/qa_marble_native.py" --approved --release-note "$PERMISSION" --candidate "$CANDIDATE" --display "$DISPLAY" --out "$OUTPUT"
