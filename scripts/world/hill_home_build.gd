class_name HillHomeBuild
extends HouseBuild
## One hillside house from its HillHomeKit plan: HouseBuild's walls, openings, roofs and porches,
## with each wing at its own floor (`y`, a lower level a storey or two down the bank) and its own
## wall foot (`base`), floor-to-ceiling glass on the hillside glass shader (hill_glass.gdshader:
## a traced room in metres, lit after dark), soffits under whatever stands out over the slope, and
## the site HouseBuild has no notion of (site()): the pad and its walls, the steel frame under a
## cantilever, the deck and its cable rail, the pool, stairs down the bank, terraced gardens, the
## garage on stilts at the road, trees.

## The pad's top plus HouseKit.FLOOR_LIFT: every wing's `y` is over this.
var g0: float = 0.0
var top: float = 0.0
var Wp: float = 0.0
var Dp: float = 0.0
var m_pos := Vector2.ZERO


func setup_hill(chunk: CityChunk, house: Dictionary) -> void:
	ch = chunk
	h = house
	o = h.o
	fu = h.fu
	fv = h.fv
	col = h.colors
	pitch = h.pitch
	eave = h.eave
	seed = h.seed
	ps = ch.plan.seed
	g0 = h.floor
	top = h.top
	g = g0
	base = HillHomeKit.PAD_BASE
	Wp = h.Wp
	Dp = h.Dp
	m_pos = h.m_pos
	# HouseBuild's openings read the house type (garage glazing, sills).
	h["style"] = h.hstyle


# --- The house -------------------------------------------------------------------------------------

func full() -> void:
	var wings: Array = h.wings
	for i in wings.size():
		_wing(i, wings[i])
	_level(0.0, HillHomeKit.PAD_BASE)
	if not (h.porch as Dictionary).is_empty():
		_porch(h.porch)
	if not (h.chimney as Dictionary).is_empty():
		_chimney(h.chimney)
	_solids()


## Puts the frame's floor at a wing's level.
func _level(y: float, b: float) -> void:
	g = g0 + y
	base = b


func _wing(i: int, w: Dictionary) -> void:
	var save_eave := eave
	var save_wall: Color = col.wall
	_level(float(w.y), float(w.base))
	if float(w.eave) >= 0.0:
		eave = float(w.eave)
	if w.get("dark", false):
		col.wall = col.dark
	super._wing(i, w)
	var r: Rect2 = w.r
	# A soffit under whatever stands clear of the ground: an upper volume over the lower one and
	# past the pad, the overhang of a cantilever (its slab underside, between the beams).
	if float(w.y) > 0.5 or (r.end.y > Dp + 0.5 and float(w.y) > -0.5):
		var v0 := r.position.y if float(w.y) > 0.5 else Dp - 0.3
		_quad("h_trim", W(r.position.x, base, v0), W(r.end.x, base, v0), W(r.end.x, base, r.end.y), W(r.position.x, base, r.end.y), Vector3.DOWN, (col.trim as Color).darkened(0.18))
	col.wall = save_wall
	eave = save_eave
	_level(0.0, HillHomeKit.PAD_BASE)


