class_name FarmersMarketKit
extends RefCounted
## The farmers' market's hardware and goods (FarmersMarket), built here in code at real size on one
## shader (shaders/farmers_market.gdshader): the 10 x 10 ft pop-up canopy (telescoping square
## aluminium legs, scissor trusses under the eaves, rafters to a centre hub, a peaked canvas roof
## with a valance, sandbags on the feet) and the same canopy folded; 6 ft folding tables under a
## cloth with wooden crates tilted to the front and heaped with produce - tomatoes, heirlooms,
## oranges, lemons, avocados, apples, peaches, peppers, strawberries in green pint baskets, lettuce,
## kale, carrots, squash - or buckets of flowers on a stepped stand, bread on boards and racks,
## jars of honey and jam, egg cartons; the stock and cardboard boxes behind; the packed-up stacks;
## removable bollards and the market's sign.
##
## What a face is rides in the vertex colour's alpha (code / 20, the C_* constants), the colour in
## its rgb (sRGB), roughness and metal in UV2; the shader decodes and works in linear. A canopy's
## canvas takes the instance's custom colour. Every mesh carries a coarse level as its one LOD
## (Geo: the near triangles are the surface, the far ones its LOD at FAR_EDGE), so a batch of
## tables a street away draws crates and heaps, not every apple.

const C_FIXED := 0.0
const C_METAL := 2.0
const C_CANVAS := 4.0
const C_PRODUCE := 6.0
const C_GLASS := 7.0
const C_WOOD := 8.0
const C_CARD := 9.0
const C_CLOTH := 10.0
const C_BULB := 12.0
const C_LEAF := 14.0
const C_CHALK := 16.0
const C_CRUST := 18.0
const C_PAINT := 20.0

## The LOD switch (metres of error): about 40 m at 1080 rows.
const FAR_EDGE := 0.06

## The canopy: half its side, the eave (leg top) and the peak.
const HALF := 1.525
const EAVE := 2.18
const PEAK := 2.98
const VALANCE := 0.24

## Canvas colours a canopy can be (instance custom rgb; 0 is the common white).
const CANVAS := [Color(0.93, 0.93, 0.91), Color(0.2, 0.32, 0.52), Color(0.24, 0.4, 0.28), Color(0.62, 0.18, 0.14),
	Color(0.78, 0.7, 0.55), Color(0.86, 0.72, 0.3)]
## Variants of each stall kind's goods table (FarmersMarket.Kind order).
const VARIANTS := [6, 2, 2, 2]
## The table, its front edge and height (local: canopy centre on the ground, +z the aisle).
const TABLE := Vector3(1.83, 0.74, 0.76)
const TABLE_Z := 0.92

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/farmers_market.gdshader")
	return _material


# --- The builder --------------------------------------------------------------------------------

## Packed arrays for one surface with two index lists: the near triangles (the surface) and the
## far ones (its LOD). `mode` says where the next triangles go: 0 both, 1 near only, 2 far only.
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var near := PackedInt32Array()
	var far := PackedInt32Array()
	var mode: int = 0

	func vert(p: Vector3, nn: Vector3, col: Color, t: Vector2, rm: Vector2) -> int:
		v.append(p)
		n.append(nn)
		c.append(col)
		uv.append(t)
		uv2.append(rm)
		return v.size() - 1

	func index(a: int, b: int, d: int) -> void:
		if mode != 2:
			near.append(a)
			near.append(b)
			near.append(d)
		if mode != 1:
			far.append(a)
			far.append(b)
			far.append(d)

	## A flat triangle turned to face `want`, UVs in metres off the dominant axis.
	func tri(a: Vector3, b: Vector3, d: Vector3, want: Vector3, col: Color, rm: Vector2) -> void:
		var cr := (b - a).cross(d - a)
		if cr.length_squared() < 1e-14:
			return
		if cr.dot(want) > 0.0:
			var t := b
			b = d
			d = t
			cr = -cr
		var nn := -cr.normalized()
		var i0 := vert(a, nn, col, _proj(a, nn), rm)
		var i1 := vert(b, nn, col, _proj(b, nn), rm)
		var i2 := vert(d, nn, col, _proj(d, nn), rm)
		index(i0, i1, i2)

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, want: Vector3, col: Color, rm: Vector2) -> void:
		tri(a, b, d, want, col, rm)
		tri(a, d, e, want, col, rm)

	static func _proj(p: Vector3, nn: Vector3) -> Vector2:
		var an := nn.abs()
		if an.y >= an.x and an.y >= an.z:
			return Vector2(p.x, p.z)
		if an.x >= an.z:
			return Vector2(p.z, -p.y)
		return Vector2(p.x, -p.y)

	## A box through `xf` (unit cube [-0.5, 0.5] scaled by `size`).
	func box(xf: Transform3D, size: Vector3, col: Color, rm: Vector2, skip_bottom: bool = true) -> void:
		var h := size * 0.5
		var cs := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
			Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
		var p: Array[Vector3] = []
		for q: Vector3 in cs:
			p.append(xf * q)
		var bx := xf.basis
		quad(p[4], p[5], p[6], p[7], bx * Vector3.BACK, col, rm)
		quad(p[1], p[0], p[3], p[2], bx * Vector3.FORWARD, col, rm)
		quad(p[5], p[1], p[2], p[6], bx * Vector3.RIGHT, col, rm)
		quad(p[0], p[4], p[7], p[3], bx * Vector3.LEFT, col, rm)
		quad(p[3], p[7], p[6], p[2], bx * Vector3.UP, col, rm)
		if not skip_bottom:
			quad(p[0], p[1], p[5], p[4], bx * Vector3.DOWN, col, rm)

	## An axis box from its centre.
	func abox(centre: Vector3, size: Vector3, col: Color, rm: Vector2) -> void:
		box(Transform3D(Basis(), centre), size, col, rm)

	## A square bar of side `w` from `a` to `b`.
	func bar(a: Vector3, b: Vector3, w: float, col: Color, rm: Vector2) -> void:
		var d := b - a
		var length := d.length()
		if length < 0.001:
			return
		var y := d / length
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, length, w), col, rm, false)

	## A round tube from `a` to `b`, smooth sides, open ends.
	func tube(a: Vector3, b: Vector3, r: float, sides: int, col: Color, rm: Vector2) -> void:
		var d := b - a
		if d.length_squared() < 1e-10:
			return
		var y := d.normalized()
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		var z := y.cross(x).normalized()
		var base := v.size()
		for k in sides + 1:
			var t := TAU * float(k) / float(sides)
			var dir := x * cos(t) + z * sin(t)
			vert(a + dir * r, dir, col, Vector2(float(k) / sides, 0.0), rm)
			vert(b + dir * r, dir, col, Vector2(float(k) / sides, d.length()), rm)
		for k in sides:
			var i := base + k * 2
			_oriented(i, i + 2, i + 1, x * cos(TAU * (k + 0.5) / sides) + z * sin(TAU * (k + 0.5) / sides))
			_oriented(i + 1, i + 2, i + 3, x * cos(TAU * (k + 0.5) / sides) + z * sin(TAU * (k + 0.5) / sides))

	## A capped upright cylinder (or frustum) on `base`.
	func cyl(base: Vector3, r0: float, r1: float, h: float, sides: int, col: Color, rm: Vector2, cap: bool = true) -> void:
		var start := v.size()
		for k in sides + 1:
			var t := TAU * float(k) / float(sides)
			var dir := Vector3(cos(t), 0.0, sin(t))
			var nn := (dir * h + Vector3.UP * (r0 - r1)).normalized()
			vert(base + dir * r0, nn, col, Vector2(t * r0, 0.0), rm)
			vert(base + dir * r1 + Vector3(0, h, 0), nn, col, Vector2(t * r1, h), rm)
		for k in sides:
			var i := start + k * 2
			var out := Vector3(cos(TAU * (k + 0.5) / sides), 0.0, sin(TAU * (k + 0.5) / sides))
			_oriented(i, i + 2, i + 1, out)
			_oriented(i + 1, i + 2, i + 3, out)
		if cap and r1 > 0.0:
			var top := base + Vector3(0, h, 0)
			for k in sides:
				var t0 := TAU * float(k) / float(sides)
				var t1 := TAU * float(k + 1) / float(sides)
				tri(top, top + Vector3(cos(t0), 0, sin(t0)) * r1, top + Vector3(cos(t1), 0, sin(t1)) * r1, Vector3.UP, col, rm)

	## An ellipsoid of radii `r` through `xf`, smooth, `seg` round and `rings` from pole to pole;
	## `squash` flattens the bottom (a fruit sitting in a heap), `bump` (0..1) dents it in lobes.
	func ellipsoid(xf: Transform3D, r: Vector3, seg: int, rings: int, col: Color, rm: Vector2, lobes: int = 0, bump: float = 0.0, taper: float = 0.0, phi_max: float = PI) -> void:
		var start := v.size()
		var nb := xf.basis.inverse().transposed()
		for j in rings + 1:
			var phi := phi_max * float(j) / float(rings)
			var sy := cos(phi)
			var sr := sin(phi)
			for k in seg + 1:
				var t := TAU * float(k) / float(seg)
				var lobe := 1.0 - bump * (0.5 - 0.5 * cos(t * float(lobes))) if lobes > 0 else 1.0
				# Taper: a pear (avocado) or an egg - wider low, narrower high.
				var w := sr * lobe * (1.0 - taper * sy)
				var p := Vector3(cos(t) * w * r.x, sy * r.y, sin(t) * w * r.z)
				var nn := Vector3(cos(t) * w / r.x, sy / r.y, sin(t) * w / r.z).normalized()
				vert(xf * p, (nb * nn).normalized(), col, Vector2(float(k) / seg, float(j) / rings), rm)
		for j in rings:
			for k in seg:
				var i := start + j * (seg + 1) + k
				var a := i
				var b := i + 1
				var d := i + seg + 1
				var e := i + seg + 2
				# Outward winding for this parametrisation (a, d, b), (b, d, e).
				index(a, d, b)
				index(b, d, e)

	func _oriented(a: int, b: int, d: int, want: Vector3) -> void:
		var cr := (v[b] - v[a]).cross(v[d] - v[a])
		if cr.dot(want) > 0.0:
			index(a, d, b)
		else:
			index(a, b, d)

	## The mesh: the near triangles as the surface, the far as its one LOD.
	func commit(lod_edge: float = 0.06) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = near
		var lods := {}
		if not far.is_empty() and far.size() < near.size():
			lods[lod_edge] = far
			# A copy of the last level at an edge nothing reaches, so the renderer's triangle
			# counter treats this batch like every other LOD'd one (CLAUDE.md, measurement trap 3).
			lods[1000.0] = far
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
		mesh.surface_set_material(0, FarmersMarketKit.material())
		# The far level casts the shadow (a batch's lighter twin, PropFactory.shadow_proxy()).
		if lods.has(lod_edge):
			var sarr := arrays.duplicate()
			sarr[Mesh.ARRAY_INDEX] = far
			var shadow := ArrayMesh.new()
			shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sarr)
			shadow.surface_set_material(0, FarmersMarketKit.material())
			PropFactory._shadow_proxies[mesh] = shadow
		return mesh


