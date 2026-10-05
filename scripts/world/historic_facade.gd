class_name HistoricFacade
extends RefCounted
## The beaux-arts ornament of a historic-core building (HistoricCore): real geometry on the
## building's STREET faces, laid on the very window grid building.gdshader draws for its one SLAB
## part (Building.part_grid(): bays of `pitch`, storeys of `floor_h` over the storefront), so
## nothing ever covers a pane:
## - the BASE: the storefront storey (bronze shop frames, Building.shop_frame_force) and the first
##   floor over it in channelled RUSTICATION (courses of stone with a recessed joint between them,
##   broken round each window), each first-floor window under a round ARCH of voussoirs with a
##   keystone and a bronze fanlight; a moulded belt course caps the base;
## - the GIANT ORDER: pilasters (fluted) or engaged columns on every bay line (every other on a
##   tight grid) and at the corners, with bases and capitals, spanning the middle storeys; on a
##   tall office block (seven storeys and more) the order is the top two storeys - base, shaft,
##   capital - and the shaft's windows get architrave surrounds with sills, keystones and hoods;
##   between the order's storeys, spandrel panels with a lozenge;
## - the ENTABLATURE: architrave, frieze (the building's invented name in bronze letters on its
##   main front) and a heavy CORNICE - bed moulding, dentils, modillion brackets under a deep
##   corona, a cyma on top - projecting about a metre and a quarter, mitred round street corners
##   and returned two metres onto a side wall;
## - the ATTIC over it (four storeys and more): panelled piers on the order's lines, a coping
##   cornice at the roof, urns on the parapet's corners and a cartouche over the main front;
## - the ENTRANCE: on the main front's middle bay, two engaged columns carrying an entablature
##   block with the name, bronze lanterns on brackets that light after dark (historic_lamp
##   shader), a pool of light on the pavement and one lamp-group OmniLight;
## - brick fronts get stone QUOINS up their street corners.
## Two meshes a building (LandmarkGeo): the big pieces (cornices, belt, order, entablature: they
## cast shadows, 380 m) and the fine ones (rustication, arches, surrounds, panels, dentils,
## modillions, capitals: no shadow, 170 m). Built one street face per build step.

const MAIN_DRAW := 380.0
const FINE_DRAW := 170.0
## Course height of the rustication and the joint between courses (m).
const COURSE := 0.5
const COURSE_JOINT := 0.045
const RUSTIC_OUT := 0.075
## The arch ring's depth on the wall and how far it stands out.
const RING := 0.26
const RING_OUT := 0.095
## A cornice's return onto a side wall (m).
const RETURN_LEN := 2.0
## Lantern light.
const LAMP_COLOR := Color(1.0, 0.80, 0.55)

static var built_count: int = 0


## The building's grid, from its one part: {"size", "center", "sf" (storefront height), "fh",
## "rows", "pitch_x", "pitch_z", "rect" (WINDOW_RECTS row)}. `style` is plan_only()'s (LOD); {}
## reads what _build_part() left on the part (FULL).
static func layout(b: Building, style: Dictionary) -> Dictionary:
	if b.parts.is_empty():
		return {}
	var part: Dictionary = b.parts[0]
	var size: Vector3 = part.size
	var out := {"size": size, "center": part.center, "rect": Building.WINDOW_RECTS[b.window_style]}
	if style.is_empty():
		if not part.has("floor_h"):
			return {}
		var sf: float = (float(part.gfh) - float(part.base_y)) if part.storefront else 0.0
		out.sf = sf
		out.fh = float(part.floor_h)
		out.pitch_x = float(part.pitch_x)
		out.pitch_z = float(part.pitch_z)
	else:
		var g := b.part_grid(part, style)
		out.sf = float(g.storefront)
		out.fh = float(g.floor_h)
		out.pitch_x = size.x / float(g.cols_x)
		out.pitch_z = size.z / float(g.cols_z)
	out.rows = maxi(1, roundi((size.y - float(out.sf)) / float(out.fh)))
	# The composition: which rows are the order, whether there is an attic.
	var r: int = out.rows
	var order0 := 1
	var order1 := r - 1
	var attic := false
	if r >= 7:
		order0 = r - 3
		order1 = r - 2
		attic = true
	elif r >= 4:
		order1 = r - 2
		attic = true
	elif r <= 2:
		order1 = 0
	out.order0 = order0
	out.order1 = order1
	out.attic = attic
	out.scale = clampf(float(out.fh) / 3.6, 0.82, 1.15)
	return out


## One face's frame: outward `n`, along `a` (Building's: UP x n), length, pitch, the face plane's
## centre at y 0, and which of the neighbouring faces (at +a and -a ends) are street faces.
static func _face(L: Dictionary, n: Vector3, streets: Array[Vector3]) -> Dictionary:
	var size: Vector3 = L.size
	var c: Vector3 = L.center
	var a := Vector3.UP.cross(n)
	var along_x := absf(n.x) < 0.5
	var length := size.x if along_x else size.z
	var depth := size.z if along_x else size.x
	return {"n": n, "a": a, "len": length, "pitch": float(L.pitch_x) if along_x else float(L.pitch_z),
		"fc": Vector3(c.x, 0.0, c.z) + n * depth * 0.5,
		"street_end": streets.has(a), "street_start": streets.has(-a)}


## The build jobs for a building: one per street face, then the commit.
static func jobs(b: Building, spec: Dictionary, streets: Array[Vector3], main_n: Vector3) -> Array[Callable]:
	var out: Array[Callable] = []
	var L := layout(b, {})
	if L.is_empty():
		return out
	var st := {"main": LandmarkGeo.new(), "fine": LandmarkGeo.new(), "lamps": [], "layout": L}
	_use(st.main, spec)
	_use(st.fine, spec)
	# Each face in four phases (base, order, entablature, attic and entrance), so no build step
	# runs much past the streamer's budget.
	for n: Vector3 in streets:
		for phase in 4:
			out.append(_face_job.bind(b, spec, L, n, streets, n == main_n, st, phase))
	# Returns of the cornice onto the side walls next to a street face.
	out.append(func() -> void:
		for n: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			if streets.has(n):
				continue
			var f := _face(L, n, streets)
			if f.street_end:
				_cornices(st, L, f, f.len * 0.5 - minf(RETURN_LEN, f.len * 0.5), f.len * 0.5, false, true)
			if f.street_start:
				_cornices(st, L, f, -f.len * 0.5, -f.len * 0.5 + minf(RETURN_LEN, f.len * 0.5), true, false))
	out.append(_commit.bind(b, st, 0))
	out.append(_commit.bind(b, st, 1))
	return out


