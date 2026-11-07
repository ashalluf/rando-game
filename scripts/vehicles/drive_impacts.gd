class_name DriveImpacts
extends RefCounted
## What the player's car does when it hits things (wave 9, drive-collide; docs/HANDOFF.md "Impacts
## and traffic"). One hook, `tick()`, from Vehicle._physics_process() while the player drives
## (and Motorcycle's). Four parts, each its own switch:
##   shove    kinematic TRAFFIC cars are infinite mass to the solver: hitting one was hitting a
##            wall. A box query ahead of the car (like PropBreak.smash_ahead) finds a traffic car
##            the player is about to hit, drops it out of the traffic BEFORE the solver meets it
##            and hands both cars the velocities of a 1D collision with restitution (masses as
##            they are: a bus barely moves, a sedan is shoved), the push applied at the contact
##            so an off-centre hit spins it, with a little arcade lift. Both take a crash dent.
##   glance   a body hit on a WALL at a shallow angle (under GLANCE_MAX of head-on) stopped the
##            car dead, because the body's friction against the wall took the speed along it.
##            Past a speed loss the car's velocity is put back to what it had ALONG the wall
##            (GLANCE_KEEP of it) plus a small bounce off it, and the nose is swung onto the wall
##            line: a scrape that redirects. Head-on hits are left as they are.
##   unstick  throttle held, nearly still and pressed against something (or high-centred) for
##            STUCK_SECONDS: a nudge up and along / away from what blocks it, like GTA's.
##   props    the player's car loses only PROP_SLOW_SHARE of what PropBreak.SLOW takes from a
##            car (an overpowered player keeps his momentum through lamps and hydrants).
## `DRIVE_IMPACTS=0` turns all of it off (the A/B); `DRIVE_SHOVE=0`, `DRIVE_GLANCE=0`,
## `DRIVE_UNSTICK=0`, `DRIVE_PROP_KEEP=0` each part. Probe: tools/drive_collide/probe.tscn;
## checks: tests/drive_collide_checks.gd.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("DRIVE_IMPACTS") != "0"
static var shove_on: bool = OS.get_environment("DRIVE_SHOVE") != "0"
static var glance_on: bool = OS.get_environment("DRIVE_GLANCE") != "0"
static var unstick_on: bool = OS.get_environment("DRIVE_UNSTICK") != "0"
static var prop_keep_on: bool = OS.get_environment("DRIVE_PROP_KEEP") != "0"

## --- shove ---
## Slowest closing speed (m/s) that shoves a traffic car out of the traffic.
const SHOVE_MIN := 2.5
## Bounce of a car-to-car hit (0 plastic, 1 elastic). Real crashes are ~0.1-0.3.
const RESTITUTION := 0.3
## The traffic car takes this much more of the impulse than physics gives it (arcade: the
## overpowered player's car hits like a truck), the player loses this share of his physical loss.
const SHOVE_GAIN := 1.35
const PLAYER_LOSS_SHARE := 0.75
## Upward kick on the shoved car, m/s per m/s of its velocity change.
const SHOVE_LIFT := 0.08
## The yaw an off-centre push gives the shoved car (share of what a rigid box would take, cap rad/s),
## and its tyres' grip (share) for how long (s) after.
const SHOVE_SPIN := 1.6
const SHOVE_SPIN_MAX := 3.5
const SHOVE_GRIP := 0.35
const SHOVE_SLIDE := 1.0
## Seconds a shoved car is ignored afterwards (the solver has it now).
const SHOVE_COOLDOWN := 0.6

## --- glance ---
## Fastest the car may be going (m/s) before a glance is looked for, and the speed loss in one step
## (m/s, and share of the speed) that says it hit something.
const GLANCE_MIN_SPEED := 6.0
const GLANCE_LOSS := 1.6
const GLANCE_LOSS_SHARE := 0.1
## Most the hit may face the wall (sin of the angle between the velocity and the wall, 1 head-on)
## to count as a glance: 0.66 is about 41 degrees.
const GLANCE_MAX := 0.66
## Share of the speed along the wall kept, and the bounce off it (share of the speed into it).
const GLANCE_KEEP := 0.88
const GLANCE_BOUNCE := 0.22
## Yaw rate per radian between the nose and the wall line (1/s), and its cap (rad/s).
const REDIRECT := 3.5
const REDIRECT_MAX := 2.2
## Seconds the nose keeps being swung onto the wall line after a glance.
const REDIRECT_SECONDS := 0.45
## Most the heading itself is turned onto the wall line (rad/s) while it is.
const SWING_RATE := 2.4
## Rubbing along a wall: slowest speed it is looked for (m/s), the share of each step's loss
## given back, and how hard it eases off the wall (m/s per second).
const SCRAPE_MIN_SPEED := 4.0
const SCRAPE_GIVE_BACK := 0.75
const SCRAPE_PUSH := 1.5
## How far past the body the wall query reaches (m).
const BODY_PAD := 0.35

