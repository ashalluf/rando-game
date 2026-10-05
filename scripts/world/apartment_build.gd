class_name ApartmentBuild
extends HouseBuild
## One apartment building's geometry, from its Apartments plan, through the house kit's emitters
## (walls cut round every opening, reveals, framed glass, roofs, LOD boxes, collision): the
## apartment's openings (unit doors on the galleries and the court, windows by the unit, a podium's
## garage gate and its vented parking level), the galleries (a concrete slab on steel posts with an
## iron or stucco rail), the open stairs (steel stringers, concrete treads, pipe rails, landings), the
## stoops, balconies, wall air conditioners, the building's name in metal letters on the parapet, and
## the court's ground and planting (and the whole lot's ground in midtown, where no yard pass runs).
## FULL into the chunk's house surfaces; LOD adds the galleries and the court's lawns.

const STOREY := HouseKit.STOREY

## Air conditioners and balconies found while laying the openings: [fo, t, n, a, y].
var _acs: Array = []
var _balconies: Array = []


func _ap(parts: Array) -> float:
	return _h(["apt"] + parts)


## The frame of a wing's face: [fo, t, n, length] (HouseBuild._wing's table).
func _face(w: Dictionary, which: String) -> Array:
	var r: Rect2 = w.r
	match which:
		"front":
			return [Vector2(r.position.x, r.position.y), Vector2(1, 0), Vector2(0, -1), r.size.x]
		"back":
			return [Vector2(r.end.x, r.end.y), Vector2(-1, 0), Vector2(0, 1), r.size.x]
		"left":
			return [Vector2(r.position.x, r.end.y), Vector2(0, -1), Vector2(-1, 0), r.size.y]
	return [Vector2(r.end.x, r.position.y), Vector2(0, 1), Vector2(1, 0), r.size.y]


# --- Openings --------------------------------------------------------------------------------------

func _openings(i: int, w: Dictionary, which: String, fo: Vector2, t: Vector2, length: float, hidden: Array[Vector2]) -> Array:
	if not w.has("apt_role"):
		return super._openings(i, w, which, fo, t, length, hidden)
	var out: Array = []
	var n := Vector2(t.y, -t.x)
	var r := RandomNumberGenerator.new()
	r.seed = hash([ps, seed, "apt_face", i, which])
	var storeys: int = w.storeys
	var kind: int = h.apt
	var spanish: bool = w.get("spanish", false)
	var podium: bool = w.get("podium", false)
	var gallery_face := false
	for g: Dictionary in h.galleries:
		if int(g.wing) == i and g.face == which:
			gallery_face = true
	var court_face := _faces_court(w, which)
	var st := STOREY
	for fl in storeys:
		var fy := float(fl) * st
		var taken: Array[Vector2] = hidden.duplicate()
		# The doors on this floor of this face.
		for d: Array in w.doors:
			if d[0] != which or absf(float(d[2]) - fy) > 0.1:
				continue
			var a: float = d[1]
			var dk := "arch_door" if spanish else "door"
			var dw := HouseKit.DOOR_W + (0.25 if spanish else 0.0)
			var top := (2.68 - dw * 0.5) if spanish else HouseKit.DOOR_H
			out.append([a - dw * 0.5, a + dw * 0.5, fy, fy + top, dk])
			taken.append(Vector2(a - dw * 0.5 - 0.35, a + dw * 0.5 + 0.35))
			# The kitchen window beside a gallery door.
			if gallery_face:
				var ka := a + dw * 0.5 + 1.1
				if ka + 0.55 < length - 0.4 and not _clash(taken, ka - 0.5, ka + 0.5):
					out.append([ka - 0.5, ka + 0.5, fy + 1.15, fy + 2.15, "window"])
					taken.append(Vector2(ka - 0.8, ka + 0.8))
		if podium and fl == 0:
			if which == "front":
				var gd: Dictionary = h.garage
				var ga0 := float(gd.u0) - fo.x
				var ga1 := float(gd.u1) - fo.x
				out.append([ga0, ga1, base + 0.02, 2.75, "gate"])
				taken.append(Vector2(ga0 - 0.6, ga1 + 0.6))
			# The parking level's vents, screened in breeze block.
			var nv := maxi(1, int(length / 3.4))
			for k in nv:
				var c := (float(k) + 0.5) * length / nv
				if c - 0.85 < 0.5 or c + 0.85 > length - 0.5 or _clash(taken, c - 0.85, c + 0.85):
					continue
				out.append([c - 0.8, c + 0.8, 1.0, 2.35, "vent"])
				taken.append(Vector2(c - 1.1, c + 1.1))
			continue
		if gallery_face:
			continue
		if spanish:
			if court_face or which == "front":
				if fl == 0:
					_fill(out, taken, length, fy + 0.55, fy + 1.9, r, 1.15, 1.45, 3.1, "arch_window")
				else:
					var before := out.size()
					_fill(out, taken, length, fy + 0.7, fy + 2.35, r, 0.95, 1.15, 3.1, "grid")
					for k in range(before, out.size()):
						if r.randf() < 0.45:
							_balconies.append([fo, t, n, (float(out[k][0]) + float(out[k][1])) * 0.5, fy, 0.55, float(out[k][1]) - float(out[k][0]) + 0.5])
			else:
				_fill(out, taken, length, fy + 1.0, fy + 2.1, r, 0.7, 1.0, 4.0, "grid")
			continue
		if kind == Apartments.Kind.BUNGALOW_COURT:
			_fill(out, taken, length, fy + 0.85, fy + 2.25, r, 1.0, 1.5, 2.6, "grid" if w.mat == "h_siding" else "window")
			continue
		if podium and (which == "front" or which == "back") and h.get("balconies", false):
			# A slider to a balcony in each unit, a window beside it.
			var units := maxi(1, int(length / Apartments.UNIT_W))
			for k in units:
				var c := (float(k) + 0.35) * length / units
				var sw := r.randf_range(1.8, 2.3)
				if c - sw * 0.5 < 0.5 or c + sw * 0.5 > length - 0.5 or _clash(taken, c - sw * 0.5, c + sw * 0.5):
					continue
				out.append([c - sw * 0.5, c + sw * 0.5, fy + 0.05, fy + 2.3, "slider"])
				taken.append(Vector2(c - sw * 0.5 - 0.4, c + sw * 0.5 + 0.4))
				_balconies.append([fo, t, n, c, fy, 1.25, sw + 0.9])
			var before := out.size()
			_fill(out, taken, length, fy + 1.0, fy + 2.25, r, 1.2, 1.6, 2.6, "window")
			_ac_from(out, before, fo, t, n, r, 0.25)
			continue
		var before2 := out.size()
		if which == "front" or which == "back":
			_fill(out, taken, length, fy + 0.95, fy + 2.25, r, 1.4, 2.0, 3.0, "window")
		else:
			_fill(out, taken, length, fy + 1.0, fy + 2.2, r, 0.8, 1.4, 3.4, "window")
		_ac_from(out, before2, fo, t, n, r, 0.35)
	return out


