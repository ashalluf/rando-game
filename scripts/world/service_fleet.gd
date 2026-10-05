class_name ServiceFleet
extends Node3D
## The city's working vehicles at work (ServiceVehicles has the vehicles themselves). A Node3D in
## city.tscn, so the streamer's origin shifts carry it; nothing here is per chunk. Every
## `spawn_interval` it looks round the player and sends, through the TrafficManager (place_car(),
## then the car's `traffic.work`):
##   * garbage trucks down the residential streets whose carts are out today (KerbBins: a hash of
##     seed + street + weekday), one stream each - trash, recycling or yard waste, as Los Angeles
##     runs a truck per colour - stopping with the arm at each cart of its colour on its kerb;
##   * a street sweeper crawling along a kerb, brushes down and water on;
##   * an ice-cream truck in the suburbs and the beach town, playing its chime, stopping now and
##     then with its flashers on;
##   * delivery vans that stop in the lane (double-parked) with their hazards on;
##   * a tow truck for a burnt-out wreck the player has left (CarDamage's wrecks, once the fire is
##     out): it drives to the kerb beside it, slides its bed back and down, winches the wreck up,
##     levels the bed and drives off with it. The wreck leaves the debris lists while it is held.
## It also draws the carts at the kerb round the player (two MultiMeshes, near and far) and hides
## the one an arm is holding. TrafficManager asks work_stop() for a working car's next stop.

## Disable to keep every service vehicle off the streets (the smoke test does, except in its checks).
static var enabled: bool = true

@export_group("Carts")
## Carts are drawn out to here round the player (m), with the moulded mesh inside `near_bins`.
@export var bin_radius: float = 150.0
@export var near_bins: float = 45.0
## Seconds between looks round for carts.
@export var bin_survey: float = 0.8
## New blocks planned per look (each walks the block's lots).
@export var blocks_per_survey: int = 6

@export_group("Dispatch")
@export var spawn_interval: float = 3.0
@export var max_garbage: int = 2
@export var max_sweepers: int = 1
@export var max_ice_cream: int = 1
@export var max_delivery: int = 2
@export var max_tows: int = 2
## Hours (game clock) each works.
@export var garbage_hours: Vector2 = Vector2(6.0, 17.5)
@export var sweeper_hours: Vector2 = Vector2(7.0, 16.0)
@export var ice_cream_hours: Vector2 = Vector2(11.0, 20.5)
@export var delivery_hours: Vector2 = Vector2(7.0, 19.5)
## Cruise speeds (m/s): a refuse truck between stops, a sweeper's crawl, the others.
@export var garbage_speed: float = 6.0
@export var sweeper_speed: float = 2.2
@export var ice_cream_speed: float = 4.5
@export var delivery_speed: float = 9.0
@export var tow_speed: float = 9.0
## How far up the street from what it works on a vehicle is put down (m).
@export var spawn_back: Vector2 = Vector2(80.0, 120.0)
## Never put one down nearer the player than this (m).
@export var spawn_clear: float = 45.0
## Pull toward the kerb (m) while working: the sweeper and the garbage truck stay clear of the
## parked cars (lane centre + shift + half a truck < the parking lane), the others less.
@export var kerb_shift: float = 0.9
## Seconds a delivery or the ice-cream truck stands at a stop.
@export var delivery_dwell: Vector2 = Vector2(22.0, 40.0)
@export var ice_cream_dwell: Vector2 = Vector2(18.0, 30.0)
## Metres between their stops.
@export var stop_every: Vector2 = Vector2(70.0, 170.0)

@export_group("Tow")
## A wreck is towed once it has been a wreck this long (s, its fire out), with the player at least
## `tow_leave` away (and no further than `tow_reach`).
@export var tow_delay: float = 30.0
@export var tow_leave: float = 30.0
@export var tow_reach: float = 220.0
## The kerb beside a wreck must be this close to it (m), or it stays where it is.
@export var tow_max_reach: float = 13.0
## Seconds: the bed down, the winch (plus a second per 3 m of pull), the bed back up.
@export var bed_seconds: float = 3.0
@export var winch_seconds: float = 4.0

static var _live: ServiceFleet = null

