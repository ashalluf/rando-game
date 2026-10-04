class_name HouseBuild
extends RefCounted
## One house's geometry, from its HouseKit plan: FULL into the chunk's house surfaces (one per
## material for every house in the chunk, HouseKit.commit()), LOD as the city's LOD boxes plus roof
## slabs. The emitters follow ReplicaHouses' (walls cut on every opening's edges, reveals, glass set
## back in a frame, roofs with eaves, soffits and fascias), generalised to the types HouseKit plans:
## arched openings, porches, rafter tails, chimneys, butterfly and overhanging flat roofs, carports,
## tuck-under parking, solar panels and vents, a breeze-block screen.
##
## Everything is laid in the house's frame (HouseKit plan "f": `u` along the street, `v` back from
## the front edge of the yard) at a height `y` over the ground floor; the front of a wing is its
## low-v face and faces -v.

var ch: CityChunk
var h: Dictionary
var acc: HouseKit.Acc
var o: Vector2
var fu: Vector2
var fv: Vector2
## The ground floor's height (chunk space) and how far below it the walls reach.
var g: float = 0.0
var base: float = -0.6
var col: Dictionary
var pitch: float = 0.33
var eave: float = 0.6
var seed: int = 0
var ps: int = 0


func setup(chunk: CityChunk, house: Dictionary) -> void:
	ch = chunk
	h = house
	var f: Dictionary = h.f
	o = f.o
	fu = f.u
	fv = f.v
	col = h.colors
	pitch = h.pitch
	eave = h.eave
	seed = h.seed
	ps = ch.plan.seed
	var gmax := -INF
	var gmin := INF
	for r: Rect2 in HouseKit.ground_parts(h):
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var gy := ch._gy(c.x, c.y)
			gmax = maxf(gmax, gy)
			gmin = minf(gmin, gy)
	g = gmax + CityChunk.SIDEWALK_TOP + YardFill.LIFT + HouseKit.FLOOR_LIFT
	base = -(gmax - gmin) - HouseKit.FLOOR_LIFT - 0.3


# --- Frame ---------------------------------------------------------------------------------------

func P(u: float, v: float) -> Vector2:
	return o + fu * u + fv * v


func W(u: float, y: float, v: float) -> Vector3:
	var p := o + fu * u + fv * v
	return Vector3(p.x, g + y, p.y)


func L(p: Vector2, y: float) -> Vector3:
	return W(p.x, y, p.y)


## A frame direction (nu along u, nv along v) in world space.
func N(n: Vector2, y: float = 0.0) -> Vector3:
	var d := fu * n.x + fv * n.y
	return Vector3(d.x, y, d.y)


func _h(parts: Array) -> float:
	return float(absi(hash([ps, seed] + parts)) % 100003) / 100003.0


# --- Emitting --------------------------------------------------------------------------------------

func _st(name: String) -> SurfaceTool:
	if not acc.st.has(name):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		acc.st[name] = s
	return acc.st[name]


func _tri(name: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, cl: Color, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	var s := _st(name)
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	# The normal and the tangent are worked out here (flat, from the triangle and its UVs) rather
	# than by generate_normals() / generate_tangents() over the chunk's whole mesh at its finish,
	# which cost 10-30 ms in one step. Godot's front faces are clockwise.
	var e1 := b - a
	var e2 := c - a
	var nn := e2.cross(e1)
	if nn.length_squared() < 1e-12:
		return
	nn = nn.normalized()
	var d1 := ub - ua
	var d2 := uc - ua
	var r := d1.x * d2.y - d2.x * d1.y
	var tg: Vector3
	var bs := 1.0
	if absf(r) > 1e-9:
		tg = (e1 * d2.y - e2 * d1.y) / r
		var bt := (e2 * d1.x - e1 * d2.x) / r
		tg = (tg - nn * nn.dot(tg))
		if tg.length_squared() < 1e-12:
			tg = nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT)
		tg = tg.normalized()
		bs = -1.0 if nn.cross(tg).dot(bt) < 0.0 else 1.0
	else:
		tg = nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT).normalized()
	var tp := Plane(tg, bs)
	s.set_color(cl)
	s.set_normal(nn)
	s.set_tangent(tp)
	s.set_uv(ua)
	s.add_vertex(a)
	s.set_uv(ub)
	s.add_vertex(b)
	s.set_uv(uc)
	s.add_vertex(c)


func _quad(name: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, cl: Color, uv: Array = []) -> void:
	if uv.is_empty():
		_tri(name, a, b, c, n, cl)
		_tri(name, a, c, d, n, cl)
	else:
		_tri(name, a, b, c, n, cl, uv[0], uv[1], uv[2])
		_tri(name, a, c, d, n, cl, uv[0], uv[2], uv[3])


## A box in the frame: centre `p` (u, v), y0..y1, half sizes `hs` along `t` and `n`.
func _box(name: String, p: Vector2, y0: float, y1: float, t: Vector2, n: Vector2, hs: Vector2, cl: Color, bottom: bool = false) -> void:
	var ht := t * hs.x
	var hn := n * hs.y
	var c := [p - ht - hn, p + ht - hn, p + ht + hn, p - ht + hn]
	for k in 4:
		var a2: Vector2 = c[k]
		var b2: Vector2 = c[(k + 1) % 4]
		var out := ((a2 + b2) * 0.5 - p).normalized()
		var lw := a2.distance_to(b2)
		_quad(name, L(a2, y0), L(b2, y0), L(b2, y1), L(a2, y1), N(out), cl, [Vector2(0, y0 - base), Vector2(lw, y0 - base), Vector2(lw, y1 - base), Vector2(0, y1 - base)])
	_quad(name, L(c[0], y1), L(c[1], y1), L(c[2], y1), L(c[3], y1), Vector3.UP, cl)
	if bottom:
		_quad(name, L(c[0], y0), L(c[1], y0), L(c[2], y0), L(c[3], y0), Vector3.DOWN, cl.darkened(0.2))


## A box between two frame points, `r` thick each way (a bar, a post, a rafter).
func _bar(name: String, a: Vector2, b: Vector2, y0: float, y1: float, r: float, cl: Color) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var t := d.normalized()
	_box(name, (a + b) * 0.5, y0, y1, t, Vector2(-t.y, t.x), Vector2(d.length() * 0.5, r), cl)


# --- The whole house -------------------------------------------------------------------------------

func full() -> void:
	var wings: Array = h.wings
	for i in wings.size():
		_wing(i, wings[i])
	if not (h.porch as Dictionary).is_empty():
		_porch(h.porch)
	if not (h.chimney as Dictionary).is_empty():
		_chimney(h.chimney)
	_roof_extras()
	var br: Rect2 = h.breeze
	if br.size.x > 0.0:
		_breeze(br)
	_solids()


## Which wall material a wing wears, and the colour (alpha: the cladding's kind) it carries.
func _wall_paint(w: Dictionary) -> Array:
	match String(w.mat):
		"h_siding":
			var c: Color = col.stain if float(w.clad) < 0.25 else col.siding
			c.a = float(w.clad)
			return ["h_siding", c]
	return ["h_wall", col.wall]


func _wing(i: int, w: Dictionary) -> void:
	var r: Rect2 = w.r
	var u0 := r.position.x
	var u1 := r.end.x
	var v0 := r.position.y
	var v1 := r.end.y
	var storeys: int = w.storeys
	var roof: String = w.roof
	var ye := float(storeys) * HouseKit.STOREY
	var wp := _wall_paint(w)
	if w.role == "carport":
		_carport(w, ye)
		return
	var along_u := _along_u(w)
	var y_top := ye - 0.2
	if roof == "flat":
		y_top = ye + HouseKit.PARAPET
	elif roof == "deck" or roof == "butterfly":
		y_top = ye
	var faces := [
		["front", Vector2(u0, v0), Vector2(1, 0), Vector2(0, -1), u1 - u0],
		["back", Vector2(u1, v1), Vector2(-1, 0), Vector2(0, 1), u1 - u0],
		["left", Vector2(u0, v1), Vector2(0, -1), Vector2(-1, 0), v1 - v0],
		["right", Vector2(u1, v0), Vector2(0, 1), Vector2(1, 0), v1 - v0],
	]
	for face: Array in faces:
		var which: String = face[0]
		var fo: Vector2 = face[1]
		var t: Vector2 = face[2]
		var n: Vector2 = face[3]
		var length: float = face[4]
		var hidden := _hidden_spans(i, fo, t, n, length)
		var holes := _openings(i, w, which, fo, t, length, hidden)
		var top := y_top
		# A butterfly roof's high eaves are the front and back walls (its valley runs along u).
		if roof == "butterfly" and (which == "front" or which == "back"):
			top = ye + _butterfly_rise(w)
		_wall(fo, t, n, length, base, top, holes, wp[0], wp[1])
		if roof == "butterfly" and (which == "left" or which == "right"):
			_butterfly_end(fo, t, n, length, ye, _butterfly_rise(w), wp[0], wp[1])
	match roof:
		"hip":
			_hip(u0, u1, v0, v1, ye, along_u)
		"gable":
			# A front wing's roof runs back into the main roof, so its far gable end is buried in it.
			_gable(u0, u1, v0, v1 + float(w.get("roof_back", 0.0)), ye, along_u, wp[0], wp[1])
		"flat":
			_flat(u0, u1, v0, v1, ye, HouseKit.PARAPET, wp[0], wp[1])
		"deck":
			_deck(u0, u1, v0, v1, ye, eave)
		"butterfly":
			_butterfly(u0, u1, v0, v1, ye, _butterfly_rise(w))
	if h.get("rafters", false) and (roof == "gable" or roof == "hip"):
		_rafter_tails(u0, u1, v0, v1, ye, along_u, roof == "hip")
	if w.get("balcony", false) and storeys >= 2:
		var a0 := (u1 - u0) * 0.3
		var a1 := (u1 - u0) * 0.7
		_balcony(Vector2(u0, v0), Vector2(1, 0), Vector2(0, -1), a0, a1, HouseKit.STOREY, 1.1)