## --- unstick ---
const STUCK_SECONDS := 1.1
const STUCK_SPEED := 0.7
## The nudge: up and along (m/s), then a wait before the next.
const NUDGE_UP := 2.6
const NUDGE_PUSH := 2.4
const NUDGE_COOLDOWN := 1.0

## --- props ---
const PROP_SLOW_SHARE := 0.45

## Counters, for the checks and the probe.
static var shoves: int = 0
static var glances: int = 0
static var nudges: int = 0
static var scrapes: int = 0
static var last_shove: Dictionary = {}
static var last_glance: Dictionary = {}

static var _box := BoxShape3D.new()
static var _q: PhysicsShapeQueryParameters3D


class State:
	extends RefCounted
	var prev_v := Vector3.ZERO
	var have_prev := false
	var stuck := 0.0
	var cool := 0.0
	var shoved := {} # instance id -> seconds left
	var redirect := 0.0 # seconds left of the nose being swung onto `line`
	var line := Vector3.FORWARD


static func _state(car: Vehicle) -> State:
	var st: Variant = car.get_meta(&"drive_impacts") if car.has_meta(&"drive_impacts") else null
	if st is State:
		return st
	var s := State.new()
	car.set_meta(&"drive_impacts", s)
	return s


## The player's car this step (from Vehicle._physics_process while `driver` is set).
static func tick(car: Vehicle, delta: float) -> void:
	if not enabled or car.freeze or not car.is_inside_tree() or car.collision_layer == 0 or delta <= 0.0:
		return
	var st := _state(car)
	if _q == null:
		_q = PhysicsShapeQueryParameters3D.new()
	for k in st.shoved.keys():
		st.shoved[k] = float(st.shoved[k]) - delta
		if float(st.shoved[k]) <= 0.0:
			st.shoved.erase(k)
	if shove_on:
		_shove(car, st, delta)
	if glance_on and st.have_prev:
		_glance(car, st, delta)
	if unstick_on:
		_unstick(car, st, delta)
	st.prev_v = car.linear_velocity
	st.have_prev = true


## A teleport, a respawn, a script setting the velocity on purpose: forget the last step.
static func reset(car: Vehicle) -> void:
	if car.has_meta(&"drive_impacts"):
		(car.get_meta(&"drive_impacts") as State).have_prev = false


## PropBreak.smash_ahead's speed share for `car` (the player's keeps more of his speed).
static func prop_slow(car: Vehicle, slow: float) -> float:
	if enabled and prop_keep_on and car.driver != null:
		return slow * PROP_SLOW_SHARE
	return slow


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- shove -------------------------------------------------------------------------------------

