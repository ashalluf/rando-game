class_name RoadWear
extends RefCounted
## Road wear (owner, 2026-10-05: "the streets are supposed to be detailed and have texture and
## potholes and look as unique as possible ... make like 25 max different pavement wear and tears,
## then from that you can inverse, make derivatives or variations up to thousands").
##
## The library: 25 stamps in one atlas (tools/make_road_wear.py -> assets/textures/road_wear/,
## the table in RoadWearTable): potholes (shallow, deep with broken edges, gravel-filled, holding
## water, a cluster), alligator and block cracking, longitudinal and transverse cracks, tar snakes
## and a sealed network, ravelling, raised and sunken patches, saw-cut utility patches and trench
## strips, rutting with polish, edge break-up at the gutter, shoving at stop lines, oil and coolant
## drips, tyre burn-outs, ground-off paint ghosts, bleeding binder, a spalled and a cracked
## concrete panel.
##
## The variations, per instance, all from a hash of seed + place: any turn (or the road's axis
## for the stamps that keep to it), a mirror on either axis, a scale per axis within the stamp
## kind's range, an age (fresh black to grey and dusty), an erosion threshold on the stamp's order
## map (one pothole erodes into many smaller, more ragged ones; a crack network loses different
## branches), a tint toward the road's own asphalt, and a pair: a second stamp laid over the first
## at its own quarter turn, mirror, zoom and threshold. Distinct looks per stamp before any
## continuous turn or scale: 4 mirrors x 27 thresholds x 8 ages = 864; with a pair (25 partners x
## 4 turns x 4 mirrors x 8 zooms x 27 thresholds) about 7.5 million - see variant_count().
##
## Placement reads as a real street: how worn a road is (road_level()) comes from its district
## (industrial and old midtown streets worst, downtown's repaved avenues least), its own age (some
## streets were resurfaced last year), bus lines and the trucks of the industrial district and the
## port. Wear clusters along the wheel paths of each travel lane and in stretches along the road,
## the kerb lane breaks up and gathers ravelling, the parking lane drips oil, the approach to a
## stop line shoves and ruts, transverse cracks cross whole lanes and are often sealed, utility
## crews leave saw-cut patches and trench strips; potholes are much rarer than cracks. Pavements
## get a little concrete cracking (the kerbs and StreetWear do the rest), surface car parks oil
## stains, patches and cracks (LotFill._car_park calls car_park()).
##
## Drawn as ONE MultiMesh a chunk ("road_wear": a flat quad on shaders/road_wear.gdshader, the
## pothole depth by parallax occlusion), FULL chunks only, no shadow, faded out by DRAW_DISTANCE;
## LOD chunks and the far city keep the road shader's own procedural patches and cracks. Deep
## potholes are also kept in a small spatial index so a car driving into one bumps (bump_for()).
## Nothing here touches a chunk or block rng. ROAD_WEAR=0 in the environment turns it off.

# --- Tunables ----------------------------------------------------------------------------------

## How worn a road is by CityPlan.District (DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN).
const DISTRICT_LEVEL := [0.45, 1.0, 0.55, 1.4, 0.4, 0.75]
## Downtown's avenues are repaved far more often than its side streets.
const DOWNTOWN_AVENUE := 0.55
## A road's own age: this share of roads was resurfaced lately (FRESH_LEVEL of the wear), the rest
## spread between OLD_RANGE.
const FRESH_SHARE := 0.16
const FRESH_LEVEL := 0.35
const OLD_RANGE := Vector2(0.6, 1.45)
## Even a new street has oil, a utility cut or two and a crack: the least a road is.
const MIN_LEVEL := 0.3
## Extra wear on a bus line (the stops and the kerb lane) and within PORT_REACH of the port.
const BUS_LINE := 0.3
const PORT_REACH := 900.0
const PORT_EXTRA := 0.45
## Stamps per 100 m of a two-lane street at level 1, and how much of them falls in clusters along
## the wheel paths (the rest: the kerb, the parking lane, cracks across, utility cuts).
const PER_100M := 32.0
## Potholes: the chance a wheel-path cluster has one at level 1 (scaled by level squared, so a
## fresh street has none and a bad industrial one several a block).
const POTHOLE_ODDS := 0.16
## Concrete cracks per metre of pavement at level 1.
const PAVEMENT_PER_M := 0.035
## Car parks: stamps per 100 m2 at level 1.
const CAR_PARK_PER_100M2 := 1.1
const MAX_PER_CHUNK := 480
const DRAW_DISTANCE := 110.0
## Metres over the road top: over the old patches (0.003), under the oil (0.0055) and the paint.
const LIFT := 0.0042
## Erosion thresholds go up to this q (of the shader's thr_div, 52) and ages over 8 buckets.
const THR_MAX := 26
const AGES := 8
## Share of stamps that get a pair.
const PAIR_SHARE := 0.35
## Deep potholes deeper than this (m) bump a car (bump_for()).
const BUMP_DEPTH := 0.035
## The jolt: metres a second taken off the corner per unit of depth gain, and the slowest a car
## feels it at.
const BUMP_GAIN := 0.32
const BUMP_MIN_SPEED := 2.0

const KEY := "road_wear"

