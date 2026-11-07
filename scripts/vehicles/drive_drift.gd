class_name DriveDrift
extends RefCounted
## Handbrake and drift for the player's car (wave 9, docs/HANDOFF.md "Handbrake and drift").
##
## What main did: the handbrake set the body's `brake`, which Godot's VehicleWheel3D ignores while
## the wheel has any engine_force (the wheel's rolling impulse IS the engine's), so with throttle
## held it did nothing at all; without throttle it braked all four wheels, which have a
## friction_slip of 10.5 (about 13 g of side grip), so the car stopped dead in a straight line
## (tools/drive_drift/probe.tscn: 3.5 degrees of slip at most, a 15 m/s handbrake turn stopped
## after 74 degrees, a J-turn turned 28).
##
## What this does, from one hook in Vehicle._physics_process (after the controls are written, so
## its per-wheel writes win) and one in the parked branch (`idle()`: the tyres back):
##  - HANDBRAKE (alt_fire: right mouse / left trigger) over HB_MIN_SPEED: the TRAILING axle (the
##    rear going forward, the front reversing) is locked and its grip drops to HB_GRIP; the leading
##    axle keeps the throttle. The slide is steered by a slip-angle controller (below), so a flick
##    swings the tail out to HB_ANGLE and no further.
##  - SPIN (180s and J-turns): handbrake with near full lock off the throttle under SPIN_SPEED, or
##    reversing, turns
##    the car on through a 180 at SPIN_RATE; nothing limits it while it is held.
##  - HOLD: released with the slide still on, the rear grip stays low while the throttle is in
##    (HOLD_GRIP at full throttle), the speed is kept by a push along the travel (DRIFT_PUSH), and
##    the angle follows the stick: steering into the slide holds it out to HOLD_MAX, counter-steer
##    brings it back to HOLD_MIN and out of the drift. It never spins out on its own.
##  - GRIP BACK: under EXIT_ANGLE, slower than EXIT_SPEED or off the throttle, the grip comes back
##    over GRIP_RETURN seconds (a snap back to 10.5 in one step hooks the car).
##  - POWER OVERSTEER: rear-driven bodies (RWD) put RWD_REAR of the torque on the rear wheels, and
##    full throttle with over half lock under POWER_MAX_SPEED lets the rear step out to POWER_ANGLE.
## The angle is Vehicle-free arithmetic in target_angle() (the checks drive it directly).
## DRIVE_DRIFT=0 in the environment turns it all off (the A/B): the car is main's.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## Turned off by DRIVE_DRIFT=0.
static var enabled: bool = OS.get_environment("DRIVE_DRIFT") != "0"

