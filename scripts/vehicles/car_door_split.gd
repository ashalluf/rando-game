class_name CarDoorSplit
extends RefCounted
## The front doors of the everyday bodies (tools/make_road_cars.py, tools/make_more_cars.py) cut
## out of the body model as their own meshes, so they can swing on their hinges and come off in a
## crash (CarInterior). The Blender run cut every door's shut line as a 4 mm groove; DOORS is those
## same lines, copied from the specs in their own coordinates (`along` the car with the nose at +,
## height over the ground), which is the body MESH's space turned: mesh x = x, y = height,
## z = -along (the glTF exporter's Y-up turn, no recentring - tools/car_cabins/model_probe.gd).
##
## A triangle is the door's when its centroid is on that side of the car, past XMIN, and either
## inside the door's side-view outline below the glass (the groove lines) or inside the side
## window's outline above it (the door glass's own hull, grown by FRAME: the frame round the glass
## and its liner go with the door). Everything else stays on the body. The body keeps its surfaces
## in their order (CarDamage and the cabin glass address them by index); a door has only the
## surfaces it has triangles on, `surf_map` naming each one's surface on the body.
##
## Classifying ~55k triangles is ~150 ms of GDScript, so it is a JOB stepped in slices
## (step(), CarInteriors runs it inside a budget) and kept per body type for the session. Mesh data
## is not kept by the headless dummy renderer: there a job finishes at once with no doors
## (`real` false), and CarInterior builds its cabin and door cards without the skin.

## Door outlines in (along, height) metres, per body type: "front" the front shut line from the
## belt down to the sill, "rear" the rear shut line's along (the B-pillar), "sill" its foot; or
## "poly" a whole outline (the van's cab door, whose groove runs up its frame to the roof).
const DOORS := {
	Vehicle.BodyType.SEDAN: {"front": [Vector2(1.00, 0.945), Vector2(0.995, 0.80), Vector2(0.985, 0.55), Vector2(0.98, 0.30)], "rear": -0.098, "sill": 0.30},
	Vehicle.BodyType.TAXI: {"front": [Vector2(1.00, 0.945), Vector2(0.995, 0.80), Vector2(0.985, 0.55), Vector2(0.98, 0.30)], "rear": -0.098, "sill": 0.30},
	Vehicle.BodyType.CROSSOVER: {"front": [Vector2(1.00, 1.05), Vector2(0.99, 0.80), Vector2(0.98, 0.60), Vector2(0.975, 0.42)], "rear": -0.285, "sill": 0.42},
	Vehicle.BodyType.PICKUP: {"front": [Vector2(1.080, 1.340), Vector2(1.070, 1.00), Vector2(1.062, 0.75), Vector2(1.058, 0.50)], "rear": -0.115, "sill": 0.50},
	Vehicle.BodyType.HATCHBACK: {"front": [Vector2(0.835, 0.95), Vector2(0.828, 0.70), Vector2(0.820, 0.40), Vector2(0.815, 0.27)], "rear": -0.352, "sill": 0.27},
	Vehicle.BodyType.SUV: {"front": [Vector2(0.995, 1.28), Vector2(0.985, 1.00), Vector2(0.975, 0.70), Vector2(0.970, 0.44)], "rear": -0.425, "sill": 0.44},
	Vehicle.BodyType.MINIVAN: {"front": [Vector2(1.355, 1.12), Vector2(1.345, 0.90), Vector2(1.335, 0.60), Vector2(1.330, 0.32)], "rear": 0.005, "sill": 0.32},
	Vehicle.BodyType.BEATER: {"front": [Vector2(0.905, 0.850), Vector2(0.900, 0.60), Vector2(0.895, 0.30), Vector2(0.890, 0.24)], "rear": -0.180, "sill": 0.24},
	Vehicle.BodyType.VAN: {"van": true},
	Vehicle.BodyType.DELIVERY_VAN: {"van": true},
}
## A door triangle's centroid is at least this far off the centre line (m): the skin, the glass and
## the window liner, never the floor or the roof's middle.
const XMIN := 0.42
## The side window's outline grows by this to take the frame and the liner round the glass (m).
const FRAME := 0.032
## The glass and frame above the belt start this far under the door glass's lowest point (m).
const BELT_SLACK := 0.03
## Painted skin above the door glass's foot goes with the door only this high (m): the belt.
const PAINT_OVER_BELT := 0.04
## A part longer than this (m) is not moved whole (see _whole_parts()), nor one thinner than
## STRIP_HEIGHT (a moulding along both doors, cut where it crosses the shut line).
const WHOLE_SPAN := 1.0
const STRIP_HEIGHT := 0.06
## A part bigger than the door whose mean width (area over its box's diagonal) is under this (m)
## is a strip or a ring, cut where it crosses rather than kept whole on the body.
const STRIP_WIDTH := 0.05
## Triangles classified per slice before the job checks its budget.
const SLICE := 2048

