class_name Micromobility
extends RefCounted
## The 2026 Los Angeles street's micromobility, laid out: shared e-scooters
## of two invented operators (SKOOTA, teal; KWIKR, amber) dropped in clusters at the pavement
## edge - most on their kickstands, some knocked over, one in the gutter, one leaning on a street
## tree; BASIN BIKE share stations (a solar kiosk with its screen and map panel, a row of docks
## with bikes in some of them); inverted-U bike racks at the corners, a bike locked to some; and
## bike lanes on some streets - green-painted lanes with bike stencils and arrows and a hatched
## buffer, flexible delineator posts in the buffer on the protected ones - where the parking lane
## was (the parked cars keep out of it: blocks_parking()).
##
## Placement is pure (plan_block(), lane_on(): hashes of the seed and the block, face, road and
## crossing, never a chunk or block rng), so tests and the riders (Cyclists) ask the same thing
## the chunk builds. FULL chunks only; LOD chunks and the far city get nothing. Everything is
## drawn through the chunk's batches: one draw per kind a chunk (MicroMesh's meshes on
## shaders/micromobility.gdshader, the lanes on shaders/bike_lane.gdshader). A scooter or a docked
## or racked bike is an EncampmentItem: a round, a car or a blast knocks it over as a real body,
## and it stays gone (WorldState). Static: call with the chunk.

enum Item { SCOOTER, STATION, RACK }
enum Pose { STAND, FALLEN, GUTTER, TREE }

# --- Tunables --------------------------------------------------------------------------------

## Chance per block face of a cluster of scooters, a share station, and per corner of a rack,
## by district (DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN).
const SCOOTER_ODDS := [0.55, 0.38, 0.06, 0.05, 0.6, 0.5]
const STATION_ODDS := [0.16, 0.08, 0.0, 0.0, 0.14, 0.12]
const RACK_ODDS := [0.25, 0.2, 0.05, 0.03, 0.4, 0.3]
## A second cluster on a face that has one.
const SECOND_CLUSTER := 0.35
## Scooters in a cluster (min, max), and the shares that lie knocked over, sit in the gutter,
## or lean on a tree.
const CLUSTER_SIZE := Vector2i(2, 7)
const FALLEN_SHARE := 0.16
const GUTTER_SHARE := 0.25
const TREE_SHARE := 0.3
## Docks in a station (min, max) and the share holding a bike.
const DOCKS := Vector2i(6, 11)
const DOCK_PITCH := 0.85
const DOCK_FULL := Vector2(0.35, 0.85)
## Share of racks with a bike locked to them.
const RACK_BIKE := 0.5
## Most knockable pieces (scooters and bikes) in one chunk.
const MAX_ITEMS := 34
## Metres from the kerb: a scooter's middle, a dock post, a rack.
const SCOOTER_IN := 0.95
const DOCK_IN := 0.42
const RACK_IN := 0.75
## Clearance from what already stands on the pavement.
const CLEAR := 0.45
## Draw and shadow distances (m).
const DRAW := 140.0
const SHADOW := 40.0
const LANE_DRAW := 260.0

## Bike lanes: the share of avenues and of streets that have one (a hash per road), the share of
## those painted green the whole way (else green dashes only in the conflict zones before each
## crossing), and the share that are protected (delineators in the buffer).
const LANE_AVENUE := 0.32
const LANE_STREET := 0.1
const GREEN_SHARE := 0.6
const PROTECTED_SHARE := 0.35
## Real downtown streets with lanes whatever the roll (public names; CityPlan.road_name()).
const LANE_STREETS := ["7th St", "Spring St", "Main St", "Figueroa St", "Los Angeles St", "1st St"]
## The lane in the old parking lane (metres from the kerb): the gutter left bare, the green lane,
## its line, the hatched buffer, its line. A rider's line.
const LANE_FROM := 0.3
const LANE_TO := 1.85
const BUFFER_TO := 2.48
const RIDE_LINE := 1.05
## Paint pieces' length (the batch lifts each to the relief, so long pieces would float).
const PIECE := 6.0
## The paint stops this far short of a crossing's road edge (the crosswalk and stop line).
const JUNCTION_GAP := 4.0
## A bike stencil and arrow every this many metres (and the first piece after a crossing).
const STENCIL_EVERY := 48.0
## Delineators every this many metres in a protected lane's buffer.
const POST_EVERY := 6.0

