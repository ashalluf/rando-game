class_name MotelKit
extends RefCounted
## The Googie motel's geometry (Motels' plan, FULL chunks): one mesh on shaders/motel.gdshader
## (kind in COLOR.a / 16, paint in COLOR.rgb sRGB, UV metres, UV2 = light mode and room key: the
## shader's header), box collision on the chunk's static body, the guests' cars through LotFill's
## static cars (StreetCloseup swaps the near ones for real bodies), light pools under the walks, one
## warm OmniLight at the office on desktop.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

enum { K_STUCCO, K_TRIM, K_GLASS, K_CONCRETE, K_STEEL, K_LAMP, K_DOOR, K_NEON, K_OFFICE_GLASS, K_STONE, K_ROOF, K_AC }

## The room bay's openings (along the bay, from its start; m): the door, the window.
const DOOR := Vector2(0.55, 1.45)
const DOOR_H := 2.15
const WIN := Vector2(2.05, 3.65)
const SILL := 0.95
const HEAD := 2.15
const SCONCE_U := 1.75
const STEEL_C := Color(0.16, 0.17, 0.18)
const CONCRETE_C := Color(0.66, 0.64, 0.6)
const ROOF_C := Color(0.5, 0.49, 0.47)
const AC_C := Color(0.78, 0.75, 0.68)
const BRASS_C := Color(0.62, 0.48, 0.22)

static var _mat: ShaderMaterial = null


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/motel.gdshader")
	return _mat


## Packed arrays for one mesh (flat-shaded quads, LandmarkGeo's winding rule).
class Geo:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()

	func quad(p: Array, want: Vector3, uvs: Array, kind: int, c: Color, mode: float = 0.0, room: float = 0.0) -> void:
		var a: Vector3 = p[0]
		var b: Vector3 = p[1]
		var cc: Vector3 = p[2]
		var flat := (cc - a).cross(b - a)
		var order := [0, 1, 2, 0, 2, 3]
		if flat.dot(want) < 0.0:
			order = [0, 2, 1, 0, 3, 2]
		var colour := Color(c.r, c.g, c.b, (float(kind) + 0.25) / 16.0)
		var nn := want.normalized()
		for i: int in order:
			v.append(p[i])
			nrm.append(nn)
			uv.append(uvs[i])
			uv2.append(Vector2(mode, room))
			col.append(colour)

	func mesh(mat: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_COLOR] = col
		var m := ArrayMesh.new()
		if v.is_empty():
			return m
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, mat)
		return m


## A frame on the ground: point (a along, s out from the facade, y up) -> chunk space.
class Frame:
	var o: Vector2
	var al: Vector2
	var out: Vector2
	var y0: float

	func _init(o_: Vector2, al_: Vector2, out_: Vector2, y0_: float) -> void:
		o = o_
		al = al_
		out = out_
		y0 = y0_

	func p(a: float, s: float, y: float) -> Vector3:
		var q := o + al * a + out * s
		return Vector3(q.x, y0 + y, q.y)

	func A() -> Vector3:
		return Vector3(al.x, 0.0, al.y)

	func S() -> Vector3:
		return Vector3(out.x, 0.0, out.y)


