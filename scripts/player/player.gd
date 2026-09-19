class_name Player
extends CharacterBody3D
## Overpowered third-person controller: run, sprint, super-high jump, double jump,
## strong air control, no fall damage. Every feel number is an @export below.

@export_group("Ground Movement")
## Top speed while walking (m/s).
@export var walk_speed: float = 12.0
## Top speed while holding sprint (m/s).
@export var sprint_speed: float = 22.0
## How fast we reach top speed on the ground (m/s^2). Higher = snappier.
@export var ground_acceleration: float = 90.0
## How fast we stop on the ground when no input (m/s^2).
@export var ground_deceleration: float = 70.0
## How quickly the body turns to face the move direction (higher = faster).
@export var turn_speed: float = 14.0

@export_group("Air Movement")
## Steering strength while airborne (m/s^2). High value = strong air control.
@export var air_acceleration: float = 45.0
## Drag while airborne with no input (m/s^2). Low value keeps momentum.
@export var air_deceleration: float = 6.0
## Terminal velocity (m/s).
@export var max_fall_speed: float = 90.0
## Gravity is multiplied by this while falling, so jumps feel less floaty.
@export var fall_gravity_multiplier: float = 1.6

@export_group("Jumping")
## Peak height of a full ground jump (meters). Gravity is derived from this.
@export var jump_height: float = 12.0
## Seconds to reach the peak of a full ground jump. Lower = snappier, higher = floatier.
@export var jump_time_to_apex: float = 0.65
## Peak height of the mid-air (double) jump (meters).
@export var double_jump_height: float = 9.0
## Number of extra jumps allowed while airborne.
@export var max_air_jumps: int = 1
## Releasing jump early multiplies upward velocity by this (1.0 = fixed-height jumps).
@export var jump_cut_multiplier: float = 0.45
## Grace period to still jump after walking off a ledge (seconds).
@export var coyote_time: float = 0.12
## Pressing jump this long before landing still triggers a jump (seconds).
@export var jump_buffer_time: float = 0.12

@export_group("Interaction")
## Shove applied to physics props you run into (impulse per second).
@export var push_force: float = 60.0
## Falling below this Y respawns the player at the start position.
@export var kill_y: float = -60.0

## Height (relative to takeoff) reached by the last jump. Shown on the debug HUD.
var last_jump_peak: float = 0.0
## Remaining mid-air jumps.
var air_jumps_left: int = 0

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _takeoff_y: float = 0.0
var _current_peak: float = 0.0
var _spawn_transform: Transform3D
var _sprinting: bool = false

@onready var visual: Node3D = $Visual
@onready var camera_rig: Node3D = $CameraRig


func _ready() -> void:
	_spawn_transform = global_transform
	air_jumps_left = max_air_jumps


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_takeoff_y = global_position.y
		_current_peak = 0.0
	_update_timers(delta, on_floor)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_sprinting = Input.is_action_pressed("sprint")
	var move_dir := _camera_relative_direction(input)

	_apply_gravity(delta, on_floor)
	_apply_horizontal(delta, on_floor, move_dir)
	_handle_jump(on_floor)

	move_and_slide()
	_push_props(delta)
	_track_jump_peak(on_floor, is_on_floor())
	_update_visual(delta, move_dir)

	if global_position.y < kill_y or Input.is_action_just_pressed("respawn"):
		respawn()


func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	air_jumps_left = max_air_jumps


func is_sprinting() -> bool:
	return _sprinting and is_on_floor() and velocity.length() > 1.0


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# --- Derived feel values -------------------------------------------------------

func rising_gravity() -> float:
	return 2.0 * jump_height / (jump_time_to_apex * jump_time_to_apex)


func jump_velocity() -> float:
	return 2.0 * jump_height / jump_time_to_apex


func double_jump_velocity() -> float:
	return sqrt(2.0 * rising_gravity() * double_jump_height)


# --- Internals -----------------------------------------------------------------

func _update_timers(delta: float, on_floor: bool) -> void:
	if on_floor:
		_coyote_timer = coyote_time
		air_jumps_left = max_air_jumps
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


func _camera_relative_direction(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var yaw := camera_rig.global_rotation.y
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	return dir.normalized() * minf(input.length(), 1.0)


func _apply_gravity(delta: float, on_floor: bool) -> void:
	if on_floor:
		return
	var g := rising_gravity()
	if velocity.y < 0.0:
		g *= fall_gravity_multiplier
	velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)


func _apply_horizontal(delta: float, on_floor: bool, move_dir: Vector3) -> void:
	var speed := sprint_speed if _sprinting else walk_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := move_dir * speed
	var rate: float
	if move_dir != Vector3.ZERO:
		rate = ground_acceleration if on_floor else air_acceleration
	else:
		rate = ground_deceleration if on_floor else air_deceleration
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _handle_jump(on_floor: bool) -> void:
	if _jump_buffer_timer > 0.0:
		if on_floor or _coyote_timer > 0.0:
			_do_jump(jump_velocity())
		elif air_jumps_left > 0:
			air_jumps_left -= 1
			_do_jump(double_jump_velocity())
	# Variable jump height: let go early to cut the jump short.
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut_multiplier


func _do_jump(vertical_speed: float) -> void:
	velocity.y = vertical_speed
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0


func _push_props(delta: float) -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body == null:
			continue
		var normal := collision.get_normal()
		if normal.y > 0.5:
			continue # Standing on it; don't stomp it into the ground.
		body.apply_impulse(-normal * push_force * delta, collision.get_position() - body.global_position)


## Measures how high the player got above the last grounded position (shown on the HUD).
func _track_jump_peak(was_on_floor: bool, now_on_floor: bool) -> void:
	if not now_on_floor:
		_current_peak = maxf(_current_peak, global_position.y - _takeoff_y)
	elif not was_on_floor:
		last_jump_peak = _current_peak


func _update_visual(delta: float, move_dir: Vector3) -> void:
	var facing := move_dir
	if facing == Vector3.ZERO:
		facing = Vector3(velocity.x, 0.0, velocity.z)
	if facing.length_squared() < 0.25:
		return
	var target_yaw := atan2(-facing.x, -facing.z)
	var t := 1.0 - exp(-turn_speed * delta)
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, t)
