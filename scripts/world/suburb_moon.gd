class_name SuburbMoon
extends RefCounted
## The moon over a residential street at night (SuburbNight's first fix, refcam5 suburb_night; one
## factor in DayNight's moon energy). Kept apart from SuburbNight on purpose, like CoastExposure:
## DayNight compiles it, and the sky tools load DayNight without a city, so it names no city class.
## `SUBURB_NIGHT=0` (or `SUBURB_MOON=0` for this part alone) is the A/B.

static var enabled: bool = OS.get_environment("SUBURB_NIGHT") != "0" and OS.get_environment("SUBURB_MOON") != "0"

## CityPlan.District's SUBURBS and BEACHTOWN (as numbers: CityPlan is not named here).
const SUBURBS := 2
const BEACHTOWN := 5
## The moon's strength over a residential street at full night (x DayNight's moon energy).
const MOON_GAIN := 0.3
## DayNight's moonlight where the cut starts and is full (18:36's sunset ~0.5 is left alone).
const DARK_FROM := 0.6
const DARK_TO := 0.95
## Seconds (real clock) the moon takes to follow the camera from one district to the next.
const EASE_SECONDS := 2.5

static var _gain := 1.0
static var _target := 1.0
static var _last_ms := -1
static var _next_look_ms := 0


## 0..1: how residential the camera's place is (true world XZ): 1 in SUBURBS and BEACHTOWN, 0
## elsewhere and on the open coast (CoastExposure.coast_weight()).
static func residential(plan: Object, pos: Vector2) -> float:
	if plan == null:
		return 0.0
	var d: int = plan.call("district_at", pos)
	if d != SUBURBS and d != BEACHTOWN:
		return 0.0
	var macro: Object = plan.get("macro")
	return 1.0 - CoastExposure.coast_weight(macro, pos)


## The moon's gain for a residential weight `res` at DayNight's `moonlight` (pure).
static func gain_for(res: float, moonlight: float) -> float:
	if not enabled:
		return 1.0
	return lerpf(1.0, MOON_GAIN, res * smoothstep(DARK_FROM, DARK_TO, moonlight))


## The moon's gain now, for DayNight: the current camera's place, eased on the real clock.
static func moon_gain(day: Node, moonlight: float) -> float:
	if not enabled or day == null or not day.is_inside_tree():
		return 1.0
	var now := Time.get_ticks_msec()
	if now >= _next_look_ms:
		_next_look_ms = now + 400
		_target = 1.0
		var cam := day.get_viewport().get_camera_3d()
		var streamer := day.get_parent()
		var plan: Object = streamer.get("plan") if streamer else null
		if cam != null and plan != null:
			# WorldState looked up, not named: --script tools compile this before the autoloads exist.
			var ws := day.get_node_or_null("/root/WorldState")
			var p: Vector3 = ws.call("to_world", cam.global_position) if ws else cam.global_position
			_target = gain_for(residential(plan, Vector2(p.x, p.z)), moonlight)
	var dt := 0.0 if _last_ms < 0 else float(now - _last_ms) / 1000.0
	_last_ms = now
	if dt <= 0.0 or dt > 30.0:
		_gain = _target
	else:
		_gain = move_toward(_gain, _target, dt / EASE_SECONDS)
	return _gain