## A box in frame `f`: a, s, y ranges. `fm` the mode of its +s face, `tm` its top's, `bm` its
## bottom's (a soffit), uv offset `ua` (the face's metres along the whole wing).
static func box(g: Geo, f: Frame, a0: float, a1: float, s0: float, s1: float, y0: float, y1: float,
		kind: int, c: Color, fm: float = 0.0, tm: float = 0.0, bm: float = -1.0, room: float = 0.0, faces: int = 63) -> void:
	var A := f.A()
	var S := f.S()
	# +s (front)
	if faces & 1:
		g.quad([f.p(a0, s1, y0), f.p(a1, s1, y0), f.p(a1, s1, y1), f.p(a0, s1, y1)], S,
			[Vector2(a0, y0), Vector2(a1, y0), Vector2(a1, y1), Vector2(a0, y1)], kind, c, fm, room)
	# -s (back)
	if faces & 2:
		g.quad([f.p(a0, s0, y0), f.p(a1, s0, y0), f.p(a1, s0, y1), f.p(a0, s0, y1)], -S,
			[Vector2(a0, y0), Vector2(a1, y0), Vector2(a1, y1), Vector2(a0, y1)], kind, c, 0.0, room)
	# +a, -a (ends)
	if faces & 4:
		g.quad([f.p(a1, s0, y0), f.p(a1, s1, y0), f.p(a1, s1, y1), f.p(a1, s0, y1)], A,
			[Vector2(s0, y0), Vector2(s1, y0), Vector2(s1, y1), Vector2(s0, y1)], kind, c, 0.0, room)
	if faces & 8:
		g.quad([f.p(a0, s0, y0), f.p(a0, s1, y0), f.p(a0, s1, y1), f.p(a0, s0, y1)], -A,
			[Vector2(s0, y0), Vector2(s1, y0), Vector2(s1, y1), Vector2(s0, y1)], kind, c, 0.0, room)
	# top, bottom
	if faces & 16:
		g.quad([f.p(a0, s0, y1), f.p(a1, s0, y1), f.p(a1, s1, y1), f.p(a0, s1, y1)], Vector3.UP,
			[Vector2(a0, s0), Vector2(a1, s0), Vector2(a1, s1), Vector2(a0, s1)], kind, c, tm, room)
	if faces & 32 and bm >= 0.0:
		g.quad([f.p(a0, s0, y0), f.p(a1, s0, y0), f.p(a1, s1, y0), f.p(a0, s1, y0)], Vector3.DOWN,
			[Vector2(a0, s0), Vector2(a1, s0), Vector2(a1, s1), Vector2(a0, s1)], kind, c, bm, room)


## A rectangle of the facade (s = 0) from (a0, y0) to (a1, y1).
static func wall(g: Geo, f: Frame, a0: float, a1: float, y0: float, y1: float, c: Color, mode: float) -> void:
	if a1 - a0 < 0.005 or y1 - y0 < 0.005:
		return
	g.quad([f.p(a0, 0.0, y0), f.p(a1, 0.0, y0), f.p(a1, 0.0, y1), f.p(a0, 0.0, y1)], f.S(),
		[Vector2(a0, y0), Vector2(a1, y0), Vector2(a1, y1), Vector2(a0, y1)], K_STUCCO, c, mode)


static func build(ch: CityChunk, L: Dictionary) -> void:
	var look: Array = Motels.LOOKS[int(L.look)]
	var stucco: Color = look[0]
	var trim: Color = look[1]
	var accent: Color = look[2]
	var neon: Color = look[3]
	var sd := int(L.seed)
	var cell: Rect2 = L.cell
	var cc := cell.get_center()
	var gy := ch._gy(cc.x, cc.y)
	var base := CityChunk.SIDEWALK_TOP + LotFill.ASPHALT_LIFT + gy
	var g := Geo.new()
	var cars: Array = []
	var pools: Array = []
	var fill := Motels.FILL_FULL if bool(L.full) else Motels.FILL
	for w: Dictionary in L.wings:
		_wing(ch, g, w, base, stucco, trim, accent, neon, sd, fill, cars, pools)
	_office(ch, g, L, base, stucco, trim, accent, neon)
	var mi := MeshInstance3D.new()
	mi.name = "Motel_%d" % (sd % 100000)
	mi.mesh = g.mesh(material())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 520.0
	ch.add_child(mi)
	# The guests' cars: LotFill's static cars (their y without the relief: the batch adds it).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ch.plan.seed, sd, "motel_cars"])
	for c: Array in cars:
		var at: Vector3 = c[0]
		LotFill._car(ch, rng, Vector3(at.x, at.y - gy, at.z), float(c[1]))
	# Light pools under the walks (the batch adds the relief).
	for q: Vector3 in pools:
		var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(4.6, 1.0, 4.6)), Vector3(q.x, q.y - gy + 0.06, q.z))
		ch._batch.add("motel_pool", PropFactory.light_pool(), pool)
	ch._batch.set_no_shadow("motel_pool")
	ch._batch.set_draw_distance("motel_pool", 260.0)