## Whether a wing's ridge runs along u: its plan says, else along its longer side.
func _along_u(w: Dictionary) -> bool:
	var r: Rect2 = w.r
	match int(w.ridge):
		1:
			return true
		2:
			return false
	return r.size.x >= r.size.y


func _butterfly_rise(w: Dictionary) -> float:
	var r: Rect2 = w.r
	return clampf((r.size.y * 0.5 + eave) * 0.16, 0.5, 1.2)


## The spans of a face (in its own `a`) another wing stands against: no openings there.
func _hidden_spans(i: int, fo: Vector2, t: Vector2, n: Vector2, length: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var wings: Array = h.wings
	for j in wings.size():
		if j == i:
			continue
		var q: Rect2 = (wings[j].r as Rect2).grow(0.05)
		# A thin probe just outside the face.
		var p0 := fo + n * 0.1
		var p1 := fo + t * length + n * 0.1
		var probe := Rect2(Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)), Vector2(absf(p1.x - p0.x), absf(p1.y - p0.y))).grow(0.01)
		if not probe.intersects(q):
			continue
		var ov := probe.intersection(q)
		var a0 := (ov.position - fo).dot(t)
		var a1 := (ov.end - fo).dot(t)
		out.append(Vector2(minf(a0, a1), maxf(a0, a1)))
	return out


# --- Openings ------------------------------------------------------------------------------------------

## Openings on one face of a wing, [a0, a1, y0, y1, kind] in the face's own coordinates.
func _openings(i: int, w: Dictionary, which: String, fo: Vector2, t: Vector2, length: float, hidden: Array[Vector2]) -> Array:
	var out: Array = []
	var taken: Array[Vector2] = hidden.duplicate()
	var style: int = h.style
	var storeys: int = w.storeys
	var role: String = w.role
	var face_rng := RandomNumberGenerator.new()
	face_rng.seed = hash([ps, seed, i, which])
	var st := HouseKit.STOREY
	if which == "front":
		# The garage door, the front door.
		var gd: Dictionary = h.garage
		if not gd.is_empty() and int(gd.wing) == i:
			var ga0 := (float(gd.u0) - fo.x)
			var ga1 := (float(gd.u1) - fo.x)
			if gd.kind == "tuck":
				var bays := maxi(1, int((ga1 - ga0) / 3.0))
				var bw := (ga1 - ga0) / bays
				for k in bays:
					out.append([ga0 + k * bw + 0.14, ga0 + (k + 1) * bw - 0.14, base + 0.02, 2.35, "dark"])
			else:
				out.append([ga0, ga1, base + 0.02, HouseKit.GARAGE_H - HouseKit.FLOOR_LIFT * 0.5, "garage"])
			taken.append(Vector2(ga0 - 0.5, ga1 + 0.5))
		var dr: Dictionary = h.door
		if not dr.is_empty() and int(dr.wing) == i:
			var da := float(dr.u) - fo.x
			var dw := HouseKit.DOOR_W + (0.25 if dr.kind == "arch_door" else 0.0)
			out.append([da - dw * 0.5, da + dw * 0.5, 0.0, (2.68 - dw * 0.5) if dr.kind == "arch_door" else HouseKit.DOOR_H, dr.kind])
			taken.append(Vector2(da - dw * 0.5 - 0.5, da + dw * 0.5 + 0.5))
		for fl in storeys:
			var fy := float(fl) * st
			if role == "garage":
				if fl > 0:
					_fill(out, taken, length, fy + 0.95, fy + 2.3, face_rng, 1.2, 1.6, 3.2)
				continue
			if w.get("tuck", false) and fl == 0:
				continue
			if w.get("arch", false) and fl == 0:
				# The arched picture window, the type's signature.
				var aw := minf(length - 1.4, face_rng.randf_range(1.6, 2.0))
				if aw > 1.0:
					var ac := _free_centre(taken, length, aw)
					if ac >= 0.0:
						out.append([ac - aw * 0.5, ac + aw * 0.5, 0.6, 2.62 - aw * 0.5, "arch_window"])
						taken.append(Vector2(ac - aw * 0.5 - 0.5, ac + aw * 0.5 + 0.5))
				continue
			match style:
				HouseKit.Style.MIDCENTURY:
					# A clerestory band under the roof, the street face kept private.
					_band(out, taken, length, fy + 1.95, fy + 2.7, 0.6)
				HouseKit.Style.CRAFTSMAN:
					_fill(out, taken, length, fy + 0.85, fy + 2.3, face_rng, 1.8, 2.3, 2.9, "grid")
				HouseKit.Style.RANCH:
					_fill(out, taken, length, fy + 0.95, fy + 2.25, face_rng, 1.8, 2.6, 3.4, "window")
				_:
					_fill(out, taken, length, fy + 0.9, fy + 2.3, face_rng, 1.1, 1.6, 2.8, "window")
	elif which == "back":
		for fl in storeys:
			var fy := float(fl) * st
			if role == "garage":
				_fill(out, taken, length, fy + 1.0, fy + 2.0, face_rng, 0.9, 1.1, 4.0)
				continue
			if fl == 0 and length >= 5.0:
				# A slider to the back yard (a wall of glass on a mid-century house).
				var sw := length * (0.55 if style == HouseKit.Style.MIDCENTURY else 0.28)
				var sc := _free_centre(taken, length, sw)
				if sc >= 0.0:
					out.append([sc - sw * 0.5, sc + sw * 0.5, 0.02, 2.3 if style != HouseKit.Style.MIDCENTURY else 2.75, "slider"])
					taken.append(Vector2(sc - sw * 0.5 - 0.6, sc + sw * 0.5 + 0.6))
			_fill(out, taken, length, fy + 0.95, fy + 2.25, face_rng, 1.0, 1.6, 3.2)
	else:
		for fl in storeys:
			var fy := float(fl) * st
			if role == "garage":
				continue
			var n := maxi(1, int(length / 4.5))
			for k in n:
				if face_rng.randf() < 0.4:
					continue
				var a := (float(k) + 0.5) * length / n
				var ww := face_rng.randf_range(0.8, 1.2)
				if _clash(taken, a - ww * 0.5, a + ww * 0.5):
					continue
				out.append([a - ww * 0.5, a + ww * 0.5, fy + 1.1, fy + 2.2, "window"])
				taken.append(Vector2(a - ww * 0.5 - 0.4, a + ww * 0.5 + 0.4))
	return out


func _clash(taken: Array[Vector2], a0: float, a1: float) -> bool:
	for sp: Vector2 in taken:
		if a1 > sp.x and a0 < sp.y:
			return true
	return false


## The centre nearest the face's middle where an opening `w` wide fits clear of `taken`; -1 if none.
func _free_centre(taken: Array[Vector2], length: float, w: float) -> float:
	var best := -1.0
	var k := 0
	while k <= 24:
		for sgn: float in [1.0, -1.0]:
			var c := length * 0.5 + sgn * float(k) * length / 48.0
			if c - w * 0.5 < 0.5 or c + w * 0.5 > length - 0.5:
				continue
			if not _clash(taken, c - w * 0.5, c + w * 0.5):
				return c
		k += 1
	return best


## Windows spread along a face, `lo`..`hi` wide, one per `pitch_m`, clear of `taken`.
func _fill(out: Array, taken: Array[Vector2], length: float, y0: float, y1: float, r: RandomNumberGenerator, lo: float, hi: float, pitch_m: float, kind: String = "window") -> void:
	var count := maxi(1, int(length / pitch_m))
	for k in count:
		var w := r.randf_range(lo, hi)
		var c := (float(k) + 0.5) * length / count
		var a0 := c - w * 0.5
		var a1 := c + w * 0.5
		if a0 < 0.5 or a1 > length - 0.5:
			continue
		if _clash(taken, a0 - 0.2, a1 + 0.2):
			continue
		out.append([a0, a1, y0, y1, kind])
		taken.append(Vector2(a0 - 0.3, a1 + 0.3))


## A continuous band of glass broken by `taken` (a clerestory).
func _band(out: Array, taken: Array[Vector2], length: float, y0: float, y1: float, margin: float) -> void:
	var a := margin
	var spans: Array[Vector2] = taken.duplicate()
	spans.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	for sp: Vector2 in spans:
		if sp.x - a > 1.0:
			out.append([a, sp.x, y0, y1, "clerestory"])
		a = maxf(a, sp.y)
	if length - margin - a > 1.0:
		out.append([a, length - margin, y0, y1, "clerestory"])


# --- Walls -------------------------------------------------------------------------------------------

## A wall from frame point `fo` along `t` for `length`, facing `n`, y0..y1, cut round `holes`. UV is
## metres along the wall and up from its foot (the siding reads it).
func _wall(fo: Vector2, t: Vector2, n: Vector2, length: float, y0: float, y1: float, holes: Array, mat: String, cl: Color) -> void:
	var xs: Array[float] = [0.0, length]
	var ys: Array[float] = [y0, y1]
	for hl: Array in holes:
		xs.append(clampf(hl[0], 0.0, length))
		xs.append(clampf(hl[1], 0.0, length))
		ys.append(clampf(hl[2], y0, y1))
		ys.append(clampf(_hole_top(hl), y0, y1))
	xs.sort()
	ys.sort()
	var nw := N(n)
	for xi in xs.size() - 1:
		var xa := xs[xi]
		var xb := xs[xi + 1]
		if xb - xa < 0.004:
			continue
		for yi in ys.size() - 1:
			var ya := ys[yi]
			var yb := ys[yi + 1]
			if yb - ya < 0.004:
				continue
			var mx := (xa + xb) * 0.5
			var my := (ya + yb) * 0.5
			var inside := false
			for hl: Array in holes:
				if mx > float(hl[0]) and mx < float(hl[1]) and my > float(hl[2]) and my < _hole_top(hl):
					inside = true
					break
			if inside:
				continue
			_quad(mat, L(fo + t * xa, ya), L(fo + t * xb, ya), L(fo + t * xb, yb), L(fo + t * xa, yb), nw, cl,
				[Vector2(xa, ya - base), Vector2(xb, ya - base), Vector2(xb, yb - base), Vector2(xa, yb - base)])
	for hl: Array in holes:
		_opening(fo, t, n, hl, mat, cl)


