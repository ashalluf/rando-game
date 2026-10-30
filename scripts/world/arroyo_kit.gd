class_name ArroyoKit
extends RefCounted
## The washes' hardware, built in code at real size: water-worn cobbles (three shapes, a metre
## across before scaling, flattened by the instance) and the culvert headwall round one or two
## corrugated steel pipes (shaders/arroyo_culvert.gdshader).

static var _cache: Dictionary = {}


## A rounded stone, about 1 m across at scale 1, base at y 0 (half its height is under ground
## when placed: ArroyoBuild sinks them). Variants differ in shape; ~180 / 80 / 24 triangles in
## three LODs.
static func pebble(v: int) -> Mesh:
	var key := "pebble_%d" % v
	if _cache.has(key):
		return _cache[key]
	var levels: Array = []
	for l in 3:
		levels.append(_pebble_level(v, [8, 5, 3][l], [12, 8, 4][l]))
	# Each level has its own rings, so the LODs are index lists into one merged vertex buffer.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx_all: Array = []
	for lv: Array in levels:
		var base := verts.size()
		verts.append_array(lv[Mesh.ARRAY_VERTEX])
		norms.append_array(lv[Mesh.ARRAY_NORMAL])
		uvs.append_array(lv[Mesh.ARRAY_TEX_UV])
		var idx := PackedInt32Array()
		for i: int in lv[Mesh.ARRAY_INDEX]:
			idx.append(i + base)
		idx_all.append(idx)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = idx_all[0]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {0.03: idx_all[1], 0.09: idx_all[2]})
	mesh.surface_set_material(0, stone_material())
	_cache[key] = mesh
	return mesh


