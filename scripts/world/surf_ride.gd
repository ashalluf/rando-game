class_name SurfRide
extends RefCounted
## A surfer riding the wave that is DRAWN (wave 8, refcam5 `surf_dawn`, docs/HANDOFF.md "The surf at
## dawn from the water"). BeachActivity's ride used to slide the rider shoreward at the crests' speed
## at the biggest face's height (Surf.crest_height()) with no idea where the ocean shader's crests
## were: from the water he stood on a flat sea or inside the back of a wave. Here the rider locks onto
## one wave n of surf.gdshaderinc's train - the crest of wave n is where its phase is a whole number,
##     (s + wob(p)) / L + t / T = n   ->   s_c = (n - t / T) * L - wob(p)
## - and sits `FACE_SHARE` of the front face landward of that crest, on SeaSurface.height() (the
## ocean's vertex stage in GDScript), the board pitched to the face's slope. Time is SeaSurface.now()
## (the shader's TIME), or 0 while the refcams / DIFF stills hold TIME at its first instant.
##
## Staged stills (BEACH_STAGE): `stage_pick()` looks along the shore round the staged z for the place
## and the wave where a SET wave (gain over STAGE_GAIN) is just throwing its lip (crest at STAGE_SIG
## of its own break distance), so the frame always holds a wave worth riding.
##
## RC5_SURF_DAWN=0 is the A/B (the old ride, and the old water / spray tunings in BeachActivity and
## the ocean material: see RcSurfDawn).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_SURF_DAWN") != "0"

## Where on the front face the rider stands: a share of the face's width (surf_profile()'s `wf` x L)
## landward of the crest. 0.35: high on the face, under the lip, where a trimming surfer is.
const FACE_SHARE := 0.35
## A staged wave: its gain at least this (a set wave), its crest at this share of its break distance.
const STAGE_GAIN := 1.08
const STAGE_SIG := 0.94
## How far along the shore (m) the stage looks either side of the staged z, in steps of STAGE_STEP.
const STAGE_REACH := 40.0
const STAGE_STEP := 0.5


static func _wob(p: Vector2) -> float:
	return 9.0 * (SeaSurface.vnoise(p / 95.0) - 0.5) + 4.0 * (SeaSurface.vnoise(p / 33.0 + Vector2(7.3, 7.3)) - 0.5)


## The point `s` metres offshore at z (TRUE world XZ): the coast's own x less s.
static func point(m: MacroMap, z: float, s: float) -> Vector2:
	return Vector2(m.coast_x(z) - s, z)


## Metres offshore of wave n's crest at z, time t: two fixed-point passes (wob reads the point).
static func crest_s(m: MacroMap, shape: Vector4, z: float, n: float, t: float) -> float:
	var L := maxf(shape.y, 1.0)
	var T := maxf(shape.z, 0.5)
	var s := (n - t / T) * L
	for i in 2:
		s = (n - t / T) * L - _wob(point(m, z, s))
	return s


## The wave whose crest is nearest seaward of `s` at z, time t (the one a surfer there catches).
static func wave_at(m: MacroMap, shape: Vector4, z: float, s: float, t: float) -> float:
	var L := maxf(shape.y, 1.0)
	var T := maxf(shape.z, 0.5)
	var phi := (s + _wob(point(m, z, s))) / L + t / T
	return ceilf(phi)


## The width of the front face (m) at s: surf_profile()'s front share at the mean wave's steepness.
static func face_width(shape: Vector4, extra: Vector4, s: float) -> float:
	var steep: float = Surf.envelope(shape, extra, s, 1.0).z
	return lerpf(0.40, 0.13, steep) * maxf(shape.y, 1.0)


## Where the rider of wave n stands at z, time t: [s offshore, the surface's height there, its slope
## along the way to the land (dh/ds, positive where the face rises seaward)].
static func ride_point(m: MacroMap, st: Array, z: float, n: float, t: float) -> Vector3:
	var shape: Vector4 = st[2]
	var extra: Vector4 = st[3]
	var sc := crest_s(m, shape, z, n, t)
	var s := sc - face_width(shape, extra, maxf(sc, 0.0)) * FACE_SHARE
	var p := point(m, z, s)
	var y := SeaSurface.height(m, p, t, st)
	var y_sea := SeaSurface.height(m, point(m, z, s + 0.6), t, st)
	var y_land := SeaSurface.height(m, point(m, z, s - 0.6), t, st)
	return Vector3(s, y, (y_sea - y_land) / 1.2)


## The gain of wave n at z (surf_wave_gain()).
static func gain(m: MacroMap, shape: Vector4, z: float, n: float) -> float:
	return SeaSurface._wave_gain(n, point(m, z, crest_s(m, shape, z, n, 0.0)))


## A staged ride round z at time t: [z, n] of the best place along the shore within STAGE_REACH -
## the set wave whose crest is nearest STAGE_SIG of its own break point - or [z, n of the nearest
## crest past the break] if no set wave is there.
static func stage_pick(m: MacroMap, st: Array, z: float, t: float) -> Vector2:
	var shape: Vector4 = st[2]
	var brk := maxf(shape.w, 2.0)
	var best := Vector2(z, wave_at(m, shape, z, brk, t))
	var best_err := INF
	var dz := -STAGE_REACH
	while dz <= STAGE_REACH + 0.001:
		var zz := z + dz
		var n0 := wave_at(m, shape, zz, brk * 0.6, t)
		for k in 3:
			var n := n0 + float(k)
			var sc := crest_s(m, shape, zz, n, t)
			var g := SeaSurface._wave_gain(n, point(m, zz, sc))
			var bg := maxf(brk * pow(g, 0.8), 2.0)
			var err := absf(sc / bg - STAGE_SIG) + maxf(STAGE_GAIN - g, 0.0) * 3.0 + absf(dz) * 0.004
			if err < best_err:
				best_err = err
				best = Vector2(zz, n)
		dz += STAGE_STEP
	return best


## The time the shaders draw (0 while TIME is held: refcams, DIFF stills).
static func now() -> float:
	var held := float(ProjectSettings.get_setting("rendering/limits/time/time_rollover_secs", 3600.0)) < 0.01
	return 0.0 if held else SeaSurface.now()
