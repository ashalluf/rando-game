class_name DriveTrain
extends RefCounted
## The player-driven car's engine and gearbox (wave 9, "drive-engine"; docs/HANDOFF.md "The drive
## train"). It replaces Vehicle's flat `engine_power * (1 - v / top_speed)` push, which pulled the
## same 7,000 N per wheel out of every body (a bus launched like a sedan, a hypercar topped out at
## the sedan's 55 m/s) and faded the pull to nothing long before the top speed.
##
## A torque curve through a real gearbox, per CLASS of body (SPECS, `class_of()`), arcade-realism
## and a little exaggerated (an overpowered chaos game):
##   * power is per kilogram (`pkw`, W/kg at the peak), so whatever mass another system gives a
##     body, a class keeps its pull;
##   * the gears are EngineAudio's (`gear_k()`: geometric between the speed first gear tops out at
##     and the speed top gear reaches near the redline), and the gear and revs ARE EngineAudio's
##     `step_engine()` run on this car's own state - the engine voice reads that state
##     (`state_of()`), so the sound and the pull never disagree;
##   * force at the wheels F = P_peak * torque(x) * k / (m * redline), x = rpm / redline, k = rpm per
##     m/s in the gear, m = max over x of torque(x) * x (so P_peak is the peak power exactly);
##   * pulling away the clutch slips at `launch` of the redline, capped by `grip` g (a launch the
##     tyres can put down; the rest of the class's pull is at the top of each gear);
##   * a shift cuts the pull to SHIFT_PULL for EngineAudio's 0.24 s;
##   * drag is solved per car so full throttle in top gear balances it at exactly `top` m/s;
##   * off the throttle: engine braking by revs and gear plus rolling resistance, through the wheels'
##     `brake` (Godot's brake is a rolling-friction impulse that only resists motion);
##   * reverse: its own gear, `rev_top` m/s;
##   * boost (nitro): `BOOST_TORQUE` x the torque, drag x `BOOST_DRAG`, the top gear's limiter off.
## Only while the PLAYER drives (Vehicle._physics_process / Motorcycle._physics_process call
## drive() after their throttle lines); traffic, police and parked cars are untouched.
## `DRIVETRAIN=0` in the environment is the A/B (the old push). Probe: tools/drive_engine/probe.tscn.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## Off with DRIVETRAIN=0.
static var enabled: bool = OS.get_environment("DRIVETRAIN") != "0"

