#!/usr/bin/env python3
"""Frame strips of a slow camera move, and a flicker measure of them (specular-aliasing pass).

Shimmer and crawl only show in motion: a still of a chain-link fence or a wet road can look clean
while every frame of a slow pan pops. So: shoot N frames of a camera moving a fraction of a pixel a
frame (tools/glshot/still_shot.gd, one load, DIFF=1 so nothing but the camera moves and shader TIME
is held), then measure, per pixel, the SECOND temporal difference |f[k+1] - 2 f[k] + f[k-1]|. A
well-filtered image moving slowly is near linear in time and gives ~0; an aliased edge, a sparkle or
a dithered cut-out that jumps from texel to texel gives its full contrast.

  GODOT=/path/godot python3 tools/specular_aliasing/strip.py run build/strip/street \
      --eye 2359.4,2,880,0,2 --agl --step yaw=0.02 --frames 10 --hour 12 [--weather rain] \
      [--res 1920x1080] [--fov 55] [--env NAME=V ...]
  python3 tools/specular_aliasing/strip.py measure build/strip/street [--crop x,y,w,h]
  python3 tools/specular_aliasing/strip.py compare build/strip/before build/strip/after [--crop ...]

--step takes yaw / pitch (degrees a frame), right / up / fwd (metres a frame, in the camera's frame).
measure writes heat.png (the mean |d2|, x4) and prints the score: MEAN (whole frame, /255), P99,
FLICKER (share of pixels whose mean |d2| > 6/255) and the worst 16 tiles of a 16 x 9 grid.
compare prints both scores and writes side.jpg: before / after heat maps and the first frames.
"""
import math, os, subprocess, sys, json
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _args(argv):
	opts = {"env": []}
	pos = []
	i = 0
	while i < len(argv):
		a = argv[i]
		if a.startswith("--"):
			k = a[2:]
			if k in ("agl",):
				opts[k] = True
			elif k == "env":
				opts["env"].append(argv[i + 1]); i += 1
			else:
				opts[k] = argv[i + 1]; i += 1
		else:
			pos.append(a)
		i += 1
	return pos, opts


def eyes(eye, step, frames):
	x, y, z, yaw, pitch = [float(v) for v in eye.split(",")]
	st = {}
	for part in step.split(","):
		k, v = part.split("=")
		st[k] = float(v)
	out = []
	for k in range(frames):
		yw = math.radians(yaw)
		# yaw 0 looks north (-z), 90 west (-x): forward = (-sin, 0, -cos), right = (cos, 0, -sin).
		fwd = (-math.sin(yw), 0.0, -math.cos(yw))
		right = (math.cos(yw), 0.0, -math.sin(yw))
		out.append("%.4f,%.4f,%.4f,%.4f,%.4f" % (x, y, z, yaw, pitch))
		x += right[0] * st.get("right", 0) + fwd[0] * st.get("fwd", 0)
		z += right[2] * st.get("right", 0) + fwd[2] * st.get("fwd", 0)
		y += st.get("up", 0)
		yaw += st.get("yaw", 0)
		pitch += st.get("pitch", 0)
	return out


def run(out_dir, o):
	godot = os.environ.get("GODOT", "godot")
	os.makedirs(out_dir, exist_ok=True)
	frames = int(o.get("frames", 10))
	ev = eyes(o["eye"], o.get("step", "yaw=0.02"), frames)
	hour = o.get("hour", "12")
	fov = o.get("fov", "55")
	w = o.get("weather", "")
	tail = "@%s@%s%s" % (hour, fov, ("@" + w) if w else "")
	env = dict(os.environ)
	env.update({
		"OUT": os.path.abspath(os.path.join(out_dir, "f.png")),
		"EYE": ev[0], "SHOTS": ";".join(e + tail for e in ev[1:]),
		"DIFF": "1", "SHOT_FRAMES": "0", "SETTLE": o.get("settle", "2"), "FOV": fov,
		"FRAMES": o.get("warm", "30"),
	})
	if o.get("agl"):
		env["EYE_AGL"] = "1"
	for kv in o["env"]:
		k, v = kv.split("=", 1)
		env[k] = v
	res = o.get("res", "1920x1080")
	rw, rh = res.split("x")
	args = ["xvfb-run", "-a", "-s", "-screen 0 %sx%sx24" % (rw, rh), godot, "--rendering-driver",
		o.get("driver", "opengl3"), "--display-driver", "x11", "--audio-driver", "Dummy", "--path", ROOT,
		"--script", "tools/glshot/still_shot.gd", "--resolution", res, "--",
		"--spawn=%s" % ",".join(ev[0].split(",")[0:1] + ev[0].split(",")[2:3] + ["0", "0"]),
		"--hour=%s" % hour, "--nohud", "--quality=%s" % o.get("quality", "0")]
	if w:
		args.append("--weather=%s" % w)
	print(" ".join(args))
	with open(os.path.join(out_dir, "run.log"), "w") as log:
		r = subprocess.run(args, env=env, stdout=log, stderr=subprocess.STDOUT)
	print("exit", r.returncode, "log", os.path.join(out_dir, "run.log"))


