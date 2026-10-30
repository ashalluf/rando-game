class_name StreetClutter2
extends RefCounted
## The small stuff of a lived-in Los Angeles street, the second pass after StreetClutter's news
## boxes and gutter litter: black trash bags piled at the kerb on collection nights and outside
## restaurants, flattened cardboard leaning by shop doors, a loaded hand truck by a delivery,
## steam rising from manholes and kerb inlets downtown, shopping carts left on the pavement (some
## tipped over), weeds in the cracks at the foot of the walls, cigarette butts and gum at the bus
## stops, puddles that stay in the road's dips after rain, traffic cones left round a utility cut,
## lost-pet and band flyers stapled round the utility poles, newspaper pages blowing along the
## gutter, and pigeon droppings on the pavement under the ledges.
##
## Every mesh is built here in code at real size and wears ONE material
## (shaders/street_clutter_2.gdshader: what a face is in the vertex colour's alpha, `C_*` / 16),
## except the steam, which is a transparent plume on its own (shaders/street_steam.gdshader). One
## batch per kind a chunk (`K_*`), FULL chunks only, each drawn to its own distance; the flat
## kinds cast nothing, the upright ones only within a few tens of metres (set_shadow_reach).
##
## Seeding: one build step of a FULL chunk, after everything the chunk lays (StreetWear's step,
## so the furniture, the parked cars, the road hardware and the shop fronts are all down). Every
## roll is a hash of the seed and the place (h01), never a chunk, block or Building rng, and
## nothing goes through CityChunk._add_prop: the block's props keep their ids, nothing else moves.
## What is out depends on the hour the chunk is built at (bags on collection nights, the dolly by
## day) and the weekday (BeachLife.hour_now, FarmersMarket.weekday), like the vendors.
##
## `STREET_CLUTTER_2=0` in the environment is the A/B (nothing laid). Static: call with the chunk.

# --- Tunables --------------------------------------------------------------------------------

static var enabled: bool = OS.get_environment("STREET_CLUTTER_2") != "0"
## Tests and stills: the hour and weekday to plan for (-1 = the scene's DayNight).
## SC2_HOUR / SC2_DAY in the environment set them for stills.
static var force_hour: float = float(OS.get_environment("SC2_HOUR")) if OS.get_environment("SC2_HOUR") != "" else -1.0
static var force_day: int = int(OS.get_environment("SC2_DAY")) if OS.get_environment("SC2_DAY") != "" else -1

## Chance a commercial block's kerb is a collection night tonight (a hash of block and weekday).
const COLLECTION_ODDS := [0.45, 0.35, 0.2, 0.3, 0.3, 0.35]
## Bag piles per metre of kerb on a collection night.
const BAG_PILE_EVERY := 14.0
## Collection nights run from the evening to the early morning.
const COLLECTION_FROM := 18.5
const COLLECTION_TO := 7.0
## A restaurant's or cafe's own pile by its door, any hour (by district).
const RESTAURANT_BAG_ODDS := [0.75, 0.6, 0.35, 0.4, 0.4, 0.55]
## Flattened cardboard leaning by a shop's door (by district).
const CARDBOARD_ODDS := [0.3, 0.22, 0.08, 0.2, 0.1, 0.15]
## A hand truck loaded with cases by a shop door, by day.
const DOLLY_ODDS := 0.08
const DOLLY_HOURS := Vector2(6.0, 18.0)
## Steam out of a cover or kerb inlet (by district: downtown's old steam lines).
const STEAM_ODDS := [0.32, 0.06, 0.0, 0.08, 0.0, 0.0]
## Shopping carts per block face (by district), and the share tipped on their side.
const CART_ODDS := [0.35, 0.22, 0.08, 0.25, 0.05, 0.12]
const CART_TIPPED := 0.35
## Weed tufts per metre of wall foot / kerb back (by district).
const WEEDS_PER_M := [0.05, 0.07, 0.11, 0.16, 0.05, 0.09]
## Butts-and-gum patches: one at every bus stop, and this many more per shopfront metre.
const BUTTS_PER_SHOP_M := [0.012, 0.007, 0.002, 0.004, 0.006, 0.006]
## Puddles in the dips per metre of kerb.
const PUDDLES_PER_M := [0.05, 0.05, 0.06, 0.08, 0.04, 0.05]
## Cones round a utility cut (RoadHardware's "cut" records).
const CONE_ODDS := 0.4
## Flyer sleeves on utility poles.
const POSTER_ODDS := 0.5
## Newspaper pages blowing along a kerb (per kerb, by district).
const PAPER_ODDS := [0.55, 0.35, 0.15, 0.4, 0.2, 0.3]
## Pigeon droppings under the ledges (per metre of wall, by district).
const DROPPINGS_PER_M := [0.07, 0.03, 0.0, 0.02, 0.01, 0.02]

## Draw distances (metres; a chunk's batch is measured from its bounds' centre).
const DRAW_BAGS := 140.0
const DRAW_CARD := 110.0
const DRAW_CART := 140.0
const DRAW_CONE := 140.0
const DRAW_DOLLY := 110.0
const DRAW_STEAM := 220.0
const DRAW_WEEDS := 70.0
const DRAW_BUTTS := 45.0
const DRAW_PUDDLE := 160.0
const DRAW_POSTER := 80.0
const DRAW_PAPER := 90.0
const DRAW_DROP := 60.0
## Shadow reach of the upright kinds.
const SHADOW_REACH := 45.0
## Clearance kept from anything already on the pavement.
const CLEAR := 0.6
## How far in from a kerb the pavement's own pieces stand (the pavement ring).
const KERB_IN := 0.45

## Batch keys (one draw each a chunk).
const K_BAGS := "sc2_bags_"
const BAG_VARIANTS := 2
const K_CARD := "sc2_card"
const K_CART := "sc2_cart"
const K_CONE := "sc2_cone"
const K_DOLLY := "sc2_dolly"
const K_STEAM := "sc2_steam"
const K_WEEDS := "sc2_weeds"
const K_BUTTS := "sc2_butts"
const K_PUDDLE := "sc2_puddle"
const K_POSTER := "sc2_poster"
const K_PAPER := "sc2_paper"
const K_DROP := "sc2_drop"
const KEYS := [K_BAGS + "0", K_BAGS + "1", K_CARD, K_CART, K_CONE, K_DOLLY, K_STEAM, K_WEEDS, K_BUTTS, K_PUDDLE, K_POSTER, K_PAPER, K_DROP]
## The keys laid flat on the ground (tilted to its slope, never casting).
const FLAT_KEYS := [K_WEEDS, K_BUTTS, K_PUDDLE, K_PAPER, K_DROP]

## Surface codes in the vertex colour's alpha (x 16), mirrored by street_clutter_2.gdshader.
const C_FIXED := 0
const C_BAG := 1
const C_CARD := 2
const C_WIRE := 3
const C_PLASTIC := 4
const C_CONE := 5
const C_WEED := 6
const C_BUTT := 7
const C_GUM := 8
const C_DROP := 9
const C_POSTER := 10
const C_PAPER := 11
const C_PUDDLE := 12
const C_RUBBER := 13
const C_STEEL := 14
const C_CRACK := 15

static var _meshes: Dictionary = {}
static var _announced := false


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


# --- Placement ---------------------------------------------------------------------------------

## The build step (CityChunk's FULL step list, after StreetWear).
static func build(chunk: CityChunk) -> void:
	if not enabled or chunk.level != CityChunk.Level.FULL or chunk.capturing:
		return
	if not _announced:
		_announced = true
		print("STREET_CLUTTER_2 on")
	if chunk.zone != MacroMap.Zone.CITY:
		return
	var plan: CityPlan = chunk.plan
	if plan.marina_block(chunk.ix, chunk.iz) or plan.river_block(chunk.ix, chunk.iz):
		return
	var replica: ReplicaAreas = plan.macro.replica if plan.macro else null
	if replica != null and replica.block_role(plan, chunk.ix, chunk.iz) != 0:
		return
	var block := plan.block(chunk.ix, chunk.iz)
	if block.has("site") or block.has("grounds") or block.has("hospital") or int(block.kind) != CityPlan.BlockKind.BUILDINGS:
		return
	var ctx := plan_block(chunk, block)
	lay(chunk, ctx)