## Per class: prof (EngineAudio profile: rpm table, redline, gears), pkw (peak W per kg), top
## (m/s, drag-limited top speed), first (m/s first gear reaches at 90 % of the redline), gtop (m/s
## top gear reaches at 92 % of the redline), grip (launch cap, g), launch (clutch-slip rpm, share of
## the redline), xp (torque peak, share of the redline), eb (engine braking at the redline in first,
## m/s2), rev_top (m/s).
const SPECS := {
	"compact": {"prof": "four", "pkw": 165.0, "top": 50.0, "first": 12.0, "gtop": 49.0, "grip": 0.78,
		"launch": 0.5, "xp": 0.55, "eb": 1.8, "rev_top": 11.0},
	"sedan": {"prof": "four", "pkw": 190.0, "top": 54.0, "first": 13.0, "gtop": 53.0, "grip": 0.82,
		"launch": 0.5, "xp": 0.55, "eb": 1.8, "rev_top": 11.0},
	"lux": {"prof": "v8", "pkw": 250.0, "top": 63.0, "first": 15.0, "gtop": 62.0, "grip": 0.9,
		"launch": 0.45, "xp": 0.5, "eb": 2.0, "rev_top": 12.0},
	"truck": {"prof": "v8", "pkw": 175.0, "top": 52.0, "first": 13.0, "gtop": 51.0, "grip": 0.78,
		"launch": 0.42, "xp": 0.45, "eb": 2.2, "rev_top": 11.0},
	"van": {"prof": "four", "pkw": 125.0, "top": 44.0, "first": 10.5, "gtop": 43.0, "grip": 0.66,
		"launch": 0.48, "xp": 0.5, "eb": 1.8, "rev_top": 9.0},
	"muscle": {"prof": "v8", "pkw": 330.0, "top": 70.0, "first": 17.0, "gtop": 68.0, "grip": 1.0,
		"launch": 0.45, "xp": 0.45, "eb": 2.4, "rev_top": 13.0},
	"super": {"prof": "v12", "pkw": 480.0, "top": 90.0, "first": 21.0, "gtop": 88.0, "grip": 1.2,
		"launch": 0.48, "xp": 0.65, "eb": 2.6, "rev_top": 14.0},
	"hyper": {"prof": "v12", "pkw": 640.0, "top": 104.0, "first": 23.0, "gtop": 101.0, "grip": 1.35,
		"launch": 0.48, "xp": 0.65, "eb": 2.8, "rev_top": 14.0},
	"lowrider": {"prof": "v8", "pkw": 150.0, "top": 47.0, "first": 13.0, "gtop": 46.0, "grip": 0.7,
		"launch": 0.4, "xp": 0.4, "eb": 1.8, "rev_top": 10.0},
	"police": {"prof": "v8", "pkw": 270.0, "top": 66.0, "first": 15.0, "gtop": 65.0, "grip": 0.92,
		"launch": 0.45, "xp": 0.48, "eb": 2.2, "rev_top": 12.0},
	"medium": {"prof": "diesel", "pkw": 90.0, "top": 37.0, "first": 5.0, "gtop": 36.0, "grip": 0.5,
		"launch": 0.4, "xp": 0.35, "eb": 1.4, "rev_top": 8.0},
	"heavy": {"prof": "diesel", "pkw": 62.0, "top": 32.0, "first": 4.0, "gtop": 31.0, "grip": 0.38,
		"launch": 0.42, "xp": 0.35, "eb": 1.2, "rev_top": 6.0},
	"bus": {"prof": "bus", "pkw": 55.0, "top": 28.0, "first": 5.0, "gtop": 27.0, "grip": 0.36,
		"launch": 0.4, "xp": 0.35, "eb": 1.1, "rev_top": 6.0},
	"moto_sport": {"prof": "moto", "pkw": 620.0, "top": 76.0, "first": 17.0, "gtop": 74.0, "grip": 1.05,
		"launch": 0.5, "xp": 0.7, "eb": 2.6, "rev_top": 4.0},
	"moto_cruiser": {"prof": "moto", "pkw": 290.0, "top": 56.0, "first": 14.0, "gtop": 55.0, "grip": 0.8,
		"launch": 0.4, "xp": 0.4, "eb": 2.4, "rev_top": 4.0},
	"moto_scooter": {"prof": "moto", "pkw": 160.0, "top": 29.0, "first": 8.0, "gtop": 28.5, "grip": 0.6,
		"launch": 0.55, "xp": 0.6, "eb": 1.6, "rev_top": 3.0},
}

## Pull left through a gear change (EngineAudio's 0.24 s throttle cut).
const SHIFT_PULL := 0.35
## Nitro: torque gain, drag share (and the top gear's limiter is off).
const BOOST_TORQUE := 2.6
const BOOST_DRAG := 0.4
## Nitro: how much more launch the tyres are allowed (the grip cap times this).
const BOOST_GRIP := 1.9
## Share of the drag felt off the throttle (the pull is exaggerated, so the drag that balances it
## is too: lifting at 190 km/h at full drag was a 6.5 m/s2 slow-down, half a brake).
const COAST_DRAG := 0.5
## Rolling resistance (share of g).
const ROLL_RESIST := 0.014
## Below this speed with nothing pressed the car is held (m/s; Godot's brake impulse).
const HOLD_SPEED := 0.6


