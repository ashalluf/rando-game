class_name TrafficMotion
extends RefCounted
## Kinematic traffic seen moving, up close (fleet wave 3, "traffic-motion"; docs/HANDOFF.md
## "Traffic that moves like cars").
##
## A traffic car is placed, not simulated (TrafficManager, TrafficAI, police / emergency / news
## cars, the stack and coast traffic): its transform glides down the lane and only the wheels
## spun. From the pavement or a chase camera that is a model on a wire. This lays the motion a
## driven car has on top of the placement, VISUALLY, on the body model alone (the Vehicle's
## BodyModel holder and its NightLights), never on the physics:
##   * PITCH: nose down under braking, a little squat pulling away, rocking back once past level
##     as the car stops (a damped spring on the body's longitudinal acceleration).
##   * ROLL: the body leans out of a turn and a lane change (the lateral acceleration v x yaw rate).
##   * HEAVE: a few millimetres of road texture with speed, and RoadWear's deep potholes - each
##     wheel drops into one as it crosses (the wheel rig moved down) and kicks the body.
##   * STEERING: the front wheels follow the path's curvature (wheelbase x yaw rate / speed) at a
##     real steering rate, and HOLD their angle when the car stops mid-turn (they snapped straight).
##   * TURNS: a street car's turn is a snap in the logic (TrafficManager: at the junction's centre
##     it is put on the cross street, turned 90 degrees in one tick). `turn_pose()` draws it round a
##     circular fillet tangent to the two lanes instead, mapped on the car's own progress through
##     the turn, so it is continuous at the snap; the steering and the roll then read a real turn.
##   * The QUEUE: a car standing behind a standing car waits a beat after the one in front moves
##     off (`queue_react()`, from TrafficManager._drive_street()): the whole queue used to pull
##     away in the same tick.
## Only within `RANGE` of the camera; past it the body is put back at rest once and nothing runs.
## State lives on the car (`Vehicle.motion`), made the first time it is needed. `TRAFFIC_MOTION=0`
## in the environment is the A/B (the old glide, the old steering, no queue beat).

static var enabled: bool = OS.get_environment("TRAFFIC_MOTION") != "0"
## The queue beat for cars placed by hand (place_car(): checks and stills). Off by default, so the
## checks that time a staged queue are unchanged; `TRAFFIC_REACT_PLACED=1` turns it on for stills.
static var react_placed: bool = OS.get_environment("TRAFFIC_REACT_PLACED") == "1"

