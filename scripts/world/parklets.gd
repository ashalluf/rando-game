class_name Parklets
extends RefCounted
## Outdoor dining parklets (GAME_PLAN G5 street life): the timber decks Los Angeles restaurants
## and cafes build out into the parking lane in front of their door - planters along the traffic
## side, slatted screens at the ends, a delineator post and a wheel stop out on the road, bistro
## tables under canvas umbrellas, and a festoon of bulbs strung between four posts that burns
## after dark. Diners sit at the tables on the crowd's own seated clips (ParkletDiner, a
## Pedestrian), a waiter walks between the shop's door and the tables.
##
## Where: a FULL chunk's buildings record every ground-floor shop's front (Building.shop_fronts);
## a CAFE or a RESTAURANT (the room its name says, Building.shop_room(), the same as its glass
## shows) on the block's +x or +z face, standing at the back of the pavement, on an open road with
## a parking lane, rolls a parklet from a hash of the seed and the shop's key (ODDS by district).
## Never across a corner's crosswalk, a bus stop, a red kerb or driveway, a fire or police
## station's kerb, a vendor's truck, road works or a bike lane, or another parklet.
##
## Every roll is a hash of the seed and the shop (and the hour the chunk is built at for who is
## sitting there), never the block rng. The parked cars keep off a parklet's stretch AFTER all
## their rolls (blocks_parking(), CityChunk._park_car), counting it as parked, so the block's
## stream is unmoved; nothing goes through CityChunk._add_prop (the deck's collision is its own
## body), so the block's prop ids are unmoved too. FULL chunks only: from further away a deck
## in the parking lane is a parked car's worth of pixels. `PARKLETS=0` in the environment is the
## A/B. Static: call with the chunk.

# --- Tunables --------------------------------------------------------------------------------

## Chance a cafe or restaurant on a street face has a parklet, by district.
const ODDS := {
	CityPlan.District.DOWNTOWN: 0.45,
	CityPlan.District.MIDTOWN: 0.6,
	CityPlan.District.BEACHTOWN: 0.65,
	CityPlan.District.SUBURBS: 0.35,
	CityPlan.District.CAMPUS: 0.3,
}
## Most parklets on one block.
const MAX_PER_BLOCK := 3
## Most diners and waiters a chunk spawns (one build step each).
const MAX_PEOPLE := 18
## How far from the block's corners a parklet keeps (the crosswalks, the corner ramps, the
## signal poles), in metres along the kerb from the pavement's end.
const CORNER_KEEP := 11.0
## How far back from the kerb a shopfront may stand and still have the street's parklet (m).
const FRONT_REACH := 9.5
## A parked car keeps this far clear of the deck's ends (m, beyond its half length).
const CAR_CLEAR := 2.8
## Draw distances (m) and shadow reach.
const DECK_DRAW := 170.0
const SET_DRAW := 95.0
const UMBRELLA_DRAW := 140.0
const PLANT_DRAW := 85.0
const SHADOW_DISTANCE := 50.0
## Umbrella canvases (sRGB): the restaurant's colour, one per parklet.
const CANVAS := [Color(0.93, 0.91, 0.84), Color(0.12, 0.2, 0.32), Color(0.6, 0.12, 0.1),
	Color(0.15, 0.32, 0.22), Color(0.82, 0.62, 0.32), Color(0.18, 0.18, 0.18), Color(0.85, 0.42, 0.18)]
## Planter paints (sRGB): black steel, deep green, terracotta, charcoal, cream, teal.
const PLANTER_PAINT := [Color(0.08, 0.08, 0.085), Color(0.12, 0.24, 0.16), Color(0.45, 0.27, 0.19),
	Color(0.22, 0.22, 0.23), Color(0.86, 0.82, 0.72), Color(0.1, 0.36, 0.38)]
