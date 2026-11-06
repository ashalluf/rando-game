class_name DriveCam
extends Node
## The chase camera while the player drives (a child of the CameraRig, made by it in _ready).
## The rig keeps its own yaw / pitch / spring arm; while the player is at the wheel of a ground
## vehicle (cars, bikes, trucks, boats - not the jets or the helicopter) `apply()` steers them:
##
## - the view follows the way the car TRAVELS (its velocity; its nose when slow or reversing) on a
##   critically damped spring, so it lags and swings into a corner by the car's yaw rate (capped by
##   `max_corner_lag_deg`), and leans a little against the cornering force (`corner_roll`);
## - it drops lower (`pitch_slow_deg` -> `pitch_fast_deg`) and pulls back (`speed_pullback`) with
##   speed, and falls back under hard acceleration / closes in under braking (`accel_pull`);
## - the field of view opens a little with speed (`speed_fov`) and on the nitro (`nitro_fov`);
## - a road shake: a low sway and a high buzz worked out from the clock (sums of sines, never
##   per-frame random), stronger off the tarmac, and every component faded out once it is above
##   `max_buzz_share` of the frame rate, so 30 fps and 144 fps see the same motion;
## - kicks (an under-damped spring, sub-stepped): a dip on a bump, a thump on a landing scaled by
##   the fall speed, a lurch and a shake on a crash;
## - free look: mouse or stick input hands the view to the player; `free_look_hold` seconds after
##   the last input it eases back behind the car over `recenter_seconds`; `look_behind` (C / pad X)
##   swings it round while held and back on release.
##
## It also hands CameraPost a driving motion blur (`blur_gain` with speed) - the car rides with
## the camera, so it stays sharp while the road and the roadside streak - and gives the spring arm
## a sphere (`arm_radius`) so the near plane never pokes into a wall the ray slipped past.
## `DRIVE_CAM=0` in the environment is the A/B: the old free camera in a car.

@export_group("Follow")
## How stiffly the view follows the car's heading at a crawl / at speed (1/s; spring omega).
@export var follow_slow: float = 3.5
@export var follow_fast: float = 5.5
## The most the view may lag the car's heading in a corner (degrees).
@export var max_corner_lag_deg: float = 22.0
## Extra lag per rad/s of yaw rate (degrees): swings the view out so the car shows its flank.
@export var corner_swing_deg: float = 4.0
## Below this speed (m/s) the view follows the car's nose, above it the way it travels.
@export var velocity_follow_from: float = 4.0
## Roll against the cornering force, degrees per g, and its cap.
@export var corner_roll: float = 1.6
@export var corner_roll_max: float = 3.0

@export_group("Framing")
## Distance behind the pivot (m) = base + per metre of the vehicle's length.
@export var distance_base: float = 3.9
@export var distance_per_length: float = 0.5
## Pulled back this far (m) at full speed.
@export var speed_pullback: float = 2.0
## Metres the camera falls back per m/s^2 of forward acceleration (closes in under braking).
@export var accel_pull: float = 0.06
@export var accel_pull_max: float = 1.1
## Pitch (degrees, negative looks down) at a crawl and at full speed.
@export var pitch_slow_deg: float = -11.0
@export var pitch_fast_deg: float = -6.0
## How much of a slope the camera follows (0 none, 1 the car's own pitch).
@export var slope_follow: float = 0.45
## Pivot height over the vehicle's centre (m) = base + per metre of length.
@export var pivot_base: float = 1.15
@export var pivot_per_length: float = 0.09
## Speeds (m/s) the speed effects start at and are full at (8 = 30 km/h, 42 = 150 km/h).
@export var speed_from: float = 8.0
@export var speed_full: float = 42.0

@export_group("Field of view")
## Degrees added at full speed (subtle), and on the nitro (replaces the on-foot boost FOV).
@export var speed_fov: float = 7.0
@export var nitro_fov: float = 5.0

@export_group("Road shake")
## Master scale of the road shake (the settings' "Driving camera shake" sets 0 or this).
@export_range(0.0, 2.0) var shake_scale: float = 1.0
## High-frequency buzz at full speed on tarmac (degrees) and the slow sway (degrees).
@export var buzz_deg: float = 0.10
@export var sway_deg: float = 0.22
## Off the tarmac (hill terrain, sand) the shake is this many times stronger.
@export var rough_gain: float = 2.4
## A shake component is faded out above this share of the frame rate (0.5 = Nyquist).
@export var max_buzz_share: float = 0.4

