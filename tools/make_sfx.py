r"""Synthesise Emberfall's combat sound effects.

    python tools\make_sfx.py            # writes godot\sounds\*.wav
    python tools\make_sfx.py --measure  # just report what is there now

WHY REPLACE THEM
----------------
Measured, the old set was one sound wearing eight costumes. Every file — rifle,
cannon, flak, rocket, both explosions and the superweapon — had a spectral
centroid within a few hundred hertz of 5 kHz, and carried 1-14% of its energy
below 200 Hz. That is the signature of a bright noise burst with an envelope on
it. A cannon has almost the opposite shape: most of its energy under 200 Hz and
a centroid down around 400-700 Hz. They were also all 22 kHz mono, and several
were far too short to have a tail (the cannon was 0.25 s).

So these are built the way real weapon effects are layered:

  BODY      a pitch-swept low oscillator — the boom, and where the weight lives
  TRANSIENT a few-millisecond click — the crack that makes it read as a firing
            rather than a rumble, and what carries over small speakers
  NOISE     band-filtered noise, enveloped — muzzle blast, debris, texture
  TAIL      a long decaying low rumble, slightly reverberated, on the big ones

Everything is numpy: no samples to license, no external DSP dependency, and the
whole set regenerates in a couple of seconds if the mix needs retuning.
"""
import argparse
import os
import struct
import sys
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "godot", "sounds")
RNG = np.random.default_rng(7)


# ------------------------------------------------------------------ helpers

def env(n, attack, decay, power=2.0):
    """Percussive envelope: near-instant rise, exponential fall."""
    a = max(1, int(SR * attack))
    e = np.ones(n)
    e[:a] = np.linspace(0.0, 1.0, a)
    t = np.linspace(0.0, 1.0, n - a)
    e[a:] = np.exp(-t * decay) * (1.0 - t) ** power
    return np.clip(e, 0.0, None)


def sweep(n, f0, f1, curve=3.0):
    """Oscillator whose pitch falls from f0 to f1 — the classic boom."""
    t = np.linspace(0.0, 1.0, n)
    f = f1 + (f0 - f1) * np.exp(-t * curve)
    phase = np.cumsum(2.0 * np.pi * f / SR)
    return np.sin(phase)


def lowpass(x, cutoff):
    """One-pole low-pass. Cheap, and the right tool for shaping noise."""
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1.0 - a) * x[i] + a * acc
        y[i] = acc
    return y


def lowpass2(x, cutoff):
    """Two cascaded one-poles (12 dB/oct).

    One pole was not enough to tame these. The first pass of the new set moved
    the low-end the right way (the cannon went 14.5% -> 56.5% under 200 Hz) but
    the CENTROID rose on half the voices — an explosion measured 6.6 kHz, which
    is fizz, not blast. A gentle 6 dB slope leaves too much of the debris layer
    sitting on top of the body.
    """
    return lowpass(lowpass(x, cutoff), cutoff)


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandnoise(n, lo, hi):
    z = RNG.normal(size=n)
    return highpass(lowpass(z, hi), lo)


def reverb(x, seconds=0.9, mix=0.35):
    """Convolve with decaying noise — turns a thump into a thump in a valley."""
    m = int(SR * seconds)
    ir = RNG.normal(size=m) * np.exp(-np.linspace(0.0, 6.0, m))
    ir = lowpass(ir, 1800.0)
    wet = np.convolve(x, ir)[:len(x)]
    wet /= max(np.abs(wet).max(), 1e-9)
    return (1.0 - mix) * x + mix * wet


def finish(x, peak=0.95):
    x = np.nan_to_num(x)
    # soft clip so the transients stay punchy without splitting
    x = np.tanh(x * 1.25)
    x /= max(np.abs(x).max(), 1e-9)
    return x * peak