## The spans of a face another wing stands against, counting only wings whose walls share its
## height (an upper volume does not hide the lower one's windows).
func _hidden_spans(i: int, fo: Vector2, t: Vector2, n: Vector2, length: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var wings: Array = h.wings
	var wi: Dictionary = wings[i]
	var a_lo: float = float(wi.y) + 0.2
	var a_hi: float = float(wi.y) + float(wi.storeys) * HouseKit.STOREY - 0.2
	for j in wings.size():
		if j == i:
			continue
		var wj: Dictionary = wings[j]
		var b_lo: float = float(wj.y) + maxf(float(wj.base), -0.5)
		var b_hi: float = float(wj.y) + float(wj.storeys) * HouseKit.STOREY
		if minf(a_hi, b_hi) - maxf(a_lo, b_lo) < 0.6:
			continue
		var q: Rect2 = (wj.r as Rect2).grow(0.05)
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


## Openings: glass walls, ribbon windows, arches, the garage on whichever face it opens to.
func _openings(i: int, w: Dictionary, which: String, fo: Vector2, t: Vector2, length: float, hidden: Array[Vector2]) -> Array:
	var out: Array = []
	var taken: Array[Vector2] = hidden.duplicate()
	var role: String = w.role
	var storeys: int = w.storeys
	var st := HouseKit.STOREY
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ps, seed, i, which, "hh"])
	if role == "garage":
		if which == String(w.get("gface", "front")):
			out.append([0.45, length - 0.45, base + 0.02, HouseKit.GARAGE_H - HouseKit.FLOOR_LIFT * 0.5, "garage"])
		return out
	var dr: Dictionary = h.door
	if which == "front" and not dr.is_empty() and int(dr.wing) == i:
		var da := float(dr.u) - fo.x
		var dw := HouseKit.DOOR_W + (0.35 if dr.kind == "arch_door" else 0.25)
		out.append([da - dw * 0.5, da + dw * 0.5, 0.0, (2.75 - dw * 0.5) if dr.kind == "arch_door" else 2.4, dr.kind])
		taken.append(Vector2(da - dw * 0.5 - 0.5, da + dw * 0.5 + 0.5))
	var glass: Array = w.glass
	var ribbon: Array = w.ribbon
	var arches: bool = w.arches
	for fl in storeys:
		var fy := float(fl) * st
		var tk: Array[Vector2] = taken.duplicate() if fl == 0 else hidden.duplicate()
		if which in glass:
			# Floor to ceiling, end to end but for the solid share of a side wall near the front.
			var a0 := 0.3
			var a1 := length - 0.3
			var solid: float = float(w.get("solid_front_share", 0.0)) * length
			if which == "left":
				a1 = length - maxf(solid, 0.3)
			elif which == "right":
				a0 = maxf(solid, 0.3)
			_span(out, tk, a0, a1, fy + 0.02, fy + 2.78, "slider")
		elif which in ribbon:
			_span(out, tk, 0.8, length - 0.8, fy + 0.95, fy + 2.4, "picture")
		elif arches:
			if role == "tower" and fl == storeys - 1:
				# The tower's top: a loggia of arches on every face.
				var n := maxi(1, int(length / 1.5))
				for k in n:
					var c := (float(k) + 0.5) * length / n
					var aw := minf(1.0, length / n - 0.35)
					out.append([c - aw * 0.5, c + aw * 0.5, fy + 0.85, fy + 2.55 - aw * 0.5, "arch_window"])
				continue
			if role == "lower" and which == "back":
				# The loggia: tall arches along the view.
				var n2 := maxi(1, int((length - 1.0) / 2.3))
				for k in n2:
					var c2 := 0.5 + (float(k) + 0.5) * (length - 1.0) / n2
					out.append([c2 - 0.8, c2 + 0.8, fy + 0.05, fy + 2.0, "arch_window"])
				continue
			if fl == 0 and (which == "front" or which == "back"):
				var pitch_m := 2.9 if which == "front" else 2.5
				var count := maxi(1, int(length / pitch_m))
				for k in count:
					var c3 := (float(k) + 0.5) * length / count
					var aw2 := 1.3 if which == "back" else 1.1
					if _clash(tk, c3 - aw2 * 0.5 - 0.2, c3 + aw2 * 0.5 + 0.2):
						continue
					out.append([c3 - aw2 * 0.5, c3 + aw2 * 0.5, fy + (0.1 if which == "back" else 0.75), fy + (2.05 if which == "back" else 2.0) - aw2 * 0.5 + 0.3, "arch_window"])
					tk.append(Vector2(c3 - aw2 * 0.5 - 0.3, c3 + aw2 * 0.5 + 0.3))
			else:
				if fl == 1 and which == "back" and w.get("balcony", false):
					var sw := minf(length * 0.3, 2.4)
					out.append([length * 0.5 - sw * 0.5, length * 0.5 + sw * 0.5, fy + 0.05, fy + 2.3, "slider"])
					tk.append(Vector2(length * 0.5 - sw * 0.5 - 0.4, length * 0.5 + sw * 0.5 + 0.4))
				_fill(out, tk, length, fy + 0.95, fy + 2.3, rng, 0.9, 1.25, 2.6, "grid")
		elif which == "front":
			if role == "lower":
				continue
			# A clerestory under the roof; the court side kept private.
			_band(out, tk, length, fy + 1.95, fy + 2.7, 0.6)
		elif role != "lower":
			_fill(out, tk, length, fy + 0.95, fy + 2.4, rng, 1.2, 2.0, 3.2, "window")
	return out


## One opening from a0 to a1, split round `taken`.
func _span(out: Array, taken: Array[Vector2], a0: float, a1: float, y0: float, y1: float, kind: String) -> void:
	var spans: Array[Vector2] = taken.duplicate()
	spans.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var a := a0
	for sp: Vector2 in spans:
		if sp.y <= a or sp.x >= a1:
			continue
		if sp.x - a > 1.0:
			out.append([a, sp.x, y0, y1, kind])
		a = maxf(a, sp.y)
	if a1 - a > 1.0:
		out.append([a, a1, y0, y1, kind])


## Glass on the hillside glass shader: UV in metres (along the pane, up from the storey's floor),
## COLOR the room's tone with a per-pane random in alpha.
func _glass(a: Vector2, b: Vector2, y0: float, y1: float, n: Vector2, rnd: float) -> void:
	var fl := floorf((maxf(y0, 0.0) + 0.3) / HouseKit.STOREY) * HouseKit.STOREY
	var len := a.distance_to(b)
	var tone: Color = ROOM_TONES[absi(hash([seed, a.x, a.y, "tone"])) % ROOM_TONES.size()]
	tone.a = rnd
	_quad("hh_glass", L(a, y1), L(b, y1), L(b, y0), L(a, y0), N(n), tone,
		[Vector2(0.0, y1 - fl), Vector2(len, y1 - fl), Vector2(len, y0 - fl), Vector2(0.0, y0 - fl)])