static func _pebble_level(v: int, rings: int, segs: int) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var lumps: Vector3 = [Vector3(1.0, 0.62, 0.8), Vector3(1.0, 0.5, 0.7), Vector3(0.85, 0.7, 0.85)][v % 3]
	for r in rings + 1:
		var th := PI * float(r) / rings
		for s in segs + 1:
			var ph := TAU * float(s) / segs
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			# A worn, uneven stone: a low-order wobble, the same at every LOD.
			var wob := 1.0 + 0.13 * sin(ph * 2.0 + v * 1.3) * sin(th * 2.0) + 0.08 * cos(ph * 3.0 + v * 2.1) * sin(th) + 0.05 * sin(ph * 5.0 + th * 3.0 + v)
			var p := Vector3(d.x * lumps.x, d.y * lumps.y, d.z * lumps.z) * 0.5 * wob
			p.y += 0.5 * lumps.y
			verts.append(p)
			norms.append(Vector3(d.x / lumps.x, d.y / lumps.y, d.z / lumps.z).normalized())
			uvs.append(Vector2(float(s) / segs, float(r) / rings))
	for r in rings:
		for s in segs:
			var a := r * (segs + 1) + s
			var b := a + 1
			var c := a + segs + 1
			var d := c + 1
			# Clockwise seen from outside (Godot's front face).
			idx.append_array([a, c, b, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


static var _stone_mat: StandardMaterial3D = null


## The cobbles' material: the rock texture world-projected, tinted per instance.
static func stone_material() -> StandardMaterial3D:
	if _stone_mat == null:
		# The rock scan at a quarter metre a tile (grain and pits at a cobble's size), darkened to
		# a wet-worn granite's value; the instance tint varies it stone to stone.
		var m: StandardMaterial3D = PropFactory.pbr("rock", 0.25, Color(0.5, 0.48, 0.45), 1.0, true).duplicate()
		m.roughness = 0.88
		m.metallic_specular = 0.35
		_stone_mat = m
	return _stone_mat


## A cobble's tint from a hash: granite greys, tan, now and then rose or a dark stone.
static func stone_tint(t: float) -> Color:
	if t < 0.5:
		return Color(1.0, 0.98, 0.95).lerp(Color(0.72, 0.7, 0.68), t * 2.0)
	if t < 0.8:
		return Color(1.0, 0.9, 0.74)
	if t < 0.92:
		return Color(1.02, 0.8, 0.72)
	return Color(0.45, 0.45, 0.43)


## The headwall's width for `pipes` pipes of radius `r`.
static func headwall_width(r: float, pipes: int) -> float:
	return pipes * 2.0 * r + (pipes - 1) * 0.6 * r + 1.4


static var _culvert_mat: ShaderMaterial = null


static func culvert_material() -> ShaderMaterial:
	if _culvert_mat == null:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/arroyo_culvert.gdshader")
		m.set_shader_parameter("concrete_albedo", PropFactory.texture("concrete", "Color"))
		m.set_shader_parameter("concrete_normal", PropFactory.texture("concrete", "NormalGL"))
		_culvert_mat = m
	return _culvert_mat


## A culvert end in its own frame: +Z out of the bank, x across, y up, the pipes' invert at the
## origin on the headwall's face (z 0). Headwall, coping, two splayed wing walls, an apron, and
## each pipe as a corrugated tube from 0.2 m proud of the face back 2.5 m into the bank.
static func culvert_mesh(r: float, pipes: int) -> Mesh:
	var key := "culvert_%.2f_%d" % [r, pipes]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := headwall_width(r, pipes)
	var h := 2.0 * r + 0.55
	var spacing := 2.6 * r
	var centres: Array[float] = []
	for k in pipes:
		centres.append((k - (pipes - 1) * 0.5) * spacing)
	# The headwall's face with the pipes' holes: a polygon with holes, triangulated.
	var outline := PackedVector2Array([Vector2(-w * 0.5, -0.4), Vector2(w * 0.5, -0.4), Vector2(w * 0.5, h), Vector2(-w * 0.5, h)])
	var pts := PackedVector2Array(outline)
	var ro := r + 0.03
	for cx in centres:
		for s in 24:
			var a := TAU * s / 24.0
			pts.append(Vector2(cx + cos(a) * ro, r + sin(a) * ro))
	# Points along the edges, so no triangle reaches from a hole to a far corner.
	for k in 9:
		var t := float(k + 1) / 10.0
		pts.append(Vector2(lerpf(-w * 0.5, w * 0.5, t), -0.4))
		pts.append(Vector2(lerpf(-w * 0.5, w * 0.5, t), h))
	for k in 4:
		var t := float(k + 1) / 5.0
		pts.append(Vector2(-w * 0.5, lerpf(-0.4, h, t)))
		pts.append(Vector2(w * 0.5, lerpf(-0.4, h, t)))
	var tri := Geometry2D.triangulate_delaunay(pts)
	for i in range(0, tri.size(), 3):
		var a := pts[tri[i]]
		var b := pts[tri[i + 1]]
		var c := pts[tri[i + 2]]
		var cen := (a + b + c) / 3.0
		var inside := false
		for cx in centres:
			if cen.distance_to(Vector2(cx, r)) < ro:
				inside = true
		if inside:
			continue
		_tri(st, Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, 0.0), Vector3(c.x, c.y, 0.0), Vector3(0, 0, 1), 0.0, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
	# The back, top and ends of the wall (0.35 thick), and the coping on top.
	var t := 0.35
	_box(st, Vector3(-w * 0.5, -0.4, -t), Vector3(w * 0.5, h, -0.0001), [false, true, true, true, true, true])
	_box(st, Vector3(-w * 0.5 - 0.06, h, -t - 0.06), Vector3(w * 0.5 + 0.06, h + 0.16, 0.08), [true, true, true, true, true, false])
	# Wing walls, splayed 30 degrees, falling from the wall's height to 0.35 m.
	for side: float in [-1.0, 1.0]:
		var base := Vector3(side * w * 0.5, 0.0, 0.0)
		var dir := Vector3(side * sin(deg_to_rad(30.0)), 0.0, cos(deg_to_rad(30.0)))
		var nrm := Vector3(dir.z, 0.0, -dir.x) * side
		var l := 1.7
		var tk := 0.25
		var a0 := base - nrm * 0.0
		var a1 := base + dir * l
		var top0 := h
		var top1 := 0.35
		# Outer face, inner face, top.
		var q := [a0 + Vector3(0, -0.4, 0), a1 + Vector3(0, -0.4, 0), a1 + Vector3(0, top1, 0), a0 + Vector3(0, top0, 0)]
		var off := -nrm * tk
		_quad(st, q[0], q[1], q[2], q[3], -nrm, 0.0, l, h)
		_quad(st, q[1] + off, q[0] + off, q[3] + off, q[2] + off, nrm, 0.0, l, h)
		_quad(st, q[3], q[2], q[2] + off, q[3] + off, Vector3.UP, 0.0, l, tk)
		_quad(st, q[1], q[1] + off, q[2] + off, q[2], dir, 0.0, tk, h)
	# The apron: a slab out from the wall between the wings.
	var ap := 1.7 * cos(deg_to_rad(30.0))
	var spread := w * 0.5 + 1.7 * sin(deg_to_rad(30.0)) - 0.25
	_quad(st, Vector3(-w * 0.5 + 0.25, 0.04, 0.0), Vector3(w * 0.5 - 0.25, 0.04, 0.0), Vector3(spread, 0.04, ap), Vector3(-spread, 0.04, ap), Vector3.UP, 0.0, w, ap)
	_quad(st, Vector3(-spread, 0.04, ap), Vector3(spread, 0.04, ap), Vector3(spread, -0.6, ap), Vector3(-spread, -0.6, ap), Vector3(0, 0, 1), 0.0, w, 0.6)
	# The pipes.
	for cx in centres:
		_pipe(st, Vector3(cx, r, 0.0), r)
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, culvert_material())
	_cache[key] = mesh
	return mesh


static func _pipe(st: SurfaceTool, c: Vector3, r: float) -> void:
	var segs := 20
	var z0 := 0.2
	var z1 := -2.5
	var th := 0.012
	for s in segs:
		# Angle from the bottom (u 0.5 there: the shader rusts and silts the invert).
		var a0 := TAU * float(s) / segs
		var a1 := TAU * float(s + 1) / segs
		var d0 := Vector3(sin(a0), -cos(a0), 0.0)
		var d1 := Vector3(sin(a1), -cos(a1), 0.0)
		var u0 := float(s) / segs + 0.5
		var u1 := float(s + 1) / segs + 0.5
		var circ := TAU * r
		# Outside (proud of the wall), inside, the cut rim.
		_quad_uv(st, c + d0 * (r + th) + Vector3(0, 0, 0.0), c + d1 * (r + th), c + d1 * (r + th) + Vector3(0, 0, z0), c + d0 * (r + th) + Vector3(0, 0, z0),
			(d0 + d1).normalized(), 1.0, [Vector2(u0 * circ, 0.0), Vector2(u1 * circ, 0.0), Vector2(u1 * circ, z0), Vector2(u0 * circ, z0)])
		_quad_uv(st, c + d0 * r + Vector3(0, 0, z1), c + d1 * r + Vector3(0, 0, z1), c + d1 * r + Vector3(0, 0, z0), c + d0 * r + Vector3(0, 0, z0),
			-(d0 + d1).normalized(), 2.0, [Vector2(u0, z1), Vector2(u1, z1), Vector2(u1, z0), Vector2(u0, z0)], true)
		_quad_uv(st, c + d0 * r + Vector3(0, 0, z0), c + d1 * r + Vector3(0, 0, z0), c + d1 * (r + th) + Vector3(0, 0, z0), c + d0 * (r + th) + Vector3(0, 0, z0),
			Vector3(0, 0, 1), 1.0, [Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 0.01), Vector2(u0, 0.01)], true)
	# A dark cap far inside, so the bore never shows the bank's back faces.
	for s in segs:
		var a0 := TAU * float(s) / segs
		var a1 := TAU * float(s + 1) / segs
		_tri(st, c + Vector3(0, 0, z1), c + Vector3(sin(a1), -cos(a1), 0) * r + Vector3(0, 0, z1), c + Vector3(sin(a0), -cos(a0), 0) * r + Vector3(0, 0, z1), Vector3(0, 0, 1), 2.0, Vector2(0.5, z1), Vector2(0.5, z1), Vector2(0.5, z1))