def frames_of(d):
	fs = [os.path.join(d, "f.png")]
	k = 1
	while os.path.exists(os.path.join(d, "f_%d.png" % k)):
		fs.append(os.path.join(d, "f_%d.png" % k))
		k += 1
	return [f for f in fs if os.path.exists(f)]


def load(d, crop=None):
	ims = []
	for f in frames_of(d):
		im = Image.open(f).convert("RGB")
		if crop:
			x, y, w, h = crop
			im = im.crop((x, y, x + w, y + h))
		ims.append(np.asarray(im).astype(np.float32))
	return ims


def heat_of(ims):
	# The first frame had the long warm-up at full speed; skip it if the strip is long enough.
	if len(ims) >= 6:
		ims = ims[1:]
	lum = [im @ np.array([0.2126, 0.7152, 0.0722], np.float32) for im in ims]
	acc = np.zeros_like(lum[0])
	for k in range(1, len(lum) - 1):
		acc += np.abs(lum[k + 1] - 2 * lum[k] + lum[k - 1])
	return acc / max(1, len(lum) - 2)


def score(heat):
	gh, gw = 9, 16
	h, w = heat.shape
	tiles = []
	for j in range(gh):
		for i in range(gw):
			t = heat[j * h // gh:(j + 1) * h // gh, i * w // gw:(i + 1) * w // gw]
			tiles.append((float(t.mean()), i, j))
	tiles.sort(reverse=True)
	return {
		"mean": float(heat.mean()), "p99": float(np.percentile(heat, 99)),
		"flicker": float((heat > 6.0).mean()), "tiles": tiles[:16],
	}


def measure(d, crop=None, quiet=False):
	ims = load(d, crop)
	heat = heat_of(ims)
	s = score(heat)
	Image.fromarray(np.clip(heat * 4.0, 0, 255).astype(np.uint8)).save(os.path.join(d, "heat.png"))
	if not quiet:
		print("%s: %d frames  MEAN %.3f  P99 %.2f  FLICKER %.4f" % (d, len(ims), s["mean"], s["p99"], s["flicker"]))
		print("  worst tiles (mean, col, row of 16x9):", ", ".join("%.2f@%d,%d" % t for t in s["tiles"][:10]))
	return s, heat, ims


def compare(a, b, crop=None):
	sa, ha, ia = measure(a, crop)
	sb, hb, ib = measure(b, crop)
	print("delta MEAN %+.1f%%  FLICKER %+.1f%%" % (100 * (sb["mean"] / max(1e-6, sa["mean"]) - 1), 100 * (sb["flicker"] / max(1e-6, sa["flicker"]) - 1)))
	h = lambda x: Image.fromarray(np.clip(x * 4.0, 0, 255).astype(np.uint8)).convert("RGB")
	f = lambda x: Image.fromarray(x.astype(np.uint8))
	top = [f(ia[len(ia) // 2]), f(ib[len(ib) // 2])]
	bot = [h(ha), h(hb)]
	W, H = top[0].size
	sheet = Image.new("RGB", (W * 2, H * 2))
	for i in range(2):
		sheet.paste(top[i], (i * W, 0)); sheet.paste(bot[i], (i * W, H))
	if sheet.size[0] > 1280:
		sheet = sheet.resize((1280, int(sheet.size[1] * 1280 / sheet.size[0])), Image.LANCZOS)
	sheet.save(os.path.join(b, "side.jpg"), quality=88)


if __name__ == "__main__":
	pos, o = _args(sys.argv[1:])
	crop = tuple(int(v) for v in o["crop"].split(",")) if "crop" in o else None
	if pos[0] == "run":
		run(pos[1], o)
		measure(pos[1], crop)
	elif pos[0] == "measure":
		measure(pos[1], crop)
	elif pos[0] == "compare":
		compare(pos[1], pos[2], crop)
