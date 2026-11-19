#!/bin/bash
# Play a known clip from the speakers and record it twice.
# Take 1: real microphone, Lull not running.
# Take 2: Lull Microphone while `lull run` is processing the real microphone.
#
# Defaults match the published example (a MacBook Air). Override them for another Mac:
#   LULL_INPUT="MacBook Pro Microphone" LULL_OUTPUT="MacBook Pro Speakers" ./run_test.sh
# List names with: /Applications/Lull.app/Contents/MacOS/lull devices
set -u
cd "$(dirname "$0")"

LULL="${LULL_BIN:-/Applications/Lull.app/Contents/MacOS/lull}"
LULL_INPUT="${LULL_INPUT:-MacBook Air Microphone}"
LULL_OUTPUT="${LULL_OUTPUT:-MacBook Air Speakers}"
VOL="${PLAYBACK_VOLUME:-70}"

if [ ! -x "$LULL" ]; then
  echo "Lull not found at $LULL. Install https://github.com/psanders/lull/releases" >&2
  exit 1
fi
python3 -c "import numpy" 2>/dev/null || {
  echo "numpy is required: python3 -m pip install -r requirements.txt" >&2
  exit 1
}
if [ ! -x ./rec ]; then
  swiftc -O rec.swift -o rec -framework AVFoundation
fi
if [ ! -x ./audioctl ]; then
  swiftc -O audioctl.swift -o audioctl
fi
if [ ! -f stimulus.wav ]; then
  python3 prepare.py
fi

OLD_IN="$(./audioctl get-input)"
OLD_OUT="$(./audioctl get-output)"
OLD_VOL="$(osascript -e 'output volume of (get volume settings)')"
LULL_PID=""
RECORD_SECONDS="$(python3 -c 'import wave; w=wave.open("stimulus.wav"); print(int(w.getnframes()/w.getframerate()) + 3); w.close()')"

restore() {
  ./audioctl set-input "$OLD_IN" >/dev/null 2>&1 || true
  ./audioctl set-output "$OLD_OUT" >/dev/null 2>&1 || true
  osascript -e "set volume output volume $OLD_VOL" >/dev/null 2>&1 || true
  if [ -n "$LULL_PID" ]; then
    kill "$LULL_PID" >/dev/null 2>&1 || true
  fi
}
trap restore EXIT

osascript -e "set volume output volume $VOL"
./audioctl set-output "$LULL_OUTPUT" >/dev/null
echo "saved input=$OLD_IN output=$OLD_OUT volume=$OLD_VOL"
echo "test output volume=$VOL device=$LULL_OUTPUT input=$LULL_INPUT record_seconds=$RECORD_SECONDS"

record_take() {
  local dest="$1"
  ./rec default "$dest" "$RECORD_SECONDS" > "$dest.log" 2>&1 &
  local pid=$!
  sleep 0.6
  afplay stimulus.wav
  wait "$pid"
}

speech_above_room() {
  python3 - << 'PY'
import json
from pathlib import Path
from prepare import read_wav, rms_db, best_lag, RATE

stimulus = read_wav(Path("stimulus.wav"))
mic = read_wav(Path("mic-off.wav"))
length = min(stimulus.size, mic.size)
lag, coeff = best_lag(stimulus[:length], mic[:length], 3 * RATE)
segments = {s["name"]: s for s in json.loads(Path("segments.json").read_text())["segments"]}

def piece(name):
    seg = segments[name]
    a = max(0, seg["start"] + lag)
    b = min(mic.size, seg["end"] + lag)
    return mic[a:b]

room = rms_db(piece("room_or_silence"))
speech = rms_db(piece("speech"))
print(f"align_lag_ms {1000*lag/RATE:.1f} corr {coeff:.4f} room_rms {room:.2f} speech_rms {speech:.2f} delta {speech-room:.2f}")
raise SystemExit(0 if speech - room >= 6 and coeff >= 0.3 else 1)
PY
}

echo "TAKE off (Lull not running)"
record_take mic-off-96k.wav
afconvert -f WAVE -d LEI16@48000 -c 1 mic-off-96k.wav mic-off.wav
if ! speech_above_room; then
  echo "speech was not clearly above the room at volume $VOL; retrying at 90"
  VOL="90"
  osascript -e "set volume output volume $VOL"
  record_take mic-off-96k.wav
  afconvert -f WAVE -d LEI16@48000 -c 1 mic-off-96k.wav mic-off.wav
  speech_above_room || echo "WARNING: speech still not 6 dB above the room segment"
fi
echo "off-take volume=$VOL"

echo "TAKE on (lull run -> Lull Microphone)"
"$LULL" run --input "$LULL_INPUT" --output "Lull Microphone" > lull-run.log 2>&1 &
LULL_PID=$!
sleep 1.5
./audioctl set-input "Lull Microphone" >/dev/null
record_take mic-on-96k.wav
kill "$LULL_PID" >/dev/null 2>&1 || true
wait "$LULL_PID" 2>/dev/null || true
LULL_PID=""
./audioctl set-input "$OLD_IN" >/dev/null

afconvert -f WAVE -d LEI16@48000 -c 1 mic-on-96k.wav mic-on.wav
echo "offline engine on the off-take recording"
"$LULL" file mic-off.wav mic-offline.wav > lull-file.log 2>&1
"$LULL" file mic-off.wav mic-offline-bypass.wav --no-nc --no-focus >> lull-file.log 2>&1
"$LULL" file stimulus.wav stimulus-lull.wav >> lull-file.log 2>&1
python3 measure.py mic-off.wav mic-on.wav mic-offline.wav mic-offline-bypass.wav stimulus-lull.wav stimulus.wav
python3 summarize.py "$VOL" "$OLD_VOL"
echo "DONE volume_used=$VOL"
echo "Recordings and RESULTS.txt are in $(pwd). The published example is untouched in example-run/."
