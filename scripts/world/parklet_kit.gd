class_name ParkletKit
extends RefCounted
## The pieces of an outdoor dining parklet (Parklets), built here in code at real size on one
## shader (shaders/parklet.gdshader): the deck with its planters, end screens, light posts, the
## festoon of bulbs strung between them, the delineators and wheel stops out on the road; the
## clipped boxwood in the planters; the bistro sets (a table and two chairs, laid for two or bare); the canvas umbrellas, open or
## furled. Every mesh is one surface in StreetClutter's vertex format (colour alpha = what the
## face is, UV in metres, UV2 = roughness and metallic), so a chunk's parklets are a handful of
## MultiMesh draws.
##
## Frames. A deck: origin on the road at the kerb line in the middle of its length, +x along the
## kerb, +z out into the road, y up from the road; its boards are DECK_Y up, level with the
## pavement. A bistro set: origin on the deck under the table's middle, the chairs at
## -x and +x facing it (CHAIR_X). An umbrella: origin on the deck at its pole's foot.

# Vertex colour alpha codes, read by shaders/parklet.gdshader (round(a * 20)).
const A_FIXED := 0.0
const A_DECK := 0.1
const A_TIMBER := 0.15
const A_CANVAS := 0.2
const A_STEEL := 0.25
const A_BULB := 0.3
const A_GLASS := 0.35
const A_CHINA := 0.4
const A_FOOD := 0.45
const A_LEAF := 0.5
const A_SOIL := 0.55
const A_MARBLE := 0.6
const A_RATTAN := 0.65
const A_REFLECT := 0.7
const A_FLAME := 0.75
const A_PAINT := 1.0

## The deck's top above the road (the kerb's height: SIDEWALK_TOP - ROAD_TOP).
const DECK_Y := 0.15
## Depth of the deck out from the kerb (the parking lane is CityPlan.PARKING_LANE, 2.6 m).
const DEPTH := 2.3
## The planters along the road side: their depth (z) and height over the deck.
const PLANTER_D := 0.46
const PLANTER_H := 0.58
## The end screens' height over the deck.
const SCREEN_H := 1.05
## The light posts' height over the deck, and the bulbs' spacing along a string.
const POST_H := 2.75
const BULB_STEP := 0.42
## A bistro set: each chair's seat centre this far from the table's (along x), its seat's top.
const CHAIR_X := 0.6
const SEAT_Y := 0.46
## How far apart the sets stand along the deck.
const SET_PITCH := 1.95
## The deck lengths there are meshes for.
const LENGTHS := [6.0, 8.0, 10.0]

const DECK_WOOD := Color(0.5, 0.31, 0.19, A_DECK)
const CEDAR := Color(0.62, 0.42, 0.26, A_TIMBER)
const POST_WOOD := Color(0.36, 0.24, 0.15, A_TIMBER)
const BLACK_STEEL := Color(0.06, 0.06, 0.065, A_STEEL)
const CABLE := Color(0.03, 0.03, 0.03)
const RUBBER := Color(0.05, 0.05, 0.05)

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/parklet.gdshader")
	return _material


static func _finish(st: SurfaceTool, key: String) -> Mesh:
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes[key] = mesh
	return mesh


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, bevel: float, col: Color, rm: Vector2) -> void:
	StreetClutter._bbox(st, Transform3D(Basis(), c), size, bevel, col, rm)


## The light posts' tops (deck frame), in the order the strings run between them.
static func post_tops(length: float) -> Array:
	var x := length * 0.5 - 0.16
	var zi := 0.22
	var zo := DEPTH - PLANTER_D * 0.5
	var y := DECK_Y + POST_H - 0.05
	return [Vector3(-x, y, zi), Vector3(x, y, zi), Vector3(-x, y, zo), Vector3(x, y, zo)]


## The strings of bulbs, as pairs of post tops (two along the deck, two crossing it).
static func strings(length: float) -> Array:
	var p := post_tops(length)
	return [[p[0], p[1]], [p[2], p[3]], [p[0], p[3]], [p[2], p[1]]]


