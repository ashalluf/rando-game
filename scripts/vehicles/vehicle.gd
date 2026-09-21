class_name Vehicle
extends VehicleBody3D
## Arcade car: bouncy, grippy, overpowered, with a nitro. Built from boxes in code with a body
## type, a paint color and an optional add-on. Press interact next to it to drive.

enum BodyType { SEDAN, PICKUP, VAN, SPORTS, SUPER, SPIDER, HYPER, TRACK }
enum Addon { NONE, ROOF_RACK, SPOILER, LIGHT_BAR }

## Original names. Nothing here is or imitates a real manufacturer's model.
const BODY_NAMES := ["Sedan", "Pickup", "Van", "Sports", "Vantari", "Vantari Aperta", "Kestrel", "Kestrel RS"]
## Generated body models per type (see docs/ASSETS.md). Missing files fall back to the box car.
const BODY_MODELS := {
	BodyType.SEDAN: "res://assets/models/car_sedan.glb",
	BodyType.PICKUP: "res://assets/models/car_pickup.glb",
	BodyType.VAN: "res://assets/models/car_van.glb",
	BodyType.SPORTS: "res://assets/models/car_sports.glb",
	BodyType.SUPER: "res://assets/models/hifi_super_coupe.glb",
	BodyType.SPIDER: "res://assets/models/exo_super_spider.glb",
	BodyType.HYPER: "res://assets/models/hifi_hyper_coupe.glb",
	BodyType.TRACK: "res://assets/models/exo_hyper_b.glb",
}
## How often each body type turns up, in parts per thousand. Exotics are deliberately rare: a
## street where every fourth car is a hypercar reads as a toy box, and the whole reason they land
## is that they are unusual. Must sum to 1000.
const BODY_ODDS := {
	BodyType.SEDAN: 300, BodyType.PICKUP: 190, BodyType.VAN: 175, BodyType.SPORTS: 215,
	BodyType.SUPER: 45, BodyType.SPIDER: 25, BodyType.HYPER: 30, BodyType.TRACK: 20,
}
## Extra yaw per model so its nose points at -Z (Meshy models come out along +X or -X).
## All four models come out of Meshy with the nose along +X; -PI/2 puts the nose at -Z, which is
## the physics forward (owner, 2026-09-20: traffic drove backwards with +PI/2).
const MODEL_YAW := {BodyType.SEDAN: -PI * 0.5, BodyType.PICKUP: -PI * 0.5, BodyType.VAN: -PI * 0.5, BodyType.SPORTS: -PI * 0.5}
const PAINT_SHADER := preload("res://shaders/car_paint.gdshader")

## How the paint is built, not what colour it is. The clearcoat shader can express all of these
## for free, they are just different uniform sets, and a street where every car is the same
## metallic basecoat reads as one car repeated whatever the colours are.
enum Finish {
	GLOSS,    ## Solid non-metallic lacquer: fleet white, taxi yellow, safety orange.
	METALLIC, ## The ordinary modern car: aluminium flake under clear.
	PEARL,    ## Flake plus a second coat that only shows at grazing angles (the pearl flip).
	DEEP,     ## Deep candy metallic: dark, very glossy, coarse flake. Reads as an expensive car.
	MATTE,    ## Satin wrap: no lacquer at all, high roughness. Rare, and very distinctive.
}
## The graphic painted on top of the base colour, in body space (see car_paint.gdshader).
enum Livery {
	NONE,
	RACING,   ## Twin stripes over the nose, roof and tail.
	TWO_TONE, ## Lower body in a second colour.
	TAXI,     ## Yellow, checker band along the doors, lit roof sign.
	DELIVERY, ## Fleet colour with a belt band and a roof vent pod (vans).
	SERVICE,  ## Municipal white/orange with a belt band and an amber beacon (pickups).
}

