class_name Valets
extends RefCounted
## Valet stands at hotels and busy restaurants (street life): a podium at the kerb under a
## market umbrella, a key box on its post, an A-frame VALET PARKING board, cones at the ends of
## the zone, and two or three valets in uniform (Valet, a Pedestrian) who run to a car that pulls
## in on its hazards, see its driver off into the building, drive it away to a lot round the
## block, and later bring a car back for a guest coming out. Arriving cars queue on their hazards
## behind the one being served.
##
## Where: a FULL chunk's buildings record every ground-floor shop front (Building.shop_fronts); a
## tower's LOBBY (a hotel, HOTEL_ODDS by district) or a RESTAURANT on a busy block (BUSY_BLOCK,
## then RESTAURANT_ODDS) on the block's +x or +z face, at the back of the pavement, on an open
## road with a parking lane, rolls a stand from a hash of the seed and the shop's key. Never
## across a corner's crosswalk, a bus stop, a red kerb or driveway, a station's kerb, a vendor's
## truck, road works, a bike lane or a parklet (Parklets._kerb_free()). Restaurants run their
## valets at lunch and dinner (open_at()), hotels round the clock.
##
## The cars are TrafficManager's: a street car already coming down the kerb lane, else one from
## its pool placed upstream (TrafficManager.place_car()); TrafficManager drives them, the stand's
## drop-off being a stop in its street rule (street_stop(), one hook in _drive_street()). A car
## being served stays a kinematic traffic car on its hazards in the parking lane; driven off it
## is ordinary traffic again. The stand itself is ValetStand (scripts/npc/valet_stand.gd).
##
## Every roll is a hash of the seed and the shop, never the block rng; the parked cars keep off a
## stand's stretch AFTER all their rolls (blocks_parking(), CityChunk._park_car), counting it as
## parked; nothing goes through CityChunk._add_prop. FULL chunks only. `VALETS=0` in the
## environment is the A/B. Static: call with the chunk.

# --- Tunables --------------------------------------------------------------------------------

## Chance a tower is a hotel with a valet stand at its lobby, by district (one stand a building).
const HOTEL_ODDS := {
	CityPlan.District.DOWNTOWN: 0.3,
	CityPlan.District.MIDTOWN: 0.4,
	CityPlan.District.BEACHTOWN: 0.45,
}
## Chance a block is a busy restaurant block (by hash), and then a restaurant on it has valets.
const BUSY_BLOCK := {
	CityPlan.District.DOWNTOWN: 0.45,
	CityPlan.District.MIDTOWN: 0.5,
	CityPlan.District.BEACHTOWN: 0.4,
	CityPlan.District.SUBURBS: 0.15,
}
const RESTAURANT_ODDS := 0.55
## Most stands on one block.
const MAX_PER_BLOCK := 2
## Valets at a hotel's stand and a restaurant's.
const HOTEL_VALETS := 3
const RESTAURANT_VALETS := 2
## Build steps reserved for spawning valets (one person a step).
const MAX_PEOPLE := MAX_PER_BLOCK * HOTEL_VALETS
## How far from the block's ends the zone keeps (m), as the parklets do.
const CORNER_KEEP := 11.0
## How far back from the kerb a shop front may stand and still have the kerb's stand (m).
const FRONT_REACH := 9.5
## The drop-off: the served car's centre this far past the shop door along the traffic (m), and
## the zone (parking lane kept clear) from ZONE_BACK upstream of it to ZONE_AHEAD past it.
const STOP_PAST := 1.6
const ZONE_BACK := 16.0
const ZONE_AHEAD := 4.0
## The podium stands this far in from the kerb face (m).
const PODIUM_IN := 1.15
## A parked car keeps this far clear of the zone's ends (m, beyond its half length).
const CAR_CLEAR := 2.4
## Draw distances (m) and shadow reach.
const DRAW := 130.0
const UMBRELLA_DRAW := 150.0
const SHADOW_DISTANCE := 45.0
## Umbrella canvases (sRGB first colour; the second is the shader's CANVAS2 by index, as the
## street vendors' umbrellas) and podium paints (sRGB).
const CANVAS := [Color(0.12, 0.12, 0.13), Color(0.45, 0.08, 0.1), Color(0.1, 0.18, 0.32), Color(0.14, 0.3, 0.2), Color(0.88, 0.86, 0.8)]
const PAINTS := [Color(0.06, 0.06, 0.065), Color(0.35, 0.06, 0.07), Color(0.08, 0.14, 0.26), Color(0.3, 0.22, 0.12), Color(0.85, 0.83, 0.78)]
## The podium lamp's pool on the pavement after dark.
const POOL := Color(1.0, 0.8, 0.55, 0.6)
## Batch keys.
const K_PODIUM := "valet_podium_"
const K_KEYS := "valet_keys"
const K_SIGN := "valet_sign_"
const K_CONE := "valet_cone"
const K_BASE := "valet_base"
const K_UMBRELLA := "valet_umbrella"
const K_POOL := "valet_pool"

