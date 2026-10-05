class_name StreetSigns
extends RefCounted
## The street's signs as real models (SignKit's meshes on `shaders/street_sign.gdshader`), placed
## where the plan already decides a sign belongs:
##   * green street-name blades, two crossed on a cast cap bracket, on every corner StreetDetail
##     names (the +X +Z corner always, the opposite one by its old hash): on their own post at an
##     unsigned junction, on top of the stop sign's post at a four-way stop, on top of the signal
##     pole at a signalised one - plus, on every mast arm, LA's big name sign naming the street the
##     approach crosses, and on an avenue's arms the lane-use sign over its two lanes (the turn
##     lane's arrow matches the paint) or a NO TURN ON RED by hash;
##   * the stop sign (a real 30 in octagon, white border, STOP in the stroke font, an ALL WAY
##     plaque, aluminium back with its bolts) on the near right corner of each approach, facing
##     the traffic it stops - the old cylinder faced the junction's centre diagonally;
##   * yield signs on the minor road's two approaches at a share of the unsigned junctions;
##   * speed limits (by district and road), LA's red street-cleaning and green 2-hour plates on
##     their posts along the kerb, and the no-parking blades by the junctions (their old rolls);
##   * the school zone assembly (the crossing pentagon over SCHOOL / SPEED LIMIT 25 WHEN CHILDREN
##     ARE PRESENT) on every approach along a school block.
## The junction signs REPLACE the old props one for one inside the same `_add_prop` calls (so no
## prop id in the chunk moves); the new block signs are props of their own with ids of their own
## ("ssign_<n>", `_add()`), so nothing else's id moves either. Every roll is a hash of seed + place.
## FULL chunks only (LOD chunks and the far city never drew signs). `STREET_SIGNS=0` in the
## environment puts the old signs back (the A/B).

static var enabled: bool = OS.get_environment("STREET_SIGNS") != "0"
## Tests: commit() keeps each sign batch's transforms on the chunk (meta "ss_debug_xforms"), as
## the dummy renderer reads a MultiMesh's back as identity.
static var keep_xforms: bool = false
## SS_DEBUG=1 prints every block sign with an EYE for still_shot.gd 7 m in front of its face.
static var debug: bool = OS.get_environment("SS_DEBUG") == "1"

## How far the signs draw (metres): plates and blades at the kerb, the mast-arm signs further, as
## they hang over the road where a driver reads them from a block back. Their shadows only near.
const DRAW := 160.0
const ARM_DRAW := 240.0
const SHADOW_REACH := 30.0
## Chances: a face carries a speed limit (avenue / street), a face is posted for parking, an
## unsigned junction has yield signs, an avenue's arm carries a NO TURN ON RED instead of nothing
## on a one-lane approach.
const SPEED_AVENUE := 0.55
const SPEED_STREET := 0.22
const PARKING_FACE := 0.5
const YIELD_ODDS := 0.4
const NO_TURN_RED := 0.3
## Parking posts: spacing along a face (metres) and how far from the face's ends they keep.
const PARKING_SPACING := 38.0
const PARKING_END := 16.0
## How far in from the kerb a post stands (metres).
const KERB_IN := 0.55
## What a new sign keeps clear of (metres, centre to centre).
const CLEAR := 1.3
const CLEAR_TREE := 2.0
## What a new sign keeps clear of: the street's own furniture, by batch key and by prop kind -
## only the core furniture every block has, never another feature's (a vendor's cart, a
## forecourt's bench), so switching a feature off never moves a sign and its checks stay exact.
const OBSTACLE_KEYS := ["lamp", "tree", "palm", "hydrant", "meter", "bench", "bus", "shelter", "rack", "newsbox", "mailbox", "bollard", "upole", "sig_", "trash", "cabinet", "kiosk", "ss_"]
const OBSTACLE_KINDS := ["lamp", "hydrant", "bench", "bus_stop", "signal", "signal_cabinet", "mailbox", "newsbox", "rack", "bollard", "street_sign", "stop_sign", "meter"]


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _roll(parts: Array) -> Color:
	return Color(_h01(parts + ["wear"]), 0.0, 0.0, 0.0)


