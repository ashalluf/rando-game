class_name RoadHardware
extends RefCounted
## The road surface's hardware: what a real carriageway carries that a plan drawing does not.
## Cast-iron manhole covers (sewer and storm, four cast patterns) sitting a little proud of the
## road or sunk below the asphalt round them, each in its ring or square of patched asphalt with
## the sealant band at its sawcut; water and gas valve covers in ones and twos; storm drain kerb
## inlets (a concrete gutter apron, the slot in the kerb under a steel angle, a grate on some, the
## catch basin's lid in the pavement behind and the stencilled "NO DUMPING / DRAINS TO OCEAN"
## plaque); utility cuts (sawcut trenches of fresh or faded asphalt, across a lane or along it);
## steel road plates over an open trench with their cold-patch ramps; raised pavement markers on
## centre lines and Botts' dots for the avenues' lane lines (LA's unpainted lanes).
##
## Every mesh is built here in code at real size, on ONE shader (shaders/road_hardware.gdshader):
## what a face is rides in the vertex colour's alpha (K_*), the per-instance pattern, wear, the
## proud / sunk height and a cut's size in INSTANCE_CUSTOM. One batch per kind a chunk (`rh_*`),
## shadowless, faded out by its own draw distance. FULL chunks only (StreetDetail.build_block,
## one hook line).
##
## Placement is a hash of seed + road + slot, never the block rng: nothing the seed already
## builds moves. Lane items stay out of the crosswalks, stop lines and lane arrows at both ends
## of the road (`END_STREET` / `END_AVENUE`), off the light rail's trackway and its trench. With
## it on, the old box grates, kerb inlets and the Poly Haven manholes StreetDetail and CityChunk
## laid are not laid (their rolls were private, so nothing else moves).
##
## ROAD_DETAIL=0 in the environment is the A/B (the old pieces come back). Checks:
## tests/road_detail_checks.gd. Placements are recorded on the chunk's "road_hardware" meta (the
## MultiMesh reads back identity under --headless).

## Off: nothing is laid and the old grates, inlets and manholes stay.
static var enabled: bool = OS.get_environment("ROAD_DETAIL") != "0"

## What a face is (vertex colour alpha = (kind + 0.5) / KIND_SCALE); the shader's K_* mirror it.
enum { K_IRON, K_FRAME, K_ASPHALT, K_SEAL, K_CONCRETE, K_STEEL, K_VOID, K_CERAMIC, K_REFLECT, K_PAINT, K_CUT, K_PLATE }
const KIND_SCALE := 16.0

## Cover patterns (INSTANCE_CUSTOM.r * 8, the shader's lid_height()).
enum Pattern { SUNBURST, DIAMOND, WAFFLE, RINGS, WATER, GAS }

## Metres kept clear at each end of a road segment: the crosswalk (to 3.3 m from the junction
## square), the stop line (3.5 m) and on avenues the lane arrows (to 10.7 m).
const END_STREET := 7.0
const END_AVENUE := 13.0
## Half-width of the light rail's trackway down a rail street's middle that lane items keep off.
const RAIL_KEEP := 4.6

## Sizes (metres). A manhole's lid, its frame's outer edge, its patched collar (round radius or
## square half-side), the sealant band at the sawcut.
const LID_R := 0.37
const FRAME_R := 0.46
const COLLAR_R := 0.74
const COLLAR_SQ := 0.70
const SEAL_W := 0.035
## Proud (+) or sunk (-) range of a cover against the road (metres).
const PROUD := Vector2(-0.018, 0.012)
## A valve cover's lid and frame.
const VALVE_R := 0.105
const VALVE_FRAME_R := 0.135
const VALVE_COLLAR_R := 0.27
## A kerb inlet: the slot's length, the apron's half-length and depth into the road.
const INLET_SLOT := 2.4
const INLET_APRON := 1.9
const INLET_DEPTH := 0.95
## Along the kerb from each corner to the inlet's middle (the crosswalk ends 3.3 m in).
const INLET_ALONG := 5.8
## Kerb face height (pavement top over road top).
const KERB_H := 0.15
## A steel road plate (5 x 8 ft x 1 in) and its cold-patch ramp.
const PLATE := Vector2(2.44, 1.52)
const PLATE_T := 0.025
const PLATE_RAMP := 0.2
## Raised pavement markers along a centre line: one every 48 ft.
const RPM_SPACING := 14.63
## Botts' dots lane lines: a cycle of 24 ft, four dots 3 ft apart, then a marker.
const BOTTS_CYCLE := 7.32
const BOTTS_STEP := 0.91
const BOTTS_MARKER_AT := 4.57
## Share of dots and markers that have come off an old road.
const MISSING := 0.07

## Odds per road segment.
const RPM_STREET_ODDS := 0.55
const PLATE_ODDS := 0.16
const INLET_GRATE_ODDS := 0.4
const INLET_MANHOLE_ODDS := 0.45

## Draw distances (metres). A batch's range is measured to the centre of its bounds, which spans
## the chunk's roads (150-250 m), so these are the chunk's reach rather than one piece's.
const DRAW_COVER := 190.0
const DRAW_INLET := 190.0
const DRAW_CUT := 260.0
const DRAW_PLATE := 220.0
const DRAW_MARKER := 170.0
const DRAW_BOTTS := 150.0

## The stencil on the catch basin (original wording, no agency).
const PLAQUE_LINES := ["NO DUMPING", "DRAINS TO OCEAN"]
const PLAQUE_BLUE := Color(0.10, 0.30, 0.60)
const PLAQUE_WHITE := Color(0.90, 0.91, 0.88)

## RD_DEBUG=1 prints every cover, inlet, cut and plate a chunk lays, with an EYE over it.
static var _debug: bool = OS.get_environment("RD_DEBUG") == "1"
## The batches that lie flat on the carriageway (tilted to the relief like the road markings).
const FLAT_KEYS := ["rh_cover_round", "rh_cover_square", "rh_valve", "rh_cut", "rh_plate", "rh_marker", "rh_botts"]

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


# --- Placement --------------------------------------------------------------------------------