## Per stamp: [scale range (each axis, of the table size), aspect jitter, threshold q max,
## pair partners (names)].
const KINDS := {
	"pothole_shallow": [Vector2(0.55, 1.4), 0.25, 22, ["crack_long", "alligator", "ravelling", "pothole_cluster"]],
	"pothole_deep": [Vector2(0.6, 1.3), 0.25, 18, ["alligator", "crack_long", "ravelling", "edge_break"]],
	"pothole_gravel": [Vector2(0.6, 1.4), 0.25, 20, ["ravelling", "crack_long", "tar_snake"]],
	"pothole_water": [Vector2(0.6, 1.25), 0.2, 16, ["alligator", "crack_long"]],
	"pothole_cluster": [Vector2(0.6, 1.3), 0.25, 22, ["alligator", "ravelling", "block_crack"]],
	"alligator": [Vector2(0.55, 1.4), 0.3, 26, ["ravelling", "pothole_shallow", "bleeding", "patch_sunken"]],
	"block_crack": [Vector2(0.6, 1.4), 0.2, 26, ["tar_network", "crack_long", "ravelling"]],
	"crack_long": [Vector2(0.6, 1.4), 0.4, 26, ["tar_snake", "crack_long", "ravelling"]],
	"crack_trans": [Vector2(0.8, 1.2), 0.3, 26, ["tar_snake", "crack_trans", "ravelling"]],
	"tar_snake": [Vector2(0.6, 1.4), 0.3, 22, ["crack_long", "tar_snake"]],
	"tar_network": [Vector2(0.6, 1.4), 0.15, 24, ["block_crack", "crack_long"]],
	"ravelling": [Vector2(0.5, 1.5), 0.3, 26, ["alligator", "crack_long", "pothole_shallow"]],
	"patch_raised": [Vector2(0.6, 1.6), 0.35, 16, ["crack_long", "ravelling", "oil_drips"]],
	"patch_sunken": [Vector2(0.6, 1.5), 0.35, 16, ["alligator", "crack_long", "pothole_shallow"]],
	"sawcut_patch": [Vector2(0.5, 1.6), 0.45, 12, ["crack_long", "tar_snake", "oil_drips"]],
	"trench_strip": [Vector2(0.6, 1.5), 0.3, 10, ["crack_long", "ravelling"]],
	"rut_polish": [Vector2(0.8, 1.6), 0.2, 20, ["bleeding", "crack_long", "alligator"]],
	"edge_break": [Vector2(0.7, 1.4), 0.25, 22, ["ravelling", "crack_long", "pothole_shallow"]],
	"shoving": [Vector2(0.7, 1.3), 0.2, 20, ["bleeding", "crack_trans", "rut_polish"]],
	"oil_drips": [Vector2(0.6, 1.4), 0.3, 22, ["oil_drips", "burnout"]],
	"burnout": [Vector2(0.7, 1.6), 0.3, 22, ["burnout", "oil_drips"]],
	"paint_ghost": [Vector2(0.8, 1.6), 0.2, 20, ["crack_long", "ravelling"]],
	"bleeding": [Vector2(0.7, 1.5), 0.25, 22, ["rut_polish", "crack_long"]],
	"concrete_spall": [Vector2(0.4, 1.0), 0.3, 22, ["concrete_crack"]],
	"concrete_crack": [Vector2(0.6, 1.3), 0.3, 26, ["concrete_crack", "concrete_spall"]],
}

## Off: build() adds nothing (ROAD_WEAR=0 in the environment; the "before" of the A/B).
static var enabled: bool = OS.get_environment("ROAD_WEAR") != "0"

## RW_LIST=1 prints every stamp laid (tools/road_wear/chunk_probe.gd finds stills with it).
static var _list: bool = OS.get_environment("RW_LIST") == "1"
static var _mesh: ArrayMesh = null
static var _index: Dictionary = {}
## Deep potholes for the car bump: Vector2i cell (BUMP_CELL m) -> [[true-world XZ, radius, depth,
## chunk key], ...].
const BUMP_CELL := 8.0
static var _bumps: Dictionary = {}


# --- Entry ---------------------------------------------------------------------------------------

## One FULL chunk's road wear, as a build step: its two roads (the +X and +Z ones it owns), the
## junction between them and its pavements. Hash-seeded; the chunk's rng is untouched.
static func build(chunk: CityChunk) -> void:
	if not enabled or chunk.level != CityChunk.Level.FULL or chunk.capturing:
		return
	_announce()
	if chunk.zone != MacroMap.Zone.CITY and chunk.zone != MacroMap.Zone.BEACH:
		return
	var plan: CityPlan = chunk.plan
	if plan.marina_block(chunk.ix, chunk.iz):
		return
	var replica: ReplicaAreas = plan.macro.replica if plan.macro else null
	if replica != null and replica.block_role(plan, chunk.ix, chunk.iz) != 0:
		return
	var block := plan.block(chunk.ix, chunk.iz)
	var rect: Rect2 = block.rect
	var district := int(block.district)
	var ctx := {"chunk": chunk, "plan": plan, "count": int(chunk.get_meta("road_wear_count", 0)), "points": [], "kinds": {}}
	var rx := plan.road_pos(CityPlan.AXIS_X, chunk.ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, chunk.ix + 1)
	var rz := plan.road_pos(CityPlan.AXIS_Z, chunk.iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, chunk.iz + 1)
	if plan.road_open(CityPlan.AXIS_X, chunk.ix + 1, rect.get_center().y):
		_road(ctx, CityPlan.AXIS_X, chunk.ix + 1, chunk.iz, rx, wx, rect.position.y, rect.end.y, district)
	if plan.road_open(CityPlan.AXIS_Z, chunk.iz + 1, rect.get_center().x):
		_road(ctx, CityPlan.AXIS_Z, chunk.iz + 1, chunk.ix, rz, wz, rect.position.x, rect.end.x, district)
	if not plan.junction_closed(chunk.ix + 1, chunk.iz + 1) and (plan.road_open(CityPlan.AXIS_X, chunk.ix + 1, rz) or plan.road_open(CityPlan.AXIS_Z, chunk.iz + 1, rx)):
		var inter := plan.intersection(chunk.ix + 1, chunk.iz + 1)
		if int(inter.kind) != CityPlan.Intersection.ROUNDABOUT:
			_junction(ctx, Vector2(rx, rz), Vector2(wx, wz), district)
	if not block.has("site") and chunk.zone == MacroMap.Zone.CITY:
		_pavements(ctx, rect, district)
	_finish(ctx)