## The hundred-block number on a blade naming a road, from the crossing road's index.
static func block_number(cross_index: int) -> String:
	return str((absi(cross_index) + 1) * 100)


## [name_x, num_x, name_z, num_z] for the chunk's junction (ix + 1, iz + 1).
static func junction_names(ch: CityChunk) -> Array:
	var plan: CityPlan = ch.plan
	return [plan.road_name(CityPlan.AXIS_X, ch.ix + 1), block_number(ch.iz + 1), plan.road_name(CityPlan.AXIS_Z, ch.iz + 1), block_number(ch.ix + 1)]


## True when corner `c` of the chunk's junction carries the name blades (StreetDetail's rule).
static func names_at(ch: CityChunk, c: Vector2) -> bool:
	if c == Vector2(1, 1):
		return true
	return c == Vector2(-1, -1) and StreetDetail._hash01([ch.plan.seed, "sign2", ch.ix, ch.iz]) < 0.55


## The names in the order SignKit.crossed_blades() wants for an assembly turned by `yaw` (a
## multiple of 90 degrees): its upper blade runs along the assembly's local Z, which is world Z
## at 0 / 180 degrees and world X at +-90.
static func _blade_order(names: Array, yaw: float) -> Array:
	var quarter := posmod(int(round(yaw / (PI * 0.5))), 4)
	if quarter % 2 == 0:
		return names
	return [names[2], names[3], names[0], names[1]]


## Local X toward `x`, the face along +-`n` whichever keeps the basis right-handed (for the
## two-sided plates, whose back reads as well as their front).
static func _basis(x: Vector3, n: Vector3) -> Basis:
	var z := n
	if z.cross(x).y < 0.0:
		z = -n
	return Basis(x, z.cross(x), z)


# --- Junction hooks (called in place of the old props) --------------------------------------------

## StreetDetail._name_sign: a post with the blades at an unsigned junction. At a stop or signal
## junction the blades go on the stop sign's post or the signal pole (stop_corner(),
## signal_extras()), and the old post's prop id is spent here so no id after it moves.
static func name_post(ch: CityChunk, corner: Vector2, name_x: String, name_z: String) -> void:
	var inter: Dictionary = ch.plan.intersection(ch.ix + 1, ch.iz + 1)
	var kind := int(inter.kind)
	if kind == CityPlan.Intersection.STOP_SIGNS or kind == CityPlan.Intersection.SIGNALS:
		ch._prop_counter += 1
		return
	var names := junction_names(ch)
	var mesh := SignKit.name_post(name_x, names[1], name_z, names[3])
	var at := Vector3(corner.x, CityChunk.SIDEWALK_TOP, corner.y)
	ch._add_prop("street_sign", at, Color(0.3, 0.3, 0.32), [
		["ss_" + _key(mesh), mesh, Transform3D(Basis(), at), Color.WHITE, _roll([ch.plan.seed, "np", corner])],
	], [[Vector3(0.2, 2.9, 0.2), at + Vector3(0.0, 1.45, 0.0), 0.0]])


## One corner of a four-way stop: the stop sign faces the approach whose near right corner this
## is (right-hand traffic), with the ALL WAY plaque; the name blades on top where StreetDetail
## put them.
static func stop_corner(ch: CityChunk, at: Vector3, c: Vector2) -> void:
	# (+-1, +-1) with c.x == c.y stands at the north-south road's approach (its traffic keeps to
	# -x going +z), the other two at the east-west road's.
	var facing := Vector3(0.0, 0.0, c.y) if c.x * c.y > 0.0 else Vector3(c.x, 0.0, 0.0)
	var yaw := atan2(facing.x, facing.z)
	var names: Array = []
	if names_at(ch, c):
		names = _blade_order(junction_names(ch), yaw)
	var mesh := SignKit.stop_post(names)
	ch._add_prop("stop_sign", at, Color(0.8, 0.12, 0.1), [
		["ss_" + _key(mesh), mesh, Transform3D(Basis(Vector3.UP, yaw), at), Color.WHITE, _roll([ch.plan.seed, "stop", ch.ix, ch.iz, c])],
	], [[Vector3(0.3, 2.8, 0.3), at + Vector3(0.0, 1.4, 0.0), 0.0]])


