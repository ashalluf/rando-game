class_name CoastExposure
extends RefCounted
## The eye's exposure on a dark coast (rc4-pier-night-2, RcPierNight's first fix; one hook in
## DayNight._apply()). The night exposure is set for a lit street (night_exposure, the grade), and
## on the open sand under the moon there is nothing a street has - the beach, the sea and the sky
## all sat in the bottom tenth of the range (refcam pier_night p50 ~21). A camera on the coast at
## night opens up by `COAST_GAIN`, the way an eye or a photographer meters a dark beach: weighted
## by how far the camera stands from the coast (`coast_weight()`: 1 on the sand and over the sea,
## 0 `COAST_REACH` m inland of the sand) and by how deep into the night the light is (`DARK_FROM`
## .. `DARK_TO` of DayNight's moonlight), so the golden hour, the 18:36 sunset on the Esplanade
## and every street at night are untouched. Kept apart from RcPierNight on purpose: DayNight
## compiles it, and the sky tools load DayNight without a city.
##
## `RC4_PIER_NIGHT=0` (or `COAST_EXPOSURE=0` for this part alone) is the A/B.

static var enabled: bool = OS.get_environment("RC4_PIER_NIGHT") != "0" and OS.get_environment("COAST_EXPOSURE") != "0"

## How far a camera on the coast opens up at full night (x DayNight's exposure).
const COAST_GAIN := 1.75
## Metres inland of the sand's landward edge where the coast's exposure is gone.
const COAST_REACH := 160.0
## DayNight's moonlight (0 day .. 1 night) where the coast's exposure starts and is full: 18:36's
## sunset (moonlight ~0.5) is left alone.
const DARK_FROM := 0.6
const DARK_TO := 0.95


## 0..1: how much of the camera's view is the open coast (true world XZ). 1 on the sand and over
## the sea, 0 COAST_REACH metres inland of the sand.
static func coast_weight(macro: Object, pos: Vector2) -> float:
	if macro == null:
		return 0.0
	var cx: float = macro.call("coast_x", pos.y)
	var inland: float = pos.x - (cx + float(macro.call("beach_width_at", pos.y)))
	return 1.0 - smoothstep(0.0, COAST_REACH, inland)


## The exposure multiplier for a camera with `coast` weight at DayNight's `moonlight`.
static func gain_for(coast: float, moonlight: float) -> float:
	if not enabled:
		return 1.0
	var dark := smoothstep(DARK_FROM, DARK_TO, moonlight)
	return lerpf(1.0, COAST_GAIN, coast * dark)


## The exposure multiplier now, for DayNight: the current camera's place on the map.
static func exposure_gain(day: Node, moonlight: float) -> float:
	if not enabled or moonlight <= DARK_FROM or day == null or not day.is_inside_tree():
		return 1.0
	var cam := day.get_viewport().get_camera_3d()
	var streamer := day.get_parent()
	var plan: Variant = streamer.get("plan") if streamer else null
	if cam == null or plan == null:
		return 1.0
	var macro: Object = plan.get("macro")
	# WorldState looked up, not named: --script tools compile this before the autoloads exist.
	var ws := day.get_node_or_null("/root/WorldState")
	var p: Vector3 = ws.call("to_world", cam.global_position) if ws else cam.global_position
	return gain_for(coast_weight(macro, Vector2(p.x, p.z)), moonlight)