## Hours of the day to force while building (tests and stills); < 0 reads the DayNight clock.
static var force_hour: float = -1.0
## Off: no valets at all (the A/B, `VALETS=0` in the environment).
static var enabled: bool = OS.get_environment("VALETS") != "0"
## Prints why each candidate front was turned down (`VALET_DEBUG=1`).
static var debug: bool = OS.get_environment("VALET_DEBUG") == "1"


# --- Placement -------------------------------------------------------------------------------

## Whether this chunk's block can have stands at all (cheap: the step is only queued if so).
static func wanted(chunk: CityChunk, block: Dictionary) -> bool:
	if chunk.level != CityChunk.Level.FULL or chunk.plan == null:
		return false
	return wanted_block(block)


## Whether a block (CityPlan.block()) can have stands: plain buildings in a district with odds.
static func wanted_block(block: Dictionary) -> bool:
	if not enabled:
		return false
	if block.has("site") or block.has("grounds") or block.has("chinatown"):
		return false
	if int(block.get("kind", CityPlan.BlockKind.BUILDINGS)) != CityPlan.BlockKind.BUILDINGS:
		return false
	var d := int(block.get("district", -1))
	return HOTEL_ODDS.has(d) or BUSY_BLOCK.has(d)


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


## Whether a stand's valets work at `hour`: a hotel's round the clock, a restaurant's at lunch
## (11:30-14:30) and dinner (17:00-23:30).
static func open_at(hotel: bool, hour: float) -> bool:
	if hotel:
		return true
	var h := fposmod(hour, 24.0)
	return (h >= 11.5 and h < 14.5) or (h >= 17.0 and h < 23.5)


## Seconds between arriving cars at `hour` (the low and high of a uniform pick).
static func arrival_gap(hotel: bool, hour: float) -> Vector2:
	var h := fposmod(hour, 24.0)
	if hotel:
		if h < 6.0:
			return Vector2(70.0, 140.0)
		if h >= 17.0 and h < 22.0:
			return Vector2(16.0, 34.0)
		return Vector2(24.0, 50.0)
	if h >= 18.5 and h < 21.5:
		return Vector2(14.0, 28.0)
	return Vector2(22.0, 45.0)


