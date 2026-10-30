class_name PowerPlantKit
extends RefCounted
## The power plant's hardware (PowerPlant lays it out), built in code at real size on ONE shader
## (shaders/power_plant.gdshader): the generating building's turbine hall and boiler house in
## ribbed metal cladding over a concrete plinth with window bands, the twin concrete stacks with
## their red and white aviation bands, platforms and ladders, the flue ducts, the combined-cycle
## trains (filter houses on legs, gas turbine enclosures, heat-recovery boilers with stiffeners,
## drums, stair towers and their steel stacks), the steam turbine hall, step-up transformers behind
## their fire walls, pipe racks and bridges of insulated pipe, the pump house and its big blue
## pipes, tanks with roofs, stairs and girders, the fuel berm, the switchyard (lattice gantries,
## breakers, disconnects, bus, two transformers, the control house), the offices with the company's
## name, the guard booth, the chain-link fence, the flood masts, the seawall and the intake.
##
## Vertex layout (the contract with the shader):
##   COLOR.rgb  paint, sRGB as written (vertex colours arrive raw on both renderers)
##   COLOR.a    the kind (K_*), in 32nds
##   UV         metres in the face's own frame (x along it, y up it; a cylinder: x round, y along)
##   UV2        x the piece's height (a stack's bands), y a per-face parameter (a seed)
## `full` false is the LOD chunks' version: the same masses with the small things left out.

const K_CLAD := 0
const K_CONCRETE := 1
const K_STEEL := 2
const K_GALV := 3
const K_STACK := 4
const K_GLASS := 5
const K_LAMP := 6
const K_RED := 7
const K_JACKET := 8
const K_ROOF := 9
const K_GRATING := 10
const K_LOUVRE := 11
const K_TANK := 12
const K_FINS := 13
const K_DARK := 14
const K_SIGN := 15
const K_LETTER := 16
const K_ROCK := 17
const K_PORCELAIN := 18
const K_CHAIN := 19
const K_DOOR := 20

const CLAD_HALL := Color(0.80, 0.76, 0.66)
const CLAD_BOILER := Color(0.62, 0.66, 0.68)
const CLAD_ST := Color(0.78, 0.79, 0.76)
const STEEL_GREY := Color(0.55, 0.57, 0.57)
const STEEL_DARK := Color(0.30, 0.31, 0.31)
const GT_GREEN := Color(0.50, 0.58, 0.54)
const HRSG_GREY := Color(0.60, 0.62, 0.62)
const PIPE_BLUE := Color(0.20, 0.36, 0.56)
const YELLOW := Color(0.86, 0.70, 0.12)
const XFMR := Color(0.50, 0.53, 0.50)
const CONCRETE := Color(0.76, 0.74, 0.70)
const WHITE := Color(0.90, 0.90, 0.88)

static var _material: ShaderMaterial = null


class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var full := true

	func _col(kind: int, paint: Color) -> Color:
		return Color(paint.r, paint.g, paint.b, (float(kind) + 0.5) / 32.0)

	## A triangle facing `nrm` (its front is clockwise seen from in front).
	func tri(a: Vector3, b: Vector3, cc: Vector3, nrm: Vector3, kind: int, paint: Color, ua: Vector2, ub: Vector2, uc: Vector2, p2: Vector2) -> void:
		var col := _col(kind, paint)
		var nn := nrm.normalized()
		if (b - a).cross(cc - a).dot(nn) > 0.0:
			var t := b
			b = cc
			cc = t
			var tu := ub
			ub = uc
			uc = tu
		for k in 3:
			v.append([a, b, cc][k])
			n.append(nn)
			c.append(col)
			uv.append([ua, ub, uc][k])
			uv2.append(p2)

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Vector3, kind: int, paint: Color, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, p2: Vector2) -> void:
		tri(a, b, cc, nrm, kind, paint, ua, ub, uc, p2)
		tri(a, cc, d, nrm, kind, paint, ua, uc, ud, p2)

	## A box of `size` placed by `xf` (centre, turn; no scale). UV in metres per face: x along the
	## face, y up from the box's foot (a top face: x and z). `skip`: 1 +x, 2 -x, 4 +z, 8 -z, 16
	## top, 32 bottom (the bottom is left out unless asked for).
	func box(xf: Transform3D, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 32) -> void:
		var h := size * 0.5
		var faces := [
			[Vector3(1, 0, 0), Vector3(0, 0, -1), size.z, size.y],
			[Vector3(-1, 0, 0), Vector3(0, 0, 1), size.z, size.y],
			[Vector3(0, 0, 1), Vector3(1, 0, 0), size.x, size.y],
			[Vector3(0, 0, -1), Vector3(-1, 0, 0), size.x, size.y],
			[Vector3(0, 1, 0), Vector3(1, 0, 0), size.x, size.z],
			[Vector3(0, -1, 0), Vector3(1, 0, 0), size.x, size.z]]
		for f in 6:
			if skip & (1 << f):
				continue
			var fn: Vector3 = faces[f][0]
			var ax: Vector3 = faces[f][1]
			var up := Vector3.UP if absf(fn.y) < 0.5 else Vector3(0, 0, 1)
			var ca := fn * h
			var eu := ax * (h * ax.abs()).length()
			var ev := up * (h * up.abs()).length()
			var w: float = faces[f][2]
			var hh: float = faces[f][3]
			var p00 := xf * (ca - eu - ev)
			var p10 := xf * (ca + eu - ev)
			var p11 := xf * (ca + eu + ev)
			var p01 := xf * (ca - eu + ev)
			quad(p00, p10, p11, p01, xf.basis * fn, kind, paint, Vector2(0, 0), Vector2(w, 0), Vector2(w, hh), Vector2(0, hh), Vector2(size.y, param))

	## A box between two points (a beam) of section `sx` x `sy`; `up` hints its turn.
	func beam(a: Vector3, b: Vector3, sx: float, sy: float, kind: int, paint: Color, up := Vector3.UP, skip := 0) -> void:
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
		box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(sx, sy, l), kind, paint, 0.0, skip)

	## A cylinder (a cone when r0 != r1) on the axis a -> b, `segs` sided. UV: x metres round, y
	## metres along from `a`; UV2.x `h2` (a stack's height, for its bands).
	func cyl(a: Vector3, b: Vector3, r0: float, r1: float, segs: int, kind: int, paint: Color, cap_b := true, cap_a := false, h2 := -1.0, param := 0.0) -> void:
		var axis := b - a
		var l := axis.length()
		if l < 0.001:
			return
		axis /= l
		var x := Vector3.UP.cross(axis)
		if x.length_squared() < 0.001:
			x = Vector3.RIGHT
		x = x.normalized()
		var y := axis.cross(x)
		var slope := (r0 - r1) / l
		var p2 := Vector2(l if h2 < 0.0 else h2, param)
		var circ := TAU * maxf(r0, r1)
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var d0 := x * cos(a0) + y * sin(a0)
			var d1 := x * cos(a1) + y * sin(a1)
			var nm := ((d0 + d1).normalized() + axis * slope).normalized()
			var u0 := circ * float(i) / float(segs)
			var u1 := circ * float(i + 1) / float(segs)
			quad(a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1, nm, kind, paint, Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, l), Vector2(u0, l), p2)
			if cap_b and r1 > 0.0:
				tri(b, b + d0 * r1, b + d1 * r1, axis, kind, paint, Vector2(0, 0), Vector2(d0.dot(x), d0.dot(y)) * r1, Vector2(d1.dot(x), d1.dot(y)) * r1, p2)
			if cap_a and r0 > 0.0:
				tri(a, a + d0 * r0, a + d1 * r0, -axis, kind, paint, Vector2(0, 0), Vector2(d0.dot(x), d0.dot(y)) * r0, Vector2(d1.dot(x), d1.dot(y)) * r0, p2)

	## A lattice angle member (two flanges, drawn both ways round: the material culls nothing).
	func angle(a: Vector3, b: Vector3, w: float, f1: Vector3, f2: Vector3, paint: Color) -> void:
		var d := (b - a).normalized()
		var g1 := (f1 - d * f1.dot(d)).normalized()
		var g2 := (f2 - d * f2.dot(d)).normalized()
		if g1.length_squared() < 0.5 or g2.length_squared() < 0.5:
			var any := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
			g1 = d.cross(any).normalized()
			g2 = d.cross(g1).normalized()
		var l := a.distance_to(b)
		quad(a, b, b + g1 * w, a + g1 * w, d.cross(g1), K_GALV, paint, Vector2(0, 0), Vector2(l, 0), Vector2(l, w), Vector2(0, w), Vector2.ZERO)
		quad(a, b, b + g2 * w, a + g2 * w, d.cross(g2), K_GALV, paint, Vector2(0, 0), Vector2(l, 0), Vector2(l, w), Vector2(0, w), Vector2.ZERO)

	## A handrail along a -> b (top rail, knee rail, posts), `h` high. FULL only.
	func rail(a: Vector3, b: Vector3, h := 1.07, paint := YELLOW) -> void:
		if not full:
			return
		var l := a.distance_to(b)
		if l < 0.2:
			return
		beam(a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.05, 0.05, K_STEEL, paint)
		beam(a + Vector3(0, h * 0.5, 0), b + Vector3(0, h * 0.5, 0), 0.04, 0.04, K_STEEL, paint)
		var np := maxi(1, int(l / 1.8))
		for i in np + 1:
			var p := a.lerp(b, float(i) / float(np))
			beam(p, p + Vector3(0, h, 0), 0.05, 0.05, K_STEEL, paint)

	## A walkway of grating with rails round its open sides: rect (local x0, z0, x1, z1) at `y`,
	## placed by `xf`. `sides` bit mask of railed sides (1 -x, 2 +x, 4 -z, 8 +z).
	func platform(xf: Transform3D, r: Rect2, y: float, sides: int) -> void:
		var c := Vector3(r.get_center().x, y, r.get_center().y)
		box(xf * Transform3D(Basis(), c), Vector3(r.size.x, 0.08, r.size.y), K_GRATING, STEEL_GREY, 0.0, 0)
		if not full:
			return
		var p00 := xf * Vector3(r.position.x, y, r.position.y)
		var p10 := xf * Vector3(r.end.x, y, r.position.y)
		var p11 := xf * Vector3(r.end.x, y, r.end.y)
		var p01 := xf * Vector3(r.position.x, y, r.end.y)
		if sides & 1:
			rail(p00, p01)
		if sides & 2:
			rail(p10, p11)
		if sides & 4:
			rail(p00, p10)
		if sides & 8:
			rail(p01, p11)

	## A caged ladder up a face from `a` to `b` (out along `out`). FULL only.
	func ladder(a: Vector3, b: Vector3, out: Vector3) -> void:
		if not full:
			return
		var side := out.cross(Vector3.UP).normalized() * 0.23
		beam(a + side + out * 0.2, b + side + out * 0.2, 0.05, 0.05, K_STEEL, STEEL_GREY)
		beam(a - side + out * 0.2, b - side + out * 0.2, 0.05, 0.05, K_STEEL, STEEL_GREY)
		var h := b.y - a.y
		var hoops := int(h / 1.2)
		for i in hoops:
			var y := a.y + 2.4 + float(i) * 1.2
			if y > b.y:
				break
			var p := Vector3(a.x, y, a.z) + out * 0.2
			beam(p + side, p + side + out * 0.7, 0.04, 0.04, K_STEEL, STEEL_GREY)
			beam(p - side, p - side + out * 0.7, 0.04, 0.04, K_STEEL, STEEL_GREY)
			beam(p + side + out * 0.7, p - side + out * 0.7, 0.04, 0.04, K_STEEL, STEEL_GREY)

	func tris() -> int:
		return v.size() / 3

	func mesh(mat: Material) -> ArrayMesh:
		var m := ArrayMesh.new()
		if v.is_empty():
			return m
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, mat)
		return m