## Paint colours. The weighting IS the duplication - random_car() picks uniformly from this list,
## so an entry twice is twice as common. Keep the shape of it: about half the cars neutral
## (white / black / grey / silver), a sixth muted, and a real saturated third, because that is
## the balance the owner asked for on 2026-09-21 ("more color and more gta") against the earlier
## all-neutral car park. Flattening this into one colour per entry, or letting the saturated
## block grow past the neutrals, turns the traffic into a bag of sweets.
const PAINTS := [
	# Whites and off-whites: the most common car colour on earth, and mostly solid gloss.
	Color(0.90, 0.90, 0.89), Color(0.90, 0.90, 0.89), Color(0.84, 0.85, 0.85),
	Color(0.93, 0.92, 0.87), Color(0.88, 0.89, 0.92),
	# Blacks and near-blacks.
	Color(0.055, 0.055, 0.062), Color(0.055, 0.055, 0.062), Color(0.10, 0.10, 0.12),
	Color(0.075, 0.080, 0.090), Color(0.120, 0.115, 0.105),
	# Greys and silvers.
	Color(0.38, 0.39, 0.41), Color(0.38, 0.39, 0.41), Color(0.58, 0.59, 0.61),
	Color(0.24, 0.25, 0.27), Color(0.68, 0.69, 0.70), Color(0.45, 0.47, 0.50),
	Color(0.30, 0.32, 0.36), Color(0.62, 0.60, 0.57), Color(0.50, 0.51, 0.53),
	Color(0.20, 0.21, 0.24),
	# Muted colours: deep navy, dark red, forest green, beige, dark teal.
	Color(0.10, 0.16, 0.34), Color(0.36, 0.07, 0.08), Color(0.12, 0.22, 0.16),
	Color(0.52, 0.47, 0.40), Color(0.10, 0.22, 0.24),
	# Saturated: the minority, but a real one. These are the cars you actually notice.
	Color(0.72, 0.04, 0.05), Color(0.88, 0.12, 0.06), Color(0.05, 0.20, 0.72),
	Color(0.08, 0.40, 0.85), Color(0.95, 0.76, 0.04), Color(0.93, 0.36, 0.02),
	Color(0.03, 0.46, 0.18), Color(0.46, 0.74, 0.08), Color(0.32, 0.06, 0.55),
	Color(0.82, 0.10, 0.42), Color(0.03, 0.55, 0.60), Color(0.75, 0.56, 0.10),
	Color(0.56, 0.26, 0.08), Color(0.32, 0.74, 0.56),
]
## Finish per entry of PAINTS: same order, same grouping, same line breaks, so the two blocks
## can be read side by side. If you add a colour, add its finish on the matching line.
const PAINT_FINISH := [
	# Whites.
	Finish.GLOSS, Finish.GLOSS, Finish.METALLIC,
	Finish.PEARL, Finish.GLOSS,
	# Blacks.
	Finish.DEEP, Finish.METALLIC, Finish.METALLIC,
	Finish.DEEP, Finish.MATTE,
	# Greys and silvers.
	Finish.METALLIC, Finish.METALLIC, Finish.METALLIC,
	Finish.DEEP, Finish.METALLIC, Finish.DEEP,
	Finish.DEEP, Finish.PEARL, Finish.MATTE,
	Finish.METALLIC,
	# Muted.
	Finish.DEEP, Finish.DEEP, Finish.METALLIC,
	Finish.METALLIC, Finish.METALLIC,
	# Saturated.
	Finish.DEEP, Finish.GLOSS, Finish.DEEP,
	Finish.METALLIC, Finish.GLOSS, Finish.GLOSS,
	Finish.DEEP, Finish.GLOSS, Finish.PEARL,
	Finish.PEARL, Finish.METALLIC, Finish.METALLIC,
	Finish.DEEP, Finish.PEARL,
]

## Shader uniforms per finish. These are the knobs the clearcoat shader already had and nothing
## was using: flake density and grain, how sharp the lacquer is, and how metallic the basecoat
## is under it. "flake_fade" is how far away the sparkle is still worth resolving.
const FINISHES := {
	Finish.GLOSS: {
		"metallic": 0.20, "roughness": 0.28, "clearcoat": 0.95, "cc_rough": 0.045,
		"flake": 0.0, "flake_scale": 190.0, "flake_fade": 9.0, "pearl": 0.0,
	},
	Finish.METALLIC: {
		"metallic": 0.70, "roughness": 0.22, "clearcoat": 0.85, "cc_rough": 0.035,
		"flake": 0.055, "flake_scale": 190.0, "flake_fade": 9.0, "pearl": 0.0,
	},
	Finish.PEARL: {
		"metallic": 0.45, "roughness": 0.16, "clearcoat": 1.00, "cc_rough": 0.018,
		"flake": 0.085, "flake_scale": 300.0, "flake_fade": 11.0, "pearl": 0.35,
	},
	Finish.DEEP: {
		"metallic": 0.88, "roughness": 0.13, "clearcoat": 1.00, "cc_rough": 0.015,
		"flake": 0.110, "flake_scale": 120.0, "flake_fade": 13.0, "pearl": 0.0,
	},
	Finish.MATTE: {
		"metallic": 0.15, "roughness": 0.62, "clearcoat": 0.0, "cc_rough": 0.30,
		"flake": 0.0, "flake_scale": 190.0, "flake_fade": 9.0, "pearl": 0.0,
	},
}

