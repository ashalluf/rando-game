class_name ChinatownKit
extends RefCounted
## Chinatown's buildings, gate, plaza and lanterns (Chinatown is the where; this is the what),
## built in code at real size into ONE mesh a block on chinatown.gdshader (ChinatownGeo, surface
## "sign": every face carries its kind in the vertex alpha, K_* below).
##
## The roof is the district's signature, so it is real geometry: `sweep_roof()` is a hip roof
## whose slopes are CONCAVE (steep at the ridge, flattening toward the eave), whose eave line
## lifts and flares out toward each corner, with a painted underside (rafters and their ringed
## ends), a fascia, glazed ridge and hip caps that curl up past the corners, and on a gate or a
## hall a ridge with upturned ends and a gilded ball. Faces share their hip lines exactly, so it
## is watertight at any subdivision. `pent()` is the same idea as a single tiled slope off a wall:
## the eave over a shopfront, the coping on a parapet.
##
## A shop building (one per claimed lot) is a row of 1-4 UNITS along its frontage, each its own
## design by hash: 2-4 storeys, a SWEEP roof (the whole front under a tiled hip roof), a PENT front
## (a flat roof behind a parapet with a tiled coping, a tiled eave over the shop) or a BALCONY
## front (a red railed balcony under a tiled eave); stucco in one of the district's colours, red
## piers, shop glass with goods behind it, an enamel sign board with the shop's invented name in
## gilt letters, a blade sign with a short word stacked down it on some, lanterns hung under the
## eave, lattice-framed windows, and the shop's goods out on the pavement (produce tables, flower
## buckets, souvenir racks, potted plants, dried-goods bins, crates).
## The gate (`gate()`): two red columns on granite plinths, painted beams, the name board, a
## frieze, a long sweeping roof; two lanterns. The plaza: paving, a three-tier pagoda-roofed hall
## on a granite platform, rows of shops facing the walk, two smaller gates, a pond, lantern masts.
## Lanterns: catenary strings of silk lanterns between the street lamps across the district's
## streets (zig-zag, as the staggered lamps fall), swaying with the wind, lit at night, with
## additive pools of their light on the street.
## LOD and the far city: `lod_box`es (walls in their colour, roofs in their tile, the gate and the
## hall as boxes).

const K_PAINT := 0
const K_TILE := 1
const K_EAVE := 2
const K_RIDGE := 3
const K_GOLD := 4
const K_SILK := 5
const K_WALL := 6
const K_WINDOW := 7
const K_SHOP := 8
const K_STONE := 9
const K_SIGN := 10
const K_INK := 11
const K_PRODUCE := 12
const K_WIRE := 13
const K_LATTICE := 14
const K_WATER := 15

const KEY := "sign"
const GROUND_STOREY := 4.4
const STOREY := 3.4

const RED := Color(0.62, 0.08, 0.06)
const DEEP_RED := Color(0.45, 0.06, 0.05)
const GOLD := Color(0.86, 0.64, 0.24)
const WIRE := Color(0.06, 0.06, 0.06)
const GRANITE := Color(0.62, 0.60, 0.57)
const MEMBRANE := Color(0.30, 0.30, 0.31)
const WOOD := Color(0.46, 0.30, 0.17)
## Glazes: green, golden yellow, terracotta, blue-grey, dark green.
const TILES := [Color(0.16, 0.42, 0.26), Color(0.82, 0.60, 0.14), Color(0.56, 0.26, 0.15), Color(0.26, 0.33, 0.37), Color(0.10, 0.30, 0.20)]
## Ridge caps go with their tiles (the yellow roof gets green caps, the rest gold-yellow or their own).
const RIDGES := [Color(0.82, 0.62, 0.16), Color(0.16, 0.42, 0.26), Color(0.62, 0.30, 0.17), Color(0.30, 0.38, 0.42), Color(0.82, 0.62, 0.16)]
## Painted beam fields.
const FIELDS := [Color(0.10, 0.40, 0.36), Color(0.13, 0.27, 0.50), Color(0.16, 0.42, 0.24)]
## Stucco: cream, pale yellow, light grey, salmon, sage, white, brick red.
const WALLS := [Color(0.86, 0.80, 0.66), Color(0.88, 0.78, 0.52), Color(0.74, 0.73, 0.70), Color(0.82, 0.62, 0.52),
	Color(0.70, 0.76, 0.64), Color(0.90, 0.88, 0.84), Color(0.58, 0.32, 0.24)]
## Trim (window frames, piers on a light wall): red, green, gold-brown.
const TRIMS := [Color(0.62, 0.08, 0.06), Color(0.10, 0.36, 0.22), Color(0.55, 0.36, 0.14)]
## Sign boards: red, black, green, gold.
const BOARDS := [Color(0.58, 0.06, 0.05), Color(0.06, 0.06, 0.06), Color(0.08, 0.30, 0.18), Color(0.80, 0.62, 0.25)]
## Produce: oranges, apples, bok choy, lemons, persimmons, dragon fruit, melons.
const PRODUCE := [Color(0.95, 0.50, 0.08), Color(0.75, 0.10, 0.08), Color(0.35, 0.62, 0.22), Color(0.92, 0.82, 0.20),
	Color(0.92, 0.42, 0.06), Color(0.85, 0.18, 0.24), Color(0.40, 0.58, 0.22)]
const LANTERN_RED := Color(0.86, 0.10, 0.06)
const LANTERN_GOLD := Color(0.96, 0.62, 0.12)
## Where the strung lanterns hang from the street lamps' columns (m over the pavement).
const STRING_ATTACH := 5.6
const STRING_STEP := 1.9

static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/chinatown.gdshader")
	return _mat


static func kc(c: Color, k: int) -> Color:
	return Color(c.r, c.g, c.b, float(k) / 16.0)


static func h01(parts: Array) -> float:
	return Chinatown.h01(parts)


static func pick(arr: Array, parts: Array) -> Variant:
	return arr[int(h01(parts) * float(arr.size())) % arr.size()]


# --- Per chunk ----------------------------------------------------------------------------------

## The block's one mesh and its collision, gathered over the chunk's steps.
static func _state(ch: CityChunk) -> Dictionary:
	if ch.has_meta("ct_state"):
		return ch.get_meta("ct_state")
	var g := ChinatownGeo.new()
	g.use(KEY, material())
	var st := {"geo": g, "shapes": []}
	ch.set_meta("ct_state", st)
	return st


## A box collision shape, in the chunk's space.
static func _shape(st: Dictionary, xf: Transform3D, center: Vector3, size: Vector3) -> void:
	(st.shapes as Array).append([Transform3D(xf.basis, xf * center), size])


static func block_step(ch: CityChunk, block: Dictionary) -> void:
	var gate := Chinatown.gate(ch.plan)
	var owns_gate: bool = not gate.is_empty() and gate.block == Vector2i(ch.ix, ch.iz)
	if ch.level != CityChunk.Level.FULL:
		if owns_gate:
			_gate_far(ch, gate)
		return
	var st := _state(ch)
	var g: ChinatownGeo = st.geo
	_strings(ch, st, block)
	if owns_gate:
		var x: float = gate.x
		var z: float = gate.z
		var y := ch._gy(x, z) + CityChunk.SIDEWALK_TOP
		g.xf = Transform3D(Basis(), Vector3(x, y, z))
		var span: float = float(gate.width) + 4.4
		gate_mesh(g, st, span, 1.0, Chinatown.NAME, Chinatown.GATE_NAME, Transform3D(Basis(), Vector3(x, y, z)))
		_floods(ch, Transform3D(Basis(), Vector3(x, y, z)), span)
	commit(ch)


## Commits the block's mesh and body (once; the plaza and the lots add to it before).
static func commit(ch: CityChunk) -> void:
	if not ch.has_meta("ct_state"):
		return
	var st: Dictionary = ch.get_meta("ct_state")
	ch.remove_meta("ct_state")
	var g: ChinatownGeo = st.geo
	g.xf = Transform3D.IDENTITY
	var node := Node3D.new()
	node.name = "Chinatown"
	node.add_to_group("chinatown")
	ch.add_child(node)
	g.commit(node, "ChinatownMesh")
	if not (st.shapes as Array).is_empty():
		var body := StaticBody3D.new()
		body.name = "ChinatownBody"
		body.collision_layer = 1
		body.collision_mask = 0
		node.add_child(body)
		for s: Array in st.shapes:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = s[1]
			cs.shape = bs
			cs.transform = s[0]
			body.add_child(cs)
	ch._batch.set_no_shadow("ct_pool")


# --- Geometry helpers ---------------------------------------------------------------------------

static func box(g: ChinatownGeo, center: Vector3, size: Vector3, col: Color, basis: Basis = Basis()) -> void:
	g.box(KEY, center, size, col, basis)


## A box from a to b, `w` wide and `h` tall across its length.
static func beam(g: ChinatownGeo, a: Vector3, b: Vector3, w: float, h: float, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-4:
		return
	var z := d / l
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	g.box(KEY, (a + b) * 0.5, Vector3(w, h, l), col, Basis(x, y, z))


## A painted beam along x centred at `c`: front and back painted (eave kind's beam mode), the
## rest red.
static func painted_beam(g: ChinatownGeo, c: Vector3, length: float, h: float, d: float, field: Color) -> void:
	var x0 := c.x - length * 0.5
	var x1 := c.x + length * 0.5
	var y0 := c.y - h * 0.5
	var y1 := c.y + h * 0.5
	for sz: float in [1.0, -1.0]:
		var z := c.z + sz * d * 0.5
		g.quad(KEY, Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z), Vector3(0, 0, sz),
			Vector2(x0, -0.999), Vector2(x1, -0.999), Vector2(x1, -0.001), Vector2(x0, -0.001), kc(field, K_EAVE))
	g.quad(KEY, Vector3(x0, y1, c.z - d * 0.5), Vector3(x1, y1, c.z - d * 0.5), Vector3(x1, y1, c.z + d * 0.5), Vector3(x0, y1, c.z + d * 0.5), Vector3.UP,
		Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, d), Vector2(x0, d), kc(DEEP_RED, K_PAINT))
	g.quad(KEY, Vector3(x0, y0, c.z - d * 0.5), Vector3(x1, y0, c.z - d * 0.5), Vector3(x1, y0, c.z + d * 0.5), Vector3(x0, y0, c.z + d * 0.5), Vector3.DOWN,
		Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, d), Vector2(x0, d), kc(DEEP_RED, K_PAINT))
	for sx: float in [-1.0, 1.0]:
		var x := c.x + sx * length * 0.5
		g.quad(KEY, Vector3(x, y0, c.z - d * 0.5), Vector3(x, y0, c.z + d * 0.5), Vector3(x, y1, c.z + d * 0.5), Vector3(x, y1, c.z - d * 0.5), Vector3(sx, 0, 0),
			Vector2(0, y0), Vector2(d, y0), Vector2(d, y1), Vector2(0, y1), kc(DEEP_RED, K_PAINT))