static func col(rgb: Color, code: float) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, code / 20.0)


static func _jit(rng: RandomNumberGenerator, base: Color, amount: float) -> Color:
	return Color(clampf(base.r * (1.0 + rng.randf_range(-amount, amount)), 0.0, 1.0),
		clampf(base.g * (1.0 + rng.randf_range(-amount, amount)), 0.0, 1.0),
		clampf(base.b * (1.0 + rng.randf_range(-amount, amount)), 0.0, 1.0))


# --- The canopy -------------------------------------------------------------------------------

## The 10 x 10 ft pop-up canopy, up: origin on the ground under its centre, +z the front.
static func canopy() -> Mesh:
	if _meshes.has("canopy"):
		return _meshes.canopy
	var g := Geo.new()
	var alu := col(Color(0.74, 0.75, 0.77), C_METAL)
	var rm_alu := Vector2(0.38, 0.9)
	var canvas := col(Color.WHITE, C_CANVAS)
	var rm_canvas := Vector2(0.82, 0.0)
	var dark := col(Color(0.06, 0.06, 0.065), C_FIXED)
	var rm_plastic := Vector2(0.6, 0.0)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for cc: Vector2 in corners:
		var x := cc.x * (HALF - 0.02)
		var z := cc.y * (HALF - 0.02)
		g.mode = 1
		# Telescoping leg: the thicker outer tube below, the inner above, the slider and the
		# height pin, the foot plate.
		g.bar(Vector3(x, 0.02, z), Vector3(x, 1.28, z), 0.038, alu, rm_alu)
		g.bar(Vector3(x, 1.2, z), Vector3(x, EAVE, z), 0.031, alu, rm_alu)
		g.abox(Vector3(x, 1.27, z), Vector3(0.05, 0.05, 0.05), dark, rm_plastic)
		g.abox(Vector3(x, 0.006, z), Vector3(0.12, 0.012, 0.12), alu, rm_alu)
		g.abox(Vector3(x, EAVE - 0.03, z), Vector3(0.06, 0.08, 0.06), dark, rm_plastic)
		g.abox(Vector3(x, 1.86, z), Vector3(0.055, 0.06, 0.055), dark, rm_plastic)
		g.mode = 2
		g.bar(Vector3(x, 0.0, z), Vector3(x, EAVE, z), 0.05, alu, rm_alu)
		g.mode = 1
		# A sandbag weight slumped round the foot.
		var bag := Transform3D(Basis(Vector3.UP, atan2(cc.x, cc.y)), Vector3(x - cc.x * 0.06, 0.06, z - cc.y * 0.06))
		g.ellipsoid(bag, Vector3(0.17, 0.07, 0.1), 8, 4, col(Color(0.36, 0.33, 0.24), C_CLOTH), Vector2(0.95, 0.0))
	# The scissor trusses under the eaves: two bays a side, an X in each.
	g.mode = 1
	for side in 4:
		var a: Vector2 = corners[side] * (HALF - 0.02)
		var b: Vector2 = corners[(side + 1) % 4] * (HALF - 0.02)
		for bay in 2:
			var p0 := a.lerp(b, bay * 0.5)
			var p1 := a.lerp(b, bay * 0.5 + 0.5)
			g.bar(Vector3(p0.x, EAVE - 0.02, p0.y), Vector3(p1.x, 1.88, p1.y), 0.02, alu, rm_alu)
			g.bar(Vector3(p0.x, 1.88, p0.y), Vector3(p1.x, EAVE - 0.02, p1.y), 0.02, alu, rm_alu)
		var m := a.lerp(b, 0.5)
		g.abox(Vector3(m.x, 2.03, m.y), Vector3(0.04, 0.04, 0.04), dark, rm_plastic)
	# Rafters from each corner to the hub, and the hub's post.
	for cc: Vector2 in corners:
		g.bar(Vector3(cc.x * (HALF - 0.03), EAVE, cc.y * (HALF - 0.03)), Vector3(0, PEAK - 0.08, 0), 0.022, alu, rm_alu)
	g.bar(Vector3(0, 2.25, 0), Vector3(0, PEAK - 0.02, 0), 0.03, alu, rm_alu)
	g.abox(Vector3(0, PEAK - 0.08, 0), Vector3(0.1, 0.07, 0.1), dark, rm_plastic)
	# The roof: four faces from the eave to the peak, sagging a little between the rafters.
	var peak := Vector3(0, PEAK, 0)
	var steps := 5
	for side in 4:
		var a2: Vector2 = corners[side] * (HALF + 0.02)
		var b2: Vector2 = corners[(side + 1) % 4] * (HALF + 0.02)
		var a := Vector3(a2.x, EAVE + 0.01, a2.y)
		var b := Vector3(b2.x, EAVE + 0.01, b2.y)
		var mid := (a + b) * 0.5
		var outward := Vector3(mid.x, 0.0, mid.z).normalized() + Vector3.UP * 0.9
		var grid: Array = []
		for i in steps + 1:
			var row: Array = []
			var r := float(i) / steps
			for j in steps + 1:
				var s := float(j) / steps
				var e := a.lerp(b, s)
				var p := e.lerp(peak, r)
				# Sag: deepest mid-face, none at the rafters (the face's edges) and the peak.
				var sag := 0.06 * sin(PI * s) * sin(PI * minf(r * 1.15, 1.0)) * (1.0 - r)
				p.y -= sag
				row.append(p)
			grid.append(row)
		for i in steps:
			for j in steps:
				g.quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j], outward, canvas, rm_canvas)
		# The valance: a flat drop round the eave, with a hem.
		var lo_a := a - Vector3(0, VALANCE, 0)
		var lo_b := b - Vector3(0, VALANCE, 0)
		g.quad(a, b, lo_b, lo_a, Vector3(mid.x, 0, mid.z), canvas, rm_canvas)
	# The far roof: four triangles and the valance band.
	g.mode = 2
	for side in 4:
		var a2: Vector2 = corners[side] * (HALF + 0.02)
		var b2: Vector2 = corners[(side + 1) % 4] * (HALF + 0.02)
		var a := Vector3(a2.x, EAVE, a2.y)
		var b := Vector3(b2.x, EAVE, b2.y)
		var mid := (a + b) * 0.5
		g.tri(a, b, peak, Vector3(mid.x, 0.0, mid.z).normalized() + Vector3.UP, canvas, rm_canvas)
		g.quad(a, b, b - Vector3(0, VALANCE, 0), a - Vector3(0, VALANCE, 0), Vector3(mid.x, 0, mid.z), canvas, rm_canvas)
	g.mode = 0
	var mesh := g.commit(0.1)
	_meshes.canopy = mesh
	return mesh