## An arch's glass (the fan over the opening's rect), on the hillside glass too.
func _arch_glass(fo: Vector2, t: Vector2, n: Vector2, a0: float, a1: float, ys: float, dep: float) -> void:
	var r := (a1 - a0) * 0.5
	var ac := (a0 + a1) * 0.5
	var back := -n * dep
	var tone: Color = ROOM_TONES[absi(hash([seed, a0, ys, "tone"])) % ROOM_TONES.size()]
	tone.a = _h([a0, "arch"])
	var fl := floorf((maxf(ys - 1.0, 0.0) + 0.3) / HouseKit.STOREY) * HouseKit.STOREY
	var nw := N(n)
	var c3 := L(fo + t * ac + back, ys)
	for k in ARCH_SEGS:
		var ang0 := PI - PI * float(k) / ARCH_SEGS
		var ang1 := PI - PI * float(k + 1) / ARCH_SEGS
		var pa := Vector2(ac + cos(ang0) * r, ys + sin(ang0) * r)
		var pb := Vector2(ac + cos(ang1) * r, ys + sin(ang1) * r)
		_tri("hh_glass", c3, L(fo + t * pa.x + back, pa.y), L(fo + t * pb.x + back, pb.y), nw, tone,
			Vector2(r, ys - fl), Vector2(pa.x - a0, pa.y - fl), Vector2(pb.x - a0, pb.y - fl))


## The rooms behind the glass: warm oak, pale stone, walnut and a cool white gallery.
const ROOM_TONES := [Color(0.62, 0.48, 0.34), Color(0.80, 0.76, 0.70), Color(0.40, 0.29, 0.21), Color(0.86, 0.86, 0.84), Color(0.70, 0.60, 0.48)]


func _solids() -> void:
	for w: Dictionary in h.wings:
		_level(float(w.y), float(w.base))
		var r: Rect2 = w.r
		var ye := float(w.storeys) * HouseKit.STOREY
		var t2 := ye + (HouseKit.PARAPET if w.roof == "flat" else 0.35)
		if w.role == "carport":
			acc.shapes.append(_shape_box(Vector2(r.get_center().x, r.end.y - 0.1), r.size.x, 0.2, base, ye))
			acc.shapes.append(_shape_box(r.get_center(), r.size.x, r.size.y, ye, ye + 0.35))
		else:
			acc.shapes.append(_shape_box(r.get_center(), r.size.x, r.size.y, base, t2))
			ch._occluder_boxes.append([Transform3D(), W(r.get_center().x, (base + ye) * 0.5, r.get_center().y), _world_size(r, ye - base)])
		if w.roof == "hip" or w.roof == "gable":
			var rr := r.grow(eave)
			var rise := minf(rr.size.x, rr.size.y) * 0.5 * pitch
			acc.shapes.append(_shape_box(rr.get_center(), rr.size.x * 0.7, rr.size.y * 0.7, ye, ye + rise * 0.7))
	_level(0.0, HillHomeKit.PAD_BASE)
	var pd: Dictionary = h.porch
	if not pd.is_empty():
		var pr: Rect2 = pd.r
		acc.shapes.append(_shape_box(pr.get_center(), pr.size.x, pr.size.y, base + 0.2, 0.0))


# --- The site ---------------------------------------------------------------------------------------

## A world point at frame (u, v), world height y.
func WY(u: float, v: float, y: float) -> Vector3:
	var p := o + fu * u + fv * v
	return Vector3(p.x, y, p.y)


func _ground(u: float, v: float) -> float:
	return ch.plan.height_at(o + fu * u + fv * v)


## A merged box in the frame: centre (u, v), world y0..y1, size along u and v.
func _sbox(mat: String, u: float, v: float, y0: float, y1: float, su: float, sv: float, collide: bool = false) -> void:
	_sboxm(HillHomeKit.site_material(mat), u, v, y0, y1, su, sv, collide)


func _sboxm(material: Material, u: float, v: float, y0: float, y1: float, su: float, sv: float, collide: bool = false) -> void:
	if y1 - y0 < 0.005:
		return
	var b := Basis(Vector3(fu.x, 0.0, fu.y) * su, Vector3(0.0, y1 - y0, 0.0), Vector3(fv.x, 0.0, fv.y) * sv)
	var c := WY(u, v, (y0 + y1) * 0.5)
	ch._merge_box_xf(material, Transform3D(b, c))
	if collide:
		ch._add_shape_xf(Vector3(su, y1 - y0, sv), Transform3D(Basis(Vector3(fu.x, 0.0, fu.y), Vector3.UP, Vector3(fv.x, 0.0, fv.y)), c))


