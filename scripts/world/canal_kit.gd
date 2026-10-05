class_name CanalKit
extends RefCounted
## The canal neighbourhood's hardware (Canals), built in code at real size: the arched footbridge
## with its white railings and lantern posts, the timber dock with its steps, the rowboat, the
## kayak and the canoe, fences, the porch lantern. Meshes that do not depend on where they stand
## (the bridge, the dock, the boats, the lantern) are built once and instanced through the chunk's
## batch, one draw per kind a chunk; fences and railings are written straight into the chunk's
## per-material meshes (Canals' accumulator).
##
## Every writer here winds its faces itself (front = counter-clockwise as seen, Godot's rule) and
## sets flat normals, so nothing depends on SurfaceTool.generate_normals() over a chunk.

## The dock stands this far from the canal's centre line (its middle), the boat beside it at BOAT_O.
const DOCK_O := 5.2
const BOAT_O := 3.25
## The footbridge: half its length between the walks it lands on, its deck width, and how far the
## crown of its arch stands over the walk.
const BRIDGE_HALF := 9.6
const BRIDGE_W := 2.5
const BRIDGE_RISE := 1.7
const RAIL_H := 1.05

const WHITE := Color(0.94, 0.94, 0.91)
const IRON := Color(0.10, 0.11, 0.11)
const DECK := Color(0.80, 0.79, 0.76)

static var _cache: Dictionary = {}


# =================================================================================================
# Low-level writers
# =================================================================================================

## A box from a transform of the unit cube (centred), flat normals, vertex colour `col`.
static func obox(st: SurfaceTool, xf: Transform3D, col: Color, skip_bottom: bool = false) -> void:
	var c := [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)]
	var faces := [[0, 1, 2, 3, Vector3(0, 0, -1)], [5, 4, 7, 6, Vector3(0, 0, 1)], [4, 0, 3, 7, Vector3(-1, 0, 0)],
		[1, 5, 6, 2, Vector3(1, 0, 0)], [3, 2, 6, 7, Vector3(0, 1, 0)], [4, 5, 1, 0, Vector3(0, -1, 0)]]
	for f: Array in faces:
		if skip_bottom and (f[4] as Vector3).y < -0.5:
			continue
		var p: Array = []
		for k in 4:
			p.append(xf * (c[int(f[k])] as Vector3))
		var n: Vector3 = (xf.basis * (f[4] as Vector3)).normalized()
		quad(st, p[0], p[1], p[2], p[3], n, col)


## A quad a-b-c-d whose front faces `n`.
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	tri(st, a, b, c, n, col)
	tri(st, a, c, d, n, col)


## A triangle whose front faces `n` (rewound if it does not), UV in metres.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	var ax := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	var u := n.cross(ax).normalized()
	var v := n.cross(u)
	for p: Vector3 in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(p.dot(u), p.dot(v)))
		st.add_vertex(p)


## A box standing between y0 and y1 along the 2D segment a-b (world XZ), `t` thick.
static func wall_box(st: SurfaceTool, a: Vector2, b: Vector2, y0: float, y1: float, t: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var mid := (a + b) * 0.5
	var basis := Basis(Vector3.UP, atan2(-d.y, d.x)).scaled(Vector3(len, y1 - y0, t))
	obox(st, Transform3D(basis, Vector3(mid.x, (y0 + y1) * 0.5, mid.y)), col, true)


## A square post at `p`.
static func post(st: SurfaceTool, p: Vector2, y: float, h: float, w: float, col: Color) -> void:
	obox(st, Transform3D(Basis().scaled(Vector3(w, h, w)), Vector3(p.x, y + h * 0.5, p.y)), col, true)
	# A cap a little wider.
	obox(st, Transform3D(Basis().scaled(Vector3(w + 0.04, 0.04, w + 0.04)), Vector3(p.x, y + h + 0.02, p.y)), col)


## Collision faces of a box along the segment centred `mid`, spanning `span`, `t` thick.
static func box_faces(mid: Vector2, span: Vector2, t: float, y0: float, y1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var len := span.length()
	if len < 0.01:
		return out
	var xf := Transform3D(Basis(Vector3.UP, atan2(-span.y, span.x)).scaled(Vector3(len, y1 - y0, t)), Vector3(mid.x, (y0 + y1) * 0.5, mid.y))
	var c := [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)]
	for f: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7]]:
		var p: Array = []
		for k in 4:
			p.append(xf * (c[int(f[k])] as Vector3))
		out.append_array([p[0], p[1], p[2], p[0], p[2], p[3]])
	return out


# =================================================================================================
# Fences and railings (written into the chunk's meshes)
# =================================================================================================

