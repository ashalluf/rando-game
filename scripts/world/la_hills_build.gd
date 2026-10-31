class_name LaHillsBuild
extends RefCounted
## The public stairways LaHills turns the too-steep street stretches into (Los Angeles' hillside
## stairs: a narrow concrete flight up the middle of what was the street, cheek walls and pipe rails,
## ivy and shrubs on the banks either side). CityChunk._build_roads() calls stretch() for a closed
## stretch on its +X or +Z side, and junction() for a crossing both of whose arms are stairs.
##
## The ground under the whole stretch is a relief-following slab with collision (the player walks
## the ramp; the steps stand on it, quantised to RISER, so a step never sinks under the slope).
## FULL chunks add the flight, its cheeks and rails as ONE LandmarkGeo mesh on the footbridges'
## shader (FootbridgeKit: concrete, walking grit, nosings, paint); LOD chunks and the far city get
## the slab.

## The flight: its width, the riser it is quantised to, the cheek walls, the rail.
const WIDTH := 3.0
const RISER := 0.165
const CHEEK_W := 0.28
const CHEEK_H := 0.32
const RAIL_H := 0.92
const POST_EVERY := 2.6
## Paint and concrete (sRGB, the footbridge shader decodes them).
const RAIL_PAINT := Color(0.16, 0.25, 0.19)
const CONCRETE := Color(0.80, 0.78, 0.74)
## The banks either side: an ivy / ice plant slab (linear-ish tint over the grass set).
const BANK_TINT := Color(0.42, 0.55, 0.32)

static var _bank_mat: Material


static func _bank_material() -> Material:
	if _bank_mat == null:
		_bank_mat = PropFactory.pbr("grass", 3.0, BANK_TINT)
	return _bank_mat


## The stretch of road `r` (the carriageway's rect between the two junction squares) on `axis`:
## a stairway. Called by CityChunk._build_roads() in place of the road slab.
static func stretch(ch: CityChunk, axis: int, r: Rect2) -> void:
	# The ground: banks over the whole stretch, a pavement-high slab with collision.
	ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP * 0.5, r.get_center().y),
		Vector3(r.size.x, CityChunk.SIDEWALK_TOP, r.size.y), BANK_TINT, true, _bank_material())
	if ch.capturing or ch.level != CityChunk.Level.FULL:
		return
	var along_x := axis == CityPlan.AXIS_Z
	var c := r.get_center()
	var s0 := r.position.x if along_x else r.position.y
	var s1 := r.end.x if along_x else r.end.y
	var mid := c.y if along_x else c.x
	var o := Vector3(c.x, 0.0, c.y)
	var g := LandmarkGeo.new()
	g.use("fb", FootbridgeKit.material())
	_flight(g, ch, along_x, mid, s0, s1, o)
	var mi := g.commit(ch, "HillStairs", true, 260.0)
	if mi:
		mi.position = o


## A crossing whose arms are all stairs: the bank slab over the square.
static func junction(ch: CityChunk, r: Rect2) -> void:
	ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP * 0.5, r.get_center().y),
		Vector3(r.size.x, CityChunk.SIDEWALK_TOP, r.size.y), BANK_TINT, true, _bank_material())


static func _p(along_x: bool, s: float, t: float) -> Vector2:
	return Vector2(s, t) if along_x else Vector2(t, s)


static func _ground(ch: CityChunk, along_x: bool, s: float, t: float) -> float:
	var p := _p(along_x, s, t)
	return ch._gy(p.x, p.y) + CityChunk.SIDEWALK_TOP