static func _use(g: LandmarkGeo, spec: Dictionary) -> void:
	var p: int = spec.palette
	var tint: Color = (HistoricCore.TERRACOTTA[p] as Color).lightened(0.05)
	var common := {"tint": tint, "roughness": 0.5, "texture_contrast": 0.35, "grime": 0.35, "seed": float(p) * 3.0,
		"flood_strength": 0.55, "flood_base_y": 0.3, "flood_reach": 9.0, "flood_floor": 0.04, "flood_spacing": 3.0}
	g.use("stone", LandmarkMats.facade("hc_stone_%d" % p, "plaster_white", 2.5, common))
	var flute := common.duplicate()
	flute.merge({"joint_spacing": Vector2(0.16, 0.0), "joint_width": 0.05, "joint_dark": 0.32}, true)
	g.use("flute", LandmarkMats.facade("hc_flute_%d" % p, "plaster_white", 2.5, flute))
	g.use("bronze", LandmarkMats.plain("hc_bronze", Color(0.40, 0.28, 0.16), 0.38, 0.85))
	g.use("fan", LandmarkMats.plain("hc_fan", Color(0.05, 0.06, 0.07), 0.12, 0.4))
	g.use("lamp", lamp_material())


static func lamp_material() -> ShaderMaterial:
	var key := "hc_lamp"
	if LandmarkMats._cache.has(key):
		return LandmarkMats._cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/historic_lamp.gdshader")
	LandmarkMats._cache[key] = m
	return m


# --- Primitives in a face's frame --------------------------------------------------------------
# A point on face f: fc + a * u + UP * y + n * o (u along the wall from its centre, o out of it).

static func _p(f: Dictionary, u: float, y: float, o: float) -> Vector3:
	return (f.fc as Vector3) + (f.a as Vector3) * u + Vector3.UP * y + (f.n as Vector3) * o


## A block on the wall: u0..u1 along it, y0..y1 up, o0..o1 out of it. No back face.
static func _slab(g: LandmarkGeo, key: String, f: Dictionary, u0: float, u1: float, y0: float, y1: float,
		o0: float, o1: float, bottom: bool = true) -> void:
	var a: Vector3 = f.a
	var n: Vector3 = f.n
	var p := func(u: float, y: float, o: float) -> Vector3: return _p(f, u, y, o)
	# Front.
	g.quad(key, p.call(u0, y0, o1), p.call(u0, y1, o1), p.call(u1, y1, o1), p.call(u1, y0, o1), n,
		Vector2(u0, y0), Vector2(u0, y1), Vector2(u1, y1), Vector2(u1, y0))
	# Top.
	g.quad(key, p.call(u0, y1, o0), p.call(u0, y1, o1), p.call(u1, y1, o1), p.call(u1, y1, o0), Vector3.UP,
		Vector2(u0, o0), Vector2(u0, o1), Vector2(u1, o1), Vector2(u1, o0))
	if bottom:
		g.quad(key, p.call(u0, y0, o0), p.call(u0, y0, o1), p.call(u1, y0, o1), p.call(u1, y0, o0), Vector3.DOWN,
			Vector2(u0, o0), Vector2(u0, o1), Vector2(u1, o1), Vector2(u1, o0))
	# Ends.
	g.quad(key, p.call(u0, y0, o0), p.call(u0, y1, o0), p.call(u0, y1, o1), p.call(u0, y0, o1), -a,
		Vector2(o0, y0), Vector2(o0, y1), Vector2(o1, y1), Vector2(o1, y0))
	g.quad(key, p.call(u1, y0, o0), p.call(u1, y1, o0), p.call(u1, y1, o1), p.call(u1, y0, o1), a,
		Vector2(o0, y0), Vector2(o0, y1), Vector2(o1, y1), Vector2(o1, y0))


## A moulding: `prof` is a list of (out, up) points from the wall at the bottom round to the wall
## at the top, extruded from u0 to u1 at height y0, scaled by `s`. `mitre0` / `mitre1`: the end
## turns a square street corner (each point's u moved by its own projection); otherwise the end is
## capped flat.
static func _extrude(g: LandmarkGeo, key: String, f: Dictionary, prof: Array, u0: float, u1: float, y0: float,
		s: float, mitre0: bool, mitre1: bool) -> void:
	var a: Vector3 = f.a
	var n: Vector3 = f.n
	var pts: Array[Vector2] = []
	for q: Vector2 in prof:
		pts.append(Vector2(q.x * s, q.y * s))
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var d := p1 - p0
		if d.length_squared() < 1e-8:
			continue
		var want := n * d.y - Vector3.UP * d.x
		var ua0 := u0 - (p0.x if mitre0 else 0.0)
		var ub0 := u0 - (p1.x if mitre0 else 0.0)
		var ua1 := u1 + (p0.x if mitre1 else 0.0)
		var ub1 := u1 + (p1.x if mitre1 else 0.0)
		var va := y0 + p0.y
		var vb := y0 + p1.y
		var t0 := float(i) * 0.3
		g.quad(key, _p(f, ua0, va, p0.x), _p(f, ub0, vb, p1.x), _p(f, ub1, vb, p1.x), _p(f, ua1, va, p0.x), want,
			Vector2(ua0, va + t0), Vector2(ub0, vb + t0), Vector2(ub1, vb + t0), Vector2(ua1, va + t0))
	# Flat caps (the profile closed against the wall).
	var poly := PackedVector2Array()
	for q in pts:
		poly.append(q)
	var tris := Geometry2D.triangulate_polygon(poly)
	for e: Array in [[mitre0, u0, -a], [mitre1, u1, a]]:
		if e[0]:
			continue
		for k in range(0, tris.size() - 2, 3):
			var qa := pts[tris[k]]
			var qb := pts[tris[k + 1]]
			var qc := pts[tris[k + 2]]
			g.tri(key, _p(f, e[1], y0 + qa.y, qa.x), _p(f, e[1], y0 + qb.y, qb.x), _p(f, e[1], y0 + qc.y, qc.x), e[2],
				Vector2(qa.x, y0 + qa.y), Vector2(qb.x, y0 + qb.y), Vector2(qc.x, y0 + qc.y))


# --- Profiles (out, up), metres at scale 1 -----------------------------------------------------

## The main cornice: bed moulding, dentil band, the soffit under a deep corona, a cyma on top.
const CORNICE := [Vector2(-0.03, 0.0), Vector2(0.10, 0.0), Vector2(0.10, 0.08), Vector2(0.16, 0.12),
	Vector2(0.22, 0.14), Vector2(0.22, 0.26), Vector2(0.30, 0.30), Vector2(1.08, 0.30), Vector2(1.08, 0.56),
	Vector2(1.14, 0.60), Vector2(1.14, 0.64), Vector2(1.17, 0.70), Vector2(1.22, 0.76), Vector2(1.28, 0.80),
	Vector2(1.28, 0.86), Vector2(-0.03, 0.86)]
const CORNICE_H := 0.86
## The roof's coping cornice over an attic.
const COPING := [Vector2(-0.03, 0.0), Vector2(0.08, 0.0), Vector2(0.08, 0.06), Vector2(0.14, 0.10),
	Vector2(0.42, 0.14), Vector2(0.42, 0.30), Vector2(0.46, 0.34), Vector2(0.46, 0.40), Vector2(-0.03, 0.40)]
