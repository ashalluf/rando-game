class_name BackyardKit
extends RefCounted
## The things people keep in a Los Angeles back yard, built in code at real size (Backyards places
## them): a powder-coated bistro set and a teak dining set, a market umbrella, a pair of chaise
## loungers, a gas cart grill and a kettle grill (and the smoke off them at dinner time), a 12 ft
## trampoline with its safety net, pool floats, a T-post washing line hung with laundry, a citrus
## tree heavy with fruit, a doghouse with its bowl, a toddler's slide and wagon, and the string
## lights over a patio.
##
## Everything opaque is ONE shader (shaders/backyard.gdshader). What a face is rides in the vertex
## colour's alpha (`code / 16`, the K_* below); the rgb is an sRGB colour or a shade. Paint comes
## from the MultiMesh instance custom (`INSTANCE_CUSTOM.rgb`, sRGB) times the vertex rgb, the
## fabric palette index from `INSTANCE_CUSTOM.a`. UV is metres (for weave, grain and stripes), UV2.x
## a part id (umbrella panel, garment, bulb), UV2.y how free the vertex is to move in the wind.
## The string lights are one merged mesh a chunk; each bulb vertex carries its bulb's centre in
## CUSTOM0 (w 1), so the shader can keep a bulb at least a pixel or so wide from the air.
## Meshes are cached (static), built once; `warm()` builds them on the loading screen.

# Vertex alpha codes (shaders/backyard.gdshader reads floor(a * 16)).
const K_FIXED := 0       # the vertex colour is the colour
const K_PAINT := 1       # vertex rgb x instance paint, satin powder coat
const K_FABRIC := 2      # outdoor fabric: the palette colour picked by INSTANCE_CUSTOM.a
const K_METAL := 3       # galvanised / aluminium, the vertex colour
const K_GLOSS := 4       # vertex rgb x instance paint, glossy (enamel, moulded plastic)
const K_BULB := 5        # a string-light bulb, lit after dark
const K_EMBER := 6       # a grill's fire showing through, lit while it cooks
const K_MAT := 7         # a trampoline's woven jump mat
const K_CLOTH := 8       # laundry: a colour per garment (UV2.x) and instance (INSTANCE_CUSTOM.a)
const K_FRUIT := 9       # citrus: the instance paint, glossy peel
const K_WOOD := 10       # timber, the vertex colour with grain along UV.x
const K_CANVAS := 11     # umbrella canvas: palette by INSTANCE_CUSTOM.a, stripes by panel (UV2.x)
const K_VINYL := 12      # a pool float: the instance paint, white bands by UV2.x parity, shiny
const K_RUBBER := 13     # tyres, caps, the grill's knobs
const K_STEEL := 14      # brushed stainless
const K_WATER := 15      # a dog's water bowl

static var _meshes := {}
static var _material: ShaderMaterial = null
static var _float_material: ShaderMaterial = null
static var _net_material: ShaderMaterial = null
static var _smoke_material: ShaderMaterial = null
static var _chain_material: ShaderMaterial = null


# --- The builder --------------------------------------------------------------------------------

class G:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cu := PackedFloat32Array()
	var idx := PackedInt32Array()
	var use_custom := false

	func vert(p: Vector3, nn: Vector3, col: Color, u: Vector2 = Vector2.ZERO, u2: Vector2 = Vector2.ZERO, cust: Vector4 = Vector4.ZERO) -> int:
		v.append(p)
		n.append(nn.normalized() if nn.length_squared() > 1e-10 else Vector3.UP)
		c.append(col)
		uv.append(u)
		uv2.append(u2)
		cu.append_array([cust.x, cust.y, cust.z, cust.w])
		return v.size() - 1

	## A triangle facing `want` (its winding is fixed to face it).
	func tri(a: int, b: int, cc: int, want: Vector3) -> void:
		var fn := (v[b] - v[a]).cross(v[cc] - v[a])
		# Godot's front faces are clockwise seen from the front: the cross product of a front
		# face's edges points away from the viewer.
		if fn.dot(want) <= 0.0:
			idx.append_array([a, b, cc])
		else:
			idx.append_array([a, cc, b])

	func quad(a: int, b: int, cc: int, d: int, want: Vector3) -> void:
		tri(a, b, cc, want)
		tri(a, cc, d, want)

	func tris() -> int:
		return idx.size() / 3

	func arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		if use_custom:
			arr[Mesh.ARRAY_CUSTOM0] = cu
		arr[Mesh.ARRAY_INDEX] = idx
		return arr

	func add_to(m: ArrayMesh, mat: Material) -> void:
		if idx.is_empty():
			return
		var flags := 0
		if use_custom:
			flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays(), [], {}, flags)
		m.surface_set_material(m.get_surface_count() - 1, mat)

	func mesh(mat: Material) -> ArrayMesh:
		var m := ArrayMesh.new()
		add_to(m, mat)
		return m


static func col(srgb: Color, code: int) -> Color:
	return Color(srgb.r, srgb.g, srgb.b, (float(code) + 0.5) / 16.0)


## A box at `xf` (its centre), `size`, flat faces, UV in metres.
static func box(g: G, xf: Transform3D, size: Vector3, cl: Color, u2: Vector2 = Vector2.ZERO) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP, size.z, size.y], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP, size.z, size.y],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK, size.x, size.z], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD, size.x, size.z],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP, size.x, size.y], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, size.x, size.y],
	]
	for f: Array in faces:
		var nn: Vector3 = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var cen := nn * Vector3(h.x, h.y, h.z)
		var ha := a * Vector3(h.x, h.y, h.z)
		var hb := b * Vector3(h.x, h.y, h.z)
		var wn := (xf.basis * nn).normalized()
		var la: float = f[3]
		var lb: float = f[4]
		var i0 := g.vert(xf * (cen - ha - hb), wn, cl, Vector2(0, 0), u2)
		var i1 := g.vert(xf * (cen + ha - hb), wn, cl, Vector2(la, 0), u2)
		var i2 := g.vert(xf * (cen + ha + hb), wn, cl, Vector2(la, lb), u2)
		var i3 := g.vert(xf * (cen - ha + hb), wn, cl, Vector2(0, lb), u2)
		g.quad(i0, i1, i2, i3, wn)


## An axis-aligned box from its foot centre.
static func block(g: G, foot: Vector3, size: Vector3, cl: Color, yaw: float = 0.0, u2: Vector2 = Vector2.ZERO) -> void:
	box(g, Transform3D(Basis(Vector3.UP, yaw), foot + Vector3(0, size.y * 0.5, 0)), size, cl, u2)


## A cylinder (or cone) from a to b, radii r0 at a and r1 at b, smooth sides, optional caps.
static func cyl(g: G, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, cl: Color, caps: bool = true, u2: Vector2 = Vector2.ZERO) -> void:
	var ax := b - a
	var L := ax.length()
	if L < 1e-5:
		return
	var d := ax / L
	var p := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var q := d.cross(p).normalized()
	var ring0: Array[int] = []
	var ring1: Array[int] = []
	var slope := (r0 - r1) / L
	for i in sides + 1:
		var t := TAU * float(i) / float(sides)
		var o := p * cos(t) + q * sin(t)
		var nn := (o + d * slope).normalized()
		ring0.append(g.vert(a + o * r0, nn, cl, Vector2(t * maxf(r0, r1), 0.0), u2))
		ring1.append(g.vert(b + o * r1, nn, cl, Vector2(t * maxf(r0, r1), L), u2))
	for i in sides:
		var mid := a.lerp(b, 0.5)
		var out := (g.v[ring0[i]] + g.v[ring1[i + 1]]) * 0.5 - mid
		g.quad(ring0[i], ring0[i + 1], ring1[i + 1], ring1[i], out)
	if caps:
		for e in 2:
			var cen := a if e == 0 else b
			var r := r0 if e == 0 else r1
			if r < 0.002:
				continue
			var wn := -d if e == 0 else d
			var ci := g.vert(cen, wn, cl, Vector2.ZERO, u2)
			var ring: Array[int] = []
			for i in sides + 1:
				var t := TAU * float(i) / float(sides)
				ring.append(g.vert(cen + (p * cos(t) + q * sin(t)) * r, wn, cl, Vector2(cos(t), sin(t)) * r, u2))
			for i in sides:
				g.tri(ci, ring[i], ring[i + 1], wn)


## A tube through `path` (smooth, no caps): bent frames, rails, rope.
static func tube(g: G, path: Array, r: float, sides: int, cl: Color, u2: Vector2 = Vector2.ZERO) -> void:
	var n := path.size()
	if n < 2:
		return
	var rings: Array = []
	var prev_p := Vector3.ZERO
	var along := 0.0
	for i in n:
		var pt: Vector3 = path[i]
		var t: Vector3
		if i == 0:
			t = (path[1] as Vector3) - pt
		elif i == n - 1:
			t = pt - (path[i - 1] as Vector3)
		else:
			t = (path[i + 1] as Vector3) - (path[i - 1] as Vector3)
		t = t.normalized()
		if i == 0:
			prev_p = t.cross(Vector3.UP if absf(t.y) < 0.95 else Vector3.RIGHT).normalized()
		else:
			along += pt.distance_to(path[i - 1])
		var p := (prev_p - t * prev_p.dot(t)).normalized()
		prev_p = p
		var q := t.cross(p).normalized()
		var ring: Array[int] = []
		for s in sides + 1:
			var a := TAU * float(s) / float(sides)
			var o := p * cos(a) + q * sin(a)
			ring.append(g.vert(pt + o * r, o, cl, Vector2(a * r, along), u2))
		rings.append(ring)
	for i in n - 1:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for s in sides:
			var out := g.n[r0[s]] + g.n[r1[s + 1]]
			g.quad(r0[s], r0[s + 1], r1[s + 1], r1[s], out)