def write(name, x):
    x = finish(x)
    data = (x * 32767.0).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    w = wave.open(path, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(data.tobytes())
    w.close()
    return path, len(x) / float(SR)


# ------------------------------------------------------------------ voices

def rifle():                       # shot_bullet — sharp crack, little weight
    n = int(SR * 0.24)
    crack = bandnoise(n, 600, 5200) * env(n, 0.0004, 26.0, 2.6)
    snap = bandnoise(n, 2000, 8000) * env(n, 0.0001, 90.0, 1.0) * 0.5
    body = sweep(n, 240, 90, 9.0) * env(n, 0.0008, 30.0) * 0.7
    return lowpass2(crack * 0.9 + snap + body, 6500.0)


def cannon():                      # shot_cannon — the heavy one
    n = int(SR * 1.05)
    body = sweep(n, 190, 42, 5.0) * env(n, 0.002, 5.0, 1.4) * 1.5
    sub = sweep(n, 90, 28, 3.0) * env(n, 0.004, 3.2, 1.2) * 1.1
    blast = bandnoise(n, 120, 3200) * env(n, 0.001, 11.0, 2.0) * 0.8
    crack = bandnoise(n, 1500, 6000) * env(n, 0.0002, 70.0, 1.0) * 0.32
    tail = lowpass(RNG.normal(size=n), 260.0) * env(n, 0.02, 3.0, 1.0) * 0.5
    mix = lowpass2(body + sub + blast + crack + tail, 3800.0)
    return reverb(mix, 1.0, 0.30)


def flak():                        # shot_flak — quick mid-weight thump
    n = int(SR * 0.42)
    body = sweep(n, 330, 95, 7.0) * env(n, 0.001, 13.0, 1.6) * 1.2
    blast = bandnoise(n, 350, 5200) * env(n, 0.0006, 22.0, 2.0) * 0.75
    snap = bandnoise(n, 1800, 7000) * env(n, 0.0002, 80.0) * 0.22
    return lowpass2(body + blast + snap, 5200.0)


def rocket():                      # shot_rocket — ignition, then departure
    n = int(SR * 0.85)
    t = np.linspace(0.0, 1.0, n)
    ign = bandnoise(n, 200, 6000) * env(n, 0.002, 16.0, 1.4) * 0.9
    # the whoosh: noise whose band climbs as the motor leaves
    z = RNG.normal(size=n)
    hiss = highpass(lowpass(z, 1800.0), 300.0) * (0.25 + 0.75 * t) \
        * np.exp(-t * 2.2) * 0.7
    body = sweep(n, 150, 60, 4.0) * env(n, 0.003, 6.0) * 1.1
    return lowpass2(ign * 0.8 + hiss + body, 4400.0)


def arc():                         # arc_zap — Luminar electrical discharge
    n = int(SR * 0.45)
    t = np.linspace(0.0, 1.0, n)
    buzz = np.sign(np.sin(2.0 * np.pi * 118.0 * t * SR / SR * 1.0
                          + 9.0 * np.sin(2.0 * np.pi * 47.0 * t)))
    crackle = bandnoise(n, 1200, 12000) * (RNG.random(n) < 0.35)
    e = env(n, 0.0005, 14.0, 1.6)
    body = sweep(n, 400, 150, 8.0) * e * 0.6
    return lowpass2(buzz * e * 0.35 + crackle * e * 0.55 + body, 7200.0)


def expl(size):                    # expl_small / expl_big
    if size == "small":
        n, f0, f1, dec, rv = int(SR * 0.95), 150, 44, 6.0, 0.9
    else:
        n, f0, f1, dec, rv = int(SR * 2.3), 95, 26, 3.0, 1.6
    body = sweep(n, f0, f1, 4.0) * env(n, 0.002, dec, 1.3) * 1.6
    sub = sweep(n, f1 * 0.7, f1 * 0.45, 2.2) * env(n, 0.006, dec * 0.6) * 1.2
    punch = bandnoise(n, 90, 2600) * env(n, 0.001, dec * 2.2, 2.0) * 0.9
    debris = bandnoise(n, 700, 4200) * env(n, 0.004, dec * 0.9, 3.0) * 0.26
    rumble = lowpass(RNG.normal(size=n), 170.0) * env(n, 0.03, dec * 0.5, 0.9) * 0.8
    cut = 3400.0 if size == "small" else 2600.0
    return reverb(lowpass2(body + sub + punch + debris + rumble, cut), rv, 0.38)


def sw_boom():                     # superweapon — the biggest thing in the game
    n = int(SR * 3.2)
    body = sweep(n, 78, 20, 2.2) * env(n, 0.004, 2.1, 1.1) * 1.8
    sub = sweep(n, 42, 16, 1.4) * env(n, 0.01, 1.5, 0.9) * 1.4
    punch = bandnoise(n, 70, 2200) * env(n, 0.001, 6.0, 1.8) * 0.9
    debris = bandnoise(n, 500, 3600) * env(n, 0.01, 3.0, 2.6) * 0.28
    rumble = lowpass(RNG.normal(size=n), 130.0) * env(n, 0.05, 1.4, 0.7) * 1.0
    return reverb(lowpass2(body + sub + punch + debris + rumble, 2200.0), 2.2, 0.44)


def crawler():                     # dep_crawler — a mobile base rolling out
    """Heavy diesel catching, then settling into a lope, with a track clank.

    The four MCVs had no entry in the deployment table and fell through to the
    generic vehicle sound, so the biggest thing a player can build left the
    factory sounding like a scout car.
    """
    n = int(SR * 1.6)
    t = np.linspace(0.0, 1.0, n)
    # firing pulses slowing from a fast crank to an idle lope
    rate = 13.0 - 5.5 * t
    ph = np.cumsum(2.0 * np.pi * rate / SR)
    pulse = (np.sin(ph) > 0.55).astype(float)
    diesel = lowpass(pulse * RNG.normal(size=n), 260.0) * 1.6
    body = sweep(n, 62, 34, 2.0) * (0.35 + 0.65 * np.exp(-t * 1.2)) * 1.1
    start = bandnoise(n, 150, 2400) * env(n, 0.004, 9.0, 1.6) * 0.7
    clank = bandnoise(n, 900, 5200) * env(n, 0.0006, 40.0, 1.2) * 0.35
    return lowpass2(diesel + body + start + clank, 3000.0)


VOICES = {
    "dep_crawler": crawler,
    "shot_bullet": rifle,
    "shot_cannon": cannon,
    "shot_flak": flak,
    "shot_rocket": rocket,
    "arc_zap": arc,
    "expl_small": lambda: expl("small"),
    "expl_big": lambda: expl("big"),
    "sw_boom": sw_boom,
}


# ------------------------------------------------------------------ report

def measure(path):
    w = wave.open(path, "rb")
    n, sr, ch = w.getnframes(), w.getframerate(), w.getnchannels()
    a = np.frombuffer(w.readframes(n), dtype=np.int16).astype(float) / 32768.0
    w.close()
    if ch == 2:
        a = a.reshape(-1, 2).mean(1)
    sp = np.abs(np.fft.rfft(a * np.hanning(len(a))))
    fr = np.fft.rfftfreq(len(a), 1.0 / sr)
    cen = float((sp * fr).sum() / max(sp.sum(), 1e-9))
    low = float(sp[fr < 200].sum() / max(sp.sum(), 1e-9))
    return sr, n / float(sr), cen, low


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--measure", action="store_true")
    a = ap.parse_args()
    print("%-13s %-8s %-8s %-11s %s" % ("sound", "rate", "length",
                                        "centroid", "energy <200Hz"))
    for name, fn in VOICES.items():
        path = os.path.join(OUT, name + ".wav")
        if not a.measure:
            path, _dur = write(name, fn())
        if os.path.exists(path):
            sr, dur, cen, low = measure(path)
            print("%-13s %5d Hz %6.2f s %7.0f Hz %9.1f%%"
                  % (name, sr, dur, cen, low * 100.0))
