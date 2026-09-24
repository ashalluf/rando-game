class_name Player
extends CharacterBody3D
## Overpowered third-person controller: run, unlimited boost (ground and air), super-high jump,
## double jump, strong air control, no fall damage. Every feel number is an @export below.

## Physics layers: 1 world, 2 player, 4 props, 8 npc (pedestrians).
const AIM_MASK := 1 | 4 | 8
const BLAST_MASK := 2 | 4 | 8

@export_group("Ground Movement")
## Top running speed (m/s).
@export var walk_speed: float = 12.0
## How fast we reach top speed on the ground (m/s^2). Higher = snappier.
@export var ground_acceleration: float = 90.0
## How fast we stop on the ground when no input (m/s^2).
@export var ground_deceleration: float = 70.0
## How quickly the body turns to face where it is going or aiming (higher = faster).
@export var turn_speed: float = 14.0

@export_group("Boost")
## Thrust while holding boost (m/s^2). Works on the ground and in the air.
@export var boost_acceleration: float = 75.0
## Speed cap while boosting (m/s).
@export var boost_max_speed: float = 45.0
## Gravity is multiplied by this while boosting in the air. Look up and boost to fly.
@export var boost_gravity_scale: float = 0.25
## After letting go of boost on the ground, you bleed back to run speed at this rate (m/s^2).
@export var boost_bleed_off: float = 25.0

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
## Owner's rule (2026-09-20): jump as many times in the air as you like. Turns max_air_jumps off.
@export var unlimited_air_jumps: bool = true
## Releasing jump early multiplies upward velocity by this (1.0 = fixed-height jumps).
@export var jump_cut_multiplier: float = 0.45
## Grace period to still jump after walking off a ledge (seconds).
@export var coyote_time: float = 0.12
## Pressing jump this long before landing still triggers a jump (seconds).
@export var jump_buffer_time: float = 0.12

@export_group("Interaction")
## Shove applied to physics props you run into (impulse per second).
@export var push_force: float = 60.0
## After firing, the body keeps facing the camera for this long (seconds).
@export var aim_hold_time: float = 1.5
## Below this Y you have fallen through the world: you get lifted back onto the ground in place.
## (Being under a hill is detected separately, whatever the height.)
@export var fall_through_y: float = -6.0
## Falling below this Y respawns the player at the start position.
@export var kill_y: float = -200.0
## How close a car has to be to get in (meters).
@export var enter_range: float = 4.5

@export_group("Look")
## Rigged character used as the player's body (one of Pedestrian.MODELS). Missing file: the
## orange capsule stays.
@export var avatar_model: String = "res://assets/models/pedestrian_d_anim.glb"
## Outfit look for the player's body (Pedestrian.character_material). Even numbers keep the
## model's own clothes; odd ones are the crowd's recoloured outfits.
@export var avatar_look: int = 0
## The hero's tracksuit colour: jacket and trousers in matching velour with white piping down
## the sleeves and legs (Pedestrian.tracksuit_material). Alpha 0 keeps `avatar_look` instead.
@export var avatar_tracksuit: Color = Color(0.20, 0.035, 0.05)

## Height (relative to takeoff) reached by the last jump. Shown on the debug HUD.
var last_jump_peak: float = 0.0
## Remaining mid-air jumps.
var air_jumps_left: int = 0
## The car being driven, or null.
var vehicle: Vehicle
## GTA-style aim: hold aim to lock onto the target nearest the crosshair (scripts/player/lock_on.gd).
var lock_on: LockOn

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _aim_timer: float = 0.0
var _takeoff_y: float = 0.0
var _current_peak: float = 0.0
var _spawn_transform: Transform3D
var _boosting: bool = false
var _boost_fx: CPUParticles3D
var _boost_sound: AudioStreamPlayer3D
## Physics frames to skip world queries after an origin shift (the broadphase lags a frame).
var _query_hold: int = 0
## True between enter_vehicle() and exit_vehicle(), even if the car vanished.
var _driving: bool = false

@onready var visual: Node3D = $Visual
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var weapon_manager: WeaponManager = $Visual/WeaponMount
## The animated body (Avatar), or null when the model is missing.
var avatar: Avatar