## An ellipsoid at `c` with radii `rad` (rings x segs), UV.x the angle round it in 0..1.
static func ellipsoid(g: G, c: Vector3, rad: Vector3, rings: int, segs: int, cl: Color, u2: Vector2 = Vector2.ZERO, y0: float = -1.0, y1: float = 1.0) -> void:
	var grid: Array = []
	for j in rings + 1:
		var yy := lerpf(y0, y1, float(j) / float(rings))
		var lat := asin(clampf(yy, -1.0, 1.0))
		var row: Array[int] = []
		for i in segs + 1:
			var lon := TAU * float(i) / float(segs)
			var o := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			row.append(g.vert(c + o * rad, (o / rad).normalized(), cl, Vector2(float(i) / float(segs), float(j) / float(rings)), u2))
		grid.append(row)
	for j in rings:
		for i in segs:
			var a: int = grid[j][i]
			var b: int = grid[j][i + 1]
			var d: int = grid[j + 1][i + 1]
			var e: int = grid[j + 1][i]
			g.quad(a, b, d, e, g.n[a] + g.n[d])


## A torus round +Y at `c` (major R, minor r). UV2.x carries the segment index (white bands).
static func torus(g: G, c: Vector3, R: float, r: float, segs: int, sides: int, cl: Color, bands: int) -> void:
	var grid: Array = []
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		var dirv := Vector3(cos(a), 0.0, sin(a))
		var row: Array[int] = []
		for j in sides + 1:
			var b := TAU * float(j) / float(sides)
			var o := dirv * cos(b) + Vector3.UP * sin(b)
			var band := float(int(floor(float(i) / float(segs) * float(bands) - 0.0001)) % 2)
			row.append(g.vert(c + dirv * R + o * r, o, cl, Vector2(a * R, b * r), Vector2(band, 0.0)))
		grid.append(row)
	for i in segs:
		for j in sides:
			var a: int = grid[i][j]
			var b: int = grid[i + 1][j]
			var d: int = grid[i + 1][j + 1]
			var e: int = grid[i][j + 1]
			g.quad(a, b, d, e, g.n[a] + g.n[d])


## A flat quad grid hanging in a plane (laundry, a valance): corners p00 (top left) .. p11, nx x ny
## cells, both faces, sway weight growing downward, `wave` metres of ripple across it.
static func sheet(g: G, top_l: Vector3, top_r: Vector3, drop: Vector3, nx: int, ny: int, cl: Color, part: float, wave: float, sway: float, sag: float = 0.0) -> void:
	var across := top_r - top_l
	var nrm := across.cross(drop).normalized()
	for face in 2:
		var s := 1.0 if face == 0 else -1.0
		var grid: Array = []
		for j in ny + 1:
			var tv := float(j) / float(ny)
			var row: Array[int] = []
			for i in nx + 1:
				var tu := float(i) / float(nx)
				var p := top_l + across * tu + drop * tv
				p += nrm * (sin(tu * PI * 2.0 + tv * 1.7) * wave * tv)
				p += Vector3.DOWN * (sin(tu * PI) * sag)
				var shade := 1.0 if face == 0 else 0.88
				row.append(g.vert(p + nrm * s * 0.002, nrm * s, Color(cl.r * shade, cl.g * shade, cl.b * shade, cl.a),
					Vector2(tu * across.length(), tv * drop.length()), Vector2(part, sway * tv)))
			grid.append(row)
		for j in ny:
			for i in nx:
				g.quad(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i], nrm * s)


# --- Materials -------------------------------------------------------------------------------------

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/backyard.gdshader")
	return _material


## The floats bob on the water (the same shader, `bob` on).
static func float_material() -> ShaderMaterial:
	if _float_material == null:
		_float_material = ShaderMaterial.new()
		_float_material.shader = load("res://shaders/backyard.gdshader")
		_float_material.set_shader_parameter("bob", 1.0)
	return _float_material


static func net_material() -> ShaderMaterial:
	if _net_material == null:
		_net_material = ShaderMaterial.new()
		_net_material.shader = load("res://shaders/backyard_net.gdshader")
	return _net_material


## Chain-link (the dog run's panels): the net shader with a bigger, finer-wired diamond.
static func chain_material() -> ShaderMaterial:
	if _chain_material == null:
		_chain_material = ShaderMaterial.new()
		_chain_material.shader = load("res://shaders/backyard_net.gdshader")
		_chain_material.set_shader_parameter("cell", 0.05)
		_chain_material.set_shader_parameter("thread", 0.07)
		_chain_material.set_shader_parameter("diamond", true)
	return _chain_material


static func smoke_material() -> ShaderMaterial:
	if _smoke_material == null:
		_smoke_material = ShaderMaterial.new()
		_smoke_material.shader = load("res://shaders/backyard_smoke.gdshader")
		_smoke_material.set_shader_parameter("puff", WeaponFX.puff_texture())
	return _smoke_material


static func _cached(key: String, maker: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = maker.call()
	return _meshes[key]


## Every mesh, built now (the loading screen); returns the materials to draw once.
static func warm() -> Array:
	for k: String in ["dining_metal", "dining_teak", "umbrella", "loungers", "grill_gas", "grill_kettle", "smoke",
			"trampoline", "float_ring", "float_mat", "float_ball", "laundry", "citrus", "citrus_leaves",
			"doghouse", "dog_run", "toys", "umbrella_lod", "trampoline_lod", "post"]:
		get_mesh(k)
	return [material(), float_material(), net_material(), chain_material(), smoke_material()]


static func get_mesh(kind: String) -> Mesh:
	match kind:
		"dining_metal": return _cached(kind, _dining_metal)
		"dining_teak": return _cached(kind, _dining_teak)
		"umbrella": return _cached(kind, _umbrella.bind(false))
		"umbrella_lod": return _cached(kind, _umbrella.bind(true))
		"loungers": return _cached(kind, _loungers)
		"grill_gas": return _cached(kind, _grill_gas)
		"grill_kettle": return _cached(kind, _grill_kettle)
		"smoke": return _cached(kind, _smoke)
		"trampoline": return _cached(kind, _trampoline.bind(false))
		"trampoline_lod": return _cached(kind, _trampoline.bind(true))
		"float_ring": return _cached(kind, _float_ring)
		"float_mat": return _cached(kind, _float_mat)
		"float_ball": return _cached(kind, _float_ball)
		"laundry": return _cached(kind, _laundry)
		"citrus": return _cached(kind, _citrus.bind(false))
		"citrus_leaves": return _cached(kind, _citrus.bind(true))
		"doghouse": return _cached(kind, _doghouse)
		"toys": return _cached(kind, _toys)
		"dog_run": return _cached(kind, _dog_run)
		"post": return _cached(kind, _post)
	push_error("BackyardKit: no mesh %s" % kind)
	return null


# --- Patio furniture -------------------------------------------------------------------------------

## A bent-tube chair (aluminium, powder coated) with sling seat and back: its front edge toward -Z
## at the origin's -0.25; `seat` the seat's height.
static func _sling_chair(g: G, xf: Transform3D) -> void:
	var paint := col(Color.WHITE, K_PAINT)
	var fab := col(Color.WHITE, K_FABRIC)
	var w := 0.5
	var r := 0.0125
	var seat := 0.44
	for s: float in [-1.0, 1.0]:
		var x := s * w * 0.5
		# Each side frame: front leg up, the arm back, the rear leg down, the back post up.
		tube(g, [xf * Vector3(x, 0.0, -0.24), xf * Vector3(x, 0.62, -0.25), xf * Vector3(x, 0.66, -0.18),
			xf * Vector3(x, 0.66, 0.2), xf * Vector3(x, 0.0, 0.26)], r, 6, paint)
		tube(g, [xf * Vector3(x, seat - 0.04, -0.22), xf * Vector3(x, seat - 0.06, 0.2), xf * Vector3(x, 0.98, 0.34)], r, 6, paint)
	# Cross rails.
	tube(g, [xf * Vector3(-w * 0.5, seat - 0.04, -0.22), xf * Vector3(w * 0.5, seat - 0.04, -0.22)], r, 6, paint)
	tube(g, [xf * Vector3(-w * 0.5, 0.98, 0.34), xf * Vector3(w * 0.5, 0.98, 0.34)], r, 6, paint)
	tube(g, [xf * Vector3(-w * 0.5, 0.12, 0.24), xf * Vector3(w * 0.5, 0.12, 0.24)], r * 0.8, 6, paint)
	# The slings: sagging cloth between the rails.
	var nx := 4
	for part in 2:
		var rows: Array = []
		var ny := 4
		for j in ny + 1:
			var t := float(j) / float(ny)
			var row: Array[int] = []
			for i in nx + 1:
				var u := float(i) / float(nx)
				var x := lerpf(-w * 0.5 + 0.015, w * 0.5 - 0.015, u)
				var sag := sin(u * PI) * 0.035 * sin(t * PI)
				var p: Vector3
				var nn: Vector3
				if part == 0:
					p = Vector3(x, lerpf(seat - 0.03, seat - 0.05, t) - sag, lerpf(-0.21, 0.19, t))
					nn = Vector3.UP
				else:
					p = Vector3(x, lerpf(seat + 0.02, 0.95, t), lerpf(0.21, 0.33, t)) + Vector3(0.0, 0.0, sag)
					nn = Vector3(0.0, 0.25, -1.0)
				row.append(g.vert(xf * p, xf.basis * nn, fab, Vector2(x, t * 0.45)))
			rows.append(row)
		for j in ny:
			for i in nx:
				var want := xf.basis * (Vector3.UP if part == 0 else Vector3(0, 0.25, -1))
				g.quad(rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i], want)
				g.quad(rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i], -want)