## Everything this chunk gets, as {kind: [[key, Transform3D (before the relief), custom], ...]}.
## Pure given the chunk's built state (its shop fronts, furniture, road hardware, poles).
static func plan_block(chunk: CityChunk, block: Dictionary) -> Dictionary:
	var plan: CityPlan = chunk.plan
	var rect: Rect2 = block.rect
	var district := int(block.district)
	var hour := hour_of(chunk)
	var day := weekday_of(chunk)
	var ctx := {"chunk": chunk, "plan": plan, "rect": rect, "district": district, "hour": hour, "day": day,
		"occupied": StreetClutter._occupied(chunk), "out": {}, "walls": StreetDetail._footprints(chunk)}
	var edges := CityChunk._sidewalk_edges(rect)
	var fronts := _shop_fronts(chunk, rect)
	_shop_things(ctx, fronts)
	_collection(ctx, edges)
	_carts(ctx, edges)
	_bus_stop_butts(ctx, fronts)
	_steam(ctx)
	_cones(ctx)
	_posters(ctx)
	_kerb_things(ctx, edges)
	_wall_things(ctx, edges)
	return ctx


## Adds the plan's instances to the chunk's batch and sets each kind's draw, shadow and tilt.
static func lay(chunk: CityChunk, ctx: Dictionary) -> void:
	var batch: MultiMeshBatch = chunk._batch
	for key: String in FLAT_KEYS:
		batch.tilt_keys[key] = true
	var out: Dictionary = ctx.out
	for key: String in out:
		var mesh := mesh_for(key)
		for it: Array in out[key]:
			batch.add(key, mesh, it[0], Color.WHITE, it[1])
	for pair: Array in [[K_BAGS + "0", DRAW_BAGS], [K_BAGS + "1", DRAW_BAGS], [K_CARD, DRAW_CARD], [K_CART, DRAW_CART],
			[K_CONE, DRAW_CONE], [K_DOLLY, DRAW_DOLLY], [K_STEAM, DRAW_STEAM], [K_WEEDS, DRAW_WEEDS], [K_BUTTS, DRAW_BUTTS],
			[K_PUDDLE, DRAW_PUDDLE], [K_POSTER, DRAW_POSTER], [K_PAPER, DRAW_PAPER], [K_DROP, DRAW_DROP]]:
		batch.set_draw_distance(pair[0], pair[1])
	for key: String in [K_STEAM, K_POSTER] + FLAT_KEYS:
		batch.set_no_shadow(key)
	for key: String in [K_BAGS + "0", K_BAGS + "1", K_CARD, K_CART, K_CONE, K_DOLLY]:
		batch.set_shadow_reach(key, SHADOW_REACH)
	chunk.set_meta("street_clutter_2", out)


static func mesh_for(key: String) -> Mesh:
	match key:
		K_CARD: return cardboard()
		K_CART: return cart()
		K_CONE: return cone()
		K_DOLLY: return dolly()
		K_STEAM: return steam()
		K_WEEDS: return weeds()
		K_BUTTS: return butts()
		K_PUDDLE: return puddle()
		K_POSTER: return posters()
		K_PAPER: return paper()
		K_DROP: return droppings()
	return bags(int(key.substr(K_BAGS.length())))


static func hour_of(node: Node) -> float:
	return force_hour if force_hour >= 0.0 else BeachLife.hour_now(node)


static func weekday_of(node: Node) -> int:
	return force_day if force_day >= 0 else FarmersMarket.weekday(node)


static func _put(ctx: Dictionary, key: String, x: Transform3D, custom: Color) -> void:
	var out: Dictionary = ctx.out
	if not out.has(key):
		out[key] = []
	(out[key] as Array).append([x, custom])


static func _free(ctx: Dictionary, p: Vector2, half: float) -> bool:
	return StreetClutter._clear(ctx.occupied, p, half)


static func _take(ctx: Dictionary, p: Vector2, half: float) -> void:
	(ctx.occupied as Array).append([p, half])


## Ground-floor shop fronts of the chunk's buildings that face this block's kerbs: [foot (x, z),
## outward normal, width, room, key hash]. Building records them when any reader is on.
static func _shop_fronts(chunk: CityChunk, rect: Rect2) -> Array:
	var out: Array = []
	for child in chunk.get_children():
		var b := child as Building
		if b == null:
			continue
		for f: Array in b.shop_fronts:
			var p: Vector3 = b.transform * (f[0] as Vector3)
			var n: Vector3 = (b.transform.basis * (f[1] as Vector3)).normalized()
			var p2 := Vector2(p.x, p.z)
			if not rect.grow(0.5).has_point(p2):
				continue
			out.append([p2, Vector2(n.x, n.z).normalized(), float(f[2]), int(f[3]), hash([b.seed, int(f[4])])])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[4] < y[4])
	return out


## Depth of the pavement from a shop front out to its kerb (along its normal), or -1.
static func _kerb_depth(rect: Rect2, p: Vector2, n: Vector2) -> float:
	var d := -1.0
	if n.y > 0.7:
		d = rect.end.y - p.y
	elif n.y < -0.7:
		d = p.y - rect.position.y
	elif n.x > 0.7:
		d = rect.end.x - p.x
	elif n.x < -0.7:
		d = p.x - rect.position.x
	return d


static func _yaw(v: Vector2) -> float:
	return atan2(-v.x, -v.y)


## Restaurants' bags, cardboard, the hand truck and gum by the shops' doors.
static func _shop_things(ctx: Dictionary, fronts: Array) -> void:
	var plan: CityPlan = ctx.plan
	var district: int = ctx.district
	var hour: float = ctx.hour
	var day_time := hour >= DOLLY_HOURS.x and hour < DOLLY_HOURS.y
	for f: Array in fronts:
		var p: Vector2 = f[0]
		var n: Vector2 = f[1]
		var width: float = f[2]
		var room: int = f[3]
		var key: int = f[4]
		var depth := _kerb_depth(ctx.rect, p, n)
		if depth < 2.2 or depth > 14.0:
			continue
		var along := Vector2(-n.y, n.x)
		var hk := [plan.seed, "sc2_shop", key]
		var food := room == Building.ShopRoom.CAFE or room == Building.ShopRoom.RESTAURANT
		# A restaurant's pile: against the wall at the end of its front, or at the kerb at night.
		if food and h01(hk + ["bags"]) < float(RESTAURANT_BAG_ODDS[district]):
			var side := 1.0 if h01(hk + ["side"]) < 0.5 else -1.0
			var at_kerb := (hour >= 20.0 or hour < 6.0) and h01(hk + ["kerb"]) < 0.6
			var q := p + along * side * (width * 0.5 - 0.6) + n * (depth - KERB_IN - 0.35 if at_kerb else 0.45)
			if _free(ctx, q, 0.55):
				_take(ctx, q, 0.55)
				var y := _yaw(-n) + (h01(hk + ["yaw"]) - 0.5) * 0.8
				_put(ctx, K_BAGS + str(int(h01(hk + ["v"]) * BAG_VARIANTS)), _xf(q, y, 0.85 + 0.3 * h01(hk + ["s"])), Color(h01(hk + ["tone"]), 0.0, 0.0, 0.0))
		# Flattened boxes leaning on the wall beside the door.
		if h01(hk + ["card"]) < float(CARDBOARD_ODDS[district]) * (1.4 if room == Building.ShopRoom.RETAIL or room == Building.ShopRoom.CLOTHING else 1.0):
			var side := -1.0 if h01(hk + ["cside"]) < 0.5 else 1.0
			var q := p + along * side * clampf(width * 0.5 - 0.7, 0.5, 3.0) + n * 0.2
			if _free(ctx, q, 0.6):
				_take(ctx, q, 0.6)
				_put(ctx, K_CARD, _xf(q, _yaw(-n) + PI + (h01(hk + ["cy"]) - 0.5) * 0.12, 1.0), Color(h01(hk + ["print"]), h01(hk + ["cwear"]), 0.0, 0.0))
		# A hand truck of cases by the door while a delivery is on.
		if day_time and h01(hk + ["dolly", int(hour)]) < DOLLY_ODDS:
			var q := p + along * (0.9 if h01(hk + ["dside"]) < 0.5 else -0.9) + n * 0.45
			if _free(ctx, q, 0.45):
				_take(ctx, q, 0.45)
				_put(ctx, K_DOLLY, _xf(q, _yaw(-n) + PI + (h01(hk + ["dy"]) - 0.5) * 0.3, 1.0), Color(h01(hk + ["dpaint"]), 0.0, 0.0, 0.0))
		# Butts and gum spread on the pavement in front of the door (more downtown, bars).
		if h01(hk + ["gum"]) < float(BUTTS_PER_SHOP_M[district]) * width * (2.5 if food else 1.0):
			var q := p + n * clampf(depth * 0.45, 1.0, 3.0) + along * (h01(hk + ["gx"]) - 0.5) * width * 0.5
			_put(ctx, K_BUTTS, _xf(q, h01(hk + ["gy"]) * TAU, 1.0, CityChunk.SIDEWALK_TOP + 0.002), Color(h01(hk + ["gseed"]), 0.6, 0.0, 0.0))