## A surface car park's wear (LotFill._car_park): `r` the asphalt, at `top` (the asphalt's height
## over the block's ground, before the relief).
static func car_park(chunk: CityChunk, r: Rect2, top: float, key: int) -> void:
	if not enabled or chunk.level != CityChunk.Level.FULL or chunk.capturing:
		return
	var plan: CityPlan = chunk.plan
	var district := int(plan.block(chunk.ix, chunk.iz).district)
	var ctx := {"chunk": chunk, "plan": plan, "count": int(chunk.get_meta("road_wear_count", 0)), "points": [], "kinds": {}}
	var rng := _rng([plan.seed, "rw_park", chunk.ix, chunk.iz, key])
	var level: float = DISTRICT_LEVEL[district] * lerpf(OLD_RANGE.x, OLD_RANGE.y, rng.randf())
	var n := int(round(r.get_area() / 100.0 * CAR_PARK_PER_100M2 * level))
	# LotFill's car-park asphalt is darker than a street: the stamps are pulled down to it.
	var tint := Color(0.38, 0.38, 0.39)
	var age := clampf(level * 0.6, 0.0, 1.0)
	for i in n:
		var roll := rng.randf()
		var name := "oil_drips"
		if roll > 0.55:
			name = ["crack_long", "alligator", "patch_raised", "sawcut_patch", "ravelling", "block_crack", "tar_snake", "pothole_shallow", "patch_sunken"][rng.randi() % 9]
		if name == "pothole_shallow" and rng.randf() > level * 0.5:
			name = "ravelling"
		var p := Vector2(rng.randf_range(r.position.x + 1.0, r.end.x - 1.0), rng.randf_range(r.position.y + 1.0, r.end.y - 1.0))
		_stamp(ctx, rng, name, p, top + LIFT, rng.randf() * TAU, tint, age, false)
	_finish(ctx)


static var _announced := false

## Tells road.gdshader the stamps are on (its own procedural cracks and patches step back near
## the camera, where the stamps are).
static func _announce() -> void:
	if _announced:
		return
	_announced = true
	RenderingServer.global_shader_parameter_set("road_stamp_near", 1.0)


# --- Roads ---------------------------------------------------------------------------------------

## How worn road (axis, index) is, 0 (new) .. ~2.5 (the worst industrial street by the port).
static func road_level(plan: CityPlan, axis: int, index: int, district: int) -> float:
	var level: float = DISTRICT_LEVEL[clampi(district, 0, DISTRICT_LEVEL.size() - 1)]
	var avenue := plan.road_width(axis, index) >= plan.avenue_width - 0.1
	if district == CityPlan.District.DOWNTOWN and avenue:
		level *= DOWNTOWN_AVENUE
	var h := _h01([plan.seed, "rw_age", axis, index])
	level *= FRESH_LEVEL if h < FRESH_SHARE else lerpf(OLD_RANGE.x, OLD_RANGE.y, (h - FRESH_SHARE) / (1.0 - FRESH_SHARE))
	if BigVehicles.route_of(plan, axis, index) != 0:
		level += BUS_LINE * (0.5 if h < FRESH_SHARE else 1.0)
	if plan.macro != null:
		var at := Vector2(plan.road_pos(axis, index), 0.0)
		var port: Rect2 = plan.macro.port_rect
		var d := absf(at.x - clampf(at.x, port.position.x, port.end.x)) if axis == CityPlan.AXIS_X else absf(plan.road_pos(axis, index) - clampf(plan.road_pos(axis, index), port.position.y, port.end.y))
		if d < PORT_REACH and district == CityPlan.District.INDUSTRIAL:
			level += PORT_EXTRA * (1.0 - d / PORT_REACH)
	return maxf(level, MIN_LEVEL)


## The road's tint as _road_look picks it (sRGB), brightened for the coarser asphalt set, which
## is lighter than the one the stamps were authored on.
static func road_tint(plan: CityPlan, axis: int, index: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, "road_look", axis, index])
	var aerial := rng.randf() >= 0.55
	var tint: Color = CityChunk.ROAD_TINTS[rng.randi() % CityChunk.ROAD_TINTS.size()]
	if aerial:
		tint = Color(tint.r * 1.2, tint.g * 1.2, tint.b * 1.2)
	return tint