## A round powder-coated bistro table (1.07 m, an umbrella hole) and four sling chairs.
static func _dining_metal() -> Mesh:
	var g := G.new()
	var paint := col(Color.WHITE, K_PAINT)
	var top := 0.73
	# The top: a pressed-steel disc with a rolled rim, a ring of slots read in the shader as a
	# darker band (the vertex shade), the hole in the middle.
	var R := 0.535
	cyl(g, Vector3(0, top - 0.025, 0), Vector3(0, top, 0), R, R, 28, paint, false)
	var rings := [0.03, 0.12, 0.22, 0.33, 0.42, 0.5, R]
	for k in rings.size() - 1:
		var shade := 0.82 if k % 2 == 1 else 1.0
		var c2 := col(Color(shade, shade, shade), K_PAINT)
		var a0: float = rings[k]
		var a1: float = rings[k + 1]
		var ring_a: Array[int] = []
		var ring_b: Array[int] = []
		for i in 29:
			var t := TAU * float(i) / 28.0
			var o := Vector3(cos(t), 0, sin(t))
			ring_a.append(g.vert(o * a0 + Vector3(0, top, 0), Vector3.UP, c2, Vector2(o.x, o.z) * a0))
			ring_b.append(g.vert(o * a1 + Vector3(0, top, 0), Vector3.UP, c2, Vector2(o.x, o.z) * a1))
		for i in 28:
			g.quad(ring_a[i], ring_a[i + 1], ring_b[i + 1], ring_b[i], Vector3.UP)
	# The underside.
	var ub: Array[int] = []
	var cu := g.vert(Vector3(0, top - 0.025, 0), Vector3.DOWN, paint)
	for i in 29:
		var t := TAU * float(i) / 28.0
		ub.append(g.vert(Vector3(cos(t) * R, top - 0.025, sin(t) * R), Vector3.DOWN, paint))
	for i in 28:
		g.tri(cu, ub[i], ub[i + 1], Vector3.DOWN)
	# Four splayed legs and a ring between them.
	for k in 4:
		var a := TAU * (float(k) + 0.5) / 4.0
		var o := Vector3(cos(a), 0, sin(a))
		tube(g, [o * 0.42 + Vector3(0, top - 0.02, 0), o * 0.46 + Vector3(0, top - 0.25, 0), o * 0.5 + Vector3(0, 0.0, 0)], 0.014, 6, paint)
	var ring: Array = []
	for i in 17:
		var t := TAU * float(i) / 16.0
		ring.append(Vector3(cos(t) * 0.475, 0.2, sin(t) * 0.475))
	tube(g, ring, 0.008, 5, paint)
	# Four chairs round it, not quite square to it.
	var turns := [0.05, -0.08, 0.12, -0.03]
	var dists := [0.78, 0.84, 0.76, 0.9]
	for k in 4:
		var a := TAU * float(k) / 4.0 + float(turns[k]) * 0.4
		var d: float = dists[k]
		var o := Vector3(sin(a), 0, cos(a))
		var xf := Transform3D(Basis(Vector3.UP, a + float(turns[k])), o * d)
		_sling_chair(g, xf)
	return g.mesh(material())


## A teak slatted table (1.8 x 0.9) with six slatted armchairs.
static func _dining_teak() -> Mesh:
	var g := G.new()
	var teak := col(Color(0.58, 0.40, 0.25), K_WOOD)
	var dark := col(Color(0.47, 0.32, 0.2), K_WOOD)
	var top := 0.74
	# Slats along the length, gaps between.
	var n := 11
	for i in n:
		var z := lerpf(-0.43, 0.43, float(i) / float(n - 1))
		block(g, Vector3(0, top - 0.03, z), Vector3(1.8, 0.03, 0.07), teak)
	# Breadboard ends, apron, legs.
	for s: float in [-1.0, 1.0]:
		block(g, Vector3(s * 0.88, top - 0.03, 0), Vector3(0.06, 0.03, 0.92), dark)
		block(g, Vector3(0, top - 0.13, s * 0.4), Vector3(1.62, 0.1, 0.025), dark)
		block(g, Vector3(s * 0.8, top - 0.13, 0), Vector3(0.025, 0.1, 0.76), dark)
		for t: float in [-1.0, 1.0]:
			block(g, Vector3(s * 0.81, 0.0, t * 0.39), Vector3(0.06, top - 0.03, 0.06), teak)
	# Chairs: two each side, one at each end.
	var seats := [[Vector3(-0.45, 0, -0.78), 0.0], [Vector3(0.45, 0, -0.8), 0.04], [Vector3(-0.42, 0, 0.8), PI + 0.03],
		[Vector3(0.48, 0, 0.77), PI - 0.05], [Vector3(-1.3, 0, 0.02), PI * 0.5], [Vector3(1.32, 0, -0.03), -PI * 0.5 + 0.06]]
	for s: Array in seats:
		_teak_chair(g, Transform3D(Basis(Vector3.UP, float(s[1])), s[0]), teak, dark)
	block(g, Vector3(0, top - 0.03, 0), Vector3(0.06, 0.031, 0.06), col(Color(0.1, 0.1, 0.1), K_FIXED))
	return g.mesh(material())


## A slatted teak armchair facing +Z (toward the table) from the origin.
static func _teak_chair(g: G, xf: Transform3D, teak: Color, dark: Color) -> void:
	var seat := 0.44
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var h := seat if sz > 0.0 else 0.9
			box(g, xf * Transform3D(Basis(), Vector3(sx * 0.27, h * 0.5, sz * 0.22)), Vector3(0.045, h, 0.045), teak)
		# The arm.
		box(g, xf * Transform3D(Basis(), Vector3(sx * 0.27, 0.66, 0.0)), Vector3(0.06, 0.025, 0.52), dark)
		box(g, xf * Transform3D(Basis(), Vector3(sx * 0.27, 0.55, 0.22)), Vector3(0.04, 0.22, 0.04), teak)
	for i in 5:
		var z := lerpf(-0.19, 0.2, float(i) / 4.0)
		box(g, xf * Transform3D(Basis(), Vector3(0, seat, z)), Vector3(0.52, 0.022, 0.06), teak)
	var tilt := Basis(Vector3.RIGHT, 0.17)
	for i in 4:
		var y := lerpf(0.56, 0.86, float(i) / 3.0)
		box(g, xf * Transform3D(tilt, Vector3(0, y, -0.24 - (y - 0.5) * 0.17)), Vector3(0.52, 0.06, 0.02), teak)
	box(g, xf * Transform3D(Basis(), Vector3(0, 0.18, 0.0)), Vector3(0.52, 0.03, 0.025), dark)


