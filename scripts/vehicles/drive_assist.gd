class_name DriveAssist
extends RefCounted
## Driving assists (wave 9, docs/HANDOFF.md "Driving assists and AI-car parity"):
##
## 1. STABILITY CONTROL for the player's car (`player_tick()`, one hook in
##    Vehicle._physics_process after the pedals and the steering are set). Each physics tick it
##    compares the body's yaw rate with what the steering asks for (a bicycle model: speed x
##    tan(steer) / wheelbase, capped at what the tyres can give, `LAT_LIMIT`) and its slip angle
##    (the angle between where the car points and where it goes). Past `SLIP_START` degrees, or
##    `YAW_MARGIN` rad/s more yaw than asked, it cuts the throttle (traction control, down to
##    `TC_FLOOR` of it) and takes the extra yaw rate out a little at a time (`YAW_CORRECT` rad/s per
##    second at full intervention) - the arcade version of ESP braking one wheel. It stands aside
##    while the handbrake is held, while a drift system says so (meta `drift_active` on the car),
##    and after a handbrake slide until the slide is over (slip back under `RESUME_SLIP`), so a
##    drift you hold with throttle and counter-steer stays a drift. Off in the air and at a crawl.
## 2. ABS-LIKE BRAKING: under the foot brake each steered wheel that starts to slide
##    (VehicleWheel3D.get_skidinfo() under `ABS_SKID`) gets its brake eased (`ABS_RELEASE`), so a
##    car braking hard still turns.
## 3. AI PARITY (`ai_drive()`): the same steering and throttle law for cars the AI drives under
##    physics (PoliceCar._pursue / PoliceChase), replacing a proportional steer at full lock at any
##    speed and a throttle that knew nothing about corners: the lock is limited by speed to what
##    the tyres hold (`AI_LAT`), the yaw rate is damped (`AI_YAW_DAMP`), the speed is held down for
##    a tight heading error (`AI_TURN_SPEED`), and the stability control above runs on it too.
##
## Pure maths in `reference_yaw()`, `slip_angle()`, `intervention()`, `ai_steer_limit()` (the checks
## call them). `DRIVE_ASSIST=0` is the A/B. Probe: tools/drive_assist/probe.tscn.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("DRIVE_ASSIST") != "0"

## Body slip (degrees) where stability control starts and where it is at full strength.
const SLIP_START := 7.0
const SLIP_FULL := 20.0
## Yaw rate over the steering's (rad/s) before stability control acts, and over it for full.
const YAW_MARGIN := 0.3
const YAW_FULL := 1.2
## Lateral acceleration the reference yaw rate is capped at (m/s2). High on purpose: the game's
## tyres hold about 4 g (wheel_grip 10.5), and the assist must never fight a car that grips; the
## cap only keeps the reference finite near standstill. A spin is caught by its slip angle.
const LAT_LIMIT := 45.0
## Share of the throttle kept at full intervention (traction control).
const TC_FLOOR := 0.3
## Yaw rate taken out per second at full intervention (rad/s per s).
const YAW_CORRECT := 6.0
## ROLL STABILITY: past ROLL_START (sine of the body's roll, about 3 degrees) or with a side's
## wheels off the road, the roll rate is pulled toward one that rights the car (ROLL_GAIN rad/s per
## unit of roll) at ROLL_CATCH per second. The game's tyres give ~4 g and the cars' centre of mass
## sits 0.1 m over the axles, so a full-lock corner at 100 km/h used to lift the inside wheels,
## roll the car onto its side and hand it to Vehicle._fly(), which then spun it round: what read as
## a spin was a rollover. It never pushes past upright.
const ROLL_START := 0.05
const ROLL_GAIN := 6.0
const ROLL_CATCH := 14.0
## A spin grows from 10 to 50 degrees of slip in a few tenths of a second, so the slip is judged
## this far ahead (s) at the rate it is growing.
const SLIP_LOOKAHEAD := 0.22
## Below this speed (m/s) nothing is done (donuts on the spot are the player's business).
const MIN_SPEED := 5.0
## After a handbrake slide the assist stays off until the slip is back under this (degrees).
const RESUME_SLIP := 6.0
## ABS: a steered wheel's skid info under this counts as sliding; its brake is eased to this share.
const ABS_SKID := 0.9
const ABS_RELEASE := 0.45