## The block's hardware: its kerbs' inlets and its two owned roads' covers, cuts, plates and
## markers. Called last from StreetDetail.build_block (FULL chunks).
static func build_block(chunk: CityChunk, rect: Rect2, edges: Array) -> void:
	if not enabled or chunk.capturing:
		return
	var plan: CityPlan = chunk.plan
	var rec: Array = []
	var taken: Array = []
	# Everything but the inlets (tilted by hand to the kerb) lies on the road: tilt it to the slope.
	for key: String in FLAT_KEYS:
		chunk._batch.tilt_keys[key] = true
	for e in edges:
		_inlets(chunk, plan, e, rect, rec, taken)
	for road in roads_of(plan, chunk.ix, chunk.iz, rect):
		_road(chunk, plan, road, rec, taken)
	var batch: MultiMeshBatch = chunk._batch
	for key: String in ["rh_cover_round", "rh_cover_square", "rh_valve", "rh_cut", "rh_plate", "rh_marker", "rh_botts", "rh_inlet", "rh_inlet_grate"]:
		batch.set_no_shadow(key)
	for pair: Array in [["rh_cover_round", DRAW_COVER], ["rh_cover_square", DRAW_COVER], ["rh_valve", DRAW_COVER * 0.7], ["rh_cut", DRAW_CUT],
			["rh_plate", DRAW_PLATE], ["rh_marker", DRAW_MARKER], ["rh_botts", DRAW_BOTTS], ["rh_inlet", DRAW_INLET], ["rh_inlet_grate", DRAW_INLET]]:
		batch.set_draw_distance(pair[0], pair[1])
	if _debug:
		for r: Dictionary in rec:
			if r.kind != "botts" and r.kind != "marker":
				var p: Vector2 = r.pos
				print("RD %s at %.1f,%.1f  EYE=%.1f,1.7,%.1f,180,-55" % [r.kind, p.x, p.y, p.x, p.y - 2.2])
	var prev: Array = chunk.get_meta("road_hardware", [])
	prev.append_array(rec)
	chunk.set_meta("road_hardware", prev)


## The two roads a block owns (its +X and +Z sides), as dictionaries: axis, index, centre,
## width, along range [a, b], along_z. Closed ones (CityPlan.road_open) are left out. Pure.
static func roads_of(plan: CityPlan, ix: int, iz: int, rect: Rect2) -> Array:
	var out: Array = []
	var rx := plan.road_pos(CityPlan.AXIS_X, ix + 1)
	if plan.road_open(CityPlan.AXIS_X, ix + 1, rect.get_center().y):
		out.append({"axis": CityPlan.AXIS_X, "index": ix + 1, "c": rx, "w": plan.road_width(CityPlan.AXIS_X, ix + 1),
			"a": rect.position.y, "b": rect.end.y, "along_z": true})
	var rz := plan.road_pos(CityPlan.AXIS_Z, iz + 1)
	if plan.road_open(CityPlan.AXIS_Z, iz + 1, rect.get_center().x):
		out.append({"axis": CityPlan.AXIS_Z, "index": iz + 1, "c": rz, "w": plan.road_width(CityPlan.AXIS_Z, iz + 1),
			"a": rect.position.x, "b": rect.end.x, "along_z": false})
	return out


## A point on a road at `along` (metres along it) and `off` (metres across from its centre line).
static func road_point(road: Dictionary, along: float, off: float) -> Vector2:
	if road.along_z:
		return Vector2(float(road.c) + off, along)
	return Vector2(along, float(road.c) + off)


## World direction along a road (+z or +x) and across it (+x or +z).
static func road_dirs(road: Dictionary) -> Array:
	return [Vector2(0.0, 1.0), Vector2(1.0, 0.0)] if road.along_z else [Vector2(1.0, 0.0), Vector2(0.0, 1.0)]


## Hash of seed + place to 0..1.
static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


static func _yaw_facing(v: Vector2) -> float:
	# Basis(UP, yaw) * +Z = (sin yaw, 0, cos yaw).
	return atan2(v.x, v.y)


static func _free(taken: Array, p: Vector2, r: float) -> bool:
	for t: Array in taken:
		if p.distance_to(t[0]) < r + float(t[1]):
			return false
	return true


## Whether a lane item at `p` (across offset `off`) may go on this road: off the rail's
## trackway and its trench.
static func _lane_ok(plan: CityPlan, road: Dictionary, p: Vector2, off: float) -> bool:
	var rail := LightRail.of(plan)
	if rail == null:
		return true
	if rail.street_rail(road.axis, road.index) and absf(off) < RAIL_KEEP:
		return false
	for r: Rect2 in rail.cuts_in(Rect2(p - Vector2(2.0, 2.0), Vector2(4.0, 4.0))):
		if r.grow(1.0).has_point(p):
			return false
	return true


