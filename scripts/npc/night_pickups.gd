class_name NightPickups
extends Node
## Taxis and ride-hail cars at the venues (NightLife), late: now and then a street car coming
## along in the kerb lane toward an open club or bar near the player is given the door as its
## stop - TrafficManager's double-park (`dp_at`: it pulls over beside the parked cars, stops on
## its hazards, the traffic behind passes it) - and somebody who was inside comes out of the door,
## crosses the pavement to its kerb side and gets in; the car drives on. A taxi on that stretch
## is taken first. If nobody comes out it waits its time on the hazards and leaves (a no-show).
##
## One node under the current scene, made by the first chunk that builds a venue (ensure()).
## Every roll is a hash of the venue and the minute, never a shared rng. `NIGHTLIFE=0` turns it
## off with the rest.

## Seconds between looks, how close to the player a venue must be, the gap between one venue's
## pickups (s) and the chance one is called on a look once that gap has passed.
@export var look_seconds: float = 0.5
@export var reach: float = 260.0
@export var gap_seconds: Vector2 = Vector2(25.0, 70.0)
@export var call_chance: float = 0.35
## How far up the road from the door a car may be when it is called (m).
const CALL_RANGE := Vector2(28.0, 170.0)
## How long a called car waits at the door (s).
@export var wait_seconds: Vector2 = Vector2(26.0, 48.0)

static var _inst: NightPickups
static var _made_frame: int = -10
## Pickups called (a running count, for the checks and the HUD).
static var called: int = 0
static var boarded: int = 0

var _timer: float = 0.0


static func ensure(from: Node) -> void:
	if not NightLife.enabled or from == null or not from.is_inside_tree():
		return
	if _inst != null and is_instance_valid(_inst):
		if _inst.is_inside_tree():
			return
		if _inst.get_parent() == null and Engine.get_process_frames() <= _made_frame + 1:
			return
		if _inst.get_parent() == null:
			_inst.free()
		_inst = null
	var scene := from.get_tree().current_scene
	if scene == null:
		return
	_inst = NightPickups.new()
	_inst.name = "NightPickups"
	_made_frame = Engine.get_process_frames()
	scene.add_child.call_deferred(_inst)


func _traffic() -> TrafficManager:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Traffic") as TrafficManager if scene else null


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = look_seconds
	var tm := _traffic()
	if tm == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var now := Pedestrian._life_now_ms()
	for v: Dictionary in NightLife.venues:
		if not is_instance_valid(v.get("chunk")) or not (v.chunk as Node).is_inside_tree():
			continue
		if v.get("pickup") != null:
			tick(v)
			continue
		if not bool(v.get("open", false)) or tm.staged:
			continue
		if player != null:
			var door: Vector2 = v.door
			var p := WorldState.to_world(player.global_position)
			if Vector2(p.x, p.z).distance_to(door) > reach:
				continue
		if now < int(v.get("next_pickup_ms", 0)):
			continue
		var minute := now / 60000
		v.next_pickup_ms = now + int(1000.0 * lerpf(gap_seconds.x, gap_seconds.y, NightLife._h01([v.key, minute, "nl_gap"])))
		if NightLife._h01([v.key, now / 1000, "nl_call"]) >= call_chance:
			continue
		var car := pick_car(tm, v)
		if car != null:
			call_car(car, v, lerpf(wait_seconds.x, wait_seconds.y, NightLife._h01([v.key, minute, "nl_wait"])))


## The street car that should take a fare at venue `v`: in the kerb lane of the road in front,
## heading the way that puts the door on its kerb side, CALL_RANGE up the road from the door,
## driving free (no stop, lane change, panic or job of its own). A taxi first, else the nearest.
static func pick_car(tm: TrafficManager, v: Dictionary) -> Vehicle:
	var road: Array = v.road
	var axis := int(road[0])
	var index := int(road[1])
	var dir := int(road[2])
	var at := float(road[3])
	var lanes := TrafficAI.lanes_of(tm.plan, axis, index)
	var kerb_lane := TrafficAI.lane_offset_n(tm.plan, axis, index, dir, lanes - 1)
	var best: Vehicle = null
	var best_score := INF
	for car: Vehicle in tm.cars:
		if not is_instance_valid(car) or car.traffic.is_empty():
			continue
		var t: Dictionary = car.traffic
		if int(t.get("axis", -1)) != axis or int(t.get("index", -999999)) != index or int(t.get("dir", 0)) != dir:
			continue
		if absf(float(t.get("lane", 0.0)) - kerb_lane) > 0.6:
			continue
		var busy := false
		for k in ["dp_at", "bus", "park_at", "work", "pull", "lc_from", "lc_want", "cp", "placed", "police", "parked"]:
			if t.has(k):
				busy = true
				break
		if busy or BigVehicles.is_big(car.body_type) or Motorcycle.is_moto(car.body_type) or Lowrider.is_lowrider(car.body_type):
			continue
		var ahead := (at - float(t.get("along", 0.0))) * float(dir)
		if ahead < CALL_RANGE.x or ahead > CALL_RANGE.y:
			continue
		var score := ahead - (200.0 if car.body_type == Vehicle.BodyType.TAXI else 0.0)
		if score < best_score:
			best_score = score
			best = car
	return best


## Sends `car` to venue `v`'s door: it double-parks there on its hazards for `wait` seconds.
static func call_car(car: Vehicle, v: Dictionary, wait: float) -> void:
	var t: Dictionary = car.traffic
	var road: Array = v.road
	var dir := int(road[2])
	var half := float(t.get("half", 2.3))
	t.dp_at = float(road[3]) + float(dir) * half
	t.dp = wait
	t.sig = 1
	t.nl = int(v.key)
	v.pickup = car
	v.passenger = null
	v.boarded = false
	called += 1


## One look at a venue's pickup: a car standing at the door sends somebody out to it, holds while
## they cross, and drives on once they are in.
static func tick(v: Dictionary) -> void:
	var car: Vehicle = v.pickup if is_instance_valid(v.pickup) else null
	if car == null or car.traffic.is_empty() or not car.traffic.has("dp_at") or int(car.traffic.get("nl", 0)) != int(v.key):
		if car != null and not car.traffic.is_empty():
			car.traffic.erase("nl")
		v.pickup = null
		v.passenger = null
		return
	var t: Dictionary = car.traffic
	var standing := float(t.get("v", 1.0)) < 0.3 and int(t.get("sig", 0)) == 2
	var who: NightGoer = v.passenger if is_instance_valid(v.get("passenger")) else null
	if who == null and standing:
		for p in v.inside:
			if is_instance_valid(p) and (p as NightGoer).is_inside():
				who = p
				break
		if who != null:
			who.go_to_car(car, kerb_point(v, car))
			v.passenger = who
	if who == null:
		return
	if who.state == NightGoer.State.TO_CAR:
		t.dp = maxf(float(t.get("dp", 0.0)), 1.5)
	elif who.state == NightGoer.State.IN_CAR:
		if not bool(v.get("boarded", false)):
			v.boarded = true
			boarded += 1
		t.dp = minf(float(t.get("dp", 0.0)), 1.2)


## Where a passenger stands to get into `car` at venue `v`: on the pavement at the kerb, level
## with the car's middle (chunk space: the true world).
static func kerb_point(v: Dictionary, car: Vehicle) -> Vector2:
	var w := WorldState.to_world(car.global_position)
	var door: Vector2 = v.door
	var out: Vector2 = v.out
	var along := out.orthogonal()
	var s := (Vector2(w.x, w.z) - door).dot(along)
	return door + out * (float(v.kerb) - 0.45) + along * s