## A signal corner's signs, appended to the pole's own prop (they break with it): the mast arm's
## name sign naming the street its approach crosses, the lane-use sign on a two-lane approach or
## a NO TURN ON RED by hash on a one-lane one, and the name blades on the pole top where
## StreetDetail put them. `heads` are the arm's head distances from the pole, `facing` the way
## they face (toward the oncoming traffic), `on_x` true when the approach is the north-south road.
static func signal_extras(ch: CityChunk, instances: Array, at: Vector3, c: Vector2, on_x: bool, arm_dir: Vector3, facing: Vector3, heads: Array) -> void:
	var names := junction_names(ch)
	var arm_y := PropFactory.SIGNAL_ARM_Y
	var yaw := atan2(facing.x, facing.z)
	var basis := Basis(Vector3.UP, yaw)
	# The arm runs along local -X or +X of that basis: which way decides which end is the pole.
	var cross_name: String = names[2] if on_x else names[0]
	var cross_num: String = names[3] if on_x else names[1]
	var near := 1e9
	var far := 0.0
	for d: float in heads:
		near = minf(near, d)
		far = maxf(far, d)
	var name_mesh := SignKit.arm_name(cross_name, cross_num)
	var name_len := SignKit.blade_length(cross_name, SignKit.ARM_SIGN_CAP) * 1.05
	name_len = clampf(name_len, 1.5, 2.9)
	var roll := _roll([ch.plan.seed, "arm", ch.ix, ch.iz, c])
	var d_name := maxf(near - name_len * 0.5 - 0.7, name_len * 0.5 + 0.6)
	if heads.size() == 1 and _h01([ch.plan.seed, "ntor", ch.ix, ch.iz, c]) < NO_TURN_RED:
		# Room for both between the pole and the head: the plate next to the head, the name nearer
		# the pole.
		var d_ntor := near - 1.1
		d_name = maxf(d_ntor - 0.5 - name_len * 0.5, name_len * 0.5 + 0.5)
		var m := SignKit.arm_no_turn_red()
		instances.append(["ss_" + _key(m), m, Transform3D(basis, at + arm_dir * d_ntor + Vector3(0.0, arm_y, 0.0)), Color.WHITE, roll])
	instances.append(["ss_" + _key(name_mesh), name_mesh, Transform3D(basis, at + arm_dir * d_name + Vector3(0.0, arm_y, 0.0)), Color.WHITE, roll])
	if heads.size() >= 2:
		var m := SignKit.arm_lanes()
		instances.append(["ss_" + _key(m), m, Transform3D(basis, at + arm_dir * ((near + far) * 0.5) + Vector3(0.0, arm_y, 0.0)), Color.WHITE, roll])
	if names_at(ch, c):
		var top := SignKit.pole_top_blades(names[0], names[1], names[2], names[3])
		instances.append(["ss_" + _key(top), top, Transform3D(Basis(), at), Color.WHITE, roll])


## StreetDetail._regulatory_signs: the no-parking blade it rolled, as LA's red plate on a post
## along the kerb facing the street (two-sided), its arrow toward the junction.
static func no_parking(ch: CityChunk, at: Vector3, face_x: bool, c: Vector2, i: int) -> void:
	var toward := Vector3(0.0, 0.0, -c.y) if face_x else Vector3(-c.x, 0.0, 0.0)
	var street := Vector3(-c.x, 0.0, 0.0) if face_x else Vector3(0.0, 0.0, -c.y)
	var mesh := SignKit.no_parking_post()
	ch._add_prop("street_sign", at, Color(0.3, 0.3, 0.32), [
		["ss_" + _key(mesh), mesh, Transform3D(_basis(toward, street), at), Color.WHITE, _roll([ch.plan.seed, "nopark", ch.ix, ch.iz, i])],
	], [[Vector3(0.2, 2.6, 0.2), at + Vector3(0.0, 1.3, 0.0), 0.0]])