## Collection night: bag piles along every kerb of the block, a hash of block and weekday.
static func _collection(ctx: Dictionary, edges: Array) -> void:
	var plan: CityPlan = ctx.plan
	var hour: float = ctx.hour
	var district: int = ctx.district
	if not (hour >= COLLECTION_FROM or hour < COLLECTION_TO):
		return
	# The night belongs to the day the bags went out before midnight.
	var night_day := posmod(int(ctx.day) - (1 if hour < COLLECTION_TO else 0), 7)
	var chunk: CityChunk = ctx.chunk
	if h01([plan.seed, "sc2_collect", chunk.ix, chunk.iz, night_day]) >= float(COLLECTION_ODDS[district]):
		return
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var n := int(length / BAG_PILE_EVERY)
		for i in n:
			var hk := [plan.seed, "sc2_pile", chunk.ix, chunk.iz, e, i]
			var t := (float(i) + 0.3 + 0.4 * h01(hk + ["t"])) * length / float(n)
			if t < 7.0 or t > length - 7.0:
				continue
			var q := a + dir * t + inward * (KERB_IN + 0.15)
			if not _free(ctx, q, 0.6):
				continue
			_take(ctx, q, 0.6)
			_put(ctx, K_BAGS + str(int(h01(hk + ["v"]) * BAG_VARIANTS)), _xf(q, _yaw(inward) + (h01(hk + ["y"]) - 0.5) * 1.2, 0.85 + 0.35 * h01(hk + ["s"])), Color(h01(hk + ["tone"]), 0.0, 0.0, 0.0))


## Shopping carts left on the pavement, upright against something or tipped over.
static func _carts(ctx: Dictionary, edges: Array) -> void:
	var plan: CityPlan = ctx.plan
	var chunk: CityChunk = ctx.chunk
	var odds: float = CART_ODDS[ctx.district]
	for e in edges.size():
		var hk := [plan.seed, "sc2_cart", chunk.ix, chunk.iz, e]
		if h01(hk) >= odds:
			continue
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		if length < 24.0:
			continue
		var dir := (b - a) / length
		var t := lerpf(9.0, length - 9.0, h01(hk + ["t"]))
		var q := a + dir * t + inward * (KERB_IN + 0.6 + 1.2 * h01(hk + ["in"]))
		if not _free(ctx, q, 0.75):
			continue
		_take(ctx, q, 0.75)
		var yaw := h01(hk + ["yaw"]) * TAU
		var x := _xf(q, yaw, 1.0)
		if h01(hk + ["tip"]) < CART_TIPPED:
			x = _tipped(x, cart(), h01(hk + ["tside"]) < 0.5)
		_put(ctx, K_CART, x, Color(h01(hk + ["seed"]), h01(hk + ["rust"]), 0.0, 0.0))


## A cart on its side: turned 90 degrees about its length, and lifted so its lowest point rests
## on the pavement.
static func _tipped(x: Transform3D, mesh: Mesh, left: bool) -> Transform3D:
	var turn := Basis(Vector3.FORWARD, (PI * 0.5 - 0.06) * (1.0 if left else -1.0))
	var b := x.basis * turn
	var box := Transform3D(b, Vector3.ZERO) * mesh.get_aabb()
	return Transform3D(b, x.origin - Vector3(0.0, box.position.y, 0.0))


## Butts and gum round the bus stops' shelters.
static func _bus_stop_butts(ctx: Dictionary, _fronts: Array) -> void:
	var chunk: CityChunk = ctx.chunk
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) != "bus_stop":
			continue
		var p: Vector3 = r.position
		var hk := [ctx.plan.seed, "sc2_stop", snappedf(p.x, 0.1), snappedf(p.z, 0.1)]
		for k in 2:
			var q := Vector2(p.x, p.z) + Vector2(h01(hk + [k, "x"]) - 0.5, h01(hk + [k, "z"]) - 0.5) * 3.2
			_put(ctx, K_BUTTS, _xf(q, h01(hk + [k, "y"]) * TAU, 1.0, CityChunk.SIDEWALK_TOP + 0.002), Color(h01(hk + [k, "seed"]), 1.0, 0.0, 0.0))


## Steam rising out of covers and kerb inlets (RoadHardware's records), downtown.
static func _steam(ctx: Dictionary) -> void:
	var odds: float = STEAM_ODDS[ctx.district]
	if odds <= 0.0:
		return
	var chunk: CityChunk = ctx.chunk
	for r: Dictionary in chunk.get_meta("road_hardware", []):
		var kind := String(r.kind)
		if kind != "cover" and kind != "inlet":
			continue
		var p: Vector2 = r.pos
		var hk := [ctx.plan.seed, "sc2_steam", snappedf(p.x, 0.1), snappedf(p.y, 0.1)]
		if h01(hk) >= odds * (0.6 if kind == "inlet" else 1.0):
			continue
		var y := CityChunk.ROAD_TOP + (0.05 if kind == "cover" else 0.12)
		var q := p
		if kind == "inlet":
			q = p - (r.inward as Vector2) * 0.25
		_put(ctx, K_STEAM, _xf(q, h01(hk + ["yaw"]) * TAU, 0.8 + 0.5 * h01(hk + ["s"]), y), Color(h01(hk + ["phase"]), 0.45 + 0.55 * h01(hk + ["strength"]), 1.0 if kind == "inlet" else 0.0, 0.0))