## Batch keys.
const K_SCOOTER := ["mm_scooter_a", "mm_scooter_b"]
const K_SHARE := "mm_share"
const K_DOCK := "mm_dock"
const K_KIOSK := "mm_kiosk"
const K_RACK := "mm_rack"
const K_LOCKED := ["mm_locked_road", "mm_locked_cruiser"]
const K_POST := "mm_post"
const K_LANE := "bike_lane"

## Off: none of it (the A/B, `MICROMOBILITY=0` in the environment).
static var enabled: bool = OS.get_environment("MICROMOBILITY") != "0"

static var _lane_mesh: Mesh
static var _lane_material: ShaderMaterial


# --- Bike lanes (pure) -------------------------------------------------------------------------

static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


## Whether road (axis, index) has a bike lane at all (before the per-crossing checks).
static func road_has_lane(plan: CityPlan, axis: int, index: int) -> bool:
	if not enabled or plan == null:
		return false
	var name := plan.road_name(axis, index).to_upper()
	for s: String in LANE_STREETS:
		if name == s.to_upper():
			return true
	var avenue := plan.road_width(axis, index) > plan.street_width + 1.0
	return _h01([plan.seed, "bike_lane", axis, index]) < (LANE_AVENUE if avenue else LANE_STREET)


## The lane's style on road (axis, index): [green the whole way, protected].
static func lane_style(plan: CityPlan, axis: int, index: int) -> Array:
	return [_h01([plan.seed, "bike_green", axis, index]) < GREEN_SHARE, _h01([plan.seed, "bike_posts", axis, index]) < PROTECTED_SHARE]


## Whether road (axis, index) has its bike lane between crossings k and k + 1 of the other axis:
## the road has one, the stretch is open city road, and the blocks either side are ordinary
## city (no landmark's site, replica, river block, industrial yard).
static func lane_on(plan: CityPlan, axis: int, index: int, k: int) -> bool:
	if not road_has_lane(plan, axis, index):
		return false
	var other := 1 - axis
	var a := plan.road_pos(other, k)
	var b := plan.road_pos(other, k + 1)
	var mid := (a + b) * 0.5
	if not plan.road_open(axis, index, mid):
		return false
	var at := plan.road_pos(axis, index)
	var p := Vector2(at, mid) if axis == CityPlan.AXIS_X else Vector2(mid, at)
	if plan.macro != null and plan.zone_at(p) != MacroMap.Zone.CITY:
		return false
	for side in 2:
		var bx := (index - 1 + side) if axis == CityPlan.AXIS_X else k
		var bz := k if axis == CityPlan.AXIS_X else (index - 1 + side)
		var block := plan.block(bx, bz)
		if block.has("site") or int(block.get("district", 0)) == CityPlan.District.INDUSTRIAL:
			return false
		# A school's kerb is its bus zone (Schools: the buses stand in the parking lane).
		if block.has("school"):
			return false
		if plan.river_block(bx, bz):
			return false
		if plan.macro != null and plan.macro.replica != null and plan.macro.replica.block_role(plan, bx, bz) != 0:
			return false
	return true


## Offset from road (axis, index)'s centre line of the rider's line for traffic running `dir`
## (right-hand running, as TrafficManager: the kerb side is -dir in x on an AXIS_X road, +dir in
## z on an AXIS_Z one).
static func ride_offset(plan: CityPlan, axis: int, index: int, dir: int) -> float:
	var side := -dir if axis == CityPlan.AXIS_X else dir
	return float(side) * (plan.road_width(axis, index) * 0.5 - RIDE_LINE)


## The stretch of road (axis, index) between crossings k and k + 1 that the lane is painted on
## (along-axis coordinates, [from, to]).
static func lane_span(plan: CityPlan, axis: int, index: int, k: int) -> Vector2:
	var other := 1 - axis
	var a := plan.road_pos(other, k) + plan.road_width(other, k) * 0.5 + JUNCTION_GAP
	var b := plan.road_pos(other, k + 1) - plan.road_width(other, k + 1) * 0.5 - JUNCTION_GAP
	return Vector2(a, b)


