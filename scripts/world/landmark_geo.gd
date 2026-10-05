class_name LandmarkGeo
extends RefCounted
## Geometry for the hand-modelled landmarks (the downtown civic set): one SurfaceTool per
## material, committed as ONE MeshInstance3D with a surface per material, so a whole building is
## a handful of draw calls however many walls, bands, bevels and steps it is made of.
##
## Conventions, because getting them wrong silently turns faces inside out:
## - Front faces wind CLOCKWISE seen from the front (Godot's default). Nothing here trusts the
##   caller's winding: every triangle is given the normal it should face, and is flipped to match
##   (`tri()`), so a builder only has to know which way is out.
## - Footprint polygons run COUNTER-CLOCKWISE on the map (north up, +X right, +Z down), i.e. with a
##   negative signed area in (x, z). `ccw()` makes any polygon so. Walls then face outward.
## - UV is in METRES: along a wall, u is the distance from its left end seen from outside and v is
##   the WORLD height; on roofs and floors (u, v) is world (x, z). The landmark shaders
##   (landmark_facade, curtain_glass, brushed_steel, clay_roof) lay windows, joints, bands,
##   mullions and tiles in those metres, so geometry and pattern line up without a texture.
## - COLOR is a per-vertex tint the shaders multiply in, so one material covers many tones.
## - `collide` adds the triangle to one ConcavePolygonShape3D for the things you stand on that are
##   not boxes (a domed roof, a leaning drum); boxes use `shape_box()` (cheaper to collide with).

## Per surface key: {"v", "nrm", "uv", "col" (packed arrays), "mat": Material, "n": triangles}
var _surfaces: Dictionary = {}
var _order: Array[String] = []
## World-space triangles for one ConcavePolygonShape3D.
var collision := PackedVector3Array()
## Triangles added, for the cost notes in the builders.
var triangles: int = 0
## Every triangle any LandmarkGeo has committed, and the surfaces (draw calls) they went into -
## for probes and the smoke test, which cannot read mesh data back under the dummy renderer.
static var committed_triangles: int = 0
static var committed_surfaces: int = 0


## Registers a surface (a material slot). Calling it again with the same key is a no-op.
func use(key: String, mat: Material) -> void:
	if _surfaces.has(key):
		return
	# Packed arrays, not SurfaceTool calls per vertex: four engine calls a vertex was most of the
	# build time of a lattice-heavy landmark.
	_surfaces[key] = {"v": PackedVector3Array(), "nrm": PackedVector3Array(), "uv": PackedVector2Array(),
		"col": PackedColorArray(), "mat": mat, "n": 0}
	_order.append(key)


func has(key: String) -> bool:
	return _surfaces.has(key)




## One triangle facing `want` (the outward direction). Winding is fixed to match, so callers
## never need to think about it. Per-corner normals when `na` is non-zero, else flat.
func tri(key: String, a: Vector3, b: Vector3, c: Vector3, want: Vector3, ua: Vector2, ub: Vector2, uc: Vector2,
		col: Color = Color.WHITE, collide: bool = false, na: Vector3 = Vector3.ZERO, nb: Vector3 = Vector3.ZERO, nc: Vector3 = Vector3.ZERO) -> void:
	var s: Dictionary = _surfaces[key]
	var flat := (c - a).cross(b - a)
	if flat.length_squared() < 1e-12:
		return
	if flat.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
		var tn := nb
		nb = nc
		nc = tn
		flat = -flat
	var fn := flat.normalized()
	if na == Vector3.ZERO:
		na = fn
		nb = fn
		nc = fn
	var vs: PackedVector3Array = s.v
	vs.append(a)
	vs.append(b)
	vs.append(c)
	var ns: PackedVector3Array = s.nrm
	ns.append(na)
	ns.append(nb)
	ns.append(nc)
	var us: PackedVector2Array = s.uv
	us.append(ua)
	us.append(ub)
	us.append(uc)
	var cs: PackedColorArray = s.col
	cs.append(col)
	cs.append(col)
	cs.append(col)
	s.n += 1
	triangles += 1
	if collide:
		collision.append_array(PackedVector3Array([a, b, c]))