## Metres from the camera inside which a car's body moves (past it: at rest, nothing runs).
const RANGE := 70.0
## Pitch (rad) per m/s^2 of longitudinal acceleration: braking (nose down) and pulling away (the
## squat is weaker: the springs are stiffer at the back and the drive is gentle). 4 m/s^2 of
## braking is about 1 degree; a hard stop's 7 m/s^2 nearly 2.
const PITCH_PER_DECEL := 0.0046
const PITCH_PER_ACCEL := 0.0028
const PITCH_MAX := 0.042
## Roll (rad) per m/s^2 of lateral acceleration, outward: a 0.3 g city turn is ~1 degree.
const ROLL_PER_ACCEL := 0.0062
const ROLL_MAX := 0.05
## The body's springs: natural frequency (Hz) and damping ratio. Under 1, so a stop rocks back
## once past level and settles, which is what reads as a sprung car.
const PITCH_HZ := 1.35
const PITCH_ZETA := 0.38
const ROLL_HZ := 1.55
const ROLL_ZETA := 0.5
const HEAVE_HZ := 1.5
const HEAVE_ZETA := 0.42
## Big vehicles (buses, trucks, semis) sit on softer, slower springs and roll more.
const BIG_HZ_SCALE := 0.75
const BIG_ROLL_GAIN := 1.4
## The accelerations are smoothed (1/s): the freeway's follow rule changes speed in steps.
const ACCEL_SMOOTH := 9.0
const ACCEL_CLAMP := 11.0
## Turn rates past this (rad/s) are a placement, not a turn (a U-turn's flip, a pool reuse).
const YAW_RATE_CAP := 1.4
## Road texture: heave (m) and pitch (rad) at `TEXTURE_SPEED` m/s, on two wavelengths (m).
const TEXTURE_HEAVE := 0.0035
const TEXTURE_PITCH := 0.0016
const TEXTURE_SPEED := 14.0
const TEXTURE_WAVES := Vector2(8.7, 3.1)
## A pothole: body heave speed (m/s) and pitch / roll rate (rad/s) per metre of depth at
## `TEXTURE_SPEED`, and how fast a wheel climbs back out of it (m/s).
const POT_HEAVE_KICK := 6.0
const POT_TILT_KICK := 3.2
const POT_CLIMB := 0.9
## Steering: the most lock (rad) and how fast a driver turns it at the wheels (rad/s); under
## `STEER_HOLD` m/s the angle is kept.
const STEER_MAX := 0.58
const STEER_RATE := 1.3
const STEER_HOLD := 0.6
## Turn fillets: the radius is what the junction box leaves (the lane's way in and out of it) plus
## `ARC_EXTEND` m, clamped. The arc starts that far before the lanes meet.
const ARC_EXTEND := 1.5
const ARC_MIN := 4.0
const ARC_MAX := 14.0
## Where the fillet is looked at (m to the junction's centre): nothing further out pays for it.
const ARC_LOOK := 30.0
## The queue beat: seconds after the car ahead moves off, from the driver's mood's reaction time
## (TrafficAI m_react) times `QUEUE_REACT_GAIN` plus a hashed jitter, clamped.
const QUEUE_REACT_GAIN := 0.75
const QUEUE_REACT_JITTER := 0.25
const QUEUE_REACT_RANGE := Vector2(0.3, 1.6)

## Microseconds the motion took this physics frame, all cars (smoothed; the checks read it).
static var usec: float = 0.0
## Cars moved this physics frame (the checks and the census).
static var moving: int = 0
static var _frame: int = -1
static var _frame_usec: float = 0.0
static var _frame_moving: int = 0

var car: Vehicle
var body: Node3D
var lights: Node3D
var body_rest := Transform3D.IDENTITY
var lights_rest := Transform3D.IDENTITY
var pivot := Vector3.ZERO
var wheelbase: float = 2.7
var big: bool = false
var fittings: Node = null
var active: bool = false
var last_v: float = 0.0
var last_yaw: float = 0.0
var last_pos := Vector3.INF
var accel: float = 0.0
var lat: float = 0.0
var pitch: float = 0.0
var pitch_v: float = 0.0
var roll: float = 0.0
var roll_v: float = 0.0
var heave: float = 0.0
var heave_v: float = 0.0
var steer: float = 0.0
var travelled: float = 0.0
var phase := Vector2.ZERO
## Per wheel rig: inside a pothole last tick, and how far the visible wheel is dropped (m).
var in_pot: Array = []
var drop := PackedFloat32Array()
## What was last written (the body's pitch, roll, heave; whether any wheel was dropped): a body at
## rest is not written again, every tick, down to the renderer.
var _written := Vector3(INF, INF, INF)
var _wheels_dropped: bool = false


## Whether this car's body may be moved at all: not the bikes (their own Pose), not a lowrider on
## its hydraulics, not a car with no body model.
static func supported(c: Vehicle) -> bool:
	if Motorcycle.is_moto(c.body_type):
		return false
	if c.get_node_or_null("BodyModel") == null:
		return false
	for ch in c.get_children():
		if ch is Lowrider.Hydraulics:
			return false
	return true