## Whether a parked car at `spot` (chunk space, the parking lane of one of the chunk's own roads)
## would stand in a bike lane (CityChunk._park_car, after its rolls).
static func blocks_parking(chunk: CityChunk, spot: Vector3) -> bool:
	if not enabled or chunk.level != CityChunk.Level.FULL:
		return false
	var plan := chunk.plan
	for g: Vector2 in chunk.get_meta("micro_gutter", []):
		if g.distance_to(Vector2(spot.x, spot.z)) < 3.6:
			return true
	var rx := plan.road_pos(CityPlan.AXIS_X, chunk.ix + 1)
	if absf(absf(spot.x - rx) - CityPlan.parking_offset(plan.road_width(CityPlan.AXIS_X, chunk.ix + 1))) < 0.5:
		return lane_on(plan, CityPlan.AXIS_X, chunk.ix + 1, chunk.iz)
	var rz := plan.road_pos(CityPlan.AXIS_Z, chunk.iz + 1)
	if absf(absf(spot.z - rz) - CityPlan.parking_offset(plan.road_width(CityPlan.AXIS_Z, chunk.iz + 1))) < 0.5:
		return lane_on(plan, CityPlan.AXIS_Z, chunk.iz + 1, chunk.ix)
	return false


## Whether the parking-stall paint of road (axis, index) by chunk (ix, iz) goes (the lane is there).
static func lane_by_chunk(plan: CityPlan, axis: int, ix: int, iz: int) -> bool:
	if not enabled:
		return false
	return lane_on(plan, axis, ix + 1, iz) if axis == CityPlan.AXIS_X else lane_on(plan, axis, iz + 1, ix)


# --- What stands on a block's pavements (pure) -------------------------------------------------

## Whether this chunk gets anything of this (cheap: the step is only queued if so).
static func wanted(chunk: CityChunk, block: Dictionary) -> bool:
	if not enabled or chunk.level != CityChunk.Level.FULL or chunk.plan == null:
		return false
	return true


static func _face_ok(plan: CityPlan, block: Dictionary) -> bool:
	if block.has("site"):
		return false
	var kind := int(block.get("kind", CityPlan.BlockKind.BUILDINGS))
	return kind == CityPlan.BlockKind.BUILDINGS or kind == CityPlan.BlockKind.PARK or kind == CityPlan.BlockKind.PLAZA


## What block (ix, iz)'s pavements carry: a list of {item, face, t, ...}. Pure.
static func plan_block(plan: CityPlan, ix: int, iz: int) -> Array:
	var out: Array = []
	if not enabled:
		return out
	var block := plan.block(ix, iz)
	if not _face_ok(plan, block):
		return out
	if plan.river_block(ix, iz):
		return out
	if plan.macro != null and plan.macro.replica != null and plan.macro.replica.block_role(plan, ix, iz) != 0:
		return out
	var district := int(block.get("district", CityPlan.District.SUBURBS))
	var rect: Rect2 = block.rect
	var edges := CityChunk._sidewalk_edges(rect)
	var station_done := false
	for e in 4:
		var length := (edges[e][0] as Vector2).distance_to(edges[e][1])
		if length < 20.0:
			continue
		var id := [plan.seed, ix, iz, e]
		if not station_done and _h01(id + ["mm_station"]) < float(STATION_ODDS[district]):
			station_done = true
			var docks := DOCKS.x + int(_h01(id + ["mm_docks"]) * float(DOCKS.y - DOCKS.x + 1))
			out.append({"item": Item.STATION, "face": e, "t": lerpf(8.0, length - 8.0, _h01(id + ["mm_station_t"])), "docks": docks, "id": "st_%d" % e})
		var clusters := 0
		if _h01(id + ["mm_scoot"]) < float(SCOOTER_ODDS[district]):
			clusters = 2 if _h01(id + ["mm_scoot2"]) < SECOND_CLUSTER else 1
		for c in clusters:
			var cid := id + ["mm_cluster", c]
			var n := CLUSTER_SIZE.x + int(_h01(cid + ["n"]) * float(CLUSTER_SIZE.y - CLUSTER_SIZE.x + 1))
			out.append({"item": Item.SCOOTER, "face": e, "t": lerpf(5.0, length - 5.0, _h01(cid + ["t"])), "n": n,
				"op": int(_h01(cid + ["op"]) * 2.0), "mixed": _h01(cid + ["mix"]) < 0.3, "id": "sc_%d_%d" % [e, c],
				"gutter": _h01(cid + ["gutter"]) < GUTTER_SHARE, "tree": _h01(cid + ["tree"]) < TREE_SHARE})
		for end in 2:
			if _h01(id + ["mm_rack", end]) < float(RACK_ODDS[district]):
				var t := 3.2 + _h01(id + ["mm_rack_t", end]) * 2.5
				out.append({"item": Item.RACK, "face": e, "t": t if end == 0 else length - t, "bike": _h01(id + ["mm_rack_b", end]) < RACK_BIKE,
					"bike_kind": int(_h01(id + ["mm_rack_k", end]) * 2.0), "paint": _h01(id + ["mm_rack_p", end]), "id": "rk_%d_%d" % [e, end]})
	return out


