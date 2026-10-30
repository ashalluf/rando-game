class_name RidgeKit
extends RefCounted
## The hardware of the ridges (Ridges), built in code at real size: the 220 kV lattice towers
## (galvanised angle members, the body tapering to its waist, three cross-arms a side, the earth
## wire peak, porcelain insulator strings, leg extensions down to each foot on its own concrete
## pier), the antenna farm's guyed masts painted in aviation orange and white, its lattice towers
## and monopoles with their panels and drum dishes, the equipment huts, the round green water
## tanks, the radar / weather domes, the fire lookout, the substation's gantries, transformers,
## breakers, bus and control house, and the fire road gates.
##
## Everything is written into an `Acc` (packed arrays per material) and committed as ONE mesh with
## a surface per material. A lattice member is an L-section angle: two flanges, one quad each,
## drawn both sides (4 triangles), because that is what a lattice tower IS and what catches the
## light along its edges. The members are a list ([a, b, width, flange 1, flange 2] in the
## tower's frame) the far tier draws again as fine lines (RidgeSystem): `tower_members()` with
## `far` true keeps only the legs, the main bracing and the arms.

const STEEL := Color(0.60, 0.62, 0.62)
const STEEL_DARK := Color(0.47, 0.49, 0.49)
const ORANGE := Color(0.86, 0.30, 0.10)
const WHITE := Color(0.88, 0.88, 0.86)
const TANK_GREEN := Color(0.30, 0.40, 0.28)
const HUT := Color(0.74, 0.70, 0.62)
const PORCELAIN := Color(0.70, 0.70, 0.68)

static var _mats: Dictionary = {}
static var _cache: Dictionary = {}


## Packed triangle soup per material; flat normals, optional colours and UVs.
## One material's triangles. (Packed arrays are values: kept in a Dictionary, an append would go
## to a copy, so each lives in an object that appends to its own members.)
class Part:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func add(p: Vector3, nn: Vector3, col: Color, t: Vector2) -> void:
		v.append(p)
		n.append(nn)
		c.append(col)
		uv.append(t)


class Acc:
	var parts: Dictionary = {}

	func _part(mat: String) -> Part:
		if not parts.has(mat):
			parts[mat] = Part.new()
		return parts[mat]

	## A triangle facing `n` (wound so its front faces `n`: Godot fronts are clockwise seen from
	## in front, which is cross(b - a, c - a) pointing AWAY from the eye).
	func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, uvs: Array = []) -> void:
		var p: Part = _part(mat)
		var flip := (b - a).cross(c - a).dot(n) > 0.0
		var nn := n.normalized()
		var pts := [a, c, b] if flip else [a, b, c]
		var tuv := [uvs[0], uvs[2], uvs[1]] if (flip and uvs.size() == 3) else uvs
		for k in 3:
			p.add(pts[k], nn, col, tuv[k] if tuv.size() == 3 else Vector2.ZERO)

	func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
		tri(mat, a, b, c, n, col)
		tri(mat, a, c, d, n, col)

	## An L-section angle from `a` to `b`: flanges `w` wide along `f1` and `f2` (unit, roughly
	## perpendicular to the member), its heel on the line a-b.
	func angle(mat: String, a: Vector3, b: Vector3, w: float, f1: Vector3, f2: Vector3, col: Color) -> void:
		var d := (b - a).normalized()
		var g1 := (f1 - d * f1.dot(d)).normalized()
		var g2 := (f2 - d * f2.dot(d)).normalized()
		if g1.length_squared() < 0.5 or g2.length_squared() < 0.5:
			var any := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
			g1 = d.cross(any).normalized()
			g2 = d.cross(g1).normalized()
		var n1 := d.cross(g1)
		if n1.dot(g2) > 0.0:
			n1 = -n1
		var n2 := d.cross(g2)
		if n2.dot(g1) > 0.0:
			n2 = -n2
		quad(mat, a, b, b + g1 * w, a + g1 * w, n1, col)
		quad(mat, a, b, b + g2 * w, a + g2 * w, n2, col)

	## A box from its transform (unit cube -0.5..0.5 scaled by the basis).
	func box(mat: String, xf: Transform3D, col: Color, top := true, bottom := false) -> void:
		var c := [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5),
			Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)]
		var w: Array[Vector3] = []
		for p: Vector3 in c:
			w.append(xf * p)
		var faces := [[0, 1, 5, 4, Vector3(0, 0, -1)], [1, 2, 6, 5, Vector3(1, 0, 0)], [2, 3, 7, 6, Vector3(0, 0, 1)],
			[3, 0, 4, 7, Vector3(-1, 0, 0)], [4, 5, 6, 7, Vector3(0, 1, 0)], [0, 3, 2, 1, Vector3(0, -1, 0)]]
		for f: Array in faces:
			var n: Vector3 = xf.basis * (f[4] as Vector3)
			if (f[4] as Vector3).y > 0.5 and not top:
				continue
			if (f[4] as Vector3).y < -0.5 and not bottom:
				continue
			quad(mat, w[f[0]], w[f[1]], w[f[2]], w[f[3]], n, col)

	## A box between two points (a beam) of section `sx` x `sy`, `up` a hint for its rotation.
	func beam(mat: String, a: Vector3, b: Vector3, sx: float, sy: float, col: Color, up := Vector3.UP) -> void:
		var d := b - a
		var l := d.length()
		if l < 0.001:
			return
		var z := d / l
		var x := up.cross(z)
		if x.length_squared() < 0.001:
			x = Vector3.RIGHT.cross(z)
		x = x.normalized()
		var y := z.cross(x)
		box(mat, Transform3D(Basis(x * sx, y * sy, z * l), (a + b) * 0.5), col, true, true)

	## A cylinder (or cone, r0 != r1) on the axis a -> b, `n` sides, capped at `cap`.
	func cyl(mat: String, a: Vector3, b: Vector3, r0: float, r1: float, n: int, col: Color, cap_a := false, cap_b := true) -> void:
		var axis := (b - a).normalized()
		var x := Vector3.UP.cross(axis)
		if x.length_squared() < 0.001:
			x = Vector3.RIGHT
		x = x.normalized()
		var y := axis.cross(x)
		var slope := (r0 - r1) / maxf(a.distance_to(b), 0.001)
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var d0 := x * cos(a0) + y * sin(a0)
			var d1 := x * cos(a1) + y * sin(a1)
			var dm := (d0 + d1).normalized()
			var nm := (dm + axis * slope).normalized()
			quad(mat, a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1, nm, col)
			if cap_b and r1 > 0.0:
				tri(mat, b, b + d0 * r1, b + d1 * r1, axis, col)
			if cap_a and r0 > 0.0:
				tri(mat, a, a + d0 * r0, a + d1 * r0, -axis, col)

	func tris() -> int:
		var n := 0
		for k in parts:
			n += (parts[k] as Part).v.size() / 3
		return n

	func commit(mats: Dictionary) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for k: String in parts:
			var p: Part = parts[k]
			if p.v.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = p.v
			arrays[Mesh.ARRAY_NORMAL] = p.n
			arrays[Mesh.ARRAY_COLOR] = p.c
			arrays[Mesh.ARRAY_TEX_UV] = p.uv
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats.get(k, RidgeKit.material(k)))
		return mesh


# --- Materials -------------------------------------------------------------------------------

