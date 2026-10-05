class_name YardDog
extends Dog
## A dog in a yard (DogYard places it): behind a front garden's low wall or pickets where the
## street can see it, or in a back yard behind the lot-line fences. It pads about its patch, lies
## up, sniffs the lawn; when the player comes within `alert_range` it runs to the fence where he
## is nearest, stands square to him and barks in bursts, following him along the fence until he
## is gone. A gun or a blast sends it running to the far corner with its tail tucked (barking
## from there); hit, it yelps and cowers there. It never leaves its yard (the fences are code, not
## physics, so the yard is a rectangle it keeps to), and it is never a crime.
##
## A child of its chunk, which frees it; placed in the chunk's space (the plan's world space).

@export var alert_range: float = 22.0
@export var calm_range: float = 30.0
## Seconds of barking in a burst and of quiet between bursts while the player is there.
@export var burst: Vector2 = Vector2(1.2, 3.0)
@export var quiet: Vector2 = Vector2(1.0, 3.5)
@export var trot_speed: float = 1.6
@export var run_speed: float = 4.2

## The yard in the lot's frame: origin, the u (along the fence) and v (in from it) axes, the patch
## [u0, v0, u1, v1] and whether the fence the dog barks over is the v = 0 edge (a front garden).
var frame_o := Vector2.ZERO
var frame_u := Vector2.RIGHT
var frame_v := Vector2.DOWN
var patch := Rect2()
var fence_front: bool = true
var chunk: CityChunk

enum State { IDLE, WALK, ALERT, COWER }
var state: int = State.IDLE
var _target := Vector2.ZERO
var _state_left: float = 0.0
var _burst_left: float = 0.0
var _quiet_left: float = 0.0
var _idle_kind: int = 0
var _player: Node3D
var _scan: float = 0.0


func _ready() -> void:
	_make_body()
	_target = patch.get_center()
	_place(_target)
	_yaw = atan2(-frame_v.x, -frame_v.y) + PI
	rotation.y = _yaw
	_state_left = _rng.randf_range(2.0, 8.0)


## A point of the patch (u, v) in the chunk's space, on the yard's ground.
func _world(uv: Vector2) -> Vector3:
	var p := frame_o + frame_u * uv.x + frame_v * uv.y
	var y := (chunk.ground_y(p.x, p.y) + YardFill.LIFT) if chunk else 0.0
	return Vector3(p.x, y, p.y)


func _to_uv(p: Vector3) -> Vector2:
	var d := Vector2(p.x, p.z) - frame_o
	return Vector2(d.dot(frame_u), d.dot(frame_v))


func _place(uv: Vector2) -> void:
	position = _world(uv)


func _on_hit() -> void:
	# A yard dog can't bolt down the street: it cowers in the far corner.
	fleeing = false
	_cower(Vector3.INF)


func _on_startle(at: Vector3) -> void:
	_cower(at)


func _cower(at: Vector3) -> void:
	state = State.COWER
	_state_left = _rng.randf_range(6.0, 10.0)
	# The corner of the patch farthest from the threat (or from the fence).
	var from := Vector2(patch.get_center().x, patch.position.y if fence_front else patch.end.y)
	if chunk and at != Vector3.INF:
		from = _to_uv(chunk.to_local(at))
	var best := patch.get_center()
	var best_d := -1.0
	for c in [patch.position, Vector2(patch.end.x, patch.position.y), patch.end, Vector2(patch.position.x, patch.end.y)]:
		var d := (c as Vector2).distance_to(from)
		if d > best_d:
			best_d = d
			best = c
	_target = best.lerp(patch.get_center(), 0.15)
	bark(_rng.randi_range(2, 4))