## Shader uniforms per livery graphic. "mode" is the stripe_mode the shader switches on; widths
## and heights are fractions of the car's own bounding box, so one table fits every body type.
const LIVERY_GRAPHIC := {
	Livery.RACING: {"mode": 1, "width": 0.032, "gap": 0.058},
	Livery.TWO_TONE: {"mode": 2, "width": 0.010, "height": 0.40},
	Livery.DELIVERY: {"mode": 3, "width": 0.075, "height": 0.46},
	Livery.SERVICE: {"mode": 3, "width": 0.090, "height": 0.42},
	Livery.TAXI: {"mode": 4, "width": 0.060, "height": 0.40},
}

## Share of each body type that goes out as a working vehicle instead of private paint. Vans are
## mostly commercial in a real city, which is why that one is high; taxis and city trucks are a
## visible minority. These do more for the "real city" read than paint variety does, so they are
## the first numbers to raise if the streets still feel like a car park.
const TAXI_SHARE := 0.16
const DELIVERY_SHARE := 0.45
const SERVICE_SHARE := 0.20
## Share of private cars wearing a graphic. Sports cars get stripes far more often than anything
## else; two-tone is a truck and van thing and never goes on a sports car.
const RACING_SHARE_SPORTS := 0.26
const RACING_SHARE_OTHER := 0.05
const TWO_TONE_SHARE := 0.12

## Fleet colours for delivery vans, with the belt band that goes with each. Flat solid gloss, the
## way a real fleet is painted, and deliberately not in PAINTS: a livery is not private taste.
## All invented - no real courier's colours, no logos anywhere.
const FLEET_PAINTS := [
	Color(0.90, 0.90, 0.88), Color(0.90, 0.90, 0.88), Color(0.36, 0.20, 0.10),
	Color(0.06, 0.18, 0.46), Color(0.68, 0.10, 0.10), Color(0.08, 0.36, 0.22),
]
const FLEET_BANDS := [
	Color(0.80, 0.10, 0.12), Color(0.10, 0.28, 0.66), Color(0.94, 0.72, 0.10),
	Color(0.92, 0.92, 0.90), Color(0.94, 0.92, 0.88), Color(0.95, 0.80, 0.10),
]
## City service trucks: utility white, highways orange, water-department blue.
const SERVICE_PAINTS := [
	Color(0.92, 0.92, 0.90), Color(0.94, 0.48, 0.03),
	Color(0.92, 0.92, 0.90), Color(0.15, 0.30, 0.58),
]
const SERVICE_BANDS := [
	Color(0.94, 0.48, 0.03), Color(0.10, 0.10, 0.12),
	Color(0.12, 0.34, 0.66), Color(0.94, 0.72, 0.10),
]
const TAXI_PAINT := Color(0.96, 0.73, 0.03)
const TAXI_TRIM := Color(0.07, 0.07, 0.08)

@export_group("Model")
## Where the generated model's tire bottoms sit in body space (meters). Raise if the car floats.
@export var model_bottom_y: float = -0.27
## Past this many meters a livery's roof prop (taxi sign, van vent, amber beacon) stops drawing.
## It is one draw call per car and at that range it is a couple of pixels.
@export var livery_prop_distance: float = 140.0

@export_group("Handling")
## Engine force at full throttle (N). Big number = silly acceleration.
@export var engine_power: float = 7000.0
## Engine force multiplier while holding boost.
@export var nitro_multiplier: float = 2.2
@export var reverse_power: float = 3500.0
@export var brake_force: float = 80.0
@export var handbrake_force: float = 40.0
## Upward speed of a car jump (m/s). Space.
@export var jump_speed: float = 9.0
@export var jump_cooldown: float = 0.22
## Jump in mid-air too, as many times as you like (owner, 2026-09-21: "unlimited jumping in the
## cars so i can fly around nonstop"). The car already goes into stabilised flight the moment it
## leaves the ground, so an air jump is a second thrust in the same regime rather than a new
## mode - it just keeps you up. Set false for a car that can only jump off the ground.
@export var air_jump: bool = true
## An air jump is worth this much of a ground jump. Under 1.0 so a held-down space bar climbs at
## a controllable rate instead of firing you into orbit.
@export var air_jump_factor: float = 0.72
## Max steering angle (radians).
@export var max_steer: float = 0.5
## How fast the wheels turn toward the stick (higher = twitchier).
@export var steer_speed: float = 8.0
## Steering shrinks at speed so the car does not spin out: full steer below this speed (m/s).
@export var steer_full_speed: float = 12.0
@export var steer_min_factor: float = 0.35
## Top speed (m/s); engine force fades to zero here.
@export var top_speed: float = 55.0
## Self-righting torque when upside down and slow on the ground.
@export var upright_torque: float = 25000.0

