"""The city ambience's audio pipeline: find CC0 recordings on Freesound, verify and fetch them,
and cut them into the game's clips (scripts/util/ambience.gd, Sfx.AMBIENCE_SAMPLES).

    python3 tools/ambience_audio.py search "city traffic distant" [n]
    python3 tools/ambience_audio.py get <freesound id>...
    python3 tools/ambience_audio.py build [clip-name-prefix...] [--out DIR]

search  lists Freesound results filtered to Creative Commons 0, most downloaded first.
get     fetches the sound's page, refuses anything whose page links a licence other than the CC0
        1.0 deed, prints the description (READ IT: a description that makes credit a condition,
        or says the sound is AI-generated, is a reason to skip it - two first picks were dropped
        that way), saves the page, then the first 2.6 MB of its HQ preview (the proxy here is
        slow, and a bed needs 30 s) into build/audio_src/<id>.mp3.
build   cuts every clip in LOOPS and SHOTS below from build/audio_src/ into assets/audio/ and
        prints each file's size and loudness: the loudest-50 ms window (Sfx's metric, for
        AMBIENCE_LOUDNESS_DB on one-shots) and, for loops, their RMS (always -22 dB by
        construction, which is what AMBIENCE_LOUDNESS_DB records for beds). Then run
        `godot --headless --path . --import` and record the sources in docs/ASSETS.md.

Loops: the steadiest stretch of a recording (least level variance with no spike 6 dB over its
median; `seam` also wants the level at both ends to match, for gusty wind and big surf), filtered
(4th-order zero-phase), resampled BEFORE cutting (resampling a finished loop filters across its
ends as if outside were silence, which clicks at the seam), cross-faded over its last `xf` s into
its start (equal power), levelled to -22 dB RMS with a soft knee on peaks, Vorbis. A mono source
that feeds a stereo bed is made wide by two different stretches of it, one per side ("wide"), or
by the loop against itself half a turn later ("roll"). One-shots: the stated span, faded, peak
-1 dB. Pass-bys ("peak") are cut so their loudest instant sits PASS_PEAK s in, which is what
Ambience.pass_peak_seconds assumes of every take.

Needs numpy, scipy and soundfile (libsndfile with MP3 and Vorbis; pip install scipy soundfile).
"""
import html
import os
import re
import subprocess
import sys
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "build", "audio_src")
OUT = os.path.join(ROOT, "assets", "audio")
MAX_BYTES = 2600000
PASS_PEAK = 1.2
LOOP_RMS_DB = -22.0

# Loops: name, Freesound id, options. len (s), xf (cross-fade, s, default 2.5), start (s; else the
# steadiest stretch), ch ("stereo", "mono", "left", "wide", "roll"), sr (Hz), hp / lp (Hz), seam.
LOOPS = [
    ("amb_city_0", 250270, dict(len=28, ch="wide", sr=32000, hp=45, lp=11000)),
    ("amb_city_far_0", 330427, dict(len=28, ch="stereo", sr=32000, hp=35, lp=10000)),
    ("amb_crowd_0", 451734, dict(len=26, ch="stereo", sr=32000, hp=110, lp=12000)),
    # 160570 (a San Gabriel mockingbird) was the first pick and was dropped: its page is CC0 but
    # its description makes credit a condition, and a condition is not CC0.
    ("amb_birds_0", 142938, dict(len=26, ch="roll", sr=32000, hp=350, lp=14000)),
    ("amb_crickets_0", 175020, dict(len=24, ch="stereo", sr=32000, hp=900, lp=15000)),
    ("amb_gale_0", 167684, dict(len=28, ch="stereo", sr=32000, hp=40, lp=9000, seam=True)),
    ("amb_rain_heavy_0", 507902, dict(len=24, ch="wide", sr=32000, hp=120, lp=14000)),
    ("amb_rain_roof_0", 239939, dict(len=22, ch="stereo", sr=32000, hp=150, lp=14000)),
    ("amb_rain_car_0", 344460, dict(len=22, ch="stereo", sr=32000, hp=80, lp=12000)),
    ("amb_freeway_0", 448092, dict(len=28, ch="mono", sr=32000, hp=40, lp=11000)),
    ("amb_surf_0", 412308, dict(len=30, ch="mono", sr=32000, hp=50, lp=12000, seam=True)),
    ("amb_airport_0", 369508, dict(len=26, ch="mono", sr=32000, hp=35, lp=9000)),
    ("amb_port_0", 342878, dict(len=28, ch="mono", sr=32000, hp=90, lp=9000)),
    ("car_roll_0", 369054, dict(len=3.6, xf=0.35, ch="left", sr=32000, hp=60, lp=9000, start=0.2)),
]

