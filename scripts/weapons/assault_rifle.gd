class_name AssaultRifle
extends Weapon
## AK-47: full-auto hitscan rifle. Every bullet shoves whatever it hits.

@export_group("AK-47")
## Impulse delivered by one bullet.
@export var impact_force: float = 12.0
## Random cone around the crosshair (degrees).
@export var spread_deg: float = 1.4
## Damage per bullet to breakable street props.
@export var bullet_damage: float = 10.0
## Max bullet reach (meters).
@export var bullet_range: float = 400.0
@export var tracer_color: Color = Color(1.0, 0.85, 0.4)
## How much one round bleeds (WeaponFX.blood's strength: spray, splats, pool, stain).
@export var blood_strength: float = 1.0

## The rifle: an AKM modelled, unwrapped and texture-baked in Blender by tools/make_weapons.py
## (rebuild it there, never by hand). The box model further down only stands in when the file
## is missing.
const MODEL_PATH := "res://assets/models/weapon_ak47.glb"
## The muzzle, for a model without its own Muzzle node.
const MODEL_MUZZLE := Vector3(0.0, 0.0, -0.55)

# Walnut, not orange: the old 0.55 / 0.32 / 0.14 blew out to bright orange in sunlight, and the
# rifle is on screen in every single frame of this game.
const WOOD := Color(0.31, 0.18, 0.09)
const WOOD_FORE := Color(0.35, 0.21, 0.10)
## Blued steel, and the duller parkerized grey of the sight blocks and gas block.
const STEEL := Color(0.105, 0.105, 0.115)
const PARK := Color(0.155, 0.150, 0.145)
## Polymer grip, and the plum bakelite magazine.
const POLY := Color(0.10, 0.10, 0.105)
const MAG := Color(0.30, 0.16, 0.09)


func _init() -> void:
	display_name = "AK-47"
	fire_rate = 10.0
	automatic = true
	kick_distance = 0.08
	camera_kick_deg = 0.35
	# The hands on the modelled rifle: the right wrist just behind the raked bakelite grip, the
	# left under the rear of the lower handguard, palm up (as far forward as these arms reach).
	grip_right = Vector3(0.025, -0.06, 0.10)
	grip_left = Vector3(-0.03, -0.075, -0.26)


func _build_model() -> void:
	var model := _load_model(MODEL_PATH)
	if model == null:
		_build_box_model()
		return
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