# --- Building it -------------------------------------------------------------------------------

## Lays out this chunk's micromobility: its own roads' bike lanes, then whatever its block's
## pavements carry. A build step of a FULL chunk after the vendors (it keeps clear of them) and
## before the parked cars (which keep out of the lanes).
static func build_block(chunk: CityChunk, block: Dictionary) -> void:
	var plan := chunk.plan
	_build_lanes(chunk)
	var rect: Rect2 = block.rect
	var edges := CityChunk._sidewalk_edges(rect)
	var occupied := StreetVendors._occupied(chunk)
	occupied.append_array(_occupied_more(chunk))
	var trees: Array = []
	var data: Dictionary = chunk._batch.data()
	if data.has("tree_grate"):
		for x: Transform3D in data["tree_grate"].xforms:
			trees.append(Vector2(x.origin.x, x.origin.z))
	var count := [0]
	for v: Dictionary in plan_block(plan, chunk.ix, chunk.iz):
		match int(v.item):
			Item.STATION:
				_place_station(chunk, edges[int(v.face)], v, occupied, count)
			Item.SCOOTER:
				_place_cluster(chunk, edges[int(v.face)], v, occupied, trees, count)
			Item.RACK:
				_place_rack(chunk, edges[int(v.face)], v, occupied, count)
	for key: String in K_SCOOTER + [K_SHARE, K_DOCK, K_KIOSK, K_RACK, K_POST] + K_LOCKED:
		chunk._batch.set_draw_distance(key, DRAW)
		# A reach, not set_shadow_distance(): that only reaches a lighter twin, and these code-built
		# meshes have none, so they cast across the whole chunk (MultiMeshBatch.set_shadow_reach()).
		chunk._batch.set_shadow_reach(key, SHADOW)
	chunk._batch.set_no_shadow(K_POST)
	chunk._batch.set_draw_distance(K_LANE, LANE_DRAW)
	chunk.set_meta("micro_items", count[0])


## What else stands on (or must stay clear on) this chunk's pavements that StreetVendors does not
## list: a fire station's apron, a police station's forecourt (as Encampment keeps clear of), and
## Broadway's goods outside the shops and its street clock.
static func _occupied_more(chunk: CityChunk) -> Array:
	var out: Array = []
	var apron := FireStation.apron_point(chunk.plan, chunk.ix, chunk.iz)
	if apron != Vector2.INF:
		out.append([apron, 12.0])
	out.append_array(PoliceStation.keep_clear_points(chunk.plan, chunk.ix, chunk.iz))
	var data: Dictionary = chunk._batch.data()
	for key: String in ["bw_rack", "bw_gown", "bw_table"]:
		if data.has(key):
			for x: Transform3D in data[key].xforms:
				out.append([Vector2(x.origin.x, x.origin.z), 1.1])
	for c in chunk.get_children():
		if c is Node3D and String(c.name).begins_with("BroadwayClock"):
			out.append([Vector2((c as Node3D).position.x, (c as Node3D).position.z), 0.9])
	return out