static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/power_plant.gdshader")
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("corrugated_tex", PropFactory.texture("metal_corrugated", "Color"))
	_material = mat
	return mat


# =================================================================================================
# Pieces. Each writes into `g` at `o` (the ground under the piece's centre, world space less the
# chunk's origin - a chunk's local space IS the true world while it sits at -world_offset).
# =================================================================================================

static func build_piece(g: Geo, p: Dictionary, o: Vector3) -> void:
	var sz: Vector3 = p.size
	var sd: int = int(p.seed)
	match String(p.kind):
		"turbine_hall":
			hall(g, o, sz, CLAD_HALL, sd, true)
		"st_hall":
			hall(g, o, sz, CLAD_ST, sd, false)
		"boiler_house":
			boiler_house(g, o, sz, sd)
		"stack", "hrsg_stack":
			stack(g, o, float(p.r0), float(p.r1), sz.y, bool(p.bands), String(p.kind) == "stack")
		"flue":
			flue(g, o, sz, float(p.y))
		"filter_house":
			filter_house(g, o, sz)
		"gas_turbine":
			gas_turbine(g, o, sz)
		"hrsg":
			hrsg(g, o, sz)
		"gsu":
			transformer(g, o, Vector3(1, 0, 0), true)
		"pipe_bridge":
			pipe_bridge(g, o, sz)
		"pipe_rack":
			pipe_rack(g, o, sz)
		"pump_house":
			pump_house(g, o, sz)
		"tank":
			tank(g, o, float(p.r), sz.y, p.paint, bool(p.get("fuel", false)))
		"berm":
			berm(g, o, sz)
		"switchyard":
			switchyard(g, o, sz, sd)
		"admin":
			admin(g, o, sz)
		"guard":
			guard(g, o, sz)


## A generating hall: a concrete plinth, ribbed cladding to the eaves, a window band under them on
## the long sides, steel pilasters every bay, a low roof with a ridge vent, louvres low down, a
## roll-up door in each gable.
static func hall(g: Geo, o: Vector3, sz: Vector3, clad: Color, sd: int, sea_side: bool) -> void:
	var plinth := 3.2
	g.box(Transform3D(Basis(), o + Vector3(0, plinth * 0.5, 0)), Vector3(sz.x + 0.4, plinth, sz.z + 0.4), K_CONCRETE, CONCRETE, float(sd % 97))
	var wall := sz.y - plinth - 1.0
	g.box(Transform3D(Basis(), o + Vector3(0, plinth + wall * 0.5, 0)), Vector3(sz.x, wall, sz.z), K_CLAD, clad, float(sd % 89), 16)
	# The window band under the eaves on both long sides, and the gables'.
	var band_y := plinth + wall - 5.0
	for sx: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), o + Vector3(sx * (sz.x * 0.5 + 0.03), band_y + 1.6, 0)), Vector3(0.08, 3.2, sz.z - 6.0), K_GLASS, Color(0.3, 0.36, 0.4), float(sd % 53))
	for sz_: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), o + Vector3(0, band_y + 1.6, sz_ * (sz.z * 0.5 + 0.03))), Vector3(sz.x - 8.0, 3.2, 0.08), K_GLASS, Color(0.3, 0.36, 0.4), float(sd % 41))
	# Roof: a parapet band, the low roof, the ridge vent along it, roof fans.
	var top := plinth + wall
	g.box(Transform3D(Basis(), o + Vector3(0, top + 0.5, 0)), Vector3(sz.x + 0.3, 1.0, sz.z + 0.3), K_STEEL, clad * 0.82, 0.0, 16)
	g.box(Transform3D(Basis(), o + Vector3(0, top + 0.3, 0)), Vector3(sz.x, 0.6, sz.z), K_ROOF, Color(0.56, 0.56, 0.54), float(sd % 31), 15)
	g.box(Transform3D(Basis(), o + Vector3(0, top + 1.5, 0)), Vector3(4.0, 2.4, sz.z * 0.85), K_LOUVRE, clad * 0.9)
	g.box(Transform3D(Basis(), o + Vector3(0, top + 2.8, 0)), Vector3(5.4, 0.25, sz.z * 0.85 + 0.6), K_STEEL, clad * 0.75)
	if g.full:
		var nf := int(sz.z / 18.0)
		for i in nf:
			var z := -sz.z * 0.4 + sz.z * 0.8 * (float(i) + 0.5) / float(nf)
			for sx: float in [-1.0, 1.0]:
				var p := o + Vector3(sx * sz.x * 0.3, top + 0.6, z)
				g.cyl(p, p + Vector3(0, 1.4, 0), 1.0, 1.0, 10, K_STEEL, STEEL_GREY)
				g.cyl(p + Vector3(0, 1.4, 0), p + Vector3(0, 1.75, 0), 1.25, 0.2, 10, K_STEEL, STEEL_GREY)
		# Pilasters every bay on the long walls, louvres between them low down.
		var nb := int(sz.z / 7.5)
		for i in nb + 1:
			var z := -sz.z * 0.5 + sz.z * float(i) / float(nb)
			for sx: float in [-1.0, 1.0]:
				g.box(Transform3D(Basis(), o + Vector3(sx * (sz.x * 0.5 + 0.18), plinth + wall * 0.5, z)), Vector3(0.36, wall, 0.5), K_STEEL, clad * 0.78, 0.0, 16)
			if i < nb and i % 3 == 1:
				for sx: float in [-1.0, 1.0]:
					g.box(Transform3D(Basis(), o + Vector3(sx * (sz.x * 0.5 + 0.05), plinth + 2.2, z + sz.z / float(nb) * 0.5)), Vector3(0.1, 2.4, 3.6), K_LOUVRE, clad * 0.85)
		# Downpipes at the corners.
		for sx: float in [-1.0, 1.0]:
			for sz_: float in [-1.0, 1.0]:
				var p := o + Vector3(sx * (sz.x * 0.5 + 0.25), 0.0, sz_ * (sz.z * 0.5 - 1.0))
				g.cyl(p, p + Vector3(0, top, 0), 0.12, 0.12, 6, K_STEEL, clad * 0.7)
	# A roll-up door in each gable, a personnel door beside it.
	for sz_: float in [-1.0, 1.0]:
		var face := o + Vector3(0, 0, sz_ * (sz.z * 0.5 + 0.06))
		g.box(Transform3D(Basis(), face + Vector3(-sz.x * 0.15, 5.0, 0)), Vector3(8.0, 10.0, 0.1), K_DOOR, Color(0.66, 0.67, 0.66))
		g.box(Transform3D(Basis(), face + Vector3(-sz.x * 0.15, 10.25, sz_ * 0.2)), Vector3(8.6, 0.5, 0.4), K_STEEL, STEEL_DARK)
		g.box(Transform3D(Basis(), face + Vector3(sz.x * 0.25, 1.1, 0)), Vector3(1.0, 2.2, 0.1), K_STEEL, Color(0.4, 0.44, 0.5))
	if sea_side and g.full:
		# Gantry crane rails' end stops and a hoist beam out over the west yard.
		var p := o + Vector3(-sz.x * 0.5, top - 3.0, sz.z * 0.3)
		g.beam(p, p + Vector3(-5.0, 0, 0), 0.4, 0.7, K_STEEL, YELLOW)