## A 2.7 m market umbrella: eight ribs, a taut canvas panel between each pair with a scalloped
## valance, a finial, the pole, a weighted base. Canvas is K_CANVAS (palette from the instance,
## stripes by panel), its underside a little darker. `lod`: a low cone and a stick (LOD chunks).
static func _umbrella(lod: bool) -> Mesh:
	var g := G.new()
	var pole := col(Color(0.82, 0.8, 0.76), K_METAL)
	var R := 1.36
	var apex := 2.42
	var rim := 2.02
	var ribs := 8
	if lod:
		var ci := g.vert(Vector3(0, apex, 0), Vector3.UP, col(Color.WHITE, K_CANVAS))
		var ring: Array[int] = []
		for i in ribs + 1:
			var t := TAU * float(i) / float(ribs)
			var o := Vector3(cos(t), 0, sin(t))
			ring.append(g.vert(o * R + Vector3(0, rim, 0), (o * 0.3 + Vector3.UP).normalized(), col(Color.WHITE, K_CANVAS), Vector2.ZERO, Vector2(float(i % ribs), 0)))
		for i in ribs:
			g.tri(ci, ring[i], ring[i + 1], Vector3.UP)
		cyl(g, Vector3(0, 0, 0), Vector3(0, apex, 0), 0.03, 0.03, 4, pole, false)
		return g.mesh(material())
	cyl(g, Vector3(0, 0.0, 0), Vector3(0, apex + 0.08, 0), 0.019, 0.019, 10, pole, false)
	# The base: a cast disc.
	cyl(g, Vector3(0, 0.0, 0), Vector3(0, 0.07, 0), 0.26, 0.2, 18, col(Color(0.16, 0.16, 0.17), K_PAINT), true)
	# Hub, crank, finial.
	cyl(g, Vector3(0, apex - 0.08, 0), Vector3(0, apex + 0.02, 0), 0.04, 0.035, 10, pole)
	cyl(g, Vector3(0, 1.25, 0), Vector3(0, 1.38, 0), 0.03, 0.03, 8, pole)
	ellipsoid(g, Vector3(0, apex + 0.12, 0), Vector3(0.05, 0.07, 0.05), 4, 8, col(Color(0.5, 0.36, 0.22), K_WOOD))
	var canvas := col(Color.WHITE, K_CANVAS)
	var under := col(Color(0.72, 0.72, 0.72), K_CANVAS)
	var nr := 5
	var na := 4
	for k in ribs:
		var a0 := TAU * float(k) / float(ribs)
		var a1 := TAU * float(k + 1) / float(ribs)
		var part := Vector2(float(k), 0.0)
		# The rib and its stretcher.
		var o0 := Vector3(cos(a0), 0, sin(a0))
		tube(g, [Vector3(0, apex - 0.02, 0), o0 * R * 0.5 + Vector3(0, lerpf(apex, rim, 0.5) + 0.015, 0), o0 * (R + 0.02) + Vector3(0, rim - 0.01, 0)], 0.008, 4, pole)
		tube(g, [Vector3(0, apex - 0.62, 0), o0 * R * 0.5 + Vector3(0, lerpf(apex, rim, 0.5) - 0.01, 0)], 0.006, 4, pole)
		# The panel: radial rows from the hub to the rim, the canvas between ribs sitting a little
		# lower (taut cloth between two ribs), each face once up, once down.
		for face in 2:
			var grid: Array = []
			for j in nr + 1:
				var t := float(j) / float(nr)
				var row: Array[int] = []
				for i in na + 1:
					var s := float(i) / float(na)
					var a := lerpf(a0, a1, s)
					var o := Vector3(cos(a), 0, sin(a))
					var dip := sin(s * PI) * 0.045 * t
					var r := R * t * lerpf(1.0, 0.985, sin(s * PI))
					var y := lerpf(apex, rim, t) - dip + 0.004 * float(face == 0)
					var nn := (o * 0.32 + Vector3.UP).normalized()
					row.append(g.vert(o * r + Vector3(0, y, 0), nn if face == 0 else -nn, canvas if face == 0 else under,
						Vector2(a * r, t * R), part))
				grid.append(row)
			for j in nr:
				for i in na:
					var want := Vector3.UP if face == 0 else Vector3.DOWN
					g.quad(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i], want)
		# The valance: a scalloped flap hanging from the rim.
		var oa := Vector3(cos(a0), 0, sin(a0)) * R + Vector3(0, rim, 0)
		var ob := Vector3(cos(a1), 0, sin(a1)) * R + Vector3(0, rim, 0)
		for face in 2:
			var nn := ((Vector3(cos(a0), 0, sin(a0)) + Vector3(cos(a1), 0, sin(a1))) * 0.5).normalized()
			if face == 1:
				nn = -nn
			var cols: Array[int] = []
			var bots: Array[int] = []
			for i in 7:
				var s := float(i) / 6.0
				var p := oa.lerp(ob, s)
				var drop := 0.11 + 0.05 * sin(s * PI)
				cols.append(g.vert(p, nn, canvas if face == 0 else under, Vector2(s * oa.distance_to(ob), 0), part))
				bots.append(g.vert(p + Vector3(0, -drop, 0), nn, canvas if face == 0 else under, Vector2(s * oa.distance_to(ob), drop), part))
			for i in 6:
				g.quad(cols[i], cols[i + 1], bots[i + 1], bots[i], nn)
	return g.mesh(material())


## Two chaise loungers side by side (feet toward -Z) with a low side table between.
static func _loungers() -> Mesh:
	var g := G.new()
	var paint := col(Color.WHITE, K_PAINT)
	var fab := col(Color.WHITE, K_FABRIC)
	var pipe := col(Color(0.62, 0.62, 0.6), K_FABRIC)
	for s: float in [-1.0, 1.0]:
		var x0 := s * 0.72
		var xf := Transform3D(Basis(Vector3.UP, s * 0.04), Vector3(x0, 0, 0))
		var w := 0.66
		var y := 0.3
		# Frame: two side rails, legs, wheels at the head end.
		for sx: float in [-1.0, 1.0]:
			var x := sx * w * 0.5
			tube(g, [xf * Vector3(x, y, -0.98), xf * Vector3(x, y, 0.9)], 0.016, 6, paint)
			for z: float in [-0.9, 0.82]:
				tube(g, [xf * Vector3(x, y, z), xf * Vector3(x, 0.0, z + 0.02)], 0.014, 6, paint)
			cyl(g, xf * Vector3(x + sx * 0.02, 0.06, 0.88), xf * Vector3(x + sx * 0.05, 0.06, 0.88), 0.06, 0.06, 10, col(Color(0.12, 0.12, 0.12), K_RUBBER))
		# The cushion: a flat pad, then the back section raised 50 degrees.
		var pad := 0.075
		box(g, xf * Transform3D(Basis(), Vector3(0, y + pad * 0.5 + 0.01, -0.28)), Vector3(w - 0.02, pad, 1.38), fab)
		var back := Basis(Vector3.RIGHT, -0.87)
		box(g, xf * Transform3D(back, Vector3(0, y + 0.31, 0.62)), Vector3(w - 0.02, pad, 0.68), fab)
		# Piping and tufts: thin darker strips across the pad.
		for z: float in [-0.76, -0.4, -0.04]:
			box(g, xf * Transform3D(Basis(), Vector3(0, y + pad + 0.012, z)), Vector3(w - 0.06, 0.004, 0.012), pipe)
		# The backrest frame and its prop.
		tube(g, [xf * Vector3(-w * 0.5, y + 0.02, 0.36), xf * Vector3(-w * 0.5, y + 0.55, 0.82), xf * Vector3(w * 0.5, y + 0.55, 0.82), xf * Vector3(w * 0.5, y + 0.02, 0.36)], 0.013, 6, paint)
	# The side table.
	block(g, Vector3(0, 0, 0.45), Vector3(0.42, 0.42, 0.42), col(Color.WHITE, K_PAINT))
	block(g, Vector3(0, 0.42, 0.45), Vector3(0.46, 0.02, 0.46), col(Color(0.9, 0.9, 0.9), K_PAINT))
	ellipsoid(g, Vector3(0.08, 0.5, 0.44), Vector3(0.04, 0.06, 0.04), 4, 8, col(Color(0.82, 0.86, 0.84), K_WATER))
	return g.mesh(material())


# --- Grills ----------------------------------------------------------------------------------------

