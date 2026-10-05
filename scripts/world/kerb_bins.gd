class_name KerbBins
extends RefCounted
## The wheelie bins at the kerb on collection day: three carts per house - black (trash), blue
## (recycling), green (yard waste), as Los Angeles puts them out - standing in the gutter in front
## of each suburban and beach-town house, on the streets whose collection day it is. Worked out,
## never placed (like the bus stops): a street's day is a hash of seed + street + weekday, each
## house's set stands where its lot fronts the street, snapped to the stall line between two
## parking bays so the parked cars stand either side of it. ServiceFleet draws them round the
## player and sends the garbage trucks down the streets that have them out; the trucks' arms
## (ServiceVehicles.GarbageArm) pick each cart up and tip it.

## Carts, in the order their colours are listed: trash, recycling, yard waste.
const COLORS := [Color(0.10, 0.10, 0.11), Color(0.10, 0.27, 0.62), Color(0.17, 0.42, 0.18)]
const STREAM_NAMES := ["trash", "recycling", "yard waste"]
## Share of residential streets (per weekday) with their bins out.
const OUT_PERCENT := 40
## A cart: width across its front, depth front to back, height to the lid's top (m).
const WIDTH := 0.62
const DEPTH := 0.74
const HEIGHT := 1.07
## Carts in a set stand this far apart along the kerb (centre to centre).
const PITCH := 0.72
## Their centre this far out from the kerb face into the gutter (18 inches and half a cart).
const KERB_OFF := 0.45 + DEPTH * 0.5
## Parking bays along the kerb (CityChunk._park_car_steps): the stall lines are this far apart,
## the first this far past the block's edge.
const STALL := 8.0
const STALL_FIRST := 12.0
## A set keeps this far from the crossing roads' kerbs.
const CORNER_CLEAR := 7.0
## Parked cars longer than this cannot stand in a bay next to a set (CityChunk asks blocks_parking()).
const LONG_CAR := 5.6

## SERVICE_VEHICLES=0 in the environment: no carts anywhere (the A/B; ServiceFleet reads it too).
static var enabled: bool = OS.get_environment("SERVICE_VEHICLES") != "0"

static var _block_cache: Dictionary = {}
static var _cache_seed: int = -1
static var _meshes: Dictionary = {}
static var _material: ShaderMaterial = null


## True when road (axis, index) has its carts out on `weekday` (0..6).
static func street_out(plan: CityPlan, axis: int, index: int, weekday: int) -> bool:
	return absi(hash([plan.seed, axis, index, posmod(weekday, 7), "bins"])) % 100 < OUT_PERCENT


## Every house's cart set round block (bx, bz), whatever the day: [{"axis", "index", "side" (+1:
## the block is on the +x / +z side of the road), "along", "lateral" (the carts' line, true world),
## "id", "order" (which colour stands first)}]. Empty for anything but a house block.
static func block_sets(plan: CityPlan, bx: int, bz: int) -> Array:
	if _cache_seed != plan.seed:
		_block_cache.clear()
		_cache_seed = plan.seed
	var key := Vector2i(bx, bz)
	if _block_cache.has(key):
		return _block_cache[key]
	var out := _plan_block(plan, bx, bz)
	if _block_cache.size() > 4000:
		_block_cache.clear()
	_block_cache[key] = out
	return out


static func _plan_block(plan: CityPlan, bx: int, bz: int) -> Array:
	var out: Array = []
	var b := plan.block(bx, bz)
	if b.has("site") or int(b.kind) != CityPlan.BlockKind.BUILDINGS or not (int(b.district) in HouseKit.DISTRICTS):
		return out
	if plan.macro and plan.macro.replica and plan.macro.replica.block_role(plan, bx, bz) != 0:
		return out
	var lots: Array = []
	lots.append_array(plan.lots(bx, bz))
	if lots.is_empty():
		return out
	lots.append_array(HouseKit.extra_lots(plan, bx, bz))
	var grid := YardFill.lot_grid(plan, bx, bz, lots)
	var inner: Rect2 = grid.inner
	var seen := {}
	for lot: Dictionary in lots:
		if lot.get("parking", false) or YardFill.is_corridor(plan, lot):
			continue
		var cell: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
		var side := YardFill.nearest_side(inner, cell)
		var axis: int
		var index: int
		var s: float
		var lo: float
		var hi: float
		match side:
			0:
				axis = CityPlan.AXIS_Z; index = bz; s = 1.0; lo = cell.position.x; hi = cell.end.x
			1:
				axis = CityPlan.AXIS_Z; index = bz + 1; s = -1.0; lo = cell.position.x; hi = cell.end.x
			2:
				axis = CityPlan.AXIS_X; index = bx; s = 1.0; lo = cell.position.y; hi = cell.end.y
			_:
				axis = CityPlan.AXIS_X; index = bx + 1; s = -1.0; lo = cell.position.y; hi = cell.end.y
		# Beside the driveway: a third of the lot's frontage one way or the other, then onto the
		# nearest stall line of this stretch of kerb.
		var h := absi(hash([plan.seed, bx, bz, lot.get("seed", 0), "binset"]))
		var along := (lo + hi) * 0.5 + (hi - lo) * 0.28 * (1.0 if h & 1 else -1.0)
		along = snap_to_stall(plan, axis, index, along)
		if is_nan(along):
			continue
		var road := plan.road_pos(axis, index)
		var lateral := road + s * (plan.road_width(axis, index) * 0.5 - KERB_OFF)
		var p := Vector2(lateral, along) if axis == CityPlan.AXIS_X else Vector2(along, lateral)
		if plan.zone_at(p) != MacroMap.Zone.CITY or not plan.road_open(axis, index, along):
			continue
		var id := absi(hash([plan.seed, axis, index, roundi(along * 4.0), int(s)]))
		if seen.has(id):
			continue
		seen[id] = true
		out.append({"axis": axis, "index": index, "side": s, "along": along, "lateral": lateral, "id": id,
			"order": (h >> 3) % 3})
	return out