## The canopy folded: legs together, the trusses closed into a bundle of parallel bars, the canvas
## bunched over the top; it stands on its feet beside the packed tables. Origin on the ground.
static func canopy_folded() -> Mesh:
	if _meshes.has("canopy_folded"):
		return _meshes.canopy_folded
	var g := Geo.new()
	var alu := col(Color(0.74, 0.75, 0.77), C_METAL)
	var rm_alu := Vector2(0.38, 0.9)
	var dark := col(Color(0.06, 0.06, 0.065), C_FIXED)
	var canvas := col(Color.WHITE, C_CANVAS)
	var h := 1.62
	g.mode = 1
	for i in 4:
		var x := 0.11 * (1.0 if i % 2 == 0 else -1.0)
		var z := 0.11 * (1.0 if i < 2 else -1.0)
		g.bar(Vector3(x, 0.02, z), Vector3(x, h, z), 0.038, alu, Vector2(0.4, 0.9))
		g.abox(Vector3(x, 0.006, z), Vector3(0.12, 0.012, 0.12), alu, Vector2(0.4, 0.9))
	# The closed trusses: bars side by side between the legs.
	for k in 6:
		var o := -0.08 + 0.032 * k
		g.bar(Vector3(o, 0.35, 0.11), Vector3(o, h - 0.05, 0.11), 0.02, alu, Vector2(0.4, 0.9))
		g.bar(Vector3(0.11, 0.35, o), Vector3(0.11, h - 0.05, o), 0.02, alu, Vector2(0.4, 0.9))
	# The canvas left on the frame: gathered at the hub on top and hanging down the bundle in deep
	# folds to about half its height, a strap round it.
	g.ellipsoid(Transform3D(Basis(), Vector3(0, h + 0.03, 0)), Vector3(0.2, 0.08, 0.19), 10, 4, canvas, Vector2(0.85, 0.0), 6, 0.2)
	g.cyl(Vector3(0, h * 0.5, 0), 0.24, 0.2, h * 0.5 + 0.02, 14, canvas, Vector2(0.85, 0.0), false)
	g.cyl(Vector3(0, h * 0.5 - 0.06, 0), 0.25, 0.24, 0.06, 14, canvas, Vector2(0.85, 0.0), false)
	g.cyl(Vector3(0, h * 0.72, 0), 0.215, 0.215, 0.04, 12, dark, Vector2(0.6, 0.0), false)
	g.mode = 2
	g.abox(Vector3(0, h * 0.5, 0), Vector3(0.3, h, 0.3), alu, Vector2(0.4, 0.9))
	g.abox(Vector3(0, h - 0.25, 0), Vector3(0.45, 0.6, 0.45), canvas, Vector2(0.85, 0.0))
	g.mode = 0
	# Its wheeled carry bag, empty, folded flat against its foot.
	g.box(Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0.0, 0.42, -0.3)), Vector3(0.42, 0.8, 0.05), col(Color(0.12, 0.16, 0.13), C_CLOTH), Vector2(0.85, 0.0))
	var mesh := g.commit(0.06)
	_meshes.canopy_folded = mesh
	return mesh


# --- Tables and goods -------------------------------------------------------------------------

## A folding table with its cloth, in the goods' frame: origin on the ground under the table's
## middle, +z the front. `cloth` [colour, gingham].
static func _table(g: Geo, at: Vector3, size: Vector3, cloth: Array) -> void:
	var top := at.y + size.y
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var cl: Color = cloth[0]
	var cc := col(cl, C_CLOTH)
	var rm := Vector2(0.92, 1.0 if bool(cloth[1]) else 0.0)
	# The top under the cloth, the folding legs.
	g.abox(Vector3(at.x, top - 0.02, at.z), Vector3(size.x, 0.04, size.z), col(Color(0.82, 0.82, 0.8), C_FIXED), Vector2(0.5, 0.0))
	var steel := col(Color(0.2, 0.2, 0.21), C_METAL)
	g.mode = 1
	for sx: float in [-1.0, 1.0]:
		g.bar(Vector3(at.x + sx * (hx - 0.12), at.y, at.z - hz + 0.06), Vector3(at.x + sx * (hx - 0.12), top - 0.04, at.z - hz + 0.06), 0.025, steel, Vector2(0.5, 0.6))
		g.bar(Vector3(at.x + sx * (hx - 0.12), at.y, at.z + hz - 0.06), Vector3(at.x + sx * (hx - 0.12), top - 0.04, at.z + hz - 0.06), 0.025, steel, Vector2(0.5, 0.6))
	g.mode = 0
	# The cloth: over the top, down the front nearly to the ground, down the sides a little; hung
	# a centimetre proud with a soft fold line at the front edge.
	var f := 0.012
	var y0 := at.y + 0.07
	g.quad(Vector3(at.x - hx - f, top + 0.002, at.z - hz), Vector3(at.x + hx + f, top + 0.002, at.z - hz), Vector3(at.x + hx + f, top + 0.002, at.z + hz + f), Vector3(at.x - hx - f, top + 0.002, at.z + hz + f), Vector3.UP, cc, rm)
	var folds := 7
	for k in folds:
		var u0 := lerpf(-hx - f, hx + f, float(k) / folds)
		var u1 := lerpf(-hx - f, hx + f, float(k + 1) / folds)
		var um := (u0 + u1) * 0.5
		var z0 := at.z + hz + f
		var bulge := 0.018
		g.quad(Vector3(at.x + u0, top + 0.002, z0), Vector3(at.x + um, top + 0.002, z0 + 0.004), Vector3(at.x + um, y0, z0 + bulge), Vector3(at.x + u0, y0, z0), Vector3(0.3, 0, 1).normalized(), cc, rm)
		g.quad(Vector3(at.x + um, top + 0.002, z0 + 0.004), Vector3(at.x + u1, top + 0.002, z0), Vector3(at.x + u1, y0, z0), Vector3(at.x + um, y0, z0 + bulge), Vector3(-0.3, 0, 1).normalized(), cc, rm)
	for sx: float in [-1.0, 1.0]:
		var x := at.x + sx * (hx + f)
		g.quad(Vector3(x, top + 0.002, at.z - hz), Vector3(x, top + 0.002, at.z + hz + f), Vector3(x, top - 0.3, at.z + hz + f), Vector3(x, top - 0.3, at.z - hz), Vector3(sx, 0, 0), cc, rm)


## A wooden slatted crate: open top, slats with gaps on the long sides, solid ends with hand holes.
## `xf` puts its bottom centre; `size` outside. Far: a plain box.
static func _crate(g: Geo, xf: Transform3D, size: Vector3, wood: Color) -> void:
	var w := col(wood, C_WOOD)
	var rm := Vector2(0.85, 0.0)
	var h := size * 0.5
	var t := 0.012
	g.mode = 1
	# Bottom.
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.008, 0)), Vector3(size.x - t, 0.016, size.z - t), w, rm)
	# Long sides: three slats with gaps.
	var slat := size.y / 2.5
	for sz: float in [-1.0, 1.0]:
		for k in 2:
			var y := slat * 0.5 + k * slat * 1.45
			g.box(xf * Transform3D(Basis(), Vector3(0, y, sz * (h.z - t * 0.5))), Vector3(size.x, slat, t), w, rm, false)
	# Ends, a little thicker, and the corner posts.
	for sx: float in [-1.0, 1.0]:
		g.box(xf * Transform3D(Basis(), Vector3(sx * (h.x - t), size.y * 0.5, 0)), Vector3(t * 2.0, size.y, size.z), w.darkened(0.08), rm, false)
	g.mode = 2
	g.box(xf * Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)), size, w, rm)
	g.mode = 0


