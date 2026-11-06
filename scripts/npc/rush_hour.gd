class_name RushHour
extends RefCounted
## The freeway at rush hour (fleet wave 8, refcam `rush_hour`: the 105 at 17:40 from a footbridge
## looking into the low sun). Before this the hour only changed how many of FreewayFill's slots
## stayed empty (FreewayCloseup.spawn_skip()): at 17:40 the deck held a car per ~45 lane-metres,
## every one doing 26 m/s, nobody braking - a quiet Sunday, not Los Angeles at 5:40 pm.
##
## `level(hour)` is how jammed the freeway is (0 outside the rushes, 1 at their peak). It scales,
## all by that one number:
## - the slots: FreewayFill's lanes get a slot every `gap()` metres (42 -> RUSH_GAP 19),
## - the cap: FreewayFill.CAP_GAIN -> RUSH_CAP_GAIN (more cars, mostly on the route under the
##   player as before),
## - the standing gap of the follow rule (freeway_gap * 0.6 = 20 m -> RUSH_STAND 8.5 m: bumper to
##   bumper is a couple of metres, not a lane's length),
## - and the flow's speed: a STOP-AND-GO wave, `wave_cap()`, a speed limit along each carriageway
##   that is low in bands `WAVE_LEN` apart and runs UPSTREAM at `WAVE_SPEED` (a jam's front moves
##   backward against the traffic, which is what makes the brake lights come on in clusters and go
##   off again as a car drives out of the slow band). Everyone keeps their own speed under it.
## Pure functions of (hour, route, direction, t, clock): no rng, nothing per car is stored.
## `RUSH_HOUR=0` in the environment is the A/B: the fill, the cap, the follow rule and the speeds
## exactly as they were. A staged TrafficManager (tests, stills that place cars) is never jammed.

static var enabled := OS.get_environment("RUSH_HOUR") != "0"

## The two rushes: [start of the ramp up, full, full until, ramp down ends], hours.
const MORNING := [6.25, 7.25, 9.0, 10.0]
const EVENING := [15.25, 16.5, 18.75, 19.75]
## A lane's slot spacing at the peak (FreewayFill.LANE_GAP 42 off peak).
const RUSH_GAP := 19.0
## FreewayFill.CAP_GAIN at the peak (1.5 off peak).
const RUSH_CAP_GAIN := 2.6
## The follow rule's standing gap at the peak, metres between two cars' centres less their
## lengths past 4.8 m (TrafficManager._fw_follow(): freeway_gap * 0.6, 20.4 m, off peak).
const RUSH_STAND := 8.5
## The stop-and-go wave: metres between slow bands, how fast a band runs back up the traffic
## (m/s), the share of the freeway speed left in a band's middle, and the share between bands.
const WAVE_LEN := 420.0
const WAVE_SPEED := 4.5
const WAVE_LOW := 0.12
const WAVE_HIGH := 0.62
## How much of the wave's length is slow (the rest is the free gap between jams).
const WAVE_SLOW := 0.42

## At the rushes the fill is spent where the camera looks (a jam is only a jam if the lanes in
## front of you are full): when the camera looks along the route under it (|cos| > LOOK_ALONG), no
## car is offered or kept more than BEHIND metres behind it, and the stretch just behind it (out of
## view, KEEP_CLEAR..BEHIND) is a source of new cars like the far inflow band, so the carriageway
## driving away from the lens fills from behind it as it would in life.
const LOOK_ALONG := 0.5
const BEHIND := 90.0
## ...and none kept more than AHEAD metres ahead (FreewayFill.retire_reach() is 580): at the cap a
## carriageway driving away from the lens kept its cars for 670 m and the one coming at it for 470,
## so the lanes leaving the camera ran thin; past ~470 m a car is a few pixels and the far decks'
## own traffic carries on.
const AHEAD := 470.0

## FreewayFill.FAR_WEIGHT at the peak: a route the player is not on gets less of the cap.
const RUSH_FAR_WEIGHT := 0.1

## The level the TrafficManager worked out at its last upkeep (so the per-car calls are cheap).
static var now_level := 0.0
## 1 while the player is on or over a route (within FreewayFill.NEAR_ROUTE) and the camera looks
## along it at a jam, else 0 (RcRushHour's traffic haze reads it).
static var now_view := 0.0


## Whether the freeway upkeep may spawn although PhysicsBudget is at its cap. Freeway cars are
## kinematic and placed, never simulated, like the street cars BusyStreets.traffic_room() already
## lets through: a busy city sits at the body cap, and the freeway upkeep returned before it
## spawned a car - the 105 by Vernon was EMPTY at any hour on main (the rush_hour refcam's
## before). The traffic's own caps bound it; the bodies that are not traffic still fit the budget.
static func freeway_room(tm: TrafficManager) -> bool:
	return enabled and BusyStreets.traffic_room(tm)