## `along` on road (axis, index) moved onto the nearest stall line between two parking bays of its
## stretch of kerb, or NAN when the stretch has none clear of its corners.
static func snap_to_stall(plan: CityPlan, axis: int, index: int, along: float) -> float:
	var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var j := plan._index_at(cross, along)
	var start := plan.road_pos(cross, j) + plan.road_width(cross, j) * 0.5
	var stop := plan.road_pos(cross, j + 1) - plan.road_width(cross, j + 1) * 0.5
	var lo := start + CORNER_CLEAR
	var hi := stop - CORNER_CLEAR
	if hi <= lo:
		return NAN
	var k := roundf((along - start - STALL_FIRST) / STALL)
	var t := start + STALL_FIRST + k * STALL
	if t < lo:
		t += STALL
	if t > hi:
		t -= STALL
	if t < lo or t > hi:
		return NAN
	return t


## Where cart `k` (0..2, in the set's order) of a set stands, true world XZ, and the way its front
## faces (toward the middle of the road).
static func cart_pos(plan: CityPlan, set_: Dictionary, k: int) -> Vector2:
	var along: float = float(set_.along) + (float(k) - 1.0) * PITCH
	var lat: float = set_.lateral
	return Vector2(lat, along) if int(set_.axis) == CityPlan.AXIS_X else Vector2(along, lat)


## The colour index of cart `k` of a set.
static func cart_color(set_: Dictionary, k: int) -> int:
	return (k + int(set_.order)) % 3


## The cart's front faces the road's centre: its local -X along this.
static func cart_facing(set_: Dictionary) -> Vector2:
	var s: float = set_.side
	return Vector2(-s, 0.0) if int(set_.axis) == CityPlan.AXIS_X else Vector2(0.0, -s)


## Every set within `radius` of `p` (true world XZ), from the blocks round it.
static func sets_near(plan: CityPlan, p: Vector2, radius: float) -> Array:
	var out: Array = []
	var a := plan.block_index_at(p - Vector2(radius, radius))
	var b := plan.block_index_at(p + Vector2(radius, radius))
	for bz in range(a.y - 1, b.y + 1):
		for bx in range(a.x - 1, b.x + 1):
			for st: Dictionary in block_sets(plan, bx, bz):
				var c := cart_pos(plan, st, 1)
				if c.distance_to(p) <= radius:
					out.append(st)
	return out


## A parked car in the bay at `spot` (true world, the bay's centre) `length` long would stand
## in a cart set (any day's: a car parked overnight stays). CityChunk._park_car() asks, after its
## rolls; a car of an ordinary length fits between two sets.
static func blocks_parking(plan: CityPlan, spot: Vector3, length: float) -> bool:
	if length < LONG_CAR or not enabled:
		return false
	var p := Vector2(spot.x, spot.z)
	for st: Dictionary in sets_near(plan, p, 8.0):
		var c := cart_pos(plan, st, 1)
		var d := c - p
		var axis: int = st.axis
		var along := absf(d.y) if axis == CityPlan.AXIS_X else absf(d.x)
		var across := absf(d.x) if axis == CityPlan.AXIS_X else absf(d.y)
		if across < 2.2 and along < length * 0.5 + PITCH + WIDTH * 0.5:
			return true
	return false


# --- The cart --------------------------------------------------------------------------------------