## Text in the frame's XY plane at `at`, facing `want` (+Z or -Z).
static func text(g: ChinatownGeo, s: String, at: Vector3, height: float, fit: float, col: Color, back: bool = false) -> void:
	var b := Basis(Vector3.UP, PI) if back else Basis()
	BroadwayTheatre.text(g, s, Transform3D(b, at), height, fit, col, Vector3.FORWARD if back else Vector3.BACK)


# --- Roofs ---------------------------------------------------------------------------------------

## A hip roof with sweeping eaves over the rectangle of walls (±hx, ±hz) round `c` (the eave
## level at the wall), overhanging (ox, oz), rising `rise` to the ridge, the corners lifted `up`.
static func sweep_roof(g: ChinatownGeo, c: Vector3, hx: float, hz: float, ox: float, oz: float, rise: float, up: float,
		tile: Color, ridge: Color, field: Color, ornaments: bool = false, ns: int = 12, nt: int = 5) -> void:
	if hz > hx:
		# Ridge along the longer side: build it turned a quarter.
		var saved := g.xf
		var rot := Basis(Vector3.UP, PI * 0.5)
		g.xf = saved * Transform3D(rot, c)
		sweep_roof(g, Vector3.ZERO, hz, hx, oz, ox, rise, up, tile, ridge, field, ornaments, ns, nt)
		g.xf = saved
		return
	var ex := hx + ox
	var ez := hz + oz
	var r := maxf(ex - ez, ex * 0.12)
	var thick := 0.16
	var flare := up * 0.45
	var faces := [
		[Vector2(-ex, ez), Vector2(ex, ez), Vector2(-r, 0), Vector2(r, 0), Vector2(0, 1)],
		[Vector2(ex, -ez), Vector2(-ex, -ez), Vector2(r, 0), Vector2(-r, 0), Vector2(0, -1)],
		[Vector2(ex, ez), Vector2(ex, -ez), Vector2(r, 0), Vector2(r, 0), Vector2(1, 0)],
		[Vector2(-ex, -ez), Vector2(-ex, ez), Vector2(-r, 0), Vector2(-r, 0), Vector2(-1, 0)],
	]
	var tc := kc(tile, K_TILE)
	var ec := kc(field, K_EAVE)
	for f: Array in faces:
		var e0: Vector2 = f[0]
		var e1: Vector2 = f[1]
		var r0: Vector2 = f[2]
		var r1: Vector2 = f[3]
		var n: Vector2 = f[4]
		var t_dir := (e1 - e0).normalized()
		var elen := e0.distance_to(e1)
		var pt := func(s: float, t: float) -> Vector3:
			var w := pow(absf(2.0 * s - 1.0), 3.0)
			var e := e0.lerp(e1, s) + (n + t_dir * signf(2.0 * s - 1.0)) * flare * w
			var rr := r0.lerp(r1, s)
			var xz := e.lerp(rr, t)
			var ye := up * w
			var y := ye + (rise - ye) * pow(t, 1.7)
			return c + Vector3(xz.x, y, xz.y)
		var slope := (e0.lerp(e1, 0.5)).distance_to(r0.lerp(r1, 0.5))
		var slope_len := sqrt(slope * slope + rise * rise)
		var want_up := Vector3(n.x, 1.6, n.y)
		var grid: Array = []
		var nrm: Array = []
		for i in ns + 1:
			var row: Array = []
			var nrow: Array = []
			var s := float(i) / float(ns)
			for j in nt + 1:
				var t := float(j) / float(nt)
				var p: Vector3 = pt.call(s, t)
				var ds: Vector3 = pt.call(minf(s + 0.01, 1.0), t) - pt.call(maxf(s - 0.01, 0.0), t)
				var dt: Vector3 = pt.call(s, minf(t + 0.02, 1.0)) - pt.call(s, maxf(t - 0.02, 0.0))
				var nn := ds.cross(dt)
				if nn.dot(want_up) < 0.0:
					nn = -nn
				if nn.length_squared() < 1e-10:
					nn = want_up
				row.append(p)
				nrow.append(nn.normalized())
			grid.append(row)
			nrm.append(nrow)
		for i in ns:
			for j in nt:
				var a: Vector3 = grid[i][j]
				var b: Vector3 = grid[i + 1][j]
				var cc: Vector3 = grid[i + 1][j + 1]
				var d: Vector3 = grid[i][j + 1]
				var u0 := float(i) / float(ns) * elen
				var u1 := float(i + 1) / float(ns) * elen
				var v0 := float(j) / float(nt) * slope_len
				var v1 := float(j + 1) / float(nt) * slope_len
				g.quad_n(KEY, a, b, cc, d, nrm[i][j], nrm[i + 1][j], nrm[i + 1][j + 1], nrm[i][j + 1],
					Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), tc)
		# The underside of the overhang (two rows in from the edge), and the fascia.
		var t_in := clampf((maxf(ox, oz) + 0.8) / maxf(slope, 0.1), 0.05, 1.0)
		var dn := Vector3(0, -thick, 0)
		for i in ns:
			var u0 := float(i) / float(ns) * elen
			var u1 := float(i + 1) / float(ns) * elen
			var s0 := float(i) / float(ns)
			var s1 := float(i + 1) / float(ns)
			var rows := [0.0, t_in * 0.5, t_in]
			for j in 2:
				var a: Vector3 = pt.call(s0, rows[j]) + dn
				var b: Vector3 = pt.call(s1, rows[j]) + dn
				var cc: Vector3 = pt.call(s1, rows[j + 1]) + dn
				var d: Vector3 = pt.call(s0, rows[j + 1]) + dn
				var v0: float = rows[j] * slope
				var v1: float = rows[j + 1] * slope
				g.quad(KEY, a, b, cc, d, Vector3.DOWN, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), ec)
			var ta: Vector3 = pt.call(s0, 0.0)
			var tb: Vector3 = pt.call(s1, 0.0)
			g.quad(KEY, ta, tb, tb + dn, ta + dn, Vector3(n.x, 0.0, n.y), Vector2(u0, -0.02), Vector2(u1, -0.02), Vector2(u1, -0.98), Vector2(u0, -0.98), kc(DEEP_RED, K_EAVE))
		# Hip caps along the face's two edges (front and back faces carry them), curling up past
		# the corner.
		if f[2] != f[3]:
			for s_edge: float in [0.0, 1.0]:
				var lift := Vector3(0, 0.1, 0)
				for j in nt:
					beam(g, pt.call(s_edge, float(j) / float(nt)) + lift, pt.call(s_edge, float(j + 1) / float(nt)) + lift, 0.24, 0.2, kc(ridge, K_RIDGE))
				var corner: Vector3 = pt.call(s_edge, 0.0) + lift
				var dir2 := (n + t_dir * (2.0 * s_edge - 1.0)).normalized()
				var tip := corner + Vector3(dir2.x * 0.5, up * 0.55 + 0.25, dir2.y * 0.5)
				beam(g, corner, tip, 0.2, 0.16, kc(ridge, K_RIDGE))
	# The main ridge, and on a gate or a hall its upturned ends and a gilded ball.
	var ra := c + Vector3(-r, rise + 0.12, 0)
	var rb := c + Vector3(r, rise + 0.12, 0)
	beam(g, ra - Vector3(0.1, 0, 0), rb + Vector3(0.1, 0, 0), 0.34, 0.34, kc(ridge, K_RIDGE))
	if ornaments:
		for sx: float in [-1.0, 1.0]:
			var e := c + Vector3(sx * r, rise + 0.2, 0)
			var top := e + Vector3(sx * 0.3, 0.9, 0)
			beam(g, e, top, 0.3, 0.32, kc(ridge, K_RIDGE))
			beam(g, top, top + Vector3(-sx * 0.42, 0.22, 0), 0.26, 0.24, kc(ridge, K_RIDGE))
		var ball := c + Vector3(0, rise + 0.3, 0)
		g.cylinder(KEY, ball, 0.22, 0.25, 8, kc(GOLD, K_GOLD))
		g.cylinder(KEY, ball + Vector3(0, 0.25, 0), 0.28, 0.32, 10, kc(GOLD, K_GOLD), 0.12)