static func _road(chunk: CityChunk, plan: CityPlan, road: Dictionary, rec: Array, taken: Array) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var w: float = road.w
	var a: float = road.a
	var b: float = road.b
	var length := b - a
	var avenue := w > plan.street_width + 1.0
	var lanes := 2 if avenue else 1
	var end := END_AVENUE if avenue else END_STREET
	if length < end * 2.0 + 4.0:
		return
	var key := [plan.seed, "road_hw", road.axis, road.index, int(floor(a))]
	var dirs := road_dirs(road)
	var along_dir: Vector2 = dirs[0]
	var yaw_along := _yaw_facing(along_dir)
	var y := CityChunk.ROAD_TOP
	var lane_c := func(side: float, n: int) -> float: return side * CityPlan.lane_center(w, lanes, n)
	var park := CityPlan.parking_offset(w)
	var span0 := a + end
	var span := length - end * 2.0

	# Utility cuts: sawcut trenches of patched asphalt, across a half-road or along a lane.
	var n_cuts := int(h01(key + ["cuts"]) * 2.6)
	for i in n_cuts:
		var k := key + ["cut", i]
		var side := -1.0 if h01(k + ["side"]) < 0.5 else 1.0
		var at := span0 + h01(k + ["at"]) * span
		var age := 0.35 + h01(k + ["age"]) * 0.75
		if h01(k + ["kind"]) < 0.55:
			# Across: kerb to the centre line (a service lateral), 0.6-1.0 m wide.
			var cw := 0.6 + h01(k + ["w"]) * 0.4
			var cl := w * 0.5 - 0.25
			var off := side * (cl * 0.5 + 0.05)
			var p := road_point(road, at, off)
			if not _lane_ok(plan, road, p, 0.0):
				continue
			_add_cut(batch, p, yaw_along, cl, cw, age, rec)
		else:
			var cl := 5.0 + h01(k + ["l"]) * 18.0
			cl = minf(cl, span)
			var cw := 0.6 + h01(k + ["w"]) * 0.35
			var at2 := span0 + cl * 0.5 + h01(k + ["at"]) * maxf(span - cl, 0.0)
			var off: float = lane_c.call(side, int(h01(k + ["lane"]) * lanes)) + (h01(k + ["o"]) - 0.5) * 1.2
			var p := road_point(road, at2, off)
			if not _lane_ok(plan, road, p, off):
				continue
			_add_cut(batch, p, yaw_along, cw, cl, age, rec)

	# Steel plates over an open trench: one to three along a lane, a fresh cut under and past them.
	if h01(key + ["plate"]) < PLATE_ODDS:
		var k := key + ["plates"]
		var side := -1.0 if h01(k + ["side"]) < 0.5 else 1.0
		var n := 1 + int(h01(k + ["n"]) * 2.99)
		var run := PLATE.y * n
		if run + 1.0 < span:
			var off: float = lane_c.call(side, int(h01(k + ["lane"]) * lanes))
			var at := span0 + run * 0.5 + 0.5 + h01(k + ["at"]) * (span - run - 1.0)
			var p0 := road_point(road, at, off)
			if _lane_ok(plan, road, p0, off) and _free(taken, p0, run * 0.5 + 0.6):
				taken.append([p0, run * 0.5 + 0.6])
				_add_cut(batch, p0, yaw_along, 1.0, run + 1.4, 0.3, rec)
				for j in n:
					var t := at + (float(j) - (n - 1) * 0.5) * PLATE.y
					var p := road_point(road, t, off + (h01(k + ["j", j]) - 0.5) * 0.12)
					var yaw := yaw_along + (h01(k + ["r", j]) - 0.5) * 0.06
					var custom := Color(h01(k + ["chalk", j]), 0.3 + h01(k + ["wear", j]) * 0.7, 0.5, 0.0)
					batch.add("rh_plate", plate_mesh(), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y)), Color.WHITE, custom)
					rec.append({"kind": "plate", "pos": p})

	# Sewer manholes: in a lane between the wheel tracks, or near the centre line.
	var n_mh := 1 + (1 if h01(key + ["mh2"]) < 0.45 else 0) + (1 if length > 150.0 else 0)
	for i in n_mh:
		var k := key + ["mh", i]
		var side := -1.0 if h01(k + ["side"]) < 0.5 else 1.0
		var off: float = side * 1.0 if h01(k + ["centre"]) < 0.3 else lane_c.call(side, int(h01(k + ["lane"]) * lanes))
		var at := span0 + (float(i) + h01(k + ["at"])) / float(n_mh) * span
		var p := road_point(road, at, off)
		if not _lane_ok(plan, road, p, off) or not _free(taken, p, COLLAR_R + 0.3):
			continue
		var pat: int = [Pattern.SUNBURST, Pattern.WAFFLE, Pattern.RINGS][int(h01(k + ["pat"]) * 2.99)]
		_add_cover(batch, p, k, pat, rec, taken)

	# Valve covers: water and gas, in ones and twos near the ends of the block.
	var n_valve := int(h01(key + ["valves"]) * 3.4)
	for i in n_valve:
		var k := key + ["valve", i]
		var side := -1.0 if h01(k + ["side"]) < 0.5 else 1.0
		var near_a := h01(k + ["end"]) < 0.5
		var at := a + end + h01(k + ["at"]) * 8.0
		if not near_a:
			at = b - end - h01(k + ["at"]) * 8.0
		var gas := h01(k + ["gas"]) < 0.4
		var off: float = side * (park + (h01(k + ["o"]) - 0.5) * 1.4) if gas else lane_c.call(side, int(h01(k + ["lane"]) * lanes)) + (h01(k + ["o"]) - 0.5) * 1.6
		var pair := 2 if h01(k + ["pair"]) < 0.4 else 1
		for j in pair:
			var p := road_point(road, at + float(j) * 0.62, off)
			if not _lane_ok(plan, road, p, off) or not _free(taken, p, VALVE_COLLAR_R + 0.1):
				continue
			taken.append([p, VALVE_COLLAR_R])
			var pk := k + [j]
			var custom := Color((float(Pattern.GAS if gas else Pattern.WATER) + 0.5) / 8.0, h01(pk + ["wear"]), _proud_code(pk), h01(pk + ["dab"]))
			batch.add("rh_valve", valve_mesh(), Transform3D(Basis(Vector3.UP, h01(pk + ["rot"]) * TAU), Vector3(p.x, y, p.y)), Color.WHITE, custom)
			rec.append({"kind": "valve", "pos": p})

	# Raised pavement markers on the centre line, and Botts' dots on an avenue's lane lines. The
	# phase is world-anchored, so a line runs on in step from block to block.
	var old := h01([plan.seed, "road_hw_old", road.axis, road.index]) < 0.35
	if avenue or h01([plan.seed, "road_hw_rpm", road.axis, road.index]) < RPM_STREET_ODDS:
		var t := ceilf((a + end) / RPM_SPACING) * RPM_SPACING
		while t < b - end:
			var p := road_point(road, t, 0.0)
			if _lane_ok(plan, road, p, 0.0) and h01(key + ["rpm", int(t)]) > MISSING * (2.0 if old else 1.0):
				batch.add("rh_marker", marker_mesh(), Transform3D(Basis(Vector3.UP, yaw_along), Vector3(p.x, y, p.y)), Color.WHITE, Color(0.125, h01(key + ["rw", int(t)]), 0.5, 0.0))
				rec.append({"kind": "marker", "pos": p})
			t += RPM_SPACING
	if avenue:
		var boundary := (w * 0.5 - CityPlan.PARKING_LANE - 0.2) / float(lanes)
		for side: float in [-1.0, 1.0]:
			var off := side * boundary
			# Traffic on this side runs -side along +z roads (TrafficManager._lane_offset), +side on
			# +x roads; the white face meets it, the red face shows a wrong-way driver.
			var motion: Vector2 = along_dir * (-side if road.along_z else side)
			var face_yaw := _yaw_facing(-motion)
			var t0 := floorf((a + end) / BOTTS_CYCLE) * BOTTS_CYCLE
			while t0 < b - end:
				for d in 5:
					var t := t0 + (BOTTS_MARKER_AT if d == 4 else float(d) * BOTTS_STEP)
					if t < a + end or t > b - end:
						continue
					var dk := key + ["botts", side, int(t * 10.0)]
					if h01(dk) < MISSING * (2.5 if old else 1.0):
						continue
					var jit := (h01(dk + ["j"]) - 0.5) * (0.05 if old else 0.02)
					var p := road_point(road, t, off + jit)
					if not _lane_ok(plan, road, p, off):
						continue
					if d == 4:
						batch.add("rh_marker", marker_mesh(), Transform3D(Basis(Vector3.UP, face_yaw), Vector3(p.x, y, p.y)), Color.WHITE, Color(0.625, h01(dk + ["w"]), 0.5, 0.0))
					else:
						batch.add("rh_botts", botts_mesh(), Transform3D(Basis(Vector3.UP, h01(dk + ["r"]) * TAU), Vector3(p.x, y, p.y)), Color.WHITE, Color(0.125 if old and h01(dk + ["y"]) < 0.05 else 0.625, h01(dk + ["w"]), 0.5, 0.0))
					rec.append({"kind": "botts" if d < 4 else "marker", "pos": p})
				t0 += BOTTS_CYCLE