## A merged bar between two world points, `r` thick.
func _sbar(mat: String, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var x := d / l
	var up := Vector3.UP if absf(x.y) < 0.95 else Vector3(fu.x, 0.0, fu.y)
	var z := x.cross(up).normalized()
	var y := z.cross(x).normalized()
	ch._merge_box_xf(HillHomeKit.site_material(mat), Transform3D(Basis(x * l, y * r * 2.0, z * r * 2.0), (a + b) * 0.5))


func site() -> void:
	pad_job()
	frame_job()
	garden_job()


# The FULL build's steps (HillHomeKit.build() queues them one a build step).
func pad_job() -> void:
	_pad(true)


func wing_job(i: int) -> void:
	_wing(i, h.wings[i])


func house_job() -> void:
	_level(0.0, HillHomeKit.PAD_BASE)
	if not (h.porch as Dictionary).is_empty():
		_porch(h.porch)
	if not (h.chimney as Dictionary).is_empty():
		_chimney(h.chimney)
	_solids()


func frame_job() -> void:
	_steel()
	_pool()


func garden_job() -> void:
	_stairs()
	_terraces()
	_road_garage()
	_trees()


## The steel frame under a cantilever: the slab's edge beams, the deck at the end with its cable
## rail, rows of columns down to footings on the slope, X bracing between them.
func _steel() -> void:
	var fi: int = h.frame_steel
	if fi < 0:
		_deck_only()
		return
	var w: Dictionary = h.wings[fi]
	var r: Rect2 = w.r
	var dk: Rect2 = h.deck
	var v_end := maxf(r.end.y, dk.end.y)
	var u0 := r.position.x
	var u1 := r.end.x
	var y_slab := g0 - HillHomeKit.SLAB
	var y_beam := y_slab - HillHomeKit.BEAM
	var vb := Dp - 0.5
	# The deck: planks at the floor, a slab under it, a cable rail round its open edges.
	if dk.size.x > 0.0:
		_sbox("deck", (u0 + u1) * 0.5, (dk.position.y + dk.end.y) * 0.5, g0 - 0.24, g0 - 0.02, u1 - u0, dk.size.y, true)
		_sbox("concrete", (u0 + u1) * 0.5, (dk.position.y + dk.end.y) * 0.5, y_slab, g0 - 0.24, u1 - u0, dk.size.y)
		_cable_rail([Vector2(u0 + 0.05, dk.position.y), Vector2(u0 + 0.05, v_end - 0.05), Vector2(u1 - 0.05, v_end - 0.05), Vector2(u1 - 0.05, dk.position.y)], g0 - 0.02)
	# Edge beams: along both sides of the overhang and across its end and the glass line.
	_sbox("steel", u0 + 0.12, (vb + v_end) * 0.5, y_beam, y_slab + 0.02, 0.24, v_end - vb)
	_sbox("steel", u1 - 0.12, (vb + v_end) * 0.5, y_beam, y_slab + 0.02, 0.24, v_end - vb)
	_sbox("steel", (u0 + u1) * 0.5, v_end - 0.12, y_beam, y_slab + 0.02, u1 - u0, 0.24)
	_sbox("steel", (u0 + u1) * 0.5, r.end.y, y_beam + 0.12, y_slab + 0.02, u1 - u0, 0.2)
	# Columns: a row under the deck's edge, and one under the middle of the overhang on a long one
	# (not through a lower level standing there).
	var rows: Array[float] = [v_end - 0.35]
	var lower := false
	for wl: Dictionary in h.wings:
		if wl.role == "lower":
			lower = true
	if not lower and v_end - Dp > 4.0:
		rows.append(Dp + (v_end - Dp) * 0.45)
	for rv in rows:
		var n := maxi(1, ceili((u1 - u0 - 0.6) / HillHomeKit.COLUMN_SPACING))
		var prev := Vector3.INF
		for k in n + 1:
			var cu := lerpf(u0 + 0.3, u1 - 0.3, float(k) / n)
			var gnd := _ground(cu, rv)
			if gnd > y_beam - 0.8:
				prev = Vector3.INF
				continue
			var c := HillHomeKit.COLUMN
			_sbox("steel", cu, rv, gnd - 0.4, y_beam, c * 2.0, c * 2.0)
			# A cap plate and a footing.
			_sbox("steel", cu, rv, y_beam - 0.03, y_beam, c * 3.2, c * 3.2)
			_sbox("concrete", cu, rv, gnd - 0.5, gnd + 0.35, 0.8, 0.8)
			ch._add_shape_xf(Vector3(c * 2.0, y_beam - gnd, c * 2.0), Transform3D(Basis(), WY(cu, rv, (y_beam + gnd) * 0.5)))
			var here := Vector3(cu, gnd, rv)
			if prev != Vector3.INF:
				# X bracing in the bay between this column and the last.
				var lo := maxf(prev.y, gnd) + 0.7
				var hi := y_beam - 0.25
				if hi - lo > 1.5:
					_sbar("steel", WY(prev.x, prev.z, hi), WY(cu, rv, lo), HillHomeKit.BRACE)
					_sbar("steel", WY(prev.x, prev.z, lo), WY(cu, rv, hi), HillHomeKit.BRACE)
			prev = here


## A deck on the pad's view edge for the types without a cantilever frame (nothing here yet).
func _deck_only() -> void:
	pass


## A cable rail along a polyline of frame points at deck height `y`: posts, a top rail, cables.
func _cable_rail(pts: Array, y: float) -> void:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var l := a.distance_to(b)
		var n := maxi(1, int(l / 1.6))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			_sbox("steel", p.x, p.y, y, y + HillHomeKit.RAIL_H, 0.05, 0.05)
		_sbar("steel", WY(a.x, a.y, y + HillHomeKit.RAIL_H), WY(b.x, b.y, y + HillHomeKit.RAIL_H), 0.035)
		for c in 4:
			var cy := y + 0.18 + float(c) * 0.21
			_sbar("steel", WY(a.x, a.y, cy), WY(b.x, b.y, cy), 0.006)


## The pool: water to its rim, a coping round it, on an infinity pool the far edge flush with the
## pad's edge spilling into a trough on the wall face below. Loungers on a stone deck beside it.
func _pool() -> void:
	var pl: Dictionary = h.pool
	if pl.is_empty():
		return
	var r: Rect2 = pl.r
	var inf: bool = pl.infinity
	var wy := top + 0.1
	var cop := 0.32
	var u0 := r.position.x
	var u1 := r.end.x
	var v0 := r.position.y
	var v1 := r.end.y
	# The stone deck round it.
	var sd := r.grow(1.6)
	sd.end = Vector2(sd.end.x, minf(sd.end.y, Dp - 0.05))
	_sbox("stone", sd.get_center().x, sd.get_center().y, top - 0.02, top + 0.06, sd.size.x, sd.size.y)
	# Coping: the near edge and both ends; the far one too on a plain pool.
	_sbox("coping", (u0 + u1) * 0.5, v0 - cop * 0.5, top, top + 0.16, u1 - u0 + cop * 2.0, cop)
	_sbox("coping", u0 - cop * 0.5, (v0 + v1) * 0.5, top, top + 0.16, cop, v1 - v0)
	_sbox("coping", u1 + cop * 0.5, (v0 + v1) * 0.5, top, top + 0.16, cop, v1 - v0)
	var wv1 := v1
	if inf:
		wv1 = Dp + 0.02
		# The vanishing edge: a thin sheet down the wall face into a trough.
		var ty := top - 0.75
		_sbox("coping", (u0 + u1) * 0.5, Dp + 0.35, ty - 0.35, ty, u1 - u0 + 0.4, 0.7)
		_sbox("coping", (u0 + u1) * 0.5, Dp + 0.68, ty, ty + 0.22, u1 - u0 + 0.4, 0.06)
		_quad("hh_water", WY(u0, Dp + 0.03, wy), WY(u1, Dp + 0.03, wy), WY(u1, Dp + 0.03, ty + 0.02), WY(u0, Dp + 0.03, ty + 0.02), N(Vector2(0, 1)), Color(1.0, 0.0, 0.0, 1.0),
			[Vector2(0, 0), Vector2(u1 - u0, 0), Vector2(u1 - u0, 1), Vector2(0, 1)])
		_quad("hh_water", WY(u0, Dp + 0.05, ty + 0.03), WY(u1, Dp + 0.05, ty + 0.03), WY(u1, Dp + 0.65, ty + 0.03), WY(u0, Dp + 0.65, ty + 0.03), Vector3.UP, Color(0.0, 0.3, 0.0, 1.0),
			[Vector2(0, 0), Vector2(u1 - u0, 0), Vector2(u1 - u0, 0.6), Vector2(0, 0.6)])
	else:
		_sbox("coping", (u0 + u1) * 0.5, v1 + cop * 0.5, top, top + 0.16, u1 - u0 + cop * 2.0, cop)
	# The water: COLOR.g the depth it reads as (0..1 over 2.5 m), UV metres.
	_quad("hh_water", WY(u0, v0, wy), WY(u1, v0, wy), WY(u1, wv1, wy), WY(u0, wv1, wy), Vector3.UP, Color(0.0, 0.85, 0.0, 1.0),
		[Vector2(0, 0), Vector2(u1 - u0, 0), Vector2(u1 - u0, wv1 - v0), Vector2(0, wv1 - v0)])
	# Loungers on the court side of the pool.
	var n := 2 + absi(hash([seed, "loungers"])) % 2
	for k in n:
		var lu := lerpf(u0 + 0.8, u1 - 0.8, (float(k) + 0.5) / n)
		var lv := v0 - 1.15
		if lv < float(h.vh):
			break
		_sbox("steel", lu, lv, top + 0.06, top + 0.3, 0.7, 1.9)
		_sbox("cushion", lu, lv + 0.15, top + 0.3, top + 0.4, 0.64, 1.5)
		_sbar("cushion", WY(lu, lv - 0.6, top + 0.38), WY(lu, lv - 0.95, top + 0.85), 0.03)


## Stairs down the bank to a lower level: solid steps with cheek walls.
func _stairs() -> void:
	for st: Array in h.stairs:
		var a: Vector2 = st[0]
		var b: Vector2 = st[1]
		var y0: float = g0 + float(st[2])
		var y1: float = g0 + float(st[3])
		var wdt: float = st[4]
		var n := maxi(2, roundi((y0 - y1) / 0.17))
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		for k in n:
			var p := a.lerp(b, (float(k) + 0.5) / n)
			var ty := lerpf(y0, y1, float(k + 1) / n)
			var gnd := _ground(p.x, p.y)
			var by := minf(gnd - 0.3, ty - 0.4)
			var run := a.distance_to(b) / n
			var su := absf(side.x) * wdt + absf(dir.x) * run
			var sv := absf(side.y) * wdt + absf(dir.y) * run
			_sbox("coping", p.x, p.y, by, ty, su, sv, k % 3 == 0)
			for sg: float in [-1.0, 1.0]:
				var cp := p + side * sg * (wdt * 0.5 + 0.1)
				_sbox("concrete", cp.x, cp.y, by, ty + 0.9, absf(side.x) * 0.2 + absf(dir.x) * run, absf(side.y) * 0.2 + absf(dir.y) * run)


## Terraced gardens below the pad's free view edge: retaining walls stepping down the bank, each
## holding a strip of clipped hedge along its top.
func _terraces() -> void:
	for fr: Vector2 in h.terraces:
		for vs: float in HillHomeKit.TERRACE_STEPS:
			var v := Dp + vs
			var hi := -INF
			var lo := INF
			for f: float in [0.1, 0.5, 0.9]:
				var u := lerpf(fr.x, fr.y, f)
				hi = maxf(hi, _ground(u, v - 0.6))
				lo = minf(lo, _ground(u, v + 0.6))
			if hi - lo < 0.4:
				continue
			var wt := minf(hi + 0.35, lo + 3.5)
			_sbox("terrace", (fr.x + fr.y) * 0.5, v, lo - 0.6, wt, fr.y - fr.x, 0.45)
			_sbox("coping", (fr.x + fr.y) * 0.5, v, wt, wt + 0.07, fr.y - fr.x + 0.1, 0.55)
			_sbox("hedge", (fr.x + fr.y) * 0.5, v - 0.75, hi - 0.2, maxf(wt, hi) + 0.75, fr.y - fr.x - 0.4, 0.8)


## A garage up at the road on steel stilts, its door to the road, a stair down to the drive.
func _road_garage() -> void:
	var rg: Dictionary = h.road_garage
	if rg.is_empty():
		return
	var c: Vector2 = rg.c
	var dir: Vector2 = rg.dir
	var side := Vector2(-dir.y, dir.x)
	var fy: float = rg.y
	var gw := 6.4
	var gd := 6.6
	var hgt := 3.1
	var wall_m := PropFactory.material(col.wall, 0.9)
	var bx := Vector3(side.x, 0.0, side.y)
	var bz := Vector3(dir.x, 0.0, dir.y)
	var at := func(s: float, d: float, y: float) -> Vector3:
		return Vector3(c.x + side.x * s + dir.x * d, y, c.y + side.y * s + dir.y * d)
	var box := func(mat: Material, s: float, d: float, y0: float, y1: float, ss: float, sd: float) -> void:
		ch._merge_box_xf(mat, Transform3D(Basis(bx * ss, Vector3(0.0, y1 - y0, 0.0), bz * sd), at.call(s, d, (y0 + y1) * 0.5)))
	# The floor slab, the back and side walls, the roof, the door across the road side.
	box.call(HillHomeKit.site_material("concrete"), 0.0, 0.0, fy - 0.35, fy, gw, gd)
	box.call(wall_m, 0.0, -gd * 0.5 + 0.12, fy, fy + hgt, gw, 0.24)
	box.call(wall_m, -gw * 0.5 + 0.12, 0.0, fy, fy + hgt, 0.24, gd)
	box.call(wall_m, gw * 0.5 - 0.12, 0.0, fy, fy + hgt, 0.24, gd)
	box.call(HillHomeKit.site_material("coping"), 0.0, 0.1, fy + hgt, fy + hgt + 0.32, gw + 0.6, gd + 0.8)
	box.call(wall_m, 0.0, gd * 0.5 - 0.12, fy + 2.4, fy + hgt, gw, 0.24)
	box.call(PropFactory.material(col.garage, 0.55), 0.0, gd * 0.5 - 0.2, fy, fy + 2.4, gw - 0.6, 0.06)
	ch._add_shape_xf(Vector3(gw, hgt + 0.35, gd), Transform3D(Basis(bx, Vector3.UP, bz), at.call(0.0, 0.0, fy + hgt * 0.5 - 0.17)))
	# Stilts to the slope.
	for s: float in [-gw * 0.5 + 0.3, gw * 0.5 - 0.3]:
		for d: float in [-gd * 0.5 + 0.3, gd * 0.5 - 0.3]:
			var p: Vector3 = at.call(s, d, 0.0)
			var gnd := ch.plan.height_at(Vector2(p.x, p.z))
			if gnd < fy - 0.8:
				ch._merge_box_xf(HillHomeKit.site_material("steel"), Transform3D(Basis().scaled(Vector3(0.3, fy - 0.35 - gnd + 0.4, 0.3)), Vector3(p.x, (fy - 0.35 + gnd - 0.4) * 0.5, p.z)))
	# A stair down beside it toward the pad, until it meets the drive's ground.
	var y := fy
	var k := 0
	while k < 40:
		var p2: Vector3 = at.call(-gw * 0.5 - 0.8, -gd * 0.5 + 0.3 - float(k) * 0.29, 0.0)
		var gnd2 := ch.plan.height_at(Vector2(p2.x, p2.z))
		y -= 0.17
		if y <= gnd2 + 0.05:
			break
		ch._merge_box_xf(HillHomeKit.site_material("coping"), Transform3D(Basis(bx * 1.2, Vector3(0.0, y - gnd2 + 0.3, 0.0), bz * 0.3), Vector3(p2.x, (y + gnd2 - 0.3) * 0.5, p2.z)))
		k += 1


## Cypress, olives and palms.
func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ps, seed, "hh_trees"])
	for tr: Array in h.trees:
		var kind: String = tr[0]
		var p: Vector2 = tr[1]
		var hgt: float = tr[2]
		var on_pad := p.y < Dp - 0.1 and p.y > 0.1 and p.x > 0.1 and p.x < Wp - 0.1
		var gy := top if on_pad else _ground(p.x, p.y)
		var wp := o + fu * p.x + fv * p.y
		var at := Vector3(wp.x, gy - 0.1, wp.y)
		match kind:
			"cypress":
				var s := PropFactory.hill_tree_scale(0, hgt)
				_badd("hh_cypress", PropFactory.model_hill_tree(0), Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s * 0.3, s, s * 0.3)), at),
					Color(rng.randf_range(0.8, 0.95), rng.randf_range(0.95, 1.1), rng.randf_range(0.8, 0.95)))
			"olive":
				var s2 := PropFactory.city_tree_scale(0, hgt)
				_badd("tree_0", PropFactory.model_tree(0), Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s2 * 1.15, s2, s2 * 1.15)), at),
					Color(rng.randf_range(0.78, 0.86), rng.randf_range(0.9, 0.98), rng.randf_range(0.8, 0.88)), Color(rng.randf(), rng.randf(), 0.8, 0.25))
			"palm":
				ch._add_palm(at + Vector3(0.0, 0.1, 0.0), rng)


