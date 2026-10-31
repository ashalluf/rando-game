class_name PoliceChase
extends Node
## How the police chase a player in a car, GTA style (fleet wave 4, "police-chase-2";
## docs/HANDOFF.md "The police chase"). One node under the Police node (attach(), one line in
## Police._ready()). Police.gd keeps the stars, the caps and the dispatch; this is the manoeuvres:
##
##   BOX     the player's car is slow or stopped: the nearest cruisers take the slots round it
##           (behind, in front, either side), nose in, and stop there - boxed in, the crews get out.
##   PIT     the player's car is fast: the nearest cruiser behind draws alongside, its front bumper
##           level with the car's rear wheel, matches speed, then turns in. The contact is helped
##           (pit_assist(): an impulse at the rear quarter and the rear tyres' grip let go for a
##           moment), because a VehicleBody3D's wheels hold a car straight through a real tap.
##   FLANK   any other cruiser near a fast car rides off its rear quarter on the other side.
##   SPIKES  a roadblock lays a spike strip across the carriageway on the player's side of the
##           cruisers (ChaseSpikeStrip); a tyre over it goes flat (ChaseFlatTyres).
##   DOORS   officers out of a stopped cruiser with the player ahead of it take cover behind its
##           open front doors (CarInterior's door rig, jammed open), then advance by bounds, one
##           at a time per car while the other covers.
##   AIR     the police helicopter's searchlight leads a fast car (spot_target()).
##   RADIO   synthesised dispatch chatter on each of these (ChaseRadio).
##
## PoliceCar._pursue() asks tactic() each physics tick (two lines); PoliceOfficer._think() asks
## door_cover() (two lines); Police._place_roadblock() calls roadblock() (one line); AirTraffic
## calls spot_target() (one line); CarInteriors keeps the open-door cruisers' rigs (one line).
## Nothing here rolls a random number from a seed stream: roles are by distance, sides by geometry,
## the radio's babble is a hash of a counter. `POLICE_CHASE=0` in the environment is the A/B.

enum Role { NONE, BOX, PIT, FLANK }

static var enabled: bool = OS.get_environment("POLICE_CHASE") != "0"

@export_group("Roles")
## How often the roles are dealt out (s), and the furthest a cruiser can be from the player's car
## to get one (m). Further out it drives the streets (PoliceCar's own routing).
@export var assign_interval: float = 0.25
@export var tactic_range: float = 55.0
## Under this speed (m/s) the player's car is boxed in; over pit_speed it gets the PIT.
@export var box_speed: float = 7.0
@export var pit_speed: float = 11.0
## Seconds between two PIT attempts on the same car.
@export var pit_cooldown: float = 7.0

@export_group("Box")
## Gap between a boxing cruiser's body and the player's car (m), and how near its slot it must be
## to stop there.
@export var box_gap: float = 0.7
@export var box_arrive: float = 1.9
## Fastest a cruiser closes on its slot (m/s, over the target's own speed).
@export var box_close_speed: float = 14.0

@export_group("PIT")
## Gap alongside while it lines up (m), how long it must hold the line before turning in (s), and
## how far ahead along the car it aims while lining up (m).
@export var pit_gap: float = 0.55
@export var pit_hold: float = 0.35
@export var pit_look: float = 9.0
## The assist: the yaw kick it gives the car (rad/s), the sideways shove at the rear (m/s) and
## how long the car's rear tyres lose their grip (s, to this share of it).
@export var pit_spin: float = 2.4
@export var pit_shove: float = 2.2
@export var pit_slip_seconds: float = 0.9
@export var pit_slip_share: float = 0.25
## Contact reach for the assist: the cruiser's front corner within this of the car's rear quarter (m).
@export var pit_reach: float = 1.35
## Seconds a turn-in may take before it is given up.
@export var pit_timeout: float = 1.8

