"""The street at eye level (docs/HANDOFF "The street at eye level"): shop door bells, car doors
opening and shutting, a truck's / bus's air brakes setting as it stops, heels on the pavement,
leaves in the wind, the sea heard from a long way off, tyres on gravel, and the hiss of tyres on a
wet road. Same pipeline and helpers as tools/ambience_audio.py and tools/city_audio.py (Freesound
CC0 pages checked by `ambience_audio.py get`, HQ previews in build/audio_src/).

    python3 tools/ambience_audio.py get <id>...      # fetch + licence check (read the description)
    python3 tools/street_audio.py build [prefix...]   # cut everything below into assets/audio/

Then `godot --headless --path . --import`, put each printed "loudest" into Sfx.SAMPLE_LOUDNESS_DB
(one-shots) - loops are -22 dB RMS by construction, which is what is recorded for them - and the
sources into docs/ASSETS.md.

`tyre_wet` is synthesised here (no CC0 recording of steady wet-road tyre hiss was found, only
pass-bys): pink-ish noise band-passed round 1.5-7 kHz, a slow swell from the tread and the road's
texture, and a crackle of droplets, as a seamless loop.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ambience_audio as aa  # noqa: E402
import city_audio as ca  # noqa: E402

# Loops: name, Freesound id, options (as ambience_audio.LOOPS).
LOOPS = [
    # Loose leaves and branches rustling in the wind (a park in Halifax): the trees' bed.
    ("amb_leaves_0", 378725, dict(len=24, ch="stereo", sr=32000, hp=180, lp=13000, seam=True)),
    # 11 ft waves breaking out at sea, heard from the top of a cliff at night: the sea from afar.
    ("amb_sea_far_0", 426074, dict(len=28, ch="stereo", sr=32000, hp=35, lp=6000, seam=True)),
    # Slowly driving on a gravel road, the mic by the wheel: tyres off the tarmac.
    ("tyre_gravel_0", 577504, dict(len=8.0, xf=0.8, ch="mono", sr=32000, hp=60, lp=10000)),
]

# One-shots: name, Freesound id, (start, end) s, options (as ambience_audio.SHOTS).
SHOTS = [
    # A shop door's bell as somebody comes in; a foley shop bell (two of its rings); a short
    # double ding cleaned up from another CC0 bell.
    ("shop_bell_0", 57743, (0.0, 3.2), {"hp": 300, "fade": 1.2}),
    ("shop_bell_1", 494565, (0.25, 2.25), {"hp": 300, "fade": 0.8}),
    ("shop_bell_2", 494565, (2.3, 4.2), {"hp": 300, "fade": 0.8}),
    ("shop_bell_3", 192761, (0.0, 0.9), {"hp": 300, "fade": 0.3}),
    # Car doors shutting, outside (an Audi, a field-recorded one, another exterior close).
    ("car_door_0", 208695, (0.0, 0.57), {"hp": 50, "fade": 0.15}),
    ("car_door_1", 9876, (0.0, 0.55), {"hp": 50, "fade": 0.15}),
    ("car_door_2", 173009, (0.22, 0.77), {"hp": 50, "fade": 0.15}),
    # The latch and the door swinging open.
    ("car_door_open_0", 335102, (0.3, 1.25), {"hp": 120, "fade": 0.2}),
    # A truck's air brakes released (the "psssht" of a heavy vehicle stopping).
    ("air_brake_0", 504865, (0.0, 2.6), {"hp": 120, "fade": 0.9}),
]

# Steps: name prefix, Freesound id, how many takes, options (as city_audio.STEPS).
STEPS = [
    # A woman in high heels on concrete: a share of the crowd click past.
    ("footstep_heels", 343390, 5, {"hp": 120, "rise": 12.0, "max": 0.3}),
]


def make_wet(out_dir, name="tyre_wet_0", seconds=6.0, sr=32000):
    np = aa._np()[0]
    rng = np.random.default_rng(4401)
    n = int(seconds * sr)
    xf = int(0.6 * sr)
    w = rng.standard_normal(n + xf)
    # Pink-ish: -3 dB / octave through a cumulative-sum blend, then the hiss band.
    b = np.cumsum(w) * 0.02
    b -= np.convolve(b, np.ones(400) / 400, mode="same")
    x = w * 0.6 + b
    x = aa.filt(x[:, None], sr, 1400, 7500)[:, 0]
    t = np.arange(n + xf) / sr
    # The tread and the road's texture: a slow, uneven swell.
    swell = 1.0 + 0.18 * np.sin(2 * np.pi * 0.7 * t) + 0.1 * np.sin(2 * np.pi * 1.9 * t + 1.3)
    x *= swell
    # Droplets flicked off the tyre: sparse short bright ticks.
    ticks = np.zeros(n + xf)
    for k in rng.integers(0, n + xf - 200, size=int(seconds * 55)):
        ticks[k:k + 120] += rng.uniform(0.3, 1.0) * np.exp(-np.arange(120) / 18.0) * rng.standard_normal(120)
    ticks = aa.filt(ticks[:, None], sr, 3000, 11000)[:, 0]
    x = x + ticks * 0.5
    y = x[:n].copy()
    f = np.linspace(0.0, 1.0, xf)
    y[:xf] = x[:xf] * np.sin(f * np.pi / 2) + x[n:n + xf] * np.cos(f * np.pi / 2)
    y = y[:, None]
    y *= 10 ** ((aa.LOOP_RMS_DB - aa.rms_db(y)) / 20.0)
    r = aa.write(out_dir, name, aa.soft_limit(y), sr, 0.62)
    print("%-18s synth  %5.1f s ch%d %4d KB rms %.2f loudest %.2f" % (name, r["dur"], r["ch"], r["kb"], r["rms"], r["loud"]))


def build(want, out_dir):
    def ok(n):
        return not want or any(n.startswith(w) for w in want)
    for name, sid, o in LOOPS:
        if ok(name):
            r = aa.make_loop(out_dir, name, sid, o)
            print("%-18s %6d %5.1f s ch%d %4d KB rms %.2f loudest %.2f  %s" % (name, sid, r["dur"], r["ch"], r["kb"], r["rms"], r["loud"], r["where"]))
    for name, sid, span, o in SHOTS:
        if ok(name):
            r = aa.make_shot(out_dir, name, sid, span, o)
            print("%-18s %6d %5.2f s %4d KB loudest %.2f  %s" % (name, sid, r["dur"], r["kb"], r["loud"], r["where"]))
    for prefix, sid, count, o in STEPS:
        if ok(prefix):
            for name, r in ca.make_steps(out_dir, prefix, sid, count, o):
                print("%-18s %6d %5.2f s %4d KB loudest %.2f  %s" % (name, sid, r["dur"], r["kb"], r["loud"], r["where"]))
    if ok("tyre_wet"):
        make_wet(out_dir)


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] != "build":
        print(__doc__)
    else:
        args = sys.argv[2:]
        out = aa.OUT
        if "--out" in args:
            i = args.index("--out")
            out = args[i + 1]
            args = args[:i] + args[i + 2:]
        build(args, out)
