class_name TrafficSignals
extends RefCounted
## Traffic signals, worked out rather than ticked (owner, 2026-09-24: "GTA-level street life").
##
## Nothing in the city runs a timer per signal. Every signalised intersection shares one clock
## (`clock`, advanced once a physics tick by TrafficManager and pushed to the shaders as the
## `signal_clock` global) and adds its own seeded offset, so the state of any head anywhere is
## a couple of multiplies: the lens shader (shaders/traffic_signal.gdshader) lights its lamps from
## the same numbers the traffic brakes for and the crowd waits on, and nothing can drift.
##
## One cycle, per intersection:
##
##   0 ................ GREEN ....... AMBER .. ALL_RED | HALF ... GREEN ... AMBER .. ALL_RED | CYCLE
##   cars on AXIS_X roads (running north-south) go   | cars on AXIS_Z roads (east-west) go
##
## Pedestrians walk with the traffic beside them: crossing an AXIS_Z road means walking along Z,
## parallel to the AXIS_X traffic, so it is WALK for the first WALK_TIME seconds of the AXIS_X
## green, the flashing hand for the rest of it (the countdown runs to its end), and the steady
## hand through the amber and both reds. The two sides of the cycle are the same length.
##
## The shader takes these four numbers from the material (PropFactory.signal_lens_material()
## pushes them), never from a copy of its own, and the smoke test checks the two agree.

enum Light { GREEN, AMBER, RED }
enum Walk { WALK, FLASH, DONT }

# --- Tunables --------------------------------------------------------------------------------
# Never instanced (every entry point is static), so the knobs are consts, all of them here.

## Seconds of green for each axis.
const GREEN := 16.0
## Seconds of amber after each green.
const AMBER := 3.5
## Seconds when every approach is red, after each amber, so the box clears.
const ALL_RED := 1.5
## Seconds of the walking figure at the start of a parallel green; the flashing hand (and the
## countdown) takes the rest of the green.
const WALK_TIME := 7.0
## Half a cycle (one axis' green, amber and all-red) and the whole cycle.
const HALF := GREEN + AMBER + ALL_RED
const CYCLE := HALF * 2.0

## The shared clock, seconds into the cycle, 0..CYCLE. Game time: it stops with the pause menu
## and slows with the weapon wheel, the same as the cars that obey it.
static var clock: float = 0.0


## Moves the clock on and hands it to the shaders. One call a physics tick (TrafficManager).
static func advance(delta: float) -> void:
	clock = fposmod(clock + delta, CYCLE)
	RenderingServer.global_shader_parameter_set("signal_clock", clock)


## Puts the clock at `value` (seconds into the cycle) and pushes it: tests and screenshots.
static func set_clock(value: float) -> void:
	clock = fposmod(value, CYCLE)
	RenderingServer.global_shader_parameter_set("signal_clock", clock)


## This intersection's offset into the shared cycle, as a fraction of it (what a head's
## INSTANCE_CUSTOM.r carries). Seeded, so the same city has the same timing.
static func offset01(plan: CityPlan, ix: int, iz: int) -> float:
	return float(absi(hash([plan.seed, "signal", ix, iz])) % 100003) / 100003.0


## Seconds into the cycle at intersection (ix, iz) right now.
static func phase(plan: CityPlan, ix: int, iz: int) -> float:
	return fposmod(clock + offset01(plan, ix, iz) * CYCLE, CYCLE)


## Seconds into the half of the cycle that belongs to `axis` (0 = its green starts).
static func _axis_time(plan: CityPlan, ix: int, iz: int, axis: int) -> float:
	return fposmod(phase(plan, ix, iz) - (HALF if axis == CityPlan.AXIS_Z else 0.0), CYCLE)


## True when the intersection is signalised at all.
static func is_signal(plan: CityPlan, ix: int, iz: int) -> bool:
	return int(plan.intersection(ix, iz).kind) == CityPlan.Intersection.SIGNALS


## What a car driving on a road of `axis` sees at intersection (ix, iz).
static func light(plan: CityPlan, ix: int, iz: int, axis: int) -> int:
	var t := _axis_time(plan, ix, iz, axis)
	if t < GREEN:
		return Light.GREEN
	if t < GREEN + AMBER:
		return Light.AMBER
	return Light.RED


## Seconds until the light a car on `axis` sees next changes.
static func light_left(plan: CityPlan, ix: int, iz: int, axis: int) -> float:
	var t := _axis_time(plan, ix, iz, axis)
	if t < GREEN:
		return GREEN - t
	if t < GREEN + AMBER:
		return GREEN + AMBER - t
	return CYCLE - t


## What a pedestrian about to cross the road of `crossing_axis` sees: they walk with the
## traffic running beside them, which is the other axis.
static func walk(plan: CityPlan, ix: int, iz: int, crossing_axis: int) -> int:
	var t := _axis_time(plan, ix, iz, 1 - crossing_axis)
	if t < WALK_TIME:
		return Walk.WALK
	if t < GREEN:
		return Walk.FLASH
	return Walk.DONT


## Puts the clock where the light on `axis` at (ix, iz) is `state`, `into` seconds after it
## started (tests and screenshots).
static func force(plan: CityPlan, ix: int, iz: int, axis: int, state: int, into: float = 0.2) -> void:
	var start := 0.0
	match state:
		Light.AMBER:
			start = GREEN
		Light.RED:
			start = GREEN + AMBER
	var t := start + into + (HALF if axis == CityPlan.AXIS_Z else 0.0)
	set_clock(t - offset01(plan, ix, iz) * CYCLE)
