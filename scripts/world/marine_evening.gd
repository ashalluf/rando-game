class_name MarineEvening
extends RefCounted
## The marine layer's evening bank from the beach (refcam `marine_evening`,
## tools/refcams/cameras_w8.json: 18:30, weather marine, the sand beside a lifeguard tower looking
## west-south-west at the fog standing ~1.6 km offshore). What it gives that the old bank did not:
##
## - THE WALL: marine_layer.gdshader mode 2 under `bank_look` 1 - the foot sunk under the water
##   (the old foot faded out over its first metres and the sky's glowing horizon showed under the
##   whole bank as an orange line), taller rounder crest domes, billowed cauliflower rolls lit from
##   above by the twilight sky, a slate body, a paler foot in the sea haze, and the crest's thin
##   fringe glowing in the afterglow behind it (`rim()`); the old one was one flat grey smear a
##   shade darker than the sky.
## - THE PEOPLE LEAVING: at the end of a beach day (LEAVE_FROM .. LEAVE_TO) BeachActivity adds
##   `leavers()` walkers in street clothes carrying their things up the sand to the path and the
##   town (BeachWalker.leaving), on top of the day's own (who stay in swimwear on the wet sand).
##
## `MARINE_EVENING=0` in the environment turns both off (the A/B).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("MARINE_EVENING") != "0"

## Hours the beach empties over (the sun sets at 18:00 in this game's clock).
const LEAVE_FROM := 17.4
const LEAVE_TO := 19.8
## Leavers a full beach stretch (BeachLife.CELL_Z cells of a chunk) puts on the sand at the peak.
const LEAVERS := 14
## How much brighter than the horizon the crest's fringe glows, and its warm lean (linear).
const RIM_GAIN := 1.5
const RIM_WARM := Color(1.0, 0.82, 0.7)
## What is left of the directional light's shadows in the blue hour (twilight_shadow()).
const TWILIGHT_SHADOW := 0.25


## The directional light's shadow opacity factor in twilight. Once the sun is down DayNight's one
## light turns to the moon, which lands crisp full-strength shadows across the sand (a palm's
## fronds black on the beach at 18:30) while the blue-hour sky - far brighter than a moon still
## low in a light sky - is what really lights the ground: shadows soften to almost nothing. They
## come back as the night deepens (moonlight toward 1). 1 everywhere else, and while off.
static func twilight_shadow(elevation: float, moonlight: float) -> float:
	if not enabled:
		return 1.0
	var tw := smoothstep(0.02, -0.05, elevation) * (1.0 - smoothstep(0.55, 0.95, moonlight))
	return lerpf(1.0, TWILIGHT_SHADOW, tw)


## marine_layer.gdshader `bank_look` (1 the wall, 0 the old ribbon).
static func bank_look() -> float:
	return 1.0 if enabled else 0.0


## The crest fringe's colour (linear): the twilight horizon this frame, warmed by the sun's own
## colour and lifted, faded into the night by `moon` (DayNight.moonlight_now).
static func rim(horizon: Color, sun_col: Color, moon: float) -> Color:
	var c := horizon.lerp(sun_col * RIM_WARM, 0.25) * RIM_GAIN
	return c.lerp(Color(0.02, 0.022, 0.03), clampf(moon, 0.0, 1.0))


## How many leavers a stretch carries at `hour` (0 outside the evening; a pure function of the
## hour and the day's beach density - the stretch's own hash scatters it in BeachActivity).
static func leavers(hour: float, dens: float) -> int:
	if not enabled:
		return 0
	var h := fposmod(hour, 24.0)
	if h < LEAVE_FROM or h > LEAVE_TO:
		return 0
	# Rising as the sun goes, falling as the beach is empty; never more than the morning's crowd.
	var w := smoothstep(LEAVE_FROM, 18.2, h) * (1.0 - smoothstep(19.0, LEAVE_TO, h))
	return roundi(float(LEAVERS) * w * clampf(0.35 + dens * 3.0, 0.0, 1.0))


## Puts a FULL beach chunk's leavers on the sand (BeachLife.build()), in the crowd cap, as build
## steps; every roll a hash of seed + chunk + index, never a chunk rng.
static func add_leavers(ch: CityChunk, z0: float, z1: float, hour: float, dens: float) -> void:
	var n := leavers(hour, dens)
	if OS.get_environment("ME_DEBUG") != "":
		print("MARINE_EVENING leavers %d chunk %d,%d z %.0f..%.0f hour %.2f dens %.2f" % [n, ch.ix, ch.iz, z0, z1, hour, dens])
	for i in n:
		ch._run_or_defer(func() -> bool:
			_add_leaver(ch, z0, z1, i, n)
			return true)


static func _hf(plan: CityPlan, ch: CityChunk, parts: Array) -> float:
	return float(absi(hash([plan.seed, ch.ix, ch.iz, "marine_evening"] + parts)) % 100003) / 100003.0


static func _add_leaver(ch: CityChunk, z0: float, z1: float, i: int, leavers_now: int) -> void:
	if not ch._take_crowd_room():
		if OS.get_environment("ME_DEBUG") != "":
			print("MARINE_EVENING no crowd room for leaver %d" % i)
		return
	var plan := ch.plan
	var macro: MacroMap = plan.macro
	var model: int = BeachGoer.BEACH_MODELS[absi(hash([plan.seed, ch.ix, ch.iz, "me_model", i])) % BeachGoer.BEACH_MODELS.size()]
	var w := BeachWalker.new()
	w.plan_ref = plan
	w.clothed = true
	w.leaving = true
	w.z_lo = z0 + 2.0
	w.z_hi = z1 - 2.0
	# A third carry their board home.
	if _hf(plan, ch, ["board", i]) < 0.34:
		w.board = absi(hash([plan.seed, ch.ix, ch.iz, "me_board", i])) % BeachLife.BOARDS.size()
	w.setup(BeachLife.sand_ring(ch, z0, z1), 4.0, BeachGoer.seed_for(model, 60 + i))
	# Somewhere down the beach toward the water: they walk up from there.
	# They go in twos as often as alone: a pair shares a spot, side by side.
	var g := i if _hf(plan, ch, ["pair", i / 2]) < 0.4 else i / 2 * 2
	# Spread along the stretch (stratified, jittered): a beach empties all along it, not in clumps.
	var n := maxi(leavers_now, 1)
	var z := lerpf(z0 + 4.0, z1 - 4.0, (float(g) + 0.1 + 0.8 * _hf(plan, ch, ["z", g])) / float(n)) + (1.1 if g != i else 0.0)
	var x := macro.coast_x(z) + macro.beach_width_at(z) * lerpf(0.03, 0.4, _hf(plan, ch, ["x", g])) + (0.4 if g != i else 0.0)
	w.position = Vector3(x, BeachLife.sand_y(ch, x, z) + 0.1, z)
	ch.add_child(w)
	if OS.get_environment("ME_DEBUG") != "":
		print("MARINE_EVENING leaver %d at %s" % [i, w.position])
