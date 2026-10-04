class_name StreetVendors
extends RefCounted
## The people who sell food on Los Angeles pavements (GAME_PLAN G5 / VISUAL_ROADMAP #50): taco
## trucks parked at the kerb after dark with a lit menu board, the serving window open under its
## propped flap, the generator humming on the back and a few people waiting; fruit carts and
## elote carts under big striped umbrellas by day; bacon-wrapped hot dog carts with a string of
## bulbs outside the arena and the bars at night; paleta push carts in the parks; flower and
## balloon sellers at the downtown corners.
##
## Every mesh is built here in code at real size (bevelled steel, tubes, the truck's panels cut
## round its window, real lettering from TextMesh) on one shader (shaders/street_vendor.gdshader)
## that takes paint from the instance custom data and what each face is from the vertex colour's
## alpha, so a chunk's carts of one kind are one draw call. Names and menus are invented.
##
## A taco truck is a static prop on the chunk's StreetProps body (CityChunk._add_prop) that
## nothing can break: a round sparks off it like any steel. A cart is an EncampmentItem, so a
## bullet, a car or a blast tips it over as a real body and it stays gone (WorldState).
##
## Who sells and when: by place (downtown, midtown, the industrial blocks' lunch trucks, the
## parks, the faces across from MacArthur Park, round the arena, the beach town by the
## boardwalk) and by the hour the chunk is built at - trucks mostly at night, carts by day - all
## from hashes of the seed, block and face, never the chunk's random stream. The vendor is a crowd
## rig (StreetVendor) at the cart or in the truck; customers are walkers who stop and wait at the
## queue spots (Pedestrian._plan_queue(), the crowd's life). Static: call with the chunk.

enum Kind { TRUCK, FRUIT, ELOTE, HOTDOG, PALETA, FLOWERS }
enum Place { NONE, DOWNTOWN, MIDTOWN, INDUSTRIAL, PARK, MACARTHUR, ARENA, BEACH }

# --- Tunables --------------------------------------------------------------------------------

## Chance per block face that a vendor of each kind works it, by place:
## [truck, fruit, elote, hotdog, paleta, flowers]. A face rolls every kind and keeps at most
## one cart and one truck; the hours (SCHEDULE) decide who is there now.
const ODDS := {
	Place.DOWNTOWN: [0.22, 0.12, 0.07, 0.14, 0.03, 0.12],
	Place.MIDTOWN: [0.1, 0.06, 0.05, 0.04, 0.03, 0.02],
	Place.INDUSTRIAL: [0.16, 0.03, 0.02, 0.0, 0.0, 0.0],
	Place.PARK: [0.1, 0.3, 0.25, 0.1, 0.45, 0.05],
	Place.MACARTHUR: [0.45, 0.55, 0.45, 0.25, 0.35, 0.1],
	Place.ARENA: [0.32, 0.12, 0.1, 0.45, 0.05, 0.08],
	Place.BEACH: [0.12, 0.25, 0.12, 0.05, 0.3, 0.04],
}
## Hours each kind works, [open, close] (close past midnight is fine: 2.5 is 02:30), and how far
## a vendor's own day is shifted from it (hashed, +- this many hours).
const SCHEDULE := {
	Kind.TRUCK: [17.5, 2.0],
	Kind.FRUIT: [9.0, 18.0],
	Kind.ELOTE: [14.0, 22.5],
	Kind.HOTDOG: [19.0, 2.5],
	Kind.PALETA: [11.0, 19.0],
	Kind.FLOWERS: [8.0, 19.5],
}
const SCHEDULE_JITTER := 1.0
## Share of trucks that work the lunch trade instead (10:30-15:00), on the industrial blocks most.
const LUNCH_TRUCKS := 0.25
const LUNCH_TRUCKS_INDUSTRIAL := 0.85
## Most vendors on one block, and how far from an arena's anchor its crowd's vendors stand.
const MAX_PER_BLOCK := 3
const ARENA_REACH := 430.0
const BOARDWALK_REACH := 650.0
## Clearance from what already stands on the pavement (lamps, trees, cans, benches, camps).
const CLEAR := 0.5
## Metres from the kerb to a cart's middle, and to where its customers stand.
const CART_IN := 1.55
const QUEUE_IN := 2.75
## How far each kind draws (m) and casts.
const TRUCK_DRAW := 230.0
const CART_DRAW := 150.0
const UMBRELLA_DRAW := 170.0
const SHADOW_DISTANCE := 70.0
## Share of the walkers near a free queue spot who go and wait at it (Pedestrian._plan_queue()).
const QUEUE_SHARE := 0.55
## How long a customer waits (s).
const QUEUE_SECONDS := Vector2(12.0, 40.0)
## A truck's footprint along the parking lane, for the parked cars to keep out of (m, half).
const TRUCK_HALF := 4.6
## The light a truck's window and a hot dog cart's bulbs throw on the pavement after dark.
const TRUCK_POOL := Color(1.0, 0.93, 0.82, 0.95)
const BULB_POOL := Color(1.0, 0.72, 0.42, 0.85)

## Batch keys (one draw call each per chunk).
const K_TRUCK := "vend_truck_"
const K_UMBRELLA := "vend_umbrella"
const CART_KEYS := {Kind.FRUIT: "vend_fruit", Kind.ELOTE: "vend_elote", Kind.HOTDOG: "vend_hotdog", Kind.PALETA: "vend_paleta", Kind.FLOWERS: "vend_flowers"}

# Vertex colour alpha codes, read by shaders/street_vendor.gdshader (round(a * 20)).
const A_FIXED := 0.0
const A_STEEL := 0.1
const A_CANVAS := 0.2
const A_GLOW := 0.3
const A_PHOTO := 0.35
const A_INTERIOR := 0.45
const A_BULB := 0.55
const A_GLASS := 0.65
const A_FOOD := 0.75
const A_LED := 0.85
const A_PAINT := 1.0

## The trucks: invented names and menus, their livery's lettering and band colours and the body
## paints they come in.
const TRUCKS := [
	{"name": "TACOS EL COMPA CHUY", "ink": Color(0.72, 0.08, 0.06), "band": Color(0.12, 0.45, 0.2), "paints": [Color(0.93, 0.93, 0.9), Color(0.96, 0.9, 0.72)],
		"menu": ["TACOS  $2.50", "BURRITOS  $12", "QUESADILLAS  $9", "MULITAS  $5", "TORTAS  $11", "VAMPIROS  $5", "ASADA · PASTOR · POLLO", "CARNITAS · LENGUA · CABEZA"]},
	{"name": "MARISCOS EL FARO AZUL", "ink": Color(0.06, 0.2, 0.55), "band": Color(0.1, 0.55, 0.62), "paints": [Color(0.93, 0.94, 0.95), Color(0.82, 0.9, 0.95)],
		"menu": ["TOSTADA CEVICHE  $5", "COCTEL CAMARÓN  $14", "AGUACHILE  $16", "TACOS GOBERNADOR  $4", "CAMPECHANA  $17", "AGUA DE COCO  $5"]},
	{"name": "TAQUERÍA LA ESTRELLITA", "ink": Color(0.08, 0.3, 0.14), "band": Color(0.75, 0.12, 0.08), "paints": [Color(0.95, 0.91, 0.8), Color(0.93, 0.93, 0.9)],
		"menu": ["TACOS  $2.75", "BURRITO  $11", "SUPER QUESADILLA  $10", "TORTA  $11", "NACHOS  $9", "AL PASTOR DEL TROMPO", "HORCHATA · JAMAICA  $4"]},
	{"name": "BIRRIA LA CHAPARRITA", "ink": Color(0.97, 0.93, 0.8), "band": Color(0.95, 0.72, 0.15), "paints": [Color(0.42, 0.06, 0.07), Color(0.2, 0.05, 0.05)],
		"menu": ["TACOS DE BIRRIA  $3", "QUESABIRRIA  $4", "MULITA  $5", "CONSOMÉ  $4", "RAMEN DE BIRRIA  $12", "3 TACOS + CONSOMÉ  $13"]},
	{"name": "LOS PRIMOS TACOS & MÁS", "ink": Color(0.07, 0.07, 0.08), "band": Color(0.8, 0.1, 0.06), "paints": [Color(0.96, 0.78, 0.12), Color(0.95, 0.62, 0.1)],
		"menu": ["TACOS  $2.50", "BURRITOS  $12", "FRIES DE ASADA  $13", "QUESADILLAS  $9", "LOADED NACHOS  $11", "AGUAS FRESCAS  $4"]},
	{"name": "EL REY DEL ASADA", "ink": Color(0.95, 0.75, 0.25), "band": Color(0.7, 0.08, 0.06), "paints": [Color(0.06, 0.06, 0.07), Color(0.1, 0.12, 0.2)],
		"menu": ["TACOS ASADA  $3", "BURRITO ASADA  $13", "PAPAS LOCAS  $11", "QUESATACOS  $4", "TORTA ASADA  $12", "CEBOLLITAS · RÁBANOS"]},
]
## Cart paints (the steel carts' trim, the paleta carts' bands) and umbrella canvases (pairs; the
## second colours are copied in street_vendor.gdshader's CANVAS2, which the smoke test checks).
const CART_PAINTS := [Color(0.75, 0.1, 0.08), Color(0.1, 0.32, 0.65), Color(0.95, 0.75, 0.12), Color(0.12, 0.5, 0.25), Color(0.9, 0.45, 0.1), Color(0.6, 0.15, 0.45)]
const CANVAS := [
	[Color(0.85, 0.12, 0.1), Color(0.95, 0.93, 0.86)], [Color(0.1, 0.35, 0.75), Color(0.96, 0.94, 0.88)],
	[Color(0.95, 0.7, 0.1), Color(0.1, 0.45, 0.25)], [Color(0.9, 0.35, 0.55), Color(0.97, 0.88, 0.3)],
	[Color(0.1, 0.55, 0.6), Color(0.95, 0.5, 0.12)], [Color(0.85, 0.12, 0.1), Color(0.1, 0.35, 0.75)],
]
## Hours of the day to force while building (tests and stills); < 0 reads the DayNight clock.
static var force_hour: float = -1.0
## Off: no vendors at all (the A/B, `STREET_VENDORS=0` in the environment).
static var enabled: bool = OS.get_environment("STREET_VENDORS") != "0"

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial
static var _text_cache: Dictionary = {}


# --- Placement -------------------------------------------------------------------------------

## Whether this chunk's block can have vendors at all (cheap: the step is only queued if so).
static func wanted(chunk: CityChunk, block: Dictionary) -> bool:
	if not enabled or chunk.level != CityChunk.Level.FULL or chunk.plan == null:
		return false
	for e in 4:
		if _place(chunk.plan, chunk.ix, chunk.iz, block, e) != Place.NONE:
			return true
	return false


## What kind of place face `e` of block (ix, iz) is for vendors (faces as CityChunk's
## _sidewalk_edges: 0 -z, 1 +z, 2 -x, 3 +x).
static func _place(plan: CityPlan, ix: int, iz: int, block: Dictionary, e: int) -> int:
	if block.has("site"):
		return Place.NONE
	var kind := int(block.get("kind", CityPlan.BlockKind.BUILDINGS))
	if kind == CityPlan.BlockKind.MALL or kind == CityPlan.BlockKind.BIGBOX:
		return Place.NONE
	var nb: Vector2i = [Vector2i(ix, iz - 1), Vector2i(ix, iz + 1), Vector2i(ix - 1, iz), Vector2i(ix + 1, iz)][e]
	var across := plan.block(nb.x, nb.y)
	if String(across.get("site", "")) == "macarthur_park":
		return Place.MACARTHUR
	var centre: Vector2 = (block.rect as Rect2).get_center()
	if plan.macro != null:
		var arena := CivicSites.anchor("arena")
		if centre.distance_to(arena) < ARENA_REACH:
			return Place.ARENA
	if kind == CityPlan.BlockKind.PARK:
		return Place.PARK
	var district := int(block.get("district", CityPlan.District.SUBURBS))
	match district:
		CityPlan.District.DOWNTOWN:
			return Place.DOWNTOWN
		CityPlan.District.MIDTOWN:
			return Place.MIDTOWN
		CityPlan.District.INDUSTRIAL:
			return Place.INDUSTRIAL
		CityPlan.District.BEACHTOWN:
			return Place.BEACH
	if plan.macro != null and centre.distance_to(_boardwalk()) < BOARDWALK_REACH:
		return Place.BEACH
	return Place.NONE


