class_name ReplicaSigns
extends RefCounted
## Street furniture of a replica area, by the reference photos: the grey double-arm cobra-head
## lamps on the ocean kerb, the parking plates on their poles, the yellow roundabout warning
## diamond with its advisory plaque, black-on-yellow chevrons on the islands, all-way stops at the
## junctions that have them, street-name posts ("ESPLANADE" and the grid street it meets), speed
## limit plates and a couple of bus stops. Designs are generic road-sign shapes and wording; no
## real agency's marks. Everything is a breakable prop (CityChunk._add_prop) seeded by position.

## Height of the plates' centres above the pavement.
const PLATE_Y := 2.35
## Where the roundabout warning stands ahead of the ring, metres of path.
const WARN_AHEAD := 75.0
## Path distances of the bus stops (east pavement) and the speed limit plates.
const BUS_STOPS := [780.0, 1530.0]
const SPEED_SIGNS := [[140.0, -1.0], [1720.0, 1.0]]

const YELLOW := Color(0.98, 0.78, 0.08)
const BLACK := Color(0.05, 0.05, 0.05)
const WHITE := Color(0.95, 0.95, 0.93)
const POLE := Color(0.55, 0.56, 0.57)

static var _cache := {}


# --- Placement -----------------------------------------------------------------------------------

## Everything along the builder's stretch of the route, lo..hi metres of path.
static func furniture(b: ReplicaBuilder, lo: float, hi: float) -> void:
	var rep := b.rep
	# Parking plates on the ocean-side lamp poles.
	var spacing: float = rep.data.get("lamp_spacing", 45.0)
	var k0 := ceili((lo - 12.0) / spacing)
	var k1 := floori((hi - 12.0) / spacing)
	for k in range(k0, k1 + 1):
		var s := 12.0 + k * spacing
		if s < lo or s >= hi or s > rep.s_city_end or s < 60.0:
			continue
		var at := rep.at_s(s)
		var sd: Dictionary = at[3]
		if float(sd.lamps) < 0.5 or float(sd.park_w) < 1.0 or not b._near_ring(at[0], 10.0).is_empty() or b._stair_near(s, 2.0):
			continue
		var l := ReplicaAreas.left_of(at[1])
		var p: Vector2 = (at[0] as Vector2) + l * (float(sd.kerb_w) - 0.55)
		var face := -(at[1] as Vector2) if k % 2 == 0 else (at[1] as Vector2)
		_plate(b, Vector3(p.x, float(at[2]) + 0.15, p.y), face, ["2 HR PARKING", "8AM - 6PM"] if k % 3 != 2 else ["NO PARKING", "2AM - 5AM"], k % 3 == 2, false)
	# Junctions with the grid.
	for m in rep.mouths(b.plan):
		var ms: float = m.s
		if ms < lo - 1.0 or ms >= hi - 1.0:
			continue
		_junction(b, m)
	# The roundabout warning, both ways.
	for ra in rep.roundabouts:
		for dir: float in [-1.0, 1.0]:
			var s := float(ra.s) + dir * WARN_AHEAD
			if s < lo or s >= hi:
				continue
			var at := rep.at_s(s)
			var sd: Dictionary = at[3]
			var l := ReplicaAreas.left_of(at[1])
			var o := 0.0 if float(sd.median_raised) > 0.5 and float(sd.median) > 2.0 else (float(sd.kerb_w) - 0.6 if dir < 0.0 else float(sd.kerb_e) + 0.6)
			var p: Vector2 = (at[0] as Vector2) + l * o
			_warning(b, Vector3(p.x, float(at[2]) + (0.17 if o == 0.0 else 0.15), p.y), (at[1] as Vector2) * dir)
	for bs in BUS_STOPS:
		var s: float = bs
		if s >= lo and s < hi and b._mouth_at(s, 8.0).is_empty():
			var at := rep.at_s(s)
			var sd: Dictionary = at[3]
			var l := ReplicaAreas.left_of(at[1])
			var p: Vector2 = (at[0] as Vector2) + l * (float(sd.kerb_e) + 0.6)
			_bus_stop(b, Vector3(p.x, float(at[2]) + 0.15, p.y), l, at[1])
	for sp: Array in SPEED_SIGNS:
		var s: float = sp[0]
		var side: float = sp[1]
		if s >= lo and s < hi and b._mouth_at(s, 6.0).is_empty():
			var at := rep.at_s(s)
			var sd: Dictionary = at[3]
			var l := ReplicaAreas.left_of(at[1])
			var o: float = (float(sd.kerb_e) + 0.5) if side > 0.0 else (float(sd.kerb_w) - 0.5)
			var p: Vector2 = (at[0] as Vector2) + l * o
			_speed(b, Vector3(p.x, float(at[2]) + 0.15, p.y), (at[1] as Vector2) * side)