## One road along one block: from `a` to `b` along it, centre line at `c`, `w` wide. `block_i` is
## the block's index on the other axis (which stretch of the road this is).
static func _road(ctx: Dictionary, axis: int, index: int, block_i: int, c: float, w: float, a: float, b: float, district: int) -> void:
	var plan: CityPlan = ctx.plan
	var level := road_level(plan, axis, index, district)
	var length := b - a
	if length < 6.0 or level <= 0.01:
		return
	var rng := _rng([plan.seed, "rw_road", axis, index, block_i])
	var tint := road_tint(plan, axis, index)
	var top := CityChunk.ROAD_TOP + LIFT
	var along_yaw := 0.0 if axis == CityPlan.AXIS_X else PI * 0.5
	var lanes := 2 if w > 15.0 else 1
	var half := w * 0.5
	var age_bias := clampf(level * 0.45, 0.1, 0.9)
	# A point on this road: u across from the centre line (+x or +z), v along it from `a`.
	var at := func(u: float, v: float) -> Vector2:
		return Vector2(c + u, a + v) if axis == CityPlan.AXIS_X else Vector2(a + v, c + u)
	# How bad each stretch is: slow noise along the road, so wear comes in stretches.
	var stretch_seed := _h01([plan.seed, "rw_stretch", axis, index]) * 100.0
	var stretch := func(v: float) -> float:
		return 0.35 + 1.3 * _noise1(stretch_seed + (a + v) / 38.0)
	var budget := PER_100M * level * length / 100.0 * (w / 14.0)
	# 1. Clusters on the wheel paths of every travel lane.
	var wheel_paths: Array[float] = []
	for side: float in [-1.0, 1.0]:
		for n in lanes:
			var lc := CityPlan.lane_center(w, lanes, n)
			for g: float in [-0.86, 0.86]:
				wheel_paths.append(side * (lc + g))
	var clusters := int(round(budget * 0.5 / 2.5))
	for k in clusters:
		var v := rng.randf_range(1.0, length - 1.0)
		if rng.randf() > stretch.call(v) * 0.75:
			continue
		var u: float = wheel_paths[rng.randi() % wheel_paths.size()]
		var travel_sign := -signf(u) # right-hand traffic: u < 0 runs toward +v
		var count := rng.randi_range(2, 5)
		for m in count:
			var du := rng.randf_range(-0.35, 0.35)
			var dv := rng.randf_range(-3.0, 3.0)
			var roll := rng.randf()
			var name := "alligator"
			if roll < POTHOLE_ODDS * level * level * stretch.call(v) * 0.6 and m == 0:
				name = ["pothole_shallow", "pothole_shallow", "pothole_deep", "pothole_gravel", "pothole_water", "pothole_cluster"][rng.randi() % 6]
			elif roll < 0.3:
				name = "alligator"
			elif roll < 0.5:
				name = "rut_polish"
			elif roll < 0.68:
				name = "crack_long"
			elif roll < 0.8:
				name = "ravelling"
			elif roll < 0.9:
				name = "bleeding"
			else:
				name = "patch_sunken" if rng.randf() < 0.5 else "patch_raised"
			var p: Vector2 = at.call(clampf(u + du, -half + 0.4, half - 0.4), clampf(v + dv, 0.5, length - 0.5))
			_stamp(ctx, rng, name, p, top, along_yaw + (0.0 if travel_sign > 0.0 else PI), tint, _age(rng, age_bias), true)
	# 2. The kerb lanes: edge break-up and ravelling against the gutter, oil in the parking lane.
	for side: float in [-1.0, 1.0]:
		var n_kerb := int(round(budget * 0.1 * rng.randf_range(0.6, 1.4) * 0.5))
		for k in n_kerb:
			var v := rng.randf_range(1.5, length - 1.5)
			if rng.randf() > stretch.call(v) * 0.8:
				continue
			var roll := rng.randf()
			var name := "edge_break" if roll < 0.45 else ("ravelling" if roll < 0.7 else ("crack_long" if roll < 0.9 else "patch_sunken"))
			var u := side * (half - 0.7)
			if name != "edge_break":
				u = side * (half - rng.randf_range(0.6, 2.0))
			# Edge break-up keeps its u = 0 side on the kerb: its local +x points into the road.
			var yaw := along_yaw + (0.0 if side < 0.0 else PI)
			if axis == CityPlan.AXIS_Z:
				yaw = along_yaw + (PI if side < 0.0 else 0.0)
			if name == "edge_break":
				u = side * half
			_stamp(ctx, rng, name, at.call(u, v), top, yaw, tint, _age(rng, age_bias), true, name == "edge_break")
		# The parking lane: drips under where cars stand.
		var n_oil := int(round(length / 6.5 * 0.16 * clampf(level, 0.4, 1.4)))
		for k in n_oil:
			var v := rng.randf_range(2.0, length - 2.0)
			var u := side * (half - CityPlan.PARKING_LANE * 0.5 + rng.randf_range(-0.4, 0.4))
			_stamp(ctx, rng, "oil_drips" if rng.randf() < 0.9 else "burnout", at.call(u, v), top, along_yaw + rng.randf_range(-0.2, 0.2), tint, _age(rng, age_bias), false)
	# 3. Longitudinal joint down the middle (where the two paving passes met), cracked and sealed.
	# Short pieces that wander off the line and leave gaps: laid end to end on it they read as a
	# line ruled down the road.
	var v0 := 0.0
	var drift := 0.0
	while v0 < length - 2.0:
		var piece := rng.randf_range(3.0, 7.0)
		drift = clampf(drift + rng.randf_range(-0.45, 0.45), -0.9, 0.9)
		if rng.randf() < 0.3 * level * stretch.call(v0):
			var name := "tar_snake" if rng.randf() < 0.55 else "crack_long"
			_stamp(ctx, rng, name, at.call(drift, v0 + piece * 0.5), top, along_yaw + (PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.3, 0.3), tint, _age(rng, age_bias), true)
			v0 += rng.randf_range(2.0, 6.0) # a gap after every sealed piece
		v0 += piece
	# 4. Transverse cracks right across a carriageway every so often (thermal), often sealed.
	var v1 := rng.randf_range(3.0, 14.0)
	while v1 < length - 2.0:
		if rng.randf() < 0.55 * level:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var sealed := rng.randf() < 0.6
			var name := "tar_snake" if sealed else "crack_trans"
			var width := half - 0.3
			if sealed:
				# A sealed crack across the road is a few short wandering runs with gaps, never one
				# stamp stretched straight from the centre line to the kerb.
				var u := side * rng.randf_range(0.2, 0.8)
				var dv := 0.0
				while absf(u) < width:
					var run := rng.randf_range(1.2, 2.6)
					dv += rng.randf_range(-0.5, 0.5)
					var piece_at: Vector2 = at.call(u + side * run * 0.5, v1 + dv)
					_stamp(ctx, rng, name, piece_at, top, along_yaw + PI * 0.5 + rng.randf_range(-0.35, 0.35), tint, _age(rng, age_bias), true, false, run)
					u += side * (run + rng.randf_range(0.4, 1.6))
			else:
				var p: Vector2 = at.call(side * width * 0.5, v1)
				_stamp(ctx, rng, name, p, top, along_yaw, tint, _age(rng, age_bias), true, false, width)
		v1 += rng.randf_range(9.0, 24.0) / maxf(level, 0.3)
	# 5. Utility cuts and old patches anywhere on the carriageway.
	var n_cut := int(round(budget * 0.14 * rng.randf_range(0.5, 1.5)))
	for k in n_cut:
		var roll := rng.randf()
		var name := "sawcut_patch" if roll < 0.35 else ("trench_strip" if roll < 0.55 else ("patch_raised" if roll < 0.7 else ("block_crack" if roll < 0.85 else ("tar_network" if roll < 0.95 else "paint_ghost"))))
		var u := rng.randf_range(-half + 1.5, half - 1.5)
		var v := rng.randf_range(2.0, length - 2.0)
		var yaw := along_yaw + (PI if rng.randf() < 0.5 else 0.0)
		if name == "trench_strip" and rng.randf() < 0.5:
			yaw += PI * 0.5 # across the road to a service
		if name == "paint_ghost":
			u = side_line(w, lanes, rng)
		_stamp(ctx, rng, name, at.call(u, v), top, yaw, tint, _age(rng, age_bias), true)
	# 6. Sealed cracks anywhere on the carriageway: LA's black tar snakes and sealed networks.
	var n_seal := int(round(budget * 0.14 * rng.randf_range(0.4, 1.6)))
	for k in n_seal:
		var v := rng.randf_range(2.0, length - 2.0)
		if rng.randf() > stretch.call(v) * 0.85:
			continue
		var name := "tar_snake" if rng.randf() < 0.6 else "tar_network"
		var yaw := along_yaw + (PI if rng.randf() < 0.5 else 0.0) + (PI * 0.5 if rng.randf() < 0.25 else 0.0) + rng.randf_range(-0.4, 0.4)
		_stamp(ctx, rng, name, at.call(rng.randf_range(-half + 1.0, half - 1.0), v), top, yaw, tint, _age(rng, age_bias), true)
	# 7. The approach to each junction: shoving and ruts before the stop line in the lanes that stop
	# there (right-hand traffic: u < 0 stops at the far end, u > 0 at the near end).
	for end in 2:
		if rng.randf() > 0.25 + 0.5 * level:
			continue
		var stop_side := -1.0 if end == 1 else 1.0
		for n in lanes:
			if rng.randf() > 0.6:
				continue
			var u := stop_side * CityPlan.lane_center(w, lanes, n)
			var dv := rng.randf_range(4.0, 11.0)
			var v := (length - dv) if end == 1 else dv
			var travel_yaw := along_yaw + (0.0 if end == 1 else PI)
			_stamp(ctx, rng, "shoving", at.call(u, v), top, travel_yaw, tint, _age(rng, age_bias), true, false, CityPlan.lane_center(w, lanes, 0) * 2.0 / lanes + 0.6)
			if rng.randf() < 0.5:
				_stamp(ctx, rng, "rut_polish", at.call(u + rng.randf_range(-0.9, 0.9), v + (dv * 0.3 if end == 0 else -dv * 0.3)), top, travel_yaw, tint, _age(rng, age_bias), true)