## A point on a string from `a` to `b` sagging `sag` at its middle (a parabola, close to the
## catenary a festoon hangs in).
static func string_point(a: Vector3, b: Vector3, f: float, sag: float) -> Vector3:
	return a.lerp(b, f) - Vector3(0.0, 4.0 * sag * f * (1.0 - f), 0.0)


## Where the bistro sets stand along a deck of `length` (x), at the deck's usable middle (z).
static func set_spots(length: float) -> Array:
	var n := maxi(1, int(floor((length - 1.2) / SET_PITCH)))
	var out: Array = []
	var z := (0.2 + DEPTH - PLANTER_D) * 0.5
	for i in n:
		out.append(Vector3((float(i) - float(n - 1) * 0.5) * SET_PITCH, DECK_Y, z))
	return out


## The deck of `length` metres: boards, fascia, planters with a clipped hedge, end screens, light posts and the festoon, delineators and
## wheel stops on the road. The planters take the instance's paint.
static func deck(length: float) -> Mesh:
	var key := "deck_%d" % int(length * 10.0)
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var hx := length * 0.5
	var wood_rm := Vector2(0.8, 0.0)
	# The boards: one top over the joists (the shader draws the boards), a nosing round the edge.
	StreetClutter._quad(st, Vector3(-hx, DECK_Y, 0.02), Vector3(hx, DECK_Y, 0.02), Vector3(hx, DECK_Y, DEPTH), Vector3(-hx, DECK_Y, DEPTH), Vector3.UP, DECK_WOOD, wood_rm)
	_box(st, Vector3(0.0, DECK_Y - 0.075, DEPTH - 0.02), Vector3(length, 0.13, 0.04), 0.006, CEDAR, wood_rm)
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * (hx - 0.02), DECK_Y - 0.075, DEPTH * 0.5), Vector3(0.04, 0.13, DEPTH), 0.006, CEDAR, wood_rm)
	# A dark steel angle where the deck meets the kerb, over the gutter it bridges.
	_box(st, Vector3(0.0, DECK_Y - 0.01, 0.015), Vector3(length, 0.02, 0.03), 0.0, BLACK_STEEL, Vector2(0.5, 0.6))
	# The planters along the road side: painted boxes in modules, a timber cap, soil inside.
	var paint := Color(1, 1, 1, A_PAINT)
	var modules := maxi(2, int(round(length / 2.0)))
	var mod_l := (length - 0.08) / float(modules)
	var pz := DEPTH - PLANTER_D * 0.5 - 0.02
	for m in modules:
		var cx := -hx + 0.04 + mod_l * (float(m) + 0.5)
		var ml := mod_l - 0.02
		# Four walls, each in two courses with a shadow line between.
		for course in 2:
			var y0 := DECK_Y + 0.02 + course * (PLANTER_H * 0.5)
			var h := PLANTER_H * 0.5 - 0.012
			_box(st, Vector3(cx, y0 + h * 0.5, pz + PLANTER_D * 0.5 - 0.02), Vector3(ml, h, 0.04), 0.008, paint, Vector2(0.55, 0.15))
			_box(st, Vector3(cx, y0 + h * 0.5, pz - PLANTER_D * 0.5 + 0.02), Vector3(ml, h, 0.04), 0.008, paint, Vector2(0.55, 0.15))
			for s: float in [-1.0, 1.0]:
				_box(st, Vector3(cx + s * (ml * 0.5 - 0.02), y0 + h * 0.5, pz), Vector3(0.04, h, PLANTER_D - 0.08), 0.008, paint, Vector2(0.55, 0.15))
		# Plinth (set back, dark) and cap.
		_box(st, Vector3(cx, DECK_Y + 0.01, pz), Vector3(ml - 0.04, 0.02, PLANTER_D - 0.04), 0.0, BLACK_STEEL, Vector2(0.6, 0.2))
		_box(st, Vector3(cx, DECK_Y + PLANTER_H + 0.015, pz + PLANTER_D * 0.5 - 0.03), Vector3(ml + 0.02, 0.03, 0.08), 0.008, CEDAR, wood_rm)
		_box(st, Vector3(cx, DECK_Y + PLANTER_H + 0.015, pz - PLANTER_D * 0.5 + 0.03), Vector3(ml + 0.02, 0.03, 0.08), 0.008, CEDAR, wood_rm)
		StreetClutter._quad(st, Vector3(cx - ml * 0.5 + 0.04, DECK_Y + PLANTER_H - 0.07, pz - PLANTER_D * 0.5 + 0.05),
			Vector3(cx + ml * 0.5 - 0.04, DECK_Y + PLANTER_H - 0.07, pz - PLANTER_D * 0.5 + 0.05),
			Vector3(cx + ml * 0.5 - 0.04, DECK_Y + PLANTER_H - 0.07, pz + PLANTER_D * 0.5 - 0.05),
			Vector3(cx - ml * 0.5 + 0.04, DECK_Y + PLANTER_H - 0.07, pz + PLANTER_D * 0.5 - 0.05), Vector3.UP,
			Color(0.16, 0.11, 0.08, A_SOIL), Vector2(0.95, 0.0))
	# A clipped boxwood hedge along the planters: one rounded mass the length of the run, its top
	# and face broken by overlapping lumps (new growth since the last clip), taller at the ends.
	var hedge_y := DECK_Y + PLANTER_H - 0.07
	var leaf := Color(0.2, 0.32, 0.13, A_LEAF)
	_box(st, Vector3(0.0, hedge_y + 0.12, pz), Vector3(length - 0.16, 0.26, PLANTER_D - 0.1), 0.11, leaf, Vector2(0.7, 0.0))
	var lumps := int(floor((length - 0.2) / 0.16))
	for k in lumps:
		var x := -hx + 0.1 + (length - 0.2) * (float(k) + 0.5) / float(lumps)
		var j := fposmod(sin(float(k) * 12.9898 + length) * 43758.5453, 1.0)
		var j2 := fposmod(sin(float(k) * 78.233 + length) * 24634.6345, 1.0)
		var end := 1.0 if k < 2 or k >= lumps - 2 else 0.0
		var r := Vector3(0.15 + 0.05 * j, 0.1 + 0.04 * j2 + 0.08 * end, 0.15 + 0.03 * j2)
		StreetVendors._ellipsoid(st, Vector3(x, hedge_y + 0.22 + 0.03 * j2 + 0.05 * end, pz + (j - 0.5) * 0.12), r, Basis(Vector3.UP, j * 3.0),
			leaf, Vector2(0.7, 0.0), 7, 4)
	# The end screens: two posts and horizontal cedar slats with gaps, a steel cap rail.
	var sz0 := 0.12
	var sz1 := DEPTH - PLANTER_D - 0.02
	for s: float in [-1.0, 1.0]:
		var x := s * (hx - 0.05)
		for z: float in [sz0 + 0.045, sz1 - 0.045]:
			_box(st, Vector3(x, DECK_Y + SCREEN_H * 0.5, z), Vector3(0.09, SCREEN_H, 0.09), 0.01, POST_WOOD, wood_rm)
		var slats := 9
		for k in slats:
			var y := DECK_Y + 0.12 + (SCREEN_H - 0.2) * (float(k) + 0.5) / float(slats)
			_box(st, Vector3(x, y, (sz0 + sz1) * 0.5), Vector3(0.03, 0.075, sz1 - sz0 - 0.1), 0.006, CEDAR, wood_rm)
		_box(st, Vector3(x, DECK_Y + SCREEN_H + 0.015, (sz0 + sz1) * 0.5), Vector3(0.06, 0.03, sz1 - sz0 + 0.02), 0.006, BLACK_STEEL, Vector2(0.45, 0.4))
	# The light posts (4 x 4 timber), a steel cap and an eye for the string.
	for top: Vector3 in post_tops(length):
		var foot := DECK_Y if top.z < 1.0 else DECK_Y + 0.1
		_box(st, Vector3(top.x, (foot + top.y + 0.05) * 0.5, top.z), Vector3(0.09, top.y + 0.05 - foot, 0.09), 0.01, POST_WOOD, wood_rm)
		_box(st, Vector3(top.x, top.y + 0.06, top.z), Vector3(0.11, 0.02, 0.11), 0.004, BLACK_STEEL, Vector2(0.45, 0.4))
		if top.z < 1.0:
			# A steel shoe bolting the pavement-side post to the deck.
			_box(st, Vector3(top.x, DECK_Y + 0.08, top.z), Vector3(0.12, 0.16, 0.12), 0.004, BLACK_STEEL, Vector2(0.45, 0.4))
	# The festoon: a cable sagging between the posts, a bulb in a socket every BULB_STEP.
	for pair: Array in strings(length):
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var span := a.distance_to(b)
		var sag := 0.05 * span
		var pts: Array = []
		var segs := maxi(6, int(span / 0.4))
		for i in segs + 1:
			pts.append(string_point(a, b, float(i) / segs, sag))
		StreetClutter._tube(st, pts, 0.004, 4, CABLE, Vector2(0.6, 0.0))
		var n := int(floor(span / BULB_STEP))
		for i in range(1, n):
			var p := string_point(a, b, float(i) / float(n), sag)
			StreetClutter._cyl(st, Transform3D(Basis(), p - Vector3(0.0, 0.045, 0.0)), 0.011, 0.011, 0.045, CABLE, Vector2(0.5, 0.0), 6)
			StreetVendors._ellipsoid(st, p - Vector3(0.0, 0.075, 0.0), Vector3(0.027, 0.036, 0.027), Basis(), Color(1, 0.9, 0.7, A_BULB), Vector2(0.15, 0.0), 6, 4)
	# Out on the road: a flexible delineator at each outer corner, a wheel stop before each end.
	for s: float in [-1.0, 1.0]:
		var dx := s * (hx + 0.35)
		var dz := DEPTH - 0.15
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(dx, 0.0, dz)), 0.12, 0.11, 0.05, BLACK_STEEL, Vector2(0.7, 0.0), 12)
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(dx, 0.05, dz)), 0.038, 0.034, 0.85, Color(0.92, 0.92, 0.9), Vector2(0.4, 0.0), 10)
		for band_y: float in [0.62, 0.76]:
			StreetClutter._cyl(st, Transform3D(Basis(), Vector3(dx, band_y, dz)), 0.037, 0.0365, 0.07, Color(0.95, 0.95, 0.93, A_REFLECT), Vector2(0.4, 0.0), 10)
		_box(st, Vector3(s * (hx + 0.95), 0.06, DEPTH * 0.5 + 0.1), Vector3(0.15, 0.11, 1.75), 0.03, RUBBER, Vector2(0.9, 0.0))
		for k in 2:
			_box(st, Vector3(s * (hx + 0.95), 0.112, DEPTH * 0.5 + 0.1 + (float(k) - 0.5) * 1.1), Vector3(0.1, 0.006, 0.16), 0.0, Color(0.95, 0.75, 0.1, A_REFLECT), Vector2(0.4, 0.0))
	return _finish(st, key)