## A quad a-b-c-d (in order round its edge, either way) facing `want`.
func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, col: Color = Color.WHITE, collide: bool = false) -> void:
	tri(key, a, b, c, want, ua, ub, uc, col, collide)
	tri(key, a, c, d, want, ua, uc, ud, col, collide)


## A quad with a smooth normal per corner (curved surfaces). `want` is only used for winding.
func quad_n(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, col: Color = Color.WHITE, collide: bool = false) -> void:
	var want := (na + nb + nc + nd)
	tri(key, a, b, c, want, ua, ub, uc, col, collide, na, nb, nc)
	tri(key, a, c, d, want, ua, uc, ud, col, collide, na, nc, nd)


## A vertical wall from p0 to p1 (map XZ) between heights y0 and y1, facing the outward side of a
## CCW footprint, i.e. to the right of p0 -> p1 seen from above with north up. u runs from `u0`
## at p0; the return value is u at p1, so a run of walls can carry u round a building.
func wall(key: String, p0: Vector2, p1: Vector2, y0: float, y1: float, col: Color = Color.WHITE,
		collide: bool = false, u0: float = 0.0) -> float:
	var d := p1 - p0
	var length := d.length()
	if length < 1e-4:
		return u0
	var n := Vector3(-d.y, 0.0, d.x).normalized()
	var a := Vector3(p0.x, y0, p0.y)
	var b := Vector3(p0.x, y1, p0.y)
	var c := Vector3(p1.x, y1, p1.y)
	var e := Vector3(p1.x, y0, p1.y)
	quad(key, a, b, c, e, n, Vector2(u0, y0), Vector2(u0, y1), Vector2(u0 + length, y1), Vector2(u0 + length, y0), col, collide)
	return u0 + length


## Signed area of a map polygon in (x, z); negative is CCW on the map (north up).
static func map_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## `poly` in the winding the builders expect (CCW on the map).
static func ccw(poly: PackedVector2Array) -> PackedVector2Array:
	if map_area(poly) > 0.0:
		var r := poly.duplicate()
		r.reverse()
		return r
	return poly


## A flat horizontal polygon at height y, facing up (or down with `down`), UV = world (x, z).
func cap(key: String, poly: PackedVector2Array, y: float, col: Color = Color.WHITE, collide: bool = false, down: bool = false) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	var want := Vector3.DOWN if down else Vector3.UP
	for i in range(0, idx.size(), 3):
		var a := poly[idx[i]]
		var b := poly[idx[i + 1]]
		var c := poly[idx[i + 2]]
		tri(key, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), want, a, b, c, col, collide)


## An extruded footprint: walls from y0 to y1 plus a top cap (and a bottom one if asked).
func prism(key: String, poly: PackedVector2Array, y0: float, y1: float, col: Color = Color.WHITE,
		collide: bool = false, top: bool = true, bottom: bool = false, top_key: String = "") -> void:
	var p := ccw(poly)
	var u := 0.0
	for i in p.size():
		u = wall(key, p[i], p[(i + 1) % p.size()], y0, y1, col, collide, u)
	if top:
		cap(top_key if top_key != "" else key, p, y1, col, collide)
	if bottom:
		cap(key, p, y0, col, false, true)