## The stands of this chunk's block, from its buildings' shop fronts: pure in the buildings (no
## rolls but hashes), so tests ask it directly. Each is a Dictionary (see the end of the loop).
static func plan_chunk(chunk: CityChunk, block: Dictionary) -> Array:
	var plan := chunk.plan
	var rect: Rect2 = block.rect
	var district := int(block.get("district", -1))
	var hotel_odds := float(HOTEL_ODDS.get(district, 0.0))
	var busy := _h01([plan.seed, "valet_block", chunk.ix, chunk.iz]) < float(BUSY_BLOCK.get(district, 0.0))
	var fronts: Array = []
	for child in chunk.get_children():
		var b := child as Building
		if b == null:
			continue
		for f: Array in b.shop_fronts:
			var room := int(f[3])
			var key := hash([b.seed, int(f[4])])
			var hotel := room == Building.ShopRoom.LOBBY
			if hotel:
				if _h01([plan.seed, "valet_hotel", b.seed]) >= hotel_odds:
					continue
			elif room == Building.ShopRoom.RESTAURANT:
				if not busy or _h01([plan.seed, "valet_rest", key]) >= RESTAURANT_ODDS:
					continue
			else:
				continue
			var p: Vector3 = b.transform * (f[0] as Vector3)
			var n: Vector3 = (b.transform.basis * (f[1] as Vector3)).normalized()
			fronts.append([Vector2(p.x, p.z), Vector2(n.x, n.z), hotel, key, room, b.seed])
	# Hotels first, then a stable order whatever order the buildings were added in.
	fronts.sort_custom(func(x: Array, y: Array) -> bool: return x[3] < y[3] if x[2] == y[2] else x[2])
	var others: Array = (chunk.get_meta("parklets", []) as Array).duplicate()
	var out: Array = []
	var used := {}
	for f: Array in fronts:
		if used.has(f[5]):
			continue
		var p: Vector2 = f[0]
		var n: Vector2 = f[1]
		# Faces as Parklets numbers them: 0 -z, 1 +z, 2 -x, 3 +x. On +x / +z the parking lane is
		# this chunk's own and the zone is kept clear of parked cars; on -x / -z it is the
		# neighbour's, so the served car stands double-parked in the kerb lane (`double`).
		var face := -1
		if n.y > 0.9:
			face = 1
		elif n.y < -0.9:
			face = 0
		elif n.x > 0.9:
			face = 3
		elif n.x < -0.9:
			face = 2
		if face < 0:
			if debug:
				print("VALET_DEBUG %s face" % ("hotel" if f[2] else "rest"))
			continue
		var xrun := face <= 1
		var high := face == 1 or face == 3
		var double := not high
		var kerb: float
		if xrun:
			kerb = rect.end.y if high else rect.position.y
		else:
			kerb = rect.end.x if high else rect.position.x
		var depth := absf(kerb - (p.y if xrun else p.x))
		if depth < 0.5 or depth > FRONT_REACH:
			if debug:
				print("VALET_DEBUG %s depth %.1f" % ["hotel" if f[2] else "rest", depth])
			continue
		# The kerb lane's traffic (right-hand running): -x past a +z face, +x past a -z face, +z
		# past a +x face, -z past a -x face.
		var tdir := (-1 if high else 1) if xrun else (1 if high else -1)
		var trav := Vector2(float(tdir), 0.0) if xrun else Vector2(0.0, float(tdir))
		var out_d := (Vector2(0.0, 1.0) if high else Vector2(0.0, -1.0)) if xrun else (Vector2(1.0, 0.0) if high else Vector2(-1.0, 0.0))
		var axis := CityPlan.AXIS_Z if xrun else CityPlan.AXIS_X
		var index: int = (chunk.iz + (1 if high else 0)) if xrun else (chunk.ix + (1 if high else 0))
		var door_s := p.x if xrun else p.y
		var r0 := rect.position.x if xrun else rect.position.y
		var stop_s := door_s + float(tdir) * STOP_PAST
		if double:
			# Behind the served car (where the valets cross to its door) a gap in the parked
			# cars' 8 m grid (CityChunk._park_car_steps: car centres 8 m apart from 8 m in).
			var behind := stop_s - float(tdir) * 3.2
			behind = r0 + 12.0 + roundf((behind - r0 - 12.0) / 8.0) * 8.0
			stop_s = behind + float(tdir) * 3.2
		var lo_end := stop_s - float(tdir) * ZONE_BACK
		var hi_end := stop_s + float(tdir) * ZONE_AHEAD
		var z0 := minf(lo_end, hi_end)
		var z1 := maxf(lo_end, hi_end)
		var r1 := rect.end.x if xrun else rect.end.y
		if z0 < r0 + CORNER_KEEP or z1 > r1 - CORNER_KEEP:
			if debug:
				print("VALET_DEBUG %s corner" % ("hotel" if f[2] else "rest"))
			continue
		var length := z1 - z0
		var mid := (z0 + z1) * 0.5
		var c := Vector2(mid, kerb) if xrun else Vector2(kerb, mid)
		var ok := _road_free(plan, axis, index, z0, z1, kerb, out_d, xrun, others, c, length) if double \
			else Parklets._kerb_free(chunk, c, trav, out_d, length, face, others)
		if not ok:
			if debug:
				print("VALET_DEBUG %s kerb" % ("hotel" if f[2] else "rest"))
			continue
		var width := plan.road_width(axis, index)
		var lanes := 2 if width > plan.street_width + 1.0 else 1
		var key: int = f[3]
		var podium_s := door_s - float(tdir) * 0.4
		var podium := (Vector2(podium_s, kerb) if xrun else Vector2(kerb, podium_s)) - out_d * PODIUM_IN
		var stand := {
			"c": c, "length": length, "face": face, "key": key, "room": int(f[4]), "hotel": bool(f[2]),
			"trav": trav, "out": out_d, "axis": axis, "index": index, "tdir": tdir, "lanes": lanes,
			"stop_s": stop_s, "zone": Vector2(z0, z1), "kerb": kerb, "xrun": xrun, "double": double,
			"podium": podium, "door": p + n * 0.6, "front": p + n * 1.6,
			"op": int(_h01([plan.seed, "valet_op", key]) * ValetKit.OPERATORS.size()) % ValetKit.OPERATORS.size(),
			"rate": int(_h01([plan.seed, "valet_rate", key]) * ValetKit.RATES.size()) % ValetKit.RATES.size(),
			"canvas": int(_h01([plan.seed, "valet_canvas", key]) * CANVAS.size()) % CANVAS.size(),
			"paint": int(_h01([plan.seed, "valet_paint", key]) * PAINTS.size()) % PAINTS.size(),
			"uniform": int(_h01([plan.seed, "valet_uniform", key]) * Valet.UNIFORMS.size()) % Valet.UNIFORMS.size(),
			"valets": HOTEL_VALETS if bool(f[2]) else RESTAURANT_VALETS,
			"rect": rect, "id": "valet_%d" % absi(key),
		}
		out.append(stand)
		others.append(stand)
		used[f[5]] = true
		if out.size() >= MAX_PER_BLOCK:
			break
	return out


