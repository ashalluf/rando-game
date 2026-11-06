#!/usr/bin/env python3
"""The car radio's audio (scripts/vehicles/car_radio.gd), built from build/radio_src/.

    tools/radio/fetch_radio.sh           # the CC0 / public-domain sources (docs/ASSETS.md)
    python3 tools/radio/make_radio.py    # writes assets/audio/radio/*.ogg
    godot --headless --path . --import   # then commit the .ogg and every .import

Each track is cut to at most MAX_SECONDS (a fade out over FADE_OUT at a musical-ish point is
better than a 4-minute file in a macOS app and a web page), levelled to TARGET_LUFS with ffmpeg's
EBU R128 loudnorm (two passes, linear) so stations do not jump in level, and encoded as
Ogg Vorbis at BITRATE / OUT_RATE (48 kbit/s stereo at 32 kHz: about 0.65 MB a track).

The station idents are synthesised here, original: no voice (the brief allows none), a four- to
six-second sting per station in its own style - a tuned-in sweep, then
  velvet: a piano arpeggio over a soft string pad and a bell;
  palm:   vinyl crackle, an electric-piano chord pair and a lazy swung kit;
  neon:   a detuned saw arpeggio through an opening filter, a sub and a gated snare;
  tiki:   a vibraphone motif with a shaker and a plucked bass;
all through a synthetic room. Plus `radio_static.ogg`, the burst heard while tuning.
numpy only (no scipy). The names here must match CarRadio.STATIONS.
"""
import json
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "build", "radio_src")
OUT = os.path.join(ROOT, "assets", "audio", "radio")
SR = 44100
MAX_SECONDS = 110.0
FADE_IN = 0.4
FADE_OUT = 4.0
TARGET_LUFS = -17.0
# 48 kbit/s stereo at 32 kHz: FM radio stops at 15 kHz anyway, and the bits go further there.
BITRATE = "48k"
OUT_RATE = 32000

# out name, source file, start second
TRACKS = [
	("velvet_0", "vel_waltz64.mp3", 0.0),
	("velvet_1", "vel_waltz70.mp3", 0.0),
	("velvet_2", "vel_aria.ogg", 0.0),
	("palm_0", "lofi_chill.ogg", 0.0),
	("palm_1", "lofi_cat.mp3", 0.0),
	("palm_2", "lofi_tea.mp3", 0.0),
	("neon_0", "syn_prowler.ogg", 0.0),
	("neon_1", "syn_moonlight.mp3", 0.0),
	("neon_2", "syn_rush.mp3", 0.0),
	("tiki_0", "lng_tiki.mp3", 0.0),
	("tiki_1", "lng_fishin.mp3", 0.0),
	("tiki_2", "lng_august.mp3", 0.0),
]


def run(cmd):
	r = subprocess.run(cmd, capture_output=True, text=True)
	if r.returncode != 0:
		sys.stderr.write(r.stderr[-2000:])
		raise SystemExit("failed: " + " ".join(cmd[:6]))
	return r


def duration(path):
	r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path])
	return float(r.stdout.strip())