## What a crate can hold: [radii (x, y, z), colours, shape, code, roughness]. Shapes: "sphere",
## "oval", "pear" (avocado), "lobed" (heirloom tomato, peach cleft), "pepper", "leafy" (a head),
## "carrot", "basket" (strawberry pints), "squash", "bunch" (kale).
const GOODS := {
	"tomato": [Vector3(0.036, 0.031, 0.036), [Color(0.78, 0.09, 0.05), Color(0.72, 0.07, 0.04), Color(0.83, 0.16, 0.06)], "sphere", C_PRODUCE, 0.28],
	"heirloom": [Vector3(0.048, 0.034, 0.048), [Color(0.78, 0.12, 0.06), Color(0.9, 0.62, 0.12), Color(0.42, 0.1, 0.12), Color(0.52, 0.55, 0.15), Color(0.95, 0.42, 0.12)], "lobed", C_PRODUCE, 0.3],
	"orange": [Vector3(0.04, 0.038, 0.04), [Color(0.95, 0.45, 0.04), Color(0.92, 0.5, 0.06), Color(0.96, 0.4, 0.03)], "sphere", C_PRODUCE, 0.5],
	"lemon": [Vector3(0.033, 0.03, 0.043), [Color(0.95, 0.82, 0.12), Color(0.93, 0.78, 0.1), Color(0.9, 0.85, 0.2)], "oval", C_PRODUCE, 0.45],
	"avocado": [Vector3(0.036, 0.035, 0.052), [Color(0.12, 0.17, 0.06), Color(0.09, 0.12, 0.05), Color(0.2, 0.26, 0.08)], "pear", C_PRODUCE, 0.62],
	"apple": [Vector3(0.039, 0.035, 0.039), [Color(0.7, 0.07, 0.06), Color(0.62, 0.12, 0.05), Color(0.82, 0.3, 0.08), Color(0.55, 0.7, 0.2)], "lobed", C_PRODUCE, 0.35],
	"peach": [Vector3(0.039, 0.037, 0.039), [Color(0.95, 0.55, 0.25), Color(0.88, 0.32, 0.18), Color(0.96, 0.68, 0.32)], "lobed", C_PRODUCE, 0.7],
	"pepper": [Vector3(0.042, 0.048, 0.042), [Color(0.78, 0.08, 0.05), Color(0.15, 0.4, 0.08), Color(0.95, 0.72, 0.08), Color(0.92, 0.42, 0.05)], "pepper", C_PRODUCE, 0.2],
	"strawberry": [Vector3(0.012, 0.014, 0.012), [Color(0.82, 0.06, 0.08), Color(0.75, 0.05, 0.06)], "basket", C_PRODUCE, 0.35],
	"lettuce": [Vector3(0.09, 0.07, 0.09), [Color(0.36, 0.6, 0.16), Color(0.45, 0.66, 0.2), Color(0.3, 0.12, 0.14)], "leafy", C_LEAF, 0.7],
	"kale": [Vector3(0.05, 0.03, 0.17), [Color(0.12, 0.26, 0.12), Color(0.18, 0.32, 0.16), Color(0.22, 0.2, 0.26)], "bunch", C_LEAF, 0.75],
	"carrot": [Vector3(0.014, 0.014, 0.1), [Color(0.95, 0.42, 0.05), Color(0.92, 0.36, 0.04), Color(0.55, 0.12, 0.3)], "carrot", C_PRODUCE, 0.6],
	"squash": [Vector3(0.06, 0.055, 0.1), [Color(0.85, 0.62, 0.32), Color(0.2, 0.32, 0.12), Color(0.95, 0.55, 0.1)], "squash", C_PRODUCE, 0.55],
}

## The goods on each produce variant's crates (front table, four crates).
const PRODUCE_MIX := [
	["tomato", "heirloom", "pepper", "avocado"],
	["orange", "lemon", "avocado", "orange"],
	["lettuce", "kale", "carrot", "lettuce"],
	["strawberry", "peach", "apple", "strawberry"],
	["apple", "peach", "lemon", "heirloom"],
	["carrot", "squash", "tomato", "pepper"],
]
## Cloth per variant: [colour, gingham].
const CLOTHS := [[Color(0.16, 0.36, 0.2), false], [Color(0.62, 0.52, 0.36), false], [Color(0.9, 0.9, 0.88), false],
	[Color(0.7, 0.12, 0.1), true], [Color(0.18, 0.3, 0.55), true], [Color(0.24, 0.24, 0.26), false]]
const WOODS := [Color(0.66, 0.5, 0.32), Color(0.56, 0.42, 0.28), Color(0.72, 0.6, 0.42)]


## A heap of `kind` in a crate whose inside is `inner` (x, z) from `base` (crate floor, the crate's
## frame in `xf`), heaped to `rise` over the crate's rim at `rim`.
static func _heap(g: Geo, xf: Transform3D, inner: Vector2, rim: float, rise: float, kind: String, rng: RandomNumberGenerator) -> void:
	var spec: Array = GOODS[kind]
	var r: Vector3 = spec[0]
	var colors: Array = spec[1]
	var shape: String = spec[2]
	var code: float = spec[3]
	var rm := Vector2(float(spec[4]), 0.0)
	var mean: Color = colors[0]
	# Under the top layer: a dome in the goods' darker colour, so nothing shows the crate's floor.
	var fill := col(mean.darkened(0.35), code)
	var hx := inner.x * 0.5
	var hz := inner.y * 0.5
	var dome_top := rim + rise - r.y * 1.2
	var segs := 6
	g.mode = 0
	for i in segs:
		for j in segs:
			var pts: Array[Vector3] = []
			for q: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
				var u := lerpf(-hx, hx, float(q.x) / segs)
				var w := lerpf(-hz, hz, float(q.y) / segs)
				var d2 := (u / hx) * (u / hx) + (w / hz) * (w / hz)
				var y := lerpf(rim - 0.02, dome_top, clampf(1.0 - d2 * 0.5, 0.0, 1.0))
				pts.append(xf * Vector3(u, y, w))
			g.quad(pts[0], pts[1], pts[2], pts[3], xf.basis * Vector3.UP, fill, rm)
	g.mode = 1
	if shape == "basket":
		_berry_baskets(g, xf, inner, rim, rng)
		g.mode = 0
		return
	var step := maxf(r.x, r.z) * 2.0
	if shape == "bunch":
		step = r.x * 2.4
	elif shape == "carrot":
		step = 0.075
	var nx := maxi(1, int(inner.x / step))
	var nz := maxi(1, int(inner.y / (maxf(r.x, r.z) * 2.0 if shape != "bunch" and shape != "carrot" else r.z * 1.6)))
	for a in nx:
		for b in nz:
			var u := lerpf(-hx, hx, (float(a) + 0.5) / nx) + rng.randf_range(-0.2, 0.2) * step
			var w := lerpf(-hz, hz, (float(b) + 0.5) / nz) + rng.randf_range(-0.2, 0.2) * step
			u = clampf(u, -hx + r.x * 0.8, hx - r.x * 0.8)
			w = clampf(w, -hz + r.x * 0.8, hz - r.x * 0.8)
			var d2 := (u / hx) * (u / hx) + (w / hz) * (w / hz)
			var y := lerpf(rim - 0.02, rim + rise, clampf(1.0 - d2 * 0.5, 0.0, 1.0))
			var cl: Color = colors[rng.randi() % colors.size()]
			cl = _jit(rng, cl, 0.12)
			_item(g, xf, Vector3(u, y, w), r, shape, col(cl, code), rm, rng)
	# A second, sparser layer on the crown of the heap, so it reads as piled up.
	if shape != "bunch" and shape != "carrot" and shape != "leafy" and nx * nz < 30:
		for k in maxi(1, nx * nz / 6):
			var u := rng.randf_range(-hx * 0.55, hx * 0.55)
			var w := rng.randf_range(-hz * 0.5, hz * 0.5)
			var cl: Color = colors[rng.randi() % colors.size()]
			_item(g, xf, Vector3(u, rim + rise + r.y * 0.9, w), r, shape, col(_jit(rng, cl, 0.12), code), rm, rng)
	g.mode = 0


