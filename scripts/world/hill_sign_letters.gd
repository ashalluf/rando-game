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
const PIPE := 0.28

static var _letter_mat: StandardMaterial3D
static var _frame_mat: StandardMaterial3D


static func build(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var text: String = Landmarks.SIGN_TEXT
	var n := text.length()
	var cell: float = Landmarks.SIGN_SPAN / (float(n) * 5.0 + float(n - 1) * 1.5)
	var cap := 7.0 * cell
	var total := float(n) * 5.0 * cell + float(n - 1) * 1.5 * cell
	var base_y: float = Landmarks.sign_line(anchor, plan).ground + 2.0
	var pen := PEN * cap
	var lay := SignFont.layout(text, cap, pen)
	var strokes: Array = lay[0]
	# Widened to the old span: the road alphabet is narrow, a hillside sign's letters are broad.
	var sx: float = (total - pen) / maxf(float(lay[1]), 1.0)
	var x0 := anchor.x - total * 0.5 + pen * 0.5
	var z := anchor.y
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each letter its own touch of weathering (one roll per glyph, a hash of the index).
	var glyph_x: Array = []
	for s: PackedVector2Array in strokes:
		var gx := s[0].x
		var shade := 0.9 + 0.06 * fposmod(sin(floor(gx / (cap * 0.4)) * 12.9898) * 43758.5453, 1.0)
		for k in s.size() - 1:
			var a := Vector2(x0 + s[k].x * sx, base_y + s[k].y)
			var b := Vector2(x0 + s[k + 1].x * sx, base_y + s[k + 1].y)
			var d := b - a
			if d.length() < 0.01:
				continue
			var len := d.length() + pen
			var c := (a + b) * 0.5
			var xf := Transform3D(Basis(Vector3.BACK, d.angle()), Vector3(c.x, c.y, z))
			_box(st, xf, Vector3(len, pen, DEPTH), Color(shade, shade, shade * 0.98))
			if detailed and statics:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(len, pen, DEPTH)
				cs.shape = bs
				cs.transform = xf
				statics.add_child(cs)
		glyph_x.append(gx)
	var mi := MeshInstance3D.new()
	mi.name = "SignLetters"
	mi.mesh = st.commit()
	mi.material_override = _letters()
	parent.add_child(mi)
	_frame(anchor, parent, statics, plan, detailed, x0, sx, cap, pen, base_y, strokes)


## The pipe frame behind each letter: posts under its strokes' extent every POST_PITCH, down to
## the ground, rails at a third, two thirds and the top, a brace in every other bay.
static func _frame(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool,
		x0: float, sx: float, cap: float, pen: float, base_y: float, strokes: Array) -> void:
	# Each letter's x extent: strokes are laid left to right, a letter's strokes overlap in x.
	var spans: Array = []
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
	var z := anchor.y - FRAME_BACK
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grey := Color(0.42, 0.43, 0.44)
	for sp: Vector2 in spans:
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
