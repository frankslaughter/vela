"""Makes stage2/boat-noise.wav: three minutes of stand-in boat noise for the Stage 2 noise test.

The plan's fallback recipe (prototype-plan.md, section 2): brown noise below 300 Hz for the
engine, pink noise for the wind. The wind rises and falls slowly, as gusts do. The file loops
without a click, so a player set to repeat can run it for as long as the test takes.

Needs numpy. From the project folder:  server/.venv/bin/python stage2/make_noise.py
"""
import wave
from pathlib import Path

import numpy as np

RATE = 48000
SECONDS = 180
ENGINE_SHARE = 0.75  # of the mix, by amplitude
WIND_SHARE = 0.45

rng = np.random.default_rng(2026)
n = RATE * SECONDS
freqs = np.fft.rfftfreq(n, 1 / RATE)


def shaped(curve: np.ndarray) -> np.ndarray:
    """Noise with the given amplitude at each frequency. It repeats exactly after n samples."""
    spectrum = curve * np.exp(2j * np.pi * rng.random(len(freqs)))
    wave_ = np.fft.irfft(spectrum, n)
    return wave_ / np.sqrt(np.mean(wave_**2))


safe = np.maximum(freqs, 1.0)

# Engine: brown noise (amplitude falls as 1/f) from 25 Hz, cut off steeply above 300 Hz.
engine_curve = (1 / safe) * (freqs >= 25) / np.sqrt(1 + (freqs / 300) ** 8)
engine = shaped(engine_curve)

# Wind: pink noise (amplitude falls as 1/sqrt(f)) from 80 Hz to 9 kHz.
wind_curve = (1 / np.sqrt(safe)) * (freqs >= 80) * (freqs <= 9000)
wind = shaped(wind_curve)

# Gusts: the wind swells and drops by a few dB over 7 to 30 seconds. Whole numbers of cycles, so it loops.
t = np.arange(n) / RATE
gust_db = 2.0 * np.sin(2 * np.pi * 6 * t / SECONDS) + 1.5 * np.sin(2 * np.pi * 13 * t / SECONDS + 1.0) \
    + 1.0 * np.sin(2 * np.pi * 25 * t / SECONDS + 2.0)
wind = wind * 10 ** (gust_db / 20)

mix = ENGINE_SHARE * engine + WIND_SHARE * wind
mix = mix / np.max(np.abs(mix)) * 0.89  # 1 dB below full scale

out = Path(__file__).with_name("boat-noise.wav")
with wave.open(str(out), "wb") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(RATE)
    f.writeframes((mix * 32767).astype("<i2").tobytes())
print(f"Wrote {out} ({SECONDS} s)")