static func _key(m: Mesh) -> String:
	return str(m.get_instance_id())


# --- The block's own signs (a build step) -----------------------------------------------------------

## The block step: speed limits, school zones and parking posts along the four faces, yield signs
## at the chunk's junction when it is unsigned. Runs once, late in a FULL chunk's build (after the
## street furniture it keeps clear of).
static func build(ch: CityChunk) -> void:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	var plan: CityPlan = ch.plan
	var block: Dictionary = plan.block(ch.ix, ch.iz)
	var rect: Rect2 = block.rect
	if ch.zone != MacroMap.Zone.CITY or block.has("site") or plan.river_block(ch.ix, ch.iz):
		return
	if plan.macro and plan.macro.replica and plan.macro.replica.block_role(plan, ch.ix, ch.iz) != 0:
		return
	var obstacles := _obstacles(ch)
	var district: int = plan.district_at(rect.get_center())
	var faces := [
		[CityPlan.AXIS_Z, ch.iz, Vector2i(0, -1)], [CityPlan.AXIS_Z, ch.iz + 1, Vector2i(0, 1)],
		[CityPlan.AXIS_X, ch.ix, Vector2i(-1, 0)], [CityPlan.AXIS_X, ch.ix + 1, Vector2i(1, 0)],
	]
	var edges: Array = CityChunk._sidewalk_edges(rect)
	var school_here := int(block.kind) == CityPlan.BlockKind.SCHOOL
	for k in 4:
		var axis: int = faces[k][0]
		var index: int = faces[k][1]
		var across: Vector2i = faces[k][2]
		var e: Array = edges[k]
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var mid := (a + b) * 0.5
		if not plan.road_open(axis, index, mid.y if axis == CityPlan.AXIS_X else mid.x):
			continue
		var length := a.distance_to(b)
		if length < 40.0:
			continue
		# The kerb lane's traffic has this block on its right: it drives along d.
		var d := Vector2(inward.y, -inward.x)
		var entry := a if d.dot(a) < d.dot(b) else b
		var width := plan.road_width(axis, index)
		var avenue := width > plan.street_width + 1.0
		var across_block: Dictionary = plan.block(ch.ix + across.x, ch.iz + across.y)
		var school := school_here or int(across_block.kind) == CityPlan.BlockKind.SCHOOL
		var f := Vector3(-d.x, 0.0, -d.y)
		var yaw := atan2(f.x, f.z)
		# The approach's sign: 14-24 m past the crossing it comes in from.
		var t := 14.0 + 10.0 * _h01([plan.seed, "spd_t", axis, index, k, ch.ix, ch.iz])
		var p := entry + d * t + inward * KERB_IN
		if school or _h01([plan.seed, "spd", axis, index, ch.ix, ch.iz, k]) < (SPEED_AVENUE if avenue else SPEED_STREET):
			p = _clear_spot(p, d, obstacles)
			if p != Vector2.INF:
				var mesh := SignKit.school_post() if school else SignKit.speed_post(speed_for(district, avenue))
				var at := Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y)
				_add(ch, "street_sign", at, [["ss_" + _key(mesh), mesh, Transform3D(Basis(Vector3.UP, yaw), at), Color.WHITE, _roll([plan.seed, "spd", ch.ix, ch.iz, k])]],
					[[Vector3(0.2, 3.0, 0.2), at + Vector3(0.0, 1.5, 0.0), 0.0]])
				obstacles.append(Vector3(p.x, p.y, CLEAR))
		# Parking posts along the rest of the face (not on avenues downtown, where nobody parks).
		if district == CityPlan.District.INDUSTRIAL or (avenue and district == CityPlan.District.DOWNTOWN):
			continue
		if _h01([plan.seed, "park", axis, index, ch.ix, ch.iz, k]) >= PARKING_FACE:
			continue
		var day := absi(hash([plan.seed, "sweep", axis, index, k % 2])) % SignKit.SWEEP_DAYS.size()
		var hours := absi(hash([plan.seed, "sweep_h", axis, index])) % SignKit.SWEEP_HOURS.size()
		var two_hour := district == CityPlan.District.MIDTOWN or district == CityPlan.District.DOWNTOWN or (district == CityPlan.District.BEACHTOWN and _h01([plan.seed, "2hr", axis, index]) < 0.6)
		var mesh := SignKit.parking_post(day, hours, two_hour)
		var dir := (b - a) / length
		var s := PARKING_END
		var n := 0
		while s < length - PARKING_END and n < 6:
			var q := a + dir * s + inward * KERB_IN
			s += PARKING_SPACING
			var spot := _clear_spot(q, dir, obstacles)
			if spot == Vector2.INF:
				continue
			var at := Vector3(spot.x, CityChunk.SIDEWALK_TOP, spot.y)
			var bas := _basis(Vector3(d.x, 0.0, d.y), Vector3(-inward.x, 0.0, -inward.y))
			_add(ch, "street_sign", at, [["ss_" + _key(mesh), mesh, Transform3D(bas, at), Color.WHITE, _roll([plan.seed, "pk", ch.ix, ch.iz, k, n])]],
				[[Vector3(0.2, 3.0, 0.2), at + Vector3(0.0, 1.5, 0.0), 0.0]])
			obstacles.append(Vector3(spot.x, spot.y, CLEAR))
			n += 1
	_yields(ch, obstacles)