## A grid street meeting the route: name posts at its corners, and at a stop junction the four
## stop signs.
static func _junction(b: ReplicaBuilder, m: Dictionary) -> void:
	var rep := b.rep
	var half: float = float(m.width) * 0.5
	var grid_name: String = str(m.name) if m.has("name") else b.plan.road_name(CityPlan.AXIS_Z, int(m.j))
	for side: float in [-1.0, 1.0]:
		var s := float(m.s) + side * (half + 1.6)
		var at := rep.at_s(s)
		var sd: Dictionary = at[3]
		var l := ReplicaAreas.left_of(at[1])
		var p: Vector2 = (at[0] as Vector2) + l * (float(sd.kerb_e) + 0.7)
		if side < 0.0:
			StreetDetail._name_sign(b.chunk, p, "ESPLANADE", grid_name)
		if bool(m.stop):
			# Northbound traffic stops on the east kerb south of the street (side +1); the
			# street's own traffic, heading west, at its north corner (side -1).
			var face := (at[1] as Vector2) if side > 0.0 else -l
			_stop(b, Vector3(p.x, float(at[2]) + 0.15, p.y), face)
	if bool(m.stop):
		var s := float(m.s) - half - 3.2
		var at := rep.at_s(s)
		var sd: Dictionary = at[3]
		var l := ReplicaAreas.left_of(at[1])
		var p: Vector2 = (at[0] as Vector2) + l * (float(sd.kerb_w) - 0.7)
		_stop(b, Vector3(p.x, float(at[2]) + 0.15, p.y), -(at[1] as Vector2))


# --- The signs ----------------------------------------------------------------------------------

## A basis whose +Z faces `n` (horizontal), Y up.
static func face_basis(n: Vector2) -> Basis:
	var z := Vector3(n.x, 0.0, n.y).normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z)


## Registers a breakable prop from world-space instance transforms (the batch and _add_prop add
## the chunk's ground themselves, so everything is handed over relative to it).
static func _prop(b: ReplicaBuilder, kind: String, at: Vector3, color: Color, instances: Array, height: float) -> void:
	var rel_instances := []
	for inst: Array in instances:
		var xf: Transform3D = inst[2]
		var entry := [inst[0], inst[1], Transform3D(xf.basis, b.rel(xf.origin))]
		if inst.size() > 3:
			entry.append(inst[3])
		rel_instances.append(entry)
	var base := b.rel(at)
	b.chunk._add_prop(kind, base, color, rel_instances, [[Vector3(0.3, height, 0.3), base + Vector3(0.0, height * 0.5, 0.0), 0.0]])


static func _stop(b: ReplicaBuilder, at: Vector3, face: Vector2) -> void:
	var fb := face_basis(face)
	_prop(b, "stop_sign", at, Color(0.8, 0.12, 0.1), [
		["sign_pole", PropFactory.sign_pole(), Transform3D(Basis(), at + Vector3(0.0, 1.3, 0.0))],
		["stop_sign", PropFactory.stop_sign(), Transform3D(fb * Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(0.0, 2.4, 0.0) + fb.z * 0.07)],
		["text_STOP", PropFactory.text_mesh("STOP", 0.24), Transform3D(fb, at + Vector3(0.0, 2.4, 0.0) + fb.z * 0.1), WHITE],
	], 2.8)