## A painted railing: newel posts, a top rail, a bottom rail and square pickets between.
static func railing(st: SurfaceTool, a: Vector2, b: Vector2, y: float, h: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.2:
		return
	var n := maxi(1, ceili(len / 1.6))
	for k in n + 1:
		post(st, a.lerp(b, float(k) / n), y, h, 0.09, col)
	wall_box(st, a, b, y + h - 0.07, y + h, 0.08, col)
	wall_box(st, a, b, y + 0.1, y + 0.16, 0.05, col)
	var pk := maxi(1, int(len / 0.13))
	for k in pk:
		var p := a.lerp(b, (float(k) + 0.5) / pk)
		obox(st, Transform3D(Basis().scaled(Vector3(0.025, h - 0.23, 0.025)), Vector3(p.x, y + 0.16 + (h - 0.23) * 0.5, p.y)), col, true)


## A white picket fence: posts every couple of metres, two rails behind, pointed pickets.
static func picket_fence(st: SurfaceTool, a: Vector2, b: Vector2, y: float, h: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.2:
		return
	var dir := d / len
	var side := Vector2(-dir.y, dir.x)
	var n := maxi(1, ceili(len / 2.2))
	for k in n + 1:
		post(st, a.lerp(b, float(k) / n) + side * 0.03, y, h + 0.1, 0.085, col)
	for ry: float in [0.22, h - 0.25]:
		wall_box(st, a + side * 0.05, b + side * 0.05, y + ry, y + ry + 0.07, 0.035, col)
	var pk := maxi(1, int(len / 0.135))
	var yaw := atan2(-d.y, d.x)
	for k in pk:
		var p := a.lerp(b, (float(k) + 0.5) / pk) - side * 0.005
		var basis := Basis(Vector3.UP, yaw)
		obox(st, Transform3D(basis.scaled(Vector3(0.075, h - 0.06, 0.018)), Vector3(p.x, y + (h - 0.06) * 0.5 + 0.02, p.y)), col, true)
		# The point: two sloped faces.
		var top := Vector3(p.x, y + h + 0.05, p.y)
		var l := Vector3(p.x, y + h - 0.04, p.y) - Vector3(dir.x, 0.0, dir.y) * 0.0375
		var r := Vector3(p.x, y + h - 0.04, p.y) + Vector3(dir.x, 0.0, dir.y) * 0.0375
		var off := Vector3(side.x, 0.0, side.y) * 0.009
		tri(st, l + off, r + off, top + off, Vector3(side.x, 0.0, side.y), col)
		tri(st, l - off, r - off, top - off, -Vector3(side.x, 0.0, side.y), col)


## A low stucco garden wall with a cap.
static func low_wall(st: SurfaceTool, a: Vector2, b: Vector2, y: float, h: float, t: float, col: Color) -> void:
	wall_box(st, a, b, y - 0.05, y + h, t, col)
	wall_box(st, a, b, y + h, y + h + 0.05, t + 0.06, col.lerp(Color(0.92, 0.9, 0.86), 0.5))


## A modern fence of horizontal slats on square steel posts.
static func glass_rail(st: SurfaceTool, a: Vector2, b: Vector2, y: float, h: float, col: Color) -> void:
	var len := (b - a).length()
	if len < 0.2:
		return
	var n := maxi(1, ceili(len / 1.8))
	for k in n + 1:
		obox(st, Transform3D(Basis().scaled(Vector3(0.06, h, 0.06)), Vector3(a.lerp(b, float(k) / n).x, y + h * 0.5, a.lerp(b, float(k) / n).y)), col, true)
	var slat := Color(0.50, 0.36, 0.25)
	var rows := int(h / 0.11)
	for r in rows:
		var sy := y + 0.08 + r * 0.11
		wall_box(st, a, b, sy, sy + 0.08, 0.025, slat)


## A timber board fence: a panel per bay between posts, a cap rail on top.
static func board_fence(st: SurfaceTool, a: Vector2, b: Vector2, y: float, h: float, col: Color) -> void:
	var len := (b - a).length()
	if len < 0.2:
		return
	var n := maxi(1, ceili(len / 2.4))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		obox(st, Transform3D(Basis().scaled(Vector3(0.09, h + 0.05, 0.09)), Vector3(p.x, y + (h + 0.05) * 0.5, p.y)), col.darkened(0.15), true)
	wall_box(st, a, b, y + 0.04, y + h - 0.04, 0.025, col)
	wall_box(st, a, b, y + h - 0.04, y + h + 0.02, 0.09, col.darkened(0.1))


# =================================================================================================
# The porch lantern
# =================================================================================================

## A wall lantern: a black iron box with glass sides, the glass glowing after dark. Two surfaces
## (iron, glow), built once.
static func lantern_mesh() -> Mesh:
	if _cache.has("lantern"):
		return _cache.lantern
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Back plate, arm, cage, roof, finial: the lantern faces +X.
	obox(iron, Transform3D(Basis().scaled(Vector3(0.03, 0.30, 0.14)), Vector3(-0.015, 0.0, 0.0)), IRON)
	obox(iron, Transform3D(Basis().scaled(Vector3(0.12, 0.03, 0.03)), Vector3(0.06, 0.05, 0.0)), IRON)
	obox(iron, Transform3D(Basis().scaled(Vector3(0.17, 0.025, 0.17)), Vector3(0.14, -0.12, 0.0)), IRON)
	obox(iron, Transform3D(Basis().scaled(Vector3(0.20, 0.03, 0.20)), Vector3(0.14, 0.10, 0.0)), IRON)
	obox(iron, Transform3D(Basis().scaled(Vector3(0.10, 0.05, 0.10)), Vector3(0.14, 0.14, 0.0)), IRON)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			obox(iron, Transform3D(Basis().scaled(Vector3(0.018, 0.21, 0.018)), Vector3(0.14 + cx * 0.075, -0.01, cz * 0.075)), IRON)
	obox(glow, Transform3D(Basis().scaled(Vector3(0.14, 0.2, 0.14)), Vector3(0.14, -0.01, 0.0)), Color(1.0, 0.86, 0.6))
	var mesh := ArrayMesh.new()
	iron.commit(mesh)
	glow.commit(mesh)
	mesh.surface_set_material(0, Canals.material("iron"))
	mesh.surface_set_material(1, Canals.material("glow"))
	_cache.lantern = mesh
	return mesh


## A porch light by the door at `at` (world XZ, y ignored), facing `dir` along x (+1 or -1): the
## lantern on the wall and, when it is `on`, its pool of light on the garden path.
static func add_porch_light(ch: CityChunk, at: Vector3, dir: float, on: bool) -> void:
	var y := Canals.LAWN_Y + YardFill.LIFT + HouseKit.FLOOR_LIFT + 2.05
	var yaw := 0.0 if dir > 0.0 else PI
	ch._batch.add("canal_lantern", lantern_mesh(), Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.z)), Color.WHITE)
	ch._batch.set_draw_distance("canal_lantern", Canals.FENCE_DRAW)
	if on:
		var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(4.5, 1.0, 4.5)), Vector3(at.x + dir * 1.4, Canals.LAWN_Y + 0.09, at.z))
		ch._batch.add("canal_porch_pool", PropFactory.light_pool(Color(1.0, 0.80, 0.52), 0.55), pool)
		ch._batch.set_no_shadow("canal_porch_pool")