## Whether a double-parked stand's stretch of road (a -x or -z face) is free: the road open, no
## bus stop or station kerb along it, no other stand or parklet.
static func _road_free(plan: CityPlan, axis: int, index: int, z0: float, z1: float, kerb: float, out_d: Vector2, xrun: bool, others: Array, c: Vector2, length: float) -> bool:
	for o: Dictionary in others:
		if (o.c as Vector2).distance_to(c) < (float(o.length) + length) * 0.5 + 1.5:
			return false
	for k in 5:
		var along := lerpf(z0, z1, float(k) / 4.0)
		var q := (Vector2(along, kerb) if xrun else Vector2(kerb, along)) + out_d * (CityPlan.PARKING_LANE * 0.5)
		if not plan.road_open(axis, index, along):
			return false
		if BigVehicles.in_stop_zone(plan, q) or FireStation.keeps_clear(plan, q) or PoliceStation.keeps_clear(plan, q) \
				or Schools.keeps_clear(plan, q) or Hospital.keeps_clear(plan, q) or FreightRail.keeps_clear(plan, q) \
				or (plan.macro and Landmarks.covers(plan, q, 3.0)) or FarmersMarket.blocks_parking(plan, Vector3(q.x, 0.4, q.y)):
			return false
	return true


## Lays out this block's stands: the podium, key box, sign, cones, umbrella and the night pool,
## and a ValetStand for each one whose valets work at the hour the chunk is built at. A build
## step of a FULL chunk, after the parklets it keeps clear of, before the parked cars.
static func build_block(chunk: CityChunk, block: Dictionary) -> void:
	var hour := StreetVendors.hour_now(chunk) if force_hour < 0.0 else force_hour
	var stands := plan_chunk(chunk, block)
	if stands.is_empty():
		return
	var people: Array = []
	for s: Dictionary in stands:
		s.open = open_at(bool(s.hotel), hour)
		_build_one(chunk, s, hour)
		if s.open:
			var node := ValetStand.new()
			node.name = "ValetStand_%s" % String(s.id)
			node.setup(s, hour)
			chunk.add_child(node)
			s.node = node
			for i in int(s.valets):
				people.append({"stand": node, "i": i, "seed": hash([chunk.plan.seed, int(s.key), "valet", i])})
	chunk.set_meta("valet_stands", stands)
	chunk.set_meta("valet_people", people)
	for k in ValetKit.OPERATORS.size():
		chunk._batch.set_draw_distance(K_PODIUM + str(k), DRAW)
		chunk._batch.set_shadow_distance(K_PODIUM + str(k), SHADOW_DISTANCE)
	for k in ValetKit.RATES.size():
		chunk._batch.set_draw_distance(K_SIGN + str(k), DRAW)
		chunk._batch.set_shadow_distance(K_SIGN + str(k), SHADOW_DISTANCE)
	for k: String in [K_KEYS, K_CONE, K_BASE]:
		chunk._batch.set_draw_distance(k, DRAW)
		chunk._batch.set_shadow_distance(k, SHADOW_DISTANCE)
	chunk._batch.set_draw_distance(K_UMBRELLA, UMBRELLA_DRAW)
	chunk._batch.set_shadow_distance(K_UMBRELLA, SHADOW_DISTANCE)