func _ready() -> void:
	_spawn_transform = global_transform
	air_jumps_left = max_air_jumps
	_build_avatar()
	_build_boost_fx()
	_boost_sound = Sfx.loop_player("boost_loop", -10.0)
	add_child(_boost_sound)
	lock_on = LockOn.new()
	lock_on.name = "LockOn"
	add_child(lock_on)


func _physics_process(delta: float) -> void:
	if _query_hold > 0:
		_query_hold -= 1
	if _driving and not is_instance_valid(vehicle):
		_vehicle_lost()
	if Input.is_action_just_pressed("interact"):
		if vehicle:
			exit_vehicle()
		else:
			_try_enter_vehicle()
	if vehicle:
		# Riding along: the car does the physics, we just sit in the seat.
		global_position = vehicle.seat_position()
		velocity = vehicle.linear_velocity
		_boosting = Input.is_action_pressed("boost")
		_boost_fx.emitting = false
		if vehicle.global_position.y < fall_through_y or _under_terrain(vehicle.global_position + Vector3.UP * 0.5):
			_lift_vehicle_onto_ground()
		if Input.is_action_just_pressed("respawn"):
			exit_vehicle()
			respawn()
		return
	if (global_position.y < fall_through_y and global_position.y > kill_y) or _under_terrain(global_position) or _under_city_ground():
		recover_from_fall()
	var on_floor := is_on_floor()
	if on_floor:
		_takeoff_y = global_position.y
		_current_peak = 0.0
	_update_timers(delta, on_floor)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_boosting = Input.is_action_pressed("boost")
	var move_dir := _camera_relative_direction(input)

	_apply_gravity(delta, on_floor)
	if _boosting:
		_apply_boost(delta, on_floor, move_dir)
	else:
		_apply_horizontal(delta, on_floor, move_dir)
	_handle_jump(on_floor)

	move_and_slide()
	_push_props(delta)
	_track_jump_peak(on_floor, is_on_floor())
	_update_visual(delta, move_dir)
	if avatar:
		avatar.drive(delta, horizontal_speed(), is_on_floor(), velocity.y, _boosting)
		var gun: Weapon = weapon_manager.current if weapon_manager and weapon_manager.visible else null
		avatar.hold_gun(gun, _aim_timer > 0.0 or (lock_on != null and lock_on.aiming), delta)
	_boost_fx.emitting = _boosting
	if _boosting and not _boost_sound.playing:
		_boost_sound.play()
	elif not _boosting and _boost_sound.playing:
		_boost_sound.stop()
	if is_on_floor() and not on_floor and velocity.length() > 1.0:
		Sfx.play("land", global_position, -6.0)

	if global_position.y < kill_y or Input.is_action_just_pressed("respawn"):
		respawn()


func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	air_jumps_left = max_air_jumps
	_ensure_ground_under(global_position)


## Fell through the world (ground not loaded yet) or ended up under a hill: load the ground and
## stand back on it, right here.
func recover_from_fall() -> void:
	global_position.y = _surface_height_at(global_position) + 0.3
	velocity = Vector3.ZERO


func _lift_vehicle_onto_ground() -> void:
	vehicle.global_position.y = _surface_height_at(vehicle.global_position) + 1.5
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO


## Real ground height under a spot (loads the chunk first). Test-room floor height otherwise.
func _surface_height_at(at: Vector3) -> float:
	var city := get_tree().get_first_node_in_group("city")
	if city and city.has_method("surface_height_at"):
		return city.surface_height_at(at)
	return 1.6


## Under the rolling city ground (the slab is above us): CityStreamer compares our height with
## the relief the city stands on. Owner's report 2026-09-20: "spawning underneath the ground".
func _under_city_ground() -> bool:
	if _query_hold > 0:
		return false
	var city := get_tree().get_first_node_in_group("city")
	if city and city.has_method("under_city_ground"):
		return city.under_city_ground(global_position)
	return false


## True when hill terrain is above this point: a ray straight up hits a body tagged "terrain".
## Roads and bridges are not tagged, so standing under the pier does not count.
func _under_terrain(from: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null or _query_hold > 0:
		return false
	# Only the terrain layer (CityChunk.TERRAIN_LAYER): pads, walls and roofs must not block it.
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.3, from + Vector3.UP * 400.0, 16))
	return not hit.is_empty() and hit.collider is Node and (hit.collider as Node).has_meta("terrain")