# =================================================================================================
# The footbridge
# =================================================================================================

## The deck's height over the walk at `x` (metres from the middle, across the canal).
static func deck_y(x: float) -> float:
	var t := clampf(absf(x) / BRIDGE_HALF, 0.0, 1.0)
	# A segmental arch eased into the walks: flat at the landings, round over the water.
	return BRIDGE_RISE * (1.0 - t * t) * (1.0 - 0.25 * t * t * (1.0 - t))


## The arch's soffit at `x`: an elliptical arch springing from the bank tops.
static func soffit_y(x: float) -> float:
	var spring := Canals.COPE_IN
	if absf(x) >= spring:
		return Canals.BANK_TOP_Y - Canals.WALK_Y - 0.25
	var top := deck_y(0.0) - 0.34
	var base := Canals.BANK_TOP_Y - Canals.WALK_Y - 0.25
	return base + (top - base) * sqrt(1.0 - pow(x / spring, 2.0))


## The whole bridge in its own frame (x across the canal, z along it, y 0 the walk): spandrels and
## soffit in white-painted stucco, the deck in concrete, railings and their newels white, two
## lantern posts on diagonal corners. Built once.
static func bridge_mesh() -> Mesh:
	if _cache.has("bridge"):
		return _cache.bridge
	var stucco := SurfaceTool.new()
	stucco.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
	var hw := BRIDGE_W * 0.5
	var fw := hw + 0.18
	for i in n:
		var x0 := -BRIDGE_HALF + 2.0 * BRIDGE_HALF * float(i) / n
		var x1 := -BRIDGE_HALF + 2.0 * BRIDGE_HALF * float(i + 1) / n
		var y0 := deck_y(x0)
		var y1 := deck_y(x1)
		var s0 := soffit_y(x0)
		var s1 := soffit_y(x1)
		var up := Vector3(-(y1 - y0), x1 - x0, 0.0).normalized()
		# Deck top (concrete), between the kerbs.
		quad(deck, Vector3(x0, y0, -hw), Vector3(x1, y1, -hw), Vector3(x1, y1, hw), Vector3(x0, y0, hw), up, DECK)
		# The kerbs: a low upstand along each edge the railing stands on.
		for sz: float in [-1.0, 1.0]:
			var zi := sz * hw
			var zo := sz * fw
			quad(stucco, Vector3(x0, y0 + 0.12, zi), Vector3(x1, y1 + 0.12, zi), Vector3(x1, y1 + 0.12, zo), Vector3(x0, y0 + 0.12, zo), up, WHITE)
			quad(stucco, Vector3(x0, y0, zi), Vector3(x1, y1, zi), Vector3(x1, y1 + 0.12, zi), Vector3(x0, y0 + 0.12, zi), Vector3(0, 0, -sz), WHITE)
			# The spandrel face, from the kerb top down to the soffit.
			quad(stucco, Vector3(x0, y0 + 0.12, zo), Vector3(x1, y1 + 0.12, zo), Vector3(x1, s1, zo), Vector3(x0, s0, zo), Vector3(0, 0, sz), WHITE)
		# The soffit underneath.
		var down := Vector3(s1 - s0, -(x1 - x0), 0.0).normalized()
		quad(stucco, Vector3(x0, s0, -fw), Vector3(x1, s1, -fw), Vector3(x1, s1, fw), Vector3(x0, s0, fw), down, WHITE.darkened(0.05))
	# End faces of the abutments at the landings.
	for sx: float in [-1.0, 1.0]:
		var x := sx * BRIDGE_HALF
		quad(stucco, Vector3(x, 0.12, -fw), Vector3(x, 0.12, fw), Vector3(x, soffit_y(x), fw), Vector3(x, soffit_y(x), -fw), Vector3(sx, 0, 0), WHITE)
	# Railings: newels at the ends and every few metres, a top rail and a bottom rail following the
	# arch in short runs, pickets.
	for sz: float in [-1.0, 1.0]:
		var z := sz * (hw + 0.09)
		var m := 14
		for i in m:
			var x0 := -BRIDGE_HALF + 0.15 + (2.0 * BRIDGE_HALF - 0.3) * float(i) / m
			var x1 := -BRIDGE_HALF + 0.15 + (2.0 * BRIDGE_HALF - 0.3) * float(i + 1) / m
			var b0 := deck_y(x0) + 0.12
			var b1 := deck_y(x1) + 0.12
			_rail(paint, Vector3(x0, b0 + RAIL_H - 0.12, z), Vector3(x1, b1 + RAIL_H - 0.12, z), 0.09, 0.07, WHITE)
			_rail(paint, Vector3(x0, b0 + 0.12, z), Vector3(x1, b1 + 0.12, z), 0.05, 0.05, WHITE)
			var pk := 9
			for k in pk:
				var px := lerpf(x0, x1, (float(k) + 0.5) / pk)
				var py := deck_y(px) + 0.12
				obox(paint, Transform3D(Basis().scaled(Vector3(0.028, RAIL_H - 0.3, 0.028)), Vector3(px, py + 0.15 + (RAIL_H - 0.3) * 0.5, z)), WHITE, true)
		for i in 5:
			var px := lerpf(-BRIDGE_HALF + 0.15, BRIDGE_HALF - 0.15, float(i) / 4.0)
			var py := deck_y(px) + 0.12
			obox(paint, Transform3D(Basis().scaled(Vector3(0.13, RAIL_H + 0.06, 0.13)), Vector3(px, py + (RAIL_H + 0.06) * 0.5, z)), WHITE, true)
			obox(paint, Transform3D(Basis().scaled(Vector3(0.17, 0.05, 0.17)), Vector3(px, py + RAIL_H + 0.08, z)), WHITE)
	# Two lantern posts on diagonal corners, outside the railing at the landings.
	for corner: Vector2 in [Vector2(-BRIDGE_HALF + 0.35, -(fw + 0.2)), Vector2(BRIDGE_HALF - 0.35, fw + 0.2)]:
		_lamp_post(iron, glow, Vector3(corner.x, deck_y(corner.x) - 0.02, corner.y))
	var mesh := ArrayMesh.new()
	var mats := []
	for pair: Array in [[stucco, "stucco"], [deck, "cope"], [paint, "paint"], [iron, "iron"], [glow, "glow"]]:
		var s: SurfaceTool = pair[0]
		if pair[1] != "glow":
			s.generate_tangents()
		s.commit(mesh)
		mats.append(pair[1])
	for i in mats.size():
		mesh.surface_set_material(i, Canals.material(mats[i]))
	_cache.bridge = mesh
	return mesh


