class_name ErrandCar
extends Node
## Hangs off a car while somebody gets into or out of it (StreetErrands): swings its driver's door
## (ErrandProps), seats or unseats the driver - the cabin trace and the lamps follow, since a car's
## lamps run while somebody is at the wheel (Vehicle.lights_running()) - and pulls a car somebody
## got into out of its kerb space into the traffic once its lane has room (StreetErrands.pull_out).
## One per car, made on demand, gone when the car is done with.

enum Mode { IDLE, IN, PULL, OUT, KEEP }

## Seconds after the door shuts before the driver pulls out; most it waits for room in the lane.
const PULL_DELAY := Vector2(1.4, 3.2)
const PULL_PATIENCE := 30.0
## How long a parked car waits for a delivery driver to come back before it gives up on them.
const KEEP_SECONDS := 180.0

var car: Vehicle
var door: Node3D
var mode: int = Mode.IDLE
var want_open: bool = false
var _open: float = 0.0
var _t: float = 0.0
var _delay: float = 2.0
## OUT: what the driver who gets out goes on to do (StreetErrands.spawn_driver).
var deliver: int = 0
var _driver: Node3D
var _tried: bool = false


## This car's ErrandCar, made now if it has none.
static func on(c: Vehicle) -> ErrandCar:
	var have := c.get_node_or_null("ErrandCar") as ErrandCar
	if have:
		return have
	var e := ErrandCar.new()
	e.name = "ErrandCar"
	e.car = c
	c.add_child(e)
	c.set_meta("errand", true)
	return e


func _ready() -> void:
	door = ErrandProps.door_node(car)
	_delay = randf_range(PULL_DELAY.x, PULL_DELAY.y)


## True once the door stands open far enough to get through.
func is_open() -> bool:
	return _open > 0.85


## Somebody has reached the door to get in: open it.
func request_open() -> void:
	want_open = true
	if mode == Mode.IDLE or mode == Mode.KEEP:
		mode = Mode.IN


## They are in: shut the door, take the wheel, and (`pull`) drive off once the lane has room.
func entered(pull: bool) -> void:
	_t = 0.0
	car._npc_driver = true
	car._occupant_seed = hash([car.get_instance_id(), Engine.get_physics_frames()])
	car._update_occupant(true)
	mode = Mode.PULL if pull else Mode.IDLE
	want_open = false


## The car has just parked (StreetErrands.park_here): its driver gets out. `what` is the errand
## they go on to (StreetErrands.DELIVER_*).
func arrive(what: int) -> void:
	deliver = what
	_tried = false
	mode = Mode.OUT
	_t = 0.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(car):
		queue_free()
		return
	# Shot, crashed, on fire, taken by the player: whatever was going on is off.
	if car.driver != null or car.is_wreck() or (car._damage != null and is_instance_valid(car._damage) and car._damage.state >= CarDamage.State.SMOKING):
		_finish()
		return
	_open = move_toward(_open, 1.0 if want_open else 0.0, delta / ErrandProps.DOOR_TIME)
	ErrandProps.swing(door, _open)
	_t += delta
	match mode:
		Mode.OUT:
			if _t > 0.8 and not _tried:
				want_open = true
			if not _tried and _open > 0.6:
				_tried = true
				_driver = StreetErrands.spawn_driver(car, deliver)
				if StreetErrands.debug:
					print("ERRAND driver out of %s: %s" % [car.name, _driver])
				# Out from behind the wheel: the cabin is empty and the lamps go off.
				car._npc_driver = false
				car._update_occupant(true)
				_t = 0.0
				if _driver == null:
					# Nobody to be them (no crowd room): the door shuts again on an empty car.
					want_open = false
					deliver = 0
			if _driver != null and want_open and (_t > 2.6 or not is_instance_valid(_driver) \
					or (_driver as Node3D).global_position.distance_to(door.global_position) > 2.2):
				want_open = false
			if _tried and not want_open and _open <= 0.0 and _t > 0.5:
				if deliver != 0 and _driver != null:
					mode = Mode.KEEP
					_t = 0.0
				else:
					_finish()
		Mode.PULL:
			if _open > 0.0 or _t < _delay:
				return
			if StreetErrands.pull_out(car):
				_finish()
			elif _t > _delay + PULL_PATIENCE:
				# Never got out of the space: the driver gives up and it stays parked, empty.
				car._npc_driver = false
				car._update_occupant(true)
				_finish()
		Mode.KEEP:
			if _t > KEEP_SECONDS:
				_finish()


func _finish() -> void:
	if is_instance_valid(door):
		door.queue_free()
	if is_instance_valid(car):
		car.remove_meta("errand")
	queue_free()