## The boiler house: taller, the cladding darker, vertical window strips, a stair tower with a
## landing every 6 m, ring platforms near the top, roof penthouses.
static func boiler_house(g: Geo, o: Vector3, sz: Vector3, sd: int) -> void:
	var plinth := 3.0
	g.box(Transform3D(Basis(), o + Vector3(0, plinth * 0.5, 0)), Vector3(sz.x + 0.4, plinth, sz.z + 0.4), K_CONCRETE, CONCRETE, float(sd % 97))
	var wall := sz.y - plinth
	g.box(Transform3D(Basis(), o + Vector3(0, plinth + wall * 0.5, 0)), Vector3(sz.x, wall, sz.z), K_CLAD, CLAD_BOILER, float(sd % 89), 16)
	g.box(Transform3D(Basis(), o + Vector3(0, sz.y + 0.35, 0)), Vector3(sz.x + 0.3, 0.7, sz.z + 0.3), K_ROOF, Color(0.5, 0.5, 0.49), float(sd % 23))
	# Vertical window strips on the long faces.
	var ns := int(sz.z / 14.0)
	for i in ns:
		var z := -sz.z * 0.5 + sz.z * (float(i) + 0.5) / float(ns)
		for sx: float in [-1.0, 1.0]:
			g.box(Transform3D(Basis(), o + Vector3(sx * (sz.x * 0.5 + 0.03), plinth + wall * 0.52, z)), Vector3(0.08, wall * 0.72, 2.2), K_GLASS, Color(0.28, 0.33, 0.38), float((sd + i) % 61))
	# The two penthouses and a row of roof vents.
	for sz_: float in [-0.25, 0.25]:
		g.box(Transform3D(Basis(), o + Vector3(sz.x * 0.15, sz.y + 3.2, sz_ * sz.z)), Vector3(12.0, 5.6, 14.0), K_CLAD, CLAD_BOILER * 0.92, float(sd % 13), 0)
		g.box(Transform3D(Basis(), o + Vector3(sz.x * 0.15, sz.y + 6.1, sz_ * sz.z)), Vector3(12.4, 0.2, 14.4), K_ROOF, Color(0.48, 0.48, 0.47))
	for i in 4:
		var z := lerpf(-sz.z * 0.4, sz.z * 0.4, float(i) / 3.0)
		g.cyl(o + Vector3(-sz.x * 0.25, sz.y + 0.7, z), o + Vector3(-sz.x * 0.25, sz.y + 4.5, z), 0.8, 0.8, 10, K_STEEL, STEEL_GREY)
	# The stair tower on the north face, its landings, railed ring platforms round the top.
	var st := o + Vector3(sz.x * 0.25, 0.0, -sz.z * 0.5 - 3.2)
	stair_tower(g, st, sz.y + 2.0, 5.6, 6.0)
	if g.full:
		for y: float in [sz.y - 6.0, sz.y - 18.0]:
			var x := Transform3D(Basis(), o)
			g.platform(x, Rect2(sz.x * 0.5, -sz.z * 0.45, 1.6, sz.z * 0.9), y, 2)
			for i in 10:
				var z := lerpf(-sz.z * 0.45, sz.z * 0.45, float(i) / 9.0)
				g.beam(o + Vector3(sz.x * 0.5, y - 1.2, z), o + Vector3(sz.x * 0.5 + 1.5, y - 0.05, z), 0.12, 0.12, K_STEEL, STEEL_GREY)
		g.ladder(o + Vector3(-sz.x * 0.5, plinth, sz.z * 0.3), o + Vector3(-sz.x * 0.5, sz.y, sz.z * 0.3), Vector3(-1, 0, 0))


## A steel stair tower: four corner columns, bracing, a stair flight and a landing every `lift`.
static func stair_tower(g: Geo, o: Vector3, h: float, w: float, lift: float) -> void:
	var hw := w * 0.5
	for c in 4:
		var s: Vector2 = RidgeKit.CORNER_SIGNS[c]
		var p := o + Vector3(s.x * hw, 0.0, s.y * hw)
		g.beam(p, p + Vector3(0, h, 0), 0.3, 0.3, K_STEEL, STEEL_GREY)
	var n := int(h / lift)
	for i in n:
		var y0 := float(i) * lift
		var y1 := y0 + lift
		g.box(Transform3D(Basis(), o + Vector3(0, y1, 0)), Vector3(w, 0.1, w), K_GRATING, STEEL_GREY, 0.0, 0)
		if g.full:
			var a := o + Vector3(-hw + 0.6, y0, -hw * 0.3 if i % 2 == 0 else hw * 0.3)
			var b := o + Vector3(hw - 0.6, y1, -hw * 0.3 if i % 2 == 0 else hw * 0.3)
			if i % 2 == 1:
				var t := a
				a = Vector3(b.x, a.y, a.z)
				b = Vector3(t.x, b.y, b.z)
			g.beam(a, b, 1.0, 0.18, K_GRATING, STEEL_GREY, Vector3.UP)
			g.rail(o + Vector3(-hw, y1, -hw), o + Vector3(hw, y1, -hw))
			g.rail(o + Vector3(-hw, y1, hw), o + Vector3(hw, y1, hw))
			# X bracing on two faces.
			g.beam(o + Vector3(-hw, y0, -hw), o + Vector3(hw, y1, -hw), 0.12, 0.12, K_STEEL, STEEL_GREY)
			g.beam(o + Vector3(hw, y0, hw), o + Vector3(-hw, y1, hw), 0.12, 0.12, K_STEEL, STEEL_GREY)


## A stack: a tapering shell (concrete with the aviation bands painted at the top, or steel), its
## foundation ring, a platform with railing near the top, a caged ladder up it, the top band.
static func stack(g: Geo, o: Vector3, r0: float, r1: float, h: float, bands: bool, concrete: bool) -> void:
	var segs := 24 if g.full else 12
	var kind := K_STACK if concrete else K_JACKET
	var paint := Color(0.74, 0.72, 0.68) if concrete else Color(0.62, 0.64, 0.64)
	g.cyl(o + Vector3(0, -0.5, 0), o + Vector3(0, 1.2, 0), r0 + 1.6, r0 + 1.3, segs, K_CONCRETE, CONCRETE)
	g.cyl(o + Vector3(0, 1.2, 0), o + Vector3(0, h, 0), r0, r1, segs, kind, paint, false, false, h, 1.0 if bands else 0.0)
	# The open top: a dark inside wall and a lip.
	g.cyl(o + Vector3(0, h, 0), o + Vector3(0, h - 3.0, 0), r1 - 0.25, r1 - 0.25, segs, K_DARK, Color(0.08, 0.08, 0.08), false, false)
	g.cyl(o + Vector3(0, h - 0.6, 0), o + Vector3(0, h + 0.25, 0), r1 + 0.18, r1 + 0.18, segs, K_STEEL, STEEL_DARK, false, false)
	var t := (h * 0.88 - 1.2) / (h - 1.2)
	var rp := lerpf(r0, r1, t)
	var py := h * 0.88
	# The platform ring and its rail.
	var nr := 16 if g.full else 8
	for i in nr:
		var a0 := TAU * float(i) / float(nr)
		var a1 := TAU * float(i + 1) / float(nr)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var o0 := o + Vector3(0, py, 0)
		g.quad(o0 + d0 * rp, o0 + d1 * rp, o0 + d1 * (rp + 1.4), o0 + d0 * (rp + 1.4), Vector3.UP, K_GRATING, STEEL_GREY, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO)
		g.quad(o0 + d0 * rp, o0 + d1 * rp, o0 + d1 * (rp + 1.4), o0 + d0 * (rp + 1.4), Vector3.DOWN, K_GRATING, STEEL_GREY, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO)
		g.rail(o0 + d0 * (rp + 1.35), o0 + d1 * (rp + 1.35))
		if g.full and i % 2 == 0:
			g.beam(o0 + d0 * rp + Vector3(0, -1.4, 0), o0 + d0 * (rp + 1.3), 0.1, 0.1, K_STEEL, STEEL_GREY)
	if not concrete:
		# Steel stacks: stiffening rings, the emissions monitoring platform and its hut.
		for y: float in [h * 0.3, h * 0.55, h * 0.76]:
			g.cyl(o + Vector3(0, y, 0), o + Vector3(0, y + 0.3, 0), r0 + 0.12, r0 + 0.12, segs, K_STEEL, STEEL_GREY, false, false)
		g.box(Transform3D(Basis(), o + Vector3(r0 + 1.4, h * 0.6 + 1.3, 0)), Vector3(2.4, 2.6, 2.6), K_CLAD, WHITE, 3.0, 0)
		g.platform(Transform3D(Basis(), o), Rect2(r0, -2.0, 3.2, 4.0), h * 0.6, 2 | 4 | 8)
	# The ladder up the side facing the yard (east).
	g.ladder(o + Vector3(lerpf(r0, r1, 0.0) + 0.05, 1.2, 0.0), o + Vector3(rp + 0.05, py, 0.0), Vector3(1, 0, 0))