const COPING_H := 0.40
## Architrave (two fasciae and a taenia), the frieze plane over it.
const ARCHITRAVE := [Vector2(-0.03, 0.0), Vector2(0.06, 0.0), Vector2(0.06, 0.15), Vector2(0.09, 0.16),
	Vector2(0.09, 0.30), Vector2(0.13, 0.31), Vector2(0.13, 0.37), Vector2(0.05, 0.38)]
const ARCHITRAVE_H := 0.38
## The belt course over the base.
const BELT := [Vector2(-0.03, 0.0), Vector2(0.12, 0.0), Vector2(0.18, 0.05), Vector2(0.20, 0.12),
	Vector2(0.17, 0.19), Vector2(0.14, 0.21), Vector2(0.14, 0.31), Vector2(0.24, 0.35), Vector2(0.24, 0.44),
	Vector2(-0.03, 0.44)]
const BELT_H := 0.44


# --- Heights ------------------------------------------------------------------------------------

## Heights (building space) of a building's composition: belt (bottom of the base's belt course),
## order bottom / top, entablature bottom, cornice bottom, roof.
static func heights(L: Dictionary) -> Dictionary:
	var sf: float = L.sf
	var fh: float = L.fh
	var s: float = L.scale
	var top: float = (L.size as Vector3).y
	var belt := sf + 1.27 * fh - 0.10 - BELT_H * s
	var h := {"belt": belt, "top": top}
	var o0: int = L.order0
	var o1: int = L.order1
	h.order_bottom = belt + BELT_H * s if o0 == 1 else sf + float(o0) * fh + 0.2 * fh
	if L.attic:
		# The entablature fills the wall between the order's last heads and the attic's sills.
		var zone0 := sf + float(o1) * fh + 0.79 * fh
		var zone1 := sf + float(o1 + 1) * fh + 0.25 * fh
		var cs := minf(s, (zone1 - zone0) / (ARCHITRAVE_H + 0.18 + CORNICE_H))
		h.ent = zone0
		h.cs = cs
		h.cornice = zone1 - CORNICE_H * cs
		h.order_top = zone0
	else:
		# No attic: the architrave and frieze under the roof line, the cornice in front of the
		# parapet.
		var zone0 := top - 0.21 * fh
		h.ent = zone0
		h.cs = s
		h.cornice = top - 0.05
		h.order_top = zone0
	return h


# --- One face ---------------------------------------------------------------------------------

static func _face_job(b: Building, spec: Dictionary, L: Dictionary, n: Vector3, streets: Array[Vector3],
		main: bool, st: Dictionary, phase: int) -> void:
	if not is_instance_valid(b):
		return
	var f := _face(L, n, streets)
	var H := heights(L)
	var main_g: LandmarkGeo = st.main
	var fine: LandmarkGeo = st.fine
	var flen: float = f.len
	var p: float = f.pitch
	var cols := maxi(1, roundi(flen / p))
	var sf: float = L.sf
	var fh: float = L.fh
	var s: float = L.scale
	var rect: Array = L.rect
	var hx: float = float(rect[2]) * p
	var rows: int = L.rows
	var u_lo := -flen * 0.5
	var u_hi := flen * 0.5
	# --- The base: rustication and arches on the first floor -------------------------------------
	if phase == 0 and rows >= 2:
		_base(fine, f, L, H, cols, p, hx)
		_extrude(main_g, "stone", f, BELT, u_lo, u_hi, float(H.belt), s, f.street_start, f.street_end)
	# --- The order ----------------------------------------------------------------------------
	var o0: int = L.order0
	var o1: int = L.order1
	var ob: float = H.order_bottom
	var ot: float = H.order_top
	if phase == 1 and o1 >= o0 and ot - ob > 2.0:
		if o0 > 1:
			# The shaft's string course under the colonnade, and its surrounds.
			_extrude(main_g, "stone", f, BELT, u_lo, u_hi, ob - BELT_H * s * 0.7, s * 0.7, f.street_start, f.street_end)
			for r in range(1, o0):
				_surrounds(fine, f, L, r, cols, p, hx)
		_order(main_g, fine, f, L, H, spec, cols, p, ob, ot)
		# Spandrel panels between the order's storeys.
		for r in range(o0, o1):
			var y0 := sf + float(r) * fh + 0.80 * fh
			var y1 := sf + float(r + 1) * fh + 0.24 * fh
			for c in cols:
				var uc := u_lo + (float(c) + 0.5) * p
				_panel(fine, f, uc, hx * 0.92, y0, y1)
	elif phase == 1 and rows >= 3:
		for r in range(1, rows):
			_surrounds(fine, f, L, r, cols, p, hx)
	# --- The entablature and the cornice -----------------------------------------------------
	if phase < 2:
		return
	var cs: float = H.cs
	var ent: float = H.ent
	var cor: float = H.cornice
	if phase == 2:
		_entablature(st, spec, f, u_lo, u_hi, ent, cor, cs, main, flen, p)
		return
	# --- The attic -------------------------------------------------------------------------
	if L.attic:
		_attic(main_g, fine, f, L, H, spec, cols, p, hx, main)
	# --- Quoins on a brick front's corners ---------------------------------------------------
	if spec.brick:
		for e: Array in [[u_lo, 1.0], [u_hi, -1.0]]:
			_quoins(fine, f, float(e[0]), float(e[1]), sf + 0.1, float(H.ent) - 0.05)
	# --- The entrance ---------------------------------------------------------------------
	if main and sf > 3.0:
		_entrance(st, f, L, spec, cols, p)
	# Collision: the cornice is a ledge to stand on.
	var depth := 1.28 * cs
	var body := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(flen + 2.0 * depth, CORNICE_H * cs, depth)
	body.shape = box
	body.transform = Transform3D(Basis(f.a as Vector3, Vector3.UP, f.n as Vector3), _p(f, 0.0, cor + CORNICE_H * cs * 0.5, depth * 0.5))
	body.name = "HistoricLedge"
	b.add_child(body)


## The architrave, the frieze (the name on the main front) and the cornices of one face.
static func _entablature(st: Dictionary, spec: Dictionary, f: Dictionary, u_lo: float, u_hi: float, ent: float,
		cor: float, cs: float, main: bool, flen: float, p: float) -> void:
	var main_g: LandmarkGeo = st.main
	var fine: LandmarkGeo = st.fine
	var L: Dictionary = st.layout
	_extrude(main_g, "stone", f, ARCHITRAVE, u_lo, u_hi, ent, cs, f.street_start, f.street_end)
	var frieze0 := ent + ARCHITRAVE_H * cs
	if cor > frieze0:
		_slab(main_g, "stone", f, u_lo - (0.05 if f.street_start else 0.0), u_hi + (0.05 if f.street_end else 0.0),
			frieze0, cor, -0.03, 0.05, false)
		if main and cor - frieze0 > 0.32 and str(spec.name) != "":
			var lh := minf((cor - frieze0) * 0.62, 0.55)
			_text(fine, str(spec.name), f, 0.0, (frieze0 + cor) * 0.5, 0.075, lh, minf(flen - 2.0 * p, 26.0))
	_cornices(st, L, f, u_lo, u_hi, f.street_start, f.street_end)