def encode_track(name, src, start):
	path = os.path.join(SRC, src)
	dur = min(duration(path) - start, MAX_SECONDS)
	cut = dur < duration(path) - start - 0.5
	fades = "afade=t=in:st=0:d=%.2f" % FADE_IN
	if cut:
		fades += ",afade=t=out:st=%.2f:d=%.2f" % (dur - FADE_OUT, FADE_OUT)
	base = ["ffmpeg", "-v", "error", "-y", "-ss", "%.2f" % start, "-t", "%.2f" % dur, "-i", path]
	# Pass 1: measure.
	r = run(["ffmpeg", "-hide_banner", "-nostats", "-v", "info"] + base[3:] + ["-af", fades + ",loudnorm=I=%g:TP=-1.5:LRA=11:print_format=json" % TARGET_LUFS,
		"-f", "null", "-"])
	text = r.stderr
	m = json.loads(text[text.rindex("{"):text.rindex("}") + 1])
	ln = ("loudnorm=I=%g:TP=-1.5:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:"
		"measured_thresh=%s:offset=%s:linear=true" % (TARGET_LUFS, m["input_i"], m["input_tp"],
		m["input_lra"], m["input_thresh"], m["target_offset"]))
	out = os.path.join(OUT, name + ".ogg")
	run(base + ["-af", fades + "," + ln, "-ar", str(OUT_RATE), "-ac", "2", "-c:a", "libvorbis",
		"-b:a", BITRATE, out])
	print("%-10s %6.1f s %6d KB  (%s)" % (name, duration(out), os.path.getsize(out) // 1024, src))


# --- synthesis ---------------------------------------------------------------------------------

rng = np.random.default_rng(1983)


def t_axis(sec):
	return np.arange(int(sec * SR)) / SR


def env_ad(n, attack, decay):
	t = np.arange(n) / SR
	a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
	return a * np.exp(-t / max(decay, 1e-4))


def place(buf, sig, at, gain=1.0):
	i = int(at * SR)
	j = min(len(buf), i + len(sig))
	if j > i:
		buf[i:j] += sig[: j - i] * gain


def midi(n):
	return 440.0 * 2.0 ** ((n - 69) / 12.0)


def onepole(x, cutoff):
	"""One-pole low-pass, cutoff per sample allowed (array) - vectorised in blocks."""
	cut = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
	a = 1.0 - np.exp(-2.0 * np.pi * cut / SR)
	y = np.empty_like(x)
	s = 0.0
	for i in range(len(x)):
		s += a[i] * (x[i] - s)
		y[i] = s
	return y


def piano(f, sec, vel=1.0):
	t = t_axis(sec)
	sig = np.zeros_like(t)
	for k in range(1, 9):
		fk = f * k * np.sqrt(1.0 + 0.0004 * k * k)
		if fk > SR * 0.45:
			break
		sig += np.sin(2 * np.pi * fk * t) * (1.0 / k ** 1.3) * np.exp(-t * (0.9 + 0.55 * k))
	hammer = rng.standard_normal(len(t)) * np.exp(-t * 300.0) * 0.08
	return (sig + hammer) * env_ad(len(t), 0.003, 9.0) * vel


def rhodes(f, sec, vel=1.0):
	t = t_axis(sec)
	mod = np.sin(2 * np.pi * f * 14.0 * t) * np.exp(-t * 9.0) * 1.6
	tine = np.sin(2 * np.pi * f * t + mod)
	body = np.sin(2 * np.pi * f * t) * 0.6 + np.sin(2 * np.pi * f * 2 * t) * 0.12
	trem = 1.0 + 0.18 * np.sin(2 * np.pi * 4.5 * t)
	return (tine * 0.5 + body) * trem * env_ad(len(t), 0.004, 1.6) * vel


def vibes(f, sec, vel=1.0):
	t = t_axis(sec)
	sig = np.sin(2 * np.pi * f * t) + 0.22 * np.sin(2 * np.pi * f * 4.0 * t) * np.exp(-t * 6.0)
	sig += 0.05 * np.sin(2 * np.pi * f * 10.0 * t) * np.exp(-t * 20.0)
	trem = 1.0 + 0.3 * np.sin(2 * np.pi * 5.5 * t)
	return sig * trem * env_ad(len(t), 0.002, 1.3) * vel


def saw(f, t, detune=0.0):
	ph = (f * (1.0 + detune)) * t
	x = 2.0 * (ph - np.floor(ph + 0.5))
	return x


def supersaw(f, sec):
	t = t_axis(sec)
	sig = np.zeros_like(t)
	for d in (-0.012, -0.005, 0.0, 0.006, 0.011):
		sig += saw(f, t + rng.random(), d)
	return sig / 4.0


def pad(freqs, sec, bright=1800.0):
	t = t_axis(sec)
	sig = np.zeros_like(t)
	for f in freqs:
		for d in (-0.004, 0.0, 0.004):
			sig += saw(f, t + rng.random(), d)
	sig /= (3.0 * len(freqs))
	sig = onepole(onepole(sig, bright), bright)
	return sig * np.clip(t / 0.6, 0, 1) * np.clip((sec - t) / 1.2, 0, 1)


def kick(sec=0.45):
	t = t_axis(sec)
	f = 48.0 + 110.0 * np.exp(-t * 28.0)
	ph = 2 * np.pi * np.cumsum(f) / SR
	return np.sin(ph) * np.exp(-t * 7.0) + rng.standard_normal(len(t)) * np.exp(-t * 400) * 0.1


def snare(sec=0.3, tone=190.0, decay=14.0):
	t = t_axis(sec)
	n = rng.standard_normal(len(t))
	n = n - onepole(n, 900.0)  # high-passed noise
	return (n * 0.7 + np.sin(2 * np.pi * tone * t) * 0.5) * np.exp(-t * decay)


def hat(sec=0.08, decay=60.0):
	t = t_axis(sec)
	n = rng.standard_normal(len(t))
	n = n - onepole(n, 6000.0)
	return n * np.exp(-t * decay) * 0.4


def shaker(sec=0.12):
	t = t_axis(sec)
	n = rng.standard_normal(len(t))
	n = n - onepole(n, 4500.0)
	return n * np.sin(np.pi * np.clip(t / sec, 0, 1)) ** 2 * 0.3


def pluck_bass(f, sec):
	t = t_axis(sec)
	s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 8)
	return s * env_ad(len(t), 0.004, 0.5)


def bell(f, sec):
	t = t_axis(sec)
	sig = np.zeros_like(t)
	for ratio, amp, dec in ((1.0, 1.0, 1.4), (2.76, 0.45, 2.6), (5.4, 0.25, 4.0), (8.93, 0.12, 7.0)):
		sig += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * dec)
	return sig * env_ad(len(t), 0.002, 4.0)


