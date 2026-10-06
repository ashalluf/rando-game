class_name GpsRoute
extends RefCounted
## A GPS route along the street grid, from a point to a waypoint (the full-screen map and the
## minimap draw it; WorldMap asks for a new one when the player leaves it).
##
## The graph is StreetRoute's: a node is an intersection (ix, iz), an edge the stretch of road to
## a neighbour, drivable when StreetRoute.drivable() (city ground) and CityPlan.road_open() (not
## through MacArthur Park, not across the river where there is no bridge). Unlike StreetRoute.path()
## - a cruiser's few hundred nodes in a box round the ends - this one crosses the basin, so it is
## A* on a binary heap with no box, run a slice at a time (step(), a budget in microseconds), and
## it prefers the avenues the way a driver does (AVENUE_COST). Both ends are snapped to the road
## nearest them and enter the graph at either end of their stretch (the cheaper one wins), so a
## route never runs to the far corner and back.

## An avenue's metre costs this much of a street's.
const AVENUE_COST := 0.8
## Most nodes one search expands before it gives up.
const MAX_EXPAND := 40000
## Points closer than this along a straight run are merged out of the drawn line (m).
const MERGE := 0.5

var plan: CityPlan
var from: Vector2
var to: Vector2
## The route as world XZ points, from `from` to `to` (empty until done, or when there is none).
var points := PackedVector2Array()
var length: float = 0.0
var done := false
var ok := false
var expanded: int = 0

var _start: Dictionary
var _goal: Dictionary
var _heap_f := PackedFloat32Array()
var _heap_n: Array[Vector2i] = []
var _g: Dictionary = {}
var _came: Dictionary = {}
var _closed: Dictionary = {}
var _best_cost := INF
var _best_node := Vector2i.ZERO
var _gp: Vector2


func _init(p: CityPlan, a: Vector2, b: Vector2) -> void:
	plan = p
	from = a
	to = b
	_start = snap(plan, a)
	_goal = snap(plan, b)
	if _start.is_empty() or _goal.is_empty():
		done = true
		return
	_gp = _goal.point
	# Both ends of the start's stretch are sources, at the distance along the road to them.
	for k in 2:
		var n: Vector2i = _start.nodes[k]
		var d: float = float(_start.dist[k]) * _cost_factor(int(_start.axis), int(_start.index))
		if d < float(_g.get(n, INF)):
			_g[n] = d
			_came[n] = n
			_push(n, d + StreetRoute.node_pos(plan, n).distance_to(_gp))
	# A start and goal on the same stretch: straight there, unless the grid says otherwise.
	if int(_start.axis) == int(_goal.axis) and int(_start.index) == int(_goal.index) \
			and _start.nodes == _goal.nodes:
		_best_cost = (_start.point as Vector2).distance_to(_goal.point) * _cost_factor(int(_start.axis), int(_start.index))
		_best_node = Vector2i(-999999, -999999)