## Whether a face of a wing looks into the plan's court (its outward normal points into it).
func _faces_court(w: Dictionary, which: String) -> bool:
	var c: Rect2 = h.court
	if c.size.x <= 0.0:
		return false
	var fc := _face(w, which)
	var fo: Vector2 = fc[0]
	var t: Vector2 = fc[1]
	var n: Vector2 = fc[2]
	var mid: Vector2 = fo + t * (float(fc[3]) * 0.5) + n * 1.0
	return c.grow(0.3).has_point(mid)


## A wall air conditioner under some of the windows just added.
func _ac_from(out: Array, from: int, fo: Vector2, t: Vector2, n: Vector2, r: RandomNumberGenerator, odds: float) -> void:
	for k in range(from, out.size()):
		if r.randf() < odds:
			_acs.append([fo, t, n, lerpf(float(out[k][0]), float(out[k][1]), r.randf_range(0.25, 0.75)), float(out[k][2])])


# --- The podium's gate and vents -----------------------------------------------------------------

func _opening(fo: Vector2, t: Vector2, n: Vector2, hl: Array, mat: String, cl: Color) -> void:
	var kind: String = hl[4]
	if kind != "gate" and kind != "vent":
		super._opening(fo, t, n, hl, mat, cl)
		return
	var dark := hl.duplicate()
	dark[4] = "dark"
	super._opening(fo, t, n, dark, mat, cl)
	var a0: float = hl[0]
	var a1: float = hl[1]
	var y0: float = hl[2]
	var y1: float = hl[3]
	var nw := N(n)
	if kind == "vent":
		# A breeze-block screen set back in the opening.
		var p0 := fo + t * a0 - n * 0.08
		var p1 := fo + t * a1 - n * 0.08
		var bc: Color = col.wall if _ap(["vent_c"]) < 0.5 else Color(0.93, 0.92, 0.88)
		_quad("h_breeze", L(p0, y0), L(p1, y0), L(p1, y1), L(p0, y1), nw, bc,
			[Vector2(0, 0), Vector2(a1 - a0, 0), Vector2(a1 - a0, y1 - y0), Vector2(0, y1 - y0)])
		return
	# The garage gate: a steel frame of square bars, rails top, middle and bottom, a lock box.
	var rail: Color = col.rail
	var gy0 := maxf(y0, -HouseKit.FLOOR_LIFT)
	var q0 := fo + t * a0 - n * 0.12
	var q1 := fo + t * a1 - n * 0.12
	var bars := int((a1 - a0) / 0.13)
	for k in bars + 1:
		var p := q0.lerp(q1, float(k) / maxf(bars, 1))
		_box("h_metal", p, gy0, y1 - 0.05, t, n, Vector2(0.012, 0.012), rail)
	for yy: float in [gy0 + 0.1, (gy0 + y1) * 0.5, y1 - 0.12]:
		_bar("h_metal", q0, q1, yy - 0.03, yy + 0.03, 0.025, rail)
	_box("h_metal", q0.lerp(q1, 0.5) + n * 0.05, gy0 + 1.0, gy0 + 1.3, t, n, Vector2(0.09, 0.04), rail.darkened(0.2))