def crackle(sec, density=40.0):
	n = int(sec * SR)
	out = rng.standard_normal(n) * 0.006
	out = out - onepole(out, 300.0)
	clicks = rng.random(n) < density / SR
	idx = np.nonzero(clicks)[0]
	for i in idx:
		ln = min(n - i, 40)
		out[i:i + ln] += rng.standard_normal(ln) * np.exp(-np.arange(ln) / 6.0) * rng.uniform(0.05, 0.25)
	return out


def tune_in(sec=0.55):
	"""The dial landing on the station: a band of noise sweeping down into the carrier."""
	t = t_axis(sec)
	n = rng.standard_normal(len(t))
	cut = 6000.0 * np.exp(-t * 4.0) + 300.0
	n = onepole(n, cut) - onepole(n, cut * 0.25)
	whistle = np.sin(2 * np.pi * np.cumsum(2400.0 * np.exp(-t * 6.0) + 200.0) / SR) * 0.08
	return (n * 0.5 + whistle) * np.clip((sec - t) / sec, 0, 1) ** 2


def room(x, seconds=1.4, wet=0.22, damp=2600.0):
	"""A synthetic room: exponentially decaying filtered noise as an impulse response (FFT)."""
	n = int(seconds * SR)
	t = np.arange(n) / SR
	ir = rng.standard_normal(n) * np.exp(-t * 6.9 / seconds)
	ir = onepole(ir, damp)
	ir[: int(0.012 * SR)] = 0.0
	ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
	m = len(x) + n
	size = 1 << int(np.ceil(np.log2(m)))
	y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
	return x + y * wet