## The flue duct from the boiler house's east face to a stack: a box duct on a steel trestle.
static func flue(g: Geo, o: Vector3, sz: Vector3, y: float) -> void:
	var c := o + Vector3(0, y, 0)
	g.box(Transform3D(Basis(), c), Vector3(sz.x, sz.y, sz.z), K_STEEL, Color(0.52, 0.5, 0.47), 7.0, 0)
	if g.full:
		var n := int(sz.x / 2.5)
		for i in n + 1:
			var x := -sz.x * 0.5 + sz.x * float(i) / float(n)
			g.box(Transform3D(Basis(), c + Vector3(x, 0, 0)), Vector3(0.18, sz.y + 0.25, sz.z + 0.25), K_STEEL, Color(0.44, 0.43, 0.41), 0.0, 0)
	for sx: float in [-0.25, 0.25]:
		for sz_: float in [-1.0, 1.0]:
			var p := o + Vector3(sx * sz.x, 0.0, sz_ * (sz.z * 0.5 - 0.4))
			g.beam(p, p + Vector3(0, y - sz.y * 0.5, 0), 0.5, 0.5, K_STEEL, STEEL_GREY)
		if g.full:
			g.beam(o + Vector3(sx * sz.x, y - sz.y * 0.5 - 6.0, -sz.z * 0.5 + 0.4), o + Vector3(sx * sz.x, y - sz.y * 0.5 - 6.0, sz.z * 0.5 - 0.4), 0.3, 0.4, K_STEEL, STEEL_GREY)


## The gas turbine's air filter house: a box of inlet hoods on steel legs, its duct down to the
## turbine (+x side).
static func filter_house(g: Geo, o: Vector3, sz: Vector3) -> void:
	var y0 := 9.0
	var bh := sz.y - y0
	var c := o + Vector3(0, y0 + bh * 0.5, 0)
	g.box(Transform3D(Basis(), c), Vector3(sz.x, bh, sz.z), K_STEEL, Color(0.82, 0.82, 0.8), 2.0, 0)
	# Weather hoods: louvred sloping panels in rows on the west and the two long faces.
	var rows := 4
	for r in rows:
		var y := y0 + 1.6 + float(r) * (bh - 2.4) / float(rows)
		g.box(Transform3D(Basis(Vector3(0, 0, 1), -0.5), o + Vector3(-sz.x * 0.5 - 0.7, y + 0.8, 0)), Vector3(0.12, 2.0, sz.z - 0.6), K_LOUVRE, Color(0.78, 0.78, 0.76))
		for sz_: float in [-1.0, 1.0]:
			g.box(Transform3D(Basis(Vector3(1, 0, 0), sz_ * 0.5), o + Vector3(-0.8, y + 0.8, sz_ * (sz.z * 0.5 + 0.7))), Vector3(sz.x - 2.0, 2.0, 0.12), K_LOUVRE, Color(0.78, 0.78, 0.76))
	for sx: float in [-1.0, 1.0]:
		for sz_: float in [-1.0, 1.0]:
			var p := o + Vector3(sx * (sz.x * 0.5 - 0.6), 0.0, sz_ * (sz.z * 0.5 - 0.6))
			g.beam(p, p + Vector3(0, y0, 0), 0.5, 0.5, K_STEEL, STEEL_GREY)
	if g.full:
		g.beam(o + Vector3(-sz.x * 0.5 + 0.6, 0.0, -sz.z * 0.5 + 0.6), o + Vector3(sz.x * 0.5 - 0.6, y0, -sz.z * 0.5 + 0.6), 0.2, 0.2, K_STEEL, STEEL_GREY)
		g.beam(o + Vector3(-sz.x * 0.5 + 0.6, 0.0, sz.z * 0.5 - 0.6), o + Vector3(sz.x * 0.5 - 0.6, y0, sz.z * 0.5 - 0.6), 0.2, 0.2, K_STEEL, STEEL_GREY)
		g.platform(Transform3D(Basis(), o), Rect2(-sz.x * 0.5, -sz.z * 0.5 - 1.6, sz.x, 1.6), y0, 4 | 1 | 2)
	# The inlet duct: down from the box's east end to the turbine's front.
	g.box(Transform3D(Basis(), o + Vector3(sz.x * 0.5 + 1.8, y0 * 0.62, 0)), Vector3(3.6, y0 * 0.9, 5.2), K_STEEL, Color(0.74, 0.75, 0.74), 1.0, 0)


## The gas turbine's enclosure: a box with roof vents and doors, the exhaust transition (+x) that
## widens into the HRSG.
static func gas_turbine(g: Geo, o: Vector3, sz: Vector3) -> void:
	g.box(Transform3D(Basis(), o + Vector3(0, 0.3, 0)), Vector3(sz.x + 2.0, 0.6, sz.z + 2.0), K_CONCRETE, CONCRETE)
	g.box(Transform3D(Basis(), o + Vector3(0, 0.6 + sz.y * 0.5, 0)), sz, K_CLAD, GT_GREEN, 5.0)
	for i in 3:
		var x := lerpf(-sz.x * 0.3, sz.x * 0.3, float(i) / 2.0)
		g.box(Transform3D(Basis(), o + Vector3(x, 0.6 + sz.y + 1.0, 0)), Vector3(2.4, 2.0, 2.4), K_LOUVRE, GT_GREEN * 0.92, 0.0, 0)
		g.box(Transform3D(Basis(), o + Vector3(x, 0.6 + sz.y + 2.1, 0)), Vector3(2.8, 0.2, 2.8), K_STEEL, GT_GREEN * 0.8)
	for sz_: float in [-1.0, 1.0]:
		for i in 3:
			g.box(Transform3D(Basis(), o + Vector3(-sz.x * 0.35 + float(i) * sz.x * 0.3, 1.7, sz_ * (sz.z * 0.5 + 0.04))), Vector3(1.1, 2.2, 0.08), K_DOOR, GT_GREEN * 0.85)
	# The exhaust transition: a tapered box from the enclosure's height to the HRSG's.
	var x0 := sz.x * 0.5
	var a := o + Vector3(x0, 0.6, 0)
	var hw0 := sz.z * 0.4
	var h0 := sz.y * 0.9
	var hw1 := 6.4
	var h1 := 24.0
	var l := 5.5
	var q := [a + Vector3(0, 0.0, -hw0), a + Vector3(0, 0.0, hw0), a + Vector3(0, h0, hw0), a + Vector3(0, h0, -hw0)]
	var r := [a + Vector3(l, 0.0, -hw1), a + Vector3(l, 0.0, hw1), a + Vector3(l, h1, hw1), a + Vector3(l, h1, -hw1)]
	var col := Color(0.6, 0.6, 0.58)
	for k in 4:
		var k1 := (k + 1) % 4
		var mid := ((q[k] as Vector3) + (q[k1] as Vector3) + (r[k] as Vector3) + (r[k1] as Vector3)) * 0.25
		var out := mid - (a + Vector3(l * 0.5, h1 * 0.4, 0))
		g.quad(q[k], q[k1], r[k1], r[k], out, K_STEEL, col, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO)