@export_group("Doors and bounds")
## Seconds behind a door before an officer bounds forward, how far a bound goes (m), how long it
## holds after one (s), and how close to the player bounds stop (m).
@export var advance_after: float = 6.5
@export var bound_length: float = 7.0
@export var bound_hold: float = 3.2
@export var advance_stop: float = 16.0
## Most cruisers with their doors open at once (each has a CarInterior rig: geometry).
@export var max_door_cars: int = 3

@export_group("Spikes")
## The strip lies this far in front of a roadblock, toward the player (m).
@export var spike_ahead: float = 15.0

@export_group("Air")
## The searchlight aims this many seconds ahead of a moving car (its gimbal slews at about 3.5
## a second, so it trails ~0.3 s), and the beam's hunting shrinks to this share at chase speed.
@export var light_lead: float = 0.32
@export var light_calm: float = 0.25

var police: Police
var radio: ChaseRadio
## Car instance id -> {"role", "side", "phase", "t", "slot"}.
var roles: Dictionary = {}
## How many PITs, box-ins and strips there have been (the checks and tuning read them).
var pits: int = 0
var boxes: int = 0
var strips: Array[ChaseSpikeStrip] = []
## Officer instance id -> {"phase", "t", "spot"}.
var _bounds: Dictionary = {}
## Cruisers whose doors stand open (instance id -> PoliceCar).
var door_cars: Dictionary = {}
var _assign_t: float = 0.0
var _pit_cool: float = 0.0
var _door_t: float = 0.0
var _was_known: bool = false
var _boxed: bool = false
## Grip let go for a while: [wheel, original slip, seconds left].
var _slips: Array = []

static var _inst: PoliceChase = null


static func attach(p: Police) -> void:
	if not enabled:
		return
	var c := PoliceChase.new()
	c.name = "Chase"
	c.police = p
	p.add_child(c)
	_inst = c


static func instance() -> PoliceChase:
	return _inst if _inst != null and is_instance_valid(_inst) and _inst.is_inside_tree() else null


func _ready() -> void:
	radio = ChaseRadio.new()
	radio.name = "Radio"
	add_child(radio)


func _exit_tree() -> void:
	if _inst == self:
		_inst = null


func _physics_process(delta: float) -> void:
	_tick_slips(delta)
	if not enabled or police == null:
		return
	_pit_cool = maxf(_pit_cool - delta, 0.0)
	_door_t -= delta
	if _door_t <= 0.0:
		_door_t = 0.5
		_tick_doors()
	if police.stars <= 0:
		roles.clear()
		_bounds.clear()
		_boxed = false
		_was_known = false
		return
	var known := police.player_known()
	if known and not _was_known and police.player_driving():
		radio.say("pursuit")
	_was_known = known
	_assign_t -= delta
	if _assign_t <= 0.0:
		_assign_t = assign_interval
		_assign()


# --- Roles ------------------------------------------------------------------------------------

## The player's car as a frame: [position, forward (flat), right, half length, half width, speed].
static func car_frame(car: Vehicle) -> Array:
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.05 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var dims := car._dims()
	var v := car.linear_velocity
	return [car.global_position, fwd, right, float(dims.get("length", 4.6)) * 0.5, float(dims.get("width", 1.85)) * 0.5,
		Vector2(v.x, v.z).length()]


## Where four boxing cruisers stand round a car (scene positions): behind, in front, left, right.
## `half_len` / `half_w` are the cruiser's own half sizes.
static func box_slots(frame: Array, half_len: float, half_w: float, gap: float) -> Array[Vector3]:
	var p: Vector3 = frame[0]
	var f: Vector3 = frame[1]
	var r: Vector3 = frame[2]
	var hl: float = frame[3]
	var hw: float = frame[4]
	return [
		p - f * (hl + half_len + gap),
		p + f * (hl + half_len + gap),
		p - r * (hw + half_w + gap) - f * 0.4,
		p + r * (hw + half_w + gap) - f * 0.4,
	]