## Where an old lane line used to be (a ground-off ghost): off the present lines by a lane's share.
static func side_line(w: float, lanes: int, rng: RandomNumberGenerator) -> float:
	var travel := w * 0.5 - CityPlan.PARKING_LANE - 0.2
	return (1.0 if rng.randf() < 0.5 else -1.0) * travel * rng.randf_range(0.35, 0.75)


static func _junction(ctx: Dictionary, pos: Vector2, size: Vector2, district: int) -> void:
	var plan: CityPlan = ctx.plan
	var chunk: CityChunk = ctx.chunk
	var level: float = (road_level(plan, CityPlan.AXIS_X, chunk.ix + 1, district) + road_level(plan, CityPlan.AXIS_Z, chunk.iz + 1, district)) * 0.5
	var rng := _rng([plan.seed, "rw_junction", chunk.ix + 1, chunk.iz + 1])
	var tint := road_tint(plan, CityPlan.AXIS_X, chunk.ix + 1)
	var top := CityChunk.ROAD_TOP + LIFT
	var n := int(round(size.x * size.y / 100.0 * 1.2 * level))
	for i in n:
		var roll := rng.randf()
		var name := "tar_network" if roll < 0.25 else ("block_crack" if roll < 0.45 else ("sawcut_patch" if roll < 0.6 else ("alligator" if roll < 0.75 else ("burnout" if roll < 0.85 else ("ravelling" if roll < 0.95 else "pothole_shallow")))))
		if name == "pothole_shallow" and rng.randf() > level * 0.6:
			name = "patch_raised"
		var p := pos + Vector2(rng.randf_range(-size.x * 0.4, size.x * 0.4), rng.randf_range(-size.y * 0.4, size.y * 0.4))
		_stamp(ctx, rng, name, p, top, rng.randf() * TAU, tint, _age(rng, clampf(level * 0.45, 0.1, 0.9)), false)