# One-shots: name, Freesound id, (start, end) s or "peak", options: hp / lp (Hz), fade / fade_in
# (s), sr (Hz, default 44100).
SHOTS = [
    ("horn_far_0", 182474, (0.55, 2.2), {}),
    ("horn_far_1", 434878, (0.0, 0.75), {}),
    ("horn_far_2", 423990, (0.05, 0.7), {}),
    ("horn_far_3", 461679, (0.45, 2.5), {}),
    ("horn_far_4", 349922, (1.4, 3.1), {}),
    ("dog_0", 440865, (0.7, 2.8), {"hp": 250}),
    ("dog_1", 440865, (4.95, 7.1), {"hp": 250}),
    ("dog_2", 440865, (8.55, 9.9), {"hp": 250}),
    ("dog_3", 54545, (2.85, 5.35), {"hp": 250}),
    ("bus_hiss_0", 454420, (3.9, 6.4), {"hp": 60}),
    ("bus_hiss_1", 454420, (10.6, 12.8), {"hp": 60}),
    ("bus_hiss_2", 801435, (0.9, 2.3), {"hp": 200}),
    ("siren_far_0", 469363, (1.8, 17.8), {"hp": 250, "lp": 7000, "fade": 3.0, "fade_in": 1.0, "sr": 32000}),
    # 705395 was the first pick and was dropped: its description says it is AI-generated.
    ("siren_far_1", 568814, (1.5, 17.5), {"hp": 250, "lp": 7000, "fade": 3.0, "fade_in": 1.0, "sr": 32000}),
    ("gull_0", 73497, (0.3, 3.5), {"hp": 400}),
    ("gull_1", 510917, (3.9, 6.4), {"hp": 400}),
    ("gull_2", 510917, (6.4, 9.0), {"hp": 400}),
    ("gull_3", 353416, (0.0, 2.6), {"hp": 400}),
    ("gull_4", 353416, (9.0, 11.6), {"hp": 400}),
    ("coyote_0", 256533, (12.5, 19.2), {"hp": 350, "fade": 1.2}),
    ("coyote_1", 256533, (0.25, 2.6), {"hp": 350}),
    ("coyote_2", 640060, (20.0, 28.0), {"hp": 350, "fade": 2.0, "fade_in": 1.0}),
    ("ship_horn_0", 208714, (11.0, 17.5), {"hp": 40, "fade": 2.0}),
    ("ship_horn_1", 64601, (0.0, 6.2), {"hp": 40, "fade": 1.5}),
    ("ship_horn_2", 636075, (0.0, 6.0), {"hp": 40, "fade": 1.5}),
    ("crane_0", 507465, (1.45, 3.3), {"hp": 120}),
    ("crane_1", 507465, (5.65, 7.4), {"hp": 120}),
    ("crane_2", 507465, (9.6, 11.3), {"hp": 120}),
    ("crane_3", 523413, (0.25, 3.8), {"hp": 300}),
    ("car_pass_0", 171447, "peak", {"hp": 40}),
    ("car_pass_1", 465397, "peak", {"hp": 40}),
    ("car_pass_2", 209767, "peak", {"hp": 40}),
    ("car_pass_3", 3179, "peak", {"hp": 40}),
    ("car_pass_wet_0", 462862, "peak", {"hp": 40}),
]


# --- Freesound ---------------------------------------------------------------------------

def _fetch(url):
    return subprocess.run(["curl", "-sSL", "--max-time", "120", url], check=True,
                          capture_output=True).stdout.decode("utf-8", "replace")


def search(q, n=15):
    page = _fetch("https://freesound.org/search/?q=" + urllib.parse.quote_plus(q)
                  + "&f=license:%22Creative+Commons+0%22&s=Downloads+(most+first)")
    for b in page.split('class="bw-search__result"')[1:n + 1]:
        def grab(pattern):
            m = re.search(pattern, b, re.S)
            return html.unescape(m.group(1)) if m else "?"
        print("%s | %s | %s | %ss | %s | dl %s" % (
            grab(r'data-sound-id="(\d+)"'), grab(r'data-username="([^"]+)"'),
            grab(r'data-title="([^"]*)"'), grab(r'data-duration="([\d.]+)"'),
            grab(r'title="License: ([^"]+)"'), grab(r'data-num-downloads="(\d+)"')))
        desc = grab(r'overflow-hidden v-spacing-1" title="([^"]*)"')
        if desc != "?":
            print("      " + desc.replace("\n", " ")[:220])