## A manhole cover with its frame and collar at `p` (round or square collar by hash).
static func _add_cover(batch: MultiMeshBatch, p: Vector2, k: Array, pat: int, rec: Array, taken: Array) -> void:
	var square := h01(k + ["sq"]) < 0.45
	taken.append([p, (COLLAR_SQ * 1.41 if square else COLLAR_R) + 0.1])
	var custom := Color((float(pat) + 0.5) / 8.0, h01(k + ["wear"]), _proud_code(k), h01(k + ["tone"]))
	var yaw := h01(k + ["rot"]) * TAU
	batch.add("rh_cover_square" if square else "rh_cover_round", cover_mesh(square), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, CityChunk.ROAD_TOP, p.y)), Color.WHITE, custom)
	rec.append({"kind": "cover", "pos": p, "pattern": pat, "square": square})


## INSTANCE_CUSTOM.b: the cover's height against the road, 0.5 flush (shader: (b - 0.5) * 0.08 m).
static func _proud_code(k: Array) -> float:
	var v := lerpf(PROUD.x, PROUD.y, h01(k + ["proud"]))
	return 0.5 + v / 0.08


static func _add_cut(batch: MultiMeshBatch, p: Vector2, yaw: float, size_x: float, size_z: float, age: float, rec: Array) -> void:
	# A unit quad scaled in its own frame; the shader draws the sawcut seal from the size, which
	# rides in the custom data (sizes / 32 m).
	var basis := Basis(Vector3.UP, yaw).scaled_local(Vector3(size_x, 1.0, size_z))
	batch.add("rh_cut", cut_mesh(), Transform3D(basis, Vector3(p.x, CityChunk.ROAD_TOP, p.y)), Color.WHITE, Color(age, size_x / 32.0, size_z / 32.0, h01([p.x, p.y])))
	rec.append({"kind": "cut", "pos": p, "size": Vector2(size_x, size_z)})


## Kerb inlets on one kerb edge: one near each corner, upstream of the crosswalk.
static func _inlets(chunk: CityChunk, plan: CityPlan, e: Array, rect: Rect2, rec: Array, taken: Array) -> void:
	var a: Vector2 = e[0]
	var b: Vector2 = e[1]
	var inward: Vector2 = e[2]
	var length := a.distance_to(b)
	if length < INLET_ALONG * 2.0 + INLET_APRON * 2.0:
		return
	var dir := (b - a) / length
	# Which road this kerb faces, and whether it is open along here.
	var axis := CityPlan.AXIS_X if absf(inward.x) > 0.5 else CityPlan.AXIS_Z
	var index := (chunk.ix if inward.x > 0.0 else chunk.ix + 1) if axis == CityPlan.AXIS_X else (chunk.iz if inward.y > 0.0 else chunk.iz + 1)
	var mid := (a + b) * 0.5
	if not plan.road_open(axis, index, mid.y if axis == CityPlan.AXIS_X else mid.x):
		return
	var width := plan.road_width(axis, index)
	var batch: MultiMeshBatch = chunk._batch
	var face_yaw := _yaw_facing(-inward)
	for k in 2:
		var along := INLET_ALONG if k == 0 else length - INLET_ALONG
		var kp := a + dir * along
		var hk := [plan.seed, "inlet", snappedf(kp.x, 0.1), snappedf(kp.y, 0.1)]
		var grate := h01(hk + ["grate"]) < INLET_GRATE_ODDS
		var basis := StreetDetail._ground_tilt(chunk, Basis(Vector3.UP, face_yaw), kp.x, kp.y, 1.6)
		var custom := Color((float(Pattern.DIAMOND) + 0.5) / 8.0, h01(hk + ["wear"]), 0.5, h01(hk + ["stain"]))
		batch.add("rh_inlet_grate" if grate else "rh_inlet", inlet_mesh(grate), Transform3D(basis, Vector3(kp.x, CityChunk.ROAD_TOP, kp.y)), Color.WHITE, custom)
		taken.append([kp - inward * INLET_DEPTH * 0.5, INLET_APRON])
		rec.append({"kind": "inlet", "pos": kp, "grate": grate, "inward": inward})
		# The storm drain's own manhole out in the parking lane in front of it, now and then.
		if h01(hk + ["mh"]) < INLET_MANHOLE_ODDS:
			var mp := kp - inward * (CityPlan.PARKING_LANE * 0.5 + 0.3) + dir * (1.0 if k == 0 else -1.0) * (0.6 + h01(hk + ["mo"]))
			if _free(taken, mp, COLLAR_R + 0.2) and _lane_ok(plan, {"axis": axis, "index": index}, mp, width * 0.5):
				_add_cover(batch, mp, hk + ["cover"], Pattern.DIAMOND, rec, taken)


# --- Meshes -----------------------------------------------------------------------------------

## The shared material (one for every kind).
static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/road_hardware.gdshader")
	m.set_shader_parameter("asphalt_tex", PropFactory.texture("asphalt", "Color"))
	m.set_shader_parameter("asphalt_nrm", PropFactory.texture("asphalt", "NormalGL"))
	m.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	_material = m
	return m


