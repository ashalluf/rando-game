"""Engine voices for EngineAudio (scripts/vehicles/engine_audio.gd), built in code.

The network policy of the sessions that made this game blocks Freesound, OpenGameArt and Wikimedia,
and no CC0 engine recording could be found anywhere it could reach, so the engines are SYNTHESISED
here, offline, the way an engine actually makes its sound - not as the runtime's sawtooth:

* every cylinder FIRES once per two crank revolutions, at its place in the firing order (an inline
  four even, a cross-plane V8 even at the crank but alternating banks L R L L R L R R, so the two
  exhausts get uneven pulse trains - the burble; a 45-degree V-twin at 0 and 315 degrees);
* each firing is an exhaust PULSE: a sharp pressure step that rings the pipe (a damped low
  resonance) plus a burst of broadband gas noise, its strength varying cylinder to cylinder (a
  fixed per-cylinder spread, which is the engine's lope at the cycle rate) and cycle to cycle;
* the pulse train runs through each bank's PIPE (a feedback comb at the pipe's round trip) and the
  MUFFLER (low-pass), and the banks are summed; diesels add the combustion KNOCK (a hard high
  click per firing, the clatter), a big one adds the cooling fan and turbo hiss as noise;
* each loop is a whole number of engine cycles and every random number is drawn per cycle and
  repeated, so the excitation is exactly periodic; the filters are run over three periods and the
  middle one kept, so the loop has no seam.

Per profile: idle, three on-load loops (low, mid, high rpm) and one coasting (off-load) loop at mid
rpm. EngineAudio crossfades the on-load ladder by rpm and pitches each loop by rpm / its rpm, and
fades toward the coasting loop as the throttle lifts. Plus a turbo whistle loop, a blow-off valve
one-shot and the reverse beeper (which IS a synthetic tone on a real truck).

A recording can replace any of these later: same file name, re-measure its loudness for
Sfx.SAMPLE_LOUDNESS_DB, and the rpm it was recorded at goes in EngineAudio.PROFILES.

    python3 tools/engine_audio.py            # writes assets/audio/eng_*.ogg, prints the loudness table
    python3 tools/engine_audio.py --wav DIR  # also writes .wav copies to listen to

Needs numpy, scipy and soundfile (pip install numpy scipy soundfile).
"""
import os
import sys

import numpy as np
import soundfile as sf
from scipy.signal import butter, lfilter, sosfilt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
SR = 32000
LOOP_SECONDS = 1.8  # about this long; a whole number of engine cycles

# Firing within the 720-degree cycle (degrees) and the bank each cylinder exhausts into.
LAYOUTS = {
    "i4": ([0, 180, 360, 540], [0, 0, 0, 0]),
    # Cross-plane V8: even firing, banks L R L L R L R R (the burble).
    "v8": ([0, 90, 180, 270, 360, 450, 540, 630], [0, 1, 0, 0, 1, 0, 1, 1]),
    "i6": ([0, 120, 240, 360, 480, 600], [0, 0, 0, 1, 1, 1]),
    "v12": ([i * 60 for i in range(12)], [i % 2 for i in range(12)]),
    "vtwin": ([0, 315], [0, 0]),
}