@export_group("Kicks")
## Vertical speed change in one tick (m/s) that counts as a bump, and the dip per m/s.
@export var bump_min_dv: float = 1.2
@export var bump_gain: float = 0.6
## Landing thump: per m/s of fall speed (degrees of pitch, metres down), capped.
@export var land_pitch_deg: float = 0.15
@export var land_drop: float = 0.022
@export var land_max: float = 30.0
## A horizontal speed change in one tick past this (m/s) is a crash: lurch per m/s, and a shake.
@export var crash_min_dv: float = 5.0
@export var crash_lurch: float = 0.09
@export var crash_shake: float = 0.03
## The kick spring: stiffness (omega, 1/s) and damping ratio (under 1 bounces once).
@export var kick_omega: float = 15.0
@export var kick_damping: float = 0.45

@export_group("Free look")
## Seconds after the last look input before the view starts to come back behind the car.
@export var free_look_hold: float = 1.3
## Seconds the ease back takes.
@export var recenter_seconds: float = 0.9
## Seconds the view stays the player's after the car touches down from a flight (in the air it
## is always the player's: the car flies where the camera looks).
@export var air_hold: float = 0.5
## Seconds to swing round to look behind and back.
@export var look_behind_seconds: float = 0.16
## Seconds to blend into the chase camera on getting in, and out of it on getting out.
@export var blend_seconds: float = 0.6

@export_group("Motion blur")
## CameraPost's blur strength is multiplied by 1 + this at full speed.
@export var blur_gain: float = 0.7
## The blur's soft knee (px) is raised this much while driving: the car's own small lag and the
## buzz stay under it, so the car stays sharp.
@export var blur_threshold_add: float = 1.5

@export_group("Spring arm")
## Radius of the sphere the arm sweeps while driving (m); the ray alone can slip past a corner.
@export var arm_radius: float = 0.25

## Off with DRIVE_CAM=0.
static var enabled: bool = OS.get_environment("DRIVE_CAM") != "0"

## 0..1: how much of the chase camera is in force (eases in and out).
var weight: float = 0.0
## The vehicle being chased, or null.
var car: Vehicle
## Debug / checks: the last values worked out.
var speed: float = 0.0
var speed_t: float = 0.0
var lag_deg: float = 0.0
var distance: float = 0.0
var fov_add: float = 0.0
var kicks: int = 0
var crashes: int = 0
var landings: int = 0

var _rig: Node3D
var _arm: SpringArm3D
var _arm_shape_keep: Shape3D
var _arm_sphere: SphereShape3D
var _chase_yaw: float = 0.0
## The heading spring's own state (its lag is capped and swung before it becomes _chase_yaw).
var _spring_yaw: float = 0.0
var _chase_yaw_v: float = 0.0
var _chase_pitch: float = 0.0
var _free_yaw: float = 0.0
var _free_pitch: float = 0.0
## 0 the player's view, 1 the chase view.
var _auto: float = 1.0
var _hold: float = 0.0
var _behind: float = 0.0
var _clock: float = 0.0
var _len: float = 4.6
var _accel: float = 0.0
var _lat_g: float = 0.0
var _prev_v := Vector3.ZERO
var _prev_pos := Vector3.ZERO
var _have_prev: bool = false
var _air_ticks: int = 0
var _air_vy: float = 0.0
var _rough: float = 1.0
var _shake_rot := Vector3.ZERO
## The kick springs: pitch (rad), drop (m), lurch (m along the arm).
var _k := Vector3.ZERO
var _kv := Vector3.ZERO
var _look_noted: bool = false
var _was_on: bool = false
var _was_air: bool = false


func setup(rig: Node3D, arm: SpringArm3D) -> void:
	_rig = rig
	_arm = arm
	_arm_shape_keep = arm.shape
	_arm_sphere = SphereShape3D.new()
	_arm_sphere.radius = arm_radius


## The vehicle a player drives that the chase camera follows, or null (on foot, a jet, the
## helicopter, the camera off).
static func chased(player: Node) -> Vehicle:
	if not enabled or player == null or not player.has_method("is_driving") or not player.is_driving():
		return null
	var v: Vehicle = player.get("vehicle")
	if v == null or v is Aircraft or v is FlyableHeli:
		return null
	return v


## The rig saw mouse or stick look input this frame.
func note_look() -> void:
	_look_noted = true


## Smooth 0..1 of `x` between `a` and `b`.
static func ramp(x: float, a: float, b: float) -> float:
	return smoothstep(a, b, x)


