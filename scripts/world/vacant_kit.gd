class_name VacantKit
extends RefCounted
## The geometry of the city's vacant lots and gravel car parks (VacantLots lays them out), all
## built in code at real size:
##   - the WEEDS, three swaying meshes for the chunk's batches on shaders/vacant_weeds.gdshader
##     (vertex colours, linear): a tuft of dry grass with foxtail heads, a clump of wild mustard
##     (branching stalks with yellow flower heads over a rosette of lobed leaves) and a clump of
##     fennel (tall blue-green stalks, threadlike foliage, flat yellow umbels);
##   - writers for everything upright, straight into a chunk's ONE walls mesh in IndustrialKit's
##     vertex layout (its box / cylinder / cone writers, kinds K_* below in COLOR.a 32nds) on
##     shaders/vacant_walls.gdshader: chain-link runs with privacy screen, padlocked gates, a
##     demolished building's stem walls and rebar, rubble piles, a sofa, an armchair, a mattress,
##     tyres, a television, a shopping cart, wheel stops, traffic cones, the car park attendant's
##     booth, and sign boards with their LETTERING (TextMesh outlines merged into the mesh).
## Everything here is pure geometry: no rolls (callers pass what they rolled), no nodes.

# --- Kinds (COLOR.a in 32nds; mirrored in vacant_walls.gdshader) --------------------------------
const K_GALV := 0
const K_CHAIN := 1
const K_SCREEN := 2
const K_CONCRETE := 3
const K_BRICK := 4
const K_RUST := 5
const K_FABRIC := 6
const K_MATTRESS := 7
const K_RUBBER := 8
const K_WOOD := 9
const K_SIGN := 10
const K_INK := 11
const K_PAINTED := 12
const K_PLASTIC := 13
const K_GLASS := 14
const K_WIRE := 15
const K_SHEET := 16
const K_EARTH := 17
const K_LAMP := 18
const KIND_COUNT := 19

## Fence: chain-link height (6 ft), post spacing, the top rail's and a post's size.
const FENCE_H := 1.83
const POST_SPACING := 3.0
const POST := 0.06
## A double swing gate's two leaves together (16 ft).
const GATE_W := 4.9

static var _weeds_material: ShaderMaterial = null
static var _walls_material: ShaderMaterial = null
static var _meshes: Dictionary = {}
## Triangles written by the writers since start (the checks and the bench read it).
static var tris: int = 0


static func weeds_material() -> ShaderMaterial:
	if _weeds_material == null:
		_weeds_material = ShaderMaterial.new()
		_weeds_material.shader = load("res://shaders/vacant_weeds.gdshader")
	return _weeds_material


static func walls_material() -> ShaderMaterial:
	if _walls_material != null:
		return _walls_material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vacant_walls.gdshader")
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("cracked_tex", PropFactory.texture("concrete_cracked", "Color"))
	mat.set_shader_parameter("brick_tex", PropFactory.texture("brick_red", "Color"))
	mat.set_shader_parameter("planks_tex", PropFactory.texture("planks", "Color"))
	mat.set_shader_parameter("fabric_tex", PropFactory.texture("fabric", "Color"))
	mat.set_shader_parameter("ticking_tex", PropFactory.texture("camp_ticking", "Color"))
	mat.set_shader_parameter("dirt_tex", PropFactory.texture("hill_dirt", "Color"))
	_walls_material = mat
	return mat


# --- Weeds --------------------------------------------------------------------------------------

## A tapered blade from `base` along a curve: leaving in `dir` (horizontal unit) at `lean` radians
## off vertical, `h` tall, `w` wide at the foot, bending over by `droop`. `segs` segments.
static func _blade(st: SurfaceTool, base: Vector3, dir: Vector3, lean: float, h: float, w: float, droop: float, col0: Color, col1: Color, segs: int = 3) -> void:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / float(segs)
		var a := lean + droop * t * t
		var p := base + dir * (sin(lean) * h * t + sin(a) * h * t * t * 0.5) + Vector3.UP * (cos(a) * h * t)
		pts.append(p)
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var w0 := w * (1.0 - t0)
		var w1 := w * (1.0 - t1)
		var a0 := pts[i] - side * w0 * 0.5
		var b0 := pts[i] + side * w0 * 0.5
		var a1 := pts[i + 1] - side * w1 * 0.5
		var b1 := pts[i + 1] + side * w1 * 0.5
		var c0 := col0.lerp(col1, t0)
		var c1 := col0.lerp(col1, t1)
		# Normals bent toward up so a clump lights as a mass, not as lit slivers.
		var n := ((pts[i + 1] - pts[i]).cross(side).normalized() * 0.45 + Vector3.UP).normalized()
		if i == segs - 1:
			_vtx(st, a0, n, c0)
			_vtx(st, b0, n, c0)
			_vtx(st, pts[i + 1], n, c1)
		else:
			_vtx(st, a0, n, c0)
			_vtx(st, b0, n, c0)
			_vtx(st, b1, n, c1)
			_vtx(st, a0, n, c0)
			_vtx(st, b1, n, c1)
			_vtx(st, a1, n, c1)