## A white regulatory plate with two lines of text (red lettering for a prohibition, green for a
## limit), on its own post or (`on_pole`) clamped to a lamp column.
static func _plate(b: ReplicaBuilder, at: Vector3, face: Vector2, lines: Array, red: bool, own_post: bool) -> void:
	var fb := face_basis(face)
	var ink := Color(0.72, 0.08, 0.06) if red else Color(0.05, 0.40, 0.18)
	var y := 3.1
	var c := at + Vector3(0.0, y, 0.0) + fb.z * (0.02 if own_post else 0.11)
	var inst := [
		["rsign_plate", plate_mesh(), Transform3D(fb, c)],
		["text_" + str(lines[0]), PropFactory.text_mesh(lines[0], 0.075), Transform3D(fb, c + Vector3(0.0, 0.09, 0.0) + fb.z * 0.016), ink],
		["text_" + str(lines[1]), PropFactory.text_mesh(lines[1], 0.06), Transform3D(fb, c + Vector3(0.0, -0.06, 0.0) + fb.z * 0.016), BLACK],
	]
	if own_post:
		inst.append(["sign_pole", PropFactory.sign_pole(), Transform3D(Basis(), at + Vector3(0.0, 1.3, 0.0))])
	_prop(b, "street_sign", at, Color(0.9, 0.9, 0.9), inst, y + 0.3)


static func _speed(b: ReplicaBuilder, at: Vector3, face: Vector2) -> void:
	var fb := face_basis(face)
	var c := at + Vector3(0.0, PLATE_Y, 0.0) + fb.z * 0.06
	_prop(b, "street_sign", at, Color(0.9, 0.9, 0.9), [
		["sign_pole", PropFactory.sign_pole(), Transform3D(Basis(), at + Vector3(0.0, 1.3, 0.0))],
		["rsign_speed", speed_mesh(), Transform3D(fb, c)],
		["text_SPEED", PropFactory.text_mesh("SPEED", 0.09), Transform3D(fb, c + Vector3(0.0, 0.21, 0.0) + fb.z * 0.016), BLACK],
		["text_LIMIT", PropFactory.text_mesh("LIMIT", 0.09), Transform3D(fb, c + Vector3(0.0, 0.1, 0.0) + fb.z * 0.016), BLACK],
		["text_25", PropFactory.text_mesh("25", 0.26), Transform3D(fb, c + Vector3(0.0, -0.12, 0.0) + fb.z * 0.016), BLACK],
	], 3.0)


## The yellow diamond with the roundabout symbol, and a plaque under it.
static func _warning(b: ReplicaBuilder, at: Vector3, face: Vector2) -> void:
	var fb := face_basis(face)
	var c := at + Vector3(0.0, 2.55, 0.0) + fb.z * 0.06
	_prop(b, "street_sign", at, Color(0.9, 0.8, 0.2), [
		["sign_pole", PropFactory.sign_pole(), Transform3D(Basis(), at + Vector3(0.0, 1.3, 0.0))],
		["sign_pole", PropFactory.sign_pole(), Transform3D(Basis(), at + Vector3(0.0, 1.9, 0.0))],
		["rsign_roundabout", roundabout_mesh(), Transform3D(fb, c)],
		["rsign_plaque", plaque_mesh(), Transform3D(fb, c - Vector3(0.0, 0.72, 0.0))],
		["text_15 MPH", PropFactory.text_mesh("15 MPH", 0.13), Transform3D(fb, c - Vector3(0.0, 0.72, 0.0) + fb.z * 0.016), BLACK],
	], 3.3)


