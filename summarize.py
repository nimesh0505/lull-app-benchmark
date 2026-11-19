"""Write RESULTS.txt from metrics.json and the wavs. No estimated labels."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

from prepare import read_wav, rms_db

OUT = Path(__file__).resolve().parent
ALIGN_MIN = 0.3


def frame_db(samples: np.ndarray) -> np.ndarray:
    frame = 960  # 20 ms at 48 kHz
    values = []
    for start in range(0, samples.size - frame + 1, frame):
        power = float(np.mean(samples[start : start + frame] ** 2))
        if power > 0:
            values.append(10.0 * np.log10(power))
    return np.array(values)


def main() -> None:
    volume_used = sys.argv[1]
    volume_before = sys.argv[2]
    reports = json.loads((OUT / "metrics.json").read_text())
    by_name = {item["name"]: item for item in reports}
    lines = [
        f"output_volume_during_playback {volume_used}",
        f"output_volume_before_test {volume_before}",
        "playback_device MacBook Air Speakers",
        "voice macOS say, system default voice, played out of the speakers",
        "not_a_person_in_the_room true",
        "takes two separate plays of stimulus.wav, not one simultaneous recording",
        f"alignment_accepted_when_correlation_at_least {ALIGN_MIN}",
        "",
    ]
    for item in reports:
        lines.append(
            f"{item['name']} seconds {item['seconds']} whole_rms_dbfs {item['whole_rms_dbfs']} "
            f"whole_peak_dbfs {item['whole_peak_dbfs']} lag_ms {item['lag_ms_vs_reference']} "
            f"correlation {item['correlation_vs_reference']}"
        )
    lines.append("")
    names = [
        "mic-off.wav",
        "mic-on.wav",
        "mic-offline.wav",
        "mic-offline-bypass.wav",
        "stimulus-lull.wav",
    ]
    header = "segment" + "".join(f" {name.replace('.wav', ''):>22}" for name in names)
    lines.append(header)
    segments = by_name["mic-off.wav"]["segments"]
    for index, segment in enumerate(segments):
        row = f"{segment['segment']:<20}"
        for name in names:
            value = by_name[name]["segments"][index]["rms_dbfs"]
            row += f" {value:22.2f}"
        lines.append(row)
    lines.append("")
    off_corr = by_name["mic-off.wav"]["correlation_vs_reference"]
    on_corr = by_name["mic-on.wav"]["correlation_vs_reference"]
    offline_corr = by_name["mic-offline.wav"]["correlation_vs_reference"]
    lines.append(f"mic_off_correlation {off_corr}")
    lines.append(f"mic_on_correlation {on_corr}")
    lines.append(f"mic_offline_correlation {offline_corr}")
    comparable_on = off_corr >= ALIGN_MIN and on_corr >= ALIGN_MIN
    comparable_offline = off_corr >= ALIGN_MIN and offline_corr >= ALIGN_MIN
    lines.append(f"compare_on_vs_off {str(comparable_on).lower()}")
    lines.append(f"compare_offline_vs_off {str(comparable_offline).lower()}")
    if comparable_on or comparable_offline:
        lines.append("delta_db = other_rms_dbfs - mic_off_rms_dbfs (negative means quieter)")
        for index, segment in enumerate(segments):
            base = segment["rms_dbfs"]
            parts = [segment["segment"]]
            if comparable_on:
                parts.append(
                    f"on_minus_off {by_name['mic-on.wav']['segments'][index]['rms_dbfs'] - base:.2f}"
                )
            if comparable_offline:
                parts.append(
                    "offline_minus_off "
                    f"{by_name['mic-offline.wav']['segments'][index]['rms_dbfs'] - base:.2f}"
                )
            lines.append(" ".join(parts))
    lines.append("")
    # Bypass is the same file length as mic-off, sample aligned, no lag.
    off = read_wav(OUT / "mic-off.wav")
    bypass = read_wav(OUT / "mic-offline-bypass.wav")
    count = min(off.size, bypass.size)
    diff = bypass[:count].astype(np.float64) - off[:count].astype(np.float64)
    lines.append(
        f"bypass_vs_mic_off samples {count} max_abs_diff {float(np.max(np.abs(diff))):.6f} "
        f"rms_diff_dbfs {rms_db(diff):.2f}"
    )
    lines.append("")
    lines.append("frame_median_dbfs is the median 20 ms RMS inside the aligned segment")
    if comparable_on and comparable_offline:
        # Re-slice using the lags already chosen.
        bounds = {
            item["name"]: item
            for item in json.loads((OUT / "segments.json").read_text())["segments"]
        }

        def aligned(path: str, name: str, lag: int) -> np.ndarray:
            data = read_wav(OUT / path)
            seg = bounds[name]
            start = max(0, seg["start"] + lag)
            end = min(data.size, seg["end"] + lag)
            return data[start:end]

        for seg in segments:
            if seg["segment"] not in {"room_or_silence", "speech", "noise", "speech_plus_noise", "quiet_voice"}:
                continue
            for label, path, report_name in (
                ("off", "mic-off.wav", "mic-off.wav"),
                ("on", "mic-on.wav", "mic-on.wav"),
                ("offline", "mic-offline.wav", "mic-offline.wav"),
            ):
                lag = by_name[report_name]["lag_samples_vs_reference"]
                values = frame_db(aligned(path, seg["segment"], lag))
                median = float(np.median(values)) if values.size else float("nan")
                lines.append(f"{seg['segment']} {label} frame_median_dbfs {median:.2f} frames {values.size}")
    log = OUT / "lull-run.log"
    lines.append("")
    lines.append("lull_run_log:")
    if log.exists():
        lines.extend(log.read_text(errors="replace").splitlines())
    text = "\n".join(lines) + "\n"
    (OUT / "RESULTS.txt").write_text(text)
    print(text)


if __name__ == "__main__":
    main()