func _physics_process(delta: float) -> void:
	if rig == null or chunk == null:
		return
	if _air:
		# Thrown by a hit: land, then cower (Dog._tick_flee handles the arc).
		_vel.y -= 18.0 * delta
		global_position += _vel * delta
		var uv := _to_uv(position)
		uv = Vector2(clampf(uv.x, patch.position.x, patch.end.x), clampf(uv.y, patch.position.y, patch.end.y))
		var w := _world(uv)
		position.x = w.x
		position.z = w.z
		if position.y <= w.y and _vel.y < 0.0:
			position.y = w.y
			_air = false
		rig.speed = 0.0
		_advance_rig(delta)
		return
	# Far from the camera nothing moves (the rig hides itself past its draw range).
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.3
		_player = get_tree().get_first_node_in_group("player") as Node3D
		_think()
	_state_left -= delta
	var uv_now := _to_uv(position)
	var to := _target - uv_now
	var dist := to.length()
	var spd := 0.0
	match state:
		State.IDLE:
			if _state_left <= 0.0:
				state = State.WALK
				_target = Vector2(_rng.randf_range(patch.position.x, patch.end.x), _rng.randf_range(patch.position.y, patch.end.y))
		State.WALK:
			spd = trot_speed * (0.45 if not is_small() else 0.7)
			if dist < 0.15:
				state = State.IDLE
				_state_left = _rng.randf_range(3.0, 10.0)
				_idle_kind = _rng.randi() % 3
		State.ALERT:
			spd = run_speed if dist > 1.0 else (trot_speed if dist > 0.15 else 0.0)
			_tick_bursts(delta)
		State.COWER:
			spd = run_speed if dist > 0.2 else 0.0
			if _state_left <= 0.0:
				state = State.IDLE
				_state_left = _rng.randf_range(2.0, 5.0)
	spd *= sqrt(height() / 0.5)
	var step := minf(spd * delta, dist)
	var face := _yaw
	if step > 1e-4:
		var dir := to / maxf(dist, 1e-5)
		var p := uv_now + dir * step
		_place(p)
		var wd := frame_u * dir.x + frame_v * dir.y
		face = atan2(-wd.x, -wd.y)
	elif state == State.ALERT and _player:
		var d := global_position.direction_to(_player.global_position)
		face = atan2(-d.x, -d.z)
	var prev := _yaw
	_yaw = lerp_angle(_yaw, face, 1.0 - exp(-7.0 * delta))
	_turn = wrapf(_yaw - prev, -PI, PI) / maxf(delta, 1e-4)
	rotation.y = _yaw
	rig.speed = step / maxf(delta, 1e-4)
	rig.turn = _turn
	rig.fear = 1.0 if state == State.COWER else 0.0
	rig.sit = 1.0 if state == State.IDLE and _idle_kind == 1 else 0.0
	rig.sniff = 1.0 if state == State.IDLE and _idle_kind == 2 else 0.0
	rig.wag = 0.25 if state != State.ALERT else 0.05
	rig.pant = 0.4 if state == State.IDLE else 0.0
	rig.look_at = rig.to_local(_player.global_position + Vector3.UP * 1.3) if state == State.ALERT and _player else Vector3.INF
	_advance_rig(delta)


## Notices the player (and forgets him): every few tenths of a second.
func _think() -> void:
	if _player == null or state == State.COWER:
		return
	var d := _player.global_position.distance_to(global_position)
	if state != State.ALERT and d < alert_range:
		state = State.ALERT
		_burst_left = _rng.randf_range(burst.x, burst.y)
		_quiet_left = 0.0
		bark(1)
	elif state == State.ALERT and d > calm_range:
		state = State.IDLE
		_state_left = _rng.randf_range(2.0, 6.0)
		_idle_kind = 0
	if state == State.ALERT:
		# The fence point nearest him, a little in from the fence.
		var uv := _to_uv(chunk.to_local(_player.global_position))
		# The dog faces him over the fence: its middle stands its own half length plus its head
		# back from the patch's edge, so the nose stays this side of the pickets.
		var b := DogMesh.breed(breed)
		var reach: float = (float(b.l) * 0.5 + float(b.hl) * 0.75) * size_scale - DogYard.INSET + 0.18
		var fv := patch.position.y + maxf(reach, 0.0) if fence_front else patch.end.y - maxf(reach, 0.0)
		_target = Vector2(clampf(uv.x, patch.position.x, patch.end.x), clampf(fv, patch.position.y, patch.end.y))


func _tick_bursts(dt: float) -> void:
	if _burst_left > 0.0:
		_burst_left -= dt
		if _bark_left <= 0:
			bark(1)
		if _burst_left <= 0.0:
			_quiet_left = _rng.randf_range(quiet.x, quiet.y)
	else:
		_quiet_left -= dt
		if _quiet_left <= 0.0:
			_burst_left = _rng.randf_range(burst.x, burst.y)