## The first floor in channelled rustication, broken round each window under its arch, and the
## arches: voussoirs, a keystone, a bronze fanlight; a stone sill under each window.
static func _base(g: LandmarkGeo, f: Dictionary, L: Dictionary, H: Dictionary, cols: int, p: float, hx: float) -> void:
	var sf: float = L.sf
	var fh: float = L.fh
	var flen: float = f.len
	var y_sill := sf + 0.27 * fh
	var y_head := sf + 0.77 * fh
	var y_top: float = H.belt
	var r := hx
	var rise := clampf(y_top - 0.04 - RING - y_head, 0.2, r)
	var y0 := sf + 0.22
	var n := maxi(1, roundi((y_top - y0) / COURSE))
	var ch := (y_top - y0) / float(n)
	for k in n:
		var ya := y0 + float(k) * ch
		var yb := ya + ch - COURSE_JOINT
		# Each window's half-width over this course (0 where the course passes under or over it).
		var holes: Array[Vector2] = []
		for c in cols:
			var uc := -flen * 0.5 + (float(c) + 0.5) * p
			var hw := 0.0
			if yb > y_sill - 0.06 and ya < y_head:
				hw = hx + 0.03
			if yb > y_head and ya < y_head + rise + RING:
				var t := clampf((maxf(ya, y_head) - y_head) / (rise + RING), 0.0, 1.0)
				hw = maxf(hw, (r + RING) * sqrt(maxf(1.0 - t * t, 0.0)) + 0.02)
			if hw > 0.0:
				holes.append(Vector2(uc - hw, uc + hw))
		var u := -flen * 0.5
		for hole: Vector2 in holes:
			if hole.x - u > 0.08:
				_slab(g, "stone", f, u, hole.x, ya, yb, -0.02, RUSTIC_OUT)
			u = hole.y
		if flen * 0.5 - u > 0.08:
			_slab(g, "stone", f, u, flen * 0.5, ya, yb, -0.02, RUSTIC_OUT)
	# Arches and sills.
	for c in cols:
		var uc := -flen * 0.5 + (float(c) + 0.5) * p
		_arch(g, f, uc, y_head, r, rise)
		_slab(g, "stone", f, uc - hx - 0.08, uc + hx + 0.08, y_sill - 0.13, y_sill - 0.02, -0.02, 0.13)


## A round (or segmental, where the wall is short) arch over a window: voussoirs between the
## intrados (r, rise) and the extrados RING further out, a deeper keystone, a dark fanlight with
## bronze glazing bars filling the tympanum, a bronze transom bar on the springing line.
static func _arch(g: LandmarkGeo, f: Dictionary, uc: float, y: float, r: float, rise: float) -> void:
	var nv := 9
	var gap := 0.025
	for i in nv:
		var t0 := PI * float(i) / float(nv) + gap * 0.5
		var t1 := PI * float(i + 1) / float(nv) - gap * 0.5
		var key_stone := i == nv / 2
		var out := RING_OUT * (1.6 if key_stone else 1.0)
		var ro := RING * (1.45 if key_stone else 1.0)
		var a0 := Vector2(uc + r * cos(t0), y + rise * sin(t0))
		var a1 := Vector2(uc + r * cos(t1), y + rise * sin(t1))
		var b0 := Vector2(uc + (r + ro) * cos(t0), y + (rise + ro) * sin(t0))
		var b1 := Vector2(uc + (r + ro) * cos(t1), y + (rise + ro) * sin(t1))
		var P := func(q: Vector2, o: float) -> Vector3: return _p(f, q.x, q.y, o)
		var nrm: Vector3 = f.n
		g.quad("stone", P.call(a0, out), P.call(b0, out), P.call(b1, out), P.call(a1, out), nrm,
			a0, b0, b1, a1)
		var tm := (t0 + t1) * 0.5
		var radial := ((f.a as Vector3) * cos(tm) + Vector3.UP * sin(tm)).normalized()
		g.quad("stone", P.call(a0, -0.02), P.call(a0, out), P.call(a1, out), P.call(a1, -0.02), -radial,
			Vector2(a0.x, 0.0), Vector2(a0.x, out), Vector2(a1.x, out), Vector2(a1.x, 0.0))
		g.quad("stone", P.call(b0, -0.02), P.call(b0, out), P.call(b1, out), P.call(b1, -0.02), radial,
			Vector2(b0.x, 0.0), Vector2(b0.x, out), Vector2(b1.x, out), Vector2(b1.x, 0.0))
		var side0 := ((f.a as Vector3) * -sin(t0) + Vector3.UP * cos(t0))
		g.quad("stone", P.call(a0, -0.02), P.call(a0, out), P.call(b0, out), P.call(b0, -0.02), -side0,
			Vector2(0, 0), Vector2(0, out), Vector2(ro, out), Vector2(ro, 0))
		var side1 := ((f.a as Vector3) * -sin(t1) + Vector3.UP * cos(t1))
		g.quad("stone", P.call(a1, -0.02), P.call(a1, out), P.call(b1, out), P.call(b1, -0.02), side1,
			Vector2(0, 0), Vector2(0, out), Vector2(ro, out), Vector2(ro, 0))
	# The fanlight: the tympanum in dark glass, a hair in front of the wall.
	var segs := 12
	var centre := _p(f, uc, y, 0.012)
	for i in segs:
		var t0 := PI * float(i) / float(segs)
		var t1 := PI * float(i + 1) / float(segs)
		g.tri("fan", centre, _p(f, uc + r * cos(t0), y + rise * sin(t0), 0.012), _p(f, uc + r * cos(t1), y + rise * sin(t1), 0.012),
			f.n, Vector2(uc, y), Vector2(uc + r * cos(t0), y + rise * sin(t0)), Vector2(uc + r * cos(t1), y + rise * sin(t1)))
	# Glazing bars radiating from the springing line's middle, and the transom bar.
	for i in range(1, 6):
		var t := PI * float(i) / 6.0
		var dir := Vector2(cos(t), sin(t))
		var side := Vector2(-dir.y, dir.x) * 0.018
		var q0 := Vector2(uc, y)
		var q1 := Vector2(uc + r * cos(t), y + rise * sin(t))
		g.quad("bronze", _p(f, q0.x + side.x, q0.y + side.y, 0.03), _p(f, q1.x + side.x, q1.y + side.y, 0.03),
			_p(f, q1.x - side.x, q1.y - side.y, 0.03), _p(f, q0.x - side.x, q0.y - side.y, 0.03), f.n,
			q0, q1, q1, q0)
	_slab(g, "bronze", f, uc - r, uc + r, y - 0.04, y + 0.04, -0.01, 0.04)