## A gas cart grill (feet at the origin, front toward -Z): cabinet on casters, the firebox and a
## rolled hood (instance paint, enamel), stainless side shelves, knobs, a propane tank.
static func _grill_gas() -> Mesh:
	var g := G.new()
	var steel := col(Color(0.72, 0.72, 0.7), K_STEEL)
	var black := col(Color(0.09, 0.09, 0.1), K_PAINT)
	var hood := col(Color.WHITE, K_GLOSS)
	var rubber := col(Color(0.06, 0.06, 0.06), K_RUBBER)
	# Cabinet with two doors (a seam and handles), casters.
	block(g, Vector3(0, 0.1, 0), Vector3(0.66, 0.66, 0.5), black)
	block(g, Vector3(0, 0.12, -0.252), Vector3(0.6, 0.6, 0.006), steel)
	block(g, Vector3(0, 0.12, -0.256), Vector3(0.006, 0.6, 0.004), black)
	for s: float in [-1.0, 1.0]:
		cyl(g, Vector3(s * 0.05, 0.62, -0.27), Vector3(s * 0.05, 0.62, -0.27) + Vector3(0, -0.2, 0), 0.008, 0.008, 6, steel)
		for z: float in [-0.2, 0.2]:
			cyl(g, Vector3(s * 0.28 - 0.02, 0.05, z), Vector3(s * 0.28 + 0.02, 0.05, z), 0.05, 0.05, 10, rubber)
	# The control panel and knobs, the firebox.
	var panel := Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0.83, -0.27))
	box(g, panel, Vector3(0.66, 0.1, 0.02), steel)
	for i in 4:
		var x := lerpf(-0.22, 0.22, float(i) / 3.0)
		cyl(g, panel * Vector3(x, 0, -0.01), panel * Vector3(x, 0, -0.045), 0.022, 0.02, 8, rubber)
	block(g, Vector3(0, 0.76, 0.02), Vector3(0.66, 0.2, 0.46), black)
	# The hood: half a cylinder along x, end caps, a handle bar, a thermometer.
	var c := Vector3(0, 0.96, 0.02)
	var hr := 0.23
	var segs := 10
	var row0: Array[int] = []
	var row1: Array[int] = []
	for i in segs + 1:
		var a := PI * float(i) / float(segs)
		var o := Vector3(0, sin(a), -cos(a))
		row0.append(g.vert(c + Vector3(-0.33, 0, 0) + o * hr, o, hood, Vector2(a * hr, 0)))
		row1.append(g.vert(c + Vector3(0.33, 0, 0) + o * hr, o, hood, Vector2(a * hr, 0.66)))
	for i in segs:
		g.quad(row0[i], row0[i + 1], row1[i + 1], row1[i], g.n[row0[i]] + g.n[row0[i + 1]])
	for s: float in [-1.0, 1.0]:
		var ci := g.vert(c + Vector3(s * 0.33, 0, 0), Vector3(s, 0, 0), black)
		var ring: Array[int] = []
		for i in segs + 1:
			var a := PI * float(i) / float(segs)
			ring.append(g.vert(c + Vector3(s * 0.33, sin(a) * hr, -cos(a) * hr), Vector3(s, 0, 0), black))
		for i in segs:
			g.tri(ci, ring[i], ring[i + 1], Vector3(s, 0, 0))
	tube(g, [c + Vector3(-0.26, 0.12, -0.26), c + Vector3(-0.26, 0.13, -0.32), c + Vector3(0.26, 0.13, -0.32), c + Vector3(0.26, 0.12, -0.26)], 0.012, 6, steel)
	cyl(g, c + Vector3(0, 0.17, -0.16), c + Vector3(0, 0.185, -0.175), 0.03, 0.03, 10, steel)
	# A sliver of the fire under the hood's front lip.
	block(g, Vector3(0, 0.852, -0.215), Vector3(0.6, 0.012, 0.004), col(Color(1, 1, 1), K_EMBER))
	# Side shelves with their brackets; the tank under the right one.
	for s: float in [-1.0, 1.0]:
		block(g, Vector3(s * 0.5, 0.84, 0.02), Vector3(0.34, 0.02, 0.44), steel)
		tube(g, [Vector3(s * 0.33, 0.62, 0.02), Vector3(s * 0.62, 0.83, 0.02)], 0.01, 5, black)
	var tank := col(Color(0.92, 0.92, 0.9), K_GLOSS)
	cyl(g, Vector3(0.52, 0.0, 0.0), Vector3(0.52, 0.32, 0.0), 0.15, 0.15, 14, tank, false)
	ellipsoid(g, Vector3(0.52, 0.32, 0.0), Vector3(0.15, 0.07, 0.15), 3, 14, tank, Vector2.ZERO, 0.0, 1.0)
	cyl(g, Vector3(0.52, 0.38, 0.0), Vector3(0.52, 0.47, 0.0), 0.07, 0.07, 10, steel, false)
	cyl(g, Vector3(0.52, 0.42, 0.0), Vector3(0.52, 0.45, 0.0), 0.03, 0.03, 8, col(Color(0.1, 0.3, 0.65), K_GLOSS))
	return g.mesh(material())


## A 22 inch kettle grill (instance paint): the bowl, the domed lid sat on it with a glow where
## they meet when it cooks, three legs, two wheels, the ash pan, a handle and a vent.
static func _grill_kettle() -> Mesh:
	var g := G.new()
	var enamel := col(Color.WHITE, K_GLOSS)
	var steel := col(Color(0.7, 0.7, 0.68), K_METAL)
	var black := col(Color(0.1, 0.1, 0.1), K_RUBBER)
	var c := Vector3(0, 0.72, 0)
	var r := 0.29
	ellipsoid(g, c, Vector3(r, r * 0.88, r), 6, 20, enamel, Vector2.ZERO, -1.0, 0.0)
	ellipsoid(g, c + Vector3(0, 0.02, 0), Vector3(r + 0.004, r * 0.85, r + 0.004), 6, 20, enamel, Vector2.ZERO, 0.0, 1.0)
	cyl(g, c + Vector3(0, -0.004, 0), c + Vector3(0, 0.022, 0), r - 0.004, r - 0.004, 20, col(Color.WHITE, K_EMBER), false)
	tube(g, [c + Vector3(-0.08, r * 0.85 + 0.04, 0), c + Vector3(-0.08, r * 0.85 + 0.07, 0), c + Vector3(0.08, r * 0.85 + 0.07, 0), c + Vector3(0.08, r * 0.85 + 0.04, 0)], 0.012, 6, black)
	cyl(g, c + Vector3(0.1, r * 0.8, 0.08), c + Vector3(0.1, r * 0.8 + 0.03, 0.08), 0.04, 0.035, 10, steel)
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.3
		var o := Vector3(cos(a), 0, sin(a))
		tube(g, [c + o * 0.2 + Vector3(0, -0.18, 0), o * 0.3 + Vector3(0, 0.05, 0)], 0.012, 6, steel)
		if k < 2:
			cyl(g, o * 0.3 + Vector3(0, 0.08, 0) - o.cross(Vector3.UP) * 0.03, o * 0.3 + Vector3(0, 0.08, 0) + o.cross(Vector3.UP) * 0.03, 0.08, 0.08, 12, black)
	# The ash pan and the triangle rack it sits in.
	cyl(g, Vector3(0, 0.3, 0), Vector3(0, 0.36, 0), 0.15, 0.17, 14, steel, true)
	return g.mesh(material())


## The smoke off a grill: puffs (quads) the shader lifts, turns to the camera, grows and fades,
## each a different moment of one rising column, all of it shown only while the grill cooks.
static func _smoke() -> Mesh:
	var g := G.new()
	var n := 9
	for i in n:
		var a := g.vert(Vector3.ZERO, Vector3.UP, Color.WHITE, Vector2(0, 0), Vector2(float(i) / float(n), 0))
		var b := g.vert(Vector3.ZERO, Vector3.UP, Color.WHITE, Vector2(1, 0), Vector2(float(i) / float(n), 0))
		var cc := g.vert(Vector3.ZERO, Vector3.UP, Color.WHITE, Vector2(1, 1), Vector2(float(i) / float(n), 0))
		var d := g.vert(Vector3.ZERO, Vector3.UP, Color.WHITE, Vector2(0, 1), Vector2(float(i) / float(n), 0))
		g.idx.append_array([a, b, cc, a, cc, d])
	var m := g.mesh(smoke_material())
	m.custom_aabb = AABB(Vector3(-3.0, 0.0, -3.0), Vector3(6.0, 7.0, 6.0))
	return m


# --- The trampoline --------------------------------------------------------------------------------

