class_name DriveSuspension
extends Node
## Suspension and weight for the PLAYER-DRIVEN car (docs/HANDOFF.md "Suspension and weight").
## One hook: Vehicle's driver setter calls driver_changed(). The first time somebody takes the
## wheel the car is re-sprung once, by class (PROFILES), and a DriveSuspension node is added that
## runs while it is driven:
##
## * Springs by FREQUENCY, dampers by DAMPING RATIO. Godot's VehicleBody3D multiplies a wheel's
##   spring and damper by the chassis mass, so suspension_stiffness k is an acceleration per metre
##   per wheel: four wheels heave at 2*sqrt(k) rad/s, f = sqrt(k) / PI Hz, and a damper c gives a
##   heave damping ratio c / sqrt(k). The old numbers (k 60, c 0.8 / 1.2) were a 2.5 Hz spring at
##   ratio 0.10 / 0.15: stiff and barely damped, so a dropped car bounced five times for three
##   seconds and a hard stop hardly dipped the nose.
## * The ride height is KEPT: a softer spring sags more, so the rest length grows by the extra sag
##   (and the travel with it, so the bump stop is where it was). The visible wheels, the body
##   model and every check that measures the ride see the same car standing still.
## * Centre of mass raised to a real car's height over the road (more pitch under brakes and
##   throttle), while the tyres' side force is applied at ROLL_LEVER under it (wheel_roll_influence,
##   which Godot measures from the body's origin, may go negative for that): the car rolls in a
##   corner but its rollover threshold stays far above any grip it can make.
## * Anti-roll bars in code: per axle, the difference in compression between the two wheels
##   pushes the compressed side up and the other down, by ARB x mass. They cut the roll and keep
##   the inside wheels down; off the ground they do nothing.
## * A roll guard: past GUARD_ROLL degrees with the wheels on one side off the road, the roll rate
##   toward the outside is bled away (never a flip in an ordinary corner; a ramp or a crash still
##   throws it).
## * The body LEANS on top of that (the BodyModel holder and NightLights, as TrafficMotion moves a
##   traffic car's): a sprung roll and pitch from the car's own measured acceleration, saturating
##   at LEAN_ROLL_MAX / LEAN_PITCH_MAX. The physics stays safe whatever grip the tyres make; what
##   the eye reads is a car that dives, squats and leans. Not on lowriders (their hydraulics own
##   the body) or anything TrafficMotion.supported() refuses. DRIVE_LEAN=0 turns this part off.
## * Kerbs: the wheels are rays and climb any step their travel takes, but the body's collision box
##   has square lower edges, and on a kerb taller than the bump room (or a low sports car on any
##   kerb, at an angle) its edge caught the kerb's and stopped the car dead and slewed it. Any
##   contact of the body with the world under KERB_HEIGHT over the road, facing the travel, is
##   taken as a step: that corner is lifted (KERB_LIFT, capped) and the speed the contact took is
##   handed back (KERB_KEEP of it). Walls (taller) are left alone. DRIVE_KERB=0 turns it off.
## DRIVE_SUSPENSION=0 is the A/B (the car keeps the old springs). Probe: tools/drive_weight/probe.tscn.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("DRIVE_SUSPENSION") != "0"

## Per class: spring frequency (Hz), compression and rebound damping ratios, the centre of mass
## over the road (m), the lever of the tyres' side force under it (m), the anti-roll bars (front,
## rear; acceleration per metre of compression difference).
const PROFILES := {
	"sport": {"f": 1.9, "zc": 0.34, "zr": 0.62, "com": 0.40, "lever": 0.09, "arb": Vector2(26.0, 18.0)},
	"car": {"f": 1.55, "zc": 0.30, "zr": 0.55, "com": 0.46, "lever": 0.12, "arb": Vector2(22.0, 14.0)},
	"tall": {"f": 1.6, "zc": 0.32, "zr": 0.58, "com": 0.48, "lever": 0.12, "arb": Vector2(28.0, 18.0)},
	"truck": {"f": 1.45, "zc": 0.32, "zr": 0.55, "com": 0.55, "lever": 0.13, "arb": Vector2(26.0, 18.0)},
	"big": {"f": 1.3, "zc": 0.32, "zr": 0.55, "com": 0.85, "lever": 0.17, "arb": Vector2(26.0, 22.0)},
	"low": {"f": 1.35, "zc": 0.28, "zr": 0.52, "com": 0.42, "lever": 0.09, "arb": Vector2(30.0, 20.0)},
}
static var lean_enabled: bool = OS.get_environment("DRIVE_LEAN") != "0"