var plan: CityPlan
var traffic: TrafficManager
var day_night: Node
var weekday: int = 0
var _last_hour: float = -1.0
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _spawn_left := 1.0
var _survey_left := 0.0
## Our cars: instance id -> {"car", "kind"}.
var _cars: Dictionary = {}
## Carts: key (set id * 3 + k) -> true while an arm holds it (hidden at the kerb), or once a truck
## of its colour has emptied it.
var _picked: Dictionary = {}
var _collected: Dictionary = {}
## The carts drawn now: [set, k, true-world position] (for the arm and the tests).
var shown: Array = []
var _sets: Array = []
var _bins_near: MultiMeshInstance3D
var _bins_far: MultiMeshInstance3D
var _bins_dirty := true
## Tows in hand: [{"car", "wreck", "state", "t", "from", "dist"}].
var _tows: Array = []
var _no_tow: Dictionary = {}
var _tow_scan := 2.0


func _ready() -> void:
	_live = self
	_rng.seed = 5150
	# The smoke test measures the traffic and the crowd: the fleet sits out everything but its own
	# checks (tests/service_vehicle_checks.gd), like the police and the fire department.
	if get_tree().root.get_node_or_null("SmokeTest") != null:
		enabled = false
	for lod in 2:
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = KerbBins.mesh(lod)
		mm.instance_count = 0
		mmi.multimesh = mm
		mmi.material_override = KerbBins.material()
		mmi.name = "KerbBins%d" % lod
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mmi)
		if lod == 0:
			_bins_near = mmi
		else:
			_bins_far = mmi
	# The chime is the one sound long enough to notice building (~0.2 s): built now, at load.
	ServiceSounds.stream("chime")


func _exit_tree() -> void:
	if _live == self:
		_live = null


func _setup() -> bool:
	if plan != null and traffic != null and _player != null and is_instance_valid(_player):
		return true
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	traffic = city.get_node_or_null("Traffic") as TrafficManager
	day_night = city.get_node_or_null("DayNight")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if plan != null and _last_hour < 0.0:
		weekday = posmod(hash([plan.seed, "weekday"]), 7)
	return plan != null and plan.macro != null and traffic != null and _player != null


func hour() -> float:
	return float(day_night.get("hour")) if day_night != null else 10.0


func _process(delta: float) -> void:
	if _live == null:
		_live = self
	if not _setup():
		return
	var h := hour()
	if _last_hour >= 0.0 and h < _last_hour - 12.0:
		weekday = posmod(weekday + 1, 7)
		_collected.clear()
		_bins_dirty = true
	_last_hour = h
	_survey_left -= delta
	if _survey_left <= 0.0:
		_survey_left = bin_survey
		_survey_bins()
	if _bins_dirty:
		_draw_bins()
	_tend(delta)
	_tick_tows(delta)
	if not enabled or traffic.staged:
		return
	_spawn_left -= delta
	if _spawn_left <= 0.0:
		_spawn_left = spawn_interval
		_dispatch()
	_tow_scan -= delta
	if _tow_scan <= 0.0:
		_tow_scan = 2.0
		_scan_wrecks()


func _player_world() -> Vector3:
	return WorldState.to_world(_player.global_position)


# --- Carts at the kerb -------------------------------------------------------------------------------

func _survey_bins() -> void:
	var pw := _player_world()
	var p := Vector2(pw.x, pw.z)
	var sets: Array = []
	var a := plan.block_index_at(p - Vector2(bin_radius, bin_radius))
	var b := plan.block_index_at(p + Vector2(bin_radius, bin_radius))
	var fresh := 0
	var out_cache := {}
	for bz in range(a.y - 1, b.y + 1):
		for bx in range(a.x - 1, b.x + 1):
			if not KerbBins._block_cache.has(Vector2i(bx, bz)) or KerbBins._cache_seed != plan.seed:
				if fresh >= blocks_per_survey:
					continue
				fresh += 1
			for st: Dictionary in KerbBins.block_sets(plan, bx, bz):
				var road := Vector2i(int(st.axis), int(st.index))
				if not out_cache.has(road):
					out_cache[road] = KerbBins.street_out(plan, road.x, road.y, weekday)
				if not out_cache[road]:
					continue
				if KerbBins.cart_pos(plan, st, 1).distance_to(p) <= bin_radius:
					sets.append(st)
	if fresh > 0 or sets.size() != _sets.size():
		_bins_dirty = true
	_sets = sets
	_bins_dirty = true


## A cart's scene transform: standing on the road surface in the gutter, its front to the road.
func cart_xform(st: Dictionary, k: int) -> Transform3D:
	var c := KerbBins.cart_pos(plan, st, k)
	var f := KerbBins.cart_facing(st)
	var x := Vector3(-f.x, 0.0, -f.y)
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP))
	var y := traffic._relief(c) + CityChunk.ROAD_TOP
	return Transform3D(basis, WorldState.to_local(Vector3(c.x, y, c.y)))


