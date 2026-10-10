#!/usr/bin/env bash
set -euo pipefail
# Requires a licensed/evaluation REAPER install and a working display.
# Set REAPER_BIN to your REAPER executable; all content paths stay relative.
cd "$(dirname "$0")"
REAPER_BIN="${REAPER_BIN:-reaper}"
mkdir -p renders ../../assets/audio
for cue in workshop_loop flight_loop; do
  "$REAPER_BIN" -nosplash -ignoreerrors -renderproject "$PWD/$cue.rpp"
  ffmpeg -v error -y -i "../../assets/audio/$cue.wav" -c:a libvorbis -q:a 5 "../../assets/audio/$cue.ogg"
  mv "../../assets/audio/$cue.wav" "renders/$cue.wav"
done
python validate_audio.py