static func _vtx(st: SurfaceTool, p: Vector3, n: Vector3, c: Color) -> void:
	st.set_normal(n)
	st.set_color(c)
	st.add_vertex(p)


## A small diamond spindle (two crossed quads) from `a` to `b`, `r` across: a foxtail head, a seed
## pod, a bud cluster.
static func _spindle(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var ax := (b - a).normalized()
	var s1 := ax.cross(Vector3.UP if absf(ax.y) < 0.95 else Vector3.RIGHT).normalized()
	var s2 := ax.cross(s1).normalized()
	var m := (a + b) * 0.5
	for s: Vector3 in [s1, s2]:
		var n := (s.cross(ax).normalized() * 0.4 + Vector3.UP).normalized()
		_vtx(st, a, n, col)
		_vtx(st, m + s * r, n, col)
		_vtx(st, b, n, col)
		_vtx(st, a, n, col)
		_vtx(st, b, n, col)
		_vtx(st, m - s * r, n, col)


static func _commit_weed(key: String, st: SurfaceTool) -> Mesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, weeds_material())
	_meshes[key] = mesh
	return mesh


## A tuft of dry grass and foxtail (variant 0, straw; 1, wild oats still green at the foot).
static func tuft(variant: int) -> Mesh:
	var key := "tuft_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7701 + variant
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Linear albedo: a dull grey-green foot, pale straw tips.
	var foot := Color(0.09, 0.09, 0.04) if variant == 0 else Color(0.07, 0.10, 0.03)
	var tip := Color(0.42, 0.33, 0.15) if variant == 0 else Color(0.33, 0.30, 0.13)
	for i in 30:
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		var base := dir * rng.randf_range(0.0, 0.09)
		var h := rng.randf_range(0.25, 0.62)
		_blade(st, base, dir, rng.randf_range(0.12, 0.7), h, rng.randf_range(0.008, 0.016), rng.randf_range(0.2, 1.1), foot, tip.lerp(Color(0.5, 0.42, 0.24), rng.randf() * 0.4))
	# Seed heads on bare stems: foxtails (bristly spindles) and oat panicles.
	for i in 8:
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		var base := dir * rng.randf_range(0.0, 0.06)
		var h := rng.randf_range(0.45, 0.78)
		var lean := rng.randf_range(0.05, 0.35)
		_blade(st, base, dir, lean, h, 0.005, 0.15, foot, tip, 2)
		var top := base + dir * sin(lean) * h * 1.05 + Vector3.UP * cos(lean) * h
		var head := Color(0.48, 0.40, 0.22) if variant == 0 else Color(0.40, 0.36, 0.18)
		_spindle(st, top - dir * 0.02 - Vector3.UP * 0.07, top + dir * 0.025, 0.012, head)
	return _commit_weed(key, st)