## The one hook (Vehicle._update_wheels, every physics tick of a car whose script runs): moves a
## traffic car's body and returns the front wheels' steering angle (rad), or NAN to leave the
## caller's. `yaw_rate` rad/s (+ left), `speed` m/s forward, `dist` to the camera.
static func tick(c: Vehicle, yaw_rate: float, speed: float, dist: float, delta: float) -> float:
	var st: TrafficMotion = c.motion
	if not enabled:
		if st != null:
			st._rest()
			c.motion = null
		return NAN
	# (A panicking driver's car, CarPanic, dives and sways as a whole already.)
	var traffic := c.is_traffic() and c.driver == null and not c.is_wreck() and not c.traffic.has("cp")
	if not traffic:
		if st != null:
			st._rest()
			c.motion = null
		return NAN
	if dist > RANGE:
		if st != null and st.active:
			st._rest()
		return NAN
	if delta <= 0.0:
		return NAN
	var t0 := Time.get_ticks_usec()
	if st == null:
		if not supported(c):
			return NAN
		st = TrafficMotion.new()
		st._setup(c)
		c.motion = st
		t0 = Time.get_ticks_usec()
	var s := st._step(yaw_rate, speed, delta)
	var frame := int(Engine.get_physics_frames())
	if frame != _frame:
		usec = lerpf(usec, _frame_usec, 0.05)
		moving = _frame_moving
		_frame = frame
		_frame_usec = 0.0
		_frame_moving = 0
	_frame_usec += float(Time.get_ticks_usec() - t0)
	_frame_moving += 1
	return s


## The queue beat (TrafficManager._drive_street(), just before its own reaction rule): a car that
## stood behind a standing car waits a beat once that car moves off. `v` is its own speed.
static func queue_react(c: Vehicle, t: Dictionary, leader: Vehicle, v: float) -> void:
	if not enabled or (t.get("placed", false) and not react_placed):
		return
	if v > 0.25:
		if t.has("qs"):
			t.erase("qs")
		return
	if leader == null or not is_instance_valid(leader) or leader.traffic.is_empty():
		return
	var lv := float(leader.traffic.get("v", leader.traffic_speed))
	if lv < 0.3:
		t.qs = true
		return
	if t.get("qs", false):
		t.erase("qs")
		if float(t.get("react", 0.0)) <= 0.0:
			t.react = queue_delay(c.look_seed, int(TrafficAI.clock * 2.0), float(t.get("m_react", 0.65)))
			t.react_t = 0.0


## The beat for a driver of reaction time `m_react` (pure: a hash of the car and the moment).
static func queue_delay(seed: int, moment: int, m_react: float) -> float:
	var u := float(absi(hash([seed, moment, "queue_beat"])) % 1000) / 999.0
	return clampf(m_react * QUEUE_REACT_GAIN + u * QUEUE_REACT_JITTER, QUEUE_REACT_RANGE.x, QUEUE_REACT_RANGE.y)


## A street car's pose round its turn (TrafficManager._place(), true world `w` and `yaw` as the
## logic places it): Vector4(x, y, z, yaw) on the fillet, or w NAN to keep the logic's own.
static func turn_pose(tm: TrafficManager, car: Vehicle, w: Vector3, yaw: float) -> Vector4:
	var none := Vector4(0.0, 0.0, 0.0, NAN)
	if not enabled:
		return none
	var t: Dictionary = car.traffic
	if not t.has("axis") or t.has("cp"):
		return none
	var p := Vector2(w.x, w.z)
	var axis: int = t.axis
	var dir: int = t.dir
	var turn := int(t.get("turn", 0))
	var arc: Array = t.get("tm_arc", [])
	if (turn == 1 or turn == -1) and absf(float(t.get("to_c", INF))) < ARC_LOOK:
		var node: Vector2i = t.get("node", Vector2i(-999999, -999999))
		if arc.is_empty() or arc[5] != node:
			arc = fillet(tm, axis, int(t.index), dir, node, turn, p)
			t.tm_arc = arc
	if arc.is_empty():
		return none
	var c: Vector2 = arc[0]
	var f: Vector2 = arc[1]
	var g: Vector2 = arc[2]
	var r: float = arc[3]
	var dd: float = arc[4]
	var here := _road_dir(axis, dir)
	var length := maxf(2.0 * r + dd, r)
	var u := 0.0
	if here.dot(f) > 0.9:
		if turn == 0:
			# The turn was dropped (its lane was taken): straight on, as the logic drives it.
			t.erase("tm_arc")
			return none
		u = ((p - c).dot(f) + r) / length
		if u <= 0.0:
			return none
	elif here.dot(g) > 0.9:
		u = (r + dd + (p - c).dot(g)) / length
		if u >= 1.0:
			t.erase("tm_arc")
			return none
	else:
		t.erase("tm_arc")
		return none
	var a := clampf(u, 0.0, 1.0) * PI * 0.5
	var o := c - f * r + g * r
	var at := o - g * (r * cos(a)) + f * (r * sin(a))
	var h := f * cos(a) + g * sin(a)
	return Vector4(at.x, w.y, at.y, atan2(-h.x, -h.y))