@export_group("Flight")
## Owner's rule (2026-09-20): a car in the air must fly like the player does, not tumble.
## Leaving the ground puts the car into a stabilised hover: it holds itself level, the stick
## aims it, and holding boost thrusts it where the camera is looking.
## Thrust while holding boost in the air (m/s^2 of acceleration).
@export var fly_thrust: float = 42.0
## Speed cap while flying (m/s).
@export var fly_max_speed: float = 62.0
## Gravity multiplier while boosting in the air. Low value = hold boost and hover.
@export var fly_gravity_scale: float = 0.12
## Gravity multiplier while airborne without boost (a floaty arc, not a brick).
@export var air_gravity_scale: float = 0.85
## How fast the car swings to the orientation you are asking for (higher = snappier).
@export var level_speed: float = 7.0
## Nose pitch from the stick while airborne (radians; W noses down, S noses up).
@export var fly_pitch_range: float = 0.75
## Turn rate from the stick while airborne (radians per second).
@export var fly_yaw_rate: float = 2.0
## Fastest the car will rotate while self-levelling (radians per second).
@export var max_turn_rate: float = 5.0
## Bank angle the car rolls into while turning in the air (radians).
@export var fly_bank: float = 0.5

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
## How the paint is built (see Finish) and what is painted on top of it (see Livery).
var finish: Finish = Finish.METALLIC
var livery: Livery = Livery.NONE
## Second colour: racing stripes, the two-tone lower body, a fleet band, the taxi checker.
var trim_color: Color = Color(0.92, 0.92, 0.93)
## The Player driving, or null.
var driver: Node3D
## How close the player has to be to get in (meters from the origin; big for aircraft).
var enter_radius: float = 4.5
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
var _jump_timer: float = 0.0
## Heading the car holds while flying (radians). Seeded from the car when it leaves the ground.
var _fly_yaw: float = 0.0
var _was_airborne: bool = false
## True when a generated body model is used: box parts then only provide collision.
var _has_model: bool = false
## Top of the generated model in body space, measured from its own bounding box, so a roof prop
## sits on the actual roof instead of on a guess. Only valid once _add_body_model() has run.
var _model_top_y: float = 1.6
## Livery roof props are one shared mesh per kind, so a hundred and fifty cars cost a hundred
## and fifty draws, not a hundred and fifty meshes.
static var _livery_meshes: Dictionary = {}


func setup(type: BodyType, color: Color, extra: Addon) -> void:
	body_type = type
	paint = color
	addon = extra


## The optional second half of setup(): the finish, the livery graphic and its colour. A car set
## up without it is a plain metallic in the body colour, which is what every old caller gets.
## Call it before adding the car to the tree - _build() runs in _ready().
func setup_look(paint_finish: Finish, car_livery: Livery = Livery.NONE, trim: Color = Color(0.92, 0.92, 0.93)) -> void:
	finish = paint_finish
	livery = car_livery
	trim_color = trim


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


## Places to try when getting out, best first: the door side, the other side, behind, in front,
## and on the roof. Flattened so a car on its side or roof never points "out" into the ground.
func exit_candidates() -> Array[Vector3]:
	var side := Vector3(global_basis.x.x, 0.0, global_basis.x.z)
	side = side.normalized() if side.length() > 0.2 else Vector3.RIGHT
	var fwd := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	fwd = fwd.normalized() if fwd.length() > 0.2 else Vector3.FORWARD
	var base := global_position + Vector3.UP * 0.5
	return [
		base + side * (2.6 * _exit_side),
		base - side * (2.6 * _exit_side),
		base - fwd * 4.0,
		base + fwd * 4.0,
		global_position + Vector3.UP * 2.5,
	]


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
		if _was_airborne:
			gravity_scale = 1.0
			_was_airborne = false
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
	if Input.is_action_pressed("alt_fire"):
		brake = handbrake_force
	_jump_timer = maxf(_jump_timer - delta, 0.0)
	var airborne := is_airborne()
	if Input.is_action_just_pressed("jump") and _jump_timer <= 0.0 and (not airborne or air_jump):
		_jump_timer = jump_cooldown
		# Straight up in world space, and kill the spin: pushing along the car's own up axis
		# while the suspension is still unloading is what used to tip the nose over. In the air
		# the same impulse is a hop, scaled down so a held space bar climbs steadily.
		var boost_up := jump_speed * (air_jump_factor if airborne else 1.0)
		# In the air, cancel any existing fall first, so a jump always gains height instead of
		# being eaten by the speed you had picked up on the way down.
		if airborne and linear_velocity.y < 0.0:
			apply_central_impulse(Vector3.UP * -linear_velocity.y * mass)
		apply_central_impulse(Vector3.UP * boost_up * mass)
		angular_velocity = Vector3.ZERO
		Sfx.play("jump", global_position, -2.0, 0.7)
	var steer_factor := lerpf(1.0, steer_min_factor, clampf(absf(speed) / (steer_full_speed * 3.0), 0.0, 1.0))
	_steer_target = -input.x * max_steer * steer_factor
	steering = lerpf(steering, _steer_target, 1.0 - exp(-steer_speed * delta))
	if is_airborne():
		_fly(delta, input)
	else:
		if _was_airborne:
			gravity_scale = 1.0
		_was_airborne = false
		if global_basis.y.y < 0.2 and linear_velocity.length() < 3.0:
			# Upside down and stuck: roll back onto the wheels.
			var axis := global_basis.z
			apply_torque(axis * upright_torque * signf(global_basis.x.y + 0.0001))