## First spot around the car where the player capsule does not overlap the world.
func _find_exit_spot(car: Vehicle) -> Vector3:
	var shape_node := $CollisionShape3D as CollisionShape3D
	var space := get_world_3d().direct_space_state
	var candidates := car.exit_candidates()
	if space == null or shape_node == null:
		return candidates[0]
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape_node.shape
	params.collision_mask = 1
	params.exclude = [car.get_rid()]
	for c in candidates:
		params.transform = Transform3D(Basis(), c + shape_node.position)
		if space.intersect_shape(params, 1).is_empty():
			return c
	return car.global_position + Vector3.UP * 3.0


func _ensure_ground_under(at: Vector3) -> void:
	var city := get_tree().get_first_node_in_group("city")
	if city and city.has_method("ensure_loaded_at"):
		city.ensure_loaded_at(at)


func is_boosting() -> bool:
	return _boosting


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _try_enter_vehicle() -> void:
	var best: Vehicle = null
	var best_d := enter_range
	for node in get_tree().get_nodes_in_group("vehicle"):
		var car := node as Vehicle
		if car == null or car.driver != null:
			continue
		if car.is_traffic():
			continue
		var d := car.global_position.distance_to(global_position) - maxf(car.enter_radius - enter_range, 0.0)
		if d < best_d:
			best_d = d
			best = car
	if best:
		enter_vehicle(best)


func enter_vehicle(car: Vehicle) -> void:
	# Parked cars live under the city root; this tag stops their chunk from freeing a car that
	# has been driven away from home.
	car.set_meta("driven", true)
	vehicle = car
	_driving = true
	car.driver = self
	car.freeze = false
	car.sleeping = false
	visible = false
	collision_layer = 0
	collision_mask = 0
	if weapon_manager:
		weapon_manager.visible = false
	if avatar:
		avatar.hold_gun(null, false, 0.0)
	global_position = car.seat_position()


func exit_vehicle() -> void:
	if vehicle == null:
		return
	var car := vehicle
	vehicle = null
	_driving = false
	car.driver = null
	visible = true
	collision_layer = 2
	collision_mask = 5
	if weapon_manager:
		weapon_manager.visible = true
	global_position = _find_exit_spot(car)
	velocity = car.linear_velocity * 0.5
	_ensure_ground_under(global_position)
	if _under_terrain(global_position):
		recover_from_fall()


func is_driving() -> bool:
	return _driving and is_instance_valid(vehicle)


## The car disappeared under us (freed by something): become a person again, on solid ground.
func _vehicle_lost() -> void:
	vehicle = null
	_driving = false
	visible = true
	collision_layer = 2
	collision_mask = 5
	if weapon_manager:
		weapon_manager.visible = true
	velocity = Vector3.ZERO
	recover_from_fall()


## The world was shifted by `offset` (origin re-centering); keep the spawn point in sync.
func shift_origin(offset: Vector3) -> void:
	_spawn_transform.origin -= offset
	_query_hold = 2


## Adds velocity from an outside force (explosions).
func launch(delta_velocity: Vector3) -> void:
	velocity += delta_velocity


## Weapons call this when they fire so the body turns to face the camera for a moment.
func notify_fired() -> void:
	_aim_timer = aim_hold_time


## While aiming the body keeps facing where the gun points.
func notify_aiming() -> void:
	_aim_timer = maxf(_aim_timer, 0.25)


## Where the crosshair points. Ray starts at the head pivot (or the shoulder, while aiming) so
## walls behind the camera are ignored. With a lock (LockOn) it goes straight at the target
## rather than at the screen centre, led for a projectile gun, so a shot fired while the camera
## is still swinging onto the target lands anyway.
func get_aim() -> Dictionary:
	var origin: Vector3 = camera_rig.aim_origin()
	var direction: Vector3 = -camera.global_basis.z
	var locked: Node3D = lock_on.target if lock_on and is_instance_valid(lock_on.target) else null
	if locked:
		var weapon: Node = weapon_manager.current if weapon_manager else null
		var lead := float(weapon.get("rocket_speed")) if weapon and weapon.get("rocket_speed") != null else 0.0
		direction = (lock_on.aim_point(lead) - origin).normalized()
	var to := origin + direction * 1000.0
	var query := PhysicsRayQueryParameters3D.create(origin, to, AIM_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return {
		"origin": origin,
		"direction": direction,
		"point": hit.position if hit else to,
		"normal": hit.normal if hit else -direction,
		"collider": hit.collider if hit else null,
		"target": locked,
	}


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
	_aim_timer = maxf(_aim_timer - delta, 0.0)


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
	if _boosting:
		g *= boost_gravity_scale
	elif velocity.y < 0.0:
		g *= fall_gravity_multiplier
	velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)