## A clump of wild mustard: branching stalks, 0.7-1.5 m, each tip a head of small yellow flowers
## over the green pods below it, and a rosette of lobed leaves at the foot.
static func mustard() -> Mesh:
	if _meshes.has("mustard"):
		return _meshes["mustard"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7801
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem0 := Color(0.06, 0.08, 0.025)
	var stem1 := Color(0.16, 0.18, 0.05)
	var yellow := Color(0.86, 0.62, 0.02)
	var pod := Color(0.2, 0.22, 0.06)
	var leaf := Color(0.05, 0.09, 0.025)
	# The rosette.
	for i in 6:
		var a := TAU * float(i) / 6.0 + rng.randf() * 0.5
		var dir := Vector3(cos(a), 0.0, sin(a))
		_blade(st, Vector3.ZERO, dir, rng.randf_range(0.9, 1.25), rng.randf_range(0.22, 0.32), 0.09, 0.3, leaf, leaf * 1.3, 2)
	for i in 5:
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		var h := rng.randf_range(0.7, 1.45)
		var lean := rng.randf_range(0.04, 0.3)
		var base := dir * rng.randf_range(0.0, 0.08)
		# The stalk as two crossed strips.
		_blade(st, base, dir, lean, h, 0.012, 0.1, stem0, stem1, 3)
		_blade(st, base, Vector3(-dir.z, 0.0, dir.x), lean * 0.3, h, 0.012, 0.0, stem0, stem1, 3)
		var top := base + dir * sin(lean) * h * 1.03 + Vector3.UP * cos(lean) * h
		var tips: Array[Vector3] = [top]
		# Two or three branches off the upper half.
		for b in rng.randi_range(2, 3):
			var t := rng.randf_range(0.5, 0.8)
			var at := base + dir * sin(lean) * h * t + Vector3.UP * cos(lean) * h * t
			var ba := a + rng.randf_range(-1.6, 1.6)
			var bdir := Vector3(cos(ba), 0.0, sin(ba))
			var bh := h * rng.randf_range(0.25, 0.45)
			var bl := rng.randf_range(0.45, 0.8)
			_blade(st, at, bdir, bl, bh, 0.008, 0.0, stem1, stem1, 2)
			tips.append(at + bdir * sin(bl) * bh + Vector3.UP * cos(bl) * bh)
		for tp: Vector3 in tips:
			# Pods along the top of the stem, then the flower head: a ball of small petals.
			for k in 3:
				var pa := rng.randf() * TAU
				var po := Vector3(cos(pa), 0.0, sin(pa)) * 0.03
				_spindle(st, tp - Vector3.UP * (0.08 + 0.05 * k) + po * 0.3, tp - Vector3.UP * (0.03 + 0.05 * k) + po, 0.004, pod)
			for k in 7:
				var fa := rng.randf() * TAU
				var fe := rng.randf_range(-0.2, 1.0)
				var c := tp + Vector3(cos(fa) * cos(fe), sin(fe) * 0.6 + 0.02, sin(fa) * cos(fe)) * rng.randf_range(0.015, 0.04)
				var s := rng.randf_range(0.011, 0.017)
				var n := (c - tp).normalized() * 0.5 + Vector3.UP
				n = n.normalized()
				var t1 := n.cross(Vector3.RIGHT).normalized()
				var t2 := n.cross(t1).normalized()
				_vtx(st, c + t1 * s, n, yellow)
				_vtx(st, c + t2 * s, n, yellow)
				_vtx(st, c - t1 * s, n, yellow)
				_vtx(st, c + t1 * s, n, yellow)
				_vtx(st, c - t1 * s, n, yellow)
				_vtx(st, c - t2 * s, n, yellow)
	return _commit_weed("mustard", st)


## A clump of fennel: tall blue-green stalks (1.2-2 m) with threadlike foliage in sprays and flat
## umbels of yellow flowers on top.
static func fennel() -> Mesh:
	if _meshes.has("fennel"):
		return _meshes["fennel"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7901
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem0 := Color(0.05, 0.08, 0.04)
	var stem1 := Color(0.12, 0.17, 0.08)
	var thread := Color(0.08, 0.14, 0.05)
	var umbel := Color(0.62, 0.52, 0.04)
	for i in 4:
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		var h := rng.randf_range(1.15, 1.95)
		var lean := rng.randf_range(0.03, 0.2)
		var base := dir * rng.randf_range(0.0, 0.1)
		_blade(st, base, dir, lean, h, 0.022, 0.05, stem0, stem1, 4)
		_blade(st, base, Vector3(-dir.z, 0.0, dir.x), lean * 0.3, h, 0.022, 0.0, stem0, stem1, 4)
		# Sprays of threads up the stalk.
		for k in 5:
			var t := 0.12 + 0.17 * float(k)
			var at := base + dir * sin(lean) * h * t + Vector3.UP * cos(lean) * h * t
			for j in 6:
				var ta := rng.randf() * TAU
				var tdir := Vector3(cos(ta), 0.0, sin(ta))
				var tl := rng.randf_range(0.16, 0.34) * (1.2 - t * 0.6)
				var end := at + tdir * tl + Vector3.UP * rng.randf_range(0.05, 0.2)
				var side := tdir.cross(Vector3.UP).normalized() * 0.006
				var n := (end - at).cross(side).normalized() * 0.4 + Vector3.UP
				n = n.normalized()
				_vtx(st, at - side, n, thread)
				_vtx(st, at + side, n, thread)
				_vtx(st, end, n, thread * 1.3)
		# The umbel: rays out to a flat ring of small yellow flower clusters.
		var top := base + dir * sin(lean) * h * 1.02 + Vector3.UP * cos(lean) * h
		var rays := 9
		for k in rays:
			var ra := TAU * float(k) / float(rays) + rng.randf() * 0.3
			var rdir := Vector3(cos(ra), 0.0, sin(ra))
			var r := rng.randf_range(0.06, 0.1)
			var end := top + rdir * r + Vector3.UP * 0.04
			var side := rdir.cross(Vector3.UP).normalized() * 0.003
			_vtx(st, top - side, Vector3.UP, stem1)
			_vtx(st, top + side, Vector3.UP, stem1)
			_vtx(st, end, Vector3.UP, stem1)
			var s := 0.018
			var t1 := rdir * s
			var t2 := Vector3(-rdir.z, 0.0, rdir.x) * s
			_vtx(st, end + t1, Vector3.UP, umbel)
			_vtx(st, end + t2, Vector3.UP, umbel)
			_vtx(st, end - t1, Vector3.UP, umbel)
			_vtx(st, end + t1, Vector3.UP, umbel)
			_vtx(st, end - t1, Vector3.UP, umbel)
			_vtx(st, end - t2, Vector3.UP, umbel)
	return _commit_weed("fennel", st)


# --- Writers into the walls mesh ---------------------------------------------------------------

static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 32) -> void:
	tris += 12
	IndustrialKit.box(st, xf, size, kind, paint, param, skip)


## A triangle facing `n` (the winding is fixed here: Godot's front faces are clockwise to the
## viewer).
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, kind: int, paint: Color, uv: Array, h: float = 1.0) -> void:
	var col := IndustrialKit.kind_color(kind, paint)
	var pts := [a, b, c]
	var uvs := uv
	if (b - a).cross(c - a).dot(n) > 0.0:
		pts = [a, c, b]
		uvs = [uv[0], uv[2], uv[1]]
	for k in 3:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(uvs[k])
		st.set_uv2(Vector2(h, 0.0))
		st.add_vertex(pts[k])
	tris += 1


