class_name LowriderMeet
## Weekend cruise nights (Lowrider): one boulevard kerb per map cell (by hash) where, on Friday,
## Saturday and Sunday nights, a row of lowriders parks nose to tail in the parking lane with the
## crowd standing round them on the pavement; a few of the cars hop, three-wheel and dance while
## the rest sit laid out. And now and then one cruises slow in the street traffic, bouncing
## (traffic_kind(), from TrafficManager._street_kind(), reusing its roll).
##
## WHERE is worked out, never placed (FarmersMarket's way): the map is cut into CELL squares; a
## hash of seed + cell says whether one has a meet and, over TRIES hashed points, which block's
## +X or +Z road it is - a boulevard (at least MIN_WIDTH) in MIDTOWN, SUBURBS or INDUSTRIAL that
## nothing else claims (a site, grounds, a school, a market street, the light rail, a freeway, the
## river) - and which kerb (a hash). The chunk owning that road (its +X / +Z road) builds it,
## AFTER every roll of the block: the parked cars it would have put in that stretch are skipped
## after their rolls (blocks_parking(), like a vendor's truck), so nothing else on the block moves.
## WHEN: the chunk's build hour (DayNight) on a meet night (Friday, Saturday or Sunday from
## HOURS.x to HOURS.y). LOWRIDER_MEET=1 in the environment (or `force`) holds every meet on;
## LOWRIDERS=0 turns meets and cruisers off.

const CELL := 1600.0
const ODDS := 0.7
const TRIES := 6
const DISTRICTS := [CityPlan.District.MIDTOWN, CityPlan.District.SUBURBS, CityPlan.District.INDUSTRIAL]
## The street must be at least this wide (a boulevard with a parking lane), the block's side this
## long, and flat enough to stand cars on.
const MIN_WIDTH := 15.5
const MIN_LEN := 60.0
const MAX_GRADE := 0.05
## Kerb space per car (a 5.5 m hardtop and a gap), the clear stretch at each end, the most cars.
const PITCH := 6.6
const END_CLEAR := 7.0
const MAX_CARS := 10
## Of the cars, how many work their switches (Hydraulics SHOW) rather than sit laid out.
const SHOW_SHARE := 0.4
## Meet nights (FarmersMarket.weekday(): 0 Sunday .. 6 Saturday) and hours (from .x to past
## midnight .y).
const NIGHTS := [5, 6, 0]
const HOURS := Vector2(18.5, 1.5)
## People at the meet: per car, and the most a meet spawns (inside the crowd cap).
const PEOPLE_PER_CAR := 2.2
const MAX_PEOPLE := 20
## Cruisers in traffic: their share of street cars (by day, on a meet night) in the districts
## above, and how slow they roll (of a street car's speed).
const CRUISE_SHARE := Vector2(0.006, 0.03)
const CRUISE_SPEED := 0.6

static var force: bool = OS.get_environment("LOWRIDER_MEET") == "1"
## Tests and stills: the hour and weekday to build for (-1: the city's clock).
static var force_hour: float = -1.0
static var force_day: int = -1
static var _cells: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func reset() -> void:
	_cells.clear()


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## The meet of map cell `cell`, or {}: {"axis" (of the road), "index", "k" (between crossing roads
## k and k + 1), "side" (+-1: which kerb), "lo"/"hi" (along the road), "lane" (the parking lane's
## centre across), "centre", "width", "owner" (the chunk), "seed", "cars" (count)}. Cached per seed.
static func decide(plan: CityPlan, cell: Vector2i) -> Dictionary:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cells.has(key):
		return _cells[key]
	var out := {}
	_cells[key] = out
	if not Lowrider.enabled or plan.macro == null:
		return out
	if _h01([plan.seed, cell.x, cell.y, "lrmeet"]) > ODDS:
		return out
	for attempt in TRIES:
		var target := Vector2((float(cell.x) + lerpf(0.1, 0.9, _h01([plan.seed, cell.x, cell.y, attempt, "lr_x"]))) * CELL,
				(float(cell.y) + lerpf(0.1, 0.9, _h01([plan.seed, cell.x, cell.y, attempt, "lr_z"]))) * CELL)
		if plan.zone_at(target) != MacroMap.Zone.CITY:
			continue
		var a := plan.block_index_at(target)
		var axes := [CityPlan.AXIS_X, CityPlan.AXIS_Z]
		if _h01([plan.seed, cell.x, cell.y, attempt, "lr_axis"]) < 0.5:
			axes.reverse()
		for axis: int in axes:
			var site := _segment(plan, a, axis)
			if site.is_empty():
				continue
			var c := Vector2(site.centre, (float(site.lo) + float(site.hi)) * 0.5) if axis == CityPlan.AXIS_X else Vector2((float(site.lo) + float(site.hi)) * 0.5, site.centre)
			if cell_of(c) != cell:
				continue
			site.cell = cell
			site.side = 1.0 if _h01([plan.seed, cell.x, cell.y, "lr_side"]) < 0.5 else -1.0
			site.lane = float(site.centre) + float(site.side) * CityPlan.parking_offset(float(site.width))
			site.seed = hash([plan.seed, cell.x, cell.y, "lr_site"])
			site.cars = mini(MAX_CARS, int((float(site.hi) - float(site.lo) - END_CLEAR * 2.0) / PITCH))
			if int(site.cars) < 3:
				continue
			out.merge(site)
			return out
	return out


