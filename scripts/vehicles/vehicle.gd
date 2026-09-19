class_name Vehicle
extends VehicleBody3D
## Arcade car: bouncy, grippy, overpowered, with a nitro. Built from boxes in code with a body
## type, a paint color and an optional add-on. Press interact next to it to drive.

enum BodyType { SEDAN, PICKUP, VAN, SPORTS }
enum Addon { NONE, ROOF_RACK, SPOILER, LIGHT_BAR }

const BODY_NAMES := ["Sedan", "Pickup", "Van", "Sports"]
const PAINTS := [
	Color(0.85, 0.15, 0.12), Color(0.15, 0.35, 0.75), Color(0.92, 0.92, 0.9), Color(0.12, 0.12, 0.14),
	Color(0.95, 0.75, 0.15), Color(0.2, 0.6, 0.35), Color(0.7, 0.7, 0.72), Color(0.9, 0.45, 0.15),
	Color(0.55, 0.2, 0.6), Color(0.35, 0.7, 0.8),
]

@export_group("Handling")
## Engine force at full throttle (N). Big number = silly acceleration.
@export var engine_power: float = 7000.0
## Engine force multiplier while holding boost.
@export var nitro_multiplier: float = 2.2
@export var reverse_power: float = 3500.0
@export var brake_force: float = 80.0
@export var handbrake_force: float = 40.0
## Max steering angle (radians).
@export var max_steer: float = 0.5
## How fast the wheels turn toward the stick (higher = twitchier).
@export var steer_speed: float = 8.0
## Steering shrinks at speed so the car does not spin out: full steer below this speed (m/s).
@export var steer_full_speed: float = 12.0
@export var steer_min_factor: float = 0.35
## Top speed (m/s); engine force fades to zero here.
@export var top_speed: float = 55.0
## Torque applied in the air from the stick (flips and rolls, Rocket League style).
@export var air_torque: float = 9000.0
## Self-righting torque when upside down and slow.
@export var upright_torque: float = 25000.0

@export_group("Suspension")
## Soft springs plus a low center of mass keep the car flat and planted. Stiffer bounces.
@export var suspension_stiffness: float = 60.0
@export var suspension_rest_length: float = 0.35
## Must stay smaller than the rest length or the wheels sink into the road.
@export var suspension_travel: float = 0.2
@export var suspension_max_force: float = 50000.0
@export var damping_compression: float = 0.8
@export var damping_relaxation: float = 1.2
## Tire grip. Godot's default is 10.5; lower drifts more.
@export var wheel_grip: float = 10.5
## How much the tires transfer roll to the body (0 = never rolls over from cornering).
@export var wheel_roll_influence: float = 0.1
## Center of mass height above the wheel axles (meters). Low = stable, no wheelies.
@export var center_of_mass_height: float = 0.1

var body_type: BodyType = BodyType.SEDAN
var addon: Addon = Addon.NONE
var paint: Color = Color(0.85, 0.15, 0.12)
## The Player driving, or null.
var driver: Node3D
## Traffic state while driven by the TrafficManager (empty otherwise).
var traffic: Dictionary = {}
var traffic_speed: float = 0.0
var wheels: Array[VehicleWheel3D] = []
var _wheel_slots: Array = []
var _wheel_visuals: Array[Node3D] = []
var _seat: Node3D
var _exit_side: float = 1.0
var _steer_target: float = 0.0
var _engine_sound: AudioStreamPlayer3D


func setup(type: BodyType, color: Color, extra: Addon) -> void:
	body_type = type
	paint = color
	addon = extra


func _ready() -> void:
	add_to_group("vehicle")
	add_to_group("physics_prop")
	set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)
	collision_layer = 4
	collision_mask = 7
	mass = 1200.0
	angular_damp = 0.5
	linear_damp = 0.05
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, center_of_mass_height, 0.0)
	_build()


func display_name() -> String:
	return BODY_NAMES[body_type]


func seat_position() -> Vector3:
	return _seat.global_position if _seat else global_position + Vector3.UP


func exit_position() -> Vector3:
	return global_position + global_basis.x * (2.6 * _exit_side) + Vector3.UP * 0.5


func is_traffic() -> bool:
	return not traffic.is_empty()