## The fillet for a car on road (axis, index) heading `dir`, at `p`, turning `turn` (+1 / -1 the
## cross road's direction) at `node`: [lanes' meeting point, way in, way out, radius, how far the
## junction's centre is past the meeting point along the way in, node], or [] (pure: no rolls).
static func fillet(tm: TrafficManager, axis: int, index: int, dir: int, node: Vector2i, turn: int, p: Vector2) -> Array:
	var plan := tm.plan
	var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var cross_index: int = node.y if axis == CityPlan.AXIS_X else node.x
	var lane := TrafficAI.turn_lane(tm, cross_axis, cross_index, turn, TrafficAI.turn_side(axis, dir, turn))
	var road_new := plan.road_pos(cross_axis, cross_index)
	var c := Vector2(p.x, road_new + lane) if cross_axis == CityPlan.AXIS_Z else Vector2(road_new + lane, p.y)
	var f := _road_dir(axis, dir)
	var g := _road_dir(cross_axis, turn)
	# Into the junction box along the way in, and out of it along the way out.
	var along_c := c.y if axis == CityPlan.AXIS_X else c.x
	var e1 := (along_c - (road_new - float(dir) * plan.road_width(cross_axis, cross_index) * 0.5)) * float(dir)
	var along_new := c.x if cross_axis == CityPlan.AXIS_Z else c.y
	var e2 := (plan.road_pos(axis, index) + float(turn) * plan.road_width(axis, index) * 0.5 - along_new) * float(turn)
	var r := clampf(minf(e1, e2) + ARC_EXTEND, ARC_MIN, ARC_MAX)
	var dd := (road_new - along_c) * float(dir)
	return [c, f, g, r, dd, node]


## The way a car on a road of `axis` driving `dir` heads, in world XZ.
static func _road_dir(axis: int, dir: int) -> Vector2:
	return Vector2(0.0, float(dir)) if axis == CityPlan.AXIS_X else Vector2(float(dir), 0.0)


## The pitch (rad, + nose up) the body settles at under a steady longitudinal acceleration (pure).
static func pitch_for(a: float) -> float:
	return clampf(a * (PITCH_PER_DECEL if a < 0.0 else PITCH_PER_ACCEL), -PITCH_MAX, PITCH_MAX)


## The roll (rad, about +Z: + raises the right side) under lateral acceleration `lat_left` (m/s^2
## toward the car's left, i.e. turning left): the body leans out, so the right side goes down.
static func roll_for(lat_left: float, is_big: bool = false) -> float:
	return clampf(-lat_left * ROLL_PER_ACCEL * (BIG_ROLL_GAIN if is_big else 1.0), -ROLL_MAX, ROLL_MAX)


## The front wheels' angle (rad, + left) for a path of yaw rate `yaw_rate` at `speed` (pure).
static func steer_for(yaw_rate: float, speed: float, wb: float) -> float:
	var v := signf(speed) * maxf(absf(speed), 1.5) if speed != 0.0 else 1.5
	return clampf(atan(wb * yaw_rate / v), -STEER_MAX, STEER_MAX)


## One damped spring step toward `target`: [x, v] after `dt` (semi-implicit Euler, sub-stepped).
static func spring(x: float, v: float, target: float, hz: float, zeta: float, dt: float) -> Vector2:
	var w := TAU * hz
	var k := w * w
	var c := 2.0 * zeta * w
	var n := maxi(1, ceili(dt / (1.0 / 90.0)))
	var h := dt / float(n)
	for i in n:
		v += ((target - x) * k - v * c) * h
		x += v * h
	return Vector2(x, v)


