class_name AirportKit
extends RefCounted
## The airport's small hardware, built in code at real size (metres) on ONE material
## (shaders/airport_kit.gdshader, the part kinds in the vertex colour's alpha, a vehicle's livery
## in the instance's INSTANCE_CUSTOM): ground service equipment - pushback tug, baggage tug and
## carts, belt loader, catering truck on its scissor lift, fuel truck, ground power unit - cones,
## floodlight masts, the runway / taxiway light fixtures, the perimeter fence, blast fences, the
## localizer, glide-slope mast, windsock and PAPI. Every mesh faces -Z (a vehicle's front), stands
## on y 0 and is cached; Airport batches them (one draw per kind a chunk).
##
## Colours below are LINEAR (the shader works in linear on both renderers).

## Width of one fence bay (a post at each end), the perimeter fence's height, a blast fence panel.
const FENCE_BAY := 3.0
const FENCE_HEIGHT := 2.6
const BLAST_PANEL := 6.0

## Part kinds (vertex alpha, see the shader).
const PAINT := 1.0
const LAMP := 0.75
const GLASS := 0.5
const RUBBER := 0.25
const METAL := 0.0

const C_TYRE := Color(0.03, 0.03, 0.03)
const C_STEEL := Color(0.30, 0.31, 0.32)
const C_DARK := Color(0.05, 0.05, 0.055)
const C_GALV := Color(0.42, 0.43, 0.44)
const C_YELLOW := Color(0.80, 0.52, 0.03)
const C_WHITE := Color(0.78, 0.79, 0.80)
const C_ORANGE := Color(0.90, 0.22, 0.02)
const C_AMBER := Color(1.0, 0.45, 0.05)
const C_RED := Color(0.75, 0.05, 0.03)

static var _cache: Dictionary = {}
static var _material: ShaderMaterial = null


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/airport_kit.gdshader")
	return _material


## Liveries for INSTANCE_CUSTOM (alpha 1 = use it).
static func livery_white() -> Color:
	return Color(0.80, 0.81, 0.82, 1.0)


static func livery_yellow() -> Color:
	return Color(0.82, 0.55, 0.04, 1.0)


## A baggage cart's curtain: navy, grey, dark green or faded red.
static func cart_tint(roll: int) -> Color:
	var tints := [Color(0.03, 0.05, 0.12, 1.0), Color(0.18, 0.19, 0.20, 1.0), Color(0.03, 0.08, 0.05, 1.0), Color(0.22, 0.04, 0.03, 1.0)]
	return tints[absi(roll) % tints.size()]


# --- Mesh building ------------------------------------------------------------------------------

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _commit(key: String, st: SurfaceTool) -> ArrayMesh:
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_cache[key] = mesh
	return mesh


## One triangle facing `n` whatever the corner order.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, kind: float) -> void:
	var pts := [a, b, c] if (c - a).cross(b - a).dot(n) >= 0.0 else [a, c, b]
	var cc := Color(col.r, col.g, col.b, kind)
	for p: Vector3 in pts:
		st.set_color(cc)
		st.set_normal(n)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, kind: float) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n == Vector3.ZERO:
		n = (c - b).cross(a - b).normalized()
	_tri(st, a, b, c, n, col, kind)
	_tri(st, a, c, d, n, col, kind)


## A box `size` at `centre`, turned by `basis` (rotation only), all six faces.
static func _box(st: SurfaceTool, centre: Vector3, size: Vector3, col: Color, kind: float = METAL, basis: Basis = Basis(), bottom: bool = false) -> void:
	var h := size * 0.5
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			if axis == 1 and sgn < 0.0 and not bottom:
				continue
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			v[(axis + 2) % 3] = 1.0
			var c0 := n * h[axis]
			var hu := u * h[(axis + 1) % 3]
			var hv := v * h[(axis + 2) % 3]
			var pts := [c0 - hu - hv, c0 + hu - hv, c0 + hu + hv, c0 - hu + hv]
			var w: Array[Vector3] = []
			for p: Vector3 in pts:
				w.append(centre + basis * p)
			var wn := (basis * n).normalized()
			_tri(st, w[0], w[1], w[2], wn, col, kind)
			_tri(st, w[0], w[2], w[3], wn, col, kind)