static func _shove(car: Vehicle, st: State, delta: float) -> void:
	var v := car.linear_velocity
	var speed := v.length()
	if speed < SHOVE_MIN:
		return
	var d: Dictionary = car._dims()
	_box.size = Vector3(float(d.width) + 0.2, 1.2, float(d.length) + 0.2)
	_q.shape = _box
	_q.collision_mask = 4
	_q.exclude = [car.get_rid()]
	var xf := car.global_transform.orthonormalized()
	xf.origin += xf.basis.y * 0.7 + v * delta * 2.0
	_q.transform = xf
	var hits := car.get_world_3d().direct_space_state.intersect_shape(_q, 8)
	for hit in hits:
		var other := hit.collider as Vehicle
		if other == null or other == car or not other.is_traffic() or other.is_wreck():
			continue
		if st.shoved.has(other.get_instance_id()):
			continue
		var vo := -other.global_basis.z * other.traffic_speed
		var n := _flat(other.global_position - car.global_position)
		if n.length() < 0.01:
			n = _flat(v)
		n = n.normalized()
		var closing := (v - vo).dot(n)
		if closing < SHOVE_MIN:
			continue
		var m1 := car.mass
		var m2 := other.mass
		var j := (1.0 + RESTITUTION) * closing / (1.0 / m1 + 1.0 / m2)
		var dv1 := -n * (j / m1) * PLAYER_LOSS_SHARE
		var dv2 := n * (j / m2) * SHOVE_GAIN
		# Where they meet: the player's nose, as far across it as the other car is off its line - so
		# an off-centre hit pushes past the other car's centre and spins it.
		var vdir := _flat(v).normalized()
		var side := Vector3(-vdir.z, 0.0, vdir.x)
		var off := (other.global_position - car.global_position).dot(side)
		var half_w := float(d.width) * 0.5
		var contact := car.global_position + vdir * (float(d.length) * 0.5) + side * clampf(off, -half_w, half_w) * 0.5 \
				+ Vector3.UP * 0.5
		other.drop_out_of_traffic()
		other.sleeping = false
		other.linear_velocity = vo
		other.apply_impulse(dv2 * m2 + Vector3.UP * dv2.length() * SHOVE_LIFT * m2, contact - other.global_position)
		# The yaw the push off its centre gives it (a box's inertia), and tyres that let go for a
		# moment: a car shunted on a corner slews round, it does not just roll on.
		var ol := float(other._dims().length)
		var ow := float(other._dims().width)
		var inertia := m2 * (ol * ol + ow * ow) / 12.0
		var torque := (contact - other.global_position).cross(dv2 * m2).y
		var ow_v := other.angular_velocity
		ow_v.y += clampf(torque / inertia * SHOVE_SPIN, -SHOVE_SPIN_MAX, SHOVE_SPIN_MAX)
		other.angular_velocity = ow_v
		_loosen(other)
		other.hold_crash_watch(3)
		car.linear_velocity = v + dv1
		v = car.linear_velocity
		car.hold_crash_watch(2)
		st.shoved[other.get_instance_id()] = SHOVE_COOLDOWN
		shoves += 1
		last_shove = {"closing": closing, "dv_player": dv1.length(), "dv_other": dv2.length(), "other_mass": m2, "other": other}
		# The dents and the camera's kick: a crash for both, by how hard each was hit.
		var over1 := dv1.length() - car.crash_min_dv * 0.5
		if over1 > 0.0:
			car.take_hit(-1, over1, n, contact, Vehicle.HIT_CRASH)
		var over2 := dv2.length() - other.crash_min_dv * 0.5
		if over2 > 0.0 and is_instance_valid(other):
			other.take_hit(-1, over2, n, contact, Vehicle.HIT_CRASH)
		Sfx.play("hit_metal", contact, clampf(-6.0 + closing * 0.5, -6.0, 6.0), 0.8)


## A shoved car's tyres at SHOVE_GRIP of their grip for SHOVE_SLIDE seconds.
static func _loosen(other: Vehicle) -> void:
	var keep: Array = []
	for w in other.wheels:
		if is_instance_valid(w):
			keep.append([w, w.wheel_friction_slip])
			w.wheel_friction_slip *= SHOVE_GRIP
	if keep.is_empty() or not other.is_inside_tree():
		return
	other.get_tree().create_timer(SHOVE_SLIDE, false, true).timeout.connect(func() -> void:
		for k: Array in keep:
			if is_instance_valid(k[0]):
				(k[0] as VehicleWheel3D).wheel_friction_slip = float(k[1]))


# --- glance ------------------------------------------------------------------------------------

static func _glance(car: Vehicle, st: State, delta: float) -> void:
	var pv := _flat(st.prev_v)
	var ps := pv.length()
	var v := car.linear_velocity
	var vh := _flat(v)
	# The nose still being swung onto the wall line after a glance.
	if st.redirect > 0.0:
		st.redirect -= delta
		_swing(car, st.line, delta)
	if ps < SCRAPE_MIN_SPEED:
		return
	var loss := ps - vh.length()
	if loss < 0.03:
		return
	# What it touched: the body's box, grown a little, above the wheels (never the road).
	var d: Dictionary = car._dims()
	_box.size = Vector3(float(d.width) + BODY_PAD * 2.0, 0.9, float(d.length) + BODY_PAD * 2.0)
	_q.shape = _box
	_q.collision_mask = 1
	_q.exclude = [car.get_rid()]
	var xf := car.global_transform.orthonormalized()
	xf.origin += xf.basis.y * 0.85
	_q.transform = xf
	var info := car.get_world_3d().direct_space_state.get_rest_info(_q)
	if info.is_empty():
		return
	var n: Vector3 = info.normal
	if absf(n.y) > 0.45:
		return
	n = _flat(n).normalized()
	var dir := pv / ps
	var into := -dir.dot(n)
	if into > GLANCE_MAX:
		return
	var along := pv + n * maxf(pv.dot(-n), 0.0) # pv less its part into the wall
	if along.length() < 0.5:
		return
	var keep: Vector3
	if ps >= GLANCE_MIN_SPEED and loss >= maxf(GLANCE_LOSS, ps * GLANCE_LOSS_SHARE) and into > 0.02:
		# A glance: put back the speed along the wall, a bounce off it, swing the nose round.
		keep = along * GLANCE_KEEP + n * (ps * into * GLANCE_BOUNCE)
		glances += 1
		last_glance = {"speed_before": ps, "speed_after": keep.length(), "into": into, "lost": loss}
		st.line = along.normalized()
		st.redirect = REDIRECT_SECONDS
		_swing(car, st.line, delta)
	else:
		# Rubbing along it: the body's friction on the wall eats speed every step; give most back.
		keep = vh + along.normalized() * loss * SCRAPE_GIVE_BACK + n * SCRAPE_PUSH * delta
		scrapes += 1
	if keep.length() <= vh.length() * 0.999 and into > 0.02:
		return
	car.linear_velocity = Vector3(keep.x, minf(v.y, maxf(st.prev_v.y, 0.0) + 0.5), keep.z)
	car.hold_crash_watch(2)


