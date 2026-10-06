class_name FireStation
extends RefCounted
## Fire stations (2026-10-04, the emergency services): a two-storey brick firehouse with two
## apparatus bays whose sectional doors roll up when a unit goes out, a concrete apron and a
## ramp down across the pavement to the kerb, the station's number over the doors, a flagpole.
## They are where the engines and ambulances come from (Emergency.send -> nearest() /
## exit_lane(): a unit pulls out of its bay, down the apron and onto the street).
##
## WHERE is worked out, never placed: the city is cut into CELL x CELL squares; a hash of the
## seed and the cell says whether the cell has a station and picks a point in it; the block under
## that point, if it is ordinary buildings in a district that has stations, gives up one lot - its
## biggest edge lot that is deep enough and clear of the freeways. Hashes of seed + cell + block
## only (never a chunk's or a block's rng), so a chunk at any level, the far city and Emergency
## ask the same question and get the same station. CityChunk._build_lot() hands the lot here
## after its own rolls (the pad roll is made either way, so no other lot moves).
##
## Names and numbers are this game's own (RANDO CITY FIRE DEPT, STATION nn), never a real
## department's.

const CELL := 850.0
const ODDS := 0.85
const STATION_DISTRICTS := [CityPlan.District.DOWNTOWN, CityPlan.District.MIDTOWN, CityPlan.District.SUBURBS,
	CityPlan.District.BEACHTOWN, CityPlan.District.INDUSTRIAL]
## Smallest lot that takes a station (frontage, depth; m).
const MIN_LOT := Vector2(19.0, 23.0)
## The building: frontage and depth at most (m), storey heights, the bays.
const MAX_W := 24.0
const MAX_D := 20.0
const BAY_H := 6.2
const UPPER_H := 3.6
const BAY_DOOR := Vector2(4.3, 4.4)
const BAYS := 2
## The apron in front of the bays (m, at least) and its fall to the pavement.
const APRON_MIN := 4.0
const DEPT := "RANDO CITY FIRE DEPT"
const BRICK_TINT := Color(0.92, 0.80, 0.74)
const DOOR_RED := Color(0.62, 0.05, 0.04)
const TRIM_CREAM := Color(0.86, 0.83, 0.75)
## Seconds a bay door takes to roll up or down, and how long it stays up.
const DOOR_TIME := 3.5
const DOOR_OPEN_HOLD := 14.0