## A cylinder between `a` and `b` (any direction), radius r0 at a and r1 at b, `segs` sides,
## smooth sides, capped.
static func _cyl(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, segs: int, col: Color, kind: float = METAL, caps: bool = true) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u).normalized()
	var cc := Color(col.r, col.g, col.b, kind)
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		var d0 := u * cos(t0) + v * sin(t0)
		var d1 := u * cos(t1) + v * sin(t1)
		var p := [a + d0 * r0, b + d0 * r1, b + d1 * r1, a + d1 * r0]
		var nn := [d0, d0, d1, d1]
		var order := [0, 1, 2, 0, 2, 3] if (p[1] - p[0]).cross(p[3] - p[0]).dot(d0 + d1) < 0.0 else [0, 2, 1, 0, 3, 2]
		for k: int in order:
			st.set_color(cc)
			st.set_normal(nn[k])
			st.add_vertex(p[k])
		if caps:
			for end in 2:
				var c: Vector3 = a if end == 0 else b
				var r := r0 if end == 0 else r1
				if r > 0.001:
					_tri(st, c, c + d0 * r, c + d1 * r, -axis if end == 0 else axis, col, kind)


## A wheel at `at` (its centre), axle along X, radius and width.
static func _wheel(st: SurfaceTool, at: Vector3, radius: float, width: float) -> void:
	_cyl(st, at - Vector3(width * 0.5, 0.0, 0.0), at + Vector3(width * 0.5, 0.0, 0.0), radius, radius, 10, C_TYRE, RUBBER)
	_cyl(st, at - Vector3(width * 0.52, 0.0, 0.0), at + Vector3(width * 0.52, 0.0, 0.0), radius * 0.55, radius * 0.55, 8, C_STEEL, METAL)


static func _wheels(st: SurfaceTool, half_track: float, z_front: float, z_rear: float, radius: float, width: float) -> void:
	for z: float in [z_front, z_rear]:
		for s: float in [-1.0, 1.0]:
			_wheel(st, Vector3(s * half_track, radius, z), radius, width)


# --- Ground service equipment -------------------------------------------------------------------

