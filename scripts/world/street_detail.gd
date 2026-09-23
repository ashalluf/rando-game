class_name StreetDetail
extends RefCounted
## The small stuff that makes a street read as a lived-in street rather than a plan drawing:
## gutters, storm drains with kerb inlets, painted red and yellow kerbs, polished wheel tracks,
## oil stains, utility locate marks, stop lines and lane arrows, named street signs, no-parking
## blades, parking meters, bus shelters, tree grates, bike racks, news boxes, mailboxes,
## bollards - and the overhead power lines that run pole to pole down every Los Angeles street.
##
## Everything is seeded from the block or the intersection and goes through the chunk's
## MultiMeshBatch, so it follows the city relief like every other prop and costs one draw call
## per kind per chunk. Static: call with the chunk.
##
## Seeding rule: the block and intersection RandomNumberGenerators handed in are shared with the
## parked cars and the crowd that are rolled after this, so everything added here draws from its
## own hash-seeded generator (`_rng_for`) instead of the passed-in `rng`. Same seed, same city.
##
## Scaling rule: `Basis.scaled()` scales in world axes, not in the mesh's own. A piece that is
## stretched along its own length (gutters, stop lines, kerb paint, wheel tracks) must use
## `scaled_local()`, or it stretches sideways on half the streets - which is exactly what the
## stop lines on the east-west approaches used to do.

const NEWS_COLORS := [Color(0.85, 0.15, 0.15), Color(0.15, 0.3, 0.7), Color(0.95, 0.75, 0.1), Color(0.2, 0.2, 0.22)]

# --- Tunables --------------------------------------------------------------------------------
# This class is never instanced (every entry point is static), so there is no node to hang
# @export vars off: the knobs are consts and they all live here at the top.

## Metres between utility poles. Poles sit on a grid in world space, so a line keeps its rhythm
## from block to block instead of restarting at every corner.
const POLE_SPACING := 30.0
## How far a pole stands back from the kerb line, in metres (the pavement is 4 m wide).
const POLE_INSET := 0.85
## Pole length in metres; PropFactory.upole() is this tall and its base sits on the pavement.
const POLE_HEIGHT := 9.0
## Keep poles this far from a block corner, so none of them lands in a crossing.
const POLE_EDGE_MARGIN := 6.0
## Height above the pavement of the power crossarm and of the lower telecom arm.
const POWER_ARM_HEIGHT := 8.15
const TELCO_ARM_HEIGHT := 6.35
## Straight pieces per cable span: more is a smoother catenary and more instances.
const CABLE_SEGMENTS := 5
## Mid-span droop of the power and telecom cables, in metres. Telecom hangs slacker.
const POWER_SAG := 1.1
const TELCO_SAG := 1.7
## Chance a block hangs the overhead line on its side of a street, in CityPlan.District order
## (downtown, midtown, suburbs, industrial, campus). Downtown mostly buries its cables.
const POLE_ODDS := [0.16, 0.62, 1.0, 1.0, 0.38, 0.88]
## Chance a pole carries a transformer can, and a service drop to the buildings behind it.
const TRANSFORMER_ODDS := 0.34
const SERVICE_DROP_ODDS := 0.45
## How far a service drop will reach across the front garden for a wall, in metres. The setback
## is `CityPlan.sidewalk_width` plus half the district's lot gap, which runs to 18 m in the
## industrial blocks, so the drop is aimed at a wall that is really standing there rather than at
## a fixed distance - and is not hung at all when nothing is within this, or it ends in open air.
const SERVICE_DROP_REACH := 16.0
## How far past the wall face the drop ends, so it reads as fixed to the building.
const SERVICE_DROP_BITE := 0.5
## Height above the pavement that a service drop lands on the wall at.
const SERVICE_DROP_HEIGHT := 3.8
## Metres of clearance kept between a pole and the edge of a freeway deck. A pole's tip is
## POLE_HEIGHT + SIDEWALK_TOP above the ground and the deck's underside is only
## Freeway.DECK_RISE - Freeway.DECK_THICKNESS above it at best (less wherever the grade limiter
## could hold no more than MIN_CLEARANCE), so a run that crosses the corridor has to break
## rather than drive poles, crossarms, cables and a collision box through the slab.
const FREEWAY_CLEARANCE := 3.0
## Draw distances in metres for the line: wires read from far off, the fittings do not.
const CABLE_DRAW_DISTANCE := 340.0
const POLE_FITTING_DRAW_DISTANCE := 150.0

## Length of one kerb-paint piece. `kerb_paint` is not one of the chunk's `tilt_keys`, so
## `_kerb_run` tilts each piece onto the ground itself; short pieces then keep what the tilt
## cannot follow - the curvature of the relief across one piece - down in the millimetres,
## against a kerb face only 15 cm tall. At 3 m and untilted the paint used to float clear of the
## kerb at one end of a piece and bury itself at the other.
const KERB_PAINT_PIECE := 1.5
## Metres of red kerb at each end of a block face (no stopping near a crossing).
const KERB_RED_RANGE := Vector2(5.0, 9.5)
## Colours of the painted kerb zones.
const KERB_RED := Color(0.72, 0.13, 0.11)
const KERB_YELLOW := Color(0.85, 0.66, 0.08)
const KERB_WHITE := Color(0.92, 0.92, 0.9)
const KERB_DRAW_DISTANCE := 210.0
## Chance of a mid-block loading (yellow) or passenger (white) zone, per district.
const LOADING_ODDS := [0.55, 0.38, 0.08, 0.6, 0.14, 0.22]

## Metres between parking meters along a metered kerb, and how far in from the kerb they stand.
const METER_SPACING := 10.0
const METER_INSET := 0.7
## Chance a downtown / midtown block face is metered.
const METER_ODDS := [0.75, 0.4, 0.0, 0.0, 0.0, 0.8]
const METER_DRAW_DISTANCE := 140.0

## Polished wheel tracks: piece length, wheel gauge, strip width, and how much lighter than a
## neutral patch they are (the patch mesh is mid grey, the asphalt under it is much darker, so
## anything near 0.5 sits just off the road's own value). Keep it subtle.
const WHEEL_TRACK_PIECE := 14.0
const WHEEL_TRACK_GAUGE := 1.72
const WHEEL_TRACK_WIDTH := 0.46
const WHEEL_TRACK_SHADE := 0.5
## Chance a road shows wheel polish at all.
const WHEEL_TRACK_ODDS := 0.7
## Shade range of an oil stain (the same patch mesh, much darker).
const OIL_SHADE := Vector2(0.11, 0.22)
## Spray-painted utility locate marks, the ones every resurfaced street has near the kerb.
const LOCATE_COLORS := [Color(1.7, 0.7, 0.1), Color(0.25, 0.7, 1.9), Color(1.6, 0.2, 1.4), Color(0.4, 1.6, 0.4)]
const LOCATE_ODDS := 0.45

