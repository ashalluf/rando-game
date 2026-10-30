class_name RooftopGeo
extends RefCounted
## A growing mesh for the rooftop kit (Rooftops): boxes, cylinders, beams, quads and flat
## lettering written straight into packed arrays with flat (or smooth, on round things) normals,
## in the building's own space through a frame transform. Every vertex carries what it is in its
## colour (rgb the paint as written, sRGB; alpha the kind, `kind / KIND_SCALE`, see
## shaders/rooftop.gdshader K_*), UV in metres in the face's plane and UV2 a feature parameter
## (a helipad's size, a pool's size). One commit() is one surface.
##
## Winding: Godot draws clockwise faces as front faces, so every triangle is flipped, if it has
## to be, to face the normal it is given (FreewayKit's and LandmarkGeo's rule). Geometry is never
## added any other way.

const KIND_SCALE := 32.0

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var idx := PackedInt32Array()
## The frame every call below writes through (building space from the feature's own).
var xf := Transform3D.IDENTITY
## UV2 written on every vertex until changed.
var param := Vector2.ZERO


func tri_count() -> int:
	return idx.size() / 3


func _col(color: Color, kind: int) -> Color:
	return Color(color.r, color.g, color.b, float(kind) / KIND_SCALE)


## One quad (a, b, cc, d in order round it), facing `normal` (feature frame), with its UVs.
func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, normal: Vector3, color: Color, kind: int,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	var nb := xf.basis.inverse().transposed()
	var nw := (nb * normal).normalized()
	var pa := xf * a
	var pb := xf * b
	var pc := xf * cc
	var pd := xf * d
	var base := v.size()
	var col := _col(color, kind)
	for p: Vector3 in [pa, pb, pc, pd]:
		v.append(p)
		n.append(nw)
		c.append(col)
		uv2.append(param)
	uv.append(ua)
	uv.append(ub)
	uv.append(uc)
	uv.append(ud)
	# Clockwise seen from the side the normal points to.
	if (pb - pa).cross(pc - pa).dot(nw) > 0.0:
		idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	else:
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


## A quad seen from both sides (a net, a sign's back).
func quad2(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, normal: Vector3, color: Color, kind: int,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	quad(a, b, cc, d, normal, color, kind, ua, ub, uc, ud)
	quad(a, b, cc, d, -normal, color, kind, ua, ub, uc, ud)


## An axis-aligned box (feature frame) of `size` centred at `at`. `skip_bottom` drops the face
## nobody sees (anything standing on a roof). UVs: metres in each face's plane.
func box(at: Vector3, size: Vector3, color: Color, kind: int, skip_bottom: bool = true) -> void:
	var h := size * 0.5
	var x0 := at.x - h.x
	var x1 := at.x + h.x
	var y0 := at.y - h.y
	var y1 := at.y + h.y
	var z0 := at.z - h.z
	var z1 := at.z + h.z
	# Top.
	quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, color, kind,
		Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1))
	if not skip_bottom:
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN, color, kind,
			Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1))
	# Sides: u along the face, v up.
	quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, color, kind,
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1))
	quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.FORWARD, color, kind,
		Vector2(-x0, y0), Vector2(-x1, y0), Vector2(-x1, y1), Vector2(-x0, y1))
	quad(Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3.RIGHT, color, kind,
		Vector2(-z0, y0), Vector2(-z1, y0), Vector2(-z1, y1), Vector2(-z0, y1))
	quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT, color, kind,
		Vector2(z0, y0), Vector2(z1, y0), Vector2(z1, y1), Vector2(z0, y1))


## A box from `p0` to `p1` (its centre line) of cross-section w x h, `up` its height direction
## (a beam, a rail, a cable, a boom).
func beam(p0: Vector3, p1: Vector3, w: float, h: float, color: Color, kind: int, up: Vector3 = Vector3.UP) -> void:
	var d := p1 - p0
	var len := d.length()
	if len < 1e-4:
		return
	var f := d / len
	var u := up
	if absf(f.dot(u)) > 0.98:
		u = Vector3.RIGHT if absf(f.x) < 0.9 else Vector3.BACK
	var s := f.cross(u).normalized()
	u = s.cross(f).normalized()
	var saved := xf
	xf = saved * Transform3D(Basis(s, u, f), (p0 + p1) * 0.5)
	box(Vector3.ZERO, Vector3(w, h, len), color, kind, false)
	xf = saved