## One step of a critically damped spring toward `target` (exact for a constant target, so any
## frame rate lands on the same curve): returns [x, v].
static func spring(x: float, v: float, target: float, omega: float, dt: float) -> Vector2:
	var e := exp(-omega * dt)
	var dx := x - target
	var temp := (v + omega * dx) * dt
	return Vector2(target + (dx + temp) * e, (v - omega * temp) * e)


## The road shake at `clock` seconds (radians: pitch, yaw, roll) for a speed share `st`, a surface
## gain `rough` and a frame of `dt` seconds. Pure: the same clock gives the same shake.
func road_shake(clock: float, st: float, rough: float, dt: float) -> Vector3:
	var nyq := max_buzz_share / maxf(dt, 0.001)
	var out := Vector3.ZERO
	# [frequency Hz, amplitude share, axis weights]
	var comps := [
		[1.3, sway_deg, Vector3(0.6, 0.35, 1.0), 0.0, true],
		[2.1, sway_deg * 0.6, Vector3(1.0, 0.25, 0.5), 1.7, true],
		[11.7, buzz_deg, Vector3(1.0, 0.4, 0.6), 0.4, false],
		[17.3, buzz_deg * 0.7, Vector3(0.7, 0.6, 1.0), 2.3, false],
		[23.9, buzz_deg * 0.45, Vector3(1.0, 0.3, 0.4), 4.1, false],
	]
	# The sway is there from a crawl, the buzz grows with the square of the speed.
	var sway_part := clampf(st * 1.5, 0.0, 1.0) * (0.4 + 0.6 * st)
	var buzz_part := st * st
	for c: Array in comps:
		var f: float = c[0]
		var fade := 1.0 - smoothstep(nyq * 0.6, nyq, f)
		if fade <= 0.0:
			continue
		var a := deg_to_rad(float(c[1])) * fade * (sway_part if c[4] else buzz_part)
		var w: Vector3 = c[2]
		var ph: float = c[3]
		out += Vector3(sin(TAU * f * clock + ph) * w.x, sin(TAU * f * 1.07 * clock + ph * 1.9) * w.y,
				sin(TAU * f * 0.93 * clock + ph * 2.7) * w.z) * a
	return out * rough * shake_scale


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		_have_prev = false
		return
	var v := car.linear_velocity
	var pos := car.global_position
	if _have_prev and pos.distance_to(_prev_pos) > maxf(30.0, v.length() * delta * 4.0 + 5.0):
		_have_prev = false # teleported (respawn, origin shift): no kick
	var grounded := _grounded()
	if _have_prev and delta > 0.0:
		var dv := v - _prev_v
		var fwd := -car.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var a_long := Vector3(dv.x, 0.0, dv.z).dot(fwd) / delta
		var a_lat := Vector3(dv.x, 0.0, dv.z).dot(right) / delta
		var lp := 1.0 - exp(-delta / 0.25)
		var hdv := Vector3(dv.x, 0.0, dv.z).length()
		if hdv < crash_min_dv:
			_accel = lerpf(_accel, a_long, lp)
			_lat_g = lerpf(_lat_g, a_lat / 9.8, lp) if grounded else lerpf(_lat_g, 0.0, lp)
		# Crash: a velocity change no engine or brake makes in one tick.
		if hdv > crash_min_dv:
			crash(hdv)
		# Landing after a real flight, or a bump on the road.
		if grounded and _air_ticks > 12:
			land(-_air_vy)
		elif grounded and dv.y > bump_min_dv:
			bump(dv.y)
	if grounded:
		_air_ticks = 0
	else:
		_air_ticks += 1
		_air_vy = v.y
	_prev_v = v
	_prev_pos = pos
	_have_prev = true


func _grounded() -> bool:
	var any := false
	var rough := 1.0
	for c in car.get_children():
		var w := c as VehicleWheel3D
		if w == null:
			continue
		if w.is_in_contact():
			any = true
			var body := w.get_contact_body()
			if body != null and (body.has_meta("terrain") or (body is CollisionObject3D and (body as CollisionObject3D).collision_layer & 16 != 0)):
				rough = rough_gain
	_rough = lerpf(_rough, rough, 0.1)
	# A wheel-less vehicle (kinematic, a boat) counts as on the ground.
	return any or not car.get_children().any(func(n: Node) -> bool: return n is VehicleWheel3D)


## A bump of `dv` m/s upward in one tick: a short dip.
func bump(dv: float) -> void:
	var s := minf(dv, 8.0) * bump_gain
	_kv += Vector3(deg_to_rad(-0.18) * s, -0.012 * s, 0.0) * kick_omega
	kicks += 1