## Heights above ROAD_TOP of the flat markings, so they layer instead of fighting.
const Y_WHEEL_TRACK := 0.0045
const Y_OIL := 0.0055
const Y_LOCATE := 0.007

static var _meshes: Dictionary = {}


## Sidewalk-ring details for one block. `edges` are [a, b, inward] like the chunk's props.
static func build_block(chunk: CityChunk, rect: Rect2, edges: Array, params: Dictionary, district: int, rng: RandomNumberGenerator) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var top: float = CityChunk.SIDEWALK_TOP
	var road_top: float = CityChunk.ROAD_TOP
	# Gutters: a dark strip on the asphalt along every curb, a drain grate near each corner and
	# the kerb inlet that goes with it (the slot in the kerb face the water actually runs into).
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var yaw := atan2(-dir.x, -dir.y)
		var face_yaw := atan2(-inward.x, -inward.y)
		var t := 2.0
		while t < length - 2.0:
			var piece := minf(4.0, length - 2.0 - t)
			var p := a + dir * (t + piece * 0.5) - inward * 0.3
			batch.add("gutter", PropFactory.gutter(), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(1.0, 1.0, piece / 4.0)), Vector3(p.x, road_top + 0.004, p.y)))
			t += piece
		for k in 2:
			var along := 4.0 if k == 0 else length - 4.0
			var gp := a + dir * along - inward * 0.55
			batch.add("grate", PropFactory.grate(), Transform3D(Basis(Vector3.UP, yaw), Vector3(gp.x, road_top + 0.006, gp.y)))
			var ip := a + dir * along - inward * 0.008
			# Tilted by hand: "kerb_inlet" is not one of the chunk's tilt_keys and the slot has
			# only 2 cm of margin inside a 15 cm kerb face.
			batch.add("kerb_inlet", _inlet_mesh(), Transform3D(_ground_tilt(chunk, Basis(Vector3.UP, face_yaw), ip.x, ip.y, 0.5), Vector3(ip.x, road_top + 0.075, ip.y)))
	batch.set_no_shadow("gutter")
	batch.set_no_shadow("kerb_inlet")
	batch.set_draw_distance("kerb_inlet", KERB_DRAW_DISTANCE)
	# Asphalt patches on this block's two roads.
	var plan: CityPlan = chunk.plan
	var roads := [
		[Vector2(plan.road_pos(CityPlan.AXIS_X, chunk.ix + 1), rect.get_center().y), Vector2(plan.road_width(CityPlan.AXIS_X, chunk.ix + 1), rect.size.y)],
		[Vector2(rect.get_center().x, plan.road_pos(CityPlan.AXIS_Z, chunk.iz + 1)), Vector2(rect.size.x, plan.road_width(CityPlan.AXIS_Z, chunk.iz + 1))],
	]
	for road in roads:
		var c: Vector2 = road[0]
		var s: Vector2 = road[1]
		for i in rng.randi_range(1, 4):
			var w := rng.randf_range(1.5, 4.0)
			var d := rng.randf_range(2.0, 6.0)
			var p := Vector2(rng.randf_range(c.x - s.x * 0.5 + 2.0, c.x + s.x * 0.5 - 2.0), rng.randf_range(c.y - s.y * 0.5 + 3.0, c.y + s.y * 0.5 - 3.0))
			var shade := 0.55 + rng.randf() * 0.7
			batch.add("patch", PropFactory.patch(), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)).scaled_local(Vector3(w, 1.0, d)), Vector3(p.x, road_top + 0.003, p.y)), Color(shade, shade, shade))
	# Wear: polished wheel tracks down the lanes, oil where cars park, locate paint by the kerb.
	# All of it rides in the "patch" batch, so it is free in draw calls and tilts with the road.
	_wheel_tracks(chunk, roads)
	_road_wear(chunk, edges)
	batch.set_no_shadow("patch")
	# Overhead power and telecom lines. Replaces the old per-block pole run, which picked an
	# edge at random (so the line stopped and hopped sides at every corner) and sank the pole
	# mesh to its middle, leaving the crossarm and the wires floating four metres above it.
	_overhead_lines(chunk, rect)
	# Painted kerbs and parking meters.
	_kerb_paint(chunk, edges, district)
	_parking_meters(chunk, edges, district)
	# Sidewalk furniture by district.
	var corner_count := 0
	var rack_odds := 0.6 if district == CityPlan.District.DOWNTOWN or district == CityPlan.District.CAMPUS else 0.25
	var news_odds := 0.7 if district == CityPlan.District.DOWNTOWN else 0.3
	var mail_odds := 0.5 if district == CityPlan.District.SUBURBS or district == CityPlan.District.MIDTOWN else 0.15
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var yaw := atan2(-inward.x, -inward.y)
		if rng.randf() < rack_odds:
			var p := a + dir * rng.randf_range(8.0, length - 8.0) + inward * 1.2
			var basis := Basis(Vector3.UP, yaw)
			for k in 3:
				var q := p + dir * (k - 1) * 0.8
				chunk._add_prop("rack", Vector3(q.x, top, q.y), Color(0.3, 0.3, 0.32), [
					["rack", PropFactory.bike_rack(), Transform3D(basis, Vector3(q.x, top, q.y))],
				], [[Vector3(0.9, 0.9, 0.1), Vector3(q.x, top + 0.45, q.y), yaw]])
		if rng.randf() < news_odds:
			var p := a + dir * rng.randf_range(5.0, 12.0) + inward * 1.0
			for k in rng.randi_range(1, 3):
				var q := p + dir * k * 0.55
				var color: Color = NEWS_COLORS[rng.randi() % NEWS_COLORS.size()]
				chunk._add_prop("newsbox", Vector3(q.x, top, q.y), color, [
					["newsbox", PropFactory.news_box(), Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, top + 0.55, q.y)), color],
				], [[Vector3(0.5, 1.1, 0.5), Vector3(q.x, top + 0.55, q.y), yaw]])
		if rng.randf() < mail_odds:
			var p := a + dir * rng.randf_range(10.0, length - 10.0) + inward * 1.1
			chunk._add_prop("mailbox", Vector3(p.x, top, p.y), Color(0.15, 0.3, 0.25), [
				["mailbox", PropFactory.mailbox(), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, top, p.y))],
			], [[Vector3(0.6, 1.3, 0.5), Vector3(p.x, top + 0.65, p.y), yaw]])
		corner_count += 1
	# Bus shelter on an avenue side (one per block at most).
	var wx := plan.road_width(CityPlan.AXIS_X, chunk.ix + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, chunk.iz + 1)
	var avenue_edges: Array = []
	if wx > plan.street_width + 1.0:
		avenue_edges.append(edges[3])
	if wz > plan.street_width + 1.0:
		avenue_edges.append(edges[1])
	if not avenue_edges.is_empty() and rng.randf() < 0.45:
		var e: Array = avenue_edges[rng.randi() % avenue_edges.size()]
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var dir := (b - a).normalized()
		var p := a + dir * rng.randf_range(12.0, a.distance_to(b) - 12.0) + inward * 2.0
		_bus_shelter(chunk, p, inward, dir)


