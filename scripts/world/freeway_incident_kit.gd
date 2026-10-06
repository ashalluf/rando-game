class_name FreewayIncidentKit
extends RefCounted
## The things FreewayIncidents puts on the freeway that are not vehicles or people, built in code
## at real size: the shredded tread of a truck tyre (a "gator": a curled strip of rubber with its
## lugs, torn ends and the steel belt's wires sticking out), a queen mattress lying in a lane
## (quilted top, border panel, piping, sagged over the joint of the deck), and the changeable
## message sign - its cabinet (FreewayKit builds it into the gantry's structure mesh through
## cms_cabinet(), at every level) and its LED face (a quad FreewayIncidents puts on the cabinets
## near the player, shaders/freeway_cms.gdshader, the message an L8 texture of LedScreen.GLYPHS).

## The tread strip: width across (m), thickness (m), the lug height (m).
const TREAD_W := 0.29
const TREAD_T := 0.022
const LUG_H := 0.014
## A queen mattress (m).
const MATTRESS := Vector3(1.52, 0.24, 2.03)
## The CMS: characters a line, lines, and the LED face's margins inside the cabinet (m).
const CMS_CHARS := 20
const CMS_LINES := 3
const CMS_DEPTH := 0.68
const CMS_BEZEL := Vector4(0.2, 0.2, 0.16, 0.26)

static var _tread: Dictionary = {}
static var _mattress: Array = []
static var _rubber_mat: StandardMaterial3D
static var _mattress_mat: ShaderMaterial
static var _cms_tex: Dictionary = {}
static var _cms_shader: Shader
static var _face_mesh: QuadMesh


# --- Tyre tread ----------------------------------------------------------------------------------

## One piece of shredded tread, `variant` 0..5 (its length, curl, which face is up, the tear).
## Origin on the deck under its middle, length along z. ~1-2k triangles.
static func tread_mesh(variant: int) -> ArrayMesh:
	if _tread.has(variant):
		return _tread[variant]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([variant, "fw_tread"])
	var length := rng.randf_range(0.55, 1.7)
	var curl := rng.randf_range(0.65, 1.6)
	var lugs_up := rng.randf() < 0.6
	var twist := rng.randf_range(-0.25, 0.25)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rubber := Color(0.030, 0.030, 0.032)
	var worn := Color(0.070, 0.068, 0.066)
	var liner := Color(0.045, 0.043, 0.042)
	var nz := maxi(8, int(length / 0.03))
	var nx := 12
	# Torn ends: each column's end is ragged.
	var tear0 := PackedFloat32Array()
	var tear1 := PackedFloat32Array()
	for i in nx + 1:
		tear0.append(rng.randf_range(0.0, 0.07))
		tear1.append(rng.randf_range(0.0, 0.07))
	var top := []
	var bot := []
	for j in nz + 1:
		var row_t := []
		var row_b := []
		for i in nx + 1:
			var fx := float(i) / nx
			var x := (fx - 0.5) * TREAD_W
			var lo := -length * 0.5 + tear0[i]
			var hi := length * 0.5 - tear1[i]
			var z := lerpf(lo, hi, float(j) / nz)
			# Curled: the ends lift off the deck, a little twist along it.
			var y := curl * 0.18 * pow(z / (length * 0.5), 2.0) * (length * 0.5) + twist * x * z
			var lug := 0.0
			# Lugs: four ribs of blocks across, the grooves between and the sipes across them.
			var rib := fposmod(fx * 4.0, 1.0)
			var blk := fposmod(z / 0.085 + (0.5 if int(fx * 4.0) % 2 == 1 else 0.0), 1.0)
			if rib > 0.16 and rib < 0.86 and blk > 0.14 and blk < 0.9 and i > 0 and i < nx:
				lug = LUG_H
			var up := Vector3(-twist * z, 1.0, -curl * 0.36 * z / (length * 0.5)).normalized()
			var base := Vector3(x, y + TREAD_T * 0.5 + 0.004, z)
			var t_off := (TREAD_T * 0.5 + (lug if lugs_up else 0.0))
			var b_off := (TREAD_T * 0.5 + (0.0 if lugs_up else lug))
			row_t.append([base + up * t_off, lug > 0.0])
			row_b.append([base - up * b_off, lug > 0.0])
		top.append(row_t)
		bot.append(row_b)
	for j in nz:
		for i in nx:
			var a: Array = top[j][i]
			var b: Array = top[j][i + 1]
			var c: Array = top[j + 1][i + 1]
			var d: Array = top[j + 1][i]
			var col_t := worn if (lugs_up and bool(a[1]) and bool(c[1])) else (rubber if lugs_up else liner)
			_quad(st, a[0], b[0], c[0], d[0], col_t, Vector3.UP)
			var e: Array = bot[j][i]
			var f: Array = bot[j][i + 1]
			var g: Array = bot[j + 1][i + 1]
			var h: Array = bot[j + 1][i]
			var col_b := worn if (not lugs_up and bool(e[1]) and bool(g[1])) else (liner if lugs_up else rubber)
			_quad(st, e[0], h[0], g[0], f[0], col_b, Vector3.DOWN)
	# Side walls along both long edges and the torn ends.
	for j in nz:
		for side in [0, nx]:
			var want := Vector3(-1.0 if side == 0 else 1.0, 0.0, 0.0)
			_quad(st, top[j][side][0], top[j + 1][side][0], bot[j + 1][side][0], bot[j][side][0], rubber, want)
	for i in nx:
		_quad(st, top[0][i][0], top[0][i + 1][0], bot[0][i + 1][0], bot[0][i][0], liner, Vector3.BACK * -1.0)
		_quad(st, top[nz][i][0], top[nz][i + 1][0], bot[nz][i + 1][0], bot[nz][i][0], liner, Vector3.BACK)
	# The steel belt's wires out of the torn ends: thin bent strands, rust brown.
	var steel := Color(0.30, 0.22, 0.16)
	for end in [0, nz]:
		var n := rng.randi_range(5, 11)
		for k in n:
			var i := rng.randi_range(1, nx - 1)
			var p: Vector3 = (top[end][i][0] + bot[end][i][0]) * 0.5
			var out := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.05, 0.4), -1.0 if end == 0 else 1.0).normalized()
			var len := rng.randf_range(0.03, 0.14)
			_strand(st, p, p + out * len + Vector3(0.0, rng.randf_range(-0.01, 0.03), 0.0), 0.0016, steel)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, rubber_material())
	_tread[variant] = mesh
	return mesh