## The speed limit for a road (mph): avenues by district, everything else 25.
static func speed_for(district: int, avenue: bool) -> int:
	if not avenue:
		return 25
	match district:
		CityPlan.District.DOWNTOWN:
			return 30
		CityPlan.District.SUBURBS, CityPlan.District.INDUSTRIAL:
			return 40
	return 35


## Yield signs on the minor road's two approaches at an unsigned junction (the narrower road; a
## hash where they are as wide), on the near right corner, a step back from the corner's blades.
static func _yields(ch: CityChunk, obstacles: Array) -> void:
	var plan: CityPlan = ch.plan
	var inter: Dictionary = plan.intersection(ch.ix + 1, ch.iz + 1)
	if int(inter.kind) != CityPlan.Intersection.PLAIN or plan.junction_closed(ch.ix + 1, ch.iz + 1):
		return
	if _h01([plan.seed, "yield", ch.ix, ch.iz]) >= YIELD_ODDS:
		return
	var pos: Vector2 = inter.pos
	var size: Vector2 = inter.size
	if plan.zone_at(pos) != MacroMap.Zone.CITY:
		return
	# size.x is the north-south road's width (StreetDetail's approaches).
	var ns_minor := size.x < size.y - 0.5 or (absf(size.x - size.y) <= 0.5 and _h01([plan.seed, "yield_ax", ch.ix, ch.iz]) < 0.5)
	var corners := [Vector2(-1, -1), Vector2(1, 1)] if ns_minor else [Vector2(-1, 1), Vector2(1, -1)]
	for i in 2:
		var c: Vector2 = corners[i]
		var facing := Vector3(0.0, 0.0, c.y) if ns_minor else Vector3(c.x, 0.0, 0.0)
		var corner := pos + Vector2(c.x * (size.x * 0.5 + 1.2), c.y * (size.y * 0.5 + 1.2)) + Vector2(facing.x, facing.z) * 1.8
		var at := Vector3(corner.x, CityChunk.SIDEWALK_TOP, corner.y)
		var mesh := SignKit.yield_post()
		_add(ch, "stop_sign", at, [["ss_" + _key(mesh), mesh, Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)), at), Color.WHITE, _roll([plan.seed, "yield", ch.ix, ch.iz, i])]],
			[[Vector3(0.3, 2.9, 0.3), at + Vector3(0.0, 1.45, 0.0), 0.0]])
		obstacles.append(Vector3(corner.x, corner.y, CLEAR))