## The class of a car (a key of SPECS).
static func class_of(car: Vehicle) -> String:
	if car.is_in_group("police_car"):
		return "police"
	match car.body_type:
		Vehicle.BodyType.HATCHBACK, Vehicle.BodyType.EV_HATCH, Vehicle.BodyType.BEATER:
			return "compact"
		Vehicle.BodyType.LUX_SEDAN, Vehicle.BodyType.LUX_SUV, Vehicle.BodyType.COUPE:
			return "lux"
		Vehicle.BodyType.PICKUP, Vehicle.BodyType.SUV, Vehicle.BodyType.WORK_TRUCK, Vehicle.BodyType.CLASSIC:
			return "truck"
		Vehicle.BodyType.VAN, Vehicle.BodyType.DELIVERY_VAN, Vehicle.BodyType.KEI_VAN:
			return "van"
		Vehicle.BodyType.SPORTS, Vehicle.BodyType.MUSCLE:
			return "muscle"
		Vehicle.BodyType.SUPER, Vehicle.BodyType.SPIDER:
			return "super"
		Vehicle.BodyType.HYPER, Vehicle.BodyType.TRACK:
			return "hyper"
		Vehicle.BodyType.LOWRIDER_HARDTOP, Vehicle.BodyType.LOWRIDER_COUPE:
			return "lowrider"
		Vehicle.BodyType.AMBULANCE, Vehicle.BodyType.ICE_CREAM_TRUCK, Vehicle.BodyType.TOW_TRUCK:
			return "medium"
		Vehicle.BodyType.BOX_TRUCK, Vehicle.BodyType.SEMI, Vehicle.BodyType.FIRE_ENGINE, \
				Vehicle.BodyType.GARBAGE_TRUCK, Vehicle.BodyType.STREET_SWEEPER:
			return "heavy"
		Vehicle.BodyType.BUS, Vehicle.BodyType.SCHOOL_BUS:
			return "bus"
		Vehicle.BodyType.MOTO_SPORT:
			return "moto_sport"
		Vehicle.BodyType.MOTO_CRUISER:
			return "moto_cruiser"
		Vehicle.BodyType.MOTO_SCOOTER:
			return "moto_scooter"
	return "sedan"


## The gearbox profile of a spec: EngineAudio's profile with the spec's first / top gear speeds.
static func profile(spec: Dictionary) -> Dictionary:
	var p: Dictionary = (EngineAudio.PROFILES[spec.prof] as Dictionary).duplicate()
	p.first = float(spec.first)
	p.top = float(spec.gtop)
	return p


## Torque at x = rpm / redline, 1 at the peak (pure).
static func torque(x: float, xp: float) -> float:
	var t := lerpf(0.6, 1.0, smoothstep(0.1, xp, x))
	if x > 0.82:
		t *= lerpf(1.0, 0.8, clampf((x - 0.82) / 0.18, 0.0, 1.0))
	return t


## max over x of torque(x) * x: P_peak = T_peak * that * redline (pure, sampled).
static func power_peak_x(xp: float) -> float:
	var best := 0.0
	for i in 101:
		var x := float(i) / 100.0
		best = maxf(best, torque(x, xp) * x)
	return best


## Full-throttle force at the wheels per kilogram (N/kg = m/s2) at `speed` in gear `g` (pure; no
## drag, no shift cut). `boost` the nitro.
static func pull(spec: Dictionary, prof: Dictionary, g: int, speed: float, boost: bool = false) -> float:
	var red := float(prof.redline)
	var k := EngineAudio.gear_k(prof, g)
	var x := speed * k / red
	var n := int(prof.gears)
	var launch := float(spec.launch)
	if g == 0 and x < launch:
		x = launch # the clutch slips
	var over := 1.0 if (boost and g == n - 1) else 1.0
	if x > 1.0:
		if not (boost and g == n - 1):
			return 0.0 # the limiter
		over = clampf(1.0 - (x - 1.0) * 2.0, 0.0, 1.0) # nitro runs on past it, fading
		x = 1.0
	var a := float(spec.pkw) * torque(x, float(spec.xp)) * k / (power_peak_x(float(spec.xp)) * red) * over
	if boost:
		a *= BOOST_TORQUE
	var cap := float(spec.grip) * 9.8 * (BOOST_GRIP if boost else 1.0)
	return minf(a, cap)