## One piece of produce at `p` (crate frame) of radii `r`.
static func _item(g: Geo, xf: Transform3D, p: Vector3, r: Vector3, shape: String, cl: Color, rm: Vector2, rng: RandomNumberGenerator) -> void:
	var yaw := rng.randf() * TAU
	var tilt := Basis(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.35)) if shape != "bunch" and shape != "carrot" else Basis()
	var b := xf.basis * Basis(Vector3.UP, yaw) * tilt
	var at := xf * p
	var stem := col(Color(0.22, 0.32, 0.1), C_LEAF)
	match shape:
		"sphere":
			g.ellipsoid(Transform3D(b, at), r, 6, 3, cl, rm, 0, 0.0, 0.0, 0.62 * PI)
		"oval":
			g.ellipsoid(Transform3D(b, at), r, 7, 3, cl, rm, 0, 0.0, 0.0, 0.62 * PI)
		"pear":
			g.ellipsoid(Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), at), Vector3(r.x, r.z, r.y), 6, 5, cl, rm, 0, 0.0, 0.28)
		"lobed":
			g.ellipsoid(Transform3D(b, at), r, 8, 3, cl, rm, 4, 0.1, 0.0, 0.62 * PI)
		"pepper":
			g.ellipsoid(Transform3D(b, at), r, 6, 3, cl, rm, 3, 0.18, 0.12, 0.62 * PI)
			g.bar(at + b * Vector3(0, r.y * 0.85, 0), at + b * Vector3(0.008, r.y * 1.25, 0), 0.01, stem, Vector2(0.7, 0))
		"leafy":
			# A head of lettuce: three crumpled shells, the outer ones open and a shade darker.
			for k in 3:
				var s := 1.0 - 0.18 * k
				var rr := Basis(Vector3.UP, k * 1.1) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
				g.ellipsoid(Transform3D(b * rr, at + b * Vector3(0, k * 0.012, 0)), r * Vector3(s, s * 0.95, s), 8, 3, Color(cl.r * (0.8 + 0.1 * k), cl.g * (0.82 + 0.09 * k), cl.b, cl.a), rm, 6, 0.22)
		"bunch":
			# A bunch of kale or chard laid along the crate, stems toward the front, tied.
			for k in 4:
				var off := Vector3(rng.randf_range(-r.x, r.x), 0.01 * k, rng.randf_range(-0.02, 0.02))
				var leaf := Basis(Vector3.UP, rng.randf_range(-0.25, 0.25))
				g.ellipsoid(Transform3D(xf.basis * leaf, at + xf.basis * off), Vector3(r.x * 0.75, r.y * 0.4, r.z), 7, 3, cl, rm, 7, 0.35)
			g.tube(at + xf.basis * Vector3(0, 0.02, r.z * 0.9), at + xf.basis * Vector3(0, 0.02, r.z * 1.45), 0.012, 5, col(Color(0.65, 0.7, 0.45), C_LEAF), rm)
		"carrot":
			# A bunch of carrots, tapering forward, the tops behind.
			for k in 4:
				var off := Vector3(rng.randf_range(-0.035, 0.035), rng.randf_range(0.0, 0.025), 0.0)
				var a := at + xf.basis * (off + Vector3(0, 0, r.z))
				var e := at + xf.basis * (off + Vector3(rng.randf_range(-0.01, 0.01), -0.006, -r.z * 0.9))
				_cone(g, a, e, r.x, cl, rm)
				g.tube(at + xf.basis * (off + Vector3(0, 0.004, r.z)), at + xf.basis * (off + Vector3(rng.randf_range(-0.03, 0.03), 0.03, r.z + 0.14)), 0.009, 4, col(Color(0.24, 0.45, 0.12), C_LEAF), Vector2(0.8, 0.0))
		"squash":
			g.ellipsoid(Transform3D(b, at), r, 7, 4, cl, rm, 0, 0.0, -0.2)
			g.bar(at + b * Vector3(0, 0, r.z * 0.95), at + b * Vector3(0, 0.01, r.z * 1.15), 0.014, col(Color(0.5, 0.45, 0.3), C_WOOD), Vector2(0.8, 0))


## A tapering cone from `a` (wide end, radius r) to `e` (the tip).
static func _cone(g: Geo, a: Vector3, e: Vector3, r: float, cl: Color, rm: Vector2) -> void:
	var d := (e - a).normalized()
	var x := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := d.cross(x).normalized()
	var sides := 6
	for k in sides:
		var t0 := TAU * float(k) / sides
		var t1 := TAU * float(k + 1) / sides
		var p0 := a + (x * cos(t0) + z * sin(t0)) * r
		var p1 := a + (x * cos(t1) + z * sin(t1)) * r
		var out := x * cos((t0 + t1) * 0.5) + z * sin((t0 + t1) * 0.5)
		g.tri(p0, p1, e, out, cl, rm)
		g.tri(p0, p1, a, -d, cl, rm)


## Green card pint baskets filled with strawberries, in rows in the crate.
static func _berry_baskets(g: Geo, xf: Transform3D, inner: Vector2, rim: float, rng: RandomNumberGenerator) -> void:
	var card := col(Color(0.18, 0.42, 0.18), C_CARD)
	var side := 0.115
	var nx := int(inner.x / (side + 0.01))
	var nz := int(inner.y / (side + 0.01))
	for a in nx:
		for b in nz:
			var c := Vector3(lerpf(-inner.x * 0.5, inner.x * 0.5, (a + 0.5) / nx), rim - 0.07, lerpf(-inner.y * 0.5, inner.y * 0.5, (b + 0.5) / nz))
			var bxf := xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)), c)
			var hs := side * 0.5
			for k in 4:
				var bb := bxf * Transform3D(Basis(Vector3.UP, PI * 0.5 * k), Vector3.ZERO)
				g.quad(bb * Vector3(-hs, 0, hs), bb * Vector3(hs, 0, hs), bb * Vector3(hs * 1.05, 0.075, hs * 1.05), bb * Vector3(-hs * 1.05, 0.075, hs * 1.05), bb.basis * Vector3.BACK, card, Vector2(0.9, 0))
			# The berries mounded over the rim: a red dome and a few berries on it.
			g.ellipsoid(Transform3D(xf.basis, bxf * Vector3(0, 0.07, 0)), Vector3(hs * 0.95, 0.03, hs * 0.95), 6, 2, col(Color(0.62, 0.05, 0.06), C_PRODUCE), Vector2(0.35, 0))
			for k in 3:
				var p := bxf * Vector3(rng.randf_range(-hs * 0.7, hs * 0.7), 0.09 + rng.randf() * 0.012, rng.randf_range(-hs * 0.7, hs * 0.7))
				g.ellipsoid(Transform3D(Basis(Vector3.RIGHT, PI) * Basis(Vector3.UP, rng.randf() * TAU), p), Vector3(0.014, 0.017, 0.014), 5, 3, col(_jit(rng, Color(0.82, 0.06, 0.08), 0.1), C_PRODUCE), Vector2(0.32, 0), 0, 0.0, 0.35)


## A small chalk price board on a stick, stuck into the heap.
static func _price(g: Geo, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.25)
	var xf := Transform3D(b, at)
	g.mode = 1
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.07, 0)), Vector3(0.12, 0.08, 0.006), col(Color(0.12, 0.12, 0.12), C_CHALK), Vector2(0.9, 0.0), false)
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.07, -0.004)), Vector3(0.13, 0.09, 0.004), col(Color(0.55, 0.4, 0.25), C_WOOD), Vector2(0.8, 0.0), false)
	g.bar(at, at + b * Vector3(0, 0.04, -0.002), 0.006, col(Color(0.62, 0.48, 0.3), C_WOOD), Vector2(0.8, 0.0))
	g.mode = 0