## Stabilised flight. The car holds itself level and pointed where you steer instead of
## tumbling: W / S aim the nose down / up, A / D turn (banking into it), and holding boost
## thrusts along the camera direction with almost no gravity, exactly like the player's boost.
func _fly(delta: float, input: Vector2) -> void:
	if not _was_airborne:
		# Just left the ground: carry the heading we were driving in.
		_fly_yaw = global_rotation.y
		_was_airborne = true
	var flying := Input.is_action_pressed("boost")
	gravity_scale = fly_gravity_scale if flying else air_gravity_scale

	# Where the nose should point. Turning is a rate, pitch is a held angle.
	_fly_yaw = wrapf(_fly_yaw - input.x * fly_yaw_rate * delta, -PI, PI)
	var pitch := input.y * fly_pitch_range
	var roll := -input.x * fly_bank
	if flying and driver != null and driver.get("camera_rig") != null:
		# Boosting: follow the camera, so the car flies where you look.
		var rig: Node3D = driver.camera_rig
		_fly_yaw = rig.global_rotation.y
		# The rig pitches positive when looking up, and a positive pitch here noses up too.
		pitch = rig.rotation.x
	var target := Basis(Vector3.UP, _fly_yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)

	# Turn the difference between where we point and where we want to point into an angular
	# velocity, and ease into it. Torque alone leaves the car wobbling; this holds an attitude.
	var swing := (target * global_basis.inverse()).orthonormalized()
	var q := Quaternion(swing)
	var angle := q.get_angle()
	if angle > PI:
		angle -= TAU
	var want := (q.get_axis() * angle * level_speed) if absf(angle) > 0.0001 else Vector3.ZERO
	# Cap the correction: a half-turn of error times the gain is a violent spin that overshoots
	# and oscillates instead of settling.
	if want.length() > max_turn_rate:
		want = want.normalized() * max_turn_rate
	angular_velocity = angular_velocity.lerp(want, 1.0 - exp(-level_speed * delta))

	if flying:
		# An impulse scaled by the step, not apply_central_force: VehicleBody3D clears the
		# per-step force accumulator while it solves its wheels, so plain forces do nothing.
		apply_central_impulse(-target.z * fly_thrust * mass * delta)
		if linear_velocity.length() > fly_max_speed:
			linear_velocity = linear_velocity.normalized() * fly_max_speed


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
	_has_model = _add_body_model(length)
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
	bumper.collision_mask = 2 | 8
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
			_wheel_slots.append([Vector3(side * float(dims.get("track", 1.62)) * 0.5, base_y - 0.1, (-wheel_z if front else wheel_z)), front])
	if is_traffic():
		# Kinematic traffic: plain wheel meshes. Real VehicleWheel3D nodes on a frozen body
		# divide by zero inside the engine, so they are only added when the car goes physical.
		for slot in _wheel_slots:
			var visual := _wheel_mesh()
			visual.position = slot[0] + Vector3(0.0, -0.3, 0.0)
			visual.visible = not _has_model # the generated models have their own wheels
			add_child(visual)
			_wheel_visuals.append(visual)
	else:
		_add_real_wheels()
	_add_night_lights(dims)
	_add_livery_props(dims)