static func _wing(ch: CityChunk, g: Geo, w: Dictionary, base: float, stucco: Color, trim: Color, accent: Color,
		neon: Color, sd: int, fill: float, cars: Array, pools: Array) -> void:
	var f := Frame.new(w.o, w.al, w.out, base)
	var Lw := float(w.L)
	var D := float(w.D)
	var ns := int(w.storeys)
	var H := float(ns) * Motels.STOREY
	var top := H + Motels.PARAPET
	var WALK := Motels.WALK
	var rooms_L := float(w.rooms_L)
	var nb := int(floorf(rooms_L / Motels.ROOM_W))
	var a0 := (rooms_L - float(nb) * Motels.ROOM_W) * 0.5
	var stair := int(w.stair) == 1 and ns > 1
	var wk := int(w.key)
	# The body behind the facade: back, ends, roof (its facade is cut round the openings below).
	box(g, f, 0.0, Lw, -D, 0.0, -0.6, top, K_STUCCO, stucco, 0.0, 0.0, -1.0, 0.0, 2 | 4 | 8)
	box(g, f, 0.0, Lw, -D, 0.0, top - 0.02, top, K_ROOF, ROOF_C, 0.0, 0.0, -1.0, 0.0, 16)
	ch._add_shape(Vector3(Lw, top + 0.6, D) if absf(f.al.x) > 0.5 else Vector3(D, top + 0.6, Lw),
		f.p(Lw * 0.5, -D * 0.5, (top - 0.6) * 0.5))
	# The facade, storey by storey: the plain ends, and each room's bay round its door and window.
	for k in ns:
		var y0 := float(k) * Motels.STOREY
		var y1 := y0 + Motels.STOREY
		var mode := 1.0 + float(k)
		wall(g, f, 0.0, a0, y0, y1, stucco, mode)
		wall(g, f, a0 + float(nb) * Motels.ROOM_W, Lw, y0, y1, stucco, mode)
		for b in nb:
			var u := a0 + float(b) * Motels.ROOM_W
			var room := float(absi(hash([sd, wk, k, b])) % 9973) + 1.0
			wall(g, f, u, u + DOOR.x, y0, y0 + DOOR_H, stucco, mode)
			wall(g, f, u + DOOR.y, u + WIN.x, y0, y0 + DOOR_H, stucco, mode)
			wall(g, f, u + WIN.x, u + WIN.y, y0, y0 + SILL, stucco, mode)
			wall(g, f, u + WIN.y, u + Motels.ROOM_W, y0, y0 + DOOR_H, stucco, mode)
			wall(g, f, u, u + Motels.ROOM_W, y0 + DOOR_H, y1, stucco, mode)
			# The door, set in 8 cm, its jambs and head.
			var dr := -0.08
			g.quad([f.p(u + DOOR.x, dr, y0), f.p(u + DOOR.y, dr, y0), f.p(u + DOOR.y, dr, y0 + DOOR_H), f.p(u + DOOR.x, dr, y0 + DOOR_H)], f.S(),
				[Vector2(0.0, 0.0), Vector2(0.9, 0.0), Vector2(0.9, DOOR_H), Vector2(0.0, DOOR_H)], K_DOOR, trim, 0.0, room)
			box(g, f, u + DOOR.x - 0.06, u + DOOR.x, dr, 0.03, y0, y0 + DOOR_H + 0.06, K_TRIM, trim.lightened(0.5), 0.0, 0.0, -1.0, 0.0, 1 | 4 | 8)
			box(g, f, u + DOOR.y, u + DOOR.y + 0.06, dr, 0.03, y0, y0 + DOOR_H + 0.06, K_TRIM, trim.lightened(0.5), 0.0, 0.0, -1.0, 0.0, 1 | 4 | 8)
			box(g, f, u + DOOR.x - 0.06, u + DOOR.y + 0.06, dr, 0.03, y0 + DOOR_H, y0 + DOOR_H + 0.06, K_TRIM, trim.lightened(0.5), 0.0, 0.0, 0.0, 0.0, 1 | 4 | 8 | 16 | 32)
			# The number plaque over the door.
			box(g, f, u + 0.82, u + 1.18, 0.0, 0.02, y0 + DOOR_H + 0.12, y0 + DOOR_H + 0.3, K_TRIM, BRASS_C, 0.0, 0.0, -1.0, 0.0, 1 | 16)
			# The window: glass set 10 cm in, a frame, a sill, the reveals.
			var wr := -0.1
			g.quad([f.p(u + WIN.x, wr, y0 + SILL), f.p(u + WIN.y, wr, y0 + SILL), f.p(u + WIN.y, wr, y0 + HEAD), f.p(u + WIN.x, wr, y0 + HEAD)], f.S(),
				[Vector2(u + WIN.x, SILL), Vector2(u + WIN.y, SILL), Vector2(u + WIN.y, HEAD), Vector2(u + WIN.x, HEAD)], K_GLASS, Color.BLACK, 0.0, room)
			# Reveals.
			g.quad([f.p(u + WIN.x, wr, y0 + SILL), f.p(u + WIN.x, 0.0, y0 + SILL), f.p(u + WIN.x, 0.0, y0 + HEAD), f.p(u + WIN.x, wr, y0 + HEAD)], f.A(),
				[Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, 1.2), Vector2(0, 1.2)], K_STUCCO, stucco.darkened(0.12))
			g.quad([f.p(u + WIN.y, wr, y0 + SILL), f.p(u + WIN.y, 0.0, y0 + SILL), f.p(u + WIN.y, 0.0, y0 + HEAD), f.p(u + WIN.y, wr, y0 + HEAD)], -f.A(),
				[Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, 1.2), Vector2(0, 1.2)], K_STUCCO, stucco.darkened(0.12))
			g.quad([f.p(u + WIN.x, wr, y0 + HEAD), f.p(u + WIN.y, wr, y0 + HEAD), f.p(u + WIN.y, 0.0, y0 + HEAD), f.p(u + WIN.x, 0.0, y0 + HEAD)], Vector3.DOWN,
				[Vector2(0, 0), Vector2(1.6, 0), Vector2(1.6, 0.1), Vector2(0, 0.1)], K_STUCCO, stucco.darkened(0.25))
			# Mullion and frame.
			var mid := u + (WIN.x + WIN.y) * 0.5
			box(g, f, mid - 0.025, mid + 0.025, wr, wr + 0.04, y0 + SILL, y0 + HEAD, K_TRIM, Color(0.75, 0.75, 0.72), 0.0, 0.0, -1.0, 0.0, 1 | 4 | 8)
			box(g, f, u + WIN.x - 0.05, u + WIN.y + 0.05, -0.02, 0.05, y0 + SILL - 0.07, y0 + SILL, K_TRIM, trim.lightened(0.55), 0.0, 0.0, -1.0, 0.0, 1 | 4 | 8 | 16)
			# The AC sleeve under the window.
			var ac := u + WIN.x + 0.35
			box(g, f, ac, ac + 0.66, 0.0, 0.32, y0 + 0.42, y0 + 0.86, K_AC, AC_C, 0.0, 0.0, 0.0, 0.0)
			# The sconce by the door.
			var sa := u + SCONCE_U
			box(g, f, sa - 0.09, sa + 0.09, 0.0, 0.05, y0 + 1.95, y0 + 2.3, K_TRIM, Color(0.15, 0.15, 0.15), 0.0, 0.0, -1.0, 0.0, 1 | 4 | 8 | 16)
			box(g, f, sa - 0.07, sa + 0.07, 0.05, 0.16, y0 + 1.99, y0 + 2.22, K_LAMP, Color.WHITE, 0.0, 0.0, 0.0, 0.0, 1 | 4 | 8 | 32)
			# A pool of light on the walk in front of every other door, and the stall with its car.
			if k == 0:
				if b % 2 == 0:
					pools.append(f.p(sa, WALK * 0.7, 0.15))
				var stall_ok := not (stair and u < 6.8)
				if stall_ok:
					var cu := u + 1.0
					if Motels._h01([sd, wk, b, "car"]) < fill:
						var yaw_dir := -f.S()
						var yaw := atan2(-yaw_dir.x, -yaw_dir.z) + (Motels._h01([sd, wk, b, "yaw"]) - 0.5) * 0.08
						cars.append([f.p(cu, WALK + Motels.STALL_D * 0.5 + 0.1, 0.0) - Vector3(0.0, 0.0, 0.0), yaw])
					# The stall's stripes.
					for e: float in [u - 0.4, u + Motels.ROOM_W - 0.4]:
						box(g, f, e - 0.06, e + 0.06, WALK + 0.2, WALK + Motels.STALL_D, -0.04, 0.008, K_CONCRETE, Color(0.92, 0.92, 0.88), 0.0, 0.0, -1.0, 0.0, 16)
					# A wheel stop.
					box(g, f, cu - 0.8, cu + 0.8, WALK + 0.55, WALK + 0.75, 0.0, 0.12, K_CONCRETE, Color(0.85, 0.82, 0.7), 0.0, 0.0, -1.0, 0.0, 1 | 2 | 4 | 8 | 16)
	# The ground walk in front of the rooms (a kerb over the asphalt).
	box(g, f, 0.0, Lw, 0.0, WALK, -0.3, 0.15, K_CONCRETE, CONCRETE_C, 0.0, 10.0, -1.0, 0.0, 1 | 4 | 8 | 16)
	ch._add_shape(Vector3(Lw, 0.45, WALK) if absf(f.al.x) > 0.5 else Vector3(WALK, 0.45, Lw), f.p(Lw * 0.5, WALK * 0.5, -0.075))
	# The walks of the upper storeys: slabs on the posts, a soffit under each, a railing.
	for k in range(1, ns):
		var y := float(k) * Motels.STOREY
		box(g, f, 0.0, Lw, 0.0, WALK, y - 0.22, y, K_CONCRETE, CONCRETE_C, 0.0, 10.0 + float(k), 20.0 + float(k - 1), 0.0, 1 | 4 | 8 | 16 | 32)
		ch._add_shape(Vector3(Lw, 0.22, WALK) if absf(f.al.x) > 0.5 else Vector3(WALK, 0.22, Lw), f.p(Lw * 0.5, WALK * 0.5, y - 0.11))
		_railing(g, f, 0.0, Lw, WALK, y, trim, stair)
		for b in nb:
			if b % 2 == 0:
				pools.append(f.p(a0 + float(b) * Motels.ROOM_W + SCONCE_U, WALK * 0.7, y + 0.02))
	# The roof's overhang over the top walk, its fascia in the accent colour, a neon line under it.
	var ry := H
	box(g, f, 0.0, Lw, 0.0, WALK + 0.3, ry + 0.05, ry + 0.25, K_CONCRETE, stucco.darkened(0.08), 0.0, 0.0, 20.0 + float(ns - 1), 0.0, 4 | 8 | 16 | 32)
	box(g, f, -0.05, Lw + 0.05, WALK + 0.3, WALK + 0.42, ry - 0.05, top, K_TRIM, accent, 0.0, 0.0, 0.0, 0.0)
	g.quad([f.p(0.0, 0.0, top), f.p(Lw, 0.0, top), f.p(Lw, WALK + 0.3, top), f.p(0.0, WALK + 0.3, top)], Vector3.UP,
		[Vector2(0, 0), Vector2(Lw, 0), Vector2(Lw, 1), Vector2(0, 1)], K_ROOF, ROOF_C)
	box(g, f, 0.2, Lw - 0.2, WALK + 0.43, WALK + 0.47, ry + 0.02, ry + 0.06, K_NEON, neon, 0.0, 0.0, 0.0, 0.0, 1 | 4 | 8 | 32)
	# Posts every other bay from the ground to the roof.
	var pa := 0.15
	while pa <= Lw - 0.1:
		box(g, f, pa - 0.06, pa + 0.06, WALK - 0.16, WALK - 0.04, 0.15, ry + 0.05, K_STEEL, STEEL_C)
		pa += Motels.ROOM_W * 2.0
	box(g, f, Lw - 0.18, Lw - 0.06, WALK - 0.16, WALK - 0.04, 0.15, ry + 0.05, K_STEEL, STEEL_C)
	if stair:
		_stair(ch, g, f, trim)