## A shaft window's surround: architrave jambs and head, a sill on blocks, and over it a hood
## cornice on even storeys or a keystone on odd ones.
static func _surrounds(g: LandmarkGeo, f: Dictionary, L: Dictionary, row: int, cols: int, p: float, hx: float) -> void:
	var sf: float = L.sf
	var fh: float = L.fh
	var flen: float = f.len
	var y0 := sf + float(row) * fh + 0.27 * fh
	var y1 := sf + float(row) * fh + 0.77 * fh
	var w := 0.13
	for c in cols:
		var uc := -flen * 0.5 + (float(c) + 0.5) * p
		_slab(g, "stone", f, uc - hx - w, uc - hx, y0, y1 + w, -0.02, 0.06)
		_slab(g, "stone", f, uc + hx, uc + hx + w, y0, y1 + w, -0.02, 0.06)
		_slab(g, "stone", f, uc - hx, uc + hx, y1, y1 + w, -0.02, 0.06, false)
		_slab(g, "stone", f, uc - hx - w - 0.06, uc + hx + w + 0.06, y0 - 0.09, y0, -0.02, 0.12)
		if row % 2 == 0:
			_slab(g, "stone", f, uc - hx - w - 0.10, uc + hx + w + 0.10, y1 + w, y1 + w + 0.12, -0.02, 0.16)
		else:
			_slab(g, "stone", f, uc - 0.11, uc + 0.11, y1 - 0.02, y1 + w + 0.12, -0.02, 0.10)


## A recessed spandrel: a frame of four bars round a lozenge.
static func _panel(g: LandmarkGeo, f: Dictionary, uc: float, hw: float, y0: float, y1: float) -> void:
	if y1 - y0 < 0.35:
		return
	var w := 0.08
	_slab(g, "stone", f, uc - hw, uc + hw, y0, y0 + w, -0.02, 0.05)
	_slab(g, "stone", f, uc - hw, uc + hw, y1 - w, y1, -0.02, 0.05)
	_slab(g, "stone", f, uc - hw, uc - hw + w, y0 + w, y1 - w, -0.02, 0.05)
	_slab(g, "stone", f, uc + hw - w, uc + hw, y0 + w, y1 - w, -0.02, 0.05)
	_lozenge(g, f, uc, (y0 + y1) * 0.5, minf((y1 - y0) * 0.32, 0.22), 0.06)


## A diamond boss on the wall, `r` its half-diagonal, standing `o` out.
static func _lozenge(g: LandmarkGeo, f: Dictionary, uc: float, yc: float, r: float, o: float) -> void:
	var tip := _p(f, uc, yc, o + 0.02)
	var pts := [Vector2(uc - r, yc), Vector2(uc, yc + r), Vector2(uc + r, yc), Vector2(uc, yc - r)]
	for i in 4:
		var q0: Vector2 = pts[i]
		var q1: Vector2 = pts[(i + 1) % 4]
		var mid := (q0 + q1) * 0.5 - Vector2(uc, yc)
		var want := ((f.n as Vector3) * r * 0.6 + (f.a as Vector3) * mid.x + Vector3.UP * mid.y).normalized()
		g.tri("stone", _p(f, q0.x, q0.y, -0.01), tip, _p(f, q1.x, q1.y, -0.01), want, q0, Vector2(uc, yc), q1)


## The giant order: on every bay line (every other on a tight grid) and at the street corners, a
## pilaster (fluted shaft) or an engaged column, each on a base and under a capital.
static func _order(main_g: LandmarkGeo, fine: LandmarkGeo, f: Dictionary, L: Dictionary, H: Dictionary,
		spec: Dictionary, cols: int, p: float, ob: float, ot: float) -> void:
	var flen: float = f.len
	var pier := p - 2.0 * float((L.rect as Array)[2]) * p
	var w := clampf(pier - 0.24, 0.36, 0.78)
	var step := 1 if p >= 2.3 else 2
	var columns: bool = spec.columns
	for k in range(0, cols + 1, step):
		var u := -flen * 0.5 + float(k) * p
		var wk := w
		if k == 0 or k == cols:
			# A corner pier is half a pier: the pilaster stands inside the corner.
			wk = minf(w, pier * 0.5 - 0.06)
			if wk < 0.26:
				continue
			u += (wk * 0.5 + 0.03) * (1.0 if k == 0 else -1.0)
		_pilaster(main_g, fine, f, u, wk, ob, ot, columns and k != 0 and k != cols)


static func _pilaster(main_g: LandmarkGeo, fine: LandmarkGeo, f: Dictionary, u: float, w: float, y0: float, y1: float,
		column: bool) -> void:
	var hw := w * 0.5
	var cap_h := clampf(w * 0.9, 0.38, 0.65)
	var base_h := clampf(w * 0.55, 0.22, 0.4)
	var o := 0.15
	# Base: a plinth and a torus step.
	_slab(fine, "stone", f, u - hw - 0.07, u + hw + 0.07, y0, y0 + base_h * 0.6, -0.02, o + 0.07)
	_slab(fine, "stone", f, u - hw - 0.035, u + hw + 0.035, y0 + base_h * 0.6, y0 + base_h, -0.02, o + 0.035)
	var s0 := y0 + base_h
	var s1 := y1 - cap_h
	if column:
		_half_column(main_g, f, u, hw, s0, s1)
	else:
		_slab(main_g, "flute", f, u - hw, u + hw, s0, s1, -0.02, o, false)
	# Capital: necking, a bell that flares, the abacus, and the volutes at its corners.
	var oo := hw if column else o
	_slab(fine, "stone", f, u - hw - 0.02, u + hw + 0.02, s1, s1 + cap_h * 0.14, -0.02, oo + 0.02)
	var b0 := s1 + cap_h * 0.14
	var b1 := s1 + cap_h * 0.74
	var flare := 0.10
	var p := func(uu: float, yy: float, ox: float) -> Vector3: return _p(f, uu, yy, ox)
	fine.quad("stone", p.call(u - hw, b0, oo), p.call(u - hw - flare, b1, oo + flare), p.call(u + hw + flare, b1, oo + flare),
		p.call(u + hw, b0, oo), (f.n as Vector3) - Vector3.UP * 0.3, Vector2(u - hw, b0), Vector2(u - hw, b1), Vector2(u + hw, b1), Vector2(u + hw, b0))
	fine.quad("stone", p.call(u - hw, b0, -0.02), p.call(u - hw - flare, b1, -0.02), p.call(u - hw - flare, b1, oo + flare),
		p.call(u - hw, b0, oo), -(f.a as Vector3), Vector2(0, b0), Vector2(0, b1), Vector2(oo, b1), Vector2(oo, b0))
	fine.quad("stone", p.call(u + hw, b0, -0.02), p.call(u + hw + flare, b1, -0.02), p.call(u + hw + flare, b1, oo + flare),
		p.call(u + hw, b0, oo), f.a, Vector2(0, b0), Vector2(0, b1), Vector2(oo, b1), Vector2(oo, b0))
	# Acanthus: two rows of leaf tips as small wedges on the bell.
	for row in 2:
		var ly := b0 + (b1 - b0) * (0.25 + 0.4 * float(row))
		var lo := oo + flare * (0.25 + 0.4 * float(row)) + 0.01
		for i in 3:
			var lu := u + (float(i) - 1.0) * w * 0.33 + (0.0 if row == 0 else w * 0.16)
			if absf(lu - u) > hw:
				continue
			fine.tri("stone", p.call(lu - 0.06, ly - 0.08, lo - 0.01), p.call(lu, ly + 0.10, lo + 0.05), p.call(lu + 0.06, ly - 0.08, lo - 0.01),
				f.n, Vector2(lu - 0.06, ly), Vector2(lu, ly + 0.1), Vector2(lu + 0.06, ly))
	_slab(fine, "stone", f, u - hw - flare - 0.04, u + hw + flare + 0.04, b1, y1, -0.02, oo + flare + 0.04)
	# Volutes: a scroll at each corner of the bell's top.
	for sgn: float in [-1.0, 1.0]:
		var vu := u + sgn * (hw + flare - 0.05)
		_slab(fine, "stone", f, vu - 0.07, vu + 0.07, b1 - 0.14, b1, -0.02, oo + flare + 0.06)