## Cones left round a utility cut (RoadHardware's "cut" records): three to five in a ring, one
## knocked over now and then.
static func _cones(ctx: Dictionary) -> void:
	var chunk: CityChunk = ctx.chunk
	for r: Dictionary in chunk.get_meta("road_hardware", []):
		if String(r.kind) != "cut":
			continue
		var p: Vector2 = r.pos
		var hk := [ctx.plan.seed, "sc2_cones", snappedf(p.x, 0.1), snappedf(p.y, 0.1)]
		if h01(hk) >= CONE_ODDS:
			continue
		var size: Vector2 = r.size
		var rad := maxf(size.x, size.y) * 0.5 + 0.45
		var n := 3 + int(h01(hk + ["n"]) * 3.0)
		var a0 := h01(hk + ["a0"]) * TAU
		for i in n:
			var ang := a0 + TAU * float(i) / float(n) + (h01(hk + [i, "j"]) - 0.5) * 0.4
			var q := p + Vector2(cos(ang), sin(ang)) * rad
			var x := _xf(q, h01(hk + [i, "y"]) * TAU, 1.0, CityChunk.ROAD_TOP)
			if h01(hk + [i, "down"]) < 0.12:
				x = _knocked(x)
			_put(ctx, K_CONE, x, Color(h01(hk + [i, "wear"]), 0.0, 0.0, 0.0))


## A cone lying on its side, its base resting on the road.
static func _knocked(x: Transform3D) -> Transform3D:
	var tilt := Basis(Vector3.RIGHT, PI * 0.5 - 0.17)
	return Transform3D(x.basis * tilt, x.origin + x.basis * Vector3(0.0, 0.17, 0.0))


## Flyer sleeves stapled round the utility poles' shafts ("upole" in the chunk's batch).
static func _posters(ctx: Dictionary) -> void:
	var chunk: CityChunk = ctx.chunk
	var data: Dictionary = chunk._batch.data()
	if not data.has("upole"):
		return
	for x: Transform3D in data["upole"].xforms:
		var o := x.origin
		var hk := [ctx.plan.seed, "sc2_flyer", snappedf(o.x, 0.1), snappedf(o.z, 0.1)]
		if h01(hk) >= POSTER_ODDS:
			continue
		# The shaft's foot before the relief (the batch adds it again), its radius at the flyers.
		var foot_y := o.y - StreetDetail.POLE_HEIGHT * 0.5 - chunk._gy(o.x, o.z)
		var r := 0.157
		var b := Basis(Vector3.UP, h01(hk + ["yaw"]) * TAU).scaled(Vector3(r, 1.0, r))
		_put(ctx, K_POSTER, Transform3D(b, Vector3(o.x, foot_y, o.z)), Color(h01(hk + ["seed"]), h01(hk + ["age"]), 0.0, 0.0))


## Puddles in the gutter's dips and blowing newspaper pages along the kerb.
static func _kerb_things(ctx: Dictionary, edges: Array) -> void:
	var plan: CityPlan = ctx.plan
	var chunk: CityChunk = ctx.chunk
	var district: int = ctx.district
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		if length < 16.0:
			continue
		var dir := (b - a) / length
		var mid := (a + b) * 0.5
		var axis := CityPlan.AXIS_X if absf(inward.x) > 0.5 else CityPlan.AXIS_Z
		var index := (chunk.ix if inward.x > 0.0 else chunk.ix + 1) if axis == CityPlan.AXIS_X else (chunk.iz if inward.y > 0.0 else chunk.iz + 1)
		if not plan.road_open(axis, index, mid.y if axis == CityPlan.AXIS_X else mid.x):
			continue
		var hk := [plan.seed, "sc2_kerb", chunk.ix, chunk.iz, e]
		# Puddles: in the gutter and the parking lane, at the corners' ramps and in hashed dips.
		var count := int(length * float(PUDDLES_PER_M[district]) * (0.5 + h01(hk + ["pn"])))
		for i in count:
			var t := lerpf(4.0, length - 4.0, h01(hk + [i, "pt"]))
			var out := 0.25 + 1.8 * pow(h01(hk + [i, "po"]), 1.5)
			var q := a + dir * t - inward * out
			var s := Vector3(0.9 + 2.6 * h01(hk + [i, "pl"]), 1.0, 0.6 + 1.2 * h01(hk + [i, "pw"]))
			var basis := Basis(Vector3.UP, _yaw(inward) + (h01(hk + [i, "pa"]) - 0.5) * 0.5).scaled_local(s)
			_put(ctx, K_PUDDLE, Transform3D(basis, Vector3(q.x, CityChunk.ROAD_TOP + 0.006, q.y)), Color(h01(hk + [i, "pseed"]), 0.35 + 0.65 * h01(hk + [i, "pdeep"]), 0.0, 0.0))
		# The corner ramps hold water: one at each end now and then.
		for k in 2:
			if h01(hk + [k, "corner"]) < 0.35:
				var q := a + dir * (2.4 if k == 0 else length - 2.4) - inward * 0.45
				var basis := Basis(Vector3.UP, _yaw(inward)).scaled_local(Vector3(1.6, 1.0, 0.9))
				_put(ctx, K_PUDDLE, Transform3D(basis, Vector3(q.x, CityChunk.ROAD_TOP + 0.006, q.y)), Color(h01(hk + [k, "cseed"]), 0.8, 0.0, 0.0))
		# Newspaper pages blowing along the gutter (down the kerb, `dir` or back).
		if h01(hk + ["paper"]) < float(PAPER_ODDS[district]):
			var n := 1 + int(h01(hk + ["pages"]) * 2.0)
			for i in n:
				var run := 7.0 + 8.0 * h01(hk + [i, "run"])
				var back := h01(hk + [i, "way"]) < 0.5
				var t0 := lerpf(4.0, length - 4.0 - run, h01(hk + [i, "t0"]))
				if t0 < 4.0:
					continue
				var start := a + dir * (t0 + (run if back else 0.0)) - inward * (0.25 + 0.35 * h01(hk + [i, "o"]))
				var d := -dir if back else dir
				# Local +X runs along the page's run; the run's length rides in custom.b (/ 32 m).
				var basis := Basis(Vector3.UP, atan2(-d.y, d.x))
				_put(ctx, K_PAPER, Transform3D(basis, Vector3(start.x, CityChunk.ROAD_TOP + 0.004, start.y)), Color(h01(hk + [i, "ph"]), h01(hk + [i, "pseed"]), run / 32.0, 0.0))


## Along the walls: weeds in the cracks at their foot and along the kerb's back, and pigeon
## droppings under the ledges.
static func _wall_things(ctx: Dictionary, edges: Array) -> void:
	var plan: CityPlan = ctx.plan
	var chunk: CityChunk = ctx.chunk
	var district: int = ctx.district
	var walls: Array[Rect2] = ctx.walls
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		if length < 12.0:
			continue
		var dir := (b - a) / length
		var hk := [plan.seed, "sc2_wall", chunk.ix, chunk.iz, e]
		var count := int(length * float(WEEDS_PER_M[district]))
		for i in count:
			var t := lerpf(3.0, length - 3.0, h01(hk + [i, "wt"]))
			var kerb := a + dir * t
			var wall := StreetClutter._wall_depth(walls, kerb, inward) if not walls.is_empty() else StreetClutter.BOARD_FRONTAGE + 1.0
			# At the wall's foot where a building stands at the back of the pavement (further in, a
			# footprint is usually behind a forecourt's planters), else in the joint behind the kerb.
			var depth := wall - 0.06 if wall < 5.0 and h01(hk + [i, "where"]) < 0.5 else 0.32 + 0.05 * h01(hk + [i, "d"])
			var q := kerb + inward * depth
			if not _free(ctx, q, 0.15):
				continue
			var yaw := _yaw(-inward) + (0.0 if depth > 1.0 else PI)
			_put(ctx, K_WEEDS, _xf(q, yaw + (h01(hk + [i, "wy"]) - 0.5) * 0.2, 0.7 + 0.6 * h01(hk + [i, "ws"]), CityChunk.SIDEWALK_TOP), Color(h01(hk + [i, "wseed"]), h01(hk + [i, "dry"]), 0.0, 0.0))
		var drops := int(length * float(DROPPINGS_PER_M[district]))
		for i in drops:
			var t := lerpf(3.0, length - 3.0, h01(hk + [i, "dt"]))
			var kerb := a + dir * t
			var wall := StreetClutter._wall_depth(walls, kerb, inward) if not walls.is_empty() else StreetClutter.BOARD_FRONTAGE + 1.0
			if wall > 5.5:
				continue
			var q := kerb + inward * (wall - 0.25 - 0.3 * h01(hk + [i, "dd"]))
			_put(ctx, K_DROP, _xf(q, h01(hk + [i, "dy"]) * TAU, 0.6 + 0.8 * h01(hk + [i, "ds"]), CityChunk.SIDEWALK_TOP + 0.003), Color(h01(hk + [i, "dseed"]), h01(hk + [i, "dfresh"]), 0.0, 0.0))