## The old primitive rifle, kept as the fallback.
func _build_box_model() -> void:
	# An AK-47 is 880 mm long. The old model spanned 1.31 m of boxes, which is why it read as a
	# plank with a pipe on it. Everything below is laid out in real proportions, butt at +0.34,
	# muzzle at -0.575, forward is -Z.

	# Receiver and top cover.
	_box(Vector3(0.062, 0.082, 0.300), STEEL, Vector3(0.0, 0.0, -0.010), Vector3.ZERO, 0.85, 0.38)
	_box(Vector3(0.058, 0.028, 0.270), STEEL, Vector3(0.0, 0.052, -0.020), Vector3.ZERO, 0.85, 0.36)
	# Rear sight block and leaf.
	_box(Vector3(0.030, 0.016, 0.046), PARK, Vector3(0.0, 0.072, 0.070), Vector3.ZERO, 0.5, 0.6)

	# Wooden furniture: the lower handguard you hold, the upper one over the gas tube.
	_box(Vector3(0.054, 0.052, 0.190), WOOD_FORE, Vector3(0.0, -0.004, -0.245), Vector3.ZERO, 0.0, 0.55)
	_box(Vector3(0.048, 0.030, 0.155), WOOD_FORE, Vector3(0.0, 0.046, -0.245), Vector3.ZERO, 0.0, 0.55)
	_cylinder(0.010, 0.175, PARK, Vector3(0.0, 0.049, -0.245), 0.5, -1.0, 0.55)

	# Barrel, gas block, front sight block and post, muzzle brake.
	_cylinder(0.0090, 0.320, STEEL, Vector3(0.0, 0.004, -0.360), 0.85, -1.0, 0.35)
	_box(Vector3(0.034, 0.046, 0.042), PARK, Vector3(0.0, 0.030, -0.345), Vector3.ZERO, 0.5, 0.6)
	_box(Vector3(0.030, 0.050, 0.034), PARK, Vector3(0.0, 0.034, -0.505), Vector3.ZERO, 0.5, 0.6)
	# Along Y, not Z: the post stands up out of its block.
	_cylinder(0.0026, 0.024, STEEL, Vector3(0.0, 0.062, -0.505), 0.85, -1.0, 0.4, Vector3.ZERO)
	_cylinder(0.0125, 0.055, STEEL, Vector3(0.0, 0.004, -0.545), 0.85, -1.0, 0.42)

	# The magazine, in three segments so it curves the way the real one does.
	_box(Vector3(0.028, 0.078, 0.076), MAG, Vector3(0.0, -0.058, -0.082), Vector3(-8.0, 0.0, 0.0), 0.0, 0.5)
	_box(Vector3(0.027, 0.072, 0.070), MAG, Vector3(0.0, -0.118, -0.106), Vector3(-20.0, 0.0, 0.0), 0.0, 0.5)
	_box(Vector3(0.026, 0.052, 0.062), MAG, Vector3(0.0, -0.172, -0.144), Vector3(-32.0, 0.0, 0.0), 0.0, 0.5)

	# Grip, trigger guard and trigger.
	_box(Vector3(0.034, 0.105, 0.048), POLY, Vector3(0.0, -0.086, 0.086), Vector3(16.0, 0.0, 0.0), 0.0, 0.72)
	_box(Vector3(0.030, 0.011, 0.078), STEEL, Vector3(0.0, -0.050, 0.030), Vector3.ZERO, 0.7, 0.45)
	_box(Vector3(0.008, 0.028, 0.010), STEEL, Vector3(0.0, -0.037, 0.036), Vector3(-10.0, 0.0, 0.0), 0.7, 0.4)

	# Stock: the body, the comb you put your cheek on, and a steel butt plate.
	_box(Vector3(0.044, 0.058, 0.255), WOOD, Vector3(0.0, -0.034, 0.232), Vector3(-5.0, 0.0, 0.0), 0.0, 0.55)
	_box(Vector3(0.042, 0.030, 0.130), WOOD, Vector3(0.0, 0.010, 0.178), Vector3(-3.0, 0.0, 0.0), 0.0, 0.55)
	_box(Vector3(0.046, 0.076, 0.012), PARK, Vector3(0.0, -0.056, 0.360), Vector3(-5.0, 0.0, 0.0), 0.6, 0.55)

	# The two things that read as "AK" from the side: the safety lever down the right of the
	# receiver, and the charging handle sticking out of it.
	_box(Vector3(0.008, 0.078, 0.013), STEEL, Vector3(0.035, 0.012, 0.018), Vector3.ZERO, 0.8, 0.4)
	_box(Vector3(0.013, 0.013, 0.048), STEEL, Vector3(0.037, 0.040, -0.062), Vector3.ZERO, 0.8, 0.4)

	_make_muzzle(Vector3(0.0, 0.004, -0.578))


func _fire(aim: Dictionary) -> void:
	var dir: Vector3 = aim.direction
	if spread_deg > 0.0:
		var spread := deg_to_rad(spread_deg)
		dir = dir.rotated(dir.cross(Vector3.UP).normalized(), randf_range(-spread, spread))
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	fire_ray(aim.origin, dir)
	WeaponFX.flash(self, muzzle.global_position)
	Sfx.play("shot", muzzle.global_position, -4.0)


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
		elif hit.collider.has_method("take_hit"):
			hit.collider.take_hit(hit.get("shape", -1), bullet_damage, dir)
		# A person goes down bleeding - in, out the far side, onto the wall behind and the ground -
		# and a body already down bleeds again where it is hit (WeaponFX.bullet_wound).
		WeaponFX.bullet_wound(self, hit, dir, blood_strength, dir * 14.0 + Vector3.UP * 5.0)
		if hit.collider is Vehicle:
			(hit.collider as Vehicle).drop_out_of_traffic(dir * impact_force)
		WeaponFX.impact(self, hit.position)
	WeaponFX.tracer(self, muzzle.global_position, end, tracer_color)
	return hit
