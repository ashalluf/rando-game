class_name PanicSkid
extends Node3D
## The hard stop of a panicking traffic car (CarPanic, STOP phase): the tyres squeal (Sfx `skid`,
## a loop pitched and levelled by the speed) and lay locked-wheel marks behind all four wheels in
## DrivingFX's mark ring, while the car is still going over CarPanic.SKID_SPEED. A child of the
## car; it frees itself once the car is slow, out of its panic, pooled or wrecked. Traffic cars
## are kinematic and have no wheels for DrivingFX to read, so this is the stop's only rubber.

var car: Vehicle
var strength: float = 0.8
var _voice: AudioStreamPlayer3D
var _wheels: Array = []
var _states: Array = []
var _age: float = 0.0


## Starts the squeal and the marks on `c` (once per stop). Null when the car already has one.
static func on(c: Vehicle, decel: float) -> PanicSkid:
	if c.get_node_or_null("PanicSkid") != null:
		return null
	var s := PanicSkid.new()
	s.name = "PanicSkid"
	s.car = c
	s.strength = clampf(0.45 + (decel - CarPanic.SKID_DECEL) * 0.25, 0.45, 0.95)
	c.add_child(s)
	return s


func _ready() -> void:
	var d: Dictionary = car._dims()
	var half_track := float(d.get("track", 1.6)) * 0.5
	var wz := float(d.get("wheel_z", 1.4))
	var front := float(d.get("wheel_front", wz))
	var rear := float(d.get("wheel_rear", wz))
	var road := float(d.get("road", -0.2))
	for x: float in [-half_track, half_track]:
		_wheels.append(Vector3(x, road, -front))
		_wheels.append(Vector3(x, road, rear))
		_states.append({})
		_states.append({})
	var sfx := get_node_or_null("/root/Sfx")
	if sfx and sfx.has("skid"):
		_voice = sfx.loop_player("skid", -4.0)
		add_child(_voice)
		_voice.play()


func _physics_process(delta: float) -> void:
	step(delta)


## One tick (CarPanic.advance_shot() calls it by hand for stills).
func step(delta: float) -> void:
	if is_queued_for_deletion():
		return
	_age += delta
	var v := 0.0
	var on := is_instance_valid(car) and not car.is_wreck() and car.is_traffic() and car.traffic.has("cp")
	if on:
		v = float(car.traffic.get("v", 0.0))
	if not on or v < 1.2 or _age > 5.0:
		queue_free()
		return
	if _voice:
		var level := clampf(v / 12.0, 0.0, 1.0)
		_voice.volume_db = lerpf(-24.0, -3.0, level)
		_voice.pitch_scale = lerpf(0.85, 1.12, level)
	if v < CarPanic.SKID_SPEED * 0.35:
		return
	var fx := DrivingFX.instance()
	if fx == null or not is_instance_valid(fx) or not fx.is_inside_tree():
		return
	var tm := CarPanic.traffic_of(get_tree())
	var xf := car.global_transform
	# The marks fade in as the tyres lock and out as the car stops.
	var s := strength * clampf((v - CarPanic.SKID_SPEED * 0.35) / 3.0, 0.25, 1.0)
	for i in _wheels.size():
		var at: Vector3 = xf * (_wheels[i] as Vector3)
		# On the road itself, not where the diving body puts the tyre (a few cm under it).
		if tm:
			var w := WorldState.to_world(at)
			w.y = tm._relief(Vector2(w.x, w.z)) + CityChunk.ROAD_TOP + 0.025
			at = WorldState.to_local(w)
		fx._lay(_states[i], at, Vector3.UP, Vector3.ZERO, 0.21, fx.rubber_tint, s)