static func _xf(p: Vector2, yaw: float, scale: float = 1.0, y: float = CityChunk.SIDEWALK_TOP) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(p.x, y, p.y))


# --- Materials -----------------------------------------------------------------------------------

static func material() -> ShaderMaterial:
	if _meshes.has("mat"):
		return _meshes["mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/street_clutter_2.gdshader")
	_meshes["mat"] = mat
	return mat


static func steam_material() -> ShaderMaterial:
	if _meshes.has("steam_mat"):
		return _meshes["steam_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/street_steam.gdshader")
	_meshes["steam_mat"] = mat
	return mat


# --- Meshes ------------------------------------------------------------------------------------
# Origin at the base, Y up. Built with StreetClutter's helpers (UV metres or 0..1 on a printed
# face, UV2 = roughness, metallic), every colour sRGB, the code in the alpha (x 16).

static func _c(rgb: Color, code: int) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, float(code) / 16.0)


static func _finish(st: SurfaceTool, key: String) -> Mesh:
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes[key] = mesh
	return mesh


## One 33-gallon bag, tied: a lumpy squashed ellipsoid resting on y 0, the neck gathered into a
## knot on top. `size` its half extents (x, height, z), `lean` tips its top.
static func _bag(st: SurfaceTool, c: Vector3, size: Vector3, yaw: float, lean: Vector2, rng: RandomNumberGenerator, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var rings := 7
	var sectors := 12
	var grid: Array = []
	var bumps: Array = []
	for j in sectors:
		bumps.append(rng.randf_range(0.82, 1.12))
	for i in rings + 1:
		var v := float(i) / float(rings)
		var row: Array = []
		# Profile: a flat-ish bottom, full belly, gathered neck.
		var prof := sin(pow(v, 0.8) * PI) * (1.0 - 0.75 * smoothstep(0.78, 1.0, v))
		prof = maxf(prof, 0.06 if v > 0.5 else 0.0)
		var hgt := size.y * (1.0 - cos(v * PI)) * 0.5
		for j in sectors:
			var u := TAU * float(j) / float(sectors)
			var wob: float = bumps[j] * (1.0 + 0.08 * sin(u * 3.0 + v * 5.0 + c.x * 7.0))
			var r := Vector3(cos(u) * size.x, 0.0, sin(u) * size.z) * prof * wob
			var p := r + Vector3(0.0, hgt, 0.0) + Vector3(lean.x, 0.0, lean.y) * v * v
			p.y = maxf(p.y, 0.0)
			row.append(c + b * p)
		grid.append(row)
	var centre := c + b * Vector3(0.0, size.y * 0.45, 0.0)
	var rm := Vector2(0.3, 0.0)
	for i in rings:
		for j in sectors:
			var p00: Vector3 = grid[i][j]
			var p01: Vector3 = grid[i][(j + 1) % sectors]
			var p10: Vector3 = grid[i + 1][j]
			var p11: Vector3 = grid[i + 1][(j + 1) % sectors]
			var out := (p00 + p01 + p10 + p11) * 0.25 - centre
			StreetClutter._quad(st, p00, p01, p11, p10, out, col, rm)
	# The knot and its two ears.
	var top: Vector3 = c + b * (Vector3(0.0, size.y, 0.0) + Vector3(lean.x, 0.0, lean.y))
	StreetClutter._cyl(st, Transform3D(Basis(), top - Vector3(0.0, 0.02, 0.0)), 0.035, 0.025, 0.06, col, rm, 6)
	for s in [-1.0, 1.0]:
		var ear := b * Vector3(s * 0.07, 0.05, rng.randf_range(-0.03, 0.03))
		StreetClutter._tri(st, top + Vector3(0.0, 0.03, 0.0), top + ear, top + ear * 0.6 + Vector3(0.0, 0.06, 0.0), b * Vector3(0, 0, 1), col, rm)
		StreetClutter._tri(st, top + Vector3(0.0, 0.03, 0.0), top + ear * 0.6 + Vector3(0.0, 0.06, 0.0), top + ear, b * Vector3(0, 0, -1), col, rm)


## A pile of tied black bags (`variant` 0..1): four to six, leaning on each other, one on top.
## About 1.4 x 0.9 m, faces -Z to the street.
static func bags(variant: int) -> Mesh:
	var key := K_BAGS + str(variant)
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["sc2_bags", variant])
	var st := StreetClutter._begin()
	var black := _c(Color(0.035, 0.035, 0.04), C_BAG)
	var spots := [Vector3(-0.42, 0, 0.08), Vector3(0.05, 0, 0.14), Vector3(0.48, 0, 0.02), Vector3(-0.2, 0, -0.34), Vector3(0.3, 0, -0.32)]
	if variant == 1:
		spots = [Vector3(-0.3, 0, 0.1), Vector3(0.28, 0, 0.12), Vector3(0.0, 0, -0.33), Vector3(0.62, 0, -0.18)]
	for i in spots.size():
		var col := black
		if (variant == 0 and i == 3) or (variant == 1 and i == 2):
			col = _c(Color(0.16, 0.15, 0.13), C_BAG)
		elif variant == 1 and i == 3:
			col = _c(Color(0.05, 0.11, 0.07), C_BAG)
		var size := Vector3(rng.randf_range(0.26, 0.33), rng.randf_range(0.5, 0.68), rng.randf_range(0.24, 0.31))
		_bag(st, spots[i], size, rng.randf_range(0.0, TAU), Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)), rng, col)
	# One more slumped on top of the others.
	_bag(st, Vector3(0.05, 0.42, 0.02), Vector3(0.3, 0.42, 0.26), rng.randf_range(0.0, TAU), Vector2(0.18, 0.0), rng, black)
	return _finish(st, key)


## A bundle of flattened boxes leaning on the wall (the wall at +Z, the street at -Z), one more
## lying flat in front, a strap round the leaning ones.
static func cardboard() -> Mesh:
	if _meshes.has(K_CARD):
		return _meshes[K_CARD]
	var st := StreetClutter._begin()
	var kraft := [Color(0.62, 0.47, 0.3), Color(0.68, 0.53, 0.35), Color(0.56, 0.42, 0.27), Color(0.72, 0.6, 0.44)]
	var rm := Vector2(0.92, 0.0)
	var sheets := [[0.95, 0.72, -0.03], [0.82, 0.86, 0.04], [1.08, 0.62, -0.1], [0.7, 0.8, 0.12]]
	for i in sheets.size():
		var w: float = sheets[i][0]
		var h: float = sheets[i][1]
		var off: float = sheets[i][2]
		var lean := 0.24 + 0.03 * i
		var b := Basis(Vector3.RIGHT, lean)
		var foot := Vector3(off, 0.0, -sin(lean) * h - 0.03 * i)
		var x := Transform3D(b, foot + b * Vector3(0.0, h * 0.5, 0.0) + Vector3(0.0, 0.0, -0.012 * i))
		StreetClutter._bbox(st, x, Vector3(w, h, 0.008), 0.002, _c(kraft[i], C_CARD), rm)
	# The strap.
	var steel := _c(Color(0.12, 0.12, 0.13), C_FIXED)
	var lean0 := 0.26
	var sb := Basis(Vector3.RIGHT, lean0)
	StreetClutter._bbox(st, Transform3D(sb, Vector3(0.0, 0.36, -sin(lean0) * 0.4 - 0.05)), Vector3(1.02, 0.025, 0.07), 0.002, steel, Vector2(0.5, 0.2))
	# A flat one on the pavement in front, a little folded.
	var fb := Basis(Vector3.UP, 0.2) * Basis(Vector3.RIGHT, -PI * 0.5 + 0.03)
	StreetClutter._bbox(st, Transform3D(fb, Vector3(0.25, 0.006, -0.62)), Vector3(0.9, 0.62, 0.008), 0.002, _c(kraft[1], C_CARD), rm)
	return _finish(st, K_CARD)