## Intersection details: stop lines, lane arrows, junction wear, street name signs, no-parking
## blades, bollards downtown.
static func build_intersection(chunk: CityChunk, pos: Vector2, size: Vector2, kind: int, rng: RandomNumberGenerator) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var plan: CityPlan = chunk.plan
	var road_top: float = CityChunk.ROAD_TOP
	var top: float = CityChunk.SIDEWALK_TOP
	# Four approaches: right-hand traffic, so the stop line spans the half of the road that
	# carries traffic toward the intersection.
	var approaches := [
		[Vector2(0.0, 1.0), size.y, size.x],   # from +Z (south), road along Z, width size.x
		[Vector2(0.0, -1.0), size.y, size.x],
		[Vector2(1.0, 0.0), size.x, size.y],
		[Vector2(-1.0, 0.0), size.x, size.y],
	]
	for ap in approaches:
		var d: Vector2 = ap[0]                 # direction from the center to the approach
		var along_w: float = ap[1]             # width of the crossing road (how far the approach starts)
		var road_w: float = ap[2]              # width of the approach road
		var half_w := road_w * 0.5
		var perp := Vector2(-d.y, d.x)
		# Right-hand traffic: cars arriving along -d keep to their right, which is -perp here
		# (matches TrafficManager._lane_offset for every approach).
		var inbound_side := -1.0
		var lane_c: Vector2 = pos + d * (along_w * 0.5 + 3.3) + perp * inbound_side * half_w * 0.5
		var yaw := atan2(-d.x, -d.y)
		if kind != CityPlan.Intersection.PLAIN:
			# scaled_local, not scaled: the east-west stop lines used to come out 1 m long and
			# three metres thick, because a world-axis scale stretched their depth instead.
			batch.add("stop_line", PropFactory.stop_line(), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(half_w - 1.0, 1.0, 1.0)), Vector3(lane_c.x, road_top + 0.016, lane_c.y)))
			_junction_wear(chunk, pos, d, perp * inbound_side, along_w, half_w)
		# Lane arrows on avenues (two lanes: straight in the outer, left turn in the inner).
		if road_w > plan.street_width + 1.0:
			var lanes := 2
			for l in lanes:
				# The same lane centres the traffic drives (CityPlan.lane_center).
				var lc: Vector2 = pos + d * (along_w * 0.5 + 9.0) + perp * inbound_side * CityPlan.lane_center(road_w, lanes, l)
				var mesh := PropFactory.arrow_left() if l == lanes - 1 else PropFactory.arrow_straight()
				var flip := Basis(Vector3.UP, yaw + PI)
				# The left-turn arrow bends to mesh -X; mirror it when that lands on the driver's
				# right. The mirror has to be local, or on half the approaches it flips the arrow
				# end for end instead of side to side and it points back up the road.
				var turned_left := flip * Vector3(-1.0, 0.0, 0.0)
				var want_left := Vector3.UP.cross(Vector3(-d.x, 0.0, -d.y))
				if l == lanes - 1 and turned_left.dot(want_left) < 0.0:
					flip = flip.scaled_local(Vector3(-1.0, 1.0, 1.0))
				batch.add("arrow_left" if l == lanes - 1 else "arrow_straight", mesh, Transform3D(flip, Vector3(lc.x, road_top + 0.016, lc.y)))
	# Street name signs. The +X +Z corner always carries one; the opposite corner often does too,
	# so the name is readable from more than one approach.
	var name_x := plan.road_name(CityPlan.AXIS_X, chunk.ix + 1)
	var name_z := plan.road_name(CityPlan.AXIS_Z, chunk.iz + 1)
	_name_sign(chunk, pos + Vector2(size.x * 0.5 + 1.4, size.y * 0.5 + 1.4), name_x, name_z)
	if _hash01([plan.seed, "sign2", chunk.ix, chunk.iz]) < 0.55:
		_name_sign(chunk, pos + Vector2(-size.x * 0.5 - 1.4, -size.y * 0.5 - 1.4), name_x, name_z)
	# No-parking blades on the kerb beside the junction.
	if kind != CityPlan.Intersection.PLAIN:
		_regulatory_signs(chunk, pos, size)
	# Bollards on downtown corners.
	if chunk.plan.district_at(pos) == CityPlan.District.DOWNTOWN and rng.randf() < 0.6:
		for c: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			var cc := pos + Vector2(c.x * (size.x * 0.5 + 0.6), c.y * (size.y * 0.5 + 0.6))
			for k in 3:
				var q := cc + Vector2(c.x * k * 1.1, 0.0) if k < 2 else cc + Vector2(0.0, c.y * 1.1)
				chunk._add_prop("bollard", Vector3(q.x, top, q.y), Color(0.25, 0.25, 0.27), [
					["bollard", PropFactory.bollard(), Transform3D(Basis(), Vector3(q.x, top + 0.45, q.y))],
				], [[Vector3(0.3, 0.9, 0.3), Vector3(q.x, top + 0.45, q.y), 0.0]])


# --- Overhead lines --------------------------------------------------------------------------

## Poles and cables along the streets this block faces. Each street picks one side from a hash,
## so exactly one of the two blocks facing it hangs the line and a street never gets two; the
## poles sit on a world-space grid, so the run carries on in step in the next block and the wire
## crosses the junction to meet it.
static func _overhead_lines(chunk: CityChunk, rect: Rect2) -> void:
	var plan: CityPlan = chunk.plan
	# [axis, road index, which side of that road this block sits on: 1 = above, 0 = below].
	var faces := [
		[CityPlan.AXIS_X, chunk.ix, 1], [CityPlan.AXIS_X, chunk.ix + 1, 0],
		[CityPlan.AXIS_Z, chunk.iz, 1], [CityPlan.AXIS_Z, chunk.iz + 1, 0],
	]
	# Gathered once for the whole block: what a service drop is allowed to land on.
	var walls := _footprints(chunk)
	for f in faces:
		var axis: int = f[0]
		var index: int = f[1]
		var side: int = f[2]
		if absi(hash([plan.seed, "pole_side", axis, index])) % 2 != side:
			continue
		if not _has_poles(plan, chunk.ix, chunk.iz, axis, index):
			continue
		_pole_run(chunk, rect, axis, index, side, walls)


