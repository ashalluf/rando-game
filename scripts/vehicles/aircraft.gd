class_name Aircraft
extends Vehicle
## A flyable jet. Rolls on three wheels like a car (taxi with the throttle, A / D steer when
## slow) and flies on an arcade model once it has airspeed: thrust along the nose, lift from
## airspeed, drag, pitch and roll from the stick, a turn that follows the bank, gentle
## self-leveling. Shift = throttle up, right click = throttle down, W / S pitch, A / D roll.
## Every feel number is an export below.

enum Kind { PRIVATE, AIRLINER }

const KIND_NAMES := ["Private Jet", "Airliner"]
## Generated models per kind (see docs/ASSETS.md). Missing files fall back to a primitive plane.
const MODELS := {
	Kind.PRIVATE: "res://assets/models/jet_private.glb",
	Kind.AIRLINER: "res://assets/models/jet_airliner.glb",
}
## Extra yaw so the nose points at -Z.
const KIND_MODEL_YAW := {Kind.PRIVATE: PI * 0.5, Kind.AIRLINER: -PI * 0.5}

@export_group("Flight")
## Full-throttle thrust as an acceleration (m/s^2).
@export var thrust_accel: float = 22.0
## Lift acceleration per (m/s)^2 of airspeed; level flight where lift = 9.8 (about 55 m/s).
@export var lift_coef: float = 0.0032
## Lift cap (m/s^2) so a fast pull-up stays sane.
@export var max_lift_accel: float = 34.0
## Forward drag acceleration per (m/s)^2 (sets the top speed with thrust_accel).
@export var drag_coef: float = 0.0006
## Sideways and vertical (wing-plane) drag per m/s: the plane flies where it points.
@export var side_drag: float = 2.2
@export var vertical_drag: float = 2.6
## Pitch and roll authority (rad/s^2 at full stick and full control).
@export var pitch_torque: float = 2.4
@export var roll_torque: float = 4.0
## Turn rate that follows the bank angle.
@export var yaw_from_bank: float = 1.6
## Self-leveling roll when the stick is centered.
@export var level_torque: float = 1.2
## Airspeed (m/s) at which the controls reach full authority.
@export var control_speed: float = 45.0
## Throttle change per second (Shift up, right click down).
@export var throttle_rate: float = 0.7
## Taxi push at full throttle on the ground (N) and wheel brake.
@export var taxi_force: float = 26000.0
@export var wheel_brake: float = 60.0

@export_group("Airframe")
@export var kind: Kind = Kind.PRIVATE
## Fuselage length (m); the model is scaled to it.
@export var length: float = 20.0
@export var wingspan: float = 18.0
@export var plane_mass: float = 3500.0

var throttle: float = 0.0


func setup_aircraft(k: Kind) -> void:
	kind = k
	if k == Kind.AIRLINER:
		length = 38.0
		wingspan = 36.0
		plane_mass = 9000.0
		thrust_accel = 18.0
		pitch_torque = 1.6
		roll_torque = 2.2
		control_speed = 60.0
	enter_radius = length * 0.6
	paint = Color(0.95, 0.95, 0.96)
	body_type = BodyType.SEDAN


func display_name() -> String:
	return KIND_NAMES[kind]


func _ready() -> void:
	super()
	mass = plane_mass
	angular_damp = 2.5
	linear_damp = 0.0
	center_of_mass = Vector3(0.0, -0.4, 0.0)


func _build() -> void:
	_has_model = _add_plane_model()
	var white := Color(0.95, 0.95, 0.96)
	var dark := Color(0.35, 0.36, 0.4)
	var fuse_r := length * 0.06
	var base_y := 0.55
	# Fuselage and wings: collision always, visible only without a model.
	_box(Vector3(fuse_r * 2.0, fuse_r * 2.0, length * 0.9), Vector3(0.0, base_y + fuse_r + 0.6, 0.0), white, true)
	_box(Vector3(wingspan, 0.35, length * 0.16), Vector3(0.0, base_y + fuse_r * 0.9, length * 0.05), white, true)
	_box(Vector3(wingspan * 0.35, 0.3, length * 0.1), Vector3(0.0, base_y + fuse_r * 1.4, length * 0.42), white, false)
	_box(Vector3(0.4, fuse_r * 2.4, length * 0.12), Vector3(0.0, base_y + fuse_r * 3.2, length * 0.42), Color(0.2, 0.35, 0.7), false)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(fuse_r * 0.9, fuse_r * 0.9, length * 0.14), Vector3(side * fuse_r * 2.2, base_y + fuse_r * 1.6, length * 0.3), dark, false)
	_seat = Node3D.new()
	_seat.position = Vector3(0.0, base_y + fuse_r * 1.2, -length * 0.36)
	add_child(_seat)
	# Bumper zone: a landing plane sweeps pedestrians and cars aside.
	var bumper := Area3D.new()
	bumper.collision_layer = 0
	bumper.collision_mask = 2 | 8
	var bshape := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(wingspan, 3.0, length)
	bshape.shape = bbox
	bshape.position = Vector3(0.0, base_y + 1.0, 0.0)
	bumper.add_child(bshape)
	bumper.body_entered.connect(_on_bumper_hit)
	add_child(bumper)
	# Tricycle gear.
	_wheel_slots = [
		[Vector3(0.0, base_y - 0.1, -length * 0.36), true],
		[Vector3(-fuse_r * 1.8, base_y - 0.1, length * 0.06), false],
		[Vector3(fuse_r * 1.8, base_y - 0.1, length * 0.06), false],
	]
	_add_real_wheels()


