r"""Generate Emberfall's faction announcers with Kokoro TTS (local, CPU).

    C:\Users\leonj\Kokoro\venv\Scripts\python.exe tools\make_announcer.py

One announcer voice per faction — the player hears their OWN side's command
net, so the voice is part of faction identity the same way the palette is:

  KARVATH   am_onyx    deep, unhurried — iron and certainty
  ASHFALL   am_michael rough, plain — a foreman on a crackling wire
  AURELIA   bf_emma    clipped British — carrier flight control
  LUMINAR   af_nicole  soft, close — the arc-choir's quiet intercom

Kokoro runs on the CPU faster than realtime and its weights are Apache-2.0,
so the whole voice pass costs nothing and ships clean. Smart App Control note:
spacy is PINNED <3.8 in the Kokoro venv — 3.8's fresh .pyds get blocked by
Windows App Control on this machine, 3.7.5's reputation clears it.

The radio chain (highpass, lowpass, gentle saturation) is what makes a clean
studio voice read as COMMS: full-range TTS over battle SFX sounds like a
podcast; band-limited and slightly gritted, it sounds like the war room.
"""
import os
import numpy as np
import soundfile as sf

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "godot", "sounds", "ann")
SR = 24000

FACTIONS = {
    1: dict(voice="am_onyx",    lang="a", speed=0.95),
    2: dict(voice="am_michael", lang="a", speed=1.0),
    3: dict(voice="bf_emma",    lang="b", speed=1.0),
    4: dict(voice="af_nicole",  lang="a", speed=0.92),
}

LINES = {
    "construction": "Construction complete.",
    "unit_ready":   "Unit ready.",
    "base_attack":  "Base under attack!",
    "low_power":    "Warning. Low power.",
    "no_funds":     "Insufficient funds.",
    "unit_lost":    "Unit lost.",
    "sw_ready":     "Superweapon ready.",
    "sw_launch":    "Warning! Enemy superweapon launched!",
    "victory":      "Mission accomplished.",
    "defeat":       "Mission failed.",
}


def lowpass(x, cutoff):
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1.0 - a) * x[i] + a * acc
        y[i] = acc
    return y


def radio(x):
    x = x - lowpass(x, 180.0)              # highpass: kill the plosive thumps
    x = lowpass(lowpass(x, 4800.0), 4800.0)  # band-limit like a field wire
    x = np.tanh(x * 2.6) / np.tanh(2.6)    # gentle saturation = transmitter grit
    peak = max(np.abs(x).max(), 1e-9)
    return x * (0.92 / peak)


def main():
    from kokoro import KPipeline
    os.makedirs(OUT, exist_ok=True)
    pipes = {}
    total = 0
    for fac, cfg in FACTIONS.items():
        if cfg["lang"] not in pipes:
            pipes[cfg["lang"]] = KPipeline(lang_code=cfg["lang"],
                                           repo_id="hexgrad/Kokoro-82M")
        pipe = pipes[cfg["lang"]]
        for event, text in LINES.items():
            chunks = [np.asarray(a) for _, _, a in
                      pipe(text, voice=cfg["voice"], speed=cfg["speed"])]
            wav = radio(np.concatenate(chunks))
            # trim leading/trailing silence below -40 dB so lines fire snappily
            loud = np.abs(wav) > 0.01
            if loud.any():
                i0 = max(0, int(np.argmax(loud)) - int(0.02 * SR))
                i1 = min(len(wav), len(wav) - int(np.argmax(loud[::-1])) + int(0.06 * SR))
                wav = wav[i0:i1]
            path = os.path.join(OUT, "f%d_%s.wav" % (fac, event))
            sf.write(path, (wav * 32767).astype(np.int16), SR)
            total += 1
            print("f%d %-13s %5.2f s  %s" % (fac, event, len(wav) / SR,
                                             cfg["voice"]))
    print("wrote %d announcer lines to %s" % (total, OUT))


if __name__ == "__main__":
    main()