## The handbrake does nothing different below this (m/s): at walking pace it is a brake.
const HB_MIN_SPEED := 4.0
## Grip of the locked axle while the handbrake is held (share of the wheel's own friction_slip).
## Godot's friction_slip IS the sliding friction coefficient (a skidding wheel's side impulse is
## suspension force x friction_slip), and the cars run 10.5 - so a tyre that slides at a share of
## 0.3 still decelerates the car at 3 g. A real drift is a tyre at about mu 0.8: 0.08 of 10.5.
const HB_GRIP := 0.07
## The leading axle's grip in a drift: lowered too, or the steered front, at an angle to the travel,
## scrubs the speed off in a second (share; Mode.SPIN uses HB_GRIP on both).
const FRONT_GRIP := 0.2
## Brake on the locked axle (Godot's brake is an impulse cap per wheel per step).
const HB_LOCK := 60.0
## Slip angle (degrees) the handbrake swings the tail to at full lock (and at no lock: HB_ANGLE_0).
const HB_ANGLE := 42.0
const HB_ANGLE_0 := 18.0
## A handbrake with lock over SPIN_STEER below this speed (m/s) is a 180, not a drift.
const SPIN_SPEED := 17.0
const SPIN_STEER := 0.85
## ... and under this much throttle (forward).
const SPIN_THROTTLE := 0.3
## Yaw rate a 180 / J-turn turns at (rad/s) and how hard it is chased (1/s).
const SPIN_RATE := 4.2
const SPIN_GAIN := 9.0
## A spin stops pushing once the nose is this far round from where it started (degrees).
const SPIN_TURN := 170.0
## Above this slip angle (degrees) a released handbrake carries on as a held drift.
const HOLD_ANGLE := 10.0
## Held drift: the angle with the stick centred, full into the slide, full counter-steer.
const HOLD_BASE := 30.0
const HOLD_MAX := 55.0
const HOLD_MIN := 0.0
## Share of opposite lock that is full counter-steer.
const COUNTER_FULL := 0.5
## Rear grip in a held drift at full throttle; off the throttle it climbs back toward 1.
const HOLD_GRIP := 0.08
## Push along the travel in a drift at full throttle (m/s^2), so a drift keeps its speed.
const DRIFT_PUSH := 9.0
## Slip-angle controller: the slip angle closes on its target at ANGLE_RATE per second (the yaw
## rate that gives is chased at YAW_GAIN, never harder than YAW_MAX_ACC rad/s^2).
const ANGLE_RATE := 3.5
const YAW_GAIN := 12.0
const YAW_MAX_ACC := 30.0
## Under this angle (degrees) or this speed (m/s) a drift ends and the grip comes back.
const EXIT_ANGLE := 7.0
const EXIT_SPEED := 4.0
## Seconds for the grip to come all the way back.
const GRIP_RETURN := 0.5
## The controller works in full from this speed (m/s), and fades below it.
const FULL_SPEED := 10.0
## Rear-driven bodies: torque split to the rear and power oversteer.
const RWD := [Vehicle.BodyType.SPORTS, Vehicle.BodyType.SUPER, Vehicle.BodyType.SPIDER,
	Vehicle.BodyType.HYPER, Vehicle.BodyType.TRACK, Vehicle.BodyType.MUSCLE, Vehicle.BodyType.COUPE,
	Vehicle.BodyType.CLASSIC, Vehicle.BodyType.LOWRIDER_HARDTOP, Vehicle.BodyType.LOWRIDER_COUPE]
## Share of the engine force on the rear wheels of an RWD body (the total is unchanged).
const RWD_REAR := 0.8
## Power oversteer: full throttle and over half lock between these speeds (m/s).
const POWER_MIN_SPEED := 3.0
const POWER_MAX_SPEED := 24.0
const POWER_GRIP := 0.22
const POWER_ANGLE := 25.0

enum Mode { GRIP, HANDBRAKE, SPIN, HOLD, POWER }


## Per-car state, kept on the car's meta "drive_drift".
class State extends RefCounted:
	var mode: int = Mode.GRIP
	var amount: float = 0.0 ## 0 gripping .. 1 fully in a drift (DrivingFX reads it)
	var grip: Array[float] = [1.0, 1.0, 1.0, 1.0] ## share of base grip per wheel, eased
	var base: Array[float] = [0.0, 0.0, 0.0, 0.0] ## the wheel's own friction_slip
	var wrote: Array[float] = [-1.0, -1.0, -1.0, -1.0] ## what we last wrote, to spot others' writes
	var dir: float = 0.0 ## +1 drifting clockwise (turning right, tail out left), -1 the other way
	var prev_beta: float = 0.0
	var prev_travel: float = 0.0 ## heading of the travel last tick
	var spin_from: float = 0.0 ## heading a spin started at
	var spin_sign: float = 0.0
	var active: bool = false


static func state_of(car: Vehicle) -> State:
	if not car.has_meta("drive_drift"): # get_meta(key, null) is an error when it is missing
		return null
	var s: Variant = car.get_meta("drive_drift")
	if s is State:
		return s
	return null


## How far into a drift the car is (0..1) - DrivingFX reads it.
static func amount_of(car: Vehicle) -> float:
	var s := state_of(car)
	return s.amount if s else 0.0