## A ground service vehicle by name: "pushback", "baggage_tug", "cart", "belt_loader",
## "catering", "fuel_truck", "gpu".
static func vehicle(kind: String) -> ArrayMesh:
	var key := "veh_" + kind
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	match kind:
		"pushback":
			# A towbarless tug: a long low slab with a raised cab on one side at the back, a cradle
			# for the nose wheel, big tyres.
			_box(st, Vector3(0.0, 0.85, 0.0), Vector3(2.9, 0.75, 6.0), C_WHITE, PAINT)
			_box(st, Vector3(0.0, 0.42, 0.0), Vector3(2.6, 0.3, 5.6), C_DARK, METAL)
			_box(st, Vector3(-0.85, 1.55, 2.0), Vector3(1.1, 0.65, 1.5), C_WHITE, PAINT)
			_box(st, Vector3(-0.85, 2.05, 2.0), Vector3(1.12, 0.35, 1.52), C_DARK, GLASS)
			_box(st, Vector3(-0.85, 2.3, 2.0), Vector3(1.2, 0.08, 1.6), C_WHITE, PAINT)
			_box(st, Vector3(0.0, 1.25, -2.6), Vector3(1.4, 0.1, 0.9), C_DARK, METAL)
			_box(st, Vector3(1.1, 1.26, -2.92), Vector3(0.3, 0.06, 0.12), C_AMBER, LAMP)
			_box(st, Vector3(-1.1, 1.26, -2.92), Vector3(0.3, 0.06, 0.12), C_AMBER, LAMP)
			_cyl(st, Vector3(-0.85, 2.34, 2.0), Vector3(-0.85, 2.5, 2.0), 0.09, 0.07, 8, C_AMBER, LAMP)
			_wheels(st, 1.2, -1.9, 1.9, 0.5, 0.45)
		"baggage_tug":
			_box(st, Vector3(0.0, 0.7, 0.3), Vector3(1.3, 0.6, 1.4), C_YELLOW, PAINT)
			_box(st, Vector3(0.0, 0.62, -0.75), Vector3(1.25, 0.45, 0.8), C_YELLOW, PAINT)
			_box(st, Vector3(0.0, 1.1, 0.55), Vector3(0.55, 0.35, 0.5), C_DARK, RUBBER)
			for x: float in [-0.58, 0.58]:
				for z: float in [-0.1, 1.0]:
					_cyl(st, Vector3(x, 1.0, z), Vector3(x, 2.0, z), 0.03, 0.03, 6, C_DARK, METAL, false)
			_box(st, Vector3(0.0, 2.02, 0.45), Vector3(1.35, 0.06, 1.3), C_YELLOW, PAINT)
			_cyl(st, Vector3(0.0, 2.05, 0.45), Vector3(0.0, 2.2, 0.45), 0.07, 0.06, 8, C_AMBER, LAMP)
			_box(st, Vector3(0.0, 0.5, 1.15), Vector3(0.3, 0.2, 0.25), C_DARK, METAL)
			_wheels(st, 0.55, -0.75, 0.75, 0.3, 0.25)
		"cart":
			# A covered baggage cart: deck, corner posts, curtained sides (the livery), a roof,
			# a tow bar out front.
			_box(st, Vector3(0.0, 0.55, 0.0), Vector3(1.5, 0.12, 2.9), C_STEEL, METAL)
			for x: float in [-0.72, 0.72]:
				for z: float in [-1.42, 1.42]:
					_box(st, Vector3(x, 1.25, z), Vector3(0.06, 1.3, 0.06), C_GALV, METAL)
				_box(st, Vector3(x, 1.25, 0.0), Vector3(0.03, 1.15, 2.78), C_DARK, PAINT)
			_box(st, Vector3(0.0, 1.25, 1.43), Vector3(1.4, 1.15, 0.03), C_DARK, PAINT)
			_box(st, Vector3(0.0, 1.95, 0.0), Vector3(1.58, 0.08, 3.0), C_GALV, METAL)
			# A few bags showing at the open front.
			_box(st, Vector3(-0.3, 0.85, -1.1), Vector3(0.5, 0.5, 0.7), Color(0.05, 0.05, 0.06), RUBBER)
			_box(st, Vector3(0.32, 0.8, -1.0), Vector3(0.45, 0.4, 0.6), Color(0.25, 0.02, 0.02), RUBBER)
			_box(st, Vector3(0.0, 1.3, -1.15), Vector3(0.6, 0.45, 0.5), Color(0.08, 0.10, 0.18), RUBBER)
			_cyl(st, Vector3(0.0, 0.45, -1.45), Vector3(0.0, 0.35, -2.3), 0.04, 0.04, 6, C_DARK, METAL)
			_wheels(st, 0.62, -1.0, 1.0, 0.22, 0.16)
		"belt_loader":
			# Chassis, a low cab at the back left, and the conveyor rising toward the front (-Z)
			# to the hold door, with side rails.
			_box(st, Vector3(0.0, 0.55, 0.4), Vector3(1.9, 0.4, 6.2), C_YELLOW, PAINT)
			_box(st, Vector3(-0.55, 1.15, 2.6), Vector3(0.8, 0.8, 1.2), C_YELLOW, PAINT)
			_box(st, Vector3(-0.55, 1.75, 2.55), Vector3(0.82, 0.4, 1.0), C_DARK, GLASS)
			_box(st, Vector3(-0.55, 2.0, 2.6), Vector3(0.9, 0.06, 1.3), C_YELLOW, PAINT)
			var belt := Basis(Vector3.RIGHT, -0.36)
			var mid := Vector3(0.2, 2.1, -1.0)
			_box(st, mid, Vector3(1.0, 0.18, 7.6), C_DARK, RUBBER, belt)
			for x: float in [-0.55, 0.95]:
				_box(st, mid + belt * Vector3(x - 0.2, 0.45, 0.0), Vector3(0.05, 0.05, 7.4), C_GALV, METAL, belt)
			_box(st, Vector3(0.2, 1.1, -1.2), Vector3(0.3, 1.0, 0.3), C_STEEL, METAL)
			_cyl(st, Vector3(-0.55, 2.03, 2.6), Vector3(-0.55, 2.18, 2.6), 0.07, 0.06, 8, C_AMBER, LAMP)
			_wheels(st, 0.85, -1.9, 2.2, 0.36, 0.28)
		"catering":
			# Cab, chassis and a box body on a scissor lift, raised to the rear door, with its
			# front platform reaching out to the fuselage.
			_box(st, Vector3(0.0, 1.35, 3.6), Vector3(2.4, 1.7, 1.9), C_WHITE, PAINT)
			_box(st, Vector3(0.0, 1.85, 2.66), Vector3(2.2, 0.75, 0.04), C_DARK, GLASS)
			_box(st, Vector3(0.0, 0.75, -0.6), Vector3(2.2, 0.5, 6.8), C_DARK, METAL)
			for s: float in [-1.0, 1.0]:
				var arm := Basis(Vector3.RIGHT, s * 0.48)
				_box(st, Vector3(0.0, 2.0, -1.0), Vector3(0.12, 0.16, 5.6), C_STEEL, METAL, arm)
				_box(st, Vector3(1.0, 2.0, -1.0), Vector3(0.12, 0.16, 5.6), C_STEEL, METAL, arm)
				_box(st, Vector3(-1.0, 2.0, -1.0), Vector3(0.12, 0.16, 5.6), C_STEEL, METAL, arm)
			_box(st, Vector3(0.0, 4.6, -0.8), Vector3(2.5, 2.6, 6.2), C_WHITE, PAINT, Basis(), true)
			_box(st, Vector3(0.0, 3.32, -4.25), Vector3(2.0, 0.08, 0.9), C_STEEL, METAL)
			_box(st, Vector3(0.0, 3.95, -3.92), Vector3(1.4, 1.8, 0.05), C_DARK, METAL)
			_cyl(st, Vector3(0.0, 2.2, 4.4), Vector3(0.0, 2.36, 4.4), 0.08, 0.07, 8, C_AMBER, LAMP)
			_wheels(st, 1.0, -2.9, 3.4, 0.48, 0.32)
		"fuel_truck":
			_box(st, Vector3(0.0, 1.35, -3.3), Vector3(2.4, 1.8, 1.9), C_WHITE, PAINT)
			_box(st, Vector3(0.0, 1.85, -4.26), Vector3(2.2, 0.75, 0.04), C_DARK, GLASS)
			_box(st, Vector3(0.0, 0.8, 0.8), Vector3(2.0, 0.4, 6.8), C_DARK, METAL)
			_cyl(st, Vector3(0.0, 2.05, -2.0), Vector3(0.0, 2.05, 4.2), 1.15, 1.15, 14, C_WHITE, PAINT)
			_box(st, Vector3(0.0, 3.25, 1.2), Vector3(0.7, 0.12, 4.6), C_GALV, METAL)
			_cyl(st, Vector3(1.0, 1.0, 3.6), Vector3(1.0, 1.0, 4.6), 0.35, 0.35, 10, C_DARK, METAL)
			_cyl(st, Vector3(0.0, 2.27, -4.3), Vector3(0.0, 2.42, -4.3), 0.08, 0.07, 8, C_AMBER, LAMP)
			_box(st, Vector3(0.0, 0.62, 4.25), Vector3(2.1, 0.3, 0.2), C_RED, PAINT)
			_wheels(st, 1.0, -3.1, 3.2, 0.5, 0.35)
		"gpu":
			_box(st, Vector3(0.0, 0.95, 0.0), Vector3(1.3, 1.1, 2.1), C_GALV, METAL)
			_box(st, Vector3(0.66, 1.0, 0.0), Vector3(0.02, 0.6, 1.4), C_DARK, METAL)
			_cyl(st, Vector3(0.0, 0.45, -1.05), Vector3(0.0, 0.3, -1.8), 0.04, 0.04, 6, C_DARK, METAL)
			_cyl(st, Vector3(-0.4, 1.5, 0.6), Vector3(-0.4, 1.7, 0.6), 0.06, 0.06, 6, C_DARK, METAL)
			_wheels(st, 0.6, -0.6, 0.6, 0.25, 0.16)
	return _commit(key, st)