## Off (FIRE_STATIONS=0 in the environment): no stations anywhere, the lots keep their buildings
## (the A/B for stills and frame counts).
static var enabled: bool = OS.get_environment("FIRE_STATIONS") != "0"
static var _cache: Dictionary = {}
## Doors asked open (cell -> ticks msec they close again), so a station built after the ask (its
## chunk streamed in later) comes up with them open.
static var _open_until: Dictionary = {}
static var _mats: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## The station of grid cell `cell`: {} or {"cell", "block", "lot" (the lot dictionary), "side",
## "frame", "number", "front" (true world XZ on the kerb in front of the bays), "road" [axis,
## index]}. Cached per plan and cell.
static func for_cell(plan: CityPlan, cell: Vector2i) -> Dictionary:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cache.has(key):
		return _cache[key]
	var out := {}
	_cache[key] = out
	if not enabled:
		return out
	if _h01([plan.seed, cell.x, cell.y, "fire_station"]) > ODDS:
		return out
	var target := Vector2((float(cell.x) + lerpf(0.25, 0.75, _h01([plan.seed, cell.x, cell.y, "fs_x"]))) * CELL,
			(float(cell.y) + lerpf(0.25, 0.75, _h01([plan.seed, cell.x, cell.y, "fs_z"]))) * CELL)
	if plan.zone_at(target) != MacroMap.Zone.CITY:
		return out
	var bi := plan.block_index_at(target)
	# The block's own cell must be this cell (so asking from the block finds the same station).
	var b := plan.block(bi.x, bi.y)
	var rect: Rect2 = b.rect
	if _cell_of(rect.get_center()) != cell:
		return out
	if not STATION_DISTRICTS.has(int(b.district)) or int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or b.has("hospital"):
		return out
	if plan.macro and (Landmarks.claims(rect) or DowntownReal.in_extent(rect.get_center()) and int(b.district) == CityPlan.District.DOWNTOWN and _core(plan, rect)):
		return out
	var inner := rect.grow(-plan.sidewalk_width)
	var best: Dictionary = {}
	var best_size := 0.0
	for lot: Dictionary in plan.lots(bi.x, bi.y):
		if lot.yard or lot.get("parking", false) or not lot.edge:
			continue
		var size: Vector2 = lot.size
		var cell_r: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
		var side := Industrial.lot_side(inner, cell_r)
		var along := size.x if side < 2 else size.y
		var depth := size.y if side < 2 else size.x
		if along < MIN_LOT.x or depth < MIN_LOT.y:
			continue
		var lot_rect := Rect2((lot.center as Vector2) - size * 0.5, size)
		if plan.macro and plan.macro.freeway and plan.macro.freeway.blocks_rect(lot_rect.grow(6.0), 3.0):
			continue
		var m := minf(along, depth)
		if m > best_size:
			best_size = m
			best = {"lot": lot, "side": side}
	if best.is_empty():
		return out
	var lot: Dictionary = best.lot
	var side: int = best.side
	var f := Industrial.frame(lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size)), side)
	var road: Array = [[CityPlan.AXIS_Z, bi.y], [CityPlan.AXIS_Z, bi.y + 1], [CityPlan.AXIS_X, bi.x], [CityPlan.AXIS_X, bi.x + 1]][side]
	var centre_u := float(f.len) * 0.5
	var edge: Vector2 = (f.o as Vector2) + (f.a as Vector2) * centre_u
	var road_pos := plan.road_pos(int(road[0]), int(road[1]))
	var front := Vector2(road_pos, edge.y) if int(road[0]) == CityPlan.AXIS_X else Vector2(edge.x, road_pos)
	out.merge({"cell": cell, "block": bi, "lot": lot, "side": side, "frame": f, "road": road, "front": front,
		"number": 1 + absi(hash([plan.seed, cell.x, cell.y, "fs_no"])) % 98})
	return out


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## Downtown's financial core is towers: no firehouse squeezed between them.
static func _core(plan: CityPlan, rect: Rect2) -> bool:
	return plan.macro.skyline_boost(rect.get_center()) > 0.5