## A small mesh builder: flat-shaded triangles turned to face the way asked (LandmarkGeo's rule),
## kind in the colour's alpha, UV the piece's own plan metres, UV2 the proud / sunk weights.
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, d: Vector3, want: Vector3, kind: int, col: Color,
			wa := Vector2.ZERO, wb := Vector2.ZERO, wd := Vector2.ZERO, ua := Vector2(INF, 0.0), ub := Vector2.ZERO, ud := Vector2.ZERO) -> void:
		var nn := (d - a).cross(b - a)
		if nn.length_squared() < 1e-14:
			return
		var flip := nn.dot(want) < 0.0
		if flip:
			var t := b
			b = d
			d = t
			var tw := wb
			wb = wd
			wd = tw
			var tu := ub
			ub = ud
			ud = tu
			nn = -nn
		nn = nn.normalized()
		var colk := Color(col.r, col.g, col.b, (float(kind) + 0.5) / RoadHardware.KIND_SCALE)
		var pts := [a, b, d]
		var ws := [wa, wb, wd]
		var us := [ua, ub, ud]
		for i in 3:
			var p: Vector3 = pts[i]
			v.append(p)
			n.append(nn)
			c.append(colk)
			# UV defaults to the plan position (x, z).
			uv.append(Vector2(p.x, p.z) if ua.x == INF else us[i])
			uv2.append(ws[i])

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, want: Vector3, kind: int, col: Color,
			wa := Vector2.ZERO, wb := Vector2.ZERO, wd := Vector2.ZERO, we := Vector2.ZERO) -> void:
		tri(a, b, d, want, kind, col, wa, wb, wd)
		tri(a, d, e, want, kind, col, wa, wd, we)

	## A box from `lo` to `hi`, every face but the bottom.
	func box(lo: Vector3, hi: Vector3, kind: int, col: Color, w := Vector2.ZERO) -> void:
		var x0 := lo.x
		var x1 := hi.x
		var y0 := lo.y
		var y1 := hi.y
		var z0 := lo.z
		var z1 := hi.z
		quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, kind, col, w, w, w, w)
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, kind, col, w, w, w, w)
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.FORWARD, kind, col, w, w, w, w)
		quad(Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3.RIGHT, kind, col, w, w, w, w)
		quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT, kind, col, w, w, w, w)

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		if v.is_empty():
			return m
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, RoadHardware.material())
		return m


static func _ring(g: Geo, segs: int, r0: Callable, r1: Callable, y0: float, y1: float, kind: int, col: Color, w0: Vector2, w1: Vector2, want := Vector3.UP) -> void:
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(t0), 0.0, sin(t0))
		var d1 := Vector3(cos(t1), 0.0, sin(t1))
		var a: Vector3 = d0 * float(r0.call(t0)) + Vector3(0.0, y0, 0.0)
		var b: Vector3 = d1 * float(r0.call(t1)) + Vector3(0.0, y0, 0.0)
		var c: Vector3 = d1 * float(r1.call(t1)) + Vector3(0.0, y1, 0.0)
		var d: Vector3 = d0 * float(r1.call(t0)) + Vector3(0.0, y1, 0.0)
		var wnt := want
		if want == Vector3.ZERO:
			# A wall: face toward the centre if r1 == r0 and y1 > y0 means an inner lip.
			wnt = -(d0 + d1).normalized()
		elif want == Vector3.DOWN:
			wnt = (d0 + d1).normalized()
		g.quad(a, b, c, d, wnt, kind, col, w0, w0, w1, w1)


static func _const(r: float) -> Callable:
	return func(_t: float) -> float: return r


static func _square(half: float) -> Callable:
	return func(t: float) -> float: return half / maxf(absf(cos(t)), absf(sin(t)))


## A round cover: lid, the dark gap round it, the frame with its bevel, the lip a sunk cover
## leaves, the collar of patched asphalt (round or square) and its sealant band. Lid and frame
## carry UV2.x 1 (moved up by a proud cover), the collar's inner edge UV2.y 1 (raised round a
## sunk one), so one mesh serves every height.
static func _cover(segs: int, lid_r: float, frame_r: float, collar: Callable, seal: float, square: bool, key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var g := Geo.new()
	var iron := Color(0.2, 0.2, 0.2)
	var top := 0.005
	var lid := Vector2(1.0, 0.0)
	var none := Vector2.ZERO
	var lip := Vector2(1.0, 1.0)
	# Lid: a centre fan and rings (the pattern is drawn by the shader in UV).
	var rings := [0.0, lid_r * 0.33, lid_r * 0.66, lid_r]
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		for r in 3:
			var ra: float = rings[r]
			var rb: float = rings[r + 1]
			var a := Vector3(cos(t0) * ra, top, sin(t0) * ra)
			var b := Vector3(cos(t1) * ra, top, sin(t1) * ra)
			var c := Vector3(cos(t1) * rb, top, sin(t1) * rb)
			var d := Vector3(cos(t0) * rb, top, sin(t0) * rb)
			if r == 0:
				g.tri(a, c, d, Vector3.UP, K_IRON, iron, lid, lid, lid)
			else:
				g.quad(a, b, c, d, Vector3.UP, K_IRON, iron, lid, lid, lid, lid)
	var gap := lid_r + 0.008
	# The gap: lid edge down, a dark floor, the frame's inner wall up.
	_ring(g, segs, _const(lid_r), _const(lid_r), top, top - 0.012, K_VOID, iron, lid, lid, Vector3.DOWN)
	_ring(g, segs, _const(lid_r), _const(gap), top - 0.012, top - 0.012, K_VOID, iron, lid, lid)
	_ring(g, segs, _const(gap), _const(gap), top - 0.012, top, K_FRAME, iron, lid, lid, Vector3.ZERO)
	# Frame top, then its bevel down to the collar.
	_ring(g, segs, _const(gap), _const(frame_r), top, top, K_FRAME, iron, lid, lid)
	_ring(g, segs, _const(frame_r), _const(frame_r + 0.012), top, 0.0025, K_FRAME, iron, lid, lid)
	# The lip of asphalt standing over a sunk cover's frame (zero height on a proud one).
	_ring(g, segs, _const(frame_r + 0.012), _const(frame_r + 0.012), 0.002, 0.0025, K_ASPHALT, iron, lid, lip, Vector3.ZERO)
	# Collar of patched asphalt out to the sawcut, then the sealant band.
	var cw := (frame_r + 0.012)
	var cr := func(t: float) -> float: return float(collar.call(t)) - seal
	_ring(g, segs, _const(cw), cr, 0.0025, 0.0025, K_ASPHALT, iron, lip, none)
	_ring(g, segs, cr, collar, 0.0025, 0.0025, K_SEAL, iron, none, none)
	# Its outer edge: a few millimetres down to the road (the sawcut's sealant spills over it).
	_ring(g, segs, collar, func(t: float) -> float: return float(collar.call(t)) + 0.015, 0.0025, -0.003, K_SEAL, iron, none, none)
	var mesh := g.commit()
	_meshes[key] = mesh
	return mesh


static func cover_mesh(square: bool) -> Mesh:
	return _cover(36, LID_R, FRAME_R, _square(COLLAR_SQ) if square else _const(COLLAR_R), SEAL_W, square, "cover_sq" if square else "cover_rd")


static func valve_mesh() -> Mesh:
	return _cover(16, VALVE_R, VALVE_FRAME_R, _const(VALVE_COLLAR_R), 0.025, false, "valve")


## A utility cut: a unit quad (scaled per instance); the shader draws the sawcut from its size.
static func cut_mesh() -> Mesh:
	if _meshes.has("cut"):
		return _meshes.cut
	var g := Geo.new()
	var col := Color(0.2, 0.2, 0.2)
	var y := 0.0022
	var a := Vector3(-0.5, y, -0.5)
	var b := Vector3(0.5, y, -0.5)
	var c := Vector3(0.5, y, 0.5)
	var d := Vector3(-0.5, y, 0.5)
	g.tri(a, b, c, Vector3.UP, K_CUT, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0))
	g.tri(a, c, d, Vector3.UP, K_CUT, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))
	_meshes.cut = g.commit()
	return _meshes.cut