## A heat-recovery steam generator: the tall casing with its stiffeners, the steam drums on top,
## risers, a stair tower at the west end with landings, the casing roof.
static func hrsg(g: Geo, o: Vector3, sz: Vector3) -> void:
	g.box(Transform3D(Basis(), o + Vector3(0, 0.3, 0)), Vector3(sz.x + 2.0, 0.6, sz.z + 2.0), K_CONCRETE, CONCRETE)
	var c := o + Vector3(0, 0.6 + sz.y * 0.5, 0)
	g.box(Transform3D(Basis(), c), sz, K_STEEL, HRSG_GREY, 11.0)
	if g.full:
		var n := int(sz.x / 2.2)
		for i in n + 1:
			var x := -sz.x * 0.5 + sz.x * float(i) / float(n)
			for sz_: float in [-1.0, 1.0]:
				g.box(Transform3D(Basis(), o + Vector3(x, 0.6 + sz.y * 0.5, sz_ * (sz.z * 0.5 + 0.12))), Vector3(0.22, sz.y, 0.24), K_STEEL, HRSG_GREY * 0.86, 0.0, 16 | 32)
		for y in [6.0, 12.0, 18.0, 24.0]:
			for sz_: float in [-1.0, 1.0]:
				g.box(Transform3D(Basis(), o + Vector3(0, y, sz_ * (sz.z * 0.5 + 0.14))), Vector3(sz.x, 0.3, 0.28), K_STEEL, HRSG_GREY * 0.86, 0.0, 0)
	# Drums: three horizontal cylinders across the top on saddles.
	for i in 3:
		var x := lerpf(-sz.x * 0.3, sz.x * 0.25, float(i) / 2.0)
		var y := 0.6 + sz.y + 2.0
		g.cyl(o + Vector3(x, y, -sz.z * 0.42), o + Vector3(x, y, sz.z * 0.42), 1.1 - float(i) * 0.15, 1.1 - float(i) * 0.15, 14, K_JACKET, Color(0.74, 0.75, 0.75), true, true)
		for sz_: float in [-0.25, 0.25]:
			g.box(Transform3D(Basis(), o + Vector3(x, 0.6 + sz.y + 0.5, sz_ * sz.z)), Vector3(1.6, 1.0, 0.4), K_STEEL, STEEL_GREY)
		if g.full:
			g.cyl(o + Vector3(x + 0.6, y, 0), o + Vector3(x + 0.6, y + 4.0, 0), 0.25, 0.25, 8, K_JACKET, Color(0.74, 0.75, 0.75))
	g.box(Transform3D(Basis(), o + Vector3(0, 0.6 + sz.y + 0.12, 0)), Vector3(sz.x + 0.4, 0.24, sz.z + 0.4), K_ROOF, Color(0.5, 0.5, 0.49))
	g.platform(Transform3D(Basis(), o), Rect2(-sz.x * 0.5, -sz.z * 0.5, sz.x, sz.z), 0.6 + sz.y + 0.24, 1 | 2 | 4 | 8)
	stair_tower(g, o + Vector3(-sz.x * 0.5 + 3.0, 0.0, sz.z * 0.5 + 3.4), sz.y + 1.0, 4.8, 5.2)
	# The duct from the HRSG's east end to its stack.
	g.box(Transform3D(Basis(), o + Vector3(sz.x * 0.5 + 1.6, 0.6 + sz.y * 0.7, 0)), Vector3(3.2, sz.y * 0.5, 5.4), K_STEEL, HRSG_GREY * 0.95, 4.0, 0)


## A step-up transformer (main tank, radiator banks, conservator, three bushings and their sheds)
## on its oil-containment curb, a concrete fire wall on one side.
static func transformer(g: Geo, o: Vector3, ax: Vector3, wall: bool) -> void:
	var bx := Vector3.UP.cross(ax).normalized()
	var col := XFMR
	g.box(Transform3D(Basis(ax, Vector3.UP, bx), o + Vector3(0, 0.25, 0)), Vector3(11.0, 0.5, 9.0), K_CONCRETE, CONCRETE)
	g.box(Transform3D(Basis(ax, Vector3.UP, bx), o + Vector3(0, 2.9, 0)), Vector3(5.2, 4.8, 3.2), K_STEEL, col)
	for sg: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(ax, Vector3.UP, bx), o + bx * sg * 2.6 + Vector3(0, 2.6, 0)), Vector3(4.8, 3.6, 1.6), K_FINS, col * 0.92)
	g.cyl(o + ax * -2.4 + Vector3(0, 6.4, 0) + bx * 1.0, o + ax * 1.2 + Vector3(0, 6.4, 0) + bx * 1.0, 0.55, 0.55, 12, K_STEEL, col, true, true)
	g.beam(o + ax * -0.8 + bx * 1.0 + Vector3(0, 5.3, 0), o + ax * -0.8 + bx * 1.0 + Vector3(0, 6.0, 0), 0.18, 0.18, K_STEEL, col)
	for k in 3:
		var b := o + ax * (float(k) - 1.0) * 1.5 + Vector3(0, 5.3, 0) - bx * 0.6
		g.cyl(b, b + Vector3(0, 2.4, 0), 0.17, 0.09, 8, K_PORCELAIN, Color(0.55, 0.32, 0.22))
		if g.full:
			for j in 7:
				var yy := 0.3 + float(j) * 0.28
				g.cyl(b + Vector3(0, yy, 0), b + Vector3(0, yy + 0.06, 0), 0.27, 0.27, 8, K_PORCELAIN, Color(0.55, 0.32, 0.22), true, true)
	if wall:
		g.box(Transform3D(Basis(ax, Vector3.UP, bx), o - ax * 5.8 + Vector3(0, 4.0, 0)), Vector3(0.45, 8.0, 10.0), K_CONCRETE, CONCRETE, 2.0, 0)
	if g.full:
		g.box(Transform3D(Basis(ax, Vector3.UP, bx), o + ax * 3.4 + Vector3(0, 1.2, 0)), Vector3(0.8, 1.6, 1.2), K_STEEL, col * 0.9)


## A pipe bridge: two columns, a truss, three insulated pipes across.
static func pipe_bridge(g: Geo, o: Vector3, sz: Vector3) -> void:
	var y := sz.y
	for sx: float in [-0.5, 0.5]:
		var p := o + Vector3(sx * sz.x, 0.0, 0.0)
		g.beam(p, p + Vector3(0, y, 0), 0.4, 0.4, K_STEEL, STEEL_GREY)
	g.beam(o + Vector3(-sz.x * 0.5, y, 0), o + Vector3(sz.x * 0.5, y, 0), 0.5, 0.7, K_STEEL, STEEL_GREY)
	for k in 3:
		var z := (float(k) - 1.0) * 0.9
		g.cyl(o + Vector3(-sz.x * 0.5 - 8.0, y + 0.8, z), o + Vector3(sz.x * 0.5 + 2.0, y + 0.8, z), 0.38 - float(k) * 0.06, 0.38 - float(k) * 0.06, 10, K_JACKET, Color(0.76, 0.77, 0.77), false, false)


## A pipe rack along z: column pairs every 6 m, two tiers of beams, a bundle of pipes.
static func pipe_rack(g: Geo, o: Vector3, sz: Vector3) -> void:
	var n := int(sz.z / 6.0)
	var hw := sz.x * 0.5
	for i in n + 1:
		var z := -sz.z * 0.5 + sz.z * float(i) / float(n)
		for sx: float in [-1.0, 1.0]:
			g.beam(o + Vector3(sx * hw, 0, z), o + Vector3(sx * hw, sz.y, z), 0.3, 0.3, K_STEEL, STEEL_GREY)
		for y: float in [sz.y * 0.62, sz.y]:
			g.beam(o + Vector3(-hw, y, z), o + Vector3(hw, y, z), 0.25, 0.35, K_STEEL, STEEL_GREY)
	for y: float in [sz.y * 0.62, sz.y]:
		g.beam(o + Vector3(-hw, y, -sz.z * 0.5), o + Vector3(-hw, y, sz.z * 0.5), 0.2, 0.3, K_STEEL, STEEL_GREY)
		g.beam(o + Vector3(hw, y, -sz.z * 0.5), o + Vector3(hw, y, sz.z * 0.5), 0.2, 0.3, K_STEEL, STEEL_GREY)
	var pipes := [[-1.5, 0.35, K_JACKET, Color(0.76, 0.77, 0.77)], [-0.6, 0.28, K_JACKET, Color(0.76, 0.77, 0.77)], [0.4, 0.22, K_STEEL, PIPE_BLUE], [1.3, 0.3, K_STEEL, Color(0.3, 0.5, 0.34)]]
	for tier: float in [sz.y * 0.62, sz.y]:
		for pp: Array in pipes:
			var x: float = pp[0]
			var r: float = pp[1]
			g.cyl(o + Vector3(x, tier + 0.18 + r, -sz.z * 0.5), o + Vector3(x, tier + 0.18 + r, sz.z * 0.5), r, r, 10 if g.full else 6, int(pp[2]), pp[3], false, false)