## A tiled pent eave off a wall (the wall's face at z = 0, out along +z): from y at the wall out
## `out` metres and down `drop`, its two ends lifted `up`, between x0 and x1.
static func pent(g: ChinatownGeo, x0: float, x1: float, y: float, out: float, drop: float, up: float,
		tile: Color, ridge: Color, field: Color, ns: int = 10, nt: int = 3) -> void:
	var w := x1 - x0
	var pt := func(s: float, t: float) -> Vector3:
		var e := pow(absf(2.0 * s - 1.0), 3.0)
		var x := lerpf(x0, x1, s) + signf(2.0 * s - 1.0) * up * 0.35 * e * t
		var yy := y - drop * (1.0 - pow(1.0 - t, 1.8)) + up * e * pow(t, 1.5)
		return Vector3(x, yy, t * out)
	var slope_len := sqrt(out * out + drop * drop)
	var tc := kc(tile, K_TILE)
	for i in ns:
		for j in nt:
			var s0 := float(i) / float(ns)
			var s1 := float(i + 1) / float(ns)
			var t0 := float(j) / float(nt)
			var t1 := float(j + 1) / float(nt)
			var a: Vector3 = pt.call(s0, t0)
			var b: Vector3 = pt.call(s1, t0)
			var cc: Vector3 = pt.call(s1, t1)
			var d: Vector3 = pt.call(s0, t1)
			var want := (b - a).cross(d - a)
			if want.y < 0.0:
				want = -want
			g.quad(KEY, a, b, cc, d, want, Vector2(s0 * w, (1.0 - t0) * slope_len), Vector2(s1 * w, (1.0 - t0) * slope_len),
				Vector2(s1 * w, (1.0 - t1) * slope_len), Vector2(s0 * w, (1.0 - t1) * slope_len), tc)
			var dn := Vector3(0, -0.12, 0)
			g.quad(KEY, a + dn, b + dn, cc + dn, d + dn, Vector3.DOWN, Vector2(s0 * w, (1.0 - t0) * out), Vector2(s1 * w, (1.0 - t0) * out),
				Vector2(s1 * w, (1.0 - t1) * out), Vector2(s0 * w, (1.0 - t1) * out), kc(field, K_EAVE))
		var ea: Vector3 = pt.call(float(i) / float(ns), 1.0)
		var eb: Vector3 = pt.call(float(i + 1) / float(ns), 1.0)
		g.quad(KEY, ea, eb, eb + Vector3(0, -0.12, 0), ea + Vector3(0, -0.12, 0), Vector3.BACK,
			Vector2(float(i) / float(ns) * w, -0.02), Vector2(float(i + 1) / float(ns) * w, -0.02),
			Vector2(float(i + 1) / float(ns) * w, -0.98), Vector2(float(i) / float(ns) * w, -0.98), kc(DEEP_RED, K_EAVE))
	# The cap where it meets the wall, the end caps, the horns.
	beam(g, Vector3(x0 - 0.05, y + 0.08, 0.06), Vector3(x1 + 0.05, y + 0.08, 0.06), 0.2, 0.2, kc(ridge, K_RIDGE))
	for s: float in [0.0, 1.0]:
		for j in nt:
			beam(g, pt.call(s, float(j) / float(nt)) + Vector3(0, 0.09, 0), pt.call(s, float(j + 1) / float(nt)) + Vector3(0, 0.09, 0), 0.18, 0.16, kc(ridge, K_RIDGE))
		var corner: Vector3 = pt.call(s, 1.0) + Vector3(0, 0.09, 0)
		beam(g, corner, corner + Vector3((2.0 * s - 1.0) * 0.3, up * 0.5 + 0.15, 0.3), 0.16, 0.13, kc(ridge, K_RIDGE))


# --- Lanterns -----------------------------------------------------------------------------------

## A silk lantern hanging `hang` metres under a point, its body `h` tall, swaying (UV2).
static func lantern(g: ChinatownGeo, pivot: Vector3, hang: float, h: float, col: Color, phase: float) -> void:
	var top := pivot - Vector3(0, hang, 0)
	var rad := h * 0.42
	g.uv2 = Vector2(maxf(hang * 0.5, 0.01), phase)
	beam(g, pivot, top + Vector3(0, 0.06 * h, 0), 0.012, 0.012, kc(WIRE, K_WIRE))
	g.uv2 = Vector2(hang + h * 0.5, phase)
	var sides := 8
	var vs := [0.0, 0.14, 0.32, 0.5, 0.68, 0.86, 1.0]
	var prof := func(v: float) -> float:
		return rad * (0.5 + 0.5 * sin(PI * v))
	var sc := kc(col, K_SILK)
	for j in vs.size() - 1:
		var va: float = vs[j]
		var vb: float = vs[j + 1]
		var ra: float = prof.call(va)
		var rb: float = prof.call(vb)
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var p00 := top + Vector3(cos(a0) * ra, -va * h, sin(a0) * ra)
			var p10 := top + Vector3(cos(a1) * ra, -va * h, sin(a1) * ra)
			var p11 := top + Vector3(cos(a1) * rb, -vb * h, sin(a1) * rb)
			var p01 := top + Vector3(cos(a0) * rb, -vb * h, sin(a0) * rb)
			var na := Vector3(cos(a0), (0.5 - va) * 1.4, sin(a0)).normalized()
			var nb := Vector3(cos(a1), (0.5 - va) * 1.4, sin(a1)).normalized()
			var nc := Vector3(cos(a1), (0.5 - vb) * 1.4, sin(a1)).normalized()
			var nd := Vector3(cos(a0), (0.5 - vb) * 1.4, sin(a0)).normalized()
			var u0 := float(i) / float(sides)
			var u1 := float(i + 1) / float(sides)
			g.quad_n(KEY, p00, p10, p11, p01, na, nb, nc, nd, Vector2(u0, 1.0 - va), Vector2(u1, 1.0 - va), Vector2(u1, 1.0 - vb), Vector2(u0, 1.0 - vb), sc)
	g.cylinder(KEY, top - Vector3(0, 0.02, 0), rad * 0.55, 0.07 * h, 8, kc(GOLD, K_GOLD))
	g.cylinder(KEY, top - Vector3(0, h + 0.05 * h, 0), rad * 0.5, 0.07 * h, 8, kc(GOLD, K_GOLD))
	box(g, top - Vector3(0, h + 0.05 * h + 0.18 * h, 0), Vector3(0.04, 0.32 * h, 0.04), kc(LANTERN_RED * 0.8, K_PAINT))
	g.uv2 = Vector2.ZERO


## A wire from a to b sagging `sag`, with lanterns every STRING_STEP.
static func string_lanterns(g: ChinatownGeo, a: Vector3, b: Vector3, sag: float, seed_value: int) -> void:
	var segs := 12
	var at := func(t: float) -> Vector3:
		return a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
	for i in segs:
		beam(g, at.call(float(i) / float(segs)), at.call(float(i + 1) / float(segs)), 0.018, 0.018, kc(WIRE, K_WIRE))
	var n := int(a.distance_to(b) / STRING_STEP)
	for i in range(1, n):
		var t := float(i) / float(n)
		var p: Vector3 = at.call(t)
		var gold := (i + seed_value) % 5 == 0
		lantern(g, p, 0.12, 0.5 if not gold else 0.42, LANTERN_GOLD if gold else LANTERN_RED, h01([seed_value, i, "ph"]))


## The district's strings over the roads this chunk owns, hung between facing street lamps (their
## columns, STRING_ATTACH up), zig-zag as the two sides' lamps are staggered, plus pools of light.
static func _strings(ch: CityChunk, st: Dictionary, block: Dictionary) -> void:
	var plan := ch.plan
	var rect: Rect2 = block.rect
	var sp: float = float(ch.style.get("lamp_spacing", 24.0))
	var g: ChinatownGeo = st.geo
	g.xf = Transform3D.IDENTITY
	# Across the avenue on the +X side.
	var ax := plan.road_pos(CityPlan.AXIS_X, ch.ix + 1)
	var aname := plan.road_name(CityPlan.AXIS_X, ch.ix + 1)
	if Chinatown.LANTERN_AVENUES.has(aname) and Chinatown.block_role(plan, ch.ix + 1, ch.iz) != "":
		var other: Rect2 = plan.block(ch.ix + 1, ch.iz).rect
		var west := _lamps(rect, 3, sp)
		var east := _lamps(other, 2, sp)
		_zigzag(ch, g, west, east, 1, "x%d" % ch.iz)
	# Across the cross street on the +Z side, inside the lantern avenues.
	var xa := Chinatown.avenue_x(Chinatown.LANTERN_AVENUES[0])
	var xb := Chinatown.avenue_x("SPRING ST")
	var cx := rect.get_center().x
	if not is_nan(xa) and not is_nan(xb) and cx > xa and cx < xb and Chinatown.block_role(plan, ch.ix, ch.iz + 1) != "":
		var other: Rect2 = plan.block(ch.ix, ch.iz + 1).rect
		var north := _lamps(rect, 1, sp)
		var south := _lamps(other, 0, sp)
		_zigzag(ch, g, north, south, 0, "z%d" % ch.ix)


## The lamp spots along edge `e` of a block (CityChunk._build_sidewalk_props' order: 0 north,
## 1 south, 2 west, 3 east), as world XZ.
static func _lamps(rect: Rect2, e: int, sp: float) -> Array:
	var edges := [
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(0.0, 1.0)],
		[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2(0.0, -1.0)],
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2(1.0, 0.0)],
		[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(-1.0, 0.0)],
	]
	var a: Vector2 = edges[e][0]
	var b: Vector2 = edges[e][1]
	var inward: Vector2 = edges[e][2]
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var out: Array = []
	var t := sp * (0.5 if e % 2 == 0 else 0.25)
	while t < length - 4.0:
		out.append(a + dir * t + inward)
		t += sp
	return out