## A rail of `w` x `h` section from a to b.
static func _rail(st: SurfaceTool, a: Vector3, b: Vector3, w: float, h: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var yaw := atan2(-d.z, d.x)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch)
	obox(st, Transform3D(basis * Basis().scaled(Vector3(len + 0.02, h, w)), (a + b) * 0.5), col)


## A cast-iron lantern post: a fluted base, a slim shaft, a lantern head with glowing glass.
static func _lamp_post(iron: SurfaceTool, glow: SurfaceTool, at: Vector3) -> void:
	obox(iron, Transform3D(Basis().scaled(Vector3(0.28, 0.45, 0.28)), at + Vector3(0, 0.225, 0)), IRON)
	obox(iron, Transform3D(Basis().scaled(Vector3(0.20, 0.10, 0.20)), at + Vector3(0, 0.50, 0)), IRON)
	obox(iron, Transform3D(Basis().scaled(Vector3(0.09, 2.5, 0.09)), at + Vector3(0, 1.75, 0)), IRON)
	obox(iron, Transform3D(Basis().scaled(Vector3(0.24, 0.04, 0.24)), at + Vector3(0, 3.02, 0)), IRON)
	obox(glow, Transform3D(Basis().scaled(Vector3(0.26, 0.38, 0.26)), at + Vector3(0, 3.23, 0)), Color(1.0, 0.86, 0.6))
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			obox(iron, Transform3D(Basis().scaled(Vector3(0.025, 0.40, 0.025)), at + Vector3(cx * 0.135, 3.23, cz * 0.135)), IRON)
	# A pyramid roof and a finial.
	var r := 0.2
	var top := at + Vector3(0, 3.62, 0)
	var base := at.y + 3.43
	var pts := [Vector3(at.x - r, base, at.z - r), Vector3(at.x + r, base, at.z - r), Vector3(at.x + r, base, at.z + r), Vector3(at.x - r, base, at.z + r)]
	for k in 4:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % 4]
		var nrm := (b - a).cross(top - a).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		tri(iron, a, b, top, nrm, IRON)
	obox(iron, Transform3D(Basis().scaled(Vector3(0.04, 0.12, 0.04)), top + Vector3(0, 0.05, 0)), IRON)


## The lantern posts' lamp height over the walk (for the real light and the pools).
const LAMP_HEAD := 3.23


## A footbridge across the canal at `at` (its middle on the centre line), `axis` the canal's
## (0: runs along z, the bridge spans x). Instanced from bridge_mesh(); collision for the deck and
## the railings into the canal ground; a light pool under each lantern and one real light.
static func add_bridge(ch: CityChunk, at: Vector2, axis: int, seed_value: int) -> void:
	var basis := Basis() if axis == 0 else Basis(Vector3.UP, -PI * 0.5)
	var xf := Transform3D(basis, Vector3(at.x, Canals.WALK_Y + ch._gy(at.x, at.y), at.y))
	ch._batch.add("canal_bridge", bridge_mesh(), xf, Color.WHITE)
	ch._batch.set_draw_distance("canal_bridge", Canals.BRIDGE_DRAW)
	var faces := Canals._acc(ch).faces
	var n := 16
	var hw := BRIDGE_W * 0.5 + 0.18
	for i in n:
		var x0 := -BRIDGE_HALF + 2.0 * BRIDGE_HALF * float(i) / n
		var x1 := -BRIDGE_HALF + 2.0 * BRIDGE_HALF * float(i + 1) / n
		var a := xf * Vector3(x0, deck_y(x0), -hw)
		var b := xf * Vector3(x1, deck_y(x1), -hw)
		var c := xf * Vector3(x1, deck_y(x1), hw)
		var d := xf * Vector3(x0, deck_y(x0), hw)
		faces.append_array([a, b, c, a, c, d])
		# The railings as walls.
		for sz: float in [-1.0, 1.0]:
			var z := sz * (BRIDGE_W * 0.5 + 0.09)
			var p0 := xf * Vector3(x0, deck_y(x0), z)
			var p1 := xf * Vector3(x1, deck_y(x1), z)
			var q0 := p0 + Vector3(0, RAIL_H + 0.12, 0)
			var q1 := p1 + Vector3(0, RAIL_H + 0.12, 0)
			faces.append_array([p0, p1, q1, p0, q1, q0])
	for corner: Vector2 in [Vector2(-BRIDGE_HALF + 0.35, -(hw + 0.2)), Vector2(BRIDGE_HALF - 0.35, hw + 0.2)]:
		var head := xf * Vector3(corner.x, deck_y(corner.x) + LAMP_HEAD, corner.y)
		var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(9.0, 1.0, 9.0)), Vector3(head.x, Canals.WALK_Y + 0.09, head.z))
		ch._batch.add("canal_bridge_pool", PropFactory.light_pool(Color(1.0, 0.82, 0.55), 0.8), pool)
	ch._batch.set_no_shadow("canal_bridge_pool")
	# One real light per bridge, over its crown, for the people and the water under it.
	var light := OmniLight3D.new()
	light.position = xf * Vector3(0.0, deck_y(0.0) + 2.6, 0.0)
	light.omni_range = 12.0
	light.omni_attenuation = 1.3
	light.light_color = Color(1.0, 0.84, 0.6)
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 50.0
	light.distance_fade_length = 15.0
	light.add_to_group("lamp_light")
	ch.add_child(light)