## True when the block at (bix, biz) hangs the overhead line for road `index` on `axis`. The
## block across the junction asks this too, so the wire that spans the junction is drawn exactly
## once and only when there really is a pole waiting at the far end.
static func _has_poles(plan: CityPlan, bix: int, biz: int, axis: int, index: int) -> bool:
	var block: Dictionary = plan.block(bix, biz)
	var centre: Vector2 = (block.rect as Rect2).get_center()
	if plan.zone_at(centre) != MacroMap.Zone.CITY:
		return false
	var district: int = plan.district_at(centre)
	return _hash01([plan.seed, "poles", bix, biz, axis, index]) < POLE_ODDS[district]


static func _pole_run(chunk: CityChunk, rect: Rect2, axis: int, index: int, side: int, walls: Array[Rect2]) -> void:
	var plan: CityPlan = chunk.plan
	var batch: MultiMeshBatch = chunk._batch
	var top: float = CityChunk.SIDEWALK_TOP
	# An AXIS_X road is a line of constant x, so it runs along Z.
	var along_z := axis == CityPlan.AXIS_X
	var kerb: float = (rect.position.x if side == 1 else rect.end.x) if along_z else (rect.position.y if side == 1 else rect.end.y)
	var inset := POLE_INSET if side == 1 else -POLE_INSET
	var line := kerb + inset
	var u0: float = rect.position.y if along_z else rect.position.x
	var u1: float = rect.end.y if along_z else rect.end.x
	var phase := float(absi(hash([plan.seed, "pole_phase", axis, index])) % 1000) * 0.001 * POLE_SPACING
	var first := ceili((u0 + POLE_EDGE_MARGIN - phase) / POLE_SPACING)
	var last := floori((u1 - POLE_EDGE_MARGIN - phase) / POLE_SPACING)
	if last < first:
		return
	# The crossarms point across the street, the pole's own yaw follows.
	var yaw := 0.0 if along_z else PI * 0.5
	var arm := Vector3(1.0, 0.0, 0.0) if along_z else Vector3(0.0, 0.0, 1.0)
	var run_dir := Vector3(0.0, 0.0, 1.0) if along_z else Vector3(1.0, 0.0, 0.0)
	var into := arm * signf(inset)
	var drops := not walls.is_empty()
	# The poles that actually get built, and for each of them whether the slot before it was
	# skipped. A skipped slot breaks the run: the wire must not carry on across the gap.
	var points: Array[Vector3] = []
	var breaks: Array[bool] = []
	var gap_before := false
	for k in range(first, last + 1):
		var u := phase + k * POLE_SPACING
		var p := Vector3(line, top, u) if along_z else Vector3(u, top, line)
		# Nothing is driven into the freeway corridor: the deck's underside is below the tip of
		# a nine-metre pole, so the pole, its crossarms, its wires and its collision box would
		# all be inside the slab.
		if _pole_blocked(chunk, p):
			gap_before = true
			continue
		points.append(p)
		breaks.append(gap_before)
		gap_before = false
		batch.add("upole", PropFactory.upole(), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0.0, POLE_HEIGHT * 0.5, 0.0)))
		batch.add("crossarm", PropFactory.crossarm(), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0.0, POWER_ARM_HEIGHT, 0.0)))
		batch.add("crossarm", PropFactory.crossarm(), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(0.62, 1.0, 1.0)), p + Vector3(0.0, TELCO_ARM_HEIGHT, 0.0)))
		for i in 3:
			batch.add("insulator", _insulator_mesh(), Transform3D(Basis(), p + arm * (i - 1) * 0.72 + Vector3(0.0, POWER_ARM_HEIGHT + 0.14, 0.0)))
		if _hash01([plan.seed, "xfmr", axis, index, k]) < TRANSFORMER_ODDS:
			batch.add("transformer", _transformer_mesh(), Transform3D(Basis(), p + arm * 0.5 + Vector3(0.0, POWER_ARM_HEIGHT - 1.0, 0.0)))
		# A pole you can crash a car into. Not breakable: the wires hang off it.
		chunk._add_shape(Vector3(0.36, POLE_HEIGHT, 0.36), p + Vector3(0.0, POLE_HEIGHT * 0.5 + chunk._gy(p.x, p.z), 0.0), yaw)
		# Service drop across the pavement to the wall behind. Aimed at a wall that is really
		# there: the setback is `CityPlan.sidewalk_width` plus half the district's lot gap, and
		# that gap runs 6-14 m in the suburbs and 10-18 m industrial, both of which hang poles on
		# every block, so a fixed 6 m drop ended 0.15-6 m short of every one of those facades and
		# hung in open air over the front garden. Nothing in reach - an inter-lot gap, a
		# courtyard lot, a lot skipped for a landmark or for the freeway - means no drop at all.
		if drops and _hash01([plan.seed, "drop", axis, index, k]) < SERVICE_DROP_ODDS:
			var reach := _facade_reach(walls, p, into)
			if reach > 0.0:
				var wall := p + into * (reach + SERVICE_DROP_BITE)
				_catenary(batch, _lift(chunk, p, TELCO_ARM_HEIGHT), _lift(chunk, wall, SERVICE_DROP_HEIGHT), 0.4)
	if points.is_empty():
		return
	# The wire run: pole to pole, then on across the junction to the first pole of the next
	# block when that block hangs the same line and has a pole standing at that end.
	var n := points.size()
	for i in n - 1:
		if breaks[i + 1]:
			continue
		_span(chunk, points[i], points[i + 1], arm)
	var nbx := chunk.ix if along_z else chunk.ix + 1
	var nbz := chunk.iz + 1 if along_z else chunk.iz
	var bridged := false
	if not gap_before:
		var ahead := _junction_pole(chunk, nbx, nbz, axis, index, along_z, line, phase, false)
		if not ahead.is_empty():
			_span(chunk, points[n - 1], ahead[0], arm)
			bridged = true
	# Down-guys where the run really ends, so a terminal pole looks anchored instead of cut off.
	# A pole the block behind us bridged to, or a through pole, gets none. Both blocks decide
	# this from the same pure functions, so the two sides always agree.
	var pbx := chunk.ix if along_z else chunk.ix - 1
	var pbz := chunk.iz - 1 if along_z else chunk.iz
	var behind := _junction_pole(chunk, pbx, pbz, axis, index, along_z, line, phase, true)
	for i in n:
		if breaks[i] or (i == 0 and behind.is_empty()):
			_guy(chunk, points[i], -run_dir)
		var ends := breaks[i + 1] if i < n - 1 else not bridged
		if ends:
			_guy(chunk, points[i], run_dir)
	batch.set_no_shadow("cable")
	batch.set_draw_distance("cable", CABLE_DRAW_DISTANCE)
	batch.set_draw_distance("insulator", POLE_FITTING_DRAW_DISTANCE)