# Profiles. rpm: idle and the three on-load loops (the coasting loop is at the mid rpm).
# pipe: each bank's pipe resonance (Hz, the comb's fundamental) and feedback; ring: the pulse's
# own ring (Hz) and decay (ms); muffler: low-pass (Hz); noise: gas noise share; knock: diesel click
# share; spread: per-cylinder strength spread; jitter: cycle-to-cycle spread; hiss: fan / turbo
# noise bed share; harsh: how much the pulse sharpens with rpm (more high harmonics revving).
PROFILES = {
    # A small four: sedans, hatchbacks, crossovers, minivans, taxis, vans.
    "four": dict(layout="i4", rpm=[800, 2200, 3900, 6000], pipe=[(410, 0.55)], ring=(170, 2.6),
                 muffler=1900, noise=0.32, knock=0.0, spread=0.10, jitter=0.07, hiss=0.03, harsh=0.6,
                 sub=0.10),
    # A big American V8: pickups, SUVs, the muscle car, the police cruiser.
    "v8": dict(layout="v8", rpm=[650, 1800, 3300, 5600], pipe=[(150, 0.62), (178, 0.6)], ring=(85, 4.2),
               muffler=1150, noise=0.26, knock=0.0, spread=0.16, jitter=0.08, hiss=0.02, harsh=0.5,
               sub=0.35),
    # A truck diesel (straight six): box trucks, semis, garbage and tow trucks, fire engines.
    "diesel": dict(layout="i6", rpm=[650, 1200, 1750, 2300], pipe=[(120, 0.6), (131, 0.55)], ring=(70, 5.0),
                   muffler=950, noise=0.22, knock=0.55, spread=0.12, jitter=0.10, hiss=0.05, harsh=0.35,
                   sub=0.2),
    # The city bus's rear diesel: deeper, more muffled, a big fan.
    "bus": dict(layout="i6", rpm=[600, 1100, 1550, 2000], pipe=[(95, 0.62), (104, 0.58)], ring=(58, 6.0),
                muffler=700, noise=0.2, knock=0.35, spread=0.10, jitter=0.09, hiss=0.08, harsh=0.25,
                sub=0.2),
    # A V12 supercar: the exotics.
    "v12": dict(layout="v12", rpm=[1000, 3000, 5500, 8400], pipe=[(560, 0.5), (610, 0.5)], ring=(240, 1.8),
                muffler=3400, noise=0.3, knock=0.0, spread=0.06, jitter=0.05, hiss=0.03, harsh=0.8,
                sub=0.05),
    # A V-twin, for the motorcycles to come.
    "moto": dict(layout="vtwin", rpm=[1000, 2600, 4600, 7400], pipe=[(230, 0.5)], ring=(110, 3.0),
                 muffler=2100, noise=0.35, knock=0.0, spread=0.06, jitter=0.07, hiss=0.02, harsh=0.6,
                 sub=0.0),
}


def _periodic(gen, period, reps=3):
    """Runs `gen(n)` (a periodic excitation of `period` samples, repeated) through its filters
    over `reps` periods and keeps the middle one: a loop with no seam."""
    full = gen(period, reps)
    return full[period:2 * period]