## True when `lot` of block (bx, bz) is a station's (CityChunk._build_lot asks).
static func claims(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> bool:
	var b := plan.block(bx, bz)
	var s := for_cell(plan, _cell_of((b.rect as Rect2).get_center()))
	return not s.is_empty() and s.block == Vector2i(bx, bz) and int((s.lot as Dictionary).seed) == int(lot.seed)


## The nearest station to `goal` (true world XZ) within `reach`, or {}.
static func nearest(plan: CityPlan, goal: Vector2, reach: float) -> Dictionary:
	if plan == null:
		return {}
	var c := _cell_of(goal)
	var best: Dictionary = {}
	var best_d := reach
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var s := for_cell(plan, c + Vector2i(dx, dz))
			if s.is_empty():
				continue
			var d := (s.front as Vector2).distance_to(goal)
			if d < best_d:
				best_d = d
				best = s
	return best


## The middle of the pavement in front of the bays of the station on block (bx, bz), or INF.
static func apron_point(plan: CityPlan, bx: int, bz: int) -> Vector2:
	var b := plan.block(bx, bz)
	var s := for_cell(plan, _cell_of((b.rect as Rect2).get_center()))
	if s.is_empty() or s.block != Vector2i(bx, bz):
		return Vector2.INF
	var n: Vector2 = (s.frame as Dictionary).n
	var w := plan.road_width(int(s.road[0]), int(s.road[1]))
	return (s.front as Vector2) + n * (w * 0.5 + plan.sidewalk_width * 0.5)


## True when `p` (true world XZ) is on the kerb in front of a station's bays, which no parked car
## may block (CityChunk._park_car asks, after its rolls).
static func keeps_clear(plan: CityPlan, p: Vector2) -> bool:
	var s := nearest(plan, p, 30.0)
	if s.is_empty():
		return false
	var axis := int(s.road[0])
	var front: Vector2 = s.front
	var d := p - front
	var along := d.y if axis == CityPlan.AXIS_X else d.x
	var lat := d.x if axis == CityPlan.AXIS_X else d.y
	return absf(along) < 11.0 and absf(lat) < plan.road_width(axis, int(s.road[1])) * 0.5 + 1.5


## Where a unit out of `station` joins the street: [axis, index, dir, point (true world XZ, the
## road's centre line in front of the bays), "station"], heading toward `goal`; [] when the road
## in front is closed.
static func exit_lane(plan: CityPlan, station: Dictionary, goal: Vector2) -> Array:
	var axis := int(station.road[0])
	var index := int(station.road[1])
	var front: Vector2 = station.front
	var along := front.y if axis == CityPlan.AXIS_X else front.x
	var to := (goal.y if axis == CityPlan.AXIS_X else goal.x) - along
	if not plan.road_open(axis, index, along):
		return []
	return [axis, index, 1 if to >= 0.0 else -1, front, "station"]


# --- Building it ---------------------------------------------------------------------------------

## Builds the station on its lot in chunk `ch` (FULL: the building, doors, apron, ramp, sign;
## LOD: boxes the far city captures). Called from CityChunk._build_lot in place of a Building.
static func build_lot(ch: CityChunk, lot: Dictionary) -> void:
	var b := ch.plan.block(ch.ix, ch.iz)
	var s := for_cell(ch.plan, _cell_of((b.rect as Rect2).get_center()))
	if s.is_empty():
		return
	var f: Dictionary = s.frame
	var size: Vector2 = lot.size
	var side: int = s.side
	var along := size.x if side < 2 else size.y
	var depth := size.y if side < 2 else size.x
	var cell: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - size * 0.5, size))
	var gap_v := ((cell.size.y if side < 2 else cell.size.x) - depth) * 0.5
	var w := minf(along - 1.0, MAX_W)
	var d := minf(depth - APRON_MIN, MAX_D)
	var apron := depth - d
	# The building's front centre in the chunk's space (true world), on the pavement top.
	var a2: Vector2 = f.a
	var n2: Vector2 = f.n
	var front2: Vector2 = (f.o as Vector2) + a2 * (float(f.len) * 0.5) + n2 * (gap_v + apron)
	var g := ch._gy(front2.x, front2.y)
	var outward := Vector3(-n2.x, 0.0, -n2.y)
	var x_axis := Vector3.UP.cross(outward)
	var basis := Basis(x_axis, Vector3.UP, outward)
	var origin := Vector3(front2.x, g + CityChunk.SIDEWALK_TOP, front2.y)
	var xf := Transform3D(basis, origin)
	var total_h := BAY_H + UPPER_H
	ch._lot_rects.append(Rect2((lot.center as Vector2) - size * 0.5, size))
	if ch.level != CityChunk.Level.FULL:
		# Far: the building and its parapet as boxes (old path, no code), brick red.
		var centre := xf * Vector3(0.0, total_h * 0.5, -d * 0.5)
		var bsz := Vector3(w, total_h, d)
		var rot := basis * Basis.from_scale(Vector3(w, total_h, d))
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(rot, centre), Color(0.48, 0.22, 0.17),
				Color(0.25, 0.05, float(int(lot.seed) % 997) / 997.0, 0.0))
		ch._add_lod_shape(bsz if side < 2 else Vector3(d, total_h, w), centre)
		return
	var node := Node3D.new()
	node.name = "FireStation%d" % int(s.number)
	node.transform = xf
	node.add_to_group("fire_station")
	node.set_meta("cell", s.cell)
	ch.add_child(node)
	_build_detail(node, w, d, apron + gap_v + ch.plan.sidewalk_width, int(s.number), int(lot.seed))
	# Collision: the building (one box), so cars and the player stop at it.
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, total_h, d)
	shape.shape = box
	shape.position = Vector3(0.0, total_h * 0.5, -d * 0.5)
	body.add_child(shape)
	node.add_child(body)
	ch._occluder_boxes.append([xf, Vector3(0.0, total_h * 0.5, -d * 0.5), Vector3(w - 0.6, total_h - 0.6, d - 0.6)])
	ch.building_count += 1