# --- The rest --------------------------------------------------------------------------------------

func full() -> void:
	super.full()
	for g: Dictionary in h.galleries:
		_gallery(g)
	for s: Dictionary in h.stairs:
		_stair(s)
	for i in (h.wings as Array).size():
		var w: Dictionary = h.wings[i]
		if w.has("stoop"):
			_stoops(w)
	for b: Array in _balconies:
		var hw: float = float(b[6]) * 0.5
		_balcony(b[0], b[1], b[2], float(b[3]) - hw, float(b[3]) + hw, float(b[4]), float(b[5]))
		acc.shapes.append(_balcony_shape(b))
	for a: Array in _acs:
		_ac(a)
	if h.get("entry_arch", false):
		_entry_arch()
	_name_sign()
	_ground()


## A gallery: the slab at each floor on the outer edge of a face, a fascia, the rail, the posts to the
## ground and a canopy over the top floor's.
func _gallery(g: Dictionary) -> void:
	var w: Dictionary = h.wings[int(g.wing)]
	var fc := _face(w, g.face)
	var fo: Vector2 = fc[0]
	var t: Vector2 = fc[1]
	var n: Vector2 = fc[2]
	var a0: float = g.a0
	var a1: float = g.a1
	var d: float = g.depth
	var acc_c: Color = col.accent
	var rail_c: Color = col.rail
	var slab := Color(0.78, 0.76, 0.72)
	var mid := fo + t * ((a0 + a1) * 0.5)
	var floors: Array = g.floors
	var top_y := float(w.storeys) * STOREY
	for fl: int in floors:
		var y := float(fl) * STOREY
		_box("h_flat", mid + n * (d * 0.5), y - 0.22, y, t, n, Vector2((a1 - a0) * 0.5, d * 0.5), slab, true)
		_box("h_trim", mid + n * (d - 0.03), y - 0.34, y + 0.04, t, n, Vector2((a1 - a0) * 0.5 + 0.03, 0.04), acc_c, true)
		acc.shapes.append(_frame_box(mid + n * (d * 0.5), t, n, (a1 - a0), d, y - 0.22, y))
		# The rail along the outer edge, broken where a stair lands.
		var gaps: Array[Vector2] = []
		for s: Dictionary in h.stairs:
			if absf(float(s.y1) - y) < 0.05:
				var la := ((s.a as Vector2) + (s.dir as Vector2) * float(s.run) - fo).dot(t)
				var lb := ((s.a as Vector2) + (s.dir as Vector2) * (float(s.run) + Apartments.LANDING) - fo).dot(t)
				gaps.append(Vector2(minf(la, lb) + 0.05, maxf(la, lb) - 0.05))
		for sp: Vector2 in YardFill._spans(a0, a1, gaps):
			_rail(fo + t * sp.x + n * (d - 0.06), fo + t * sp.y + n * (d - 0.06), y, String(g.rail), rail_c)
		# The rails across each end.
		for e: float in [a0 + 0.04, a1 - 0.04]:
			_rail(fo + t * e + n * 0.05, fo + t * e + n * (d - 0.06), y, String(g.rail), rail_c)
	# The canopy over the top gallery (under a flat roof's parapet line or the eave).
	_box("h_trim", mid + n * (d * 0.5 + 0.05), top_y - 0.05, top_y + 0.22, t, n, Vector2((a1 - a0) * 0.5 + 0.05, d * 0.5 + 0.05), (col.trim as Color), true)
	# Steel posts at the outer edge, ground to canopy.
	if g.get("posts", false):
		var np := maxi(1, int((a1 - a0) / 3.4))
		for k in np + 1:
			var a := lerpf(a0 + 0.12, a1 - 0.12, float(k) / np)
			_box("h_metal", fo + t * a + n * (d - 0.1), -HouseKit.FLOOR_LIFT, top_y - 0.05, t, n, Vector2(0.06, 0.06), rail_c)