static func _build_one(chunk: CityChunk, s: Dictionary, hour: float) -> void:
	var trav: Vector2 = s.trav
	var out_d: Vector2 = s.out
	var key := int(s.key)
	# Frame: +z the road, x along the kerb (with the traffic).
	# (x is against the traffic: x, y, z right-handed with z the road.)
	var basis := Basis(Vector3(-trav.x, 0.0, -trav.y), Vector3.UP, Vector3(out_d.x, 0.0, out_d.y))
	var pod: Vector2 = s.podium
	var y := CityChunk.SIDEWALK_TOP
	var paint: Color = PAINTS[int(s.paint)]
	var seed01 := _h01([chunk.plan.seed, "valet_seed", key]) * 0.49
	var custom := Color(paint.r, paint.g, paint.b, seed01)
	var gy := chunk._gy(pod.x, pod.y)
	var at := func(along: float, inward: float) -> Vector3:
		var q := pod + trav * along - out_d * inward
		return Vector3(q.x, y, q.y)
	# The podium, knocked over as a real body (an EncampmentItem), gone for good.
	var pod_xf := Transform3D(basis, at.call(0.0, 0.0))
	_item(chunk, s, "podium", K_PODIUM + str(int(s.op)), ValetKit.podium(int(s.op)), pod_xf, custom, Vector3(0.7, ValetKit.PODIUM_H, 0.55), 45.0, gy)
	# The key box beside it, the umbrella on its base behind them, the sign upstream at the
	# kerb edge where arriving drivers read it.
	var keys_xf := Transform3D(basis, at.call(0.75, 0.25))
	_item(chunk, s, "keys", K_KEYS, ValetKit.key_box(), keys_xf, Color(0.1, 0.12, 0.11, seed01), Vector3(0.45, 1.65, 0.3), 30.0, gy)
	var umb: Vector3 = at.call(-0.15, 0.95)
	var umb_xf := Transform3D(basis, umb)
	if not WorldState.is_destroyed(chunk.key, String(s.id) + "_umbrella"):
		var canvas: Color = CANVAS[int(s.canvas)]
		chunk._batch.add(K_BASE, ValetKit.umbrella_base(), umb_xf, Color.WHITE, Color(0.1, 0.1, 0.1, seed01))
		if s.open:
			chunk._batch.add(K_UMBRELLA, StreetVendors.umbrella_mesh(), umb_xf, Color.WHITE, Color(canvas.r, canvas.g, canvas.b, float(int(s.canvas) % 6) / 8.0))
	var stop_s := float(s.stop_s)
	var tdir := float(s.tdir)
	var podium_s := pod.x if bool(s.xrun) else pod.y
	# `along` runs with the traffic (trav = tdir along the road's coordinate); the boards face up
	# and down the kerb, at the drivers coming in.
	var sign_along := (stop_s - tdir * 12.0 - podium_s) * tdir
	var sign_xf := Transform3D(basis * Basis(Vector3.UP, PI * 0.5), at.call(sign_along, -(PODIUM_IN - 0.45)))
	_item(chunk, s, "sign", K_SIGN + str(int(s.rate)), ValetKit.sign(int(s.rate)), sign_xf, Color(1, 1, 1, seed01), Vector3(0.62, 1.0, 0.45), 8.0, gy)
	# Cones in the parking lane at the zone's two ends (by the kerb; none where the zone is the
	# neighbour's parking lane and the cars double-park).
	for end: float in ([] if bool(s.double) else [float((s.zone as Vector2).x), float((s.zone as Vector2).y)]):
		var q: Vector2 = (Vector2(end, float(s.kerb)) if bool(s.xrun) else Vector2(float(s.kerb), end)) + out_d * 0.45
		var cone_xf := Transform3D(Basis(), Vector3(q.x, CityChunk.ROAD_TOP, q.y))
		chunk._batch.add(K_CONE, ValetKit.cone(), cone_xf, Color.WHITE, Color(0.0, 0.0, 0.0, seed01))
	# The lamp's pool on the pavement after dark.
	if s.open:
		var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(3.2, 1.0, 3.2)), Vector3(pod.x, CityChunk.SIDEWALK_TOP + 0.07, pod.y))
		chunk._batch.add(K_POOL, PropFactory.shop_spill(), pool, POOL)
		chunk._batch.set_no_shadow(K_POOL)
		chunk._batch.set_draw_distance(K_POOL, DRAW)