static func cone() -> ArrayMesh:
	if _cache.has("cone"):
		return _cache["cone"]
	var st := _begin()
	_box(st, Vector3(0.0, 0.02, 0.0), Vector3(0.42, 0.04, 0.42), C_DARK, RUBBER)
	_cyl(st, Vector3(0.0, 0.04, 0.0), Vector3(0.0, 0.32, 0.0), 0.16, 0.11, 10, C_ORANGE, METAL, false)
	_cyl(st, Vector3(0.0, 0.32, 0.0), Vector3(0.0, 0.46, 0.0), 0.11, 0.075, 10, Color(0.85, 0.85, 0.85), METAL, false)
	_cyl(st, Vector3(0.0, 0.46, 0.0), Vector3(0.0, 0.72, 0.0), 0.075, 0.025, 10, C_ORANGE, METAL)
	return _commit("cone", st)


## An apron floodlight mast: a tapered pole, a ladder cage, a head frame with four floods aimed
## out over -Z and an obstruction light on top. Its lamps' night glow is in Airport.lights_mesh().
static func mast() -> ArrayMesh:
	if _cache.has("mast"):
		return _cache["mast"]
	var st := _begin()
	var h := Airport.MAST_HEIGHT
	_box(st, Vector3(0.0, 0.25, 0.0), Vector3(1.6, 0.5, 1.6), Color(0.38, 0.37, 0.35), METAL)
	_cyl(st, Vector3(0.0, 0.5, 0.0), Vector3(0.0, h - 0.6, 0.0), 0.42, 0.22, 12, C_GALV, METAL, false)
	# Head frame: a ring platform and a bar the floods hang from.
	_box(st, Vector3(0.0, h - 0.6, -0.2), Vector3(5.6, 0.12, 1.8), C_GALV, METAL)
	_box(st, Vector3(0.0, h + 0.2, -0.8), Vector3(5.6, 0.1, 0.1), C_GALV, METAL)
	for k in 4:
		var x := (float(k) - 1.5) * 1.15
		var tilt := Basis(Vector3.RIGHT, 0.75)
		_box(st, Vector3(x, h - 0.2, -0.95), Vector3(0.95, 0.75, 0.32), C_DARK, METAL, tilt)
		_box(st, Vector3(x, h - 0.32, -1.08), Vector3(0.82, 0.62, 0.04), Color(1.0, 0.85, 0.6), LAMP, tilt)
	_cyl(st, Vector3(0.0, h - 0.6, 0.0), Vector3(0.0, h + 1.1, 0.0), 0.05, 0.05, 6, C_GALV, METAL, false)
	_cyl(st, Vector3(0.0, h + 1.1, 0.0), Vector3(0.0, h + 1.4, 0.0), 0.12, 0.1, 8, C_RED, LAMP)
	return _commit("mast", st)