## A steel road plate on the road, chamfered, with the cold-patch ramp all round it.
static func plate_mesh() -> Mesh:
	if _meshes.has("plate"):
		return _meshes.plate
	var g := Geo.new()
	var steel := Color(0.3, 0.3, 0.3)
	var hx := PLATE.x * 0.5
	var hz := PLATE.y * 0.5
	var t := PLATE_T + 0.002
	var ch := 0.012
	var top := [Vector3(-hx + ch, t, -hz + ch), Vector3(hx - ch, t, -hz + ch), Vector3(hx - ch, t, hz - ch), Vector3(-hx + ch, t, hz - ch)]
	var edge := [Vector3(-hx, t - ch * 0.6, -hz), Vector3(hx, t - ch * 0.6, -hz), Vector3(hx, t - ch * 0.6, hz), Vector3(-hx, t - ch * 0.6, hz)]
	var foot := [Vector3(-hx - PLATE_RAMP, 0.002, -hz - PLATE_RAMP), Vector3(hx + PLATE_RAMP, 0.002, -hz - PLATE_RAMP), Vector3(hx + PLATE_RAMP, 0.002, hz + PLATE_RAMP), Vector3(-hx - PLATE_RAMP, 0.002, hz + PLATE_RAMP)]
	g.quad(top[0], top[1], top[2], top[3], Vector3.UP, K_PLATE, steel)
	for i in 4:
		var j := (i + 1) % 4
		var mid: Vector3 = (top[i] + top[j]) * 0.5
		var out := Vector3(mid.x, 0.0, mid.z).normalized()
		if absf(mid.x) < 0.01:
			out = Vector3(0.0, 0.0, signf(mid.z))
		else:
			out = Vector3(signf(mid.x), 0.0, 0.0) if absf(mid.z) < 0.01 else out
		g.quad(top[i], top[j], edge[j], edge[i], (out + Vector3.UP).normalized(), K_PLATE, steel)
		# The cold patch: from the plate's edge down to the road.
		g.quad(edge[i], edge[j], foot[j], foot[i], (out * 0.2 + Vector3.UP).normalized(), K_ASPHALT, Color(0.42, 0.42, 0.42))
	_meshes.plate = g.commit()
	return _meshes.plate


## A raised pavement marker: a 10 cm ceramic square with two sloped retroreflective faces, the
## white (or yellow) one facing local +Z, its back (red, or yellow again) -Z; UV.x says which.
static func marker_mesh() -> Mesh:
	if _meshes.has("marker"):
		return _meshes.marker
	var g := Geo.new()
	var col := Color(0.8, 0.8, 0.8)
	var b := 0.05
	var tx := 0.04
	var tz := 0.022
	var h := 0.018
	var y0 := 0.001
	var lo := [Vector3(-b, y0, -b), Vector3(b, y0, -b), Vector3(b, y0, b), Vector3(-b, y0, b)]
	var hi := [Vector3(-tx, h, -tz), Vector3(tx, h, -tz), Vector3(tx, h, tz), Vector3(-tx, h, tz)]
	g.quad(hi[0], hi[1], hi[2], hi[3], Vector3.UP, K_CERAMIC, col)
	# Sides (ceramic).
	g.quad(lo[1], lo[2], hi[2], hi[1], Vector3(1.0, 0.6, 0.0), K_CERAMIC, col)
	g.quad(lo[3], lo[0], hi[0], hi[3], Vector3(-1.0, 0.6, 0.0), K_CERAMIC, col)
	# Front (+Z) and back (-Z) reflectors.
	g.tri(lo[2], lo[3], hi[3], Vector3(0.0, 0.7, 1.0), K_REFLECT, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(1.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.0))
	g.tri(lo[2], hi[3], hi[2], Vector3(0.0, 0.7, 1.0), K_REFLECT, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(1.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.0))
	g.tri(lo[0], lo[1], hi[1], Vector3(0.0, 0.7, -1.0), K_REFLECT, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(-1.0, 0.0), Vector2(-1.0, 0.0), Vector2(-1.0, 0.0))
	g.tri(lo[0], hi[1], hi[0], Vector3(0.0, 0.7, -1.0), K_REFLECT, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(-1.0, 0.0), Vector2(-1.0, 0.0), Vector2(-1.0, 0.0))
	_meshes.marker = g.commit()
	return _meshes.marker


## A Botts' dot: a 10 cm ceramic dome, 1.7 cm high, with smooth normals.
static func botts_mesh() -> Mesh:
	if _meshes.has("botts"):
		return _meshes.botts
	var g := Geo.new()
	var col := Color(0.85, 0.85, 0.82)
	var segs := 10
	var r := 0.05
	var h := 0.017
	var rings := [[1.0, 0.001], [0.82, 0.009], [0.5, 0.0145], [0.0, h]]
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		for k in 3:
			var ra: float = rings[k][0] * r
			var rb: float = rings[k + 1][0] * r
			var ya: float = rings[k][1]
			var yb: float = rings[k + 1][1]
			var a := Vector3(cos(t0) * ra, ya, sin(t0) * ra)
			var b := Vector3(cos(t1) * ra, ya, sin(t1) * ra)
			var c := Vector3(cos(t1) * rb, yb, sin(t1) * rb)
			var d := Vector3(cos(t0) * rb, yb, sin(t0) * rb)
			var out := Vector3(cos((t0 + t1) * 0.5), 1.2 + float(k), sin((t0 + t1) * 0.5)).normalized()
			if k == 2:
				g.tri(a, b, c, out, K_CERAMIC, col)
			else:
				g.quad(a, b, c, d, out, K_CERAMIC, col)
	var m := g.commit()
	_meshes.botts = m
	return m


