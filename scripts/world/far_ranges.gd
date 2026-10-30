class_name FarRanges
extends RefCounted
## The back range and the east range as massive ridgelines instead of rows of teeth (fleet wave 3,
## "far-ranges"; docs/HANDOFF.md "The far ranges").
##
## From the basin both read as evenly spaced cones. Three things made them, in this order:
## 1. The base. Each range was a plateau (full height from `*_full` to the map's edge) whose height
##    was the map noise's two octaves at 830 m and 415 m, +-34 % of the range's height. Seen over
##    the plateau's three kilometres of depth, the skyline is whichever bump of that field stands
##    highest at each bearing: a summit every few hundred metres, each 300-400 m tall.
## 2. The erosion. The front range's 440 m canyon spacing at a quarter of the range's height cut a
##    1,150 m range into 300 m deep notches every 440 m, walls over 50 degrees: every spur a spike.
## 3. The crags on the horizon plane (macro_relief.gdshaderinc): ridged noise, 1 - |n|, whose crests
##    are creases - a jagged saw along every far skyline.
## So here: each range is a CREST LINE (`crest_profile()`: the front face up to a crest that wanders
## across the range, a high shoulder behind it, then a long fall away from the basin), its height
## along the crest a slow massing (`MASS_FREQ`, a few summits kilometres apart) over a little of
## the old noise; its canyons twice as far apart (`BACK_SPACING` / `EAST_SPACING`), so the spurs
## between them are massive; and the plane's crags turned over (`crag_shape` 1: |n|, round crests
## and creased valleys, the way a weathered range lies). The front range is not touched: the sign,
## the observatory, the hill roads, estates, reservoir and ballpark are laid on it.
##
## Everything is pure (seed and position) and lives in MacroMap.raw_height_at(), so the streamed
## hill tiles, the bake, the planting and every far shader keep agreeing. `enabled` false is the
## old shape exactly (FAR_RANGES=0).

static var enabled: bool = OS.get_environment("FAR_RANGES") != "0" and not OS.get_cmdline_user_args().has("--no-far-ranges")

## The massing noise's frequency (1 / metres): ~3.6 km between the big summits.
const MASS_FREQ := 0.00028
## Its second octave's share: a little, so a summit massif has a shoulder or two, not a twin.
const MASS_GAIN := 0.35
## The crest line's wander across the range (metres either way) and its own frequency. It must stay
## well under CREST_IN: a crest pulled onto the old full-height line made the rise a step - a
## 150 m wall a few metres wide.
const CREST_WANDER := 420.0
const CREST_FREQ := 0.00022
## Metres from the old "full height" line to the crest (into the range), the shoulder behind it,
## and how far the land falls (share of the crest's height) over `FALL_RUN` metres past it.
const CREST_IN := 700.0
const SHOULDER := 1100.0
const FALL := 0.42
const FALL_RUN := 3600.0
## Canyon spacing (metres) on the back and east ranges, against MacroMap.erosion_spacing 440.
const BACK_SPACING := 980.0
const EAST_SPACING := 820.0
## Canyon depth (share of the range's height, ridge to floor) on the back range: deeper than the
## old 0.26 - the San Gabriels' canyons are their whole character - but further apart.
const BACK_DEPTH := 0.34
const EAST_DEPTH := 0.28
## Each finer order of canyons against the one above (MacroMap.erosion_gain is 0.5): the 245 m
## gullies at a quarter of the main canyons' depth were the crumple that stood up as small teeth
## along every crest; at 0.4 they are 16 %.
const EROSION_GAIN := 0.4


## 0..1 across a range: the old front face (smoothstep from `start_u` to `full_u`, exactly, so the
## range's foot - where zone_at() turns CITY into HILLS - stays where it was), on up to the crest,
## then a long fall away from the basin. `u` is how far into the range the point is (metres,
## increasing away from the basin), `wander` -1..1 moves the crest. Returns [profile, face share]:
## the face share (the old ramp alone) is what the old height factor hands over to the new by.
static func crest_profile(u: float, start_u: float, full_u: float, wander: float) -> Vector2:
	var face := smoothstep(start_u, full_u, u)
	var crest := full_u + CREST_IN + wander * CREST_WANDER
	# 1 at the foot (the old ramp exactly), easing to 0.82 at the full-height line and back up to 1
	# at the crest: the face is the old one where the city meets it, the crest a ridge behind.
	var rise := lerpf(1.0, 0.82 + 0.18 * smoothstep(full_u, crest, u), face)
	var past := maxf(u - crest - SHOULDER, 0.0)
	var fall := FALL * smoothstep(0.0, FALL_RUN, past)
	return Vector2(face * rise * (1.0 - fall), face)