static var _boardwalk_at := Vector2.INF


static func _boardwalk() -> Vector2:
	if _boardwalk_at == Vector2.INF:
		_boardwalk_at = Vector2(1e9, 1e9)
		for lm: Dictionary in Landmarks.all():
			if String(lm.id) == "venice_boardwalk":
				_boardwalk_at = lm.anchor
	return _boardwalk_at


## The hour vendors are built for: `force_hour`, else the city's clock, else early afternoon.
static func hour_now(node: Node) -> float:
	if force_hour >= 0.0:
		return force_hour
	if node != null and node.is_inside_tree():
		var scene := node.get_tree().current_scene
		var dn := scene.get_node_or_null("DayNight") if scene else null
		if dn != null:
			return float(dn.get("hour"))
	return 13.5


## Whether a vendor with this schedule [open, close] works at `hour`.
static func open_at(schedule: Vector2, hour: float) -> bool:
	var h := fposmod(hour, 24.0)
	var a := fposmod(schedule.x, 24.0)
	var b := fposmod(schedule.y, 24.0)
	return (h >= a and h < b) if a <= b else (h >= a or h < b)


## One vendor's own hours (the kind's, shifted by a hash; some trucks work lunch).
static func schedule_of(plan_seed: int, kind: int, place: int, id: Array) -> Vector2:
	var s: Array = SCHEDULE[kind]
	var shift := (_h01([plan_seed, "vend_hours"] + id) * 2.0 - 1.0) * SCHEDULE_JITTER
	if kind == Kind.TRUCK:
		var lunch := LUNCH_TRUCKS_INDUSTRIAL if place == Place.INDUSTRIAL else LUNCH_TRUCKS
		if _h01([plan_seed, "vend_lunch"] + id) < lunch:
			return Vector2(10.5 + shift * 0.5, 15.0 + shift * 0.5)
	return Vector2(float(s[0]) + shift, float(s[1]) + shift)


## The vendors working block (ix, iz) at `hour`: pure (no chunk), so tests ask it directly.
## Each is {kind, face, t (metres along the face), place, variant, paint, canvas, id, hours}.
static func plan_block(plan: CityPlan, ix: int, iz: int, hour: float) -> Array:
	var out: Array = []
	var block := plan.block(ix, iz)
	var rect: Rect2 = block.rect
	var edges := CityChunk._sidewalk_edges(rect)
	for e in 4:
		var place := _place(plan, ix, iz, block, e)
		if place == Place.NONE:
			continue
		var odds: Array = ODDS[place]
		var length := (edges[e][0] as Vector2).distance_to(edges[e][1])
		var cart_done := false
		var truck_done := false
		for kind in Kind.size():
			var id := [ix, iz, e, kind]
			var roll := _h01([plan.seed, "vendor"] + id)
			if roll >= float(odds[kind]):
				continue
			var hours := schedule_of(plan.seed, kind, place, id)
			if not open_at(hours, hour):
				continue
			if kind == Kind.TRUCK:
				# Parked in this chunk's own parking lane: the +x and +z faces, an open road, room.
				if truck_done or (e != 1 and e != 3) or length < 30.0 or not _truck_road_open(plan, ix, iz, e, rect):
					continue
				truck_done = true
			else:
				if cart_done:
					continue
				cart_done = true
			var t: float
			if kind == Kind.FLOWERS:
				# At a corner, where the crossing crowd passes.
				t = 4.5 + _h01([plan.seed, "vend_t"] + id) * 2.0
				if _h01([plan.seed, "vend_end"] + id) < 0.5:
					t = length - t
			else:
				var margin := 9.0 if kind == Kind.TRUCK else 6.5
				t = lerpf(margin, length - margin, _h01([plan.seed, "vend_t"] + id))
			var variant := int(_h01([plan.seed, "vend_var"] + id) * 1000.0)
			out.append({
				"kind": kind, "face": e, "t": t, "place": place, "variant": variant,
				"paint": _h01([plan.seed, "vend_paint"] + id), "id": "vend_%d_%d" % [e, kind], "hours": hours,
			})
			if out.size() >= MAX_PER_BLOCK:
				return out
	return out


static func _truck_road_open(plan: CityPlan, ix: int, iz: int, e: int, rect: Rect2) -> bool:
	if e == 3:
		return plan.road_open(CityPlan.AXIS_X, ix + 1, rect.get_center().y)
	return plan.road_open(CityPlan.AXIS_Z, iz + 1, rect.get_center().x)


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


## Lays out this block's vendors: their props, collision, light, the vendor's spot and the
## customers' queue. A build step of a FULL chunk, after the street furniture and the camps
## (it keeps clear of them) and before the parked cars (which keep out of a truck's stretch).
static func build_block(chunk: CityChunk, block: Dictionary) -> void:
	var plan: CityPlan = chunk.plan
	var rect: Rect2 = block.rect
	var edges := CityChunk._sidewalk_edges(rect)
	var occupied := _occupied(chunk)
	var people: Array = chunk.get_meta("vendor_people", [])
	for v: Dictionary in plan_block(plan, chunk.ix, chunk.iz, hour_now(chunk)):
		var edge: Array = edges[int(v.face)]
		if int(v.kind) == Kind.TRUCK:
			_place_truck(chunk, rect, edge, int(v.face), v, people)
		else:
			_place_cart(chunk, edge, v, occupied, people)
	chunk.set_meta("vendor_people", people)
	for k: String in CART_KEYS.values():
		chunk._batch.set_draw_distance(k, CART_DRAW)
		chunk._batch.set_shadow_distance(k, SHADOW_DISTANCE)
	chunk._batch.set_draw_distance(K_UMBRELLA, UMBRELLA_DRAW)
	chunk._batch.set_shadow_distance(K_UMBRELLA, SHADOW_DISTANCE)
	for i in TRUCKS.size():
		chunk._batch.set_draw_distance(K_TRUCK + str(i), TRUCK_DRAW)


## A taco truck in the parking lane of the road on face `e` (1: +z, 3: +x), its serving side to
## the kerb, nose the way that lane's traffic runs.
static func _place_truck(chunk: CityChunk, rect: Rect2, edge: Array, e: int, v: Dictionary, people: Array) -> void:
	var plan: CityPlan = chunk.plan
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var inward: Vector2 = edge[2]
	var dir := (b - a).normalized()
	var lane: float
	if e == 3:
		var rx := plan.road_pos(CityPlan.AXIS_X, chunk.ix + 1)
		lane = rx - CityPlan.parking_offset(plan.road_width(CityPlan.AXIS_X, chunk.ix + 1))
	else:
		var rz := plan.road_pos(CityPlan.AXIS_Z, chunk.iz + 1)
		lane = rz - CityPlan.parking_offset(plan.road_width(CityPlan.AXIS_Z, chunk.iz + 1))
	var kerb := a + dir * float(v.t)
	var c := Vector2(lane, kerb.y) if e == 3 else Vector2(kerb.x, lane)
	# Local +x (the serving side) to the pavement: x = inward, y up, z = x cross y.
	var x3 := Vector3(inward.x, 0.0, inward.y)
	var basis := Basis(x3, Vector3.UP, x3.cross(Vector3.UP))
	var variant := int(v.variant) % TRUCKS.size()
	var lv: Dictionary = TRUCKS[variant]
	var paints: Array = lv.paints
	var paint: Color = paints[int(float(v.paint) * paints.size()) % paints.size()]
	# The truck stands on the road (ROAD_TOP), not the pavement.
	var at := Vector3(c.x, CityChunk.ROAD_TOP, c.y)
	var xf := Transform3D(basis, at)
	var before := chunk.prop_records.size()
	var shapes: Array = []
	for s: Array in TRUCK_SHAPES:
		var size: Vector3 = s[0]
		var centre: Vector3 = xf * (s[1] as Vector3)
		shapes.append([size, centre, atan2(basis.z.x, basis.z.z)])
	chunk._add_prop("vendor_truck", at, paint, [
		[K_TRUCK + str(variant), truck(variant), xf, Color.WHITE, Color(paint.r, paint.g, paint.b, float(v.paint))],
	], shapes)
	if chunk.prop_records.size() == before:
		return
	# Nothing breaks a truck: rounds spark off its steel (WeaponFX classifies a prop as metal).
	chunk.prop_records.back().health = 1e12
	var trucks: Array = chunk.get_meta("vendor_trucks", [])
	trucks.append([c, dir])
	chunk.set_meta("vendor_trucks", trucks)
	# The light from the window and the awning's LED strip on the pavement, after dark: from the
	# kerb (1.3 m from the lane's middle) four metres onto the pavement.
	var pool_at := c + inward * 3.3
	var pool_size := Vector3(7.5, 1.0, 4.0) if e == 1 else Vector3(4.0, 1.0, 7.5)
	var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(pool_size), Vector3(pool_at.x, CityChunk.SIDEWALK_TOP + 0.06, pool_at.y))
	chunk._batch.add("shop_spill", PropFactory.shop_spill(), pool, TRUCK_POOL)
	chunk.set_meta("vendor_pools", int(chunk.get_meta("vendor_pools", 0)) + 1)
	_add_light(chunk, xf * Vector3(1.9, 2.35, 0.6), 7.5, Color(1.0, 0.93, 0.82))
	_add_generator_sound(chunk, xf * Vector3(0.0, 0.8, 3.95))
	# The cook in the window, on the truck's floor, facing out; the customers on the pavement in
	# front of it, facing the truck.
	var record: Dictionary = chunk.prop_records.back()
	var cook := xf * Vector3(0.3, 0.0, 0.6)
	people.append({"at": Vector2(cook.x, cook.z), "yaw": atan2(-inward.x, -inward.y), "truck": true,
		"floor": TRUCK_FLOOR + CityChunk.ROAD_TOP - CityChunk.SIDEWALK_TOP,
		"seed": hash([plan.seed, chunk.ix, chunk.iz, v.id]), "record": record, "rect": rect})
	var queue: Array = chunk.get_meta("vendor_queue", [])
	var window_mid := xf * Vector3(0.0, 0.0, 0.6)
	var to := -inward
	for k in 4:
		var along: float = [-0.6, 0.65, -1.3, 1.45][k]
		var depth: float = [1.0, 1.25, 2.1, 2.4][k]
		var p := Vector2(window_mid.x, window_mid.z) + dir * along + inward * (1.3 + depth)
		queue.append({"p": p, "yaw": atan2(-to.x, -to.y), "taken": null, "record": record})
	chunk.set_meta("vendor_queue", queue)