## A torus lying flat (axis +y in `xf`): a dumped tyre. `R` to the tube's centre, `r` the tube.
static func torus(st: SurfaceTool, xf: Transform3D, R: float, r: float, kind: int, paint: Color, segs: int = 14, rings: int = 6) -> void:
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		for j in rings:
			var b0 := TAU * float(j) / float(rings)
			var b1 := TAU * float(j + 1) / float(rings)
			var q := []
			var ns := []
			var uvs := []
			for ab: Vector2 in [Vector2(a0, b0), Vector2(a1, b0), Vector2(a1, b1), Vector2(a0, b1)]:
				var d := Vector3(cos(ab.x), 0.0, sin(ab.x))
				var n := d * cos(ab.y) + Vector3.UP * sin(ab.y)
				q.append(xf * (d * R + n * r))
				ns.append((xf.basis * n).normalized())
				uvs.append(Vector2(ab.x * R, ab.y * r))
			var nm: Vector3 = ((ns[0] as Vector3) + (ns[2] as Vector3)).normalized()
			tri(st, q[0], q[1], q[2], nm, kind, paint, [uvs[0], uvs[1], uvs[2]], r * 2.0)
			tri(st, q[0], q[2], q[3], nm, kind, paint, [uvs[0], uvs[2], uvs[3]], r * 2.0)


## Lettering: `text` in a line `height` tall centred at xf's origin, on xf's x-y plane facing +z,
## squeezed to at most `max_w` wide. Returns the width drawn.
static func letters(st: SurfaceTool, text: String, height: float, xf: Transform3D, paint: Color, max_w: float = 99.0) -> float:
	if text == "":
		return 0.0
	var geo := FreewayKit.text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var width: float = geo[2]
	var squeeze := minf(1.0, max_w / maxf(width, 0.001))
	var n := xf.basis.z.normalized()
	var col := IndustrialKit.kind_color(K_INK, paint)
	for k in range(0, idx.size() - 2, 3):
		var p0 := xf * Vector3(verts[idx[k]].x * squeeze, verts[idx[k]].y, 0.0)
		var p1 := xf * Vector3(verts[idx[k + 1]].x * squeeze, verts[idx[k + 1]].y, 0.0)
		var p2 := xf * Vector3(verts[idx[k + 2]].x * squeeze, verts[idx[k + 2]].y, 0.0)
		var pts := [p0, p1, p2]
		if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
			pts = [p0, p2, p1]
		for p: Vector3 in pts:
			st.set_normal(n)
			st.set_color(col)
			st.set_uv(Vector2.ZERO)
			st.set_uv2(Vector2(1.0, 0.0))
			st.add_vertex(p)
		tris += 1
	return width * squeeze