## DrivingFX's smoke share for one tyre: a drift is thick off the rear tyres and thin off the
## front ones (which slide too, at FRONT_GRIP, but a real drift smokes from the back).
static func fx_smoke(car: Vehicle, rear: bool, s: float) -> float:
	var a := amount_of(car)
	if a <= 0.0:
		return s
	return minf(1.0, s * (1.0 + 0.6 * a) + 0.2 * a) if rear else s * (1.0 - 0.6 * a)


static func _ok(car: Vehicle) -> bool:
	return enabled and car.wheels.size() == 4 and not (car is Motorcycle)


static func _is_rear(w: VehicleWheel3D) -> bool:
	return not w.use_as_steering


## Signed slip angle (radians, -PI..PI): + when the travel is to the LEFT of the nose (the car
## rotated clockwise of its travel, which is a right-hand drift with the tail out to the left).
static func slip_angle(car: Vehicle) -> float:
	var v := car.linear_velocity
	v.y = 0.0
	if v.length() < 0.8:
		return 0.0
	var f := -car.global_basis.z
	f.y = 0.0
	if f.length() < 0.01:
		return 0.0
	return f.normalized().signed_angle_to(v.normalized(), Vector3.UP)


## The slip angle a drift steers to (radians, signed like slip_angle()), from the mode, the drift's
## direction and the stick (+ right). Into the slide is the stick toward the drift's turn.
static func target_angle(mode: int, dir: float, steer: float) -> float:
	var into := clampf(steer * dir, -1.0, 1.0)
	var deg := 0.0
	match mode:
		Mode.HANDBRAKE:
			deg = lerpf(HB_ANGLE_0, HB_ANGLE, maxf(into, 0.0))
		Mode.HOLD:
			# Counter-steer is quick: COUNTER_FULL of opposite lock is all the way back to HOLD_MIN.
			deg = HOLD_BASE + (HOLD_MAX - HOLD_BASE) * into if into >= 0.0 \
					else HOLD_BASE + (HOLD_BASE - HOLD_MIN) * maxf(into / COUNTER_FULL, -1.0)
		Mode.POWER:
			deg = POWER_ANGLE * maxf(into, 0.0)
	return dir * deg_to_rad(deg)


## Yaw acceleration (rad/s^2, + turns left) that steers `beta` to `target`. beta = travel heading
## minus nose heading, so with the travel turning at `travel_rate` the nose must turn at
## travel_rate - ANGLE_RATE * (target - beta); `yaw_rate` is what it turns at now.
static func angle_acc(beta: float, target: float, travel_rate: float, yaw_rate: float) -> float:
	var want := travel_rate - ANGLE_RATE * (target - beta)
	return clampf(YAW_GAIN * (want - yaw_rate), -YAW_MAX_ACC, YAW_MAX_ACC)


static func _inertia_y(car: Vehicle) -> float:
	var st := PhysicsServer3D.body_get_direct_state(car.get_rid())
	if st:
		var inv := st.inverse_inertia
		if inv.y > 0.0:
			return 1.0 / inv.y
	return car.mass * 2.3


static func _spin_done(car: Vehicle, s: State) -> bool:
	return rad_to_deg(absf(wrapf(car.global_rotation.y - s.spin_from, -PI, PI))) >= SPIN_TURN


## The parked branch: put every tyre back the moment nobody drives.
static func idle(car: Vehicle) -> void:
	var s := state_of(car)
	if s == null or not s.active:
		return
	for i in mini(car.wheels.size(), 4):
		var w := car.wheels[i]
		if is_instance_valid(w) and s.base[i] > 0.0 and absf(w.wheel_friction_slip - s.wrote[i]) < 0.0001:
			w.wheel_friction_slip = s.base[i]
	s.active = false
	s.mode = Mode.GRIP
	s.amount = 0.0
	s.grip = [1.0, 1.0, 1.0, 1.0]
	s.wrote = [-1.0, -1.0, -1.0, -1.0]