## A cart on the pavement of face `edge`, the vendor on its kerb side and the customers on its
## building side; slid along the face to clear whatever already stands there, or skipped.
static func _place_cart(chunk: CityChunk, edge: Array, v: Dictionary, occupied: Array, people: Array) -> void:
	var kind := int(v.kind)
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var inward: Vector2 = edge[2]
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var half := 0.95 if kind != Kind.FLOWERS else 1.1
	var depth := CART_IN if kind != Kind.FLOWERS else CART_IN + 0.6
	var found := false
	var q := Vector2.ZERO
	for k in 9:
		var t: float = float(v.t) + [0.0, 1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0][k]
		if t < 3.5 or t > length - 3.5:
			continue
		q = a + dir * t + inward * depth
		if _clear(occupied, q, half) and _clear(occupied, q - inward * 1.0, 0.3):
			found = true
			break
	if not found:
		return
	occupied.append([q, half])
	var yaw := atan2(-inward.x, -inward.y)
	# Local -z (the customers' side) toward the buildings: the yaw of a facing of `inward`.
	var basis := Basis(Vector3.UP, yaw)
	var at := Vector3(q.x, CityChunk.SIDEWALK_TOP, q.y)
	var xf := Transform3D(basis, at)
	var paint: Color = CART_PAINTS[int(float(v.paint) * CART_PAINTS.size()) % CART_PAINTS.size()]
	var custom := Color(paint.r, paint.g, paint.b, float(v.paint))
	var key: String = CART_KEYS[kind]
	var mesh := cart(kind)
	var id := "%s_%d_%d" % [String(v.id), chunk.ix, chunk.iz]
	if WorldState.is_destroyed(chunk.key, id):
		return
	var index := chunk._batch.add(key, mesh, xf, Color.WHITE, custom)
	var instances := [[key, index]]
	# The umbrella over a fruit or elote cart (and some paleta carts), in its socket.
	var umbrella := kind == Kind.FRUIT or kind == Kind.ELOTE or (kind == Kind.PALETA and float(v.paint) < 0.5)
	if umbrella:
		var canvas: Array = CANVAS[int(v.variant) % CANVAS.size()]
		var socket: Vector3 = UMBRELLA_SOCKET.get(kind, Vector3.ZERO)
		var scale := 0.75 if kind == Kind.PALETA else 1.0
		var uxf := Transform3D(basis.scaled(Vector3.ONE * scale), xf * socket)
		var c1: Color = canvas[0]
		# The second stripe is the shader's copy of CANVAS[i][1], picked by the custom alpha.
		var pick := float(int(v.variant) % CANVAS.size()) / 8.0
		instances.append([K_UMBRELLA, chunk._batch.add(K_UMBRELLA, umbrella_mesh(), uxf, Color.WHITE, Color(c1.r, c1.g, c1.b, pick))])
	var item := EncampmentItem.new()
	item.name = "Vendor_" + id
	item.chunk = chunk
	item.item_id = id
	item.instances = instances
	item.mesh = mesh
	item.mass_kg = CART_MASS[kind]
	item.tint = Color.WHITE
	item.custom = custom
	var box: Vector3 = CART_BOX[kind]
	item.setup(box, box.y * 0.5)
	item.transform = Transform3D(basis, at + Vector3(0.0, chunk._gy(q.x, q.y), 0.0))
	chunk.add_child(item)
	if kind == Kind.HOTDOG:
		var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(5.0, 1.0, 5.0)), at + Vector3(0.0, 0.06, 0.0))
		chunk._batch.add("shop_spill", PropFactory.shop_spill(), pool, BULB_POOL)
		chunk.set_meta("vendor_pools", int(chunk.get_meta("vendor_pools", 0)) + 1)
		_add_light(chunk, xf * Vector3(0.0, 2.0, 0.0), 5.0, Color(1.0, 0.75, 0.45))
	# The vendor, on the kerb side facing the pavement (or beside the flowers).
	var side := dir * (0.0 if kind != Kind.FLOWERS else 1.3)
	var vat := q - inward * (0.95 if kind != Kind.FLOWERS else 0.2) + side
	people.append({"at": vat, "yaw": atan2(-inward.x, -inward.y), "truck": false, "floor": 0.0,
		"seed": hash([chunk.plan.seed, chunk.ix, chunk.iz, v.id]), "record": item, "rect": chunk.plan.block(chunk.ix, chunk.iz).rect})
	occupied.append([vat, 0.35])
	var queue: Array = chunk.get_meta("vendor_queue", [])
	for k in (2 if kind != Kind.FLOWERS else 1):
		var p := q + inward * (QUEUE_IN - CART_IN) + dir * (-0.45 + 0.9 * k)
		var to := -inward
		queue.append({"p": p, "yaw": atan2(-to.x, -to.y), "taken": null, "record": item})
	chunk.set_meta("vendor_queue", queue)


## The vendor of the `index`-th stand this chunk built (a build step each), if the crowd cap has
## room for one more person.
static func spawn_vendor(chunk: CityChunk, index: int) -> void:
	var people: Array = chunk.get_meta("vendor_people", [])
	if index >= people.size():
		return
	var s: Dictionary = people[index]
	if not is_instance_valid(s.record) and not (s.record is Dictionary):
		return
	if not chunk._take_crowd_room():
		return
	var ped := StreetVendor.new()
	ped.setup_vendor(s.rect, int(s.seed), s.at, float(s.yaw), bool(s.truck), float(s.floor))
	var at: Vector2 = s.at
	ped.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + float(s.floor) + 0.05, at.y)
	chunk.add_child(ped)


## The free queue spot nearest `from` (chunk space) within `reach`, or {} (Pedestrian's life).
static func free_queue(chunk: Node, from: Vector2, reach: float) -> Dictionary:
	if chunk == null or not chunk.has_meta("vendor_queue"):
		return {}
	var best := {}
	var best_d := reach * reach
	for q: Dictionary in chunk.get_meta("vendor_queue"):
		if q.taken != null and is_instance_valid(q.taken):
			continue
		var rec: Variant = q.record
		if rec is Dictionary and bool((rec as Dictionary).get("dead", false)):
			continue
		if rec is Object and (not is_instance_valid(rec) or (rec as Node).is_queued_for_deletion()):
			continue
		var d := (q.p as Vector2).distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = q
	return best


## Whether the parked car at `spot` (chunk space) would stand in a truck's stretch of kerb.
static func blocks_parking(chunk: Node, spot: Vector3) -> bool:
	if not chunk.has_meta("vendor_trucks"):
		return false
	for t: Array in chunk.get_meta("vendor_trucks"):
		var c: Vector2 = t[0]
		var d: Vector2 = t[1]
		var rel := Vector2(spot.x, spot.z) - c
		if absf(rel.dot(d)) < TRUCK_HALF + 2.6 and absf(rel.dot(Vector2(d.y, -d.x))) < 2.0:
			return true
	return false