## The cart's mesh, its origin at the middle of its base, its front toward -X, its hinge and
## wheels at +X. `lod` 0: the moulded cart (body with its taper and ribs, the rim, the lid with its
## lip, the handle bar over the hinge, the wheels on their axle, the label); 1: a tapered box and
## a lid. `part` "all", or "body" / "lid" (the lid alone, its origin on the hinge) for the cart an
## arm carries, whose lid falls open.
## Vertex alpha says what a face is (kerb_bin.gdshader): 1 body, 0.8 lid, 0.6 rubber, 0.4 steel,
## 0.2 the label.
static func mesh(lod: int, part: String = "all") -> Mesh:
	var key := "%d_%s" % [lod, part]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if part != "lid":
		_body(st, lod)
	if part != "body":
		var off := Vector3.ZERO if part == "all" else -hinge()
		_lid(st, lod, off)
	st.generate_normals()
	var m := st.commit()
	_meshes[key] = m
	return m


## The lid's hinge, in cart space.
static func hinge() -> Vector3:
	return Vector3(DEPTH * 0.5 + 0.015, HEIGHT - 0.045, 0.0)


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/kerb_bin.gdshader")
	return _material


static func _c(kind: float) -> Color:
	return Color(1.0, 1.0, 1.0, kind)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, kind: float) -> void:
	st.set_color(_c(kind))
	st.set_smooth_group(0xffffffff)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)


## A quad facing the way its winding says (counter-clockwise seen from outside).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, kind: float) -> void:
	_tri(st, a, c, b, kind)
	_tri(st, a, d, c, kind)


## A ring of the body's rounded-rectangle plan at height y: half depth hx, half width hz, corner
## radius r, `n` points a corner. Anticlockwise seen from above.
static func _ring(y: float, hx: float, hz: float, r: float, n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var corners := [Vector2(hx - r, hz - r), Vector2(-hx + r, hz - r), Vector2(-hx + r, -hz + r), Vector2(hx - r, -hz + r)]
	var start := [0.0, 90.0, 180.0, 270.0]
	for i in 4:
		for k in n + 1:
			var a := deg_to_rad(float(start[i]) + (90.0 * float(k) / float(n) if n > 0 else 45.0))
			var c: Vector2 = corners[i]
			pts.append(Vector3(c.x + cos(a) * r, y, c.y + sin(a) * r))
	return pts


static func _loft(st: SurfaceTool, a: PackedVector3Array, b: PackedVector3Array, kind: float) -> void:
	var n := a.size()
	for i in n:
		var j := (i + 1) % n
		_quad(st, a[i], a[j], b[j], b[i], kind)


static func _cap(st: SurfaceTool, ring: PackedVector3Array, up: bool, kind: float) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	for i in ring.size():
		var j := (i + 1) % ring.size()
		if up:
			_tri(st, c, ring[j], ring[i], kind)
		else:
			_tri(st, c, ring[i], ring[j], kind)


static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, kind: float) -> void:
	var p := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	_quad(st, p[0], p[1], p[2], p[3], kind)
	_quad(st, p[4], p[7], p[6], p[5], kind)
	_quad(st, p[0], p[4], p[5], p[1], kind)
	_quad(st, p[1], p[5], p[6], p[2], kind)
	_quad(st, p[2], p[6], p[7], p[3], kind)
	_quad(st, p[3], p[7], p[4], p[0], kind)


## A cylinder along Z (wheels, the axle, the handle bar).
static func _zcyl(st: SurfaceTool, c: Vector3, r: float, z0: float, z1: float, n: int, kind: float) -> void:
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	for k in n:
		var t := TAU * float(k) / float(n)
		a.append(Vector3(c.x + cos(t) * r, c.y + sin(t) * r, z0))
		b.append(Vector3(c.x + cos(t) * r, c.y + sin(t) * r, z1))
	for k in n:
		var j := (k + 1) % n
		_quad(st, a[k], b[k], b[j], a[j], kind)
	_cap(st, a, false, kind)
	_cap(st, b, true, kind)
	# The caps' winding: z1 faces +Z.