func _draw_bins() -> void:
	_bins_dirty = false
	shown.clear()
	var near: Array = []
	var far: Array = []
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else _player.global_position
	for st: Dictionary in _sets:
		for k in 3:
			var key := int(st.id) * 3 + k
			if _picked.has(key):
				continue
			var xf := cart_xform(st, k)
			shown.append([st, k, xf])
			var e := [to_local(xf.origin), xf.basis, KerbBins.COLORS[KerbBins.cart_color(st, k)]]
			if xf.origin.distance_to(eye) < near_bins:
				near.append(e)
			else:
				far.append(e)
	_fill(_bins_near, near)
	_fill(_bins_far, far)


func _fill(mmi: MultiMeshInstance3D, list: Array) -> void:
	var mm := mmi.multimesh
	mm.instance_count = list.size()
	for i in list.size():
		var e: Array = list[i]
		mm.set_instance_transform(i, Transform3D(global_basis.inverse() * (e[1] as Basis), e[0]))
		mm.set_instance_color(i, e[2])
	mmi.visible = not list.is_empty()


# --- The work hook ---------------------------------------------------------------------------------

## TrafficManager._drive_street() asks this for a working car (`t.work` set): x the distance it
## may still go before its next stop (INF: none), y how far toward the kerb it wants to pull. It also runs the stop itself (the arm, a dwell, a tow's arrival).
static func work_stop(car: Vehicle, t: Dictionary, along: float, v: float, delta: float) -> Vector2:
	if _live == null or not is_instance_valid(_live) or _live.plan == null:
		return Vector2(INF, 0.0)
	return _live._work_stop(car, t, along, v, delta)


func _work_stop(car: Vehicle, t: Dictionary, along: float, v: float, delta: float) -> Vector2:
	var dir := float(t.dir)
	match String(t.work):
		"garbage":
			return _garbage_stop(car, t, along, v)
		"sweep":
			var g := ServiceVehicles.gear_of(car) as ServiceVehicles.SweeperGear
			if g:
				g.set_working(true)
			return Vector2(INF, kerb_shift)
		"tow":
			if not t.has("tow_at"):
				return Vector2(INF, 0.0)
			var d := (float(t.tow_at) - along) * dir
			if v < 0.25 and absf(d) < 0.8:
				t.arrived = true
			return Vector2(d + 0.3 if not t.get("arrived", false) else 0.0, 0.0)
		"ice_cream", "delivery":
			return _dwell_stop(car, t, along, v, delta)
	return Vector2(INF, 0.0)


func _garbage_stop(car: Vehicle, t: Dictionary, along: float, v: float) -> Vector2:
	var arm := ServiceVehicles.gear_of(car) as ServiceVehicles.GarbageArm
	var dir := float(t.dir)
	if t.has("cart"):
		var c: Array = t.cart
		var key: int = c[0]
		var d := (float(c[1]) - along) * dir - ServiceVehicles.ARM_AHEAD
		if t.get("lifting", false):
			if arm == null or not arm.busy():
				_collected[key] = true
				t.erase("cart")
				t.lifting = false
				t.hazard = false
				return Vector2(INF, kerb_shift)
			return Vector2(0.0, kerb_shift)
		if d < -0.8:
			t.erase("cart")
			return Vector2(INF, kerb_shift)
		if v < 0.25 and absf(d) < 0.7:
			var st: Dictionary = c[2]
			var k: int = c[3]
			var xf := cart_xform(st, k)
			if arm != null and arm.begin(xf, KerbBins.cart_color(st, k), _cart_taken.bind(key), _cart_back.bind(key)):
				t.lifting = true
				t.hazard = true
				return Vector2(0.0, kerb_shift)
			# Out of the arm's reach from here: left for another day.
			_collected[key] = true
			t.erase("cart")
			return Vector2(INF, kerb_shift)
		return Vector2(d + 0.3, kerb_shift if d < 35.0 else 0.0)
	# The next cart of this truck's colour on its kerb, ahead.
	var best := INF
	var pick: Array = []
	var side := StreetRoute.lane_side(int(t.axis), int(t.dir))
	for st: Dictionary in _sets:
		if int(st.axis) != int(t.axis) or int(st.index) != int(t.index) or float(st.side) != side:
			continue
		for k in 3:
			if KerbBins.cart_color(st, k) != int(t.get("stream", 0)):
				continue
			var key := int(st.id) * 3 + k
			if _collected.has(key) or _picked.has(key):
				continue
			var p := KerbBins.cart_pos(plan, st, k)
			var a := p.y if int(st.axis) == CityPlan.AXIS_X else p.x
			var d := (a - along) * dir - ServiceVehicles.ARM_AHEAD
			if d > -0.5 and d < best and d < 160.0:
				best = d
				pick = [key, a, st, k]
	if pick.is_empty():
		return Vector2(INF, 0.0)
	t.cart = pick
	return Vector2(best + 0.3, kerb_shift if best < 35.0 else 0.0)