## One straight run of chain-link from `a` to `b` (chunk space, y the ground under each end, over
## the relief): posts every POST_SPACING, a top rail, the fabric, and on `screen` a privacy screen
## on the street side (`out` the horizontal unit toward the street). `rusty` is an old run.
static func fence_run(st: SurfaceTool, a: Vector3, b: Vector3, out: Vector3, screen: bool, screen_paint: Color, rusty: bool, wear: float, posts_at_ends: bool = true) -> void:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var len := flat.length()
	if len < 0.3:
		return
	var dir := flat / len
	var yaw := atan2(-dir.z, dir.x)
	var basis := Basis(Vector3.UP, yaw)
	var steel := Color(0.70, 0.71, 0.72) if not rusty else Color(0.55, 0.5, 0.45)
	var n := maxi(1, ceili(len / POST_SPACING))
	for i in n:
		var q0 := a.lerp(b, float(i) / float(n))
		var q1 := a.lerp(b, float(i + 1) / float(n))
		var m := (q0 + q1) * 0.5
		var seg := Vector2(q1.x - q0.x, q1.z - q0.z).length()
		var g := minf(q0.y, q1.y)
		box(st, Transform3D(basis, Vector3(m.x, g + FENCE_H * 0.5 + 0.02, m.z)), Vector3(seg, FENCE_H, 0.02), K_CHAIN, steel, 1.0 if rusty else 0.0, 32 | 16)
		box(st, Transform3D(basis, Vector3(m.x, g + FENCE_H + 0.03, m.z)), Vector3(seg, 0.042, 0.042), K_GALV, steel)
		if screen:
			box(st, Transform3D(basis, Vector3(m.x, g + FENCE_H * 0.5 + 0.05, m.z) + out * 0.03), Vector3(seg - 0.04, FENCE_H - 0.12, 0.012), K_SCREEN, screen_paint, wear, 32 | 16)
	for i in n + 1:
		if not posts_at_ends and (i == 0 or i == n):
			continue
		var p := a.lerp(b, float(i) / float(n))
		var big := i == 0 or i == n
		var ps := POST * (1.4 if big else 1.0)
		box(st, Transform3D(basis, Vector3(p.x, p.y + (FENCE_H + 0.12) * 0.5 - 0.05, p.z)), Vector3(ps, FENCE_H + 0.12, ps), K_GALV, steel)


## A double swing gate across `a`..`b`, shut with a chain and a padlock where the leaves meet (or
## `open`: both leaves swung back against the fence inside).
static func gate(st: SurfaceTool, a: Vector3, b: Vector3, inward: Vector3, open: bool, screen: bool, screen_paint: Color, wear: float) -> void:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var len := flat.length()
	if len < 0.5:
		return
	var dir := flat / len
	var steel := Color(0.72, 0.73, 0.74)
	var leaf := len * 0.5 - 0.06
	var hgt := FENCE_H - 0.1
	for side in 2:
		var hinge := a if side == 0 else b
		var along := dir if side == 0 else -dir
		if open:
			along = (along * 0.15 + inward).normalized()
		var yaw := atan2(-along.z, along.x)
		var basis := Basis(Vector3.UP, yaw)
		var c := hinge + along * (leaf * 0.5 + 0.06) + Vector3.UP * (0.08 + hgt * 0.5)
		# Frame: two rails and two stiles of 1-5/8" tube, a diagonal brace, the fabric.
		for yy: float in [-hgt * 0.5, hgt * 0.5]:
			box(st, Transform3D(basis, c + Vector3.UP * yy), Vector3(leaf, 0.042, 0.042), K_GALV, steel)
		for xx: float in [-leaf * 0.5, leaf * 0.5]:
			box(st, Transform3D(basis, c + along * xx), Vector3(0.042, hgt, 0.042), K_GALV, steel)
		var diag := Vector2(leaf, hgt)
		box(st, Transform3D(basis * Basis(Vector3.FORWARD, atan2(diag.y, diag.x)), c), Vector3(diag.length(), 0.03, 0.03), K_GALV, steel)
		box(st, Transform3D(basis, c), Vector3(leaf, hgt, 0.02), K_CHAIN, steel, 0.0, 32 | 16)
		if screen:
			box(st, Transform3D(basis, c - inward * 0.03), Vector3(leaf - 0.05, hgt - 0.1, 0.012), K_SCREEN, screen_paint, wear, 32 | 16)
		# The hinge post.
		box(st, Transform3D(basis, hinge + Vector3.UP * (FENCE_H + 0.15) * 0.5), Vector3(0.09, FENCE_H + 0.15, 0.09), K_GALV, steel)
	if not open:
		# The chain wrapped round both stiles and the padlock hanging off it.
		var m := (a + b) * 0.5 + Vector3.UP * 1.0
		var yaw := atan2(-dir.z, dir.x)
		box(st, Transform3D(Basis(Vector3.UP, yaw), m), Vector3(0.16, 0.05, 0.08), K_RUST, Color.WHITE)
		box(st, Transform3D(Basis(Vector3.UP, yaw), m - Vector3.UP * 0.09 - inward * 0.05), Vector3(0.05, 0.065, 0.025), K_GALV, Color(0.62, 0.55, 0.3))