## Where the plants go in a deck's planters (deck frame, the planters' soil), one every ~0.45 m.
static func plant_spots(length: float) -> Array:
	var out: Array = []
	var n := maxi(4, int(floor((length - 0.3) / 0.45)))
	var z := DEPTH - PLANTER_D * 0.5 - 0.02
	for i in n:
		out.append(Vector3(-length * 0.5 + 0.3 + (length - 0.6) * (float(i) + 0.5) / float(n), DECK_Y + PLANTER_H - 0.07, z))
	return out


## A bistro set: `square` a timber-topped square table (else a round marble one), the chairs'
## frames rattan-woven in the instance's paint; `laid` plates and glasses (else just the candle).
## `cafe` lays cups and pastries instead of dinner.
static func bistro_set(square: bool, laid: bool, cafe: bool) -> Mesh:
	var key := "set_%d%d%d" % [int(square), int(laid), int(cafe)]
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var steel_rm := Vector2(0.45, 0.5)
	var top_y := 0.74
	if square:
		_box(st, Vector3(0.0, top_y - 0.018, 0.0), Vector3(0.66, 0.036, 0.66), 0.006, Color(0.55, 0.36, 0.22, A_TIMBER), Vector2(0.55, 0.0))
		_box(st, Vector3(0.0, top_y - 0.05, 0.0), Vector3(0.56, 0.03, 0.56), 0.004, BLACK_STEEL, steel_rm)
	else:
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, top_y - 0.03, 0.0)), 0.33, 0.33, 0.03, Color(0.9, 0.89, 0.86, A_MARBLE), Vector2(0.22, 0.0), 24)
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, top_y - 0.045, 0.0)), 0.31, 0.33, 0.016, BLACK_STEEL, steel_rm, 24)
	# Pedestal: a column on a cross of feet.
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.04, 0.0)), 0.032, 0.026, top_y - 0.09, BLACK_STEEL, steel_rm, 10)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, top_y - 0.07, 0.0)), 0.05, 0.08, 0.02, BLACK_STEEL, steel_rm, 10)
	for k in 4:
		var b := Basis(Vector3.UP, PI * 0.25 + PI * 0.5 * float(k))
		StreetClutter._bbox(st, Transform3D(b, b * Vector3(0.0, 0.025, -0.13)), Vector3(0.05, 0.03, 0.27), 0.008, BLACK_STEEL, steel_rm)
		StreetClutter._cyl(st, Transform3D(b, b * Vector3(0.0, 0.0, -0.25)), 0.025, 0.025, 0.012, RUBBER, Vector2(0.9, 0.0), 8)
	# The chairs, facing the table.
	for s: float in [-1.0, 1.0]:
		_chair(st, Transform3D(Basis(Vector3.UP, -PI * 0.5 * s), Vector3(-s * CHAIR_X, 0.0, 0.0)))
	# On the table.
	var ty := top_y
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, ty, 0.0)), 0.034, 0.032, 0.075, Color(0.75, 0.82, 0.8, A_GLASS), Vector2(0.05, 0.0), 10)
	StreetVendors._ellipsoid(st, Vector3(0.0, ty + 0.035, 0.0), Vector3(0.012, 0.022, 0.012), Basis(), Color(1, 0.8, 0.5, A_FLAME), Vector2(0.5, 0.0), 6, 3)
	if laid:
		for s: float in [-1.0, 1.0]:
			var px := s * 0.17
			StreetClutter._cyl(st, Transform3D(Basis(), Vector3(px, ty, 0.0)), 0.115 if not cafe else 0.08, 0.12 if not cafe else 0.085, 0.016, Color(0.95, 0.95, 0.93, A_CHINA), Vector2(0.15, 0.0), 18)
			if cafe:
				# A cup on its saucer and a pastry.
				StreetClutter._cyl(st, Transform3D(Basis(), Vector3(px, ty + 0.016, 0.07)), 0.035, 0.042, 0.075, Color(0.95, 0.95, 0.93, A_CHINA), Vector2(0.15, 0.0), 12)
				StreetClutter._cyl(st, Transform3D(Basis(), Vector3(px, ty + 0.086, 0.07)), 0.037, 0.037, 0.002, Color(0.2, 0.11, 0.06), Vector2(0.2, 0.0), 12)
				StreetVendors._ellipsoid(st, Vector3(px, ty + 0.035, -0.02), Vector3(0.06, 0.025, 0.035), Basis(Vector3.UP, 0.4 * s), Color(0.78, 0.52, 0.24, A_FOOD), Vector2(0.6, 0.0), 8, 4)
			else:
				# Dinner on the plate, a wine glass and a water tumbler, cutlery either side.
				StreetVendors._ellipsoid(st, Vector3(px, ty + 0.03, 0.0), Vector3(0.07, 0.03, 0.06), Basis(Vector3.UP, s), Color(0.62, 0.4, 0.22, A_FOOD), Vector2(0.6, 0.0), 8, 4)
				StreetVendors._ellipsoid(st, Vector3(px - 0.03, ty + 0.035, 0.035), Vector3(0.035, 0.022, 0.03), Basis(), Color(0.25, 0.5, 0.15, A_FOOD), Vector2(0.6, 0.0), 6, 3)
				var gx := px + s * -0.02
				var gz := 0.17
				StreetClutter._cyl(st, Transform3D(Basis(), Vector3(gx, ty, gz)), 0.03, 0.03, 0.004, Color(0.75, 0.82, 0.8, A_GLASS), Vector2(0.05, 0.0), 10)
				StreetClutter._cyl(st, Transform3D(Basis(), Vector3(gx, ty, gz)), 0.004, 0.004, 0.09, Color(0.75, 0.82, 0.8, A_GLASS), Vector2(0.05, 0.0), 5)
				StreetClutter._cyl(st, Transform3D(Basis(), Vector3(gx, ty + 0.09, gz)), 0.022, 0.038, 0.06, Color(0.4, 0.06, 0.08, A_GLASS), Vector2(0.05, 0.0), 10)
				StreetClutter._cyl(st, Transform3D(Basis(), Vector3(gx, ty + 0.15, gz)), 0.038, 0.034, 0.05, Color(0.75, 0.82, 0.8, A_GLASS), Vector2(0.05, 0.0), 10)
				StreetClutter._cyl(st, Transform3D(Basis(), Vector3(px + s * 0.06, ty, -0.18)), 0.03, 0.033, 0.1, Color(0.75, 0.82, 0.8, A_GLASS), Vector2(0.05, 0.0), 10)
				for c: float in [-1.0, 1.0]:
					_box(st, Vector3(px, ty + 0.004, c * 0.15), Vector3(0.16, 0.006, 0.018), 0.0, Color(0.7, 0.7, 0.72), Vector2(0.2, 0.9))
			# A folded napkin.
			_box(st, Vector3(px + s * 0.02, ty + 0.006, -0.15 if not cafe else 0.16), Vector3(0.1, 0.012, 0.06), 0.003, Color(0.93, 0.92, 0.88), Vector2(0.8, 0.0))
	return _finish(st, key)