## Block `a`'s +X road (axis X) or +Z road (axis Z) between its two crossings, if a meet fits.
static func _segment(plan: CityPlan, a: Vector2i, axis: int) -> Dictionary:
	var index := a.x + 1 if axis == CityPlan.AXIS_X else a.y + 1
	var k := a.y if axis == CityPlan.AXIS_X else a.x
	var o := 1 - axis
	var width := plan.road_width(axis, index)
	if width < MIN_WIDTH:
		return {}
	var lo := plan.road_pos(o, k) + plan.road_width(o, k) * 0.5
	var hi := plan.road_pos(o, k + 1) - plan.road_width(o, k + 1) * 0.5
	if hi - lo < MIN_LEN:
		return {}
	var centre := plan.road_pos(axis, index)
	var rect := Rect2(centre - width * 0.5, lo, width, hi - lo) if axis == CityPlan.AXIS_X else Rect2(lo, centre - width * 0.5, hi - lo, width)
	var other := a + (Vector2i(1, 0) if axis == CityPlan.AXIS_X else Vector2i(0, 1))
	for b: Vector2i in [a, other]:
		if not _eligible(plan, b):
			return {}
	if not FarmersMarket._street_clear(plan, axis, index, rect):
		return {}
	if not FarmersMarket.market_on(plan, axis, index, k).is_empty():
		return {}
	var p0 := Vector2(centre, lo + 4.0) if axis == CityPlan.AXIS_X else Vector2(lo + 4.0, centre)
	var p1 := Vector2(centre, hi - 4.0) if axis == CityPlan.AXIS_X else Vector2(hi - 4.0, centre)
	if absf(plan.macro.relief_at(p0) - plan.macro.relief_at(p1)) > MAX_GRADE * (hi - lo):
		return {}
	return {"axis": axis, "index": index, "k": k, "lo": lo, "hi": hi, "centre": centre, "width": width,
		"owner": Vector2i(index - 1, k) if axis == CityPlan.AXIS_X else Vector2i(k, index - 1)}


static func _eligible(plan: CityPlan, k: Vector2i) -> bool:
	var b := plan.block(k.x, k.y)
	if not (int(b.district) in DISTRICTS):
		return false
	if b.has("site") or b.has("grounds") or b.has("school") or b.has("hospital") or b.has("chinatown"):
		return false
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS and int(b.kind) != CityPlan.BlockKind.PARK:
		return false
	var rect: Rect2 = b.rect
	for p: Vector2 in [rect.position, rect.end, rect.get_center()]:
		if plan.macro.zone_at(p) != MacroMap.Zone.CITY:
			return false
	if DowntownReal.in_extent(rect.get_center()) or Landmarks.claims(rect):
		return false
	if not plan.site_at_block(k.x, k.y).is_empty() or plan.river_block(k.x, k.y) or plan.marina_block(k.x, k.y):
		return false
	return true