## A 12 ft round trampoline: galvanised frame on six W legs, the black jump mat, the pad over the
## springs (instance paint), six foam-covered net poles and the enclosure net (its own surface,
## shaders/backyard_net.gdshader) with a zip door. `lod`: the mat and pad as a low disc.
static func _trampoline(lod: bool) -> Mesh:
	var g := G.new()
	var galv := col(Color(0.7, 0.71, 0.7), K_METAL)
	var mat := col(Color(0.05, 0.05, 0.055), K_MAT)
	var pad := col(Color.WHITE, K_GLOSS)
	var y := 0.88
	var R := 1.83
	var segs := 10 if lod else 40
	# The mat and the pad (an annulus, a rolled outer edge).
	var ci := g.vert(Vector3(0, y - 0.03, 0), Vector3.UP, mat, Vector2.ZERO)
	var mr: Array[int] = []
	for i in segs + 1:
		var t := TAU * float(i) / float(segs)
		mr.append(g.vert(Vector3(cos(t), 0, sin(t)) * 1.55 + Vector3(0, y - 0.01, 0), Vector3.UP, mat, Vector2(cos(t), sin(t)) * 1.55))
	for i in segs:
		g.tri(ci, mr[i], mr[i + 1], Vector3.UP)
	var pr_in: Array[int] = []
	var pr_out: Array[int] = []
	var pr_low: Array[int] = []
	for i in segs + 1:
		var t := TAU * float(i) / float(segs)
		var o := Vector3(cos(t), 0, sin(t))
		pr_in.append(g.vert(o * 1.53 + Vector3(0, y + 0.02, 0), Vector3.UP, pad, Vector2(t * 1.5, 0)))
		pr_out.append(g.vert(o * 1.9 + Vector3(0, y + 0.03, 0), (Vector3.UP + o * 0.4).normalized(), pad, Vector2(t * 1.9, 0.37)))
		pr_low.append(g.vert(o * 1.93 + Vector3(0, y - 0.1, 0), o, pad, Vector2(t * 1.9, 0.5)))
	for i in segs:
		g.quad(pr_in[i], pr_in[i + 1], pr_out[i + 1], pr_out[i], Vector3.UP)
		g.quad(pr_out[i], pr_out[i + 1], pr_low[i + 1], pr_low[i], Vector3(cos(TAU * (float(i) + 0.5) / float(segs)), 0, sin(TAU * (float(i) + 0.5) / float(segs))))
	if lod:
		return g.mesh(material())
	# The frame ring, the legs, the net poles.
	var ring: Array = []
	for i in 41:
		var t := TAU * float(i) / 40.0
		ring.append(Vector3(cos(t) * R, y - 0.12, sin(t) * R))
	tube(g, ring, 0.024, 8, galv)
	for k in 6:
		var a := TAU * float(k) / 6.0
		var o := Vector3(cos(a), 0, sin(a))
		var side := o.cross(Vector3.UP)
		tube(g, [o * R + side * 0.22 + Vector3(0, y - 0.12, 0), o * (R + 0.02) + side * 0.24 + Vector3(0, 0.0, 0)], 0.02, 6, galv)
		tube(g, [o * R - side * 0.22 + Vector3(0, y - 0.12, 0), o * (R + 0.02) - side * 0.24 + Vector3(0, 0.0, 0)], 0.02, 6, galv)
		tube(g, [o * (R + 0.02) + side * 0.26 + Vector3(0, 0.02, 0), o * (R + 0.02) - side * 0.26 + Vector3(0, 0.02, 0)], 0.02, 6, galv)
		var foam := col(Color(0.08, 0.08, 0.09), K_RUBBER)
		var b := TAU * (float(k) + 0.5) / 6.0
		var ob := Vector3(cos(b), 0, sin(b))
		tube(g, [ob * 1.86 + Vector3(0, y - 0.1, 0), ob * 1.86 + Vector3(0, y + 0.9, 0), ob * 1.8 + Vector3(0, y + 1.6, 0), ob * 1.7 + Vector3(0, y + 1.82, 0)], 0.028, 8, foam)
	# The top rope and the net.
	var top: Array = []
	for i in 49:
		var t := TAU * float(i) / 48.0
		var sag := 0.06 * absf(sin(t * 3.0))
		top.append(Vector3(cos(t) * 1.72, y + 1.82 - sag, sin(t) * 1.72))
	tube(g, top, 0.008, 4, col(Color(0.1, 0.1, 0.1), K_RUBBER))
	var mesh := g.mesh(material())
	var nt := G.new()
	var ny := 3
	var door := 0.36
	for face in 2:
		var grid: Array = []
		for j in ny + 1:
			var tv := float(j) / float(ny)
			var row: Array[int] = []
			for i in 49:
				var t := TAU * float(i) / 48.0 + door
				var sag := 0.06 * absf(sin((t - door) * 3.0)) * tv
				var rr := lerpf(1.84, 1.72, tv * tv)
				var o := Vector3(cos(t), 0, sin(t))
				var p := o * rr + Vector3(0, lerpf(y + 0.02, y + 1.82, tv) - sag, 0)
				var nn := -o if face == 0 else o
				row.append(nt.vert(p, nn, Color(0.06, 0.06, 0.065, 1.0), Vector2((t - door) * rr, p.y - y), Vector2(0, tv)))
			grid.append(row)
		for j in ny:
			for i in 48:
				var o := Vector3(cos(TAU * (float(i) + 0.5) / 48.0 + door), 0, sin(TAU * (float(i) + 0.5) / 48.0 + door))
				nt.quad(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i], -o if face == 0 else o)
	nt.add_to(mesh, net_material())
	return mesh


# --- Pool floats -----------------------------------------------------------------------------------

## A swim ring (instance paint with white bands), floating: its middle at the water line.
static func _float_ring() -> Mesh:
	var g := G.new()
	torus(g, Vector3(0, 0.05, 0), 0.43, 0.16, 28, 12, col(Color.WHITE, K_VINYL), 8)
	# The valve.
	cyl(g, Vector3(0.43, 0.2, 0), Vector3(0.43, 0.23, 0), 0.02, 0.018, 8, col(Color(0.95, 0.95, 0.93), K_GLOSS))
	return g.mesh(float_material())


## An air mattress: six tubes lengthwise (instance paint, every other in white), a pillow tube.
static func _float_mat() -> Mesh:
	var g := G.new()
	var vinyl := col(Color.WHITE, K_VINYL)
	var n := 6
	var w := 0.72
	var L := 1.55
	for i in n:
		var x := lerpf(-w * 0.5 + w / float(n) * 0.5, w * 0.5 - w / float(n) * 0.5, float(i) / float(n - 1))
		var r := w / float(n) * 0.56
		var c := Vector3(x, 0.05, -0.12)
		var u2 := Vector2(float(i % 2), 0)
		# A sausage: a cylinder with rounded ends.
		var grid: Array = []
		var ring_n := 10
		var len_n := 8
		for j in len_n + 1:
			var t := float(j) / float(len_n)
			var z := lerpf(-L * 0.5, L * 0.5, t)
			var end := 1.0 - pow(absf(t * 2.0 - 1.0), 6.0)
			var row: Array[int] = []
			for k in ring_n + 1:
				var a := TAU * float(k) / float(ring_n)
				var o := Vector3(cos(a), sin(a) * 0.75, 0.0)
				var p := c + Vector3(o.x * r * (0.6 + 0.4 * end), o.y * r * (0.5 + 0.5 * end), z)
				var nn := (o + Vector3(0, 0, (t * 2.0 - 1.0) * (1.0 - end) * 2.0)).normalized()
				var vtx := g.vert(p, nn, vinyl, Vector2(a * r, z), u2)
				g.uv2[vtx] = u2
				row.append(vtx)
			grid.append(row)
		for j in len_n:
			for k in ring_n:
				g.quad(grid[j][k], grid[j][k + 1], grid[j + 1][k + 1], grid[j + 1][k], g.n[grid[j][k]] + g.n[grid[j + 1][k + 1]])
	# The pillow across the head end.
	tube(g, [Vector3(-w * 0.48, 0.1, L * 0.5 - 0.02), Vector3(0, 0.12, L * 0.5 - 0.01), Vector3(w * 0.48, 0.1, L * 0.5 - 0.02)], 0.09, 10, col(Color(0.96, 0.96, 0.94), K_GLOSS))
	return g.mesh(float_material())


## A beach ball: six gores in the classic colours, white caps.
static func _float_ball() -> Mesh:
	var g := G.new()
	var gores := [Color(0.85, 0.12, 0.1), Color(0.97, 0.97, 0.95), Color(0.12, 0.35, 0.78), Color(0.97, 0.8, 0.12), Color(0.97, 0.97, 0.95), Color(0.16, 0.6, 0.3)]
	var r := 0.24
	var rings := 8
	var per := 3
	for k in 6:
		var gc := col(gores[k], K_GLOSS)
		var grid: Array = []
		for j in rings + 1:
			var lat := lerpf(-PI * 0.5, PI * 0.5, float(j) / float(rings))
			var row: Array[int] = []
			for i in per + 1:
				var lon := TAU * (float(k) + float(i) / float(per)) / 6.0
				var o := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
				var cap := absf(sin(lat)) > 0.93
				row.append(g.vert(o * r + Vector3(0, r * 0.75, 0), o, col(Color(0.97, 0.97, 0.95), K_GLOSS) if cap else gc))
			grid.append(row)
		for j in rings:
			for i in per:
				g.quad(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i], g.n[grid[j][i]] + g.n[grid[j + 1][i + 1]])
	return g.mesh(float_material())


# --- Laundry ---------------------------------------------------------------------------------------