static func _zigzag(ch: CityChunk, g: ChinatownGeo, side_a: Array, side_b: Array, axis_along: int, tag: String) -> void:
	if side_a.is_empty() or side_b.is_empty():
		return
	var pts: Array = []
	for p: Vector2 in side_a:
		pts.append([p[axis_along], p, 0])
	for p: Vector2 in side_b:
		pts.append([p[axis_along], p, 1])
	pts.sort_custom(func(l: Array, r: Array) -> bool: return float(l[0]) < float(r[0]))
	var k := 0
	for i in pts.size() - 1:
		var p: Array = pts[i]
		var q: Array = pts[i + 1]
		if int(p[2]) == int(q[2]):
			continue
		var a2: Vector2 = p[1]
		var b2: Vector2 = q[1]
		var a := Vector3(a2.x, ch._gy(a2.x, a2.y) + CityChunk.SIDEWALK_TOP + STRING_ATTACH, a2.y)
		var b := Vector3(b2.x, ch._gy(b2.x, b2.y) + CityChunk.SIDEWALK_TOP + STRING_ATTACH, b2.y)
		var l := a.distance_to(b)
		var sag := 0.35 + 0.035 * l
		string_lanterns(g, a, b, sag, absi(hash([ch.plan.seed, tag, k])) % 1000)
		# Their light on the street.
		var mid := (a + b) * 0.5
		var yaw := atan2(b.x - a.x, b.z - a.z)
		var pool := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(5.0, 1.0, l * 0.8)),
			Vector3(mid.x, CityChunk.ROAD_TOP + 0.08, mid.z))
		ch._batch.add("ct_pool", PropFactory.light_pool(Color(1.0, 1.0, 1.0), 1.3, 1.6), pool, Color(1.0, 0.36, 0.16, 0.45))
		k += 1


# --- Shop buildings -----------------------------------------------------------------------------

## A lot's frame: [Transform3D (x along the frontage, +z out to the street, the face at z 0, y
## from the pavement), frontage, depth].
static func lot_frame(ch: CityChunk, lot: Dictionary, out2: Vector2) -> Array:
	var c: Vector2 = lot.center
	var s: Vector2 = lot.size
	var half := absf(out2.x) * s.x * 0.5 + absf(out2.y) * s.y * 0.5
	var face := c + out2 * half
	var out := Vector3(out2.x, 0.0, out2.y)
	var x_axis := Vector3.UP.cross(out)
	var gy := ch._gy(face.x, face.y)
	var xf := Transform3D(Basis(x_axis, Vector3.UP, out), Vector3(face.x, gy + CityChunk.SIDEWALK_TOP, face.y))
	var frontage := s.y if out2.x != 0.0 else s.x
	var depth := s.x if out2.x != 0.0 else s.y
	return [xf, frontage, depth]


## The units along a frontage W (pure: seed + lot).
static func plan_units(seed_value: int, lot_seed: int, w: float, plaza: bool = false) -> Array:
	var n := maxi(1, int(round(w / 9.0)))
	var cuts: Array = [-w * 0.5]
	for i in range(1, n):
		cuts.append(-w * 0.5 + w * float(i) / float(n) + (h01([seed_value, lot_seed, i, "cut"]) - 0.5) * 1.6)
	cuts.append(w * 0.5)
	var out: Array = []
	for i in n:
		var hv := func(tag: String) -> float: return h01([seed_value, lot_seed, i, tag])
		var storeys := 2
		var rs: float = hv.call("st")
		if rs > 0.5:
			storeys = 3
		if rs > 0.9:
			storeys = 4
		var roof := "pent"
		var rr: float = hv.call("roof")
		if rr < 0.34 and storeys <= 3:
			roof = "sweep"
		elif rr > 0.78:
			roof = "balcony"
		if plaza:
			storeys = 2
			roof = "sweep"
		var shop := int(hv.call("shop") * float(Chinatown.SHOP_NAMES.size())) % Chinatown.SHOP_NAMES.size()
		var tile := int(hv.call("tile") * float(TILES.size())) % TILES.size()
		out.append({
			"x0": float(cuts[i]), "x1": float(cuts[i + 1]), "storeys": storeys, "roof": roof,
			"h": GROUND_STOREY + float(storeys - 1) * STOREY,
			"wall": pick(WALLS, [seed_value, lot_seed, i, "wall"]),
			"trim": pick(TRIMS, [seed_value, lot_seed, i, "trim"]),
			"tile": TILES[tile], "ridge": RIDGES[tile],
			"field": pick(FIELDS, [seed_value, lot_seed, i, "field"]),
			"board": pick(BOARDS, [seed_value, lot_seed, i, "board"]),
			"shop": shop, "goods": int(Chinatown.SHOP_GOODS[shop]),
			"blade": hv.call("blade") < 0.45 and storeys >= 2,
			"word": pick(Chinatown.BLADE_WORDS, [seed_value, lot_seed, i, "word"]),
			"door_left": hv.call("door") < 0.5,
			"seed": absi(hash([seed_value, lot_seed, i])) % 100000,
			"open_l": i == 0 and not plaza, "open_r": i == n - 1 and not plaza,
		})
	return out


