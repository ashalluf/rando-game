class_name PierMesh
extends RefCounted
## Geometry for the pier amusement park (PierPark, FerrisWheel, PierCoaster): one set of packed
## arrays per material slot, committed as ONE MeshInstance3D with a surface per slot, so a whole
## ride or a whole midway is a handful of draws however many tubes, slats and bulbs it is.
##
## What a vertex IS rides in UV2 (shaders/pier_park.gdshader reads it):
##   UV2.x  the surface kind (PierMesh.K_*): paint, metal, canvas stripes, bulb, LED, lit sign,
##          window, rubber, neon - one material covers a whole ride.
##   UV2.y  the animation index the ride shader moves it by (a gondola, a horse, a bumper car:
##          index + 1; 0 moves with the ride's body), or for an LED the spoke it lies on.
## COLOR is the paint in sRGB (the shader decodes it on both renderers), UV is in metres along the
## surface (stripes, bulb spacing, LED dots and board seams are laid in those metres).
##
## Winding: every triangle is given the direction it must face and is flipped to match (the
## LandmarkGeo rule), so a builder never has to think about vertex order.

const K_PAINT := 0
const K_METAL := 1
const K_CANVAS := 2
const K_BULB := 3
const K_LED := 4
const K_SIGN := 5
const K_WINDOW := 6
const K_BOARDS := 7
const K_RUBBER := 8
const K_NEON := 9
const K_CHROME := 10
const K_GOLD := 11

## Per slot: {"v", "n", "uv", "uv2", "col", "mat"}
var _slots: Dictionary = {}
var _order: Array[String] = []
## Triangles added so far (the cost notes and the checks).
var triangles: int = 0
## Current kind and animation index, set by the builders before they add geometry.
var kind: int = K_PAINT
var anim: float = 0.0
## World-space triangles for one concave collision shape (things you stand on that are not boxes).
var collision := PackedVector3Array()
var collide := false


func use(key: String, mat: Material) -> void:
	if _slots.has(key):
		return
	_slots[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
		"uv2": PackedVector2Array(), "col": PackedColorArray(), "mat": mat}
	_order.append(key)


var _slot: Dictionary = {}
var _slot_key: String = ""


## Selects the slot later geometry goes into.
func slot(key: String) -> void:
	_slot_key = key
	_slot = _slots[key]


func tri(a: Vector3, b: Vector3, c: Vector3, want: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col: Color,
		na: Vector3 = Vector3.ZERO, nb: Vector3 = Vector3.ZERO, nc: Vector3 = Vector3.ZERO) -> void:
	var flat := (c - a).cross(b - a)
	if flat.length_squared() < 1e-14:
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
	if na == Vector3.ZERO:
		na = flat.normalized()
		nb = na
		nc = na
	var vs: PackedVector3Array = _slot.v
	vs.append(a)
	vs.append(b)
	vs.append(c)
	var ns: PackedVector3Array = _slot.n
	ns.append(na)
	ns.append(nb)
	ns.append(nc)
	var us: PackedVector2Array = _slot.uv
	us.append(ua)
	us.append(ub)
	us.append(uc)
	var u2: PackedVector2Array = _slot.uv2
	var d := Vector2(float(kind), anim)
	u2.append(d)
	u2.append(d)
	u2.append(d)
	var cs: PackedColorArray = _slot.col
	cs.append(col)
	cs.append(col)
	cs.append(col)
	triangles += 1
	if collide:
		collision.append_array(PackedVector3Array([a, b, c]))


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, col: Color) -> void:
	tri(a, b, c, want, ua, ub, uc, col)
	tri(a, c, d, want, ua, uc, ud, col)


## A smooth quad (per-corner normals); `want` is the average of them.
func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, col: Color) -> void:
	var want := na + nb + nc + nd
	tri(a, b, c, want, ua, ub, uc, col, na, nb, nc)
	tri(a, c, d, want, ua, uc, ud, col, na, nc, nd)


