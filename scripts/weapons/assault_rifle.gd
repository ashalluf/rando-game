class_name AssaultRifle
extends Weapon
## AK-47: full-auto hitscan rifle. Every bullet shoves whatever it hits.

@export_group("AK-47")
## Impulse delivered by one bullet.
@export var impact_force: float = 12.0
## Random cone around the crosshair (degrees).
@export var spread_deg: float = 1.4
## Max bullet reach (meters).
@export var bullet_range: float = 400.0
@export var tracer_color: Color = Color(1.0, 0.85, 0.4)

const WOOD := Color(0.55, 0.32, 0.14)
const STEEL := Color(0.22, 0.22, 0.24)


func _init() -> void:
	display_name = "AK-47"
	fire_rate = 10.0
	automatic = true
	kick_distance = 0.08
	camera_kick_deg = 0.35


func _build_model() -> void:
	# Receiver, barrel, gas tube, wooden handguard and stock, pistol grip, curved magazine.
	_box(Vector3(0.07, 0.09, 0.40), STEEL, Vector3(0.0, 0.0, 0.0), Vector3.ZERO, 0.6)
	_box(Vector3(0.06, 0.06, 0.28), WOOD, Vector3(0.0, 0.0, -0.32))
	_cylinder(0.012, 0.40, STEEL, Vector3(0.0, 0.015, -0.60), 0.7)
	_cylinder(0.014, 0.22, STEEL, Vector3(0.0, 0.05, -0.36), 0.7)
	_box(Vector3(0.05, 0.08, 0.30), WOOD, Vector3(0.0, -0.03, 0.34), Vector3(-6.0, 0.0, 0.0))
	_box(Vector3(0.045, 0.11, 0.05), WOOD, Vector3(0.0, -0.10, 0.10), Vector3(-18.0, 0.0, 0.0))
	_box(Vector3(0.045, 0.20, 0.06), STEEL, Vector3(0.0, -0.13, -0.08), Vector3(22.0, 0.0, 0.0), 0.5)
	_box(Vector3(0.02, 0.03, 0.02), STEEL, Vector3(0.0, 0.07, -0.78), Vector3.ZERO, 0.7)
	_make_muzzle(Vector3(0.0, 0.015, -0.82))


func _fire(aim: Dictionary) -> void:
	var dir: Vector3 = aim.direction
	if spread_deg > 0.0:
		var spread := deg_to_rad(spread_deg)
		dir = dir.rotated(dir.cross(Vector3.UP).normalized(), randf_range(-spread, spread))
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	fire_ray(aim.origin, dir)
	WeaponFX.flash(self, muzzle.global_position)


## Fires one hitscan bullet from `from` along `dir`. Public so tests can call it.
func fire_ray(from: Vector3, dir: Vector3) -> Dictionary:
	var to := from + dir * bullet_range
	var query := PhysicsRayQueryParameters3D.create(from, to, Player.AIM_MASK, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := to
	if hit:
		end = hit.position
		var body := hit.collider as RigidBody3D
		if body:
			body.sleeping = false
			body.apply_impulse(dir * impact_force, hit.position - body.global_position)
		WeaponFX.impact(self, hit.position)
	WeaponFX.tracer(self, muzzle.global_position, end, tracer_color)
	return hit