## An engaged column: a half cylinder standing out of the wall, with entasis (it narrows a little
## toward the top).
static func _half_column(g: LandmarkGeo, f: Dictionary, u: float, r: float, y0: float, y1: float) -> void:
	var segs := 10
	var a: Vector3 = f.a
	var n: Vector3 = f.n
	var r1 := r * 0.88
	for i in segs:
		var t0 := PI * float(i) / float(segs)
		var t1 := PI * float(i + 1) / float(segs)
		var d0 := a * cos(t0) + n * sin(t0)
		var d1 := a * cos(t1) + n * sin(t1)
		var c0 := _p(f, u, y0, 0.0)
		var c1 := _p(f, u, y1, 0.0)
		g.quad_n("stone", c0 + d0 * r, c1 + d0 * r1, c1 + d1 * r1, c0 + d1 * r, d0, d0, d1, d1,
			Vector2(t0 * r, y0), Vector2(t0 * r, y1), Vector2(t1 * r, y1), Vector2(t1 * r, y0))


## The cornices of a run: the main one at H.cornice, and over an attic the coping at the roof.
static func _cornices(st: Dictionary, L: Dictionary, f: Dictionary, u0: float, u1: float, mitre0: bool, mitre1: bool) -> void:
	var H := heights(L)
	var cs: float = H.cs
	var main_g: LandmarkGeo = st.main
	var fine: LandmarkGeo = st.fine
	var y0: float = H.cornice
	_extrude(main_g, "stone", f, CORNICE, u0, u1, y0, cs, mitre0, mitre1)
	# Modillions under the corona and dentils on their band.
	var mstep := 0.64 * cs
	var mu0 := u0 + 0.3
	var mu1 := u1 - 0.3
	var m := maxi(0, floori((mu1 - mu0) / mstep))
	var off := ((mu1 - mu0) - float(m) * mstep) * 0.5
	for i in m + 1:
		var u := mu0 + off + float(i) * mstep
		_slab(fine, "stone", f, u - 0.08 * cs, u + 0.08 * cs, y0 + 0.17 * cs, y0 + 0.30 * cs, 0.29 * cs, 1.0 * cs)
		_slab(fine, "stone", f, u - 0.07 * cs, u + 0.07 * cs, y0 + 0.04 * cs, y0 + 0.30 * cs, 0.09 * cs, 0.36 * cs)
	var dstep := 0.15 * cs
	var dn := maxi(0, floori((u1 - u0 - 0.1) / dstep))
	for i in dn:
		var u := u0 + 0.05 + (float(i) + 0.5) * dstep
		_slab(fine, "stone", f, u - 0.035 * cs, u + 0.035 * cs, y0 + 0.15 * cs, y0 + 0.25 * cs, 0.2 * cs, 0.27 * cs)
	if L.attic:
		var top: float = (L.size as Vector3).y
		_extrude(main_g, "stone", f, COPING, u0, u1, top - COPING_H * cs * 0.6, cs, mitre0, mitre1)


## The attic storey: panelled piers on the order's lines, urns on the street corners of the
## parapet and a cartouche over the main front.
static func _attic(main_g: LandmarkGeo, fine: LandmarkGeo, f: Dictionary, L: Dictionary, H: Dictionary,
		spec: Dictionary, cols: int, p: float, hx: float, main: bool) -> void:
	var flen: float = f.len
	var cs: float = H.cs
	var top: float = (L.size as Vector3).y
	var y0: float = float(H.cornice) + CORNICE_H * cs + 0.12
	var y1 := top - COPING_H * cs * 0.6 - 0.1
	if y1 - y0 < 0.6:
		return
	var step := 1 if p >= 2.3 else 2
	var pier := p - 2.0 * hx
	var w := clampf(pier - 0.24, 0.36, 0.78)
	for k in range(step, cols, step):
		var u := -flen * 0.5 + float(k) * p
		_slab(main_g, "stone", f, u - w * 0.5, u + w * 0.5, y0, y1, -0.02, 0.10, false)
		var r := minf(w * 0.3, (y1 - y0) * 0.22)
		_lozenge(fine, f, u, (y0 + y1) * 0.5, r, 0.12)
	# Urns on the parapet over the street corners.
	var parapet_top := top + 0.85
	for e: Array in [[-flen * 0.5 + 0.45, f.street_start], [flen * 0.5 - 0.45, f.street_end]]:
		if e[1]:
			_urn(fine, _p(f, float(e[0]), parapet_top, -0.35))
	if main:
		# The cartouche: a shield on the parapet's middle, between two scrolls.
		var c := Vector2(0.0, parapet_top + 0.55)
		var shield := [Vector2(-0.55, 0.65), Vector2(0.55, 0.65), Vector2(0.62, 0.0), Vector2(0.35, -0.55),
			Vector2(0.0, -0.75), Vector2(-0.35, -0.55), Vector2(-0.62, 0.0)]
		var poly := PackedVector2Array()
		for q: Vector2 in shield:
			poly.append(q)
		var tris := Geometry2D.triangulate_polygon(poly)
		for k in range(0, tris.size() - 2, 3):
			var qa: Vector2 = shield[tris[k]]
			var qb: Vector2 = shield[tris[k + 1]]
			var qc: Vector2 = shield[tris[k + 2]]
			main_g.tri("stone", _p(f, qa.x, c.y + qa.y, 0.2), _p(f, qb.x, c.y + qb.y, 0.2), _p(f, qc.x, c.y + qc.y, 0.2),
				f.n, qa + c, qb + c, qc + c)
		for i in shield.size():
			var qa: Vector2 = shield[i]
			var qb: Vector2 = shield[(i + 1) % shield.size()]
			var mid := (qa + qb) * 0.5
			main_g.quad("stone", _p(f, qa.x, c.y + qa.y, -0.1), _p(f, qa.x, c.y + qa.y, 0.2), _p(f, qb.x, c.y + qb.y, 0.2),
				_p(f, qb.x, c.y + qb.y, -0.1), ((f.a as Vector3) * mid.x + Vector3.UP * mid.y).normalized(), qa, qa, qb, qb)
		main_g.quad("stone", _p(f, -0.62, c.y + 0.65, -0.1), _p(f, -0.62, c.y + 0.65, 0.2), _p(f, 0.62, c.y + 0.65, 0.2),
			_p(f, 0.62, c.y + 0.65, -0.1), Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ONE, Vector2.ONE)
		for sgn: float in [-1.0, 1.0]:
			var ua := sgn * 0.62
			var ub := sgn * 0.97
			_slab(fine, "stone", f, minf(ua, ub), maxf(ua, ub), parapet_top, parapet_top + 0.45, -0.1, 0.14)
		_lozenge(fine, f, 0.0, c.y + 0.05, 0.22, 0.24)