## The cooling water pump house: a concrete building, louvres, its big blue pipes east and north.
static func pump_house(g: Geo, o: Vector3, sz: Vector3) -> void:
	g.box(Transform3D(Basis(), o + Vector3(0, sz.y * 0.5, 0)), sz, K_CONCRETE, Color(0.8, 0.78, 0.73), 3.0)
	g.box(Transform3D(Basis(), o + Vector3(0, sz.y + 0.35, 0)), Vector3(sz.x + 0.6, 0.7, sz.z + 0.6), K_ROOF, Color(0.55, 0.55, 0.53))
	for sz_: float in [-1.0, 1.0]:
		for i in 3:
			g.box(Transform3D(Basis(), o + Vector3(-sz.x * 0.3 + float(i) * sz.x * 0.3, sz.y * 0.65, sz_ * (sz.z * 0.5 + 0.05))), Vector3(3.0, 2.4, 0.1), K_LOUVRE, Color(0.62, 0.62, 0.6))
	g.box(Transform3D(Basis(), o + Vector3(sz.x * 0.5 + 0.05, 2.5, 0)), Vector3(0.1, 5.0, 5.0), K_DOOR, Color(0.6, 0.62, 0.62))
	# Two circulating water pipes, 2.4 m across, east along the ground then north into the hall.
	for k in 2:
		var dz := (float(k) - 0.5) * 6.0
		var a := o + Vector3(sz.x * 0.5, 1.6, dz)
		var b := a + Vector3(10.0 + float(k) * 6.0, 0, 0)
		var cc := Vector3(b.x, 1.6, o.z - sz.z * 0.5 - 6.0)
		g.cyl(a, b, 1.2, 1.2, 14 if g.full else 8, K_STEEL, PIPE_BLUE, false, false)
		g.cyl(b + Vector3(0, 0, 1.2 * signf(dz) * 0.0), cc, 1.2, 1.2, 14 if g.full else 8, K_STEEL, PIPE_BLUE, false, false)
		g.cyl(b + Vector3(-1.2, 0, 0), b + Vector3(1.2, 0, 0), 1.35, 1.35, 14 if g.full else 8, K_STEEL, PIPE_BLUE * 0.9, true, true)
		if g.full:
			for t in 4:
				var p := a.lerp(b, (float(t) + 0.5) / 4.0)
				g.box(Transform3D(Basis(), Vector3(p.x, 0.25, p.z)), Vector3(0.6, 0.5, 3.0), K_CONCRETE, CONCRETE)


## A tank: shell with courses, a cone roof, the wind girder, a stair up the side, the top rail.
static func tank(g: Geo, o: Vector3, r: float, h: float, paint: Color, fuel: bool) -> void:
	var segs := 28 if g.full else 14
	g.cyl(o + Vector3(0, -0.2, 0), o + Vector3(0, 0.4, 0), r + 0.8, r + 0.8, segs, K_CONCRETE, CONCRETE)
	g.cyl(o + Vector3(0, 0.4, 0), o + Vector3(0, h, 0), r, r, segs, K_TANK, paint, false, false)
	var rh := r * 0.12
	var top := o + Vector3(0, h, 0)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var nm := ((d0 + d1).normalized() * rh + Vector3(0, r, 0)).normalized()
		g.tri(top + d0 * r, top + d1 * r, top + Vector3(0, rh, 0), nm, K_TANK, paint * 0.96, Vector2(d0.x, d0.z) * r, Vector2(d1.x, d1.z) * r, Vector2.ZERO, Vector2(h, 1.0))
	g.cyl(o + Vector3(0, h - 1.4, 0), o + Vector3(0, h - 1.1, 0), r + 0.5, r + 0.5, segs, K_STEEL, paint * 0.9, false, false)
	if g.full:
		var n := 24
		for i in n:
			var a0 := TAU * float(i) / float(n)
			var a1 := TAU * float(i + 1) / float(n)
			g.rail(top + Vector3(cos(a0), 0, sin(a0)) * (r - 0.3) + Vector3(0, rh * 0.1, 0), top + Vector3(cos(a1), 0, sin(a1)) * (r - 0.3) + Vector3(0, rh * 0.1, 0), 1.0, Color(0.7, 0.7, 0.68))
		# The stair: a helical flight up a quarter of the shell.
		var steps := 10
		for i in steps:
			var t0 := float(i) / float(steps)
			var t1 := float(i + 1) / float(steps)
			var a0 := PI * 0.1 + t0 * PI * 0.55
			var a1 := PI * 0.1 + t1 * PI * 0.55
			var p0 := o + Vector3(cos(a0) * (r + 0.6), 0.4 + t0 * (h - 0.4), sin(a0) * (r + 0.6))
			var p1 := o + Vector3(cos(a1) * (r + 0.6), 0.4 + t1 * (h - 0.4), sin(a1) * (r + 0.6))
			g.beam(p0, p1, 0.9, 0.12, K_GRATING, STEEL_GREY)
			g.rail(p0 + Vector3(cos(a0), 0, sin(a0)) * 0.45, p1 + Vector3(cos(a1), 0, sin(a1)) * 0.45, 1.0, Color(0.7, 0.7, 0.68))
		if fuel:
			# The foam pipe and a vent on the roof, the fuel line out at the foot.
			g.cyl(o + Vector3(r + 0.4, 0.4, 0), o + Vector3(r + 0.4, h + 0.4, 0), 0.12, 0.12, 6, K_STEEL, Color(0.75, 0.2, 0.16))
			g.cyl(top + Vector3(0, rh, 0), top + Vector3(0, rh + 1.2, 0), 0.3, 0.3, 8, K_STEEL, paint * 0.8)
			g.cyl(o + Vector3(-r - 0.2, 0.9, 0), o + Vector3(-r - 6.0, 0.9, 0), 0.3, 0.3, 8, K_STEEL, Color(0.3, 0.3, 0.3), false, false)


## The fuel berm: a low concrete wall round the tank yard, stairs over it.
static func berm(g: Geo, o: Vector3, sz: Vector3) -> void:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var y := sz.y * 0.5
	g.box(Transform3D(Basis(), o + Vector3(0, y, -hd)), Vector3(sz.x + 0.4, sz.y, 0.4), K_CONCRETE, CONCRETE, 1.0)
	g.box(Transform3D(Basis(), o + Vector3(0, y, hd)), Vector3(sz.x + 0.4, sz.y, 0.4), K_CONCRETE, CONCRETE, 1.0)
	g.box(Transform3D(Basis(), o + Vector3(-hw, y, 0)), Vector3(0.4, sz.y, sz.z), K_CONCRETE, CONCRETE, 1.0)
	g.box(Transform3D(Basis(), o + Vector3(hw, y, 0)), Vector3(0.4, sz.y, sz.z), K_CONCRETE, CONCRETE, 1.0)
	if g.full:
		for sz_: float in [-0.3, 0.3]:
			var p := o + Vector3(-hw, 0, sz_ * sz.z)
			g.beam(p + Vector3(-2.0, 0, 0), p + Vector3(0, sz.y + 0.2, 0), 1.0, 0.12, K_GRATING, STEEL_GREY)
			g.beam(p + Vector3(2.0, 0, 0), p + Vector3(0, sz.y + 0.2, 0), 1.0, 0.12, K_GRATING, STEEL_GREY)


## The switchyard: lattice dead-end gantries on the north, two rows of strain gantries across the
## yard, the bays of breakers, disconnects and current transformers between, two transformers,
## lightning masts, the control house. `sz`: the yard's size (x, -, z), `o` its centre.
static func switchyard(g: Geo, o: Vector3, sz: Vector3, sd: int) -> void:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	# Strain gantries: two rows across the yard (each a Ridges gantry, the dead-end one's twin).
	for row: float in [-hd + 44.0, -hd + 82.0]:
		var gxf := Transform3D(Basis(), o + Vector3(0, 0, row))
		for m: Array in RidgeKit.gantry_members(not g.full):
			g.angle(gxf * (m[0] as Vector3), gxf * (m[1] as Vector3), float(m[2]), gxf.basis * (m[3] as Vector3), gxf.basis * (m[4] as Vector3), m[5])
		for cx: float in [-Ridges.GANTRY_HALF, 0.0, Ridges.GANTRY_HALF]:
			g.box(gxf * Transform3D(Basis(), Vector3(cx, 0.1, 0)), Vector3(1.8, 0.8, 1.8), K_CONCRETE, CONCRETE)
	# Bays: three columns (one per phase) of breaker, disconnects and CTs, in four bays N-S.
	for bay in 4:
		var bx := lerpf(-hw + 12.0, hw - 12.0, float(bay) / 3.0)
		for z: float in [-hd + 28.0, -hd + 62.0, -hd + 98.0]:
			_bay(g, o + Vector3(bx, 0, z))
	# Two transformers at the south end, lightning masts at the corners, the control house.
	for sx: float in [-0.28, 0.28]:
		transformer(g, o + Vector3(sx * sz.x, 0, hd - 9.0), Vector3(1, 0, 0), false)
	for c in 4:
		var s: Vector2 = RidgeKit.CORNER_SIGNS[c]
		var p := o + Vector3(s.x * (hw - 2.0), 0, s.y * (hd - 2.0))
		g.cyl(p, p + Vector3(0, 24.0, 0), 0.32, 0.08, 8, K_GALV, Color(0.6, 0.62, 0.62))
	var house := o + Vector3(hw - 9.0, 0, hd - 22.0)
	g.box(Transform3D(Basis(), house + Vector3(0, 2.3, 0)), Vector3(12.0, 4.6, 8.0), K_CONCRETE, Color(0.8, 0.76, 0.68), 4.0)
	g.box(Transform3D(Basis(), house + Vector3(0, 4.8, 0)), Vector3(12.6, 0.4, 8.6), K_ROOF, Color(0.52, 0.52, 0.5))
	g.box(Transform3D(Basis(), house + Vector3(-6.03, 1.1, 1.5)), Vector3(0.08, 2.2, 1.0), K_STEEL, Color(0.38, 0.4, 0.42))
	g.box(Transform3D(Basis(), house + Vector3(-6.03, 3.0, -1.8)), Vector3(0.08, 1.0, 2.4), K_GLASS, Color(0.3, 0.34, 0.36), 9.0)


