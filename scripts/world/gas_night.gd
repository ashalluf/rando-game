class_name GasNight
extends RefCounted
## A gas station at night (wave 8 refcam `gas_station_night`, docs/HANDOFF.md "The gas station at
## 23:30"). Hooks in Roadside._gas(), all AFTER the pad's own rolls (hashes of seed + place only):
##
## * The canopy LIGHTS its forecourt: the forecourt concrete is written with the canopy's half size
##   and turn in UV2 (`forecourt_u2()`), and roadside.gdshader works out per pixel the light of
##   every recessed LED panel (a downward Lambert source: h^4 / r^4) - bright pools under the panels,
##   a falloff past the canopy's edge - and the panels mirrored in the sealed concrete as soft
##   glossy blobs (the reflected ray met with the soffit's plane). Was: one flat additive pool.
## * A car at a pump (`PUMP_CAR_ODDS` of gas stations, a real parked Vehicle, empty, lamps off, meta
##   `roadside`) beside a hash-picked island, its filler by the dispenser, and its driver standing
##   at the pump (a StreetVendor, in the crowd cap) - `CUSTOMER_ODDS` of those.
## * The canopy's light reaches what stands under it: the omni is moved down and out to cover the
##   whole canopy and the islands (`LIGHT_REACH_GAIN`).
##
## `GAS_NIGHT=0` is the A/B (the station exactly as before). Checks: tests/rc5_gas_station_night_checks.gd.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("GAS_NIGHT") != "0"
## Forced on for every gas station (refcam staging and checks): `PUMP_CAR=1`.
static var force_pump_car: bool = OS.get_environment("PUMP_CAR") == "1"

## Share of gas stations with a car at a pump.
const PUMP_CAR_ODDS := 0.6
## Share of those whose driver stands at the pump.
const CUSTOMER_ODDS := 0.8
## Metres from the island's centre line to the car's.
const CAR_OFFSET := 2.25
## Metres from the island's centre line to where the customer stands.
const CUSTOMER_OFFSET := 1.0
## The canopy omni's reach, as a share of the canopy's half diagonal (plus 6 m).
const LIGHT_REACH_GAIN := 1.25
## The old flat forecourt pool's strength with the canopy's light on (it still spills onto the apron).
const POOL_ALPHA := 0.55
## Where a value in UV2.x says "forecourt": UV2.x = FLAG + half width, UV2.y = half depth + 100 x quarter turns.
const FLAG := 100.0

static var stats := {"cars": 0, "customers": 0, "forecourts": 0}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100000) / 100000.0


## The forecourt concrete's UV2 (roadside.gdshader's code-2 branch reads it): the canopy's half size
## and the pad's quarter turn. Its UV is then frame metres FROM THE CANOPY'S CENTRE.
static func forecourt_u2(yaw: float, cw: float, cd: float) -> Vector2:
	var q := posmod(roundi(yaw / (PI * 0.5)), 4)
	return Vector2(FLAG + cw * 0.5, cd * 0.5 + 100.0 * q)


## The canopy omni: (position in the frame, reach).
static func light_spot(cc: Vector2, cw: float, cd: float, under: float) -> Array:
	var reach := Vector2(cw, cd).length() * 0.5 * LIGHT_REACH_GAIN + 6.0
	return [Vector3(cc.x, under - 1.2, cc.y), reach]


## A car at a pump and its driver (FULL chunks, after every roll of the pad). `islands` is
## [[x, y, [pump z, ...]], ...] in the pad's frame.
static func dress(s: Variant, islands: Array, cc: Vector2) -> void:
	if not enabled or not s.full or islands.is_empty():
		return
	var ch: CityChunk = s.ch
	var c: Vector2 = s.lot.center
	var key := [ch.plan.seed, int(c.x * 4.0), int(c.y * 4.0), "gas_night"]
	if not force_pump_car and _h01(key + ["car"]) >= PUMP_CAR_ODDS:
		return
	var isl: Array = islands[absi(hash(key + ["island"])) % islands.size()]
	var pumps: Array = isl[2]
	var pz: float = pumps[absi(hash(key + ["pump"])) % pumps.size()]
	var side := 1.0 if _h01(key + ["side"]) < 0.5 else -1.0
	var ix: float = isl[0]
	# Nose toward the canopy's far end from the pump, so the rear quarter (the filler) is at it.
	var dir := 1.0 if pz < cc.y else -1.0
	if absf(pz - cc.y) < 0.3:
		dir = 1.0 if _h01(key + ["dir"]) < 0.5 else -1.0
	var car_at := Vector2(ix + side * CAR_OFFSET, pz + dir * 1.15)
	var yaw := 0.0 if dir < 0.0 else PI  # frame -z is yaw 0
	var w: Vector3 = s.at(Vector3(car_at.x, 0.0, car_at.y))
	var world_yaw: float = s.yaw + yaw
	var seed := hash(key + ["vehicle"])
	ch._run_or_defer(func() -> bool:
		if not is_instance_valid(ch) or not PhysicsBudget.can_spawn():
			return true
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var car := Vehicle.random_car(rng)
		car.set_meta("roadside", true)
		car.set_meta("pump_car", true)
		var holder: Node = ch.get_parent() if ch.get_parent() else ch
		var spot := Vector3(w.x, Roadside.TOP + ch._gy(w.x, w.z) + Roadside.GROUND_LIFT + 0.4, w.z)
		car.position = WorldState.to_local(spot) if holder != ch else spot
		car.rotation.y = world_yaw
		holder.add_child(car)
		car.visible = ch.visible
		ch._cars.append(car)
		stats.cars += 1
		return true)
	if _h01(key + ["customer"]) >= CUSTOMER_ODDS and not force_pump_car:
		return
	var p_at := Vector2(ix + side * CUSTOMER_OFFSET, pz + dir * 0.15)
	var pw: Vector3 = s.at(Vector3(p_at.x, 0.0, p_at.y))
	# Facing the dispenser (toward the island's centre line).
	var face: Vector3 = s.xf.basis * Vector3(-side, 0.0, 0.0)
	var face_yaw := atan2(-face.x, -face.z)
	var lot_rect := Rect2(c - Vector2(s.w, s.d) * 0.5, Vector2(s.w, s.d)).grow(4.0)
	var pseed := absi(hash(key + ["person"]))
	ch._run_or_defer(func() -> bool:
		if not is_instance_valid(ch) or not ch._take_crowd_room():
			return true
		var at := Vector2(pw.x, pw.z)
		var floor_y := Roadside.TOP + ch._gy(at.x, at.y) + Roadside.GROUND_LIFT
		var ped := StreetVendor.new()
		ped.setup_vendor(lot_rect, pseed, at, face_yaw, false, floor_y - ch.ground_y(at.x, at.y))
		ped.position = Vector3(at.x, floor_y + 0.05, at.y)
		ped.add_to_group("gas_customer")
		ch.add_child(ped)
		stats.customers += 1
		return true)
