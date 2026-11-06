class_name NewsLive
extends RefCounted
## The "news_live" reference camera's fixes (tools/refcams/cameras_w8.json; docs/HANDOFF.md "The
## news crew live at a burning wreck"). Three things that gave the scene away as a game:
##
## - A burning car threw a 12 m wisp of particles and nothing else: TreeFire only grows a smoke
##   column for a cluster of weight 2 (a burning car is 1, a wreck 0.8), so a lone car fire - the
##   commonest fire in the game - had no plume over the street. With this on, a car fire alone
##   gets a car-sized column (`car_height()`: ~55-75 m, narrow, leaning with the wind) through
##   the same SmokeColumn; clusters of weight 2 and more are exactly as before.
## - The onlookers stood in the live shot: Onlookers._pick_spot() put people between the camera
##   and the reporter and at the reporter's elbow. `in_shot()` keeps their spots out of every
##   on-air crew's line (camera -> reporter and a little past) and a circle round the reporter.
## - The camera operator wore whatever the rig came in (overalls, a mustard tee): a station's crew
##   in dark crew wear (`crew_material()`: charcoal top, dark cargo-khaki trousers), the overalls
##   rig off the operators' list.
##
## `NEWS_LIVE=0` in the environment is the A/B (all three off).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("NEWS_LIVE") != "0"

## A lone car fire's column: the weight at which it starts (a burning wreck is 0.8), its height
## at weight 0.8 and at weight 2 (where TreeFire's own columns begin).
const CAR_MIN_WEIGHT := 0.75
const CAR_HEIGHT := 58.0
const CAR_HEIGHT_AT_2 := 160.0
## The keep-out round a live shot: half width of the line (m) at the camera and at the reporter,
## how far past the reporter it runs, and the circle round the reporter.
const SHOT_HALF_NEAR := 0.9
const SHOT_HALF_FAR := 1.8
const SHOT_PAST := 3.5
const REPORTER_CLEAR := 2.4
## Crew wear (HSV): the top and the trousers.
const CREW_TOP := Color(0.13, 0.13, 0.14)
const CREW_TROUSERS := Color(0.27, 0.25, 0.20)

static var _crew_mats: Dictionary = {}


## The weight a cluster of fires needs for a column: TreeFire's own unless this is on.
static func column_min(weight: float) -> float:
	return CAR_MIN_WEIGHT if enabled else weight


## A column's height for a fire of weight `fed` under 2 (a lone car); `base` is SmokeColumn's.
static func car_height(fed: float) -> float:
	return lerpf(CAR_HEIGHT, CAR_HEIGHT_AT_2, clampf((fed - 0.8) / 1.2, 0.0, 1.0))


## The column's top radius for a car-sized plume of `shown` metres.
static func car_radius_top(shown: float) -> float:
	return clampf(shown * 0.22, 7.0, 30.0)


## Every on-air news crew's shot as [camera xz, reporter xz] in true world, or [] when off.
static func shots(tree: SceneTree) -> Array:
	var out: Array = []
	if not enabled or tree == null:
		return out
	var by_van := {}
	for n in tree.get_nodes_in_group("news_crew"):
		var c := n as NewsCrew
		if c == null or not is_instance_valid(c) or c._down or c.van == null:
			continue
		var w := WorldState.to_world(c.global_position)
		var entry: Array = by_van.get(c.van, [Vector2.INF, Vector2.INF])
		entry[0 if c.role == NewsCrew.Role.CAMERA else 1] = Vector2(w.x, w.z)
		by_van[c.van] = entry
	for e: Array in by_van.values():
		if e[0] != Vector2.INF and e[1] != Vector2.INF:
			out.append(e)
	return out


## Whether true world point `q` stands in one of `shot_list`'s shots (shots()).
static func in_shot(shot_list: Array, q: Vector2) -> bool:
	for e: Array in shot_list:
		var cam: Vector2 = e[0]
		var rep: Vector2 = e[1]
		if q.distance_to(rep) < REPORTER_CLEAR:
			return true
		var d := rep - cam
		var l := d.length()
		if l < 0.1:
			continue
		var u := d / l
		var t := (q - cam).dot(u)
		if t < 0.0 or t > l + SHOT_PAST:
			continue
		var half := lerpf(SHOT_HALF_NEAR, SHOT_HALF_FAR, clampf(t / l, 0.0, 1.0))
		if absf((q - cam).cross(u)) < half:
			return true
	return false


## A camera operator's crew wear: a copy of `src` (the rig's own character material, its look
## applied) with the top and trousers recoloured, cached per source material.
static func crew_material(src: ShaderMaterial) -> ShaderMaterial:
	var key := src.get_instance_id()
	if _crew_mats.has(key):
		return _crew_mats[key]
	var mat := src.duplicate() as ShaderMaterial
	mat.set_shader_parameter("cloth_hue", CREW_TOP.h)
	mat.set_shader_parameter("cloth_sat", CREW_TOP.s)
	mat.set_shader_parameter("cloth_value", CREW_TOP.v)
	mat.set_shader_parameter("cloth_strength", 0.95)
	mat.set_shader_parameter("pants_hue", CREW_TROUSERS.h)
	mat.set_shader_parameter("pants_sat", CREW_TROUSERS.s)
	mat.set_shader_parameter("pants_value", CREW_TROUSERS.v)
	mat.set_shader_parameter("pants_strength", 0.95)
	mat.set_shader_parameter("cloth_shade_keep", 0.7)
	_crew_mats[key] = mat
	return mat