func _setup(c: Vehicle) -> void:
	car = c
	body = c.get_node_or_null("BodyModel") as Node3D
	lights = c.get_node_or_null("NightLights") as Node3D
	if body:
		body_rest = body.transform
	if lights:
		lights_rest = lights.transform
	big = BigVehicles.is_big(c.body_type)
	for ch in c.get_children():
		if ch is BigVehicles.BusFittings:
			fittings = ch
	# Axles from the wheel rigs themselves: every body type (cars, trucks' axle sets, the exotics).
	var zf := 0.0
	var nf := 0
	var zr := 0.0
	var nr := 0
	for rig: Array in c._wheel_rigs:
		var z := (rig[0] as Node3D).position.z
		if rig[4]:
			zf += z
			nf += 1
		else:
			zr += z
			nr += 1
	var front := zf / float(nf) if nf > 0 else -1.4
	var rear := zr / float(nr) if nr > 0 else 1.4
	wheelbase = clampf(absf(rear - front), 1.8, 8.0)
	# Pitch and roll about a point between the axles about half a metre over the road: roughly
	# where the springs' roll and pitch centres put a passenger car's body.
	var road := -c.road_lift()
	pivot = Vector3(0.0, road + (0.75 if big else 0.45), (front + rear) * 0.5)
	in_pot.resize(c._wheel_rigs.size())
	in_pot.fill(false)
	drop.resize(c._wheel_rigs.size())
	drop.fill(0.0)
	var h := absi(hash([c.look_seed, "traffic_motion"]))
	phase = Vector2(float(h % 1000) / 1000.0 * TAU, float((h / 1000) % 1000) / 1000.0 * TAU)
	last_yaw = c.rotation.y
	last_v = c.traffic_speed
	steer = 0.0


func _step(yaw_rate: float, speed: float, dt: float) -> float:
	var pos := car.global_position
	var jumped := last_pos != Vector3.INF and pos.distance_to(last_pos) > maxf(absf(speed) * dt * 3.0, 0.0) + 2.0
	last_pos = pos
	if jumped or not active:
		# Placed somewhere new (the pool, a U-turn, a re-entry into range): no forces from that.
		last_v = speed
		accel = 0.0
		lat = 0.0
		if jumped:
			steer = 0.0
	active = true
	var raw := clampf((speed - last_v) / dt, -ACCEL_CLAMP, ACCEL_CLAMP)
	last_v = speed
	var k := 1.0 - exp(-ACCEL_SMOOTH * dt)
	accel += (raw - accel) * k
	var yr := clampf(yaw_rate, -YAW_RATE_CAP, YAW_RATE_CAP) if absf(yaw_rate) < YAW_RATE_CAP * 2.5 else 0.0
	lat += (speed * yr - lat) * k
	# Steering: toward the path's curvature at a driver's rate; held while standing.
	if absf(speed) > STEER_HOLD:
		steer = move_toward(steer, steer_for(yr, speed, wheelbase), STEER_RATE * dt)
	# Road texture and the potholes under the wheels.
	travelled += absf(speed) * dt
	var tex := clampf(absf(speed) / TEXTURE_SPEED, 0.0, 1.4)
	var wv := TAU * travelled
	var tex_h := TEXTURE_HEAVE * tex * (sin(wv / TEXTURE_WAVES.x + phase.x) + 0.55 * sin(wv / TEXTURE_WAVES.y + phase.y))
	var tex_p := TEXTURE_PITCH * tex * sin(wv / (TEXTURE_WAVES.x * 0.83) + phase.y)
	_potholes(speed, dt)
	var hz := BIG_HZ_SCALE if big else 1.0
	var p := spring(pitch, pitch_v, pitch_for(accel) + tex_p, PITCH_HZ * hz, PITCH_ZETA, dt)
	pitch = p.x
	pitch_v = p.y
	var r := spring(roll, roll_v, roll_for(lat, big), ROLL_HZ * hz, ROLL_ZETA, dt)
	roll = r.x
	roll_v = r.y
	var hv := spring(heave, heave_v, tex_h, HEAVE_HZ * hz, HEAVE_ZETA, dt)
	heave = hv.x
	heave_v = hv.y
	pitch = clampf(pitch, -PITCH_MAX * 1.6, PITCH_MAX * 1.6)
	roll = clampf(roll, -ROLL_MAX * 1.6, ROLL_MAX * 1.6)
	heave = clampf(heave, -0.08, 0.08)
	_write()
	return steer


