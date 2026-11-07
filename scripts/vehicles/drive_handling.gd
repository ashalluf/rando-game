class_name DriveHandling
extends RefCounted
static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"
## Steering and grip for the PLAYER-driven car (wave 9, drive-steer; docs/HANDOFF.md "Steering and
## grip"). One hook in Vehicle._physics_process() replaces its three steering lines with
## DriveHandling.steer(): the car keeps its own state here (Vehicle meta "drive_handling").
##
## What it does, in order, each physics tick:
##  1. Input shaping. A keyboard is digital: the steer input eases toward the key at `key_in` per
##     second (an ease-in, so a tap is a small correction, not a full lock), back to centre at
##     `key_out` (faster: letting go straightens the wheels) and across centre at `key_flip`. A
##     stick goes through a response curve (`stick_expo`: fine near centre, full at the edge) and
##     only light smoothing (`stick_rate`).
##  2. Speed-sensitive lock. Full lock (`low_lock`, radians) up to `lock_full_speed`, then the
##     angle that asks the tyres for `lat_target` g with a little understeer margin, never under
##     `high_lock`: quick in a car park, calm at 150 km/h.
##  3. Grip balance (once per wheel, on the first driven tick): front x `front_grip`, rear x
##     `rear_grip` of the car's own wheel_friction_slip. A grippier rear is mild understeer at the
##     limit; the car pushes wide rather than spins. Put back when the player leaves.
##  4. Counter-steer assist: when the tail slides (the rear axle's slip angle over `assist_from`
##     degrees) the front wheels are turned toward where it is going by `assist_gain` of the angle
##     (the drift session's handbrake slides keep it, scaled by `assist_handbrake`).
##  5. Yaw settle: with the wheel centred and the car not sliding, the yaw rate left over decays
##     by `yaw_settle` a second on the ground (the self-aligning torque a real tyre has and
##     Godot's raycast wheels do not), so a car straightens after a turn instead of drifting on.
## Symmetric by construction: every term is odd in the input / the slip angle.
## DRIVE_HANDLING=0 in the environment is the A/B (Vehicle's old three lines).

static var enabled: bool = OS.get_environment("DRIVE_HANDLING") != "0"

## --- Input shaping -------------------------------------------------------------------------
## Keyboard: steer input rise per second at the start of a press (it ramps to `key_in_max`).
static var key_in: float = 3.2
## Keyboard: rise per second once the key has been held `key_in_ramp` seconds.
static var key_in_max: float = 7.0
static var key_in_ramp: float = 0.25
## Keyboard: back to centre per second after letting go.
static var key_out: float = 6.5
## Keyboard: from one side to the other per second (a flick in a slalom).
static var key_flip: float = 9.0
## Stick: 0 linear, 1 cubic. Fine control near centre, full lock at the edge.
static var stick_expo: float = 0.45
## Stick: smoothing rate per second (light: a stick is already analogue).
static var stick_rate: float = 14.0

## --- Speed-sensitive lock --------------------------------------------------------------------
## Full lock in radians at walking pace (the old max_steer was 0.5).
static var low_lock: float = 0.6
## Full lock held up to this speed (m/s).
static var lock_full_speed: float = 6.0
## The lock past it asks for this lateral acceleration (g) on a kinematic bicycle ...
static var lat_target: float = 1.15
## ... times this (the tyres slip, so a little more than kinematic).
static var lock_margin: float = 2.2
## Never less lock than this (radians): at 200 km/h a car still changes lanes.
static var high_lock: float = 0.075

## --- Grip ------------------------------------------------------------------------------------
## The player's tyres' friction_slip (the car's own wheel_grip, 10.5, never lets go until it
## snaps into a spin; about this is a 1.1 g limit that slides progressively).
static var tyre_grip: float = 1.6
static var front_grip: float = 0.95
static var rear_grip: float = 1.12

## --- Assists ---------------------------------------------------------------------------------
## Slip angle (degrees) where the counter-steer begins.
static var assist_from: float = 3.0
## Front wheel turned by this share of the slip angle past `assist_from`.
static var assist_gain: float = 1.6
## The assist's share while the handbrake is held (the drift keeps some help).
static var assist_handbrake: float = 0.4
## Yaw-rate decay per second with the wheel centred, on the ground, above `settle_speed`.
static var yaw_settle: float = 2.6
static var settle_speed: float = 4.0

## The per-car state.
var input: float = 0.0
var held: float = 0.0
var grip_applied: bool = false
## The factor each wheel's friction_slip was multiplied by (put back exactly by release()).
var grip_factors: Array = []
var slip_deg: float = 0.0
var lock: float = 0.0


static func of(car: Vehicle) -> DriveHandling:
	var h: DriveHandling = car.get_meta("drive_handling") if car.has_meta("drive_handling") else null
	if h == null:
		h = DriveHandling.new()
		car.set_meta("drive_handling", h)
	return h


## True when a keyboard steering key is down (the digital path). An action pressed from code
## (the probe, the checks) with a strength of exactly 0 or 1 counts as digital too.
static func _digital(raw: float) -> bool:
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_D) \
			or Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_RIGHT):
		return true
	return is_zero_approx(raw) or is_equal_approx(absf(raw), 1.0)