## A box of `size` placed by `xf` (its centre at xf.origin). UVs in metres on every face (u
## across, v up the face; top and bottom in the box's own x/z). `bevel` chamfers the vertical
## edges only (the catch-light on a post or a fascia), at 8 more triangles.
func box(xf: Transform3D, size: Vector3, col: Color, bevel: float = 0.0, bottom: bool = true) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, h.z) * 0.8)
	# The outline in plan (x, z), CCW from above when looking down -Y with +X right, +Z down.
	var ring: Array[Vector2] = []
	if b > 0.0:
		ring = [Vector2(h.x - b, -h.z), Vector2(h.x, -h.z + b), Vector2(h.x, h.z - b), Vector2(h.x - b, h.z),
			Vector2(-h.x + b, h.z), Vector2(-h.x, h.z - b), Vector2(-h.x, -h.z + b), Vector2(-h.x + b, -h.z)]
	else:
		ring = [Vector2(h.x, -h.z), Vector2(h.x, h.z), Vector2(-h.x, h.z), Vector2(-h.x, -h.z)]
	var u := 0.0
	for i in ring.size():
		var p0: Vector2 = ring[i]
		var p1: Vector2 = ring[(i + 1) % ring.size()]
		var a := xf * Vector3(p0.x, -h.y, p0.y)
		var bb := xf * Vector3(p0.x, h.y, p0.y)
		var c := xf * Vector3(p1.x, h.y, p1.y)
		var d := xf * Vector3(p1.x, -h.y, p1.y)
		var mid2 := (p0 + p1) * 0.5
		var want := xf.basis * Vector3(mid2.x, 0.0, mid2.y)
		var w := p0.distance_to(p1)
		quad(a, bb, c, d, want, Vector2(u, 0.0), Vector2(u, size.y), Vector2(u + w, size.y), Vector2(u + w, 0.0), col)
		u += w
	var up := xf.basis.y.normalized()
	for s: float in ([1.0, -1.0] if bottom else [1.0]):
		var pts: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for p: Vector2 in ring:
			pts.append(xf * Vector3(p.x, s * h.y, p.y))
			uvs.append(p + Vector2(h.x, h.z))
		for i in range(1, pts.size() - 1):
			tri(pts[0], pts[i], pts[i + 1], up * s, uvs[0], uvs[i], uvs[i + 1], col)


## An axis-aligned box from its centre and size, with an optional yaw.
func abox(center: Vector3, size: Vector3, col: Color, yaw: float = 0.0, bevel: float = 0.0, bottom: bool = true) -> void:
	box(Transform3D(Basis(Vector3.UP, yaw), center), size, col, bevel, bottom)


## A box stretched between two points (a beam, a brace, a slat): `w` across, `t` thick, `up` is
## the direction its thickness is measured along (it must not be parallel to b - a).
func beam(a: Vector3, b: Vector3, w: float, t: float, col: Color, up: Vector3 = Vector3.UP) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-4:
		return
	var z := d / length
	var x := up.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, t, length), col)


## A round tube (a frustum) from a to b, radii ra -> rb, `sides` facets, smooth shaded, open ends
## unless `caps`. u runs round it in metres, v along it from a.
func tube(a: Vector3, b: Vector3, ra: float, rb: float, col: Color, sides: int = 6, caps: bool = false) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-4:
		return
	var z := d / length
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x)
	var slope := (ra - rb) / length
	for i in sides:
		var t0 := TAU * float(i) / float(sides)
		var t1 := TAU * float(i + 1) / float(sides)
		var r0 := x * cos(t0) + y * sin(t0)
		var r1 := x * cos(t1) + y * sin(t1)
		var n0 := (r0 + z * slope).normalized()
		var n1 := (r1 + z * slope).normalized()
		var u0 := t0 * ra
		var u1 := t1 * ra
		quad_n(a + r0 * ra, b + r0 * rb, b + r1 * rb, a + r1 * ra, n0, n0, n1, n1,
			Vector2(u0, 0.0), Vector2(u0, length), Vector2(u1, length), Vector2(u1, 0.0), col)
	if caps:
		for e: Array in [[a, ra, -z], [b, rb, z]]:
			var c: Vector3 = e[0]
			var r: float = e[1]
			var n: Vector3 = e[2]
			for i in sides:
				var t0 := TAU * float(i) / float(sides)
				var t1 := TAU * float(i + 1) / float(sides)
				tri(c, c + (x * cos(t0) + y * sin(t0)) * r, c + (x * cos(t1) + y * sin(t1)) * r, n,
					Vector2.ZERO, Vector2(r, 0.0), Vector2(0.0, r), col)