## RoadWear's deep potholes under each wheel: the wheel drops in as it enters (the rig moved
## down), the body takes a kick toward that corner, and the wheel climbs back out.
func _potholes(speed: float, dt: float) -> void:
	var rigs: Array = car._wheel_rigs
	var look := absf(speed) > 0.8 and not RoadWear._bumps.is_empty()
	if not look and not _wheels_dropped:
		return
	var xf := car.global_transform
	for i in rigs.size():
		var depth := 0.0
		if look:
			var wp := WorldState.to_world(xf * (rigs[i][0] as Node3D).position)
			depth = RoadWear.bump_for(Vector2(wp.x, wp.z))
		var was: bool = in_pot[i]
		in_pot[i] = depth > 0.0
		if depth > 0.0:
			drop[i] = minf(drop[i], -depth)
			if not was:
				var f := depth * clampf(absf(speed) / TEXTURE_SPEED, 0.3, 1.4)
				var node := rigs[i][0] as Node3D
				heave_v -= f * POT_HEAVE_KICK
				# A front wheel dropping puts the nose down; a rear one the tail. The side rolls.
				pitch_v += f * POT_TILT_KICK * (-1.0 if node.position.z < pivot.z else 1.0)
				roll_v += f * POT_TILT_KICK * (-1.0 if node.position.x > 0.0 else 1.0) * 0.7
		elif drop[i] < 0.0:
			drop[i] = minf(drop[i] + POT_CLIMB * dt, 0.0)


func _write() -> void:
	var now := Vector3(pitch, roll, heave)
	if now.distance_squared_to(_written) > 1e-10:
		_written = now
		_write_body()
	var dropped := false
	for d in drop:
		if d != 0.0:
			dropped = true
			break
	if not dropped and not _wheels_dropped:
		return
	_wheels_dropped = dropped
	var rigs: Array = car._wheel_rigs
	for i in rigs.size():
		var node := rigs[i][0] as Node3D
		node.position.y = float(rigs[i][5]) + drop[i]


func _write_body() -> void:
	var rot := Basis.from_euler(Vector3(pitch, 0.0, roll))
	var m := Transform3D(rot, pivot - rot * pivot + Vector3(0.0, heave, 0.0))
	# A bus kneeling at its stop owns its body (BigVehicles.BusFittings): it is standing still.
	if body and not _kneeling():
		body.transform = m * body_rest
	if lights:
		lights.transform = m * lights_rest


func _kneeling() -> bool:
	if fittings == null or not is_instance_valid(fittings):
		return false
	var bf := fittings as BigVehicles.BusFittings
	return bf.kneel > 0.0 or bf.is_processing()


## Back at rest: the body, its lights and the wheels where they were built.
func _rest() -> void:
	active = false
	pitch = 0.0
	pitch_v = 0.0
	roll = 0.0
	roll_v = 0.0
	heave = 0.0
	heave_v = 0.0
	accel = 0.0
	lat = 0.0
	last_pos = Vector3.INF
	drop.fill(0.0)
	_written = Vector3(INF, INF, INF)
	_wheels_dropped = false
	if not is_instance_valid(car):
		return
	if is_instance_valid(body) and not _kneeling():
		body.transform = body_rest
	if is_instance_valid(lights):
		lights.transform = lights_rest
	var rigs: Array = car._wheel_rigs
	for i in rigs.size():
		var node := rigs[i][0] as Node3D
		if is_instance_valid(node) and car.wheels.is_empty():
			node.position.y = float(rigs[i][5])