## Where a PIT cruiser's centre lines up: alongside on `side` (+1 the car's right), its front
## bumper level with the car's rear wheel.
static func pit_slot(frame: Array, side: float, half_len: float, half_w: float, gap: float) -> Vector3:
	var p: Vector3 = frame[0]
	var f: Vector3 = frame[1]
	var r: Vector3 = frame[2]
	var hl: float = frame[3]
	var hw: float = frame[4]
	return p - f * (hl * 0.55 + half_len) + r * side * (hw + half_w + gap)


func _assign() -> void:
	var target := police.player_vehicle()
	if target == null or not is_instance_valid(target):
		roles.clear()
		_boxed = false
		return
	var frame := car_frame(target)
	var tp: Vector3 = frame[0]
	var speed: float = frame[5]
	var cand: Array = []
	for c in police.cruisers:
		if not is_instance_valid(c):
			continue
		var car: PoliceCar = c
		if car.driver != null or car.roadblock or car.scripted or car.is_traffic() or car.is_wreck() or car.crew_alive <= 0:
			continue
		if car.mode != PoliceCar.Mode.PURSUE or car.global_basis.y.y < 0.6:
			continue
		var d := car.global_position.distance_to(tp)
		if d < tactic_range:
			cand.append([d, car])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var live := {}
	for e in cand:
		live[(e[1] as PoliceCar).get_instance_id()] = true
	for id in roles.keys():
		if not live.has(id):
			roles.erase(id)
	if cand.is_empty():
		_boxed = false
		return
	if speed < box_speed:
		_assign_box(cand, frame)
		return
	_boxed = false
	# A PIT under way keeps its car; otherwise the nearest one behind gets it.
	var pit_car: PoliceCar = null
	for e in cand:
		var r: Dictionary = roles.get((e[1] as PoliceCar).get_instance_id(), {})
		if int(r.get("role", Role.NONE)) == Role.PIT:
			pit_car = e[1]
	var f: Vector3 = frame[1]
	var rt: Vector3 = frame[2]
	if pit_car == null and speed > pit_speed and _pit_cool <= 0.0:
		for e in cand:
			var car: PoliceCar = e[1]
			if (car.global_position - tp).dot(f) < 2.0:
				pit_car = car
				var lat := (car.global_position - tp).dot(rt)
				roles[car.get_instance_id()] = {"role": Role.PIT, "side": 1.0 if lat >= 0.0 else -1.0, "phase": 0, "t": 0.0}
				radio.say("pit")
				break
	var pit_side := 0.0
	if pit_car != null:
		pit_side = float(roles[pit_car.get_instance_id()].side)
	var flank_side := -pit_side if pit_side != 0.0 else 1.0
	for e in cand:
		var car: PoliceCar = e[1]
		if car == pit_car:
			continue
		var id := car.get_instance_id()
		var r: Dictionary = roles.get(id, {})
		if int(r.get("role", Role.NONE)) != Role.FLANK:
			roles[id] = {"role": Role.FLANK, "side": flank_side, "phase": 0, "t": 0.0}
		flank_side = -flank_side


func _assign_box(cand: Array, frame: Array) -> void:
	var slots := box_slots(frame, 2.47, 0.92, box_gap)
	var taken := {}
	var busy := 0
	for e in cand:
		var car: PoliceCar = e[1]
		var id := car.get_instance_id()
		var r: Dictionary = roles.get(id, {})
		if int(r.get("role", Role.NONE)) == Role.BOX:
			taken[int(r.slot)] = true
	for e in cand:
		var car: PoliceCar = e[1]
		var id := car.get_instance_id()
		var r: Dictionary = roles.get(id, {})
		if int(r.get("role", Role.NONE)) == Role.BOX:
			continue
		var best := -1
		var best_d := INF
		for k in slots.size():
			if taken.has(k):
				continue
			var d := car.global_position.distance_to(slots[k])
			if d < best_d:
				best_d = d
				best = k
		if best < 0:
			roles.erase(id)
			continue
		taken[best] = true
		roles[id] = {"role": Role.BOX, "slot": best, "phase": 0, "t": 0.0}
	for e in cand:
		var r: Dictionary = roles.get((e[1] as PoliceCar).get_instance_id(), {})
		if int(r.get("role", Role.NONE)) == Role.BOX:
			busy += 1
	if busy > 0 and not _boxed:
		radio.say("box")