## A kerb inlet in its frame: x along the kerb, +z out into the road, y 0 the road top, the kerb
## face on z 0 (the pavement behind it at y KERB_H). The concrete gutter apron (raised a few
## millimetres at its rim and dipping to the slot, so it shades as the depression it is), the dark
## slot under a steel angle, concrete facing round it, the catch basin's lid in the pavement with
## its access cover; with `grate`, a bar grate in the apron in front of the slot.
static func inlet_mesh(grate: bool) -> Mesh:
	var key := "inlet_g" if grate else "inlet"
	if _meshes.has(key):
		return _meshes[key]
	var g := Geo.new()
	var conc := Color(0.62, 0.61, 0.58)
	var steel := Color(0.28, 0.27, 0.26)
	var dark := Color(0.02, 0.02, 0.02)
	var hl := INLET_APRON
	var d := INLET_DEPTH
	var hs := INLET_SLOT * 0.5
	# Apron as a grid; the height falls from the rim to the kerb (and to nothing at the ends).
	var gx := 12
	var gz := 4
	var gr := Rect2(-0.45, 0.16, 0.9, 0.58)
	var ay := func(x: float, z: float) -> float:
		var end := clampf((hl - absf(x)) / 0.5, 0.0, 1.0)
		return 0.002 + 0.008 * lerpf(1.0, z / d, end)
	for i in gx:
		for j in gz:
			var x0 := -hl + 2.0 * hl * float(i) / gx
			var x1 := -hl + 2.0 * hl * float(i + 1) / gx
			var z0 := d * float(j) / gz
			var z1 := d * float(j + 1) / gz
			if grate and Rect2(x0, z0, x1 - x0, z1 - z0).intersects(gr.grow(-0.001)):
				continue
			g.quad(Vector3(x0, ay.call(x0, z0), z0), Vector3(x1, ay.call(x1, z0), z0), Vector3(x1, ay.call(x1, z1), z1), Vector3(x0, ay.call(x0, z1), z1), Vector3.UP, K_CONCRETE, conc)
	# The apron's outer edge down to the road.
	for i in gx:
		var x0 := -hl + 2.0 * hl * float(i) / gx
		var x1 := -hl + 2.0 * hl * float(i + 1) / gx
		g.quad(Vector3(x0, ay.call(x0, d), d), Vector3(x1, ay.call(x1, d), d), Vector3(x1, -0.004, d + 0.01), Vector3(x0, -0.004, d + 0.01), Vector3(0.0, 0.3, 1.0), K_CONCRETE, conc)
	for sx: float in [-1.0, 1.0]:
		g.quad(Vector3(sx * hl, ay.call(sx * hl, 0.0), 0.0), Vector3(sx * hl, ay.call(sx * hl, d), d), Vector3(sx * (hl + 0.01), -0.004, d), Vector3(sx * (hl + 0.01), -0.004, 0.0), Vector3(sx, 0.3, 0.0), K_CONCRETE, conc)
	if grate:
		# The grate's well round its rim, then the bars over the dark.
		var x0 := gr.position.x
		var x1 := gr.end.x
		var z0 := gr.position.y
		var z1 := gr.end.y
		var cells := [x0 - 0.33, x1 + 0.33]
		# Fill the apron round the cut-out rect's cells that the grid skipped.
		var cx0 := -hl + 2.0 * hl * floorf((x0 + hl) / (2.0 * hl / gx)) / gx
		var cx1 := -hl + 2.0 * hl * ceilf((x1 + hl) / (2.0 * hl / gx)) / gx
		var cz0 := d * floorf(z0 / (d / gz)) / gz
		var cz1 := d * ceilf(z1 / (d / gz)) / gz
		var ring := [[cx0, cz0, cx1, z0], [cx0, z1, cx1, cz1], [cx0, z0, x0, z1], [x1, z0, cx1, z1]]
		for rr: Array in ring:
			var a0: float = rr[0]
			var b0: float = rr[1]
			var a1: float = rr[2]
			var b1: float = rr[3]
			if a1 - a0 < 0.001 or b1 - b0 < 0.001:
				continue
			g.quad(Vector3(a0, ay.call(a0, b0), b0), Vector3(a1, ay.call(a1, b0), b0), Vector3(a1, ay.call(a1, b1), b1), Vector3(a0, ay.call(a0, b1), b1), Vector3.UP, K_CONCRETE, conc)
		cells.clear()
		var gy := ay.call(0.0, (z0 + z1) * 0.5) as float
		g.quad(Vector3(x0, gy - 0.004, z0), Vector3(x1, gy - 0.004, z0), Vector3(x1, gy - 0.004, z1), Vector3(x0, gy - 0.004, z1), Vector3.UP, K_VOID, dark)
		# Frame (angle iron round the opening) and the bars across the flow (along z).
		g.box(Vector3(x0 - 0.03, gy - 0.004, z0 - 0.03), Vector3(x1 + 0.03, gy + 0.002, z0), K_STEEL, steel)
		g.box(Vector3(x0 - 0.03, gy - 0.004, z1), Vector3(x1 + 0.03, gy + 0.002, z1 + 0.03), K_STEEL, steel)
		g.box(Vector3(x0 - 0.03, gy - 0.004, z0), Vector3(x0, gy + 0.002, z1), K_STEEL, steel)
		g.box(Vector3(x1, gy - 0.004, z0), Vector3(x1 + 0.03, gy + 0.002, z1), K_STEEL, steel)
		var bars := 13
		for b in bars:
			var bx := x0 + (x1 - x0) * (float(b) + 0.5) / float(bars)
			g.box(Vector3(bx - 0.011, gy - 0.004, z0), Vector3(bx + 0.011, gy + 0.001, z1), K_STEEL, steel)
		for cz: float in [z0 + (z1 - z0) * 0.33, z0 + (z1 - z0) * 0.66]:
			g.box(Vector3(x0, gy - 0.004, cz - 0.008), Vector3(x1, gy - 0.0005, cz + 0.008), K_STEEL, steel)
	# The slot in the kerb face. It is drawn on the face, in front of it: the kerb paint
	# (StreetDetail) stands 5 mm proud of the kerb and would cover anything set back into it, so the
	# throat's depth is the shader's (K_VOID darkens toward the head). Concrete facing either side,
	# a sill under it and the steel angle over it.
	var fz := 0.016
	var sy0 := 0.012
	var sy1 := 0.106
	g.quad(Vector3(-hs, sy0, fz + 0.001), Vector3(hs, sy0, fz + 0.001), Vector3(hs, sy1, fz + 0.001), Vector3(-hs, sy1, fz + 0.001), Vector3.BACK, K_VOID, dark)
	g.box(Vector3(-hs - 0.02, 0.0, -0.01), Vector3(hs + 0.02, sy0, fz + 0.02), K_CONCRETE, conc)
	g.box(Vector3(-hs - 0.05, sy1, -0.01), Vector3(hs + 0.05, KERB_H + 0.0025, fz + 0.006), K_STEEL, steel)
	g.quad(Vector3(-hs - 0.05, KERB_H + 0.0025, -0.06), Vector3(hs + 0.05, KERB_H + 0.0025, -0.06), Vector3(hs + 0.05, KERB_H + 0.0025, -0.01), Vector3(-hs - 0.05, KERB_H + 0.0025, -0.01), Vector3.UP, K_STEEL, steel)
	for sx: float in [-1.0, 1.0]:
		var xa := sx * hs
		var xb := sx * hl
		g.quad(Vector3(xa, 0.0, fz), Vector3(xb, 0.0, fz), Vector3(xb, KERB_H + 0.002, fz), Vector3(xa, KERB_H + 0.002, fz), Vector3.BACK, K_CONCRETE, conc)
		g.quad(Vector3(xb, 0.0, fz), Vector3(xb, KERB_H + 0.002, fz), Vector3(xb, KERB_H + 0.002, -0.004), Vector3(xb, 0.0, -0.004), Vector3(sx, 0.0, 0.0), K_CONCRETE, conc)
		# The kerb's top over the facing.
		g.quad(Vector3(xa, KERB_H + 0.002, fz), Vector3(xb, KERB_H + 0.002, fz), Vector3(xb, KERB_H + 0.002, -0.06), Vector3(xa, KERB_H + 0.002, -0.06), Vector3.UP, K_CONCRETE, conc)
	# The catch basin's lid in the pavement behind: a concrete slab with an access cover.
	var py := KERB_H + 0.003
	var bz := -1.05
	g.quad(Vector3(-hl + 0.2, py, bz), Vector3(hl - 0.2, py, bz), Vector3(hl - 0.2, py, -0.06), Vector3(-hl + 0.2, py, -0.06), Vector3.UP, K_CONCRETE, conc)
	for sx: float in [-1.0, 1.0]:
		g.quad(Vector3(sx * (hl - 0.2), py, bz), Vector3(sx * (hl - 0.2), py, 0.0), Vector3(sx * (hl - 0.19), KERB_H - 0.003, 0.0), Vector3(sx * (hl - 0.19), KERB_H - 0.003, bz), Vector3(sx, 0.5, 0.0), K_CONCRETE, conc)
	g.quad(Vector3(-hl + 0.2, py, bz), Vector3(hl - 0.2, py, bz), Vector3(hl - 0.19, KERB_H - 0.003, bz - 0.01), Vector3(-hl + 0.19, KERB_H - 0.003, bz - 0.01), Vector3(0.0, 0.5, -1.0), K_CONCRETE, conc)
	# The access cover (a small diamond-pattern iron lid in its frame), centred at x -0.95.
	var acx := -hl + 0.75
	var acz := -0.6
	var ar := 0.3
	var segs := 20
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		var c0 := Vector3(acx, py + 0.002, acz)
		var a := c0 + Vector3(cos(t0), 0.0, sin(t0)) * ar
		var b := c0 + Vector3(cos(t1), 0.0, sin(t1)) * ar
		var a2 := c0 + Vector3(cos(t0), 0.0, sin(t0)) * (ar + 0.05)
		var b2 := c0 + Vector3(cos(t1), 0.0, sin(t1)) * (ar + 0.05)
		g.tri(c0, a, b, Vector3.UP, K_IRON, steel, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(c0.x - acx, c0.z - acz) * (LID_R / ar), Vector2(a.x - acx, a.z - acz) * (LID_R / ar), Vector2(b.x - acx, b.z - acz) * (LID_R / ar))
		g.quad(a, b, b2, a2, Vector3.UP, K_FRAME, steel)
	_plaque(g)
	var mesh := g.commit()
	_meshes[key] = mesh
	return mesh