## AI: the lateral acceleration the AI steers to (m/s2), its yaw damping (steering per rad/s of
## yaw rate over the wanted one), the speed it slows to for a heading error of 90 degrees (m/s),
## and its steering gain (steering per radian of heading error).
const AI_LAT := 22.0
const AI_YAW_DAMP := 0.12
const AI_TURN_SPEED := 8.0
const AI_GAIN := 2.0


## The yaw rate the steering asks for (rad/s, positive = left, Godot's +Y): the bicycle model,
## capped at what LAT_LIMIT allows at that speed.
static func reference_yaw(speed: float, steer: float, wheelbase: float) -> float:
	var r := speed * tan(steer) / maxf(wheelbase, 0.5)
	var cap := LAT_LIMIT / maxf(absf(speed), 1.0)
	return clampf(r, -cap, cap)


## Degrees between where the car points and where it goes (positive = sliding to its right).
static func slip_angle(v_long: float, v_side: float) -> float:
	return rad_to_deg(atan2(v_side, maxf(absf(v_long), 0.5)))


## 0..1: how hard stability control steps in for this slip (degrees) and yaw rate (rad/s) against
## the reference.
static func intervention(slip_deg: float, yaw: float, ref_yaw: float) -> float:
	var s := clampf((absf(slip_deg) - SLIP_START) / (SLIP_FULL - SLIP_START), 0.0, 1.0)
	var over := 0.0
	if absf(yaw) > absf(ref_yaw) and (signf(yaw) == signf(ref_yaw) or absf(ref_yaw) < 0.05):
		over = absf(yaw) - absf(ref_yaw)
	elif signf(yaw) != signf(ref_yaw) and absf(ref_yaw) >= 0.05:
		over = absf(yaw) # turning against the wheel: a spin
	var y := clampf((over - YAW_MARGIN) / (YAW_FULL - YAW_MARGIN), 0.0, 1.0)
	return maxf(s, y)


## The most steering (radians) the AI asks for at this speed: what keeps it under AI_LAT.
static func ai_steer_limit(speed: float, wheelbase: float, max_steer: float) -> float:
	var v2 := maxf(speed * speed, 1.0)
	return clampf(atan(AI_LAT * wheelbase / v2), minf(0.08, max_steer), max_steer)


static func wheelbase(car: Vehicle) -> float:
	if car.has_meta("da_wb"):
		return float(car.get_meta("da_wb"))
	var zf := 0.0
	var zr := 0.0
	var nf := 0
	var nr := 0
	for w in car.wheels:
		if w.use_as_steering:
			zf += w.position.z
			nf += 1
		else:
			zr += w.position.z
			nr += 1
	var wb := 2.7
	if nf > 0 and nr > 0:
		wb = clampf(absf(zr / nr - zf / nf), 1.2, 9.0)
	car.set_meta("da_wb", wb)
	return wb


## [forward speed, sideways speed (to the right), yaw rate] in the car's flat frame.
static func motion(car: Vehicle) -> Vector3:
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.05:
		return Vector3.ZERO
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var v := car.linear_velocity
	return Vector3(v.dot(fwd), v.dot(right), car.angular_velocity.y)


## The player's car, once per physics tick after its pedals and steering are set.
static func player_tick(car: Vehicle, delta: float, handbrake: bool) -> void:
	if not enabled:
		return
	if not handbrake:
		_abs(car)
	if handbrake or bool(car.get_meta("drift_active", false)):
		car.set_meta("da_off", true)
		car.set_meta("da_k", 0.0)
		# A drift may slide but never roll the car over.
		if not car.wheels.is_empty() and not car.is_airborne():
			_roll(car, delta)
		return
	_stability(car, delta)