def get(sid):
    os.makedirs(SRC, exist_ok=True)
    page = _fetch("https://freesound.org/s/%s/" % sid)
    with open(os.path.join(SRC, "%s.html" % sid), "w") as f:
        f.write(page)
    title = re.search(r"<title>([^<]*)</title>", page)
    print("title:", html.unescape(title.group(1)) if title else "?")
    links = sorted(set(re.findall(r"creativecommons\.org/[a-z/.0-9]+", page)))
    print("licence links:", links)
    desc = re.search(r'<div id="soundDescriptionSection">(.*?)</div>', page, re.S)
    if desc:
        print("description:", " ".join(html.unescape(re.sub("<[^>]+>", " ", desc.group(1))).split()))
    if links != ["creativecommons.org/publicdomain/zero/1.0/"]:
        print("NOT CC0 ONLY - not downloaded")
        return
    mp3 = re.search(r'data-mp3="([^"]+)"', page)
    url = mp3.group(1).replace("-lq.mp3", "-hq.mp3")
    out = os.path.join(SRC, "%s.mp3" % sid)
    subprocess.run(["curl", "-sSL", "--max-time", "240", "-r", "0-%d" % MAX_BYTES, url, "-o", out])
    print("saved", out, os.path.getsize(out), "bytes")


# --- Cutting -----------------------------------------------------------------------------

def _np():
    import numpy as np
    import soundfile as sf
    from scipy.signal import butter, resample_poly, sosfiltfilt
    return np, sf, butter, resample_poly, sosfiltfilt


def load(sid):
    """Block by block: a range-limited preview ends mid-frame and the decoder errors there, which
    a single sf.read() would turn into losing the whole file."""
    np, sf, _, _, _ = _np()
    blocks = []
    with sf.SoundFile(os.path.join(SRC, "%s.mp3" % sid)) as f:
        sr = f.samplerate
        while True:
            try:
                b = f.read(sr * 5, always_2d=True)
            except Exception:
                break
            if len(b) == 0:
                break
            blocks.append(b)
    x = np.concatenate(blocks)
    if x.shape[1] == 1:
        x = np.repeat(x, 2, axis=1)
    return x, sr


def filt(x, sr, hp=None, lp=None):
    _, _, butter, _, sosfiltfilt = _np()
    if hp:
        x = sosfiltfilt(butter(4, hp, "hp", fs=sr, output="sos"), x, axis=0)
    if lp and lp < sr / 2:
        x = sosfiltfilt(butter(4, lp, "lp", fs=sr, output="sos"), x, axis=0)
    return x