## An axis-aligned or turned box. `basis` turns it (and may scale it). UVs are metres on every
## face: u from the face's left edge seen from outside, v the WORLD height (walls) or (x, z) on
## the top and bottom. `u_fit` > 0 stretches u on each wall so its width is a whole number of
## that pitch, which is how a window grid never ends in half a window. `bevel` chamfers every
## edge (the catch-light a real corner has), at 44 triangles instead of 12.
func box(key: String, center: Vector3, size: Vector3, col: Color = Color.WHITE, basis: Basis = Basis(),
		bevel: float = 0.0, collide: bool = false, u_fit: float = 0.0, bottom: bool = false) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	# A bevelled box always closes its underside: its walls stop a bevel short of the bottom edge,
	# and without the bottom chamfers a floating one (a cornice, a beam) shows a slot of sky.
	if b > 0.0:
		bottom = true
	var xf := Transform3D(basis, center)
	# Faces: axis, sign. Walls first, then top, then (optionally) bottom.
	for f: Array in [[0, 1.0], [0, -1.0], [2, 1.0], [2, -1.0], [1, 1.0], [1, -1.0]]:
		var axis: int = f[0]
		var sgn: float = f[1]
		if axis == 1 and sgn < 0.0 and not bottom:
			continue
		var n_local := Vector3.ZERO
		n_local[axis] = sgn
		# The face's two in-plane axes: across (u) and up (v), seen from outside.
		var ua := 2 if axis == 0 else 0
		var va := 2 if axis == 1 else 1
		var right := Vector3.ZERO
		# Right-hand direction seen from outside the face (see the header): +X face -> -Z,
		# -X -> +Z, +Z -> +X, -Z -> -X, and for the top (seen from above, north up) +X.
		if axis == 0:
			right[2] = -sgn
		elif axis == 2:
			right[0] = sgn
		else:
			right[0] = 1.0
		var up := Vector3.ZERO
		if axis == 1:
			up[2] = -1.0
		else:
			up[1] = 1.0
		var hu: float = h[ua] - b
		var hv: float = h[va] - b
		var o := n_local * h[axis]
		var corners := [o - right * hu - up * hv, o - right * hu + up * hv, o + right * hu + up * hv, o + right * hu - up * hv]
		var world: Array[Vector3] = []
		for c: Vector3 in corners:
			world.append(xf * c)
		var want := (basis * n_local).normalized()
		var uvs: Array[Vector2] = []
		var width: float = size[ua]
		var scale_u := 1.0
		if u_fit > 0.0 and axis != 1:
			scale_u = maxf(1.0, roundf(width / u_fit)) * u_fit / width
		for i in 4:
			var cl: Vector3 = corners[i]
			if axis == 1:
				var w: Vector3 = world[i]
				uvs.append(Vector2(w.x, w.z))
			else:
				var across := (cl.dot(right) + h[ua]) * scale_u
				uvs.append(Vector2(across, world[i].y))
		quad(key, world[0], world[1], world[2], world[3], want, uvs[0], uvs[1], uvs[2], uvs[3], col, collide)
	if b <= 0.0:
		return
	# The chamfers: a strip along each of the twelve edges and a triangle at each of the eight
	# corners, joining the inset faces.
	var pt := func(v: Vector3) -> Vector3:
		return xf * v
	for e: Array in [[0, 1], [0, 2], [1, 2]]:
		var a1: int = e[0]
		var a2: int = e[1]
		var a3: int = 3 - a1 - a2
		for s1: float in [-1.0, 1.0]:
			for s2: float in [-1.0, 1.0]:
				if ((a1 == 1 and s1 < 0.0) or (a2 == 1 and s2 < 0.0)) and not bottom:
					continue
				var p0 := Vector3.ZERO
				p0[a1] = s1 * h[a1]
				p0[a2] = s2 * (h[a2] - b)
				var p1 := Vector3.ZERO
				p1[a1] = s1 * (h[a1] - b)
				p1[a2] = s2 * h[a2]
				var ext := Vector3.ZERO
				ext[a3] = h[a3] - b
				var n := Vector3.ZERO
				n[a1] = s1
				n[a2] = s2
				var want: Vector3 = (basis * n).normalized()
				var q0: Vector3 = pt.call(p0 - ext)
				var q1: Vector3 = pt.call(p1 - ext)
				var q2: Vector3 = pt.call(p1 + ext)
				var q3: Vector3 = pt.call(p0 + ext)
				var along: float = (h[a3] - b) * 2.0
				quad(key, q0, q1, q2, q3, want, Vector2(0.0, q0.y), Vector2(b, q1.y), Vector2(b + along, q2.y), Vector2(along, q3.y), col, collide)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			if sy < 0.0 and not bottom:
				continue
			for sz: float in [-1.0, 1.0]:
				var c0: Vector3 = pt.call(Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b)))
				var c1: Vector3 = pt.call(Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b)))
				var c2: Vector3 = pt.call(Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z))
				var want: Vector3 = (basis * Vector3(sx, sy, sz)).normalized()
				tri(key, c0, c1, c2, want, Vector2(0.0, c0.y), Vector2(b, c1.y), Vector2(0.0, c2.y), col, collide)