## A little concrete cracking along the pavements, set back from the kerb paint and the gum.
static func _pavements(ctx: Dictionary, rect: Rect2, district: int) -> void:
	var plan: CityPlan = ctx.plan
	var chunk: CityChunk = ctx.chunk
	var level: float = DISTRICT_LEVEL[district] * lerpf(OLD_RANGE.x, OLD_RANGE.y, _h01([plan.seed, "rw_pave", chunk.ix, chunk.iz]))
	var rng := _rng([plan.seed, "rw_pave", chunk.ix, chunk.iz])
	var top := CityChunk.SIDEWALK_TOP + 0.004
	var sw: float = plan.sidewalk_width
	# Where Kerbs builds the pavement's outer ring (ramps, aprons, tree wells, heaves), the slabs'
	# cracks keep to the inner band it leaves flat.
	var ring: float = Kerbs.RING if Kerbs.takes(chunk, rect) else 0.0
	var band := maxf(sw - ring, 0.5)
	for e: Array in CityChunk._sidewalk_edges(rect):
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var n := int(round(length * PAVEMENT_PER_M * level))
		for i in n:
			var along := rng.randf_range(3.0, length - 3.0)
			var into := ring + band * (rng.randf_range(sw * 0.35, sw * 0.7) / sw)
			var p := a + dir * along + inward * into
			var name := "concrete_crack" if rng.randf() < 0.8 else "concrete_spall"
			_stamp(ctx, rng, name, p, top, rng.randf() * TAU, Color(0.8, 0.8, 0.8), _age(rng, 0.6), false, false, minf(sw * 0.5, band * 0.6))


# --- Instances -----------------------------------------------------------------------------------

