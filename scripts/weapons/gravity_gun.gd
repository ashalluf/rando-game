class_name GravityGun
extends Weapon
## Grabs a physics prop, floats it in front of you, and hurls it. Fire: grab / launch. Alt fire: drop.

@export_group("Gravity Gun")
## How far away you can grab something (meters).
@export var grab_range: float = 16.0
## How far in front of the camera the held object floats (meters).
@export var hold_distance: float = 4.0
## Held objects never float lower than this above the player's feet (meters).
@export var min_hold_height: float = 1.2
## How aggressively the held object chases its hold point (higher = stiffer).
@export var hold_stiffness: float = 14.0
## Speed cap for the held object while carried (m/s).
@export var max_hold_speed: float = 60.0
## Launch speed when you fire while holding (m/s).
@export var launch_speed: float = 50.0
## Heaviest prop you can lift (kg).
@export var max_grab_mass: float = 5000.0
@export var beam_color: Color = Color(0.3, 0.9, 1.0)

const SHELL := Color(0.9, 0.5, 0.15)
const DARK := Color(0.15, 0.15, 0.16)

var _held: RigidBody3D
var _beam: MeshInstance3D
var _core: MeshInstance3D


func _init() -> void:
	display_name = "Gravity Gun"
	fire_rate = 4.0
	automatic = false
	kick_distance = 0.15
	camera_kick_deg = 0.0


func _build_model() -> void:
	_box(Vector3(0.14, 0.14, 0.45), SHELL, Vector3(0.0, 0.0, 0.0))
	_box(Vector3(0.05, 0.14, 0.06), DARK, Vector3(0.0, -0.12, 0.12), Vector3(15.0, 0.0, 0.0))
	for angle in [0.0, 120.0, 240.0]:
		var claw := _box(Vector3(0.03, 0.03, 0.22), DARK, Vector3.ZERO, Vector3.ZERO, 0.5)
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, 0.0, -0.3)
		pivot.rotation_degrees = Vector3(0.0, 0.0, angle)
		remove_child(claw)
		pivot.add_child(claw)
		claw.position = Vector3(0.0, 0.11, 0.0)
		claw.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
		add_child(pivot)
	_core = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	_core.mesh = sphere
	_core.material_override = WeaponFX.unshaded(beam_color)
	_core.position = Vector3(0.0, 0.0, -0.3)
	add_child(_core)
	_make_muzzle(Vector3(0.0, 0.0, -0.42))

	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.0
	cyl.radial_segments = 6
	_beam.mesh = cyl
	_beam.material_override = WeaponFX.unshaded(beam_color, 0.7)
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)


func is_holding() -> bool:
	return _held != null and is_instance_valid(_held)


func _fire(aim: Dictionary) -> void:
	if is_holding():
		launch()
		return
	var body := aim.collider as RigidBody3D
	if body and aim.origin.distance_to(aim.point) <= grab_range and body.mass <= max_grab_mass:
		grab(body)


func _alt_fire(_aim: Dictionary) -> void:
	drop()


func grab(body: RigidBody3D) -> void:
	_held = body
	_held.freeze = false
	_held.sleeping = false
	_held.angular_velocity = Vector3.ZERO
	player.notify_fired()


func drop() -> void:
	if is_holding():
		_held.linear_velocity = _held.linear_velocity.limit_length(5.0)
	_held = null
	_beam.visible = false


func launch() -> void:
	if not is_holding():
		return
	var aim := player.get_aim()
	_held.sleeping = false
	_held.linear_velocity = aim.direction * launch_speed
	_held.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	WeaponFX.tracer(self, muzzle.global_position, _held.global_position, beam_color, 0.1, 0.06)
	_held = null
	_beam.visible = false


func _update(delta: float) -> void:
	if not is_holding():
		_held = null
		_beam.visible = false
		return
	var aim := player.get_aim()
	var target: Vector3 = aim.origin + aim.direction * hold_distance
	target.y = maxf(target.y, player.global_position.y + min_hold_height)
	var to_target: Vector3 = target - _held.global_position
	if to_target.length() > grab_range * 1.5:
		drop() # Something yanked it away; let go.
		return
	_held.sleeping = false
	_held.linear_velocity = (to_target * hold_stiffness).limit_length(max_hold_speed)
	_held.angular_velocity = _held.angular_velocity.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	player.notify_fired()
	_draw_beam(muzzle.global_position, _held.global_position)


func _draw_beam(from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.05:
		_beam.visible = false
		return
	dir /= length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	_beam.visible = true
	_beam.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, -PI * 0.5), from + dir * length * 0.5)
	_beam.scale = Vector3(1.0, length, 1.0)


func on_unequip() -> void:
	drop()
	super()