## An elevated edge light: a frangible stalk and a lens (its colour from the instance's
## INSTANCE_CUSTOM via the PAINT kind: blue for taxiways, clear for runways).
static func edge_light() -> ArrayMesh:
	if _cache.has("edge_light"):
		return _cache["edge_light"]
	var st := _begin()
	_cyl(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.05, 0.0), 0.11, 0.11, 8, C_DARK, METAL)
	_cyl(st, Vector3(0.0, 0.05, 0.0), Vector3(0.0, 0.3, 0.0), 0.03, 0.03, 6, C_YELLOW, METAL, false)
	_cyl(st, Vector3(0.0, 0.3, 0.0), Vector3(0.0, 0.42, 0.0), 0.075, 0.06, 8, Color(0.9, 0.9, 0.85), PAINT)
	return _commit("edge_light", st)


## An inset light in the pavement: a steel disc with its lens.
static func inset_light() -> ArrayMesh:
	if _cache.has("inset_light"):
		return _cache["inset_light"]
	var st := _begin()
	_cyl(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.03, 0.0), 0.17, 0.15, 10, Color(0.36, 0.36, 0.36), METAL)
	_box(st, Vector3(0.0, 0.032, -0.06), Vector3(0.12, 0.012, 0.05), Color(0.9, 0.9, 0.85), LAMP)
	return _commit("inset_light", st)