## An urn on a pedestal: a lathe of a few rings.
static func _urn(g: LandmarkGeo, at: Vector3) -> void:
	var prof := [[0.0, 0.22], [0.18, 0.22], [0.2, 0.14], [0.32, 0.10], [0.42, 0.2], [0.62, 0.24], [0.78, 0.17],
		[0.84, 0.2], [0.9, 0.06], [1.0, 0.0]]
	var segs := 8
	for i in prof.size() - 1:
		var y0: float = prof[i][0]
		var r0: float = prof[i][1]
		var y1: float = prof[i + 1][0]
		var r1: float = prof[i + 1][1]
		g.band("stone", Vector2(at.x, at.z), Vector2(r0, r0), Vector2(r1, r1), at.y + y0, at.y + y1, 0.0, TAU, segs)
	g.box("stone", at + Vector3(0.0, -0.25, 0.0), Vector3(0.5, 0.5, 0.5))


## Stone quoins up a corner of a brick front: alternating long and short blocks.
static func _quoins(g: LandmarkGeo, f: Dictionary, u_edge: float, inward: float, y0: float, y1: float) -> void:
	var h := 0.42
	var n := floori((y1 - y0) / h)
	for i in n:
		var w := 0.85 if i % 2 == 0 else 0.55
		var ya := y0 + float(i) * h
		var u0 := u_edge
		var u1 := u_edge + inward * w
		_slab(g, "stone", f, minf(u0, u1), maxf(u0, u1), ya, ya + h - 0.04, -0.02, 0.05)


## The entrance on the main front's middle bay: two engaged columns, an entablature block with the
## name in bronze, lanterns on brackets that light after dark, the light pool, one lamp.
static func _entrance(st: Dictionary, f: Dictionary, L: Dictionary, spec: Dictionary, cols: int, p: float) -> void:
	var main_g: LandmarkGeo = st.main
	var fine: LandmarkGeo = st.fine
	var flen: float = f.len
	var sf: float = L.sf
	var ci := cols / 2
	var u0 := -flen * 0.5 + float(ci) * p
	var u1 := u0 + p
	var uc := (u0 + u1) * 0.5
	var r := 0.3
	# Out past the shop piers' cladding, so the frontispiece stands in front of the shopfront.
	var front := 0.68
	var glass_top := sf * 0.74
	for u: float in [u0, u1]:
		# A pedestal, the column standing proud of the wall on a block, a capital block.
		_slab(fine, "stone", f, u - r - 0.1, u + r + 0.1, 0.0, 0.85, -0.02, front + 0.06)
		_slab(main_g, "stone", f, u - r * 0.8, u + r * 0.8, 0.85, glass_top - 0.3, -0.02, front - r)
		_half_column_at(main_g, f, u, r, 0.85, glass_top - 0.3, front - r)
		_slab(fine, "stone", f, u - r - 0.12, u + r + 0.12, glass_top - 0.3, glass_top, -0.02, front + 0.08)
	# The entablature block over the door bay, the name on it, a cornice ledge, a crest.
	var e0 := glass_top
	var e1 := sf + 0.5
	var ul := u0 - r - 0.2
	var ur := u1 + r + 0.2
	_slab(main_g, "stone", f, ul, ur, e0, e1, -0.02, front + 0.1)
	_slab(main_g, "stone", f, ul - 0.14, ur + 0.14, e1, e1 + 0.2, -0.02, front + 0.32)
	_slab(fine, "stone", f, ul + 0.1, ur - 0.1, e0 - 0.08, e0, -0.02, front + 0.04)
	_text(fine, str(spec.name), f, uc, (e0 + e1) * 0.5, front + 0.11, minf((e1 - e0) * 0.42, 0.42), ur - ul - 0.4)
	# A segmental pediment over it: a shallow arc of stone with a lozenge in the tympanum.
	var span := (ur - ul) * 0.5 + 0.1
	var rise := 0.55
	var py := e1 + 0.2
	var segs := 10
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var x0 := lerpf(-span, span, t0)
		var x1 := lerpf(-span, span, t1)
		var y0 := py + rise * (1.0 - pow(x0 / span, 2.0))
		var y1 := py + rise * (1.0 - pow(x1 / span, 2.0))
		# The tympanum (flat face) and the curved cap on top.
		main_g.quad("stone", _p(f, uc + x0, py, front + 0.05), _p(f, uc + x0, y0, front + 0.05), _p(f, uc + x1, y1, front + 0.05),
			_p(f, uc + x1, py, front + 0.05), f.n, Vector2(uc + x0, py), Vector2(uc + x0, y0), Vector2(uc + x1, y1), Vector2(uc + x1, py))
		var up := (Vector3.UP + (f.a as Vector3) * (2.0 * rise * (x0 + x1) * 0.5 / (span * span))).normalized()
		main_g.quad("stone", _p(f, uc + x0, y0, -0.02), _p(f, uc + x0, y0, front + 0.22), _p(f, uc + x1, y1, front + 0.22),
			_p(f, uc + x1, y1, -0.02), up, Vector2(uc + x0, 0.0), Vector2(uc + x0, 0.6), Vector2(uc + x1, 0.6), Vector2(uc + x1, 0.0))
		main_g.quad("stone", _p(f, uc + x0, y0, front + 0.22), _p(f, uc + x0, y0 - 0.14, front + 0.22), _p(f, uc + x1, y1 - 0.14, front + 0.22),
			_p(f, uc + x1, y1, front + 0.22), f.n, Vector2(uc + x0, y0), Vector2(uc + x0, y0 - 0.14), Vector2(uc + x1, y1 - 0.14), Vector2(uc + x1, y1))
	_lozenge(fine, f, uc, py + 0.24, 0.17, front + 0.07)
	# The lit soffit under the block, over the door.
	_slab(fine, "lamp", f, u0 + r, u1 - r, e0 - 0.1, e0 - 0.06, front - 0.4, front)
	# Lanterns on scroll brackets, one on each column's outer side.
	for u: float in [u0, u1]:
		var side := -1.0 if u == u0 else 1.0
		var lu := u + side * (r + 0.42)
		var ly := 3.0
		var lo := front + 0.05
		_slab(fine, "bronze", f, minf(u + side * r, lu), maxf(u + side * r, lu), ly + 0.5, ly + 0.56, lo - 0.05, lo + 0.05)
		_slab(fine, "bronze", f, lu - 0.03, lu + 0.03, ly + 0.36, ly + 0.56, lo - 0.03, lo + 0.03)
		_slab(fine, "bronze", f, lu - 0.2, lu + 0.2, ly - 0.06, ly, lo - 0.2, lo + 0.2)
		_slab(fine, "lamp", f, lu - 0.16, lu + 0.16, ly, ly + 0.42, lo - 0.16, lo + 0.16, false)
		for cu: float in [-0.165, 0.165]:
			_slab(fine, "bronze", f, lu + cu - 0.015, lu + cu + 0.015, ly, ly + 0.42, lo - 0.18, lo - 0.15)
			_slab(fine, "bronze", f, lu + cu - 0.015, lu + cu + 0.015, ly, ly + 0.42, lo + 0.15, lo + 0.18)
		_slab(fine, "bronze", f, lu - 0.22, lu + 0.22, ly + 0.42, ly + 0.48, lo - 0.22, lo + 0.22)
		_slab(fine, "bronze", f, lu - 0.08, lu + 0.08, ly + 0.48, ly + 0.58, lo - 0.08, lo + 0.08)
		(st.lamps as Array).append(_p(f, lu, ly + 0.2, lo + 0.4))
	st.pool = [_p(f, uc, 0.05, 2.6), f.n, p + 4.0]