## The top of the rect cut for an opening (an arch's crown).
func _hole_top(hl: Array) -> float:
	if String(hl[4]).begins_with("arch"):
		return float(hl[3]) + (float(hl[1]) - float(hl[0])) * 0.5
	return float(hl[3])


func _opening(fo: Vector2, t: Vector2, n: Vector2, hl: Array, mat: String, cl: Color) -> void:
	var a0: float = hl[0]
	var a1: float = hl[1]
	var y0: float = hl[2]
	var y1: float = hl[3]
	var kind: String = hl[4]
	var arch := kind.begins_with("arch")
	var dep := HouseKit.REVEAL
	match kind:
		"garage":
			dep = 0.22
		"dark":
			dep = 4.5
		"slider", "door", "mod_door", "arch_door":
			dep = 0.2
	var back := -n * dep
	var p0 := fo + t * a0
	var p1 := fo + t * a1
	var reveal := cl.darkened(0.06)
	var rmat := mat if mat == "h_wall" else "h_trim"
	var rcol: Color = reveal if mat == "h_wall" else col.trim
	_quad(rmat, L(p0, y0), L(p0 + back, y0), L(p0 + back, y1), L(p0, y1), N(t), rcol)
	_quad(rmat, L(p1, y0), L(p1 + back, y0), L(p1 + back, y1), L(p1, y1), N(-t), rcol)
	if not arch:
		_quad(rmat, L(p0, y1), L(p1, y1), L(p1 + back, y1), L(p0 + back, y1), Vector3.DOWN, (rcol as Color).darkened(0.15))
	if y0 > base + 0.05:
		_quad(rmat, L(p0, y0), L(p1, y0), L(p1 + back, y0), L(p0 + back, y0), Vector3.UP, (rcol as Color).lightened(0.04))
	var q0 := p0 + back
	var q1 := p1 + back
	var nw := N(n)
	if arch:
		_arch(fo, t, n, a0, a1, y1, dep, mat, cl, rmat, rcol)
	match kind:
		"garage":
			var door: Color = col.garage
			var gy0 := maxf(y0, -HouseKit.FLOOR_LIFT)
			_quad("h_door", L(q0, gy0), L(q1, gy0), L(q1, y1), L(q0, y1), nw, door)
			# Sectional panels: four seams across, raised panels in bays; a row of lights on top
			# on a craftsman's or a Spanish house's (carriage style).
			for k in range(1, 4):
				var y := gy0 + (y1 - gy0) * k / 4.0
				_quad("h_door", L(q0 + n * 0.005, y - 0.016), L(q1 + n * 0.005, y - 0.016), L(q1 + n * 0.005, y + 0.016), L(q0 + n * 0.005, y + 0.016), nw, door.darkened(0.4))
			var bays := maxi(2, int(round((a1 - a0) / 0.75)))
			for k in range(1, bays):
				var pa := q0.lerp(q1, float(k) / bays) + n * 0.006
				_quad("h_door", L(pa - t * 0.012, gy0), L(pa + t * 0.012, gy0), L(pa + t * 0.012, y1), L(pa - t * 0.012, y1), nw, door.darkened(0.22))
			if h.style == HouseKit.Style.CRAFTSMAN or h.style == HouseKit.Style.SPANISH:
				var ly0 := gy0 + (y1 - gy0) * 0.78
				for k in bays:
					var la := q0.lerp(q1, (float(k) + 0.15) / bays) + n * 0.01
					var lb := q0.lerp(q1, (float(k) + 0.85) / bays) + n * 0.01
					_glass(la, lb, ly0, y1 - 0.08, n, 0.1)
			# The trim round it.
			_frame_ring(fo + t * a0 + n * 0.02, fo + t * a1 + n * 0.02, gy0, y1 + 0.08, t, n, col.trim, 0.09)
		"door", "mod_door", "arch_door":
			var dc: Color = col.door
			var dy1 := y1 if not arch else y1
			_quad("h_door", L(q0, y0), L(q1, y0), L(q1, dy1), L(q0, dy1), nw, dc)
			# Panels on a plain door, a tall light down a mid-century one.
			if kind == "mod_door":
				_glass(q0.lerp(q1, 0.62) + n * 0.01, q0.lerp(q1, 0.86) + n * 0.01, y0 + 0.2, dy1 - 0.2, n, 0.3)
			else:
				for k in 2:
					var py0 := y0 + 0.25 + float(k) * 0.95
					_quad("h_door", L(q0.lerp(q1, 0.18) + n * 0.008, py0), L(q0.lerp(q1, 0.82) + n * 0.008, py0),
						L(q0.lerp(q1, 0.82) + n * 0.008, py0 + 0.75), L(q0.lerp(q1, 0.18) + n * 0.008, py0 + 0.75), nw, dc.lightened(0.06))
			# A knob.
			_box("h_metal", q0.lerp(q1, 0.82) + n * 0.05, y0 + 0.95, y0 + 1.02, t, n, Vector2(0.03, 0.04), Color(0.75, 0.66, 0.42))
			if arch:
				_arch_glass(fo, t, n, a0, a1, y1, dep)
			_frame_ring(q0 + n * 0.01, q1 + n * 0.01, y0, dy1, t, n, col.frame, HouseKit.FRAME)
			# The light by the door.
			var lamp_a := a0 - 0.35 if a0 > 0.7 else a1 + 0.35
			_box("h_metal", fo + t * lamp_a + n * 0.08, y0 + 1.75, y0 + 2.05, t, n, Vector2(0.07, 0.07), IRON_LAMP)
		"dark":
			_quad("h_dark", L(q0, y0), L(q1, y0), L(q1, y1), L(q0, y1), nw, Color(0.06, 0.06, 0.06))
			_quad("h_dark", L(p0, y0 + 0.01), L(p1, y0 + 0.01), L(q1, y0 + 0.01), L(q0, y0 + 0.01), Vector3.UP, Color(0.2, 0.2, 0.2))
			_quad("h_dark", L(p0, y1), L(p1, y1), L(q1, y1), L(q0, y1), Vector3.DOWN, Color(0.12, 0.12, 0.12))
		_:
			_glass(q0, q1, y0, y1, n, _h([a0, y0]))
			_frame_ring(q0 + n * 0.012, q1 + n * 0.012, y0, y1, t, n, col.frame, HouseKit.FRAME)
			var width := a1 - a0
			var pitch_b := 1.2
			match kind:
				"slider":
					pitch_b = 1.5
				"clerestory":
					pitch_b = 1.2
				"picture":
					pitch_b = 9.0
				"arch_window":
					pitch_b = 0.7
				"grid":
					pitch_b = 0.55
				_:
					pitch_b = 0.85
			var bars := int(width / pitch_b)
			var by1 := y1
			if kind == "grid":
				# The craftsman sash: one bar across at the meeting rail, the upper sash in a grid.
				var my := lerpf(y0, y1, 0.58)
				_quad("h_trim", L(q0 + n * 0.02, my - 0.03), L(q1 + n * 0.02, my - 0.03), L(q1 + n * 0.02, my + 0.03), L(q0 + n * 0.02, my + 0.03), nw, col.frame)
				for k in range(1, bars + 1):
					var pa := q0.lerp(q1, float(k) / (bars + 1)) + n * 0.02
					_quad("h_trim", L(pa - t * 0.02, my), L(pa + t * 0.02, my), L(pa + t * 0.02, y1), L(pa - t * 0.02, y1), nw, col.frame)
			else:
				for k in range(1, bars + 1):
					var pa := q0.lerp(q1, float(k) / (bars + 1)) + n * 0.02
					_quad("h_trim", L(pa - t * 0.03, y0), L(pa + t * 0.03, y0), L(pa + t * 0.03, by1), L(pa - t * 0.03, by1), nw, col.frame)
			if arch:
				_arch_glass(fo, t, n, a0, a1, y1, dep)
			if kind == "window" or kind == "grid" or kind == "arch_window":
				# A sill proud of the wall, and on a stucco house a header band.
				_box("h_trim", (p0 + p1) * 0.5 + n * 0.035, y0 - 0.06, y0, t, n, Vector2(width * 0.5 + 0.07, 0.075), col.trim)
				if h.style == HouseKit.Style.CRAFTSMAN:
					_box("h_trim", (p0 + p1) * 0.5 + n * 0.03, y1, y1 + 0.16, t, n, Vector2(width * 0.5 + 0.1, 0.05), col.trim)
					_box("h_trim", p0 + n * 0.02 - t * 0.05, y0, y1, t, n, Vector2(0.05, 0.03), col.trim)
					_box("h_trim", p1 + n * 0.02 + t * 0.05, y0, y1, t, n, Vector2(0.05, 0.03), col.trim)


const IRON_LAMP := Color(0.14, 0.13, 0.12)


## A glass pane from frame point a to b, y0..y1, facing n. UV 0..1 across it, COLOR the blind
## colour with a per-window random in alpha (shaders/house_glass.gdshader).
func _glass(a: Vector2, b: Vector2, y0: float, y1: float, n: Vector2, rnd: float) -> void:
	var blind: Color = HouseKit.BLINDS[absi(hash([seed, a.x, a.y])) % HouseKit.BLINDS.size()]
	blind.a = rnd
	_quad("glass", L(a, y1), L(b, y1), L(b, y0), L(a, y0), N(n), blind, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])