## The stencil on the catch basin's lid, read from the pavement: a blue panel and the two lines,
## in the inlet's frame (part of the inlet's mesh).
static func _plaque(g: Geo) -> void:
	var py := KERB_H + 0.0045
	var x0 := 0.05
	var x1 := 1.55
	var z0 := -0.98
	var z1 := -0.16
	g.quad(Vector3(x0, py, z0), Vector3(x1, py, z0), Vector3(x1, py, z1), Vector3(x0, py, z1), Vector3.UP, K_PAINT, PLAQUE_BLUE)
	var cx := (x0 + x1) * 0.5
	var lines := [[PLAQUE_LINES[0], 0.13, -0.33], [PLAQUE_LINES[1], 0.1, -0.6]]
	for ln: Array in lines:
		var geo: Array = FreewayKit.text_geo(ln[0], ln[1])
		var verts: PackedVector3Array = geo[0]
		var idx: PackedInt32Array = geo[1]
		var span: float = geo[2]
		var s := minf(1.0, (x1 - x0 - 0.16) / maxf(span, 0.01))
		for t in range(0, idx.size() - 2, 3):
			var p := []
			for q in 3:
				var vv: Vector3 = verts[idx[t + q]]
				# Letter x runs along -X for a reader on the pavement facing the road (+Z); its up
				# is toward the road.
				p.append(Vector3(cx - vv.x * s, py + 0.0006, float(ln[2]) + vv.y * s))
			g.tri(p[0], p[1], p[2], Vector3.UP, K_PAINT, PLAQUE_WHITE)
	# A wave under the words: a strip of short quads along a sine.
	var steps := 18
	for i in steps:
		var u0 := lerpf(x0 + 0.25, x1 - 0.25, float(i) / steps)
		var u1 := lerpf(x0 + 0.25, x1 - 0.25, float(i + 1) / steps)
		var w0 := -0.8 + sin(float(i) / steps * TAU * 2.0) * 0.035
		var w1 := -0.8 + sin(float(i + 1) / steps * TAU * 2.0) * 0.035
		g.quad(Vector3(u0, py + 0.0006, w0 - 0.012), Vector3(u1, py + 0.0006, w1 - 0.012), Vector3(u1, py + 0.0006, w1 + 0.012), Vector3(u0, py + 0.0006, w0 + 0.012), Vector3.UP, K_PAINT, PLAQUE_WHITE)