## The meet whose kerb chunk (ix, iz) builds, or {}.
static func meet_of_chunk(plan: CityPlan, ix: int, iz: int) -> Dictionary:
	var rect := FarmersMarket._block_rect(plan, Vector2i(ix, iz))
	var c := cell_of(rect.get_center())
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var m := decide(plan, c + Vector2i(dx, dz))
			if not m.is_empty() and m.owner == Vector2i(ix, iz):
				return m
	return {}


# --- When -------------------------------------------------------------------------------------

static func hour_now(node: Node) -> float:
	if force_hour >= 0.0:
		return force_hour
	var dn := FarmersMarket._day_night(node)
	return float(dn.get("hour")) if dn != null else 9.5


static func day_now(node: Node) -> int:
	return force_day if force_day >= 0 else FarmersMarket.weekday(node)


## Whether a meet is on at `hour` of weekday `day` (a night that runs past midnight belongs to the
## evening it started on).
static func is_on(hour: float, day: int) -> bool:
	if force:
		return true
	if hour >= HOURS.x:
		return day in NIGHTS
	if hour < HOURS.y:
		return posmod(day - 1, 7) in NIGHTS
	return false


# --- The chunk's steps -----------------------------------------------------------------------

## The build steps for chunk `ch` (CityChunk, a FULL block, before its parked cars), or none.
static func steps(ch: Node, plan: CityPlan, ix: int, iz: int, block_rect: Rect2) -> Array[Callable]:
	var out: Array[Callable] = []
	if not Lowrider.enabled:
		return out
	var m := meet_of_chunk(plan, ix, iz)
	if m.is_empty() or not is_on(hour_now(ch), day_now(ch)):
		return out
	ch.set_meta("lowrider_meet", m)
	var spots := layout(m)
	for i in spots.size():
		out.append(func() -> void: _park(ch, plan, m, spots[i], i))
	var people := people_spots(plan, m, spots)
	for i in people.size():
		out.append(func() -> void: _spawn_person(ch, m, people[i], i, block_rect))
	return out


## The cars' places: [centre (Vector2, plan space), yaw, type, look, show].
static func layout(m: Dictionary) -> Array:
	var out := []
	var n := int(m.cars)
	var axis := int(m.axis)
	var lo := float(m.lo) + END_CLEAR + PITCH * 0.5
	var span := float(m.hi) - float(m.lo) - END_CLEAR * 2.0
	lo += (span - PITCH * float(n)) * 0.5
	# Right-hand traffic: the kerb on the +side of an X road runs toward -z... every car faces the
	# way its lane drives.
	var dir := 1.0 if float(m.side) > 0.0 else -1.0
	for i in n:
		var along := lo + PITCH * float(i)
		var p := Vector2(float(m.lane), along) if axis == CityPlan.AXIS_X else Vector2(along, float(m.lane))
		var yaw := (0.0 if dir > 0.0 else PI) if axis == CityPlan.AXIS_X else (PI * 0.5 if dir > 0.0 else -PI * 0.5)
		var seed_i := hash([int(m.seed), i])
		var type := Lowrider.HARDTOP if _h01([seed_i, "type"]) < 0.55 else Lowrider.COUPE
		var show := _h01([seed_i, "show"]) < SHOW_SHARE
		out.append([p, yaw, type, absi(seed_i), show])
	return out