func _frame_ring(q0: Vector2, q1: Vector2, y0: float, y1: float, t: Vector2, n: Vector2, cl: Color, fw: float) -> void:
	var nw := N(n)
	_quad("h_trim", L(q0, y1 - fw), L(q1, y1 - fw), L(q1, y1), L(q0, y1), nw, cl)
	_quad("h_trim", L(q0, y0), L(q1, y0), L(q1, y0 + fw), L(q0, y0 + fw), nw, cl)
	_quad("h_trim", L(q0, y0), L(q0 + t * fw, y0), L(q0 + t * fw, y1), L(q0, y1), nw, cl)
	_quad("h_trim", L(q1 - t * fw, y0), L(q1, y0), L(q1, y1), L(q1 - t * fw, y1), nw, cl)


const ARCH_SEGS := 8


## An arched opening's head: the wall filled in round the arch up to the rect's top, the reveal
## following the curve, a frame band round it.
func _arch(fo: Vector2, t: Vector2, n: Vector2, a0: float, a1: float, ys: float, dep: float, mat: String, cl: Color, rmat: String, rcol: Color) -> void:
	var r := (a1 - a0) * 0.5
	var ac := (a0 + a1) * 0.5
	var top := ys + r
	var nw := N(n)
	var back := -n * dep
	var pts: Array[Vector2] = []
	for k in ARCH_SEGS + 1:
		var ang := PI - PI * float(k) / ARCH_SEGS
		pts.append(Vector2(ac + cos(ang) * r, ys + sin(ang) * r))
	for k in ARCH_SEGS:
		var pa := pts[k]
		var pb := pts[k + 1]
		# The spandrel: a fan from the rect's top corner on this side.
		var corner := Vector2(a0, top) if k < ARCH_SEGS / 2 else Vector2(a1, top)
		_tri(mat, L(fo + t * corner.x, corner.y), L(fo + t * pa.x, pa.y), L(fo + t * pb.x, pb.y), nw, cl,
			Vector2(corner.x, corner.y - base), Vector2(pa.x, pa.y - base), Vector2(pb.x, pb.y - base))
		# The reveal under the curve, facing down and in.
		var inward := (Vector2(ac, ys) - (pa + pb) * 0.5).normalized()
		var nn := N(t * inward.x, inward.y)
		_quad(rmat, L(fo + t * pa.x, pa.y), L(fo + t * pb.x, pb.y), L(fo + t * pb.x + back, pb.y), L(fo + t * pa.x + back, pa.y), nn, rcol)
		# A frame band round the arch, just proud of the glass.
		var ia := Vector2(ac, ys) + (pa - Vector2(ac, ys)) * ((r - HouseKit.FRAME) / r)
		var ib := Vector2(ac, ys) + (pb - Vector2(ac, ys)) * ((r - HouseKit.FRAME) / r)
		var fb := back + n * 0.012
		_quad("h_trim", L(fo + t * pa.x + fb, pa.y), L(fo + t * pb.x + fb, pb.y), L(fo + t * ib.x + fb, ib.y), L(fo + t * ia.x + fb, ia.y), nw, col.frame)


## The glass in an arch's head (a fan over the opening's rect).
func _arch_glass(fo: Vector2, t: Vector2, n: Vector2, a0: float, a1: float, ys: float, dep: float) -> void:
	var r := (a1 - a0) * 0.5
	var ac := (a0 + a1) * 0.5
	var back := -n * dep
	var blind: Color = HouseKit.BLINDS[absi(hash([seed, a0, ys])) % HouseKit.BLINDS.size()]
	blind.a = _h([a0, "arch"])
	var nw := N(n)
	var c3 := L(fo + t * ac + back, ys)
	for k in ARCH_SEGS:
		var ang0 := PI - PI * float(k) / ARCH_SEGS
		var ang1 := PI - PI * float(k + 1) / ARCH_SEGS
		var pa := Vector2(ac + cos(ang0) * r, ys + sin(ang0) * r)
		var pb := Vector2(ac + cos(ang1) * r, ys + sin(ang1) * r)
		_tri("glass", c3, L(fo + t * pa.x + back, pa.y), L(fo + t * pb.x + back, pb.y), nw, blind,
			Vector2(0.5, 0.0), Vector2((pa.x - a0) / (2.0 * r), 0.0), Vector2((pb.x - a0) / (2.0 * r), 0.0))


# --- Roofs -----------------------------------------------------------------------------------------

func _roof_name() -> String:
	return h.roof_mat if h.roof_mat == "h_roof" else "h_shingle"


func _roof_color() -> Color:
	if h.roof_mat == "h_roof":
		return col.clay
	var c: Color = col.shingle
	c.a = 0.75 if int(h.shingle_kind) == 1 else 0.25
	return c


## A hipped roof over the rect, eaves at y: four planes up to a ridge along the longer side.
func _hip(u0: float, u1: float, v0: float, v1: float, y: float, along_u: bool) -> void:
	var U0 := u0 - eave
	var U1 := u1 + eave
	var V0 := v0 - eave
	var V1 := v1 + eave
	_eaves(u0, u1, v0, v1, U0, U1, V0, V1, y)
	var ew := U1 - U0
	var ed := V1 - V0
	if ew >= ed:
		var rise := ed * 0.5 * pitch
		var r0 := Vector2(U0 + ed * 0.5, (V0 + V1) * 0.5)
		var r1 := Vector2(U1 - ed * 0.5, (V0 + V1) * 0.5)
		var ry := y + rise
		_roof_plane(Vector2(U0, V1), Vector2(U1, V1), r1, r0, y, ry, Vector2(0, 1))
		_roof_plane(Vector2(U1, V0), Vector2(U0, V0), r0, r1, y, ry, Vector2(0, -1))
		_roof_plane(Vector2(U0, V0), Vector2(U0, V1), r0, r0, y, ry, Vector2(-1, 0))
		_roof_plane(Vector2(U1, V1), Vector2(U1, V0), r1, r1, y, ry, Vector2(1, 0))
		_ridge(r0, r1, ry)
	else:
		var rise := ew * 0.5 * pitch
		var r0 := Vector2((U0 + U1) * 0.5, V0 + ew * 0.5)
		var r1 := Vector2((U0 + U1) * 0.5, V1 - ew * 0.5)
		var ry := y + rise
		_roof_plane(Vector2(U1, V1), Vector2(U1, V0), r0, r1, y, ry, Vector2(1, 0))
		_roof_plane(Vector2(U0, V0), Vector2(U0, V1), r1, r0, y, ry, Vector2(-1, 0))
		_roof_plane(Vector2(U0, V1), Vector2(U1, V1), r1, r1, y, ry, Vector2(0, 1))
		_roof_plane(Vector2(U1, V0), Vector2(U0, V0), r0, r0, y, ry, Vector2(0, -1))
		_ridge(r0, r1, ry)


## A gabled roof: two planes on a ridge (along u or v), the gable ends walled in the wing's
## cladding, the rakes overhanging them.
func _gable(u0: float, u1: float, v0: float, v1: float, y: float, along_u: bool, mat: String, cl: Color) -> void:
	var U0 := u0 - eave
	var U1 := u1 + eave
	var V0 := v0 - eave
	var V1 := v1 + eave
	_eaves(u0, u1, v0, v1, U0, U1, V0, V1, y, along_u, not along_u)
	var tc: Color = (col.trim as Color).darkened(0.08)
	if along_u:
		var ry := y + (V1 - V0) * 0.5 * pitch
		var vm := (V0 + V1) * 0.5
		_roof_plane(Vector2(U0, V1), Vector2(U1, V1), Vector2(U1, vm), Vector2(U0, vm), y, ry, Vector2(0, 1))
		_roof_plane(Vector2(U1, V0), Vector2(U0, V0), Vector2(U0, vm), Vector2(U1, vm), y, ry, Vector2(0, -1))
		var ey := y + eave * pitch
		var wy := ey + ((v1 - v0) * 0.5) * pitch
		for e: Array in [[u0, -1.0, U0], [u1, 1.0, U1]]:
			var u: float = e[0]
			var nn := N(Vector2(e[1], 0))
			_quad(mat, W(u, y - 0.2, v0), W(u, y - 0.2, v1), W(u, ey, v1), W(u, ey, v0), nn, cl,
				[Vector2(v0, y - 0.2 - base), Vector2(v1, y - 0.2 - base), Vector2(v1, ey - base), Vector2(v0, ey - base)])
			_tri(mat, W(u, ey, v0), W(u, ey, v1), W(u, wy, (v0 + v1) * 0.5), nn, cl,
				Vector2(v0, ey - base), Vector2(v1, ey - base), Vector2((v0 + v1) * 0.5, wy - base))
			var UU: float = e[2]
			_quad("h_trim", W(u, y, V1), W(u, ry, vm), W(UU, ry, vm), W(UU, y, V1), Vector3.DOWN, tc)
			_quad("h_trim", W(u, y, V0), W(u, ry, vm), W(UU, ry, vm), W(UU, y, V0), Vector3.DOWN, tc)
			# The barge board along the rake.
			_rake(Vector2(UU, V0), Vector2(UU, vm), Vector2(UU, V1), y, ry, Vector2(e[1], 0))
			_gable_vent(u, Vector2(e[1], 0), v0, v1, ey, wy, true)
		_ridge(Vector2(U0, vm), Vector2(U1, vm), ry)
	else:
		var ry := y + (U1 - U0) * 0.5 * pitch
		var um := (U0 + U1) * 0.5
		_roof_plane(Vector2(U1, V1), Vector2(U1, V0), Vector2(um, V0), Vector2(um, V1), y, ry, Vector2(1, 0))
		_roof_plane(Vector2(U0, V0), Vector2(U0, V1), Vector2(um, V1), Vector2(um, V0), y, ry, Vector2(-1, 0))
		var ey := y + eave * pitch
		var wy := ey + ((u1 - u0) * 0.5) * pitch
		for e: Array in [[v0, -1.0, V0], [v1, 1.0, V1]]:
			var v: float = e[0]
			var nn := N(Vector2(0, e[1]))
			_quad(mat, W(u0, y - 0.2, v), W(u1, y - 0.2, v), W(u1, ey, v), W(u0, ey, v), nn, cl,
				[Vector2(u0, y - 0.2 - base), Vector2(u1, y - 0.2 - base), Vector2(u1, ey - base), Vector2(u0, ey - base)])
			_tri(mat, W(u0, ey, v), W(u1, ey, v), W((u0 + u1) * 0.5, wy, v), nn, cl,
				Vector2(u0, ey - base), Vector2(u1, ey - base), Vector2((u0 + u1) * 0.5, wy - base))
			var VV: float = e[2]
			_quad("h_trim", W(U1, y, v), W(um, ry, v), W(um, ry, VV), W(U1, y, VV), Vector3.DOWN, tc)
			_quad("h_trim", W(U0, y, v), W(um, ry, v), W(um, ry, VV), W(U0, y, VV), Vector3.DOWN, tc)
			_rake(Vector2(U0, VV), Vector2(um, VV), Vector2(U1, VV), y, ry, Vector2(0, e[1]))
			_gable_vent(v, Vector2(0, e[1]), u0, u1, ey, wy, false)
		_ridge(Vector2(um, V0), Vector2(um, V1), ry)