## A produce stall's goods (variant 0..5): origin on the ground under the canopy's centre, +z
## the aisle. The front table with four crates tilted to the front, a side table or bins, the
## stock behind.
static func produce(variant: int) -> Mesh:
	var key := "produce_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var g := Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["fm_produce", variant])
	var cloth: Array = CLOTHS[variant % CLOTHS.size()]
	var t_at := Vector3(0, 0, TABLE_Z)
	_table(g, t_at, TABLE, cloth)
	var mix: Array = PRODUCE_MIX[variant % PRODUCE_MIX.size()]
	var wood: Color = WOODS[variant % WOODS.size()]
	var crate := Vector3(0.43, 0.2, 0.62)
	var top := TABLE.y + 0.004
	# The crates lean toward the aisle on a riser along the back of the table.
	g.abox(Vector3(0, top + 0.025, TABLE_Z - TABLE.z * 0.5 + 0.08), Vector3(TABLE.x - 0.06, 0.05, 0.1), col(wood.darkened(0.3), C_WOOD), Vector2(0.9, 0))
	var lean := Basis(Vector3.RIGHT, 0.17)
	for k in 4:
		var x := lerpf(-TABLE.x * 0.5 + crate.x * 0.55, TABLE.x * 0.5 - crate.x * 0.55, k / 3.0)
		var xf := Transform3D(lean, Vector3(x, top + 0.055, TABLE_Z + 0.02))
		_crate(g, xf, crate, _jit(rng, wood, 0.06))
		_heap(g, xf, Vector2(crate.x - 0.04, crate.z - 0.04), crate.y - 0.005, 0.05, String(mix[k]), rng)
		_price(g, xf * Vector3(rng.randf_range(-0.1, 0.1), crate.y + 0.04, crate.z * 0.3), rng.randf_range(-0.2, 0.2))
	# A side table along one side (most stalls), or bulk bins on the ground.
	var sx := -1.0 if rng.randf() < 0.5 else 1.0
	if rng.randf() < 0.65:
		var side_at := Vector3(sx * 1.05, 0, 0.1)
		var st := Transform3D(Basis(Vector3.UP, PI * 0.5 * sx), side_at)
		_table_xf(g, st, Vector3(1.22, TABLE.y, 0.6), cloth)
		for k in 2:
			var cx := lerpf(-0.3, 0.3, float(k))
			var xf := st * Transform3D(lean, Vector3(cx, top + 0.01, 0.02))
			_crate(g, xf, Vector3(0.43, 0.18, 0.5), _jit(rng, wood, 0.06))
			_heap(g, xf, Vector2(0.39, 0.46), 0.175, 0.04, String(mix[(k + 2) % 4]), rng)
	else:
		for k in 2:
			var bx := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)), Vector3(sx * 1.05, 0.0, 0.55 - k * 0.62))
			_bin(g, bx, rng)
	# Stock behind: stacked crates, a cooler, a scale on the table, paper bags.
	_stock(g, rng, wood)
	_scale(g, Vector3(TABLE.x * 0.5 - 0.2 if sx < 0.0 else -TABLE.x * 0.5 + 0.2, top, TABLE_Z - 0.22))
	g.abox(Vector3(-sx * (TABLE.x * 0.5 - 0.15), top + 0.06, TABLE_Z - 0.25), Vector3(0.18, 0.12, 0.11), col(Color(0.7, 0.55, 0.38), C_CARD), Vector2(0.95, 0))
	var mesh := g.commit()
	_meshes[key] = mesh
	return mesh


## A folding table through `xf` (its own frame as _table's).
static func _table_xf(g: Geo, xf: Transform3D, size: Vector3, cloth: Array) -> void:
	var sub := Geo.new()
	_table(sub, Vector3.ZERO, size, cloth)
	_append(g, sub, xf)


## Appends another Geo's triangles through `xf` (both index lists kept as they were).
static func _append(g: Geo, sub: Geo, xf: Transform3D) -> void:
	var base := g.v.size()
	var nb := xf.basis.inverse().transposed()
	for i in sub.v.size():
		g.vert(xf * sub.v[i], (nb * sub.n[i]).normalized(), sub.c[i], sub.uv[i], sub.uv2[i])
	for i in sub.near.size():
		g.near.append(sub.near[i] + base)
	for i in sub.far.size():
		g.far.append(sub.far[i] + base)


## A big cardboard bulk bin on a pallet heaped with melons or squash.
static func _bin(g: Geo, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var card := col(Color(0.62, 0.48, 0.32), C_CARD)
	g.box(xf * Transform3D(Basis(), Vector3(0, 0.06, 0)), Vector3(0.6, 0.12, 0.55), col(Color(0.6, 0.5, 0.36), C_WOOD), Vector2(0.9, 0))
	var hx := 0.27
	var hz := 0.25
	var y0 := 0.12
	var y1 := 0.55
	var b := xf.basis
	for k in 4:
		var r := Transform3D(Basis(Vector3.UP, PI * 0.5 * k), Vector3.ZERO)
		var hw := hx if k % 2 == 0 else hz
		var hd := hz if k % 2 == 0 else hx
		g.quad(xf * (r * Vector3(-hw, y0, hd)), xf * (r * Vector3(hw, y0, hd)), xf * (r * Vector3(hw, y1, hd)), xf * (r * Vector3(-hw, y1, hd)), b * (r.basis * Vector3.BACK), card, Vector2(0.95, 0))
	_heap(g, xf, Vector2(0.5, 0.46), y1 - 0.03, 0.08, "squash", rng)


## The stock behind a stall: crates stacked, cardboard boxes, a cooler.
static func _stock(g: Geo, rng: RandomNumberGenerator, wood: Color) -> void:
	var x := rng.randf_range(-0.8, 0.8)
	for k in 1 + rng.randi() % 3:
		var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.08, 0.08)), Vector3(x, k * 0.24, -1.05))
		_crate(g, xf, Vector3(0.43, 0.23, 0.62), _jit(rng, wood, 0.08))
	var cx := x + (0.55 if x < 0.0 else -0.55)
	g.abox(Vector3(cx, 0.17, -1.1), Vector3(0.6, 0.34, 0.4), col(Color(0.2, 0.36, 0.62), C_FIXED), Vector2(0.45, 0))
	g.abox(Vector3(cx, 0.355, -1.1), Vector3(0.62, 0.04, 0.42), col(Color(0.92, 0.92, 0.9), C_FIXED), Vector2(0.45, 0))
	for k in 2:
		g.box(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), Vector3(cx + rng.randf_range(-0.2, 0.2), 0.39 + 0.15 + k * 0.3, -1.1)), Vector3(0.45, 0.3, 0.32), col(Color(0.66, 0.5, 0.33), C_CARD), Vector2(0.95, 0))


## A hanging-pan produce scale on the table.
static func _scale(g: Geo, at: Vector3) -> void:
	g.mode = 1
	g.abox(at + Vector3(0, 0.08, 0), Vector3(0.2, 0.16, 0.22), col(Color(0.88, 0.88, 0.86), C_FIXED), Vector2(0.35, 0.0))
	g.abox(at + Vector3(0, 0.12, 0.112), Vector3(0.12, 0.05, 0.004), col(Color(0.08, 0.15, 0.1), C_BULB), Vector2(0.2, 0.0))
	g.cyl(at + Vector3(0, 0.16, 0), 0.13, 0.15, 0.03, 12, col(Color(0.72, 0.74, 0.76), C_METAL), Vector2(0.3, 0.9))
	g.mode = 0


## A flower stall's goods (variant 0..1): a stepped stand of buckets, wrapped bouquets on the
## table, buckets on the ground in front.
static func flowers(variant: int) -> Mesh:
	var key := "flowers_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var g := Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["fm_flowers", variant])
	var wood := Color(0.5, 0.36, 0.22)
	# The stand: three wooden steps across the back half.
	for k in 2:
		var y := 0.3 + k * 0.34
		var z := 0.3 - k * 0.55
		g.abox(Vector3(0, y - 0.02, z), Vector3(2.4, 0.04, 0.44), col(wood, C_WOOD), Vector2(0.85, 0))
		for sx: float in [-1.15, 1.15]:
			g.abox(Vector3(sx, (y - 0.04) * 0.5, z), Vector3(0.05, y - 0.04, 0.4), col(wood.darkened(0.2), C_WOOD), Vector2(0.85, 0))
		for b in 5:
			var x := lerpf(-1.0, 1.0, b / 4.0) + rng.randf_range(-0.04, 0.04)
			_bucket(g, Vector3(x, y, z), rng, variant)
	# Buckets on the ground along the front.
	for b in 4:
		_bucket(g, Vector3(lerpf(-1.05, 1.05, b / 3.0), 0.0, 1.05 + rng.randf_range(-0.05, 0.05)), rng, variant + 3)
	_stock(g, rng, Color(0.6, 0.45, 0.3))
	var mesh := g.commit()
	_meshes[key] = mesh
	return mesh


## Flower colours a bunch can be.
const BLOOMS := [Color(0.92, 0.75, 0.08), Color(0.86, 0.12, 0.2), Color(0.95, 0.55, 0.7), Color(0.98, 0.96, 0.92),
	Color(0.6, 0.3, 0.75), Color(0.98, 0.5, 0.12), Color(0.85, 0.2, 0.45), Color(0.45, 0.55, 0.9)]