## A bistro chair in its own frame: seat centre at the origin's x/z, facing -z (the table), seat
## top SEAT_Y. A bent aluminium frame in a bamboo finish, the seat and back rattan-woven.
static func _chair(st: SurfaceTool, xf: Transform3D) -> void:
	var frame := Color(0.55, 0.38, 0.22, A_TIMBER)
	var frm := Vector2(0.5, 0.0)
	var weave := Color(0.86, 0.8, 0.66, A_RATTAN)
	var hw := 0.21
	var hd := 0.2
	var y := SEAT_Y
	# Seat panel and its rim.
	var c := [Vector3(-hw, y, -hd), Vector3(hw, y, -hd), Vector3(hw, y, hd), Vector3(-hw, y, hd)]
	StreetClutter._quad(st, xf * c[0], xf * c[1], xf * c[2], xf * c[3], xf.basis * Vector3.UP, weave, Vector2(0.7, 0.0))
	StreetClutter._quad(st, xf * (c[0] - Vector3(0, 0.025, 0)), xf * (c[1] - Vector3(0, 0.025, 0)), xf * (c[2] - Vector3(0, 0.025, 0)), xf * (c[3] - Vector3(0, 0.025, 0)), xf.basis * Vector3.DOWN, weave, Vector2(0.7, 0.0))
	var rim: Array = []
	for i in 13:
		var a := TAU * float(i) / 12.0
		var p := Vector3(cos(a) * hw, y - 0.012, sin(a) * hd)
		# A rounded square: pushed out toward the corners.
		p.x = signf(p.x) * minf(absf(p.x) * 1.25, hw)
		p.z = signf(p.z) * minf(absf(p.z) * 1.25, hd)
		rim.append(xf * p)
	StreetClutter._tube(st, rim, 0.013, 6, frame, frm)
	# Legs, splayed a little, front pair straight up into the seat, back pair rising into the back.
	for sx: float in [-1.0, 1.0]:
		StreetClutter._tube(st, [xf * Vector3(sx * (hw - 0.02), y - 0.02, -hd + 0.02), xf * Vector3(sx * (hw + 0.01), 0.0, -hd - 0.01)], 0.013, 6, frame, frm)
		StreetClutter._tube(st, [xf * Vector3(sx * (hw + 0.02), 0.0, hd + 0.04), xf * Vector3(sx * (hw - 0.01), y, hd - 0.01), xf * Vector3(sx * (hw - 0.02), y + 0.22, hd + 0.03), xf * Vector3(sx * (hw - 0.05), y + 0.4, hd + 0.06)], 0.013, 6, frame, frm)
	# A stretcher ring.
	var ring: Array = []
	for i in 13:
		var a := TAU * float(i) / 12.0
		ring.append(xf * Vector3(cos(a) * (hw + 0.005), 0.2, sin(a) * (hd + 0.01)))
	StreetClutter._tube(st, ring, 0.009, 5, frame, frm)
	# The back: a curved top rail, and a woven panel under it.
	var rail: Array = []
	var panel_hi: Array = []
	var panel_lo: Array = []
	for i in 9:
		var t := float(i) / 8.0
		var a := lerpf(-0.95, 0.95, t)
		var p := Vector3(sin(a) * (hw - 0.03), y + 0.4, hd + 0.06 - (1.0 - cos(a)) * 0.08)
		rail.append(xf * p)
		panel_hi.append(xf * (p - Vector3(0.0, 0.03, 0.0)))
		panel_lo.append(xf * (p - Vector3(0.0, 0.16, 0.01)))
	StreetClutter._tube(st, rail, 0.014, 6, frame, frm)
	for i in 8:
		var n := xf.basis * Vector3(0.0, 0.0, -1.0)
		StreetClutter._quad(st, panel_hi[i], panel_hi[i + 1], panel_lo[i + 1], panel_lo[i], n, weave, Vector2(0.7, 0.0))
		StreetClutter._quad(st, panel_hi[i], panel_hi[i + 1], panel_lo[i + 1], panel_lo[i], -n, weave, Vector2(0.7, 0.0))