## The barge boards up a gable's two rakes (a-b, b-c in plan, a and c at the eave y, b at the ridge).
func _rake(a: Vector2, b: Vector2, c: Vector2, y: float, ry: float, out: Vector2) -> void:
	var nw := N(out)
	var d := 0.2
	var o2 := out * 0.03
	_quad("h_trim", L(a + o2, y - d), L(b + o2, ry - d), L(b + o2, ry + 0.02), L(a + o2, y + 0.02), nw, col.trim)
	_quad("h_trim", L(b + o2, ry - d), L(c + o2, y - d), L(c + o2, y + 0.02), L(b + o2, ry + 0.02), nw, col.trim)


## A louvred vent high in a gable end (a dark slot with a trim surround), on most of them.
func _gable_vent(at: float, out: Vector2, s0: float, s1: float, ey: float, wy: float, along_v: bool) -> void:
	if wy - ey < 1.0 or _h([at, "gvent"]) > 0.7:
		return
	var m := (s0 + s1) * 0.5
	var vy := ey + (wy - ey) * 0.45
	var w := 0.32
	var hh := 0.22
	var p := Vector2(at, m) if along_v else Vector2(m, at)
	var t := Vector2(0, 1) if along_v else Vector2(1, 0)
	var pc := p + out * 0.02
	var nw := N(out)
	_quad("h_trim", L(pc - t * (w + 0.06), vy - hh - 0.06), L(pc + t * (w + 0.06), vy - hh - 0.06), L(pc + t * (w + 0.06), vy + hh + 0.06), L(pc - t * (w + 0.06), vy + hh + 0.06), nw, col.trim)
	var pd := pc + out * 0.01
	for k in 4:
		var yy := vy - hh + (2.0 * hh) * (float(k) + 0.2) / 4.0
		_quad("h_dark", L(pd - t * w, yy), L(pd + t * w, yy), L(pd + t * w, yy + 0.06), L(pd - t * w, yy + 0.06), nw, Color(0.07, 0.07, 0.07))


## The soffit under an overhang and the fascia round its edge (`skip_u` / `skip_v`: a gable's rakes).
func _eaves(u0: float, u1: float, v0: float, v1: float, U0: float, U1: float, V0: float, V1: float, y: float, skip_u: bool = false, skip_v: bool = false) -> void:
	var fy := y - 0.2
	var tr: Color = col.trim
	var sof := tr.darkened(0.12)
	if not skip_v:
		_quad("h_trim", W(U0, fy, V1), W(U1, fy, V1), W(u1, fy, v1), W(u0, fy, v1), Vector3.DOWN, sof)
		_quad("h_trim", W(U1, fy, V0), W(U0, fy, V0), W(u0, fy, v0), W(u1, fy, v0), Vector3.DOWN, sof)
		_quad("h_trim", W(U0, fy, V1), W(U1, fy, V1), W(U1, y, V1), W(U0, y, V1), N(Vector2(0, 1)), tr)
		_quad("h_trim", W(U1, fy, V0), W(U0, fy, V0), W(U0, y, V0), W(U1, y, V0), N(Vector2(0, -1)), tr)
	if not skip_u:
		_quad("h_trim", W(U0, fy, V0), W(U0, fy, V1), W(u0, fy, v1), W(u0, fy, v0), Vector3.DOWN, sof)
		_quad("h_trim", W(U1, fy, V1), W(U1, fy, V0), W(u1, fy, v0), W(u1, fy, v1), Vector3.DOWN, sof)
		_quad("h_trim", W(U0, fy, V0), W(U0, fy, V1), W(U0, y, V1), W(U0, y, V0), N(Vector2(-1, 0)), tr)
		_quad("h_trim", W(U1, fy, V1), W(U1, fy, V0), W(U1, y, V0), W(U1, y, V1), N(Vector2(1, 0)), tr)


## One roof plane from eave edge a-b (at y) up to ridge points c-d (at ry); c == d makes a hip's
## triangle. UV: metres along the eave and up the slope.
func _roof_plane(a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, ry: float, out: Vector2) -> void:
	var e := (b - a).normalized()
	var slope := ry - y
	var run := absf((c - a).dot(out))
	var up_len := sqrt(run * run + slope * slope)
	var uvf := func(p: Vector2, py: float) -> Vector2:
		return Vector2((p - a).dot(e), (py - y) / maxf(slope, 0.001) * up_len)
	var n := N(out).normalized() * slope + Vector3(0, run, 0)
	var name := _roof_name()
	var rc := _roof_color()
	if c.distance_to(d) < 0.01:
		_tri(name, L(a, y), L(b, y), L(c, ry), n, rc, uvf.call(a, y), uvf.call(b, y), uvf.call(c, ry))
	else:
		_quad(name, L(a, y), L(b, y), L(c, ry), L(d, ry), n, rc, [uvf.call(a, y), uvf.call(b, y), uvf.call(c, ry), uvf.call(d, ry)])


## Ridge capping along the top.
func _ridge(r0: Vector2, r1: Vector2, ry: float) -> void:
	var d := r1 - r0
	if d.length() < 0.05:
		return
	var t := d.normalized()
	var n := Vector2(-t.y, t.x)
	var name := _roof_name()
	var rc := _roof_color()
	if name == "h_roof":
		_box(name, (r0 + r1) * 0.5, ry - 0.04, ry + 0.11, t, n, Vector2(d.length() * 0.5 + 0.1, 0.13), rc.darkened(0.08))
	else:
		_box(name, (r0 + r1) * 0.5, ry - 0.03, ry + 0.05, t, n, Vector2(d.length() * 0.5 + 0.05, 0.16), Color(rc.r * 0.85, rc.g * 0.85, rc.b * 0.85, rc.a))


## A flat roof behind a parapet: the membrane, the parapet's inner faces and a coping.
func _flat(u0: float, u1: float, v0: float, v1: float, y: float, parapet: float, mat: String, cl: Color) -> void:
	var t := 0.22
	_quad("h_flat", W(u0 + t, y, v0 + t), W(u1 - t, y, v0 + t), W(u1 - t, y, v1 - t), W(u0 + t, y, v1 - t), Vector3.UP, Color.WHITE)
	var top := y + parapet
	var ic := cl.darkened(0.08)
	_quad(mat, W(u0 + t, y, v1 - t), W(u1 - t, y, v1 - t), W(u1 - t, top, v1 - t), W(u0 + t, top, v1 - t), N(Vector2(0, -1)), ic)
	_quad(mat, W(u0 + t, y, v0 + t), W(u1 - t, y, v0 + t), W(u1 - t, top, v0 + t), W(u0 + t, top, v0 + t), N(Vector2(0, 1)), ic)
	_quad(mat, W(u0 + t, y, v0 + t), W(u0 + t, y, v1 - t), W(u0 + t, top, v1 - t), W(u0 + t, top, v0 + t), N(Vector2(1, 0)), ic)
	_quad(mat, W(u1 - t, y, v0 + t), W(u1 - t, y, v1 - t), W(u1 - t, top, v1 - t), W(u1 - t, top, v0 + t), N(Vector2(-1, 0)), ic)
	var cy := top + 0.07
	var tr: Color = col.trim if h.style != HouseKit.Style.DINGBAT else cl.lightened(0.2)
	_box("h_trim", Vector2((u0 + u1) * 0.5, v1 - t * 0.5), top, cy, Vector2(1, 0), Vector2(0, 1), Vector2((u1 - u0) * 0.5 + 0.04, t * 0.5 + 0.05), tr, true)
	_box("h_trim", Vector2((u0 + u1) * 0.5, v0 + t * 0.5), top, cy, Vector2(1, 0), Vector2(0, 1), Vector2((u1 - u0) * 0.5 + 0.04, t * 0.5 + 0.05), tr, true)
	_box("h_trim", Vector2(u0 + t * 0.5, (v0 + v1) * 0.5), top, cy, Vector2(0, 1), Vector2(1, 0), Vector2((v1 - v0) * 0.5 - t, t * 0.5 + 0.05), tr, true)
	_box("h_trim", Vector2(u1 - t * 0.5, (v0 + v1) * 0.5), top, cy, Vector2(0, 1), Vector2(1, 0), Vector2((v1 - v0) * 0.5 - t, t * 0.5 + 0.05), tr, true)
	# A condenser or two on the roof, and a parapet scupper.
	var k := absi(hash([seed, u0, "ac"])) % 3
	for i in k:
		var p := Vector2(lerpf(u0 + 1.4, u1 - 1.4, _h([i, "acu"])), lerpf(v0 + 1.4, v1 - 1.4, _h([i, "acv"])))
		_box("h_metal", p, y, y + 0.85, Vector2(1, 0), Vector2(0, 1), Vector2(0.45, 0.42), Color(0.74, 0.74, 0.72))