static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match key:
		"steel":
			m.metallic = 0.55
			m.roughness = 0.52
		"paint":
			m.metallic = 0.0
			m.roughness = 0.62
		"porcelain":
			m.metallic = 0.0
			m.roughness = 0.16
			m.cull_mode = BaseMaterial3D.CULL_BACK
		"concrete":
			var c := PropFactory.pbr("concrete", 3.0, Color(0.78, 0.77, 0.74))
			_mats[key] = c
			return c
		"gravel":
			var g := PropFactory.pbr("rock", 1.6, Color(0.62, 0.6, 0.57))
			_mats[key] = g
			return g
		"glass":
			m.metallic = 0.4
			m.roughness = 0.06
			m.cull_mode = BaseMaterial3D.CULL_BACK
		"dome":
			m.metallic = 0.0
			m.roughness = 0.5
			m.cull_mode = BaseMaterial3D.CULL_BACK
		"solid":
			m.metallic = 0.25
			m.roughness = 0.55
			m.cull_mode = BaseMaterial3D.CULL_BACK
	_mats[key] = m
	return m


# --- The lattice tower ------------------------------------------------------------------------

## Half the body's width at height y (local), from the base to the waist, the hamper and the peak.
static func _half(sp: Dictionary, y: float) -> float:
	var top: float = float(sp.arm_y[2]) + float(sp.arm_depth)
	if y <= float(sp.waist_y):
		return lerpf(float(sp.base_half), float(sp.waist_half), y / float(sp.waist_y))
	if y <= top:
		return float(sp.waist_half)
	return lerpf(float(sp.waist_half), 0.42, clampf((y - top) / (float(sp.h) - 1.0 - top), 0.0, 1.0))


const CORNER_SIGNS := [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]


static func _corner(sp: Dictionary, c: int, y: float) -> Vector3:
	var s: Vector2 = CORNER_SIGNS[c % 4]
	var h := _half(sp, y)
	return Vector3(s.x * h, y, s.y * h)


## The members of a tower of height `h`, local (x across, z along, y up from the body's base),
## as [a, b, width, flange 1, flange 2, kind] (kind 0 leg, 1 bracing, 2 arm). `feet` (4 local
## foot heights, <= 0) adds the leg extensions; `far` keeps only what reads from afar.
static func tower_members(h: float, feet: Array, far: bool) -> Array:
	var sp := Ridges.spec(h)
	var out: Array = []
	var leg_w := 0.10 + h * 0.0012
	var br_w := 0.07
	var wy: float = sp.waist_y
	var arm_y: Array = sp.arm_y
	var depth: float = sp.arm_depth
	var top := float(arm_y[2]) + depth
	var levels: Array[float] = []
	for f: float in [0.0, 0.2, 0.37, 0.52, 0.65, 0.77, 0.89, 1.0]:
		levels.append(wy * f)
	for k in 3:
		levels.append(float(arm_y[k]))
		levels.append(float(arm_y[k]) + depth)
	levels.append(lerpf(top, h - 1.0, 0.5))
	levels.append(h - 1.0)
	levels.sort()
	var lv: Array[float] = []
	for y in levels:
		if lv.is_empty() or y - lv[lv.size() - 1] > 0.6:
			lv.append(y)
	# Legs: each corner up through every level.
	for c in 4:
		var s: Vector2 = CORNER_SIGNS[c]
		var f1 := Vector3(-s.x, 0.0, 0.0)
		var f2 := Vector3(0.0, 0.0, -s.y)
		for i in range(1, lv.size()):
			out.append([_corner(sp, c, lv[i - 1]), _corner(sp, c, lv[i]), leg_w * (1.0 if lv[i] < wy else 0.75), f1, f2, 0])
	# Faces: X bracing in every panel, a strut at its top, a redundant through the crossing in the big ones.
	for c in 4:
		var c2 := (c + 1) % 4
		var mid := (_corner(sp, c, 0.0) + _corner(sp, c2, 0.0)) * 0.5
		var nrm := Vector3(mid.x, 0.0, mid.z).normalized()
		for i in range(1, lv.size()):
			var y0 := lv[i - 1]
			var y1 := lv[i]
			if far and (i % 2 == 0 and y1 < wy):
				continue
			var a0 := _corner(sp, c, y0)
			var b0 := _corner(sp, c2, y0)
			var a1 := _corner(sp, c, y1)
			var b1 := _corner(sp, c2, y1)
			var fa := nrm.cross(a1 - b0).normalized()
			out.append([a0, b1, br_w, fa, -nrm, 1])
			out.append([b0, a1, br_w, -fa, -nrm, 1])
			if far:
				continue
			out.append([a1, b1, br_w * 0.9, Vector3.DOWN, -nrm, 1])
			if y1 - y0 > 4.5:
				var ym := (y0 + y1) * 0.5
				var cm := (a0 + b0 + a1 + b1) * 0.25
				out.append([_corner(sp, c, ym), cm, br_w * 0.75, Vector3.DOWN, -nrm, 1])
				out.append([_corner(sp, c2, ym), cm, br_w * 0.75, Vector3.DOWN, -nrm, 1])
	# Plan bracing at the waist and under each arm.
	if not far:
		for y: float in [wy, float(arm_y[0]), float(arm_y[1]), float(arm_y[2])]:
			out.append([_corner(sp, 0, y), _corner(sp, 2, y), br_w, Vector3.UP, Vector3.RIGHT, 1])
			out.append([_corner(sp, 1, y), _corner(sp, 3, y), br_w, Vector3.UP, Vector3.RIGHT, 1])
	# The cross-arms: two bottom chords and two top chords from the body to the tip, laced.
	var arm_w := 0.085
	for k in 3:
		var y: float = arm_y[k]
		var tip: float = sp.arm_tip[k]
		var wh: float = sp.waist_half
		for side: float in [-1.0, 1.0]:
			var tb := Vector3(side * tip, y, 0.0)
			var tt := Vector3(side * (tip - 0.25), y + 0.35, 0.0)
			var rb0 := Vector3(side * wh, y, -wh)
			var rb1 := Vector3(side * wh, y, wh)
			var rt0 := Vector3(side * wh, y + depth, -wh)
			var rt1 := Vector3(side * wh, y + depth, wh)
			for pair: Array in [[rb0, tb], [rb1, tb], [rt0, tt], [rt1, tt]]:
				out.append([pair[0], pair[1], arm_w, Vector3.UP, Vector3(0.0, 0.0, 1.0), 2])
			if far:
				continue
			var n := 4
			for j in range(1, n):
				var t := float(j) / n
				var pb0 := rb0.lerp(tb, t)
				var pb1 := rb1.lerp(tb, t)
				var pt0 := rt0.lerp(tt, t)
				var pt1 := rt1.lerp(tt, t)
				out.append([pb0, pb1, 0.06, Vector3.UP, Vector3.RIGHT, 1])
				out.append([pb0, pt0, 0.06, Vector3.RIGHT, Vector3.FORWARD, 1])
				out.append([pb1, pt1, 0.06, Vector3.RIGHT, Vector3.FORWARD, 1])
				var qb0 := rb0.lerp(tb, float(j - 1) / n)
				var qt1 := rt1.lerp(tt, float(j - 1) / n)
				out.append([qb0, pt0, 0.055, Vector3.RIGHT, Vector3.FORWARD, 1])
				out.append([qt1, pb1, 0.055, Vector3.RIGHT, Vector3.FORWARD, 1])
				out.append([qb0, pb1, 0.055, Vector3.UP, Vector3.RIGHT, 1])
	# The earth wire peak's cross-arm.
	var pk: float = sp.peak_tip
	for side: float in [-1.0, 1.0]:
		var tip := Vector3(side * pk, h, 0.0)
		out.append([_corner(sp, 0 if side < 0.0 else 1, h - 1.0), tip, 0.07, Vector3.UP, Vector3.FORWARD, 2])
		out.append([_corner(sp, 3 if side < 0.0 else 2, h - 1.0), tip, 0.07, Vector3.UP, Vector3.FORWARD, 2])
		out.append([_corner(sp, 0 if side < 0.0 else 1, lerpf(top, h - 1.0, 0.5)), tip, 0.06, Vector3.UP, Vector3.FORWARD, 2])
	# Leg extensions down the batter to each foot, braced to the base of the next legs.
	if not feet.is_empty():
		for c in 4:
			var fy: float = feet[c]
			if fy > -0.15:
				continue
			var s: Vector2 = CORNER_SIGNS[c]
			var foot := _corner(sp, c, fy)
			out.append([foot, _corner(sp, c, 0.0), leg_w * 1.05, Vector3(-s.x, 0, 0), Vector3(0, 0, -s.y), 0])
			if fy < -1.5 and not far:
				for c2: int in [(c + 1) % 4, (c + 3) % 4]:
					out.append([foot.lerp(_corner(sp, c, 0.0), 0.15), _corner(sp, c2, 0.0).lerp(_corner(sp, c, 0.0), 0.5), br_w,
						Vector3.UP, Vector3(-s.x, 0, -s.y).normalized(), 1])
	return out