## A sign board: `size` (w, h) face on two posts, its foot at `at` (ground height in y), facing
## `face` (horizontal unit). `band` paints a header band of that height (0 none) in `band_paint`.
## Returns the board's frame (origin at the board's centre, +z out of the face).
static func sign_board(st: SurfaceTool, at: Vector3, face: Vector3, size: Vector2, bottom: float, paint: Color, band: float, band_paint: Color, posts: bool, wood: bool) -> Transform3D:
	var yaw := atan2(face.x, face.z)
	var basis := Basis(Vector3.UP, yaw)
	var c := at + Vector3.UP * (bottom + size.y * 0.5)
	box(st, Transform3D(basis, c), Vector3(size.x, size.y, 0.03), K_PAINTED if wood else K_SIGN, paint, 0.0)
	if band > 0.0:
		box(st, Transform3D(basis, c + basis * Vector3(0.0, size.y * 0.5 - band * 0.5, 0.017)), Vector3(size.x, band, 0.004), K_SIGN, band_paint)
	if posts:
		for sx: float in [-1.0, 1.0]:
			var px := sx * size.x * 0.32
			box(st, Transform3D(basis, at + basis * Vector3(px, (bottom + size.y) * 0.5, -0.06)), Vector3(0.09, bottom + size.y, 0.09), K_WOOD, Color(0.82, 0.76, 0.66))
	return Transform3D(basis, c + basis * Vector3(0.0, 0.0, 0.02))


## A dumped sofa (its foot at xf's origin, length along x, its back toward -z).
static func sofa(st: SurfaceTool, xf: Transform3D, paint: Color, sag: float) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.26, 0.0)), Vector3(2.0, 0.3, 0.86), K_FABRIC, paint)
	for sx: float in [-0.48, 0.48]:
		var tilt := Basis(Vector3.RIGHT, sag * (0.12 if sx < 0.0 else -0.05))
		box(st, xf * Transform3D(tilt, Vector3(sx, 0.48, 0.06)), Vector3(0.94, 0.16, 0.66), K_FABRIC, paint * 1.04)
	box(st, xf * Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0.0, 0.62, -0.33)), Vector3(1.96, 0.56, 0.2), K_FABRIC, paint * 0.96)
	for sx: float in [-0.92, 0.92]:
		box(st, xf * Transform3D(Basis(), Vector3(sx, 0.45, 0.02)), Vector3(0.2, 0.42, 0.84), K_FABRIC, paint)
	for sx: float in [-0.9, 0.9]:
		for sz: float in [-0.34, 0.34]:
			box(st, xf * Transform3D(Basis(), Vector3(sx, 0.055, sz)), Vector3(0.06, 0.11, 0.06), K_WOOD, Color(0.4, 0.3, 0.22))


## A dumped armchair.
static func armchair(st: SurfaceTool, xf: Transform3D, paint: Color) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.25, 0.0)), Vector3(0.82, 0.28, 0.8), K_FABRIC, paint)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.46, 0.06)), Vector3(0.56, 0.14, 0.62), K_FABRIC, paint * 1.05)
	box(st, xf * Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0.0, 0.66, -0.3)), Vector3(0.8, 0.6, 0.2), K_FABRIC, paint * 0.95)
	for sx: float in [-0.33, 0.33]:
		box(st, xf * Transform3D(Basis(), Vector3(sx, 0.46, 0.02)), Vector3(0.16, 0.4, 0.78), K_FABRIC, paint)


## A mattress, flat on the ground (or leaning: `lean` radians back from upright against a fence).
static func mattress(st: SurfaceTool, xf: Transform3D, paint: Color, lean: float) -> void:
	if lean > 0.0:
		box(st, xf * Transform3D(Basis(Vector3.RIGHT, -lean), Vector3(0.0, 0.0, 0.0)) * Transform3D(Basis(), Vector3(0.0, 0.95, 0.11)), Vector3(1.4, 1.9, 0.22), K_MATTRESS, paint, 0.0, 0)
	else:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.11, 0.0)), Vector3(1.4, 0.22, 1.9), K_MATTRESS, paint)


