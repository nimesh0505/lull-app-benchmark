"""Build a 48 kHz mono stimulus and prove the lag finder on a synthetic shift."""

from __future__ import annotations

import json
import subprocess
import wave
from pathlib import Path

import numpy as np

RATE = 48_000
OUT = Path(__file__).resolve().parent


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as handle:
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())
    if width != 2:
        raise SystemExit(f"{path}: expected 16-bit, got {width * 8}")
    samples = np.frombuffer(frames, dtype="<i2").astype(np.float64) / 32768.0
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    if rate != RATE:
        raise SystemExit(f"{path}: expected {RATE} Hz, got {rate}")
    return samples


def write_wav(path: Path, samples: np.ndarray) -> None:
    clipped = np.clip(samples, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(pcm.tobytes())


def rms_db(samples: np.ndarray) -> float:
    if samples.size == 0:
        return float("-inf")
    power = float(np.mean(samples.astype(np.float64) ** 2))
    if power <= 0.0:
        return float("-inf")
    return 10.0 * np.log10(power)


def peak_db(samples: np.ndarray) -> float:
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    if peak <= 0.0:
        return float("-inf")
    return 20.0 * np.log10(peak)


def scale_to_peak(samples: np.ndarray, peak_dbfs: float) -> np.ndarray:
    peak = float(np.max(np.abs(samples)))
    if peak <= 0.0:
        raise SystemExit("cannot scale a silent clip")
    target = 10.0 ** (peak_dbfs / 20.0)
    return samples * (target / peak)


def trim_silence(samples: np.ndarray, threshold_db: float = -45.0) -> np.ndarray:
    frame = RATE // 100
    thresh = 10.0 ** (threshold_db / 20.0)
    keep = []
    for start in range(0, samples.size, frame):
        chunk = samples[start : start + frame]
        if float(np.sqrt(np.mean(chunk**2))) >= thresh:
            keep.append(start)
    if not keep:
        return samples
    begin = keep[0]
    end = min(samples.size, keep[-1] + frame)
    return samples[begin:end]


def best_lag(reference: np.ndarray, signal: np.ndarray, max_lag: int) -> tuple[int, float]:
    """Return how many samples `signal` is delayed relative to `reference`."""
    ref = reference.astype(np.float64)
    sig = signal.astype(np.float64)
    ref = ref - ref.mean()
    sig = sig - sig.mean()
    size = 1
    while size < ref.size + sig.size:
        size *= 2
    corr = np.fft.irfft(np.fft.rfft(sig, size) * np.conj(np.fft.rfft(ref, size)), size)
    lags = np.concatenate(
        [np.arange(0, max_lag + 1), np.arange(size - max_lag, size)]
    )
    window = corr[lags]
    pick = int(np.argmax(window))
    lag_index = int(lags[pick])
    lag = lag_index if lag_index <= max_lag else lag_index - size
    denom = float(np.linalg.norm(ref) * np.linalg.norm(sig))
    coeff = float(corr[lag_index] / denom) if denom > 0 else 0.0
    return lag, coeff


def prove_lag_finder() -> None:
    source = np.random.default_rng(0).standard_normal(RATE)
    shifted = np.concatenate([np.zeros(1234), source])
    lag, coeff = best_lag(source, shifted[: source.size], max_lag=RATE)
    if lag != 1234 or coeff < 0.95:
        raise SystemExit(f"lag finder failed: lag={lag} coeff={coeff}")
    print(f"lag finder check: shift 1234 samples, found {lag}, correlation {coeff:.6f}")


def main() -> None:
    prove_lag_finder()
    speech_aiff = OUT / "speech.aiff"
    speech_wav = OUT / "speech-raw.wav"
    text = (
        "This is a microphone test. One person is speaking in a clear voice. "
        "The words should stay understandable when the noise is removed."
    )
    subprocess.run(["say", "-o", str(speech_aiff), text], check=True)
    subprocess.run(
        [
            "afconvert",
            "-f",
            "WAVE",
            "-d",
            "LEI16@48000",
            "-c",
            "1",
            str(speech_aiff),
            str(speech_wav),
        ],
        check=True,
    )
    speech = trim_silence(read_wav(speech_wav))
    speech = scale_to_peak(speech, -6.0)
    quiet = scale_to_peak(speech, -26.0)

    rng = np.random.default_rng(1)
    noise = rng.standard_normal(4 * RATE)
    # One-pole lowpass so the noise is rumble and hiss, not a full-scale click train.
    alpha = 0.08
    for index in range(1, noise.size):
        noise[index] = alpha * noise[index] + (1.0 - alpha) * noise[index - 1]
    noise = scale_to_peak(noise, -18.0)

    pieces: list[tuple[str, np.ndarray]] = [
        ("room_or_silence", np.zeros(int(1.0 * RATE))),
        ("beep", 0.25 * np.sin(2 * np.pi * 1000 * np.arange(int(0.15 * RATE)) / RATE)),
        ("gap", np.zeros(int(0.35 * RATE))),
        ("speech", speech),
        ("noise", noise),
        ("speech_plus_noise", speech[: min(speech.size, noise.size)] + noise[: min(speech.size, noise.size)]),
        ("quiet_voice", quiet),
        ("tail", np.zeros(int(1.0 * RATE))),
    ]
    mix = pieces[5][1]
    mix_peak = float(np.max(np.abs(mix)))
    mix_scale = 1.0
    if mix_peak > 0.98:
        mix_scale = 0.98 / mix_peak
        pieces[5] = ("speech_plus_noise", mix * mix_scale)

    cursor = 0
    segments = []
    audio = []
    for name, data in pieces:
        segments.append(
            {
                "name": name,
                "start": cursor,
                "end": cursor + int(data.size),
                "seconds": round(data.size / RATE, 3),
                "file_rms_dbfs": None if name in {"room_or_silence", "gap", "tail"} and np.all(data == 0) else round(rms_db(data), 2),
                "file_peak_dbfs": None if np.all(data == 0) else round(peak_db(data), 2),
            }
        )
        audio.append(data)
        cursor += int(data.size)
    stimulus = np.concatenate(audio)
    write_wav(OUT / "stimulus.wav", stimulus)
    meta = {
        "sample_rate": RATE,
        "samples": int(stimulus.size),
        "seconds": round(stimulus.size / RATE, 3),
        "speech_text": text,
        "quiet_voice": "same utterance as speech, peak set 20 dB lower",
        "speech_plus_noise_scale": mix_scale,
        "note": "file_rms_dbfs is the digital playback file, not the microphone",
        "segments": segments,
    }
    (OUT / "segments.json").write_text(json.dumps(meta, indent=2))
    print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