static func build_lot(ch: CityChunk, lot: Dictionary, out2: Vector2) -> void:
	var f := lot_frame(ch, lot, out2)
	var xf: Transform3D = f[0]
	var w: float = f[1]
	var d: float = minf(f[2], 30.0)
	ch._lot_rects.append(Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
	ch.building_count += 1
	var units := plan_units(ch.plan.seed, int(lot.seed), w)
	if ch.level != CityChunk.Level.FULL:
		_far_units(ch, xf, units, d)
		return
	var st := _state(ch)
	_units(ch, st, xf, units, d, true)


static func _units(ch: CityChunk, st: Dictionary, xf: Transform3D, units: Array, d: float, goods: bool) -> void:
	var g: ChinatownGeo = st.geo
	g.xf = xf
	for u: Dictionary in units:
		shop_unit(g, u, d, goods)
		var top: float = float(u.h) + (0.0 if u.roof == "sweep" else 0.9)
		var cx := (float(u.x0) + float(u.x1)) * 0.5
		var w := float(u.x1) - float(u.x0)
		_shape(st, xf, Vector3(cx, (top - 1.2) * 0.5, -d * 0.5), Vector3(w, top + 1.2, d))
		ch._occluder_boxes.append([xf, Vector3(cx, top * 0.5, -d * 0.5), Vector3(maxf(w - 0.8, 0.5), maxf(top - 0.8, 0.5), maxf(d - 1.2, 0.5))])


## One unit of a shop building in its lot's frame.
static func shop_unit(g: ChinatownGeo, u: Dictionary, d: float, goods: bool) -> void:
	var x0: float = u.x0
	var x1: float = u.x1
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	var hgt: float = u.h
	var roof: String = u.roof
	var wall: Color = u.wall
	var trim: Color = u.trim
	var tile: Color = u.tile
	var ridge: Color = u.ridge
	var field: Color = u.field
	var top := hgt + (0.0 if roof == "sweep" else 0.9)
	var wc := kc(wall, K_WALL)
	# The body (sides and back) and the upper front wall.
	box(g, Vector3(cx, (top - 1.2) * 0.5, -0.3 - (d - 0.3) * 0.5), Vector3(w, top + 1.2, d - 0.3), wc)
	box(g, Vector3(cx, (GROUND_STOREY + top) * 0.5, -0.15), Vector3(w, top - GROUND_STOREY, 0.3), wc)
	# The roof membrane behind the parapet (or behind the hip roof).
	box(g, Vector3(cx, hgt + 0.03, -d * 0.5 - 0.15), Vector3(w - 0.3, 0.06, d - 0.6), kc(MEMBRANE, K_STONE))
	_shopfront(g, u, x0, x1)
	# Upper storeys: lattice-framed windows with surrounds and sills.
	var storeys: int = u.storeys
	var m := maxi(1, int(round(w / 3.0)))
	var ww := minf(1.5, w / float(m) - 0.9)
	var balcony := roof == "balcony"
	for s in range(1, storeys):
		var y0 := GROUND_STOREY + float(s - 1) * STOREY
		var sill := y0 + 0.95
		var wh := 1.75
		if balcony and s == 1:
			# Glazed doors onto the balcony.
			sill = y0 + 0.2
			wh = 2.5
		for i in m:
			var wx := x0 + (float(i) + 0.5) * w / float(m)
			box(g, Vector3(wx, sill + wh * 0.5, 0.03), Vector3(ww, wh, 0.06), kc(trim, K_WINDOW))
			box(g, Vector3(wx, sill + wh + 0.07, 0.06), Vector3(ww + 0.3, 0.14, 0.12), kc(trim, K_PAINT))
			box(g, Vector3(wx, sill - 0.05, 0.08), Vector3(ww + 0.2, 0.1, 0.16), kc(GRANITE, K_STONE))
			for sx: float in [-1.0, 1.0]:
				box(g, Vector3(wx + sx * (ww * 0.5 + 0.06), sill + wh * 0.5, 0.05), Vector3(0.12, wh + 0.1, 0.1), kc(trim, K_PAINT))
	# Windows down the open sides of the end units (a light well or the next lot's gap), the
	# front 12 m.
	for sx: float in [-1.0, 1.0]:
		if not u.get("open_l" if sx < 0.0 else "open_r", false):
			continue
		var xs := cx + sx * (w * 0.5 + 0.03)
		var nd := clampi(int(minf(d, 12.0) / 3.2), 1, 4)
		for s in range(1, storeys):
			var y0 := GROUND_STOREY + float(s - 1) * STOREY + 0.95
			for i in nd:
				var z := -1.8 - float(i) * 3.2
				box(g, Vector3(xs, y0 + 0.85, z), Vector3(0.06, 1.7, 1.2), kc(trim, K_WINDOW))
				box(g, Vector3(xs + sx * 0.03, y0 - 0.05, z), Vector3(0.12, 0.1, 1.4), kc(GRANITE, K_STONE))
	# Corner piers up the front.
	for sx: float in [-1.0, 1.0]:
		box(g, Vector3(cx + sx * (w * 0.5 - 0.2), (top + GROUND_STOREY) * 0.5, 0.06), Vector3(0.4, top - GROUND_STOREY, 0.12), kc(wall * 0.88, K_WALL))
	match roof:
		"sweep":
			var hz := minf(d, 11.0) * 0.5
			var rise := 1.5 + 0.07 * w
			sweep_roof(g, Vector3(cx, hgt, -hz), w * 0.5, hz, 0.35, 1.1, rise, 0.55, tile, ridge, field, false, 10, 4)
			# The painted beam under the front eave.
			painted_beam(g, Vector3(cx, hgt - 0.3, 0.12), w, 0.5, 0.24, field)
			# Lanterns under the front eave.
			_eave_lanterns(g, x0, x1, hgt - 0.5, 0.75, u)
		_:
			# Parapet and its tiled coping.
			sweep_roof(g, Vector3(cx, top - 0.05, -0.15), w * 0.5 - 0.05, 0.2, 0.12, 0.3, 0.42, 0.22, tile, ridge, field, false, 6, 2)
			painted_beam(g, Vector3(cx, top - 0.45, 0.06), w, 0.35, 0.12, field)
			if balcony:
				_balcony(g, x0, x1, GROUND_STOREY, trim)
				var y_eave := GROUND_STOREY + STOREY - 0.15
				pent(g, x0, x1, y_eave, 1.3, 0.5, 0.35, tile, ridge, field)
				_eave_lanterns(g, x0, x1, y_eave - 0.55, 1.0, u)
			else:
				pent(g, x0 + 0.05, x1 - 0.05, GROUND_STOREY + 0.35, 1.1, 0.45, 0.35, tile, ridge, field)
				_eave_lanterns(g, x0, x1, GROUND_STOREY - 0.25, 0.8, u)
	if u.blade:
		_blade(g, u, x0, x1, top)
	if goods and int(u.goods) >= 0:
		_goods(g, u, x0, x1)


static func _shopfront(g: ChinatownGeo, u: Dictionary, x0: float, x1: float) -> void:
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	var trim: Color = u.trim
	var wall: Color = u.wall
	var pier := RED if wall.v > 0.6 else trim
	# Piers at both ends, a bulkhead, the glass, a door, the transom bar.
	for sx: float in [-1.0, 1.0]:
		box(g, Vector3(cx + sx * (w * 0.5 - 0.25), GROUND_STOREY * 0.5, -0.1), Vector3(0.5, GROUND_STOREY, 0.42), kc(pier, K_PAINT))
		box(g, Vector3(cx + sx * (w * 0.5 - 0.25), 0.25, 0.0), Vector3(0.62, 0.5, 0.5), kc(GRANITE, K_STONE))
	var gw := w - 1.0
	box(g, Vector3(cx, 0.3, -0.24), Vector3(gw, 0.6, 0.12), kc(GRANITE * 0.8, K_STONE))
	box(g, Vector3(cx, 1.85, -0.26), Vector3(gw, 2.5, 0.04), kc(trim, K_SHOP))
	box(g, Vector3(cx, 3.12, -0.2), Vector3(gw, 0.08, 0.14), kc(trim, K_PAINT))
	var door_x := x0 + 1.2 if u.door_left else x1 - 1.2
	box(g, Vector3(door_x, 1.4, -0.22), Vector3(1.1, 2.6, 0.06), kc(trim * 0.6, K_SHOP))
	for sx: float in [-0.6, 0.6]:
		box(g, Vector3(door_x + sx, 1.4, -0.2), Vector3(0.08, 2.7, 0.1), kc(trim, K_PAINT))
	# Mullions.
	var mn := maxi(1, int(gw / 1.8))
	for i in range(1, mn):
		box(g, Vector3(x0 + 0.5 + gw * float(i) / float(mn), 1.85, -0.21), Vector3(0.07, 2.5, 0.08), kc(trim, K_PAINT))
	# The sign board with its gilt name and a gold frame.
	var board: Color = u.board
	var bw := w - 0.9
	box(g, Vector3(cx, 3.6, 0.12), Vector3(bw, 0.8, 0.14), kc(board, K_SIGN))
	for sy: float in [-1.0, 1.0]:
		box(g, Vector3(cx, 3.6 + sy * 0.43, 0.13), Vector3(bw + 0.1, 0.07, 0.17), kc(GOLD, K_GOLD))
	for sx: float in [-1.0, 1.0]:
		box(g, Vector3(cx + sx * (bw * 0.5 + 0.02), 3.6, 0.13), Vector3(0.07, 0.93, 0.17), kc(GOLD, K_GOLD))
	var ink := GOLD if board != BOARDS[3] else RED
	if board == BOARDS[1]:
		ink = Color(0.95, 0.25, 0.18) if int(u.seed) % 3 == 0 else GOLD
	text(g, Chinatown.SHOP_NAMES[int(u.shop)], Vector3(cx, 3.6, 0.2), 0.42, bw - 0.5, kc(ink, K_INK))


static func _eave_lanterns(g: ChinatownGeo, x0: float, x1: float, y: float, z: float, u: Dictionary) -> void:
	var w := x1 - x0
	var n := clampi(int(round(w / 3.0)), 1, 4)
	for i in n:
		var x := x0 + (float(i) + 0.5) * w / float(n)
		var gold := (int(u.seed) + i) % 4 == 0
		lantern(g, Vector3(x, y, z), 0.12, 0.62, LANTERN_GOLD if gold else LANTERN_RED, h01([u.seed, i, "el"]))


static func _balcony(g: ChinatownGeo, x0: float, x1: float, y: float, trim: Color) -> void:
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	box(g, Vector3(cx, y - 0.1, 0.55), Vector3(w - 0.4, 0.2, 1.1), kc(GRANITE * 0.9, K_STONE))
	var rail := kc(RED, K_PAINT)
	box(g, Vector3(cx, y + 1.0, 1.05), Vector3(w - 0.5, 0.1, 0.1), rail)
	box(g, Vector3(cx, y + 0.12, 1.05), Vector3(w - 0.5, 0.08, 0.08), rail)
	var n := maxi(2, int(w / 1.4))
	for i in n + 1:
		var x := x0 + 0.25 + (w - 0.5) * float(i) / float(n)
		box(g, Vector3(x, y + 0.55, 1.05), Vector3(0.1, 1.0, 0.1), rail)
		if i < n:
			box(g, Vector3(x + (w - 0.5) / float(n) * 0.5, y + 0.55, 1.05), Vector3((w - 0.5) / float(n) - 0.14, 0.7, 0.04), kc(trim, K_LATTICE))
	for sx: float in [-1.0, 1.0]:
		box(g, Vector3(cx + sx * (w * 0.5 - 0.25), y + 0.55, 0.55), Vector3(0.08, 1.0, 1.0), rail)


static func _blade(g: ChinatownGeo, u: Dictionary, x0: float, x1: float, top: float) -> void:
	var word: String = u.word
	var bx := x0 + 0.55 if not u.door_left else x1 - 0.55
	var y0 := GROUND_STOREY + 0.6
	var y1 := minf(top - 0.3, y0 + 0.62 * float(word.length()) + 0.5)
	if y1 - y0 < 1.6:
		return
	var board: Color = u.board
	box(g, Vector3(bx, (y0 + y1) * 0.5, 0.55), Vector3(0.16, y1 - y0, 0.9), kc(board, K_SIGN))
	box(g, Vector3(bx, y1 + 0.05, 0.55), Vector3(0.22, 0.1, 1.0), kc(GOLD, K_GOLD))
	box(g, Vector3(bx, y0 - 0.05, 0.55), Vector3(0.22, 0.1, 1.0), kc(GOLD, K_GOLD))
	beam(g, Vector3(bx, y1 - 0.2, 0.0), Vector3(bx, y1 - 0.2, 0.15), 0.06, 0.06, kc(WIRE, K_WIRE))
	beam(g, Vector3(bx, y0 + 0.2, 0.0), Vector3(bx, y0 + 0.2, 0.15), 0.06, 0.06, kc(WIRE, K_WIRE))
	var ink := GOLD if board != BOARDS[3] else RED
	var step := (y1 - y0 - 0.3) / float(word.length())
	for i in word.length():
		var ch := word[i]
		if ch == " ":
			continue
		var y := y1 - 0.25 - (float(i) + 0.5) * step
		for sx: float in [-1.0, 1.0]:
			var b := Basis(Vector3.UP, sx * PI * 0.5)
			BroadwayTheatre.text(g, ch, Transform3D(b, Vector3(bx + sx * 0.09, y - step * 0.28, 0.55)), minf(step * 0.62, 0.5), 0.7,
				kc(ink, K_INK), Vector3(sx, 0, 0))


## The shop's goods on the pavement in front of it (z 0.2 .. 1.6), leaving the door clear.
static func _goods(g: ChinatownGeo, u: Dictionary, x0: float, x1: float) -> void:
	var door_x := x0 + 1.2 if u.door_left else x1 - 1.2
	var a := x0 + 0.4
	var b := x1 - 0.4
	if u.door_left:
		a = door_x + 0.9
	else:
		b = door_x - 0.9
	if b - a < 1.2:
		return
	var s: int = u.seed
	match int(u.goods):
		Chinatown.Goods.PRODUCE:
			var n := maxi(1, int((b - a) / 1.9))
			var tw := (b - a) / float(n)
			for i in n:
				var tx := a + (float(i) + 0.5) * tw
				_table(g, tx, tw - 0.2, 0.82)
				var crates := maxi(2, int((tw - 0.2) / 0.6))
				for c in crates:
					var cxx := tx - (tw - 0.2) * 0.5 + (float(c) + 0.5) * (tw - 0.2) / float(crates)
					var pc: Color = PRODUCE[(s + i * 3 + c) % PRODUCE.size()]
					_crate(g, Vector3(cxx, 0.86, 0.95), Vector3(0.52, 0.2, 0.62), pc, deg_to_rad(14.0))
					_crate(g, Vector3(cxx, 0.12, 1.0), Vector3(0.5, 0.24, 0.42), PRODUCE[(s + i + c * 5) % PRODUCE.size()], 0.0)
		Chinatown.Goods.FLOWERS:
			var n := maxi(2, int((b - a) / 0.5))
			for i in n:
				var x := a + (float(i) + 0.5) * (b - a) / float(n)
				var row := i % 2
				var y := 0.0 if row == 0 else 0.42
				var z := 1.2 if row == 0 else 0.6
				if row == 1:
					box(g, Vector3(x, 0.21, z), Vector3((b - a) / float(n), 0.42, 0.5), kc(WOOD, K_PAINT))
				g.cylinder(KEY, Vector3(x, y, z), 0.17, 0.36, 8, kc(Color(0.55, 0.56, 0.57), K_WIRE), 0.19)
				var fc: Color = [Color(0.85, 0.35, 0.55), Color(0.92, 0.80, 0.30), Color(0.90, 0.40, 0.30)][(s + i) % 3]
				box(g, Vector3(x, y + 0.5, z), Vector3(0.36, 0.3, 0.36), kc(fc, K_PRODUCE))
		Chinatown.Goods.RACKS:
			var n := maxi(1, int((b - a) / 1.6))
			for i in n:
				var rx := a + (float(i) + 0.5) * (b - a) / float(n)
				_rack(g, rx, minf(1.3, (b - a) / float(n) - 0.2), s + i)
		Chinatown.Goods.PLANTS:
			var n := maxi(1, int((b - a) / 1.1))
			for i in n:
				var x := a + (float(i) + 0.5) * (b - a) / float(n)
				var pot: Color = [Color(0.15, 0.35, 0.45), Color(0.15, 0.36, 0.25), Color(0.62, 0.30, 0.18)][(s + i) % 3]
				g.cylinder(KEY, Vector3(x, 0.0, 0.7), 0.3, 0.5, 10, kc(pot, K_PAINT), 0.38)
				if (s + i) % 2 == 0:
					box(g, Vector3(x, 0.85, 0.7), Vector3(0.7, 0.75, 0.7), kc(Color(0.25, 0.48, 0.18), K_PRODUCE))
				else:
					for k in 5:
						var o := Vector3(cos(float(k) * 1.3) * 0.12, 0.0, sin(float(k) * 1.3) * 0.12)
						beam(g, Vector3(x, 0.45, 0.7) + o, Vector3(x, 2.0 + 0.2 * float(k % 3), 0.7) + o * 1.6, 0.05, 0.05, kc(Color(0.38, 0.52, 0.20), K_PAINT))
						box(g, Vector3(x, 1.9, 0.7) + o * 1.8, Vector3(0.3, 0.5, 0.3), kc(Color(0.30, 0.55, 0.20), K_PRODUCE))
		Chinatown.Goods.BINS:
			_table(g, (a + b) * 0.5, b - a, 0.62)
			var n := maxi(2, int((b - a) / 0.45))
			var dried := [Color(0.45, 0.25, 0.12), Color(0.55, 0.12, 0.08), Color(0.65, 0.52, 0.30), Color(0.30, 0.20, 0.12)]
			for i in n:
				var x := a + (float(i) + 0.5) * (b - a) / float(n)
				_crate(g, Vector3(x, 0.66, 0.9), Vector3((b - a) / float(n) - 0.06, 0.18, 0.5), dried[(s + i) % dried.size()], deg_to_rad(10.0))
			box(g, Vector3(b - 0.3, 0.3, 0.45), Vector3(0.5, 0.6, 0.45), kc(Color(0.62, 0.48, 0.32), K_PAINT))
		Chinatown.Goods.CRATES:
			for i in 4:
				var x := a + 0.4 + float(i % 2) * 0.62
				var y := 0.18 + float(i / 2) * 0.36
				box(g, Vector3(x, y, 0.55), Vector3(0.58, 0.34, 0.44), kc(Color(0.62, 0.48, 0.32) * (0.9 + 0.1 * float(i)), K_PAINT))


static func _table(g: ChinatownGeo, cx: float, w: float, h: float) -> void:
	box(g, Vector3(cx, h - 0.02, 0.9), Vector3(w, 0.04, 0.95), kc(WOOD, K_PAINT))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(g, Vector3(cx + sx * (w * 0.5 - 0.06), (h - 0.04) * 0.5, 0.9 + sz * 0.4), Vector3(0.05, h - 0.04, 0.05), kc(WIRE, K_WIRE))


## A crate with its goods heaped in it, tipped toward the street by `tilt`.
static func _crate(g: ChinatownGeo, base: Vector3, size: Vector3, goods: Color, tilt: float) -> void:
	var b := Basis(Vector3.RIGHT, tilt)
	var c := base + b * Vector3(0, size.y * 0.5, 0)
	box(g, c, size, kc(WOOD * 1.15, K_PAINT), b)
	box(g, c + b * Vector3(0, size.y * 0.5 + 0.015, 0), Vector3(size.x - 0.05, 0.04, size.z - 0.05), kc(goods, K_PRODUCE), b)


static func _rack(g: ChinatownGeo, cx: float, w: float, s: int) -> void:
	var wc := kc(Color(0.5, 0.5, 0.52), K_WIRE)
	for sx: float in [-1.0, 1.0]:
		beam(g, Vector3(cx + sx * w * 0.5, 0.0, 0.9), Vector3(cx + sx * w * 0.5, 1.9, 0.9), 0.04, 0.04, wc)
	beam(g, Vector3(cx - w * 0.5, 1.9, 0.9), Vector3(cx + w * 0.5, 1.9, 0.9), 0.04, 0.04, wc)
	beam(g, Vector3(cx - w * 0.5, 1.2, 0.9), Vector3(cx + w * 0.5, 1.2, 0.9), 0.03, 0.03, wc)
	var cols := [Color(0.80, 0.12, 0.10), Color(0.90, 0.70, 0.20), Color(0.15, 0.40, 0.55), Color(0.85, 0.85, 0.80), Color(0.20, 0.45, 0.25)]
	var n := maxi(2, int(w / 0.28))
	for i in n:
		var x := cx - w * 0.5 + (float(i) + 0.5) * w / float(n)
		var c: Color = cols[(s + i) % cols.size()]
		box(g, Vector3(x, 1.62, 0.9), Vector3(0.2, 0.5, 0.04), kc(c, K_PAINT))
		if i % 3 == 0:
			lantern(g, Vector3(x, 1.18, 0.9), 0.04, 0.3, LANTERN_RED if i % 2 == 0 else LANTERN_GOLD, float(i) * 0.37)
		else:
			box(g, Vector3(x, 0.92, 0.9), Vector3(0.18, 0.5, 0.05), kc(cols[(s + i + 2) % cols.size()], K_PAINT))


static func _far_units(ch: CityChunk, xf: Transform3D, units: Array, d: float) -> void:
	for u: Dictionary in units:
		var top: float = float(u.h) + (0.0 if u.roof == "sweep" else 0.9)
		var cx := (float(u.x0) + float(u.x1)) * 0.5
		var w := float(u.x1) - float(u.x0)
		var wall: Color = u.wall
		_lod_box(ch, xf, Vector3(cx, top * 0.5, -d * 0.5), Vector3(w, top, d), wall, Color(0.25, 0.3, float(int(u.seed) % 997) / 997.0, 0.0), true)
		if u.roof == "sweep":
			var hz := minf(d, 11.0) * 0.5
			_lod_box(ch, xf, Vector3(cx, float(u.h) + 0.6, -hz), Vector3(w + 0.7, 1.2, hz * 2.0 + 2.2), u.tile, Color(0.0, 0.0, 0.0, 1.0), false)
		else:
			_lod_box(ch, xf, Vector3(cx, top + 0.15, 0.1), Vector3(w, 0.3, 0.9), u.tile, Color(0.0, 0.0, 0.0, 1.0), false)


static func _lod_box(ch: CityChunk, xf: Transform3D, center: Vector3, size: Vector3, col: Color, custom: Color, collide: bool) -> void:
	var c := xf * center
	var b := xf.basis * Basis.from_scale(size)
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(b, c - Vector3(0.0, ch._gy(c.x, c.z), 0.0)), col, custom)
	if collide:
		var ws := (xf.basis * size).abs()
		ch._add_lod_shape(ws, c)