## Touch-down after a flight falling at `fall` m/s.
func land(fall: float) -> void:
	if fall < 3.0:
		return
	var f := minf(fall, land_max)
	_kv += Vector3(deg_to_rad(-land_pitch_deg) * f, -land_drop * f, 0.0) * kick_omega
	landings += 1
	kicks += 1
	if f > 12.0 and _rig and _rig.has_method("shake"):
		_rig.shake(clampf((f - 12.0) * 0.012, 0.0, 0.25) * shake_scale)


## A crash: the car lost `dv` m/s in one tick.
func crash(dv: float) -> void:
	var d := minf(dv, 40.0)
	_kv += Vector3(deg_to_rad(0.15) * d, 0.0, -crash_lurch * d) * kick_omega
	crashes += 1
	kicks += 1
	if _rig and _rig.has_method("shake"):
		_rig.shake(clampf(d * crash_shake, 0.0, 0.8) * maxf(shake_scale, 0.3))


## Integrates the kick springs over `dt` in sub-steps (frame-rate independent).
func _kick_step(dt: float) -> void:
	var n := maxi(1, ceili(dt / (1.0 / 240.0)))
	var h := dt / float(n)
	var w := kick_omega
	for i in n:
		var acc := -w * w * _k - 2.0 * kick_damping * w * _kv
		_kv += acc * h
		_k += _kv * h
	_k.x = clampf(_k.x, deg_to_rad(-6.0), deg_to_rad(6.0))
	_k.y = clampf(_k.y, -0.6, 0.4)
	_k.z = clampf(_k.z, -2.0, 1.0)