## A tube swept along a polyline (a rail, a hand rail, a hose): the frame is carried along with
## minimal twist; `closed` joins the last point to the first.
func sweep(pts: PackedVector3Array, r: float, col: Color, sides: int = 6, closed: bool = false, up_hint: Vector3 = Vector3.UP) -> void:
	var n := pts.size()
	if n < 2:
		return
	var frames: Array[Basis] = []
	var tangents: Array[Vector3] = []
	for i in n:
		var prev := pts[i - 1] if (i > 0 or closed) else pts[i]
		var next := pts[(i + 1) % n] if (i < n - 1 or closed) else pts[i]
		tangents.append((next - prev).normalized())
	var x := up_hint.cross(tangents[0])
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(tangents[0])
	x = x.normalized()
	for i in n:
		var t := tangents[i]
		x = (x - t * x.dot(t)).normalized()
		var y := t.cross(x)
		frames.append(Basis(x, y, t))
	var along := 0.0
	var count := n if closed else n - 1
	for i in count:
		var j := (i + 1) % n
		var seg := pts[i].distance_to(pts[j])
		var f0: Basis = frames[i]
		var f1: Basis = frames[j]
		for k in sides:
			var t0 := TAU * float(k) / float(sides)
			var t1 := TAU * float(k + 1) / float(sides)
			var a0 := f0.x * cos(t0) + f0.y * sin(t0)
			var a1 := f0.x * cos(t1) + f0.y * sin(t1)
			var b0 := f1.x * cos(t0) + f1.y * sin(t0)
			var b1 := f1.x * cos(t1) + f1.y * sin(t1)
			quad_n(pts[i] + a0 * r, pts[j] + b0 * r, pts[j] + b1 * r, pts[i] + a1 * r, a0, b0, b1, a1,
				Vector2(t0 * r, along), Vector2(t0 * r, along + seg), Vector2(t1 * r, along + seg), Vector2(t1 * r, along), col)
		along += seg


## An ellipsoid of radii `r` placed by `xf`, `seg` round and `rings` pole to pole, smooth.
func ellipsoid(xf: Transform3D, r: Vector3, col: Color, seg: int = 10, rings: int = 6) -> void:
	var pt := func(th: float, ph: float) -> Array:
		var s := Vector3(cos(th) * sin(ph), cos(ph), sin(th) * sin(ph))
		var p := xf * Vector3(s.x * r.x, s.y * r.y, s.z * r.z)
		var nl := Vector3(s.x / r.x, s.y / r.y, s.z / r.z)
		return [p, (xf.basis.inverse().transposed() * nl).normalized()]
	for j in rings:
		var p0 := PI * float(j) / float(rings)
		var p1 := PI * float(j + 1) / float(rings)
		for i in seg:
			var t0 := TAU * float(i) / float(seg)
			var t1 := TAU * float(i + 1) / float(seg)
			var a: Array = pt.call(t0, p0)
			var b: Array = pt.call(t0, p1)
			var c: Array = pt.call(t1, p1)
			var d: Array = pt.call(t1, p0)
			var uv0 := Vector2(t0 * r.x, p0 * r.y)
			var uv1 := Vector2(t1 * r.x, p1 * r.y)
			quad_n(a[0], b[0], c[0], d[0], a[1], b[1], c[1], d[1], uv0, Vector2(uv0.x, uv1.y), uv1, Vector2(uv1.x, uv0.y), col)


## A flat disc / annulus at height y round (cx, cz) in the slot's space, facing `n`.
func ring_flat(c: Vector3, r_in: float, r_out: float, segs: int, col: Color, n: Vector3 = Vector3.UP, a0: float = 0.0, a1: float = TAU) -> void:
	for i in segs:
		var t0 := lerpf(a0, a1, float(i) / float(segs))
		var t1 := lerpf(a0, a1, float(i + 1) / float(segs))
		var i0 := c + Vector3(cos(t0), 0.0, sin(t0)) * r_in
		var o0 := c + Vector3(cos(t0), 0.0, sin(t0)) * r_out
		var i1 := c + Vector3(cos(t1), 0.0, sin(t1)) * r_in
		var o1 := c + Vector3(cos(t1), 0.0, sin(t1)) * r_out
		if r_in <= 0.0:
			tri(c, o0, o1, n, Vector2.ZERO, Vector2(t0 * r_out, r_out), Vector2(t1 * r_out, r_out), col)
		else:
			quad(i0, o0, o1, i1, n, Vector2(t0 * r_out, r_in), Vector2(t0 * r_out, r_out), Vector2(t1 * r_out, r_out), Vector2(t1 * r_out, r_in), col)