## Everything a FULL chunk draws of a station, in its own frame (x along the street, +z out
## toward it, y up from the pavement; the building's front face at z = 0). `to_kerb` is how far
## the kerb is in front of the face (m): the apron and the ramp across the pavement reach it.
static func _build_detail(node: Node3D, w: float, d: float, to_kerb: float, number: int, seed_value: int) -> void:
	var g := Geo.new()
	var hb := BAY_H + UPPER_H
	var bays := BAYS
	var bay_w := BAY_DOOR.x
	var pier := (w - bay_w * float(bays) - 4.2) / float(bays + 1)
	pier = maxf(pier, 0.7)
	# The office and entry at one end, the bays in the rest.
	var bay_x0 := -w * 0.5 + 4.2 + pier
	var doors: Array[float] = []
	for i in bays:
		doors.append(bay_x0 + bay_w * 0.5 + float(i) * (bay_w + pier))
	var t := 0.32
	# Front wall: piers between and beside the bays, the header over them, the office wall.
	var dh := BAY_DOOR.y
	var edges: Array[float] = [-w * 0.5]
	for x in doors:
		edges.append(x - bay_w * 0.5)
		edges.append(x + bay_w * 0.5)
	edges.append(w * 0.5)
	for k in range(0, edges.size(), 2):
		var x0 := edges[k]
		var x1 := edges[k + 1]
		if x1 - x0 > 0.05:
			g.box("brick", Vector3((x0 + x1) * 0.5, hb * 0.5, -t * 0.5), Vector3(x1 - x0, hb, t))
	for x in doors:
		g.box("brick", Vector3(x, (dh + hb) * 0.5, -t * 0.5), Vector3(bay_w, hb - dh, t))
		# Cast-stone surround: jambs and a lintel standing proud of the brick.
		for sx: float in [-1.0, 1.0]:
			g.box("trim", Vector3(x + sx * (bay_w * 0.5 + 0.12), dh * 0.5, 0.06), Vector3(0.24, dh, 0.12))
		g.box("trim", Vector3(x, dh + 0.25, 0.07), Vector3(bay_w + 0.7, 0.5, 0.14))
		# A lamp each side of the door (lit after dark).
		for sx: float in [-1.0, 1.0]:
			g.box("lamp", Vector3(x + sx * (bay_w * 0.5 + 0.55), dh - 0.3, 0.14), Vector3(0.18, 0.26, 0.16))
	# Side and back walls.
	for sx: float in [-1.0, 1.0]:
		g.box("brick", Vector3(sx * (w * 0.5 - t * 0.5), hb * 0.5, -d * 0.5), Vector3(t, hb, d))
	g.box("brick", Vector3(0.0, hb * 0.5, -d + t * 0.5), Vector3(w, hb, t))
	# Base course, the storey band and the cornice, parapet coping.
	g.box("trim", Vector3(0.0, 0.3, 0.04), Vector3(w + 0.1, 0.6, 0.1) * Vector3(1, 1, 1))
	g.box("trim", Vector3(0.0, BAY_H + 0.1, 0.05), Vector3(w + 0.12, 0.3, 0.12))
	g.box("trim", Vector3(0.0, hb + 0.55, -d * 0.5), Vector3(w + 0.3, 0.18, d + 0.3))
	for sx: float in [-1.0, 1.0]:
		g.box("brick", Vector3(sx * (w * 0.5 - 0.15), hb + 0.25, -d * 0.5), Vector3(0.3, 0.5, d))
	g.box("brick", Vector3(0.0, hb + 0.25, -0.15), Vector3(w, 0.5, 0.3))
	g.box("brick", Vector3(0.0, hb + 0.25, -d + 0.15), Vector3(w, 0.5, 0.3))
	g.box("roof", Vector3(0.0, hb - 0.05, -d * 0.5), Vector3(w - 0.6, 0.1, d - 0.6))
	# Upper-floor windows over the bays and the office: dark glass in cream frames.
	var wn := maxi(3, int(w / 2.6))
	for k in wn:
		var x := -w * 0.5 + (float(k) + 0.5) * w / float(wn)
		g.box("glass", Vector3(x, BAY_H + 1.75, 0.02), Vector3(1.1, 1.5, 0.04))
		g.box("trim", Vector3(x, BAY_H + 0.95, 0.06), Vector3(1.3, 0.1, 0.12))
	# The office: a door with a canopy and a window at the open end.
	var ox := -w * 0.5 + 2.1
	g.box("door", Vector3(ox - 0.6, 1.1, 0.01), Vector3(1.0, 2.2, 0.05))
	g.box("glass", Vector3(ox + 0.85, 1.55, 0.01), Vector3(1.4, 1.5, 0.05))
	g.box("trim", Vector3(ox, 2.6, 0.55), Vector3(3.2, 0.15, 1.1))
	# The bays inside: floor, back and side walls, ceiling, lights - what an open door shows.
	g.box("floor", Vector3((edges[1] + edges[edges.size() - 2]) * 0.5, 0.01, -d * 0.5),
			Vector3(edges[edges.size() - 2] - edges[1], 0.02, d - t * 2.0))
	g.box("inner", Vector3((edges[1] + edges[edges.size() - 2]) * 0.5, BAY_H - 0.1, -d * 0.5),
			Vector3(edges[edges.size() - 2] - edges[1], 0.1, d - t * 2.0))
	g.box("inner", Vector3(-w * 0.5 + 4.2, BAY_H * 0.5, -d * 0.5), Vector3(0.2, BAY_H, d - t * 2.0))
	for x in doors:
		for k in 3:
			g.box("light", Vector3(x, BAY_H - 0.2, -2.5 - float(k) * 5.0), Vector3(0.4, 0.06, 1.6))
		# The parked apparatus' outline at the back of the bay: a dark shape and its lamps.
		g.box("inner", Vector3(x, 0.03, -d * 0.5), Vector3(0.12, 0.04, d - 2.0))
	# Apron and the ramp down across the pavement to the kerb.
	var apron_len := maxf(to_kerb - 0.1, 1.0)
	var ramp := 3.2
	var deck := apron_len - ramp
	if deck > 0.1:
		g.box("apron", Vector3((doors[0] + doors[doors.size() - 1]) * 0.5, -0.03, deck * 0.5),
				Vector3(doors[doors.size() - 1] - doors[0] + bay_w + 1.6, 0.1, deck))
	g.ramp(Vector3((doors[0] + doors[doors.size() - 1]) * 0.5, 0.02, deck), doors[doors.size() - 1] - doors[0] + bay_w + 1.6,
			ramp, -(CityChunk.SIDEWALK_TOP - CityChunk.ROAD_TOP) - 0.02)
	# Red "keep clear" stripes on the apron, one band per bay.
	for x in doors:
		g.box("paint", Vector3(x, 0.025, deck * 0.55), Vector3(0.12, 0.012, deck * 0.8))
	# The flagpole by the office.
	g.box("pole", Vector3(-w * 0.5 + 0.8, 4.6, 1.8), Vector3(0.09, 9.2, 0.09))
	g.box("flag", Vector3(-w * 0.5 + 1.55, 8.4, 1.8), Vector3(1.4, 0.85, 0.02))
	var mi := MeshInstance3D.new()
	mi.name = "Building"
	mi.mesh = g.commit()
	node.add_child(mi)
	# The sectional doors, one node each so they can roll up (FireStation.open_door).
	for i in doors.size():
		var door := MeshInstance3D.new()
		door.name = "BayDoor%d" % i
		door.mesh = door_mesh()
		door.position = Vector3(doors[i], 0.0, -0.12)
		door.set_meta("closed_y", 0.0)
		node.add_child(door)
		if Time.get_ticks_msec() < int(_open_until.get(node.get_meta("cell"), 0)):
			door.position.y = BAY_DOOR.y - 0.35
	# The station's name and number over the doors.
	if not OS.has_feature("web"):
		var num := MeshInstance3D.new()
		num.name = "StationNumber"
		num.mesh = BigVehicles.text_mesh("STATION %d" % number, 0.62, TRIM_CREAM)
		num.position = Vector3((doors[0] + doors[doors.size() - 1]) * 0.5, BAY_H - 0.75, 0.02)
		num.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		num.visibility_range_end = 140.0
		node.add_child(num)
		var dept := MeshInstance3D.new()
		dept.name = "Dept"
		dept.mesh = BigVehicles.text_mesh(DEPT, 0.34, Color(0.9, 0.86, 0.78))
		dept.position = Vector3(0.0, BAY_H + 0.12, 0.12)
		dept.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dept.visibility_range_end = 100.0
		node.add_child(dept)
	node.set_meta("open_until", 0.0)