## A mid-century flat roof: a thin slab on a deep overhang, gravel on top, a fascia band, the
## soffit under it.
func _deck(u0: float, u1: float, v0: float, v1: float, y: float, over: float) -> void:
	var U0 := u0 - over
	var U1 := u1 + over
	var V0 := v0 - over
	var V1 := v1 + over
	var th := 0.32
	var fc: Color = col.trim if _h(["fascia"]) < 0.5 else Color(0.18, 0.18, 0.18)
	_quad("h_flat", W(U0, y + th, V0), W(U1, y + th, V0), W(U1, y + th, V1), W(U0, y + th, V1), Vector3.UP, Color.WHITE)
	_quad("h_trim", W(U0, y, V0), W(U1, y, V0), W(U1, y, V1), W(U0, y, V1), Vector3.DOWN, (col.trim as Color).darkened(0.1))
	_quad("h_trim", W(U0, y, V0), W(U1, y, V0), W(U1, y + th, V0), W(U0, y + th, V0), N(Vector2(0, -1)), fc)
	_quad("h_trim", W(U1, y, V1), W(U0, y, V1), W(U0, y + th, V1), W(U1, y + th, V1), N(Vector2(0, 1)), fc)
	_quad("h_trim", W(U0, y, V1), W(U0, y, V0), W(U0, y + th, V0), W(U0, y + th, V1), N(Vector2(-1, 0)), fc)
	_quad("h_trim", W(U1, y, V0), W(U1, y, V1), W(U1, y + th, V1), W(U1, y + th, V0), N(Vector2(1, 0)), fc)


## A butterfly roof: two planes falling from the front and back eaves to a valley down the middle
## (along u), on thin fascias, over a deep overhang.
func _butterfly(u0: float, u1: float, v0: float, v1: float, y: float, rise: float) -> void:
	var U0 := u0 - eave
	var U1 := u1 + eave
	var V0 := v0 - eave
	var V1 := v1 + eave
	var vm := (v0 + v1) * 0.5
	var th := 0.18
	var fc: Color = col.trim
	var hi := y + rise
	# The two top planes (gravel-coated membrane), their undersides, the fascias.
	for side: Array in [[V0, v0], [V1, v1]]:
		var VV: float = side[0]
		var out := Vector2(0, -1) if VV < vm else Vector2(0, 1)
		var slope_out := (hi - y) / absf(VV - vm)
		var hy := y + slope_out * absf(VV - vm)
		_quad("h_flat", W(U0, hy + th, VV), W(U1, hy + th, VV), W(U1, y + th, vm), W(U0, y + th, vm), Vector3(0, 1, 0) + N(-out) * 0.2, Color.WHITE)
		_quad("h_trim", W(U0, hy, VV), W(U1, hy, VV), W(U1, y, vm), W(U0, y, vm), Vector3.DOWN, (col.trim as Color).darkened(0.12))
		_quad("h_trim", W(U0, hy, VV), W(U1, hy, VV), W(U1, hy + th, VV), W(U0, hy + th, VV), N(out), fc)
		for e: Array in [[U0, -1.0], [U1, 1.0]]:
			var UU: float = e[0]
			_quad("h_trim", W(UU, hy, VV), W(UU, y, vm), W(UU, y + th, vm), W(UU, hy + th, VV), N(Vector2(e[1], 0)), fc)


## The V-topped end wall under a butterfly roof, between the eave line and its two high corners.
func _butterfly_end(fo: Vector2, t: Vector2, n: Vector2, length: float, ye: float, rise: float, mat: String, cl: Color) -> void:
	var nw := N(n)
	var hi := ye + rise * (length * 0.5) / (length * 0.5 + eave)
	var a := fo
	var m := fo + t * (length * 0.5)
	var b := fo + t * length
	_tri(mat, L(a, ye), L(a, hi), L(m, ye), nw, cl, Vector2(0, ye - base), Vector2(0, hi - base), Vector2(length * 0.5, ye - base))
	_tri(mat, L(m, ye), L(b, hi), L(b, ye), nw, cl, Vector2(length * 0.5, ye - base), Vector2(length, hi - base), Vector2(length, ye - base))


## A shed roof over a porch, sloping down toward the street from the wall at `hi` to `lo`.
func _shed(u0: float, u1: float, v0: float, v1: float, lo: float, hi: float) -> void:
	var a := Vector2(u0 - 0.15, v0 - 0.3)
	var b := Vector2(u1 + 0.15, v0 - 0.3)
	var c := Vector2(u1 + 0.15, v1)
	var d := Vector2(u0 - 0.15, v1)
	_roof_plane(a, b, c, d, lo, hi, Vector2(0, -1))
	var tr: Color = col.trim
	_quad("h_trim", L(a, lo - 0.18), L(b, lo - 0.18), L(b, lo), L(a, lo), N(Vector2(0, -1)), tr)
	_quad("h_trim", L(a, lo - 0.18), L(b, lo - 0.18), L(c, hi - 0.18), L(d, hi - 0.18), Vector3.DOWN, tr.darkened(0.12))
	for e: Array in [[a, d, -1.0], [b, c, 1.0]]:
		_quad("h_trim", L(e[0], lo - 0.18), L(e[1], hi - 0.18), L(e[1], hi), L(e[0], lo), N(Vector2(e[2], 0)), tr)


## Exposed rafter tails under a craftsman's eaves, every 0.6 m along the eave sides.
func _rafter_tails(u0: float, u1: float, v0: float, v1: float, y: float, along_u: bool, hip: bool) -> void:
	var tr: Color = col.trim
	var sides: Array = []
	if along_u or hip:
		sides.append([Vector2(u0, v0), Vector2(u1, v0), Vector2(0, -1)])
		sides.append([Vector2(u0, v1), Vector2(u1, v1), Vector2(0, 1)])
	if not along_u or hip:
		sides.append([Vector2(u0, v0), Vector2(u0, v1), Vector2(-1, 0)])
		sides.append([Vector2(u1, v0), Vector2(u1, v1), Vector2(1, 0)])
	for sd: Array in sides:
		var a: Vector2 = sd[0]
		var b: Vector2 = sd[1]
		var out: Vector2 = sd[2]
		var n := int(a.distance_to(b) / 0.6)
		for k in range(1, n):
			var p := a.lerp(b, float(k) / n)
			_bar("h_trim", p, p + out * (eave - 0.04), y - 0.36, y - 0.2, 0.035, tr)


# --- Porches, chimneys, the rest ---------------------------------------------------------------------

func _porch(pc: Dictionary) -> void:
	var r: Rect2 = pc.r
	var u0 := r.position.x
	var u1 := r.end.x
	var v0 := r.position.y
	var v1 := r.end.y
	var kind: String = pc.kind
	var deck_y := 0.0
	# The slab (a step's height below the floor on a stoop).
	var slab_top := deck_y - (0.0 if kind == "porch" else 0.04)
	_box("h_flat", Vector2((u0 + u1) * 0.5, (v0 + v1) * 0.5), base + 0.2, slab_top, Vector2(1, 0), Vector2(0, 1), Vector2((u1 - u0) * 0.5, (v1 - v0) * 0.5), CONCRETE_PORCH)
	# Steps down to the walk, centred on the door.
	var du: float = h.door_u
	var steps := 1 if kind != "porch" else 2
	for k in steps:
		var sy := slab_top - (float(k) + 1.0) * HouseKit.FLOOR_LIFT / float(steps + 1) * 1.3
		var sv := v0 - 0.32 * (float(k) + 1.0)
		_box("h_flat", Vector2(du, sv + 0.16), base + 0.2, sy, Vector2(1, 0), Vector2(0, 1), Vector2(0.75, 0.16), CONCRETE_PORCH)
	match kind:
		"porch":
			# Tapered columns on brick piers at the front corners (and the middle on a wide one),
			# a beam across, the porch's own front gable.
			var top: float = float(pc.top)
			var n := 2 if u1 - u0 < 7.0 else 3
			for k in n:
				var cu := lerpf(u0 + 0.35, u1 - 0.35, float(k) / float(n - 1))
				_box("h_brick", Vector2(cu, v0 + 0.35), base + 0.2, 0.95, Vector2(1, 0), Vector2(0, 1), Vector2(0.3, 0.3), Color.WHITE)
				_box("h_trim", Vector2(cu, v0 + 0.35), 0.95, 1.02, Vector2(1, 0), Vector2(0, 1), Vector2(0.34, 0.34), col.trim)
				_taper(Vector2(cu, v0 + 0.35), 1.02, top - 0.3, 0.2, 0.13, col.trim)
			_box("h_trim", Vector2((u0 + u1) * 0.5, v0 + 0.35), top - 0.3, top, Vector2(1, 0), Vector2(0, 1), Vector2((u1 - u0) * 0.5 + 0.1, 0.12), col.trim)
			var save := eave
			eave = minf(save, 0.55)
			var wp := _wall_paint(h.wings[h.door.wing])
			_gable(u0, u1, v0 + 0.1, v1 + 0.6, top, false, wp[0], wp[1])
			eave = save
		"shed":
			var top2: float = float(pc.top)
			for cu: float in [u0 + 0.2, u1 - 0.2]:
				_box("h_trim", Vector2(cu, v0 + 0.2), 0.0, top2 - 0.2, Vector2(1, 0), Vector2(0, 1), Vector2(0.08, 0.08), col.trim)
			_shed(u0, u1, v0, v1, top2 - 0.05, top2 + 0.45)
		"canopy":
			var top3: float = float(pc.top)
			for cu: float in [u0 + 0.15, u1 - 0.15]:
				_box("h_metal", Vector2(cu, v0 + 0.15), 0.0, top3, Vector2(1, 0), Vector2(0, 1), Vector2(0.04, 0.04), Color(0.2, 0.2, 0.2))
			_box("h_trim", Vector2((u0 + u1) * 0.5, (v0 + v1) * 0.5 + 0.1), top3, top3 + 0.12, Vector2(1, 0), Vector2(0, 1), Vector2((u1 - u0) * 0.5 + 0.3, (v1 - v0) * 0.5 + 0.2), col.trim, true)