## A warm light at a truck's window or over a hot dog cart's bulbs, driven with the street lamps
## (DayNight sets the group's energy; Quality turns the group off at the low levels).
static func _add_light(chunk: CityChunk, at: Vector3, reach: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = at + Vector3(0.0, chunk._gy(at.x, at.z), 0.0)
	light.omni_range = reach
	light.omni_attenuation = 1.5
	light.light_color = color
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 40.0
	light.distance_fade_length = 15.0
	light.add_to_group("lamp_light")
	chunk.add_child(light)


## The generator's hum on the back of a truck (Sfx "generator", a real recording; a tone when
## the file is missing), heard within a street of it.
static func _add_generator_sound(chunk: CityChunk, at: Vector3) -> void:
	if not Sfx.has_method("loop_player"):
		return
	var p: AudioStreamPlayer3D = Sfx.loop_player("generator", -14.0)
	if p == null or p.stream == null:
		return
	p.position = at + Vector3(0.0, chunk._gy(at.x, at.z), 0.0)
	p.max_distance = 38.0
	p.unit_size = 4.0
	p.autoplay = true
	p.name = "GeneratorHum"
	chunk.add_child(p)


## Everything already on this chunk's pavements (StreetClutter's list plus the camps' pieces).
static func _occupied(chunk: CityChunk) -> Array:
	var out := StreetClutter._occupied(chunk)
	for c in chunk.get_children():
		if c is EncampmentItem:
			out.append([Vector2((c as Node3D).position.x, (c as Node3D).position.z), 0.8])
	return out


static func _clear(occupied: Array, p: Vector2, half: float) -> bool:
	for o: Array in occupied:
		if (o[0] as Vector2).distance_to(p) < float(o[1]) + half:
			return false
	return true


# --- The truck -------------------------------------------------------------------------------
# Local frame: origin on the road under the middle, +y up, the nose toward -z, the serving side
# +x. A step van: a 6 m box on a chassis, a short bonnet, the window cut into the right side.

const TW := 1.18          # half the box's width
const TZ0 := -2.5         # box front (behind the windscreen)
const TZ1 := 3.45         # box rear
const TYB := 0.88         # box floor (under it the chassis and wheels)
const TYT := 3.1          # roof
const WZ0 := -0.75        # serving window, along the side
const WZ1 := 1.95
const WY0 := 1.5          # window sill and head
const WY1 := 2.45
## The truck's floor inside, above the road (where its cook stands).
const TRUCK_FLOOR := 0.95
## Collision: [size, centre] in the truck's frame. The window span is open above the sill, so a
## round through the window finds the cook.
const TRUCK_SHAPES := [
	[Vector3(2.36, 1.22, 7.9), Vector3(0.0, 0.89, 0.3)],
	[Vector3(2.36, 1.62, 1.75), Vector3(0.0, 2.31, -1.625)],
	[Vector3(2.36, 1.62, 1.5), Vector3(0.0, 2.31, 2.7)],
	[Vector3(0.3, 1.62, 2.7), Vector3(-1.03, 2.31, 0.6)],
	[Vector3(2.36, 0.5, 2.7), Vector3(0.0, 2.85, 0.6)],
	[Vector3(2.2, 0.78, 1.0), Vector3(0.0, 0.95, -3.0)],
]


static func truck(variant: int) -> Mesh:
	var key := K_TRUCK + str(variant)
	if _meshes.has(key):
		return _meshes[key]
	var lv: Dictionary = TRUCKS[variant]
	var st := StreetClutter._begin()
	var paint := Color(1, 1, 1, 1)
	var rm_paint := Vector2(0.32, 0.0)
	var black := Color(0.05, 0.05, 0.055)
	var rubber := Vector2(0.88, 0.0)
	var steel := Color(0.66, 0.67, 0.68, A_STEEL)
	var rm_steel := Vector2(0.3, 0.85)
	var dark_steel := Color(0.16, 0.16, 0.17)
	var glass := Color(0.035, 0.045, 0.05, A_GLASS)
	var rm_glass := Vector2(0.05, 0.0)
	var h := TYT - TYB
	var length := TZ1 - TZ0
	var zm := (TZ0 + TZ1) * 0.5
	# Chassis, rails, fuel tank and exhaust, mud flaps.
	_box(st, Vector3(0.0, 0.62, 0.35), Vector3(1.05, 0.22, 7.4), 0.02, dark_steel, Vector2(0.7, 0.4))
	_box(st, Vector3(-0.78, 0.6, 0.9), Vector3(0.42, 0.36, 0.9), 0.05, Color(0.5, 0.5, 0.52, A_STEEL), rm_steel)
	_box(st, Vector3(0.0, TYB - 0.07, zm), Vector3(TW * 2.0 - 0.04, 0.1, length - 0.04), 0.01, dark_steel, Vector2(0.8, 0.2))
	for zf: float in [-1.75, 3.05]:
		for s: float in [-1.0, 1.0]:
			_box(st, Vector3(s * 1.0, 0.42, zf), Vector3(0.32, 0.5, 0.012), 0.004, black, rubber)
	# Wheels: tyre, rim, hub; the front pair under the cab, the rear pair under the box.
	for wz: float in [-2.2, 2.3]:
		for s: float in [-1.0, 1.0]:
			_cylx(st, Vector3(s * (TW - 0.2), 0.43, wz), s, 0.43, 0.29, black, rubber, 16)
			_cylx(st, Vector3(s * (TW - 0.06), 0.43, wz), s, 0.25, 0.02, Color(0.72, 0.73, 0.74, A_STEEL), Vector2(0.25, 1.0), 12)
			_cylx(st, Vector3(s * (TW - 0.05), 0.43, wz), s, 0.09, 0.05, Color(0.5, 0.5, 0.52, A_STEEL), Vector2(0.3, 1.0), 8)
	# The box: left wall whole, right wall round the window, roof, floor, front and rear walls.
	_box(st, Vector3(-TW + 0.02, TYB + h * 0.5, zm), Vector3(0.04, h, length), 0.012, paint, rm_paint)
	_box(st, Vector3(TW - 0.02, (TYB + WY0) * 0.5, zm), Vector3(0.04, WY0 - TYB, length), 0.012, paint, rm_paint)
	_box(st, Vector3(TW - 0.02, (WY1 + TYT) * 0.5, zm), Vector3(0.04, TYT - WY1, length), 0.012, paint, rm_paint)
	_box(st, Vector3(TW - 0.02, (WY0 + WY1) * 0.5, (TZ0 + WZ0) * 0.5), Vector3(0.04, WY1 - WY0, WZ0 - TZ0), 0.01, paint, rm_paint)
	_box(st, Vector3(TW - 0.02, (WY0 + WY1) * 0.5, (WZ1 + TZ1) * 0.5), Vector3(0.04, WY1 - WY0, TZ1 - WZ1), 0.01, paint, rm_paint)
	_box(st, Vector3(0.0, TYT - 0.03, zm), Vector3(TW * 2.0 - 0.1, 0.06, length - 0.02), 0.01, paint, rm_paint)
	_box(st, Vector3(0.0, TYB + h * 0.5, TZ1 - 0.025), Vector3(TW * 2.0, h, 0.05), 0.012, paint, rm_paint)
	_box(st, Vector3(0.0, (WY1 + TYT) * 0.5, TZ0 + 0.025), Vector3(TW * 2.0, TYT - WY1, 0.05), 0.012, paint, rm_paint)
	# Rounded roof edges.
	for s: float in [-1.0, 1.0]:
		StreetClutter._tube(st, [Vector3(s * (TW - 0.05), TYT - 0.05, TZ0 + 0.02), Vector3(s * (TW - 0.05), TYT - 0.05, TZ1 - 0.02)], 0.06, 8, paint, rm_paint)
		StreetClutter._tube(st, [Vector3(s * (TW - 0.03), TYB + 0.03, TZ0 + 0.02), Vector3(s * (TW - 0.03), TYB + 0.03, TZ1 - 0.02)], 0.035, 6, paint, rm_paint)
	for zf: float in [TZ0 + 0.04, TZ1 - 0.04]:
		StreetClutter._tube(st, [Vector3(-TW + 0.04, TYT - 0.05, zf), Vector3(TW - 0.04, TYT - 0.05, zf)], 0.05, 8, paint, rm_paint)
	# Cab: windscreen leaning forward to the bonnet, its side wedges, A-pillars, door glass.
	var ws_bot := 1.38
	var ws_top := WY1
	var ws_z := TZ0 - 0.32
	StreetClutter._quad(st, Vector3(-TW + 0.07, ws_bot, ws_z), Vector3(TW - 0.07, ws_bot, ws_z), Vector3(TW - 0.07, ws_top, TZ0), Vector3(-TW + 0.07, ws_top, TZ0), Vector3(0.0, 0.3, -1.0), glass, rm_glass)
	for s: float in [-1.0, 1.0]:
		StreetClutter._tri(st, Vector3(s * TW, ws_bot, ws_z), Vector3(s * TW, ws_bot, TZ0), Vector3(s * TW, ws_top, TZ0), Vector3(s, 0.0, 0.0), paint, rm_paint)
		StreetClutter._tube(st, [Vector3(s * (TW - 0.04), ws_bot, ws_z), Vector3(s * (TW - 0.04), ws_top, TZ0)], 0.045, 6, paint, rm_paint)
		# Door glass and the door's shut lines.
		var gx := s * (TW + 0.003)
		StreetClutter._quad(st, Vector3(gx, 1.55, TZ0 + 0.08), Vector3(gx, 1.55, TZ0 + 0.95), Vector3(gx, 2.32, TZ0 + 0.95), Vector3(gx, 2.32, TZ0 + 0.08), Vector3(s, 0.0, 0.0), glass, rm_glass)
		for dz: float in [TZ0 + 0.02, TZ0 + 1.02]:
			_box(st, Vector3(s * (TW + 0.002), (TYB + 2.4) * 0.5, dz), Vector3(0.006, 2.4 - TYB, 0.012), 0.0, black, rubber)
		# Mirror on its arm.
		StreetClutter._tube(st, [Vector3(s * TW, 2.05, TZ0 - 0.15), Vector3(s * (TW + 0.22), 2.1, TZ0 - 0.2)], 0.015, 6, black, Vector2(0.5, 0.3))
		_box(st, Vector3(s * (TW + 0.25), 2.0, TZ0 - 0.2), Vector3(0.05, 0.36, 0.2), 0.02, black, Vector2(0.4, 0.2))
	# Wall below the windscreen, then the bonnet, grille, lamps, bumper.
	_box(st, Vector3(0.0, (TYB + ws_bot) * 0.5, ws_z + 0.02), Vector3(TW * 2.0, ws_bot - TYB, 0.04), 0.01, paint, rm_paint)
	_box(st, Vector3(0.0, 0.98, (ws_z - 3.45) * 0.5 - 0.0), Vector3(TW * 2.0 - 0.14, 0.78, -3.45 - ws_z + 0.05), 0.09, paint, rm_paint)
	_box(st, Vector3(0.0, 0.98, -3.47), Vector3(1.15, 0.42, 0.04), 0.01, Color(0.09, 0.09, 0.1), Vector2(0.5, 0.5))
	for gy in 5:
		_box(st, Vector3(0.0, 0.82 + gy * 0.08, -3.49), Vector3(1.12, 0.018, 0.012), 0.0, Color(0.7, 0.71, 0.72, A_STEEL), rm_steel)
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * 0.82, 1.0, -3.46), Vector3(0.28, 0.2, 0.04), 0.02, Color(0.85, 0.87, 0.86, A_GLASS), Vector2(0.05, 0.0))
		_box(st, Vector3(s * 0.82, 0.83, -3.46), Vector3(0.22, 0.06, 0.03), 0.01, Color(0.9, 0.55, 0.12, A_GLASS), Vector2(0.1, 0.0))
	_box(st, Vector3(0.0, 0.58, -3.52), Vector3(2.3, 0.2, 0.16), 0.03, Color(0.7, 0.71, 0.72, A_STEEL), rm_steel)
	_box(st, Vector3(0.0, 0.62, -3.6), Vector3(0.52, 0.12, 0.01), 0.0, Color(0.92, 0.92, 0.88), Vector2(0.4, 0.0))
	# Rear: barn doors' shut lines and handles, tail lamps, bumper, step, plate.
	_box(st, Vector3(0.0, TYB + h * 0.42, TZ1 + 0.003), Vector3(0.012, h * 0.82, 0.006), 0.0, black, rubber)
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * (TW - 0.12), 1.15, TZ1 + 0.01), Vector3(0.14, 0.3, 0.04), 0.01, Color(0.55, 0.04, 0.03, A_GLASS), Vector2(0.1, 0.0))
		_box(st, Vector3(s * 0.12, 1.55, TZ1 + 0.03), Vector3(0.03, 0.22, 0.04), 0.008, Color(0.7, 0.71, 0.72, A_STEEL), rm_steel)
	_box(st, Vector3(0.0, 1.05, TZ1 + 0.012), Vector3(0.32, 0.16, 0.01), 0.0, Color(0.92, 0.92, 0.88), Vector2(0.4, 0.0))
	_box(st, Vector3(0.0, 0.6, TZ1 + 0.12), Vector3(2.3, 0.16, 0.22), 0.02, Color(0.62, 0.63, 0.64, A_STEEL), rm_steel)
	# The generator on its rack behind the bumper: frame, cabinet, louvres, exhaust.
	_box(st, Vector3(0.0, 0.58, TZ1 + 0.55), Vector3(1.1, 0.04, 0.62), 0.005, Color(0.5, 0.5, 0.52, A_STEEL), Vector2(0.45, 1.0))
	_box(st, Vector3(0.0, 0.9, TZ1 + 0.55), Vector3(0.82, 0.58, 0.52), 0.04, Color(0.72, 0.13, 0.08), Vector2(0.45, 0.0))
	for gy in 4:
		_box(st, Vector3(0.0, 0.78 + gy * 0.08, TZ1 + 0.815), Vector3(0.6, 0.025, 0.012), 0.0, black, rubber)
	for s: float in [-1.0, 1.0]:
		StreetClutter._tube(st, [Vector3(s * 0.45, 0.6, TZ1 + 0.28), Vector3(s * 0.45, 1.25, TZ1 + 0.28), Vector3(s * 0.45, 1.25, TZ1 + 0.82), Vector3(s * 0.45, 0.6, TZ1 + 0.82)], 0.018, 6, black, Vector2(0.5, 0.4))
	StreetClutter._tube(st, [Vector3(-0.3, 1.0, TZ1 + 0.82), Vector3(-0.3, 1.0, TZ1 + 0.95), Vector3(-0.3, 1.3, TZ1 + 0.95)], 0.022, 8, Color(0.3, 0.28, 0.26, A_STEEL), Vector2(0.6, 1.0))
	# Roof: air conditioner, the extractor's stack over the grill, a light bar at the front.
	_box(st, Vector3(0.0, TYT + 0.17, 0.2), Vector3(0.82, 0.28, 0.95), 0.05, Color(0.85, 0.85, 0.83), Vector2(0.45, 0.0))
	for gz in 5:
		_box(st, Vector3(0.0, TYT + 0.315, -0.15 + gz * 0.17), Vector3(0.7, 0.01, 0.08), 0.0, Color(0.3, 0.3, 0.3), Vector2(0.6, 0.0))
	_box(st, Vector3(-0.35, TYT + 0.2, 1.6), Vector3(0.45, 0.4, 0.45), 0.02, steel, rm_steel)
	_box(st, Vector3(-0.35, TYT + 0.46, 1.6), Vector3(0.6, 0.06, 0.6), 0.01, steel, rm_steel)
	# Serving window: frame, the inside (lit), a sliding pane pushed to one end.
	var wx := TW - 0.02
	for zz: float in [WZ0, WZ1]:
		_box(st, Vector3(wx, (WY0 + WY1) * 0.5, zz), Vector3(0.08, WY1 - WY0 + 0.08, 0.05), 0.01, steel, rm_steel)
	_box(st, Vector3(wx, WY1, (WZ0 + WZ1) * 0.5), Vector3(0.08, 0.05, WZ1 - WZ0 + 0.05), 0.01, steel, rm_steel)
	StreetClutter._quad(st, Vector3(TW - 0.06, WY0 + 0.02, WZ1 - 0.95), Vector3(TW - 0.06, WY0 + 0.02, WZ1 - 0.03), Vector3(TW - 0.06, WY1 - 0.02, WZ1 - 0.03), Vector3(TW - 0.06, WY1 - 0.02, WZ1 - 0.95), Vector3(1.0, 0.0, 0.0), Color(0.12, 0.14, 0.15, A_GLASS), rm_glass)
	var inside := Color(0.82, 0.8, 0.74, A_INTERIOR)
	var back_x := -0.95
	StreetClutter._quad(st, Vector3(back_x, TYB, WZ0), Vector3(back_x, TYB, WZ1), Vector3(back_x, TYT - 0.1, WZ1), Vector3(back_x, TYT - 0.1, WZ0), Vector3(1.0, 0.0, 0.0), inside, Vector2(0.35, 0.0))
	StreetClutter._quad(st, Vector3(back_x, TYT - 0.12, WZ0), Vector3(TW - 0.04, TYT - 0.12, WZ0), Vector3(TW - 0.04, TYT - 0.12, WZ1), Vector3(back_x, TYT - 0.12, WZ1), Vector3(0.0, -1.0, 0.0), Color(0.95, 0.94, 0.9, A_INTERIOR), Vector2(0.4, 0.0))
	for zz: float in [WZ0, WZ1]:
		var n := 1.0 if zz == WZ0 else -1.0
		StreetClutter._quad(st, Vector3(back_x, TYB, zz), Vector3(TW - 0.04, TYB, zz), Vector3(TW - 0.04, TYT - 0.1, zz), Vector3(back_x, TYT - 0.1, zz), Vector3(0.0, 0.0, n), Color(0.66, 0.65, 0.6, A_INTERIOR), Vector2(0.35, 0.0))
	StreetClutter._quad(st, Vector3(back_x, TRUCK_FLOOR, WZ0), Vector3(TW - 0.04, TRUCK_FLOOR, WZ0), Vector3(TW - 0.04, TRUCK_FLOOR, WZ1), Vector3(back_x, TRUCK_FLOOR, WZ1), Vector3.UP, Color(0.2, 0.18, 0.16), Vector2(0.7, 0.0))
	# Fluorescent tubes on the ceiling.
	for tz: float in [WZ0 + 0.6, WZ1 - 0.6]:
		_box(st, Vector3(0.1, TYT - 0.15, tz), Vector3(1.2, 0.04, 0.08), 0.01, Color(0.98, 0.97, 0.92, A_LED), Vector2(0.3, 0.0))
	# The kitchen along the back wall: the hood, the plancha and its glow, a fridge, shelves.
	_box(st, Vector3(-0.72, 2.55, 0.15), Vector3(0.45, 0.35, 1.4), 0.02, steel, rm_steel)
	_box(st, Vector3(-0.68, 1.35, 0.15), Vector3(0.55, 0.06, 1.3), 0.01, Color(0.12, 0.11, 0.1), Vector2(0.35, 0.8))
	_box(st, Vector3(-0.7, 1.12, 0.15), Vector3(0.5, 0.4, 1.3), 0.01, steel, rm_steel)
	for k in 6:
		var mz := -0.35 + k * 0.2
		_box(st, Vector3(-0.62, 1.4, mz), Vector3(0.12, 0.04, 0.14), 0.01, [Color(0.55, 0.25, 0.1, A_FOOD), Color(0.75, 0.35, 0.15, A_FOOD), Color(0.3, 0.5, 0.2, A_FOOD)][k % 3], Vector2(0.4, 0.0))
	_box(st, Vector3(-0.7, 1.55, 1.55), Vector3(0.48, 1.3, 0.62), 0.02, steel, rm_steel)
	for k in 3:
		_box(st, Vector3(-0.82, 2.0 + k * 0.0, -0.55 + k * 0.42), Vector3(0.22, 0.02, 0.36), 0.0, steel, rm_steel)
		_box(st, Vector3(-0.82, 2.08, -0.55 + k * 0.42), Vector3(0.14, 0.14, 0.3), 0.01, [Color(0.85, 0.2, 0.1), Color(0.95, 0.85, 0.3), Color(0.2, 0.5, 0.25)][k], Vector2(0.5, 0.0))
	# The counter outside the window: shelf, brackets, and what is on it.
	var cx := TW + 0.2
	_box(st, Vector3(cx, WY0 - 0.02, (WZ0 + WZ1) * 0.5), Vector3(0.4, 0.035, WZ1 - WZ0 + 0.1), 0.006, steel, rm_steel)
	for zz: float in [WZ0 + 0.25, (WZ0 + WZ1) * 0.5, WZ1 - 0.25]:
		StreetClutter._tube(st, [Vector3(TW, WY0 - 0.35, zz), Vector3(TW + 0.36, WY0 - 0.04, zz)], 0.015, 6, steel, rm_steel)
	_box(st, Vector3(cx, WY0 + 0.09, WZ0 + 0.35), Vector3(0.12, 0.18, 0.16), 0.01, steel, rm_steel)
	for k in 4:
		var bz := WZ0 + 0.75 + k * 0.11
		var bc: Color = [Color(0.75, 0.1, 0.05), Color(0.2, 0.55, 0.15), Color(0.75, 0.1, 0.05), Color(0.9, 0.55, 0.1)][k]
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(cx + 0.05, WY0, bz)), 0.035, 0.03, 0.2, bc, Vector2(0.3, 0.0), 8)
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(cx + 0.05, WY0 + 0.2, bz)), 0.012, 0.004, 0.05, Color(0.95, 0.95, 0.9), Vector2(0.4, 0.0), 6)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(cx, WY0, WZ1 - 0.5)), 0.12, 0.15, 0.08, Color(0.85, 0.83, 0.78), Vector2(0.3, 0.0), 12)
	for k in 6:
		var a := TAU * k / 6.0
		_sphere(st, Vector3(cx + cos(a) * 0.06, WY0 + 0.09, WZ1 - 0.5 + sin(a) * 0.06), 0.035, Color(0.3, 0.55, 0.12, A_FOOD), Vector2(0.4, 0.0), 6)
	# The awning flap, propped up and out over the window, on two struts, an LED strip under it.
	var hinge := Vector3(TW, WY1 + 0.04, (WZ0 + WZ1) * 0.5)
	var tilt := deg_to_rad(5.0)
	var flap_b := Basis(Vector3.BACK, tilt)
	var out := flap_b * Vector3.RIGHT
	var flap_len := WZ1 - WZ0 + 0.3
	_xbox(st, Transform3D(flap_b, hinge + out * 0.45), Vector3(0.9, 0.04, flap_len), 0.01, paint, rm_paint)
	_xbox(st, Transform3D(flap_b, hinge + out * 0.86 + Vector3(0.0, -0.04, 0.0)), Vector3(0.04, 0.05, flap_len), 0.0, Color(0.95, 0.96, 1.0, A_LED), Vector2(0.3, 0.0))
	_xbox(st, Transform3D(flap_b, hinge + out * 0.12 + Vector3(0.0, -0.035, 0.0)), Vector3(0.03, 0.03, flap_len - 0.2), 0.0, Color(0.95, 0.96, 1.0, A_LED), Vector2(0.3, 0.0))
	for s: float in [-1.0, 1.0]:
		var zz := hinge.z + s * (flap_len * 0.5 - 0.15)
		StreetClutter._tube(st, [Vector3(TW, WY1 - 0.55, zz), hinge + out * 0.78 + Vector3(0.0, -0.03, zz - hinge.z)], 0.014, 6, steel, rm_steel)
	# The menu board on the rear quarter: a lightbox, the photos, the lettering.
	var mz0 := WZ1 + 0.18
	var mz1 := TZ1 - 0.15
	var my0 := 1.42
	var my1 := 2.85
	var mx := TW + 0.044
	_box(st, Vector3(TW + 0.015, (my0 + my1) * 0.5, (mz0 + mz1) * 0.5), Vector3(0.05, my1 - my0 + 0.06, mz1 - mz0 + 0.06), 0.01, Color(0.08, 0.08, 0.09), Vector2(0.4, 0.5))
	StreetClutter._quad(st, Vector3(mx, my0, mz0), Vector3(mx, my0, mz1), Vector3(mx, my1, mz1), Vector3(mx, my1, mz0), Vector3(1.0, 0.0, 0.0), Color(0.98, 0.96, 0.88, A_GLOW), Vector2(0.3, 0.0))
	var menu: Array = lv.menu
	var row_h := (my1 - my0 - 0.42) / float(menu.size())
	var mzc := (mz0 + mz1) * 0.5
	var face := Basis(Vector3.UP, PI * 0.5)
	_text(st, "MENÚ", 0.16, Transform3D(face, Vector3(mx + 0.004, my1 - 0.14, mzc)), lv.ink, mz1 - mz0 - 0.1)
	for i in menu.size():
		var y := my1 - 0.32 - (float(i) + 0.5) * row_h
		var line_col: Color = Color(0.08, 0.07, 0.06) if i < menu.size() - 2 else lv.band
		_text(st, String(menu[i]), minf(row_h * 0.62, 0.1), Transform3D(face, Vector3(mx + 0.004, y, mzc + 0.12)), line_col, mz1 - mz0 - 0.38)
	for k in 3:
		var pz := mz0 + 0.06
		var py := my1 - 0.42 - k * 0.32
		StreetClutter._page(st, Vector3(mx + 0.003, py, pz), Vector3(mx + 0.003, py, pz + 0.24), Vector3(mx + 0.003, py - 0.26, pz + 0.24), Vector3(mx + 0.003, py - 0.26, pz),
			Vector3(1.0, 0.0, 0.0), A_PHOTO, Vector2(float(variant * 3 + k), 0.0), Vector2(0.3, 0.0))
	# The name, along the top of the serving side and big on the street side, with the band.
	_box(st, Vector3(TW + 0.004, 2.62, zm), Vector3(0.006, 0.05, length - 0.1), 0.0, lv.band, rm_paint)
	_text(st, String(lv.name), 0.28, Transform3D(face, Vector3(TW + 0.008, 2.88, zm)), lv.ink, length - 0.5)
	var face_l := Basis(Vector3.UP, -PI * 0.5)
	_box(st, Vector3(-TW - 0.004, 1.3, zm), Vector3(0.006, 0.12, length - 0.1), 0.0, lv.band, rm_paint)
	_box(st, Vector3(-TW - 0.004, 1.12, zm), Vector3(0.006, 0.05, length - 0.1), 0.0, lv.ink, rm_paint)
	_text(st, String(lv.name), 0.42, Transform3D(face_l, Vector3(-TW - 0.008, 2.25, zm)), lv.ink, length - 0.6)
	_text(st, "CATERING · EVENTOS", 0.14, Transform3D(face_l, Vector3(-TW - 0.008, 1.75, zm)), lv.band, length - 1.0)
	return _finish(st, key)