## The flight from s0 to s1 along the stretch's centre line `mid`: treads grouped by quantised
## level (a gentle stretch is a landing), risers between, cheek walls and rails each side.
static func _flight(g: LandmarkGeo, ch: CityChunk, along_x: bool, mid: float, s0: float, s1: float, o: Vector3) -> void:
	var ds := 0.05
	var hmin := INF
	var n := int(ceil((s1 - s0) / ds))
	var hs := PackedFloat32Array()
	for i in n + 1:
		var s := s0 + (s1 - s0) * float(i) / float(n)
		var hh := _ground(ch, along_x, s, mid)
		hs.append(hh)
		hmin = minf(hmin, hh)
	# Groups of equal level: [s_a, s_b, y].
	var groups: Array = []
	var cur := -1
	var sa := s0
	for i in n + 1:
		var lv := int(ceil((hs[i] - hmin) / RISER + 0.02))
		if i == 0:
			cur = lv
			continue
		if lv != cur or i == n:
			var s := s0 + (s1 - s0) * float(i) / float(n)
			groups.append([sa, s, hmin + float(cur) * RISER])
			sa = s
			cur = lv
	if groups.is_empty():
		return
	var half := WIDTH * 0.5
	var up := Vector3.UP
	var dir3 := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var white := Color(1, 1, 1)
	for gi in groups.size():
		var gr: Array = groups[gi]
		var a: float = gr[0]
		var b: float = gr[1]
		var y: float = gr[2]
		# The tread.
		var q0 := _p(along_x, a, mid - half)
		var q1 := _p(along_x, a, mid + half)
		var q2 := _p(along_x, b, mid + half)
		var q3 := _p(along_x, b, mid - half)
		g.quad("fb", _v(q0, y, o), _v(q1, y, o), _v(q2, y, o), _v(q3, y, o), up,
			Vector2(0, 0), Vector2(WIDTH, 0), Vector2(WIDTH, b - a), Vector2(0, b - a), FootbridgeKit.kc(white, FootbridgeKit.K_WALK))
		# The riser to the next tread, facing the lower side.
		if gi + 1 < groups.size():
			var y2: float = groups[gi + 1][2]
			if absf(y2 - y) > 0.01:
				var lo := minf(y, y2)
				var hi := maxf(y, y2)
				var face := -dir3 if y2 > y else dir3
				var r0 := _p(along_x, b, mid - half)
				var r1 := _p(along_x, b, mid + half)
				g.quad("fb", _v(r0, hi, o), _v(r1, hi, o), _v(r1, lo, o), _v(r0, lo, o), face,
					Vector2(0, hi), Vector2(WIDTH, hi), Vector2(WIDTH, lo), Vector2(0, lo), FootbridgeKit.kc(white, FootbridgeKit.K_CONCRETE))
				# The nosing on the higher tread's front edge.
				var ns := b + (0.05 if y2 > y else -0.05)
				var n0 := _p(along_x, b, mid - half * 0.94)
				var n1 := _p(along_x, b, mid + half * 0.94)
				var n2 := _p(along_x, ns, mid + half * 0.94)
				var n3 := _p(along_x, ns, mid - half * 0.94)
				g.quad("fb", _v(n0, hi + 0.004, o), _v(n1, hi + 0.004, o), _v(n2, hi + 0.004, o), _v(n3, hi + 0.004, o), up,
					Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.05), Vector2(0, 0.05), FootbridgeKit.kc(white, FootbridgeKit.K_NOSING))
		# The cheek walls: a block each side over the tread, from below the ground to over it.
		for side: float in [-1.0, 1.0]:
			var t := mid + side * (half + CHEEK_W * 0.5)
			var gl := minf(_ground(ch, along_x, a, t), _ground(ch, along_x, b, t)) - 0.35
			var top := y + CHEEK_H
			var cc := _p(along_x, (a + b) * 0.5, t)
			var size := Vector3(b - a, top - gl, CHEEK_W) if along_x else Vector3(CHEEK_W, top - gl, b - a)
			g.box("fb", Vector3(cc.x, (top + gl) * 0.5, cc.y) - o, size, FootbridgeKit.kc(CONCRETE, FootbridgeKit.K_CONCRETE))
	# Pipe rails on posts along both cheeks, following the treads.
	var posts := maxi(int(ceil((s1 - s0) / POST_EVERY)), 1)
	for side: float in [-1.0, 1.0]:
		var t := mid + side * (half + CHEEK_W * 0.5)
		var prev := Vector3.INF
		for i in posts + 1:
			var s := lerpf(s0 + 0.4, s1 - 0.4, float(i) / float(posts))
			var y := _level_at(groups, s) + CHEEK_H
			var p := _p(along_x, s, t)
			var foot := Vector3(p.x, y, p.y) - o
			var head := foot + Vector3(0, RAIL_H, 0)
			_tube(g, foot, head, 0.03, RAIL_PAINT)
			if prev != Vector3.INF:
				_tube(g, prev, head, 0.026, RAIL_PAINT)
			prev = head


static func _level_at(groups: Array, s: float) -> float:
	for gr: Array in groups:
		if s >= float(gr[0]) - 0.001 and s <= float(gr[1]) + 0.001:
			return gr[2]
	return float(groups[-1][2])


static func _v(p: Vector2, y: float, o: Vector3) -> Vector3:
	return Vector3(p.x, y, p.y) - o


static func _tube(g: LandmarkGeo, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var z := b - a
	var length := z.length()
	if length < 0.01:
		return
	z /= length
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-4:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x)
	var c := FootbridgeKit.kc(col, FootbridgeKit.K_PAINT)
	var sides := 6
	for s in sides:
		var t0 := TAU * float(s) / float(sides)
		var t1 := TAU * float(s + 1) / float(sides)
		var n0 := x * cos(t0) + y * sin(t0)
		var n1 := x * cos(t1) + y * sin(t1)
		var p0 := a + n0 * r
		var p1 := a + n1 * r
		g.quad_n("fb", p0, p1, p1 + z * length, p0 + z * length, n0, n1, n1, n0,
			Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, length), Vector2(0, length), c)
