class_name HillSignLetters
## The ridge sign's letters as a real hillside sign (refcam hills, RcHills): tall sheet-metal
## letters in a clean sans (SignFont's strokes, a heavy pen, widened to the old span) standing on a
## galvanised pipe frame on the uphill side - posts every few metres down to the slope, rails and
## braces between them. The old letters were runs of 5 x 7 pixel boxes: from the basin they read as
## a voxel font. One mesh for the letters, one for the frame; box collision per stroke and post.
## Same span, the same level line and the same anchor as before (Landmarks.sign_line()).

## The pen, in cap heights (the real sign's letters are broad strokes of sheet metal).
const PEN := 0.19
## Front panel depth and the frame's offset behind it (metres).
const DEPTH := 0.6
const FRAME_BACK := 1.4
const POST_PITCH := 4.6
## A letter steps down with the hill at most this many cap heights under the old level line.
const STEP_MAX := 0.25
const PIPE := 0.28

static var _letter_mat: StandardMaterial3D
static var _frame_mat: StandardMaterial3D


static func build(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var text: String = Landmarks.SIGN_TEXT
	var n := text.length()
	var cell: float = Landmarks.SIGN_SPAN / (float(n) * 5.0 + float(n - 1) * 1.5)
	var cap := 7.0 * cell
	var total := float(n) * 5.0 * cell + float(n - 1) * 1.5 * cell
	var level: float = Landmarks.sign_line(anchor, plan).ground + 2.0
	var pen := PEN * cap
	var lay := SignFont.layout(text, cap, pen)
	var strokes: Array = lay[0]
	# Widened to the old span: the road alphabet is narrow, a hillside sign's letters are broad.
	var sx: float = (total - pen) / maxf(float(lay[1]), 1.0)
	var x0 := anchor.x - total * 0.5 + pen * 0.5
	var z := anchor.y
	# Each letter's x extent (a letter's strokes overlap in x) and the stroke -> letter index.
	var spans: Array = []
	var of: Array = []
	for s: PackedVector2Array in strokes:
		var lo := INF
		var hi := -INF
		for v in s:
			lo = minf(lo, x0 + v.x * sx)
			hi = maxf(hi, x0 + v.x * sx)
		lo -= pen * 0.5
		hi += pen * 0.5
		if not spans.is_empty() and lo < float(spans[-1].y) + pen * 0.6:
			spans[-1] = Vector2(minf(spans[-1].x, lo), maxf(spans[-1].y, hi))
		else:
			spans.append(Vector2(lo, hi))
		of.append(spans.size() - 1)
	# Each letter stands on its own ground, as a hillside sign's letters do: the highest ground
	# under its width, in front of it and under its frame, never lower than STEP_MAX caps under the
	# old level line. One level for the whole name sank the end letters where the ridge rises under
	# them (the S and H were half in the hill from the basin).
	var bases: Array = []
	for sp: Vector2 in spans:
		var g := -INF
		var x: float = sp.x
		while x <= sp.y + 0.01:
			for dz: float in [2.0, 0.0, -FRAME_BACK]:
				g = maxf(g, plan.height_at(Vector2(x, z + dz)))
			x += 2.0
		bases.append(maxf(g + 1.5, level - STEP_MAX * cap))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The ridge-sign refcam (RcRidgeSign): mitred ribbons on a sheet-metal shader, not boxes.
	var v2: bool = RcRidgeSign.on()
	if v2:
		_letters_v2(st, strokes, of, bases, x0, sx, z, pen)
	for si in strokes.size():
		var s: PackedVector2Array = strokes[si]
		var li: int = of[si]
		var base_y: float = bases[li]
		# Each letter its own touch of weathering (a hash of its index).
		var shade := 0.9 + 0.06 * fposmod(sin(float(li) * 12.9898 + 1.3) * 43758.5453, 1.0)
		for k in s.size() - 1:
			var a := Vector2(x0 + s[k].x * sx, base_y + s[k].y)
			var b := Vector2(x0 + s[k + 1].x * sx, base_y + s[k + 1].y)
			var d := b - a
			if d.length() < 0.01:
				continue
			var len := d.length() + pen
			var c := (a + b) * 0.5
			var xf := Transform3D(Basis(Vector3.BACK, d.angle()), Vector3(c.x, c.y, z))
			if not v2:
				_box(st, xf, Vector3(len, pen, DEPTH), Color(shade, shade, shade * 0.98))
			if detailed and statics:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(len, pen, DEPTH)
				cs.shape = bs
				cs.transform = xf
				statics.add_child(cs)
	if v2:
		# Kept for the checks: the headless renderer keeps no mesh data to read back.
		last_arrays = st.commit_to_arrays()
	var mi := MeshInstance3D.new()
	mi.name = "SignLetters"
	mi.mesh = st.commit()
	mi.material_override = _letters_v2_material() if v2 else _letters()
	parent.add_child(mi)
	_frame(anchor, parent, statics, plan, detailed, cap, spans, bases)


## The pipe frame behind each letter: posts across its width every POST_PITCH, down to the
## ground, rails at a third, two thirds and the top, a brace in every other bay.
static func _frame(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool,
		cap: float, spans: Array, bases: Array) -> void:
	var z := anchor.y - FRAME_BACK
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grey := Color(0.42, 0.43, 0.44)
	for li in spans.size():
		var sp: Vector2 = spans[li]
		var base_y: float = bases[li]
		var w: float = sp.y - sp.x
		var posts := maxi(2, int(ceil(w / POST_PITCH)) + 1)
		var xs: Array = []
		for i in posts:
			xs.append(lerpf(sp.x + 0.4, sp.y - 0.4, float(i) / float(posts - 1)))
		var top := base_y + cap
		for i in posts:
			var px: float = xs[i]
			var gy := plan.height_at(Vector2(px, z)) - 0.5
			var h := top - gy
			var xf := Transform3D(Basis(), Vector3(px, gy + h * 0.5, z))
			_box(st, xf, Vector3(PIPE, h, PIPE), grey)
			if detailed and statics and i % 2 == 0:
				Landmarks._shape(statics, Vector3(PIPE, h, PIPE), Vector3(px, gy + h * 0.5, z))
			# Short arms forward to the letter panels at the rails.
			for f: float in [0.33, 0.66, 0.98]:
				_box(st, Transform3D(Basis(), Vector3(px, base_y + cap * f, z + FRAME_BACK * 0.5)), Vector3(PIPE * 0.7, PIPE * 0.7, FRAME_BACK), grey)
		for f: float in [0.0, 0.33, 0.66, 0.98]:
			var y := base_y + cap * f
			_box(st, Transform3D(Basis(), Vector3((sp.x + sp.y) * 0.5, y, z)), Vector3(w - 0.4, PIPE * 0.8, PIPE * 0.8), grey)
		for i in posts - 1:
			if i % 2 == 1:
				continue
			var a := Vector2(float(xs[i]), base_y)
			var b := Vector2(float(xs[i + 1]), base_y + cap * 0.66)
			var d := b - a
			var c := (a + b) * 0.5
			_box(st, Transform3D(Basis(Vector3.BACK, d.angle()), Vector3(c.x, c.y, z)), Vector3(d.length(), PIPE * 0.6, PIPE * 0.6), grey)
		if RcRidgeSign.on():
			_legs_braced(st, plan, xs, z, base_y, grey)
	var mi := MeshInstance3D.new()
	mi.name = "SignFrame"
	mi.mesh = st.commit()
	mi.material_override = _frame_material()
	if not detailed:
		# From the basin the pipes are under a pixel: the far copy draws the frame to 600 m only.
		mi.visibility_range_end = 600.0
	parent.add_child(mi)


## A box of `size` placed by `xf`, flat-shaded (each face its own vertices).
static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f: Array in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := nrm * h
		var du := u * h
		var dv := v * h
		var p0 := xf * (c - du - dv)
		var p1 := xf * (c + du - dv)
		var p2 := xf * (c + du + dv)
		var p3 := xf * (c - du + dv)
		st.set_color(col)
		st.set_normal((xf.basis * nrm).normalized())
		# Godot's front faces wind clockwise seen from outside.
		for p: Vector3 in [p0, p2, p1, p0, p3, p2]:
			st.add_vertex(p)


static func _letters() -> StandardMaterial3D:
	if _letter_mat == null:
		_letter_mat = StandardMaterial3D.new()
		_letter_mat.vertex_color_use_as_albedo = true
		_letter_mat.vertex_color_is_srgb = true
		_letter_mat.albedo_color = Color(0.93, 0.93, 0.91)
		_letter_mat.roughness = 0.7
	return _letter_mat


static func _frame_material() -> StandardMaterial3D:
	if _frame_mat == null:
		_frame_mat = StandardMaterial3D.new()
		_frame_mat.vertex_color_use_as_albedo = true
		_frame_mat.vertex_color_is_srgb = true
		_frame_mat.metallic = 0.5
		_frame_mat.roughness = 0.55
	return _frame_mat


# --- The ridge-sign refcam's letters (RcRidgeSign) ------------------------------------------------

static var _v2_mat: ShaderMaterial
## The last v2 letters' surface arrays (tests/rc3_ridge_sign_checks.gd).
static var last_arrays: Array = []


## Every stroke as a mitred ribbon of sheet metal: a front face, a back and the returns round its
## edges, square ends. A stroke's joints are mitred (the bowls of S, U, D, O read as curves, not
## as notched boxes); strokes that overlap in a letter stand a few centimetres apart in depth, so
## no two front faces are coplanar. Colours: a per-letter tone (linear) and the part in alpha;
## UV the surface in metres, UV2 the letter and the height over its foot (ridge_sign.gdshader).
static func _letters_v2(st: SurfaceTool, strokes: Array, of: Array, bases: Array, x0: float, sx: float, z: float, pen: float) -> void:
	var in_letter := {}
	for si in strokes.size():
		var s: PackedVector2Array = strokes[si]
		var li: int = of[si]
		var k: int = in_letter.get(li, 0)
		in_letter[li] = k + 1
		var base_y: float = bases[li]
		var pts := PackedVector2Array()
		for v in s:
			var q := Vector2(x0 + v.x * sx, base_y + v.y)
			if pts.is_empty() or pts[pts.size() - 1].distance_to(q) > 0.05:
				pts.append(q)
		if pts.size() < 2:
			continue
		# Each letter a slightly different age of paint (a hash of its index).
		var r := fposmod(sin(float(li) * 12.9898 + 1.3) * 43758.5453, 1.0)
		var tone := Color(0.95 + 0.06 * r, 0.95 + 0.05 * r, 0.93 + 0.05 * r)
		var dz := 0.045 * float(k)
		_ribbon(st, pts, pen * 0.5, z + DEPTH * 0.5 + dz, z - DEPTH * 0.5 - dz, tone, float(li), base_y)


static func _ribbon(st: SurfaceTool, pts: PackedVector2Array, h: float, zf: float, zb: float, tone: Color, li: float, base_y: float) -> void:
	var n := pts.size()
	var closed := pts[0].distance_to(pts[n - 1]) < 0.1
	if closed:
		pts.remove_at(n - 1)
		n -= 1
	var segs := n if closed else n - 1
	# Segment directions and left normals.
	var dirs: Array = []
	for i in segs:
		dirs.append((pts[(i + 1) % n] - pts[i]).normalized())
	var p := pts.duplicate()
	if not closed:
		# Square ends: the pen's half width past each end.
		p[0] = p[0] - dirs[0] * h
		p[n - 1] = p[n - 1] + dirs[segs - 1] * h
	var off: Array = []      # per vertex: the left offset (mitre)
	var smooth: Array = []   # per vertex: soft corner (a curve) or a hard one
	for i in n:
		var a: Vector2
		var b: Vector2
		if closed:
			a = dirs[(i - 1 + segs) % segs]
			b = dirs[i % segs]
		else:
			a = dirs[maxi(i - 1, 0)]
			b = dirs[mini(i, segs - 1)]
		var na := Vector2(-a.y, a.x)
		var nb := Vector2(-b.y, b.x)
		var m := (na + nb).normalized()
		if m.length() < 0.5:
			m = nb
		# A very sharp corner (the W's and V's points) is bevelled: a true mitre there runs 1.4 pens out.
		var c := maxf(m.dot(nb), 0.72)
		off.append(m * (h / c))
		smooth.append(a.dot(b) > 0.86)
	var L := PackedVector2Array()
	var R := PackedVector2Array()
	for i in n:
		L.append(p[i] + off[i])
		R.append(p[i] - off[i])
	var fwd := Vector3(0, 0, 1)
	for i in segs:
		var j := (i + 1) % n
		# Front and back.
		_quad(st, Vector3(L[i].x, L[i].y, zf), Vector3(R[i].x, R[i].y, zf), Vector3(R[j].x, R[j].y, zf), Vector3(L[j].x, L[j].y, zf), [fwd, fwd, fwd, fwd], 1.0, tone, li, base_y)
		_quad(st, Vector3(L[i].x, L[i].y, zb), Vector3(R[i].x, R[i].y, zb), Vector3(R[j].x, R[j].y, zb), Vector3(L[j].x, L[j].y, zb), [-fwd, -fwd, -fwd, -fwd], 0.33, tone, li, base_y)
		# The returns along the left and right edges.
		var d: Vector2 = dirs[i]
		var nl := Vector2(-d.y, d.x)
		var nli: Vector2 = (off[i] as Vector2).normalized() if smooth[i] else nl
		var nlj: Vector2 = (off[j] as Vector2).normalized() if smooth[j] else nl
		var a3 := Vector3(nli.x, nli.y, 0.0)
		var b3 := Vector3(nlj.x, nlj.y, 0.0)
		_quad(st, Vector3(L[i].x, L[i].y, zf), Vector3(L[j].x, L[j].y, zf), Vector3(L[j].x, L[j].y, zb), Vector3(L[i].x, L[i].y, zb), [a3, b3, b3, a3], 0.66, tone, li, base_y)
		_quad(st, Vector3(R[i].x, R[i].y, zf), Vector3(R[j].x, R[j].y, zf), Vector3(R[j].x, R[j].y, zb), Vector3(R[i].x, R[i].y, zb), [-a3, -b3, -b3, -a3], 0.66, tone, li, base_y)
	if not closed:
		var d0: Vector2 = -(dirs[0] as Vector2)
		var d1: Vector2 = dirs[segs - 1]
		var e0 := Vector3(d0.x, d0.y, 0.0)
		var e1 := Vector3(d1.x, d1.y, 0.0)
		_quad(st, Vector3(L[0].x, L[0].y, zf), Vector3(R[0].x, R[0].y, zf), Vector3(R[0].x, R[0].y, zb), Vector3(L[0].x, L[0].y, zb), [e0, e0, e0, e0], 0.66, tone, li, base_y)
		var k := n - 1
		_quad(st, Vector3(L[k].x, L[k].y, zf), Vector3(R[k].x, R[k].y, zf), Vector3(R[k].x, R[k].y, zb), Vector3(L[k].x, L[k].y, zb), [e1, e1, e1, e1], 0.66, tone, li, base_y)


## A quad a-b-c-d (two triangles), wound so it faces its normals (Godot's front faces are clockwise
## seen from outside: the cross product of the edges points away from the normal).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Array, part: float, tone: Color, li: float, base_y: float) -> void:
	var avg: Vector3 = (nrm[0] as Vector3) + (nrm[1] as Vector3) + (nrm[2] as Vector3) + (nrm[3] as Vector3)
	var ps := [a, b, c, d]
	var order := [0, 1, 2, 0, 2, 3]
	if (b - a).cross(c - a).dot(avg) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for o: int in order:
		var v: Vector3 = ps[o]
		st.set_color(Color(tone.r, tone.g, tone.b, part))
		st.set_normal(nrm[o])
		st.set_uv(Vector2(v.x, v.y))
		st.set_uv2(Vector2(li, v.y - base_y))
		st.add_vertex(v)


static func _letters_v2_material() -> ShaderMaterial:
	if _v2_mat == null:
		_v2_mat = ShaderMaterial.new()
		_v2_mat.shader = load("res://shaders/ridge_sign.gdshader")
	return _v2_mat


## Under a letter held up off a falling slope the posts ran down to the ground bare: from the basin
## a comb of thin lines hanging under the name. Now the legs are a braced bent (RcRidgeSign): a
## tie between neighbouring posts every LEG_BAY metres down to where the ground meets them, and a
## diagonal across each bay, alternating, as a real hillside sign's legs are braced.
const LEG_BAY := 4.5


static func _legs_braced(st: SurfaceTool, plan: CityPlan, xs: Array, z: float, base_y: float, col: Color) -> void:
	var gys: Array = []
	for px: float in xs:
		gys.append(plan.height_at(Vector2(px, z)) - 0.5)
	for i in xs.size() - 1:
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		var floor_y := maxf(float(gys[i]), float(gys[i + 1])) + 0.6
		var y := base_y
		var k := 0
		while y - LEG_BAY > floor_y:
			var y1 := y - LEG_BAY
			_box(st, Transform3D(Basis(), Vector3((x0 + x1) * 0.5, y1, z)), Vector3(x1 - x0, PIPE * 0.7, PIPE * 0.7), col)
			var a := Vector2(x0, y) if (i + k) % 2 == 0 else Vector2(x1, y)
			var b := Vector2(x1, y1) if (i + k) % 2 == 0 else Vector2(x0, y1)
			var d := b - a
			var c := (a + b) * 0.5
			_box(st, Transform3D(Basis(Vector3.BACK, d.angle()), Vector3(c.x, c.y, z)), Vector3(d.length(), PIPE * 0.55, PIPE * 0.55), col)
			y = y1
			k += 1
