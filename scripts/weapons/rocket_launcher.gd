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

const TUBE := Color(0.2, 0.32, 0.2)
const DARK := Color(0.15, 0.15, 0.16)


func _init() -> void:
	display_name = "Rocket Launcher"
	fire_rate = 1.5
	automatic = false
	kick_distance = 0.3
	camera_kick_deg = 2.5


func _build_model() -> void:
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
