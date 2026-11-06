"""The city's newer sounds (docs/HANDOFF "City acoustics"): footsteps by surface, the bus's doors and
diesel idle, the light rail's door chime, the river, fountains, a playground, a basketball and
construction one-shots. Same pipeline and helpers as tools/ambience_audio.py (Freesound CC0 pages
checked by its `get`, HQ previews in build/audio_src/), plus Kenney's CC0 Impact Sounds for three
of the footstep surfaces.

    python3 tools/ambience_audio.py get <id>...      # fetch + licence check, as before
    python3 tools/city_audio.py kenney <zip>          # unpack Kenney's Impact Sounds into build/
    python3 tools/city_audio.py build [prefix...]     # cut everything below into assets/audio/

Footsteps and bounces ("steps") are cut automatically: onsets on 10 ms frames (a rise of
`rise` dB over the quietest of the last 60 ms, above the recording's median), each step from 15 ms
before its onset to the next onset or `max` s, faded; the `take` loudest of them are kept, spread
over the recording. One-shots peak at -1 dB like the other one-shots; loops are levelled to -22 dB
RMS. Every file's loudest-50 ms level is printed for Sfx's tables.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ambience_audio as aa  # noqa: E402

ROOT = aa.ROOT
KENNEY = os.path.join(ROOT, "build", "kenney_impact", "Audio")

# Loops: name, Freesound id, options (as ambience_audio.LOOPS).
LOOPS = [
    ("amb_river_0", 433589, dict(len=22, ch="wide", sr=32000, hp=120, lp=13000)),
    ("amb_fountain_0", 156969, dict(len=22, ch="roll", sr=32000, hp=150, lp=14000)),
    ("amb_playground_0", 469613, dict(len=26, ch="stereo", sr=32000, hp=180, lp=11000)),
    ("diesel_idle_0", 540398, dict(len=7.5, xf=0.8, ch="mono", sr=32000, hp=30, lp=8000)),
]

# One-shots: name, Freesound id, (start, end) s, options (as ambience_audio.SHOTS).
SHOTS = [
    # Pneumatic doors at a stop: the open (hiss and swing) and the close (hiss under the warning
    # beeper). A school bus's folding door, for a third.
    ("bus_door_0", 379373, (1.15, 3.65), {"hp": 120, "fade": 0.35}),
    ("bus_door_1", 379373, (8.1, 10.35), {"hp": 120, "fade": 0.35}),
    ("bus_door_2", 380320, (0.25, 3.6), {"hp": 120, "fade": 0.3}),
    # The two-tone transport chime (made by its author as a sine chime), once.
    ("bus_chime_0", 845146, (0.0, 1.9), {"hp": 200, "fade": 0.2}),
    ("bus_chime_1", 845146, (3.12, 5.0), {"hp": 200, "fade": 0.2}),
    # A metro car's door chime (recorded on the train) and a marimba version of a door chime.
    ("rail_chime_0", 249835, (0.0, 0.92), {"hp": 250, "fade": 0.15}),
    ("rail_chime_1", 434085, (0.0, 1.7), {"hp": 250, "fade": 0.4}),
    # Construction somewhere down the block: jackhammer bursts and a hammer.
    ("construction_0", 273697, (0.05, 3.6), {"hp": 120, "fade": 0.4, "fade_in": 0.05}),
    ("construction_1", 273697, (3.9, 7.6), {"hp": 120, "fade": 0.4, "fade_in": 0.05}),
    ("construction_2", 17012, (0.0, 1.55), {"hp": 120, "fade": 0.15}),
]

# Steps: name prefix, Freesound id, how many takes, options: hp / lp, rise (dB), max (s).
STEPS = [
    ("footstep_sand", 384082, 4, {"hp": 90, "lp": 12000, "rise": 10.0, "max": 0.32}),
    ("footstep_metal", 834029, 4, {"hp": 80, "rise": 14.0, "max": 0.42}),
    ("footstep_asphalt", 637556, 4, {"hp": 70, "rise": 12.0, "max": 0.32}),
    ("ball_dribble", 453757, 4, {"hp": 50, "rise": 12.0, "max": 0.4}),
]

# Kenney's Impact Sounds (CC0): name prefix, file prefix, how many.
KENNEY_STEPS = [
    ("footstep_concrete", "footstep_concrete_", 5),
    ("footstep_grass", "footstep_grass_", 5),
    ("footstep_wood", "footstep_wood_", 5),
]


def onsets(m, sr, rise, max_s):
    np = aa._np()[0]
    hop = int(0.01 * sr)
    e = np.array([aa.rms_db(m[i:i + hop]) for i in range(0, len(m) - hop, hop)])
    floor = np.median(e)
    out = []
    last = -100
    for i in range(6, len(e)):
        if e[i] - e[i - 6:i].min() > rise and e[i] > floor + 3.0 and i - last > 12:
            out.append(i)
            last = i
    spans = []
    for k, i in enumerate(out):
        a = max(0, i * hop - int(0.015 * sr))
        nxt = out[k + 1] * hop - int(0.02 * sr) if k + 1 < len(out) else len(m)
        b = min(nxt, a + int(max_s * sr))
        if b - a > int(0.08 * sr):
            spans.append((a, b))
    return spans


def make_steps(out_dir, prefix, sid, count, o):
    np = aa._np()[0]
    x, sr = aa.load(sid)
    m = aa.filt(x, sr, o.get("hp", 60), o.get("lp")).mean(axis=1)
    spans = onsets(m, sr, o.get("rise", 12.0), o.get("max", 0.35))
    # The loudest of each third of the recording, then the next loudest: spread over the take.
    ranked = sorted(spans, key=lambda s: -aa.loudest_window_db(m[s[0]:s[1]], sr))
    pick = ranked[:count]
    pick.sort()
    res = []
    for k, (a, b) in enumerate(pick):
        y = m[a:b].copy()
        nf = min(int(0.06 * sr), len(y) // 2)
        y[-nf:] *= np.cos(np.linspace(0, 1, nf) * np.pi / 2) ** 2
        ni = int(0.004 * sr)
        y[:ni] *= np.sin(np.linspace(0, 1, ni) * np.pi / 2) ** 2
        y = aa.resample(y[:, None], sr, 44100)
        y *= 0.89 / max(np.abs(y).max(), 1e-9)
        name = "%s_%d" % (prefix, k)
        r = aa.write(out_dir, name, y, 44100, 0.55)
        r["where"] = "%.2f-%.2f s" % (a / sr, b / sr)
        res.append((name, r))
    return res


def make_kenney(out_dir, prefix, src, count):
    np, sf = aa._np()[:2]
    res = []
    for k in range(count):
        x, sr = sf.read(os.path.join(KENNEY, "%s%03d.ogg" % (src, k)), always_2d=True)
        y = x.mean(axis=1, keepdims=True)
        y = aa.resample(y, sr, 44100)
        y *= 0.89 / max(np.abs(y).max(), 1e-9)
        name = "%s_%d" % (prefix, k)
        r = aa.write(out_dir, name, y, 44100, 0.55)
        r["where"] = "%s%03d.ogg" % (src, k)
        res.append((name, r))
    return res


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
            for name, r in make_steps(out_dir, prefix, sid, count, o):
                print("%-18s %6d %5.2f s %4d KB loudest %.2f  %s" % (name, sid, r["dur"], r["kb"], r["loud"], r["where"]))
    for prefix, src, count in KENNEY_STEPS:
        if ok(prefix):
            for name, r in make_kenney(out_dir, prefix, src, count):
                print("%-18s kenney %5.2f s %4d KB loudest %.2f  %s" % (name, r["dur"], r["kb"], r["loud"], r["where"]))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
    elif sys.argv[1] == "kenney":
        import zipfile
        zipfile.ZipFile(sys.argv[2]).extractall(os.path.join(ROOT, "build", "kenney_impact"))
    elif sys.argv[1] == "build":
        args = sys.argv[2:]
        out = aa.OUT
        if "--out" in args:
            i = args.index("--out")
            out = args[i + 1]
            args = args[:i] + args[i + 2:]
        build(args, out)