## Stability control (shared by the player and the AI). Returns the intervention 0..1.
static func _stability(car: Vehicle, delta: float) -> float:
	if car.wheels.is_empty() or car.is_airborne():
		car.set_meta("da_k", 0.0)
		return 0.0
	_roll(car, delta)
	var m := motion(car)
	if absf(m.x) < MIN_SPEED or m.x < 0.0:
		car.set_meta("da_off", false)
		car.remove_meta("da_slip")
		car.set_meta("da_k", 0.0)
		return 0.0
	var slip := slip_angle(m.x, m.y)
	var prev := float(car.get_meta("da_slip", slip))
	car.set_meta("da_slip", slip)
	var growing := (slip - prev) / maxf(delta, 0.001)
	if growing * slip > 0.0:
		slip += growing * SLIP_LOOKAHEAD
	if bool(car.get_meta("da_off", false)):
		if absf(slip) > RESUME_SLIP:
			car.set_meta("da_k", 0.0)
			return 0.0
		car.set_meta("da_off", false)
	var ref := reference_yaw(m.x, car.steering, wheelbase(car))
	var k := intervention(slip, m.z, ref)
	car.set_meta("da_k", k)
	if k <= 0.0:
		return 0.0
	if car.engine_force < 0.0:
		car.engine_force *= lerpf(1.0, TC_FLOOR, k)
	var over := absf(m.z) - absf(ref) if signf(m.z) == signf(ref) else absf(m.z)
	if over > 0.0:
		var take := minf(over, YAW_CORRECT * k * delta)
		var av := car.angular_velocity
		av.y -= signf(m.z) * take
		car.angular_velocity = av
	return k


## Roll stability: rights a car tipping in a corner (see ROLL_START).
static func _roll(car: Vehicle, delta: float) -> void:
	var b := car.global_basis
	if b.y.y < 0.3:
		return # already over: Vehicle's own upright torque and the flight code take it
	var roll := b.x.y # > 0: the right side up, rolling to the left
	var lifted := 0
	for w in car.wheels:
		if not w.is_in_contact():
			lifted += 1
	if absf(roll) < ROLL_START and lifted == 0:
		return
	var axis := -b.z # a positive rate about the nose lowers the right side
	var rate := car.angular_velocity.dot(axis)
	var want := roll * ROLL_GAIN
	var diff := want - rate
	# Only ever toward upright: never add roll the car does not already have.
	if diff * roll <= 0.0:
		return
	var step := clampf(diff, -ROLL_CATCH * delta, ROLL_CATCH * delta)
	car.angular_velocity += axis * step
	car.set_meta("da_roll", roll)


## ABS: per wheel, after Vehicle set the brake for every wheel.
static func _abs(car: Vehicle) -> void:
	if car.brake < car.brake_force * 0.9:
		return
	for w in car.wheels:
		var b := car.brake
		if w.use_as_steering and w.is_in_contact() and w.get_skidinfo() < ABS_SKID:
			b *= ABS_RELEASE
		w.brake = b


## The AI's steering and pedals toward a heading error `ang` (radians, positive = target to the
## left) at a wanted speed `want` (m/s). Sets steering, engine_force and brake.
static func ai_drive(car: Vehicle, ang: float, want: float, delta: float, cornering: bool = true) -> void:
	var m := motion(car)
	var speed := m.x
	var wb := wheelbase(car)
	var lim := ai_steer_limit(speed, wb, car.max_steer)
	if not cornering:
		lim = minf(lim * 1.6, car.max_steer) # a chase manoeuvre (PoliceChase) may lean on the tyres
	var target := clampf(ang * AI_GAIN, -lim, lim)
	# Damp the yaw rate toward the one this steering asks for: no fishtailing on the way out.
	var ref := reference_yaw(speed, target, wb)
	target = clampf(target - (m.z - ref) * AI_YAW_DAMP, -lim, lim)
	car.steering = lerpf(car.steering, target, 1.0 - exp(-car.steer_speed * delta))
	# Slow for a big heading error: a corner is taken at a speed the lock can hold.
	var turn := clampf(absf(ang) / (PI * 0.5), 0.0, 1.0) if cornering else 0.0
	var v := minf(want, lerpf(want, AI_TURN_SPEED, turn))
	if speed < v:
		var push := clampf((v - speed) / 6.0, 0.25, 1.0)
		car.engine_force = -car.engine_power * push
		car.brake = 0.0
	else:
		car.engine_force = 0.0
		car.brake = car.brake_force * clampf((speed - v) / 6.0, 0.15, 1.0)
	if not enabled:
		return
	_stability(car, delta)
