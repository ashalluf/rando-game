class_name NightFlight
extends RefCounted
## The city at night from a helicopter or the wingsuit, 150-800 m up (docs/HANDOFF.md "The night
## flight"). Three fixes to the night systems, all in shaders that were already running:
## - traffic in PLATOONS (far_traffic.gdshaderinc ft_platoon()): the share of a far lane's cells
##   taken is scaled by a smooth noise along the moving road, so a freeway from the air is a
##   broken river of bright knots and gaps instead of one even cream band, and a far lane's tail
##   lights weigh FT_TAIL_MEAN in its mean (the red side of a freeway reads red);
## - the street grid's HIERARCHY (street_glow.gdshaderinc street_rank()): a street glows by its
##   width, the arterials bright ribbons and the side streets dim threads, near (road.gdshader's
##   far glow) and far (the LOD ground, the far city's plates) alike; and a junction square is lit
##   at its four corners (street_glow_junction()) rather than as a flat orange tile;
## - sky beams (nightlife_beam.gdshader) fade when a camera beside or above them is close, where
##   they were solid white bars across the frame.
## `NIGHT_FLIGHT=0` in the environment turns it off (the A/B): the `night_flight` global goes to 0
## and every shader is as it was. tests/night_flight_checks.gd holds the copies below equal.

static var enabled: bool = OS.get_environment("NIGHT_FLIGHT") != "0"

## far_traffic.gdshaderinc's platoon numbers.
const PLATOON := 120.0
const PLATOON_LO := 0.3
const PLATOON_SPAN := 1.4
const TAIL_MEAN := 2.2
## street_glow.gdshaderinc's rank by width.
const RANK_LO := 0.45
const RANK_HI := 1.35
const RANK_W0 := 9.0
const RANK_W1 := 22.0


## Pushes the switch to the shaders (DayNight._ready()).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("night_flight", 1.0 if enabled else 0.0)


## Turns the pass on or off at once (tests, stills).
static func set_enabled(on: bool) -> void:
	enabled = on
	install()


## far_traffic.gdshaderinc ft_hash().
static func ft_hash(p: Vector3) -> float:
	var q := Vector3(_fract(p.x * 0.1031), _fract(p.y * 0.1030), _fract(p.z * 0.0973))
	var d := q.dot(Vector3(q.y, q.x, q.z) + Vector3(33.33, 33.33, 33.33))
	q += Vector3(d, d, d)
	return _fract((q.x + q.y) * q.z)


static func _fract(x: float) -> float:
	return x - floorf(x)


## far_traffic.gdshaderinc ft_platoon(): the share of cells taken at `u` metres along the moving
## road, as a factor on the hour's level (mean 1).
static func platoon(u: float, key: float) -> float:
	if not enabled:
		return 1.0
	var f := u / PLATOON
	var c := floorf(f)
	var t := f - c
	t = t * t * (3.0 - 2.0 * t)
	var n := lerpf(ft_hash(Vector3(c, key, 5.3)), ft_hash(Vector3(c + 1.0, key, 5.3)), t)
	return PLATOON_LO + PLATOON_SPAN * smoothstep(0.1, 0.9, n)


## street_glow.gdshaderinc street_rank(): a street's glow by its width in metres.
static func street_rank(w: float) -> float:
	if not enabled or w <= 0.0:
		return 1.0
	return lerpf(RANK_LO, RANK_HI, smoothstep(RANK_W0, RANK_W1, w))