# =================================================================================================
# The dock
# =================================================================================================

const DOCK_Y := Canals.WATER_Y + 0.3


## A small timber dock in its own frame (+x out over the water, z along the bank, y world): a
## deck of boards on four pilings, steps up the bank to the walk, a handrail on the steps.
static func dock_mesh() -> Mesh:
	if _cache.has("dock"):
		return _cache.dock
	var timber := SurfaceTool.new()
	timber.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.58, 0.45, 0.33)
	# The deck: boards across it.
	var boards := 20
	for k in boards:
		var z := -1.6 + 3.2 * (float(k) + 0.5) / boards
		var tone := wood.darkened(0.08 * float(absi(hash([k, "board"])) % 3))
		obox(timber, Transform3D(Basis().scaled(Vector3(1.7, 0.05, 3.2 / boards - 0.012)), Vector3(0.0, DOCK_Y - 0.025, z)), tone)
	# Bearers under the boards and the pilings.
	for z: float in [-1.4, 0.0, 1.4]:
		obox(timber, Transform3D(Basis().scaled(Vector3(1.75, 0.12, 0.1)), Vector3(0.0, DOCK_Y - 0.11, z)), wood.darkened(0.25))
	for cx: float in [-0.78, 0.78]:
		for cz: float in [-1.5, 1.5]:
			obox(timber, Transform3D(Basis().scaled(Vector3(0.16, DOCK_Y + 0.55 - Canals.FLOOR_Y, 0.16)), Vector3(cx, (DOCK_Y + 0.55 + Canals.FLOOR_Y) * 0.5, cz)), wood.darkened(0.35))
	# Steps up the bank, from the deck's landward edge to the coping (x from 0.85 to 2.3).
	var steps := 4
	var x0 := 0.85
	var x1 := 2.35
	var y0 := DOCK_Y
	var y1 := Canals.COPE_Y
	for k in steps:
		var tx := lerpf(x0, x1, (float(k) + 0.5) / steps)
		var ty := lerpf(y0, y1, float(k + 1) / (steps + 1))
		obox(timber, Transform3D(Basis().scaled(Vector3((x1 - x0) / steps + 0.04, 0.05, 1.0)), Vector3(tx, ty - 0.025, 0.0)), wood)
	for sz: float in [-0.52, 0.52]:
		# Stringers.
		var a := Vector3(x0, y0 - 0.1, sz)
		var b := Vector3(x1, y1 - 0.06, sz)
		_rail(timber, a, b, 0.05, 0.22, wood.darkened(0.2))
	# A handrail on one side of the steps.
	_rail(paint, Vector3(x0 + 0.1, y0 + 0.9, 0.55), Vector3(x1, y1 + 0.9, 0.55), 0.05, 0.05, WHITE)
	for t: float in [0.1, 0.95]:
		var px := lerpf(x0 + 0.1, x1, t)
		var py := lerpf(y0, y1, t)
		obox(paint, Transform3D(Basis().scaled(Vector3(0.05, 0.9, 0.05)), Vector3(px, py + 0.45, 0.55)), WHITE)
	# Cleats on the water edge.
	for cz: float in [-1.1, 1.1]:
		obox(paint, Transform3D(Basis().scaled(Vector3(0.06, 0.05, 0.22)), Vector3(-0.78, DOCK_Y + 0.025, cz)), IRON)
	var mesh := ArrayMesh.new()
	timber.generate_tangents()
	timber.commit(mesh)
	paint.commit(mesh)
	mesh.surface_set_material(0, Canals.material("timber"))
	mesh.surface_set_material(1, Canals.material("paint"))
	_cache.dock = mesh
	return mesh