## A shopping cart: wire basket over a chassis on four casters, the plastic handle bar and its
## child seat flap; 0.95 m long (handle at -Z... +Z), the basket's rim 0.98 m up.
static func cart() -> Mesh:
	if _meshes.has(K_CART):
		return _meshes[K_CART]
	var st := StreetClutter._begin()
	var wire := _c(Color(0.7, 0.71, 0.72), C_WIRE)
	var chrome := _c(Color(0.72, 0.73, 0.74), C_FIXED)
	var rm_c := Vector2(0.3, 1.0)
	var plastic := _c(Color(0.42, 0.07, 0.06), C_PLASTIC)
	# Basket: bottom at y 0.48, tapering toward the nose (-Z).
	var y0 := 0.48
	var y1 := 0.98
	var bot := [Vector3(-0.23, y0, -0.42), Vector3(0.23, y0, -0.42), Vector3(0.24, y0, 0.36), Vector3(-0.24, y0, 0.36)]
	var top := [Vector3(-0.27, y1, -0.52), Vector3(0.27, y1, -0.52), Vector3(0.28, y1, 0.42), Vector3(-0.28, y1, 0.42)]
	var c := Vector3(0.0, 0.73, 0.0)
	for i in 4:
		var j := (i + 1) % 4
		var face_c: Vector3 = (bot[i] + bot[j] + top[i] + top[j]) * 0.25
		# Both sides of every wire panel (it is a grid you see through).
		StreetClutter._quad(st, bot[i], bot[j], top[j], top[i], face_c - c, wire, rm_c)
		StreetClutter._quad(st, bot[i], bot[j], top[j], top[i], c - face_c, wire, rm_c)
	StreetClutter._quad(st, bot[0], bot[1], bot[2], bot[3], Vector3.UP, wire, rm_c)
	StreetClutter._quad(st, bot[0], bot[1], bot[2], bot[3], Vector3.DOWN, wire, rm_c)
	# The rim tube round the top and the corners.
	for i in 4:
		StreetClutter._tube(st, [top[i], top[(i + 1) % 4]], 0.009, 6, chrome, rm_c)
		StreetClutter._tube(st, [bot[i], top[i]], 0.007, 5, chrome, rm_c)
	# Handle bar (plastic over steel) on two uprights behind the basket.
	for s in [-1.0, 1.0]:
		StreetClutter._tube(st, [Vector3(0.27 * s, y1, 0.42), Vector3(0.27 * s, 1.03, 0.5)], 0.011, 6, chrome, rm_c)
	StreetClutter._tube(st, [Vector3(-0.29, 1.03, 0.5), Vector3(0.29, 1.03, 0.5)], 0.02, 8, plastic, Vector2(0.45, 0.0))
	# The child seat's flap folded against the back.
	StreetClutter._quad(st, Vector3(-0.2, 0.62, 0.37), Vector3(0.2, 0.62, 0.37), Vector3(0.21, 0.93, 0.4), Vector3(-0.21, 0.93, 0.4), Vector3(0, 0, 1), plastic, Vector2(0.5, 0.0))
	StreetClutter._quad(st, Vector3(-0.2, 0.62, 0.37), Vector3(0.2, 0.62, 0.37), Vector3(0.21, 0.93, 0.4), Vector3(-0.21, 0.93, 0.4), Vector3(0, 0, -1), plastic, Vector2(0.5, 0.0))
	# Chassis: two side rails low down, the bottom tray's struts, and the casters.
	for s in [-1.0, 1.0]:
		StreetClutter._tube(st, [Vector3(0.22 * s, 0.12, -0.45), Vector3(0.25 * s, 0.12, 0.38), Vector3(0.25 * s, y0, 0.38)], 0.012, 6, chrome, rm_c)
		StreetClutter._tube(st, [Vector3(0.22 * s, 0.12, -0.45), Vector3(0.23 * s, y0, -0.42)], 0.012, 6, chrome, rm_c)
	StreetClutter._quad(st, Vector3(-0.21, 0.14, -0.38), Vector3(0.21, 0.14, -0.38), Vector3(0.23, 0.14, 0.3), Vector3(-0.23, 0.14, 0.3), Vector3.UP, wire, rm_c)
	StreetClutter._quad(st, Vector3(-0.21, 0.14, -0.38), Vector3(0.21, 0.14, -0.38), Vector3(0.23, 0.14, 0.3), Vector3(-0.23, 0.14, 0.3), Vector3.DOWN, wire, rm_c)
	var rubber := _c(Color(0.05, 0.05, 0.05), C_RUBBER)
	for wp: Vector3 in [Vector3(-0.21, 0.0, -0.42), Vector3(0.21, 0.0, -0.42), Vector3(-0.24, 0.0, 0.34), Vector3(0.24, 0.0, 0.34)]:
		StreetClutter._bbox(st, Transform3D(Basis(), wp + Vector3(0.0, 0.1, 0.0)), Vector3(0.04, 0.03, 0.06), 0.006, chrome, rm_c)
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), wp + Vector3(-0.012, 0.05, 0.0)), 0.05, 0.05, 0.024, rubber, Vector2(0.7, 0.0), 10)
	return _finish(st, K_CART)


## A 28" traffic cone: a 36 cm square base, the cone to 71 cm, two reflective collars.
static func cone() -> Mesh:
	if _meshes.has(K_CONE):
		return _meshes[K_CONE]
	var st := StreetClutter._begin()
	var orange := _c(Color(0.93, 0.33, 0.06), C_CONE)
	var base := _c(Color(0.06, 0.06, 0.06), C_RUBBER)
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, 0.018, 0.0)), Vector3(0.36, 0.036, 0.36), 0.03, base, Vector2(0.8, 0.0))
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)), 0.135, 0.022, 0.68, orange, Vector2(0.45, 0.0), 16)
	return _finish(st, K_CONE)