## A rail from frame point a to b at floor height y: pickets under a top rail, or a stucco half wall.
func _rail(a: Vector2, b: Vector2, y: float, kind: String, rail_c: Color) -> void:
	var len := a.distance_to(b)
	if len < 0.2:
		return
	var t := (b - a) / len
	var n := Vector2(-t.y, t.x)
	if kind == "solid":
		_box("h_wall", (a + b) * 0.5, y, y + 0.98, t, n, Vector2(len * 0.5, 0.06), col.wall, false)
		_box("h_trim", (a + b) * 0.5, y + 0.98, y + 1.05, t, n, Vector2(len * 0.5 + 0.02, 0.09), col.accent, true)
		return
	_bar("h_metal", a, b, y + 1.0, y + 1.05, 0.025, rail_c)
	_bar("h_metal", a, b, y + 0.08, y + 0.11, 0.015, rail_c)
	var cnt := int(len / 0.13)
	for k in cnt + 1:
		var p := a.lerp(b, float(k) / maxf(cnt, 1))
		_box("h_metal", p, y + 0.08, y + 1.0, t, n, Vector2(0.009, 0.009), rail_c)


## An open stair flight: steel stringers, concrete treads, pipe rails, the landing at its top.
func _stair(s: Dictionary) -> void:
	var a: Vector2 = s.a
	var dir: Vector2 = s.dir
	var out: Vector2 = s.out
	var y0: float = s.y0
	var y1: float = s.y1
	var risers: int = s.risers
	var run: float = s.run
	var W := Apartments.STAIR_W
	var rise := (y1 - y0) / float(risers)
	var steel: Color = col.accent if _ap(["stringer"]) < 0.5 else col.rail
	var tread_c := Color(0.74, 0.72, 0.68)
	for k in risers - 1:
		var top := y0 + float(k + 1) * rise
		var p := a + dir * ((float(k) + 0.5) * Apartments.TREAD) + out * (W * 0.5)
		_box("h_flat", p, top - 0.05, top, dir, out, Vector2(Apartments.TREAD * 0.5 + 0.01, W * 0.5 - 0.03), tread_c, true)
		_box("h_metal", p - dir * (Apartments.TREAD * 0.5 - 0.02), top - 0.09, top - 0.04, dir, out, Vector2(0.02, W * 0.5 - 0.03), steel)
	# The stringers: from the foot to the landing, each side.
	for side: float in [0.03, W - 0.03]:
		var p0 := a + out * side
		var p1 := a + dir * run + out * side
		_beam("h_metal", L(p0, y0 - 0.05), L(p1, y1 - rise - 0.02), N(out), 0.02, 0.14, steel)
		# The pipe rail, 0.9 m over the nosings, and its posts.
		var r0 := L(p0, y0 + rise + 0.9)
		var r1 := L(p1, y1 - rise + 0.9)
		_beam("h_metal", r0, r1, N(out), 0.022, 0.022, col.rail)
		for f: float in [0.0, 0.5, 1.0]:
			var pp := p0.lerp(p1, f)
			var yy := lerpf(y0 + rise, y1 - rise, f)
			_box("h_metal", pp, yy - 0.05, yy + 0.9, dir, out, Vector2(0.02, 0.02), col.rail)
	# The landing, reaching back to the gallery's edge.
	var lp := a + dir * (run + Apartments.LANDING * 0.5) + out * (W * 0.5 - 0.04)
	_box("h_flat", lp, y1 - 0.22, y1, dir, out, Vector2(Apartments.LANDING * 0.5, W * 0.5 + 0.04), Color(0.78, 0.76, 0.72), true)
	_box("h_trim", lp + out * (W * 0.5 + 0.02), y1 - 0.34, y1 + 0.04, dir, out, Vector2(Apartments.LANDING * 0.5 + 0.02, 0.04), col.accent, true)
	var le0 := a + dir * run + out * (W - 0.04)
	var le1 := a + dir * (run + Apartments.LANDING) + out * (W - 0.04)
	_rail(le0, le1, y1, "picket", col.rail)
	var continues := false
	for s2: Dictionary in h.stairs:
		if absf(float(s2.y0) - y1) < 0.05:
			continues = true
	if not continues:
		_rail(le1, a + dir * (run + Apartments.LANDING) + out * 0.02, y1, "picket", col.rail)
	# A post under the landing's outer corners.
	for q: Vector2 in [le0, le1]:
		_box("h_metal", q, -HouseKit.FLOOR_LIFT, y1 - 0.22, dir, out, Vector2(0.05, 0.05), steel)
	# Collision: the flight as a ramp, the landing as a box.
	var hull := PackedVector3Array()
	for q: Vector2 in [a, a + out * W]:
		hull.append(L(q, y0 - 0.02))
		hull.append(L(q + dir * run, y1 - rise))
		hull.append(L(q + dir * run, y1 - rise - 0.3))
		hull.append(L(q, y0 - 0.3))
	var cs := ConvexPolygonShape3D.new()
	cs.points = hull
	var shape := CollisionShape3D.new()
	shape.shape = cs
	acc.shapes.append(shape)
	acc.shapes.append(_frame_box(lp, dir, out, Apartments.LANDING, W + 0.08, y1 - 0.22, y1))