## The bike lanes on the chunk's own roads (the +x and +z ones, as the parked cars).
static func _build_lanes(chunk: CityChunk) -> void:
	var plan := chunk.plan
	chunk._batch.tilt_keys[K_LANE] = true
	var lanes := 0
	for axis in 2:
		var index := chunk.ix + 1 if axis == CityPlan.AXIS_X else chunk.iz + 1
		var k := chunk.iz if axis == CityPlan.AXIS_X else chunk.ix
		if not lane_on(plan, axis, index, k):
			continue
		var span := lane_span(plan, axis, index, k)
		if span.y - span.x < 8.0:
			continue
		var style := lane_style(plan, axis, index)
		var green: bool = style[0]
		var posts: bool = style[1]
		var at := plan.road_pos(axis, index)
		var w := plan.road_width(axis, index)
		for s: float in [-1.0, 1.0]:
			var across := Vector3(-s, 0.0, 0.0) if axis == CityPlan.AXIS_X else Vector3(0.0, 0.0, -s)
			var yaw := atan2(-across.z, across.x)
			var basis := Basis(Vector3.UP, yaw)
			var along := basis.z
			# Which way the lane's traffic runs along the axis (+1 or -1), and so where it starts.
			var run_dir := along.z if axis == CityPlan.AXIS_X else along.x
			var kerb := at + s * w * 0.5
			var length := span.y - span.x
			var pieces := maxi(1, ceili(length / PIECE))
			var piece := length / float(pieces)
			var next_stencil := 3.0
			for p in pieces:
				# Distance from the lane's start (where its riders come in) to this piece's middle.
				var from_start := (float(p) + 0.5) * piece
				var u := span.x + (from_start if run_dir > 0.0 else length - from_start)
				var centre := Vector3(kerb, CityChunk.ROAD_TOP + 0.017, u) if axis == CityPlan.AXIS_X else Vector3(u, CityChunk.ROAD_TOP + 0.017, kerb)
				centre += across * (CityPlan.PARKING_LANE * 0.5)
				var conflict := from_start > length - 22.0 or from_start < piece
				var g := 1.0 if green else (0.5 if conflict else 0.0)
				var stencil := 0.0
				if from_start >= next_stencil:
					stencil = 1.0
					next_stencil = from_start + STENCIL_EVERY
				var xf := Transform3D(basis.scaled_local(Vector3(CityPlan.PARKING_LANE, 1.0, piece + 0.02)), centre)
				chunk._batch.add(K_LANE, lane_mesh(), xf, Color.WHITE, Color(g, stencil, 1.0, 0.0))
				lanes += 1
			if posts:
				var n := int((length - 16.0) / POST_EVERY)
				for i in n + 1:
					var u := span.x + 8.0 + float(i) * POST_EVERY
					var c := Vector3(kerb, CityChunk.ROAD_TOP, u) if axis == CityPlan.AXIS_X else Vector3(u, CityChunk.ROAD_TOP, kerb)
					c += across * ((LANE_TO + BUFFER_TO) * 0.5 + 0.06)
					chunk._batch.add(K_POST, MicroMesh.delineator(), Transform3D(Basis(Vector3.UP, float(i) * 1.3), c))
	chunk.set_meta("bike_lane_pieces", lanes)