## A hand truck leaning back on its wheels with three cases strapped on: 1.2 m rails, 25 cm
## wheels, the toe plate on the pavement. The wall at +Z.
static func dolly() -> Mesh:
	if _meshes.has(K_DOLLY):
		return _meshes[K_DOLLY]
	var st := StreetClutter._begin()
	var paint := _c(Color(1, 1, 1), C_STEEL)
	var rm := Vector2(0.45, 0.4)
	var lean := Basis(Vector3.RIGHT, 0.32)
	var o := Vector3(0.0, 0.125, 0.12)
	for s in [-1.0, 1.0]:
		var rail: Array = []
		for k in 6:
			var t := float(k) / 5.0
			var y := t * 1.22
			var z := 0.0 if t < 0.85 else (t - 0.85) * 0.25
			rail.append(o + lean * Vector3(0.2 * s, y, z))
		StreetClutter._tube(st, rail, 0.014, 6, paint, rm)
		var tyre := _c(Color(0.05, 0.05, 0.05), C_RUBBER)
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.22 if s > 0.0 else -0.28, 0.125, 0.12)), 0.125, 0.125, 0.06, tyre, Vector2(0.8, 0.0), 14)
	# Cross bars and the handle loop.
	for y in [0.35, 0.7, 1.0]:
		StreetClutter._tube(st, [o + lean * Vector3(-0.2, y, 0.0), o + lean * Vector3(0.2, y, 0.0)], 0.01, 5, paint, rm)
	StreetClutter._tube(st, [o + lean * Vector3(-0.2, 1.22, 0.04), o + lean * Vector3(-0.12, 1.3, 0.07), o + lean * Vector3(0.12, 1.3, 0.07), o + lean * Vector3(0.2, 1.22, 0.04)], 0.012, 6, _c(Color(0.05, 0.05, 0.05), C_RUBBER), Vector2(0.7, 0.0))
	# Axle and toe plate (on the pavement in front of the rails).
	StreetClutter._tube(st, [Vector3(-0.27, 0.125, 0.12), Vector3(0.27, 0.125, 0.12)], 0.01, 5, _c(Color(0.5, 0.5, 0.52), C_FIXED), Vector2(0.3, 0.9))
	StreetClutter._bbox(st, Transform3D(lean, Vector3(0.0, 0.012, -0.03)), Vector3(0.36, 0.008, 0.22), 0.002, paint, rm)
	# Three cases stacked on the toe plate, leaning with the truck.
	var case_cols := [Color(0.64, 0.5, 0.32), Color(0.55, 0.42, 0.27), Color(0.66, 0.55, 0.38)]
	var hy := 0.03
	for i in 3:
		var h := [0.3, 0.26, 0.3][i] as float
		var c := lean * Vector3(0.0, hy + h * 0.5, -0.2)
		StreetClutter._bbox(st, Transform3D(lean * Basis(Vector3.UP, 0.04 * (i - 1)), Vector3(0.0, 0.02, 0.0) + c), Vector3(0.42, h, 0.33), 0.006, _c(case_cols[i], C_CARD), Vector2(0.9, 0.0))
		hy += h + 0.004
	return _finish(st, K_DOLLY)


## The steam plume: four tall quads crossed round the vertical axis, each 0..1 in UV (v up),
## turned to the camera and drifted by the wind in shaders/street_steam.gdshader. 0.8 m wide at
## the bottom, 4 m tall.
static func steam() -> Mesh:
	if _meshes.has(K_STEAM):
		return _meshes[K_STEAM]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := 4
	for k in parts:
		var y0 := float(k) * 0.9
		var y1 := y0 + 1.6
		# Each puff is a quad around the axis; the shader turns it to the camera and spreads it.
		var corners := [Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.5, 1.0), Vector2(-0.5, 1.0)]
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			for i: int in tri:
				var cv: Vector2 = corners[i]
				st.set_uv(Vector2(cv.x + 0.5, cv.y))
				st.set_uv2(Vector2(float(k), y0))
				st.set_color(Color(1, 1, 1, 1))
				st.set_normal(Vector3(0, 0, 1))
				st.add_vertex(Vector3(cv.x, lerpf(y0, y1, cv.y), 0.0))
	var mesh := st.commit()
	mesh.surface_set_material(0, steam_material())
	# The shader moves every vertex: give the culler the whole plume.
	mesh.custom_aabb = AABB(Vector3(-2.0, -0.2, -2.0), Vector3(4.0, 5.2, 4.0))
	_meshes[K_STEAM] = mesh
	return mesh


## A weed tuft in a crack: a dozen blades and a dandelion rosette, with the crack it grows from
## running 0.7 m along local X (the wall's foot or the kerb's back).
static func weeds() -> Mesh:
	if _meshes.has(K_WEEDS):
		return _meshes[K_WEEDS]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("sc2_weeds")
	var st := StreetClutter._begin()
	var crack := _c(Color(0.05, 0.05, 0.045), C_CRACK)
	var x := -0.35
	var zz := 0.0
	while x < 0.35:
		var nx := x + rng.randf_range(0.05, 0.11)
		var nz := clampf(zz + rng.randf_range(-0.02, 0.02), -0.03, 0.03)
		var w0 := 0.004 + 0.008 * (1.0 - absf(x) / 0.35)
		var w1 := 0.004 + 0.008 * (1.0 - absf(nx) / 0.35)
		StreetClutter._quad(st, Vector3(x, 0.001, zz - w0), Vector3(nx, 0.001, nz - w1), Vector3(nx, 0.001, nz + w1), Vector3(x, 0.001, zz + w0), Vector3.UP, crack, Vector2(1.0, 0.0))
		x = nx
		zz = nz
	var green := [Color(0.24, 0.36, 0.12), Color(0.33, 0.42, 0.16), Color(0.2, 0.3, 0.1), Color(0.42, 0.44, 0.2)]
	for i in 14:
		var base := Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.02, 0.02))
		var h := rng.randf_range(0.07, 0.24)
		var ang := rng.randf_range(0.0, TAU)
		var lean := Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(0.02, 0.09)
		var side := Vector3(-sin(ang), 0.0, cos(ang)) * rng.randf_range(0.005, 0.009)
		var col := _c(green[rng.randi() % green.size()], C_WEED)
		var mid := base + lean * 0.4 + Vector3(0.0, h * 0.55, 0.0)
		var tip := base + lean + Vector3(0.0, h, 0.0)
		var n := Vector3(cos(ang), 0.4, sin(ang))
		StreetClutter._quad(st, base - side, base + side, mid + side * 0.7, mid - side * 0.7, n, col, Vector2(0.75, 0.0))
		StreetClutter._quad(st, base - side, base + side, mid + side * 0.7, mid - side * 0.7, -n, col, Vector2(0.75, 0.0))
		StreetClutter._tri(st, mid - side * 0.7, mid + side * 0.7, tip, n, col, Vector2(0.75, 0.0))
		StreetClutter._tri(st, mid - side * 0.7, mid + side * 0.7, tip, -n, col, Vector2(0.75, 0.0))
	# A rosette of toothed leaves flat on the paving.
	var leaf := _c(Color(0.22, 0.34, 0.11), C_WEED)
	for i in 7:
		var ang := TAU * float(i) / 7.0 + rng.randf_range(-0.2, 0.2)
		var d := Vector3(cos(ang), 0.0, sin(ang))
		var s := Vector3(-d.z, 0.0, d.x)
		var l := rng.randf_range(0.07, 0.12)
		var c0 := Vector3(0.1, 0.006, 0.0)
		var p1 := c0 + d * l * 0.45 + s * 0.016 + Vector3(0.0, 0.012, 0.0)
		var p2 := c0 + d * l + Vector3(0.0, 0.01, 0.0)
		var p3 := c0 + d * l * 0.45 - s * 0.016 + Vector3(0.0, 0.012, 0.0)
		StreetClutter._tri(st, c0, p1, p2, Vector3.UP, leaf, Vector2(0.6, 0.0))
		StreetClutter._tri(st, c0, p2, p3, Vector3.UP, leaf, Vector2(0.6, 0.0))
	return _finish(st, K_WEEDS)