## One tick for a driven car. `input` is Vehicle's stick (x right, y back).
static func step(car: Vehicle, delta: float, input: Vector2, airborne: bool) -> void:
	if not _ok(car):
		return
	var s := state_of(car)
	if s == null:
		s = State.new()
		car.set_meta("drive_drift", s)
	s.active = true
	# The wheels' own grip: whatever else wrote last (a tyre model, flats, a wreck) is the base.
	for i in 4:
		var w := car.wheels[i]
		if not is_instance_valid(w):
			return
		if s.wrote[i] < 0.0 or absf(w.wheel_friction_slip - s.wrote[i]) > 0.0001:
			s.base[i] = w.wheel_friction_slip
	# The raw actions, not `input`: Input.get_vector() clamps the stick to a circle, so W + D on a
	# keyboard reads 0.71 throttle and 0.71 steer, and full throttle with lock could never be told
	# from a part-throttle turn.
	var throttle := clampf(Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"), 0.0, 1.0)
	var steer := clampf(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"), -1.0, 1.0) # + right
	if absf(input.x) > absf(steer):
		steer = clampf(input.x, -1.0, 1.0)
	var hb := Input.is_action_pressed("alt_fire")
	var v := car.linear_velocity
	v.y = 0.0
	var spd := v.length()
	var fwd_speed := car.linear_velocity.dot(-car.global_basis.z)
	var back := fwd_speed < -1.0
	var beta := slip_angle(car)
	var travel := atan2(-v.x, -v.z)
	var travel_rate := wrapf(travel - s.prev_travel, -PI, PI) / maxf(delta, 0.001) if spd > 1.0 and s.mode != Mode.GRIP else 0.0
	s.prev_travel = travel
	s.prev_beta = beta
	var abeta_deg := rad_to_deg(absf(beta))
	var heading := car.global_rotation.y
	var rwd := RWD.has(car.body_type)
	# --- The mode.
	var mode := s.mode
	if airborne:
		mode = Mode.GRIP if s.mode != Mode.SPIN else Mode.SPIN
	elif s.mode == Mode.SPIN and not hb and not _spin_done(car, s) and spd > EXIT_SPEED:
		# A 180 once started finishes, handbrake held or not (a J-turn is a flick, then drive).
		mode = Mode.SPIN
	elif hb and spd > HB_MIN_SPEED:
		# Forward, a 180 is lock and the handbrake OFF the throttle (on it, the same is a tight drift
		# round a hairpin); reversing it is always a J-turn.
		if s.mode == Mode.SPIN or back or (absf(steer) > SPIN_STEER and spd < SPIN_SPEED and throttle < SPIN_THROTTLE):
			if s.mode != Mode.SPIN:
				s.spin_from = heading
				# Forward, right lock turns the nose clockwise (yaw -); reversing, the other way.
				s.spin_sign = -signf(steer) * (-1.0 if back else 1.0)
				if absf(steer) < 0.1:
					s.spin_sign = 0.0
			mode = Mode.SPIN
		else:
			mode = Mode.HANDBRAKE
			if s.mode != Mode.HANDBRAKE and s.mode != Mode.HOLD:
				s.dir = signf(steer) if absf(steer) > 0.1 else signf(beta)
	elif (s.mode == Mode.HANDBRAKE or s.mode == Mode.HOLD) \
			and abeta_deg > HOLD_ANGLE and spd > EXIT_SPEED and not back and throttle > 0.05:
		mode = Mode.HOLD
	elif rwd and throttle > 0.8 and absf(steer) > 0.5 and spd > POWER_MIN_SPEED \
			and spd < POWER_MAX_SPEED and fwd_speed > 0.0:
		if s.mode != Mode.POWER:
			s.dir = signf(steer)
		mode = Mode.POWER
	else:
		mode = Mode.GRIP
	if mode == Mode.HOLD and abeta_deg > 5.0:
		s.dir = signf(beta)
	s.mode = mode
	var target_amount := 0.0
	match mode:
		Mode.HANDBRAKE, Mode.SPIN:
			target_amount = 1.0
		Mode.HOLD:
			target_amount = clampf(0.3 + throttle, 0.0, 1.0)
		Mode.POWER:
			target_amount = clampf((throttle - 0.8) / 0.2, 0.0, 1.0) * clampf((absf(steer) - 0.5) / 0.3, 0.0, 1.0) \
					* clampf((POWER_MAX_SPEED - spd) / 6.0, 0.0, 1.0)
	var rate := 8.0 if target_amount > s.amount else 1.0 / GRIP_RETURN
	s.amount = move_toward(s.amount, target_amount, rate * delta)
	# --- Grip per wheel: the trailing axle goes light.
	var trailing_rear := not back
	for i in 4:
		var w := car.wheels[i]
		var want := 1.0
		if _is_rear(w) == trailing_rear:
			match mode:
				Mode.HANDBRAKE, Mode.SPIN:
					want = HB_GRIP
				Mode.HOLD:
					want = lerpf(1.0, lerpf(0.3, HOLD_GRIP, throttle), s.amount)
				Mode.POWER:
					want = lerpf(1.0, POWER_GRIP, s.amount)
		else:
			match mode:
				Mode.SPIN:
					want = HB_GRIP
				Mode.HANDBRAKE, Mode.HOLD:
					want = lerpf(1.0, FRONT_GRIP, s.amount)
		# Down fast, back up over GRIP_RETURN.
		var r := 12.0 if want < s.grip[i] else 1.0 / GRIP_RETURN
		s.grip[i] = move_toward(s.grip[i], want, r * delta)
		var fs := s.base[i] * s.grip[i]
		w.wheel_friction_slip = fs
		s.wrote[i] = fs
	# --- Engine and brakes per wheel (after Vehicle wrote the body-wide numbers).
	var ef := car.engine_force
	if rwd and ef != 0.0:
		for w in car.wheels:
			w.engine_force = ef * (RWD_REAR if _is_rear(w) else 1.0 - RWD_REAR) * 2.0
	if mode == Mode.HANDBRAKE or mode == Mode.SPIN:
		for w in car.wheels:
			if _is_rear(w) == trailing_rear:
				w.engine_force = 0.0
				w.brake = HB_LOCK
			else:
				# The leading axle pulls on the throttle and rolls free without it.
				w.brake = 0.0
				w.engine_force = ef * 2.0
	if airborne or mode == Mode.GRIP:
		return
	# --- Yaw: the slip-angle controller, or the spin.
	var inertia := _inertia_y(car)
	var spd_k := clampf(spd / FULL_SPEED, 0.0, 1.0)
	var yaw_acc := 0.0
	if mode == Mode.SPIN:
		# Turn at SPIN_RATE until the nose is SPIN_TURN round, then stop the rotation there.
		var want := 0.0 if _spin_done(car, s) or s.spin_sign == 0.0 else s.spin_sign * SPIN_RATE
		yaw_acc = clampf((want - car.angular_velocity.y) * SPIN_GAIN, -40.0, 40.0)
	elif s.dir != 0.0:
		yaw_acc = angle_acc(beta, target_angle(mode, s.dir, steer), travel_rate, car.angular_velocity.y) \
				* spd_k * maxf(s.amount, 0.4)
	if yaw_acc != 0.0:
		# Impulses scaled by the step: VehicleBody3D clears its force accumulator (CLAUDE.md).
		car.apply_torque_impulse(Vector3.UP * yaw_acc * inertia * delta)
	if mode == Mode.HOLD or mode == Mode.POWER:
		if throttle > 0.0 and spd > 1.0 and spd < car.top_speed:
			car.apply_central_impulse(v.normalized() * DRIFT_PUSH * throttle * s.amount * car.mass * delta)