## Chevron plates on an island: `count` side by side facing `face`, pointing the way to turn
## (`right` for a roundabout's anticlockwise ring, left for a left-hand curve).
static func chevron(b: ReplicaBuilder, at: Vector3, face: Vector2, count: int, right: bool = true) -> void:
	var fb := face_basis(face)
	var inst := []
	for k in count:
		var off := fb.x * ((float(k) - (count - 1) * 0.5) * 0.52)
		inst.append(["sign_post_short", short_post(), Transform3D(Basis(), at + off + Vector3(0.0, 0.6, 0.0))])
		inst.append(["rsign_chevron_r" if right else "rsign_chevron_l", chevron_mesh(right), Transform3D(fb, at + off + Vector3(0.0, 1.05, 0.0) + fb.z * 0.04)])
	_prop(b, "street_sign", at, Color(0.9, 0.8, 0.2), inst, 1.4)


static func _bus_stop(b: ReplicaBuilder, at: Vector3, inward: Vector2, along: Vector2) -> void:
	var fb := face_basis(along)
	var road := face_basis(inward)
	_prop(b, "bus_stop", at, Color(0.3, 0.3, 0.32), [
		["sign_post", PropFactory.sign_post(), Transform3D(Basis(), at + Vector3(0.0, 1.4, 0.0))],
		["bus_sign", PropFactory.bus_sign(), Transform3D(fb, at + Vector3(0.0, 2.7, 0.0))],
		["bench", PropFactory.model_bench(), Transform3D(road, at + Vector3(inward.x, 0.0, inward.y) * 1.6 + Vector3(along.x, 0.0, along.y) * 2.2)],
	], 2.9)


# --- Meshes -------------------------------------------------------------------------------------

static func _st(smooth: bool = false) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0 if smooth else -1)
	return st


static func _finish(st: SurfaceTool, key: String, rough: float = 0.5) -> Mesh:
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	mesh.surface_set_material(0, m)
	_cache[key] = mesh
	return mesh


## A flat polygon (XY plane, facing +Z) at depth z.
static func _poly(st: SurfaceTool, pts: PackedVector2Array, z: float, col: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(pts)
	for k in range(0, idx.size(), 3):
		var a := Vector3(pts[idx[k]].x, pts[idx[k]].y, z)
		var bb := Vector3(pts[idx[k + 1]].x, pts[idx[k + 1]].y, z)
		var c := Vector3(pts[idx[k + 2]].x, pts[idx[k + 2]].y, z)
		# Front faces are clockwise seen from the front (+Z).
		if (bb - a).cross(c - a).z > 0.0:
			var t := bb
			bb = c
			c = t
		for v: Vector3 in [a, bb, c]:
			st.set_color(col)
			st.add_vertex(v)


## A sign blank: the polygon as a plate `thick` deep, face at z 0, grey back and edges.
static func _blank(st: SurfaceTool, pts: PackedVector2Array, col: Color, thick: float = 0.02) -> void:
	_poly(st, pts, 0.0, col)
	var back := PackedVector2Array()
	for k in range(pts.size() - 1, -1, -1):
		back.append(pts[k])
	# The back, facing -Z: mirror the winding by building it at -thick with reversed order and
	# flipping in _poly's test (it faces +Z), so emit as-is then swap to face -Z.
	var idx := Geometry2D.triangulate_polygon(pts)
	for k in range(0, idx.size(), 3):
		var a := Vector3(pts[idx[k]].x, pts[idx[k]].y, -thick)
		var bb := Vector3(pts[idx[k + 1]].x, pts[idx[k + 1]].y, -thick)
		var c := Vector3(pts[idx[k + 2]].x, pts[idx[k + 2]].y, -thick)
		if (bb - a).cross(c - a).z < 0.0:
			var t := bb
			bb = c
			c = t
		for v: Vector3 in [a, bb, c]:
			st.set_color(Color(0.6, 0.6, 0.6))
			st.add_vertex(v)
	for k in pts.size():
		var p0 := pts[k]
		var p1 := pts[(k + 1) % pts.size()]
		var a := Vector3(p0.x, p0.y, 0.0)
		var bb := Vector3(p1.x, p1.y, 0.0)
		var c := Vector3(p1.x, p1.y, -thick)
		var d := Vector3(p0.x, p0.y, -thick)
		var out := Vector3((p0 + p1).x * 0.5, (p0 + p1).y * 0.5, 0.0)
		for tri: Array in [[a, bb, c], [a, c, d]]:
			var ta: Vector3 = tri[0]
			var tb: Vector3 = tri[1]
			var tc: Vector3 = tri[2]
			if (tb - ta).cross(tc - ta).dot(out) > 0.0:
				var t := tb
				tb = tc
				tc = t
			for v: Vector3 in [ta, tb, tc]:
				st.set_color(Color(0.6, 0.6, 0.6))
				st.add_vertex(v)


static func _rect(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5), Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5)])