static func _item(chunk: CityChunk, s: Dictionary, what: String, key: String, mesh: Mesh, xf: Transform3D, custom: Color, size: Vector3, mass: float, gy: float) -> void:
	var id := "%s_%s" % [String(s.id), what]
	if WorldState.is_destroyed(chunk.key, id):
		return
	var item := EncampmentItem.new()
	item.name = "Valet_" + id
	item.chunk = chunk
	item.item_id = id
	item.instances = [[key, chunk._batch.add(key, mesh, xf, Color.WHITE, custom)]]
	item.mesh = mesh
	item.mass_kg = mass
	item.tint = Color.WHITE
	item.custom = custom
	item.setup(size, size.y * 0.5)
	item.transform = Transform3D(xf.basis, xf.origin + Vector3(0.0, gy, 0.0))
	chunk.add_child(item)


## The `index`-th valet this chunk planned (a build step each), if the crowd cap has room.
static func spawn_valet(chunk: CityChunk, index: int) -> void:
	var people: Array = chunk.get_meta("valet_people", [])
	if index >= people.size():
		return
	var v: Dictionary = people[index]
	var stand := v.stand as ValetStand
	if stand == null or not is_instance_valid(stand):
		return
	if not chunk._take_crowd_room():
		return
	stand.add_valet(chunk, int(v.i), int(v.seed))


## Whether the parked car at `spot` (chunk space) would stand in a stand's zone.
static func blocks_parking(chunk: Node, spot: Vector3) -> bool:
	if not chunk.has_meta("valet_stands"):
		return false
	for s: Dictionary in chunk.get_meta("valet_stands"):
		if bool(s.double):
			continue
		var z: Vector2 = s.zone
		var along := spot.x if bool(s.xrun) else spot.z
		var across := ((spot.z if bool(s.xrun) else spot.x) - float(s.kerb)) * ((s.out as Vector2).y if bool(s.xrun) else (s.out as Vector2).x)
		if along > z.x - CAR_CLEAR and along < z.y + CAR_CLEAR and across > -0.5 and across < CityPlan.PARKING_LANE + 0.6:
			return true
	return false


## TrafficManager._drive_street: a car on its way to (or standing at) a valet stand. Returns
## (metres to the drop-off ahead - a stop, like a bus's - and the shift toward the kerb), or
## (INF, 0) when the car has no stand any more (its tags are dropped).
static func street_stop(traffic: Node, car: Vehicle, t: Dictionary, along: float, v: float, _delta: float) -> Vector2:
	var stand := instance_from_id(int(t.valet)) as ValetStand
	if stand == null or not is_instance_valid(stand) or not stand.is_inside_tree():
		release_car(car)
		return Vector2(INF, 0.0)
	return stand.stop_for(traffic, car, t, along, v)


## A car's valet tags gone: it is ordinary traffic again.
static func release_car(car: Vehicle) -> void:
	var t: Dictionary = car.traffic
	t.erase("valet")
	t.erase("valet_return")
	t.erase("no_turns")
	t.erase("hazard")
	if car.has_meta("valet"):
		car.remove_meta("valet")
		if car.has_meta("errand") and car.get_node_or_null("ErrandCar") == null:
			car.remove_meta("errand")


## Builds every mesh once (the loading screen).
static func warm() -> Array:
	if not enabled:
		return []
	ValetKit.warm()
	StreetVendors.umbrella_mesh()
	return [StreetVendors.material()]