## Tyres: `n` in a sloppy stack, or scattered flat when `scatter`.
static func tyres(st: SurfaceTool, xf: Transform3D, n: int, scatter: bool, seed: int) -> void:
	for i in n:
		var h01 := func(tag: String) -> float: return float(absi(hash([seed, i, tag])) % 1000) / 1000.0
		var o := Vector3((h01.call("x") - 0.5) * (1.6 if scatter else 0.1), 0.1 + (0.0 if scatter else 0.2 * float(i)), (h01.call("z") - 0.5) * (1.6 if scatter else 0.1))
		var tilt := Basis(Vector3.UP, h01.call("y") * TAU) * Basis(Vector3.RIGHT, (h01.call("t") - 0.5) * 0.25)
		torus(st, xf * Transform3D(tilt, o), 0.3, 0.1, K_RUBBER, Color.WHITE, 12, 6)


## A boxy television on its back or face.
static func television(st: SurfaceTool, xf: Transform3D, paint: Color) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.24, 0.0)), Vector3(0.66, 0.48, 0.5), K_PLASTIC, paint)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.25, 0.252)), Vector3(0.54, 0.38, 0.01), K_INK, Color(0.05, 0.06, 0.07))


## A shopping cart: wire basket over a frame on four casters, the handle. `tipped` lays it on its
## side.
static func cart(st: SurfaceTool, xf: Transform3D, tipped: bool) -> void:
	var x := xf
	if tipped:
		x = xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.3, 0.0))
	var chrome := Color(0.78, 0.79, 0.8)
	var red := Color(0.62, 0.1, 0.08)
	var bc := Vector3(0.0, 0.72, 0.0)
	var bs := Vector3(0.55, 0.42, 0.9)
	# The basket's five wire faces.
	box(st, x * Transform3D(Basis(), bc + Vector3(0.0, -bs.y * 0.5, 0.0)), Vector3(bs.x, 0.01, bs.z), K_WIRE, chrome, 0.0, 0)
	for sx: float in [-1.0, 1.0]:
		box(st, x * Transform3D(Basis(), bc + Vector3(sx * bs.x * 0.5, 0.0, 0.0)), Vector3(0.01, bs.y, bs.z), K_WIRE, chrome, 0.0, 0)
	for sz: float in [-1.0, 1.0]:
		box(st, x * Transform3D(Basis(), bc + Vector3(0.0, 0.0, sz * bs.z * 0.5)), Vector3(bs.x, bs.y, 0.01), K_WIRE, chrome, 0.0, 0)
	# The rim, the frame legs, the handle with its plastic grip.
	for sz: float in [-1.0, 1.0]:
		box(st, x * Transform3D(Basis(), bc + Vector3(0.0, bs.y * 0.5, sz * bs.z * 0.5)), Vector3(bs.x, 0.02, 0.02), K_GALV, chrome)
	for sx: float in [-1.0, 1.0]:
		box(st, x * Transform3D(Basis(), bc + Vector3(sx * bs.x * 0.5, bs.y * 0.5, 0.0)), Vector3(0.02, 0.02, bs.z), K_GALV, chrome)
		for sz: float in [-1.0, 1.0]:
			box(st, x * Transform3D(Basis(), Vector3(sx * 0.22, 0.28, sz * 0.38)), Vector3(0.025, 0.5, 0.025), K_GALV, chrome)
			IndustrialKit.cyl(st, x * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * 0.22 + 0.02, 0.05, sz * 0.38)), 0.05, 0.035, K_PLASTIC, Color(0.1, 0.1, 0.1), 8)
			tris += 24
	box(st, x * Transform3D(Basis(), Vector3(0.0, 0.03 + 0.06, 0.0)), Vector3(0.46, 0.02, 0.82), K_GALV, chrome)
	box(st, x * Transform3D(Basis(), bc + Vector3(0.0, bs.y * 0.5 + 0.12, -bs.z * 0.5 - 0.06)), Vector3(bs.x + 0.04, 0.035, 0.035), K_PLASTIC, red)