## Pure: the shaped input after one tick. `raw` -1 (left) .. 1 (right).
static func shape(cur: float, raw: float, digital: bool, held_s: float, delta: float) -> float:
	if not digital:
		var target := signf(raw) * lerpf(absf(raw), pow(absf(raw), 3.0), stick_expo)
		return lerpf(cur, target, 1.0 - exp(-stick_rate * delta))
	var rate: float
	if is_zero_approx(raw):
		rate = key_out
	elif cur * raw < 0.0:
		rate = key_flip
	else:
		rate = lerpf(key_in, key_in_max, clampf(held_s / key_in_ramp, 0.0, 1.0))
	return move_toward(cur, raw, rate * delta)


## Pure: the full lock (radians) at `speed` m/s for a car of wheelbase `wb`, capped at `cap`.
static func lock_at(speed: float, wb: float, cap: float) -> float:
	var v := absf(speed)
	var top := minf(low_lock, maxf(cap, low_lock)) # a car with a bigger max_steer keeps low_lock
	if v <= lock_full_speed:
		return top
	var kin := atan(wb * lat_target * 9.8 / (v * v)) * lock_margin
	return clampf(kin, high_lock, top)


## Pure: the counter-steer (radians, + = left) for a slip angle `slip` (radians, + = velocity to
## the left of the nose).
static func counter_steer(slip: float, share: float) -> float:
	var past := maxf(absf(slip) - deg_to_rad(assist_from), 0.0)
	return signf(slip) * past * assist_gain * share


static func steer(car: Vehicle, raw_x: float, speed: float, delta: float) -> void:
	var h := of(car)
	var digital := _digital(raw_x)
	h.held = h.held + delta if not is_zero_approx(raw_x) else 0.0
	h.input = shape(h.input, raw_x, digital, h.held, delta)
	if not h.grip_applied:
		h.grip_applied = true
		var base := tyre_grip / maxf(car.wheel_grip, 0.01)
		for w in car.wheels:
			var f := base * (front_grip if w.use_as_steering else rear_grip)
			h.grip_factors.append(f)
			w.wheel_friction_slip *= f
	h.lock = lock_at(speed, _wheelbase(car), car.max_steer)
	var target := -h.input * h.lock
	# The slip angle at the REAR AXLE: where the tail goes against where the car points. In a
	# turn on grip it stays near 0 (the CoM's own slip angle does not: it points into the turn,
	# and counter-steering that tightened every corner); a rear stepping out makes it large.
	var v := car.linear_velocity
	var r: Vector3 = car.global_basis * (Vector3(0.0, 0.0, _rear_z(car)) - car.center_of_mass)
	var vr := v + car.angular_velocity.cross(r)
	var flat := Vector3(vr.x, 0.0, vr.z)
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	var slip := 0.0
	if flat.length() > 3.0 and fwd.length() > 0.1 and speed > 0.0:
		slip = fwd.normalized().signed_angle_to(flat.normalized(), Vector3.UP)
	h.slip_deg = rad_to_deg(slip)
	var hb := Input.is_action_pressed("alt_fire")
	# A drift system (wave 9, drive-drift) may set meta "assist_share" (0..1) on the car while it
	# holds a slide on purpose; otherwise the handbrake keeps `assist_handbrake` of the help.
	var share := assist_handbrake if hb else 1.0
	if car.has_meta("assist_share"):
		share = float(car.get_meta("assist_share"))
	target += counter_steer(slip, share)
	target = clampf(target, -maxf(h.lock, low_lock), maxf(h.lock, low_lock))
	car._steer_target = target
	# The wheels follow the target fast: the input shaping above is the ramp.
	car.steering = lerpf(car.steering, target, 1.0 - exp(-maxf(car.steer_speed, 14.0) * delta))
	# Yaw settle with the wheel centred and the body gripping.
	if is_zero_approx(raw_x) and absf(h.input) < 0.05 and not hb and absf(speed) > settle_speed \
			and absf(slip) < deg_to_rad(assist_from) and not car.is_airborne():
		# A torque impulse, never a write to angular_velocity: VehicleBody3D syncs that before its
		# wheel impulses (the Motorcycles note), and writing it back fights the tyres.
		var st := PhysicsServer3D.body_get_direct_state(car.get_rid())
		if st:
			var inv: Basis = st.inverse_inertia_tensor
			var iyy := 1.0 / maxf(absf(inv.y.y), 1e-6)
			var dw := car.angular_velocity.y * (1.0 - exp(-yaw_settle * delta))
			car.apply_torque_impulse(Vector3.UP * -dw * iyy)


## Put the car's tyres back as they were (the player got out).
static func release(car: Vehicle) -> void:
	if not car.has_meta("drive_handling"):
		return
	var h: DriveHandling = car.get_meta("drive_handling")
	if h.grip_applied:
		for i in mini(car.wheels.size(), h.grip_factors.size()):
			var w: VehicleWheel3D = car.wheels[i]
			if is_instance_valid(w):
				# Something reset the tyre to the car's full grip meanwhile (CrashBreakup's repair):
			# it is the car's own again, leave it.
			if w.wheel_friction_slip < car.wheel_grip * 0.99:
				w.wheel_friction_slip /= float(h.grip_factors[i])
	car.remove_meta("drive_handling")


static func _rear_z(car: Vehicle) -> float:
	var zr := 0.0
	for w in car.wheels:
		if is_instance_valid(w):
			zr = maxf(zr, w.position.z)
	return zr


static func _wheelbase(car: Vehicle) -> float:
	var zf := INF
	var zr := -INF
	for w in car.wheels:
		if is_instance_valid(w):
			zf = minf(zf, w.position.z)
			zr = maxf(zr, w.position.z)
	return clampf(zr - zf, 1.6, 8.0) if zf < INF else 2.7