## One pole-to-pole span: three power wires on the upper arm, two telecom on the lower.
static func _span(chunk: CityChunk, a: Vector3, b: Vector3, arm: Vector3) -> void:
	var batch: MultiMeshBatch = chunk._batch
	for k in 3:
		var o := arm * (k - 1) * 0.72
		_catenary(batch, _lift(chunk, a + o, POWER_ARM_HEIGHT + 0.2), _lift(chunk, b + o, POWER_ARM_HEIGHT + 0.2), POWER_SAG)
	for k in 2:
		var o := arm * (k * 2.0 - 1.0) * 0.44
		_catenary(batch, _lift(chunk, a + o, TELCO_ARM_HEIGHT + 0.08), _lift(chunk, b + o, TELCO_ARM_HEIGHT + 0.08), TELCO_SAG)


## True where a pole would stand inside a freeway corridor. `Freeway._clear_ground()` only
## guarantees MIN_CLEARANCE (4 m) over the ground, well under a pole's 9.25 m tip, so a pole in
## the corridor is through the deck - along with the solid box a car can hit.
static func _pole_blocked(chunk: CityChunk, p: Vector3) -> bool:
	return chunk._under_freeway(Vector2(p.x, p.z), FREEWAY_CLEARANCE)


## The pole of the neighbouring block that a wire would meet across the junction, as a one-entry
## array, or empty when that block hangs no line, has no pole at that end, or its end pole stands
## in a freeway corridor. `low_end` asks for the neighbour before us on the run instead of after.
## Pure: both blocks facing a junction evaluate it identically, so a span is drawn exactly once
## and a guy wire goes exactly where a span does not.
static func _junction_pole(chunk: CityChunk, bx: int, bz: int, axis: int, index: int, along_z: bool, line: float, phase: float, low_end: bool) -> Array:
	var plan: CityPlan = chunk.plan
	if not _has_poles(plan, bx, bz, axis, index):
		return []
	var nrect: Rect2 = plan.block(bx, bz).rect
	var nu0: float = nrect.position.y if along_z else nrect.position.x
	var nu1: float = nrect.end.y if along_z else nrect.end.x
	var nfirst := ceili((nu0 + POLE_EDGE_MARGIN - phase) / POLE_SPACING)
	var nlast := floori((nu1 - POLE_EDGE_MARGIN - phase) / POLE_SPACING)
	if nlast < nfirst:
		return []
	var u := phase + (nlast if low_end else nfirst) * POLE_SPACING
	var p := Vector3(line, CityChunk.SIDEWALK_TOP, u) if along_z else Vector3(u, CityChunk.SIDEWALK_TOP, line)
	if _pole_blocked(chunk, p):
		return []
	return [p]


## The ground-storey walls of this block, in the same plan coordinates the pole run works in.
## Read off the `Building` nodes the lot builder has already added as children of the chunk:
## `CityStreamer` adds a chunk to the tree before calling `build()`, so every `add_child()` has
## run that building's `_ready()` and its parts are final by the time the sidewalk props go in.
## A lot that became a courtyard garden, or was skipped for a landmark or for the freeway
## corridor, never made a node, so it is absent here without a second copy of any of those rules.
##
## `Building.parts` rather than `Building.footprint`, because the footprint is the symmetric
## bounding extent: on an L-shaped building it covers the notch, and a drop aimed into the notch
## would end in mid air again. The parts are axis-aligned boxes, and only the ones standing on
## the base are walls a service head can be fixed to - an upper setback is metres above it and
## is not over the garden anyway.
static func _footprints(chunk: CityChunk) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c in chunk.get_children():
		var b := c as Building
		if b == null:
			continue
		var o := Vector2(b.position.x, b.position.z)
		for part in b.parts:
			var size: Vector3 = part.size
			var mid: Vector3 = part.center
			if mid.y - size.y * 0.5 > 0.05:
				continue
			out.append(Rect2(o + Vector2(mid.x, mid.z) - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)))
	return out


## Distance from `p` along `into` to the nearest wall in `walls`, or -1 when nothing stands
## within SERVICE_DROP_REACH. `into` is axis-aligned and the footprints are axis-aligned rects,
## so this is a couple of compares per building and the list is one block long.
static func _facade_reach(walls: Array[Rect2], p: Vector3, into: Vector3) -> float:
	var along_x := absf(into.x) > 0.5
	var s := into.x if along_x else into.z
	var o := p.x if along_x else p.z
	var cross := p.z if along_x else p.x
	var best := -1.0
	for r: Rect2 in walls:
		var lo: float = r.position.y if along_x else r.position.x
		var hi: float = r.end.y if along_x else r.end.x
		if cross < lo or cross > hi:
			continue
		var near: float = (r.position.x if along_x else r.position.y) if s > 0.0 else (r.end.x if along_x else r.end.y)
		var d := (near - o) * s
		if d <= 0.5 or d > SERVICE_DROP_REACH:
			continue
		if best < 0.0 or d < best:
			best = d
	return best


## A guy wire from near the top of a terminal pole down to an anchor in the pavement.
static func _guy(chunk: CityChunk, pole: Vector3, dir: Vector3) -> void:
	var anchor := pole + dir * 3.4
	_cable(chunk._batch, _lift(chunk, pole, POWER_ARM_HEIGHT - 0.35), _lift(chunk, anchor, 0.1))


## World point at `at` raised `height` above the pavement, including the city relief.
static func _lift(chunk: CityChunk, at: Vector3, height: float) -> Vector3:
	return Vector3(at.x, at.y + height + chunk._gy(at.x, at.z), at.z)


## A sagging wire from a to b, approximated with CABLE_SEGMENTS straight pieces on a parabola.
static func _catenary(batch: MultiMeshBatch, a: Vector3, b: Vector3, sag: float) -> void:
	var prev := a
	for i in range(1, CABLE_SEGMENTS + 1):
		var s := float(i) / float(CABLE_SEGMENTS)
		var next := a.lerp(b, s) - Vector3(0.0, sag * 4.0 * s * (1.0 - s), 0.0)
		_cable(batch, prev, next)
		prev = next