## Finished splits per body type: {"real", "body": ArrayMesh, "doors": [door, ...]}, a door being
## {"side": -1 / 1, "mesh": ArrayMesh, "surf_map": PackedInt32Array, "hinge": Vector3,
## "skin_x": |x| of the door skin, "front": along at the belt, "rear", "sill", "top": door glass top,
## "belt": door glass bottom, "lower": PackedVector2Array (the outline below the glass)}.
static var _done: Dictionary = {}
## step() runs the arithmetic on a worker thread (now() never does).
static var threaded: bool = true
static var _jobs: Dictionary = {}


static func supported(type: int) -> bool:
	return DOORS.has(type)


## The van's cab door outline (make_road_cars.py van_details: down the front edge and round the
## front arch, along the sill, up the B-pillar, along the top of its frame).
static func van_outline() -> PackedVector2Array:
	var out := PackedVector2Array([Vector2(1.705, 2.065), Vector2(2.225, 1.205), Vector2(2.17, 0.95)])
	for k in 13:
		var a := deg_to_rad(84.0 + (172.0 - 84.0) * float(k) / 12.0)
		out.append(Vector2(2.10 + 0.475 * cos(a), 0.36 + 0.475 * sin(a)))
	out.append(Vector2(1.27, 0.42))
	out.append(Vector2(1.27, 2.065))
	return out


## The door's outline below the glass, closed, in (along, height).
static func lower_outline(type: int) -> PackedVector2Array:
	var d: Dictionary = DOORS[type]
	if d.has("van"):
		return van_outline()
	var out := PackedVector2Array(d.front)
	var top: float = (d.front[0] as Vector2).y
	out.append(Vector2(float(d.rear), float(d.sill)))
	out.append(Vector2(float(d.rear), top))
	return out


## Front shut line's along at height `h` (the outline's foremost point for the van).
static func front_at(type: int, h: float) -> float:
	var d: Dictionary = DOORS[type]
	if d.has("van"):
		return 2.17
	var pts: Array = d.front
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if h <= a.y and h >= b.y:
			return lerpf(a.x, b.x, (a.y - h) / maxf(a.y - b.y, 1e-4))
	return (pts[0] as Vector2).x if h > (pts[0] as Vector2).y else (pts[pts.size() - 1] as Vector2).x


static func rear_of(type: int) -> float:
	var d: Dictionary = DOORS[type]
	return 1.27 if d.has("van") else float(d.rear)


static func sill_of(type: int) -> float:
	var d: Dictionary = DOORS[type]
	return 0.42 if d.has("van") else float(d.sill)


## The finished split for `type`, or {} while its job runs (or none was asked for).
static func result(type: int) -> Dictionary:
	return _done.get(type, {})


## Asks for `type`'s split from `mesh` (the body's near mesh); true once it is ready.
static func request(type: int, mesh: Mesh) -> bool:
	if _done.has(type):
		return true
	if not supported(type) or mesh == null:
		return false
	if not _jobs.has(type):
		_jobs[type] = Job.new(type, mesh)
	return false