## The one piece of geometry a livery needs: a lit taxi sign, a van's roof vent pod, a service
## truck's amber beacon. One box each, one shared mesh per kind, no shadow, and it stops drawing
## at livery_prop_distance. Everything else about a livery is paint, so it costs nothing.
## The height comes from the model's own bounding box (_model_top_y), and the position along the
## car is kept close to the middle on purpose: that is inside the roof of every one of the four
## models whichever way round the mesh was authored.
func _add_livery_props(dims: Dictionary) -> void:
	if livery != Livery.TAXI and livery != Livery.DELIVERY and livery != Livery.SERVICE:
		return
	var top := _model_top_y
	if not _has_model:
		top = 0.55 + float(dims.chassis_h) + float(dims.cabin_h)
	var length: float = dims.length
	var node := MeshInstance3D.new()
	node.name = "LiveryProp"
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = livery_prop_distance
	match livery:
		Livery.TAXI:
			node.mesh = _shared_box(&"taxi_sign", Vector3(0.62, 0.20, 0.30),
					WeaponFX.unshaded(Color(0.99, 0.84, 0.30)))
			node.position = Vector3(0.0, top + 0.08, length * 0.06)
		Livery.DELIVERY:
			node.mesh = _shared_box(&"van_vent", Vector3(0.60, 0.18, 0.78),
					PropFactory.material(Color(0.62, 0.63, 0.64), 0.55))
			node.position = Vector3(0.0, top + 0.07, length * 0.12)
		Livery.SERVICE:
			node.mesh = _shared_box(&"beacon", Vector3(0.95, 0.15, 0.22),
					WeaponFX.unshaded(Color(1.0, 0.55, 0.06)))
			node.position = Vector3(0.0, top + 0.06, 0.0)
	add_child(node)


## A BoxMesh carrying its own material, built once and shared by every car that wants it.
static func _shared_box(key: StringName, size: Vector3, mat: Material) -> BoxMesh:
	if _livery_meshes.has(key):
		return _livery_meshes[key]
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	_livery_meshes[key] = box
	return box


## Headlights, tail lights and the pool of light the beams throw on the road. All of it is the
## additive night quad (shaders/light_pool.gdshader), so it costs no real lights and it is
## invisible by day. The generated body models carry no lamps of their own and _box() skips
## every primitive once a model is in use, so without this a city of cars drives around at
## midnight completely dark.
func _add_night_lights(dims: Dictionary) -> void:
	var node := MeshInstance3D.new()
	node.name = "NightLights"
	node.mesh = PropFactory.vehicle_lights(dims.width, dims.length, 0.55 + dims.chassis_h * 0.62)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# One node per car rather than five: with a hundred and fifty cars on the road the separate
	# quads were several hundred draw calls on their own. Past this distance the car is a few
	# pixels and its lights are not worth one.
	node.visibility_range_end = 160.0
	add_child(node)


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


## Per body type. "track" is the distance between the two wheel CENTRES and "tyre_r" the wheel
## radius, both in metres, and both used to be one shared value that was simply wrong: wheels
## were parked at width * 0.5 - 0.05, which on a 2.1 m body is a 2.0 m track, and the radius was
## a flat 0.42 (an 0.84 m wheel). A real car runs a 1.55-1.75 m track on 0.63-0.72 m wheels, so
## every body built to fit those wheels had to be flared out past 2.2 m wide and still looked
## like it was on tractor tyres. "ride" is where the bottom of the body model sits: a van cannot
## share a saloon's ride height without looking slammed.
func _dims() -> Dictionary:
	match body_type:
		BodyType.PICKUP:
			return {"length": 5.4, "width": 2.0, "chassis_h": 0.8, "cabin": Vector2(-1.4, 1.8), "cabin_h": 0.75, "wheel_z": 1.75, "track": 1.72, "tyre_r": 0.37, "ride": -0.16}
		BodyType.VAN:
			return {"length": 5.2, "width": 2.0, "chassis_h": 0.8, "cabin": Vector2(-2.0, 4.4), "cabin_h": 1.2, "wheel_z": 1.65, "track": 1.70, "tyre_r": 0.35, "ride": -0.18}
		BodyType.SPORTS:
			return {"length": 4.6, "width": 1.9, "chassis_h": 0.55, "cabin": Vector2(-0.9, 2.0), "cabin_h": 0.55, "wheel_z": 1.45, "track": 1.64, "tyre_r": 0.34, "ride": -0.30}
		BodyType.SUPER, BodyType.SPIDER:
			return {"length": 4.55, "width": 1.98, "chassis_h": 0.5, "cabin": Vector2(-0.6, 1.6), "cabin_h": 0.5, "wheel_z": 1.32, "track": 1.70, "tyre_r": 0.35, "ride": -0.34}
		BodyType.HYPER, BodyType.TRACK:
			return {"length": 4.6, "width": 2.02, "chassis_h": 0.48, "cabin": Vector2(-0.6, 1.5), "cabin_h": 0.48, "wheel_z": 1.35, "track": 1.74, "tyre_r": 0.36, "ride": -0.35}
		_:
			return {"length": 4.8, "width": 1.9, "chassis_h": 0.7, "cabin": Vector2(-1.0, 2.4), "cabin_h": 0.7, "wheel_z": 1.5, "track": 1.62, "tyre_r": 0.34, "ride": -0.24}