## A cluster of scooters along face `edge`, slid along it to clear what stands there.
static func _place_cluster(chunk: CityChunk, edge: Array, v: Dictionary, occupied: Array, trees: Array, count: Array) -> void:
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var inward: Vector2 = edge[2]
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var n := int(v.n)
	var span := float(n) * 0.55
	var id := [chunk.plan.seed, chunk.ix, chunk.iz, String(v.id)]
	var start := -1.0
	for k in 9:
		var t: float = float(v.t) + [0.0, 1.5, -1.5, 3.0, -3.0, 4.5, -4.5, 6.0, -6.0][k]
		if t < 3.0 or t + span > length - 3.0:
			continue
		var ok := true
		for i in n:
			var q := a + dir * (t + float(i) * 0.55) + inward * SCOOTER_IN
			if not StreetVendors._clear(occupied, q, 0.32):
				ok = false
				break
		if ok:
			start = t
			break
	if start < 0.0:
		return
	var gutter_at := int(_h01(id + ["gutter_at"]) * float(n)) if bool(v.gutter) else -1
	for i in n:
		if count[0] >= MAX_ITEMS:
			return
		var sid := id + [i]
		var op := int(v.op) if not bool(v.mixed) else int(_h01(sid + ["op"]) * 2.0)
		var pose := Pose.STAND
		if i == gutter_at:
			pose = Pose.GUTTER
		elif _h01(sid + ["fall"]) < FALLEN_SHARE:
			pose = Pose.FALLEN
		var q := a + dir * (start + float(i) * 0.55) + inward * SCOOTER_IN
		var y := CityChunk.SIDEWALK_TOP
		# Mostly side by side, nose to the kerb or to the shops; now and then turned along it.
		var face_in := _h01(sid + ["face"]) < 0.5
		var heading := -inward if face_in else inward
		if _h01(sid + ["along"]) < 0.15:
			heading = dir
		var yaw := atan2(-heading.x, -heading.y) + (_h01(sid + ["yaw"]) - 0.5) * 0.5
		var roll := 0.1
		if pose == Pose.FALLEN:
			yaw += (_h01(sid + ["fyaw"]) - 0.5) * 1.6
			roll = 1.38 if _h01(sid + ["side"]) < 0.5 else -1.38
		elif pose == Pose.GUTTER:
			# Over the kerb into the gutter, lying along it.
			q = a + dir * (start + float(i) * 0.55) - inward * 0.3
			y = CityChunk.ROAD_TOP
			# The parked car that would stand on it stays away (blocks_parking()).
			var gutters: Array = chunk.get_meta("micro_gutter", [])
			gutters.append(q)
			chunk.set_meta("micro_gutter", gutters)
			yaw = atan2(-dir.x, -dir.y) + (_h01(sid + ["gyaw"]) - 0.5) * 0.6
			roll = 1.38 if _h01(sid + ["side"]) < 0.5 else -1.38
		# The cluster's last one leans on a street tree within reach.
		var lean_on := Vector2.INF
		if pose == Pose.STAND and bool(v.tree) and i == n - 1:
			var best := Vector2.INF
			for tr: Vector2 in trees:
				if tr.distance_to(q) < 4.0 and tr.distance_to(q) < best.distance_to(q):
					best = tr
			if best != Vector2.INF:
				lean_on = best
				var to := (best - q).normalized()
				q = best - to * 0.42 + Vector2(to.y, -to.x) * 0.05
				var along := Vector2(-to.y, to.x)
				yaw = atan2(-along.x, -along.y)
				pose = Pose.TREE
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, roll)
		if pose == Pose.TREE:
			# Leaning sideways onto the trunk: its top tipped toward the tree's side.
			var tree_x := (Basis(Vector3.UP, yaw) * Vector3.RIGHT).dot(Vector3(lean_on.x - q.x, 0.0, lean_on.y - q.y))
			basis = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -0.3 * signf(tree_x))
		var mesh := MicroMesh.whole(MicroMesh.Kind.SCOOTER_A + op)
		var lift := _rest_lift(mesh, basis)
		var at := Vector3(q.x, y + lift, q.y)
		var xf := Transform3D(basis, at)
		var wear := 0.15 + _h01(sid + ["wear"]) * 0.6
		var custom := Color(0.0, 0.0, 0.0, wear)
		_item(chunk, K_SCOOTER[op], mesh, xf, custom, "%s_%d" % [String(v.id), i], Vector3(0.36, 1.15, 1.08), 0.55, 15.0, count)
		occupied.append([q, 0.3])


## How far up a scooter turned by `basis` must sit for its lowest point to touch the ground:
## the lowest of the points it can rest on (the tyres' rims all round, the bar's ends, the
## deck's edges, the stem's top, the kickstand's foot). The mesh's box would float it: its
## corners reach far past the scooter once it is rolled over.
static func _rest_lift(_mesh: Mesh, basis: Basis) -> float:
	var lo := INF
	for p: Vector3 in _support_points():
		lo = minf(lo, (basis * p).y)
	return -lo if lo != INF else 0.0


static var _support: PackedVector3Array


static func _support_points() -> PackedVector3Array:
	if not _support.is_empty():
		return _support
	var g: Dictionary = MicroMesh.GEO[MicroMesh.Kind.SCOOTER_A]
	var r: float = g.r
	for c: Vector3 in [g.front, g.rear]:
		for k in 16:
			var a := TAU * float(k) / 16.0
			for x: float in [-0.028, 0.028]:
				_support.append(c + Vector3(x, cos(a) * r, sin(a) * r))
	var grip: Vector3 = g.grip
	for sx: float in [-1.0, 1.0]:
		_support.append(Vector3(sx * (grip.x + 0.04), grip.y + 0.0, grip.z))
		for z: float in [-0.33, 0.29]:
			_support.append(Vector3(sx * 0.09, float(g.deck) - 0.06, z))
			_support.append(Vector3(sx * 0.09, float(g.deck), z))
	_support.append(Vector3(0.0, 1.1, -0.34))
	_support.append(Vector3(-0.17, 0.0, 0.11))
	return _support