## One stamp at true-world `p`, `y` over the ground (before the relief), facing `yaw` (the stamp's
## v along the yaw's local z). `aligned` keeps the yaw (a stamp that runs with the road), else the
## turn is free. `fixed_u` pins the stamp's u size (metres) instead of the kind's scale range: a
## crack across a carriageway, edge break-up against a kerb.
static func _stamp(ctx: Dictionary, rng: RandomNumberGenerator, name: String, p: Vector2, y: float, yaw: float, tint: Color, age: float, aligned: bool, kerb: bool = false, fixed_u: float = 0.0) -> void:
	if int(ctx.count) >= MAX_PER_CHUNK:
		return
	var i := index_of(name)
	if i < 0:
		return
	var row: Array = RoadWearTable.STAMPS[i]
	var kind: Array = KINDS[name]
	var flags: int = row[3]
	var keeps_axis := aligned and (flags & RoadWearTable.ALIGN) != 0
	if keeps_axis:
		yaw += rng.randf_range(-0.05, 0.05)
	else:
		yaw = rng.randf() * TAU
	var base: Vector2 = row[1]
	var range_v: Vector2 = kind[0]
	var s := rng.randf_range(range_v.x, range_v.y)
	var aspect := 1.0 + rng.randf_range(-float(kind[1]), float(kind[1]))
	var size := Vector2(base.x * s * aspect, base.y * s / aspect)
	if fixed_u > 0.0:
		# A crack across the road spans the carriageway: its run is u for crack_trans, v for a
		# turned tar snake.
		if name == "crack_trans" or name == "concrete_crack" or name == "concrete_spall":
			size.x = fixed_u
			if name != "crack_trans":
				size.y = minf(size.y, fixed_u)
		elif name == "tar_snake":
			size.y = fixed_u
		elif name == "shoving":
			size.x = fixed_u
	if kerb:
		# `p` is on the kerb: the stamp's u = 0 edge goes there, its body into the road.
		p += Vector2(cos(yaw), -sin(yaw)) * (size.x * 0.5 + 0.02)
	var mirror_u := rng.randf() < 0.5 and not kerb
	var mirror_v := rng.randf() < 0.5
	var thr_a := rng.randi_range(0, int(kind[2]))
	var custom_r := float(i)
	var custom_g := (1 if mirror_u else 0) + (2 if mirror_v else 0)
	var thr_b := 0
	var zoom := 0
	if rng.randf() < PAIR_SHARE:
		var partners: Array = kind[3]
		var j := index_of(partners[rng.randi() % partners.size()])
		if j >= 0:
			custom_r += 32.0 * float(j + 1)
			custom_g += (4 if rng.randf() < 0.5 else 0) + (8 if rng.randf() < 0.5 else 0)
			# A stamp that keeps the road's axis pairs only at half turns, so a crack along the
			# road never turns across it.
			var turns := rng.randi_range(0, 3)
			var pflags: int = RoadWearTable.STAMPS[j][3]
			if (pflags & RoadWearTable.ALIGN) != 0 or keeps_axis:
				turns = 2 * rng.randi_range(0, 1)
			custom_g += 16 * turns
			thr_b = rng.randi_range(4, THR_MAX)
			zoom = rng.randi_range(0, 7)
	if (flags & RoadWearTable.SURFACE) != 0:
		custom_g += 64
	if (flags & RoadWearTable.DEEP) != 0:
		custom_g += 128
	var basis := Basis(Vector3.UP, yaw).scaled_local(Vector3(size.x, 1.0, size.y))
	var chunk: CityChunk = ctx.chunk
	var custom := Color(custom_r, float(custom_g), float(thr_a * 32 + thr_b), float(zoom))
	var col := Color(tint.r, tint.g, tint.b, age)
	chunk._batch.tilt_keys[KEY] = true
	chunk._batch.add(KEY, mesh(), Transform3D(basis, Vector3(p.x, y, p.y)), col, custom)
	ctx.count = int(ctx.count) + 1
	if _list:
		print("RW_STAMP %s %.1f,%.1f size=%.1fx%.1f yaw=%.0f thr=%d age=%.2f pair=%d" % [name, p.x, p.y, size.x, size.y, rad_to_deg(yaw), thr_a, age, int(custom_r) / 32 - 1])
	# An Array, not a PackedVector2Array: a packed array in a Dictionary is a value, and appending
	# to it appends to a copy.
	(ctx.points as Array).append(p)
	ctx.kinds[name] = int((ctx.kinds as Dictionary).get(name, 0)) + 1
	# A deep pothole the car feels.
	if name.begins_with("pothole") and float(row[2]) * s >= BUMP_DEPTH and thr_a < 16:
		var r := minf(size.x, size.y) * 0.3 * (1.0 - float(thr_a) / 52.0)
		_add_bump(chunk.key, p, r, float(row[2]) * minf(s, 1.0))


static func _age(rng: RandomNumberGenerator, bias: float) -> float:
	var t := clampf(bias + rng.randf_range(-0.45, 0.45), 0.0, 1.0)
	return floorf(t * (AGES - 1) + 0.5) / float(AGES - 1)


static func _finish(ctx: Dictionary) -> void:
	var chunk: CityChunk = ctx.chunk
	if int(ctx.count) == 0:
		return
	chunk._batch.set_no_shadow(KEY)
	chunk._batch.set_draw_distance(KEY, DRAW_DISTANCE)
	var pts: PackedVector2Array = chunk.get_meta("road_wear", PackedVector2Array())
	pts.append_array(PackedVector2Array(ctx.points))
	chunk.set_meta("road_wear", pts)
	chunk.set_meta("road_wear_count", int(ctx.count))
	var kinds: Dictionary = chunk.get_meta("road_wear_kinds", {})
	for k: String in ctx.kinds:
		kinds[k] = int(kinds.get(k, 0)) + int(ctx.kinds[k])
	chunk.set_meta("road_wear_kinds", kinds)
	if not chunk.has_meta("road_wear_forget"):
		chunk.set_meta("road_wear_forget", true)
		chunk.tree_exiting.connect(_forget.bind(chunk.key))


## The stamp's index in RoadWearTable.STAMPS, or -1.
static func index_of(name: String) -> int:
	if _index.is_empty():
		for i in RoadWearTable.STAMPS.size():
			_index[RoadWearTable.STAMPS[i][0]] = i
	return int(_index.get(name, -1))


## The number of distinct looks the variation system gives before any continuous turn or scale
## (docs): per stamp, mirrors x thresholds x ages; with a pair, partners x quarter turns x the
## pair's mirrors x zooms x thresholds on top.
static func variant_count() -> Dictionary:
	var single := 0
	var paired := 0
	for name: String in KINDS:
		var kind: Array = KINDS[name]
		var own := 4 * (int(kind[2]) + 1) * AGES
		single += own
		paired += own * (kind[3] as Array).size() * 4 * 4 * 8 * (THR_MAX - 3)
	return {"single": single, "paired": paired}


# --- The mesh and material -----------------------------------------------------------------------