## Rattan weave second colours (sRGB): natural, white, black, navy, red, green (the chairs).
const WEAVE := [Color(0.55, 0.42, 0.26), Color(0.9, 0.9, 0.86), Color(0.08, 0.08, 0.09),
	Color(0.12, 0.16, 0.3), Color(0.55, 0.1, 0.08), Color(0.16, 0.32, 0.2)]
## The warm pool of the festoon on the deck and the pavement after dark.
const POOL := Color(1.0, 0.72, 0.42, 0.75)
## Batch keys.
const K_DECK := "parklet_deck_"
const K_SET := "parklet_set_"
const K_UMBRELLA := "parklet_umbrella_"

## Hours of the day to force while building (tests and stills); < 0 reads the DayNight clock.
static var force_hour: float = -1.0
## Off: no parklets at all (the A/B, `PARKLETS=0` in the environment).
static var enabled: bool = OS.get_environment("PARKLETS") != "0"


# --- Placement -------------------------------------------------------------------------------

## Whether this chunk's block can have parklets at all (cheap: the step is only queued if so).
static func wanted(chunk: CityChunk, block: Dictionary) -> bool:
	if chunk.level != CityChunk.Level.FULL or chunk.plan == null:
		return false
	return wanted_block(block)


## Whether a block (CityPlan.block()) can have parklets: plain buildings in a district with odds.
static func wanted_block(block: Dictionary) -> bool:
	if not enabled:
		return false
	if block.has("site") or block.has("grounds") or block.has("chinatown"):
		return false
	if int(block.get("kind", CityPlan.BlockKind.BUILDINGS)) != CityPlan.BlockKind.BUILDINGS:
		return false
	return ODDS.has(int(block.get("district", -1)))


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