## A share station along face `edge`: its kiosk, a row of docks, bikes in some of them.
static func _place_station(chunk: CityChunk, edge: Array, v: Dictionary, occupied: Array, count: Array) -> void:
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var inward: Vector2 = edge[2]
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var docks := int(v.docks)
	var span := float(docks) * DOCK_PITCH + 1.4
	var id := [chunk.plan.seed, chunk.ix, chunk.iz, String(v.id)]
	var start := -1.0
	var best_free := -1
	for k in 11:
		var t: float = float(v.t) - span * 0.5 + [0.0, 1.0, -1.0, 2.0, -2.0, 3.5, -3.5, 5.0, -5.0, 7.0, -7.0][k]
		if t < 3.0 or t + span > length - 3.0:
			continue
		# The kiosk's spot must be clear; the docks' row mostly (a dock that meets a lamp or a
		# meter is left out of the row).
		if not StreetVendors._clear(occupied, a + dir * (t + 0.6) + inward * 0.75, 0.4):
			continue
		var free := 0
		for d in docks:
			if _dock_clear(occupied, a + dir * (t + 1.4 + (float(d) + 0.5) * DOCK_PITCH), inward):
				free += 1
		if free > best_free and free >= int(docks * 0.6):
			best_free = free
			start = t
			if free == docks:
				break
	if start < 0.0:
		return
	# Docks: their bike side (local -z) toward the shops, the posts at the kerb.
	var yaw := atan2(inward.x, inward.y)
	var dock_basis := Basis(Vector3.UP, yaw)
	var full := lerpf(DOCK_FULL.x, DOCK_FULL.y, _h01(id + ["full"]))
	for d in docks:
		var t := start + 1.4 + (float(d) + 0.5) * DOCK_PITCH
		if not _dock_clear(occupied, a + dir * t, inward):
			continue
		var q := a + dir * t + inward * DOCK_IN
		var dxf := Transform3D(dock_basis, Vector3(q.x, CityChunk.SIDEWALK_TOP, q.y) + dock_basis * Vector3(0.0, 0.0, -0.32))
		chunk._batch.add(K_DOCK, MicroMesh.dock(), dxf, Color.WHITE, Color(0, 0, 0, 0.2))
		if _h01(id + ["bike", d]) < full and count[0] < MAX_ITEMS:
			# The bike faces the dock, its front wheel in the lock.
			var bb := Basis(Vector3.UP, yaw + PI)
			var bq := q + inward * 1.02
			var bxf := Transform3D(bb, Vector3(bq.x, CityChunk.SIDEWALK_TOP, bq.y))
			_item(chunk, K_SHARE, MicroMesh.whole(MicroMesh.Kind.SHARE), bxf, Color(0, 0, 0, 0.1 + 0.4 * _h01(id + ["wear", d])),
				"%s_%d" % [String(v.id), d], Vector3(0.5, 1.1, 1.85), 0.55, 23.0, count)
	# The kiosk at the row's start, its screen to the pavement.
	var kq := a + dir * (start + 0.6) + inward * 0.75
	var kxf := Transform3D(Basis(Vector3.UP, atan2(-inward.x, -inward.y) + PI), Vector3(kq.x, CityChunk.SIDEWALK_TOP, kq.y))
	chunk._batch.add(K_KIOSK, MicroMesh.kiosk(), kxf, Color.WHITE, Color(0, 0, 0, 0.2))
	var body := StaticBody3D.new()
	body.name = "ShareKiosk_" + String(v.id)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.56, 1.7, 0.4)
	shape.shape = box
	shape.position = Vector3(0.0, 0.85, 0.0)
	body.add_child(shape)
	body.transform = Transform3D(kxf.basis, kxf.origin + Vector3(0.0, chunk._gy(kq.x, kq.y), 0.0))
	chunk.add_child(body)
	for x in int(span / 0.7) + 1:
		occupied.append([a + dir * (start + float(x) * 0.7) + inward * 1.2, 0.9])
	var stations: Array = chunk.get_meta("share_stations", [])
	stations.append(kq)
	chunk.set_meta("share_stations", stations)