## The body of a tower of height `h` and kind (everything at or above its base: the members, the
## insulator strings, the clamps, the plates), cached: every tower of a height and kind is the
## same mesh.
static func tower_body(h: float, kind: int) -> ArrayMesh:
	var key := "tower_%d_%d" % [int(h), kind]
	if _cache.has(key):
		return _cache[key]
	var acc := Acc.new()
	for m: Array in tower_members(h, [], false):
		acc.angle("steel", m[0], m[1], float(m[2]), m[3], m[4], STEEL if int(m[5]) != 1 else STEEL_DARK)
	var sp := Ridges.spec(h)
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var tip := Vector3(side * float(sp.arm_tip[k]), float(sp.arm_y[k]), 0.0)
			if kind == Ridges.Kind.SUSPENSION:
				_string(acc, tip, tip - Vector3(0.0, Ridges.STRING, 0.0), Vector3(1.0, 0.0, 0.0))
			else:
				for dz: float in ([-1.0, 1.0] if kind == Ridges.Kind.ANGLE else [-1.0, 1.0]):
					var a := tip + Vector3(0.0, -0.1, dz * 0.25)
					var b := tip + Vector3(0.0, -0.35, dz * Ridges.TENSION)
					_string(acc, a, b, Vector3(1.0, 0.0, 0.0))
		# The earth wire's clamp at the peak tip.
		acc.box("steel", Transform3D(Basis().scaled(Vector3(0.25, 0.18, 0.4)), Vector3(side * float(sp.peak_tip), h + 0.05, 0.0)), STEEL)
	# The number plate and the danger sign on a leg, three metres up.
	var c0 := _corner(sp, 0, 3.0)
	acc.box("paint", Transform3D(Basis().scaled(Vector3(0.36, 0.42, 0.02)), c0 + Vector3(0.05, 0.0, -0.02)), Color(0.9, 0.86, 0.2))
	acc.box("paint", Transform3D(Basis().scaled(Vector3(0.3, 0.2, 0.02)), c0 + Vector3(0.05, 0.4, -0.02)), WHITE)
	# The anti-climb guard: a frame of barbed spikes round the body four metres up.
	for c in 4:
		var a := _corner(sp, c, 4.2)
		var b := _corner(sp, (c + 1) % 4, 4.2)
		var out := Vector3(a.x + b.x, 0.0, a.z + b.z).normalized()
		acc.beam("steel", a + out * 0.25, b + out * 0.25, 0.04, 0.04, STEEL_DARK)
		for j in 8:
			var p := (a + out * 0.25).lerp(b + out * 0.25, (j + 0.5) / 8.0)
			acc.beam("steel", p, p + out * 0.35 + Vector3(0, 0.3, 0), 0.02, 0.02, STEEL_DARK)
	var mesh := acc.commit({})
	_cache[key] = mesh
	return mesh


## An insulator string from `a` (the arm) to `b` (the conductor clamp): a link, porcelain discs
## (146 mm pitch, 255 mm across), a yoke across `across` holding the twin bundle's clamps.
static func _string(acc: Acc, a: Vector3, b: Vector3, across: Vector3) -> void:
	var axis := (b - a).normalized()
	var l := a.distance_to(b)
	acc.cyl("steel", a, a + axis * 0.35, 0.025, 0.025, 4, STEEL_DARK)
	var n := int((l - 0.75) / 0.146)
	for i in n:
		var c := a + axis * (0.45 + i * 0.146)
		acc.cyl("porcelain", c - axis * 0.03, c + axis * 0.012, 0.045, 0.128, 8, PORCELAIN, false, false)
		acc.cyl("porcelain", c + axis * 0.012, c + axis * 0.06, 0.128, 0.04, 8, PORCELAIN, false, false)
	acc.cyl("steel", b - axis * 0.3, b, 0.03, 0.03, 4, STEEL_DARK)
	var yoke := across - axis * across.dot(axis)
	yoke = yoke.normalized() * Ridges.BUNDLE * 0.5
	acc.beam("steel", b - yoke * 1.15, b + yoke * 1.15, 0.05, 0.12, STEEL_DARK, axis)
	for sg: float in [-1.0, 1.0]:
		acc.cyl("steel", b + yoke * sg - axis * 0.06, b + yoke * sg + axis * 0.12, 0.05, 0.05, 6, STEEL_DARK, true, true)


## Leg extensions below the body (one mesh a tower, local frame) and the four concrete piers.
static func tower_legs(t: Dictionary) -> ArrayMesh:
	var acc := Acc.new()
	var feet := _local_feet(t)
	var sp := Ridges.spec(float(t.h))
	var all := tower_members(float(t.h), feet, false)
	for m: Array in all:
		if (m[0] as Vector3).y < -0.01 or (m[1] as Vector3).y < -0.01:
			acc.angle("steel", m[0], m[1], float(m[2]), m[3], m[4], STEEL)
	for c in 4:
		var foot := _corner(sp, c, float(feet[c]))
		acc.box("concrete", Transform3D(Basis().scaled(Vector3(1.3, 1.6, 1.3)), foot + Vector3(0.0, -0.45, 0.0)), Color.WHITE)
	return acc.commit({})


## The four feet's heights below the body's base, local.
static func _local_feet(t: Dictionary) -> Array:
	var out: Array = []
	for c in 4:
		out.append(float(t.legs[c]) - float(t.base) + 0.05)
	return out


# --- The antenna farm ------------------------------------------------------------------------