## The drawn body's lean: degrees of roll / pitch per g of lateral / longitudinal acceleration,
## its limits (tanh-saturated), the spring (Hz, damping ratio), the pivot over the road (m).
const LEAN_ROLL_PER_G := 2.2
const LEAN_PITCH_PER_G := 1.25
const LEAN_ROLL_MAX := 3.5
const LEAN_PITCH_MAX := 2.1
const LEAN_HZ := 1.7
const LEAN_ZETA := 0.42
const LEAN_PIVOT := 0.45
## Acceleration measured over one tick is clamped (a crash or a landing is not a lean) and
## smoothed over about 1 / LEAN_SMOOTH s.
const LEAN_ACCEL_CLAMP := 30.0
const LEAN_SMOOTH := 10.0

static var kerb_enabled: bool = OS.get_environment("DRIVE_KERB") != "0"

## A body contact this low over the road (m, at the contact) is a step, not a wall.
const KERB_HEIGHT := 0.42
## Upward speed given to the corner on a step (m/s at most), and the share of the speed the
## contact took that is handed back along the travel.
const KERB_LIFT := 1.6
const KERB_KEEP := 1.0
## Not below this speed (parking against a kerb is not climbing it).
const KERB_MIN_SPEED := 1.2

const GUARD_ROLL := 14.0
## How hard the roll guard bleeds roll rate (per second).
const GUARD_RATE := 9.0

var car: Vehicle
var profile: Dictionary = {}
## Per wheel: the chassis connection point's height (local) - the hub's position at zero length.
var _conn_y: PackedFloat32Array = PackedFloat32Array()
var _rest: PackedFloat32Array = PackedFloat32Array()
var _body: Node3D
var _lights: Node3D
var _body_rest := Transform3D.IDENTITY
var _lights_rest := Transform3D.IDENTITY
var _pivot := Vector3.ZERO
var _last_v := Vector3.INF
## Smoothed acceleration in the car's frame: x right, y forward (m/s^2).
var acc := Vector2.ZERO
## The drawn lean (degrees: roll + right side up, pitch + nose up) and its rates.
var lean := Vector2.ZERO
var _lean_v := Vector2.ZERO
var _written := Vector2(INF, INF)
var _road_y: float = -0.2
var _v_prev := Vector3.ZERO
## Steps climbed (the checks and the probe read it).
var kerb_steps: int = 0


static func class_of(type: int) -> String:
	match type:
		Vehicle.BodyType.SPORTS, Vehicle.BodyType.SUPER, Vehicle.BodyType.SPIDER, Vehicle.BodyType.HYPER, \
				Vehicle.BodyType.TRACK, Vehicle.BodyType.COUPE, Vehicle.BodyType.MUSCLE:
			return "sport"
		Vehicle.BodyType.CROSSOVER, Vehicle.BodyType.SUV, Vehicle.BodyType.MINIVAN, Vehicle.BodyType.COMPACT_SUV, \
				Vehicle.BodyType.LUX_SUV, Vehicle.BodyType.KEI_VAN:
			return "tall"
		Vehicle.BodyType.PICKUP, Vehicle.BodyType.VAN, Vehicle.BodyType.WORK_TRUCK, Vehicle.BodyType.DELIVERY_VAN, \
				Vehicle.BodyType.AMBULANCE:
			return "truck"
		Vehicle.BodyType.LOWRIDER_HARDTOP, Vehicle.BodyType.LOWRIDER_COUPE:
			return "low"
	if BigVehicles.is_big(type):
		return "big"
	return "car"


