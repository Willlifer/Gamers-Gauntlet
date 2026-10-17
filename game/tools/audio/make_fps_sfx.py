"""Procedural sound for the FPS duels (G62). Deterministic: the same script
always writes the same files.

    python game/tools/audio/make_fps_sfx.py            # writes game/audio/sfx/fps/*.wav + fps_sfx.json
    python game/tools/audio/make_fps_sfx.py --only shot  # names containing "shot"

Then `python game/tools/audio/web_ogg.py` for the web build's Ogg twins
(G49) and `godot --headless --path . --import`.

Gunshots are layered: a 1-2 ms click, a body (a pitch sweep down into the
chest, the "thump"), the crack (band-passed noise, fast decay), a tail
(low-passed noise, slow decay: the outdoors) and a touch of saturation.
Each class moves those knobs: a pistol is short and bright, the Desert
Eagle and the bolt rifles thump and ring, the automatics snap, the
shotgun is wide and doubled. The slingshot is a plucked band and a leather
thwip. Mechanics (mag out / in, shell, bolt, pump) are damped metal and
plastic clicks. The whizz is a narrow noise band sweeping down through
the ear; the hit marker a dry tick; the headshot a bright two-note ding;
the kill sting a short rising chord with a thump.

Every sound has 1-3 variations, <name>_<n>.wav; fps_sfx.json lists each
name, its count and measured levels. FpsAudio (src/tourney/fps/) plays
them; tools/fps_audio_check.gd checks them.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bwdsp as d  # noqa: E402

SR = d.SR
GAME = Path(__file__).resolve().parents[2]
OUT = GAME / "audio" / "sfx" / "fps"
TARGET = -16.0          # momentary K-weighted RMS, "LUFS-ish" (the pool's level)
CEIL = -1.0


# ------------------------------------------------------------------ building blocks

def t_axis(secs: float) -> np.ndarray:
    return np.arange(int(secs * SR)) / SR


def env_exp(secs: float, tau: float, attack: float = 0.0) -> np.ndarray:
    t = t_axis(secs)
    e = np.exp(-t / max(tau, 1e-4))
    if attack > 0:
        e *= np.clip(t / attack, 0.0, 1.0)
    return e


def noise(rng: np.random.Generator, secs: float) -> np.ndarray:
    return rng.standard_normal(int(secs * SR))


def bandpass(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    lo = max(20.0, lo)
    hi = min(SR * 0.49, hi)
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def lowpass(x: np.ndarray, hz: float, order: int = 2) -> np.ndarray:
    b, a = signal.butter(order, min(hz, SR * 0.49) / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def highpass(x: np.ndarray, hz: float, order: int = 2) -> np.ndarray:
    b, a = signal.butter(order, max(hz, 10.0) / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def sweep(secs: float, f0: float, f1: float, tau: float, curve: float = 3.0) -> np.ndarray:
    """A sine whose pitch falls f0 -> f1 (exponentially, `curve` fast) under an exp decay."""
    t = t_axis(secs)
    k = np.exp(-t * curve / max(tau, 1e-4))
    f = f1 + (f0 - f1) * k
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / max(tau, 1e-4))


def sat(x: np.ndarray, drive: float) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


def fit(parts: list[np.ndarray]) -> np.ndarray:
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x: np.ndarray, secs: float) -> np.ndarray:
    """`x` delayed by `secs`."""
    return np.concatenate([np.zeros(int(secs * SR)), x])


def mode(secs: float, hz: float, tau: float, phase: float = 0.0) -> np.ndarray:
    t = t_axis(secs)
    return np.sin(2 * np.pi * hz * t + phase) * np.exp(-t / max(tau, 1e-4))


def fade_out(x: np.ndarray, secs: float = 0.01) -> np.ndarray:
    n = min(len(x), int(secs * SR))
    if n > 0:
        x[-n:] *= np.linspace(1.0, 0.0, n)
    return x


# ------------------------------------------------------------------ gunshots

def gunshot(rng, *, click=1.0, thump_f=(220, 45), thump_tau=0.07, thump=1.0, crack_band=(1500, 7000), crack_tau=0.045,
            crack=1.0, tail_hz=1800, tail_tau=0.25, tail=0.6, secs=1.1, drive=2.2, double=0.0, ring=0.0):
    parts = []
    # the click: a 1.5 ms burst of bright noise
    c = noise(rng, 0.004) * env_exp(0.004, 0.0012)
    parts.append(highpass(c, 2500.0) * 1.6 * click)
    # the body: the pressure wave into the chest
    parts.append(sweep(secs, thump_f[0], thump_f[1], thump_tau) * 1.1 * thump)
    # the crack
    cr = bandpass(noise(rng, secs), crack_band[0], crack_band[1]) * env_exp(secs, crack_tau, 0.0008)
    parts.append(cr * 0.9 * crack)
    # the tail: the shot in the open, duller and longer
    tl = lowpass(noise(rng, secs), tail_hz) * env_exp(secs, tail_tau, 0.004)
    parts.append(tl * 0.5 * tail)
    if ring > 0.0:                                   # a barrel / receiver ring
        parts.append(mode(secs, 1240.0 * rng.uniform(0.95, 1.05), 0.09) * 0.18 * ring)
        parts.append(mode(secs, 2210.0 * rng.uniform(0.95, 1.05), 0.05) * 0.1 * ring)
    x = fit(parts)
    if double > 0.0:                                 # the shotgun's second barrel of noise 6 ms later
        x = fit([x, at(x * double, 0.006 * rng.uniform(0.8, 1.2))])
    x = sat(x, drive)
    return fade_out(highpass(x, 40.0), 0.02)


def shot_pistol(rng, k):
    return gunshot(rng, thump_f=(300, 90), thump_tau=0.03, thump=0.7, crack_band=(1800, 8000), crack_tau=0.03,
                   tail_hz=2400, tail_tau=0.14, tail=0.45, secs=0.7, drive=2.0, ring=0.6)


def shot_deagle(rng, k):
    return gunshot(rng, thump_f=(240, 50), thump_tau=0.09, thump=1.3, crack_band=(900, 6000), crack_tau=0.06,
                   crack=1.2, tail_hz=1500, tail_tau=0.38, tail=0.8, secs=1.4, drive=3.0, ring=0.8)


def shot_carbine(rng, k):
    return gunshot(rng, thump_f=(320, 110), thump_tau=0.025, thump=0.6, crack_band=(2200, 9000), crack_tau=0.028,
                   crack=1.1, tail_hz=2600, tail_tau=0.12, tail=0.4, secs=0.55, drive=2.4, ring=0.4)


def shot_auto_rifle(rng, k):
    return gunshot(rng, thump_f=(260, 80), thump_tau=0.035, thump=0.8, crack_band=(1600, 8000), crack_tau=0.035,
                   crack=1.1, tail_hz=2000, tail_tau=0.16, tail=0.5, secs=0.7, drive=2.6, ring=0.5)


def shot_marksman(rng, k):
    return gunshot(rng, thump_f=(220, 55), thump_tau=0.07, thump=1.1, crack_band=(1200, 7000), crack_tau=0.05,
                   crack=1.2, tail_hz=1700, tail_tau=0.32, tail=0.75, secs=1.3, drive=2.8, ring=0.7)


def shot_sniper(rng, k):
    return gunshot(rng, thump_f=(190, 38), thump_tau=0.11, thump=1.4, crack_band=(900, 6500), crack_tau=0.07,
                   crack=1.3, tail_hz=1300, tail_tau=0.5, tail=0.9, secs=1.8, drive=3.2, ring=0.9)


def shot_shotgun(rng, k):
    return gunshot(rng, thump_f=(200, 48), thump_tau=0.09, thump=1.3, crack_band=(500, 5500), crack_tau=0.08,
                   crack=1.4, tail_hz=1200, tail_tau=0.4, tail=1.0, secs=1.5, drive=3.4, double=0.7, ring=0.3)


def shot_slingshot(rng, k):
    secs = 0.5
    # the band: a plucked, inharmonic pair of modes dropping in pitch as it slackens
    x = sweep(secs, 140.0, 95.0, 0.09, curve=2.0) * 0.8 + sweep(secs, 265.0, 190.0, 0.05, curve=2.0) * 0.4
    # the leather pouch's thwip: a short bright noise band
    th = bandpass(noise(rng, 0.08), 2500.0, 9000.0) * env_exp(0.08, 0.012, 0.002)
    x = fit([x, at(th * 0.7, 0.003)])
    return fade_out(sat(x, 1.6))


# ------------------------------------------------------------------ mechanics

def click(rng, secs, hz_lo, hz_hi, tau, gain=1.0, body=0.0, body_hz=180.0):
    c = bandpass(noise(rng, secs), hz_lo, hz_hi) * env_exp(secs, tau, 0.0006)
    x = c * gain
    if body > 0:
        x = fit([x, mode(secs, body_hz, tau * 2.5) * body])
    return x


def reload_out(rng, k):
    # the mag release's catch, the magazine sliding free, the mag landing (the pistols / rifles)
    x = fit([click(rng, 0.3, 1800, 6000, 0.012, 0.9, 0.3, 240),
             at(lowpass(noise(rng, 0.09), 1400) * env_exp(0.09, 0.03, 0.01) * 0.35, 0.03),
             at(click(rng, 0.25, 300, 1600, 0.03, 0.7, 0.5, 120), 0.17)])
    return fade_out(sat(x, 1.5))


def reload_in(rng, k):
    # the fresh mag seated: a slide, a hard seat, the slide / bolt release
    x = fit([at(lowpass(noise(rng, 0.08), 1600) * env_exp(0.08, 0.03, 0.01) * 0.3, 0.0),
             at(click(rng, 0.25, 900, 4000, 0.014, 1.1, 0.6, 200), 0.06),
             at(click(rng, 0.25, 1500, 7000, 0.01, 0.9, 0.25, 320), 0.19)])
    return fade_out(sat(x, 1.6))


def shell_in(rng, k):
    # a shell thumbed into the tube: plastic on steel, then the lifter's click
    x = fit([click(rng, 0.2, 700, 3500, 0.012, 0.8, 0.4, 260),
             at(click(rng, 0.2, 2000, 7000, 0.008, 0.6), 0.07)])
    return fade_out(sat(x, 1.4))


def bolt_open(rng, k):
    # the handle lifts (a steel knock) and the bolt draws back (a scrape)
    x = fit([click(rng, 0.3, 1200, 5000, 0.012, 1.0, 0.5, 300),
             at(bandpass(noise(rng, 0.12), 800, 3000) * env_exp(0.12, 0.05, 0.015) * 0.3, 0.05)])
    return fade_out(sat(x, 1.5))


def bolt_close(rng, k):
    # the bolt runs home and the handle turns down: a scrape into a hard clack
    x = fit([bandpass(noise(rng, 0.1), 800, 3000) * env_exp(0.1, 0.04, 0.01) * 0.3,
             at(click(rng, 0.3, 900, 4500, 0.016, 1.2, 0.7, 220), 0.07)])
    return fade_out(sat(x, 1.6))


def pump_back(rng, k):
    # the fore-end racked back: a rattle of the action bars and the shell ejecting
    x = fit([bandpass(noise(rng, 0.14), 500, 2500) * env_exp(0.14, 0.05, 0.01) * 0.4,
             at(click(rng, 0.3, 700, 3500, 0.018, 1.1, 0.6, 170), 0.08),
             at(click(rng, 0.2, 2500, 8000, 0.006, 0.4), 0.11)])
    return fade_out(sat(x, 1.6))


def pump_fwd(rng, k):
    x = fit([bandpass(noise(rng, 0.12), 500, 2500) * env_exp(0.12, 0.04, 0.01) * 0.35,
             at(click(rng, 0.3, 600, 3200, 0.02, 1.3, 0.8, 150), 0.06)])
    return fade_out(sat(x, 1.7))


# ------------------------------------------------------------------ feedback

def whizz(rng, k):
    # a narrow noise band sweeping down (the Doppler of a round going past), 0.25 s
    secs = 0.3
    t = t_axis(secs)
    n = noise(rng, secs)
    f = 3600.0 * np.exp(-t * 4.0) + 900.0
    out = np.zeros_like(n)
    # a time-varying 2-pole band-pass, sample by sample via a state-variable filter
    lp = bp = 0.0
    q = 0.08
    for i in range(len(n)):
        fc = 2.0 * np.sin(np.pi * min(f[i], SR * 0.45) / SR)
        hp = n[i] - lp - q * bp
        bp += fc * hp
        lp += fc * bp
        out[i] = bp
    e = np.exp(-((t - 0.08) ** 2) / (2 * 0.035 ** 2)) * 0.9 + np.exp(-((t - 0.16) ** 2) / (2 * 0.07 ** 2)) * 0.3
    return fade_out(out * e * 0.9, 0.03)


def hitmark(rng, k):
    # a dry tick: two damped modes and a 1 ms click
    x = fit([click(rng, 0.05, 3000, 9000, 0.003, 0.9),
             mode(0.09, 1850.0, 0.02) * 0.5, mode(0.09, 3100.0, 0.012) * 0.3])
    return fade_out(x)


def headshot(rng, k):
    # a bright two-note ding: the tick, then a bell a fifth up
    x = fit([hitmark(rng, k) * 0.9,
             at(mode(0.35, 1760.0, 0.11) * 0.5 + mode(0.35, 2640.0, 0.08) * 0.35 + mode(0.35, 5280.0, 0.04) * 0.15, 0.03)])
    return fade_out(sat(x, 1.3), 0.03)


def kill(rng, k):
    # a short rising chord (A major, the loops' key) over a thump
    secs = 0.7
    notes = [220.0, 277.18, 329.63, 440.0]
    parts = [sweep(0.3, 150.0, 55.0, 0.08) * 0.8]
    for i, f in enumerate(notes):
        tone = mode(secs, f, 0.22) * 0.5 + mode(secs, f * 2.0, 0.12) * 0.2
        parts.append(at(tone * 0.5, 0.04 * i))
    x = fit(parts)
    return fade_out(sat(x, 1.4), 0.05)


SOUNDS = {
    "shot_pistol": (shot_pistol, 3), "shot_deagle": (shot_deagle, 2), "shot_carbine": (shot_carbine, 3),
    "shot_auto_rifle": (shot_auto_rifle, 3), "shot_marksman": (shot_marksman, 2), "shot_sniper": (shot_sniper, 2),
    "shot_shotgun": (shot_shotgun, 2), "shot_slingshot": (shot_slingshot, 2),
    "reload_out": (reload_out, 2), "reload_in": (reload_in, 2), "shell_in": (shell_in, 2),
    "bolt_open": (bolt_open, 1), "bolt_close": (bolt_close, 1), "pump_back": (pump_back, 1), "pump_fwd": (pump_fwd, 1),
    "whizz": (whizz, 3), "hitmark": (hitmark, 2), "headshot": (headshot, 1), "kill": (kill, 1),
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "fps_sfx.json"
    manifest = {"sounds": {}}
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
    for name, (fn, n) in SOUNDS.items():
        if args.only and args.only not in name:
            continue
        levels = []
        for k in range(1, n + 1):
            rng = np.random.default_rng(sum(ord(c) for c in name) * 31 + k)
            x = fn(rng, k)
            x = np.asarray(x, dtype=np.float64)
            x = x - x.mean()
            x = x[:, None]
            y, g = d.normalise(x, TARGET, SR, CEIL)
            d.save(OUT / f"{name}_{k}.wav", y, SR)
            levels.append({"loud": round(d.loudness(y, SR), 1), "peak": round(d.peak_db(y), 1), "secs": round(len(y) / SR, 3)})
        manifest["sounds"][name] = {"variants": n, "bus": "SFX", "levels": levels}
        print(f"{name}: {n} x {levels[0]['secs']} s, {levels[0]['loud']} dB")
    manifest_path.write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