## A rubble pile: a low mound of earth with broken concrete and brick on and round it.
static func rubble(st: SurfaceTool, at: Vector3, r: float, seed: int, brick: bool) -> void:
	var h := r * 0.42
	IndustrialKit.cone(st, Transform3D(Basis(Vector3.UP, float(seed % 100)), at - Vector3.UP * 0.05), r, h, K_EARTH, Color(0.95, 0.88, 0.76), 9)
	tris += 9
	var n := clampi(int(r * 9.0), 8, 26)
	for i in n:
		var u := float(absi(hash([seed, i, "u"])) % 1000) / 1000.0
		var v := float(absi(hash([seed, i, "v"])) % 1000) / 1000.0
		var w := float(absi(hash([seed, i, "w"])) % 1000) / 1000.0
		var a := u * TAU
		var d := sqrt(v) * r * 1.05
		var y := maxf(h * (1.0 - d / r), 0.0)
		var size := Vector3(lerpf(0.18, 0.7, w), lerpf(0.08, 0.22, v), lerpf(0.15, 0.5, u))
		var rot := Basis(Vector3.UP, w * TAU) * Basis(Vector3.RIGHT, (u - 0.5) * 1.2) * Basis(Vector3.FORWARD, (v - 0.5) * 1.0)
		var is_brick := brick and w > 0.55
		box(st, Transform3D(rot, at + Vector3(cos(a) * d, y + size.y * 0.3, sin(a) * d)), size, K_BRICK if is_brick else K_CONCRETE, Color(0.92, 0.9, 0.86) if not is_brick else Color.WHITE, 0.0, 0)


## A traffic cone (foot at xf's origin).
static func cone(st: SurfaceTool, xf: Transform3D) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.015, 0.0)), Vector3(0.36, 0.03, 0.36), K_PLASTIC, Color(0.08, 0.08, 0.08))
	IndustrialKit.cone(st, xf * Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)), 0.14, 0.68, K_PLASTIC, Color(0.95, 0.36, 0.06), 10)
	tris += 10


## The car park attendant's booth (foot at xf's origin, its window and door toward +z): a painted
## sheet-metal hut with windows on three sides, a flat roof with an overhang, a lamp inside.
static func booth(st: SurfaceTool, xf: Transform3D, paint: Color) -> void:
	var w := 1.6
	var d := 1.5
	var h := 2.25
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.06, 0.0)), Vector3(w + 0.2, 0.12, d + 0.2), K_CONCRETE, Color(0.85, 0.84, 0.8))
	# Walls: a solid skirt to 1.0 m, windows to 2.0 m, a band over them, on three sides; the back
	# (-z) solid with the door.
	var y0 := 0.12
	box(st, xf * Transform3D(Basis(), Vector3(0.0, y0 + 0.5, 0.0)), Vector3(w, 1.0, d), K_SHEET, paint)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, y0 + 1.5, 0.0)), Vector3(w - 0.08, 1.0, d - 0.08), K_GLASS, Color.WHITE)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(st, xf * Transform3D(Basis(), Vector3(sx * (w * 0.5 - 0.03), y0 + 1.5, sz * (d * 0.5 - 0.03))), Vector3(0.07, 1.0, 0.07), K_SHEET, paint)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, y0 + 1.5, -d * 0.5 + 0.02)), Vector3(w, 1.0, 0.06), K_SHEET, paint)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, y0 + 2.06, 0.0)), Vector3(w, 0.12, d), K_SHEET, paint)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, y0 + 2.17, 0.0)), Vector3(w + 0.5, 0.1, d + 0.5), K_GALV, Color(0.66, 0.67, 0.66))
	# The door in the back, the lamp under the overhang over the window.
	box(st, xf * Transform3D(Basis(), Vector3(0.3, y0 + 1.0, -d * 0.5 - 0.01)), Vector3(0.7, 1.95, 0.02), K_SHEET, paint * 0.8)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, y0 + 2.06, d * 0.5 + 0.12)), Vector3(0.14, 0.06, 0.1), K_LAMP, Color.WHITE)
	# A stool's back and a cash box on the counter, seen through the glass.
	box(st, xf * Transform3D(Basis(), Vector3(0.0, y0 + 1.0, d * 0.5 - 0.25)), Vector3(w - 0.2, 0.04, 0.4), K_WOOD, Color(0.7, 0.62, 0.5))
	box(st, xf * Transform3D(Basis(), Vector3(-0.3, y0 + 1.09, d * 0.5 - 0.25)), Vector3(0.28, 0.14, 0.2), K_PLASTIC, Color(0.12, 0.3, 0.55))
	box(st, xf * Transform3D(Basis(), Vector3(0.1, y0 + 0.65, 0.0)), Vector3(0.36, 0.06, 0.36), K_PLASTIC, Color(0.1, 0.1, 0.1))