## Vehicle's driver setter (the one hook).
static func driver_changed(c: Vehicle, who: Node3D) -> void:
	if not enabled or c == null or not c.is_inside_tree():
		return
	var ds := c.get_node_or_null(^"DriveSuspension") as DriveSuspension
	if who == null:
		if ds != null:
			ds.set_physics_process(false)
			ds.rest()
		return
	if c is Motorcycle or c is Aircraft or c is FlyableHeli or c is Boat or c.wheels.size() != 4:
		return
	if ds == null:
		ds = DriveSuspension.new()
		ds.name = "DriveSuspension"
		c.add_child(ds)
		ds.setup(c)
	ds.set_physics_process(true)


## Pure: the new wheel numbers from the old ones, for one profile. Keeps the ride height (the rest
## length grows by the extra sag) and the bump stop (the travel grows by the same).
static func tuned(old: Dictionary, prof: Dictionary) -> Dictionary:
	var k: float = PI * PI * float(prof.f) * float(prof.f)
	var g := 9.8
	var sag_old := g / (4.0 * maxf(float(old.k), 0.01))
	var sag_new := g / (4.0 * k)
	var grow := sag_new - sag_old
	return {
		"k": k,
		"rest": float(old.rest) + grow,
		"travel": float(old.travel) + grow,
		"comp": float(prof.zc) * sqrt(k),
		"reb": float(prof.zr) * sqrt(k),
	}


func setup(c: Vehicle) -> void:
	car = c
	profile = PROFILES[class_of(c.body_type)]
	var old := {"k": c.suspension_stiffness, "rest": c.suspension_rest_length, "travel": c.suspension_travel}
	var t := tuned(old, profile)
	# Road level in the car's own frame, from where the hubs stand now (a settled car: the slot's
	# height less its compressed length; rest length less the old sag, less the tyre).
	var sag_old := 9.8 / (4.0 * maxf(c.suspension_stiffness, 0.01))
	var road_y := 0.0
	_conn_y.resize(4)
	_rest.resize(4)
	for i in 4:
		var w := c.wheels[i]
		var slot_y: float = (c._wheel_slots[i][0] as Vector3).y if i < c._wheel_slots.size() else w.position.y + c.suspension_rest_length
		_conn_y[i] = slot_y
		road_y += slot_y - (c.suspension_rest_length - sag_old) - w.wheel_radius
	road_y /= 4.0
	c.suspension_stiffness = t.k
	c.suspension_rest_length = t.rest
	c.suspension_travel = t.travel
	c.damping_compression = t.comp
	c.damping_relaxation = t.reb
	_road_y = road_y
	var com_y := road_y + float(profile.com)
	# Side force applied at roll_influence x road_y (Godot measures it from the origin).
	var ri := (com_y - float(profile.lever)) / road_y if absf(road_y) > 0.01 else c.wheel_roll_influence
	c.wheel_roll_influence = ri
	for i in 4:
		var w := c.wheels[i]
		w.suspension_stiffness = t.k
		w.wheel_rest_length = t.rest
		w.suspension_travel = t.travel
		w.damping_compression = t.comp
		w.damping_relaxation = t.reb
		w.wheel_roll_influence = ri
		_rest[i] = t.rest
	var com := c.center_of_mass
	c.center_of_mass = Vector3(com.x, com_y, com.z)
	c.set_meta("drive_suspension", {"road_y": road_y, "com_y": com_y, "ri": ri, "k": t.k})
	if lean_enabled and TrafficMotion.supported(c):
		_body = c.get_node_or_null(^"BodyModel") as Node3D
		_lights = c.get_node_or_null(^"NightLights") as Node3D
		if _body != null:
			_body_rest = _body.transform
		if _lights != null:
			_lights_rest = _lights.transform
		var zf := 0.0
		var zr := 0.0
		for i in 4:
			if i < 2:
				zf += c.wheels[i].position.z
			else:
				zr += c.wheels[i].position.z
		_pivot = Vector3(0.0, road_y + LEAN_PIVOT, (zf + zr) * 0.25)