## A sectional door: horizontal panels with a row of windows, painted, in its own frame (bottom
## centre at the origin, facing +z).
static func door_mesh() -> Mesh:
	if _mats.has("door_mesh"):
		return _mats.door_mesh
	var g := Geo.new()
	var w := BAY_DOOR.x
	var h := BAY_DOOR.y
	var n := 6
	for k in n:
		var y0 := h * float(k) / float(n)
		var y1 := h * float(k + 1) / float(n)
		if k == 3:
			# The window row: frames and dark glass.
			var panes := 5
			for p in panes:
				var x := -w * 0.5 + (float(p) + 0.5) * w / float(panes)
				g.box("door_glass", Vector3(x, (y0 + y1) * 0.5, 0.02), Vector3(w / float(panes) - 0.18, (y1 - y0) - 0.2, 0.02))
			g.box("door_panel", Vector3(0.0, y0 + 0.05, 0.0), Vector3(w, 0.1, 0.06))
			g.box("door_panel", Vector3(0.0, y1 - 0.05, 0.0), Vector3(w, 0.1, 0.06))
			for p in panes + 1:
				g.box("door_panel", Vector3(-w * 0.5 + float(p) * w / float(panes), (y0 + y1) * 0.5, 0.0), Vector3(0.12, y1 - y0, 0.06))
		else:
			g.box("door_panel", Vector3(0.0, (y0 + y1) * 0.5, 0.0), Vector3(w, (y1 - y0) - 0.03, 0.05))
			# The panel's raised field.
			g.box("door_panel", Vector3(0.0, (y0 + y1) * 0.5, 0.03), Vector3(w - 0.3, (y1 - y0) * 0.55, 0.012))
	var mesh := g.commit()
	_mats.door_mesh = mesh
	return mesh