def resample(x, sr_in, sr_out):
    np, _, _, resample_poly, _ = _np()
    if sr_in == sr_out:
        return x
    g = np.gcd(sr_in, sr_out)
    return resample_poly(x, sr_out // g, sr_in // g, axis=0)


def rms_db(x):
    np = _np()[0]
    return 10 * np.log10(max(np.mean(x ** 2), 1e-18))


def loudest_window_db(x, sr):
    np = _np()[0]
    m = x.mean(axis=1) if x.ndim > 1 else x
    w = int(0.05 * sr)
    sq = np.convolve(m * m, np.ones(w) / w, mode="valid")
    return 10 * np.log10(max(sq.max(), 1e-12))


def steadiest(m, sr, length, seam=False):
    np = _np()[0]
    hop = int(0.5 * sr)
    lv = np.array([rms_db(m[i:i + hop]) for i in range(0, len(m) - hop, hop)])
    n = int(length / 0.5)
    best, best_i = 1e9, 0
    for i in range(0, len(lv) - n):
        w = lv[i:i + n]
        med = np.median(w)
        if w.max() > med + 6.0 or w.min() < med - 12.0:
            continue
        cost = np.std(w)
        if seam:
            cost += 0.5 * abs(np.mean(lv[i:i + 3]) - np.mean(lv[i + n - 3:i + n]))
        if cost < best:
            best, best_i = cost, i
    return best_i * 0.5


def loop_from(x, sr, start, length, xf):
    np = _np()[0]
    a = int(start * sr)
    n = int(length * sr)
    f = int(xf * sr)
    seg = x[a:a + n + f].copy()
    if len(seg) < n + f:
        raise ValueError("source too short for %.1f s from %.1f" % (length, start))
    t = np.linspace(0.0, 1.0, f)[:, None]
    out = seg[:n].copy()
    out[:f] = seg[:f] * np.sin(t * np.pi / 2) + seg[n:n + f] * np.cos(t * np.pi / 2)
    return out


def soft_limit(x, ceiling=0.89):
    np = _np()[0]
    knee = ceiling * 0.7
    a = np.abs(x)
    over = a > knee
    y = x.copy()
    y[over] = np.sign(x[over]) * (knee + (ceiling - knee) * np.tanh((a[over] - knee) / (ceiling - knee)))
    return y


def write(out_dir, name, x, sr, level):
    np, sf = _np()[:2]
    path = os.path.join(out_dir, name + ".ogg")
    data = x.astype(np.float32)
    if data.ndim == 2 and data.shape[1] == 1:
        data = data[:, 0]
    sf.write(path, data, sr, format="OGG", subtype="VORBIS", compression_level=level)
    y, ysr = sf.read(path, always_2d=True) # measure the file as Godot will read it
    return dict(loud=loudest_window_db(y, ysr), rms=rms_db(y), kb=os.path.getsize(path) // 1024,
                dur=len(y) / ysr, ch=y.shape[1])


def make_loop(out_dir, name, sid, o):
    np = _np()[0]
    x, sr = load(sid)
    x = resample(filt(x, sr, o.get("hp"), o.get("lp")), sr, o["sr"])
    sr = o["sr"]
    length, xf = o["len"], o.get("xf", 2.5)
    start = o.get("start")
    if start is None:
        start = steadiest(x.mean(axis=1), sr, length + xf, o.get("seam", False))
    ch = o["ch"]
    if ch == "wide":
        mono = x.mean(axis=1, keepdims=True)
        other = start + length + xf + 3.0
        if other * sr + (length + xf) * sr > len(mono):
            other = max(0.0, start - length - xf - 3.0)
        y = np.concatenate([loop_from(mono, sr, start, length, xf), loop_from(mono, sr, other, length, xf)], axis=1)
        where = "%.1f-%.1f s (left) and %.1f-%.1f s (right)" % (start, start + length + xf, other, other + length + xf)
    else:
        y = loop_from(x, sr, start, length, xf)
        if ch == "mono":
            y = y.mean(axis=1, keepdims=True)
        elif ch == "left":
            y = y[:, :1]
        elif ch == "roll":
            m1 = y.mean(axis=1, keepdims=True)
            y = np.concatenate([m1, np.roll(m1, len(m1) // 2, axis=0)], axis=1)
        where = "%.1f-%.1f s" % (start, start + length + xf)
    y *= 10 ** ((LOOP_RMS_DB - rms_db(y)) / 20.0)
    r = write(out_dir, name, soft_limit(y), sr, 0.62)
    r["where"] = where
    return r


def make_shot(out_dir, name, sid, span, o):
    np = _np()[0]
    x, sr = load(sid)
    m = filt(x, sr, o.get("hp", 40), o.get("lp")).mean(axis=1)
    if span == "peak":
        w = int(0.05 * sr)
        pk = int(np.argmax(np.convolve(m * m, np.ones(w) / w, mode="same")))
        a, b = pk - int(PASS_PEAK * sr), pk + int(1.6 * sr)
        pad = max(0, -a)
        a = max(a, 0)
        y = m[a:b]
        if pad:
            y = np.concatenate([np.zeros(pad), y])
        span = (a / sr - pad / sr, b / sr)
        fade_in = 0.35
    else:
        y = m[int(span[0] * sr):int(span[1] * sr)]
        fade_in = o.get("fade_in", 0.006)
    y = y.copy()
    nf = min(int(o.get("fade", 0.25) * sr), len(y) // 2)
    y[-nf:] *= np.cos(np.linspace(0, 1, nf) * np.pi / 2) ** 2
    ni = max(1, int(fade_in * sr))
    y[:ni] *= np.sin(np.linspace(0, 1, ni) * np.pi / 2) ** 2
    out_sr = o.get("sr", 44100)
    y = resample(y[:, None], sr, out_sr)
    y *= 0.89 / max(np.abs(y).max(), 1e-9)
    r = write(out_dir, name, y, out_sr, 0.55)
    r["where"] = "%.2f-%.2f s" % span
    return r


def build(want, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for name, sid, o in LOOPS:
        if not want or any(name.startswith(w) for w in want):
            r = make_loop(out_dir, name, sid, o)
            total += r["kb"]
            print("%-16s %6d %5.1f s ch%d %4d KB  rms %.2f  loudest %.2f  %s" % (name, sid, r["dur"], r["ch"], r["kb"], r["rms"], r["loud"], r["where"]))
    for name, sid, span, o in SHOTS:
        if not want or any(name.startswith(w) for w in want):
            r = make_shot(out_dir, name, sid, span, o)
            total += r["kb"]
            print("%-16s %6d %5.2f s ch%d %4d KB  loudest %.2f  %s" % (name, sid, r["dur"], r["ch"], r["kb"], r["loud"], r["where"]))
    print("total %.2f MB" % (total / 1024.0))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
    elif sys.argv[1] == "search":
        search(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 15)
    elif sys.argv[1] == "get":
        for s in sys.argv[2:]:
            get(s)
    elif sys.argv[1] == "build":
        args = sys.argv[2:]
        out = OUT
        if "--out" in args:
            i = args.index("--out")
            out = args[i + 1]
            args = args[:i] + args[i + 2:]
        build(args, out)