## A mast of the antenna farm in its own frame (base at the origin): a guyed triangular lattice
## painted in seven bands of aviation orange and white, a tapering square lattice tower, or a
## monopole; platforms, panel antennas, drum dishes, the guy wires' attachment collars. Cached.
static func mast_mesh(m: Dictionary) -> ArrayMesh:
	var key := "mast_%s_%d_%d" % [m.id, int(float(m.h) * 10.0), int(m.kind)]
	if _cache.has(key):
		return _cache[key]
	var acc := Acc.new()
	var h: float = m.h
	var kind: int = m.kind
	for seg: Array in mast_members(m, false):
		acc.angle("paint" if kind == Ridges.Mast.GUYED else "steel", seg[0], seg[1], float(seg[2]), seg[3], seg[4], seg[5])
	if kind == Ridges.Mast.MONOPOLE:
		acc.cyl("steel", Vector3.ZERO, Vector3(0.0, h, 0.0), 0.85, 0.38, 14, STEEL, false, true)
	# Platforms with panel antennas near the top (three sectors), and a work platform under them.
	var r_top := 0.9 if kind == Ridges.Mast.GUYED else (0.45 if kind == Ridges.Mast.MONOPOLE else 0.7)
	for lvl: float in ([h - 3.0, h * 0.62] if kind != Ridges.Mast.MONOPOLE else [h - 2.0, h - 6.5]):
		var pr := r_top + 1.4
		for i in 3:
			var a := TAU * i / 3.0 + float(m.face)
			var d := Vector3(cos(a), 0.0, sin(a))
			acc.beam("steel", Vector3(0.0, lvl, 0.0), Vector3(0.0, lvl, 0.0) + d * pr, 0.08, 0.08, STEEL_DARK)
			var t := Vector3(-d.z, 0.0, d.x)
			acc.beam("steel", Vector3(0.0, lvl, 0.0) + d * pr - t * 1.3, Vector3(0.0, lvl, 0.0) + d * pr + t * 1.3, 0.06, 0.06, STEEL_DARK)
			for j in 3:
				var p := Vector3(0.0, lvl + 1.2, 0.0) + d * (pr + 0.15) + t * (float(j) - 1.0) * 0.8
				acc.box("solid", Transform3D(Basis(t * 0.3, Vector3(0, 1.8, 0), d * 0.12), p), Color(0.82, 0.82, 0.8))
	# Drum dishes (microwave radomes) on the mast.
	for dsh: Array in m.dishes:
		var y: float = dsh[0]
		var a: float = dsh[1]
		var r: float = dsh[2]
		var d := Vector3(cos(a), 0.0, sin(a))
		var at := Vector3(0.0, y, 0.0) + d * (r_top + 0.45)
		acc.beam("steel", Vector3(0.0, y, 0.0), at, 0.08, 0.08, STEEL_DARK)
		acc.cyl("solid", at, at + d * 0.55, r, r, 16, Color(0.86, 0.86, 0.84), false, false)
		acc.cyl("solid", at + d * 0.55, at + d * 0.7, r, r * 0.55, 16, Color(0.9, 0.9, 0.88), false, true)
		acc.cyl("solid", at, at - d * 0.15, r, r * 0.9, 16, Color(0.6, 0.6, 0.58), false, true)
	# Guy collars.
	for y: float in m.levels:
		acc.cyl("steel", Vector3(0.0, y - 0.2, 0.0), Vector3(0.0, y + 0.2, 0.0), r_top * 1.15, r_top * 1.15, 6, STEEL_DARK, true, true)
	# Base pier.
	acc.box("concrete", Transform3D(Basis().scaled(Vector3(3.2, 1.6, 3.2)), Vector3(0.0, -0.3, 0.0)), Color.WHITE)
	var mesh := acc.commit({})
	_cache[key] = mesh
	return mesh


## A mast's lattice in its own frame: [a, b, width, f1, f2, colour]. `far` keeps the legs and a
## coarse lacing for the fine-line far tier.
static func mast_members(m: Dictionary, far: bool) -> Array:
	var out: Array = []
	var h: float = m.h
	var kind: int = m.kind
	if kind == Ridges.Mast.MONOPOLE:
		if far:
			out.append([Vector3.ZERO, Vector3(0.0, h, 0.0), 0.6, Vector3.RIGHT, Vector3.FORWARD, STEEL])
		return out
	var legs := 3 if kind == Ridges.Mast.GUYED else 4
	var pitch := 1.6 if not far else 6.4
	var n := maxi(2, int(h / pitch))
	var bands := 7
	for i in n:
		var y0 := h * i / n
		var y1 := h * (i + 1) / n
		var col := ORANGE if int(floor(y0 / h * bands)) % 2 == 0 else WHITE
		if kind != Ridges.Mast.GUYED:
			col = STEEL
		var r0 := _mast_r(m, y0)
		var r1 := _mast_r(m, y1)
		for c in legs:
			var a0 := TAU * c / legs + float(m.face)
			var a1 := TAU * (c + 1) / legs + float(m.face)
			var p0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p1 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var q0 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var q1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var nrm := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
			out.append([p0, p1, 0.11 if not far else 0.14, -nrm, Vector3(-cos(a0), 0, -sin(a0)), col])
			# Zig-zag lacing, the struts every other panel.
			out.append([p0 if i % 2 == 0 else q0, q1 if i % 2 == 0 else p1, 0.05 if not far else 0.06, -nrm, Vector3.UP, col])
			if not far and i % 2 == 0:
				out.append([p0, q0, 0.045, -nrm, Vector3.UP, col])
	return out


## A mast's lattice radius (centre to leg) at height y.
static func _mast_r(m: Dictionary, y: float) -> float:
	var h: float = m.h
	if int(m.kind) == Ridges.Mast.GUYED:
		return 0.95
	return lerpf(maxf(h * 0.07, 2.2), 0.8, clampf(y / h, 0.0, 1.0) ** 0.8)


## The obstruction lights of a mast, local: [position, kind (0 steady, 2 beacon)].
static func mast_lights(m: Dictionary) -> Array:
	var h: float = m.h
	var out: Array = []
	if h < 40.0:
		return out
	out.append([Vector3(0.0, h + 0.6, 0.0), 2])
	var n := int(h / 50.0)
	for k in n:
		var y := h * float(k + 1) / float(n + 1)
		var r := _mast_r(m, y) + 0.15
		for i in 2:
			var a := TAU * i / 2.0 + float(m.face)
			out.append([Vector3(cos(a) * r, y, sin(a) * r), 0])
	return out


# --- Small sites -----------------------------------------------------------------------------

## A site's mesh in its own frame (origin on its pad, +Z along its yaw), cached per site.
static func site_mesh(s: Dictionary, seed_value: int) -> ArrayMesh:
	var key := "site_%s_%d_%d" % [s.id, seed_value, int(float(s.r) * 100.0)]
	if _cache.has(key):
		return _cache[key]
	var acc := Acc.new()
	match int(s.kind):
		Ridges.Site.TANK:
			_tank(acc, float(s.r), float(s.h))
		Ridges.Site.DOME:
			_dome(acc, float(s.r), float(s.h))
		Ridges.Site.LOOKOUT:
			_lookout(acc)
		Ridges.Site.HUT:
			_hut(acc, float(s.r), float(s.h))
		Ridges.Site.DISH:
			_ground_dish(acc, float(s.r))
	var mesh := acc.commit({})
	_cache[key] = mesh
	return mesh