## The perimeter fence's mesh: one metre of chain-link (instances stretch it along x) with a
## barbed-wire outrigger leaning out over -Z, on the chain-link shader.
static func fence_panel() -> ArrayMesh:
	if _cache.has("fence_panel"):
		return _cache["fence_panel"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := FENCE_HEIGHT
	var quads := [
		[Vector3(-0.5, 0.05, 0.0), Vector3(0.5, 0.05, 0.0), Vector3(0.5, h, 0.0), Vector3(-0.5, h, 0.0), 0.05],
		[Vector3(-0.5, h, 0.0), Vector3(0.5, h, 0.0), Vector3(0.5, h + 0.45, -0.35), Vector3(-0.5, h + 0.45, -0.35), h],
	]
	for q: Array in quads:
		var y0: float = q[4]
		var pts := [q[0], q[1], q[2], q[3]]
		for k: int in [0, 1, 2, 0, 2, 3]:
			var p: Vector3 = pts[k]
			st.set_normal(Vector3(0.0, 0.0, 1.0))
			# UV in metres: x along, y up the wire (the outrigger continues up its slope).
			st.set_uv(Vector2(p.x + 0.5, p.y if y0 < 1.0 else y0 + (p.y - h) / 0.45 * 0.57))
			st.add_vertex(p)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/chain_link.gdshader")
	st.set_material(mat)
	var mesh := st.commit()
	_cache["fence_panel"] = mesh
	return mesh


static func fence_post() -> ArrayMesh:
	if _cache.has("fence_post"):
		return _cache["fence_post"]
	var st := _begin()
	var h := FENCE_HEIGHT
	_cyl(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, h, 0.0), 0.04, 0.04, 6, C_GALV, METAL)
	_cyl(st, Vector3(0.0, h, 0.0), Vector3(0.0, h + 0.47, -0.37), 0.025, 0.025, 5, C_GALV, METAL)
	# Top rail and three strands of barbed wire along the outrigger (to the next post, 3 m on).
	_cyl(st, Vector3(0.0, h - 0.02, 0.0), Vector3(FENCE_BAY, h - 0.02, 0.0), 0.022, 0.022, 5, C_GALV, METAL, false)
	for k in 3:
		var f := (float(k) + 1.0) / 3.0
		var p := Vector3(0.0, h + 0.47 * f, -0.37 * f)
		_cyl(st, p, p + Vector3(FENCE_BAY, 0.0, 0.0), 0.006, 0.006, 3, C_GALV, METAL, false)
	return _commit("fence_post", st)


## A blast deflector panel: a sloped corrugated steel face toward +Z (the runway) on a frame.
static func blast_fence() -> ArrayMesh:
	if _cache.has("blast_fence"):
		return _cache["blast_fence"]
	var st := _begin()
	var w := BLAST_PANEL * 0.5
	var ribs := 12
	for i in ribs:
		var x0 := -w + BLAST_PANEL * float(i) / float(ribs)
		var x1 := -w + BLAST_PANEL * (float(i) + 0.5) / float(ribs)
		var x2 := -w + BLAST_PANEL * float(i + 1) / float(ribs)
		var lean := 1.6
		for seg: Array in [[x0, x1, 0.0, 0.12], [x1, x2, 0.12, 0.0]]:
			var a := Vector3(float(seg[0]), 0.1, 0.6 + float(seg[2]))
			var b := Vector3(float(seg[1]), 0.1, 0.6 + float(seg[3]))
			_quad(st, a, b, b + Vector3(0.0, 4.2, -lean), a + Vector3(0.0, 4.2, -lean), Color(0.36, 0.37, 0.38), METAL)
	for x: float in [-w + 0.2, 0.0, w - 0.2]:
		_box(st, Vector3(x, 1.6, -0.6), Vector3(0.18, 3.2, 0.18), C_STEEL, METAL, Basis(Vector3.RIGHT, 0.35))
	_box(st, Vector3(0.0, 0.15, 0.0), Vector3(BLAST_PANEL, 0.3, 1.6), Color(0.40, 0.39, 0.37), METAL)
	return _commit("blast_fence", st)


## One element of the localizer array: a post with a horizontal boom carrying the dipoles.
static func localizer() -> ArrayMesh:
	if _cache.has("localizer"):
		return _cache["localizer"]
	var st := _begin()
	_box(st, Vector3(0.0, 0.1, 0.0), Vector3(0.6, 0.2, 0.6), Color(0.4, 0.39, 0.37), METAL)
	_cyl(st, Vector3(0.0, 0.2, 0.0), Vector3(0.0, 2.6, 0.0), 0.05, 0.05, 6, C_GALV, METAL, false)
	_box(st, Vector3(0.0, 2.6, 0.0), Vector3(0.08, 0.08, 2.0), C_GALV, METAL)
	for z: float in [-0.9, -0.3, 0.3, 0.9]:
		_box(st, Vector3(0.0, 2.6, z), Vector3(1.3, 0.04, 0.04), Color(0.85, 0.85, 0.83), METAL)
	_box(st, Vector3(0.0, 1.3, 0.0), Vector3(2.4, 0.06, 0.06), C_GALV, METAL)
	_cyl(st, Vector3(0.0, 2.65, 0.0), Vector3(0.0, 2.8, 0.0), 0.05, 0.04, 6, C_RED, LAMP)
	return _commit("localizer", st)