## A bucket of one kind of flower: sunflowers, roses, tulips, or a mixed bunch with statice.
static func _bucket(g: Geo, base: Vector3, rng: RandomNumberGenerator, salt: int) -> void:
	var metal := col(Color(0.62, 0.64, 0.66), C_METAL) if rng.randf() < 0.5 else col(Color(0.08, 0.08, 0.09), C_FIXED)
	g.cyl(base, 0.1, 0.13, 0.28, 10, metal, Vector2(0.4, 0.7 if metal.a > 0.05 else 0.0), false)
	g.cyl(base + Vector3(0, 0.22, 0), 0.12, 0.12, 0.0, 10, col(Color(0.06, 0.07, 0.06), C_FIXED), Vector2(0.1, 0.0))
	var kind := rng.randi() % 4
	var bloom: Color = BLOOMS[(rng.randi() + salt) % BLOOMS.size()]
	var stem := col(Color(0.2, 0.38, 0.12), C_LEAF)
	var stems := 7 if kind != 0 else 5
	g.mode = 1
	for k in stems:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.08)
		var foot := base + Vector3(cos(a) * r * 0.5, 0.25, sin(a) * r * 0.5)
		var head := base + Vector3(cos(a) * r * 2.0, rng.randf_range(0.62, 0.78) if kind == 0 else rng.randf_range(0.5, 0.62), sin(a) * r * 2.0)
		g.tube(foot, head, 0.005, 3, stem, Vector2(0.8, 0))
		var face := (head - foot).normalized()
		var hb := Basis(Quaternion(Vector3.UP, face))
		var cl := col(_jit(rng, bloom, 0.12), C_LEAF)
		match kind:
			0:
				# A sunflower: a disc of petals round a dark centre, facing out and up.
				var out := Vector3(head.x - base.x, 0.6, head.z - base.z).normalized()
				var fb := Basis(Quaternion(Vector3.UP, out))
				g.ellipsoid(Transform3D(fb, head), Vector3(0.075, 0.012, 0.075), 10, 2, col(Color(0.95, 0.75, 0.08), C_LEAF), Vector2(0.8, 0), 12, 0.35)
				g.ellipsoid(Transform3D(fb, head + out * 0.01), Vector3(0.035, 0.012, 0.035), 6, 1, col(Color(0.18, 0.1, 0.04), C_FIXED), Vector2(0.9, 0))
			1:
				# A rose: a tight cupped head.
				g.ellipsoid(Transform3D(hb, head), Vector3(0.026, 0.03, 0.026), 6, 3, cl, Vector2(0.75, 0), 5, 0.18)
			2:
				# A tulip: a closed cup.
				g.ellipsoid(Transform3D(hb, head + face * 0.02), Vector3(0.02, 0.035, 0.02), 5, 3, cl, Vector2(0.7, 0), 3, 0.15, 0.2)
			_:
				# Statice or stock: a spike of small florets.
				for f in 3:
					g.ellipsoid(Transform3D(hb, head + face * (0.028 * f)), Vector3(0.024, 0.018, 0.024) * (1.0 - f * 0.15), 5, 2, cl, Vector2(0.8, 0), 4, 0.3)
		# A leaf or two on the stem.
		if k % 3 == 0:
			var lp := foot.lerp(head, 0.45)
			g.ellipsoid(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, 0.8), lp), Vector3(0.012, 0.06, 0.004), 5, 3, stem, Vector2(0.75, 0))
	g.mode = 2
	g.ellipsoid(Transform3D(Basis(), base + Vector3(0, 0.55, 0)), Vector3(0.16, 0.14, 0.16), 6, 3, col(bloom, C_LEAF), Vector2(0.8, 0))
	g.mode = 0


## A bread stall (variant 0..1): boards of boules and batards on the cloth, a basket of
## baguettes standing up, a wire rack of loaves behind.
static func bread(variant: int) -> Mesh:
	var key := "bread_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var g := Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["fm_bread", variant])
	_table(g, Vector3(0, 0, TABLE_Z), TABLE, [Color(0.86, 0.82, 0.72), false] if variant == 0 else [Color(0.3, 0.18, 0.12), false])
	var top := TABLE.y + 0.004
	var board := col(Color(0.62, 0.45, 0.26), C_WOOD)
	for k in 3:
		var x := lerpf(-0.6, 0.6, k / 2.0)
		g.abox(Vector3(x, top + 0.012, TABLE_Z + 0.05), Vector3(0.5, 0.024, 0.55), board, Vector2(0.7, 0))
		for l in 4:
			var p := Vector3(x + rng.randf_range(-0.14, 0.14), top + 0.024, TABLE_Z + 0.05 + rng.randf_range(-0.15, 0.15))
			_loaf(g, p, rng, k == 1)
	# Baguettes standing in a tall basket at one end.
	var bx := 0.78 if variant == 0 else -0.78
	g.cyl(Vector3(bx, top, TABLE_Z - 0.2), 0.11, 0.13, 0.3, 10, col(Color(0.6, 0.45, 0.25), C_WOOD), Vector2(0.9, 0), false)
	for k in 8:
		var a := TAU * k / 8.0
		var foot := Vector3(bx + cos(a) * 0.06, top + 0.05, TABLE_Z - 0.2 + sin(a) * 0.06)
		var tip := foot + Vector3(cos(a) * 0.08, 0.62, sin(a) * 0.08)
		g.mode = 1
		g.tube(foot, tip, 0.028, 7, col(_jit(rng, Color(0.78, 0.52, 0.22), 0.08), C_CRUST), Vector2(0.75, 0))
		g.ellipsoid(Transform3D(Basis(Quaternion(Vector3.UP, (tip - foot).normalized())), tip), Vector3(0.028, 0.05, 0.028), 7, 3, col(Color(0.72, 0.46, 0.18), C_CRUST), Vector2(0.75, 0))
		g.mode = 0
	# The rack behind: three wire shelves of loaves.
	var steel := col(Color(0.3, 0.3, 0.32), C_METAL)
	for sx: float in [-0.75, 0.75]:
		for sz: float in [-0.95, -0.55]:
			g.bar(Vector3(sx, 0, sz), Vector3(sx, 1.55, sz), 0.022, steel, Vector2(0.4, 0.8))
	for k in 3:
		var y := 0.5 + k * 0.45
		g.abox(Vector3(0, y, -0.75), Vector3(1.55, 0.02, 0.42), col(Color(0.55, 0.42, 0.26), C_WOOD), Vector2(0.8, 0))
		for l in 5:
			_loaf(g, Vector3(lerpf(-0.6, 0.6, l / 4.0), y + 0.01, -0.75 + rng.randf_range(-0.05, 0.05)), rng, l % 2 == 0)
	g.abox(Vector3(-bx, top + 0.06, TABLE_Z - 0.25), Vector3(0.2, 0.12, 0.12), col(Color(0.88, 0.85, 0.78), C_CARD), Vector2(0.95, 0))
	var mesh := g.commit()
	_meshes[key] = mesh
	return mesh


## One loaf: a round boule with a scored cross, or a long batard with its slashes.
static func _loaf(g: Geo, p: Vector3, rng: RandomNumberGenerator, round_loaf: bool) -> void:
	var crust := col(_jit(rng, Color(0.72, 0.46, 0.2), 0.1), C_CRUST)
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	if round_loaf:
		g.ellipsoid(Transform3D(b, p + Vector3(0, 0.035, 0)), Vector3(0.095, 0.07, 0.095), 10, 5, crust, Vector2(0.8, 0), 0, 0.0, -0.15)
		g.mode = 1
		var score := col(Color(0.92, 0.82, 0.62), C_CRUST)
		g.abox(p + Vector3(0, 0.1, 0), Vector3(0.11, 0.008, 0.012), score, Vector2(0.9, 0))
		g.box(Transform3D(b * Basis(Vector3.UP, PI * 0.5), p + Vector3(0, 0.1, 0)), Vector3(0.11, 0.008, 0.012), score, Vector2(0.9, 0))
		g.mode = 0
	else:
		g.ellipsoid(Transform3D(b, p + Vector3(0, 0.03, 0)), Vector3(0.06, 0.055, 0.15), 9, 5, crust, Vector2(0.8, 0))
		g.mode = 1
		for k in 3:
			g.box(Transform3D(b * Basis(Vector3.UP, 0.5), p + b * Vector3(0, 0.083, -0.08 + k * 0.08)), Vector3(0.05, 0.006, 0.012), col(Color(0.9, 0.8, 0.6), C_CRUST), Vector2(0.9, 0))
		g.mode = 0