## A patch of pavement round a stop or a door, 2.4 x 1.6 m: cigarette butts (filter and paper),
## blackened gum, a few bottle caps.
static func butts() -> Mesh:
	if _meshes.has(K_BUTTS):
		return _meshes[K_BUTTS]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("sc2_butts")
	var st := StreetClutter._begin()
	for i in 28:
		var p := Vector3(rng.randf_range(-1.2, 1.2) * sqrt(rng.randf()), 0.0, rng.randf_range(-0.8, 0.8) * sqrt(rng.randf()))
		var yaw := rng.randf_range(0.0, TAU)
		var d := Vector3(cos(yaw), 0.0, sin(yaw))
		var flat := rng.randf() < 0.3
		var r := 0.0042 * (0.6 if flat else 1.0)
		var filt := _c(Color(0.78, 0.56, 0.3) if rng.randf() < 0.7 else Color(0.85, 0.83, 0.78), C_BUTT)
		var paper := _c(Color(0.86, 0.84, 0.8), C_BUTT)
		var ash := _c(Color(0.2, 0.19, 0.18), C_BUTT)
		var a := p + Vector3(0.0, r, 0.0)
		var m := a + d * 0.02
		var e := m + d * rng.randf_range(0.008, 0.018)
		StreetClutter._tube(st, [a, m], r, 4, filt, Vector2(0.8, 0.0))
		StreetClutter._tube(st, [m, e], r, 4, paper, Vector2(0.8, 0.0))
		StreetClutter._tube(st, [e, e + d * 0.003], r * 0.9, 4, ash, Vector2(0.9, 0.0))
	for i in 34:
		var p := Vector3(rng.randf_range(-1.2, 1.2), 0.0015, rng.randf_range(-0.8, 0.8))
		var r := rng.randf_range(0.007, 0.014)
		var g := rng.randf_range(0.12, 0.3)
		var col := _c(Color(g, g, g * 0.95), C_GUM)
		var pts: Array = []
		for k in 7:
			var ang := TAU * float(k) / 7.0
			pts.append(p + Vector3(cos(ang), 0.0, sin(ang)) * r * rng.randf_range(0.75, 1.2))
		for k in 7:
			StreetClutter._tri(st, p + Vector3(0.0, 0.0006, 0.0), pts[k], pts[(k + 1) % 7], Vector3.UP, col, Vector2(0.55, 0.0))
	var caps := [Color(0.75, 0.75, 0.76), Color(0.7, 0.55, 0.15), Color(0.6, 0.1, 0.08)]
	for i in 3:
		var p := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-0.7, 0.7))
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2)), p), 0.015, 0.014, 0.004, _c(caps[i], C_FIXED), Vector2(0.35, 0.9), 8)
	return _finish(st, K_BUTTS)


## A puddle: a unit quad (scaled per instance) whose outline and depth the shader draws from the
## road's wetness, so it is there only after rain and shrinks as the street dries.
static func puddle() -> Mesh:
	if _meshes.has(K_PUDDLE):
		return _meshes[K_PUDDLE]
	var st := StreetClutter._begin()
	var col := Color(1, 1, 1, float(C_PUDDLE) / 16.0)
	var n := 4
	for i in n:
		for j in n:
			var x0 := -0.5 + float(i) / n
			var x1 := -0.5 + float(i + 1) / n
			var z0 := -0.5 + float(j) / n
			var z1 := -0.5 + float(j + 1) / n
			for tri: Array in [[Vector2(x0, z0), Vector2(x1, z1), Vector2(x1, z0)], [Vector2(x0, z0), Vector2(x0, z1), Vector2(x1, z1)]]:
				for v: Vector2 in tri:
					StreetClutter._vtx(st, Vector3(v.x, 0.0, v.y), Vector3.UP, v + Vector2(0.5, 0.5), col, Vector2(0.05, 0.0))
	return _finish(st, K_PUDDLE)


## Flyers stapled round a pole (radius 1, scaled per instance to the shaft): four to six sheets
## at 1.9-2.6 m, each wrapped part way round, a corner curled off, the oldest torn. UV 0..1 over
## each sheet, its whole part picking the design.
static func posters() -> Mesh:
	if _meshes.has(K_POSTER):
		return _meshes[K_POSTER]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("sc2_posters")
	var st := StreetClutter._begin()
	var sheets := 6
	for s in sheets:
		var w := rng.randf_range(0.2, 0.3)
		var h := rng.randf_range(0.26, 0.4)
		var y0 := rng.randf_range(1.85, 2.45)
		var a0 := rng.randf_range(0.0, TAU)
		var off := 1.02 + 0.012 * s
		# Arc length w on a 0.157 m pole is the angle w / 0.157.
		var span := w / 0.157
		var cols := 6
		var rows := 4
		var code := float(C_POSTER) / 16.0
		var grid: Array = []
		for j in rows + 1:
			var row: Array = []
			var v := float(j) / rows
			for i in cols + 1:
				var u := float(i) / cols
				var ang := a0 + (u - 0.5) * span
				var rr := off
				# The bottom outer corner curls off the pole.
				if s % 2 == 0 and v > 0.7 and u > 0.75:
					rr += (v - 0.7) * (u - 0.75) * 4.0
				row.append([Vector3(cos(ang) * rr, y0 + h * (1.0 - v), sin(ang) * rr), Vector3(cos(ang), 0.0, sin(ang)), Vector2(u + float(s), v)])
			grid.append(row)
		for j in rows:
			for i in cols:
				var q := [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
				for tri: Array in [[0, 1, 2], [0, 2, 3]]:
					var pa: Vector3 = q[tri[0]][0]
					var pb: Vector3 = q[tri[1]][0]
					var pc: Vector3 = q[tri[2]][0]
					var nrm: Vector3 = q[tri[0]][1]
					var order: Array = tri if (pc - pa).cross(pb - pa).dot(nrm) >= 0.0 else [tri[0], tri[2], tri[1]]
					for k: int in order:
						StreetClutter._vtx(st, q[k][0], q[k][1], q[k][2], Color(1, 1, 1, code), Vector2(0.9, 0.0))
		# Staples at the top corners.
		for u: float in [0.08, 0.92]:
			var ang := a0 + (u - 0.5) * span
			var pp := Vector3(cos(ang) * (off + 0.02), y0 + h - 0.02, sin(ang) * (off + 0.02))
			StreetClutter._bbox(st, Transform3D(Basis(Vector3.UP, -ang), pp), Vector3(0.02, 0.003, 0.012), 0.0, _c(Color(0.65, 0.65, 0.66), C_FIXED), Vector2(0.3, 1.0))
	return _finish(st, K_POSTER)


## A newspaper page: 0.56 x 0.38 m, a 7 x 5 grid the shader lifts, flutters and slides along
## local +X down the gutter (UV 0..1 over the page).
static func paper() -> Mesh:
	if _meshes.has(K_PAPER):
		return _meshes[K_PAPER]
	var st := StreetClutter._begin()
	var code := Color(1, 1, 1, float(C_PAPER) / 16.0)
	var nx := 7
	var nz := 5
	for i in nx:
		for j in nz:
			var u0 := float(i) / nx
			var u1 := float(i + 1) / nx
			var v0 := float(j) / nz
			var v1 := float(j + 1) / nz
			for tri: Array in [[Vector2(u0, v0), Vector2(u1, v1), Vector2(u1, v0)], [Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1)]]:
				for v: Vector2 in tri:
					StreetClutter._vtx(st, Vector3((v.x - 0.5) * 0.56, 0.0, (v.y - 0.5) * 0.38), Vector3.UP, v, code, Vector2(0.85, 0.0))
	var mesh := _finish(st, K_PAPER)
	# The page travels up to 15 m along +X and lifts up to a metre: give the culler all of it.
	mesh.custom_aabb = AABB(Vector3(-0.6, -0.1, -1.0), Vector3(16.5, 1.6, 2.0))
	return mesh


## Pigeon droppings: a 0.6 m quad of white splashes the shader draws (cut out), lying flat.
static func droppings() -> Mesh:
	if _meshes.has(K_DROP):
		return _meshes[K_DROP]
	var st := StreetClutter._begin()
	var col := Color(1, 1, 1, float(C_DROP) / 16.0)
	for tri: Array in [[Vector2(0, 0), Vector2(1, 1), Vector2(1, 0)], [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]]:
		for v: Vector2 in tri:
			StreetClutter._vtx(st, Vector3((v.x - 0.5) * 0.6, 0.0, (v.y - 0.5) * 0.6), Vector3.UP, v, col, Vector2(0.7, 0.0))
	return _finish(st, K_DROP)


## Builds every mesh (the loading screen; ~tens of ms).
static func warm() -> void:
	if not enabled:
		return
	for key: String in KEYS:
		mesh_for(key)