## A batch instance at a world transform (the batch lifts by the relief when its lift is on).
func _badd(key: String, mesh: Mesh, xf: Transform3D, cl: Color, custom: Color = Color(0, 0, 0, 0)) -> void:
	var o3 := xf.origin
	if ch._batch.ground.is_valid():
		o3.y -= ch._gy(o3.x, o3.z)
	ch._batch.add(key, mesh, Transform3D(xf.basis, o3), cl, custom)


# --- The pad -----------------------------------------------------------------------------------------

## The graded pad (pavers, one box), and at FULL its walls - each side whatever the ground beyond
## it makes it (CityChunk._build_mansions' rule: a garden wall where the hillside is level with the
## pad, a retaining wall holding the cut back where it stands above, one dropping down the fill
## where the pad stands out over the slope) - the gate between two piers. The view side's wall
## stops flush with the pad where the house, the deck, the pool or a stair stand at the edge, and
## carries a rail (a stucco parapet on a villa) elsewhere.
func _pad(detail: bool) -> void:
	var pad: Vector3 = h.pad
	var pad_m := PropFactory.pbr("pavers", 3.0, Color(0.93, 0.9, 0.85))
	_sboxm(pad_m, Wp * 0.5, Dp * 0.5, top - pad.y, top, Wp, Dp, detail)
	if not detail:
		return
	ch.building_count += 1
	var villa: bool = int(h.style) == HillHomeKit.Style.VILLA
	var stucco := PropFactory.material(col.wall, 0.9)
	var retain: Material = HillHomeKit.site_material("retain_villa" if villa else ("board_concrete" if _h(["retain"]) < 0.5 else "concrete"))
	var gate: Vector2 = h.gate
	var gate_gap := 5.2
	# [start, direction along, outward normal, length] in the frame.
	var sides := [[Vector2(0, 0), Vector2(1, 0), Vector2(0, -1), Wp], [Vector2(Wp, 0), Vector2(0, 1), Vector2(1, 0), Dp],
		[Vector2(0, 0), Vector2(0, 1), Vector2(-1, 0), Dp], [Vector2(0, Dp), Vector2(1, 0), Vector2(0, 1), Wp]]
	var open := _open_spans()
	for sd: Array in sides:
		var s0: Vector2 = sd[0]
		var t: Vector2 = sd[1]
		var n: Vector2 = sd[2]
		var length: float = sd[3]
		var view := n.y > 0.5
		# Pieces of the side: the gate leaves a gap in the side it is on.
		var pieces: Array[Vector2] = [Vector2(0.0, length)]
		var ga := (gate - s0).dot(t)
		var on_side := absf((gate - s0).dot(n)) < 0.6 and ga > 0.0 and ga < length
		if on_side:
			pieces = [Vector2(0.0, ga - gate_gap * 0.5), Vector2(ga + gate_gap * 0.5, length)]
		for pc: Vector2 in pieces:
			if pc.y - pc.x < 0.3:
				continue
			var hi := -INF
			var lo := INF
			for f: float in [0.05, 0.5, 0.95]:
				var q := s0 + t * lerpf(pc.x, pc.y, f) + n * 2.5
				var gq := _ground(q.x, q.y)
				hi = maxf(hi, gq)
				lo = minf(lo, gq)
			var thick := 0.5
			var mat: Material = stucco
			var y0 := top
			var y1 := top + 1.1
			if hi - top > 1.2:
				mat = retain
				y1 = top + clampf(hi - top + 0.4, 1.4, 4.5)
				thick = 0.7
			elif top - lo > 1.2:
				mat = retain
				y0 = top - clampf(top - lo + 1.5, 2.0, 9.0)
				y1 = top + 1.0
				thick = 0.7
			if view and y1 <= top + 1.05:
				# Flush with the pad: the parapet or rail goes only where nothing stands at the edge.
				y1 = top + 0.02
				if y0 >= top:
					y0 = top - 0.8
			var c := s0 + t * ((pc.x + pc.y) * 0.5) - n * thick * 0.5
			var su := absf(t.x) * (pc.y - pc.x) + absf(n.x) * thick
			var sv := absf(t.y) * (pc.y - pc.x) + absf(n.y) * thick
			_sboxm(mat, c.x, c.y, y0, y1, su, sv, true)
			_sbox("coping", c.x, c.y, y1, y1 + 0.08, su + 0.1, sv + 0.1)
			if view:
				for fr: Vector2 in _minus(Vector2(pc.x, pc.y), open):
					if fr.y - fr.x < 0.8:
						continue
					if villa:
						var cc := s0 + t * ((fr.x + fr.y) * 0.5) - n * 0.15
						var fu2 := absf(t.x) * (fr.y - fr.x) + absf(n.x) * 0.3
						var fv2 := absf(t.y) * (fr.y - fr.x) + absf(n.y) * 0.3
						_sboxm(stucco, cc.x, cc.y, y1, y1 + 0.95, fu2, fv2, true)
						_sbox("coping", cc.x, cc.y, y1 + 0.95, y1 + 1.03, fu2 + 0.1, fv2 + 0.1)
					else:
						var a := s0 + t * fr.x - n * 0.12
						var b := s0 + t * fr.y - n * 0.12
						_cable_rail([a, b], y1)
	# Gate piers and the gate.
	var gt := Vector2(1, 0)
	var gn := Vector2(0, -1)
	if gate.x < 0.6:
		gt = Vector2(0, 1)
		gn = Vector2(-1, 0)
	elif gate.x > Wp - 0.6:
		gt = Vector2(0, 1)
		gn = Vector2(1, 0)
	var gc := gate - gn * 0.35
	for sx: float in [-1.0, 1.0]:
		var pp := gc + gt * sx * (gate_gap * 0.5 + 0.35)
		_sboxm(stucco, pp.x, pp.y, top, top + 2.4, 0.75, 0.75, true)
		_sbox("coping", pp.x, pp.y, top + 2.4, top + 2.5, 0.9, 0.9)
	var gm := CityChunk.ESTATE_GATE_MATERIAL()
	_sboxm(gm, gc.x, gc.y, top + 0.1, top + 1.8, absf(gt.x) * (gate_gap - 0.1) + absf(gn.x) * 0.08, absf(gt.y) * (gate_gap - 0.1) + absf(gn.y) * 0.08, true)