func _cart_taken(key: int) -> void:
	_picked[key] = true
	_bins_dirty = true


func _cart_back(key: int) -> void:
	_picked.erase(key)
	_bins_dirty = true


## A stop every so often (`t.next_stop`): stand there `dwell`, hazards on (the van) or the
## flashers on and the chime off (the ice-cream truck).
func _dwell_stop(car: Vehicle, t: Dictionary, along: float, v: float, delta: float) -> Vector2:
	var dir := float(t.dir)
	var ice := String(t.work) == "ice_cream"
	var gear := ServiceVehicles.gear_of(car) as ServiceVehicles.IceCreamGear
	if not t.has("next_stop"):
		t.next_stop = along + dir * _rng.randf_range(stop_every.x, stop_every.y)
	var d := (float(t.next_stop) - along) * dir
	var shift := 0.6 if ice else 0.45
	if v < 0.25 and d < 0.8:
		var need: float = t.get("dwell_need", 0.0)
		if need <= 0.0:
			var r: Vector2 = ice_cream_dwell if ice else delivery_dwell
			need = _rng.randf_range(r.x, r.y)
			t.dwell_need = need
		t.dwell = float(t.get("dwell", 0.0)) + delta
		t.hazard = not ice
		if gear:
			gear.set_standing(true)
			gear.set_music(float(t.dwell) < 5.0)
		if float(t.dwell) > need:
			t.dwell = 0.0
			t.dwell_need = 0.0
			t.hazard = false
			t.next_stop = along + dir * _rng.randf_range(stop_every.x, stop_every.y)
			if gear:
				gear.set_standing(false)
				gear.set_music(true)
			return Vector2(INF, 0.0)
		return Vector2(0.0, shift)
	if gear and not gear.standing:
		gear.set_music(true)
	if d < -2.0:
		t.next_stop = along + dir * _rng.randf_range(stop_every.x, stop_every.y)
	t.hazard = not ice and d < 12.0
	return Vector2(d + 0.3, shift if d < 30.0 else 0.0)


# --- Sending them out -------------------------------------------------------------------------------

func _count(kind: int) -> int:
	var n := 0
	for id in _cars.keys():
		var e: Dictionary = _cars[id]
		if int(e.kind) == kind:
			n += 1
	return n


## Our cars that have left the traffic (pooled, knocked out of it, freed): forgotten, their gear
## put back to rest and any cart an arm held set back on the kerb.
func _tend(_delta: float) -> void:
	for id in _cars.keys():
		var e: Dictionary = _cars[id]
		var car: Variant = e.car
		var gone: bool = not is_instance_valid(car) or not (car as Vehicle).is_inside_tree() or not (car as Vehicle).is_traffic() \
				or not (car as Vehicle).traffic.has("work")
		if not gone:
			continue
		if is_instance_valid(car):
			var g := ServiceVehicles.gear_of(car)
			if g:
				g.reset()
		_cars.erase(id)
	if not _picked.is_empty():
		# A cart whose arm is gone goes back to the kerb.
		var held := {}
		for id in _cars.keys():
			var c: Vehicle = _cars[id].car
			if c.traffic.has("cart") and c.traffic.get("lifting", false):
				held[int((c.traffic.cart as Array)[0])] = true
		for key in _picked.keys():
			if not held.has(key):
				_picked.erase(key)
				_bins_dirty = true


func _in_hours(r: Vector2) -> bool:
	var h := hour()
	return h >= r.x and h < r.y


func _dispatch() -> void:
	var pw := _player_world()
	var p := Vector2(pw.x, pw.z)
	if plan.zone_at(p) != MacroMap.Zone.CITY and plan.zone_at(p) != MacroMap.Zone.BEACH:
		return
	if _in_hours(garbage_hours) and _count(ServiceVehicles.GARBAGE) < max_garbage:
		_send_garbage(p)
	var district := plan.district_at(p)
	if _in_hours(ice_cream_hours) and _count(ServiceVehicles.ICE_CREAM) < max_ice_cream \
			and (district == CityPlan.District.SUBURBS or district == CityPlan.District.BEACHTOWN) and _rng.randf() < 0.4:
		_send_roaming(ServiceVehicles.ICE_CREAM, "ice_cream", p, ice_cream_speed)
	if _in_hours(sweeper_hours) and _count(ServiceVehicles.SWEEPER) < max_sweepers and _rng.randf() < 0.3:
		_send_roaming(ServiceVehicles.SWEEPER, "sweep", p, sweeper_speed)
	if _in_hours(delivery_hours) and _count(ServiceVehicles.DELIVERY) < max_delivery and _rng.randf() < 0.5:
		_send_roaming(ServiceVehicles.DELIVERY, "delivery", p, delivery_speed)