static func rubber_material() -> StandardMaterial3D:
	if _rubber_mat == null:
		_rubber_mat = StandardMaterial3D.new()
		_rubber_mat.vertex_color_use_as_albedo = true
		_rubber_mat.roughness = 0.82
		_rubber_mat.specular = 0.35
		_rubber_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _rubber_mat


# --- Mattress ------------------------------------------------------------------------------------

## The mattress, `variant` 0..2 (cover colour, sag, its fold): origin under its middle on the
## deck, length along z. UV in metres; COLOR.a is the part for fw_mattress.gdshader (1 the quilted
## top, 0.5 the border, 0 the underside), COLOR.rgb the cover.
static func mattress_mesh(variant: int) -> ArrayMesh:
	while _mattress.size() <= variant:
		_mattress.append(null)
	if _mattress[variant] != null:
		return _mattress[variant]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([variant, "fw_mattress"])
	var covers := [Color(0.86, 0.86, 0.84), Color(0.80, 0.81, 0.84), Color(0.84, 0.80, 0.72)]
	var cover: Color = covers[variant % covers.size()]
	var fold := rng.randf_range(0.05, 0.16)
	var fold_at := rng.randf_range(-0.35, 0.35)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := MATTRESS.x
	var h := MATTRESS.y
	var l := MATTRESS.z
	var nx := 16
	var nz := 22
	var r := 0.07
	# Heights of the centre plane along z: lying over the deck's camber with one end kicked up
	# where it folded when it hit the road.
	var lift := func(z: float, x: float) -> float:
		var k := clampf((z / (l * 0.5) - fold_at) / (1.0 - fold_at), 0.0, 1.0)
		return fold * k * k + 0.01 * sin(x * 3.1 + z * 1.7)
	# Top and bottom, with the edge rounded: x and y pulled in toward the corners.
	for face in [1.0, -1.0]:
		var grid := []
		for j in nz + 1:
			var z := (float(j) / nz - 0.5) * l
			var row := []
			for i in nx + 1:
				var x := (float(i) / nx - 0.5) * w
				var y := (h if face > 0.0 else 0.0) + float(lift.call(z, x))
				# The top crowns a little in the middle (filling).
				if face > 0.0:
					y += 0.025 * (1.0 - pow(2.0 * x / w, 4.0)) * (1.0 - pow(2.0 * z / l, 4.0))
				row.append(Vector3(x, y, z))
			grid.append(row)
		var col := Color(cover.r, cover.g, cover.b, 1.0 if face > 0.0 else 0.0)
		for j in nz:
			for i in nx:
				var a: Vector3 = grid[j][i]
				var b: Vector3 = grid[j][i + 1]
				var c: Vector3 = grid[j + 1][i + 1]
				var d: Vector3 = grid[j + 1][i]
				_quad_uv(st, a, b, c, d, col, Vector3.UP * face, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z))
	# The border: four sides as strips of rows up the height, the corner rounded by `r`.
	var ring := PackedVector2Array()
	for k in 4:
		var cx := w * 0.5 - r if k == 0 or k == 1 else -w * 0.5 + r
		var cz := l * 0.5 - r if k == 1 or k == 2 else -l * 0.5 + r
		var a0 := -PI * 0.5 + PI * 0.5 * float(k)
		for s in 4:
			var a := a0 + PI * 0.5 * float(s) / 3.0
			ring.append(Vector2(cx + cos(a) * r, cz + sin(a) * r))
	var side_col := Color(cover.r * 0.92, cover.g * 0.92, cover.b * 0.94, 0.5)
	var run := 0.0
	for k in ring.size():
		var p0 := ring[k]
		var p1 := ring[(k + 1) % ring.size()]
		var seg := p0.distance_to(p1)
		var out := Vector2(p1.y - p0.y, p0.x - p1.x).normalized()
		var nrm := Vector3(out.x, 0.0, out.y)
		var y0a := float(lift.call(p0.y, p0.x))
		var y0b := float(lift.call(p1.y, p1.x))
		_quad_uv(st, Vector3(p0.x, y0a, p0.y), Vector3(p1.x, y0b, p1.y), Vector3(p1.x, y0b + h, p1.y), Vector3(p0.x, y0a + h, p0.y),
			side_col, nrm, Vector2(run, 0.0), Vector2(run + seg, 0.0), Vector2(run + seg, h), Vector2(run, h))
		run += seg
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, mattress_material())
	_mattress[variant] = mesh
	return mesh