## The glide-slope antenna: a lattice mast with its dishes, an equipment shelter at the foot.
static func glide_slope() -> ArrayMesh:
	if _cache.has("glide_slope"):
		return _cache["glide_slope"]
	var st := _begin()
	var h := 15.0
	for c: Vector2 in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(0.4, 0.4), Vector2(-0.4, 0.4)]:
		_cyl(st, Vector3(c.x, 0.0, c.y), Vector3(c.x * 0.5, h, c.y * 0.5), 0.04, 0.03, 5, Color(0.8, 0.8, 0.78), METAL, false)
	var y := 1.0
	while y < h:
		var s := lerpf(0.4, 0.2, y / h)
		_box(st, Vector3(0.0, y, 0.0), Vector3(s * 2.0, 0.04, s * 2.0), Color(0.75, 0.75, 0.73), METAL)
		y += 1.5
	for k in 3:
		_box(st, Vector3(0.0, 5.0 + float(k) * 4.0, -0.45), Vector3(1.4, 0.5, 0.1), Color(0.85, 0.85, 0.83), METAL)
	_cyl(st, Vector3(0.0, h, 0.0), Vector3(0.0, h + 0.2, 0.0), 0.1, 0.08, 8, C_RED, LAMP)
	_box(st, Vector3(3.0, 1.3, 0.0), Vector3(3.0, 2.6, 2.4), Color(0.70, 0.69, 0.64), METAL)
	_box(st, Vector3(3.0, 2.65, 0.0), Vector3(3.2, 0.1, 2.6), Color(0.45, 0.45, 0.44), METAL)
	return _commit("glide_slope", st)


## A windsock: pole, the frame ring and an orange-and-white sock half filled, streaming toward +X.
static func windsock() -> ArrayMesh:
	if _cache.has("windsock"):
		return _cache["windsock"]
	var st := _begin()
	_box(st, Vector3(0.0, 0.15, 0.0), Vector3(1.2, 0.3, 1.2), Color(0.42, 0.41, 0.38), METAL)
	_cyl(st, Vector3(0.0, 0.3, 0.0), Vector3(0.0, 6.4, 0.0), 0.07, 0.05, 8, Color(0.85, 0.85, 0.83), METAL, false)
	var droop := Vector3(1.0, -0.22, 0.0).normalized()
	var at := Vector3(0.1, 6.2, 0.0)
	var r := 0.45
	for k in 5:
		var a := at + droop * (float(k) * 0.72)
		var b := at + droop * (float(k + 1) * 0.72)
		var r1 := r - 0.055
		_cyl(st, a, b, r, r1, 12, C_ORANGE if k % 2 == 0 else Color(0.85, 0.85, 0.85), METAL, false)
		r = r1
	_cyl(st, Vector3(0.0, 6.4, 0.0), Vector3(0.0, 6.6, 0.0), 0.06, 0.05, 6, C_RED, LAMP)
	return _commit("windsock", st)


## A PAPI unit: a low box on legs with its two lenses facing -Z... turned by the caller to face
## the approach.
static func papi() -> ArrayMesh:
	if _cache.has("papi"):
		return _cache["papi"]
	var st := _begin()
	for x: float in [-0.5, 0.5]:
		_cyl(st, Vector3(x, 0.0, 0.0), Vector3(x, 0.45, 0.0), 0.04, 0.04, 6, C_GALV, METAL, false)
	_box(st, Vector3(0.0, 0.7, 0.0), Vector3(1.4, 0.5, 0.8), Color(0.82, 0.55, 0.05), METAL)
	for x: float in [-0.35, 0.35]:
		_box(st, Vector3(x, 0.72, -0.41), Vector3(0.36, 0.3, 0.02), Color(0.9, 0.85, 0.8), LAMP)
	return _commit("papi", st)
