extends Node3D
## Third-person follow camera. Sits on the player, yaw/pitch from mouse or right stick,
## SpringArm3D keeps the camera out of walls. Feel numbers are @exports below.

@export_group("Look")
## Radians per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0025
## Radians per second at full right-stick deflection.
@export var gamepad_look_speed: float = 2.6
@export var invert_y: bool = false
## Lowest the camera can look (negative = looking down at the player).
@export_range(-89.0, 0.0) var min_pitch_deg: float = -80.0
## Highest the camera can look up.
@export_range(0.0, 89.0) var max_pitch_deg: float = 55.0
@export var start_pitch_deg: float = -15.0

@export_group("Camera")
## Distance from the pivot to the camera (meters). The spring arm shortens it near walls.
@export var camera_distance: float = 6.5
@export var camera_fov: float = 75.0
## Extra field of view while sprinting, for a sense of speed.
@export var sprint_fov_boost: float = 10.0
@export var fov_lerp_speed: float = 6.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	spring_arm.spring_length = camera_distance
	camera.fov = camera_fov
	_pitch = deg_to_rad(start_pitch_deg)
	var body := get_parent() as CollisionObject3D
	if body:
		spring_arm.add_excluded_object(body.get_rid())
	_apply_rotation()
	# Browsers only allow grabbing the mouse after a click, so on web we wait for one.
	if not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch -= motion.relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
		_apply_rotation()
	elif event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		_yaw -= look.x * gamepad_look_speed * delta
		_pitch -= look.y * gamepad_look_speed * delta * (-1.0 if invert_y else 1.0)
		_apply_rotation()

	var target_fov := camera_fov
	var player := get_parent() as Player
	if player and player.is_sprinting():
		target_fov += sprint_fov_boost
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-fov_lerp_speed * delta))


func _apply_rotation() -> void:
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	_yaw = wrapf(_yaw, -PI, PI)
	rotation = Vector3(_pitch, _yaw, 0.0)