## What a pursuing cruiser does this tick: {"aim": scene point to steer at, "want": forward speed
## (m/s)} or {} for PoliceCar's own driving. Called from PoliceCar._pursue().
static func tactic(car: PoliceCar) -> Dictionary:
	var inst := instance()
	if inst == null or not enabled:
		return {}
	return inst._tactic(car)


func _tactic(car: PoliceCar) -> Dictionary:
	var r: Dictionary = roles.get(car.get_instance_id(), {})
	var role := int(r.get("role", Role.NONE))
	if role == Role.NONE:
		return {}
	var target := police.player_vehicle()
	if target == null or not is_instance_valid(target):
		return {}
	var frame := car_frame(target)
	var tp: Vector3 = frame[0]
	var f: Vector3 = frame[1]
	var tspeed: float = frame[5]
	var dt := get_physics_process_delta_time()
	r.t = float(r.t) + dt
	var dims := car._dims()
	var hl := float(dims.get("length", 4.9)) * 0.5
	var hw := float(dims.get("width", 1.84)) * 0.5
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.05 else Vector3.FORWARD
	var speed := car.linear_velocity.dot(fwd)
	match role:
		Role.BOX:
			var slot: Vector3 = box_slots(frame, hl, hw, box_gap)[int(r.slot)]
			var to := slot - car.global_position
			to.y = 0.0
			var d := to.length()
			if d < box_arrive and absf(speed) < 3.5 and tspeed < box_speed:
				roles.erase(car.get_instance_id())
				car.stop_here()
				_note_boxed(target)
				return {"aim": slot, "want": 0.0}
			# Nose in on a side or in front: aim through the slot at the car, not past it.
			var aim := slot + (tp - slot).normalized() * 3.0 if d < 6.0 else slot
			return {"aim": aim, "want": clampf(d * 1.1, 0.0, box_close_speed) + tspeed}
		Role.PIT:
			var side := float(r.side)
			var slot := pit_slot(frame, side, hl, hw, pit_gap)
			var to := slot - car.global_position
			to.y = 0.0
			var along := to.dot(f)
			var across := to.dot(frame[2] as Vector3)
			if int(r.phase) == 0:
				# Lining up: ride the slot, parallel to the car.
				var lined := absf(along) < 1.4 and absf(across) < 0.9 and tspeed > pit_speed
				r.hold = float(r.get("hold", 0.0)) + dt if lined else 0.0
				if float(r.hold) > pit_hold:
					r.phase = 1
					r.t = 0.0
				if float(r.t) > 12.0:
					_end_pit(car)
					return {}
				return {"aim": slot + f * pit_look, "want": tspeed + clampf(along * 1.6, -6.0, 9.0)}
			# Turning in: at the rear quarter, a little ahead of it, faster than the car.
			var rear := tp - f * float(frame[3]) * 0.7
			var corner := car.global_position + fwd * hl - (frame[2] as Vector3) * side * hw
			if corner.distance_to(rear + (frame[2] as Vector3) * side * float(frame[4])) < pit_reach + hw:
				pit_assist(car, target, side)
				_end_pit(car)
				return {}
			if float(r.t) > pit_timeout:
				_end_pit(car)
				return {}
			return {"aim": rear + f * 2.5, "want": tspeed + 2.5}
		Role.FLANK:
			var side := float(r.side)
			var slot := tp - f * (float(frame[3]) + hl + 3.5) + (frame[2] as Vector3) * side * (float(frame[4]) + hw + 1.6)
			var along := (slot - car.global_position).dot(f)
			return {"aim": slot + f * pit_look, "want": tspeed + clampf(along * 1.2, -6.0, 8.0)}
	return {}