## A T-post washing line, 3.6 m between the posts along x, three lines, hung with the week's wash:
## sheets, towels, shirts, jeans, a dress, a row of small things. Each garment's colour is the
## shader's (K_CLOTH: UV2.x the garment, INSTANCE_CUSTOM.a the household).
static func _laundry() -> Mesh:
	var g := G.new()
	var galv := col(Color(0.64, 0.65, 0.63), K_METAL)
	var L := 3.6
	var H := 1.95
	var arm := 0.45
	for s: float in [-1.0, 1.0]:
		var x := s * L * 0.5
		cyl(g, Vector3(x, 0, 0), Vector3(x, H + 0.04, 0), 0.03, 0.03, 8, galv, true)
		cyl(g, Vector3(x, H, -arm), Vector3(x, H, arm), 0.022, 0.022, 8, galv, true)
		cyl(g, Vector3(x, 0, 0), Vector3(x, 0.04, 0), 0.09, 0.09, 10, col(Color(0.6, 0.6, 0.58), K_FIXED))
	var line_col := col(Color(0.9, 0.9, 0.88), K_FIXED)
	var lines := [-0.36, 0.0, 0.36]
	for z: float in lines:
		var pts: Array = []
		for i in 13:
			var t := float(i) / 12.0
			pts.append(Vector3(lerpf(-L * 0.5, L * 0.5, t), H + 0.02 - sin(t * PI) * 0.1, z))
		tube(g, pts, 0.003, 3, line_col)
	var cloth := col(Color.WHITE, K_CLOTH)
	var part := 0
	# Each line: a list of [kind, width, drop].
	var rows := [
		[["sheet", 1.5, 1.05], ["towel", 0.62, 0.55], ["towel", 0.55, 0.5], ["socks", 0.5, 0.2]],
		[["shirt", 0.55, 0.62], ["jeans", 0.45, 0.95], ["shirt", 0.5, 0.58], ["dress", 0.5, 0.9], ["towel", 0.5, 0.45]],
		[["towel", 0.75, 0.6], ["shirt", 0.52, 0.6], ["shirt", 0.5, 0.56], ["jeans", 0.42, 0.92]],
	]
	for li in 3:
		var z: float = lines[li]
		var x := -L * 0.5 + 0.18
		for item: Array in rows[li]:
			var w: float = item[1]
			var drop: float = item[2]
			if x + w > L * 0.5 - 0.15:
				break
			var t0 := (x + L * 0.5) / L
			var t1 := (x + w + L * 0.5) / L
			var y0 := H + 0.02 - sin(t0 * PI) * 0.1
			var y1 := H + 0.02 - sin(t1 * PI) * 0.1
			var tl := Vector3(x, y0, z)
			var tr := Vector3(x + w, y1, z)
			match String(item[0]):
				"shirt":
					# Body and short sleeves out to the sides, hung by the hem (upside down, as
					# you hang a T-shirt) - a cut silhouette from three sheets.
					sheet(g, tl + Vector3(0.08, 0, 0), tr - Vector3(0.08, 0, 0), Vector3(0, -drop, 0), 3, 4, cloth, float(part), 0.02, 1.0)
					sheet(g, tl + Vector3(0.0, -drop + 0.2, 0.002), tl + Vector3(0.08, -drop + 0.2, 0.002), Vector3(-0.04, -0.18, 0), 1, 1, cloth, float(part), 0.0, 1.0)
					sheet(g, tr + Vector3(-0.08, -drop + 0.2, 0.002), tr + Vector3(0.0, -drop + 0.2, 0.002), Vector3(0.04, -0.18, 0), 1, 1, cloth, float(part), 0.0, 1.0)
				"jeans":
					# Two legs hung by the cuffs, joined at the seat.
					var lw := w * 0.46
					sheet(g, tl, tl + Vector3(lw, 0, 0), Vector3(0.03, -drop * 0.7, 0), 1, 4, cloth, float(part), 0.01, 0.8)
					sheet(g, tr - Vector3(lw, 0, 0), tr, Vector3(-0.03, -drop * 0.7, 0), 1, 4, cloth, float(part), 0.01, 0.8)
					sheet(g, tl + Vector3(0.03, -drop * 0.7, 0), tr + Vector3(-0.03, -drop * 0.7, 0), Vector3(0, -drop * 0.3, 0), 2, 1, cloth, float(part), 0.0, 1.0)
				"socks":
					var n := 4
					for k in n:
						var sx := x + w * (float(k) + 0.1) / float(n)
						var syp := H + 0.02 - sin(((sx + L * 0.5) / L) * PI) * 0.1
						sheet(g, Vector3(sx, syp, z), Vector3(sx + 0.08, syp, z), Vector3(0, -drop, 0), 1, 2, cloth, float(part + k), 0.01, 0.6)
					part += n - 1
				_:
					sheet(g, tl, tr, Vector3(0, -drop, 0), maxi(2, int(w / 0.25)), maxi(2, int(drop / 0.25)), cloth, float(part), 0.03, 1.0)
			# Pegs.
			for px: float in [x + 0.03, x + w - 0.03]:
				var tp := (px + L * 0.5) / L
				block(g, Vector3(px, H + 0.0 - sin(tp * PI) * 0.1, z), Vector3(0.012, 0.07, 0.014), col(Color(0.82, 0.7, 0.5), K_WOOD))
			x += w + 0.1
			part += 1
	return g.mesh(material())


# --- The citrus tree -------------------------------------------------------------------------------

## A backyard citrus (an orange, a lemon: the fruit's colour is the instance paint): a short grey
## trunk forking low, a dense round crown. `leaves`: the crown, leaf cards cut from the climbing
## plants' atlas (its glossy jasmine sprigs and masses) on their own shader; else the trunk, the
## limbs and the fruit on the backyard shader.
static func _citrus(leaves: bool) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var c := Vector3(0, 1.75, 0)
	var rad := Vector3(1.25, 1.0, 1.25)
	if leaves:
		var acc := ClimbingPlants.Acc.new()
		acc.fade = 160.0
		# Inner masses for body, then sprigs over the surface for the silhouette.
		for i in 70:
			var o := _rand_dir(rng)
			o.y = o.y * 0.9
			var p := c + o * rad * rng.randf_range(0.35, 0.72)
			var ay := (o + Vector3.UP * 0.4).normalized()
			var ax := ay.cross(o if absf(o.dot(ay)) < 0.95 else Vector3.RIGHT).normalized()
			ClimbingPlants._card_into(acc, p, ax, ay, o, 1.0, 1.0, ClimbingPlants.C_JASMINE_MASS, _leaf_tint(rng, 0.78), 0.1, 0.3, 0.0, 0.0)
		for i in 420:
			var o := _rand_dir(rng)
			if o.y < -0.55:
				o.y = -0.55 + rng.randf() * 0.2
				o = o.normalized()
			var p := c + o * rad * rng.randf_range(0.82, 1.04)
			var ay := (o * 0.6 + Vector3(rng.randf_range(-0.4, 0.4), 0.5, rng.randf_range(-0.4, 0.4))).normalized()
			var ax := ay.cross(o).normalized()
			if ax.length_squared() < 0.01:
				ax = Vector3.RIGHT
			var s := rng.randf_range(0.42, 0.62)
			var cell: int = ClimbingPlants.C_JASMINE[rng.randi() % 2]
			ClimbingPlants._card_into(acc, p, ax, ay, o, s, s * 1.1, cell, _leaf_tint(rng, lerpf(0.72, 1.05, o.y * 0.5 + 0.5)), 0.2, 0.6, 0.0, 0.05)
		return acc.mesh(ClimbingPlants.material())
	var g := G.new()
	var bark := col(Color(0.38, 0.35, 0.3), K_WOOD)
	tube(g, [Vector3(0, -0.05, 0), Vector3(0.02, 0.45, 0.01), Vector3(0.0, 0.8, 0.03)], 0.075, 8, bark)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		var o := Vector3(cos(a), 0, sin(a))
		tube(g, [Vector3(0.0, 0.75, 0.03), o * 0.3 + Vector3(0, 1.2, 0), o * 0.6 + Vector3(0, 1.75, 0)], 0.045, 6, bark)
	var fruit := col(Color.WHITE, K_FRUIT)
	for i in 46:
		var o := _rand_dir(rng)
		if o.y > 0.75:
			continue
		var p := c + o * rad * rng.randf_range(0.86, 1.0)
		var r := rng.randf_range(0.04, 0.05)
		ellipsoid(g, p, Vector3(r, r * 1.05, r), 3, 6, fruit)
	return g.mesh(material())


static func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var s := sqrt(1.0 - z * z)
	return Vector3(s * cos(a), z, s * sin(a))


static func _leaf_tint(rng: RandomNumberGenerator, sun: float) -> Color:
	# Citrus leaves: darker and bluer than jasmine's.
	var k := rng.randf_range(0.82, 1.08) * sun
	return Color(0.82 * k, 0.9 * k, 0.86 * k)


# --- The dog, the toys, the posts -------------------------------------------------------------------

## A timber doghouse (instance paint on the boards, a shingled gable roof, a dark arched door)
## facing -Z, and a steel bowl of water beside it.
static func _doghouse() -> Mesh:
	var g := G.new()
	var paint := col(Color.WHITE, K_PAINT)
	var trim := col(Color(0.92, 0.91, 0.88), K_PAINT)
	var roof := col(Color(0.24, 0.22, 0.21), K_FIXED)
	var w := 0.86
	var d := 1.06
	var h := 0.62
	# Floor on runners, walls as boards (alternating shade), the dark door.
	block(g, Vector3(0, 0, 0), Vector3(w + 0.04, 0.06, d + 0.04), col(Color(0.4, 0.33, 0.25), K_WOOD))
	var boards := 7
	for i in boards:
		var y := 0.06 + h * float(i) / float(boards)
		var shade := 1.0 if i % 2 == 0 else 0.9
		block(g, Vector3(0, y, 0), Vector3(w, h / float(boards) - 0.004, d), col(Color(shade, shade, shade), K_PAINT))
	# The gable ends and the roof.
	for s: float in [-1.0, 1.0]:
		var z := s * d * 0.5
		var a := g.vert(Vector3(-w * 0.5, 0.06 + h, z), Vector3(0, 0, s), paint)
		var b := g.vert(Vector3(w * 0.5, 0.06 + h, z), Vector3(0, 0, s), paint)
		var top := g.vert(Vector3(0, 0.06 + h + 0.34, z), Vector3(0, 0, s), paint)
		g.tri(a, b, top, Vector3(0, 0, s))
	var ridge := 0.06 + h + 0.36
	for s: float in [-1.0, 1.0]:
		var slope := Basis(Vector3.BACK, s * atan2(0.36, w * 0.5))
		var ctr := Vector3(s * w * 0.27, ridge - 0.18, 0)
		box(g, Transform3D(slope, ctr), Vector3(w * 0.62, 0.03, d + 0.16), roof)
		# Shingle courses: thin steps.
		for k in 4:
			box(g, Transform3D(slope, ctr + slope * Vector3(0, 0.02, 0) + slope * Vector3(s * (-0.2 + 0.12 * float(k)), 0, 0)), Vector3(0.02, 0.012, d + 0.16), col(Color(0.18, 0.17, 0.16), K_FIXED))
	block(g, Vector3(0, ridge - 0.02, 0), Vector3(0.06, 0.04, d + 0.18), trim)
	# The door: an arched dark opening on the -Z face.
	var door := col(Color(0.02, 0.02, 0.02), K_FIXED)
	block(g, Vector3(0, 0.06, -d * 0.5 - 0.002), Vector3(0.36, 0.34, 0.004), door)
	ellipsoid(g, Vector3(0, 0.4, -d * 0.5 - 0.004), Vector3(0.18, 0.12, 0.002), 3, 10, door, Vector2.ZERO, 0.0, 1.0)
	# Trim round the door.
	block(g, Vector3(-0.2, 0.06, -d * 0.5 - 0.006), Vector3(0.04, 0.36, 0.008), trim)
	block(g, Vector3(0.2, 0.06, -d * 0.5 - 0.006), Vector3(0.04, 0.36, 0.008), trim)
	# The bowl.
	cyl(g, Vector3(0.65, 0.0, -0.4), Vector3(0.65, 0.07, -0.4), 0.11, 0.13, 14, col(Color(0.75, 0.75, 0.74), K_STEEL), false)
	cyl(g, Vector3(0.65, 0.05, -0.4), Vector3(0.65, 0.055, -0.4), 0.115, 0.115, 14, col(Color(0.5, 0.6, 0.62), K_WATER), true)
	return g.mesh(material())