## `p`, or a spot up to 4.5 m along `dir` either way that keeps clear of everything in
## `obstacles` (Vector3: x, z, the clearance it needs); Vector2.INF when there is none.
static func _clear_spot(p: Vector2, dir: Vector2, obstacles: Array) -> Vector2:
	for k: float in [0.0, 1.5, -1.5, 3.0, -3.0, 4.5]:
		var q := p + dir * k
		var ok := true
		for o: Vector3 in obstacles:
			if Vector2(o.x, o.y).distance_squared_to(q) < o.z * o.z:
				ok = false
				break
		if ok:
			return q
	return Vector2.INF


## Where the street furniture already stands in this chunk: every core prop's position and the
## furniture batches' instances (chunk-local x, z, the space signs are placed in), with the
## clearance each needs (a tree's grate and trunk more than a pole).
static func _obstacles(ch: CityChunk) -> Array:
	var out: Array = []
	for r: Dictionary in ch.prop_records:
		if not OBSTACLE_KINDS.has(String(r.kind)):
			continue
		var p: Vector3 = r.position
		out.append(Vector3(p.x, p.z, CLEAR))
	var data: Dictionary = ch._batch.data()
	for key: String in data:
		var hit := false
		for pre: String in OBSTACLE_KEYS:
			if key.begins_with(pre):
				hit = true
				break
		if not hit:
			continue
		var r := CLEAR_TREE if key.begins_with("tree") or key.begins_with("palm") else CLEAR
		for x: Transform3D in data[key].xforms:
			out.append(Vector3(x.origin.x, x.origin.z, r))
	return out


## A prop of the block's own signs, with an id of its own ("ssign_<n>"), so adding these moves no
## other prop's id (CityChunk._add_prop with a separate counter).
static func _add(ch: CityChunk, kind: String, at: Vector3, instances: Array, shapes: Array) -> void:
	var n: int = ch.get_meta("ssign_n", 0)
	ch.set_meta("ssign_n", n + 1)
	var id := "ssign_%d" % n
	if WorldState.is_destroyed(ch.key, id):
		return
	var g := ch._gy(at.x, at.z)
	var record := {"id": id, "kind": kind, "position": at + Vector3(0.0, g, 0.0), "color": Color(0.3, 0.3, 0.32), "health": CityChunk.PROP_HEALTH.get(kind, 20.0), "instances": [], "shapes": [], "dead": false}
	if debug:
		var z: Vector3 = (instances[0][2] as Transform3D).basis.z
		var eye := at + z * 7.0
		print("SSIGN %s %s at=%.1f,%.1f EYE=%.1f,1.6,%.1f,%.0f,8" % [id, String((instances[0][1] as Mesh).get_meta("ss_key", "")), at.x, at.z, eye.x, eye.z, rad_to_deg(atan2(z.x, z.z))])
	for inst: Array in instances:
		var index: int = ch._batch.add(inst[0], inst[1], inst[2], inst[3], inst[4])
		record.instances.append([inst[0], index])
	for s: Array in shapes:
		var shape: Node = ch._add_shape(s[0], s[1] + Vector3(0.0, g, 0.0), s[2])
		if shape:
			shape.set_meta("prop", record)
			record.shapes.append(shape)
	ch.prop_records.append(record)


## From CityChunk._finish_build(), before the batches are built: every sign batch's draw distance
## and shadow reach.
static func commit(ch: CityChunk) -> void:
	var kept := {}
	if debug:
		var all := {}
		for k2: String in ch._batch.keys():
			all[k2] = (ch._batch.data()[k2].xforms as Array).duplicate()
		ch.set_meta("ss_debug_all", all)
	for key: String in ch._batch.keys():
		if not key.begins_with("ss_"):
			continue
		var data: Dictionary = ch._batch.data()[key]
		var high := false
		for x: Transform3D in data.xforms:
			high = high or x.origin.y - ch._gy(x.origin.x, x.origin.z) > 4.0
		ch._batch.set_draw_distance(key, ARM_DRAW if high else DRAW)
		ch._batch.set_shadow_reach(key, SHADOW_REACH)
		if keep_xforms:
			kept[key] = (data.xforms as Array).duplicate()
	if keep_xforms:
		ch.set_meta("ss_debug_xforms", kept)