## A welded steel water tank: courses of plate, a shallow cone roof, a caged ladder, a roof rail,
## a vent, a ring wall foundation; painted green.
static func _tank(acc: Acc, r: float, h: float) -> void:
	acc.cyl("concrete", Vector3(0.0, -0.6, 0.0), Vector3(0.0, 0.25, 0.0), r + 0.5, r + 0.5, 32, Color.WHITE, false, true)
	var courses := int(h / 2.4)
	for i in courses + 1:
		var y0 := 0.25 + h * float(i) / float(courses + 1)
		var y1 := 0.25 + h * float(i + 1) / float(courses + 1)
		var shade := 1.0 - 0.03 * float(i % 2)
		acc.cyl("paint", Vector3(0.0, y0, 0.0), Vector3(0.0, y1, 0.0), r, r, 32, TANK_GREEN * shade, false, false)
		acc.cyl("paint", Vector3(0.0, y1 - 0.02, 0.0), Vector3(0.0, y1 + 0.02, 0.0), r + 0.015, r + 0.015, 32, TANK_GREEN * 0.92, false, false)
	var top := 0.25 + h
	acc.cyl("paint", Vector3(0.0, top, 0.0), Vector3(0.0, top + r * 0.18, 0.0), r + 0.12, 0.0, 32, TANK_GREEN * 1.04, false, false)
	acc.cyl("paint", Vector3(0.0, top + r * 0.18 - 0.1, 0.0), Vector3(0.0, top + r * 0.18 + 0.7, 0.0), 0.45, 0.45, 10, TANK_GREEN, false, true)
	# The ladder and its cage up the side, a rail round the roof's edge.
	var a := 0.4
	var d := Vector3(cos(a), 0.0, sin(a))
	var t := Vector3(-d.z, 0.0, d.x)
	for sg: float in [-1.0, 1.0]:
		acc.beam("steel", d * (r + 0.25) + t * 0.22 * sg + Vector3(0, 1.0, 0), d * (r + 0.25) + t * 0.22 * sg + Vector3(0, top + 1.1, 0), 0.05, 0.05, STEEL_DARK)
	var rungs := int((top + 0.1) / 0.3)
	for i in rungs:
		var y := 1.0 + i * 0.3
		if y > top + 1.0:
			break
		acc.beam("steel", d * (r + 0.25) - t * 0.22 + Vector3(0, y, 0), d * (r + 0.25) + t * 0.22 + Vector3(0, y, 0), 0.025, 0.025, STEEL_DARK)
	for i in int(top / 0.9):
		var y := 2.6 + i * 0.9
		if y > top + 1.0:
			break
		for k in 8:
			var a0 := PI * k / 8.0
			var a1 := PI * (k + 1) / 8.0
			var c := d * (r + 0.6)
			var p0 := c + (t * cos(a0) + d * sin(a0)) * 0.42
			var p1 := c + (t * cos(a1) + d * sin(a1)) * 0.42
			acc.beam("steel", p0 + Vector3(0, y, 0), p1 + Vector3(0, y, 0), 0.03, 0.03, STEEL_DARK)
	for k in 24:
		var a0 := TAU * k / 24.0
		var a1 := TAU * (k + 1) / 24.0
		var p0 := Vector3(cos(a0) * (r - 0.15), top + 1.05, sin(a0) * (r - 0.15))
		var p1 := Vector3(cos(a1) * (r - 0.15), top + 1.05, sin(a1) * (r - 0.15))
		acc.beam("steel", p0, p1, 0.04, 0.04, STEEL_DARK)
		acc.beam("steel", p0, Vector3(p0.x, top + 0.05, p0.z), 0.035, 0.035, STEEL_DARK)


## A radar / weather dome: a geodesic radome (an icosphere of white panels, its seams read by the
## facets) on a cylindrical concrete tower with a door and a rooftop rail.
static func _dome(acc: Acc, r: float, h: float) -> void:
	var base_r := r * 0.62
	acc.cyl("concrete", Vector3(0.0, -0.5, 0.0), Vector3(0.0, h, 0.0), base_r, base_r, 20, Color.WHITE, false, true)
	acc.box("paint", Transform3D(Basis().scaled(Vector3(1.0, 2.2, 0.1)), Vector3(0.0, 1.1, base_r + 0.02)), Color(0.32, 0.34, 0.36))
	acc.cyl("steel", Vector3(0.0, h, 0.0), Vector3(0.0, h + 0.35, 0.0), base_r + 0.05, base_r + 0.05, 20, STEEL_DARK, false, false)
	var centre := Vector3(0.0, h + r * 0.62, 0.0)
	for t: Array in _icosphere(2):
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		if (a.y + b.y + c.y) / 3.0 < -0.62:
			continue
		var n := (a + b + c).normalized()
		var shade := 0.94 + 0.06 * fposmod(sin(n.x * 91.0 + n.z * 37.0) * 13.7, 1.0)
		acc.tri("dome", centre + a * r, centre + b * r, centre + c * r, n, Color(0.93, 0.93, 0.91) * shade)


static func _icosphere(level: int) -> Array:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var tris: Array = []
	for tri: Array in f:
		tris.append([v[tri[0]], v[tri[1]], v[tri[2]]])
	for l in level:
		var nt: Array = []
		for tr: Array in tris:
			var a: Vector3 = tr[0]
			var b: Vector3 = tr[1]
			var c: Vector3 = tr[2]
			var ab := ((a + b) * 0.5).normalized()
			var bc := ((b + c) * 0.5).normalized()
			var ca := ((c + a) * 0.5).normalized()
			nt.append_array([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]])
		tris = nt
	return tris


