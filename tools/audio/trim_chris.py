"""Trim the author's three "Chris" recordings into game-ready music loops.

  python tools/audio/trim_chris.py

Reads the originals from game/audio/source/chris/ (kept untouched; a
.gdignore keeps Godot from importing them) and writes
game/audio/music/chris/{chris_full,chris_loop_a,chris_loop_b}.wav:
  - mono (the takes are dual-mono), 48 kHz, 16-bit
  - DC removed, a gentle 30 Hz high-pass
  - the lead silence cut to 10 ms before the first sound
  - the whole take kept as the loop (each was played to repeat): the seam
    is the point in its last half second whose waveform best matches the
    head, crossfaded (tail into head, 40 ms) so it repeats without a click
  - levelled to -20 dB RMS (the project's music layers, layers.json
    k_rms_db) with the peak held under -1 dBFS
Prints what it did per file.
"""
import json
import os
import wave

import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "game", "audio", "source", "chris")
DST = os.path.join(ROOT, "game", "audio", "music", "chris")
JOBS = [
    ("Full Chris.wav", "chris_full"),
    ("Repeat Chris.wav", "chris_loop_a"),
    ("Repeat Chris 2.wav", "chris_loop_b"),
]
TARGET_RMS_DB = -20.0
PEAK_DB = -1.0
XFADE = 0.04


def load(p):
    w = wave.open(p)
    sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
    a = np.frombuffer(w.readframes(n), np.int16).astype(np.float64) / 32768.0
    return a.reshape(-1, ch).mean(1), sr


def highpass(x, sr, fc=30.0):
    # one-pole high-pass (also removes DC)
    rc = 1.0 / (2 * np.pi * fc)
    k = rc / (rc + 1.0 / sr)
    y = np.empty_like(x)
    prev_x = prev_y = 0.0
    for i, v in enumerate(x):
        prev_y = k * (prev_y + v - prev_x)
        prev_x = v
        y[i] = prev_y
    return y


def first_sound(x, sr, db=-48.0):
    blk = int(sr * 0.005)
    th = 10 ** (db / 20)
    for i in range(0, len(x) - blk, blk):
        if np.sqrt(np.mean(x[i:i + blk] ** 2)) > th:
            return max(0, i - int(sr * 0.01))
    return 0


def best_seam(x, sr):
    """The loop length in the take's last half second whose next 50 ms best
    matches the head's first 50 ms (waveform correlation)."""
    w = int(sr * 0.05)
    n = int(sr * XFADE)
    h = x[:w]
    best, bl = -2.0, len(x) - n
    for L in range(len(x) - int(sr * 0.5), len(x) - max(w, n)):
        s = x[L:L + w]
        c = float(np.dot(h, s) / (np.linalg.norm(h) * np.linalg.norm(s) + 1e-12))
        if c > best:
            best, bl = c, L
    return bl, best


def main():
    os.makedirs(DST, exist_ok=True)
    report = {}
    for src, name in JOBS:
        x, sr = load(os.path.join(SRC, src))
        x = highpass(x, sr)
        s0 = first_sound(x, sr)
        x = x[s0:]
        L, c_wave = best_seam(x, sr)
        n = int(sr * XFADE)
        # loop body x[:L]; fold the next n samples (the tail past L) into the head
        body = x[:L].copy()
        tail = x[L:L + n]
        ramp = np.linspace(0.0, 1.0, len(tail))
        body[:len(tail)] = body[:len(tail)] * ramp + tail * (1.0 - ramp)
        rms = np.sqrt(np.mean(body ** 2))
        g = 10 ** (TARGET_RMS_DB / 20) / rms
        peak = np.max(np.abs(body)) * g
        if peak > 10 ** (PEAK_DB / 20):
            g *= 10 ** (PEAK_DB / 20) / peak
        body *= g
        out = os.path.join(DST, name + ".wav")
        w = wave.open(out, "wb")
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(body, -1, 1) * 32767).astype(np.int16).tobytes())
        w.close()
        info = {"from": src, "lead_cut_s": round(s0 / sr, 3), "loop_s": round(L / sr, 4), "seam_corr": round(c_wave, 3), "gain_db": round(float(20 * np.log10(g)), 2),
                "rms_db": round(float(20 * np.log10(np.sqrt(np.mean(body ** 2)))), 2), "peak_db": round(float(20 * np.log10(np.max(np.abs(body)))), 2)}
        report[name] = info
        print(name, info)
    with open(os.path.join(DST, "chris.json"), "w") as f:
        json.dump(report, f, indent=1)


if __name__ == "__main__":
    main()