## One switchyard bay: a dead-tank breaker for each phase, disconnect switches on porcelain posts
## either side, a current transformer, the bus supports.
static func _bay(g: Geo, p: Vector3) -> void:
	for k in 3:
		var c := p + Vector3((float(k) - 1.0) * 3.0, 0, 0)
		# Breaker: a horizontal tank on a frame, two bushings.
		g.box(Transform3D(Basis(), c + Vector3(0, 0.9, 0)), Vector3(0.9, 1.8, 2.0), K_STEEL, Color(0.62, 0.64, 0.64), 0.0, 0)
		g.cyl(c + Vector3(0, 2.2, -1.1), c + Vector3(0, 2.2, 1.1), 0.42, 0.42, 10, K_STEEL, Color(0.7, 0.72, 0.72), true, true)
		for sg: float in [-1.0, 1.0]:
			var b := c + Vector3(0, 2.5, sg * 0.7)
			g.cyl(b, b + Vector3(0, 2.0, sg * 0.4), 0.13, 0.08, 8, K_PORCELAIN, Color(0.55, 0.32, 0.22))
		# Disconnects: a steel stand, two porcelain posts, the blade.
		for sg: float in [-1.0, 1.0]:
			var d := c + Vector3(0, 0, sg * 7.0)
			g.beam(d, d + Vector3(0, 3.0, 0), 0.25, 0.25, K_GALV, Color(0.6, 0.62, 0.62))
			if g.full:
				for j in 2:
					var q := d + Vector3(0, 3.0, (float(j) - 0.5) * 1.6)
					g.cyl(q, q + Vector3(0, 1.8, 0), 0.12, 0.1, 8, K_PORCELAIN, Color(0.55, 0.32, 0.22))
				g.beam(d + Vector3(0, 4.85, -0.8), d + Vector3(0, 4.85, 0.8), 0.06, 0.08, K_GALV, Color(0.72, 0.73, 0.73))
		# Bus support: a taller post with the tubular bus on it.
		var s := c + Vector3(0, 0, -12.0)
		g.beam(s, s + Vector3(0, 5.0, 0), 0.3, 0.3, K_GALV, Color(0.6, 0.62, 0.62))
		g.cyl(s + Vector3(0, 5.0, 0), s + Vector3(0, 6.8, 0), 0.13, 0.1, 8, K_PORCELAIN, Color(0.55, 0.32, 0.22))
	# The tubular bus along the bay's three phases.
	for k in 3:
		var x := (float(k) - 1.0) * 3.0
		g.cyl(p + Vector3(x, 6.9, -12.0), p + Vector3(x, 6.9, 9.0), 0.06, 0.06, 6, K_GALV, Color(0.78, 0.79, 0.79), false, false)


## The offices: two storeys of concrete and ribbon glass, a flat roof with plant, an entrance
## canopy, the company's name on the parapet facing the gate.
static func admin(g: Geo, o: Vector3, sz: Vector3) -> void:
	g.box(Transform3D(Basis(), o + Vector3(0, sz.y * 0.5, 0)), sz, K_CONCRETE, Color(0.86, 0.84, 0.8), 6.0)
	for y: float in [1.2, 4.6]:
		for sx: float in [-1.0, 1.0]:
			g.box(Transform3D(Basis(), o + Vector3(sx * (sz.x * 0.5 + 0.04), y + 1.0, 0)), Vector3(0.08, 2.0, sz.z - 3.0), K_GLASS, Color(0.24, 0.3, 0.34), 21.0)
		for sz_: float in [-1.0, 1.0]:
			g.box(Transform3D(Basis(), o + Vector3(0, y + 1.0, sz_ * (sz.z * 0.5 + 0.04))), Vector3(sz.x - 3.0, 2.0, 0.08), K_GLASS, Color(0.24, 0.3, 0.34), 22.0)
	g.box(Transform3D(Basis(), o + Vector3(0, sz.y + 0.5, 0)), Vector3(sz.x + 0.3, 1.0, sz.z + 0.3), K_CONCRETE, Color(0.8, 0.78, 0.74), 0.0, 16)
	g.box(Transform3D(Basis(), o + Vector3(0, sz.y + 0.2, 0)), Vector3(sz.x, 0.4, sz.z), K_ROOF, Color(0.6, 0.6, 0.58))
	for i in 3:
		g.box(Transform3D(Basis(), o + Vector3(-sz.x * 0.3 + float(i) * sz.x * 0.3, sz.y + 1.2, 0)), Vector3(2.6, 1.6, 2.0), K_STEEL, Color(0.78, 0.79, 0.78), 0.0, 0)
	# Canopy over the door on the east face.
	g.box(Transform3D(Basis(), o + Vector3(sz.x * 0.5 + 2.0, 3.4, 0)), Vector3(4.0, 0.3, 7.0), K_STEEL, Color(0.3, 0.32, 0.34), 0.0, 0)
	for sz_: float in [-1.0, 1.0]:
		g.cyl(o + Vector3(sz.x * 0.5 + 3.7, 0, sz_ * 3.2), o + Vector3(sz.x * 0.5 + 3.7, 3.3, sz_ * 3.2), 0.12, 0.12, 8, K_STEEL, Color(0.3, 0.32, 0.34))
	g.box(Transform3D(Basis(), o + Vector3(sz.x * 0.5 + 0.05, 1.25, 0)), Vector3(0.1, 2.5, 3.0), K_GLASS, Color(0.2, 0.24, 0.26), 23.0)
	# The name on a board on the east parapet.
	var board_c := o + Vector3(sz.x * 0.5 + 0.12, sz.y + 0.5, 0)
	g.box(Transform3D(Basis(), board_c), Vector3(0.1, 1.2, sz.z - 2.0), K_SIGN, Color(0.12, 0.22, 0.38))
	if g.full:
		letters(g, PowerPlant.COMPANY, 0.62, Transform3D(Basis(Vector3.UP, PI * 0.5), board_c + Vector3(0.08, 0.0, 0)), Color(0.95, 0.95, 0.92), sz.z - 3.0)


## The guard booth by the gate, its barrier arm.
static func guard(g: Geo, o: Vector3, sz: Vector3) -> void:
	g.box(Transform3D(Basis(), o + Vector3(0, 0.5, 0)), Vector3(sz.x, 1.0, sz.z), K_CONCRETE, Color(0.84, 0.82, 0.78))
	g.box(Transform3D(Basis(), o + Vector3(0, 1.0 + 1.0, 0)), Vector3(sz.x - 0.2, 2.0, sz.z - 0.2), K_GLASS, Color(0.3, 0.36, 0.38), 31.0)
	g.box(Transform3D(Basis(), o + Vector3(0, 3.15, 0)), Vector3(sz.x + 0.6, 0.3, sz.z + 0.6), K_STEEL, Color(0.82, 0.82, 0.8))
	g.box(Transform3D(Basis(), o + Vector3(sz.x * 0.5 + 0.3, 0.55, -1.0)), Vector3(0.4, 1.1, 0.4), K_STEEL, YELLOW)
	g.beam(o + Vector3(sz.x * 0.5 + 0.3, 1.0, -1.0), o + Vector3(sz.x * 0.5 + 0.3, 1.0, -7.0), 0.1, 0.1, K_STEEL, Color(0.9, 0.2, 0.15))