## +1 / -1 when the camera (true world `eye_fwd`, flat) looks along route direction `d` (+t / -t),
## 0 when it looks across it (or there is no jam).
static func look_sign(lv: float, eye_fwd: Vector3, d: Vector2) -> int:
	if lv <= 0.0:
		return 0
	var c := eye_fwd.x * d.x + eye_fwd.z * d.y
	return 0 if absf(c) < LOOK_ALONG else (1 if c > 0.0 else -1)


## Whether a car (or a slot) `t` metres along, the camera at `anchor` looking `look`, is too far
## behind the camera (or too far ahead of it) to spend a car on.
static func behind(t: float, anchor: float, look: int) -> bool:
	if look == 0:
		return false
	var d := (t - anchor) * float(look)
	return d < -BEHIND or d > AHEAD


## Whether a free slot is offered: the old rule (`filling` the whole window, else the far inflow
## band) plus, while the camera looks along the route, the out-of-view stretch just behind it and
## never past BEHIND behind it.
static func offer(t: float, anchor: float, look: int, filling: bool) -> bool:
	var d := (t - anchor) * float(look) if look != 0 else absf(t - anchor)
	if look == 0:
		return filling or d >= FreewayFill.INFLOW_FROM
	if d < -BEHIND:
		return false
	if d < 0.0:
		return -d >= FreewayFill.KEEP_CLEAR
	return filling or d >= FreewayFill.INFLOW_FROM


## 0..1: how jammed the freeway is at `hour`.
static func level(hour: float) -> float:
	if not enabled:
		return 0.0
	var h := fposmod(hour, 24.0)
	return maxf(_bump(h, MORNING), _bump(h, EVENING))


static func _bump(h: float, k: Array) -> float:
	return smoothstep(float(k[0]), float(k[1]), h) * (1.0 - smoothstep(float(k[2]), float(k[3]), h))


## A lane's slot spacing at level `lv` (metres).
static func gap(lv: float) -> float:
	return lerpf(FreewayFill.LANE_GAP, RUSH_GAP, clampf(lv, 0.0, 1.0))


## The freeway car cap's gain at level `lv`.
static func cap_gain(lv: float) -> float:
	return lerpf(FreewayFill.CAP_GAIN, RUSH_CAP_GAIN, clampf(lv, 0.0, 1.0))


## FreewayFill.shares()' far_weight at level `lv`.
static func far_weight(lv: float) -> float:
	return lerpf(FreewayFill.FAR_WEIGHT, RUSH_FAR_WEIGHT, clampf(lv, 0.0, 1.0))


## The follow rule's standing gap at level `lv`, from the old one (`base`, freeway_gap * 0.6).
static func stand_gap(base: float, lv: float) -> float:
	return lerpf(base, minf(base, RUSH_STAND), clampf(lv, 0.0, 1.0))


## 0..1 along the wave at route distance `t` for traffic driving `dir` at `clock` seconds: 0 is the
## middle of a slow band. `s` = t * dir is the distance in the direction of travel; the band runs
## toward smaller s (upstream) at WAVE_SPEED. Each (route, direction) has its own phase.
static func wave_phase(ri: int, dir: int, t: float, clock: float) -> float:
	var off := float(posmod((ri + 3) * 7919 + (dir + 2) * 104729, 1000)) / 1000.0
	return fposmod((t * float(dir) + clock * WAVE_SPEED) / WAVE_LEN + off, 1.0)


## The speed limit the wave puts on a car (m/s), `free` the freeway speed, at level `lv`. Smooth
## (a car meets it as a gentle brake over ~100 m, the lamps' 0.8 m/s2), lowest mid-band.
static func wave_cap(free: float, lv: float, ri: int, dir: int, t: float, clock: float) -> float:
	if lv <= 0.0:
		return INF
	var p := wave_phase(ri, dir, t, clock)
	# Distance from the band's middle as a share of the slow part, 0 in the middle, 1 at its edge.
	var d := minf(p, 1.0 - p) / (WAVE_SLOW * 0.5)
	var k := smoothstep(0.0, 1.0, d) if d < 1.0 else 1.0
	# Between bands the flow speeds up toward WAVE_HIGH, never the free speed (it is still a rush).
	var share := lerpf(WAVE_LOW, WAVE_HIGH, k)
	return free * lerpf(1.0, share, clampf(lv, 0.0, 1.0))