## A box between two 3D points: `side` its horizontal width direction, half widths hw (side) and hh
## (up, square to the run).
func _beam(name: String, p0: Vector3, p1: Vector3, side: Vector3, hw: float, hh: float, cl: Color) -> void:
	var d := p1 - p0
	if d.length() < 0.01:
		return
	var sd := side.normalized() * hw
	var up := side.cross(d).normalized()
	if up.y < 0.0:
		up = -up
	up *= hh
	var c0 := [p0 - sd - up, p0 + sd - up, p0 + sd + up, p0 - sd + up]
	var c1 := [p1 - sd - up, p1 + sd - up, p1 + sd + up, p1 - sd + up]
	var mid := (p0 + p1) * 0.5
	for k in 4:
		var k2 := (k + 1) % 4
		var nrm: Vector3 = (((c0[k] as Vector3) + (c0[k2] as Vector3)) * 0.5 - p0).normalized()
		_quad(name, c0[k], c0[k2], c1[k2], c1[k], nrm, cl)
	_quad(name, c0[0], c0[1], c0[2], c0[3], (p0 - mid).normalized(), cl)
	_quad(name, c1[0], c1[1], c1[2], c1[3], (p1 - mid).normalized(), cl)


## A collision box in the frame along t / n (HouseBuild._shape_box is along u / v).
func _frame_box(c: Vector2, t: Vector2, n: Vector2, lt: float, ln: float, y0: float, y1: float) -> CollisionShape3D:
	if absf(t.x) > 0.5:
		return _shape_box(c, lt, ln, y0, y1)
	return _shape_box(c, ln, lt, y0, y1)


func _balcony_shape(b: Array) -> CollisionShape3D:
	var fo: Vector2 = b[0]
	var t: Vector2 = b[1]
	var n: Vector2 = b[2]
	var depth: float = b[5]
	return _frame_box(fo + t * float(b[3]) + n * (depth * 0.5), t, n, float(b[6]), depth, float(b[4]) - 0.18, float(b[4]))


## A cottage's stoop: a concrete step and a little canopy over each door.
func _stoops(w: Dictionary) -> void:
	for d: Array in w.doors:
		var fc := _face(w, d[0])
		var fo: Vector2 = fc[0]
		var t: Vector2 = fc[1]
		var n: Vector2 = fc[2]
		var p := fo + t * float(d[1])
		_box("h_flat", p + n * 0.55, -HouseKit.FLOOR_LIFT - 0.1, -0.02, t, n, Vector2(0.8, 0.55), Color(0.78, 0.76, 0.72), true)
		_box("h_trim", p + n * 0.5, 2.45, 2.55, t, n, Vector2(0.85, 0.5), col.trim, true)
		for sx: float in [-0.75, 0.75]:
			_bar("h_trim", p + t * sx + n * 0.08, p + t * sx + n * 0.92, 2.25, 2.45, 0.03, col.trim)


## A wall air conditioner: a sleeve through the wall under the window, its grille facing out.
func _ac(a: Array) -> void:
	var fo: Vector2 = a[0]
	var t: Vector2 = a[1]
	var n: Vector2 = a[2]
	var at: float = a[3]
	var y: float = a[4]
	var p := fo + t * at + n * 0.2
	_box("h_metal", p, y - 0.55, y - 0.12, t, n, Vector2(0.33, 0.24), Color(0.80, 0.80, 0.77), true)
	_box("h_dark", p + n * 0.245, y - 0.5, y - 0.17, t, n, Vector2(0.28, 0.005), Color(0.22, 0.22, 0.21))
	# A drip stain down the stucco under it.
	var c: Color = (col.wall as Color).darkened(0.18)
	var q := fo + t * at + n * 0.012
	_quad("h_wall", L(q - t * 0.08, base + 0.3), L(q + t * 0.08, base + 0.3), L(q + t * 0.05, y - 0.55), L(q - t * 0.05, y - 0.55), N(n), c,
		[Vector2(0, base + 0.3), Vector2(0.16, base + 0.3), Vector2(0.16, y - 0.55), Vector2(0, y - 0.55)])