## A railing along the walk's edge: a top rail, a bottom rail and pickets.
static func _railing(g: Geo, f: Frame, a0: float, a1: float, s: float, y: float, c: Color, stair: bool) -> void:
	var start := a0 + (1.1 if stair else 0.05)
	box(g, f, start, a1 - 0.05, s - 0.09, s - 0.03, y + 0.98, y + 1.04, K_STEEL, c)
	box(g, f, start, a1 - 0.05, s - 0.08, s - 0.04, y + 0.1, y + 0.14, K_STEEL, c, 0.0, 0.0, -1.0, 0.0, 1 | 2 | 16)
	var a := start + 0.07
	while a < a1 - 0.1:
		box(g, f, a - 0.012, a + 0.012, s - 0.07, s - 0.05, y + 0.14, y + 0.98, K_STEEL, c, 0.0, 0.0, -1.0, 0.0, 1 | 2)
		a += 0.13


## A straight steel stair at the wing's start: from the court up to the first walk, outside it.
static func _stair(ch: CityChunk, g: Geo, f: Frame, c: Color) -> void:
	var WALK := Motels.WALK
	var rise := Motels.STOREY
	var n := 16
	var run := 0.28
	var a_top := 1.1
	var s0 := WALK
	var s1 := WALK + 1.05
	for i in n:
		var y := rise * float(i + 1) / float(n)
		var a := a_top + float(n - 1 - i) * run
		box(g, f, a, a + run + 0.02, s0 + 0.05, s1 - 0.05, y - 0.05, y, K_CONCRETE, CONCRETE_C, 0.0, 0.0, 0.0)
		ch._add_shape(Vector3(run, 0.1, 1.0) if absf(f.al.x) > 0.5 else Vector3(1.0, 0.1, run), f.p(a + run * 0.5, (s0 + s1) * 0.5, y - 0.05))
	# A landing at the top, the stringers and a handrail.
	box(g, f, 0.05, a_top, s0, s1, rise - 0.2, rise, K_CONCRETE, CONCRETE_C, 0.0, 0.0, 0.0)
	var a_bot := a_top + float(n) * run
	for s: float in [s0 + 0.02, s1 - 0.06]:
		_slant(g, f, a_bot, a_top, s, s + 0.05, 0.0, rise, 0.3, c)
		_slant(g, f, a_bot, a_top, s, s + 0.04, 0.95, rise + 0.95, 0.05, c)
	box(g, f, a_bot - 0.05, a_bot, s1 - 0.06, s1 - 0.02, 0.0, 0.95, K_STEEL, c)