func _end_pit(car: PoliceCar) -> void:
	roles.erase(car.get_instance_id())
	_pit_cool = pit_cooldown


func _note_boxed(target: Vehicle) -> void:
	if _boxed:
		return
	var near := 0
	for c in police.cruisers:
		if is_instance_valid(c) and (c as PoliceCar).mode != PoliceCar.Mode.PURSUE \
				and (c as PoliceCar).global_position.distance_to(target.global_position) < 7.5:
			near += 1
	if near >= 2:
		_boxed = true
		boxes += 1
		radio.say("boxed")


## The PIT's contact: a yaw kick and a shove at the car's rear quarter toward the side away from
## the cruiser, the car's rear tyres let go for a moment, and a bang. Public so the checks can
## call it on a staged pair.
func pit_assist(car: PoliceCar, target: Vehicle, side: float) -> void:
	var frame := car_frame(target)
	var f: Vector3 = frame[1]
	var r: Vector3 = frame[2]
	var hl: float = frame[3]
	var hw: float = frame[4]
	var m := target.mass
	# Inertia about the vertical of a uniform box: m (L^2 + W^2) / 12.
	var inertia := m * ((hl * 2.0) * (hl * 2.0) + (hw * 2.0) * (hw * 2.0)) / 12.0
	var arm := hl * 0.75
	# The cruiser on the right pushes the rear left: the nose swings right (yaw toward -side).
	var j := pit_spin * inertia / arm
	var push := -r * side
	target.hold_crash_watch(3)
	target.apply_impulse(push * j, -f * arm)
	target.apply_central_impulse(push * m * maxf(pit_shove - j / m, 0.0))
	for w in target.wheels:
		if is_instance_valid(w) and not w.use_as_steering:
			_slips.append([w, w.wheel_friction_slip, pit_slip_seconds])
			w.wheel_friction_slip *= pit_slip_share
	car.hold_crash_watch(3)
	car.apply_central_impulse(r * side * car.mass * 0.6)
	pits += 1
	Sfx.play("hit_metal", target.global_position - f * arm, 2.0, 0.8)
	radio.say("pit_done")


func _tick_slips(delta: float) -> void:
	for i in range(_slips.size() - 1, -1, -1):
		var s: Array = _slips[i]
		s[2] = float(s[2]) - delta
		var w: Variant = s[0]
		if not is_instance_valid(w):
			_slips.remove_at(i)
			continue
		if float(s[2]) <= 0.0:
			(w as VehicleWheel3D).wheel_friction_slip = float(s[1]) * ChaseFlatTyres.grip_of(w as VehicleWheel3D)
			_slips.remove_at(i)


# --- Doors and bounds -----------------------------------------------------------------------------

## Where an officer out of `car` should stand, with the player at `pp` (scene, at the officer's
## height): behind its own front door while the player is ahead of the car, then forward by bounds.
## Vector3.INF when the doors are no cover (player behind the car, no rig, a van). From
## PoliceOfficer._think().
static func door_cover(o: PoliceOfficer, car: PoliceCar, pp: Vector3) -> Vector3:
	var inst := instance()
	if inst == null or not enabled or car == null or car.heavy:
		return Vector3.INF
	return inst._door_cover(o, car, pp)