## A Spanish court's street wall: two stucco piers and an arch over the court's mouth, clay capped.
func _entry_arch() -> void:
	var c: Rect2 = h.court
	if c.size.x < 3.0:
		return
	var v := c.position.y
	var u0 := c.position.x
	var u1 := c.end.x
	var y1 := 3.6
	var span := minf(c.size.x - 1.2, 3.2)
	var mu := (u0 + u1) * 0.5
	var wall_c: Color = col.wall
	# The wall either side of the arch, to the wings.
	for e: Array in [[u0, mu - span * 0.5], [mu + span * 0.5, u1]]:
		var ea: float = e[0]
		var eb: float = e[1]
		if eb - ea > 0.1:
			_box("h_wall", Vector2((ea + eb) * 0.5, v), base + 0.2, y1, Vector2(1, 0), Vector2(0, 1), Vector2((eb - ea) * 0.5, 0.2), wall_c)
	# The lintel over the opening, its underside an arch of short faces.
	var crown := y1 - 0.45
	var spring := crown - span * 0.5
	_box("h_wall", Vector2(mu, v), crown, y1, Vector2(1, 0), Vector2(0, 1), Vector2(span * 0.5, 0.2), wall_c)
	var segs := HouseBuild.ARCH_SEGS
	for k in segs:
		var t0 := PI * float(k) / segs
		var t1 := PI * float(k + 1) / segs
		var pa := Vector2(mu - cos(t0) * span * 0.5, v)
		var pb := Vector2(mu - cos(t1) * span * 0.5, v)
		var ya := spring + sin(t0) * span * 0.5
		var yb := spring + sin(t1) * span * 0.5
		# The spandrel above each segment, front and back.
		for side: float in [-0.2, 0.2]:
			var o := Vector2(0, side)
			_quad("h_wall", L(pa + o, ya), L(pb + o, yb), L(pb + o, crown), L(pa + o, crown), N(Vector2(0, signf(side))), wall_c)
		_quad("h_wall", L(pa + Vector2(0, -0.2), ya), L(pb + Vector2(0, -0.2), yb), L(pb + Vector2(0, 0.2), yb), L(pa + Vector2(0, 0.2), ya), Vector3.DOWN, wall_c.darkened(0.08))
	_box("h_roof", Vector2((u0 + u1) * 0.5, v), y1, y1 + 0.16, Vector2(1, 0), Vector2(0, 1), Vector2((u1 - u0) * 0.5 + 0.1, 0.32), col.clay, true)
	for e: Array in [[u0, mu - span * 0.5], [mu + span * 0.5, u1]]:
		var ea2: float = e[0]
		var eb2: float = e[1]
		if eb2 - ea2 > 0.1:
			acc.shapes.append(_shape_box(Vector2((ea2 + eb2) * 0.5, v), eb2 - ea2, 0.4, base + 0.2, y1))
	# A lantern on the arch.
	_box("h_metal", Vector2(mu, v - 0.3), crown - 0.65, crown - 0.25, Vector2(1, 0), Vector2(0, 1), Vector2(0.12, 0.12), HouseBuild.IRON_LAMP)


## The building's name in metal script letters on the street face's parapet (a flat roof) or over the
## entry (a pitched one).
func _name_sign() -> void:
	var nm: String = h.get("name", "")
	if nm == "" or _ap(["named"]) > 0.7:
		return
	var w: Dictionary = h.wings[0]
	if w.get("spanish", false) or int(h.apt) == Apartments.Kind.BUNGALOW_COURT:
		return
	var fc := _face(w, "front")
	var fo: Vector2 = fc[0]
	var t: Vector2 = fc[1]
	var n: Vector2 = fc[2]
	var length: float = fc[3]
	var ye := float(w.storeys) * STOREY
	var hgt := 0.42
	var y := ye + HouseKit.PARAPET * 0.5 if w.roof == "flat" else ye - 0.55
	var geo := FreewayKit.text_geo(nm, hgt)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var width: float = geo[2]
	if width <= 0.0 or width > length - 1.0:
		return
	var at := length * (0.3 if _ap(["sign_at"]) < 0.5 else 0.7)
	at = clampf(at, width * 0.5 + 0.4, length - width * 0.5 - 0.4)
	var c: Color = Color(0.86, 0.84, 0.80) if _ap(["sign_c"]) < 0.6 else (col.accent as Color)
	var nw := N(n)
	var k := 0
	while k + 2 < idx.size():
		var tri: Array[Vector3] = []
		for m in 3:
			var v: Vector3 = verts[idx[k + m]]
			var p := fo + t * (at - v.x) + n * 0.035
			tri.append(L(p, y + v.y))
		_tri("h_metal", tri[0], tri[1], tri[2], nw, c)
		k += 3