def finish(mono_l, mono_r, name, peak=0.89):
	st = np.stack([mono_l, mono_r], axis=1)
	st /= max(1e-9, np.max(np.abs(st))) / peak
	fade = int(0.08 * SR)
	st[-fade:] *= np.linspace(1, 0, fade)[:, None]
	wav = os.path.join(SRC, name + ".wav")
	pcm = (st * 32767).astype("<i2")
	import wave
	with wave.open(wav, "wb") as w:
		w.setnchannels(2)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(pcm.tobytes())
	out = os.path.join(OUT, name + ".ogg")
	# Idents sit a little under the music's level, like a station's own bumpers.
	run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-af",
		"loudnorm=I=%g:TP=-1.5:LRA=11" % (TARGET_LUFS - 1.0), "-ar", str(OUT_RATE), "-c:a", "libvorbis",
		"-b:a", "64k", out])
	print("%-10s %6.1f s %6d KB  (synthesised)" % (name, duration(out), os.path.getsize(out) // 1024))


def stereo(sig, pan):
	return sig * np.sqrt(0.5 * (1 - pan)), sig * np.sqrt(0.5 * (1 + pan))


def ident_velvet():
	sec = 5.5
	n = int(sec * SR)
	L = np.zeros(n)
	R = np.zeros(n)
	tl, tr = stereo(tune_in(), 0.0)
	place(L, tl, 0.0)
	place(R, tr, 0.0)
	# Eb major 9: Eb3 Bb3 G4 D5 F5 Bb5, rolled.
	notes = [51, 58, 67, 74, 77, 82]
	for i, nn in enumerate(notes):
		l, r = stereo(piano(midi(nn), 4.6, 0.8 - i * 0.05), -0.5 + i * 0.2)
		place(L, l, 0.45 + i * 0.11)
		place(R, r, 0.45 + i * 0.11)
	pl = pad([midi(51), midi(58), midi(63), midi(67)], 4.8, 1200.0) * 0.35
	place(L, pl, 0.5)
	place(R, np.roll(pl, 300), 0.5)
	b = bell(midi(87), 3.0) * 0.18
	place(L, b * 0.8, 1.6)
	place(R, b, 1.6)
	finish(room(L, 2.2, 0.35), room(R, 2.2, 0.35), "ident_velvet")


def ident_palm():
	bpm = 82.0
	beat = 60.0 / bpm
	sec = beat * 6 + 0.6
	n = int(sec * SR)
	L = crackle(sec)
	R = crackle(sec)
	tl, tr = stereo(tune_in(), 0.0)
	place(L, tl, 0.0)
	place(R, tr, 0.0)
	t0 = 0.4
	chords = [[53, 57, 60, 64], [52, 55, 59, 62]]  # Fmaj7, Em7
	for c, ch in enumerate(chords):
		for i, nn in enumerate(ch):
			l, r = stereo(rhodes(midi(nn), beat * 3, 0.5), -0.3 + i * 0.2)
			place(L, l, t0 + c * beat * 2 + i * 0.012)
			place(R, r, t0 + c * beat * 2 + i * 0.012)
	swing = beat * 0.58
	for b in range(5):
		at = t0 + b * beat
		if b % 2 == 0:
			k = kick() * 0.8
			place(L, k, at)
			place(R, k, at)
		else:
			s = onepole(snare(0.3, 180.0, 11.0), 3500.0) * 0.5
			place(L, s, at)
			place(R, s, at)
		place(L, hat() * 0.5, at)
		place(R, hat() * 0.6, at + swing)
	bass = pluck_bass(midi(41), beat * 2) * 0.55
	place(L, bass, t0)
	place(R, bass, t0)
	bass = pluck_bass(midi(40), beat * 2) * 0.55
	place(L, bass, t0 + beat * 2)
	place(R, bass, t0 + beat * 2)
	# Tape-ish: a soft low-pass over everything, a slow wow.
	L = onepole(L, 5200.0)
	R = onepole(R, 5200.0)
	finish(room(L, 1.0, 0.18), room(R, 1.0, 0.18), "ident_palm")


def ident_neon():
	bpm = 112.0
	step = 60.0 / bpm / 4.0
	sec = step * 24 + 1.4
	n = int(sec * SR)
	L = np.zeros(n)
	R = np.zeros(n)
	tl, tr = stereo(tune_in(), 0.0)
	place(L, tl, 0.0)
	place(R, tr, 0.0)
	t0 = 0.4
	arp = [57, 60, 64, 69, 64, 60, 57, 60, 64, 69, 72, 69, 65, 69, 72, 77, 72, 69, 65, 69, 72, 77, 81, 84]
	seq = np.zeros(n)
	for i, nn in enumerate(arp):
		s = supersaw(midi(nn), step * 1.6) * env_ad(int(step * 1.6 * SR), 0.003, 0.18)
		place(seq, s, t0 + i * step, 0.5)
	tt = np.arange(n) / SR
	cut = 400.0 + 5200.0 * np.clip((tt - t0) / (step * 24), 0, 1) ** 1.5
	seq = onepole(onepole(seq, cut), cut)
	l = seq + np.roll(seq, int(0.011 * SR)) * 0.5
	r = seq + np.roll(seq, int(0.017 * SR)) * 0.5
	L += l
	R += r
	for b, root in ((0, 45), (8, 45), (16, 41)):
		sub = np.sin(2 * np.pi * midi(root - 12) * t_axis(step * 8)) * env_ad(int(step * 8 * SR), 0.01, 1.2)
		place(L, sub * 0.6, t0 + b * step)
		place(R, sub * 0.6, t0 + b * step)
	for b in range(0, 24, 4):
		k = kick() * 0.9
		place(L, k, t0 + b * step)
		place(R, k, t0 + b * step)
	# The gated snare on the last downbeat, with its big room cut short.
	s = snare(0.6, 200.0, 5.0)
	s = room(s, 1.8, 0.9)
	s[int(0.32 * SR):] *= 0.0
	place(L, s * 0.6, t0 + 20 * step)
	place(R, s * 0.6, t0 + 20 * step)
	pd = pad([midi(65), midi(69), midi(72), midi(76)], 1.6, 2600.0) * 0.4
	place(L, pd, t0 + 22 * step)
	place(R, np.roll(pd, 200), t0 + 22 * step)
	finish(room(L, 1.6, 0.25), room(R, 1.6, 0.25), "ident_neon")


def ident_tiki():
	bpm = 100.0
	beat = 60.0 / bpm
	sec = beat * 7 + 0.8
	n = int(sec * SR)
	L = np.zeros(n)
	R = np.zeros(n)
	tl, tr = stereo(tune_in(), 0.0)
	place(L, tl, 0.0)
	place(R, tr, 0.0)
	t0 = 0.4
	motif = [(0, 72), (0.5, 76), (1.0, 79), (1.5, 83), (2.5, 81), (3.0, 79), (3.5, 76), (4.5, 79)]
	for at, nn in motif:
		l, r = stereo(vibes(midi(nn), 2.2, 0.55), 0.3)
		place(L, l, t0 + at * beat)
		place(R, r, t0 + at * beat)
	for at, nn in ((0, 48), (1.5, 55), (2.5, 53), (4.0, 48)):
		bs = pluck_bass(midi(nn), beat * 1.4) * 0.55
		place(L, bs, t0 + at * beat)
		place(R, bs, t0 + at * beat)
	for i in range(int(5.5 * 2)):
		sh = shaker() * (0.7 if i % 2 else 0.45)
		place(L, sh * 0.8, t0 + i * beat * 0.5)
		place(R, sh, t0 + i * beat * 0.5 + 0.01)
	chord = pad([midi(60), midi(64), midi(67), midi(71)], beat * 3, 1500.0) * 0.25
	place(L, chord, t0 + 4.5 * beat)
	place(R, chord, t0 + 4.5 * beat)
	finish(room(L, 1.8, 0.3), room(R, 1.8, 0.3), "ident_tiki")


def static_burst():
	sec = 0.7
	t = t_axis(sec)
	n = rng.standard_normal(len(t))
	n = n - onepole(n, 250.0)
	n = onepole(n, 7000.0)
	flutter = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 23.0 * t + np.sin(2 * np.pi * 7.0 * t)))
	whine = np.sin(2 * np.pi * np.cumsum(900 + 700 * np.sin(2 * np.pi * 2.3 * t)) / SR) * 0.06
	sig = (n * flutter + whine) * np.clip(t / 0.02, 0, 1) * np.clip((sec - t) / 0.2, 0, 1)
	finish(sig, onepole(sig, 6000.0), "static", 0.6)


def main():
	os.makedirs(OUT, exist_ok=True)
	only = sys.argv[1:]
	if not only or "tracks" in only:
		for name, src, start in TRACKS:
			encode_track(name, src, start)
	if not only or "idents" in only:
		ident_velvet()
		ident_palm()
		ident_neon()
		ident_tiki()
		static_burst()
	total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".ogg"))
	print("total %.2f MB" % (total / 1048576.0))


if __name__ == "__main__":
	main()