# --- The gate -----------------------------------------------------------------------------------

## A gateway in its frame (x across the opening, the columns at ±span/2, faces ±z, y up from the
## pavement), `s` its scale (1 the street gate), carrying `name` on its board and `sub` under it.
static func gate_mesh(g: ChinatownGeo, st: Dictionary, span: float, s: float, name: String, sub: String, world: Transform3D) -> void:
	var hx := span * 0.5
	var lantern_tile := TILES[0]
	for sx: float in [-1.0, 1.0]:
		var x := sx * hx
		box(g, Vector3(x, 0.55 * s, 0), Vector3(1.3, 1.1, 1.3) * s, kc(GRANITE, K_STONE))
		box(g, Vector3(x, 1.18 * s, 0), Vector3(1.05, 0.16, 1.05) * s, kc(GRANITE * 0.9, K_STONE))
		g.cylinder(KEY, Vector3(x, 1.26 * s, 0), 0.42 * s, 7.95 * s, 14, kc(RED, K_PAINT))
		g.cylinder(KEY, Vector3(x, 1.4 * s, 0), 0.45 * s, 0.14 * s, 14, kc(GOLD, K_GOLD))
		g.cylinder(KEY, Vector3(x, 8.75 * s, 0), 0.45 * s, 0.14 * s, 14, kc(GOLD, K_GOLD))
		_shape(st, world, Vector3(x, 4.6 * s, 0), Vector3(1.3, 9.2, 1.3) * s)
		# Small roofs over each column's head, under the main one.
		box(g, Vector3(x, 9.05 * s, 0), Vector3(1.2, 0.3, 1.2) * s, kc(DEEP_RED, K_PAINT))
	painted_beam(g, Vector3(0, 6.65 * s, 0), span + 2.4 * s, 0.6 * s, 0.55 * s, FIELDS[0])
	painted_beam(g, Vector3(0, 8.55 * s, 0), span + 3.2 * s, 0.62 * s, 0.6 * s, FIELDS[1])
	painted_beam(g, Vector3(0, 9.2 * s, 0), span + 3.6 * s, 0.5 * s, 0.9 * s, FIELDS[2])
	# Struts between the beams.
	for x: float in [-3.6 * s, 3.6 * s, -(hx - 1.6 * s), hx - 1.6 * s]:
		box(g, Vector3(x, 7.6 * s, 0), Vector3(0.3, 1.3, 0.38) * s, kc(RED, K_PAINT))
	# The name board, gold-framed, the name both ways.
	var bw := minf(6.4 * s, span - 2.0 * s)
	box(g, Vector3(0, 7.6 * s, 0), Vector3(bw, 1.3 * s, 0.28 * s), kc(BOARDS[0], K_SIGN))
	for sy: float in [-1.0, 1.0]:
		box(g, Vector3(0, 7.6 * s + sy * 0.68 * s, 0), Vector3(bw + 0.2 * s, 0.12 * s, 0.34 * s), kc(GOLD, K_GOLD))
	for sx: float in [-1.0, 1.0]:
		box(g, Vector3(sx * (bw * 0.5 + 0.05 * s), 7.6 * s, 0), Vector3(0.12 * s, 1.48 * s, 0.34 * s), kc(GOLD, K_GOLD))
	for back: bool in [false, true]:
		var z := (0.15 * s) * (-1.0 if back else 1.0)
		text(g, name, Vector3(0, 7.6 * s, z), 0.74 * s, bw - 0.8 * s, kc(GOLD, K_INK), back)
	if sub != "":
		var sw := minf(span - 3.0 * s, 0.32 * s * float(sub.length()) + 0.8 * s)
		box(g, Vector3(0, 6.08 * s, 0), Vector3(sw, 0.46 * s, 0.14 * s), kc(BOARDS[1], K_SIGN))
		for back: bool in [false, true]:
			text(g, sub, Vector3(0, 6.08 * s, (0.08 * s) * (-1.0 if back else 1.0)), 0.26 * s, sw - 0.4 * s, kc(GOLD, K_INK), back)
	sweep_roof(g, Vector3(0, 9.45 * s, 0), hx + 1.9 * s, 0.75 * s, 1.3 * s, 1.0 * s, 1.7 * s, 0.8 * s, lantern_tile, RIDGES[0], FIELDS[0], true, 16, 4)
	for sx: float in [-1.0, 1.0]:
		lantern(g, Vector3(sx * (hx - 3.2 * s), 6.35 * s, 0), 0.25 * s, 1.0 * s, LANTERN_RED, 0.3 + sx)