## One straight cable piece between two true world points.
static func _cable(batch: MultiMeshBatch, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var basis := Basis.looking_at(b - a, Vector3.UP).scaled_local(Vector3(1.0, 1.0, length))
	var center := (a + b) * 0.5
	# The batch adds the relief; these points already include it, so take it back out.
	batch.add("cable", PropFactory.cable(), Transform3D(basis, Vector3(center.x, center.y - (batch.ground.call(center.x, center.z) if batch.ground.is_valid() else 0.0), center.z)))


# --- Kerbs, meters and road wear ---------------------------------------------------------------

## Red kerb at both ends of every block face and the odd loading zone mid-block. Nothing says
## "American street" for fewer triangles than painted kerbs.
static func _kerb_paint(chunk: CityChunk, edges: Array, district: int) -> void:
	var batch: MultiMeshBatch = chunk._batch
	for i in edges.size():
		var e: Array = edges[i]
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var length := a.distance_to(b)
		if length < 18.0:
			continue
		var dir := (b - a) / length
		var yaw := atan2(-inward.x, -inward.y)
		var rng := _rng_for([chunk.plan.seed, "kerb", chunk.ix, chunk.iz, i])
		var red_a := rng.randf_range(KERB_RED_RANGE.x, KERB_RED_RANGE.y)
		var red_b := rng.randf_range(KERB_RED_RANGE.x, KERB_RED_RANGE.y)
		_kerb_run(chunk, a, dir, yaw, 0.5, red_a, KERB_RED)
		_kerb_run(chunk, a, dir, yaw, length - 0.5 - red_b, red_b, KERB_RED)
		if rng.randf() < LOADING_ODDS[district]:
			var run := rng.randf_range(7.0, 14.0)
			var lo := red_a + 4.0
			var hi := length - red_b - run - 4.0
			if hi > lo:
				var color := KERB_YELLOW if rng.randf() < 0.7 else KERB_WHITE
				_kerb_run(chunk, a, dir, yaw, rng.randf_range(lo, hi), run, color)
	batch.set_no_shadow("kerb_paint")
	batch.set_draw_distance("kerb_paint", KERB_DRAW_DISTANCE)


## One painted run along a kerb. The paint mesh wraps a kerb face only 15 cm tall, so it has to
## follow the ground the way the kerb does - and "kerb_paint" is not one of the keys listed in
## `CityChunk.build()`'s `tilt_keys`, so the batch gives it the relief height and no tilt at all.
## An untilted 3 m piece on the grades these blocks are built for (a metre or so of relief across
## one 20-30 m lot, which is what `Building.plinth_depth` is computed for) is 6 cm out at each
## end of a 15 cm face: asphalt shows under the paint at the uphill end and the paint is buried
## at the downhill one. So each piece is tilted here, with the same maths the batch applies to
## its own tilt keys, and KERB_PAINT_PIECE is short enough that the curvature a flat piece cannot
## follow stays in the millimetres.
##
## What is left over is that the kerb face is the sidewalk slab's skirt, and that slab is a grid
## of about 5 m quads, so the kerb is a chord between grid vertices while the paint sits on the
## smooth relief. That gap is a few millimetres at these curvatures and the mesh carries enough
## margin above and below the face to swallow it - see `_kerb_paint_mesh()`. Matching the chord
## exactly would mean hard-coding `CityChunk`'s grid step in this file, which is a worse trade.
static func _kerb_run(chunk: CityChunk, a: Vector2, dir: Vector2, yaw: float, from_t: float, run: float, color: Color) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var t := 0.0
	while t < run - 0.05:
		var piece := minf(KERB_PAINT_PIECE, run - t)
		var p := a + dir * (from_t + t + piece * 0.5)
		var basis := _ground_tilt(chunk, Basis(Vector3.UP, yaw), p.x, p.y, piece * 0.45).scaled_local(Vector3(piece, 1.0, 1.0))
		batch.add("kerb_paint", _kerb_paint_mesh(), Transform3D(basis, Vector3(p.x, CityChunk.ROAD_TOP, p.y)), color)
		t += piece


## `basis` rotated onto the ground slope at (x, z), sampled `half` either side so a piece takes
## its own slope rather than an average over its neighbours. Same maths as the tilt
## `MultiMeshBatch.add()` applies to its `tilt_keys`, applied on the same side of the basis, so a
## piece lands exactly where a tilted batch key would. The keys handled here are not in
## `CityChunk.build()`'s `tilt_keys` and that file is not this one to grow.
static func _ground_tilt(chunk: CityChunk, basis: Basis, x: float, z: float, half: float) -> Basis:
	var e := clampf(half, 0.1, 0.6)
	var gx := (chunk._gy(x + e, z) - chunk._gy(x - e, z)) / (2.0 * e)
	var gz := (chunk._gy(x, z + e) - chunk._gy(x, z - e)) / (2.0 * e)
	var normal := Vector3(-gx, 1.0, -gz).normalized()
	var axis := Vector3.UP.cross(normal)
	if axis.length_squared() < 1e-8:
		return basis
	return Basis(axis.normalized(), Vector3.UP.angle_to(normal)) * basis


## Parking meters along the two kerbs this block owns, downtown and midtown only. Breakable,
## one shape each, and they stop drawing well before the pavement they stand on does.
static func _parking_meters(chunk: CityChunk, edges: Array, district: int) -> void:
	if METER_ODDS[district] <= 0.0:
		return
	var top: float = CityChunk.SIDEWALK_TOP
	for i in [1, 3]:
		if _hash01([chunk.plan.seed, "meters", chunk.ix, chunk.iz, i]) > METER_ODDS[district]:
			continue
		var e: Array = edges[i]
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var length := a.distance_to(b)
		if length < 30.0:
			continue
		var dir := (b - a) / length
		var yaw := atan2(-inward.x, -inward.y)
		var t := 8.0
		while t < length - 8.0:
			var p := a + dir * t + inward * METER_INSET
			var at := Vector3(p.x, top, p.y)
			chunk._add_prop("meter", at, Color(0.32, 0.33, 0.34), [
				["meter", _meter_mesh(), Transform3D(Basis(Vector3.UP, yaw), at)],
			], [[Vector3(0.2, 1.4, 0.2), at + Vector3(0.0, 0.7, 0.0), yaw]])
			t += METER_SPACING
	chunk._batch.set_draw_distance("meter", METER_DRAW_DISTANCE)


## Polished strips where the wheels run. Real asphalt is worn lighter and smoother along the
## wheel paths and darker between them; this is the cheapest thing that stops a carriageway
## reading as one flat surface with paint on it. Pieces are short so they tilt with the relief.
static func _wheel_tracks(chunk: CityChunk, roads: Array) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var road_top: float = CityChunk.ROAD_TOP
	for r in roads.size():
		var c: Vector2 = roads[r][0]
		var s: Vector2 = roads[r][1]
		var along_z := r == 0
		var width: float = s.x if along_z else s.y
		var span: float = s.y if along_z else s.x
		if _hash01([chunk.plan.seed, "tracks", chunk.ix, chunk.iz, r]) > WHEEL_TRACK_ODDS:
			continue
		var rng := _rng_for([chunk.plan.seed, "trackshade", chunk.ix, chunk.iz, r])
		var u0: float = (c.y if along_z else c.x) - span * 0.5
		for lane: float in [-1.0, 1.0]:
			for wheel: float in [-1.0, 1.0]:
				var off := lane * width * 0.25 + wheel * WHEEL_TRACK_GAUGE * 0.5
				var t := 0.0
				while t < span - 0.5:
					var piece := minf(WHEEL_TRACK_PIECE, span - t)
					var u := u0 + t + piece * 0.5
					var p := Vector2(c.x + off, u) if along_z else Vector2(u, c.y + off)
					var basis := Basis(Vector3.UP, 0.0 if along_z else PI * 0.5).scaled_local(Vector3(WHEEL_TRACK_WIDTH, 1.0, piece))
					var shade := WHEEL_TRACK_SHADE * rng.randf_range(0.9, 1.12)
					batch.add("patch", PropFactory.patch(), Transform3D(basis, Vector3(p.x, road_top + Y_WHEEL_TRACK, p.y)), Color(shade, shade, shade * 1.02))
					t += piece


## Oil where cars park and the spray-painted locate marks a resurfaced street keeps for years.
static func _road_wear(chunk: CityChunk, edges: Array) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var road_top: float = CityChunk.ROAD_TOP
	for i in edges.size():
		var e: Array = edges[i]
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var length := a.distance_to(b)
		if length < 14.0:
			continue
		var dir := (b - a) / length
		var rng := _rng_for([chunk.plan.seed, "wear", chunk.ix, chunk.iz, i])
		for k in rng.randi_range(2, 6):
			var p := a + dir * rng.randf_range(4.0, length - 4.0) - inward * rng.randf_range(1.3, 2.9)
			var shade := rng.randf_range(OIL_SHADE.x, OIL_SHADE.y)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, PI)).scaled_local(Vector3(rng.randf_range(0.5, 1.1), 1.0, rng.randf_range(0.8, 1.9)))
			batch.add("patch", PropFactory.patch(), Transform3D(basis, Vector3(p.x, road_top + Y_OIL, p.y)), Color(shade, shade, shade * 1.1))
		if rng.randf() < LOCATE_ODDS:
			var base := a + dir * rng.randf_range(6.0, length - 6.0) - inward * rng.randf_range(0.9, 2.2)
			var color: Color = LOCATE_COLORS[rng.randi() % LOCATE_COLORS.size()]
			var yaw := atan2(-dir.x, -dir.y)
			for k in rng.randi_range(2, 4):
				var p := base + dir * (k - 1) * rng.randf_range(0.6, 1.4)
				var basis := Basis(Vector3.UP, yaw + rng.randf_range(-0.5, 0.5)).scaled_local(Vector3(0.09, 1.0, rng.randf_range(0.5, 1.3)))
				batch.add("patch", PropFactory.patch(), Transform3D(basis, Vector3(p.x, road_top + Y_LOCATE, p.y)), color)