## A garbage truck to the busiest kerb of carts round the player, up the street from them.
func _send_garbage(p: Vector2) -> void:
	var kerbs := {}
	for st: Dictionary in _sets:
		var key := Vector3i(int(st.axis), int(st.index), int(st.side))
		if not kerbs.has(key):
			kerbs[key] = []
		(kerbs[key] as Array).append(st)
	var keys := kerbs.keys()
	keys.shuffle()
	for key: Vector3i in keys:
		var list: Array = kerbs[key]
		# A colour some cart of this kerb still has to be emptied of.
		var streams: Array = []
		for st: Dictionary in list:
			for k in 3:
				var c := KerbBins.cart_color(st, k)
				if not _collected.has(int(st.id) * 3 + k) and not c in streams:
					streams.append(c)
		if streams.is_empty():
			continue
		var stream: int = streams[_rng.randi() % streams.size()]
		var busy := false
		for id in _cars:
			var c: Vehicle = _cars[id].car
			if int(_cars[id].kind) == ServiceVehicles.GARBAGE and int(c.traffic.axis) == key.x and int(c.traffic.index) == key.y \
					and int(c.traffic.get("stream", -1)) == stream:
				busy = true
		if busy:
			continue
		# Driving with the carts on its right: the lane on their side.
		var side := float(key.z)
		var dir := int(-side) if key.x == CityPlan.AXIS_X else int(side)
		# Up the street from the first of them.
		var first := INF
		for st: Dictionary in list:
			first = minf(first, float(st.along) * dir)
		var along := first * dir - dir * _rng.randf_range(spawn_back.x, spawn_back.y)
		var car := _place(ServiceVehicles.GARBAGE, key.x, key.y, dir, along, garbage_speed)
		if car != null:
			car.traffic.work = "garbage"
			car.traffic.stream = stream
			return


## A roaming worker on a street round the player: the sweeper along a kerb, the ice-cream truck,
## a delivery van.
func _send_roaming(kind: int, work: String, p: Vector2, speed: float) -> void:
	var axis := _rng.randi_range(0, 1)
	var center := plan.block_index_at(p)
	var index := (center.x if axis == CityPlan.AXIS_X else center.y) + _rng.randi_range(-1, 2)
	var dir := 1 if _rng.randf() < 0.5 else -1
	var here := p.y if axis == CityPlan.AXIS_X else p.x
	var along := here - dir * _rng.randf_range(spawn_back.x, spawn_back.y)
	var car := _place(kind, axis, index, dir, along, speed)
	if car != null:
		car.traffic.work = work


## A service vehicle put down in the kerb lane of road (axis, index) heading `dir`, `along` (true
## world), going `speed`: null when the spot is off the city, closed, too near the player or not
## clear.
func _place(kind: int, axis: int, index: int, dir: int, along: float, speed: float) -> Vehicle:
	var width := plan.road_width(axis, index)
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	var lane := StreetRoute.lane_side(axis, dir) * CityPlan.lane_center(width, lanes, lanes - 1)
	var pos2 := Vector2(plan.road_pos(axis, index) + lane, along) if axis == CityPlan.AXIS_X else Vector2(along, plan.road_pos(axis, index) + lane)
	if plan.zone_at(pos2) != MacroMap.Zone.CITY or not plan.road_open(axis, index, along) or not plan.road_open(axis, index, along + dir * 20.0):
		return null
	if traffic._replica_blocks(pos2, 8.0):
		return null
	var pw := _player_world()
	if pos2.distance_to(Vector2(pw.x, pw.z)) < spawn_clear:
		return null
	if not traffic._lane_clear(axis, index, dir, lane, along, 22.0):
		return null
	if not PhysicsBudget.can_spawn():
		return null
	var car := traffic.place_car(axis, index, dir, lanes - 1, along, speed, false, kind)
	if car == null:
		return null
	var g := ServiceVehicles.gear_of(car)
	if g:
		g.reset()
	_cars[car.get_instance_id()] = {"car": car, "kind": kind}
	return car