func _add_wheel(pos: Vector3, front: bool) -> void:
	var wheel := VehicleWheel3D.new()
	wheel.position = pos
	wheel.use_as_traction = true
	wheel.use_as_steering = front
	wheel.wheel_radius = float(_dims().get("tyre_r", 0.34))
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
	if _has_model:
		return # the generated models have their own wheels
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


## Instances the generated body model for this type, scaled to `length` and tinted with the
## paint (the models are textured white). Returns false when the model file does not exist.
func _add_body_model(length: float) -> bool:
	var path: String = BODY_MODELS.get(body_type, "")
	if path == "" or not ResourceLoader.exists(path):
		return false
	var scene: PackedScene = load(path)
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = "BodyModel"
	holder.add_child(inst)
	var aabb := AABB()
	var first := true
	var painted_mats: Array[ShaderMaterial] = []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var box := m.mesh.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
		# Per SURFACE, not material_override. The Meshy bodies are one surface with the paint
		# baked into the albedo, so overriding the whole instance was right for them. The
		# generated bodies carry six named slots - paint, glass, trim, tyre, light_front,
		# light_rear - and material_override would have painted the windows, the tyres and the
		# headlights in body colour, which is exactly the problem the slots exist to solve.
		for si in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(si)
			if not (mat is StandardMaterial3D):
				continue
			var sm := mat as StandardMaterial3D
			# A multi-slot body paints only the slot called "paint"; a single-slot body is a
			# Meshy car and the one surface IS the bodywork.
			if m.mesh.get_surface_count() > 1 and not String(sm.resource_name).begins_with("paint"):
				continue
			var painted := _paint_material(sm.albedo_texture, sm.normal_texture)
			painted_mats.append(painted)
			m.set_surface_override_material(si, painted)
	if first:
		return false
	# Longest horizontal axis is the length; scale so it matches our chassis.
	var along_x := aabb.size.x >= aabb.size.z
	var model_len := aabb.size.x if along_x else aabb.size.z
	var scale_f := length / maxf(model_len, 0.01)
	inst.scale = Vector3.ONE * scale_f
	# The livery is painted in the mesh's own space, so the shader needs the box it lives in and
	# which way round it was authored. Set after the loop, because the box is only complete once
	# every surface has been merged into it.
	for pm in painted_mats:
		pm.set_shader_parameter("body_min", aabb.position)
		pm.set_shader_parameter("body_size", aabb.size)
		pm.set_shader_parameter("length_is_x", along_x)
	# inst.position below puts the bottom of the box at model_bottom_y, so the top of the car is
	# exactly that plus the scaled height of the box. That is where a roof prop goes.
	var bottom: float = float(_dims().get("ride", model_bottom_y))
	_model_top_y = bottom + aabb.size.y * scale_f
	inst.rotation.y = (MODEL_YAW.get(body_type, 0.0) if along_x else 0.0)
	var center := aabb.get_center()
	inst.position = -(inst.transform.basis * Vector3(center.x, aabb.position.y, center.z)) + Vector3(0.0, bottom, 0.0)
	add_child(holder)
	return true


