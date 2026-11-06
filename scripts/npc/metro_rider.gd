class_name MetroRider
extends RailRider
## Someone in the Coral Line's underground station (MetroBuild puts them there, in the crowd
## cap): level 0 waits on the island platform (boarding and alighting as RailRider does), level 1
## drifts about the concourse's ticket halls. Both keep clear of what stands on their floor (the
## bank, the lift, the benches; the stair blocks, the gates' line) by where they pick to go, and
## stand on their own floor's height. They pass through the city's ground box for good: they never
## leave the station (MetroStation.sink()'s exception, added before their first step).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## MetroStation.frame() of the station.
var frame: Dictionary = {}
## 0 the platform, 1 the concourse, 2 riding an escalator of the bank (MetroCrowd, wave 7).
var level := 0
## On an escalator: +1 riding down (u rising, onto the island), -1 riding up; where along it (u).
var esc_dir := 0
var esc_u := 0.0
## Riders stand still on the step and move with it (m/s along the incline, ~0.5 like a real one).
const ESC_SPEED := 0.5


## Puts this rider on the bank's down (dir +1) or up (dir -1) escalator at `u`, standing.
func ride(dir: int, u: float) -> void:
	level = 2
	esc_dir = dir
	esc_u = u
	state = 0
	var p := _esc_point(u)
	position = p
	if _visual:
		_face_esc()


## The escalator lanes: the down one at v 0, the up one at v 1.45 (MetroBuild._bank()).
func _esc_v() -> float:
	return 0.0 if esc_dir > 0 else 1.45


## The step's tread under `u` (station frame), as a TRUE world point.
func _esc_point(u: float) -> Vector3:
	if frame.is_empty():
		return position
	var top := MetroStation.CONC_FLOOR
	var foot := float(frame.plat)
	var ua := -MetroStation.BANK_U + 0.3 + 0.85
	var ub := MetroStation.BANK_U - 0.3 - 0.85
	var h := lerpf(top, foot, clampf((u - ua) / (ub - ua), 0.0, 1.0)) + 0.06
	return MetroStation.to_world(frame, Vector3(u, h, _esc_v()))


func _face_esc() -> void:
	var d: Vector2 = (frame.d as Vector2) * float(esc_dir)
	_visual.rotation.y = atan2(-d.x, -d.y)


## Only the island boards: someone on the concourse (or on an escalator) sent to a door walked
## to it at the concourse's height, five metres over the platform (wave 7).
func board(door: Vector2) -> void:
	if level != 0 and MetroCrowd.enabled:
		return
	super(door)


## Alighting here means off toward the bank's up escalator, and up it (not gone at its foot).
func alight(exit: Vector2) -> void:
	if not frame.is_empty() and MetroCrowd.enabled:
		var w := MetroStation.to_world(frame, Vector3(MetroStation.BANK_U + 0.4, 0.0, 1.45))
		exit = Vector2(w.x, w.z)
	super(exit)


func _physics_process(delta: float) -> void:
	if state == 2 and level == 0 and MetroCrowd.enabled and not frame.is_empty() and not _down \
			and Vector2(position.x, position.z).distance_to(_goal) < 1.0:
		ride(-1, MetroStation.BANK_U - 0.3)
	if level != 2 or _down or frame.is_empty():
		super(delta)
		return
	# Standing on a moving step: the gait's idle (a pause that never runs out), placed every tick.
	_pause_left = 60.0
	_speed = 0.0
	velocity = Vector3.ZERO
	super(delta)
	if _down or not is_inside_tree():
		return
	# Along the incline at ESC_SPEED: 30 degrees, so a little faster than the plan's u.
	esc_u += float(esc_dir) * ESC_SPEED * 0.86 * delta
	position = _esc_point(esc_u)
	velocity = Vector3.ZERO
	_face_esc()
	var off := MetroStation.BANK_U + 0.6
	if esc_dir > 0 and esc_u > off:
		# Off at the foot: onto the island, a spot to wait at.
		level = 0
		_pause_left = 0.0
		_go_to(_random_ring_point(3.0))
	elif esc_dir < 0 and esc_u < -off:
		# Off at the top: up through the paid zone and away (the concourse's halls).
		level = 1
		_pause_left = 0.0
		_go_to(_random_ring_point(3.0))


func _ready() -> void:
	super()
	var city := get_tree().get_first_node_in_group("city")
	var ground := city.get_node_or_null("GroundBody") as PhysicsBody3D if city else null
	if ground:
		PhysicsServer3D.body_add_collision_exception(get_rid(), ground.get_rid())


func _ground_y(x: float, z: float, fallback: float) -> float:
	if frame.is_empty():
		return super(x, z, fallback)
	if level == 2:
		return _esc_point(esc_u).y
	if level == 1:
		return float(frame.y0) + MetroStation.CONC_FLOOR + 0.1
	return float(frame.y0) + float(frame.plat) + 0.1


func _random_ring_point(_sidewalk: float) -> Vector2:
	if state != 0 or frame.is_empty():
		return super(_sidewalk)
	var u := 0.0
	var v := 0.0
	if level == 0:
		# Either end of the island, clear of the bank (and the lift beside it) and the benches.
		u = _rng.randf_range(12.0, 29.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		v = _rng.randf_range(1.0, 2.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
		if MetroCrowd.enabled:
			# Wave 7: from just past the bank's foot (and the lift beside it) to the island's ends,
			# toward the edges where people wait for a train. The same rolls, spread wider.
			u = (7.0 + (absf(u) - 12.0) * (22.0 / 17.0)) * signf(u)
			v = (1.3 + (absf(v) - 1.0) * (1.4 / 1.6)) * signf(v)
	else:
		# The unpaid halls by the ticket machines, or the paid zone round the bank.
		if _rng.randf() < 0.7:
			u = _rng.randf_range(14.0, 18.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
			v = _rng.randf_range(2.2, 5.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
		else:
			u = _rng.randf_range(-10.0, 7.0)
			v = _rng.randf_range(2.9, 5.8) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var w := MetroStation.to_world(frame, Vector3(u, 0.0, v))
	return Vector2(w.x, w.z)