## Whether a dock at kerb point `k` and its bike (in to 2.3 m) are clear of what stands there.
static func _dock_clear(occupied: Array, k: Vector2, inward: Vector2) -> bool:
	return StreetVendors._clear(occupied, k + inward * DOCK_IN, 0.18) and StreetVendors._clear(occupied, k + inward * 1.25, 0.3) \
		and StreetVendors._clear(occupied, k + inward * 2.0, 0.25)


## A rack near a corner, parallel to the kerb, a bike locked to some.
static func _place_rack(chunk: CityChunk, edge: Array, v: Dictionary, occupied: Array, count: Array) -> void:
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var inward: Vector2 = edge[2]
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var q := Vector2.INF
	for k in 7:
		var t: float = float(v.t) + [0.0, 0.8, -0.8, 1.6, -1.6, 2.4, -2.4][k]
		if t < 2.5 or t > length - 2.5:
			continue
		var p := a + dir * t + inward * RACK_IN
		if StreetVendors._clear(occupied, p, 0.45) and StreetVendors._clear(occupied, p + inward * 0.4, 0.35):
			q = p
			break
	if q == Vector2.INF:
		return
	var basis := Basis(Vector3.UP, atan2(-dir.y, dir.x))
	chunk._batch.add(K_RACK, MicroMesh.rack(), Transform3D(basis, Vector3(q.x, CityChunk.SIDEWALK_TOP, q.y)), Color.WHITE, Color(0, 0, 0, 0.3))
	occupied.append([q, 0.5])
	if bool(v.bike) and count[0] < MAX_ITEMS:
		var bk := MicroMesh.Kind.ROAD if int(v.bike_kind) == 0 else MicroMesh.Kind.CRUISER
		var paints: Array = MicroMesh.PAINTS[bk]
		var paint: Color = paints[int(float(v.paint) * paints.size()) % paints.size()]
		var bq := q + inward * 0.22
		var bb := Basis(Vector3.UP, atan2(-dir.x, -dir.y) + (PI if float(v.paint) < 0.5 else 0.0)) * Basis(Vector3.BACK, 0.06)
		var bxf := Transform3D(bb, Vector3(bq.x, CityChunk.SIDEWALK_TOP, bq.y))
		_item(chunk, K_LOCKED[int(v.bike_kind)], MicroMesh.whole(bk), bxf, Color(paint.r, paint.g, paint.b, 0.35),
			String(v.id), Vector3(0.45, 1.0, 1.75), 0.5, 11.0, count)
		occupied.append([bq, 0.6])


## One knockable piece: drawn in the chunk's batch, an EncampmentItem for its collision, gone
## for good once knocked (WorldState).
static func _item(chunk: CityChunk, key: String, mesh: Mesh, xf: Transform3D, custom: Color, item_id: String, box: Vector3, centre_y: float, mass: float, count: Array) -> void:
	var id := "mm_%s_%d_%d" % [item_id, chunk.ix, chunk.iz]
	if WorldState.is_destroyed(chunk.key, id):
		return
	var index := chunk._batch.add(key, mesh, xf, Color.WHITE, custom)
	var item := EncampmentItem.new()
	item.name = "Micro_" + id
	item.chunk = chunk
	item.item_id = id
	item.instances = [[key, index]]
	item.mesh = mesh
	item.mass_kg = mass
	item.tint = Color.WHITE
	item.custom = custom
	item.health = 30.0
	item.setup(box, centre_y)
	item.transform = Transform3D(xf.basis, xf.origin + Vector3(0.0, chunk._gy(xf.origin.x, xf.origin.z), 0.0))
	chunk.add_child(item)
	count[0] += 1


# --- The lane paint ------------------------------------------------------------------------------

## A unit quad facing up (x across from the kerb, z along the lane's traffic), UV 0..1 over it.
static func lane_mesh() -> Mesh:
	if _lane_mesh != null:
		return _lane_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := [Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.5), Vector3(-0.5, 0.0, 0.5)]
	var uv := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	# Clockwise seen from above (Godot's front faces).
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uv[i])
		st.add_vertex(c[i])
	var mesh := st.commit()
	if _lane_material == null:
		_lane_material = ShaderMaterial.new()
		_lane_material.shader = load("res://shaders/bike_lane.gdshader")
	mesh.surface_set_material(0, _lane_material)
	_lane_mesh = mesh
	return mesh


## The meshes, once, on the loading screen.
static func warm() -> void:
	if not enabled:
		return
	MicroMesh.warm()
	lane_mesh()