# --- Tows -----------------------------------------------------------------------------------------

func _scan_wrecks() -> void:
	if _tows.size() >= max_tows:
		return
	var pw := _player_world()
	var now := Time.get_ticks_msec() / 1000.0
	for w in CarDamage._wrecks:
		if not is_instance_valid(w) or not (w as Node).is_inside_tree() or _no_tow.has((w as Node).get_instance_id()):
			continue
		var car := w as Vehicle
		if car == null or car.freeze or car.linear_velocity.length() > 0.6:
			continue
		var dmg: CarDamage = car._damage
		if dmg != null and is_instance_valid(dmg) and dmg.on_fire():
			continue
		if now - float(car.get_meta("spawn_time", now)) < tow_delay:
			continue
		var wp := WorldState.to_world(car.global_position)
		var dist := wp.distance_to(pw)
		if dist < tow_leave or dist > tow_reach:
			continue
		if send_tow(car):
			return
		_no_tow[car.get_instance_id()] = true


## Sends a tow truck for `wreck` (tests call it directly). True when one is on its way.
func send_tow(wreck: Vehicle) -> bool:
	for e: Dictionary in _tows:
		if e.wreck == wreck:
			return true
	var wp := WorldState.to_world(wreck.global_position)
	var ks := StreetRoute.kerb_stop(plan, Vector2(wp.x, wp.z), 0.0)
	if ks.is_empty():
		return false
	var stop: Vector2 = ks.stop
	if stop.distance_to(Vector2(wp.x, wp.z)) > tow_max_reach:
		return false
	var axis: int = ks.axis
	var index: int = ks.index
	var dir: int = ks.dir
	# The truck's middle this far on from the wreck: its bed, slid back and down, ends a couple
	# of metres short of it.
	var rear := 9.5
	var at: float = float(ks.along) + dir * rear
	var along := at - dir * _rng.randf_range(spawn_back.x, spawn_back.y)
	var car := _place(ServiceVehicles.TOW, axis, index, dir, along, tow_speed)
	if car == null:
		return false
	car.traffic.work = "tow"
	car.traffic.tow_at = at
	CarDamage._wrecks.erase(wreck)
	wreck.set_meta("debris_life", 1.0e9)
	_tows.append({"car": car, "wreck": wreck, "state": "drive", "t": 0.0})
	return true


func _tick_tows(delta: float) -> void:
	for i in range(_tows.size() - 1, -1, -1):
		var e: Dictionary = _tows[i]
		var car: Variant = e.car
		var wreck: Variant = e.wreck
		var car_ok: bool = is_instance_valid(car) and (car as Vehicle).is_inside_tree() and (car as Vehicle).is_traffic()
		if not is_instance_valid(wreck):
			if car_ok:
				(car as Vehicle).traffic.erase("tow_at")
			_tows.remove_at(i)
			continue
		if not car_ok:
			if String(e.state) == "drive":
				# The truck never got there: the wreck goes back on the debris clock.
				(wreck as Node).set_meta("debris_life", 60.0)
				(wreck as Node).set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)
				CarDamage._wrecks.append(wreck)
			else:
				# Gone with the truck.
				(wreck as Node).queue_free()
			_tows.remove_at(i)
			continue
		_tow_step(e, car as Vehicle, wreck as Vehicle, delta)


func _tow_step(e: Dictionary, car: Vehicle, wreck: Vehicle, delta: float) -> void:
	var bed := ServiceVehicles.gear_of(car) as ServiceVehicles.TowBed
	if bed == null:
		return
	var t: Dictionary = car.traffic
	e.t = float(e.t) + delta
	match String(e.state):
		"drive":
			if t.get("arrived", false):
				e.state = "bed_down"
				e.t = 0.0
		"bed_down":
			bed.pose(float(e.t) / bed_seconds)
			if float(e.t) >= bed_seconds:
				_take_wreck(wreck)
				e.from = wreck.global_transform
				e.dist = wreck.global_position.distance_to(bed.deck(3.2).origin)
				e.state = "winch"
				e.t = 0.0
				if bed.winch:
					bed.winch.play()
		"winch":
			var dur := winch_seconds + float(e.dist) / 3.0
			var u := clampf(float(e.t) / dur, 0.0, 1.0)
			var lift := Transform3D(Basis(), Vector3(0.0, wreck.road_lift(), 0.0))
			var foot: Transform3D = bed.deck(3.2) * lift
			var home: Transform3D = bed.deck(0.0) * lift
			var from: Transform3D = e.from
			var xf: Transform3D
			if u < 0.45:
				var a := ServiceVehicles._ease(u / 0.45)
				xf = Transform3D(from.basis.orthonormalized().slerp(foot.basis.orthonormalized(), a), from.origin.lerp(foot.origin, a))
			else:
				xf = foot.interpolate_with(home, ServiceVehicles._ease((u - 0.45) / 0.55))
			wreck.global_transform = xf
			if u >= 1.0:
				e.state = "bed_up"
				e.t = 0.0
				if bed.winch:
					bed.winch.stop()
		"bed_up":
			bed.pose(1.0 - float(e.t) / bed_seconds)
			wreck.global_transform = bed.deck(0.0) * Transform3D(Basis(), Vector3(0.0, wreck.road_lift(), 0.0))
			if float(e.t) >= bed_seconds:
				bed.pose(0.0)
				e.state = "carry"
				t.erase("tow_at")
				t.arrived = false
		"carry":
			wreck.global_transform = bed.deck(0.0) * Transform3D(Basis(), Vector3(0.0, wreck.road_lift(), 0.0))