## A point on an ellipse of radii r (x, z) around c at angle t (from +X toward +Z).
static func ell(c: Vector2, r: Vector2, t: float) -> Vector2:
	return c + Vector2(r.x * cos(t), r.y * sin(t))


## The outward normal of that ellipse at angle t, in map XZ.
static func ell_normal(r: Vector2, t: float) -> Vector2:
	return Vector2(cos(t) / r.x, sin(t) / r.y).normalized()


## Arc length of an ellipse from angle a0 to a1 (numerically), for u along a curved wall.
static func ell_arc(r: Vector2, a0: float, a1: float, steps: int = 32) -> float:
	var s := 0.0
	var prev := ell(Vector2.ZERO, r, a0)
	for i in range(1, steps + 1):
		var p := ell(Vector2.ZERO, r, lerpf(a0, a1, float(i) / float(steps)))
		s += p.distance_to(prev)
		prev = p
	return s


## A curved band round an ellipse centred on `c` (map XZ): radii `r0` at height y0 growing (or
## shrinking) to `r1` at y1, so one call is a leaning glass wall or an overhanging drum. From
## angle a0 to a1 in `segs` pieces, smooth-shaded, facing out (or in with `inward`). u is the arc
## length from a0 (plus u0), v the world height.
func band(key: String, c: Vector2, r0: Vector2, r1: Vector2, y0: float, y1: float, a0: float, a1: float, segs: int,
		col: Color = Color.WHITE, collide: bool = false, inward: bool = false, u0: float = 0.0) -> void:
	var u := u0
	var sign := -1.0 if inward else 1.0
	var prev_b := ell(c, r0, a0)
	var prev_t := ell(c, r1, a0)
	var prev_n := _band_normal(r0, r1, y1 - y0, a0) * sign
	for i in range(1, segs + 1):
		var t := lerpf(a0, a1, float(i) / float(segs))
		var pb := ell(c, r0, t)
		var ptop := ell(c, r1, t)
		var n := _band_normal(r0, r1, y1 - y0, t) * sign
		var du := (pb.distance_to(prev_b) + ptop.distance_to(prev_t)) * 0.5
		quad_n(key, Vector3(prev_b.x, y0, prev_b.y), Vector3(prev_t.x, y1, prev_t.y), Vector3(ptop.x, y1, ptop.y), Vector3(pb.x, y0, pb.y),
			prev_n, prev_n, n, n, Vector2(u, y0), Vector2(u, y1), Vector2(u + du, y1), Vector2(u + du, y0), col, collide)
		u += du
		prev_b = pb
		prev_t = ptop
		prev_n = n


## Normal of a leaning elliptical band: the ellipse's own outward normal tipped by the lean.
static func _band_normal(r0: Vector2, r1: Vector2, h: float, t: float) -> Vector3:
	var r := (r0 + r1) * 0.5
	var n2 := ell_normal(r, t)
	# How far the wall moves outward per metre of height along that normal.
	var d := ell(Vector2.ZERO, r1, t) - ell(Vector2.ZERO, r0, t)
	var lean := d.dot(n2) / maxf(h, 0.01)
	return Vector3(n2.x, -lean, n2.y).normalized()


## A flat elliptical ring (annulus) at height y between radii `r_in` and `r_out`, facing up (or
## down). For the lip of a drum, a soffit, a terrace edge.
func ring_flat(key: String, c: Vector2, r_in: Vector2, r_out: Vector2, y: float, a0: float, a1: float, segs: int,
		col: Color = Color.WHITE, collide: bool = false, down: bool = false) -> void:
	var want := Vector3.DOWN if down else Vector3.UP
	var pi := ell(c, r_in, a0)
	var po := ell(c, r_out, a0)
	for i in range(1, segs + 1):
		var t := lerpf(a0, a1, float(i) / float(segs))
		var ni := ell(c, r_in, t)
		var no := ell(c, r_out, t)
		quad(key, Vector3(pi.x, y, pi.y), Vector3(po.x, y, po.y), Vector3(no.x, y, no.y), Vector3(ni.x, y, ni.y), want,
			pi, po, no, ni, col, collide)
		pi = ni
		po = no