## Compression of wheel i in metres (0 at full droop or off the ground).
func compression(i: int) -> float:
	var w := car.wheels[i]
	if not w.is_in_contact():
		return 0.0
	var length := _conn_y[i] - w.position.y
	return clampf(_rest[i] - length, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if car == null or car.wheels.size() != 4 or car.freeze:
		return
	var arb: Vector2 = profile.arb
	var m := car.mass
	var up := car.global_basis.y
	var origin := car.global_position
	# Wheels 0, 1 the front pair (left, right), 2, 3 the rear (Vehicle._build's slot order).
	for axle in 2:
		var a := axle * 2
		var b := a + 1
		var wa := car.wheels[a]
		var wb := car.wheels[b]
		if not (wa.is_in_contact() and wb.is_in_contact()):
			continue
		var diff := compression(a) - compression(b)
		var f := (arb.x if axle == 0 else arb.y) * diff * m * delta
		if absf(f) < 1e-5:
			continue
		car.apply_impulse(up * f, wa.global_position - origin)
		car.apply_impulse(-up * f, wb.global_position - origin)
	_guard(delta)
	_kerb()
	_lean(delta)


## A body contact with a step under KERB_HEIGHT: lift that corner and give back the speed it took.
func _kerb() -> void:
	var v := car.linear_velocity
	var v_was := _v_prev
	_v_prev = v
	if not kerb_enabled:
		return
	if not car.contact_monitor:
		car.contact_monitor = true
	if car.max_contacts_reported < 4:
		car.max_contacts_reported = 4
	var hv := Vector3(v_was.x, 0.0, v_was.z)
	if hv.length() < KERB_MIN_SPEED or car.global_basis.y.y < 0.7:
		return
	var st := PhysicsServer3D.body_get_direct_state(car.get_rid())
	if st == null:
		return
	var n := st.get_contact_count()
	var hit := false
	var lift_at := Vector3.INF
	for i in n:
		var other := st.get_contact_collider_object(i)
		if not (other is StaticBody3D):
			continue
		var p := st.get_contact_local_position(i)
		var lp := car.to_local(p)
		if lp.y - _road_y > KERB_HEIGHT:
			continue
		# The underbody on a step: a scrape over its edge (the normal up) or the edge in the way
		# (the normal back against the travel). Either way it is not a wall.
		hit = true
		var nrm := st.get_contact_local_normal(i)
		var flat := Vector3(nrm.x, 0.0, nrm.z)
		if flat.length() > 0.25 and flat.normalized().dot(hv.normalized()) < -0.2:
			lift_at = p
	if not hit:
		return
	kerb_steps += 1
	var m := car.mass
	if lift_at != Vector3.INF:
		var lift := clampf(KERB_LIFT - maxf(car.linear_velocity.y, 0.0), 0.0, KERB_LIFT)
		car.apply_impulse(Vector3.UP * lift * m * 0.5, lift_at - car.global_position)
	var hv_now := Vector3(v.x, 0.0, v.z)
	var lost := hv.length() - hv_now.dot(hv.normalized())
	if lost > 0.0:
		car.apply_central_impulse(hv.normalized() * lost * KERB_KEEP * m)
	car.hold_crash_watch(2)


## Pure: one step of a critically-ish damped spring toward `target` (x, v), sub-stepped so a slow
## frame cannot blow it up.
static func spring(x: float, v: float, target: float, hz: float, zeta: float, dt: float) -> Vector2:
	var w := TAU * hz
	var n := maxi(1, ceili(dt / (1.0 / 120.0)))
	var h := dt / float(n)
	for i in n:
		v += ((target - x) * w * w - v * 2.0 * zeta * w) * h
		x += v * h
	return Vector2(x, v)


## Pure: the lean the body wants for an acceleration in the car's frame (x right, y forward;
## m/s^2): Vector2(roll, pitch) in degrees. Cornering right (acceleration toward +x) rolls the
## body out to the left (right side up, +roll); braking (y < 0) dips the nose (-pitch).
static func lean_for(a: Vector2) -> Vector2:
	var roll := LEAN_ROLL_MAX * tanh(a.x / 9.8 * LEAN_ROLL_PER_G / LEAN_ROLL_MAX)
	var pitch := LEAN_PITCH_MAX * tanh(a.y / 9.8 * LEAN_PITCH_PER_G / LEAN_PITCH_MAX)
	return Vector2(roll, pitch)


func _lean(delta: float) -> void:
	if _body == null or delta <= 0.0:
		return
	var v := car.linear_velocity
	var target := Vector2.ZERO
	if _last_v != Vector3.INF and not car.is_airborne():
		var a := ((v - _last_v) / delta).limit_length(LEAN_ACCEL_CLAMP)
		var raw := Vector2(a.dot(car.global_basis.x), a.dot(-car.global_basis.z))
		acc += (raw - acc) * (1.0 - exp(-LEAN_SMOOTH * delta))
		target = lean_for(acc)
	else:
		acc = acc.lerp(Vector2.ZERO, 1.0 - exp(-LEAN_SMOOTH * delta))
	_last_v = v
	var r := spring(lean.x, _lean_v.x, target.x, LEAN_HZ, LEAN_ZETA, delta)
	var p := spring(lean.y, _lean_v.y, target.y, LEAN_HZ, LEAN_ZETA, delta)
	lean = Vector2(r.x, p.x)
	_lean_v = Vector2(r.y, p.y)
	if absf(lean.x - _written.x) < 0.01 and absf(lean.y - _written.y) < 0.01:
		return
	_written = lean
	_apply(lean)


## Puts the drawn body (and its lamps) at `deg` (roll, pitch) about the pivot.
func _apply(deg: Vector2) -> void:
	# Roll about the car's nose axis (-Z): + lifts the right side. Pitch about +X: + lifts the nose.
	var rot := Basis(Vector3(0, 0, -1), -deg_to_rad(deg.x)) * Basis(Vector3.RIGHT, deg_to_rad(deg.y))
	var xf := Transform3D(rot, _pivot - rot * _pivot)
	_body.transform = xf * _body_rest
	if _lights != null:
		_lights.transform = xf * _lights_rest


## Back to the rest pose (getting out).
func rest() -> void:
	lean = Vector2.ZERO
	_lean_v = Vector2.ZERO
	acc = Vector2.ZERO
	_last_v = Vector3.INF
	_written = Vector2(INF, INF)
	if _body != null:
		_body.transform = _body_rest
	if _lights != null:
		_lights.transform = _lights_rest


## Past GUARD_ROLL degrees with one side's wheels off the road, bleed the roll rate that is
## taking it further over.
func _guard(delta: float) -> void:
	var right := car.global_basis.x
	var roll := rad_to_deg(asin(clampf(right.y, -1.0, 1.0)))
	if absf(roll) < GUARD_ROLL or car.global_basis.y.y < 0.3:
		return
	var left_down := car.wheels[0].is_in_contact() or car.wheels[2].is_in_contact()
	var right_down := car.wheels[1].is_in_contact() or car.wheels[3].is_in_contact()
	if left_down == right_down:
		return
	var fwd := -car.global_basis.z
	var rate := car.angular_velocity.dot(fwd)
	# Positive roll (right side up) grows with a negative rate about the nose... take the part of
	# the rate that increases |roll| and bleed it.
	var growing := (roll > 0.0 and rate < 0.0) or (roll < 0.0 and rate > 0.0)
	if not growing:
		return
	car.angular_velocity -= fwd * rate * minf(GUARD_RATE * delta, 1.0)