## Something hit a traffic car hard: hand it over to physics.
func drop_out_of_traffic(impulse: Vector3 = Vector3.ZERO) -> void:
	if not is_traffic():
		return
	var v := -global_basis.z * traffic_speed
	traffic = {}
	traffic_speed = 0.0
	for visual in _wheel_visuals:
		visual.queue_free()
	_wheel_visuals.clear()
	_add_real_wheels()
	freeze = false
	sleeping = false
	linear_velocity = v
	if impulse != Vector3.ZERO:
		apply_central_impulse(impulse)


func is_airborne() -> bool:
	for w in wheels:
		if w.is_in_contact():
			return false
	return true


func _physics_process(delta: float) -> void:
	if driver == null:
		engine_force = 0.0
		brake = 2.0
		steering = lerpf(steering, 0.0, 1.0 - exp(-steer_speed * delta))
		if _engine_sound and _engine_sound.playing:
			_engine_sound.stop()
		return
	if _engine_sound == null:
		_engine_sound = Sfx.loop_player("engine_loop", -8.0)
		add_child(_engine_sound)
	if not _engine_sound.playing:
		_engine_sound.play()
	_engine_sound.pitch_scale = 0.8 + clampf(linear_velocity.length() / top_speed, 0.0, 1.0) * 1.4
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var throttle := -input.y # forward is negative y on the stick
	var speed := linear_velocity.dot(-global_basis.z)
	var boost := nitro_multiplier if Input.is_action_pressed("boost") else 1.0
	var fade := clampf(1.0 - absf(speed) / top_speed, 0.0, 1.0)
	# Godot's engine_force pushes toward local +Z, which is the tail of our model, so negate it.
	if throttle > 0.0:
		engine_force = -throttle * engine_power * boost * (fade if boost == 1.0 else maxf(fade, 0.3))
		brake = 0.0
	elif throttle < 0.0:
		if speed > 1.0:
			engine_force = 0.0
			brake = brake_force
		else:
			engine_force = -throttle * reverse_power
			brake = 0.0
	else:
		engine_force = 0.0
		brake = 1.0
	if Input.is_action_pressed("jump"):
		brake = handbrake_force
	var steer_factor := lerpf(1.0, steer_min_factor, clampf(absf(speed) / (steer_full_speed * 3.0), 0.0, 1.0))
	_steer_target = -input.x * max_steer * steer_factor
	steering = lerpf(steering, _steer_target, 1.0 - exp(-steer_speed * delta))
	if is_airborne():
		# W = nose down (front flip), S = nose up, A / D = roll.
		apply_torque(global_basis.x * input.y * air_torque + global_basis.z * (-input.x) * air_torque * 0.7)
	elif global_basis.y.y < 0.2 and linear_velocity.length() < 3.0:
		# Upside down and stuck: roll back onto the wheels.
		var axis := global_basis.z
		apply_torque(axis * upright_torque * signf(global_basis.x.y + 0.0001))


func _on_bumper_hit(body: Node3D) -> void:
	var speed := traffic_speed if is_traffic() else linear_velocity.length()
	if speed < 4.0 or body == driver:
		return
	var dir := -global_basis.z if is_traffic() else linear_velocity.normalized()
	if body is Player and (body as Player).vehicle == null:
		(body as Player).launch(dir * (8.0 + speed) + Vector3.UP * 9.0)
	elif body.has_method("knock"):
		body.knock(dir * (8.0 + speed * 0.6) + Vector3.UP * 6.0)


# --- Model -----------------------------------------------------------------------------