## A shallow elliptical dome from its rim at y_rim rising `rise` at the centre (a paraboloid,
## which is the profile of a real long-span roof), UV = world (x, z).
func dome(key: String, c: Vector2, r: Vector2, y_rim: float, rise: float, segs: int, rings: int,
		col: Color = Color.WHITE, collide: bool = false) -> void:
	var at := func(rho: float, t: float) -> Vector3:
		var p := ell(c, r * rho, t)
		return Vector3(p.x, y_rim + rise * (1.0 - rho * rho), p.y)
	var nrm := func(rho: float, t: float) -> Vector3:
		# Gradient of y = rise (1 - (x/rx)^2 - (z/rz)^2).
		var dx := -2.0 * rise * rho * cos(t) / r.x
		var dz := -2.0 * rise * rho * sin(t) / r.y
		return Vector3(-dx, 1.0, -dz).normalized()
	for j in rings:
		var r0 := float(j) / float(rings)
		var r1 := float(j + 1) / float(rings)
		for i in segs:
			var t0 := TAU * float(i) / float(segs)
			var t1 := TAU * float(i + 1) / float(segs)
			var a: Vector3 = at.call(r0, t0)
			var b: Vector3 = at.call(r1, t0)
			var cc: Vector3 = at.call(r1, t1)
			var d: Vector3 = at.call(r0, t1)
			quad_n(key, a, b, cc, d, nrm.call(r0, t0), nrm.call(r1, t0), nrm.call(r1, t1), nrm.call(r0, t1),
				Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(cc.x, cc.z), Vector2(d.x, d.z), col, collide)


## A cylinder (or a cone frustum) standing at `base`, `segs` sides, smooth sides, a flat top.
func cylinder(key: String, base: Vector3, radius: float, height: float, segs: int = 12,
		col: Color = Color.WHITE, top_radius: float = -1.0, collide: bool = false, top: bool = true) -> void:
	var rt := radius if top_radius < 0.0 else top_radius
	var c := Vector2(base.x, base.z)
	band(key, c, Vector2(radius, radius), Vector2(rt, rt), base.y, base.y + height, 0.0, TAU, segs, col, collide)
	if top and rt > 0.0:
		var poly := PackedVector2Array()
		for i in segs:
			poly.append(ell(c, Vector2(rt, rt), -TAU * float(i) / float(segs)))
		cap(key, ccw(poly), base.y + height, col, collide)


## Commits every surface into one MeshInstance3D under `parent`. Tangents are generated for the
## normal-mapped landmark shaders. Returns the node (null if nothing was added).
func commit(parent: Node3D, node_name: String, shadow: bool = true, draw_distance: float = 0.0) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for key in _order:
		var s: Dictionary = _surfaces[key]
		# A slot the builder registered and then did not use (a far copy skips most detail).
		if int(s.n) == 0:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.v
		arrays[Mesh.ARRAY_NORMAL] = s.nrm
		arrays[Mesh.ARRAY_TEX_UV] = s.uv
		arrays[Mesh.ARRAY_COLOR] = s.col
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		st.index()
		st.generate_tangents()
		var before := mesh.get_surface_count()
		st.commit(mesh)
		if mesh.get_surface_count() > before:
			mesh.surface_set_material(before, s.mat)
	_surfaces.clear()
	_order.clear()
	committed_triangles += triangles
	committed_surfaces += mesh.get_surface_count()
	triangles = 0
	if mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if draw_distance > 0.0:
		mi.visibility_range_end = draw_distance
		mi.visibility_range_end_margin = draw_distance * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mi


## Adds the collected curved-surface collision to `statics` as one concave shape.
func commit_collision(statics: StaticBody3D) -> void:
	if statics == null or collision.is_empty():
		collision = PackedVector3Array()
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	statics.add_child(cs)
	collision = PackedVector3Array()


## A box collision shape, turned by `basis` (rotation only).
static func shape_box(statics: StaticBody3D, center: Vector3, size: Vector3, basis: Basis = Basis()) -> void:
	if statics == null:
		return
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, center)
	statics.add_child(cs)


## A yaw basis (facing a map direction), for boxes and batch instances.
static func yaw(a: float) -> Basis:
	return Basis(Vector3.UP, a)