## The u spans of the view edge something stands at (no rail there).
func _open_spans() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for w: Dictionary in h.wings:
		var r: Rect2 = w.r
		if r.end.y > Dp - 0.5:
			out.append(Vector2(r.position.x - 0.1, r.end.x + 0.1))
	var dk: Rect2 = h.deck
	if dk.size.x > 0.0:
		out.append(Vector2(dk.position.x, dk.end.x))
	var pl: Dictionary = h.pool
	if not pl.is_empty() and pl.infinity:
		out.append(Vector2((pl.r as Rect2).position.x - 0.4, (pl.r as Rect2).end.x + 0.4))
	for st: Array in h.stairs:
		var a: Vector2 = st[0]
		out.append(Vector2(a.x - 0.8, a.x + 0.8))
	return out


## A span less a set of spans.
static func _minus(span: Vector2, cuts: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = [span]
	for c: Vector2 in cuts:
		var next: Array[Vector2] = []
		for s: Vector2 in out:
			if c.y <= s.x or c.x >= s.y:
				next.append(s)
				continue
			if c.x > s.x:
				next.append(Vector2(s.x, c.x))
			if c.y < s.y:
				next.append(Vector2(c.y, s.y))
		out = next
	return out


# --- Far (LOD chunks) ----------------------------------------------------------------------------------

func lod() -> void:
	_pad(false)
	var lit := 0.55
	var custom := Color(0.25, lit, float(absi(seed) % 997) / 997.0, 0.0)
	var plain := Color(0.0, 0.0, float(absi(seed) % 997) / 997.0, 1.0)
	for w: Dictionary in h.wings:
		_level(float(w.y), maxf(float(w.base), -3.0))
		var r: Rect2 = w.r
		var ye := float(w.storeys) * HouseKit.STOREY
		var t2 := ye + (HouseKit.PARAPET if w.roof == "flat" else 0.0)
		var wall_c: Color = col.wall
		if w.mat == "h_siding":
			wall_c = col.stain
		elif w.get("dark", false):
			wall_c = col.dark
		var c := r.get_center()
		var size := _world_size(r, t2 - base)
		var centre := W(c.x, (base + t2) * 0.5, c.y)
		_lod_add(Transform3D(Basis().scaled(size), centre), wall_c, custom if w.role != "carport" and w.role != "garage" else plain)
		ch._add_lod_shape(size, centre)
		if w.roof == "hip" or w.roof == "gable":
			_lod_roof(w, ye, HouseKit.CLAY_FAR, wall_c, plain)
		elif w.roof == "deck":
			var ev := maxf(float(w.eave), 0.0) if float(w.eave) >= 0.0 else eave
			var rr := r.grow(ev)
			_lod_add(Transform3D(Basis().scaled(_world_size(rr, 0.3)), W(c.x, ye + 0.15, c.y)), col.trim, plain)
	_level(0.0, HillHomeKit.PAD_BASE)
	# The columns under a cantilever as two dark boxes.
	var fi: int = h.frame_steel
	if fi >= 0:
		var r2: Rect2 = h.wings[fi].r
		var dk: Rect2 = h.deck
		var ve := maxf(r2.end.y, dk.end.y) - 0.35
		for cu: float in [r2.position.x + 0.3, r2.end.x - 0.3]:
			var gnd := _ground(cu, ve)
			var yb := g0 - HillHomeKit.SLAB - HillHomeKit.BEAM
			if gnd < yb - 0.8:
				_lod_add(Transform3D(Basis().scaled(Vector3(0.3, yb - gnd, 0.3)), WY(cu, ve, (yb + gnd) * 0.5)), HillHomeKit.STEEL, plain)
	var pl: Dictionary = h.pool
	if not pl.is_empty():
		var pr: Rect2 = pl.r
		var pc := pr.get_center()
		_lod_add(Transform3D(Basis().scaled(_world_size(pr, 0.2)), WY(pc.x, pc.y, top + 0.1)), Color(0.22, 0.62, 0.72), plain)


func _lod_add(xf: Transform3D, cl: Color, custom: Color) -> void:
	var o3 := xf.origin
	if ch._batch.ground.is_valid():
		o3.y -= ch._gy(o3.x, o3.z)
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(xf.basis, o3), cl, custom)