func _build() -> void:
	var dims := _dims()
	var length: float = dims.length
	var width: float = dims.width
	var chassis_h: float = dims.chassis_h
	var cabin: Vector2 = dims.cabin # x = start z (front negative), y = length, along the car
	var base_y := 0.55
	var trim := Color(0.12, 0.12, 0.14)
	var glass := Color(0.35, 0.5, 0.65)
	# Chassis.
	_box(Vector3(width, chassis_h, length), Vector3(0.0, base_y + chassis_h * 0.5, 0.0), paint, true)
	# Cabin.
	var cabin_h: float = dims.cabin_h
	_box(Vector3(width * 0.9, cabin_h, cabin.y), Vector3(0.0, base_y + chassis_h + cabin_h * 0.5, cabin.x + cabin.y * 0.5), paint, true)
	_box(Vector3(width * 0.92, cabin_h * 0.55, cabin.y * 0.96), Vector3(0.0, base_y + chassis_h + cabin_h * 0.55, cabin.x + cabin.y * 0.5), glass, false)
	# Bumpers, lights.
	_box(Vector3(width * 1.02, 0.25, 0.2), Vector3(0.0, base_y + 0.15, -length * 0.5), trim, false)
	_box(Vector3(width * 1.02, 0.25, 0.2), Vector3(0.0, base_y + 0.15, length * 0.5), trim, false)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.35, 0.18, 0.06), Vector3(side * (width * 0.5 - 0.3), base_y + chassis_h * 0.7, -length * 0.5 - 0.02), Color(1.0, 0.95, 0.8), false, true)
		_box(Vector3(0.35, 0.18, 0.06), Vector3(side * (width * 0.5 - 0.3), base_y + chassis_h * 0.7, length * 0.5 + 0.02), Color(1.0, 0.2, 0.15), false, true)
	# Body-type extras.
	match body_type:
		BodyType.PICKUP:
			_box(Vector3(width * 0.9, 0.5, length * 0.42), Vector3(0.0, base_y + chassis_h + 0.25, length * 0.28), paint.darkened(0.2), true)
		BodyType.SPORTS:
			_box(Vector3(width * 0.6, 0.15, 0.8), Vector3(0.0, base_y + chassis_h + 0.08, -length * 0.35), trim, false)
	match addon:
		Addon.ROOF_RACK:
			_box(Vector3(width * 0.8, 0.12, cabin.y * 0.8), Vector3(0.0, base_y + chassis_h + cabin_h + 0.2, cabin.x + cabin.y * 0.5), trim, false)
			_box(Vector3(width * 0.6, 0.5, cabin.y * 0.6), Vector3(0.0, base_y + chassis_h + cabin_h + 0.5, cabin.x + cabin.y * 0.5), Color(0.5, 0.36, 0.22), false)
		Addon.SPOILER:
			_box(Vector3(width * 0.95, 0.08, 0.45), Vector3(0.0, base_y + chassis_h + 0.55, length * 0.45), trim, false)
			for side: float in [-1.0, 1.0]:
				_box(Vector3(0.08, 0.5, 0.3), Vector3(side * width * 0.35, base_y + chassis_h + 0.28, length * 0.45), trim, false)
		Addon.LIGHT_BAR:
			_box(Vector3(width * 0.8, 0.14, 0.2), Vector3(0.0, base_y + chassis_h + cabin_h + 0.1, cabin.x + 0.2), trim, false)
			for i in 6:
				_box(Vector3(0.1, 0.1, 0.1), Vector3(-width * 0.35 + i * width * 0.14, base_y + chassis_h + cabin_h + 0.1, cabin.x + 0.08), Color(1.0, 0.95, 0.7), false, true)
	# Seat marker (where the driver sits) and wheels.
	_seat = Node3D.new()
	_seat.position = Vector3(-0.4, base_y + chassis_h + 0.2, cabin.x + cabin.y * 0.4)
	add_child(_seat)
	# Bumper zone: fast cars knock pedestrians over and launch the player.
	var bumper := Area3D.new()
	bumper.collision_layer = 0
	bumper.collision_mask = 2
	var bshape := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(width + 0.4, 1.6, length + 0.8)
	bshape.shape = bbox
	bshape.position = Vector3(0.0, base_y + 0.6, 0.0)
	bumper.add_child(bshape)
	bumper.body_entered.connect(_on_bumper_hit)
	add_child(bumper)
	var wheel_z: float = dims.wheel_z
	_wheel_slots = []
	for front: bool in [true, false]:
		for side: float in [-1.0, 1.0]:
			_wheel_slots.append([Vector3(side * (width * 0.5 - 0.05), base_y - 0.1, (-wheel_z if front else wheel_z)), front])
	if is_traffic():
		# Kinematic traffic: plain wheel meshes. Real VehicleWheel3D nodes on a frozen body
		# divide by zero inside the engine, so they are only added when the car goes physical.
		for slot in _wheel_slots:
			var visual := _wheel_mesh()
			visual.position = slot[0] + Vector3(0.0, -0.3, 0.0)
			add_child(visual)
			_wheel_visuals.append(visual)
	else:
		_add_real_wheels()