func _add_plane_model() -> bool:
	var path: String = MODELS.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		return false
	var scene: PackedScene = load(path)
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	var aabb := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var box := m.mesh.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	if first:
		return false
	var along_x := aabb.size.x >= aabb.size.z
	var model_len := aabb.size.x if along_x else aabb.size.z
	inst.scale = Vector3.ONE * (length / maxf(model_len, 0.01))
	inst.rotation.y = (KIND_MODEL_YAW.get(kind, 0.0) if along_x else 0.0)
	var center := aabb.get_center()
	inst.position = -(inst.transform.basis * Vector3(center.x, aabb.position.y, center.z)) + Vector3(0.0, model_bottom_y, 0.0)
	var holder := Node3D.new()
	holder.name = "BodyModel"
	holder.add_child(inst)
	add_child(holder)
	return true


func exit_candidates() -> Array[Vector3]:
	var side := Vector3(global_basis.x.x, 0.0, global_basis.x.z)
	side = side.normalized() if side.length() > 0.2 else Vector3.RIGHT
	var fwd := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	fwd = fwd.normalized() if fwd.length() > 0.2 else Vector3.FORWARD
	var base := global_position + Vector3.UP * 0.5 - fwd * length * 0.3
	var reach := length * 0.12 + 2.0
	return [base + side * reach, base - side * reach, base - fwd * (length * 0.3 + 3.0), base + fwd * (length * 0.3 + 3.0), global_position + Vector3.UP * (length * 0.15 + 2.0)]


func _physics_process(delta: float) -> void:
	if driver == null:
		engine_force = 0.0
		brake = wheel_brake
		throttle = 0.0
		steering = lerpf(steering, 0.0, 1.0 - exp(-steer_speed * delta))
		if _engine_sound and _engine_sound.playing:
			_engine_sound.stop()
		return
	if _engine_sound == null:
		_engine_sound = Sfx.loop_player("engine_loop", -6.0)
		add_child(_engine_sound)
	if not _engine_sound.playing:
		_engine_sound.play()
	if Input.is_action_pressed("boost"):
		throttle = minf(throttle + throttle_rate * delta, 1.0)
	if Input.is_action_pressed("alt_fire"):
		throttle = maxf(throttle - throttle_rate * 1.3 * delta, 0.0)
	_engine_sound.pitch_scale = 0.6 + throttle * 1.2
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var fwd := -global_basis.z
	var v := linear_velocity
	var air := maxf(v.dot(fwd), 0.0)
	var grounded := not is_airborne()
	# Thrust, lift, drag.
	apply_central_force(fwd * thrust_accel * throttle * mass)
	var lift := minf(air * air * lift_coef, max_lift_accel)
	apply_central_force(global_basis.y * lift * mass)
	if v.length() > 0.5:
		apply_central_force(-v.normalized() * v.length_squared() * drag_coef * mass)
	apply_central_force(-global_basis.x * v.dot(global_basis.x) * side_drag * mass)
	if not grounded:
		apply_central_force(-global_basis.y * v.dot(global_basis.y) * vertical_drag * mass)
	# Stick: pitch and roll scale with airspeed; the turn follows the bank; level out when idle.
	var ctrl := clampf(air / control_speed, 0.0, 1.0)
	apply_torque(global_basis.x * input.y * pitch_torque * ctrl * mass)
	apply_torque(global_basis.z * (-input.x) * roll_torque * ctrl * mass)
	apply_torque(Vector3.UP * global_basis.x.y * yaw_from_bank * ctrl * mass)
	if absf(input.x) < 0.1:
		apply_torque(global_basis.z * (-global_basis.x.y) * level_torque * ctrl * mass)
	# Wheels: taxi push, steering, brakes.
	if grounded:
		engine_force = -throttle * taxi_force if air < control_speed else 0.0
		var steer_amount := clampf(1.0 - air / control_speed, 0.15, 1.0)
		steering = lerpf(steering, -input.x * max_steer * steer_amount, 1.0 - exp(-steer_speed * delta))
		brake = wheel_brake if (input.y > 0.5 and throttle < 0.05) else 0.0
	else:
		engine_force = 0.0
		brake = 0.0
		steering = 0.0