## Rolls the bay doors of `station` up (they come down again DOOR_OPEN_HOLD later).
static func open_door(tree: SceneTree, station: Dictionary) -> void:
	if tree == null or station.is_empty():
		return
	_open_until[station.cell] = Time.get_ticks_msec() + int((DOOR_TIME * 2.0 + DOOR_OPEN_HOLD) * 1000.0)
	for node in tree.get_nodes_in_group("fire_station"):
		var n := node as Node3D
		if n == null or n.get_meta("cell", Vector2i(-99999, -99999)) != station.cell:
			continue
		for child in n.get_children():
			if not String(child.name).begins_with("BayDoor"):
				continue
			var door := child as Node3D
			var tw := door.create_tween()
			tw.tween_property(door, "position:y", BAY_DOOR.y - 0.35, DOOR_TIME).set_trans(Tween.TRANS_SINE)
			tw.tween_interval(DOOR_OPEN_HOLD)
			tw.tween_property(door, "position:y", 0.0, DOOR_TIME).set_trans(Tween.TRANS_SINE)


## Materials by name (shared by every station).
static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"brick":
			m = PropFactory.pbr("brick_red", 2.4, BRICK_TINT)
		"trim":
			m = PropFactory.pbr("concrete", 3.0, TRIM_CREAM)
		"roof":
			m = PropFactory.material(Color(0.42, 0.42, 0.43), 0.9)
		"apron":
			m = PropFactory.pbr("concrete", 4.0, Color(0.86, 0.85, 0.82))
		"floor":
			m = PropFactory.material(Color(0.36, 0.36, 0.36), 0.6)
		"inner":
			m = PropFactory.material(Color(0.62, 0.60, 0.55), 0.85)
		"paint":
			m = PropFactory.material(Color(0.62, 0.06, 0.04), 0.6)
		"pole":
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(0.8, 0.8, 0.82)
			pm.metallic = 0.9
			pm.roughness = 0.3
			m = pm
		"flag":
			m = PropFactory.material(Color(0.7, 0.12, 0.1), 0.8)
		"door", "door_panel":
			var dm := StandardMaterial3D.new()
			dm.albedo_color = DOOR_RED if key == "door_panel" else Color(0.15, 0.17, 0.2)
			dm.roughness = 0.35
			dm.metallic = 0.2
			m = dm
		"glass", "door_glass":
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.05, 0.06, 0.07)
			gm.roughness = 0.08
			gm.metallic = 0.4
			m = gm
		"lamp", "light":
			var lm := ShaderMaterial.new()
			lm.shader = _lamp_shader()
			lm.set_shader_parameter("strength", 3.0 if key == "light" else 5.0)
			m = lm
		_:
			m = PropFactory.material(Color(0.5, 0.5, 0.5))
	_mats[key] = m
	return m


