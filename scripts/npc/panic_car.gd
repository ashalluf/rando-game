class_name PanicCar
extends Node
## Hangs off a traffic car whose driver ran from it (CarPanic ABANDON): swings the driver's door
## open (ErrandProps, as StreetErrands' parking drivers do), puts the driver out at it
## (CarPanic.spawn_driver) and empties the cabin (CarCabin follows Vehicle._npc_driver: the
## traced driver is gone and the lamps go dark), then leaves the door standing open. Once the
## driver is off the road it sends them on fleeing round their block. Gone - and the door with
## it - when the car is pooled, wrecked or the player gets in (the door shuts first).

var car: Vehicle
var door: Node3D
var threat: Vector2
var driver: Pedestrian
var _open: float = 0.0
var _want_open: bool = false
var _t: float = 0.0
var _delay: float = 0.6
var _out: bool = false
var _fled: bool = false


## Starts the abandoning on `c` (once), the threat at true world `at`.
static func on(c: Vehicle, at: Vector2) -> PanicCar:
	var have := c.get_node_or_null("PanicCar") as PanicCar
	if have:
		return have
	var p := PanicCar.new()
	p.name = "PanicCar"
	p.car = c
	p.threat = at
	var h := absi(hash([c.get_instance_id(), "panic_door"]))
	p._delay = lerpf(CarPanic.DOOR_DELAY.x, CarPanic.DOOR_DELAY.y, float(h % 101) / 100.0)
	c.add_child(p)
	return p


func _ready() -> void:
	door = ErrandProps.door_node(car)


## True once the door stands open (the checks read it).
func is_open() -> bool:
	return _open > 0.85


func _physics_process(delta: float) -> void:
	if not is_instance_valid(car):
		queue_free()
		return
	if car.is_wreck() or (car.is_traffic() and not car.traffic.has("cp")):
		_finish()
		return
	if car.driver != null:
		# The player got in: the door shuts behind them.
		_want_open = false
		_open = move_toward(_open, 0.0, delta / ErrandProps.DOOR_TIME)
		ErrandProps.swing(door, _open)
		if _open <= 0.0:
			_finish()
		return
	_t += delta
	if not _out and _t > _delay:
		_want_open = true
	_open = move_toward(_open, 1.0 if _want_open else 0.0, delta / ErrandProps.DOOR_TIME)
	ErrandProps.swing(door, _open)
	if not _out and _open > 0.55:
		_out = true
		driver = CarPanic.spawn_driver(car, threat)
		car._npc_driver = false
		car._update_occupant(true)
	if driver != null and not _fled:
		if not is_instance_valid(driver) or driver._down:
			_fled = true
		elif driver.errand.is_empty():
			_fled = true
			if driver._panic_left > 0.0:
				driver._go_to(driver._flee_point())


func _finish() -> void:
	if is_instance_valid(door):
		door.queue_free()
	queue_free()
