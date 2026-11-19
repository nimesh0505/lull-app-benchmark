"""Measure recorded WAVs against the stimulus timeline. Prints only computed values."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

from prepare import RATE, best_lag, peak_db, read_wav, rms_db

OUT = Path(__file__).resolve().parent
BANDS = ((0, 300), (300, 3400), (3400, 8000))


def load_segments() -> list[dict]:
    meta = json.loads((OUT / "segments.json").read_text())
    return meta["segments"]


def slice_aligned(samples: np.ndarray, start: int, end: int, lag: int) -> np.ndarray:
    """Take the stimulus interval after shifting samples back by `lag`."""
    begin = start + lag
    stop = end + lag
    begin = max(0, begin)
    stop = min(samples.size, stop)
    if stop <= begin:
        return np.zeros(0)
    return samples[begin:stop]


def band_rms(samples: np.ndarray) -> dict[str, float]:
    if samples.size < 256:
        return {}
    window = np.hanning(samples.size)
    spectrum = np.fft.rfft(samples * window)
    power = (np.abs(spectrum) ** 2) / np.sum(window**2)
    freqs = np.fft.rfftfreq(samples.size, 1.0 / RATE)
    total = float(np.sum(power))
    result = {}
    for low, high in BANDS:
        band = float(np.sum(power[(freqs >= low) & (freqs < high)]))
        result[f"{low}-{high}Hz_share"] = round(band / total, 4) if total > 0 else 0.0
    return result


def describe(name: str, samples: np.ndarray, lag: int, coeff: float) -> dict:
    segments = load_segments()
    rows = []
    for segment in segments:
        piece = slice_aligned(samples, segment["start"], segment["end"], lag)
        row = {
            "segment": segment["name"],
            "rms_dbfs": round(rms_db(piece), 2),
            "peak_dbfs": round(peak_db(piece), 2),
            "samples": int(piece.size),
        }
        row.update(band_rms(piece))
        rows.append(row)
    return {
        "name": name,
        "seconds": round(samples.size / RATE, 3),
        "whole_rms_dbfs": round(rms_db(samples), 2),
        "whole_peak_dbfs": round(peak_db(samples), 2),
        "lag_samples_vs_reference": lag,
        "lag_ms_vs_reference": round(1000.0 * lag / RATE, 2),
        "correlation_vs_reference": round(coeff, 4),
        "segments": rows,
    }


def align_to(reference: np.ndarray, signal: np.ndarray) -> tuple[int, float]:
    length = min(reference.size, signal.size)
    return best_lag(reference[:length], signal[:length], max_lag=3 * RATE)


def main() -> None:
    stimulus = read_wav(OUT / "stimulus.wav")
    reports = []
    paths = sys.argv[1:]
    if not paths:
        raise SystemExit("usage: measure.py <wav> [<wav> ...]")
    for raw in paths:
        path = Path(raw)
        samples = read_wav(path)
        lag, coeff = align_to(stimulus, samples)
        reports.append(describe(path.name, samples, lag, coeff))
    text = json.dumps(reports, indent=2)
    print(text)
    (OUT / "metrics.json").write_text(text)


if __name__ == "__main__":
    main()
