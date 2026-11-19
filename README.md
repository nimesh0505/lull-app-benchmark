<p align="center">
  <img src="docs/lull-logo.png" alt="Lull" width="300">
</p>

<h1 align="center">Lull offline benchmark</h1>

<p align="center">
  Does <a href="https://github.com/psanders/lull">Lull</a> remove the noise without losing the voice?<br>
  This repo answers that with a test you can run yourself. No microphone, no room recording.
</p>

---

## Quick start

1. Install [Lull](https://github.com/psanders/lull/releases) to `/Applications/Lull.app`.
2. Run the test:

   ```sh
   python3 -m pip install -r requirements.txt
   ./run_offline.sh
   ```

3. Listen to the difference:

   ```sh
   afplay example-run/stimulus.wav        # clean clip, with noise and a second, quieter voice
   afplay example-run/stimulus-lull.wav   # the same clip after Lull
   ```

The run takes about 3 seconds and writes `metrics.json` to the repo folder.

## What it shows

| Question | Answer |
| --- | --- |
| How much noise does Lull remove? | About **31 dB** from the noise-only part of the clip. |
| Does the voice stay intact? | Yes. The speech changes by **0.17 dB**, a change too small for most listeners to notice. |
| What happens to the quieter second voice? | It drops by **27 dB**. |
| What does it cost? | A **30 ms** delay. |
| Is there a trade-off? | Voice focus on its own lowers the speech by **6.44 dB**. With noise removal first, the speech change is only 0.17 dB. |

Levels are RMS in dBFS. A more negative number is quieter. Each row shows the clean clip, Lull's full output, and two single-stage versions.

| Part of the clip | Clean clip | Full Lull | Change | Noise removal only | Change | Voice focus only | Change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Speech | −23.32 | −23.49 | −0.17 | −23.45 | −0.13 | −29.76 | −6.44 |
| Noise only | −32.65 | −63.71 | −31.06 | −62.46 | −29.81 | −94.55 | −61.90 |
| Speech plus noise | −22.64 | −23.68 | −1.04 | −23.62 | −0.98 | −25.59 | −2.95 |
| Quieter sentence | −43.33 | −70.23 | −26.90 | −47.99 | −4.66 | −87.68 | −44.35 |
| Silence before the clip | digital silence | −92.54 | — | −92.54 | — | digital silence | — |

“Full Lull” is the default. “Noise removal only” runs with `--no-focus`. “Voice focus only” runs with `--no-nc`.

Other measurements:

- **Delay.** The full chain and the noise-removal stage add 30 ms. Voice focus alone adds none.
- **Shape match.** After alignment, the full output correlates 0.917 with the clean clip. Noise removal alone gives 0.922 and voice focus alone gives 0.657.

Noise removal does most of the noise reduction. Voice focus runs on the denoised signal and takes the quieter sentence down further.

The full numbers are in [`example-run/metrics.json`](example-run/metrics.json). The run log is [`example-run/lull-file.log`](example-run/lull-file.log).

## What the test plays

`prepare.py` builds the clip, a 48 kHz mono file:

1. One second of silence.
2. A short 1 kHz beep, used only as an alignment mark.
3. One sentence from macOS `say`, peak-normalized to −6 dBFS: “This is a microphone test. One person is speaking in a clear voice. The words should stay understandable when the noise is removed.”
4. Four seconds of low-passed noise, peak −18 dBFS.
5. The sentence mixed with that noise.
6. The same sentence again, peak −26 dBFS.
7. One second of silence.

`measure.py` lines each processed file up with the clean clip by cross-correlation, then reports each part's level. The alignment is checked on a synthetic shift of 1234 samples before the clip is built.

## Files

| Path | What it is |
| --- | --- |
| `run_offline.sh` | Runs the whole offline test. |
| `prepare.py` | Builds `stimulus.wav` and `segments.json`. |
| `measure.py` | Aligns each processed file to the clean clip and prints the levels. |
| `example-run/stimulus.wav` | The clean clip. |
| `example-run/stimulus-lull.wav` | Lull's full output. |
| `example-run/stimulus-nc-only.wav` | Lull with voice focus off. |
| `example-run/stimulus-focus-only.wav` | Lull with noise removal off. |
| `example-run/segments.json` | Where each part of the clip sits in time. |
| `example-run/metrics.json`, `lull-file.log` | Numbers and log from the published run. |

## Live microphone test (not validated)

The repo also has scripts that play the clip through the speakers and record the microphone with Lull off and on: `run_test.sh`, `rec.swift`, `audioctl.swift`, `summarize.py`. They are not part of the benchmark above and produce no published results.

They record whatever the room sounds like during the test, so the captures can contain speech from people nearby. Run them only where nobody else is around, and do not share the captures in the repo folder (they are git-ignored). The most recent live run failed its own checks, so the live path is unproven. A run only counts if the printed correlation is at least 0.3 and speech is clearly above the room in both takes.

## Limits

This measures Lull's offline engine on one generated clip with one voice. It does not measure the live app, meeting-app latency, or real rooms. The numbers are for Lull 0.1.0 and may change in later versions.

## Credits

Lull is by [psanders](https://github.com/psanders), MIT licensed. The logo in `docs/` comes from the Lull repository.