static func pending() -> bool:
	return not _jobs.is_empty()


## Runs the jobs until `budget_usec` is spent. Returns true while any is left.
static func step(budget_usec: int) -> bool:
	var t0 := Time.get_ticks_usec()
	for type: int in _jobs.keys():
		var job: Job = _jobs[type]
		if threaded and job._stage >= 1 and job._stage <= 4:
			# The arithmetic on a worker thread; back here for the renderer's part.
			if job.task < 0:
				job.task = WorkerThreadPool.add_task(job.crunch, false, "CarDoorSplit")
			if not job.crunched:
				continue
			WorkerThreadPool.wait_for_task_completion(job.task)
		while not job.finished and Time.get_ticks_usec() - t0 < budget_usec:
			job.advance()
		if job.finished:
			_done[type] = job.out
			_jobs.erase(type)
		if Time.get_ticks_usec() - t0 >= budget_usec:
			break
	return not _jobs.is_empty()


## Runs `type`'s job to the end at once (tools and tests).
static func now(type: int, mesh: Mesh) -> Dictionary:
	var was := threaded
	threaded = false
	request(type, mesh)
	while _jobs.has(type):
		step(1 << 30)
	threaded = was
	return result(type)


static func clear() -> void:
	_done.clear()
	_jobs.clear()