func _door_cover(o: PoliceOfficer, car: PoliceCar, pp: Vector3) -> Vector3:
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.05 else Vector3.FORWARD
	var to := pp - car.global_position
	to.y = 0.0
	var oid := o.get_instance_id()
	var b: Dictionary = _bounds.get(oid, {})
	# The door is cover against what is ahead of it (and a little to the side).
	if b.is_empty() and to.normalized().dot(fwd) < 0.1:
		return Vector3.INF
	var side := -1.0 if o.seat % 2 == 0 else 1.0
	if b.is_empty():
		var spot := door_spot(car, side)
		if spot == Vector3.INF:
			return Vector3.INF
		_open_door(car, side)
		b = {"phase": 0, "t": 0.0, "spot": spot, "side": side}
		_bounds[oid] = b
	var dt := 0.42
	b.t = float(b.t) + dt
	var here := o.global_position
	var d_player := Vector2(pp.x - here.x, pp.z - here.z).length()
	match int(b.phase):
		0:
			b.spot = door_spot(car, side) if door_spot(car, side) != Vector3.INF else b.spot
			if float(b.t) > advance_after and d_player > advance_stop and not _partner_moving(o, car):
				b.phase = 1
				b.t = 0.0
				var dir := Vector3(pp.x - here.x, 0.0, pp.z - here.z).normalized()
				var lat := dir.cross(Vector3.UP) * side * 2.5
				b.spot = here + dir * minf(bound_length, d_player - advance_stop * 0.8) + lat
				radio.say("advance")
		1:
			if here.distance_to(b.spot as Vector3) < 1.2 or float(b.t) > 4.0:
				b.phase = 2
				b.t = 0.0
		2:
			if float(b.t) > bound_hold and d_player > advance_stop and not _partner_moving(o, car):
				b.phase = 1
				b.t = 0.0
				var dir := Vector3(pp.x - here.x, 0.0, pp.z - here.z).normalized()
				var lat := dir.cross(Vector3.UP) * side * randf_range(-1.5, 2.5)
				b.spot = here + dir * minf(bound_length, d_player - advance_stop * 0.8) + lat
	var s: Vector3 = b.spot
	s.y = here.y
	return s


## True while another officer of the same car is mid-bound (one moves, one covers).
func _partner_moving(o: PoliceOfficer, car: PoliceCar) -> bool:
	for other in police.officers:
		if other == o or not is_instance_valid(other) or (other as PoliceOfficer).car != car:
			continue
		var b: Dictionary = _bounds.get((other as Node).get_instance_id(), {})
		if int(b.get("phase", 0)) == 1:
			return true
	return false


## Where to crouch behind `car`'s front door on `side` (-1 the car's left), scene position at the
## car's floor; Vector3.INF if the car has no door there. From the door rig's hinge when the car
## has one, else from the car's size.
static func door_spot(car: Vehicle, side: float) -> Vector3:
	var rig := CarInteriors.rig_of(car)
	if rig != null:
		var d := rig.door(side)
		if not d.is_empty() and not bool(d.lost):
			var hinge: Vector3 = (d.data as Dictionary).hinge
			var along := float((d.data as Dictionary).get("front", 0.0)) - float((d.data as Dictionary).get("rear", -1.0))
			# Behind the open door: out past the skin and back from the hinge (mesh -z is forward).
			var local := Vector3(hinge.x + side * 0.55, hinge.y, hinge.z + clampf(along, 0.8, 1.3) * 0.75)
			var p := rig.global_transform * local
			p.y = car.global_position.y - 0.42
			return p
	var dims := car._dims()
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.05 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	return car.global_position - Vector3.UP * 0.42 + right * side * (float(dims.get("width", 1.84)) * 0.5 + 0.55) \
			+ fwd * float(dims.get("length", 4.9)) * 0.08


func _open_door(car: PoliceCar, side: float) -> void:
	if not door_cars.has(car.get_instance_id()) and door_cars.size() >= max_door_cars:
		return
	door_cars[car.get_instance_id()] = car
	var inst := CarInteriors.instance()
	if inst != null:
		inst.activate(car)
	var rig := CarInteriors.rig_of(car)
	if rig != null:
		rig.jam(side, 1.0, 0.0)
		var d := rig.door(side)
		if not d.is_empty():
			d.chase_open = true


