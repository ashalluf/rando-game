class_name StreetRoute
extends RefCounted
## Routes along the city's street grid (owner, 2026-09-24: "GTA-level street life"), for the
## police: a cruiser used to steer straight at the player under physics, so a player on a roof,
## or deep in a block, got a cruiser nosing into the nearest wall. Now it drives the streets to
## the kerb nearest the player and pulls up there.
##
## The graph is CityPlan's own grid: a node is an intersection (ix, iz) - the crossing of AXIS_X
## road ix and AXIS_Z road iz - and an edge is the stretch of road between two neighbouring
## ones, drivable when it stays on city ground. A* over it, bounded to a box round the two
## ends, a few hundred nodes at most; a cruiser asks twice a second. Static, no state but a
## small cache of which stretches are drivable.
##
## Directions follow TrafficManager: a car on AXIS_X road `index` drives along z, `dir` +1 toward
## +z, and keeps right, so its lane is on the -x side when dir is +1. On an AXIS_Z road it drives
## along x and its lane is on the +z side when dir is +1.

## Most nodes a search expands before it gives up (the box round the ends is smaller anyway).
const MAX_EXPAND := 900
## Extra intersections searched round the box spanned by the start and the goal.
const BOX_MARGIN := 3
## A U-turn costs as much as this many metres more (a cruiser can make one; it should not want to).
const U_TURN_COST := 70.0
## A stop is kept this far from the crossing roads at either end of its stretch (m).
const STOP_CLEAR := 9.0

static var _drivable_cache: Dictionary = {}


## The intersection a car on (axis, index, dir) at `along` comes to next.
static func next_node(plan: CityPlan, axis: int, index: int, dir: int, along: float) -> Vector2i:
	var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var ci := plan._index_at(cross_axis, along) + (1 if dir > 0 else 0)
	return Vector2i(index, ci) if axis == CityPlan.AXIS_X else Vector2i(ci, index)


## World XZ of an intersection's centre.
static func node_pos(plan: CityPlan, n: Vector2i) -> Vector2:
	return Vector2(plan.road_pos(CityPlan.AXIS_X, n.x), plan.road_pos(CityPlan.AXIS_Z, n.y))


## The road leaving node `a` for its neighbour `b`: [axis, index, dir].
static func edge(a: Vector2i, b: Vector2i) -> Array:
	if a.x == b.x:
		return [CityPlan.AXIS_X, a.x, 1 if b.y > a.y else -1]
	return [CityPlan.AXIS_Z, a.y, 1 if b.x > a.x else -1]


## Which side of its road a lane of `dir` keeps to: the sign of its offset from the centre line.
static func lane_side(axis: int, dir: int) -> float:
	return float(-dir) if axis == CityPlan.AXIS_X else float(dir)


## True when the stretch of road between neighbouring nodes `a` and `b` stays on city ground
## (city or beach zone, as far as the traffic drives).
static func drivable(plan: CityPlan, a: Vector2i, b: Vector2i) -> bool:
	var key := Vector4i(mini(a.x, b.x), mini(a.y, b.y), maxi(a.x, b.x), maxi(a.y, b.y))
	var cached: Variant = _drivable_cache.get(key)
	if cached != null:
		return cached
	var pa := node_pos(plan, a)
	var pb := node_pos(plan, b)
	var ok := true
	for f: float in [0.2, 0.5, 0.8]:
		var z := plan.zone_at(pa.lerp(pb, f))
		if z != MacroMap.Zone.CITY and z != MacroMap.Zone.BEACH:
			ok = false
			break
	if _drivable_cache.size() > 20000:
		_drivable_cache.clear()
	_drivable_cache[key] = ok
	return ok