# --- Carts -----------------------------------------------------------------------------------
# Local frame: origin on the pavement under the middle, +y up, the customers' side toward -z,
# the vendor's +z, the long side along x.

## Where each cart's umbrella pole stands (its socket), and the box each is knocked over as.
const UMBRELLA_SOCKET := {Kind.FRUIT: Vector3(0.78, 0.0, 0.32), Kind.ELOTE: Vector3(0.68, 0.0, 0.3), Kind.PALETA: Vector3(-0.47, 0.45, 0.0)}
const CART_BOX := {Kind.FRUIT: Vector3(1.55, 1.3, 0.8), Kind.ELOTE: Vector3(1.35, 1.25, 0.75), Kind.HOTDOG: Vector3(1.1, 1.05, 0.65), Kind.PALETA: Vector3(1.2, 0.95, 0.7), Kind.FLOWERS: Vector3(1.6, 1.0, 0.9)}
const CART_MASS := {Kind.FRUIT: 70.0, Kind.ELOTE: 60.0, Kind.HOTDOG: 50.0, Kind.PALETA: 35.0, Kind.FLOWERS: 25.0}


static func cart(kind: int) -> Mesh:
	var key: String = CART_KEYS[kind]
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	match kind:
		Kind.FRUIT:
			_fruit_cart(st)
		Kind.ELOTE:
			_elote_cart(st)
		Kind.HOTDOG:
			_hotdog_cart(st)
		Kind.PALETA:
			_paleta_cart(st)
		Kind.FLOWERS:
			_flower_stand(st)
	return _finish(st, key)