static func _park(ch: Node, plan: CityPlan, m: Dictionary, spot: Array, i: int) -> void:
	if not PhysicsBudget.can_spawn():
		return
	var car := Lowrider.make(int(spot[2]), int(spot[3]))
	# Kinematic like a traffic car (so its hydraulics move it and nothing simulates it); a hit
	# knocks it out of its row into a physics car like any.
	car.traffic = {"axis": int(m.axis), "index": int(m.index), "dir": 1, "lane": 0.0, "speed": 0.0, "v": 0.0,
		"half": 2.7, "rear": 2.7, "parked": true}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	var p: Vector2 = spot[0]
	var y: float = ch.call("_gy", p.x, p.y) + CityChunk.ROAD_TOP + car.road_lift()
	var holder: Node = ch.get_parent() if ch.get_parent() else ch
	var at := Vector3(p.x, y, p.y)
	car.position = WorldState.to_local(at) if holder != ch else at
	car.rotation.y = float(spot[1])
	car.set_meta("lowrider_meet", true)
	car.add_to_group("lowrider_meet")
	holder.add_child(car)
	var h := car.get_node_or_null("Hydraulics")
	if h != null:
		h.set("mode", Lowrider.Hydraulics.Mode.SHOW if bool(spot[4]) else Lowrider.Hydraulics.Mode.PARKED)
		# Stills: LOWRIDER_POSE=i:routine:seconds[,...] holds car i of the row mid-routine.
		for entry in OS.get_environment("LOWRIDER_POSE").split(",", false):
			var f := entry.split(":")
			if f.size() >= 3 and f[0].to_int() == i:
				h.call("perform", f[1], -1.0 if f.size() < 4 else f[3].to_float())
				h.call("advance", f[2].to_float())
				h.set("frozen", true)
	car.visible = (ch as Node3D).visible
	(ch.get("_cars") as Array).append(car)


## Where the crowd stands: on the pavement beside the cars (facing them) and in twos at the
## gaps between them. [position (plan space), yaw, seed].
static func people_spots(plan: CityPlan, m: Dictionary, spots: Array) -> Array:
	var out := []
	var axis := int(m.axis)
	var side := float(m.side)
	var kerb := float(m.centre) + side * float(m.width) * 0.5
	var want := mini(MAX_PEOPLE, int(round(float(spots.size()) * PEOPLE_PER_CAR)))
	for i in want:
		var s := hash([int(m.seed), i, "person"])
		var j := i % spots.size()
		var car_p: Vector2 = spots[j][0]
		var along := (car_p.y if axis == CityPlan.AXIS_X else car_p.x) + (_h01([s, "a"]) - 0.5) * PITCH * 0.9
		var off := kerb + side * lerpf(0.9, 3.2, _h01([s, "o"]))
		var p := Vector2(off, along) if axis == CityPlan.AXIS_X else Vector2(along, off)
		# Facing the car beside them, a little either way.
		var to := car_p - p
		var yaw := atan2(-to.x, -to.y) + (_h01([s, "y"]) - 0.5) * 0.9
		out.append([p, yaw, s])
	return out


static func _spawn_person(ch: Node, m: Dictionary, spot: Array, _i: int, block_rect: Rect2) -> void:
	if not bool(ch.call("_take_crowd_room")):
		return
	var ped := MeetGoer.new()
	var p: Vector2 = spot[0]
	ped.setup_goer(block_rect, int(spot[2]), p, float(spot[1]), int(m.axis))
	ped.position = Vector3(p.x, ch.call("ground_y", p.x, p.y) + 0.05, p.y)
	ch.add_child(ped)


## Whether chunk `ch`'s parked car at `spot` would stand in its meet's row (CityChunk._park_car,
## after its rolls).
static func blocks_parking(ch: Node, spot: Vector3) -> bool:
	if not ch.has_meta("lowrider_meet"):
		return false
	var m: Dictionary = ch.get_meta("lowrider_meet")
	var axis := int(m.axis)
	var across := spot.x if axis == CityPlan.AXIS_X else spot.z
	var along := spot.z if axis == CityPlan.AXIS_X else spot.x
	return absf(across - float(m.lane)) < 2.5 and along > float(m.lo) and along < float(m.hi)


# --- Cruisers ----------------------------------------------------------------------------------

## A street car's kind (TrafficManager._street_kind(), after its own picks; `roll` its last roll,
## reused): a lowrider now and then in the districts that have meets, more on a meet night.
static func traffic_kind(node: Node, plan: CityPlan, at: Vector2, roll: float) -> int:
	if not Lowrider.enabled or plan == null:
		return -1
	if not (int(plan.district_at(at)) in DISTRICTS):
		return -1
	var share := CRUISE_SHARE.y if is_on(hour_now(node), day_now(node)) else CRUISE_SHARE.x
	var r := fposmod(roll * 37.13 + 0.17, 1.0)
	if r >= share:
		return -1
	return Lowrider.HARDTOP if r < share * 0.55 else Lowrider.COUPE