const CONCRETE_PORCH := Color(0.78, 0.76, 0.72)


## A square column tapering from `w0` (half-width at its foot) to `w1` (at its top).
func _taper(p: Vector2, y0: float, y1: float, w0: float, w1: float, cl: Color) -> void:
	var cs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k in 4:
		var a: Vector2 = cs[k]
		var b: Vector2 = cs[(k + 1) % 4]
		var out := ((a + b) * 0.5).normalized()
		_quad("h_trim", L(p + a * w0, y0), L(p + b * w0, y0), L(p + b * w1, y1), L(p + a * w1, y1), N(out, (w0 - w1) / (y1 - y0)), cl)


## A chimney on the end wall of a wing: from the ground past the ridge, a cap and a flue.
func _chimney(cm: Dictionary) -> void:
	var w: Dictionary = h.wings[int(cm.wing)]
	var r: Rect2 = w.r
	var along_u := _along_u(w)
	var at_u: bool = along_u if not cm.get("side", false) else not along_u
	var end: int = cm.end
	var mat: String = cm.mat
	var cl: Color = Color.WHITE if mat == "h_brick" else col.wall
	var ye := float(w.storeys) * HouseKit.STOREY
	var rise := minf(r.size.x, r.size.y) * 0.5 * pitch + eave * pitch
	var top := ye + rise + 0.75
	var p: Vector2
	var t: Vector2
	var n: Vector2
	if at_u:
		# On the -u or +u end wall, a little back of centre.
		var u := r.position.x if end == 0 else r.end.x
		n = Vector2(-1, 0) if end == 0 else Vector2(1, 0)
		t = Vector2(0, 1)
		p = Vector2(u, lerpf(r.position.y, r.end.y, 0.62)) + n * 0.35
	else:
		var v := r.position.y if end == 0 else r.end.y
		n = Vector2(0, -1) if end == 0 else Vector2(0, 1)
		t = Vector2(1, 0)
		p = Vector2(lerpf(r.position.x, r.end.x, 0.7), v) + n * 0.35
	if cm.get("side", false):
		# Through the eave on a side wall: up to a little over the roof there.
		top = ye + (eave + 0.7) * pitch + 0.9
	_box(mat, p, base + 0.2, top, t, n, Vector2(0.62, 0.35), cl)
	_box(mat, p + n * 0.12, base + 0.2, 1.5, t, n, Vector2(0.8, 0.47), cl)
	_box("h_flat", p, top, top + 0.1, t, n, Vector2(0.7, 0.43), CONCRETE_PORCH, true)
	_box("h_dark", p, top + 0.1, top + 0.38, t, n, Vector2(0.14, 0.14), Color(0.15, 0.14, 0.13))
	if mat == "h_wall":
		# A Spanish chimney's little tiled hood.
		_box("h_roof", p, top + 0.38, top + 0.5, t, n, Vector2(0.4, 0.3), col.clay)


## Roof vents and solar panels on the main wing.
func _roof_extras() -> void:
	var wings: Array = h.wings
	var mi := 0
	for i in wings.size():
		if wings[i].role == "main":
			mi = i
	var w: Dictionary = wings[mi]
	var roof: String = w.roof
	if roof != "hip" and roof != "gable":
		return
	var r: Rect2 = w.r
	var ye := float(w.storeys) * HouseKit.STOREY
	var along_u := r.size.x >= r.size.y if roof == "hip" else _along_u(w)
	# The back plane (away from the street) carries the vents; the plane facing most to the south
	# (+z) the panels.
	for k in int(h.vents):
		var fu_ := _h([k, "vu"])
		var fv_ := _h([k, "vv"])
		var p := Vector2(lerpf(r.position.x + 1.0, r.end.x - 1.0, fu_), lerpf(r.get_center().y + 0.6, r.end.y - 0.4, fv_))
		if not along_u:
			p = Vector2(lerpf(r.get_center().x + 0.6, r.end.x - 0.4, fv_), lerpf(r.position.y + 1.0, r.end.y - 1.0, fu_))
		var y := ye + _roof_height(w, p)
		if k % 2 == 0:
			_box("h_metal", p, y - 0.1, y + 0.45, Vector2(1, 0), Vector2(0, 1), Vector2(0.05, 0.05), Color(0.30, 0.30, 0.30))
		else:
			_box("h_metal", p, y - 0.1, y + 0.22, Vector2(1, 0), Vector2(0, 1), Vector2(0.22, 0.22), Color(0.45, 0.45, 0.44))
	if h.solar:
		_solar(w, ye, along_u)


## The roof's height over the eave line at frame point p (equal-pitch planes: a hip is the nearest
## of its four eave lines, a gable the nearer of its two).
func _roof_height(w: Dictionary, p: Vector2) -> float:
	var r: Rect2 = (w.r as Rect2).grow(eave)
	var du := minf(p.x - r.position.x, r.end.x - p.x)
	var dv := minf(p.y - r.position.y, r.end.y - p.y)
	var d: float
	if w.roof == "hip":
		d = minf(du, dv)
	elif _along_u(w):
		d = dv
	else:
		d = du
	return maxf(d, 0.0) * pitch


## A rack of panels on the roof plane that looks most to the south, each 1.0 x 1.7 m with a gap,
## standing PANEL_LIFT off the roof on a dark skirt.
func _solar(w: Dictionary, ye: float, along_u: bool) -> void:
	var r: Rect2 = w.r
	# The two long planes face -v / +v (ridge along u) or -u / +u.
	var cands := [Vector2(0, -1), Vector2(0, 1)] if along_u else [Vector2(-1, 0), Vector2(1, 0)]
	var best := Vector2.ZERO
	var best_z := 0.35
	for c: Vector2 in cands:
		var d := N(c)
		if d.z > best_z:
			best_z = d.z
			best = c
	if best == Vector2.ZERO:
		return
	var run := (r.size.y if along_u else r.size.x) * 0.5 + eave
	var length := r.size.x if along_u else r.size.y
	var hip: bool = w.roof == "hip"
	var rows := clampi(int((run - 1.0) / 1.75), 0, 3)
	if rows == 0:
		return
	var y_eave := ye
	var cx := r.get_center()
	var e := Vector2(1, 0) if along_u else Vector2(0, 1)
	var up := -best
	# The eave line of that plane, in the frame, and the run up it.
	var eave_pt := cx + best * run
	var cl := Color(0.10, 0.13, 0.22)
	var frame_c := Color(0.75, 0.76, 0.78)
	var s0 := 0.6
	var nrm := N(best).normalized() * pitch + Vector3(0, 1, 0)
	nrm = nrm.normalized()
	for row in rows:
		var sa := s0 + float(row) * 1.75
		var sb := sa + 1.7
		# A hip's plane narrows going up; keep the row inside it.
		var half := length * 0.5 + eave - (sb + 0.4 if hip else 0.6)
		var cols := int((half * 2.0) / 1.03)
		if cols < 2:
			break
		cols = mini(cols, 8)
		var w0 := -float(cols) * 1.03 * 0.5
		for c in cols:
			var a0 := w0 + float(c) * 1.03
			var a1 := a0 + 1.0
			var pts: Array[Vector3] = []
			for q: Vector2 in [Vector2(a0, sa), Vector2(a1, sa), Vector2(a1, sb), Vector2(a0, sb)]:
				var pp := eave_pt + e * q.x + up * q.y
				pts.append(W(pp.x, y_eave + q.y * pitch, pp.y) + nrm * HouseKit.PANEL_LIFT)
			_quad("h_solar", pts[0], pts[1], pts[2], pts[3], nrm, cl)
		# The skirt and frame round the row.
		var ra := w0
		var rb := w0 + float(cols) * 1.03 - 0.03
		var corners: Array[Vector3] = []
		var lows: Array[Vector3] = []
		for q: Vector2 in [Vector2(ra, sa), Vector2(rb, sa), Vector2(rb, sb), Vector2(ra, sb)]:
			var pp := eave_pt + e * q.x + up * q.y
			var on := W(pp.x, y_eave + q.y * pitch, pp.y)
			corners.append(on + nrm * HouseKit.PANEL_LIFT)
			lows.append(on)
		for k in 4:
			var k2 := (k + 1) % 4
			var mid := (corners[k] + corners[k2]) * 0.5 - (corners[0] + corners[2]) * 0.5
			_quad("h_metal", lows[k], lows[k2], corners[k2], corners[k], mid.normalized(), frame_c)


## A breeze-block screen wall: a quad of the pattern on a low stuccoed footing with a cap.
func _breeze(r: Rect2) -> void:
	var u0 := r.position.x
	var u1 := r.end.x
	var v := r.get_center().y
	var hgt := 2.1
	var cl: Color = Color(0.93, 0.92, 0.88) if _h(["breeze_c"]) < 0.6 else col.wall
	var y0 := -HouseKit.FLOOR_LIFT + 0.3
	_box("h_wall", Vector2((u0 + u1) * 0.5, v), base + 0.2, y0, Vector2(1, 0), Vector2(0, 1), Vector2((u1 - u0) * 0.5 + 0.05, 0.1), col.wall)
	_quad("h_breeze", W(u0, y0, v), W(u1, y0, v), W(u1, hgt, v), W(u0, hgt, v), N(Vector2(0, -1)), cl,
		[Vector2(0, 0), Vector2(u1 - u0, 0), Vector2(u1 - u0, hgt - y0), Vector2(0, hgt - y0)])
	_box("h_trim", Vector2((u0 + u1) * 0.5, v), hgt, hgt + 0.08, Vector2(1, 0), Vector2(0, 1), Vector2((u1 - u0) * 0.5 + 0.06, 0.12), col.wall, true)
	acc.shapes.append(_shape_box(Vector2((u0 + u1) * 0.5, v), u1 - u0, 0.2, base + 0.2, hgt))