static func mattress_material() -> ShaderMaterial:
	if _mattress_mat == null:
		_mattress_mat = ShaderMaterial.new()
		_mattress_mat.shader = load("res://shaders/fw_mattress.gdshader")
	return _mattress_mat


# --- The changeable message sign -----------------------------------------------------------------

## LED cells across and down the face (one texel a LED): CMS_CHARS 5x7 glyphs a line, a column
## between them, three dark rows between lines, a two-LED margin all round.
static func cms_cells() -> Vector2i:
	return Vector2i(CMS_CHARS * 6 - 1 + 4, CMS_LINES * 7 + (CMS_LINES - 1) * 3 + 4)


## The face's size (m) for a cabinet `w` wide: the LED pitch is the same across and down.
static func cms_face_size(w: float) -> Vector2:
	var c := cms_cells()
	var fw := w - CMS_BEZEL.x - CMS_BEZEL.y
	return Vector2(fw, fw * float(c.y) / float(c.x))


## The cabinet's height for a face `w` wide.
static func cms_height(w: float) -> float:
	return cms_face_size(w).y + CMS_BEZEL.z + CMS_BEZEL.w


## The message as one L8 texture: `lines` (up to CMS_LINES strings, each up to CMS_CHARS), every
## line centred. Cached by text.
static func cms_texture(lines: Array) -> ImageTexture:
	var key := "|".join(PackedStringArray(lines))
	if _cms_tex.has(key):
		return _cms_tex[key]
	var c := cms_cells()
	var img := Image.create(c.x, c.y, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	for li in mini(lines.size(), CMS_LINES):
		var text := String(lines[li]).to_upper().substr(0, CMS_CHARS)
		var x := (c.x - (text.length() * 6 - 1)) / 2
		var y0 := 2 + li * 10
		for ch in text:
			var rows: Array = LedScreen.GLYPHS.get(ch, LedScreen.GLYPHS[" "])
			for r in 7:
				var row: String = rows[r]
				for k in 5:
					if row[k] == "#":
						img.set_pixel(x + k, y0 + r, Color.WHITE)
			x += 6
	var tex := ImageTexture.create_from_image(img)
	if _cms_tex.size() > 256:
		_cms_tex.clear()
	_cms_tex[key] = tex
	return tex


## A face's material: two pages that alternate (`b` empty: one page), its own copy per sign.
static func cms_material(a: Array, b: Array) -> ShaderMaterial:
	if _cms_shader == null:
		_cms_shader = load("res://shaders/freeway_cms.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = _cms_shader
	set_message(mat, a, b)
	return mat


static func set_message(mat: ShaderMaterial, a: Array, b: Array) -> void:
	var c := cms_cells()
	mat.set_shader_parameter("page_a", cms_texture(a))
	mat.set_shader_parameter("page_b", cms_texture(b if not b.is_empty() else a))
	mat.set_shader_parameter("cells", Vector2(c.x, c.y))
	mat.set_shader_parameter("two_pages", 0.0 if b.is_empty() else 1.0)


## The face quad, 1 x 1 m (scaled per sign), facing +Z.
static func face_mesh() -> QuadMesh:
	if _face_mesh == null:
		_face_mesh = QuadMesh.new()
		_face_mesh.size = Vector2.ONE
	return _face_mesh


## The cabinet into a FreewayKit's structure mesh (its gantry hook): a walk-in LED cabinet hung
## on the truss in front of the board's place, `xf` the board's frame (origin bottom centre, x
## right, z out toward the traffic), `w` its width. A black bezel round the face, a sun hood on
## top, louvred vents down the sides, and the catwalk below at FULL.
static func cms_cabinet(kit: FreewayKit, xf: Transform3D, w: float) -> void:
	var right := xf.basis.x
	var out := xf.basis.z
	var up := Vector3.UP
	var h := cms_height(w)
	var steel := FreewayKit.kind_color(Color(0.46, 0.47, 0.48), FreewayKit.S_STEEL)
	var dark := FreewayKit.kind_color(Color(0.035, 0.035, 0.04), FreewayKit.S_PAINTED)
	var c := xf.origin + up * (h * 0.5) + out * (CMS_DEPTH * 0.5 - 0.1)
	kit.box(kit.body, c, right * (w * 0.5), up * (h * 0.5), out * (CMS_DEPTH * 0.5), steel, 0.0, false)
	# The bezel: a black frame proud of the front.
	var front := xf.origin + out * (CMS_DEPTH - 0.1 + 0.012)
	var fs := cms_face_size(w)
	var fx0 := -w * 0.5 + CMS_BEZEL.x
	var fy0 := CMS_BEZEL.z
	var x1 := fx0 + fs.x
	var y1 := fy0 + fs.y
	# [x0, x1, y0, y1] of each frame piece: bottom, top, left, right.
	for r: Array in [[-w * 0.5, w * 0.5, 0.0, fy0], [-w * 0.5, w * 0.5, y1, h], [-w * 0.5, fx0, fy0, y1], [x1, w * 0.5, fy0, y1]]:
		var mx := (float(r[0]) + float(r[1])) * 0.5
		var my := (float(r[2]) + float(r[3])) * 0.5
		kit.box(kit.body, front + right * mx + up * my, right * ((float(r[1]) - float(r[0])) * 0.5), up * ((float(r[3]) - float(r[2])) * 0.5), out * 0.012, dark, 0.0, false)
	# The dark glass behind where the LED face goes (seen when the face is not built: LOD).
	kit.quad(kit.body, front + right * (fx0) + up * fy0 - out * 0.004, front + right * (fx0 + fs.x) + up * fy0 - out * 0.004,
		front + right * (fx0 + fs.x) + up * (fy0 + fs.y) - out * 0.004, front + right * fx0 + up * (fy0 + fs.y) - out * 0.004,
		out, dark, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	# Sun hood over the face.
	kit.box(kit.body, xf.origin + up * (h + 0.02) + out * (CMS_DEPTH - 0.1 + 0.12), right * (w * 0.5 + 0.03), up * 0.02, out * 0.14, steel, 0.0, false)
	if kit.full:
		# Louvres down each end and the catwalk with its rail below.
		for s: float in [-1.0, 1.0]:
			for k in 6:
				var lv := xf.origin + right * (s * (w * 0.5 + 0.01)) + up * (0.35 + float(k) * h * 0.12) + out * (CMS_DEPTH * 0.5 - 0.1)
				kit.box(kit.body, lv, right * 0.012, up * 0.025, out * 0.22, dark, 0.0, false)
		var cw := xf.origin + out * 0.3 + up * -0.2
		kit.box(kit.body, cw, right * (w * 0.5), up * 0.04, out * 0.42, FreewayKit.kind_color(Color(0.40, 0.41, 0.42), FreewayKit.S_STEEL))
		kit.prism(kit.body, cw + out * 0.4 + up * 0.95 - right * (w * 0.5), cw + out * 0.4 + up * 0.95 + right * (w * 0.5), 0.022, 0.022, 4, steel, false)


## A light strip of shredded tread for the shoulders' litter (FreewayKit._furniture): `l` metres
## half-length along `ax` (unit, flat), `w` half-width along `az`, curled up at the far end and
## sagging at the near one, lug blocks across its top as alternating shades. ~72 triangles into
## the kit's structure mesh (S_RUBBER).
static func shoulder_tread(kit: FreewayKit, p: Vector3, ax: Vector3, az: Vector3, l: float, w: float, seed: float) -> void:
	var n := 6
	var rub := FreewayKit.kind_color(Color(0.055, 0.055, 0.058), FreewayKit.S_RUBBER)
	var lug := FreewayKit.kind_color(Color(0.085, 0.084, 0.082), FreewayKit.S_RUBBER)
	var t := 0.02
	var curl := 0.3 + 0.5 * seed
	var pts := []
	for j in n + 1:
		var f := float(j) / n * 2.0 - 1.0
		var lift := curl * 0.22 * maxf(f, 0.0) * maxf(f, 0.0) * l + 0.01 * (1.0 - f * f)
		var tear := 0.015 * sin(float(j) * 2.7 + seed * 9.0)
		pts.append(p + ax * (f * l) + Vector3(0.0, lift, 0.0) + az * tear)
	for j in n:
		var a: Vector3 = pts[j]
		var b: Vector3 = pts[j + 1]
		var up := (b - a).cross(az).normalized()
		if up.y < 0.0:
			up = -up
		for k in 3:
			var u0 := -w + 2.0 * w * float(k) / 3.0
			var u1 := -w + 2.0 * w * float(k + 1) / 3.0
			var col := lug if (j + k) % 2 == 0 else rub
			kit.quad(kit.body, a + az * u0 + up * t, a + az * u1 + up * t, b + az * u1 + up * t, b + az * u0 + up * t, up, col)
		kit.quad(kit.body, a - az * w, a + az * w, b + az * w, b - az * w, -up, rub)
		kit.quad(kit.body, a + az * w, a + az * w + up * t, b + az * w + up * t, b + az * w, az, rub)
		kit.quad(kit.body, a - az * w, a - az * w + up * t, b - az * w + up * t, b - az * w, -az, rub)


## Where the LED face of the cabinet in frame `xf` (w wide) goes: the quad's transform (scaled to
## the face's size, a hair in front of the bezel's inner edge).
static func cms_face_xform(xf: Transform3D, w: float) -> Transform3D:
	var fs := cms_face_size(w)
	var right := xf.basis.x
	var out := xf.basis.z
	var centre := xf.origin + out * (CMS_DEPTH - 0.1 + 0.016) + Vector3.UP * (CMS_BEZEL.z + fs.y * 0.5) \
		+ right * ((CMS_BEZEL.x - CMS_BEZEL.y) * 0.5)
	return Transform3D(Basis(right * fs.x, Vector3.UP * fs.y, out), centre)


# --- helpers --------------------------------------------------------------------------------------

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, want: Vector3) -> void:
	_quad_uv(st, a, b, c, d, col, want, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z))


## Two triangles, wound so they face `want` (generate_normals() then points them that way).
static func _quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, want: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(want) > 0.0:
		# The project's winding is clockwise from the front: flip.
		var t := b
		b = d
		d = t
		var tu := ub
		ub = ud
		ud = tu
	for pv: Array in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
		st.set_color(col)
		st.set_uv(pv[1])
		st.add_vertex(pv[0])


## A thin square strand from a to b.
static func _strand(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized() * r
	var v := ax.cross(u).normalized() * r
	var corners := [u + v, u - v, -u - v, -u + v]
	for k in 4:
		var p: Vector3 = corners[k]
		var q: Vector3 = corners[(k + 1) % 4]
		_quad(st, a + p, a + q, b + q, b + p, col, (p + q).normalized())
