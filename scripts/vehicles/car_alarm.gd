class_name CarAlarm
extends Node
## A parked car's alarm: a blast nearby (Explosion.blast() -> `blast()`) or a hit on the car
## itself (Vehicle.take_hit() -> `on_hit()`) sets it off. It sounds one of the real recordings
## (Sfx `car_alarm`: a pulsing siren, a multi-tone warble cycle, a horn honking in time), flashes
## the hazards (Vehicle.alarm_left, which Vehicle._tick_lights() turns into the hazard state) and
## stops on its own after `alarm_seconds`. Only empty parked cars carry one (`armed()`), and only
## `alarm_share` of them, rolled from the car (a hash, never an rng). A child node of the car,
## made when it goes off and freed when it stops, so a quiet car costs nothing.

## How long an alarm sounds (seconds, min..max), rolled per car.
static var alarm_seconds: Vector2 = Vector2(24.0, 46.0)
## Share of parked cars that have an alarm at all.
static var alarm_share: float = 0.72
## Alarms sounding at once; past it a new one is not started (the city is loud enough).
static var max_alarms: int = 7
## A blast sets off the alarms within this many blast radii of its centre (and at least
## `blast_min_reach` metres): the shock carries well past what it throws.
static var blast_reach: float = 4.0
static var blast_min_reach: float = 28.0
## A round or a pellet in a parked car sets its alarm off this often (a blast or a crash always).
static var shot_odds: float = 0.85
## Loudness of the recording at the car (dB, before Sfx's normalisation).
static var volume_db: float = 2.0
## Slowest the alarm starts after a blast (seconds): a street of alarms going off one after
## another rather than in one chord.
static var stagger: float = 1.6
## Off: no car alarms at all (the A/B, `CAR_ALARMS=0` in the environment).
static var enabled: bool = OS.get_environment("CAR_ALARMS") != "0"

static var _live: Array = []

var car: Vehicle
var _left: float = 0.0
var _delay: float = 0.0
var _player: AudioStreamPlayer3D


## Does this car have an alarm that can go off now: empty, parked, not a wreck, not police or an
## emergency unit, not an aircraft, and one of the `alarm_share` that have one at all.
static func armed(v: Vehicle) -> bool:
	if not enabled or v == null or not is_instance_valid(v) or not v.is_inside_tree():
		return false
	if v.driver != null or v.is_traffic() or v._npc_driver or v.is_wreck() or v.has_meta("wreck"):
		return false
	if v is Aircraft or v.is_in_group("police_car") or v.is_in_group("emergency_unit"):
		return false
	return _roll(v, 1) < alarm_share


## A hash of the car's identity, 0..1 (`salt` picks an independent roll).
static func _roll(v: Vehicle, salt: int) -> float:
	return float(hash([v.get_instance_id(), salt, "car_alarm"]) & 0xffff) / 65535.0


## Every armed parked car within reach of a blast at `at` (scene space) of `radius`.
static func blast(tree: SceneTree, at: Vector3, radius: float) -> int:
	if not enabled or tree == null:
		return 0
	var reach := maxf(radius * blast_reach, blast_min_reach)
	var n := 0
	for node in tree.get_nodes_in_group("vehicle"):
		var v := node as Vehicle
		if v == null:
			continue
		var d := v.global_position.distance_to(at)
		if d > reach:
			continue
		# Nearer cars first: the delay grows with distance, plus a little of the car's own.
		if trigger(v, clampf(d / reach, 0.0, 1.0) * stagger + _roll(v, 2) * 0.4):
			n += 1
	return n


## Vehicle.take_hit()'s hook: a round, a blast, a crash or a prop against a parked car.
static func on_hit(v: Vehicle, kind: int, _damage: float) -> void:
	if not enabled:
		return
	if (kind == Vehicle.HIT_BULLET or kind == Vehicle.HIT_PELLET) and randf() > shot_odds:
		return
	trigger(v, 0.15)


## Sets the car's alarm off after `delay` seconds (or keeps one already going a while longer).
## False when it has none, or too many are going already.
static func trigger(v: Vehicle, delay: float = 0.0) -> bool:
	if not armed(v):
		return false
	var existing := v.get_node_or_null("CarAlarm") as CarAlarm
	if existing:
		existing._left = maxf(existing._left, alarm_seconds.x)
		return true
	_live = _live.filter(func(a): return is_instance_valid(a))
	if _live.size() >= max_alarms:
		return false
	var a := CarAlarm.new()
	a.name = "CarAlarm"
	a.car = v
	a._delay = delay
	a._left = lerpf(alarm_seconds.x, alarm_seconds.y, _roll(v, 3))
	v.add_child(a)
	_live.append(a)
	return true


## How many alarms are going (tests, the HUD).
static func sounding() -> int:
	_live = _live.filter(func(a): return is_instance_valid(a))
	return _live.size()


func _process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or car.driver != null or car.is_wreck():
		_stop()
		return
	if _delay > 0.0:
		_delay -= delta
		if _delay <= 0.0:
			_start()
		return
	_left -= delta
	car.alarm_left = maxf(_left, 0.0)
	if _left <= 0.0:
		_stop()


func _start() -> void:
	car.alarm_left = _left
	car._refresh_lights()
	var take: Array = Sfx.take("car_alarm")
	if take.is_empty():
		return
	_player = AudioStreamPlayer3D.new()
	_player.name = "AlarmSound"
	_player.stream = take[0]
	_player.volume_db = volume_db + float(take[1])
	_player.unit_size = 9.0
	_player.max_distance = 260.0
	_player.bus = Sfx.bus_for("car_alarm")
	# Every car's speaker is a little different.
	_player.pitch_scale = lerpf(0.94, 1.06, _roll(car, 4))
	add_child(_player)
	_player.play(randf() * 3.0)


func _stop() -> void:
	if car and is_instance_valid(car):
		car.alarm_left = 0.0
		car._refresh_lights()
	_live.erase(self)
	queue_free()
	set_process(false)