def engine(name, prof, rpm, load, seed):
    rng = np.random.default_rng(seed)
    angles, banks = LAYOUTS[prof["layout"]]
    cycle = 120.0 / rpm  # seconds per 720 degrees
    n_cycles = max(4, int(round(LOOP_SECONDS / cycle)))
    period = int(round(n_cycles * cycle * SR))
    nb = max(banks) + 1
    cyl_gain = 1.0 + prof["spread"] * rng.standard_normal(len(angles))
    jit = 1.0 + prof["jitter"] * rng.standard_normal((n_cycles, len(angles)))
    tim = 0.012 * rng.standard_normal((n_cycles, len(angles)))  # timing scatter, degrees-ish share
    r = (rpm - prof["rpm"][0]) / float(prof["rpm"][3] - prof["rpm"][0])
    ring_f, ring_ms = prof["ring"]
    ring_f *= 1.0 + 0.35 * r
    tau = ring_ms / 1000.0 * (1.0 - 0.35 * r)
    sharp = 1.0 + prof["harsh"] * r * 2.0
    plen = int(SR * min(cycle / len(angles) * 2.5, tau * 8 + 0.004))
    t = np.arange(plen) / SR
    # Load: on-load pulses are full and noisy; coasting ones are soft and darker.
    amp = 0.35 + 0.65 * load
    noise_share = prof["noise"] * (0.5 + 0.8 * load)

    noise_bank = rng.standard_normal(period)

    def gen(per, reps):
        out = np.zeros(per * reps)
        exc = np.zeros((nb, per))
        knock = np.zeros(per)
        for c in range(n_cycles):
            for k, a in enumerate(angles):
                pos = (c + (a / 720.0) + tim[c, k] / len(angles)) * cycle
                i0 = int(pos * SR) % per
                g = amp * cyl_gain[k] * jit[c, k]
                env = np.exp(-t / tau)
                # The pressure step's ring plus gas noise, sharpened as it revs.
                ring = np.sin(2 * np.pi * ring_f * t) * env
                step = np.exp(-t / (tau * 0.35)) * sharp
                nz = rng.standard_normal(plen) * np.exp(-t / (tau * 0.8)) * noise_share * 1.6
                p = g * (ring + 0.6 * step + nz)
                idx = (i0 + np.arange(plen)) % per
                np.add.at(exc[banks[k]], idx, p)
                if prof["knock"] > 0:
                    kl = int(SR * 0.004)
                    kt = np.arange(kl) / SR
                    click = rng.standard_normal(kl) * np.exp(-kt / 0.0009) * prof["knock"] * g
                    np.add.at(knock, (i0 + int(SR * 0.0015) + np.arange(kl)) % per, click)
        for b in range(nb):
            x = np.tile(exc[b], reps)
            f0, fb = prof["pipe"][min(b, len(prof["pipe"]) - 1)]
            d = max(2, int(round(SR / f0)))
            # Pipe: a feedback comb at the round trip, then the muffler.
            a_coef = np.zeros(d + 1)
            a_coef[0] = 1.0
            a_coef[d] = -fb
            y = lfilter([1.0], a_coef, x)
            out += y
        out = sosfilt(butter(3, prof["muffler"] * (0.75 + 0.5 * load) / (SR / 2), "low", output="sos"), out)
        out = sosfilt(butter(2, 30.0 / (SR / 2), "high", output="sos"), out)
        if prof["knock"] > 0:
            kk = sosfilt(butter(2, [1000 / (SR / 2), 3500 / (SR / 2)], "band", output="sos"), np.tile(knock, reps))
            out += kk * np.std(out) * 1.6 / max(np.std(kk), 1e-9) * prof["knock"] * (1.0 - 0.55 * load)
        # A sub-cycle lope: the per-cylinder spread already makes it; `sub` adds a touch of the
        # crank-rate rumble a big engine carries in its body.
        if prof["sub"] > 0:
            tt = np.arange(per * reps) / SR
            out *= 1.0 + prof["sub"] * 0.25 * np.sin(2 * np.pi * (n_cycles / (per / SR)) * tt)
        if prof["hiss"] > 0:
            hz = sosfilt(butter(2, [700 / (SR / 2), 7000 / (SR / 2)], "band", output="sos"), np.tile(noise_bank, reps))
            out += hz * np.std(out) / max(np.std(hz), 1e-9) * prof["hiss"] * (0.6 + 0.6 * r)
        return out

    y = _periodic(gen, period)
    return _level(y)


def _level(y, rms_db=-20.0):
    y = y - np.mean(y)
    rms = np.sqrt(np.mean(y * y))
    y = y * (10 ** (rms_db / 20.0) / max(rms, 1e-9))
    peak = np.max(np.abs(y))
    if peak > 0.97:
        y *= 0.97 / peak
    return y


def turbo_loop(seed=7):
    rng = np.random.default_rng(seed)
    n = int(SR * 1.5)
    t = np.arange(n) / SR
    # Whine at 3.2 kHz with a slow wobble (periodic over the loop), a breathy band of air under it.
    wob = 0.012 * np.sin(2 * np.pi * (2.0 / 1.5) * t) + 0.006 * np.sin(2 * np.pi * (5.0 / 1.5) * t)
    f = 3200.0 * (1.0 + wob)
    ph = 2 * np.pi * np.cumsum(f) / SR
    ph *= (np.round(ph[-1] / (2 * np.pi)) * 2 * np.pi) / ph[-1]
    tone = np.sin(ph) + 0.25 * np.sin(2 * ph)
    nz = rng.standard_normal(n)

    def gen(per, reps):
        x = np.tile(nz, reps)
        air = sosfilt(butter(2, [2200 / (SR / 2), 5200 / (SR / 2)], "band", output="sos"), x)
        return np.tile(tone, reps) * 0.6 + air * 2.5
    return _level(_periodic(gen, n), -22.0)