## A dock at `p` (its middle, world XZ) for a lot fronting the canal toward `dir` (+-1 along x):
## the dock reaches out toward the canal's middle, its boat moored beside it.
static func add_dock(ch: CityChunk, p: Vector2, dir: float, seed_value: int) -> void:
	# The dock's +x points out over the water: toward the canal's centre, which is `dir` from the lot.
	var basis := Basis() if dir < 0.0 else Basis(Vector3.UP, PI)
	# Its frame's x 0 is the deck's middle; the canal centre is DOCK_O further on.
	var xf := Transform3D(basis, Vector3(p.x, 0.0, p.y))
	ch._batch.add("canal_dock", dock_mesh(), xf, Color.WHITE)
	ch._batch.set_draw_distance("canal_dock", Canals.BOAT_DRAW)
	var faces := Canals._acc(ch).faces
	var c0 := xf * Vector3(-0.85, DOCK_Y, -1.6)
	var c1 := xf * Vector3(0.85, DOCK_Y, -1.6)
	var c2 := xf * Vector3(0.85, DOCK_Y, 1.6)
	var c3 := xf * Vector3(-0.85, DOCK_Y, 1.6)
	faces.append_array([c0, c1, c2, c0, c2, c3])
	var s0 := xf * Vector3(0.85, DOCK_Y, -0.5)
	var s1 := xf * Vector3(2.35, Canals.COPE_Y, -0.5)
	var s2 := xf * Vector3(2.35, Canals.COPE_Y, 0.5)
	var s3 := xf * Vector3(0.85, DOCK_Y, 0.5)
	faces.append_array([s0, s1, s2, s0, s2, s3])
	# The boat alongside, on the water side of the dock, lying along the canal.
	var boat := xf * Vector3(-(DOCK_O - BOAT_O), Canals.WATER_Y, 0.15)
	add_boat(ch, boat, PI * 0.5, seed_value)
	# Now and then a kayak pulled up onto the deck, upside down.
	if Canals._h01([seed_value, "kayak_on_dock"]) < 0.3:
		var kxf := Transform3D(Basis(Vector3.UP, PI * 0.5 + (0.0 if dir < 0.0 else PI)) * Basis(Vector3.RIGHT, PI) * Basis().scaled(Vector3(0.82, 0.82, 0.82)), xf * Vector3(0.2, DOCK_Y + 0.16, 0.0))
		ch._batch.add("canal_boat_1", boat_mesh(1), kxf, Color.WHITE, paint_for(1, seed_value ^ 5))


# =================================================================================================
# Boats
# =================================================================================================

const BOAT_NAMES := ["rowboat", "kayak", "canoe"]
## Hull paints per kind (sRGB; the shader takes the instance colour onto the painted parts only).
const ROWBOAT_PAINTS := [Color(0.93, 0.93, 0.90), Color(0.20, 0.42, 0.52), Color(0.62, 0.16, 0.13), Color(0.16, 0.26, 0.20), Color(0.86, 0.80, 0.62), Color(0.30, 0.55, 0.62)]
const KAYAK_PAINTS := [Color(0.90, 0.28, 0.10), Color(0.95, 0.72, 0.10), Color(0.12, 0.45, 0.75), Color(0.22, 0.62, 0.30), Color(0.85, 0.15, 0.20), Color(0.95, 0.95, 0.92)]
const CANOE_PAINTS := [Color(0.20, 0.38, 0.22), Color(0.66, 0.18, 0.12), Color(0.86, 0.56, 0.18), Color(0.18, 0.30, 0.48), Color(0.75, 0.60, 0.42)]


static func paint_for(kind: int, seed_value: int) -> Color:
	var arr: Array = [ROWBOAT_PAINTS, KAYAK_PAINTS, CANOE_PAINTS][kind]
	return arr[absi(hash([seed_value, "boat_paint"])) % arr.size()]


## A boat of a kind picked from `seed_value` at `at` (y the waterline), `yaw` about up (its length
## runs along its local x).
static func add_boat(ch: CityChunk, at: Vector3, yaw: float, seed_value: int) -> void:
	var r := Canals._h01([seed_value, "boat_kind"])
	var kind := 0 if r < 0.45 else (1 if r < 0.78 else 2)
	var jitter := (Canals._h01([seed_value, "boat_yaw"]) - 0.5) * 0.12
	var xf := Transform3D(Basis(Vector3.UP, yaw + jitter), at + Vector3(0.0, ch._gy(at.x, at.z), 0.0))
	ch._batch.add("canal_boat_%d" % kind, boat_mesh(kind), xf, Color.WHITE, paint_for(kind, seed_value))
	ch._batch.set_draw_distance("canal_boat_%d" % kind, Canals.BOAT_DRAW)
	# Something to stand on (and to stop a body sinking through it).
	var dims := [Vector2(3.7, 1.3), Vector2(3.9, 0.66), Vector2(4.8, 0.9)][kind] as Vector2
	var faces := Canals._acc(ch).faces
	var corners: Array = []
	for c: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		corners.append(xf * Vector3(c.x * dims.x * 0.8, 0.18, c.y * dims.y * 0.8))
	faces.append_array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]])


## The hull's half-breadth, keel and sheer at `t` (0 stern .. 1 bow), per kind.
static func _hull(kind: int, t: float) -> Vector3:
	match kind:
		0:
			# Rowboat: a transom stern, the beam forward of the middle, a raked stem.
			var b := 0.0
			if t < 0.45:
				b = lerpf(0.48, 0.65, smoothstep(0.0, 1.0, t / 0.45))
			else:
				b = 0.65 * sqrt(maxf(0.0, 1.0 - pow((t - 0.45) / 0.55, 2.0)))
			var keel := lerpf(-0.12, -0.21, smoothstep(0.0, 0.35, t)) + 0.32 * pow(maxf(0.0, (t - 0.72) / 0.28), 2.0)
			var sheer := 0.34 + 0.12 * pow(maxf(0.0, (t - 0.55) / 0.45), 2.0) + 0.03 * (1.0 - t)
			return Vector3(maxf(b, 0.012), keel, sheer)
		1:
			# Kayak: long, narrow, pointed both ends, a low deck.
			var b := 0.33 * pow(sin(PI * t), 0.75)
			var keel := -0.11 + 0.10 * pow(absf(t - 0.5) * 2.0, 3.0)
			var sheer := 0.10 + 0.05 * pow(absf(t - 0.5) * 2.0, 2.0)
			return Vector3(maxf(b, 0.01), keel, sheer)
		_:
			# Canoe: pointed both ends, the sheer sweeping up at the tips.
			var b := 0.45 * pow(sin(PI * t), 0.6)
			var keel := -0.15 + 0.12 * pow(absf(t - 0.5) * 2.0, 4.0)
			var sheer := 0.26 + 0.24 * pow(absf(t - 0.5) * 2.0, 3.0)
			return Vector3(maxf(b, 0.012), keel, sheer)