## A band `w` wide along a polyline, flat on the sign face (the roundabout arrows, chevrons).
static func _stroke(st: SurfaceTool, path: PackedVector2Array, w: float, z: float, col: Color) -> void:
	for k in path.size() - 1:
		var a := path[k]
		var bb := path[k + 1]
		var n := (bb - a).normalized().orthogonal() * (w * 0.5)
		_poly(st, PackedVector2Array([a - n, bb - n, bb + n, a + n]), z, col)


static func plate_mesh() -> Mesh:
	if _cache.has("plate"):
		return _cache["plate"]
	var st := _st()
	_blank(st, _rect(0.32, 0.42), WHITE)
	# A thin coloured border.
	var r := _rect(0.30, 0.40)
	for k in 4:
		_stroke(st, PackedVector2Array([r[k], r[(k + 1) % 4]]), 0.012, 0.002, Color(0.2, 0.2, 0.2))
	return _finish(st, "plate")


static func speed_mesh() -> Mesh:
	if _cache.has("speed"):
		return _cache["speed"]
	var st := _st()
	_blank(st, _rect(0.6, 0.75), WHITE)
	var r := _rect(0.56, 0.71)
	for k in 4:
		_stroke(st, PackedVector2Array([r[k], r[(k + 1) % 4]]), 0.018, 0.002, BLACK)
	return _finish(st, "speed")


static func plaque_mesh() -> Mesh:
	if _cache.has("plaque"):
		return _cache["plaque"]
	var st := _st()
	_blank(st, _rect(0.62, 0.3), YELLOW)
	var r := _rect(0.58, 0.26)
	for k in 4:
		_stroke(st, PackedVector2Array([r[k], r[(k + 1) % 4]]), 0.014, 0.002, BLACK)
	return _finish(st, "plaque")


## The diamond: yellow, a black border, three arrows chasing each other round a ring.
static func roundabout_mesh() -> Mesh:
	if _cache.has("roundabout"):
		return _cache["roundabout"]
	var st := _st()
	var s := 0.53
	_blank(st, PackedVector2Array([Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)]), YELLOW)
	var i := s - 0.035
	var ring := PackedVector2Array([Vector2(0, -i), Vector2(i, 0), Vector2(0, i), Vector2(-i, 0)])
	for k in 4:
		_stroke(st, PackedVector2Array([ring[k], ring[(k + 1) % 4]]), 0.02, 0.002, BLACK)
	var radius := 0.2
	for arrow in 3:
		var a0 := TAU * arrow / 3.0 + 0.35
		var a1 := a0 + TAU / 3.0 - 0.55
		var path := PackedVector2Array()
		for k in 9:
			var a := lerpf(a0, a1, float(k) / 8.0)
			path.append(Vector2(cos(a), sin(a)) * radius)
		_stroke(st, path, 0.055, 0.003, BLACK)
		# The head, at the end of the arc, pointing on round the ring (anticlockwise).
		var tip_dir := Vector2(-sin(a1), cos(a1))
		var base := Vector2(cos(a1), sin(a1)) * radius
		var nrm := Vector2(cos(a1), sin(a1))
		_poly(st, PackedVector2Array([base + nrm * 0.075, base + tip_dir * 0.1, base - nrm * 0.075]), 0.003, BLACK)
	return _finish(st, "roundabout")