## One car's paint: the base colour, the finish's uniform set and the livery graphic. Every car
## gets its own ShaderMaterial (they differ per car), but they all share the one shader.
func _paint_material(albedo: Texture2D, normal: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PAINT_SHADER
	mat.set_shader_parameter("albedo_tex", albedo)
	mat.set_shader_parameter("paint", paint)
	if normal:
		mat.set_shader_parameter("normal_tex", normal)
		mat.set_shader_parameter("has_normal", true)
	var f: Dictionary = FINISHES.get(finish, FINISHES[Finish.METALLIC])
	mat.set_shader_parameter("paint_metallic", f.metallic)
	mat.set_shader_parameter("paint_roughness", f.roughness)
	mat.set_shader_parameter("clearcoat_amount", f.clearcoat)
	mat.set_shader_parameter("clearcoat_roughness_value", f.cc_rough)
	mat.set_shader_parameter("flake_strength", f.flake)
	mat.set_shader_parameter("flake_scale", f.flake_scale)
	mat.set_shader_parameter("flake_fade_distance", f.flake_fade)
	if float(f.pearl) > 0.0:
		mat.set_shader_parameter("pearl_amount", f.pearl)
		mat.set_shader_parameter("pearl_color", _pearl_tint(paint))
	var g: Dictionary = LIVERY_GRAPHIC.get(livery, {})
	if not g.is_empty():
		mat.set_shader_parameter("stripe_mode", g.mode)
		mat.set_shader_parameter("stripe_color", trim_color)
		mat.set_shader_parameter("stripe_width", g.width)
		mat.set_shader_parameter("stripe_gap", g.get("gap", 0.058))
		mat.set_shader_parameter("stripe_height", g.get("height", 0.42))
	return mat


## The colour a pearl coat flips to at grazing angles: the paint's own hue nudged round, washed
## out and lifted. On a white pearl that is the faint warm glow round the edge of the panel.
static func _pearl_tint(base: Color) -> Color:
	return Color.from_hsv(fposmod(base.h + 0.10, 1.0), minf(base.s * 0.5, 0.55), minf(base.v * 1.5 + 0.30, 1.0))


func _box(size: Vector3, pos: Vector3, color: Color, collide: bool, glow: bool = false) -> void:
	if not _has_model:
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


## A seeded random car: body type, add-on, paint, finish and livery.
## Maps a 0-999 roll onto a body type through BODY_ODDS.
static func _body_for_roll(roll: int) -> BodyType:
	var run := 0
	for t: int in BODY_ODDS:
		run += int(BODY_ODDS[t])
		if roll < run:
			return t as BodyType
	return BodyType.SEDAN


static func random_car(rng: RandomNumberGenerator) -> Vehicle:
	var car := Vehicle.new()
	# The look seed is read off the generator's state rather than drawn from it. Reading does not
	# advance the stream, so the whole finish / livery pass below costs zero rng calls: one extra
	# call here would shift every later roll in the caller's stream and move the parked cars,
	# props and lots that the city has already been generated with (CLAUDE.md).
	var look := hash([rng.state, 7717])
	# ONE rng call, as before - the range widens but the stream advances identically, so every
	# later roll in the caller's stream is untouched and the city does not move (CLAUDE.md).
	var type := _body_for_roll(rng.randi_range(0, 999))
	var extra := Addon.NONE
	if rng.randf() < 0.35:
		extra = rng.randi_range(1, Addon.size() - 1) as Addon
	var index := rng.randi() % PAINTS.size()
	var color: Color = PAINTS[index]
	var fin: Finish = Finish.METALLIC
	if index < PAINT_FINISH.size():
		fin = PAINT_FINISH[index]
	var livery := Livery.NONE
	var trim := _contrast_trim(color)
	# Working vehicles first: they replace the private paint entirely, and they are what makes a
	# street read as a city rather than a car park.
	var job := _roll(look, 11)
	match type:
		BodyType.SEDAN:
			if job < TAXI_SHARE:
				livery = Livery.TAXI
				color = TAXI_PAINT
				trim = TAXI_TRIM
				fin = Finish.GLOSS
				extra = Addon.NONE
		BodyType.VAN:
			if job < DELIVERY_SHARE:
				livery = Livery.DELIVERY
				var fleet := absi(hash([look, 12])) % FLEET_PAINTS.size()
				color = FLEET_PAINTS[fleet]
				trim = FLEET_BANDS[fleet]
				fin = Finish.GLOSS
				extra = Addon.NONE
		BodyType.PICKUP:
			if job < SERVICE_SHARE:
				livery = Livery.SERVICE
				var kind := absi(hash([look, 13])) % SERVICE_PAINTS.size()
				color = SERVICE_PAINTS[kind]
				trim = SERVICE_BANDS[kind]
				fin = Finish.GLOSS
				extra = Addon.NONE
	if livery == Livery.NONE:
		var graphic := _roll(look, 21)
		var racing := RACING_SHARE_SPORTS if type == BodyType.SPORTS else RACING_SHARE_OTHER
		if graphic < racing:
			livery = Livery.RACING
		elif type != BodyType.SPORTS and graphic < racing + TWO_TONE_SHARE:
			livery = Livery.TWO_TONE
	car.setup(type, color, extra)
	car.setup_look(fin, livery, trim)
	return car


## A 0..1 roll from a look seed. Deterministic and free: it never touches a RandomNumberGenerator,
## so adding one of these to a generation path cannot move anything else in the world.
static func _roll(look: int, salt: int) -> float:
	return float(absi(hash([look, salt])) % 100000) / 100000.0


## Stripes and bands have to read against the paint under them, so they flip with its brightness.
static func _contrast_trim(base: Color) -> Color:
	return Color(0.07, 0.07, 0.08) if base.get_luminance() > 0.30 else Color(0.93, 0.93, 0.92)