## The unit quad (x across -0.5..0.5, z along, facing up) wearing the wear material.
static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var corners := [Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.5), Vector3(-0.5, 0.0, 0.5)]
	for k: int in [0, 1, 2, 0, 2, 3]:
		var v: Vector3 = corners[k]
		st.set_uv(Vector2(v.x + 0.5, v.z + 0.5))
		st.add_vertex(v)
	# Faces up: Godot's front faces are clockwise seen from the front, and (-,-) (+,-) (+,+) is
	# clockwise seen from above.
	_mesh = st.commit()
	_mesh.surface_set_material(0, material())
	_mesh.custom_aabb = AABB(Vector3(-0.5, -0.2, -0.5), Vector3(1.0, 0.4, 1.0))
	return _mesh


static var _material: ShaderMaterial = null


static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/road_wear.gdshader")
	_material.set_shader_parameter("wear_color", load("res://assets/textures/road_wear/road_wear_color.png"))
	_material.set_shader_parameter("wear_nrm", load("res://assets/textures/road_wear/road_wear_nrm.png"))
	_material.set_shader_parameter("wear_data", load("res://assets/textures/road_wear/road_wear_data.png"))
	_material.set_shader_parameter("grid", float(RoadWearTable.GRID))
	_material.set_shader_parameter("span", float(RoadWearTable.STAMP_PX) / (float(RoadWearTable.ATLAS_PX) / float(RoadWearTable.GRID)))
	_material.set_shader_parameter("height_range", RoadWearTable.HEIGHT_RANGE)
	_material.set_shader_parameter("fade_start", DRAW_DISTANCE * 0.62)
	_material.set_shader_parameter("fade_end", DRAW_DISTANCE * 0.95)
	if OS.get_environment("RW_POM") != "":
		_material.set_shader_parameter("pom_distance", float(OS.get_environment("RW_POM")))
	if OS.get_environment("RW_DEBUG") != "":
		_material.set_shader_parameter("debug_mode", int(OS.get_environment("RW_DEBUG")))
	return _material


# --- The car bump --------------------------------------------------------------------------------

static func _add_bump(chunk_key: String, p: Vector2, r: float, depth: float) -> void:
	var cell := Vector2i(floori(p.x / BUMP_CELL), floori(p.y / BUMP_CELL))
	if not _bumps.has(cell):
		_bumps[cell] = []
	(_bumps[cell] as Array).append([p, r, depth, chunk_key])


static func _forget(chunk_key: String) -> void:
	for cell: Vector2i in _bumps.keys():
		var list: Array = _bumps[cell]
		var kept := list.filter(func(e: Array) -> bool: return e[3] != chunk_key)
		if kept.is_empty():
			_bumps.erase(cell)
		else:
			_bumps[cell] = kept


## The depth (m) of the deep pothole under true-world XZ `p`, or 0: how far a wheel there drops.
static func bump_for(p: Vector2) -> float:
	if _bumps.is_empty():
		return 0.0
	var list: Variant = _bumps.get(Vector2i(floori(p.x / BUMP_CELL), floori(p.y / BUMP_CELL)))
	if list == null:
		return 0.0
	for e: Array in list:
		var d := p.distance_to(e[0])
		if d < float(e[1]):
			return float(e[2]) * (1.0 - d / float(e[1]) * 0.5)
	return 0.0


## The driven car's wheels dropping into a deep pothole (Vehicle._physics_process, the player's car
## only): a jolt down at that corner, once as the wheel enters, which the suspension throws back.
## A dictionary lookup a wheel a tick, nothing when no pothole is near.
static func bump(car: Vehicle) -> void:
	if _bumps.is_empty() or not car.is_inside_tree():
		return
	var speed := car.linear_velocity.length()
	var inside: Array = car.get_meta("rw_in", [])
	inside.resize(car.wheels.size())
	for k in car.wheels.size():
		var w := car.wheels[k]
		if not is_instance_valid(w) or not w.is_in_contact():
			continue
		var wp: Vector3 = WorldState.to_world(w.global_position)
		var depth := bump_for(Vector2(wp.x, wp.z))
		var was: bool = inside[k] == true
		inside[k] = depth > 0.0
		if depth <= 0.0 or was or speed < BUMP_MIN_SPEED:
			continue
		var kick := car.mass * BUMP_GAIN * clampf(depth / 0.06, 0.4, 2.0) * clampf(speed / 14.0, 0.3, 1.3)
		car.hold_crash_watch(3)
		car.apply_impulse(Vector3.DOWN * kick, w.global_position - car.global_position)
		Sfx.play("hit_concrete", w.global_position, -14.0 + depth * 60.0, 0.55)
	car.set_meta("rw_in", inside)


## How many deep potholes are indexed (tests).
static func bump_total() -> int:
	var n := 0
	for cell: Vector2i in _bumps:
		n += (_bumps[cell] as Array).size()
	return n


# --- Hashes --------------------------------------------------------------------------------------

static func _rng(parts: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(parts)
	return rng


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100000) / 100000.0


## Smooth 1D value noise, 0..1.
static func _noise1(x: float) -> float:
	var i := floorf(x)
	var f := x - i
	f = f * f * (3.0 - 2.0 * f)
	var a := float(absi(hash(int(i))) % 1000) / 1000.0
	var b := float(absi(hash(int(i) + 1)) % 1000) / 1000.0
	return lerpf(a, b, f)
