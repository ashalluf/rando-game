class_name VehicleAudio
extends RefCounted
## The newer vehicles' own sounds (the city's audio pass): a bus at a stop and the light rail car.
##
## The bus (BigVehicles.BusFittings.set_doors() calls bus_doors()): the door chime, the pneumatic
## doors swinging, and the kneel's air release as the body drops to the kerb; closing, the chime
## and the doors again. Its diesel idle is the street's traffic voice (Ambience gives the nearest
## bus or truck the diesel loop instead of the tyre roll), so a bus that stands at a stop is heard
## idling without a player of its own.
##
## The light rail car (LightRailTrain.setup() adds a TrainVoice): the traction inverters' whine,
## pitched with the train's speed and loudest while it accelerates or brakes, the hum and crackle
## of the pantograph on the wire, and the door chime as the doors open and again before they
## close. Its wheels on the rails stay the train's own rolling loop.

## Doors opening at a stop (true) or closing (false), on the bus `car`.
static func bus_doors(car: Node3D, opening: bool) -> void:
	if car == null or not car.is_inside_tree():
		return
	var at := car.global_position + car.global_basis.x * 1.3 + Vector3.UP * 1.6
	Sfx.play("bus_chime", at, -9.0, 1.0)
	Sfx.play("bus_door", at, -6.0 if opening else -7.0, randf_range(0.95, 1.05))
	if opening:
		Sfx.play("bus_kneel", car.global_position + Vector3.UP * 0.5, -5.0, randf_range(0.85, 0.95))


## The light rail car's motors, wire and door chime. Rides a section of the car (the sections are
## what move; the train node does not) and reads `train`, the LightRailTrain.
class TrainVoice extends Node3D:
	## Level of the whine at full effort and of the wire's hum, dB.
	const MOTOR_DB := -9.0
	const HUM_DB := -20.0
	## The whine's pitch at a standstill and at 25 m/s.
	const PITCH := Vector2(0.45, 1.7)
	## Heard out to this far, metres.
	const REACH := 90.0

	var train: Node3D
	var _motor: AudioStreamPlayer3D
	var _hum: AudioStreamPlayer3D
	var _motor_db := 0.0
	var _hum_db := 0.0
	var _last_speed := 0.0
	var _effort := 0.0
	var _doors_were := 0.0
	var _closing_rung := false

	func _ready() -> void:
		if train == null:
			train = get_parent() as Node3D
		_motor = Sfx.loop_player("rail_motor", MOTOR_DB)
		_motor_db = _motor.volume_db
		_motor.max_distance = REACH
		_motor.unit_size = 12.0
		_motor.position = Vector3(0.0, 0.6, 0.0)
		add_child(_motor)
		_hum = Sfx.loop_player("rail_hum", HUM_DB)
		_hum_db = _hum.volume_db
		_hum.max_distance = REACH * 0.5
		_hum.unit_size = 6.0
		_hum.position = Vector3(0.0, 4.2, 0.0)
		add_child(_hum)

	func _process(delta: float) -> void:
		if train == null or not is_instance_valid(train) or not train.is_visible_in_tree():
			_stop()
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null or cam.global_position.distance_to(global_position) > REACH:
			_stop()
			return
		var speed := float(train.get("speed"))
		var accel := (speed - _last_speed) / maxf(delta, 0.001)
		_last_speed = speed
		# The inverters work hardest pulling away and braking; coasting they are a faint whine.
		var want := clampf(absf(accel) / 1.2, 0.0, 1.0)
		_effort = lerpf(_effort, want, 1.0 - exp(-delta * 3.0))
		var move := clampf(speed / 3.0, 0.0, 1.0)
		_motor.pitch_scale = lerpf(PITCH.x, PITCH.y, clampf(speed / 25.0, 0.0, 1.0))
		_motor.volume_db = _motor_db + linear_to_db(maxf(move * (0.3 + 0.7 * _effort), 0.001))
		_hum.volume_db = _hum_db + linear_to_db(0.5 + 0.5 * move)
		if not _hum.playing:
			_hum.play(randf() * 1.5)
		if move > 0.01 and not _motor.playing:
			_motor.play(randf() * 1.5)
		elif move <= 0.01 and _motor.playing:
			_motor.stop()
		var doors := float(train.get("doors_open"))
		if doors > 0.0 and _doors_were <= 0.0:
			Sfx.play("rail_chime", global_position + Vector3.UP * 2.0, -6.0, 1.0)
			_closing_rung = false
		# The chime again as the doors start to close.
		if doors > 0.0 and doors < _doors_were and not _closing_rung:
			_closing_rung = true
			Sfx.play("rail_chime", global_position + Vector3.UP * 2.0, -6.0, 0.97)
		_doors_were = doors

	func _stop() -> void:
		if _motor and _motor.playing:
			_motor.stop()
		if _hum and _hum.playing:
			_hum.stop()
