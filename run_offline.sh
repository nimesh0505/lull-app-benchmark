#!/bin/bash
# Runs the generated clip through Lull's offline engine. No microphone and no room audio.
# Each stage is measured alone so its effect can be read off the numbers.
set -eu
cd "$(dirname "$0")"

LULL="${LULL_BIN:-/Applications/Lull.app/Contents/MacOS/lull}"
if [ ! -x "$LULL" ]; then
  echo "Lull not found at $LULL. Install https://github.com/psanders/lull/releases" >&2
  exit 1
fi
if ! python3 -c "import numpy" 2>/dev/null; then
  echo "numpy is required: python3 -m pip install -r requirements.txt" >&2
  exit 1
fi

for file in stimulus.wav segments.json; do
  [ -f "$file" ] || cp "example-run/$file" "$file"
done

: > lull-file.log
run_variant() {
  local name="$1"
  shift
  "$LULL" file stimulus.wav "$name.wav" "$@" >> lull-file.log 2>&1
}
run_variant stimulus-lull
run_variant stimulus-nc-only --no-focus
run_variant stimulus-focus-only --no-nc

python3 measure.py stimulus.wav stimulus-lull.wav stimulus-nc-only.wav stimulus-focus-only.wav
echo "Wrote metrics.json and the processed clips to $(pwd)."