## Floodlight pools at the gate's feet (night).
static func _floods(ch: CityChunk, world: Transform3D, span: float) -> void:
	for sx: float in [-1.0, 1.0]:
		var p := world * Vector3(sx * span * 0.5, 0.0, 0.0)
		var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(6.0, 1.0, 6.0)), Vector3(p.x, CityChunk.SIDEWALK_TOP + 0.09, p.z))
		ch._batch.add("ct_pool", PropFactory.light_pool(Color(1.0, 1.0, 1.0), 1.3, 1.6), pool, Color(1.0, 0.55, 0.30, 0.6))


static func _gate_far(ch: CityChunk, gate: Dictionary) -> void:
	var x: float = gate.x
	var z: float = gate.z
	var y := ch._gy(x, z) + CityChunk.SIDEWALK_TOP
	var xf := Transform3D(Basis(), Vector3(x, y, z))
	var hx: float = (float(gate.width) + 4.4) * 0.5
	for sx: float in [-1.0, 1.0]:
		_lod_box(ch, xf, Vector3(sx * hx, 4.6, 0), Vector3(0.9, 9.2, 0.9), RED, Color(0, 0, 0, 1.0), true)
	_lod_box(ch, xf, Vector3(0, 7.6, 0), Vector3(hx * 2.0 + 3.0, 2.6, 0.7), DEEP_RED, Color(0, 0, 0, 1.0), false)
	_lod_box(ch, xf, Vector3(0, 10.3, 0), Vector3(hx * 2.0 + 6.0, 1.6, 4.0), TILES[0], Color(0, 0, 0, 1.0), false)


# --- The plaza ----------------------------------------------------------------------------------

## The plaza's layout in world XZ (pure): the walk, the hall, the pond, the shop rows, the gates.
static func plaza_layout(rect: Rect2, sidewalk: float) -> Dictionary:
	var inner := rect.grow(-sidewalk)
	var c := inner.get_center()
	var row_d := 12.0
	return {
		"inner": inner, "walk_z": c.y, "walk_w": 10.0,
		"hall": Vector2(c.x, c.y - 5.0 - 13.0), "pond": Vector2(c.x, c.y + 5.0 + 11.0),
		"north_face": inner.position.y + row_d, "south_face": inner.end.y - row_d, "row_d": row_d,
		"gate_w": Vector2(inner.position.x + 1.6, c.y), "gate_e": Vector2(inner.end.x - 1.6, c.y),
	}


static func build_plaza(ch: CityChunk, block: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var L := plaza_layout(rect, ch.plan.sidewalk_width)
	var inner: Rect2 = L.inner
	var c := inner.get_center()
	var walk_z: float = L.walk_z
	# Paving over the whole block, the walk a different stone (both levels: the far city sees it).
	ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + 0.02, c.y), Vector3(inner.size.x, 0.04, inner.size.y), Color(0.70, 0.62, 0.55), false,
		PropFactory.road("paving", 2.0, Color(0.86, 0.74, 0.66), hash([ch.plan.seed, ch.ix, ch.iz, "ct_plaza"]), 1.5, 0.3))
	ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + 0.045, walk_z), Vector3(inner.size.x, 0.04, L.walk_w), Color(0.66, 0.64, 0.60), false,
		PropFactory.road("paving", 1.2, Color(0.80, 0.78, 0.74), hash([ch.plan.seed, ch.ix, ch.iz, "ct_walk"]), 0.9, 0.2))
	var seed_value := ch.plan.seed
	var row_x0 := inner.position.x + 2.0
	var row_x1 := inner.end.x - 2.0
	var rows := [[float(L.north_face), Vector2(0, 1)], [float(L.south_face), Vector2(0, -1)]]
	var hall: Vector2 = L.hall
	if ch.level != CityChunk.Level.FULL:
		for r: Array in rows:
			var face: float = r[0]
			var out2: Vector2 = r[1]
			var xf := _row_frame(ch, Vector2((row_x0 + row_x1) * 0.5, face), out2)
			_far_units(ch, xf, plan_units(seed_value, absi(hash([ch.ix, ch.iz, out2.y])), row_x1 - row_x0, true), float(L.row_d))
		var hy := ch._gy(hall.x, hall.y) + CityChunk.SIDEWALK_TOP
		var hxf := Transform3D(Basis(), Vector3(hall.x, hy, hall.y))
		_lod_box(ch, hxf, Vector3(0, 0.45, 0), Vector3(20, 0.9, 16), GRANITE, Color(0, 0, 0, 1.0), true)
		_lod_box(ch, hxf, Vector3(0, 5.0, 0), Vector3(13.6, 8.6, 9.6), DEEP_RED, Color(0.25, 0.2, 0.5, 0.0), true)
		_lod_box(ch, hxf, Vector3(0, 6.2, 0), Vector3(19.0, 1.2, 15.0), TILES[0], Color(0, 0, 0, 1.0), false)
		_lod_box(ch, hxf, Vector3(0, 10.6, 0), Vector3(13.6, 1.0, 9.8), TILES[0], Color(0, 0, 0, 1.0), false)
		_lod_box(ch, hxf, Vector3(0, 14.4, 0), Vector3(8.6, 1.8, 6.6), TILES[0], Color(0, 0, 0, 1.0), false)
		return
	var st := _state(ch)
	var g: ChinatownGeo = st.geo
	for r: Array in rows:
		var face: float = r[0]
		var out2: Vector2 = r[1]
		var xf := _row_frame(ch, Vector2((row_x0 + row_x1) * 0.5, face), out2)
		_units(ch, st, xf, plan_units(seed_value, absi(hash([ch.ix, ch.iz, out2.y])), row_x1 - row_x0, true), float(L.row_d), true)
	# The hall.
	var hy := ch._gy(hall.x, hall.y) + CityChunk.SIDEWALK_TOP
	var hxf := Transform3D(Basis(), Vector3(hall.x, hy, hall.y))
	g.xf = hxf
	hall_mesh(g, st, hxf)
	# The gates at the walk's two ends.
	for e: Vector2 in [L.gate_w, L.gate_e]:
		var gy := ch._gy(e.x, e.y) + CityChunk.SIDEWALK_TOP
		var gxf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(e.x, gy, e.y))
		g.xf = gxf
		gate_mesh(g, st, float(L.walk_w) + 1.2, 0.72, Chinatown.PLAZA_NAME, "", gxf)
	# The pond.
	var pond: Vector2 = L.pond
	var py := ch._gy(pond.x, pond.y) + CityChunk.SIDEWALK_TOP
	g.xf = Transform3D(Basis(), Vector3(pond.x, py, pond.y))
	_pond(g, st, g.xf)
	# Lantern masts down the walk and strings across it.
	g.xf = Transform3D.IDENTITY
	var masts: Array = []
	var mx := inner.position.x + 9.0
	var side := 0
	while mx < inner.end.x - 8.0:
		for sz: float in [-1.0, 1.0]:
			var p := Vector2(mx + (4.5 if sz > 0.0 else 0.0), walk_z + sz * (float(L.walk_w) * 0.5 + 0.6))
			var y := ch._gy(p.x, p.y) + CityChunk.SIDEWALK_TOP
			box(g, Vector3(p.x, y + 2.4, p.y), Vector3(0.16, 4.8, 0.16), kc(RED, K_PAINT))
			box(g, Vector3(p.x, y + 0.12, p.y), Vector3(0.4, 0.24, 0.4), kc(GRANITE, K_STONE))
			box(g, Vector3(p.x, y + 4.86, p.y), Vector3(0.26, 0.12, 0.26), kc(GOLD, K_GOLD))
			_shape(st, Transform3D.IDENTITY, Vector3(p.x, y + 2.4, p.y), Vector3(0.2, 4.8, 0.2))
			masts.append([p.x, Vector3(p.x, y + 4.6, p.y), 0 if sz < 0.0 else 1])
		mx += 9.0
		side += 1
	masts.sort_custom(func(l: Array, r: Array) -> bool: return float(l[0]) < float(r[0]))
	for i in masts.size() - 1:
		var p: Array = masts[i]
		var q: Array = masts[i + 1]
		if int(p[2]) != int(q[2]):
			string_lanterns(g, p[1], q[1], 0.5, i + 17)
	# Trees in planters at the four quarters, and benches facing the pond and the hall.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, ch.ix, ch.iz, "ct_trees"])
	for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p := Vector2(c.x + q.x * inner.size.x * 0.32, walk_z + q.y * 12.0)
		var y := ch._gy(p.x, p.y) + CityChunk.SIDEWALK_TOP
		g.xf = Transform3D(Basis(), Vector3(p.x, y, p.y))
		box(g, Vector3(0, 0.3, 0), Vector3(2.6, 0.6, 2.6), kc(GRANITE, K_STONE))
		box(g, Vector3(0, 0.58, 0), Vector3(2.3, 0.04, 2.3), kc(Color(0.22, 0.42, 0.16), K_PRODUCE))
		ch._add_tree(Vector3(p.x, CityChunk.SIDEWALK_TOP + 0.6, p.y), rng)
	for k in 4:
		var a := PI * 0.25 + float(k) * PI * 0.5
		var p := pond + Vector2(cos(a), sin(a)) * 8.0
		ch._add_bench(Vector3(p.x, CityChunk.SIDEWALK_TOP + 0.04, p.y), atan2(cos(a), sin(a)))
	g.xf = Transform3D.IDENTITY