## A stainless cart body on two wheels and two legs, a shelf under it, the push handle.
static func _cart_body(st: SurfaceTool, half_x: float, half_z: float, top: float) -> void:
	var steel := Color(0.72, 0.73, 0.74, A_STEEL)
	var rm := Vector2(0.34, 0.8)
	var paint := Color(1, 1, 1, 1)
	_box(st, Vector3(0.0, (top + 0.32) * 0.5, 0.0), Vector3(half_x * 2.0, top - 0.32, half_z * 2.0), 0.02, steel, rm)
	# A painted band round the top edge, the vendor's colour.
	_box(st, Vector3(0.0, top - 0.06, 0.0), Vector3(half_x * 2.0 + 0.01, 0.06, half_z * 2.0 + 0.01), 0.005, paint, Vector2(0.4, 0.0))
	_box(st, Vector3(0.0, 0.17, 0.0), Vector3(half_x * 2.0 - 0.08, 0.025, half_z * 2.0 - 0.06), 0.004, steel, rm)
	for s: float in [-1.0, 1.0]:
		for t: float in [-1.0, 1.0]:
			StreetClutter._tube(st, [Vector3(s * (half_x - 0.04), 0.32, t * (half_z - 0.04)), Vector3(s * (half_x - 0.04), 0.06 if s > 0.0 else 0.15, t * (half_z - 0.04))], 0.016, 6, steel, rm)
	# Wheels at the -x end, feet at the +x end, the handle over the feet.
	for t: float in [-1.0, 1.0]:
		var c := Vector3(-half_x + 0.12, 0.18, t * (half_z + 0.04))
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * t), c), 0.18, 0.18, 0.05, Color(0.05, 0.05, 0.05), Vector2(0.85, 0.0), 14)
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * t), c + Vector3(0.0, 0.0, t * 0.01)), 0.1, 0.1, 0.05, Color(0.6, 0.6, 0.62, A_STEEL), rm, 10)
		_box(st, Vector3(half_x - 0.04, 0.03, t * (half_z - 0.04)), Vector3(0.06, 0.06, 0.06), 0.01, Color(0.08, 0.08, 0.08), Vector2(0.8, 0.0))
	StreetClutter._tube(st, [Vector3(half_x, top - 0.12, -half_z + 0.06), Vector3(half_x + 0.28, top + 0.0, -half_z + 0.06), Vector3(half_x + 0.28, top + 0.0, half_z - 0.06), Vector3(half_x, top - 0.12, half_z - 0.06)], 0.018, 8, steel, rm)


static func _fruit_cart(st: SurfaceTool) -> void:
	var top := 0.9
	_cart_body(st, 0.7, 0.36, top)
	var steel := Color(0.7, 0.71, 0.72, A_STEEL)
	var rm := Vector2(0.25, 1.0)
	# The tray of ice, its rim, and the cut fruit laid on it in sections.
	_box(st, Vector3(0.0, top + 0.03, 0.0), Vector3(1.36, 0.06, 0.68), 0.005, steel, rm)
	_box(st, Vector3(0.0, top + 0.065, 0.0), Vector3(1.3, 0.02, 0.62), 0.0, Color(0.86, 0.9, 0.93, A_FOOD), Vector2(0.12, 0.0))
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(0.0, top + 0.09, s * 0.335), Vector3(1.36, 0.06, 0.012), 0.0, steel, rm)
		_box(st, Vector3(s * 0.675, top + 0.09, 0.0), Vector3(0.012, 0.06, 0.68), 0.0, steel, rm)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("vend_fruit")
	# [colour, inside colour (or skin), section x]
	var fruits := [
		[Color(0.98, 0.62, 0.08), Color(0.95, 0.75, 0.2)],    # mango
		[Color(0.88, 0.16, 0.18), Color(0.2, 0.42, 0.15)],    # watermelon, green rind
		[Color(0.97, 0.88, 0.45), Color(0.98, 0.9, 0.55)],    # pineapple
		[Color(0.78, 0.9, 0.62), Color(0.15, 0.35, 0.12)],    # cucumber, dark skin
		[Color(0.95, 0.94, 0.9), Color(0.6, 0.48, 0.3)],      # jicama
		[Color(0.98, 0.55, 0.25), Color(0.92, 0.5, 0.2)],     # papaya
	]
	for i in fruits.size():
		var sx := -0.55 + i * 0.22
		var f: Array = fruits[i]
		for k in 9:
			var px := sx + rng.randf_range(-0.07, 0.07)
			var pz := rng.randf_range(-0.22, 0.22)
			var yaw := rng.randf_range(-0.5, 0.5) + PI * 0.5
			var yb := top + 0.08 + rng.randf_range(0.0, 0.04)
			var b := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, rng.randf_range(-0.3, 0.3))
			var size := Vector3(0.035, 0.03, rng.randf_range(0.11, 0.16))
			_xbox(st, Transform3D(b, Vector3(px, yb + 0.015, pz)), size, 0.004, Color(f[0].r, f[0].g, f[0].b, A_FOOD), Vector2(0.35, 0.0))
			if i == 1 or i == 3:
				_xbox(st, Transform3D(b, Vector3(px, yb + 0.015, pz)) * StreetClutter._at(0.0, -0.016, 0.0), size * Vector3(1.05, 0.25, 1.0), 0.0, Color(f[1].r, f[1].g, f[1].b, A_FOOD), Vector2(0.4, 0.0))
	# The glass case's frame over the tray (open-fronted on the vendor's side) and its top.
	var gy := top + 0.42
	for s: float in [-1.0, 1.0]:
		StreetClutter._tube(st, [Vector3(s * 0.67, top + 0.1, -0.33), Vector3(s * 0.67, gy, -0.12), Vector3(s * 0.67, gy, 0.3)], 0.01, 6, steel, rm)
	StreetClutter._tube(st, [Vector3(-0.67, gy, -0.12), Vector3(0.67, gy, -0.12)], 0.01, 6, steel, rm)
	StreetClutter._quad(st, Vector3(-0.67, top + 0.1, -0.335), Vector3(0.67, top + 0.1, -0.335), Vector3(0.67, top + 0.14, -0.32), Vector3(-0.67, top + 0.14, -0.32), Vector3(0.0, 0.3, -1.0), Color(0.55, 0.65, 0.65, A_GLASS), Vector2(0.05, 0.0))
	_box(st, Vector3(0.0, gy + 0.01, 0.09), Vector3(1.36, 0.02, 0.44), 0.004, Color(0.75, 0.82, 0.84, A_GLASS), Vector2(0.06, 0.0))
	# On top: a stack of clear cups, filled cups with a fork in each, chile-lime and chamoy.
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(-0.5, gy + 0.02, 0.15)), 0.042, 0.05, 0.3, Color(0.88, 0.9, 0.9), Vector2(0.15, 0.0), 10)
	for k in 5:
		var cpos := Vector3(-0.3 + k * 0.15, gy + 0.02, 0.12 + (k % 2) * 0.1)
		StreetClutter._cyl(st, Transform3D(Basis(), cpos), 0.04, 0.05, 0.13, Color(0.85, 0.88, 0.88), Vector2(0.15, 0.0), 10)
		var mix: Color = [Color(0.95, 0.62, 0.12), Color(0.85, 0.2, 0.2), Color(0.9, 0.82, 0.4)][k % 3]
		_sphere(st, cpos + Vector3(0.0, 0.15, 0.0), 0.055, Color(mix.r, mix.g, mix.b, A_FOOD), Vector2(0.4, 0.0), 7)
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.RIGHT, 0.25), cpos + Vector3(0.0, 0.15, 0.0)), 0.005, 0.004, 0.12, Color(0.95, 0.93, 0.85), Vector2(0.5, 0.0), 4)
	for k in 2:
		var bpos := Vector3(0.45 + k * 0.1, gy + 0.02, 0.25)
		StreetClutter._cyl(st, Transform3D(Basis(), bpos), 0.035, 0.035, 0.15, [Color(0.85, 0.1, 0.05), Color(0.45, 0.12, 0.08)][k], Vector2(0.3, 0.0), 8)
		StreetClutter._cyl(st, Transform3D(Basis(), bpos + Vector3(0.0, 0.15, 0.0)), 0.025, 0.02, 0.04, Color(0.95, 0.9, 0.2), Vector2(0.4, 0.0), 8)
	# The cooler on the shelf and the cutting board on the vendor's side.
	_box(st, Vector3(0.05, 0.36, 0.0), Vector3(0.55, 0.36, 0.42), 0.03, Color(0.1, 0.38, 0.75), Vector2(0.45, 0.0))
	_box(st, Vector3(0.05, 0.56, 0.0), Vector3(0.57, 0.05, 0.44), 0.02, Color(0.94, 0.94, 0.92), Vector2(0.45, 0.0))
	_box(st, Vector3(0.3, top + 0.11, 0.42), Vector3(0.4, 0.025, 0.2), 0.005, Color(0.78, 0.62, 0.42), Vector2(0.6, 0.0))
	_box(st, Vector3(0.3, top + 0.13, 0.42), Vector3(0.22, 0.006, 0.03), 0.0, Color(0.8, 0.81, 0.82, A_STEEL), Vector2(0.2, 1.0))
	_umbrella_socket(st, UMBRELLA_SOCKET[Kind.FRUIT], top)


static func _elote_cart(st: SurfaceTool) -> void:
	var top := 0.9
	_cart_body(st, 0.62, 0.34, top)
	var steel := Color(0.7, 0.71, 0.72, A_STEEL)
	var rm := Vector2(0.25, 1.0)
	# The big pot of corn with its lid tipped back, the cobs standing in it, and the esquites pot.
	var pot := Vector3(-0.25, top, 0.0)
	StreetClutter._cyl(st, Transform3D(Basis(), pot), 0.24, 0.24, 0.38, steel, rm, 18)
	StreetClutter._cyl(st, Transform3D(Basis(), pot + Vector3(0.0, 0.375, 0.0)), 0.225, 0.225, 0.006, Color(0.45, 0.35, 0.12, A_FOOD), Vector2(0.3, 0.0), 18)
	_xbox(st, Transform3D(Basis(Vector3.RIGHT, 1.1), pot + Vector3(0.0, 0.42, 0.22)), Vector3(0.48, 0.48, 0.015), 0.0, steel, rm)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("vend_elote")
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(0.05, 0.16)
		var base := pot + Vector3(cos(a) * r, 0.25, sin(a) * r)
		var b := Basis(Vector3(sin(a), 0.0, -cos(a)), rng.randf_range(0.1, 0.35))
		StreetClutter._cyl(st, Transform3D(b, base), 0.026, 0.02, 0.22, Color(0.97, 0.82, 0.25, A_FOOD), Vector2(0.4, 0.0), 8)
		StreetClutter._cyl(st, Transform3D(b, base + b * Vector3(0.0, 0.2, 0.0)), 0.012, 0.004, 0.07, Color(0.65, 0.58, 0.35), Vector2(0.7, 0.0), 6)
	var pot2 := Vector3(0.28, top, -0.05)
	StreetClutter._cyl(st, Transform3D(Basis(), pot2), 0.15, 0.15, 0.22, steel, rm, 14)
	StreetClutter._cyl(st, Transform3D(Basis(), pot2 + Vector3(0.0, 0.2, 0.0)), 0.14, 0.14, 0.006, Color(0.95, 0.78, 0.25, A_FOOD), Vector2(0.4, 0.0), 14)
	# Mayonnaise, chile, cotija, butter, limes, a stack of foam cups, a roll of paper towels.
	for k in 3:
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.45, top, 0.18 - k * 0.09)), 0.03, 0.028, 0.18, [Color(0.95, 0.94, 0.86), Color(0.85, 0.15, 0.08), Color(0.95, 0.94, 0.86)][k], Vector2(0.3, 0.0), 8)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.05, top, 0.2)), 0.06, 0.06, 0.08, Color(0.95, 0.94, 0.9), Vector2(0.5, 0.0), 10)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.05, top + 0.08, 0.2)), 0.055, 0.055, 0.004, Color(0.97, 0.96, 0.9, A_FOOD), Vector2(0.6, 0.0), 10)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.22, top, 0.2)), 0.05, 0.05, 0.06, Color(0.98, 0.85, 0.35, A_FOOD), Vector2(0.4, 0.0), 10)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.45, top, -0.18)), 0.045, 0.05, 0.32, Color(0.96, 0.96, 0.95), Vector2(0.5, 0.0), 10)
	StreetClutter._cyl(st, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, top + 0.06, -0.22)), 0.06, 0.06, 0.24, Color(0.96, 0.95, 0.92), Vector2(0.8, 0.0), 10)
	for k in 5:
		_sphere(st, Vector3(-0.1 + k * 0.05, top + 0.03, 0.27), 0.03, Color(0.3, 0.55, 0.12, A_FOOD), Vector2(0.4, 0.0), 6)
	# A cooler below and a hand-lettered card on the front.
	_box(st, Vector3(0.0, 0.36, 0.0), Vector3(0.5, 0.34, 0.4), 0.03, Color(0.85, 0.15, 0.1), Vector2(0.45, 0.0))
	_box(st, Vector3(0.0, 0.55, 0.0), Vector3(0.52, 0.04, 0.42), 0.02, Color(0.94, 0.94, 0.92), Vector2(0.45, 0.0))
	_box(st, Vector3(0.0, top - 0.25, -0.348), Vector3(0.6, 0.3, 0.006), 0.0, Color(0.96, 0.93, 0.82), Vector2(0.8, 0.0))
	var face := Basis(Vector3.UP, PI)
	_text(st, "ELOTES", 0.1, Transform3D(face, Vector3(0.0, top - 0.17, -0.352)), Color(0.8, 0.1, 0.06), 0.55)
	_text(st, "ESQUITES $5", 0.065, Transform3D(face, Vector3(0.0, top - 0.32, -0.352)), Color(0.1, 0.2, 0.55), 0.55)
	_umbrella_socket(st, UMBRELLA_SOCKET[Kind.ELOTE], top)