## Drag coefficient per kilogram (1/m) that balances full throttle at the spec's top speed in the
## best gear there (pure).
static func drag_for(spec: Dictionary, prof: Dictionary) -> float:
	var v := float(spec.top)
	var best := 0.0
	for g in int(prof.gears):
		best = maxf(best, pull(spec, prof, g, v))
	return maxf(best - ROLL_RESIST * 9.8, 0.05) / (v * v)


## A fresh per-car state: EngineAudio's state keys plus the spec and its numbers.
static func new_state(car: Vehicle) -> Dictionary:
	var cls := class_of(car)
	var spec: Dictionary = SPECS[cls]
	var prof := profile(spec)
	var st := EngineAudio.new_state(prof)
	st.cls = cls
	st.spec = spec
	st.prof = prof
	st.drag = drag_for(spec, prof)
	st.base_power = car.engine_power
	st.force = 0.0
	st.throttle = 0.0
	return st


## This car's drive-train state (null when none has run): EngineAudio's voice reads it.
static func state_of(car: Object) -> Variant:
	if car == null or not is_instance_valid(car) or not car.has_meta("drive_train"):
		return null
	return car.get_meta("drive_train")


## True when the engine voice should read this car's state rather than step its own.
static func feeds(car: Object) -> bool:
	return enabled and state_of(car) != null and (car as Vehicle).driver != null


## From Vehicle's driver setter: put engine_power back when the player gets out.
static func driver_changed(car: Vehicle, who: Node3D) -> void:
	if who == null and car.has_meta("drive_train"):
		var st: Dictionary = car.get_meta("drive_train")
		car.engine_power = float(st.base_power)
		car.remove_meta("drive_train")


