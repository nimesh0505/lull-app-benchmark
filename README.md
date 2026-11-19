# Lull offline benchmark

A repeatable check of [Lull](https://github.com/psanders/lull) 0.1.0, the open-source macOS noise-cancellation app. It runs a generated clip through Lull's offline engine and measures what each stage does to the speech and the noise.

No microphone is used, so no room audio is recorded. Everything here can be re-run and checked from this repository.

Lull is not included. Install it from its [releases](https://github.com/psanders/lull/releases) first.

## Result

Machine: MacBook Air, Apple Silicon, macOS 26.6.1, Lull 0.1.0. Levels are RMS in dBFS, where a more negative number is quieter. The change column is Lull's output minus the clean clip.

| Part of the clip | Clean clip | Full Lull | Change | Noise removal only | Change | Voice focus only | Change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Speech | −23.32 | −23.49 | −0.17 | −23.45 | −0.13 | −29.76 | −6.44 |
| Noise only | −32.65 | −63.71 | −31.06 | −62.46 | −29.81 | −94.55 | −61.90 |
| Speech plus noise | −22.64 | −23.68 | −1.04 | −23.62 | −0.98 | −25.59 | −2.95 |
| Quieter sentence | −43.33 | −70.23 | −26.90 | −47.99 | −4.66 | −87.68 | −44.35 |
| Silence before the clip | digital silence | −92.54 | — | −92.54 | — | digital silence | — |

“Full Lull” is the default. “Noise removal only” runs with `--no-focus`, and “Voice focus only” runs with `--no-nc`.

Other measurements:

- **Delay.** The full chain and the noise-removal stage add 30 ms. Voice focus alone adds none.
- **Shape match.** After alignment, the full output correlates 0.917 with the clean clip, noise removal alone 0.922, and voice focus alone 0.657.

The noise-removal stage does most of the noise reduction. Voice focus, which runs on the denoised signal, takes the quieter sentence down further. On its own, voice focus lowers the speech by 6.44 dB. In the full chain the speech change is only −0.17 dB, because the noise-removal stage runs first.

The full table is in [`example-run/metrics.json`](example-run/metrics.json). The offline run log is [`example-run/lull-file.log`](example-run/lull-file.log).

## What was played

`prepare.py` builds the clip, a 48 kHz mono file:

1. One second of silence.
2. A short 1 kHz beep, used only as an alignment mark.
3. One sentence from `say`, peak-normalized to −6 dBFS: “This is a microphone test. One person is speaking in a clear voice. The words should stay understandable when the noise is removed.”
4. Four seconds of low-passed noise, peak −18 dBFS.
5. The sentence mixed with that noise.
6. The same sentence again, peak −26 dBFS.
7. One second of silence.

`measure.py` lines each processed file up with the clean clip by cross-correlation, then reports each slice's level. The lag finder is checked on a synthetic shift of 1234 samples before the clip is built.

## Run it

Requirements: macOS 13 or later, Apple Silicon, Python 3 with numpy, and Lull installed at `/Applications/Lull.app`.

```sh
python3 -m pip install -r requirements.txt
./run_offline.sh
```

The script takes about 3 seconds. It runs the clip through Lull three times (full, noise removal only, voice focus only), writes the processed clips and `metrics.json` to the repository root, and does not touch `example-run/`. Those root files are git-ignored.

Listen to the clean clip and the full Lull output:

```sh
afplay example-run/stimulus.wav
afplay example-run/stimulus-lull.wav
```

## Files

| Path | What it is |
| --- | --- |
| `run_offline.sh` | Runs the offline benchmark end to end. |
| `prepare.py` | Builds `stimulus.wav` and `segments.json`. |
| `measure.py` | Aligns each processed file to the clean clip and prints the levels. |
| `example-run/stimulus.wav` | The clean clip. |
| `example-run/stimulus-lull.wav` | Lull's full output for the clip. |
| `example-run/stimulus-nc-only.wav` | Lull with voice focus off. |
| `example-run/stimulus-focus-only.wav` | Lull with noise removal off. |
| `example-run/segments.json` | Where each part of the clip sits in time. |
| `example-run/metrics.json`, `lull-file.log` | Numbers and log from the published run. |

## Live microphone test (not validated)

The repository also has scripts that play the clip through the speakers and record the microphone with Lull off and on: `run_test.sh`, `rec.swift`, `audioctl.swift`, `summarize.py`. They are not part of the benchmark above and produce no published results.

They record whatever the room sounds like during the test, so the captures can contain speech from people nearby. Run them only in a room where nobody is nearby, and do not share the captures in the repository root (git-ignored) unless you have checked them. The most recent live run failed its own checks, so the live path is unproven. Do not rely on it until a run passes: the printed correlation must be at least 0.3, and speech must be clearly above the room in both takes.

## Limits

This measures Lull's offline engine on one generated clip with one voice, not the live app. Live microphone behaviour, latency through a meeting app, and behaviour with real speakers and real rooms are not measured here. The numbers are for Lull 0.1.0 and may change in later versions.