static func _body(st: SurfaceTool, lod: int) -> void:
	var hx0 := DEPTH * 0.5 - 0.07
	var hz0 := WIDTH * 0.5 - 0.06
	var hx1 := DEPTH * 0.5 - 0.01
	var hz1 := WIDTH * 0.5 - 0.01
	var top := HEIGHT - 0.075
	if lod >= 1:
		var r0 := _ring(0.05, hx0, hz0, 0.0, 0)
		var r1 := _ring(top, hx1, hz1, 0.0, 0)
		_loft(st, r0, r1, 1.0)
		_cap(st, r0, false, 1.0)
		return
	var n := 3
	# Body: the foot, the taper up to the rim, the rim's flare (a lip all round), under the lid.
	var rings := [
		_ring(0.03, hx0 - 0.01, hz0 - 0.01, 0.05, n), _ring(0.07, hx0, hz0, 0.06, n),
		_ring(top * 0.55, lerpf(hx0, hx1, 0.55), lerpf(hz0, hz1, 0.55), 0.075, n),
		_ring(top - 0.05, hx1, hz1, 0.08, n), _ring(top - 0.045, hx1 + 0.018, hz1 + 0.018, 0.09, n),
		_ring(top, hx1 + 0.018, hz1 + 0.018, 0.09, n), _ring(top + 0.002, hx1 - 0.02, hz1 - 0.02, 0.07, n),
	]
	for i in rings.size() - 1:
		_loft(st, rings[i], rings[i + 1], 1.0)
	_cap(st, rings[0], false, 1.0)
	_cap(st, rings[rings.size() - 1], true, 1.0)
	# Moulded ribs: two vertical ribs down each side, a horizontal one round the front.
	for sz: float in [-1.0, 1.0]:
		for x: float in [-0.14, 0.12]:
			var y0 := 0.12
			var y1 := top - 0.10
			var z0 := lerpf(hz0, hz1, y0 / top) * sz
			var z1 := lerpf(hz0, hz1, y1 / top) * sz
			var d := 0.012 * sz
			var w := 0.025
			_quad(st, Vector3(x - w, y0, z0 + d), Vector3(x + w, y0, z0 + d), Vector3(x + w, y1, z1 + d), Vector3(x - w, y1, z1 + d), 1.0) if sz > 0 \
				else _quad(st, Vector3(x + w, y0, z0 + d), Vector3(x - w, y0, z0 + d), Vector3(x - w, y1, z1 + d), Vector3(x + w, y1, z1 + d), 1.0)
	# The label on the front, a hand grip moulded under the front lip.
	var fx := -lerpf(hx0, hx1, 0.62) - 0.004
	_quad(st, Vector3(fx, top * 0.50, 0.12), Vector3(fx, top * 0.50, -0.12), Vector3(fx, top * 0.66, -0.12), Vector3(fx, top * 0.66, 0.12), 0.2)
	# The tipping bar across the front foot (the grabber's lower claw seats under it).
	_box(st, Vector3(-hx0 - 0.03, 0.10, -hz0 + 0.04), Vector3(-hx0 + 0.01, 0.14, hz0 - 0.04), 1.0)
	# Wheels on their axle at the back foot, the axle housing, the handle bar over the hinge.
	var wr := 0.13
	var wc := Vector3(hx0 + 0.02, wr + 0.005, 0.0)
	_zcyl(st, wc, wr, hz0 - 0.03, hz0 + 0.04, 12, 0.6)
	_zcyl(st, wc, wr, -hz0 - 0.04, -hz0 + 0.03, 12, 0.6)
	_zcyl(st, wc, wr * 0.45, -hz0 + 0.03, hz0 - 0.03, 8, 0.4)
	_box(st, Vector3(hx0 - 0.06, 0.06, -hz0 + 0.02), Vector3(hx0 + 0.05, 0.22, hz0 - 0.02), 1.0)
	_zcyl(st, Vector3(hx1 + 0.06, top + 0.012, 0.0), 0.022, -hz1 + 0.02, hz1 - 0.02, 8, 1.0)
	for sz: float in [-1.0, 1.0]:
		var z := (hz1 - 0.02) * sz
		_box(st, Vector3(hx1 - 0.02, top - 0.10, z - 0.025), Vector3(hx1 + 0.08, top + 0.02, z + 0.025), 1.0)


static func _lid(st: SurfaceTool, lod: int, off: Vector3) -> void:
	var hx := DEPTH * 0.5 + 0.008
	var hz := WIDTH * 0.5 + 0.012
	var y0 := HEIGHT - 0.075
	if lod >= 1:
		_box(st, Vector3(-hx, y0, -hz) + off, Vector3(hx, HEIGHT, hz) + off, 0.8)
		return
	# A shallow dome with a skirt down round its edge and a lip at the front to lift it by.
	var a := _ring(y0 - 0.015, hx, hz, 0.09, 3)
	var b := _ring(y0 + 0.035, hx, hz, 0.09, 3)
	var c := _ring(HEIGHT - 0.008, hx - 0.03, hz - 0.03, 0.07, 3)
	var d := _ring(HEIGHT, hx - 0.08, hz - 0.08, 0.04, 3)
	for r: PackedVector3Array in [a, b, c, d]:
		for i in r.size():
			r[i] += off
	_loft(st, a, b, 0.8)
	_loft(st, b, c, 0.8)
	_loft(st, c, d, 0.8)
	_cap(st, d, true, 0.8)
	_cap(st, a, false, 0.8)
	_box(st, Vector3(-hx - 0.035, y0 - 0.02, -0.15) + off, Vector3(-hx + 0.01, y0 + 0.03, 0.15) + off, 0.8)