static func chevron_mesh(right: bool) -> Mesh:
	var key := "chevron_%s" % right
	if _cache.has(key):
		return _cache[key]
	var st := _st()
	_blank(st, _rect(0.45, 0.6), YELLOW)
	var sgn := 1.0 if right else -1.0
	var pts := PackedVector2Array([Vector2(-0.12 * sgn, 0.22), Vector2(0.1 * sgn, 0.0), Vector2(-0.12 * sgn, -0.22),
		Vector2(-0.02 * sgn, -0.22), Vector2(0.2 * sgn, 0.0), Vector2(-0.02 * sgn, 0.22)])
	if not right:
		pts.reverse()
	_poly(st, pts, 0.003, BLACK)
	return _finish(st, key)


static func short_post() -> Mesh:
	return PropFactory.cylinder("replica_short_post", 0.035, 1.2, Color(0.55, 0.56, 0.57), -1.0, 10)


## The grey cobra-head lamp column: a tapered pole, two arms sweeping up and out - the long one
## toward the road (+X), the short one back over the walkway - and a cobra head on each.
static func cobra_lamp() -> Mesh:
	if _cache.has("cobra"):
		return _cache["cobra"]
	var st := _st(true)
	var col := Color(1.0, 1.0, 1.0)
	var sides := 12
	var h := ReplicaBuilder.LAMP_HEIGHT
	# Base collar, and the column tapering from 0.12 to 0.075.
	_taper(st, 0.0, 0.55, 0.19, 0.16, sides, col)
	_taper(st, 0.55, h, 0.12, 0.075, sides, col)
	var road := PackedVector3Array([Vector3(0.0, h - 0.7, 0.0), Vector3(0.35, h - 0.2, 0.0), Vector3(1.0, h + 0.15, 0.0), Vector3(1.9, h + 0.3, 0.0), Vector3(ReplicaBuilder.LAMP_ARM_ROAD, h + 0.28, 0.0)])
	var walk := PackedVector3Array([Vector3(0.0, h - 0.8, 0.0), Vector3(-0.3, h - 0.45, 0.0), Vector3(-0.9, h - 0.25, 0.0), Vector3(-ReplicaBuilder.LAMP_ARM_WALK, h - 0.32, 0.0)])
	PropFactory._tube_into(st, road, 0.045, col, 8)
	PropFactory._tube_into(st, walk, 0.04, col, 8)
	PropFactory._sphere_into(st, Vector3(ReplicaBuilder.LAMP_ARM_ROAD + 0.08, h + 0.22, 0.0), Vector3(0.36, 0.1, 0.17), col, 12, 6)
	PropFactory._sphere_into(st, Vector3(-ReplicaBuilder.LAMP_ARM_WALK - 0.06, h - 0.38, 0.0), Vector3(0.3, 0.09, 0.15), col, 12, 6)
	# A finial on the column top.
	PropFactory._sphere_into(st, Vector3(0.0, h, 0.0), Vector3(0.08, 0.08, 0.08), col, 8, 4)
	return _finish(st, "cobra", 0.45)


static func _taper(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, sides: int, col: Color) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var p := [d0 * r0 + Vector3(0, y0, 0), d1 * r0 + Vector3(0, y0, 0), d1 * r1 + Vector3(0, y1, 0), d0 * r1 + Vector3(0, y1, 0)]
		var out := (d0 + d1) * 0.5
		for tri: Array in [[p[0], p[1], p[2]], [p[0], p[2], p[3]]]:
			var ta: Vector3 = tri[0]
			var tb: Vector3 = tri[1]
			var tc: Vector3 = tri[2]
			if (tb - ta).cross(tc - ta).dot(out) > 0.0:
				var t := tb
				tb = tc
				tc = t
			for v: Vector3 in [ta, tb, tc]:
				# UV and normal on every vertex: the tubes after it carry both, and a SurfaceTool's
				# format is fixed by its first vertex.
				st.set_color(col)
				st.set_uv(Vector2.ZERO)
				st.set_normal(Vector3(v.x, 0.0, v.z).normalized())
				st.add_vertex(v)