## How busy a cafe (or a restaurant) is at `hour`: the share of its chairs taken.
static func busy(room: int, hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if room == Building.ShopRoom.CAFE:
		if h < 6.5 or h >= 22.0:
			return 0.0
		if h < 11.0:
			return 0.6
		if h < 14.5:
			return 0.75
		if h < 17.5:
			return 0.5
		return 0.3
	if h < 11.0 and h >= 2.0:
		return 0.0
	if h < 11.5 or h >= 23.5 or h < 2.0:
		return 0.15 if h >= 11.0 else 0.0
	if h < 14.5:
		return 0.7
	if h < 17.5:
		return 0.25
	if h < 22.0:
		return 0.85
	return 0.45


## Whether `hour` is after dark for the restaurants (when a closed one leaves its deck dark).
static func evening(hour: float) -> bool:
	var h := fposmod(hour, 24.0)
	return h >= 19.0 or h < 6.0


## The parklets of this chunk's block, from its buildings' shop fronts: pure in the buildings
## (no rolls but hashes), so tests ask it directly. Each is {c (the kerb point at the middle,
## chunk space), dir (along the kerb, the deck's +x), out (into the road, its +z), length, key,
## room, front (the shop door's foot on the pavement), face}.
static func plan_chunk(chunk: CityChunk, block: Dictionary) -> Array:
	var plan := chunk.plan
	var rect: Rect2 = block.rect
	var odds := float(ODDS.get(int(block.get("district", -1)), 0.0))
	var fronts: Array = []
	for child in chunk.get_children():
		var b := child as Building
		if b == null:
			continue
		for f: Array in b.shop_fronts:
			var room := int(f[3])
			if room != Building.ShopRoom.CAFE and room != Building.ShopRoom.RESTAURANT:
				continue
			var p: Vector3 = b.transform * (f[0] as Vector3)
			var n: Vector3 = (b.transform.basis * (f[1] as Vector3)).normalized()
			fronts.append([Vector2(p.x, p.z), Vector2(n.x, n.z), float(f[2]), room, hash([b.seed, int(f[4])]), int(f[4])])
	# Stable order whatever order the buildings were added in.
	fronts.sort_custom(func(x: Array, y: Array) -> bool: return x[4] < y[4])
	var out: Array = []
	for f: Array in fronts:
		var p: Vector2 = f[0]
		var n: Vector2 = f[1]
		var face := -1
		if n.y > 0.9:
			face = 1
		elif n.x > 0.9:
			face = 3
		if face < 0:
			continue
		var dir := Vector2(1.0, 0.0) if face == 1 else Vector2(0.0, -1.0)
		var out_d := Vector2(0.0, 1.0) if face == 1 else Vector2(1.0, 0.0)
		var kerb := rect.end.y if face == 1 else rect.end.x
		var depth := kerb - (p.y if face == 1 else p.x)
		if depth < 0.5 or depth > FRONT_REACH:
			continue
		if _h01([plan.seed, "parklet", f[4]]) >= odds:
			continue
		var length: float = ParkletKit.LENGTHS[0]
		var width := float(f[2])
		for l: float in ParkletKit.LENGTHS:
			if l <= width + 3.0:
				length = l
		var along := p.x if face == 1 else p.y
		var lo := (rect.position.x if face == 1 else rect.position.y) + CORNER_KEEP + length * 0.5
		var hi := (rect.end.x if face == 1 else rect.end.y) - CORNER_KEEP - length * 0.5
		if hi < lo:
			continue
		along = clampf(along, lo, hi)
		var c := Vector2(along, kerb) if face == 1 else Vector2(kerb, along)
		if not _kerb_free(chunk, c, dir, out_d, length, face, out):
			continue
		out.append({"c": c, "dir": dir, "out": out_d, "length": length, "key": int(f[4]), "room": int(f[3]),
			"front": p + n * 1.2, "face": face, "id": "parklet_%d" % absi(int(f[4])), "shop_key": int(f[5])})
		if out.size() >= MAX_PER_BLOCK:
			break
	return out


## Whether the stretch of parking lane a deck of `length` at kerb point `c` takes is free: the
## road open, no bus stop, red kerb, driveway, station kerb, vendor's truck, road works, bike lane
## or other parklet on it.
static func _kerb_free(chunk: CityChunk, c: Vector2, dir: Vector2, out_d: Vector2, length: float, face: int, others: Array) -> bool:
	var plan := chunk.plan
	var lane := c + out_d * (CityPlan.PARKING_LANE * 0.5)
	var axis := CityPlan.AXIS_X if face == 3 else CityPlan.AXIS_Z
	var index := (chunk.ix + 1) if face == 3 else (chunk.iz + 1)
	for o: Dictionary in others:
		if (o.c as Vector2).distance_to(c) < (float(o.length) + length) * 0.5 + 1.5:
			return false
	for k in 5:
		var t := (float(k) / 4.0 - 0.5) * (length + 1.0)
		var q := lane + dir * t
		var q3 := Vector3(q.x, 0.4, q.y)
		var along := q.y if axis == CityPlan.AXIS_X else q.x
		if not plan.road_open(axis, index, along):
			return false
		if BigVehicles.in_stop_zone(plan, q) or FireStation.keeps_clear(plan, q) or PoliceStation.keeps_clear(plan, q) \
				or Schools.keeps_clear(plan, q) or Alleys.keeps_clear(plan, q) or Hospital.keeps_clear(plan, q) \
				or FreightRail.keeps_clear(plan, q) or CivicBuildings.keeps_clear(plan, q) \
				or (plan.macro and Landmarks.covers(plan, q, 3.0)) or FarmersMarket.blocks_parking(plan, q3):
			return false
		if Kerbs.blocks_parking(chunk, q3) or StreetVendors.blocks_parking(chunk, q3) \
				or Construction.blocks_parking(chunk, q3) or Micromobility.blocks_parking(chunk, q3):
			return false
	return true


## Lays out this block's parklets: the deck, its plants, the sets and umbrellas, the collision,
## the night light, the diners' chairs and the waiter's beat. A build step of a FULL chunk, after
## the vendors, road works and bike lanes it keeps clear of, before the parked cars.
static func build_block(chunk: CityChunk, block: Dictionary) -> void:
	var plan := chunk.plan
	var hour := StreetVendors.hour_now(chunk) if force_hour < 0.0 else force_hour
	var parklets := plan_chunk(chunk, block)
	if parklets.is_empty():
		return
	var people: Array = chunk.get_meta("parklet_people", [])
	var body := StaticBody3D.new()
	body.name = "Parklets"
	body.collision_layer = 1
	body.collision_mask = 0
	chunk.add_child(body)
	for pk: Dictionary in parklets:
		_build_one(chunk, block, pk, hour, body, people)
	chunk.set_meta("parklets", parklets)
	chunk.set_meta("parklet_people", people)
	for l: float in ParkletKit.LENGTHS:
		chunk._batch.set_draw_distance(K_DECK + str(int(l)), DECK_DRAW)
		chunk._batch.set_shadow_distance(K_DECK + str(int(l)), SHADOW_DISTANCE)
	for k in 8:
		chunk._batch.set_draw_distance(K_SET + str(k), SET_DRAW)
		chunk._batch.set_shadow_distance(K_SET + str(k), SHADOW_DISTANCE)
	for k in 2:
		chunk._batch.set_draw_distance(K_UMBRELLA + str(k), UMBRELLA_DRAW)
		chunk._batch.set_shadow_distance(K_UMBRELLA + str(k), SHADOW_DISTANCE)


static func _build_one(chunk: CityChunk, block: Dictionary, pk: Dictionary, hour: float, body: StaticBody3D, people: Array) -> void:
	var plan := chunk.plan
	var key := int(pk.key)
	var length := float(pk.length)
	var dir: Vector2 = pk.dir
	var out_d: Vector2 = pk.out
	var c: Vector2 = pk.c
	var basis := Basis(Vector3(dir.x, 0.0, dir.y), Vector3.UP, Vector3(out_d.x, 0.0, out_d.y))
	var xf := Transform3D(basis, Vector3(c.x, CityChunk.ROAD_TOP, c.y))
	var room := int(pk.room)
	var cafe := room == Building.ShopRoom.CAFE
	var open_now := busy(room, hour) > 0.0 and (not evening(hour) or Building.shop_open(int(pk.shop_key)))
	var seed01 := _h01([plan.seed, "parklet_seed", key]) * 0.49
	var paint: Color = PLANTER_PAINT[int(_h01([plan.seed, "parklet_paint", key]) * PLANTER_PAINT.size()) % PLANTER_PAINT.size()]
	var lit := 0.5 if open_now else 0.0
	chunk._batch.add(K_DECK + str(int(length)), ParkletKit.deck(length), xf, Color.WHITE, Color(paint.r, paint.g, paint.b, lit + seed01))
	# The planting: a row of ornamental grass (a cheap scan, 941 triangles), a clipped shrub at
	# each end; one species of each a parklet.
	var clump := 0
	var shrub := int(_h01([plan.seed, "parklet_shrub", key]) * 4.0) % 4
	var spots_p := ParkletKit.plant_spots(length)
	for i in spots_p.size():
		var s: Vector3 = spots_p[i]
		var h := _h01([plan.seed, "parklet_plant", key, i])
		var tint := Color(0.9 + 0.2 * h, 0.95 + 0.1 * h, 0.9)
		if i == 0 or i == spots_p.size() - 1:
			var pb := Basis(Vector3.UP, h * TAU).scaled(Vector3.ONE * (0.5 + 0.12 * h))
			chunk._batch.add("shrub_%d" % shrub, PropFactory.model_shrub(shrub), Transform3D(pb, xf * s), tint)
		else:
			var pb := Basis(Vector3.UP, h * TAU).scaled(Vector3.ONE * (1.25 + 0.4 * h))
			chunk._batch.add("gclump_%d" % clump, PropFactory.model_grass_clump(clump), Transform3D(pb, xf * s), tint)
	chunk._batch.set_draw_distance("gclump_%d" % clump, PLANT_DRAW)
	# Collision: the deck (stood on), the planters along the road and the end screens.
	var gy := chunk._gy(c.x, c.y)
	var hx := length * 0.5
	var dpt := ParkletKit.DEPTH
	var shapes := [
		[Vector3(length, ParkletKit.DECK_Y, dpt), Vector3(0.0, ParkletKit.DECK_Y * 0.5, dpt * 0.5)],
		[Vector3(length, ParkletKit.PLANTER_H, ParkletKit.PLANTER_D), Vector3(0.0, ParkletKit.DECK_Y + ParkletKit.PLANTER_H * 0.5, dpt - ParkletKit.PLANTER_D * 0.5)],
		[Vector3(0.1, ParkletKit.SCREEN_H, dpt - ParkletKit.PLANTER_D), Vector3(-hx + 0.05, ParkletKit.DECK_Y + ParkletKit.SCREEN_H * 0.5, (dpt - ParkletKit.PLANTER_D) * 0.5)],
		[Vector3(0.1, ParkletKit.SCREEN_H, dpt - ParkletKit.PLANTER_D), Vector3(hx - 0.05, ParkletKit.DECK_Y + ParkletKit.SCREEN_H * 0.5, (dpt - ParkletKit.PLANTER_D) * 0.5)],
	]
	for sh: Array in shapes:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = sh[0]
		cs.shape = bx
		cs.transform = Transform3D(basis, xf * (sh[1] as Vector3) + Vector3(0.0, gy, 0.0))
		body.add_child(cs)
	# The sets: laid where somebody sits, umbrellas open by day, furled after dark.
	var square := _h01([plan.seed, "parklet_square", key]) < 0.4
	var canvas: Color = CANVAS[int(_h01([plan.seed, "parklet_canvas", key]) * CANVAS.size()) % CANVAS.size()]
	var weave: Color = WEAVE[int(_h01([plan.seed, "parklet_weave", key]) * WEAVE.size()) % WEAVE.size()]
	var umbrellas := _h01([plan.seed, "parklet_umbrella", key]) < 0.75
	var umbrella_open := fposmod(hour, 24.0) >= 8.0 and fposmod(hour, 24.0) < 19.5
	var share := busy(room, hour) if open_now else 0.0
	var spots := ParkletKit.set_spots(length)
	var tables: Array = []
	for t in spots.size():
		var spot: Vector3 = spots[t]
		var seats: Array = []
		for side in 2:
			if _h01([plan.seed, "parklet_diner", key, t, side, int(hour)]) < share:
				seats.append(side)
		var laid := not seats.is_empty()
		var set_kind := int(square) * 4 + int(laid) * 2 + int(cafe)
		var sxf := Transform3D(basis, xf * spot)
		var id := "%s_t%d" % [String(pk.id), t]
		if WorldState.is_destroyed(chunk.key, id):
			continue
		var custom := Color(weave.r, weave.g, weave.b, lit + seed01)
		var set_mesh := ParkletKit.bistro_set(square, laid, cafe)
		var instances := [[K_SET + str(set_kind), chunk._batch.add(K_SET + str(set_kind), set_mesh, sxf, Color.WHITE, custom)]]
		if umbrellas:
			var uk := K_UMBRELLA + str(int(umbrella_open))
			instances.append([uk, chunk._batch.add(uk, ParkletKit.umbrella(umbrella_open), sxf, Color.WHITE, Color(canvas.r, canvas.g, canvas.b, lit + seed01))])
		var item := EncampmentItem.new()
		item.name = "Parklet_" + id
		item.chunk = chunk
		item.item_id = id
		item.instances = instances
		item.mesh = set_mesh
		item.mass_kg = 22.0
		item.tint = Color.WHITE
		item.custom = custom
		item.setup(Vector3(0.66, 0.76, 0.66), 0.38)
		item.transform = Transform3D(basis, xf * spot + Vector3(0.0, gy, 0.0))
		chunk.add_child(item)
		var world_spot := xf * spot
		tables.append(Vector2(world_spot.x, world_spot.z))
		for side: int in seats:
			# Chair `side` 0 is at the table's -x, facing +x (the deck's dir).
			var sgn := -1.0 if side == 0 else 1.0
			var seat := Vector2(world_spot.x, world_spot.z) + dir * (sgn * ParkletKit.CHAIR_X)
			var face := -dir * sgn
			people.append({"kind": "diner", "seat": seat, "yaw": atan2(-face.x, -face.y),
				"seed": hash([plan.seed, key, t, side, "diner"]), "item": item, "rect": block.rect,
				"mate": Vector2(world_spot.x, world_spot.z) + dir * (-sgn * ParkletKit.CHAIR_X)})
	# The waiter, between the door and the tables.
	if not tables.is_empty() and share > 0.0 and _h01([plan.seed, "parklet_waiter", key]) < 0.85:
		people.append({"kind": "waiter", "door": pk.front, "tables": tables, "out": out_d,
			"seed": hash([plan.seed, key, "waiter"]), "rect": block.rect, "item": null})
	# The festoon's light on the deck and the pavement after dark (when the restaurant is open).
	if open_now:
		var pool_at := xf * Vector3(0.0, 0.0, dpt * 0.4)
		var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(length + 2.0, 1.0, 5.0) if pk.face == 1 else Vector3(5.0, 1.0, length + 2.0)),
			Vector3(pool_at.x, CityChunk.SIDEWALK_TOP + 0.07, pool_at.z))
		chunk._batch.add("shop_spill", PropFactory.shop_spill(), pool, POOL)
		_add_light(chunk, xf * Vector3(0.0, ParkletKit.DECK_Y + 2.3, dpt * 0.45), 6.5 + length * 0.3)