## A slanted bar from (a0, y0) to (a1, y1), `h` tall, s0..s1 thick.
static func _slant(g: Geo, f: Frame, a0: float, a1: float, s0: float, s1: float, y0: float, y1: float, h: float, c: Color) -> void:
	var up := Vector3.UP
	var dir := f.p(a1, s0, y1) - f.p(a0, s0, y0)
	var nrm := dir.cross(f.S()).normalized()
	if nrm.dot(up) < 0.0:
		nrm = -nrm
	for s: float in [s0, s1]:
		var side := f.S() if s == s1 else -f.S()
		g.quad([f.p(a0, s, y0 - h), f.p(a1, s, y1 - h), f.p(a1, s, y1), f.p(a0, s, y0)], side,
			[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], K_STEEL, c)
	g.quad([f.p(a0, s0, y0), f.p(a1, s0, y1), f.p(a1, s1, y1), f.p(a0, s1, y0)], nrm,
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], K_STEEL, c)
	g.quad([f.p(a0, s0, y0 - h), f.p(a1, s0, y1 - h), f.p(a1, s1, y1 - h), f.p(a0, s1, y0 - h)], -nrm,
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], K_STEEL, c)


## The office in the front corner: a glass front to the street and the court, a stone wall, a
## swept roof tipped up toward the boulevard, OFFICE in neon on the fascia, a warm light inside.
static func _office(ch: CityChunk, g: Geo, L: Dictionary, base: float, stucco: Color, trim: Color, accent: Color, neon: Color) -> void:
	var of: Dictionary = L.office
	var d: Vector2 = L.d
	var n: Vector2 = L.n
	var O: Vector2 = L.O
	# Frame: a along -d from the office's high-u side... simpler: a along d, s out toward the street (-n).
	var u0 := float(of.u0)
	var u1 := float(of.u1)
	var v0 := float(of.v0)
	var v1 := float(of.v1)
	var f := Frame.new(O + d * u0 + n * v0, d, -n, base)
	var W := u1 - u0
	var Dp := v1 - v0
	var H := Motels.OFFICE_H
	# s runs 0 (street face) to -Dp (back).
	# The stone wall at the high-u end and the back.
	box(g, f, W - 0.35, W, -Dp, 0.0, -0.4, H, K_STONE, Color(0.62, 0.55, 0.47), 0.0, 0.0, -1.0, 0.0, 1 | 2 | 4 | 8)
	box(g, f, 0.0, W - 0.35, -Dp, -Dp + 0.3, -0.4, H, K_STUCCO, stucco, 0.0, 0.0, -1.0, 0.0, 1 | 2 | 8)
	# The glass front to the street and to the court (the low-u side), on a stucco base.
	box(g, f, 0.0, W - 0.35, -0.2, 0.0, -0.4, 0.45, K_STUCCO, stucco, 0.0, 0.0, -1.0, 0.0, 1 | 8 | 16)
	g.quad([f.p(0.05, -0.1, 0.45), f.p(W - 0.35, -0.1, 0.45), f.p(W - 0.35, -0.1, H - 0.2), f.p(0.05, -0.1, H - 0.2)], f.S(),
		[Vector2(0.05, 0.45), Vector2(W - 0.35, 0.45), Vector2(W - 0.35, H - 0.2), Vector2(0.05, H - 0.2)], K_OFFICE_GLASS, Color.BLACK)
	g.quad([f.p(0.05, -Dp + 0.3, 0.0), f.p(0.05, -0.1, 0.0), f.p(0.05, -0.1, H - 0.2), f.p(0.05, -Dp + 0.3, H - 0.2)], -f.A(),
		[Vector2(0.0, 0.0), Vector2(Dp, 0.0), Vector2(Dp, H - 0.2), Vector2(0.0, H - 0.2)], K_OFFICE_GLASS, Color.BLACK)
	var mul := 0.0
	while mul <= W - 0.3:
		box(g, f, mul, mul + 0.07, -0.14, -0.04, 0.45, H - 0.2, K_STEEL, Color(0.75, 0.75, 0.73), 0.0, 0.0, -1.0, 0.0, 1 | 4 | 8)
		mul += 1.2
	# The swept roof: a slab rising toward the street, overhanging both glass faces.
	var r0 := H - 0.05
	var r1 := H + 1.3
	var sa := -Dp - 0.3
	var sb := 1.6
	var ea := -0.9
	var eb := W + 0.4
	var top := [f.p(ea, sa, r0 + 0.25), f.p(eb, sa, r0 + 0.25), f.p(eb, sb, r1 + 0.25), f.p(ea, sb, r1 + 0.25)]
	var bot := [f.p(ea, sa, r0), f.p(eb, sa, r0), f.p(eb, sb, r1), f.p(ea, sb, r1)]
	var b0: Vector3 = bot[0]
	var slope_n: Vector3 = ((bot[3] as Vector3) - b0).cross((bot[1] as Vector3) - b0).normalized()
	if slope_n.y < 0.0:
		slope_n = -slope_n
	g.quad(top, slope_n, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], K_ROOF, ROOF_C)
	g.quad(bot, -slope_n, [Vector2(ea, sa), Vector2(eb, sa), Vector2(eb, sb), Vector2(ea, sb)], K_TRIM, Color(0.93, 0.92, 0.88))
	g.quad([bot[3], bot[2], top[2], top[3]], f.S(), [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], K_TRIM, accent)
	g.quad([bot[0], bot[1], top[1], top[0]], -f.S(), [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], K_TRIM, accent)
	g.quad([bot[0], bot[3], top[3], top[0]], -f.A(), [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], K_TRIM, accent)
	g.quad([bot[1], bot[2], top[2], top[1]], f.A(), [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], K_TRIM, accent)
	# A downlit soffit edge: the neon line under the street edge of the roof.
	g.quad([f.p(ea + 0.3, sb - 0.05, r1 - 0.02), f.p(eb - 0.3, sb - 0.05, r1 - 0.02), f.p(eb - 0.3, sb - 0.12, r1 - 0.02 - 0.06), f.p(ea + 0.3, sb - 0.12, r1 - 0.08)], Vector3.DOWN,
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], K_NEON, neon)
	# OFFICE in neon letters, on a stand on the stone wall's top, facing the street.
	_neon_text(g, "OFFICE", 0.62, f.p(W * 0.45, 0.25, H + 0.25), f.S(), neon.lerp(Color(1.0, 0.3, 0.3), 0.5))
	ch._add_shape(Vector3(W, H, Dp) if absf(d.x) > 0.5 else Vector3(Dp, H, W), f.p(W * 0.5, -Dp * 0.5, H * 0.5))
	# The light inside, on the desktop renderers (DayNight drives the lamp_light group).
	if not OS.has_feature("web"):
		var light := OmniLight3D.new()
		light.position = f.p(W * 0.4, 0.8, 2.9)
		light.omni_range = 16.0
		light.omni_attenuation = 1.4
		light.light_color = Color(1.0, 0.78, 0.55)
		light.light_energy = 0.0
		light.set_meta("lamp_gain", 0.7)
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 120.0
		light.distance_fade_length = 30.0
		light.add_to_group("lamp_light")
		ch.add_child(light)