## Braking polish and drip stains on an approach lane, just short of the stop line.
static func _junction_wear(chunk: CityChunk, pos: Vector2, d: Vector2, lane: Vector2, along_w: float, half_w: float) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var road_top: float = CityChunk.ROAD_TOP
	var rng := _rng_for([chunk.plan.seed, "jwear", chunk.ix, chunk.iz, int(d.x * 3.0 + d.y)])
	var yaw := atan2(-d.x, -d.y)
	for k in 2:
		var side := (k * 2.0 - 1.0) * WHEEL_TRACK_GAUGE * 0.5
		var c := pos + d * (along_w * 0.5 + rng.randf_range(5.0, 8.0)) + lane * (half_w * 0.5 + side)
		var basis := Basis(Vector3.UP, yaw).scaled_local(Vector3(WHEEL_TRACK_WIDTH * 1.2, 1.0, rng.randf_range(3.0, 6.0)))
		var shade := rng.randf_range(0.16, 0.3)
		batch.add("patch", PropFactory.patch(), Transform3D(basis, Vector3(c.x, road_top + Y_OIL, c.y)), Color(shade, shade, shade * 1.08))


# --- Signs -------------------------------------------------------------------------------------

## One street-name post: two plates crossed at the top, each with its name on both faces.
static func _name_sign(chunk: CityChunk, corner: Vector2, name_x: String, name_z: String) -> void:
	var top: float = CityChunk.SIDEWALK_TOP
	var at := Vector3(corner.x, top, corner.y)
	var instances := [
		["sign_post", PropFactory.sign_post(), Transform3D(Basis(), at + Vector3(0.0, 1.4, 0.0))],
		["sign_plate", PropFactory.sign_plate(), Transform3D(Basis(Vector3.UP, PI * 0.5), at + Vector3(0.0, 2.6, 0.0)), Color(0.1, 0.4, 0.2)],
		["sign_plate", PropFactory.sign_plate(), Transform3D(Basis(), at + Vector3(0.0, 2.32, 0.0)), Color(0.1, 0.4, 0.2)],
		["text_" + name_x, PropFactory.text_mesh(name_x), Transform3D(Basis(Vector3.UP, PI * 0.5), at + Vector3(0.03, 2.6, 0.0)), Color.WHITE],
		["text_" + name_x, PropFactory.text_mesh(name_x), Transform3D(Basis(Vector3.UP, -PI * 0.5), at + Vector3(-0.03, 2.6, 0.0)), Color.WHITE],
		["text_" + name_z, PropFactory.text_mesh(name_z), Transform3D(Basis(), at + Vector3(0.0, 2.32, 0.03)), Color.WHITE],
		["text_" + name_z, PropFactory.text_mesh(name_z), Transform3D(Basis(Vector3.UP, PI), at + Vector3(0.0, 2.32, -0.03)), Color.WHITE],
	]
	chunk._add_prop("street_sign", at, Color(0.3, 0.3, 0.32), instances, [[Vector3(0.2, 2.8, 0.2), at + Vector3(0.0, 1.4, 0.0), 0.0]])