## Where to pull up for a goal at world XZ `goal`: on the road nearest it, in the lane whose kerb
## is on the goal's side, level with it (kept clear of the crossings at either end). A goal on
## the carriageway itself - somebody standing in the road - is stopped `short` metres before.
## {axis, index, dir, along, lateral (offset from the centre line of the stopping spot), stop
## (world XZ), entry (the node a car enters that stretch through), on_road} or {} off the grid.
static func kerb_stop(plan: CityPlan, goal: Vector2, short: float = 12.0) -> Dictionary:
	var best := {}
	var best_d := INF
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var across := goal.x if axis == CityPlan.AXIS_X else goal.y
		var i0 := plan._index_at(axis, across)
		for index: int in [i0, i0 + 1]:
			var road := plan.road_pos(axis, index)
			var width := plan.road_width(axis, index)
			var off := across - road
			var d := maxf(absf(off) - width * 0.5, 0.0)
			if d >= best_d:
				continue
			var along := goal.y if axis == CityPlan.AXIS_X else goal.x
			var p := Vector2(road, along) if axis == CityPlan.AXIS_X else Vector2(along, road)
			var zone := plan.zone_at(p)
			if zone != MacroMap.Zone.CITY and zone != MacroMap.Zone.BEACH:
				continue
			best_d = d
			best = {"axis": axis, "index": index, "off": off, "along": along, "width": width}
	if best.is_empty():
		return {}
	var axis: int = best.axis
	var index: int = best.index
	var width: float = best.width
	var off: float = best.off
	var side := 1.0 if off >= 0.0 else -1.0
	# The lane whose kerb is on the goal's side: right-hand traffic.
	var dir := int(-side) if axis == CityPlan.AXIS_X else int(side)
	var on_road := absf(off) < width * 0.5
	var along: float = best.along
	if on_road:
		along -= float(dir) * short
	# Kept clear of the crossing roads at both ends of this stretch.
	var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var j := plan._index_at(cross_axis, along)
	var lo := plan.road_pos(cross_axis, j) + plan.road_width(cross_axis, j) * 0.5 + STOP_CLEAR
	var hi := plan.road_pos(cross_axis, j + 1) - plan.road_width(cross_axis, j + 1) * 0.5 - STOP_CLEAR
	along = clampf(along, lo, hi) if hi > lo else (lo + hi) * 0.5
	# Just inside the parked cars: double-parked, which is what a cruiser at a call does.
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	var lateral := maxf(CityPlan.parking_offset(width) - 2.4, CityPlan.lane_center(width, lanes, lanes - 1)) * lane_side(axis, dir)
	var road_pos := plan.road_pos(axis, index)
	var stop := Vector2(road_pos + lateral, along) if axis == CityPlan.AXIS_X else Vector2(along, road_pos + lateral)
	var entry_cross := j if dir > 0 else j + 1
	var entry := Vector2i(index, entry_cross) if axis == CityPlan.AXIS_X else Vector2i(entry_cross, index)
	return {"axis": axis, "index": index, "dir": dir, "along": along, "lateral": lateral, "stop": stop, "entry": entry, "on_road": on_road}


## Nodes from `start` to `goal` inclusive, A* over the drivable grid, or [] when there is no
## way (or it is too far to look). `arrive` is the direction the path must leave `goal` in,
## [axis, index, dir], so a path that would reach it only to turn round is charged the U-turn;
## `first` the road a car at `start` arrives on, likewise for its first move.
static func path(plan: CityPlan, start: Vector2i, goal: Vector2i, first: Array = [], arrive: Array = []) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if start == goal:
		out.append(start)
		return out
	var lo := Vector2i(mini(start.x, goal.x) - BOX_MARGIN, mini(start.y, goal.y) - BOX_MARGIN)
	var hi := Vector2i(maxi(start.x, goal.x) + BOX_MARGIN, maxi(start.y, goal.y) + BOX_MARGIN)
	var gp := node_pos(plan, goal)
	var open: Array[Vector2i] = [start]
	var g := {start: 0.0}
	var came := {}
	var closed := {}
	var expanded := 0
	while not open.is_empty() and expanded < MAX_EXPAND:
		# The open set is small; a linear pick of the best is cheaper than a heap in GDScript.
		var bi := 0
		var bf := INF
		for k in open.size():
			var n: Vector2i = open[k]
			var f: float = float(g[n]) + node_pos(plan, n).distance_to(gp)
			if f < bf:
				bf = f
				bi = k
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if cur == goal:
			var n2 := cur
			while n2 != start:
				out.push_front(n2)
				n2 = came[n2]
			out.push_front(start)
			return out
		if closed.has(cur):
			continue
		closed[cur] = true
		expanded += 1
		var cp := node_pos(plan, cur)
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb := cur + step
			if nb.x < lo.x or nb.y < lo.y or nb.x > hi.x or nb.y > hi.y or closed.has(nb):
				continue
			if not drivable(plan, cur, nb):
				continue
			var cost := float(g[cur]) + cp.distance_to(node_pos(plan, nb))
			# Turning round: back the way we came into this node.
			var into: Array = first if cur == start else edge(came.get(cur, cur), cur) if came.has(cur) else []
			var leave := edge(cur, nb)
			if not into.is_empty() and int(into[0]) == int(leave[0]) and int(into[1]) == int(leave[1]) and int(into[2]) != int(leave[2]):
				cost += U_TURN_COST
			if nb == goal and not arrive.is_empty():
				var last := edge(cur, nb)
				if int(last[0]) == int(arrive[0]) and int(last[1]) == int(arrive[1]) and int(last[2]) != int(arrive[2]):
					cost += U_TURN_COST
			if cost < float(g.get(nb, INF)):
				g[nb] = cost
				came[nb] = cur
				open.append(nb)
	return out