## A fire lookout: a 12 m four-legged steel tower, braced, with a stair up its middle, and on top a
## glazed cab under a pyramid roof, a catwalk with a rail all round.
static func _lookout(acc: Acc) -> void:
	var h := 12.0
	var b0 := 3.0
	var b1 := 2.0
	for c in 4:
		var s: Vector2 = CORNER_SIGNS[c]
		var lo := Vector3(s.x * b0, 0.0, s.y * b0)
		var hi := Vector3(s.x * b1, h, s.y * b1)
		acc.angle("steel", lo, hi, 0.14, Vector3(-s.x, 0, 0), Vector3(0, 0, -s.y), STEEL)
		acc.box("concrete", Transform3D(Basis().scaled(Vector3(0.9, 0.9, 0.9)), lo + Vector3(0, -0.2, 0)), Color.WHITE)
	for i in 4:
		var y0 := h * i / 4.0
		var y1 := h * (i + 1) / 4.0
		for c in 4:
			var c2 := (c + 1) % 4
			var p0 := _lk(c, y0, b0, b1, h)
			var p1 := _lk(c2, y1, b0, b1, h)
			var q0 := _lk(c2, y0, b0, b1, h)
			var q1 := _lk(c, y1, b0, b1, h)
			var nrm := Vector3(p0.x + q0.x, 0, p0.z + q0.z).normalized()
			acc.angle("steel", p0, p1, 0.07, nrm.cross(Vector3.UP), -nrm, STEEL_DARK)
			acc.angle("steel", q0, q1, 0.07, nrm.cross(Vector3.UP), -nrm, STEEL_DARK)
			acc.angle("steel", q1, p1, 0.07, Vector3.DOWN, -nrm, STEEL_DARK)
	# Stairs: flights zig-zagging up inside the frame.
	for i in 6:
		var y0 := h * i / 6.0
		var y1 := h * (i + 1) / 6.0
		var x0 := -0.9 if i % 2 == 0 else 0.9
		acc.beam("steel", Vector3(x0, y0, -0.4), Vector3(-x0, y1, -0.4), 0.9, 0.06, STEEL_DARK, Vector3(0, 0, 1).cross(Vector3(-x0 * 2.0, 2.0, 0)).normalized())
		acc.box("steel", Transform3D(Basis().scaled(Vector3(1.4, 0.06, 1.0)), Vector3(-x0, y1, -0.1)), STEEL_DARK)
	# The cab.
	var cw := 2.6
	acc.box("paint", Transform3D(Basis().scaled(Vector3(cw * 2.0 + 2.0, 0.2, cw * 2.0 + 2.0)), Vector3(0, h + 0.1, 0)), Color(0.42, 0.40, 0.36), true, true)
	acc.box("paint", Transform3D(Basis().scaled(Vector3(cw * 2.0, 1.0, cw * 2.0)), Vector3(0, h + 0.7, 0)), Color(0.62, 0.55, 0.42))
	for c in 4:
		var s: Vector2 = CORNER_SIGNS[c]
		acc.beam("paint", Vector3(s.x * cw, h + 1.2, s.y * cw), Vector3(s.x * cw, h + 3.0, s.y * cw), 0.14, 0.14, Color(0.62, 0.55, 0.42))
	for f in 4:
		var n := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][f] as Vector3
		var t := Vector3(-n.z, 0, n.x)
		var c := n * cw
		acc.quad("glass", c - t * cw + Vector3(0, h + 1.2, 0), c + t * cw + Vector3(0, h + 1.2, 0), c + t * cw + Vector3(0, h + 3.0, 0), c - t * cw + Vector3(0, h + 3.0, 0), n, Color(0.45, 0.5, 0.52))
		for k in 3:
			var p := c + t * cw * (float(k) - 1.0) * 0.66
			acc.beam("paint", p + Vector3(0, h + 1.2, 0), p + Vector3(0, h + 3.0, 0), 0.07, 0.07, Color(0.62, 0.55, 0.42))
	acc.box("paint", Transform3D(Basis().scaled(Vector3(cw * 2.0 + 0.6, 0.18, cw * 2.0 + 0.6)), Vector3(0, h + 3.1, 0)), Color(0.36, 0.30, 0.26), true, true)
	var apex := Vector3(0, h + 4.5, 0)
	for f in 4:
		var s0: Vector2 = CORNER_SIGNS[f]
		var s1: Vector2 = CORNER_SIGNS[(f + 1) % 4]
		var e := cw + 0.5
		var a := Vector3(s0.x * e, h + 3.2, s0.y * e)
		var b := Vector3(s1.x * e, h + 3.2, s1.y * e)
		acc.tri("paint", a, b, apex, ((a + b) * 0.5 - Vector3(0, h + 3.2, 0)).normalized() + Vector3(0, 1.2, 0), Color(0.36, 0.30, 0.26))
	acc.cyl("steel", apex, apex + Vector3(0, 1.4, 0), 0.03, 0.03, 4, STEEL_DARK)
	# The catwalk's rail.
	for f in 4:
		var s0: Vector2 = CORNER_SIGNS[f]
		var s1: Vector2 = CORNER_SIGNS[(f + 1) % 4]
		var e := cw + 0.95
		for y: float in [h + 0.65, h + 1.15]:
			acc.beam("steel", Vector3(s0.x * e, y, s0.y * e), Vector3(s1.x * e, y, s1.y * e), 0.045, 0.045, STEEL_DARK)
		for k in 5:
			var p := Vector3(s0.x * e, 0, s0.y * e).lerp(Vector3(s1.x * e, 0, s1.y * e), k / 5.0)
			acc.beam("steel", p + Vector3(0, h + 0.2, 0), p + Vector3(0, h + 1.15, 0), 0.045, 0.045, STEEL_DARK)


static func _lk(c: int, y: float, b0: float, b1: float, h: float) -> Vector3:
	var s: Vector2 = CORNER_SIGNS[c % 4]
	var b := lerpf(b0, b1, y / h)
	return Vector3(s.x * b, y, s.y * b)


## An equipment hut: a block shelter on a slab, a steel door, a wall air conditioner, a cable
## bridge out toward the mast, a parapet.
static func _hut(acc: Acc, r: float, h: float) -> void:
	var w := r * 2.0
	var d := r * 1.3
	acc.box("concrete", Transform3D(Basis().scaled(Vector3(w + 0.6, 0.3, d + 0.6)), Vector3(0, 0.0, 0)), Color.WHITE)
	acc.box("paint", Transform3D(Basis().scaled(Vector3(w, h, d)), Vector3(0, 0.15 + h * 0.5, 0)), HUT, true, false)
	acc.box("paint", Transform3D(Basis().scaled(Vector3(w + 0.1, 0.25, d + 0.1)), Vector3(0, 0.15 + h + 0.12, 0)), HUT * 0.9)
	acc.box("paint", Transform3D(Basis().scaled(Vector3(0.95, 2.1, 0.06)), Vector3(-w * 0.25, 1.2, d * 0.5 + 0.02)), Color(0.42, 0.44, 0.45))
	acc.box("solid", Transform3D(Basis().scaled(Vector3(0.75, 0.5, 0.55)), Vector3(w * 0.22, 1.7, d * 0.5 + 0.3)), Color(0.8, 0.8, 0.78))
	acc.beam("steel", Vector3(-w * 0.3, h - 0.3, -d * 0.5), Vector3(-w * 0.3, h - 0.3, -d * 0.5 - 2.6), 0.5, 0.06, STEEL_DARK)


## A ground-mounted microwave dish: a parabolic reflector with its feed, on a pipe frame.
static func _ground_dish(acc: Acc, r: float) -> void:
	var c := Vector3(0, r + 1.2, 0)
	var d := Vector3(0, 0.25, 1).normalized()
	acc.beam("steel", Vector3(0, 0, 0), c, 0.18, 0.18, STEEL_DARK)
	acc.beam("steel", Vector3(-1.0, 0, -0.8), c, 0.09, 0.09, STEEL_DARK)
	acc.beam("steel", Vector3(1.0, 0, -0.8), c, 0.09, 0.09, STEEL_DARK)
	var n := 20
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var x := Vector3.UP.cross(d).normalized()
		var y := d.cross(x)
		for ring in 3:
			var r0 := r * ring / 3.0
			var r1 := r * (ring + 1) / 3.0
			var z0 := (r0 * r0) / (4.0 * r * 0.4)
			var z1 := (r1 * r1) / (4.0 * r * 0.4)
			var p00 := c + (x * cos(a0) + y * sin(a0)) * r0 + d * z0
			var p01 := c + (x * cos(a1) + y * sin(a1)) * r0 + d * z0
			var p10 := c + (x * cos(a0) + y * sin(a0)) * r1 + d * z1
			var p11 := c + (x * cos(a1) + y * sin(a1)) * r1 + d * z1
			var nn := (d - (x * cos(a0 + 0.15) + y * sin(a0 + 0.15)) * ((r0 + r1) / (4.0 * r * 0.4))).normalized()
			acc.quad("solid", p00, p10, p11, p01, nn, Color(0.86, 0.86, 0.84))
	acc.beam("steel", c, c + d * r * 0.65, 0.05, 0.05, STEEL_DARK)


# --- The substation --------------------------------------------------------------------------