## The wreck off the physics: its wheels off (a frozen VehicleBody3D with wheels is NaN), frozen
## kinematic, no collision, out of the debris lists - it rides the bed now.
func _take_wreck(w: Vehicle) -> void:
	for wh in w.wheels:
		if is_instance_valid(wh):
			w.remove_child(wh)
			wh.free()
	w.wheels.clear()
	w.linear_velocity = Vector3.ZERO
	w.angular_velocity = Vector3.ZERO
	w.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	w.freeze = true
	w.collision_layer = 0
	w.collision_mask = 0
	w.remove_from_group("physics_prop")
	w.remove_from_group("debris")
	CarDamage._wrecks.erase(w)


## Tests and stills: the tow in hand for `wreck` ({} none).
func tow_of(wreck: Node) -> Dictionary:
	for e: Dictionary in _tows:
		if e.wreck == wreck:
			return e
	return {}


static func live() -> ServiceFleet:
	return _live


# --- Stills ---------------------------------------------------------------------------------------

## Stages one at work in front of `cam` for tools/glshot/still_shot.gd (SERVICE=...): "garbage" a
## truck at the cart set nearest the camera's view with a cart up in its arm, "sweeper" a sweeper
## at the kerb with its brooms going, "tow" a tow truck with a burnt-out wreck on its bed,
## "ice_cream" the ice-cream truck standing at the kerb. Held still (no work, speed 0, the arm's
## clock stopped). Returns an EYE ("x,y,z,yaw,pitch", true world) that frames it, or "".
func stage_for_shot(scene: String, cam: Camera3D) -> String:
	if not _setup():
		return ""
	traffic.staged = true
	var cw := WorldState.to_world(cam.global_position)
	var fwd := -cam.global_basis.z
	var f2 := Vector2(fwd.x, fwd.z).normalized()
	var look := Vector2(cw.x, cw.z) + f2 * 25.0
	var lift := float(OS.get_environment("SERVICE_LIFT")) if OS.get_environment("SERVICE_LIFT") != "" else 0.55
	match scene:
		"garbage":
			var best := {}
			var best_d := INF
			var day := weekday
			for st: Dictionary in KerbBins.sets_near(plan, look, 260.0):
				var d := KerbBins.cart_pos(plan, st, 1).distance_to(look)
				if d < best_d:
					best_d = d
					best = st
			if best.is_empty():
				return ""
			for k in 7:
				if KerbBins.street_out(plan, int(best.axis), int(best.index), k):
					day = k
					break
			weekday = day
			_survey_bins()
			var axis: int = best.axis
			var dir := int(-float(best.side)) if axis == CityPlan.AXIS_X else int(float(best.side))
			var c := KerbBins.cart_pos(plan, best, 1)
			var a := c.y if axis == CityPlan.AXIS_X else c.x
			var lanes := 2 if plan.road_width(axis, int(best.index)) > plan.street_width + 1.0 else 1
			var car := traffic.place_car(axis, int(best.index), dir, lanes - 1, a - dir * ServiceVehicles.ARM_AHEAD, 0.0, false, ServiceVehicles.GARBAGE)
			if car == null:
				return ""
			car.traffic.shift = kerb_shift
			_cars[car.get_instance_id()] = {"car": car, "kind": ServiceVehicles.GARBAGE}
			await get_tree().physics_frame
			await get_tree().physics_frame
			var arm := ServiceVehicles.gear_of(car) as ServiceVehicles.GarbageArm
			var key := int(best.id) * 3 + 1
			if arm and arm.begin(cart_xform(best, 1), KerbBins.cart_color(best, 1), _cart_taken.bind(key), _cart_back.bind(key)):
				var until := arm.T_EXT + arm.T_GRAB + arm.T_LIFT * lift
				while arm.t < until:
					arm.advance(1.0 / 60.0)
				arm.set_process(false)
			car.traffic.speed = 0.0
			_draw_bins()
			var side := StreetRoute.lane_side(axis, dir)
			var across := Vector2(1.0, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, 1.0)
			var along_v := Vector2(0.0, 1.0) if axis == CityPlan.AXIS_X else Vector2(1.0, 0.0)
			var e2 := c + across * side * 4.2 + along_v * float(dir) * 9.0
			var tgt := c + along_v * float(dir) * -1.0 - across * side * 1.5
			return _eye(e2, 1.6, tgt, 1.9)
		"sweeper", "ice_cream", "tow", "delivery":
			var ks := StreetRoute.kerb_stop(plan, look, 0.0)
			if ks.is_empty():
				return ""
			var axis: int = ks.axis
			var dir: int = ks.dir
			var lanes := 2 if plan.road_width(axis, int(ks.index)) > plan.street_width + 1.0 else 1
			var kind: int = {"sweeper": ServiceVehicles.SWEEPER, "ice_cream": ServiceVehicles.ICE_CREAM, "tow": ServiceVehicles.TOW,
				"delivery": ServiceVehicles.DELIVERY}[scene]
			var along := float(ks.along)
			var car := traffic.place_car(axis, int(ks.index), dir, lanes - 1, along, 0.0, false, kind)
			if car == null:
				return ""
			car.traffic.shift = kerb_shift if scene == "sweeper" else 0.6
			_cars[car.get_instance_id()] = {"car": car, "kind": kind}
			await get_tree().physics_frame
			var gear := ServiceVehicles.gear_of(car)
			var side := StreetRoute.lane_side(axis, dir)
			var across := Vector2(1.0, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, 1.0)
			var along_v := Vector2(0.0, 1.0) if axis == CityPlan.AXIS_X else Vector2(1.0, 0.0)
			var road := plan.road_pos(axis, int(ks.index))
			var w := plan.road_width(axis, int(ks.index))
			var at := along_v * along + across * road
			var kerb_pt := at + across * side * (w * 0.5 + 1.5)
			match scene:
				"sweeper":
					(gear as ServiceVehicles.SweeperGear).set_working(true)
					for i in 40:
						(gear as ServiceVehicles.SweeperGear)._process(1.0 / 60.0)
					return _eye(kerb_pt + along_v * float(dir) * 11.0, 1.6, at + across * side * 2.5, 1.0)
				"ice_cream":
					car.traffic.hazard = false
					(gear as ServiceVehicles.IceCreamGear).set_standing(true)
					(gear as ServiceVehicles.IceCreamGear).set_music(true)
					return _eye(kerb_pt + along_v * float(dir) * 6.5 + across * side * 0.5, 1.6, at + across * side * 2.6 - along_v * float(dir) * 1.0, 1.7)
				"delivery":
					car.traffic.hazard = true
					return _eye(kerb_pt - along_v * float(dir) * 9.0, 1.6, at + across * side * 2.0, 1.2)
				"tow":
					var rng := RandomNumberGenerator.new()
					rng.seed = 21
					var wreck := Vehicle.random_car(rng)
					get_parent().add_child(wreck)
					wreck.global_position = car.global_position + Vector3(0.0, 3.0, 0.0)
					await get_tree().physics_frame
					var dmg := wreck.damage_state()
					dmg.become_wreck()
					await get_tree().physics_frame
					dmg.extinguish()
					_take_wreck(wreck)
					wreck.global_transform = (gear as ServiceVehicles.TowBed).deck(0.0) * Transform3D(Basis(), Vector3(0.0, wreck.road_lift(), 0.0))
					_tows.append({"car": car, "wreck": wreck, "state": "carry", "t": 0.0})
					return _eye(kerb_pt - along_v * float(dir) * 12.0 + across * side * 1.0, 1.7, at + across * side * 1.5 - along_v * float(dir) * 1.5, 1.4)
	return ""


func _eye(e2: Vector2, up: float, target: Vector2, target_up: float) -> String:
	var e := Vector3(e2.x, plan.height_at(e2) + CityChunk.SIDEWALK_TOP + up, e2.y)
	var t := Vector3(target.x, plan.height_at(target) + target_up, target.y)
	var d := t - e
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [e.x, e.y, e.z, yaw, pitch]