## A cylinder (a cone or frustum when the radii differ) standing on `base` (feature frame), with
## smooth sides and `segs` facets, capped on top (and on the bottom when `bottom_cap`).
func cyl(base: Vector3, r0: float, r1: float, h: float, segs: int, color: Color, kind: int, bottom_cap: bool = false, top_cap: bool = true) -> void:
	var nb := xf.basis.inverse().transposed()
	var col := _col(color, kind)
	var slope := (r0 - r1) / maxf(h, 1e-4)
	var circ := TAU * maxf(r0, r1)
	var base_i := v.size()
	for k in segs + 1:
		var a := TAU * float(k) / float(segs)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var nl := (nb * (dir + Vector3(0.0, slope, 0.0)).normalized()).normalized()
		for j in 2:
			var r := r0 if j == 0 else r1
			v.append(xf * (base + dir * r + Vector3(0.0, h * float(j), 0.0)))
			n.append(nl)
			c.append(col)
			uv.append(Vector2(circ * float(k) / float(segs), h * float(j)))
			uv2.append(param)
	for k in segs:
		var i0 := base_i + k * 2
		var a0 := v[i0]
		var a1 := v[i0 + 2]
		var b0 := v[i0 + 1]
		var face_n := n[i0]
		if (a1 - a0).cross(b0 - a0).dot(face_n) > 0.0:
			idx.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0 + 2, i0 + 1, i0 + 3]))
		else:
			idx.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0 + 2, i0 + 3, i0 + 1]))
	if top_cap and r1 > 0.001:
		_disc(base + Vector3(0.0, h, 0.0), r1, segs, Vector3.UP, col)
	if bottom_cap and r0 > 0.001:
		_disc(base, r0, segs, Vector3.DOWN, col)


func _disc(centre: Vector3, r: float, segs: int, normal: Vector3, col: Color) -> void:
	var nb := xf.basis.inverse().transposed()
	var nw := (nb * normal).normalized()
	var ci := v.size()
	v.append(xf * centre)
	n.append(nw)
	c.append(col)
	uv.append(Vector2(centre.x, centre.z))
	uv2.append(param)
	for k in segs:
		var a := TAU * float(k) / float(segs)
		var p := centre + Vector3(cos(a), 0.0, sin(a)) * r
		v.append(xf * p)
		n.append(nw)
		c.append(col)
		uv.append(Vector2(p.x, p.z))
		uv2.append(param)
	for k in segs:
		var a := ci + 1 + k
		var b := ci + 1 + (k + 1) % segs
		if (v[a] - v[ci]).cross(v[b] - v[ci]).dot(nw) > 0.0:
			idx.append_array(PackedInt32Array([ci, b, a]))
		else:
			idx.append_array(PackedInt32Array([ci, a, b]))


## Flat lettering (FreewayKit.text_geo(), cached per string) centred at `at`, in the plane whose
## right is `right` and up `up` (feature frame), facing right x up's... the side `face` points to.
func text(s: String, height: float, at: Vector3, right: Vector3, up: Vector3, face: Vector3, color: Color, kind: int) -> float:
	var geo: Array = FreewayKit.text_geo(s, height)
	var tv: PackedVector3Array = geo[0]
	var ti: PackedInt32Array = geo[1]
	if tv.is_empty():
		return 0.0
	var nb := xf.basis.inverse().transposed()
	var nw := (nb * face).normalized()
	var col := _col(color, kind)
	var base := v.size()
	for p: Vector3 in tv:
		var q := at + right * p.x + up * p.y
		v.append(xf * q)
		n.append(nw)
		c.append(col)
		uv.append(Vector2(p.x, p.y))
		uv2.append(param)
	for k in range(0, ti.size() - 2, 3):
		var a := base + ti[k]
		var b := base + ti[k + 1]
		var d := base + ti[k + 2]
		if (v[b] - v[a]).cross(v[d] - v[a]).dot(nw) > 0.0:
			idx.append_array(PackedInt32Array([a, d, b]))
		else:
			idx.append_array(PackedInt32Array([a, b, d]))
	return float(geo[2])


## The surface arrays, or [] when nothing was written.
func arrays() -> Array:
	if idx.is_empty():
		return []
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	out[Mesh.ARRAY_COLOR] = c
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = idx
	return out