## A dead-end gantry in its own frame (x across the two bays, z toward the line): three laced
## square columns, a laced beam at GANTRY_BEAM, earth peaks on the outer columns. Members only.
static func gantry_members(far: bool) -> Array:
	var out: Array = []
	var hb := Ridges.GANTRY_BEAM
	var half := Ridges.GANTRY_HALF
	var w := 0.6
	for cx: float in [-half, 0.0, half]:
		var top := hb + (4.6 if absf(cx) > 1.0 else 1.2)
		var n := int(top / 1.5)
		for c in 4:
			var s: Vector2 = CORNER_SIGNS[c]
			var a := Vector3(cx + s.x * w, 0.0, s.y * w)
			out.append([a, a + Vector3(0, top, 0), 0.1, Vector3(-s.x, 0, 0), Vector3(0, 0, -s.y), STEEL])
		if far:
			continue
		for i in n:
			var y0 := top * i / n
			var y1 := top * (i + 1) / n
			for c in 4:
				var s0: Vector2 = CORNER_SIGNS[c]
				var s1: Vector2 = CORNER_SIGNS[(c + 1) % 4]
				var nrm := Vector3(s0.x + s1.x, 0, s0.y + s1.y).normalized()
				out.append([Vector3(cx + s0.x * w, y0, s0.y * w), Vector3(cx + s1.x * w, y1, s1.y * w), 0.05, nrm.cross(Vector3.UP), -nrm, STEEL_DARK])
	# The beam: a box truss 1.2 m square across both bays.
	var bw := 0.6
	for c in 4:
		var s: Vector2 = CORNER_SIGNS[c]
		out.append([Vector3(-half, hb + s.x * bw, s.y * bw), Vector3(half, hb + s.x * bw, s.y * bw), 0.09, Vector3(0, -s.x, 0), Vector3(0, 0, -s.y), STEEL])
	if not far:
		var n := int(half * 2.0 / 1.2)
		for i in n:
			var x0 := -half + half * 2.0 * i / n
			var x1 := -half + half * 2.0 * (i + 1) / n
			for c in 4:
				var s0: Vector2 = CORNER_SIGNS[c]
				var s1: Vector2 = CORNER_SIGNS[(c + 1) % 4]
				out.append([Vector3(x0, hb + s0.x * bw, s0.y * bw), Vector3(x1, hb + s1.x * bw, s1.y * bw), 0.05, Vector3.UP, Vector3.FORWARD, STEEL_DARK])
	return out


## The yard: gravel, the transformers (tank, radiator banks, conservator, bushings), breakers,
## bus supports with their porcelain posts and tubular bus, the gantries, light masts and the
## control house, in WORLD space less `origin` (the chunk's local frame). Built once per seed.
static func substation_mesh(sub: Dictionary, origin: Vector3, seed_value: int) -> ArrayMesh:
	var key := "sub_%d" % seed_value
	if _cache.has(key):
		return _cache[key]
	var acc := Acc.new()
	var rect: Rect2 = sub.rect
	var y: float = float(sub.base)
	var c3 := Vector3(rect.get_center().x, y, rect.get_center().y) - origin
	var long_x := rect.size.x >= rect.size.y
	var ax := Vector3(1, 0, 0) if long_x else Vector3(0, 0, 1)
	var bx := Vector3(0, 0, 1) if long_x else Vector3(1, 0, 0)
	var la := maxf(rect.size.x, rect.size.y)
	var lb := minf(rect.size.x, rect.size.y)
	for g: Dictionary in sub.gantries:
		var gp: Vector2 = g.pos
		var xf := Transform3D(Basis(Vector3.UP, float(g.yaw)), Vector3(gp.x, y, gp.y) - origin)
		for m: Array in gantry_members(false):
			acc.angle("steel", xf * (m[0] as Vector3), xf * (m[1] as Vector3), float(m[2]), xf.basis * (m[3] as Vector3), xf.basis * (m[4] as Vector3), m[5])
		for cx: float in [-Ridges.GANTRY_HALF, 0.0, Ridges.GANTRY_HALF]:
			acc.box("concrete", xf * Transform3D(Basis().scaled(Vector3(1.8, 0.8, 1.8)), Vector3(cx, 0.1, 0)), Color.WHITE)
		# Tension strings off the beam toward the line, and droppers down to the bus.
		for side: float in [-1.0, 1.0]:
			for k in 3:
				var x := side * (2.0 + 4.2 * float(k))
				var a := xf * Vector3(x, Ridges.GANTRY_BEAM - 0.5, 0.6)
				var b := xf * Vector3(x, Ridges.GANTRY_BEAM - 0.4, Ridges.TENSION)
				_string(acc, a, b, xf.basis * Vector3(1, 0, 0))
	# Transformers in a row down the middle of the yard, each in its oil-containment curb.
	var nt := 3 if la > 150.0 else 2
	for i in nt:
		var along := lerpf(-la * 0.22, la * 0.22, float(i) / maxf(nt - 1, 1))
		var p := c3 + ax * along
		_transformer(acc, p, ax, bx)
	# Breakers and bus supports in two bays either side.
	for sg: float in [-1.0, 1.0]:
		for i in 6:
			var along := lerpf(-la * 0.38, la * 0.38, float(i) / 5.0)
			var p := c3 + ax * along + bx * sg * lb * 0.26
			_breaker(acc, p, ax)
			var q := c3 + ax * along + bx * sg * lb * 0.12
			for k in 3:
				var pk := q + ax * (float(k) - 1.0) * 2.4
				acc.beam("steel", pk, pk + Vector3(0, 3.2, 0), 0.28, 0.28, STEEL)
				acc.cyl("porcelain", pk + Vector3(0, 3.2, 0), pk + Vector3(0, 5.2, 0), 0.13, 0.11, 8, PORCELAIN)
				for j in 7:
					var yy := 3.4 + j * 0.25
					acc.cyl("porcelain", pk + Vector3(0, yy, 0), pk + Vector3(0, yy + 0.06, 0), 0.24, 0.24, 8, PORCELAIN, true, true)
		# Tubular bus along each bay.
		for k in 3:
			var off := c3 + bx * sg * lb * 0.12 + Vector3(0, 5.35, 0)
			acc.cyl("steel", off + ax * (-la * 0.42) + ax.cross(Vector3.UP) * 0.0 + ax * (float(k) - 1.0) * 0.0 + bx * (float(k) - 1.0) * 2.4,
				off + ax * (la * 0.42) + bx * (float(k) - 1.0) * 2.4, 0.06, 0.06, 6, Color(0.75, 0.76, 0.76), true, true)
	# The control house at one end, light masts at the corners.
	var house := c3 + ax * (la * 0.5 - 12.0) + bx * (lb * 0.5 - 9.0)
	acc.box("paint", Transform3D(Basis(ax * 18.0, Vector3(0, 4.4, 0), bx * 10.0), house + Vector3(0, 2.2, 0)), Color(0.78, 0.74, 0.66))
	acc.box("paint", Transform3D(Basis(ax * 18.6, Vector3(0, 0.4, 0), bx * 10.6), house + Vector3(0, 4.6, 0)), Color(0.6, 0.58, 0.55))
	acc.box("paint", Transform3D(Basis(ax * 1.0, Vector3(0, 2.2, 0), bx * 0.1), house + Vector3(0, 1.1, 0) - bx * 5.02), Color(0.38, 0.4, 0.42))
	for i in 3:
		acc.box("solid", Transform3D(Basis(ax * 1.1, Vector3(0, 1.0, 0), bx * 1.1), house + ax * (float(i) - 1.0) * 4.0 + Vector3(0, 5.3, 0)), Color(0.8, 0.8, 0.78))
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var p := c3 + ax * cx * (la * 0.5 - 4.0) + bx * cz * (lb * 0.5 - 4.0)
			acc.cyl("steel", p, p + Vector3(0, 14.0, 0), 0.16, 0.1, 8, STEEL)
			acc.box("solid", Transform3D(Basis().scaled(Vector3(0.6, 0.3, 0.6)), p + Vector3(0, 14.1, 0)), Color(0.3, 0.3, 0.3))
	var mesh := acc.commit({})
	_cache[key] = mesh
	return mesh