## A square market umbrella over a table: pole from the deck through the table, four canvas
## panels sagging between their ribs and a valance; furled, the canvas wrapped round the pole.
static func umbrella(open: bool) -> Mesh:
	var key := "umbrella_%d" % int(open)
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var pole := Color(0.55, 0.38, 0.22, A_TIMBER)
	var canvas := Color(0.5, 0.5, 0.5, A_CANVAS)
	var crm := Vector2(0.88, 0.0)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), 0.022, 0.02, 2.5, pole, Vector2(0.5, 0.0), 10)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 2.5, 0.0)), 0.025, 0.004, 0.12, BLACK_STEEL, Vector2(0.4, 0.5), 8)
	if open:
		var apex := Vector3(0.0, 2.48, 0.0)
		var half := 1.08
		var rim_y := 2.12
		var segs := 4
		for p in 4:
			var a0 := PI * 0.5 * float(p) + PI * 0.25
			var a1 := a0 + PI * 0.5
			var r := half * sqrt(2.0)
			var e0 := Vector3(cos(a0) * r, rim_y, sin(a0) * r)
			var e1 := Vector3(cos(a1) * r, rim_y, sin(a1) * r)
			var mid := (e0 + e1) * 0.5
			var outward := (mid * Vector3(1, 0, 1)).normalized()
			var rows: Array = []
			for s in segs + 1:
				var f := float(s) / segs
				var sag := 0.045 * f
				rows.append([apex.lerp(e0, f), apex.lerp(mid, f) - Vector3(0.0, sag, 0.0), apex.lerp(e1, f)])
			for s in segs:
				var r0: Array = rows[s]
				var r1: Array = rows[s + 1]
				for k in 2:
					var up := outward + Vector3(0.0, 2.4, 0.0)
					StreetClutter._quad(st, r0[k], r0[k + 1], r1[k + 1], r1[k], up, canvas, crm)
					StreetClutter._quad(st, r0[k], r0[k + 1], r1[k + 1], r1[k], -up, canvas, crm)
			# The valance: a straight skirt round each edge.
			var drop := Vector3(0.0, -0.16, 0.0)
			var m: Vector3 = rows[segs][1]
			for k in 2:
				var ea: Vector3 = [e0, m][k]
				var eb: Vector3 = [m, e1][k]
				StreetClutter._quad(st, ea, eb, eb + drop, ea + drop, outward, canvas, crm)
				StreetClutter._quad(st, ea, eb, eb + drop, ea + drop, -outward, canvas, crm)
			# A rib under the seam and its stretcher to the pole's runner.
			StreetClutter._tube(st, [apex + Vector3(0.0, -0.02, 0.0), e0 + Vector3(0.0, -0.01, 0.0)], 0.008, 4, pole, Vector2(0.5, 0.0))
			StreetClutter._tube(st, [Vector3(0.0, 1.95, 0.0), apex.lerp(e0, 0.5) + Vector3(0.0, -0.02, 0.0)], 0.006, 4, pole, Vector2(0.5, 0.0))
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 1.92, 0.0)), 0.035, 0.035, 0.08, BLACK_STEEL, Vector2(0.4, 0.5), 8)
	else:
		# Furled: the canvas in soft folds round the top of the pole, tied with a strap.
		var rings := 6
		var sides := 8
		var prof := [0.025, 0.07, 0.095, 0.085, 0.06, 0.035, 0.02]
		var y0 := 1.3
		var y1 := 2.47
		for i in rings:
			for k in sides:
				var a0 := TAU * float(k) / sides
				var a1 := TAU * float(k + 1) / sides
				var ya := lerpf(y0, y1, float(i) / rings)
				var yb := lerpf(y0, y1, float(i + 1) / rings)
				var ra: float = prof[i] * (1.0 + 0.12 * float(k % 2))
				var rb: float = prof[i + 1] * (1.0 + 0.12 * float(k % 2))
				var p00 := Vector3(cos(a0) * ra, ya, sin(a0) * ra)
				var p10 := Vector3(cos(a1) * ra, ya, sin(a1) * ra)
				var p01 := Vector3(cos(a0) * rb, yb, sin(a0) * rb)
				var p11 := Vector3(cos(a1) * rb, yb, sin(a1) * rb)
				var n := Vector3(cos((a0 + a1) * 0.5), 0.15, sin((a0 + a1) * 0.5))
				StreetClutter._quad(st, p00, p10, p11, p01, n, canvas, crm)
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 1.78, 0.0)), 0.093, 0.093, 0.04, canvas, crm, 10)
	return _finish(st, key)


## Builds every mesh once (the loading screen), so the first parklet does not stall, and hands
## back the material to draw once through a MultiMesh.
static func warm() -> Array:
	for l: float in LENGTHS:
		deck(l)
	for sq in 2:
		for laid in 2:
			for cafe in 2:
				bistro_set(sq == 1, laid == 1, cafe == 1)
	umbrella(true)
	umbrella(false)
	return [material()]