func _apply_horizontal(delta: float, on_floor: bool, move_dir: Vector3) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := move_dir * walk_speed
	var rate: float
	if move_dir != Vector3.ZERO:
		rate = ground_acceleration if on_floor else air_acceleration
		# Coming out of a boost: keep the momentum, bleed off gently instead of braking.
		if horizontal.length() > walk_speed + 0.5:
			rate = boost_bleed_off if on_floor else air_deceleration
	else:
		rate = ground_deceleration if on_floor else air_deceleration
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _apply_boost(delta: float, on_floor: bool, move_dir: Vector3) -> void:
	var yaw: float = camera_rig.global_rotation.y
	var pitch: float = camera_rig.rotation.x
	var flat_dir := move_dir if move_dir != Vector3.ZERO else Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var dir := flat_dir
	if not on_floor:
		# In the air the boost follows the camera pitch, so looking up and boosting is flight.
		dir = (flat_dir * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	velocity += dir * boost_acceleration * delta
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() > boost_max_speed:
		horizontal = horizontal.normalized() * boost_max_speed
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = clampf(velocity.y, -max_fall_speed, boost_max_speed)


func _handle_jump(on_floor: bool) -> void:
	if _jump_buffer_timer > 0.0:
		if on_floor or _coyote_timer > 0.0:
			_do_jump(jump_velocity())
		elif unlimited_air_jumps or air_jumps_left > 0:
			if not unlimited_air_jumps:
				air_jumps_left -= 1
			_do_jump(double_jump_velocity())
	# Variable jump height: let go early to cut the jump short.
	if Input.is_action_just_released("jump") and velocity.y > 0.0 and not _boosting:
		velocity.y *= jump_cut_multiplier


func _do_jump(vertical_speed: float) -> void:
	velocity.y = vertical_speed
	Sfx.play("jump", global_position, -8.0)
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
	var target_yaw: float
	if _aim_timer > 0.0:
		target_yaw = camera_rig.global_rotation.y
	else:
		var facing := move_dir
		if facing == Vector3.ZERO:
			facing = Vector3(velocity.x, 0.0, velocity.z)
		if facing.length_squared() < 0.25:
			return
		target_yaw = atan2(-facing.x, -facing.z)
	var t := 1.0 - exp(-turn_speed * delta)
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, t)


## Swaps the placeholder capsule for the rigged character when its file exists.
func _build_avatar() -> void:
	var body := Avatar.new()
	body.name = "Avatar"
	visual.add_child(body)
	if body.load_model(avatar_model, avatar_look, avatar_tracksuit):
		avatar = body
		if weapon_manager:
			avatar.setup_gun_hands(weapon_manager, visual, self)
		for placeholder in ["Body", "Visor"]:
			if visual.has_node(placeholder):
				visual.get_node(placeholder).visible = false
	else:
		body.queue_free()


func _build_boost_fx() -> void:
	_boost_fx = CPUParticles3D.new()
	_boost_fx.emitting = false
	_boost_fx.amount = 48
	_boost_fx.lifetime = 0.35
	_boost_fx.local_coords = false
	_boost_fx.direction = Vector3(0.0, 0.0, 1.0)
	_boost_fx.spread = 12.0
	_boost_fx.initial_velocity_min = 9.0
	_boost_fx.initial_velocity_max = 14.0
	_boost_fx.gravity = Vector3.ZERO
	_boost_fx.scale_amount_min = 0.4
	_boost_fx.scale_amount_max = 1.0
	var puff := SphereMesh.new()
	puff.radius = 0.16
	puff.height = 0.32
	puff.radial_segments = 6
	puff.rings = 3
	puff.material = WeaponFX.unshaded(Color(0.45, 0.9, 1.0))
	_boost_fx.mesh = puff
	_boost_fx.position = Vector3(0.0, 0.8, 0.45)
	visual.add_child(_boost_fx)