## One physics tick of the player's car, after Vehicle's own throttle lines (which it overrides):
## `throttle` -1..1 (forward positive), `speed` m/s along the nose, `boost` nitro held.
## Writes engine_force and brake (it leaves a hard brake - reversing the stick at speed - alone).
static func drive(car: Vehicle, throttle: float, speed: float, boost: bool, delta: float) -> void:
	if not enabled or not (car.driver is Player or car.has_meta("drive_train_test")):
		return
	var st: Dictionary
	if car.has_meta("drive_train"):
		st = car.get_meta("drive_train")
	else:
		st = new_state(car)
		car.set_meta("drive_train", st)
	var spec: Dictionary = st.spec
	var prof: Dictionary = st.prof
	var n_drive := 0
	for w in car.wheels:
		if w.use_as_traction:
			n_drive += 1
	n_drive = maxi(n_drive, 1)
	var grounded := not car.is_airborne()
	var th := clampf(throttle, 0.0, 1.0)
	var fwd_speed := maxf(speed, 0.0)
	# Gear and revs: EngineAudio's own step on this car's state (the voice reads the same state).
	EngineAudio.step_engine(st, prof, fwd_speed, th, not grounded, boost and th > 0.0, delta)
	st.throttle = th
	var g := int(st.gear)
	var mass := car.mass
	# Godot damps every body's velocity (the project's 0.1 plus the car's own 0.05: 4.5 m/s2 at
	# 30 m/s, which held the old car to 146 km/h). The drive train's drag is the car's whole air
	# resistance, so the damping is handed back on the ground.
	var damp := damping(car) * absf(speed) if grounded else 0.0
	if throttle > 0.0:
		var a := pull(spec, prof, g, fwd_speed, boost) * th
		if float(st.shift_t) > 0.0:
			a *= SHIFT_PULL
		var drag := float(st.drag) * (BOOST_DRAG if boost else 1.0) * fwd_speed * fwd_speed
		a -= drag + ROLL_RESIST * 9.8
		a += damp
		var f := a * mass / float(n_drive)
		# engine_power is what DrivingFX reads the pedal against: full throttle here and now.
		car.engine_power = maxf(pull(spec, prof, g, fwd_speed) * mass / float(n_drive), 1.0)
		car.engine_force = -f # Godot pushes toward +Z, the tail
		car.brake = 0.0
		if a < 0.0:
			car.engine_force = 0.0
			car.brake = -a * mass / float(n_drive) * delta
		st.force = f
	elif throttle < 0.0 and speed <= 1.0:
		# Reverse: its own gear, a gentle launch, `rev_top` m/s.
		var rv := maxf(-speed, 0.0)
		var rev_top := float(spec.rev_top)
		var a := float(spec.grip) * 9.8 * 0.55 * (-throttle) * clampf(1.0 - pow(rv / rev_top, 2.0), 0.0, 1.0)
		a += damp * (-throttle)
		car.engine_force = a * mass / float(n_drive)
		car.brake = 0.0
		st.force = -a * mass / float(n_drive)
	elif throttle < 0.0:
		st.force = 0.0 # the brakes (Vehicle's own lines)
	else:
		# Off the throttle: engine braking by revs in the gear, rolling resistance, drag.
		var x := clampf(fwd_speed * EngineAudio.gear_k(prof, g) / float(prof.redline), 0.0, 1.0)
		var a := float(spec.eb) * x * x * (1.0 if grounded else 0.0)
		a += ROLL_RESIST * 9.8 + float(st.drag) * COAST_DRAG * speed * speed
		a -= damp
		car.engine_force = 0.0
		car.brake = maxf(a, 0.0) * mass / float(n_drive) * delta
		if a < 0.0 and speed > 1.0:
			# Less slow-down wanted than the damping gives: the difference rolls on.
			car.engine_force = a * mass / float(n_drive)
		if absf(speed) < HOLD_SPEED:
			car.brake = maxf(car.brake, 1.0)
		st.force = 0.0


## The body's total linear damping per second (the project's default combined with its own).
static func damping(car: Vehicle) -> float:
	var ds := PhysicsServer3D.body_get_direct_state(car.get_rid())
	return ds.total_linear_damp if ds != null else car.linear_damp + 0.1


## A straight-line run of a class on flat ground (pure: the same pull, gearbox and drag as drive(),
## no tyres): {t60, t100, top, shifts}. `seconds` of full throttle at 60 Hz.
static func simulate(cls: String, seconds: float = 40.0, boost: bool = false) -> Dictionary:
	var spec: Dictionary = SPECS[cls]
	var prof := profile(spec)
	var st := EngineAudio.new_state(prof)
	var drag := drag_for(spec, prof)
	var v := 0.0
	var t := 0.0
	var dt := 1.0 / 60.0
	var out := {"t60": -1.0, "t100": -1.0, "top": 0.0, "shifts": 0}
	while t < seconds:
		EngineAudio.step_engine(st, prof, v, 1.0, false, boost, dt)
		var a := pull(spec, prof, int(st.gear), v, boost)
		if float(st.shift_t) > 0.0:
			a *= SHIFT_PULL
		a -= drag * (BOOST_DRAG if boost else 1.0) * v * v + ROLL_RESIST * 9.8
		v = maxf(v + a * dt, 0.0)
		t += dt
		if out.t60 < 0.0 and v * 3.6 >= 60.0:
			out.t60 = t
		if out.t100 < 0.0 and v * 3.6 >= 100.0:
			out.t100 = t
		out.top = maxf(float(out.top), v)
	out.shifts = int(st.shifts)
	return out
