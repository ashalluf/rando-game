extends Node3D
## Third-person follow camera. Sits on the player, yaw/pitch from mouse or right stick,
## SpringArm3D keeps the camera out of walls. Feel numbers are @exports below.

@export_group("Focus")
## Depth-of-field far distance with the camera at ground level (metres).
@export var dof_ground_distance: float = 260.0
## Extra far distance per metre of altitude. At 150 m up this puts the focus beyond the far
## side of the basin, which is what an aerial shot needs.
@export var dof_altitude_gain: float = 14.0
## How quickly the focus follows a change in altitude. Slow on purpose: a focus that snaps as
## you clear a rooftop is more distracting than the blur it is fixing.
@export var dof_lerp_speed: float = 1.6

@export_group("Look")
## Radians per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0025
## Radians per second at full right-stick deflection.
@export var gamepad_look_speed: float = 2.6
@export var invert_y: bool = false
## Lowest the camera can look (negative = looking down at the player).
@export_range(-89.0, 0.0) var min_pitch_deg: float = -80.0
## Highest the camera can look up.
@export_range(0.0, 89.0) var max_pitch_deg: float = 75.0
@export var start_pitch_deg: float = -15.0

@export_group("Camera")
## Distance from the pivot to the camera (meters). The spring arm shortens it near walls.
@export var camera_distance: float = 6.5
@export var camera_fov: float = 75.0
## Extra field of view while boosting, for a sense of speed.
@export var boost_fov_boost: float = 15.0
@export var fov_lerp_speed: float = 6.0
## How fast recoil kicks settle (higher = faster).
@export var kick_recover_speed: float = 10.0
## How fast an explosion shake settles (higher = faster).
@export var shake_recover_speed: float = 3.2
## Angular size of a full-strength shake (radians).
@export var shake_strength: float = 0.05

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var _yaw: float = 0.0
var _pitch: float = 0.0
var _kick_pitch: float = 0.0
var _shake: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO


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
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		_yaw -= look.x * gamepad_look_speed * delta
		_pitch -= look.y * gamepad_look_speed * delta * (-1.0 if invert_y else 1.0)
	if _kick_pitch != 0.0:
		_kick_pitch = lerpf(_kick_pitch, 0.0, 1.0 - exp(-kick_recover_speed * delta))
	if _shake > 0.001:
		_shake = lerpf(_shake, 0.0, 1.0 - exp(-shake_recover_speed * delta))
		var amp := _shake * _shake * shake_strength
		_shake_offset = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0) * 0.6) * amp
	elif _shake_offset != Vector3.ZERO:
		_shake = 0.0
		_shake_offset = Vector3.ZERO
	_apply_rotation()

	var target_fov := camera_fov
	var player := get_parent() as Player
	if player and player.is_boosting():
		target_fov += boost_fov_boost
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-fov_lerp_speed * delta))
	_update_focus(delta)


## Pushes the depth-of-field focus out with altitude. On the ground a far blur past
## `dof_ground_distance` reads as a lens and gives the street depth. In the air it is simply
## wrong: the player flies, and from a few hundred metres up EVERYTHING in frame is past that
## distance, so the whole city goes soft and an aerial shot looks like a watercolour. The focus
## therefore opens out in proportion to how high the camera is above the ground under it, which
## is the one number that distinguishes the two cases.
func _update_focus(delta: float) -> void:
	var attrs := camera.attributes as CameraAttributesPractical
	if attrs == null or not attrs.dof_blur_far_enabled:
		return
	var ground := 0.0
	var city := get_tree().get_first_node_in_group("city")
	if city and city.has_method("ground_height_at"):
		ground = city.ground_height_at(camera.global_position)
	var altitude := maxf(camera.global_position.y - ground, 0.0)
	var want := dof_ground_distance + altitude * dof_altitude_gain
	attrs.dof_blur_far_distance = lerpf(attrs.dof_blur_far_distance, want, 1.0 - exp(-dof_lerp_speed * delta))
	attrs.dof_blur_far_transition = attrs.dof_blur_far_distance


## Rattles the view. `amount` is 0..1; explosions call this scaled by distance.
func shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


## Recoil: nudges the view up by `degrees` with a little random sideways wobble.
func kick(degrees: float) -> void:
	if degrees == 0.0:
		return
	_kick_pitch += deg_to_rad(degrees)
	_yaw += deg_to_rad(randf_range(-degrees, degrees) * 0.3)


## Sets the view direction directly (degrees). Used by the spawn override.
func set_look(yaw_deg: float, pitch_deg: float) -> void:
	_yaw = deg_to_rad(yaw_deg)
	_pitch = deg_to_rad(pitch_deg)
	_kick_pitch = 0.0
	_apply_rotation()


## Points the camera from the pivot at a world position. Used by tests and later by cutscenes.
func look_at_point(point: Vector3) -> void:
	var dir := (point - global_position).normalized()
	_yaw = atan2(-dir.x, -dir.z)
	_pitch = asin(clampf(dir.y, -1.0, 1.0))
	_kick_pitch = 0.0
	_apply_rotation()


func _apply_rotation() -> void:
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	_yaw = wrapf(_yaw, -PI, PI)
	rotation = Vector3(_pitch + _kick_pitch + _shake_offset.x, _yaw + _shake_offset.y, _shake_offset.z)