## A triangle facing `n` (the winding is fixed to face it), part `part` (COLOR.a * 4).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, part: float, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		# Godot's front face is clockwise seen from the front: swap to make it so.
		var tmp := b
		b = c
		c = tmp
		var tu := ub
		ub = uc
		uc = tu
	for v: Array in [[a, ua], [b, ub], [c, uc]]:
		st.set_color(Color(1, 1, 1, part / 4.0))
		st.set_normal(n)
		st.set_uv(v[1])
		st.add_vertex(v[0])


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, part: float, uw: float, vh: float) -> void:
	# UV in metres: along a-b, up a-d.
	var ub := Vector2(a.distance_to(b), 0.0)
	_quad_uv(st, a, b, c, d, n, part, [Vector2(0, a.y), Vector2(ub.x, b.y), Vector2(ub.x, c.y), Vector2(0, d.y)])


static func _quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, part: float, uv: Array, _inner: bool = false) -> void:
	_tri(st, a, b, c, n, part, uv[0], uv[1], uv[2])
	_tri(st, a, c, d, n, part, uv[0], uv[2], uv[3])


## A box between `lo` and `hi`, faces -x, +x, -y, +y, -z, +z kept where `faces` says.
static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, faces: Array) -> void:
	var x0 := lo.x
	var x1 := hi.x
	var y0 := lo.y
	var y1 := hi.y
	var z0 := lo.z
	var z1 := hi.z
	if faces[0]:
		_quad_uv(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(-1, 0, 0), 0.0, [Vector2(z0, y0), Vector2(z1, y0), Vector2(z1, y1), Vector2(z0, y1)])
	if faces[1]:
		_quad_uv(st, Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(1, 0, 0), 0.0, [Vector2(z0, y0), Vector2(z1, y0), Vector2(z1, y1), Vector2(z0, y1)])
	if faces[2]:
		_quad_uv(st, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(0, -1, 0), 0.0, [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	if faces[3]:
		_quad_uv(st, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(0, 1, 0), 0.0, [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	if faces[4]:
		_quad_uv(st, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(0, 0, -1), 0.0, [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])
	if faces[5]:
		_quad_uv(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(0, 0, 1), 0.0, [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])