class Job:
	extends RefCounted
	var type: int
	var mesh: Mesh
	var finished := false
	var crunched := false
	var task := -1
	var out := {}
	var _stage := 0
	var _surfs: Array = []
	var _si := 0
	var _ti := 0
	## Per surface, per triangle: 0 body, 1 door on -x, 2 door on +x.
	var _cls: Array = []
	var _lower := PackedVector2Array()
	var _lower_k := [PackedVector2Array(), PackedVector2Array()]
	var _upper := [PackedVector2Array(), PackedVector2Array()]
	var _glass_lo := [INF, INF]
	var _glass_hi := [-INF, -INF]
	var _front_top := 0.0
	var _rear := 0.0
	var _sill := 0.0
	var _van := false

	func _init(t: int, m: Mesh) -> void:
		type = t
		mesh = m
		_lower = CarDoorSplit.lower_outline(t)
		_van = (CarDoorSplit.DOORS[t] as Dictionary).has("van")
		_rear = CarDoorSplit.rear_of(t)
		_sill = CarDoorSplit.sill_of(t)
		_front_top = CarDoorSplit.front_at(t, 9.0)

	func advance() -> void:
		match _stage:
			0:
				_read()
			1:
				_glass_hulls()
			2:
				_classify_slice()
			3:
				# One surface's parts made whole a step.
				if _si < _surfs.size():
					_whole_parts(_si)
					_si += 1
				else:
					_si = 0
					_stage = 4
			4:
				# A slice of one surface's triangles sorted a step; its arrays when done.
				if _si < _surfs.size():
					if _sort_slice(_si):
						_prepare_surface(_si)
						_si += 1
						_ti = 0
				else:
					_si = 0
					_stage = 5
			5:
				# One surface made a step (the renderer: the main thread's part).
				if _si < _surfs.size():
					_make_surface(_si)
					_si += 1
				else:
					_finish()

	## Everything from the glass hulls to the sorted arrays, at once: run on a worker thread
	## (CarDoorSplit.step()), it never touches the renderer.
	func crunch() -> void:
		while _stage >= 1 and _stage <= 4:
			advance()
		crunched = true

	func _read() -> void:
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var mat := mesh.surface_get_material(si)
			_surfs.append({"arr": arr, "mat": mat, "glass": mat != null and String(mat.resource_name) == "glass"})
			_cls.append(PackedByteArray())
		var real := false
		for s: Dictionary in _surfs:
			var arr: Array = s.arr
			if not arr.is_empty() and arr[Mesh.ARRAY_VERTEX] != null and (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
				real = true
		if not real:
			out = {"real": false, "body": null, "doors": []}
			finished = true
			return
		_stage = 1

	## The door glass on each side: lateral glass between the shut lines (inside the outline for
	## the van), and its side-view hull grown by FRAME.
	func _glass_hulls() -> void:
		var pts0 := PackedVector2Array()
		var pts1 := PackedVector2Array()
		for s: Dictionary in _surfs:
			if not s.glass:
				continue
			var arr: Array = s.arr
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for t in idx.size() / 3:
				var a := v[idx[t * 3]]
				var b := v[idx[t * 3 + 1]]
				var c := v[idx[t * 3 + 2]]
				var n := (b - a).cross(c - a)
				if n.length_squared() < 1e-12:
					continue
				n = n.normalized()
				var m := (a + b + c) / 3.0
				if absf(n.x) < 0.45 or absf(m.x) < 0.3:
					continue
				var p := Vector2(-m.z, m.y)
				if _van:
					if not Geometry2D.is_point_in_polygon(p, _lower):
						continue
				elif p.x < _rear + 0.02 or p.x > _front_top + 0.03 or p.y < _sill:
					continue
				var k := 1 if m.x > 0.0 else 0
				for q in [a, b, c]:
					if k == 0:
						pts0.append(Vector2(-q.z, q.y))
					else:
						pts1.append(Vector2(-q.z, q.y))
					_glass_lo[k] = minf(_glass_lo[k], q.y)
					_glass_hi[k] = maxf(_glass_hi[k], q.y)
		var pts := [pts0, pts1]
		for k in 2:
			# The outline below the glass reaches up to the glass's foot (the belt moulding).
			var low := PackedVector2Array(_lower)
			if not _van and _glass_lo[k] < INF:
				var top := maxf(low[0].y, _glass_lo[k] + 0.006)
				low[0] = Vector2(low[0].x, top)
				low[low.size() - 1] = Vector2(low[low.size() - 1].x, top)
			_lower_k[k] = low
			if (pts[k] as PackedVector2Array).size() >= 3:
				var hull := Geometry2D.convex_hull(pts[k])
				var grown := Geometry2D.offset_polygon(hull, CarDoorSplit.FRAME)
				_upper[k] = grown[0] if not grown.is_empty() else hull
		_si = 0
		_ti = 0
		_stage = 2

	func _classify_slice() -> void:
		if _si >= _surfs.size():
			_si = 0
			_stage = 3
			return
		var s: Dictionary = _surfs[_si]
		var arr: Array = s.arr
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			_si += 1
			return
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var nt := idx.size() / 3
		var paint := s.mat != null and String(s.mat.resource_name).begins_with("paint")
		var cls: PackedByteArray = _cls[_si]
		if cls.size() != nt:
			cls.resize(nt)
		var end := mini(_ti + CarDoorSplit.SLICE, nt)
		for t in range(_ti, end):
			var m := (v[idx[t * 3]] + v[idx[t * 3 + 1]] + v[idx[t * 3 + 2]]) / 3.0
			var c := 0
			if absf(m.x) > CarDoorSplit.XMIN:
				var k := 1 if m.x > 0.0 else 0
				var p := Vector2(-m.z, m.y)
				if Geometry2D.is_point_in_polygon(p, _lower_k[k] if (_lower_k[k] as PackedVector2Array).size() >= 3 else _lower):
					c = k + 1
				elif m.y > _glass_lo[k] - CarDoorSplit.BELT_SLACK and (_upper[k] as PackedVector2Array).size() >= 3 \
						and (not paint or m.y < _glass_lo[k] + CarDoorSplit.PAINT_OVER_BELT) \
						and Geometry2D.is_point_in_polygon(p, _upper[k]):
					# Above the belt: the glass, its seals and liners - but the painted pillars and
					# the roof rail stay with the body.
					c = k + 1
			cls[t] = c
		_cls[_si] = cls
		_ti = end
		if _ti >= nt:
			_si += 1
			_ti = 0

	## Parts that are not the painted skin or the glass (cladding, mirrors, handles, seals) go
	## whole, to whichever side has most of their area: cut triangle by triangle they were torn
	## into teeth along the shut lines.
	func _whole_parts(si: int) -> void:
		if true:
			var s: Dictionary = _surfs[si]
			var mat: Material = s.mat
			if s.glass or mat == null or String(mat.resource_name).begins_with("paint"):
				return
			var arr: Array = s.arr
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				return
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var cls: PackedByteArray = _cls[si]
			# Vertices joined by index and by position (seams split them).
			# An Array, not a PackedInt32Array: a packed array handed to a function is a copy.
			var parent := []
			parent.resize(v.size())
			for i in v.size():
				parent[i] = i
			var at := {}
			# Only near the doors: a part further off cannot reach them (WHOLE_SPAN).
			var z_lo := -(_front_top + CarDoorSplit.WHOLE_SPAN + 0.3)
			var z_hi := -(_rear - CarDoorSplit.WHOLE_SPAN - 0.3)
			var near := PackedByteArray()
			near.resize(v.size())
			for i in v.size():
				var q := v[i]
				if absf(q.x) < CarDoorSplit.XMIN - 0.1 or q.z < z_lo or q.z > z_hi:
					continue
				near[i] = 1
				var key := Vector3i(roundi(q.x * 2000.0), roundi(q.y * 2000.0), roundi(q.z * 2000.0))
				var j: int = at.get(key, -1)
				if j < 0:
					at[key] = i
				else:
					_union(parent, i, j)
			for t in idx.size() / 3:
				if near[idx[t * 3]] == 0:
					continue
				_union(parent, idx[t * 3], idx[t * 3 + 1])
				_union(parent, idx[t * 3], idx[t * 3 + 2])
			var votes := {}
			var box_lo := {}
			var box_hi := {}
			for t in idx.size() / 3:
				if near[idx[t * 3]] == 0:
					continue
				var a := v[idx[t * 3]]
				var area := (v[idx[t * 3 + 1]] - a).cross(v[idx[t * 3 + 2]] - a).length()
				var r := _find(parent, idx[t * 3])
				var w: Vector3 = votes.get(r, Vector3.ZERO)
				w[cls[t]] += area
				votes[r] = w
				for q in 3:
					var p := v[idx[t * 3 + q]]
					var pp := Vector2(-p.z, p.y)
					box_lo[r] = (box_lo.get(r, pp) as Vector2).min(pp)
					box_hi[r] = (box_hi.get(r, pp) as Vector2).max(pp)
			var top := maxf(_glass_hi[0], _glass_hi[1])
			var fit_lo := Vector2(_rear - 0.06, _sill - 0.12)
			var fit_hi := Vector2(_front_top + 0.3, (top if top > -INF else _sill + 1.0) + 0.06)
			for t in idx.size() / 3:
				if near[idx[t * 3]] == 0:
					continue
				var r := _find(parent, idx[t * 3])
				var lo: Vector2 = box_lo[r]
				var hi: Vector2 = box_hi[r]
				if hi.y - lo.y < CarDoorSplit.STRIP_HEIGHT:
					# A thin strip (the belt moulding along both doors) is cut where it crosses.
					continue
				var w: Vector3 = votes[r]
				if lo.x < fit_lo.x or lo.y < fit_lo.y or hi.x > fit_hi.x or hi.y > fit_hi.y:
					# Bigger than the door: a ring or strip (the chrome round both windows, the
					# liner) is cut where it crosses; anything solid (the cladding along the
					# whole side) stays on the body.
					if (w.x + w.y + w.z) * 0.5 / maxf((hi - lo).length(), 0.01) > CarDoorSplit.STRIP_WIDTH:
						cls[t] = 0
					continue
				cls[t] = 0 if w.x >= w.y and w.x >= w.z else (1 if w.y >= w.z else 2)
			_cls[si] = cls

	static func _find(parent: Array, x: int) -> int:
		while int(parent[x]) != x:
			parent[x] = parent[int(parent[x])]
			x = int(parent[x])
		return x

	static func _union(parent: Array, a: int, b: int) -> void:
		var ra := _find(parent, a)
		var rb := _find(parent, b)
		if ra != rb:
			parent[ra] = rb

	var _body := ArrayMesh.new()
	var _dm := [ArrayMesh.new(), ArrayMesh.new()]
	var _maps := [[], []]
	var _skin := [0.0, 0.0]
	var _hinge_x := [0.0, 0.0]
	var _hinge_n := [0, 0]

	var _keep := PackedInt32Array()
	var _p0 := PackedInt32Array()
	var _p1 := PackedInt32Array()

	## Sorts the next SLICE * 2 triangles of surface `si` into the body's and the doors' index
	## lists. True once the surface is through.
	func _sort_slice(si: int) -> bool:
		var arr: Array = (_surfs[si] as Dictionary).arr
		if arr.is_empty() or arr[Mesh.ARRAY_INDEX] == null:
			return true
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var cls: PackedByteArray = _cls[si]
		var nt := idx.size() / 3
		var end := mini(_ti + CarDoorSplit.SLICE * 2, nt)
		for t in range(_ti, end):
			var c := cls[t] if t < cls.size() else 0
			if c == 0:
				_keep.append(idx[t * 3])
				_keep.append(idx[t * 3 + 1])
				_keep.append(idx[t * 3 + 2])
			elif c == 1:
				_p0.append(idx[t * 3])
				_p0.append(idx[t * 3 + 1])
				_p0.append(idx[t * 3 + 2])
			else:
				_p1.append(idx[t * 3])
				_p1.append(idx[t * 3 + 1])
				_p1.append(idx[t * 3 + 2])
		_ti = end
		return _ti >= nt

	var _prepared: Array = []

	## The body's arrays and each door's compacted ones for surface `si` (no renderer calls).
	func _prepare_surface(si: int) -> void:
		var s: Dictionary = _surfs[si]
		var arr: Array = s.arr
		var keep := _keep
		var parts := [_p0, _p1]
		_keep = PackedInt32Array()
		_p0 = PackedInt32Array()
		_p1 = PackedInt32Array()
		var barr := arr.duplicate()
		if keep.is_empty():
			# A surface wholly on the doors keeps one degenerate triangle: the body's surface
			# order is what the cabin glass and the damage address.
			keep = PackedInt32Array([0, 0, 0])
		barr[Mesh.ARRAY_INDEX] = keep
		var darrs := [null, null]
		if not arr.is_empty() and arr[Mesh.ARRAY_VERTEX] != null:
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for k in 2:
				var part: PackedInt32Array = parts[k]
				if part.is_empty():
					continue
				darrs[k] = _compact(arr, part)
				if not s.glass:
					for i in part:
						var q := v[i]
						if q.y > _sill + 0.08 and q.y < _glass_lo[k] - 0.05:
							_skin[k] += absf(q.x)
							var along := -q.z
							if along > CarDoorSplit.front_at(type, q.y) - 0.12:
								_hinge_x[k] = maxf(_hinge_x[k], absf(q.x))
							_hinge_n[k] += 1
		while _prepared.size() <= si:
			_prepared.append(null)
		_prepared[si] = {"barr": barr, "darrs": darrs, "mat": s.mat}

	func _make_surface(si: int) -> void:
		var pr: Dictionary = _prepared[si]
		_body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pr.barr)
		_body.surface_set_material(si, pr.mat)
		for k in 2:
			if pr.darrs[k] == null:
				continue
			var dm: ArrayMesh = _dm[k]
			dm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pr.darrs[k])
			dm.surface_set_material(dm.get_surface_count() - 1, pr.mat)
			_maps[k].append(si)
		_prepared[si] = null

	func _finish() -> void:
		var doors := []
		var dm := _dm
		var maps := _maps
		var skin := _skin
		var hinge_x := _hinge_x
		var hinge_n := _hinge_n
		for k in 2:
			if (dm[k] as ArrayMesh).get_surface_count() == 0:
				continue
			var side := -1.0 if k == 0 else 1.0
			var n := maxi(hinge_n[k], 1)
			var belt: float = _glass_lo[k] if _glass_lo[k] < INF else _front_top
			var mid_h: float = (_sill + belt) * 0.5
			var hx: float = hinge_x[k] if hinge_x[k] > 0.0 else skin[k] / n
			doors.append({
				"side": side, "mesh": dm[k], "surf_map": PackedInt32Array(maps[k]),
				"hinge": Vector3(side * hx, mid_h, -CarDoorSplit.front_at(type, mid_h)),
				"skin_x": skin[k] / n, "front": CarDoorSplit.front_at(type, belt), "rear": _rear,
				"sill": _sill, "belt": belt, "top": _glass_hi[k] if _glass_hi[k] > -INF else belt,
				"lower": _lower_k[k] if (_lower_k[k] as PackedVector2Array).size() >= 3 else _lower, "upper": _upper[k],
			})
		out = {"real": true, "body": _body, "doors": doors}
		_surfs.clear()
		_cls.clear()
		_prepared.clear()
		finished = true

	## The triangles `part` of `arr` with their vertices renumbered from 0.
	static func _compact(arr: Array, part: PackedInt32Array) -> Array:
		var remap := {}
		var order := PackedInt32Array()
		var ni := PackedInt32Array()
		ni.resize(part.size())
		for j in part.size():
			var i := part[j]
			var r: int = remap.get(i, -1)
			if r < 0:
				r = order.size()
				remap[i] = r
				order.append(i)
			ni[j] = r
		var nv := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		for a in Mesh.ARRAY_MAX:
			var src: Variant = arr[a]
			if src == null or a == Mesh.ARRAY_INDEX:
				continue
			out[a] = _pick(src, order, nv)
		out[Mesh.ARRAY_INDEX] = ni
		return out

	static func _pick(src: Variant, order: PackedInt32Array, nv: int) -> Variant:
		if src is PackedVector3Array:
			var s3: PackedVector3Array = src
			var o3 := PackedVector3Array()
			o3.resize(order.size())
			for j in order.size():
				o3[j] = s3[order[j]]
			return o3
		if src is PackedVector2Array:
			var s2: PackedVector2Array = src
			var o2 := PackedVector2Array()
			o2.resize(order.size())
			for j in order.size():
				o2[j] = s2[order[j]]
			return o2
		if src is PackedColorArray:
			var sc: PackedColorArray = src
			var oc := PackedColorArray()
			oc.resize(order.size())
			for j in order.size():
				oc[j] = sc[order[j]]
			return oc
		if src is PackedFloat32Array:
			# Tangents (4 a vertex) and the custom channels' float layouts.
			var sf: PackedFloat32Array = src
			var per := sf.size() / maxi(nv, 1)
			var of := PackedFloat32Array()
			of.resize(order.size() * per)
			for j in order.size():
				for q in per:
					of[j * per + q] = sf[order[j] * per + q]
			return of
		if src is PackedInt32Array:
			var si: PackedInt32Array = src
			var per_i := si.size() / maxi(nv, 1)
			var oi := PackedInt32Array()
			oi.resize(order.size() * per_i)
			for j in order.size():
				for q in per_i:
					oi[j * per_i + q] = si[order[j] * per_i + q]
			return oi
		if src is PackedByteArray:
			var sb: PackedByteArray = src
			var per_b := sb.size() / maxi(nv, 1)
			var ob := PackedByteArray()
			ob.resize(order.size() * per_b)
			for j in order.size():
				for q in per_b:
					ob[j * per_b + q] = sb[order[j] * per_b + q]
			return ob
		return src
