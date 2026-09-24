class_name RocketLauncher
extends Weapon
## Shoulder-fired rocket launcher. Big radial shove, and it launches you too if you are close.

@export_group("Rocket Launcher")
@export var rocket_speed: float = 70.0
## Blast radius (meters).
@export var explosion_radius: float = 9.0
## Velocity change for props at the center of the blast (m/s).
@export var explosion_launch_speed: float = 30.0
## Velocity change for the player at the center of the blast (m/s). Rocket jumps!
@export var player_launch_speed: float = 35.0
## Seconds before a rocket that hits nothing explodes anyway.
@export var rocket_lifetime: float = 6.0

## An original RPG-pattern launcher with a warhead loaded in its muzzle, modelled and
## texture-baked in Blender by tools/make_weapons.py. The box model below is the fallback.
const MODEL_PATH := "res://assets/models/weapon_rocket_launcher.glb"
## The warhead's tip, where the rocket leaves, for a model without its own Muzzle node.
const MODEL_MUZZLE := Vector3(0.0, 0.08, -0.80)

const TUBE := Color(0.2, 0.32, 0.2)
const DARK := Color(0.15, 0.15, 0.16)

## The loaded warhead: hidden when it flies, back once the launcher has reloaded.
var _warhead: Node3D


func _init() -> void:
	display_name = "Rocket Launcher"
	fire_rate = 1.5
	automatic = false
	kick_distance = 0.3
	camera_kick_deg = 2.5
	# Shoulder-fired: the rear heat shield rests on top of the shoulder, the venturi sticking out
	# behind. The right wrist sits behind the trigger grip, the left behind the vertical fore
	# grip with the palm turned in against it.
	grip_right = Vector3(0.025, -0.035, 0.065)
	grip_left = Vector3(-0.02, -0.03, -0.18)
	grip_left_fingers = Vector3(0.25, -0.3, -0.9)
	grip_left_palm = Vector3(1.0, 0.0, 0.0)
	hold_hip = Vector3(-0.08, -0.26, -0.22)
	hold_aim = Vector3(-0.06, 0.03, -0.16)
	hold_hip_rot = Vector3(-15.0, 15.0, 0.0)


func _build_model() -> void:
	var model := _load_model(MODEL_PATH)
	if model == null:
		_build_box_model()
		return
	_warhead = model.get_node_or_null("Warhead") as Node3D
	var mark := model.get_node_or_null("Muzzle") as Node3D
	_make_muzzle(mark.position if mark else MODEL_MUZZLE)


## Instances a generated gun model as a child; null when the file is missing.
func _load_model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	return model


## The old primitive launcher, kept as the fallback.
func _build_box_model() -> void:
	_cylinder(0.11, 1.1, TUBE, Vector3(0.0, 0.08, -0.15))
	_cylinder(0.13, 0.12, DARK, Vector3(0.0, 0.08, -0.72), 0.4)
	_cylinder(0.13, 0.12, DARK, Vector3(0.0, 0.08, 0.40), 0.4)
	_box(Vector3(0.05, 0.14, 0.06), DARK, Vector3(0.0, -0.08, 0.0), Vector3(15.0, 0.0, 0.0))
	_box(Vector3(0.05, 0.12, 0.05), DARK, Vector3(0.0, -0.06, -0.3), Vector3(15.0, 0.0, 0.0))
	_box(Vector3(0.04, 0.06, 0.16), DARK, Vector3(0.0, 0.22, -0.2))
	_make_muzzle(Vector3(0.0, 0.08, -0.75))


func _fire(aim: Dictionary) -> void:
	var from := muzzle.global_position
	var dir: Vector3 = (aim.point - from).normalized()
	if dir.dot(aim.direction) < 0.5:
		dir = aim.direction # Aim point is behind or beside the muzzle; just fire straight.
	launch_rocket(from, dir)
	WeaponFX.flash(self, from, Color(1.0, 0.6, 0.2), 0.5, 0.08)
	Sfx.play("rocket", from)
	if _warhead:
		_warhead.visible = false


func _update(_delta: float) -> void:
	# Reloaded: the next warhead is in the tube.
	if _warhead and not _warhead.visible and _cooldown <= 0.0:
		_warhead.visible = true


## Spawns a rocket. Public so tests can call it.
func launch_rocket(from: Vector3, dir: Vector3) -> Rocket:
	var rocket := Rocket.new()
	rocket.speed = rocket_speed
	rocket.lifetime = rocket_lifetime
	rocket.explosion_radius = explosion_radius
	rocket.explosion_launch_speed = explosion_launch_speed
	rocket.player_launch_speed = player_launch_speed
	rocket.direction = dir
	rocket.exclude = [player.get_rid()]
	WeaponFX.fx_parent(self).add_child(rocket)
	rocket.global_position = from
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	rocket.global_basis = Basis.looking_at(dir, up)
	return rocket