## An engaged column standing off the wall: a half cylinder whose axis is `o` out of the wall.
static func _half_column_at(g: LandmarkGeo, f: Dictionary, u: float, r: float, y0: float, y1: float, o: float) -> void:
	var segs := 12
	var a: Vector3 = f.a
	var n: Vector3 = f.n
	for i in segs:
		var t0 := PI * float(i) / float(segs)
		var t1 := PI * float(i + 1) / float(segs)
		var d0 := a * cos(t0) + n * sin(t0)
		var d1 := a * cos(t1) + n * sin(t1)
		var c0 := _p(f, u, y0, o)
		var c1 := _p(f, u, y1, o)
		g.quad_n("stone", c0 + d0 * r, c1 + d0 * r * 0.92, c1 + d1 * r * 0.92, c0 + d1 * r, d0, d0, d1, d1,
			Vector2(t0 * r, y0), Vector2(t0 * r, y1), Vector2(t1 * r, y1), Vector2(t1 * r, y0))


## Bronze letters on the wall, centred at (u, y), `o` out of it, `h` their em, at most `fit` wide.
static func _text(g: LandmarkGeo, s: String, f: Dictionary, u: float, y: float, o: float, h: float, fit: float) -> void:
	var geo := ShopfrontKit._text_geo(s, h)
	var vs: PackedVector3Array = geo[0]
	if vs.is_empty():
		return
	var lo := INF
	var hi := -INF
	for v in vs:
		lo = minf(lo, v.x)
		hi = maxf(hi, v.x)
	var sc := minf(1.0, fit / maxf(hi - lo, 0.01))
	var xf := Transform3D(Basis(f.a as Vector3, Vector3.UP, f.n as Vector3), _p(f, u, y, o)) \
		* Transform3D(Basis.from_scale(Vector3(sc, sc, 1.0)), Vector3.ZERO)
	var idx = geo[2]
	var ids: PackedInt32Array = idx if idx != null else PackedInt32Array()
	if ids.is_empty():
		for k in vs.size():
			ids.append(k)
	for k in range(0, ids.size() - 2, 3):
		var a := vs[ids[k]]
		var b := vs[ids[k + 1]]
		var c := vs[ids[k + 2]]
		g.tri("bronze", xf * a, xf * b, xf * c, f.n, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))


## Commits the two meshes under the building, the lamps and the pool.
static func _commit(b: Building, st: Dictionary, part: int) -> void:
	if not is_instance_valid(b):
		return
	if part == 0:
		var holder := Node3D.new()
		holder.name = "Historic"
		b.add_child(holder)
		(st.main as LandmarkGeo).commit(holder, "HistoricMain", true, MAIN_DRAW)
		return
	var node := b.get_node("Historic") as Node3D
	(st.fine as LandmarkGeo).commit(node, "HistoricFine", false, FINE_DRAW)
	built_count += 1
	var lamps: Array = st.lamps
	if not lamps.is_empty():
		var light := OmniLight3D.new()
		var mid := Vector3.ZERO
		for q: Vector3 in lamps:
			mid += q
		light.position = mid / float(lamps.size())
		light.omni_range = 9.0
		light.omni_attenuation = 1.3
		light.light_color = LAMP_COLOR
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 70.0
		light.distance_fade_length = 20.0
		light.add_to_group("lamp_light")
		node.add_child(light)
	if st.has("pool"):
		var pl: Array = st.pool
		var pool := MeshInstance3D.new()
		pool.name = "EntrancePool"
		pool.mesh = PropFactory.light_pool(LAMP_COLOR, 1.1, 1.8)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var n: Vector3 = pl[1]
		var d: float = pl[2]
		pool.transform = Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)) * Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(d, 1.0, 5.0)), pl[0])
		pool.visibility_range_end = 120.0
		node.add_child(pool)


# --- Far ------------------------------------------------------------------------------------

## LOD chunks and the far city: the cornice of each street face as one far box (and its returns'
## worth of length), so the skyline keeps the overhang. The building's own coded boxes carry the
## rest.
static func far_boxes(ch: CityChunk, b: Building, style: Dictionary, faces: Array[Vector3], spec: Dictionary) -> void:
	var L := layout(b, style)
	if L.is_empty():
		return
	var H := heights(L)
	var cs: float = H.cs
	var depth := 1.28 * cs
	var tint: Color = HistoricCore.TERRACOTTA[int(spec.palette)]
	for n: Vector3 in faces:
		var f := _face(L, n, faces)
		var length: float = float(f.len) + 2.0 * depth
		var c := _p(f, 0.0, float(H.cornice) + CORNICE_H * cs * 0.5, depth * 0.5)
		var at: Vector3 = b.position + c
		at.y -= ch._gy(at.x, at.z)
		var basis := Basis(f.a as Vector3, Vector3.UP, f.n as Vector3) * Basis.from_scale(Vector3(length, CORNICE_H * cs, depth))
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(basis, at), tint, Color(0.0, 0.0, 0.0, 1.0))
		# The belt course over the base, thinner.
		var cb := _p(f, 0.0, float(H.belt) + BELT_H * L.scale * 0.5, 0.12)
		var atb: Vector3 = b.position + cb
		atb.y -= ch._gy(atb.x, atb.z)
		var bb := Basis(f.a as Vector3, Vector3.UP, f.n as Vector3) * Basis.from_scale(Vector3(float(f.len) + 0.48, BELT_H * float(L.scale), 0.24))
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(bb, atb), tint, Color(0.0, 0.0, 0.0, 1.0))