## The doors of cruisers whose crew is back in (or gone) shut again; the bounds of officers no
## longer about are forgotten.
func _tick_doors() -> void:
	for id in door_cars.keys():
		var c: Variant = door_cars[id]
		if not is_instance_valid(c):
			door_cars.erase(id)
			continue
		var car: PoliceCar = c
		var done := car.crew_aboard >= car.crew_alive or car.mode != PoliceCar.Mode.PARKED or car.driver != null \
				or not car.is_inside_tree() or police.stars <= 0
		if not done:
			continue
		var rig := CarInteriors.rig_of(car)
		if rig != null:
			for d: Dictionary in rig.doors:
				if bool(d.get("chase_open", false)):
					d.ajar = 0.0
					d.erase("chase_open")
		door_cars.erase(id)
	for oid in _bounds.keys():
		if not is_instance_id_valid(oid):
			_bounds.erase(oid)


## The cruisers CarInteriors must keep rigs on (their doors stand open). From CarInteriors._pick().
static func open_door_cars() -> Array:
	var inst := instance()
	if inst == null:
		return []
	var out := []
	for c in inst.door_cars.values():
		if is_instance_valid(c):
			out.append(c)
	return out


# --- Spikes ---------------------------------------------------------------------------------------

## A roadblock went up across the road at `mid` (true world XZ) on road (axis, index), the player
## coming at it travelling `travel` (+1 / -1 along the road). Lays a strip on the player's side.
static func roadblock(p: Police, mid: Vector2, axis: int, index: int, travel: float) -> ChaseSpikeStrip:
	var inst := instance()
	if inst == null or not enabled or p.plan == null:
		return null
	var along := Vector2(0.0, 1.0) if axis == CityPlan.AXIS_X else Vector2(1.0, 0.0)
	var at := mid - along * travel * inst.spike_ahead
	var width := p.plan.road_width(axis, index)
	var h := p.traffic._relief(at) if p.traffic else 0.0
	var strip := ChaseSpikeStrip.new()
	strip.length = maxf(width - 1.2, 3.0)
	# The strip's length runs across the road (its local +X).
	var yaw := 0.0 if axis == CityPlan.AXIS_X else PI * 0.5
	inst.add_strip(strip, WorldState.to_local(Vector3(at.x, h + CityChunk.ROAD_TOP, at.y)), yaw)
	inst.radio.say("spikes")
	return strip


## Puts `strip` down at `local` (scene) turned `yaw`; the oldest strip goes past four.
func add_strip(strip: ChaseSpikeStrip, local: Vector3, yaw: float) -> void:
	for i in range(strips.size() - 1, -1, -1):
		if not is_instance_valid(strips[i]):
			strips.remove_at(i)
	while strips.size() >= 4:
		var old: ChaseSpikeStrip = strips.pop_front()
		old.queue_free()
	strip.police = police
	police.add_child(strip)
	strip.global_transform = Transform3D(Basis(Vector3.UP, yaw), local)
	strip.deploy()
	strips.append(strip)


# --- Air ------------------------------------------------------------------------------------------

## Where the police helicopter's searchlight aims (TRUE world): the player `p` plus its hunt
## `wobble`, led ahead of a moving car and steadier at chase speed. From AirTraffic.
static func spot_target(p: Vector3, wobble: Vector3) -> Vector3:
	var inst := instance()
	if inst == null or not enabled or inst.police == null or not inst.police.player_driving():
		return p + wobble
	var v := inst.police.player_velocity()
	v.y = 0.0
	var calm := lerpf(1.0, inst.light_calm, clampf(v.length() / 20.0, 0.0, 1.0))
	return p + v * inst.light_lead + wobble * calm


## The radio from anywhere (Police's own events: shots fired, an officer down).
static func say(kind: String) -> void:
	var inst := instance()
	if inst != null and inst.radio != null:
		inst.radio.say(kind)