## A power transformer: the main tank with stiffeners, radiator banks of fins on both long sides,
## the conservator on its stand, three HV bushings with their sheds, three LV ones, the curb.
static func _transformer(acc: Acc, p: Vector3, ax: Vector3, bx: Vector3) -> void:
	var col := Color(0.52, 0.55, 0.52)
	acc.box("concrete", Transform3D(Basis(ax * 13.0, Vector3(0, 0.5, 0), bx * 11.0), p + Vector3(0, 0.2, 0)), Color.WHITE)
	acc.box("paint", Transform3D(Basis(ax * 6.0, Vector3(0, 4.2, 0), bx * 3.4), p + Vector3(0, 2.6, 0)), col)
	for i in 6:
		acc.beam("paint", p + ax * (-2.5 + i) - bx * 1.75 + Vector3(0, 0.5, 0), p + ax * (-2.5 + i) - bx * 1.75 + Vector3(0, 4.7, 0), 0.12, 0.12, col * 0.9)
	for sg: float in [-1.0, 1.0]:
		for i in 14:
			var fx := ax * (-2.6 + i * 0.4)
			acc.box("paint", Transform3D(Basis(ax * 0.05, Vector3(0, 3.2, 0), bx * 1.1), p + fx + bx * sg * 2.45 + Vector3(0, 2.4, 0)), col * (0.95 if i % 2 == 0 else 0.85))
		acc.beam("paint", p + ax * -2.8 + bx * sg * 2.0 + Vector3(0, 4.1, 0), p + ax * 2.8 + bx * sg * 2.0 + Vector3(0, 4.1, 0), 0.14, 0.14, col)
	acc.cyl("paint", p + ax * -2.8 + Vector3(0, 6.0, 0) + bx * 1.1, p + ax * 1.0 + Vector3(0, 6.0, 0) + bx * 1.1, 0.55, 0.55, 12, col, true, true)
	acc.beam("paint", p + ax * -1.0 + bx * 1.1 + Vector3(0, 4.7, 0), p + ax * -1.0 + bx * 1.1 + Vector3(0, 5.5, 0), 0.15, 0.15, col)
	for k in 3:
		var b := p + ax * (float(k) - 1.0) * 1.7 + Vector3(0, 4.7, 0) - bx * 0.6
		acc.cyl("porcelain", b, b + Vector3(0, 2.6, 0), 0.16, 0.09, 8, PORCELAIN)
		for j in 9:
			var yy := 0.3 + j * 0.25
			acc.cyl("porcelain", b + Vector3(0, yy, 0), b + Vector3(0, yy + 0.05, 0), 0.26, 0.26, 8, PORCELAIN, true, true)
		var l := p + ax * (float(k) - 1.0) * 1.2 + Vector3(0, 4.7, 0) + bx * 0.9
		acc.cyl("porcelain", l, l + Vector3(0, 1.0, 0), 0.1, 0.07, 8, PORCELAIN)


## A dead-tank SF6 breaker: three horizontal tanks on a frame, a bushing pair on each, the cabinet.
static func _breaker(acc: Acc, p: Vector3, ax: Vector3) -> void:
	var bx := Vector3.UP.cross(ax).normalized()
	for k in 3:
		var c := p + ax * (float(k) - 1.0) * 2.4
		acc.beam("steel", c - bx * 0.9, c - bx * 0.9 + Vector3(0, 2.0, 0), 0.12, 0.12, STEEL)
		acc.beam("steel", c + bx * 0.9, c + bx * 0.9 + Vector3(0, 2.0, 0), 0.12, 0.12, STEEL)
		acc.cyl("solid", c - bx * 1.2 + Vector3(0, 2.3, 0), c + bx * 1.2 + Vector3(0, 2.3, 0), 0.42, 0.42, 12, Color(0.7, 0.72, 0.72), true, true)
		for sg: float in [-1.0, 1.0]:
			var b := c + bx * sg * 0.75 + Vector3(0, 2.6, 0)
			var tip := b + Vector3(0, 2.0, 0) + bx * sg * 0.5
			acc.cyl("porcelain", b, tip, 0.14, 0.08, 8, PORCELAIN)
	acc.box("solid", Transform3D(Basis(ax * 1.0, Vector3(0, 1.6, 0), bx * 0.6), p + ax * 3.8 + Vector3(0, 0.8, 0)), Color(0.66, 0.68, 0.68))


# --- Gates -----------------------------------------------------------------------------------

## A fire road gate in its frame (z along the road, x across): two steel posts, a swing gate of
## pipe rails, a padlock box, and a sign board on a post beside it.
static func gate_mesh(w: float) -> ArrayMesh:
	var key := "gate_%d" % int(w * 10.0)
	if _cache.has(key):
		return _cache[key]
	var acc := Acc.new()
	var half := w * 0.5 + 0.6
	var yellow := Color(0.82, 0.68, 0.16)
	for sg: float in [-1.0, 1.0]:
		acc.cyl("paint", Vector3(sg * half, -0.6, 0), Vector3(sg * half, 1.3, 0), 0.1, 0.1, 10, yellow)
	for y: float in [0.45, 1.05]:
		acc.cyl("paint", Vector3(-half + 0.1, y, 0), Vector3(half - 0.1, y, 0), 0.045, 0.045, 8, yellow, true, true)
	for k in 5:
		var x := lerpf(-half + 0.3, half - 0.3, k / 4.0)
		acc.cyl("paint", Vector3(x, 0.45, 0), Vector3(x, 1.05, 0), 0.03, 0.03, 6, yellow)
	acc.cyl("paint", Vector3(-half + 0.1, 0.45, 0), Vector3(half - 0.1, 1.05, 0), 0.03, 0.03, 6, yellow)
	acc.box("steel", Transform3D(Basis().scaled(Vector3(0.12, 0.16, 0.1)), Vector3(half - 0.2, 0.8, 0.06)), STEEL_DARK)
	acc.cyl("steel", Vector3(half + 1.4, -0.5, 0.3), Vector3(half + 1.4, 1.9, 0.3), 0.04, 0.04, 6, STEEL_DARK)
	acc.box("paint", Transform3D(Basis().scaled(Vector3(0.9, 0.6, 0.03)), Vector3(half + 1.4, 1.75, 0.34)), Color(0.82, 0.8, 0.74))
	acc.box("paint", Transform3D(Basis().scaled(Vector3(0.82, 0.14, 0.035)), Vector3(half + 1.4, 1.93, 0.345)), Color(0.62, 0.12, 0.08))
	var mesh := acc.commit({})
	_cache[key] = mesh
	return mesh