## The back range's height before erosion (`zs` the embay-shifted z, `n` the map's two octaves,
## `mass` the massing noise, `wander` the crest noise; all -1..1). At the foot it is the old
## factor (0.62 + 0.34 n), handed over to the massing as the face rises.
static func back_base(zs: float, start_z: float, full_z: float, height: float, n: float, mass: float, wander: float) -> float:
	# z falls going north, into the range.
	var p := crest_profile(-zs, -start_z, -full_z, wander)
	return p.x * height * lerpf(0.62 + 0.34 * n, 0.74 + 0.30 * mass + 0.07 * n, p.y)


static func east_base(x: float, start_x: float, full_x: float, height: float, n: float, mass: float, wander: float) -> float:
	var p := crest_profile(x, start_x, full_x, wander)
	return p.x * height * lerpf(0.62 + 0.32 * n, 0.72 + 0.30 * mass + 0.07 * n, p.y)


## How much of the canyons' depth is cut at `u` across a range (same measures as crest_profile()):
## all of it down the face, `CREST_KEEP` of it from the crest line over the shoulder behind it,
## easing back over `CREST_SOFT` metres either side. A canyon cuts its head back into a crest as a saddle, not as a notch to the foot: cut to
## full depth, the main canyons split the crest into a row of free-standing cones.
const CREST_KEEP := 0.3
const CREST_SOFT := 950.0
static func erosion_share(u: float, full_u: float, wander: float) -> float:
	var crest := full_u + CREST_IN + wander * CREST_WANDER
	# Behind the crest the high shoulder is held too, until the land starts its long fall: its
	# canyons, cut full depth, stood up over the crest as a second row of little teeth.
	var off := u - crest
	var from := -off if off < 0.0 else maxf(off - SHOULDER, 0.0)
	return lerpf(CREST_KEEP, 1.0, smoothstep(0.0, CREST_SOFT, from))


## A skyline (elevation angles, degrees, one per column `step` degrees apart) measured: peaks that
## stand more than `PEAK_PROMINENCE` degrees over the lower of the two cols either side within
## `PEAK_WINDOW` degrees, the mean absolute second difference per degree (how sharp it is), the mean.
const PEAK_PROMINENCE := 0.25
const PEAK_WINDOW := 2.5
static func skyline_stats(sky: PackedFloat32Array, step: float) -> Dictionary:
	var n := sky.size()
	var win := maxi(int(PEAK_WINDOW / maxf(step, 0.0001)), 2)
	var peaks := 0
	var sharp := 0.0
	var mean := 0.0
	for i in n:
		mean += sky[i]
		if i > 0 and i < n - 1:
			sharp += absf(sky[i - 1] - 2.0 * sky[i] + sky[i + 1]) / (step * step)
			if sky[i] >= sky[i - 1] and sky[i] > sky[i + 1]:
				var lo_l := sky[i]
				var lo_r := sky[i]
				var top := true
				for k in range(1, win + 1):
					if i - k >= 0:
						if sky[i - k] > sky[i]:
							top = false
						lo_l = minf(lo_l, sky[i - k])
					if i + k < n:
						if sky[i + k] > sky[i]:
							top = false
						lo_r = minf(lo_r, sky[i + k])
				if top and sky[i] - maxf(lo_l, lo_r) > PEAK_PROMINENCE:
					peaks += 1
	return {"peaks": peaks, "sharp": sharp / maxf(n - 2, 1) * step, "mean": mean / maxf(n, 1)}


## The horizon plane's crag shape on a material that includes macro_relief.gdshaderinc.
static func apply(m: ShaderMaterial) -> void:
	m.set_shader_parameter("crag_shape", 1.0 if enabled else 0.0)
	if not enabled:
		m.set_shader_parameter("range_haze", 0.0)