static func _section(hv: Vector3, k: int, kk: int, sgn: float, inner: float) -> Vector2:
	# k 0 the keel, kk the sheer. A flattish bottom turning up through the bilge to the topsides.
	var th := float(k) / float(kk) * PI * 0.5
	var x := hv.x * pow(sin(th), 0.75) * sgn
	var y := hv.y + (hv.z - hv.y) * pow(1.0 - cos(th), 1.15)
	if inner > 0.0:
		x *= 1.0 - inner / maxf(hv.x, 0.05)
		y += inner * (1.0 - float(k) / float(kk))
	return Vector2(x, y)


## A boat hull and its fittings, length along local x (bow +x), y 0 the waterline. Vertex alpha 0
## marks paint (the instance colour takes it), 1 a fixed colour. Built once per kind.
static func boat_mesh(kind: int) -> Mesh:
	var key := "boat_%d" % kind
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := [3.7, 3.9, 4.8][kind] as float
	var ns := 22
	var kk := 6
	var paint := Color(1, 1, 1, 0)
	var wood := Color(0.62, 0.47, 0.32, 1)
	var inside := wood if kind == 0 else Color(0.85, 0.85, 0.82, 0) if kind == 2 else Color(0.08, 0.08, 0.08, 1)
	var trim := Color(0.45, 0.32, 0.2, 1) if kind != 1 else Color(0.1, 0.1, 0.1, 1)
	var stations: Array = []
	for i in ns + 1:
		var t := float(i) / ns
		stations.append([t, -L * 0.5 + L * t, _hull(kind, t)])
	# Outer and inner skins.
	for skin: int in [0, 1]:
		var inset := 0.0 if skin == 0 else 0.03
		if skin == 1 and kind == 1:
			continue
		for i in ns:
			var sa: Array = stations[i]
			var sb: Array = stations[i + 1]
			for sgn: float in [-1.0, 1.0]:
				for k in kk:
					var pa0 := _section(sa[2], k, kk, sgn, inset)
					var pa1 := _section(sa[2], k + 1, kk, sgn, inset)
					var pb0 := _section(sb[2], k, kk, sgn, inset)
					var pb1 := _section(sb[2], k + 1, kk, sgn, inset)
					var a := Vector3(sa[1], pa0.y, pa0.x)
					var b := Vector3(sb[1], pb0.y, pb0.x)
					var c := Vector3(sb[1], pb1.y, pb1.x)
					var d := Vector3(sa[1], pa1.y, pa1.x)
					var mid := (a + b + c + d) * 0.25
					var out := Vector3(0.0, -0.4, sgn).normalized()
					var nrm := (b - a).cross(d - a).normalized()
					if nrm.dot(out) < 0.0:
						nrm = -nrm
					if skin == 1:
						nrm = -nrm
					# The waterline stripe: a darker band where the hull meets the water.
					var col := paint
					if skin == 0 and kind != 1 and mid.y < 0.03 and mid.y > -0.04:
						col = Color(0.12, 0.12, 0.12, 1)
					elif skin == 0 and mid.y < -0.04 and kind == 0:
						col = Color(0.32, 0.14, 0.10, 1)
					elif skin == 1:
						col = inside
					quad(st, a, b, c, d, nrm, col)
		# The gunwale cap between the skins (open boats).
	if kind != 1:
		for i in ns:
			var sa: Array = stations[i]
			var sb: Array = stations[i + 1]
			for sgn: float in [-1.0, 1.0]:
				var o0 := _section(sa[2], kk, kk, sgn, 0.0)
				var o1 := _section(sb[2], kk, kk, sgn, 0.0)
				var i0 := _section(sa[2], kk, kk, sgn, 0.03)
				var i1 := _section(sb[2], kk, kk, sgn, 0.03)
				quad(st, Vector3(sa[1], o0.y + 0.02, o0.x), Vector3(sb[1], o1.y + 0.02, o1.x), Vector3(sb[1], i1.y + 0.02, i1.x), Vector3(sa[1], i0.y + 0.02, i0.x), Vector3.UP, trim)
				# Its outer face, a rubbing strake.
				quad(st, Vector3(sa[1], o0.y + 0.02, o0.x), Vector3(sb[1], o1.y + 0.02, o1.x), Vector3(sb[1], o1.y - 0.04, o1.x * 1.01), Vector3(sa[1], o0.y - 0.04, o0.x * 1.01), Vector3(0, 0, sgn), trim)
	if kind == 0:
		# The transom: a flat board closing the stern.
		var s0: Array = stations[0]
		for k in kk:
			for sgn: float in [-1.0, 1.0]:
				var p0 := _section(s0[2], k, kk, sgn, 0.0)
				var p1 := _section(s0[2], k + 1, kk, sgn, 0.0)
				tri(st, Vector3(s0[1], p0.y, p0.x), Vector3(s0[1], p1.y, p1.x), Vector3(s0[1], (s0[2] as Vector3).y, 0.0), Vector3(-1, 0, 0), paint)
				tri(st, Vector3(s0[1] + 0.03, p0.y, p0.x * 0.95), Vector3(s0[1] + 0.03, p1.y, p1.x * 0.95), Vector3(s0[1] + 0.03, (s0[2] as Vector3).y + 0.03, 0.0), Vector3(1, 0, 0), wood)
		# Thwarts, a stern seat, the oars lying in the boat, rowlocks.
		for tx: float in [-0.25, 0.55]:
			var hv := _hull(0, (tx + L * 0.5) / L)
			obox(st, Transform3D(Basis().scaled(Vector3(0.24, 0.035, hv.x * 1.9)), Vector3(tx, hv.z - 0.13, 0.0)), wood)
		var hs := _hull(0, 0.08)
		obox(st, Transform3D(Basis().scaled(Vector3(0.5, 0.035, hs.x * 1.85)), Vector3(-L * 0.5 + 0.45, hs.z - 0.13, 0.0)), wood)
		for sz: float in [-0.16, 0.18]:
			obox(st, Transform3D(Basis(Vector3.UP, sz * 0.15).scaled(Vector3(2.6, 0.035, 0.05)), Vector3(0.05, 0.08, sz)), wood.lightened(0.1))
			obox(st, Transform3D(Basis().scaled(Vector3(0.5, 0.012, 0.13)), Vector3(1.15, 0.081, sz)), wood.lightened(0.1))
		for sgn: float in [-1.0, 1.0]:
			var hv := _hull(0, (0.15 + L * 0.5) / L)
			obox(st, Transform3D(Basis().scaled(Vector3(0.04, 0.08, 0.04)), Vector3(0.15, hv.z + 0.06, sgn * (hv.x - 0.02))), Color(0.15, 0.15, 0.15, 1))
	elif kind == 1:
		# The deck: a crowned surface from sheer to sheer, open over the cockpit.
		for i in ns:
			var sa: Array = stations[i]
			var sb: Array = stations[i + 1]
			var t := (float(sa[0]) + float(sb[0])) * 0.5
			var cockpit := t > 0.40 and t < 0.62
			for sgn: float in [-1.0, 1.0]:
				var ha: Vector3 = sa[2]
				var hb: Vector3 = sb[2]
				var oa := Vector3(sa[1], ha.z, ha.x * sgn)
				var ob := Vector3(sb[1], hb.z, hb.x * sgn)
				var ca := Vector3(sa[1], ha.z + ha.x * 0.25, 0.0)
				var cb := Vector3(sb[1], hb.z + hb.x * 0.25, 0.0)
				if cockpit:
					ca = Vector3(sa[1], ha.z + 0.02, ha.x * sgn * 0.55)
					cb = Vector3(sb[1], hb.z + 0.02, hb.x * sgn * 0.55)
				quad(st, oa, ob, cb, ca, Vector3(0, 1, sgn * 0.3).normalized(), paint)
				if cockpit:
					# The coaming, a black lip round the opening.
					quad(st, ca, cb, cb + Vector3(0, 0.05, 0), ca + Vector3(0, 0.05, 0), Vector3(0, 0, sgn), trim)
		# The opening's floor, dark, and a seat back.
		var c0 := -L * 0.5 + L * 0.40
		var c1 := -L * 0.5 + L * 0.62
		var hm := _hull(1, 0.51)
		quad(st, Vector3(c0, hm.z - 0.06, -hm.x * 0.5), Vector3(c1, hm.z - 0.06, -hm.x * 0.5), Vector3(c1, hm.z - 0.06, hm.x * 0.5), Vector3(c0, hm.z - 0.06, hm.x * 0.5), Vector3.UP, Color(0.05, 0.05, 0.05, 1))
		obox(st, Transform3D(Basis().scaled(Vector3(0.05, 0.16, hm.x * 0.9)), Vector3(c0 + 0.18, hm.z + 0.02, 0.0)), Color(0.12, 0.12, 0.12, 1))
		# Deck lines and a hatch.
		obox(st, Transform3D(Basis().scaled(Vector3(0.3, 0.025, 0.22)), Vector3(c0 - 0.55, _hull(1, 0.26).z + 0.07, 0.0)), Color(0.1, 0.1, 0.1, 1))
	else:
		# Canoe: two seats, a centre thwart, cane decks at the tips.
		for t: float in [0.2, 0.5, 0.8]:
			var hv := _hull(2, t)
			var w := 0.035 if t == 0.5 else 0.22
			obox(st, Transform3D(Basis().scaled(Vector3(w, 0.03, hv.x * 1.88)), Vector3(-L * 0.5 + L * t, hv.z - (0.03 if t == 0.5 else 0.09), 0.0)), wood)
		for t: float in [0.04, 0.96]:
			var hv := _hull(2, t)
			obox(st, Transform3D(Basis().scaled(Vector3(0.28, 0.02, hv.x * 1.6 + 0.05)), Vector3(-L * 0.5 + L * t + (0.1 if t < 0.5 else -0.1), hv.z - 0.02, 0.0)), wood)
		# A paddle in the bottom.
		obox(st, Transform3D(Basis().scaled(Vector3(1.4, 0.025, 0.035)), Vector3(0.1, -0.08, 0.1)), wood.lightened(0.1))
		obox(st, Transform3D(Basis().scaled(Vector3(0.5, 0.012, 0.18)), Vector3(0.9, -0.08, 0.1)), wood.lightened(0.1))
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/canal_boat.gdshader")
	mesh.surface_set_material(0, mat)
	_cache[key] = mesh
	return mesh