## Turns the car's nose (or tail, if it is going backwards) toward `line` by at most SWING_RATE x
## delta this step - its heading itself, not its yaw rate, which the tyres fight - and holds down
## the roll a wall hit puts into it.
static func _swing(car: Vehicle, line: Vector3, delta: float) -> void:
	var fwd := _flat(-car.global_basis.z).normalized()
	if fwd.dot(line) < 0.0:
		line = -line
	var ang := fwd.signed_angle_to(line, Vector3.UP)
	var step := clampf(ang, -SWING_RATE * delta, SWING_RATE * delta)
	if absf(step) > 0.0001:
		var xf := car.global_transform
		xf.basis = Basis(Vector3.UP, step) * xf.basis
		car.global_transform = xf
	var w := car.angular_velocity
	w.y = clampf(ang * REDIRECT, -REDIRECT_MAX, REDIRECT_MAX)
	var roll_axis := -car.global_basis.z
	w -= roll_axis * w.dot(roll_axis) * 0.5
	car.angular_velocity = w


# --- unstick -----------------------------------------------------------------------------------

static func _unstick(car: Vehicle, st: State, delta: float) -> void:
	st.cool = maxf(st.cool - delta, 0.0)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var throttle := -input.y
	var v := car.linear_velocity
	if absf(throttle) < 0.3 or _flat(v).length() > STUCK_SPEED or absf(v.y) > 1.0 or car.global_basis.y.y < 0.3:
		st.stuck = 0.0
		return
	st.stuck += delta
	if st.stuck < STUCK_SECONDS or st.cool > 0.0:
		return
	# Pressed against something, or not on all its wheels (high-centred on a kerb or a median).
	var d: Dictionary = car._dims()
	var fwd := _flat(-car.global_basis.z).normalized() * signf(throttle)
	_box.size = Vector3(float(d.width) + 0.5, 1.0, float(d.length) + 0.7)
	_q.shape = _box
	_q.collision_mask = 1 | 4
	_q.exclude = [car.get_rid()]
	var xf := car.global_transform.orthonormalized()
	xf.origin += xf.basis.y * 0.8 + fwd * 0.2
	_q.transform = xf
	var info := car.get_world_3d().direct_space_state.get_rest_info(_q)
	var touching := 0
	for w in car.wheels:
		if is_instance_valid(w) and w.is_in_contact():
			touching += 1
	var blocked := not info.is_empty() and absf((info.normal as Vector3).y) < 0.6
	if not blocked and touching >= mini(car.wheels.size(), 3):
		return
	var push := fwd
	var turn := -input.x
	if blocked:
		var n := _flat(info.normal).normalized()
		var right := _flat(car.global_basis.x).normalized()
		if absf(fwd.dot(n)) > 0.7:
			# Square on: slide off sideways, away from where it touches, nose turned that way.
			var side := -signf((info.point as Vector3 - car.global_position).dot(right))
			if side == 0.0:
				side = 1.0 if turn >= 0.0 else -1.0
			push = (right * side + n * 0.45 + fwd * 0.15).normalized()
			if absf(turn) < 0.1:
				turn = -side * signf(throttle) # yaw left (positive) when sliding left
		else:
			# Along it if it faces us, plus a bit away from it.
			push = ((fwd - n * minf(fwd.dot(n), 0.0)).normalized() + n * 0.5).normalized()
	car.linear_velocity = v + push * NUDGE_PUSH + Vector3.UP * NUDGE_UP
	var w := car.angular_velocity
	w.y += turn * 1.2
	car.angular_velocity = w
	car.hold_crash_watch(3)
	st.stuck = 0.0
	st.cool = NUDGE_COOLDOWN
	nudges += 1