## A carport: four steel posts and the wing's deck roof, the slab under it.
func _carport(w: Dictionary, ye: float) -> void:
	var r: Rect2 = w.r
	for c: Vector2 in [r.position + Vector2(0.15, 0.15), Vector2(r.end.x - 0.15, r.position.y + 0.15), r.end - Vector2(0.15, 0.15), Vector2(r.position.x + 0.15, r.end.y - 0.15)]:
		_box("h_metal", c, -HouseKit.FLOOR_LIFT, ye, Vector2(1, 0), Vector2(0, 1), Vector2(0.05, 0.05), Color(0.2, 0.2, 0.2))
	_deck(r.position.x + 0.1, r.end.x - 0.1, r.position.y + 0.1, r.end.y - 0.1, ye, 0.25)
	# The back wall (the house's storage, a stuccoed end).
	_wall(Vector2(r.end.x, r.end.y), Vector2(-1, 0), Vector2(0, 1), r.size.x, base, ye, [], "h_wall", col.wall)
	_wall(Vector2(r.position.x, r.end.y - 0.15), Vector2(1, 0), Vector2(0, -1), r.size.x, base, ye, [], "h_wall", col.wall)


## A balcony on a wall: a slab out from it, an iron rail round its edge.
func _balcony(fo: Vector2, t: Vector2, n: Vector2, a0: float, a1: float, y: float, depth: float) -> void:
	var mid := fo + t * ((a0 + a1) * 0.5) + n * (depth * 0.5)
	_box("h_trim", mid, y - 0.18, y, t, n, Vector2((a1 - a0) * 0.5, depth * 0.5), col.trim, true)
	var e0 := fo + t * a0 + n * (depth - 0.04)
	var e1 := fo + t * a1 + n * (depth - 0.04)
	var w0 := fo + t * a0 + n * 0.02
	var w1 := fo + t * a1 + n * 0.02
	for pair: Array in [[e0, e1], [w0 + t * 0.04, e0 + t * 0.04], [w1 - t * 0.04, e1 - t * 0.04]]:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		_bar("h_metal", a, b, y + 1.0, y + 1.05, 0.025, HouseKit.IRON)
		var cnt := int(a.distance_to(b) / 0.14)
		for k in cnt + 1:
			var p := a.lerp(b, float(k) / maxf(cnt, 1))
			_box("h_metal", p, y, y + 1.0, t, n, Vector2(0.01, 0.01), HouseKit.IRON)


# --- Collision ------------------------------------------------------------------------------------

func _shape_box(c: Vector2, du: float, dv: float, y0: float, y1: float) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	var wu := N(Vector2(1, 0))
	var size := Vector3(absf(wu.x) * du + absf(wu.z) * dv, y1 - y0, absf(wu.z) * du + absf(wu.x) * dv)
	bx.size = size
	shape.shape = bx
	shape.position = W(c.x, (y0 + y1) * 0.5, c.y)
	return shape


func _solids() -> void:
	for w: Dictionary in h.wings:
		var r: Rect2 = w.r
		var ye := float(w.storeys) * HouseKit.STOREY
		var top := ye + (HouseKit.PARAPET if w.roof == "flat" else 0.0)
		if w.role == "carport":
			acc.shapes.append(_shape_box(Vector2(r.get_center().x, r.end.y - 0.1), r.size.x, 0.2, base, ye))
		else:
			acc.shapes.append(_shape_box(r.get_center(), r.size.x, r.size.y, base, top))
			ch._occluder_boxes.append([Transform3D(), W(r.get_center().x, (base + top) * 0.5, r.get_center().y), _world_size(r, top - base)])
		if w.roof == "hip" or w.roof == "gable":
			var hull := PackedVector3Array()
			var rr := r.grow(eave)
			for p: Vector2 in [rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]:
				hull.append(W(p.x, ye, p.y))
			var cu := rr.get_center()
			var hip: bool = w.roof == "hip"
			var along: bool = rr.size.x >= rr.size.y if hip else _along_u(w)
			var half := (rr.size.y if along else rr.size.x) * 0.5
			var inset := half if hip else 0.0
			var rise := half * pitch
			if along:
				hull.append(W(rr.position.x + inset, ye + rise, cu.y))
				hull.append(W(rr.end.x - inset, ye + rise, cu.y))
			else:
				hull.append(W(cu.x, ye + rise, rr.position.y + inset))
				hull.append(W(cu.x, ye + rise, rr.end.y - inset))
			var shape := CollisionShape3D.new()
			var cs := ConvexPolygonShape3D.new()
			cs.points = hull
			shape.shape = cs
			acc.shapes.append(shape)
		elif w.roof == "deck" or w.roof == "butterfly":
			var rr2 := r.grow(eave)
			acc.shapes.append(_shape_box(rr2.get_center(), rr2.size.x, rr2.size.y, ye, ye + 0.35))
	var pd: Dictionary = h.porch
	if not pd.is_empty():
		var pr: Rect2 = pd.r
		acc.shapes.append(_shape_box(pr.get_center(), pr.size.x, pr.size.y, base + 0.2, 0.0))


## A frame rect's size in world axes, `hgt` tall.
func _world_size(r: Rect2, hgt: float) -> Vector3:
	var wu := N(Vector2(1, 0))
	return Vector3(absf(wu.x) * r.size.x + absf(wu.z) * r.size.y, hgt, absf(wu.z) * r.size.x + absf(wu.x) * r.size.y)


# --- Far (LOD chunks, the far city) -------------------------------------------------------------------

## The city's LOD box for each wing, and for a pitched roof two slabs in the roof colour over a prism
## in the wall colour that closes the gable ends - in the `lod_box` batch, which the far city takes
## as it is. Plus the wings' collision where the chunk wants it, and their occluder.
func lod() -> void:
	var custom := Color(0.25, 0.32, float(absi(seed) % 997) / 997.0, 0.0)
	var plain := Color(0.0, 0.0, float(absi(seed) % 997) / 997.0, 1.0)
	var roof_far: Color = HouseKit.CLAY_FAR if h.roof_mat == "h_roof" else (col.shingle as Color).lightened(0.12)
	for w: Dictionary in h.wings:
		var r: Rect2 = w.r
		var ye := float(w.storeys) * HouseKit.STOREY
		var top := ye + (HouseKit.PARAPET if w.roof == "flat" else 0.0)
		var wall_c: Color = col.wall if w.mat == "h_wall" else (col.siding if float(w.clad) >= 0.25 else col.stain)
		var c := r.get_center()
		var size := _world_size(r, top - base)
		var centre := W(c.x, (base + top) * 0.5, c.y)
		_lod_add(Transform3D(Basis().scaled(size), centre), wall_c, custom if w.role != "carport" else plain)
		ch._add_lod_shape(size, centre)
		ch._occluder_boxes.append([Transform3D(), centre, size])
		if w.roof == "hip" or w.roof == "gable":
			_lod_roof(w, ye, roof_far, wall_c, plain)
		elif w.roof == "deck" or w.roof == "butterfly":
			# The overhang as a thin plain slab a little wider than the walls.
			var rr := r.grow(eave)
			var ds := _world_size(rr, 0.3)
			_lod_add(Transform3D(Basis().scaled(ds), W(c.x, ye + 0.15 + 0.16, c.y)), (col.trim as Color), plain)


## Adds a LOD box at a chunk-space transform (the batch lifts every instance by the relief at its
## origin, so that is taken off here).
func _lod_add(xf: Transform3D, cl: Color, custom: Color) -> void:
	var o3 := xf.origin
	o3.y -= ch._gy(o3.x, o3.z)
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(xf.basis, o3), cl, custom)


func _lod_roof(w: Dictionary, ye: float, roof_c: Color, wall_c: Color, plain: Color) -> void:
	var r: Rect2 = w.r
	var along_u := _along_u(w)
	if w.roof == "hip":
		along_u = r.size.x >= r.size.y
	var rr := r.grow(eave)
	var c := r.get_center()
	# Ridge direction and the across direction, in the world.
	var rd := N(Vector2(1, 0) if along_u else Vector2(0, 1)).normalized()
	var ac := N(Vector2(0, 1) if along_u else Vector2(1, 0)).normalized()
	var run := (rr.size.y if along_u else rr.size.x) * 0.5
	var length := rr.size.x if along_u else rr.size.y
	var rise := run * pitch
	var slope_len := sqrt(run * run + rise * rise)
	var th := 0.25
	var ridge_c := W(c.x, ye + rise, c.y)
	for sgn: float in [-1.0, 1.0]:
		# Down-slope: from the ridge outward along `ac * sgn` and down.
		var down := (ac * sgn * run + Vector3(0, -rise, 0)).normalized()
		var nrm := (ac * sgn * rise + Vector3(0, run, 0)).normalized()
		var mid := ridge_c + down * (slope_len * 0.5) - nrm * (th * 0.5)
		var bx := nrm * th
		var by := -down * slope_len
		var bz := rd * length
		if bx.cross(by).dot(bz) < 0.0:
			bz = -bz
		_lod_add(Transform3D(Basis(bx, by, bz), mid), roof_c, plain)
	# The prism under them: a square rotated 45 degrees about the ridge, its top at the ridge line
	# over the walls, filling the gable ends.
	var hh := (r.size.y if along_u else r.size.x) * 0.5 * pitch + eave * pitch
	var a := hh * sqrt(2.0)
	var wl := r.size.x if along_u else r.size.y
	var px := rd * wl
	var py := (Vector3.UP + ac).normalized() * a
	var pz := (Vector3.UP - ac).normalized() * a
	if px.cross(py).dot(pz) < 0.0:
		pz = -pz
	_lod_add(Transform3D(Basis(px, py, pz), W(c.x, ye, c.y)), wall_c, plain)