## A warm light under the festoon, driven with the street lamps (DayNight sets the group's
## energy; Quality turns the group off at the low levels).
static func _add_light(chunk: CityChunk, at: Vector3, reach: float) -> void:
	var light := OmniLight3D.new()
	light.name = "ParkletLight"
	light.position = at + Vector3(0.0, chunk._gy(at.x, at.z), 0.0)
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.light_color = Color(1.0, 0.74, 0.46)
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 15.0
	light.add_to_group("lamp_light")
	chunk.add_child(light)


## The `index`-th diner or waiter this chunk planned (a build step each), if the crowd cap has
## room for one more person.
static func spawn_person(chunk: CityChunk, index: int) -> void:
	var people: Array = chunk.get_meta("parklet_people", [])
	if index >= people.size():
		return
	var s: Dictionary = people[index]
	if s.item != null and not is_instance_valid(s.item):
		return
	if not chunk._take_crowd_room():
		return
	var ped := ParkletDiner.new()
	if String(s.kind) == "diner":
		ped.setup_diner(s.rect, int(s.seed), s.seat, float(s.yaw), s.mate)
		var at: Vector2 = s.seat
		ped.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.1, at.y)
	else:
		ped.setup_waiter(s.rect, int(s.seed), s.door, s.tables, s.out)
		var at: Vector2 = s.door
		ped.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.1, at.y)
	chunk.add_child(ped)


## Whether the parked car at `spot` (chunk space) would stand on a parklet's stretch of kerb.
static func blocks_parking(chunk: Node, spot: Vector3) -> bool:
	if not chunk.has_meta("parklets"):
		return false
	for pk: Dictionary in chunk.get_meta("parklets"):
		var c: Vector2 = pk.c
		var d: Vector2 = pk.dir
		var o: Vector2 = pk.out
		var rel := Vector2(spot.x, spot.z) - c
		if absf(rel.dot(d)) < float(pk.length) * 0.5 + CAR_CLEAR and rel.dot(o) > -0.5 and rel.dot(o) < CityPlan.PARKING_LANE + 0.6:
			return true
	return false


## Builds every mesh once (the loading screen).
static func warm() -> Array:
	if not enabled:
		return []
	return ParkletKit.warm()