## The court's ground and planting, and in midtown the whole lot's ground (no yard pass runs there).
func _ground() -> void:
	# The court and the lot ground are yard ground (YardFill's mesh): off with the yard fill's A/B.
	if not YardFill.enabled:
		return
	var f: Dictionary = h.f
	var court: Rect2 = h.court
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ps, seed, "apt_ground"])
	var full_level := ch.level == CityChunk.Level.FULL and not ch.capturing
	if court.size.x > 0.5:
		var kind: String = h.get("court_kind", "walk")
		match kind:
			"spanish":
				var beds := 1.0
				_lay(Rect2(court.position.x + beds, court.position.y, court.size.x - 2.0 * beds, court.size.y), YardFill.G_TILE, 0.3)
				_lay(Rect2(court.position.x, court.position.y, beds, court.size.y), YardFill.G_MULCH, 0.5)
				_lay(Rect2(court.end.x - beds, court.position.y, beds, court.size.y), YardFill.G_MULCH, 0.5)
				if full_level:
					var mid := Rect2(court.position.x + beds, court.position.y + court.size.y * 0.3, court.size.x - 2.0 * beds, court.size.y * 0.5)
					YardFill._dress_court(ch, YardFill._fr(f, mid.position.x, mid.position.y, mid.end.x, mid.end.y), YardFill.G_TILE, rng)
					_bed_planting(Rect2(court.position.x, court.position.y, beds, court.size.y), rng)
					_bed_planting(Rect2(court.end.x - beds, court.position.y, beds, court.size.y), rng)
			"bungalow":
				var walk := 1.5
				var cu := court.get_center().x
				_lay(Rect2(cu - walk * 0.5, court.position.y, walk, court.size.y), YardFill.G_CONCRETE, 0.2)
				var bed := 0.9
				for side in 2:
					var lu0 := court.position.x if side == 0 else cu + walk * 0.5
					var lu1 := cu - walk * 0.5 if side == 0 else court.end.x
					var b0 := lu0 if side == 0 else lu1 - bed
					_lay(Rect2(b0, court.position.y, bed, court.size.y), YardFill.G_MULCH, 0.4)
					var l0 := lu0 + (bed if side == 0 else 0.0)
					_lay(Rect2(l0, court.position.y, lu1 - lu0 - bed, court.size.y), YardFill.G_LAWN, 0.4)
					if full_level:
						_bed_planting(Rect2(b0, court.position.y, bed, court.size.y), rng)
				if full_level:
					for e: float in [court.position.y + 1.2, court.end.y - 1.2]:
						for side: float in [-1.0, 1.0]:
							var p := YardFill._fp(f, cu + side * (walk * 0.5 + 1.1), e)
							YardFill._palm(ch, p, rng)
			_:
				var walk2 := Apartments.GALLERY_D + 0.4
				# The walk under the galleries, the rest of the court a planted strip.
				var gal_left := court.position.x < (h.wings[0].r as Rect2).position.x
				var wu0 := court.end.x - walk2 if gal_left else court.position.x
				_lay(Rect2(wu0, court.position.y, walk2, court.size.y), YardFill.G_CONCRETE, 0.15)
				var pu0 := court.position.x if gal_left else court.position.x + walk2
				var plant := Rect2(pu0, court.position.y, court.size.x - walk2, court.size.y)
				# The stairs stand on the walk's edge: keep the planting off them.
				var holes: Array[Rect2] = []
				for r: Rect2 in h.extra_ground:
					holes.append(r)
				for piece: Rect2 in LotFill._minus(plant, holes, 0.0):
					_lay(piece, YardFill.G_MULCH if piece.size.x < 1.6 else YardFill.G_LAWN, 0.45)
				if full_level:
					_bed_planting(plant, rng)
				for r: Rect2 in h.extra_ground:
					_lay(r, YardFill.G_CONCRETE, 0.15)
	if not h.get("own_ground", false):
		return
	# Midtown: the rest of the cell, the front a lawn with a walk to the entry, the sides and back
	# concrete.
	var yard := Rect2(0.0, 0.0, float(f.U), float(f.V))
	var holes2: Array[Rect2] = []
	var front_v := float(f.V)
	for w: Dictionary in h.wings:
		holes2.append(w.r)
		front_v = minf(front_v, (w.r as Rect2).position.y)
	if court.size.x > 0.5:
		holes2.append(court)
	for r: Rect2 in h.extra_ground:
		holes2.append(r)
	var walk_r := Rect2(float(h.door_u) - 0.8, 0.0, 1.6, maxf(float(h.door_v), 0.1))
	var drive: Vector2 = h.drive
	if drive.y > drive.x:
		holes2.append(Rect2(drive.x, 0.0, drive.y - drive.x, float(h.drive_v)))
		_lay(Rect2(drive.x, 0.0, drive.y - drive.x, float(h.drive_v)), YardFill.G_CONCRETE, 0.6)
	holes2.append(walk_r)
	_lay(walk_r, YardFill.G_CONCRETE, 0.25)
	for piece: Rect2 in LotFill._minus(yard, holes2, 0.0):
		var front := piece.end.y <= front_v + 0.05
		var kind2 := YardFill.G_LAWN if front else YardFill.G_CONCRETE
		if not front and minf(piece.size.x, piece.size.y) < 1.2:
			kind2 = YardFill.G_MULCH
		_lay(piece, kind2, 0.35)
		if full_level and front and piece.size.x * piece.size.y > 6.0:
			_front_planting(piece, rng)