## Works the chase view out for this frame and writes it into the rig. Returns a dictionary the
## rig applies after its own: {"yaw", "pitch", "rot" (extra rotation), "distance", "fov_add",
## "pivot" (global), "weight"}. Empty when there is nothing to do.
func apply(rig_yaw: float, rig_pitch: float, player: Node, delta: float, look_behind: bool) -> Dictionary:
	var target := chased(player)
	if target != car:
		_set_car(target, rig_yaw, rig_pitch)
	var on := car != null and is_instance_valid(car)
	if not on and car != null:
		car = null
	weight = move_toward(weight, 1.0 if on else 0.0, delta / maxf(blend_seconds, 0.01))
	if weight <= 0.0 and not on:
		_look_noted = false
		if _was_on:
			_was_on = false
			_restore_arm()
		return {}
	if on and not _was_on:
		_was_on = true
		if _arm and _arm_sphere:
			_arm_sphere.radius = arm_radius
			_arm.shape = _arm_sphere
	_clock += delta
	if not on:
		# Getting out: hand the view back where it is, just ease the framing out.
		_look_noted = false
		_kick_step(delta)
		return {"yaw": rig_yaw, "pitch": rig_pitch, "rot": _k.x * Vector3.RIGHT, "distance": distance,
			"fov_add": fov_add * weight, "pivot": Vector3.INF, "weight": weight, "drop": _k.y}

	var v := car.linear_velocity
	var flat := Vector3(v.x, 0.0, v.z)
	speed = flat.length()
	speed_t = ramp(speed, speed_from, speed_full)
	var fwd := -car.global_basis.z
	var nose := Vector3(fwd.x, 0.0, fwd.z)
	nose = nose.normalized() if nose.length() > 0.1 else Vector3.FORWARD
	# Where it travels: its velocity when moving forward at a pace, its nose otherwise.
	var head := nose
	if speed > velocity_follow_from and flat.normalized().dot(nose) > -0.2:
		head = nose.slerp(flat.normalized(), ramp(speed, velocity_follow_from, velocity_follow_from * 2.5))
	var heading := atan2(-head.x, -head.z)
	var yaw_rate := car.angular_velocity.y
	var omega := lerpf(follow_slow, follow_fast, speed_t)
	# The spring on the heading (unwrapped round the current value), held within the cap.
	var cap := deg_to_rad(max_corner_lag_deg)
	var tgt := _spring_yaw + wrapf(heading - _spring_yaw, -PI, PI)
	var sv := spring(_spring_yaw, _chase_yaw_v, tgt, omega, delta)
	var spring_lag := clampf(wrapf(heading - sv.x, -PI, PI), -cap, cap)
	_spring_yaw = wrapf(heading - spring_lag, -PI, PI)
	_chase_yaw_v = sv.y
	# The swing: lag a little more by the yaw rate (never stored in the spring), then the cap.
	var lag := clampf(spring_lag + deg_to_rad(corner_swing_deg) * clampf(yaw_rate, -2.0, 2.0) * speed_t, -cap, cap)
	_chase_yaw = wrapf(heading - lag, -PI, PI)
	lag_deg = rad_to_deg(lag)

	var airborne := _air_ticks > 6
	var slope := 0.0
	if not airborne:
		slope = asin(clampf(fwd.y, -1.0, 1.0)) * slope_follow
	var want_pitch := deg_to_rad(lerpf(pitch_slow_deg, pitch_fast_deg, speed_t)) + slope
	_chase_pitch = lerpf(_chase_pitch, want_pitch, 1.0 - exp(-3.0 * delta))

	# Free look: the player's input takes the view; after a hold it eases back.
	# In the air the car flies where the CAMERA looks (Vehicle._fly(): boost thrusts along it), so
	# leaving the ground hands the view to the player as it stands, and it is never taken back
	# while the car is airborne; the chase eases back in after touch-down.
	if airborne and not _was_air:
		_free_yaw = rig_yaw
		_free_pitch = rig_pitch
		_auto = 0.0
	_was_air = airborne
	if _look_noted:
		_free_yaw = rig_yaw
		_free_pitch = rig_pitch
		_auto = 0.0
		_hold = free_look_hold
	elif airborne:
		_hold = maxf(_hold, air_hold)
	else:
		_hold -= delta
		if _hold <= 0.0:
			_auto = move_toward(_auto, 1.0, delta / maxf(recenter_seconds, 0.01))
	_look_noted = false
	var a := smoothstep(0.0, 1.0, _auto)
	var yaw := lerp_angle(_free_yaw, _chase_yaw, a)
	var pitch := lerpf(_free_pitch, _chase_pitch, a)
	_behind = move_toward(_behind, 1.0 if look_behind else 0.0, delta / maxf(look_behind_seconds, 0.01))
	if _behind > 0.0:
		var b := smoothstep(0.0, 1.0, _behind)
		yaw = lerp_angle(yaw, wrapf(_chase_yaw + PI, -PI, PI), b)
		pitch = lerpf(pitch, deg_to_rad(pitch_slow_deg), b)
	# Blend from the view the rig had when we got in.
	if weight < 1.0:
		var wb := smoothstep(0.0, 1.0, weight)
		yaw = lerp_angle(rig_yaw, yaw, wb)
		pitch = lerpf(rig_pitch, pitch, wb)

	_kick_step(delta)
	_shake_rot = road_shake(_clock, speed_t, _rough, delta)
	var roll := clampf(-_lat_g * corner_roll, -corner_roll_max, corner_roll_max)
	var accel_off := clampf(_accel * accel_pull, -accel_pull_max, accel_pull_max)
	distance = distance_base + distance_per_length * _len + speed_pullback * speed_t + accel_off + _k.z
	var nitro := Input.is_action_pressed("boost") and not airborne
	fov_add = speed_fov * pow(speed_t, 1.5) + (nitro_fov if nitro else 0.0)
	var pivot := car.global_position + Vector3.UP * (pivot_base + pivot_per_length * _len)
	return {"yaw": yaw, "pitch": pitch,
		"rot": Vector3(_shake_rot.x + _k.x, _shake_rot.y, _shake_rot.z + deg_to_rad(roll)),
		"distance": distance, "fov_add": fov_add, "pivot": pivot, "weight": weight, "drop": _k.y}


func _set_car(c: Vehicle, rig_yaw: float, rig_pitch: float) -> void:
	car = c
	_have_prev = false
	_air_ticks = 0
	_accel = 0.0
	_lat_g = 0.0
	_k = Vector3.ZERO
	_kv = Vector3.ZERO
	_behind = 0.0
	if c == null:
		return
	_len = 4.6
	if c.has_method("_dims"):
		var d: Dictionary = c.call("_dims")
		_len = clampf(float(d.get("length", 4.6)), 2.0, 22.0)
	if c.body_type == Vehicle.BodyType.SEMI:
		_len += 7.0 # the trailer
	var fwd := -c.global_basis.z
	_chase_yaw = atan2(-fwd.x, -fwd.z)
	_spring_yaw = _chase_yaw
	_chase_yaw_v = 0.0
	_chase_pitch = deg_to_rad(pitch_slow_deg)
	# Ease from the view the player had into the chase view.
	_free_yaw = rig_yaw
	_free_pitch = rig_pitch
	_auto = 0.0
	_hold = 0.0


func _restore_arm() -> void:
	if _arm:
		_arm.shape = _arm_shape_keep


## The road's share of the motion blur while driving: [strength multiplier, threshold px added].
func blur_terms() -> Vector2:
	if car == null:
		return Vector2(1.0, 0.0)
	return Vector2(1.0 + blur_gain * speed_t * weight, blur_threshold_add * weight)