## A dog run (2.4 x 3.6 m, 1.2 m high): a galvanised tube frame, chain-link panels (their own
## surface on the chain material), a gate in the front (-Z) end. The doghouse is placed in it.
static func _dog_run() -> Mesh:
	var g := G.new()
	var galv := col(Color(0.68, 0.69, 0.68), K_METAL)
	var w := 2.4
	var d := 3.6
	var h := 1.22
	var corners := [Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0, d * 0.5), Vector3(-w * 0.5, 0, d * 0.5)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var n := 2 if a.distance_to(b) > 3.0 else 1
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n))
			cyl(g, p, p + Vector3(0, h + 0.03, 0), 0.022, 0.022, 6, galv, true)
		tube(g, [a + Vector3(0, h, 0), b + Vector3(0, h, 0)], 0.017, 6, galv)
		tube(g, [a + Vector3(0, 0.08, 0), b + Vector3(0, 0.08, 0)], 0.012, 5, galv)
	# The gate's frame and latch.
	tube(g, [Vector3(-0.45, 0.08, -d * 0.5 - 0.02), Vector3(-0.45, h - 0.05, -d * 0.5 - 0.02), Vector3(0.45, h - 0.05, -d * 0.5 - 0.02), Vector3(0.45, 0.08, -d * 0.5 - 0.02)], 0.014, 5, galv)
	var mesh := g.mesh(material())
	var nt := G.new()
	var wire := Color(0.62, 0.63, 0.62, 1.0)
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var L := a.distance_to(b)
		var nn := (b - a).cross(Vector3.UP).normalized()
		var i0 := nt.vert(a + Vector3(0, 0.03, 0), nn, wire, Vector2(0, 0.03))
		var i1 := nt.vert(b + Vector3(0, 0.03, 0), nn, wire, Vector2(L, 0.03))
		var i2 := nt.vert(b + Vector3(0, h, 0), nn, wire, Vector2(L, h))
		var i3 := nt.vert(a + Vector3(0, h, 0), nn, wire, Vector2(0, h))
		nt.quad(i0, i1, i2, i3, nn)
	nt.add_to(mesh, chain_material())
	return mesh


## A toddler's moulded slide, a red wagon and a ball, left out on the lawn (no children: the crowd
## has none). Moulded plastic in its own primary colours.
static func _toys() -> Mesh:
	var g := G.new()
	var red := col(Color(0.82, 0.12, 0.1), K_GLOSS)
	var yellow := col(Color(0.96, 0.74, 0.1), K_GLOSS)
	var blue := col(Color(0.12, 0.36, 0.78), K_GLOSS)
	var green := col(Color(0.18, 0.62, 0.3), K_GLOSS)
	# The slide: steps up the back to a platform, the chute down the front (-Z).
	for s: float in [-1.0, 1.0]:
		box(g, Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(s * 0.24, 0.38, 0.38)), Vector3(0.06, 0.82, 0.12), blue)
	for i in 3:
		block(g, Vector3(0, 0.18 + 0.2 * float(i), 0.46 - 0.12 * float(i)), Vector3(0.44, 0.04, 0.16), yellow)
	block(g, Vector3(0, 0.62, 0.14), Vector3(0.5, 0.05, 0.3), yellow)
	for s: float in [-1.0, 1.0]:
		tube(g, [Vector3(s * 0.24, 0.66, 0.26), Vector3(s * 0.24, 0.92, 0.2), Vector3(s * 0.24, 0.9, 0.0)], 0.03, 8, green)
	var chute := Basis(Vector3.RIGHT, -0.62)
	box(g, Transform3D(chute, Vector3(0, 0.36, -0.42)), Vector3(0.4, 0.03, 1.12), red)
	for s: float in [-1.0, 1.0]:
		box(g, Transform3D(chute, Vector3(s * 0.21, 0.42, -0.42)), Vector3(0.03, 0.12, 1.12), red)
	# The wagon off to the side: a box on four wheels, the handle down.
	var wx := Vector3(1.05, 0, 0.1)
	block(g, wx + Vector3(0, 0.16, 0), Vector3(0.48, 0.16, 0.86), red)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			cyl(g, wx + Vector3(sx * 0.27, 0.09, sz * 0.32), wx + Vector3(sx * 0.31, 0.09, sz * 0.32), 0.09, 0.09, 12, col(Color(0.1, 0.1, 0.1), K_RUBBER))
	tube(g, [wx + Vector3(0, 0.2, -0.44), wx + Vector3(0.05, 0.05, -1.0)], 0.012, 6, col(Color(0.1, 0.1, 0.1), K_RUBBER))
	ellipsoid(g, Vector3(-0.8, 0.13, -0.7), Vector3(0.13, 0.13, 0.13), 6, 10, col(Color.WHITE, K_GLOSS))
	return g.mesh(material())


## A string-light post: a 4x4 timber post (2.9 m) with a cap and an eye hook.
static func _post() -> Mesh:
	var g := G.new()
	block(g, Vector3.ZERO, Vector3(0.09, 2.9, 0.09), col(Color(0.5, 0.4, 0.3), K_WOOD))
	block(g, Vector3(0, 2.9, 0), Vector3(0.11, 0.03, 0.11), col(Color(0.44, 0.35, 0.27), K_WOOD))
	return g.mesh(material())


# --- String lights (one merged mesh a chunk) --------------------------------------------------------

## Adds a run of string lights from `a` to `b` (world points at the anchor heights) sagging `sag`
## metres, a bulb every `pitch` metres hanging on a short drop, to `g` (use_custom on).
static func string_run(g: G, a: Vector3, b: Vector3, sag: float, pitch: float) -> void:
	var L := a.distance_to(b)
	if L < 0.5:
		return
	var n := maxi(2, int(L / 0.4))
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / float(n)
		pts.append(a.lerp(b, t) + Vector3.DOWN * (4.0 * t * (1.0 - t) * sag))
	tube(g, pts, 0.004, 3, col(Color(0.05, 0.05, 0.05), K_RUBBER))
	var nb := maxi(1, int(L / pitch))
	for k in nb:
		var t := (float(k) + 0.5) / float(nb)
		var p := a.lerp(b, t) + Vector3.DOWN * (4.0 * t * (1.0 - t) * sag)
		# The socket, then the bulb (an S14 shape: a short fat drop).
		var sock := p + Vector3.DOWN * 0.05
		cyl(g, p, sock, 0.012, 0.014, 5, col(Color(0.06, 0.06, 0.06), K_RUBBER), false)
		var bc := sock + Vector3.DOWN * 0.045
		var cu := Vector4(bc.x, bc.y, bc.z, 1.0)
		var bulb := col(Color(1.0, 0.86, 0.6), K_BULB)
		var rows := 3
		var segs := 6
		var grid: Array = []
		for j in rows + 1:
			var lat := lerpf(-PI * 0.5, PI * 0.5, float(j) / float(rows))
			var row: Array[int] = []
			for i in segs + 1:
				var lon := TAU * float(i) / float(segs)
				var o := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
				row.append(g.vert(bc + o * Vector3(0.024, 0.035, 0.024), o, bulb, Vector2.ZERO, Vector2(float(k), 0), cu))
			grid.append(row)
		for j in rows:
			for i in segs:
				g.quad(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i], g.n[grid[j][i]] + g.n[grid[j + 1][i + 1]])