## Lettering (FreewayKit's TextMesh outlines) laid flat on the plane of `xf` (its +z out).
static func letters(g: Geo, text: String, height: float, xf: Transform3D, col: Color, max_w: float) -> void:
	var geo := FreewayKit.text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var width: float = geo[2]
	var sq := minf(1.0, max_w / maxf(width, 0.001))
	var out := xf.basis.z.normalized()
	for k in range(0, idx.size() - 2, 3):
		var p: Array[Vector3] = []
		for j in 3:
			var vv := verts[idx[k + j]]
			p.append(xf * Vector3(vv.x * sq, vv.y, 0.02))
		g.tri(p[0], p[1], p[2], out, K_LETTER, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


## A flood mast: a tapering pole, the head frame, four flood lights aimed down and in.
static func flood_mast(g: Geo, o: Vector3, h: float) -> void:
	g.cyl(o + Vector3(0, -0.2, 0), o + Vector3(0, 0.6, 0), 0.6, 0.55, 8, K_CONCRETE, CONCRETE)
	g.cyl(o + Vector3(0, 0.6, 0), o + Vector3(0, h, 0), 0.26, 0.14, 8 if g.full else 5, K_GALV, Color(0.62, 0.64, 0.64))
	g.box(Transform3D(Basis(), o + Vector3(0, h, 0)), Vector3(2.4, 0.15, 0.6), K_GALV, Color(0.62, 0.64, 0.64), 0.0, 0)
	for k in 4:
		var x := (float(k) - 1.5) * 0.6
		g.box(Transform3D(Basis(Vector3.RIGHT, 0.55), o + Vector3(x, h + 0.25, 0.1)), Vector3(0.48, 0.38, 0.12), K_STEEL, STEEL_DARK)
		g.box(Transform3D(Basis(Vector3.RIGHT, 0.55), o + Vector3(x, h + 0.22, 0.17)), Vector3(0.4, 0.3, 0.02), K_LAMP, Color(1.0, 0.92, 0.8))


## A run of the security fence from `a` to `b` (world XZ, heights at `y0` / `y1`): chain-link on
## posts every 3 m, a top rail, barbed wire on outriggers.
static func fence(g: Geo, a: Vector3, b: Vector3) -> void:
	var l := Vector2(b.x - a.x, b.z - a.z).length()
	if l < 0.5:
		return
	var d := (b - a) / l
	var out := Vector3(d.z, 0, -d.x)
	var h := 2.4
	var n := maxi(1, int(ceil(l / 3.0)))
	for i in n:
		var p0 := a.lerp(b, float(i) / float(n))
		var p1 := a.lerp(b, float(i + 1) / float(n))
		var s := p0.distance_to(p1)
		g.quad(p0, p1, p1 + Vector3(0, h, 0), p0 + Vector3(0, h, 0), out, K_CHAIN, Color(0.7, 0.71, 0.72), Vector2(0, 0), Vector2(s, 0), Vector2(s, h), Vector2(0, h), Vector2(h, 0.0))
		g.beam(p0, p0 + Vector3(0, h + 0.5, 0), 0.07, 0.07, K_GALV, Color(0.64, 0.65, 0.66))
		if g.full:
			g.beam(p0 + Vector3(0, h + 0.45, 0), p0 + Vector3(0, h + 0.45, 0) + out * 0.45 + Vector3(0, 0.3, 0), 0.04, 0.04, K_GALV, Color(0.6, 0.6, 0.6))
	g.beam(a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.05, 0.05, K_GALV, Color(0.68, 0.69, 0.7))
	if g.full:
		for k in 3:
			var off := out * (0.15 * float(k + 1)) + Vector3(0, h + 0.55 + 0.1 * float(k), 0)
			g.beam(a + off, b + off, 0.02, 0.02, K_GALV, Color(0.55, 0.55, 0.55))


# =================================================================================================
# The seawall and the intake on the sand
# =================================================================================================

## A run of seawall along z at `x` (world), from `z0` to `z1`, its foot at `y_sand`, top at
## `y_top`: a stepped concrete face toward the sea (-x), a cap, rip-rap at its toe.
static func seawall(g: Geo, x: float, z0: float, z1: float, y_sand: float, y_top: float, seed_value: int) -> void:
	var h := y_top - y_sand
	var l := z1 - z0
	var zc := (z0 + z1) * 0.5
	g.box(Transform3D(Basis(), Vector3(x + 0.6, y_sand + h * 0.5 - 0.4, zc)), Vector3(1.4, h + 0.8, l), K_CONCRETE, Color(0.72, 0.7, 0.66), 5.0, 1)
	g.box(Transform3D(Basis(), Vector3(x - 0.55, y_sand + h * 0.3 - 0.3, zc)), Vector3(1.0, h * 0.6 + 0.6, l), K_CONCRETE, Color(0.7, 0.68, 0.64), 5.0, 1)
	g.box(Transform3D(Basis(), Vector3(x + 0.5, y_top + 0.2, zc)), Vector3(1.9, 0.4, l + 0.2), K_CONCRETE, Color(0.8, 0.78, 0.74), 1.0)
	# Rip-rap: boulders at the toe on the sea side, hashed along z.
	var n := int(l / 1.6)
	for i in n:
		var z := z0 + (float(i) + 0.5) * l / float(n)
		var hv := PowerPlant.h01([seed_value, "rip", i])
		var rr := 0.5 + hv * 0.7
		_rock(g, Vector3(x - 1.5 - hv * 1.6, y_sand + rr * 0.35, z + (hv - 0.5) * 0.8), rr, i + seed_value)
		if g.full and hv > 0.4:
			var h2 := PowerPlant.h01([seed_value, "rip2", i])
			_rock(g, Vector3(x - 3.0 - h2 * 1.2, y_sand + 0.2, z + 0.5), 0.4 + h2 * 0.4, i * 7 + seed_value)


## A boulder: an octahedron squashed and turned by a hash.
static func _rock(g: Geo, c: Vector3, r: float, sd: int) -> void:
	var b := Basis(Vector3.UP, float(sd % 37) * 0.31) * Basis(Vector3.RIGHT, float(sd % 11) * 0.2)
	var ax := [b.x * r * 1.1, b.y * r * 0.75, b.z * r * 0.95]
	var col := Color(0.52, 0.5, 0.47) * (0.85 + float(sd % 7) * 0.04)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz_: float in [-1.0, 1.0]:
				var a: Vector3 = c + ax[0] * sx
				var bb: Vector3 = c + ax[1] * sy
				var cc: Vector3 = c + ax[2] * sz_
				g.tri(a, bb, cc, (a + bb + cc) / 3.0 - c, K_ROCK, col, Vector2(a.x, a.z), Vector2(bb.x, bb.z), Vector2(cc.x, cc.z), Vector2.ZERO)


## The intake / outfall: a concrete headwall in the seawall at (x, z) facing the sea, its bar
## screens, and a pipe trestle `out` metres out to sea on pile bents (none within 3 m of the bike
## path at `path_x`, which runs under its deck), with a walkway, rails and a light at the end.
static func intake(g: Geo, x: float, z: float, y_sand: float, out: float, path_x: float) -> void:
	var c := Vector3(x - 3.0, y_sand, z)
	g.box(Transform3D(Basis(), c + Vector3(0, 2.6, 0)), Vector3(6.0, 5.2, 20.0), K_CONCRETE, Color(0.74, 0.72, 0.68), 6.0)
	g.box(Transform3D(Basis(), c + Vector3(0, 5.35, 0)), Vector3(6.4, 0.3, 20.4), K_CONCRETE, Color(0.8, 0.78, 0.74))
	for k in 4:
		g.box(Transform3D(Basis(), c + Vector3(-3.05, 1.8, -6.6 + float(k) * 4.4)), Vector3(0.1, 2.8, 3.4), K_LOUVRE, Color(0.4, 0.42, 0.42))
	g.platform(Transform3D(Basis(), c), Rect2(-3.0, -10.0, 6.0, 20.0), 5.5, 1 | 4 | 8)
	var y := y_sand + 5.2
	var x0 := x - 6.0
	var n := int(out / 6.0)
	for i in n + 1:
		var px := x0 - float(i) * 6.0
		if absf(px - path_x) < 3.0:
			continue
		for sz_: float in [-1.4, 1.4]:
			g.cyl(Vector3(px, y_sand - 3.0, z + sz_), Vector3(px, y, z + sz_), 0.3, 0.3, 8, K_CONCRETE, Color(0.62, 0.6, 0.56), false, false)
		g.beam(Vector3(px, y, z - 1.8), Vector3(px, y, z + 1.8), 0.5, 0.6, K_CONCRETE, Color(0.7, 0.68, 0.64))
	var x1 := x0 - float(n) * 6.0
	g.box(Transform3D(Basis(), Vector3((x0 + x1) * 0.5, y + 0.35, z)), Vector3(x0 - x1, 0.1, 2.0), K_GRATING, STEEL_GREY, 0.0, 0)
	g.beam(Vector3(x0, y, z - 1.0), Vector3(x1, y, z - 1.0), 0.3, 0.6, K_STEEL, STEEL_GREY)
	g.beam(Vector3(x0, y, z + 1.0), Vector3(x1, y, z + 1.0), 0.3, 0.6, K_STEEL, STEEL_GREY)
	g.rail(Vector3(x0, y + 0.4, z - 1.0), Vector3(x1, y + 0.4, z - 1.0))
	g.rail(Vector3(x0, y + 0.4, z + 1.0), Vector3(x1, y + 0.4, z + 1.0))
	for sz_: float in [-0.6, 0.6]:
		g.cyl(Vector3(x0, y + 0.95, z + sz_ * 2.2), Vector3(x1, y + 0.95, z + sz_ * 2.2), 0.45, 0.45, 10, K_STEEL, Color(0.3, 0.33, 0.36), false, false)
	# The riser cap at the end, a warning light.
	g.cyl(Vector3(x1 - 3.0, y_sand - 3.0, z), Vector3(x1 - 3.0, y + 0.8, z), 1.6, 1.6, 14, K_CONCRETE, Color(0.66, 0.64, 0.6))
	g.cyl(Vector3(x1 - 3.0, y + 0.8, z), Vector3(x1 - 3.0, y + 2.4, z), 0.12, 0.12, 6, K_STEEL, YELLOW)
	g.box(Transform3D(Basis(), Vector3(x1 - 3.0, y + 2.6, z)), Vector3(0.35, 0.35, 0.35), K_LAMP, Color(1.0, 0.8, 0.4))