static func _hotdog_cart(st: SurfaceTool) -> void:
	var top := 0.88
	_cart_body(st, 0.5, 0.3, top)
	var steel := Color(0.6, 0.61, 0.62, A_STEEL)
	var rm := Vector2(0.35, 1.0)
	# The griddle under foil, the bacon-wrapped dogs in rows, onions and peppers piled at one end.
	_box(st, Vector3(-0.05, top + 0.02, 0.0), Vector3(0.82, 0.04, 0.52), 0.005, Color(0.1, 0.1, 0.1), Vector2(0.4, 0.8))
	_box(st, Vector3(-0.05, top + 0.042, 0.0), Vector3(0.78, 0.004, 0.48), 0.0, Color(0.78, 0.77, 0.74, A_STEEL), Vector2(0.45, 1.0))
	for row in 3:
		for k in 5:
			var p := Vector3(-0.38 + k * 0.08, top + 0.07, -0.16 + row * 0.12)
			var b := Basis(Vector3.RIGHT, PI * 0.5)
			StreetClutter._cyl(st, Transform3D(b, p + Vector3(0.0, 0.0, -0.08)), 0.024, 0.024, 0.16, Color(0.48, 0.2, 0.1, A_FOOD), Vector2(0.4, 0.0), 7)
			for w in 3:
				StreetClutter._cyl(st, Transform3D(b, p + Vector3(0.0, 0.0, -0.055 + w * 0.045)), 0.027, 0.027, 0.02, Color(0.35, 0.12, 0.07, A_FOOD), Vector2(0.35, 0.0), 7)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("vend_hotdog")
	for k in 40:
		var c: Color = [Color(0.82, 0.62, 0.3, A_FOOD), Color(0.7, 0.45, 0.2, A_FOOD), Color(0.25, 0.5, 0.12, A_FOOD), Color(0.75, 0.15, 0.08, A_FOOD)][k % 4]
		var r := sqrt(rng.randf()) * 0.13
		var a := rng.randf() * TAU
		var p := Vector3(0.2 + cos(a) * r, top + 0.06 + (0.13 - r) * 0.4, sin(a) * r * 1.4)
		_xbox(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), Vector3(0.05, 0.012, 0.012), 0.0, c, Vector2(0.4, 0.0))
	# Buns in their bag at the end, the squeeze bottles, the propane tank under the cart.
	_box(st, Vector3(0.42, top + 0.06, 0.0), Vector3(0.16, 0.1, 0.4), 0.03, Color(0.9, 0.75, 0.5), Vector2(0.6, 0.0))
	for k in 3:
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.3 + k * 0.07, top + 0.04, 0.24)), 0.025, 0.022, 0.17, [Color(0.8, 0.08, 0.05), Color(0.95, 0.78, 0.1), Color(0.95, 0.94, 0.85)][k], Vector2(0.3, 0.0), 8)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.05, 0.2, 0.0)), 0.15, 0.15, 0.42, Color(0.92, 0.92, 0.9), Vector2(0.4, 0.0), 14)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.05, 0.62, 0.0)), 0.04, 0.04, 0.06, Color(0.65, 0.55, 0.25, A_STEEL), Vector2(0.3, 1.0), 8)
	# The light pole at the back corner, its arm, and a string of bulbs on a wire.
	var pole := Vector3(0.46, top, 0.26)
	var arm_y := 2.15
	StreetClutter._tube(st, [pole, Vector3(pole.x, arm_y, pole.z), Vector3(-0.55, arm_y, pole.z)], 0.018, 8, steel, rm)
	var n := 7
	for k in n:
		var t := float(k) / float(n - 1)
		var x := lerpf(pole.x - 0.05, -0.55, t)
		var sag := sin(t * PI) * 0.16
		var p := Vector3(x, arm_y - 0.04 - sag, pole.z)
		if k > 0:
			var t0 := float(k - 1) / float(n - 1)
			var p0 := Vector3(lerpf(pole.x - 0.05, -0.55, t0), arm_y - 0.04 - sin(t0 * PI) * 0.16, pole.z)
			StreetClutter._tube(st, [p0, p], 0.004, 4, Color(0.05, 0.05, 0.05), Vector2(0.6, 0.0))
		StreetClutter._cyl(st, Transform3D(Basis(), p + Vector3(0.0, -0.035, 0.0)), 0.012, 0.012, 0.035, Color(0.08, 0.08, 0.08), Vector2(0.5, 0.0), 6)
		_sphere(st, p + Vector3(0.0, -0.07, 0.0), 0.03, Color(1.0, 0.78, 0.48, A_BULB), Vector2(0.2, 0.0), 7)
	# A cardboard sign in marker on the front.
	_box(st, Vector3(0.0, top - 0.24, -0.307), Vector3(0.6, 0.3, 0.008), 0.0, Color(0.74, 0.6, 0.42), Vector2(0.9, 0.0))
	var face := Basis(Vector3.UP, PI)
	_text(st, "HOT DOGS", 0.085, Transform3D(face, Vector3(0.0, top - 0.17, -0.312)), Color(0.08, 0.07, 0.06), 0.55)
	_text(st, "BACON $5", 0.075, Transform3D(face, Vector3(0.0, top - 0.3, -0.312)), Color(0.7, 0.08, 0.05), 0.55)


static func _paleta_cart(st: SurfaceTool) -> void:
	var steel := Color(0.66, 0.67, 0.68, A_STEEL)
	var rm := Vector2(0.3, 1.0)
	var white := Color(0.93, 0.93, 0.9)
	# The insulated box on its frame, printed sides, two lids, the push bar with its bells.
	var y0 := 0.3
	var y1 := 0.88
	_box(st, Vector3(0.0, (y0 + y1) * 0.5, 0.0), Vector3(0.82, y1 - y0, 0.56), 0.03, white, Vector2(0.4, 0.0))
	for s: float in [-1.0, 1.0]:
		var z := s * 0.283
		StreetClutter._page(st, Vector3(0.38 * s, y1 - 0.06, z), Vector3(-0.38 * s, y1 - 0.06, z), Vector3(-0.38 * s, y0 + 0.06, z), Vector3(0.38 * s, y0 + 0.06, z),
			Vector3(0.0, 0.0, s), A_PHOTO, Vector2(40.0 + (s + 1.0), 0.0), Vector2(0.45, 0.0))
	for k in 2:
		var lx := -0.2 + k * 0.4
		_box(st, Vector3(lx, y1 + 0.02, 0.0), Vector3(0.38, 0.04, 0.52), 0.015, white, Vector2(0.35, 0.0))
		_box(st, Vector3(lx, y1 + 0.05, -0.2), Vector3(0.12, 0.02, 0.03), 0.005, steel, rm)
	_box(st, Vector3(0.0, y1 - 0.01, 0.0), Vector3(0.84, 0.03, 0.58), 0.005, Color(1, 1, 1, 1), Vector2(0.4, 0.0))
	_box(st, Vector3(0.0, y0 - 0.02, 0.0), Vector3(0.86, 0.04, 0.6), 0.005, steel, rm)
	for s: float in [-1.0, 1.0]:
		var c := Vector3(-0.32, 0.13, s * 0.31)
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * s), c), 0.13, 0.13, 0.04, Color(0.05, 0.05, 0.05), Vector2(0.85, 0.0), 12)
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * s), c + Vector3(0.0, 0.0, s * 0.008)), 0.07, 0.07, 0.04, Color(0.6, 0.6, 0.62, A_STEEL), rm, 8)
		StreetClutter._tube(st, [Vector3(0.36, y0, s * 0.26), Vector3(0.36, 0.03, s * 0.26)], 0.014, 6, steel, rm)
		StreetClutter._tube(st, [Vector3(0.41, y0 + 0.05, s * 0.25), Vector3(0.62, 1.02, s * 0.25)], 0.016, 8, steel, rm)
	StreetClutter._tube(st, [Vector3(0.62, 1.02, -0.27), Vector3(0.62, 1.02, 0.27)], 0.02, 8, Color(0.08, 0.08, 0.08), Vector2(0.8, 0.0))
	for k in 3:
		var bz := -0.12 + k * 0.12
		StreetClutter._tube(st, [Vector3(0.62, 1.0, bz), Vector3(0.62, 0.95, bz)], 0.003, 4, steel, rm)
		_sphere(st, Vector3(0.62, 0.93, bz), 0.022, Color(0.78, 0.62, 0.25, A_STEEL), Vector2(0.25, 1.0), 7)
	if UMBRELLA_SOCKET.has(Kind.PALETA):
		_umbrella_socket(st, UMBRELLA_SOCKET[Kind.PALETA], y1)