## A pantry stall (variant 0..1): honey and jam jars on a tiered shelf, egg cartons, bottles.
static func pantry(variant: int) -> Mesh:
	var key := "pantry_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var g := Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["fm_pantry", variant])
	_table(g, Vector3(0, 0, TABLE_Z), TABLE, [Color(0.85, 0.75, 0.45), true] if variant == 0 else [Color(0.2, 0.32, 0.22), false])
	var top := TABLE.y + 0.004
	var wood := col(Color(0.58, 0.42, 0.26), C_WOOD)
	# A two-step riser on the table.
	g.abox(Vector3(0, top + 0.06, TABLE_Z - 0.18), Vector3(1.6, 0.12, 0.3), wood, Vector2(0.85, 0))
	g.abox(Vector3(0, top + 0.16, TABLE_Z - 0.3), Vector3(1.6, 0.1, 0.12), wood, Vector2(0.85, 0))
	var jars := [Color(0.85, 0.5, 0.08), Color(0.65, 0.3, 0.05), Color(0.55, 0.06, 0.12), Color(0.35, 0.08, 0.3), Color(0.9, 0.6, 0.15)]
	for row in 3:
		var y: float = [top, top + 0.12, top + 0.21][row]
		var z: float = [TABLE_Z + 0.2, TABLE_Z - 0.12, TABLE_Z - 0.3][row]
		for k in 11:
			var x := lerpf(-0.75, 0.75, k / 10.0)
			if row == 0 and absf(x) < 0.32:
				continue
			var c: Color = jars[(k + row * 2 + variant) % jars.size()]
			g.mode = 1
			g.cyl(Vector3(x, y, z), 0.035, 0.035, 0.1, 9, col(c, C_GLASS), Vector2(0.06, 0.0))
			g.cyl(Vector3(x, y + 0.1, z), 0.036, 0.036, 0.018, 9, col(Color(0.8, 0.65, 0.2) if k % 2 == 0 else Color(0.85, 0.85, 0.82), C_METAL), Vector2(0.35, 0.9))
			g.mode = 2
			g.abox(Vector3(x, y + 0.06, z), Vector3(0.07, 0.12, 0.07), col(c, C_GLASS), Vector2(0.1, 0))
			g.mode = 0
	# Egg cartons, open, in the middle of the front row.
	for k in 3:
		var c := Vector3(-0.2 + k * 0.2, top, TABLE_Z + 0.18)
		g.abox(c + Vector3(0, 0.025, 0), Vector3(0.15, 0.05, 0.3), col(Color(0.62, 0.55, 0.45), C_CARD), Vector2(0.95, 0))
		g.mode = 1
		for e in 12:
			var p := c + Vector3(-0.035 + (e % 2) * 0.07, 0.065, -0.125 + (e / 2) * 0.05)
			g.ellipsoid(Transform3D(Basis(), p), Vector3(0.021, 0.027, 0.021), 7, 4, col(_jit(rng, Color(0.75, 0.55, 0.38) if k != 1 else Color(0.92, 0.9, 0.85), 0.06), C_PRODUCE), Vector2(0.6, 0), 0, 0.0, -0.12)
		g.mode = 0
	# Olive oil bottles at one end.
	for k in 4:
		var p := Vector3(0.62 + (k % 2) * 0.09, top + 0.12, TABLE_Z - 0.18 + (k / 2) * 0.1)
		g.cyl(p, 0.032, 0.032, 0.2, 8, col(Color(0.18, 0.3, 0.08), C_GLASS), Vector2(0.06, 0))
		g.cyl(p + Vector3(0, 0.2, 0), 0.032, 0.012, 0.06, 8, col(Color(0.18, 0.3, 0.08), C_GLASS), Vector2(0.06, 0))
	_stock(g, rng, Color(0.6, 0.45, 0.3))
	var mesh := g.commit()
	_meshes[key] = mesh
	return mesh


## The goods mesh for a stall kind and variant.
static func goods(kind: int, variant: int) -> Mesh:
	match kind:
		FarmersMarket.Kind.FLOWERS:
			return flowers(variant % VARIANTS[1])
		FarmersMarket.Kind.BREAD:
			return bread(variant % VARIANTS[2])
		FarmersMarket.Kind.PANTRY:
			return pantry(variant % VARIANTS[3])
	return produce(variant % VARIANTS[0])


static func goods_key(kind: int, variant: int) -> String:
	return "fm_goods_%d_%d" % [kind, variant % int(VARIANTS[kind])]


## A stall packed up (variant 0..1): the tables folded and leant together, crates stacked empty,
## boxes. Origin on the ground at the back of the stall's space.
static func packed(variant: int) -> Mesh:
	var key := "packed_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var g := Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["fm_packed", variant])
	# Two folded tables standing on their long edges, leant on each other.
	for k in 2:
		var b := Basis(Vector3.UP, 0.05 * k) * Basis(Vector3.RIGHT, -0.12 + 0.24 * k)
		var xf := Transform3D(b, Vector3(0.35, 0.39, -0.05 + k * 0.08))
		g.box(xf, Vector3(1.83, 0.76, 0.045), col(Color(0.84, 0.84, 0.82), C_FIXED), Vector2(0.5, 0.0), false)
	# Crates stacked three or four high, empty.
	var wood: Color = WOODS[variant % WOODS.size()]
	for s in 2:
		var x := -0.75 + s * 0.5
		for k in 3 + (variant + s) % 2:
			var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)), Vector3(x, k * 0.205, 0.0))
			_crate(g, xf, Vector3(0.43, 0.2, 0.62), _jit(rng, wood, 0.08))
	# Cardboard boxes and a cooler.
	for k in 3:
		g.box(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(-0.2 + k * 0.42, 0.15, 0.55)), Vector3(0.42, 0.3, 0.32), col(Color(0.64, 0.49, 0.33), C_CARD), Vector2(0.95, 0))
	g.abox(Vector3(1.0, 0.17, 0.45), Vector3(0.6, 0.34, 0.4), col(Color(0.2, 0.36, 0.62), C_FIXED), Vector2(0.45, 0))
	var mesh := g.commit()
	_meshes[key] = mesh
	return mesh


# --- Street furniture ----------------------------------------------------------------------------

## A removable steel bollard: a black post with a reflective band and a cap, on its socket.
static func bollard() -> Mesh:
	if _meshes.has("bollard"):
		return _meshes.bollard
	var g := Geo.new()
	var black := col(Color(0.05, 0.05, 0.055), C_FIXED)
	var rm := Vector2(0.45, 0.2)
	g.cyl(Vector3(0, -0.01, 0), 0.11, 0.11, 0.02, 12, col(Color(0.35, 0.35, 0.36), C_METAL), Vector2(0.5, 0.8))
	g.cyl(Vector3(0, 0.0, 0), 0.075, 0.075, 0.88, 12, black, rm, false)
	g.cyl(Vector3(0, 0.62, 0), 0.077, 0.077, 0.1, 12, col(Color(0.92, 0.9, 0.82), C_BULB), Vector2(0.3, 0.0), false)
	g.cyl(Vector3(0, 0.88, 0), 0.075, 0.03, 0.06, 12, black, rm)
	g.mode = 2
	g.abox(Vector3(0, 0.45, 0), Vector3(0.15, 0.9, 0.15), black, rm)
	g.mode = 0
	var mesh := g.commit(0.04)
	_meshes.bollard = mesh
	return mesh


## The market's sign at each end: a post with a printed panel (the lettering is the chunk's sign
## mesh, FarmersMarketBuild). Origin on the ground, +z the face.
static func sign_post() -> Mesh:
	if _meshes.has("sign_post"):
		return _meshes.sign_post
	var g := Geo.new()
	var steel := col(Color(0.5, 0.52, 0.54), C_METAL)
	g.cyl(Vector3(0, 0, -0.03), 0.04, 0.04, 2.9, 10, steel, Vector2(0.4, 0.85))
	g.abox(Vector3(0, 2.35, 0.0), Vector3(0.95, 1.1, 0.03), col(Color(0.18, 0.36, 0.2), C_FIXED), Vector2(0.4, 0.0))
	g.abox(Vector3(0, 2.35, 0.016), Vector3(0.91, 1.06, 0.004), col(Color(0.94, 0.92, 0.84), C_FIXED), Vector2(0.4, 0.0))
	g.abox(Vector3(0, 2.68, 0.019), Vector3(0.91, 0.36, 0.004), col(Color(0.18, 0.36, 0.2), C_FIXED), Vector2(0.4, 0.0))
	var mesh := g.commit(0.05)
	_meshes.sign_post = mesh
	return mesh


## Builds every mesh once (the loading screen), so the first market does not stall.
static func warm() -> void:
	if not FarmersMarket.enabled:
		return
	canopy()
	canopy_folded()
	bollard()
	sign_post()
	for k in 4:
		for v in int(VARIANTS[k]):
			goods(k, v)
	for v in 2:
		packed(v)