## Where a car at world XZ `p` heading `heading` is on the grid: the road it is on (the one
## its heading runs along, when it is in a junction), {axis, index, dir, along}, or {}.
static func locate(plan: CityPlan, p: Vector2, heading: Vector2) -> Dictionary:
	var along_z := absf(heading.y) >= absf(heading.x)
	var best := {}
	var best_d := INF
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var across := p.x if axis == CityPlan.AXIS_X else p.y
		var i0 := plan._index_at(axis, across)
		for index: int in [i0, i0 + 1]:
			var d := absf(across - plan.road_pos(axis, index)) - plan.road_width(axis, index) * 0.5
			# Prefer the road the car is pointing along: it may be inside the other one's junction.
			if (axis == CityPlan.AXIS_X) != along_z:
				d += 6.0
			if d < best_d:
				best_d = d
				var h := heading.y if axis == CityPlan.AXIS_X else heading.x
				best = {"axis": axis, "index": index, "dir": 1 if h >= 0.0 else -1, "along": p.y if axis == CityPlan.AXIS_X else p.x}
	return best if best_d < 14.0 else {}


## The lane line of (axis, index, dir) `offset` metres out from the centre line, as the world XZ
## at `along`.
static func lane_point(plan: CityPlan, axis: int, index: int, dir: int, offset: float, along: float) -> Vector2:
	var lat := plan.road_pos(axis, index) + offset * lane_side(axis, dir)
	return Vector2(lat, along) if axis == CityPlan.AXIS_X else Vector2(along, lat)


## A drive as a polyline of world XZ points along the lanes, `offset` metres out from the centre
## lines: from `from` (the car on road `road` = [axis, index, dir]) through `nodes` (from the next
## one, ending at the destination's entry) to the destination `dest` (kerb_stop()). A point at
## every turn, where the two lanes cross; two at a U-turn.
static func polyline(plan: CityPlan, from: Vector2, road: Array, nodes: Array[Vector2i], dest: Dictionary, offset: float) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var cur := road.duplicate()
	for k in nodes.size():
		var n: Vector2i = nodes[k]
		var out: Array = edge(n, nodes[k + 1]) if k + 1 < nodes.size() else [dest.axis, dest.index, dest.dir]
		if int(out[0]) == int(cur[0]) and int(out[1]) == int(cur[1]) and int(out[2]) == int(cur[2]):
			continue
		var np := node_pos(plan, n)
		if int(out[0]) == int(cur[0]):
			# Round in the junction: our lane at its middle, then the other carriageway's.
			var at := np.y if int(cur[0]) == CityPlan.AXIS_X else np.x
			pts.append(lane_point(plan, int(cur[0]), int(cur[1]), int(cur[2]), offset, at))
			pts.append(lane_point(plan, int(out[0]), int(out[1]), int(out[2]), offset, at))
		else:
			# Where the two lane lines cross.
			var a := lane_point(plan, int(cur[0]), int(cur[1]), int(cur[2]), offset, 0.0)
			var b := lane_point(plan, int(out[0]), int(out[1]), int(out[2]), offset, 0.0)
			pts.append(Vector2(a.x, b.y) if int(cur[0]) == CityPlan.AXIS_X else Vector2(b.x, a.y))
		cur = out
	pts.append(dest.stop)
	return pts