static func _row_frame(ch: CityChunk, face: Vector2, out2: Vector2) -> Transform3D:
	var out := Vector3(out2.x, 0.0, out2.y)
	var gy := ch._gy(face.x, face.y)
	return Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), Vector3(face.x, gy + CityChunk.SIDEWALK_TOP, face.y))


## The plaza's hall in its frame (facing +z): a granite platform with steps, a red-columned hall
## under three tiers of sweeping roof, lattice screens, the name board, lanterns on the eave.
static func hall_mesh(g: ChinatownGeo, st: Dictionary, world: Transform3D) -> void:
	var tile: Color = TILES[0]
	var ridge: Color = RIDGES[0]
	var field: Color = FIELDS[0]
	box(g, Vector3(0, 0.45, 0), Vector3(20, 0.9, 16), kc(GRANITE, K_STONE))
	for i in 3:
		box(g, Vector3(0, 0.15 + 0.3 * float(i), 8.0 + 0.45 * float(2 - i) + 0.22), Vector3(8.0, 0.3, 0.45), kc(GRANITE * 0.95, K_STONE))
	_shape(st, world, Vector3(0, 0.45, 0), Vector3(20, 0.9, 16))
	var y0 := 0.9
	var col_h := 4.2
	# Columns round a 16 x 12 hall.
	for i in 7:
		var x := -8.0 + float(i) * 16.0 / 6.0
		for sz: float in [-1.0, 1.0]:
			g.cylinder(KEY, Vector3(x, y0, sz * 6.0), 0.28, col_h, 10, kc(RED, K_PAINT))
			box(g, Vector3(x, y0 + 0.12, sz * 6.0), Vector3(0.7, 0.24, 0.7), kc(GRANITE, K_STONE))
	for i in range(1, 4):
		var z := -6.0 + float(i) * 3.0
		for sx: float in [-1.0, 1.0]:
			g.cylinder(KEY, Vector3(sx * 8.0, y0, z), 0.28, col_h, 10, kc(RED, K_PAINT))
	# The hall itself inside the colonnade: walls, lattice screens, the doors.
	box(g, Vector3(0, y0 + col_h * 0.5, 0), Vector3(13.6, col_h, 9.6), kc(DEEP_RED, K_PAINT))
	_shape(st, world, Vector3(0, y0 + col_h * 0.5 + 2.5, 0), Vector3(13.6, col_h + 5.0, 9.6))
	for i in 5:
		var x := -5.4 + float(i) * 2.7
		var door := i == 2
		box(g, Vector3(x, y0 + 1.8, 4.82), Vector3(2.3, 3.0, 0.06), kc(GOLD * 0.8 if not door else RED, K_LATTICE if not door else K_SHOP))
		box(g, Vector3(x, y0 + 3.5, 4.83), Vector3(2.3, 0.3, 0.06), kc(GOLD, K_GOLD))
	for z: float in [-2.7, 0.0, 2.7]:
		for sx: float in [-1.0, 1.0]:
			box(g, Vector3(sx * 6.82, y0 + 1.8, z), Vector3(0.06, 3.0, 2.3), kc(GOLD * 0.8, K_LATTICE))
	# Beams round the column heads.
	painted_beam(g, Vector3(0, y0 + col_h + 0.25, 6.0), 16.6, 0.5, 0.34, field)
	painted_beam(g, Vector3(0, y0 + col_h + 0.25, -6.0), 16.6, 0.5, 0.34, field)
	var saved := g.xf
	g.xf = saved * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	painted_beam(g, Vector3(0, y0 + col_h + 0.25, 8.0), 12.6, 0.5, 0.34, field)
	painted_beam(g, Vector3(0, y0 + col_h + 0.25, -8.0), 12.6, 0.5, 0.34, field)
	g.xf = saved
	var r1 := y0 + col_h + 0.5
	sweep_roof(g, Vector3(0, r1, 0), 8.2, 6.2, 1.6, 1.6, 1.4, 0.7, tile, ridge, field, false, 14, 4)
	# The upper storey and its roof.
	var y1 := r1 + 0.8
	box(g, Vector3(0, y1 + 1.7, 0), Vector3(11.0, 3.4, 7.4), kc(DEEP_RED, K_PAINT))
	for i in 4:
		var x := -4.0 + float(i) * 2.66
		box(g, Vector3(x, y1 + 1.8, 3.72), Vector3(1.8, 1.9, 0.05), kc(GOLD * 0.8, K_LATTICE))
		box(g, Vector3(x, y1 + 1.8, -3.72), Vector3(1.8, 1.9, 0.05), kc(GOLD * 0.8, K_LATTICE))
	box(g, Vector3(0, y1 + 3.0, 3.85), Vector3(6.0, 0.8, 0.12), kc(BOARDS[1], K_SIGN))
	text(g, Chinatown.HALL_NAME, Vector3(0, y1 + 3.0, 3.93), 0.42, 5.4, kc(GOLD, K_INK))
	painted_beam(g, Vector3(0, y1 + 3.6, 3.75), 11.2, 0.4, 0.2, FIELDS[1])
	painted_beam(g, Vector3(0, y1 + 3.6, -3.75), 11.2, 0.4, 0.2, FIELDS[1])
	var r2 := y1 + 3.8
	sweep_roof(g, Vector3(0, r2, 0), 5.6, 3.8, 1.3, 1.3, 1.2, 0.6, tile, ridge, field, false, 12, 4)
	var y2 := r2 + 0.7
	box(g, Vector3(0, y2 + 1.2, 0), Vector3(6.4, 2.4, 4.4), kc(DEEP_RED, K_PAINT))
	for sx: float in [-1.0, 1.0]:
		box(g, Vector3(sx * 1.6, y2 + 1.25, 2.22), Vector3(2.4, 1.5, 0.05), kc(GOLD * 0.8, K_LATTICE))
	painted_beam(g, Vector3(0, y2 + 2.55, 2.25), 6.6, 0.3, 0.15, field)
	var r3 := y2 + 2.7
	sweep_roof(g, Vector3(0, r3, 0), 3.2, 2.2, 1.2, 1.2, 2.0, 0.75, tile, ridge, field, true, 12, 5)
	# The finial.
	var fy := r3 + 2.0 + 0.4
	g.cylinder(KEY, Vector3(0, fy, 0), 0.3, 0.4, 10, kc(GOLD, K_GOLD))
	g.cylinder(KEY, Vector3(0, fy + 0.4, 0), 0.12, 1.2, 8, kc(GOLD, K_GOLD), 0.04)
	# Lanterns along the first roof's front eave.
	for i in 6:
		var x := -7.0 + float(i) * 2.8
		lantern(g, Vector3(x, r1 - 0.2, 7.0), 0.15, 0.75, LANTERN_RED, float(i) * 0.61)


static func _pond(g: ChinatownGeo, st: Dictionary, world: Transform3D) -> void:
	var r := 5.2
	var n := 16
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		beam(g, p0 + Vector3(0, 0.25, 0), p1 + Vector3(0, 0.25, 0), 0.55, 0.5, kc(GRANITE, K_STONE))
		g.tri(KEY, Vector3(0, 0.3, 0), p0 * 0.97 + Vector3(0, 0.3, 0), p1 * 0.97 + Vector3(0, 0.3, 0), Vector3.UP,
			Vector2(0, 0), Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), kc(Color(0.1, 0.2, 0.2), K_WATER))
	# A heap of rocks in the middle and a small stone lantern.
	for k in 5:
		var a := float(k) * 1.9
		box(g, Vector3(cos(a) * 0.8, 0.5 + 0.15 * float(k % 2), sin(a) * 0.8), Vector3(1.0, 0.7 + 0.2 * float(k % 3), 0.9), kc(GRANITE * 0.8, K_STONE), Basis(Vector3.UP, a))
	box(g, Vector3(0, 1.3, 0), Vector3(0.5, 1.0, 0.5), kc(GRANITE, K_STONE))
	box(g, Vector3(0, 1.95, 0), Vector3(0.9, 0.3, 0.9), kc(GRANITE * 0.9, K_STONE))
	_shape(st, world, Vector3(0, 0.25, 0), Vector3(r * 2.0, 0.5, r * 2.0))