def blowoff(seed=11):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.55)
    t = np.arange(n) / SR
    env = np.minimum(t / 0.008, 1.0) * np.exp(-t / 0.13)
    nz = rng.standard_normal(n)
    # A falling flutter (the compressor surging) on a band of escaping air.
    air = sosfilt(butter(2, [1400 / (SR / 2), 7500 / (SR / 2)], "band", output="sos"), nz)
    flutter = 1.0 + 0.5 * np.sin(2 * np.pi * (38.0 - 30.0 * t) * t)
    f = 2600.0 * np.exp(-t / 0.35) + 900.0
    whistle = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.25
    y = (air * flutter + whistle) * env
    y[-int(SR * 0.05):] *= np.linspace(1, 0, int(SR * 0.05))
    return _peak(y)


def beeper():
    # A reversing alarm: 1.1 kHz, half a second on, half off (a real one is a piezo tone this shape).
    n = SR
    t = np.arange(n) / SR
    tone = np.sign(np.sin(2 * np.pi * 1100.0 * t)) * 0.6 + np.sin(2 * np.pi * 1100.0 * t) * 0.4
    tone = sosfilt(butter(2, 5000 / (SR / 2), "low", output="sos"), np.tile(tone, 3))[n:2 * n]
    gate = ((t % 1.0) < 0.5).astype(float)
    ramp = int(SR * 0.006)
    g2 = np.real(np.fft.ifft(np.fft.fft(gate) * np.fft.fft(np.r_[np.ones(ramp) / ramp, np.zeros(n - ramp)])))
    return _peak(tone * g2, -3.0)


def _peak(y, db=-1.0):
    return y * (10 ** (db / 20.0) / max(np.max(np.abs(y)), 1e-9))


def loudness_db(y):
    w = int(0.05 * SR)
    sq = np.convolve(y * y, np.ones(w) / w, mode="valid")
    return 10 * np.log10(max(np.max(sq), 1e-12))


def main():
    wav_dir = None
    if "--wav" in sys.argv:
        wav_dir = sys.argv[sys.argv.index("--wav") + 1]
        os.makedirs(wav_dir, exist_ok=True)
    files = {}
    for pi, (pname, prof) in enumerate(PROFILES.items()):
        rpms = prof["rpm"]
        files["eng_%s_idle" % pname] = engine(pname, prof, rpms[0], 0.25, 100 + pi * 10)
        for li, (tag, rpm) in enumerate(zip(["low", "mid", "high"], rpms[1:])):
            files["eng_%s_%s" % (pname, tag)] = engine(pname, prof, rpm, 1.0, 101 + pi * 10 + li)
        files["eng_%s_off" % pname] = engine(pname, prof, rpms[2], 0.0, 105 + pi * 10)
    files["eng_turbo"] = turbo_loop()
    files["eng_blowoff"] = blowoff()
    files["eng_beeper"] = beeper()
    print("# Sfx.SAMPLE_LOUDNESS_DB rows:")
    for name, y in files.items():
        path = os.path.join(OUT, name + "_0.ogg")
        sf.write(path, y.astype(np.float32), SR, format="OGG", subtype="VORBIS")
        if wav_dir:
            sf.write(os.path.join(wav_dir, name + ".wav"), y.astype(np.float32), SR)
        back, _ = sf.read(path, dtype="float32")
        print('\t"%s": [%.2f],' % (name, loudness_db(back.astype(np.float64))))


if __name__ == "__main__":
    main()