## A frame rect of yard ground.
func _lay(r: Rect2, kind: int, variant: float) -> void:
	if r.size.x < 0.3 or r.size.y < 0.3:
		return
	var f: Dictionary = h.f
	YardFill._ground(ch, YardFill._fr(f, r.position.x, r.position.y, r.end.x, r.end.y), kind, variant)


## Shrubs and flowers down a planting bed (frame rect).
func _bed_planting(r: Rect2, rng: RandomNumberGenerator) -> void:
	var f: Dictionary = h.f
	var along_v := r.size.y >= r.size.x
	var length := r.size.y if along_v else r.size.x
	var n := int(length / 2.6)
	for k in n:
		var s := (float(k) + 0.5) / n
		var p := Vector2(r.get_center().x, lerpf(r.position.y, r.end.y, s)) if along_v else Vector2(lerpf(r.position.x, r.end.x, s), r.get_center().y)
		if rng.randf() < 0.55:
			YardFill._shrub(ch, YardFill._fp(f, p.x, p.y), rng, 0.75)
		else:
			YardFill._flower(ch, YardFill._fp(f, p.x, p.y), rng)


## A midtown front lawn's planting: a shrub row along the building, a palm or a tree.
func _front_planting(r: Rect2, rng: RandomNumberGenerator) -> void:
	var f: Dictionary = h.f
	var row := Rect2(r.position.x, r.end.y - 0.8, r.size.x, 0.7)
	_bed_planting(row, rng)
	if r.size.y > 2.5 and rng.randf() < 0.7:
		var p := Vector2(lerpf(r.position.x + 1.0, r.end.x - 1.0, rng.randf()), r.position.y + r.size.y * 0.4)
		if rng.randf() < 0.6:
			YardFill._palm(ch, YardFill._fp(f, p.x, p.y), rng)
		else:
			YardFill._tree(ch, YardFill._fp(f, p.x, p.y), rng)


# --- Far ---------------------------------------------------------------------------------------------

func lod() -> void:
	super.lod()
	var plain := Color(0.0, 0.0, float(absi(seed) % 997) / 997.0, 1.0)
	for g: Dictionary in h.galleries:
		var w: Dictionary = h.wings[int(g.wing)]
		var fc := _face(w, g.face)
		var fo: Vector2 = fc[0]
		var t: Vector2 = fc[1]
		var n: Vector2 = fc[2]
		var mid := fo + t * ((float(g.a0) + float(g.a1)) * 0.5) + n * (float(g.depth) * 0.5)
		var top := float(w.storeys) * STOREY
		var lt := float(g.a1) - float(g.a0)
		var d: float = g.depth
		var sz := Vector3(absf(t.x) * lt + absf(t.y) * d, 0.3, absf(t.y) * lt + absf(t.x) * d)
		var wsz := _world_size(Rect2(Vector2.ZERO, Vector2(sz.x, sz.z)), 0.3)
		for fl: int in g.floors:
			_lod_add(Transform3D(Basis().scaled(wsz), W(mid.x, float(fl) * STOREY - 0.1, mid.y)), Color(0.78, 0.76, 0.72), plain)
		_lod_add(Transform3D(Basis().scaled(wsz), W(mid.x, top + 0.08, mid.y)), col.trim, plain)
	_ground()