## A cone / frustum skin round a vertical axis: radius r0 at y0 to r1 at y1 (a tent roof, a
## canopy, a drum), facing out (or in). u is metres round at r0, v the slant distance.
func cone(c: Vector3, r0: float, y0: float, r1: float, y1: float, segs: int, col: Color, inward: bool = false, a0: float = 0.0, a1: float = TAU) -> void:
	var slant := Vector2(r1 - r0, y1 - y0).length()
	var sgn := -1.0 if inward else 1.0
	for i in segs:
		var t0 := lerpf(a0, a1, float(i) / float(segs))
		var t1 := lerpf(a0, a1, float(i + 1) / float(segs))
		var d0 := Vector3(cos(t0), 0.0, sin(t0))
		var d1 := Vector3(cos(t1), 0.0, sin(t1))
		var lean := (r0 - r1) / maxf(absf(y1 - y0), 1e-3) * signf(y1 - y0)
		var n0 := (d0 + Vector3.UP * lean).normalized() * sgn
		var n1 := (d1 + Vector3.UP * lean).normalized() * sgn
		quad_n(c + d0 * r0 + Vector3.UP * y0, c + d0 * r1 + Vector3.UP * y1, c + d1 * r1 + Vector3.UP * y1, c + d1 * r0 + Vector3.UP * y0,
			n0, n0, n1, n1, Vector2(t0 * r0, 0.0), Vector2(t0 * r0, slant), Vector2(t1 * r0, slant), Vector2(t1 * r0, 0.0), col)


## Flat lettering (FreewayKit's cached TextMesh outlines) laid in the plane of `xf` (x right, y up,
## facing +z), centred on its origin, at most `max_w` wide. Returns the width drawn.
func letters(text: String, height: float, xf: Transform3D, col: Color, max_w: float = 99.0) -> float:
	if text == "":
		return 0.0
	var geo := FreewayKit.text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var width: float = geo[2]
	if verts.is_empty():
		return 0.0
	var s := 1.0
	if width > max_w and width > 0.0:
		s = max_w / width
	var face := xf.basis.z.normalized()
	for i in range(0, idx.size() - 2, 3):
		var a := verts[idx[i]] * s
		var b := verts[idx[i + 1]] * s
		var c := verts[idx[i + 2]] * s
		tri(xf * Vector3(a.x, a.y, 0.0), xf * Vector3(b.x, b.y, 0.0), xf * Vector3(c.x, c.y, 0.0), face,
			Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y), col)
	return width * s


## Commits every slot into one MeshInstance3D under `parent` (null: just returns the mesh in the
## node, unparented). Slots with nothing in them are skipped.
func commit(parent: Node3D, node_name: String, shadow: bool = true) -> MeshInstance3D:
	var mesh := build_mesh()
	if mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent:
		parent.add_child(mi)
	return mi


## Triangles every PierMesh has built (probes and checks; the dummy renderer keeps no mesh data
## to count).
static var built_triangles: int = 0


func build_mesh() -> ArrayMesh:
	built_triangles += triangles
	var mesh := ArrayMesh.new()
	for key in _order:
		var s: Dictionary = _slots[key]
		if (s.v as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.v
		arrays[Mesh.ARRAY_NORMAL] = s.n
		arrays[Mesh.ARRAY_TEX_UV] = s.uv
		arrays[Mesh.ARRAY_TEX_UV2] = s.uv2
		arrays[Mesh.ARRAY_COLOR] = s.col
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, s.mat)
	return mesh


## Adds the collected collision to `statics` as one concave shape.
func commit_collision(statics: CollisionObject3D, xf: Transform3D = Transform3D.IDENTITY) -> void:
	if statics == null or collision.is_empty():
		collision = PackedVector3Array()
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	statics.add_child(cs)
	collision = PackedVector3Array()


static var _mats: Dictionary = {}


## The park's material for `ride` (0 static, 1 wheel, 2 carousel, 3 bumper cars) with the given
## shader uniforms, cached by `key`: every copy of a ride (near and far) shares one.
static func material(key: String, ride: int = 0, params: Dictionary = {}) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pier_park.gdshader")
	mat.set_shader_parameter("ride", ride)
	for p: String in params:
		mat.set_shader_parameter(p, params[p])
	_mats[key] = mat
	return mat