## The road nearest world XZ `p` on city ground: {axis, index, point (on the centre line),
## nodes: [the two intersections at the ends of its stretch], dist: [metres to each]} or {}.
static func snap(p_plan: CityPlan, p: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var across := p.x if axis == CityPlan.AXIS_X else p.y
		var along := p.y if axis == CityPlan.AXIS_X else p.x
		var i0 := p_plan._index_at(axis, across)
		var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
		var j := p_plan._index_at(cross_axis, along)
		for index: int in [i0, i0 + 1]:
			var road := p_plan.road_pos(axis, index)
			var d := absf(across - road)
			if d >= best_d:
				continue
			var a := Vector2i(index, j) if axis == CityPlan.AXIS_X else Vector2i(j, index)
			var b := Vector2i(index, j + 1) if axis == CityPlan.AXIS_X else Vector2i(j + 1, index)
			if not edge_ok(p_plan, a, b):
				continue
			var lo := p_plan.road_pos(cross_axis, j)
			var hi := p_plan.road_pos(cross_axis, j + 1)
			var t := clampf(along, lo, hi)
			best_d = d
			var pt := Vector2(road, t) if axis == CityPlan.AXIS_X else Vector2(t, road)
			best = {"axis": axis, "index": index, "point": pt, "nodes": [a, b], "dist": [t - lo, hi - t]}
	return best


## True when a car may drive the stretch between neighbouring intersections `a` and `b`.
static func edge_ok(p_plan: CityPlan, a: Vector2i, b: Vector2i) -> bool:
	if not StreetRoute.drivable(p_plan, a, b):
		return false
	var mid := (StreetRoute.node_pos(p_plan, a) + StreetRoute.node_pos(p_plan, b)) * 0.5
	if a.x == b.x:
		return p_plan.road_open(CityPlan.AXIS_X, a.x, mid.y)
	return p_plan.road_open(CityPlan.AXIS_Z, a.y, mid.x)


func _cost_factor(axis: int, index: int) -> float:
	return AVENUE_COST if plan.road_width(axis, index) > plan.street_width + 1.0 else 1.0


## Runs the search for up to `budget_usec`; true once it is done (see `ok`).
func step(budget_usec: int) -> bool:
	if done:
		return true
	var t0 := Time.get_ticks_usec()
	while not _heap_n.is_empty():
		var f := _heap_f[0]
		if f >= _best_cost:
			break
		var cur := _pop()
		if _closed.has(cur):
			continue
		_closed[cur] = true
		expanded += 1
		if expanded > MAX_EXPAND:
			break
		var gc: float = _g[cur]
		# Reaching either end of the goal's stretch: the rest is along it.
		for k in 2:
			if cur == _goal.nodes[k]:
				var total := gc + float(_goal.dist[k]) * _cost_factor(int(_goal.axis), int(_goal.index))
				if total < _best_cost:
					_best_cost = total
					_best_node = cur
		var cp := StreetRoute.node_pos(plan, cur)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb := cur + d
			if _closed.has(nb) or not edge_ok(plan, cur, nb):
				continue
			var e := StreetRoute.edge(cur, nb)
			var np := StreetRoute.node_pos(plan, nb)
			var cost := gc + cp.distance_to(np) * _cost_factor(int(e[0]), int(e[1]))
			if cost < float(_g.get(nb, INF)):
				_g[nb] = cost
				_came[nb] = cur
				_push(nb, cost + np.distance_to(_gp) * AVENUE_COST)
		if Time.get_ticks_usec() - t0 > budget_usec:
			return false
	_finish()
	return true


func _finish() -> void:
	done = true
	if _best_cost == INF:
		return
	ok = true
	var pts := PackedVector2Array([from, _start.point])
	if _best_node != Vector2i(-999999, -999999):
		var chain: Array[Vector2i] = []
		var n := _best_node
		while true:
			chain.push_front(n)
			var prev: Vector2i = _came[n]
			if prev == n:
				break
			n = prev
		for c in chain:
			pts.append(StreetRoute.node_pos(plan, c))
	pts.append(_goal.point)
	pts.append(to)
	points = _simplify(pts)
	length = 0.0
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])


## Drops repeated points and the middle of straight runs.
static func _simplify(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		if not out.is_empty() and out[out.size() - 1].distance_to(p) < MERGE:
			continue
		if out.size() >= 2:
			var a := out[out.size() - 2]
			var b := out[out.size() - 1]
			if absf((b - a).normalized().cross((p - b).normalized())) < 0.001 and (b - a).dot(p - b) > 0.0:
				out[out.size() - 1] = p
				continue
		out.append(p)
	return out


## Distance from `p` to the route's line, and the index of the segment nearest it.
func nearest(p: Vector2) -> Vector2:
	var best := INF
	var bi := 0
	for i in points.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1])
		var d := q.distance_to(p)
		if d < best:
			best = d
			bi = i
	return Vector2(best, bi)


# --- A binary min-heap on f ---------------------------------------------------------------------

func _push(n: Vector2i, f: float) -> void:
	_heap_f.append(f)
	_heap_n.append(n)
	var i := _heap_f.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _heap_f[p] <= _heap_f[i]:
			break
		_swap(i, p)
		i = p


func _pop() -> Vector2i:
	var top := _heap_n[0]
	var last := _heap_f.size() - 1
	_swap(0, last)
	_heap_f.resize(last)
	_heap_n.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= last:
			break
		var m := l
		if l + 1 < last and _heap_f[l + 1] < _heap_f[l]:
			m = l + 1
		if _heap_f[i] <= _heap_f[m]:
			break
		_swap(i, m)
		i = m
	return top


func _swap(a: int, b: int) -> void:
	var f := _heap_f[a]
	_heap_f[a] = _heap_f[b]
	_heap_f[b] = f
	var n := _heap_n[a]
	_heap_n[a] = _heap_n[b]
	_heap_n[b] = n