## Lamps and bay lights: dim fittings by day, lit after dark (lamp_factor).
static func _lamp_shader() -> Shader:
	if _mats.has("lamp_shader"):
		return _mats.lamp_shader
	var sh := Shader.new()
	sh.code = """shader_type spatial;
#include "res://shaders/color_space.gdshaderinc"
global uniform float lamp_factor;
uniform float strength = 4.0;
void fragment() {
	ALBEDO = cs_out(vec3(0.75, 0.72, 0.62));
	ROUGHNESS = 0.4;
	EMISSION = cs_out(vec3(1.0, 0.86, 0.62) * strength * (0.15 + 0.85 * lamp_factor));
}
"""
	_mats.lamp_shader = sh
	return sh


## Boxes into one mesh, a surface per material (flat faces, UV in metres for the textures that
## are not triplanar).
class Geo:
	var _st: Dictionary = {}

	func _tool(key: String) -> SurfaceTool:
		if not _st.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_st[key] = st
		return _st[key]

	func box(key: String, c: Vector3, s: Vector3) -> void:
		var st := _tool(key)
		var h := s * 0.5
		var faces := [
			[Vector3.RIGHT, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
			[Vector3.LEFT, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
			[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)],
			[Vector3.DOWN, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)],
			[Vector3.BACK, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
			[Vector3.FORWARD, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
		]
		for f: Array in faces:
			_quad(st, f[0], [c + (f[1] as Vector3), c + (f[2] as Vector3), c + (f[3] as Vector3), c + (f[4] as Vector3)])

	## A slab sloping down by `drop` over `length` along +z from `at` (its high edge's centre).
	func ramp(at: Vector3, width: float, length: float, drop: float) -> void:
		var st := _tool("apron")
		var a := at + Vector3(-width * 0.5, 0.0, 0.0)
		var b := at + Vector3(width * 0.5, 0.0, 0.0)
		var c := at + Vector3(width * 0.5, drop, length)
		var d := at + Vector3(-width * 0.5, drop, length)
		var up := (c - b).cross(a - b).normalized()
		if up.y < 0.0:
			up = -up
		_quad(st, up, [a, b, c, d])
		# Flared sides down to the pavement.
		for sx: float in [-1.0, 1.0]:
			var e := at + Vector3(sx * width * 0.5, 0.0, 0.0)
			var e2 := at + Vector3(sx * (width * 0.5 + 1.0), drop, length)
			var e3 := at + Vector3(sx * width * 0.5, drop, length)
			var n := (e2 - e).cross(e3 - e).normalized()
			if n.y < 0.0:
				n = -n
			_tri(st, n, e, e2, e3)

	func _quad(st: SurfaceTool, n: Vector3, q: Array) -> void:
		_tri(st, n, q[0], q[1], q[2])
		_tri(st, n, q[0], q[2], q[3])

	func _tri(st: SurfaceTool, n: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
		# Clockwise seen from the side `n` points to (Godot's front faces).
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		for v: Vector3 in [a, b, c]:
			st.set_normal(n)
			var uv := Vector2(v.x + v.z, v.y) if absf(n.y) < 0.5 else Vector2(v.x, v.z)
			st.set_uv(uv)
			st.add_vertex(v)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key: String in _st:
			var st: SurfaceTool = _st[key]
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, FireStation.material(key))
		return mesh