func _add_real_wheels() -> void:
	for slot in _wheel_slots:
		_add_wheel(slot[0], slot[1])


func _wheel_mesh() -> Node3D:
	var holder := Node3D.new()
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.42
	cyl.height = 0.3
	cyl.radial_segments = 10
	mesh.mesh = cyl
	mesh.material_override = PropFactory.material(Color(0.1, 0.1, 0.1))
	mesh.rotation.z = PI * 0.5
	holder.add_child(mesh)
	var hub := MeshInstance3D.new()
	var hub_cyl := CylinderMesh.new()
	hub_cyl.top_radius = 0.22
	hub_cyl.bottom_radius = 0.22
	hub_cyl.height = 0.32
	hub_cyl.radial_segments = 8
	hub.mesh = hub_cyl
	hub.material_override = PropFactory.material(Color(0.75, 0.75, 0.78), 0.4)
	hub.rotation.z = PI * 0.5
	holder.add_child(hub)
	return holder


func _dims() -> Dictionary:
	match body_type:
		BodyType.PICKUP:
			return {"length": 5.4, "width": 2.1, "chassis_h": 0.8, "cabin": Vector2(-1.4, 1.8), "cabin_h": 0.75, "wheel_z": 1.75}
		BodyType.VAN:
			return {"length": 5.2, "width": 2.1, "chassis_h": 0.8, "cabin": Vector2(-2.0, 4.4), "cabin_h": 1.2, "wheel_z": 1.65}
		BodyType.SPORTS:
			return {"length": 4.6, "width": 2.0, "chassis_h": 0.55, "cabin": Vector2(-0.9, 2.0), "cabin_h": 0.55, "wheel_z": 1.45}
		_:
			return {"length": 4.8, "width": 2.0, "chassis_h": 0.7, "cabin": Vector2(-1.0, 2.4), "cabin_h": 0.7, "wheel_z": 1.5}


func _add_wheel(pos: Vector3, front: bool) -> void:
	var wheel := VehicleWheel3D.new()
	wheel.position = pos
	wheel.use_as_traction = true
	wheel.use_as_steering = front
	wheel.wheel_radius = 0.42
	wheel.wheel_rest_length = suspension_rest_length
	wheel.suspension_travel = suspension_travel
	wheel.suspension_stiffness = suspension_stiffness
	wheel.suspension_max_force = suspension_max_force
	wheel.damping_compression = damping_compression
	wheel.damping_relaxation = damping_relaxation
	wheel.wheel_friction_slip = wheel_grip
	wheel.wheel_roll_influence = wheel_roll_influence
	add_child(wheel)
	wheels.append(wheel)
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.42
	cyl.height = 0.3
	cyl.radial_segments = 10
	mesh.mesh = cyl
	mesh.material_override = PropFactory.material(Color(0.1, 0.1, 0.1))
	mesh.rotation.z = PI * 0.5
	wheel.add_child(mesh)
	var hub := MeshInstance3D.new()
	var hub_cyl := CylinderMesh.new()
	hub_cyl.top_radius = 0.22
	hub_cyl.bottom_radius = 0.22
	hub_cyl.height = 0.32
	hub_cyl.radial_segments = 8
	hub.mesh = hub_cyl
	hub.material_override = PropFactory.material(Color(0.75, 0.75, 0.78), 0.4)
	hub.rotation.z = PI * 0.5
	wheel.add_child(hub)


func _box(size: Vector3, pos: Vector3, color: Color, collide: bool, glow: bool = false) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = WeaponFX.unshaded(color) if glow else PropFactory.material(color, 0.45)
	mesh.position = pos
	add_child(mesh)
	if collide:
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		shape.position = pos
		add_child(shape)


## A seeded random car.
static func random_car(rng: RandomNumberGenerator) -> Vehicle:
	var car := Vehicle.new()
	var type := rng.randi_range(0, BodyType.size() - 1) as BodyType
	var extra := Addon.NONE
	if rng.randf() < 0.35:
		extra = rng.randi_range(1, Addon.size() - 1) as Addon
	car.setup(type, PAINTS[rng.randi() % PAINTS.size()], extra)
	return car