## No-parking blades on the kerb beside a junction: a white plate with a red band along the top,
## which is what the eye picks out at a distance. Same post and plate meshes as the name signs,
## so they cost no extra draw call.
static func _regulatory_signs(chunk: CityChunk, pos: Vector2, size: Vector2) -> void:
	var plan: CityPlan = chunk.plan
	var top: float = CityChunk.SIDEWALK_TOP
	var corners := [Vector2(1, -1), Vector2(-1, 1)]
	for i in corners.size():
		var c: Vector2 = corners[i]
		if _hash01([plan.seed, "noparking", chunk.ix, chunk.iz, i]) > 0.6:
			continue
		var rng := _rng_for([plan.seed, "noparking_p", chunk.ix, chunk.iz, i])
		var along := rng.randf_range(3.5, 7.0)
		var face_x := rng.randf() < 0.5
		var at := Vector3(0.0, top, 0.0)
		var yaw := 0.0
		if face_x:
			at = Vector3(pos.x + c.x * (size.x * 0.5 + 1.3), top, pos.y + c.y * (size.y * 0.5 + along))
			yaw = PI * 0.5 * c.x
		else:
			at = Vector3(pos.x + c.x * (size.x * 0.5 + along), top, pos.y + c.y * (size.y * 0.5 + 1.3))
			yaw = 0.0 if c.y > 0.0 else PI
		var basis := Basis(Vector3.UP, yaw)
		var plate := basis.scaled_local(Vector3(0.34, 1.95, 1.0))
		var band := basis.scaled_local(Vector3(0.34, 0.42, 1.0))
		# The band sits proud of the plate along its facing direction; flat on it the two
		# coplanar faces would z-fight and the sign would flicker from every angle.
		var front := basis * Vector3(0.0, 0.0, -0.02)
		chunk._add_prop("street_sign", at, Color(0.3, 0.3, 0.32), [
			["sign_post", PropFactory.sign_post(), Transform3D(Basis(), at + Vector3(0.0, 1.25, 0.0))],
			["sign_plate", PropFactory.sign_plate(), Transform3D(plate, at + Vector3(0.0, 2.15, 0.0)), Color(0.95, 0.95, 0.93)],
			["sign_plate", PropFactory.sign_plate(), Transform3D(band, at + front + Vector3(0.0, 2.34, 0.0)), Color(0.78, 0.12, 0.1)],
		], [[Vector3(0.2, 2.6, 0.2), at + Vector3(0.0, 1.3, 0.0), yaw]])


# --- Meshes ------------------------------------------------------------------------------------

## Merges a list of [Mesh, Transform3D] parts into one cached mesh with one material, the way
## PropFactory builds its small pieces. Cached here because PropFactory is not ours to grow.
static func _merged(key: String, color: Color, roughness: float, parts: Array) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(PropFactory.material(color, roughness))
	for part in parts:
		st.append_from(part[0], 0, part[1])
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## Kerb paint: one metre of it, long along local X, with local -Z pointing into the block.
## The face strip sits just proud of the kerb face and the lip wraps over the top of the kerb,
## because kerb paint is painted over the edge and it is the top you see from a car.
##
## Built exactly to the 15 cm face, the mesh had 2 mm of total slack, which nothing that follows
## a relief field can hold. So the strip runs 5.5 cm below the face - the sidewalk slab's skirt
## hangs 75 cm, so everything under the road surface is buried rather than floating - and 8 mm
## above it, where the lip covers it. The lip is thick enough that a centimetre either way still
## leaves paint on the kerb top instead of a grey rim.
static func _kerb_paint_mesh() -> Mesh:
	var face := BoxMesh.new()
	face.size = Vector3(1.0, 0.213, 0.014)
	var lip := BoxMesh.new()
	lip.size = Vector3(1.0, 0.026, 0.16)
	return _merged("kerb_paint", Color(1.0, 1.0, 1.0), 0.75, [
		[face, Transform3D(Basis(), Vector3(0.0, 0.0515, 0.005))],
		[lip, Transform3D(Basis(), Vector3(0.0, 0.149, -0.07))],
	])


## The slot in the kerb face beside a storm grate. Long along local X, local -Z into the block.
static func _inlet_mesh() -> Mesh:
	return PropFactory.box("sd_kerb_inlet", Vector3(1.15, 0.105, 0.03), Color(0.05, 0.05, 0.06))


static func _insulator_mesh() -> Mesh:
	return PropFactory.cylinder("sd_insulator", 0.055, 0.15, Color(0.2, 0.24, 0.22), -1.0, 6)


static func _transformer_mesh() -> Mesh:
	return PropFactory.cylinder("sd_transformer", 0.33, 0.95, Color(0.44, 0.45, 0.46), -1.0, 10)


## Parking meter: post, head and a cap, base at the origin, facing local -Z.
static func _meter_mesh() -> Mesh:
	var post := CylinderMesh.new()
	post.bottom_radius = 0.045
	post.top_radius = 0.04
	post.height = 1.02
	post.radial_segments = 8
	post.rings = 1
	var head := BoxMesh.new()
	head.size = Vector3(0.16, 0.34, 0.13)
	var cap := BoxMesh.new()
	cap.size = Vector3(0.18, 0.045, 0.15)
	var foot := BoxMesh.new()
	foot.size = Vector3(0.13, 0.05, 0.13)
	return _merged("sd_meter", Color(0.34, 0.35, 0.36), 0.55, [
		[foot, Transform3D(Basis(), Vector3(0.0, 0.025, 0.0))],
		[post, Transform3D(Basis(), Vector3(0.0, 0.56, 0.0))],
		[head, Transform3D(Basis(), Vector3(0.0, 1.22, 0.0))],
		[cap, Transform3D(Basis(), Vector3(0.0, 1.41, 0.0))],
	])


# --- Seeding helpers ---------------------------------------------------------------------------

## A generator of our own, so nothing added here shifts the block rng the parked cars and the
## crowd draw from after us.
static func _rng_for(parts: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(parts)
	return rng


## A stable 0..1 roll from a hash.
static func _hash01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


static func _bus_shelter(chunk: CityChunk, p: Vector2, inward: Vector2, dir: Vector2) -> void:
	var top: float = CityChunk.SIDEWALK_TOP
	var yaw := atan2(-inward.x, -inward.y)      # faces the road
	var basis := Basis(Vector3.UP, yaw + PI)
	var at := Vector3(p.x, top, p.y)
	var back := Vector3(inward.x, 0.0, inward.y) * 0.9
	var along := Vector3(dir.x, 0.0, dir.y)
	var instances := [
		["shelter_post", PropFactory.shelter_post(), Transform3D(basis, at + back + along * 1.8 + Vector3(0.0, 1.25, 0.0))],
		["shelter_post", PropFactory.shelter_post(), Transform3D(basis, at + back - along * 1.8 + Vector3(0.0, 1.25, 0.0))],
		["shelter_roof", PropFactory.shelter_roof(), Transform3D(basis, at + back * 0.4 + Vector3(0.0, 2.55, 0.0))],
		["shelter_glass", PropFactory.shelter_glass(), Transform3D(basis, at + back + Vector3(0.0, 1.3, 0.0))],
		["bench", PropFactory.model_bench(), Transform3D(Basis(Vector3.UP, yaw), at + back * 0.55)],
		["sign_post", PropFactory.sign_post(), Transform3D(Basis(), at + along * 2.6 + Vector3(0.0, 1.4, 0.0))],
		["bus_sign", PropFactory.bus_sign(), Transform3D(basis, at + along * 2.6 + Vector3(0.0, 2.7, 0.0))],
	]
	chunk._add_prop("bus_stop", at, Color(0.3, 0.3, 0.32), instances, [[Vector3(4.2, 2.6, 1.0), at + back + Vector3(0.0, 1.3, 0.0), yaw]])