static var _text_cache: Dictionary = {}


## Text as flat neon geometry facing `face` (TextMesh outlines, filled).
static func _neon_text(g: Geo, txt: String, height: float, at: Vector3, face: Vector3, c: Color) -> void:
	var key := "%s|%.2f" % [txt, height]
	if not _text_cache.has(key):
		var tm := TextMesh.new()
		tm.text = txt
		tm.font_size = 48
		tm.pixel_size = height / 48.0 * 1.3
		tm.depth = 0.0
		tm.curve_step = 4.0
		tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var arr := tm.get_mesh_arrays()
		var verts := PackedVector3Array()
		var idx := PackedInt32Array()
		if arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
			verts = arr[Mesh.ARRAY_VERTEX]
			var ids = arr[Mesh.ARRAY_INDEX]
			if ids == null or (ids as PackedInt32Array).is_empty():
				for k in verts.size():
					idx.append(k)
			else:
				idx = ids
		_text_cache[key] = [verts, idx]
	var geo: Array = _text_cache[key]
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	# The reader's right, looking at the face.
	var r := (-face).cross(Vector3.UP).normalized()
	var colour := Color(c.r, c.g, c.b, (float(K_NEON) + 0.25) / 16.0)
	var i := 0
	while i + 2 < idx.size():
		var tri: Array = []
		for k in 3:
			var p: Vector3 = verts[idx[i + k]]
			tri.append(at + r * p.x + Vector3.UP * p.y + face * 0.01)
		var t0: Vector3 = tri[0]
		var flat: Vector3 = ((tri[2] as Vector3) - t0).cross((tri[1] as Vector3) - t0)
		var order := [0, 1, 2] if flat.dot(face) >= 0.0 else [0, 2, 1]
		for k: int in order:
			g.v.append(tri[k])
			g.nrm.append(face)
			g.uv.append(Vector2.ZERO)
			g.uv2.append(Vector2.ZERO)
			g.col.append(colour)
		i += 3