static func _flower_stand(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("vend_flowers")
	# A two-step stand of slats, the buckets on it and in front of it, each with a bunch.
	var wood := Color(0.48, 0.34, 0.2)
	_box(st, Vector3(0.0, 0.2, 0.12), Vector3(1.3, 0.04, 0.32), 0.008, wood, Vector2(0.75, 0.0))
	_box(st, Vector3(0.0, 0.42, 0.3), Vector3(1.3, 0.04, 0.3), 0.008, wood, Vector2(0.75, 0.0))
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * 0.62, 0.22, 0.2), Vector3(0.04, 0.44, 0.5), 0.005, wood, Vector2(0.75, 0.0))
	var buckets := [Vector3(-0.45, 0.22, 0.12), Vector3(0.0, 0.22, 0.12), Vector3(0.45, 0.22, 0.12),
		Vector3(-0.3, 0.44, 0.3), Vector3(0.15, 0.44, 0.3), Vector3(-0.55, 0.0, -0.22), Vector3(0.5, 0.0, -0.2)]
	var bunch := [
		[Color(0.75, 0.04, 0.08), 1], [Color(0.98, 0.78, 0.12), 2], [Color(0.95, 0.55, 0.65), 1], [Color(0.97, 0.95, 0.9), 1],
		[Color(0.98, 0.45, 0.1), 3], [Color(0.55, 0.2, 0.6), 3], [Color(0.85, 0.08, 0.12), 1],
	]
	for i in buckets.size():
		var b: Vector3 = buckets[i]
		var bc: Color = [Color(0.12, 0.12, 0.13), Color(0.92, 0.92, 0.9), Color(0.15, 0.4, 0.2), Color(0.9, 0.45, 0.1)][i % 4]
		StreetClutter._cyl(st, Transform3D(Basis(), b), 0.11, 0.14, 0.3, bc, Vector2(0.5, 0.0), 12)
		var col: Color = bunch[i][0]
		var style: int = bunch[i][1]
		for k in 12:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 0.13
			var p := b + Vector3(cos(a) * r, 0.3 + 0.18 + (0.13 - r) * 0.5 + rng.randf_range(0.0, 0.08), sin(a) * r)
			StreetClutter._tube(st, [b + Vector3(cos(a) * r * 0.3, 0.25, sin(a) * r * 0.3), p], 0.004, 3, Color(0.2, 0.42, 0.15), Vector2(0.6, 0.0))
			var c := col.lightened(rng.randf_range(-0.08, 0.1))
			if style == 2:
				# Sunflowers: a gold ring with a brown middle, facing out.
				StreetClutter._cyl(st, Transform3D(Basis(Vector3.RIGHT, -1.2 + rng.randf_range(-0.2, 0.2)), p), 0.055, 0.055, 0.01, Color(c.r, c.g, c.b, A_FOOD), Vector2(0.7, 0.0), 10)
				StreetClutter._cyl(st, Transform3D(Basis(Vector3.RIGHT, -1.2), p + Vector3(0.0, 0.0, -0.006)), 0.025, 0.025, 0.012, Color(0.28, 0.16, 0.06, A_FOOD), Vector2(0.8, 0.0), 8)
			elif style == 3:
				_sphere(st, p, 0.035, Color(c.r, c.g, c.b, A_FOOD), Vector2(0.75, 0.0), 6)
			else:
				# Roses: a tight bud of petals.
				_sphere(st, p, 0.032, Color(c.r, c.g, c.b, A_FOOD), Vector2(0.6, 0.0), 7)
				_sphere(st, p + Vector3(0.0, -0.025, 0.0), 0.025, Color(0.2, 0.42, 0.15, A_FOOD), Vector2(0.7, 0.0), 5)
	# The balloons, on ribbons from a weight beside the stand: foil hearts' and stars' worth of
	# shine as round foil.
	var weight := Vector3(0.75, 0.0, 0.3)
	_box(st, weight + Vector3(0.0, 0.06, 0.0), Vector3(0.14, 0.12, 0.14), 0.02, Color(0.15, 0.15, 0.16), Vector2(0.6, 0.2))
	var foil := [Color(0.85, 0.1, 0.15), Color(0.9, 0.75, 0.25), Color(0.75, 0.78, 0.82), Color(0.25, 0.4, 0.85), Color(0.95, 0.45, 0.65), Color(0.4, 0.75, 0.35)]
	for k in 10:
		var a := TAU * k / 10.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(0.15, 0.4)
		var top := weight + Vector3(cos(a) * r, rng.randf_range(2.0, 2.7), sin(a) * r)
		StreetClutter._tube(st, [weight + Vector3(0.0, 0.12, 0.0), top + Vector3(0.0, -0.2, 0.0)], 0.003, 3, Color(0.92, 0.92, 0.9), Vector2(0.5, 0.0))
		var fc: Color = foil[k % foil.size()]
		_ellipsoid(st, top, Vector3(0.21, 0.2, 0.07), Basis(Vector3.UP, a + rng.randf_range(-0.6, 0.6)), Color(fc.r, fc.g, fc.b), Vector2(0.18, 0.85), 10, 6)


static func _umbrella_socket(st: SurfaceTool, at: Vector3, top: float) -> void:
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(at.x, top - 0.45, at.z)), 0.03, 0.03, 0.5, Color(0.55, 0.56, 0.58, A_STEEL), Vector2(0.3, 1.0), 8)


## A market umbrella: pole, eight canvas panels sagging between their ribs, a scalloped valance.
## Its stripes are the shader's (the angle round the pole), so the mesh is shared by every cart.
static func umbrella_mesh() -> Mesh:
	if _meshes.has(K_UMBRELLA):
		return _meshes[K_UMBRELLA]
	var st := StreetClutter._begin()
	var canvas := Color(0.5, 0.5, 0.5, A_CANVAS)
	var rm := Vector2(0.85, 0.0)
	var steel := Color(0.6, 0.6, 0.62, A_STEEL)
	StreetClutter._tube(st, [Vector3(0.0, 0.4, 0.0), Vector3(0.0, 2.55, 0.0)], 0.02, 8, steel, Vector2(0.3, 1.0))
	var apex := Vector3(0.0, 2.5, 0.0)
	var radius := 1.15
	var rim_y := 2.12
	var panels := 8
	var segs := 4
	for p in panels:
		var a0 := TAU * float(p) / panels
		var a1 := TAU * float(p + 1) / panels
		var am := (a0 + a1) * 0.5
		var rows: Array = []
		for s in segs + 1:
			var f := float(s) / segs
			var y := lerpf(apex.y, rim_y, f) - sin(f * PI) * 0.04
			var r := radius * f
			var mid_sag := 0.05 * f
			rows.append([Vector3(cos(a0) * r, y, sin(a0) * r), Vector3(cos(am) * r * 0.97, y - mid_sag, sin(am) * r * 0.97), Vector3(cos(a1) * r, y, sin(a1) * r)])
		for s in segs:
			var r0: Array = rows[s]
			var r1: Array = rows[s + 1]
			for k in 2:
				var up := Vector3(cos(am), 2.2, sin(am))
				StreetClutter._quad(st, r0[k], r0[k + 1], r1[k + 1], r1[k], up, canvas, rm)
				StreetClutter._quad(st, r0[k], r0[k + 1], r1[k + 1], r1[k], -up, canvas, rm)
		# Valance: a short skirt below the rim, scalloped.
		var e0: Vector3 = rows[segs][0]
		var em: Vector3 = rows[segs][1]
		var e1: Vector3 = rows[segs][2]
		for k in 2:
			var ea: Vector3 = [e0, em][k]
			var eb: Vector3 = [em, e1][k]
			var outward := ((ea + eb) * 0.5 * Vector3(1, 0, 1)).normalized()
			StreetClutter._quad(st, ea, eb, eb + Vector3(0.0, -0.13, 0.0), ea + Vector3(0.0, -0.13, 0.0), outward, canvas, rm)
			StreetClutter._quad(st, ea, eb, eb + Vector3(0.0, -0.13, 0.0), ea + Vector3(0.0, -0.13, 0.0), -outward, canvas, rm)
			StreetClutter._tri(st, ea + Vector3(0.0, -0.13, 0.0), eb + Vector3(0.0, -0.13, 0.0), (ea + eb) * 0.5 + Vector3(0.0, -0.2, 0.0), outward, canvas, rm)
			StreetClutter._tri(st, ea + Vector3(0.0, -0.13, 0.0), eb + Vector3(0.0, -0.13, 0.0), (ea + eb) * 0.5 + Vector3(0.0, -0.2, 0.0), -outward, canvas, rm)
		# A rib under the seam and its stretcher to the pole.
		var tip := Vector3(cos(a0) * radius, rim_y - 0.01, sin(a0) * radius)
		StreetClutter._tube(st, [apex + Vector3(0.0, -0.02, 0.0), tip], 0.007, 4, steel, Vector2(0.3, 1.0))
		StreetClutter._tube(st, [Vector3(0.0, 2.05, 0.0), apex.lerp(tip, 0.55) + Vector3(0.0, -0.02, 0.0)], 0.005, 4, steel, Vector2(0.3, 1.0))
	_sphere(st, apex + Vector3(0.0, 0.05, 0.0), 0.04, Color(0.5, 0.5, 0.5, A_CANVAS), rm, 6)
	return _finish(st, K_UMBRELLA)


# --- Geometry helpers ------------------------------------------------------------------------

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/street_vendor.gdshader")
	return _material


static func _finish(st: SurfaceTool, key: String) -> Mesh:
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes[key] = mesh
	return mesh


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, bevel: float, col: Color, rm: Vector2) -> void:
	StreetClutter._bbox(st, Transform3D(Basis(), c), size, bevel, col, rm)


static func _xbox(st: SurfaceTool, xf: Transform3D, size: Vector3, bevel: float, col: Color, rm: Vector2) -> void:
	StreetClutter._bbox(st, xf, size, bevel, col, rm)


## A cylinder lying along x, from `c` outward (toward `side`'s sign) by `width`.
static func _cylx(st: SurfaceTool, c: Vector3, side: float, r: float, width: float, col: Color, rm: Vector2, sides: int) -> void:
	var b := Basis(Vector3.BACK, -PI * 0.5 * side)
	StreetClutter._cyl(st, Transform3D(b, c - b * Vector3(0.0, width * 0.5, 0.0)), r, r, width, col, rm, sides)


static func _sphere(st: SurfaceTool, c: Vector3, r: float, col: Color, rm: Vector2, seg: int) -> void:
	_ellipsoid(st, c, Vector3(r, r, r), Basis(), col, rm, seg, maxi(seg / 2, 3))


static func _ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, b: Basis, col: Color, rm: Vector2, seg: int, rings: int) -> void:
	var grid: Array = []
	for i in rings + 1:
		var v := PI * float(i) / rings
		var row: Array = []
		for j in seg:
			var u := TAU * float(j) / seg
			var d := Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
			row.append([c + b * (d * r), (b * (d / r)).normalized()])
		grid.append(row)
	for i in rings:
		for j in seg:
			var p00: Array = grid[i][j]
			var p01: Array = grid[i][(j + 1) % seg]
			var p10: Array = grid[i + 1][j]
			var p11: Array = grid[i + 1][(j + 1) % seg]
			StreetClutter._smooth_quad(st, p00[0], p01[0], p11[0], p10[0], p00[1], p01[1], p11[1], p10[1], col, rm)


## Lettering (TextMesh outlines, coarse curves) into the mesh, centred at `xf`'s origin, facing
## its +z, at most `max_w` wide; `col` must not be pure white (that is the paint code).
static func _text(st: SurfaceTool, text: String, height: float, xf: Transform3D, col: Color, max_w: float) -> void:
	var key := "%s|%.3f" % [text, height]
	var geo: Array
	if _text_cache.has(key):
		geo = _text_cache[key]
	else:
		var tm := TextMesh.new()
		tm.text = text
		tm.font_size = 40
		tm.pixel_size = height / 40.0 * 1.4
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
		var lo := INF
		var hi := -INF
		for v in verts:
			lo = minf(lo, v.x)
			hi = maxf(hi, v.x)
		geo = [verts, idx, maxf(hi - lo, 0.0)]
		_text_cache[key] = geo
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var squeeze := minf(1.0, max_w / maxf(float(geo[2]), 0.001))
	if col.is_equal_approx(Color.WHITE):
		col = Color(0.98, 0.98, 0.97)
	var n := xf.basis.z.normalized()
	var rm := Vector2(0.4, 0.0)
	for k in range(0, idx.size() - 2, 3):
		var a := xf * (verts[idx[k]] * Vector3(squeeze, 1.0, 0.0))
		var b := xf * (verts[idx[k + 1]] * Vector3(squeeze, 1.0, 0.0))
		var c := xf * (verts[idx[k + 2]] * Vector3(squeeze, 1.0, 0.0))
		StreetClutter._tri(st, a, b, c, n, col, rm)


## Builds every mesh once (the loading screen), so the first vendor street does not stall, and
## hands back the material to draw once through a MultiMesh.
static func warm() -> Array:
	if not enabled:
		return []
	for i in TRUCKS.size():
		truck(i)
	for kind: int in CART_KEYS:
		cart(kind)
	umbrella_mesh()
	return [material()]
