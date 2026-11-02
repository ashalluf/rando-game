class_name AmbientJet
extends AmbientCraft
## An airliner or private jet flying a scripted AirRoute (see AirTraffic): an arrival (down the
## approach, flare, touchdown on the centre line, rollout, taxi, fade out at the runway end), a
## departure (fade in lined up on the runway, hold, take-off roll, rotate, climb out, gone past
## `despawn_distance`) or a crossing at altitude. Distance along the route is the whole state:
## position, heading and height are read off the route, the bank from its turn rate and the
## speed, the pitch from its grade. Only the flare and the roll on the runway are integrated.
## Uses the same models as the flyable Aircraft (Aircraft.MODELS).

enum Plan { ARRIVAL, DEPARTURE, CROSSING }
## GROUND: driven along AirportGround's taxi legs (to a gate, a pushback, out to the runway);
## PARKED: standing at a gate, engines off.
enum Phase { LINEUP, ROLL, AIRBORNE, FLARE, ROLLOUT, TAXI, GROUND, PARKED }

@export_group("Approach")
## Speed on the downwind leg, on the turn to final, over the threshold and at touchdown (m/s).
## An airliner's real numbers are about 90 / 75 / 70 / 65; these run a little slower because the
## runway is 740 m, not 3 km.
@export var approach_speeds: Vector4 = Vector4(92.0, 72.0, 61.0, 54.0)
## Height above the runway (m) at which the flare starts, how hard it rounds out (1/s: target
## sink rate per metre of height) and the sink rate it touches down at (m/s).
@export var flare_height: float = 9.0
@export var flare_rate: float = 0.9
@export var touchdown_sink: float = 0.45
## Nose-up attitude on the approach and at the end of the flare (degrees).
@export var approach_attitude: float = 2.5
@export var flare_attitude: float = 5.5
## Braking on the runway after touchdown (m/s^2) and the speed it taxis at (m/s).
@export var rollout_decel: float = 4.0
@export var taxi_speed: float = 9.0
@export_group("Departure")
## Seconds lined up on the runway before the roll, and the take-off acceleration (m/s^2).
@export var hold_seconds: float = 4.0
@export var roll_accel: float = 3.5
## Speed it lifts off at, climbs at, and cruises at (m/s).
@export var liftoff_speed: float = 56.0
@export var climb_speed: float = 86.0
@export var cruise_speed: float = 135.0
## Rotation: nose-up attitude at lift-off and in the climb (degrees).
@export var rotate_attitude: float = 9.0
@export var climb_attitude: float = 4.0
## A departure is removed once it is this far from the camera (metres), just inside the camera's
## 12 km far plane: it is drawn all the way out now, so going sooner would pop it out of the sky.
@export var despawn_distance: float = 11000.0
@export_group("Feel")
## How fast the bank follows the turn (1/s) and the most it banks (degrees).
@export var bank_rate: float = 1.4
@export var max_bank: float = 30.0
@export_group("Ground")
## Taxi speed on a straight (m/s, about 16 knots), the sideways acceleration a turn is taken at
## (m/s^2: a 25 m lead-in is 4.7 m/s), and how hard it speeds up and brakes on the ground.
@export var ground_speed: float = 8.0
@export var turn_accel: float = 0.9
@export var ground_accel: float = 0.6
@export var ground_brake: float = 1.2
## Pushback speed (m/s).
@export var push_speed: float = 1.3

var kind: Aircraft.Kind = Aircraft.Kind.AIRLINER
var plan: Plan = Plan.ARRIVAL
var phase: Phase = Phase.AIRBORNE
var route: AirRoute
## Distance flown along the route, and the speed along it (m/s).
var d: float = 0.0
var speed: float = 0.0
var length: float = 38.0
var wingspan: float = 36.0
## Where the wheels met the runway, TRUE world (INF until they have). Read by the smoke test.
var touchdown_world: Vector3 = Vector3.INF
var runway_y: float = 0.14
## Off: no heat shimmer behind the engines (the A/B; it is off on the web regardless).
static var shimmer_enabled: bool = true
## Heat shimmer is drawn within this distance of the camera (m).
static var shimmer_range: float = 260.0
static var _shimmer_shader: Shader = null

var _h: float = 0.0
var _vs: float = 0.0
## Sink rate the flare started from: it only ever eases off from there.
var _vs_entry: float = 0.0
var _hold_left: float = 0.0
var _model_height: float = 8.0
var _since_touchdown: float = 0.0
## The airliner livery (0..Airport.LIVERIES - 1); -1 rolls one.
var livery: int = -1
## Ground legs (AirportGround.leg()): each {route, reverse, vmax, stop, tag, wait, prof}; the
## leg being driven, and its distance in `d`. `ground_done` is called when the last one ends.
var ground_legs: Array = []
var ground_leg: int = 0
var ground_done: Callable
## Seconds left standing at the start of the current leg.
var ground_wait: float = 0.0
## 0 off .. 1 take-off thrust: the engine sound and the heat behind them follow it.
var engine_level: float = 0.0
var _shimmers: Array[MeshInstance3D] = []
var _asked_ground: bool = false
var _leg_entered: bool = false
var _shimmer_mat: ShaderMaterial = null


## Sets the kind and the plan before the jet enters the tree. `start_d` is where along the route
## it begins (an arrival already on final, a departure already climbing).
func setup(k: Aircraft.Kind, p: Plan, r: AirRoute, start_d: float, seed_value: int) -> void:
	plan = p
	route = r
	d = start_d
	_rng.seed = seed_value
	setup_numbers(k)
	runway_y = float(r.marks.get("runway_y", 0.14))
	match p:
		Plan.ARRIVAL:
			var aim: float = r.marks.get("aim", r.length)
			speed = _approach_speed(aim - d)
			phase = Phase.AIRBORNE
			if d >= aim:
				phase = Phase.ROLLOUT
				speed = taxi_speed * 2.0
		Plan.DEPARTURE:
			var lift: float = r.marks.get("liftoff", 0.0)
			var start: float = r.marks.get("runway_start", 0.0)
			if d <= start + 1.0:
				phase = Phase.LINEUP
				speed = 0.0
				_hold_left = hold_seconds
				fade = 1.0
			elif d < lift:
				phase = Phase.ROLL
				speed = sqrt(2.0 * roll_accel * maxf(d - start, 0.0))
			else:
				phase = Phase.AIRBORNE
				speed = lerpf(liftoff_speed, climb_speed, clampf((d - lift) / 1500.0, 0.0, 1.0))
		Plan.CROSSING:
			phase = Phase.AIRBORNE
			speed = cruise_speed
	var smp := route.sample(d)
	world_pos = smp.pos
	yaw = smp.yaw


## Everything that depends on the kind alone. AirTraffic also reads the take-off numbers off a
## throwaway jet to lay out the departure routes, so they are never written down twice.
func setup_numbers(k: Aircraft.Kind) -> void:
	kind = k
	if k == Aircraft.Kind.PRIVATE:
		length = 20.0
		wingspan = 18.0
		health = 70.0
		crash_radius = 12.0
		approach_speeds = Vector4(80.0, 64.0, 54.0, 48.0)
		liftoff_speed = 48.0
		climb_speed = 80.0
		cruise_speed = 150.0
		roll_accel = 3.2
		rollout_decel = 3.8
		flare_height = 6.0
		sound_unit_size = 26.0
		sound_range = 1400.0
	else:
		# A firm autobrake on this short runway: down to taxi speed with room to turn off into
		# the west connector (AirportGround) from a touchdown 150-250 m past the aim point.
		rollout_decel = 4.6
		health = 140.0
		crash_radius = 18.0
		crash_launch = 38.0
		sound_unit_size = 55.0
		sound_range = 2600.0


func _ready() -> void:
	super()
	_build_model()
	_build_jet_lights()
	_start_sound("jet_loop")
	_apply_fade()
	_fly(0.0)
	apply_pose()


func _build_model() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var path: String = Aircraft.MODELS.get(kind, "")
	var inst: Node3D = null
	if path != "" and ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene:
			inst = scene.instantiate() as Node3D
	var aabb := AABB()
	var first := true
	if inst:
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var box := (mi as MeshInstance3D).mesh.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
	if inst == null or first:
		# No model file: a primitive stand-in, so a missing asset is visible rather than silent.
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = length * 0.06
		cap.height = length
		mi.mesh = cap
		mi.rotation.x = PI * 0.5
		mi.position.y = length * 0.08
		_visual.add_child(mi)
		_model_height = length * 0.2
	else:
		# Same fit as Aircraft._add_plane_model(): scale to the length, nose to -Z, and here the
		# wheels (the bottom of the box) on the body's origin.
		var along_x := aabb.size.x >= aabb.size.z
		var model_len := aabb.size.x if along_x else aabb.size.z
		var s := length / maxf(model_len, 0.01)
		inst.scale = Vector3.ONE * s
		inst.rotation.y = (Aircraft.KIND_MODEL_YAW.get(kind, 0.0) if along_x else 0.0)
		var centre := aabb.get_center()
		inst.position = -(inst.transform.basis * Vector3(centre.x, aabb.position.y, centre.z))
		_visual.add_child(inst)
		_model_height = aabb.size.y * s
		if kind == Aircraft.Kind.AIRLINER:
			# An invented airline's livery, painted from the model's own shape (the model's
			# texture reads as camouflage): AirportTerminal.livery_material().
			if livery < 0:
				livery = _rng.randi() % Airport.LIVERIES
			var livery_mat := AirportTerminal.livery_material(livery)
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = livery_mat
	_adopt_meshes(_visual)
	_build_shimmer()
	var h := _model_height
	_box_shape(Vector3(length * 0.12, length * 0.12, length * 0.92), Vector3(0.0, h * 0.34, 0.0))
	_box_shape(Vector3(wingspan, length * 0.035, length * 0.18), Vector3(0.0, h * 0.24, length * 0.06))
	_box_shape(Vector3(0.5, h * 0.45, length * 0.13), Vector3(0.0, h * 0.72, length * 0.42))


func _build_jet_lights() -> void:
	var h := _model_height
	var sc := length / 38.0
	var tip := wingspan * 0.5
	var tip_z := length * 0.13
	var red := Color(1.0, 0.10, 0.06, 1.0)
	var green := Color(0.15, 1.0, 0.35, 1.0)
	var white := Color(1.0, 0.98, 0.92, 1.0)
	var land := Color(1.0, 0.95, 0.82, 1.0)
	var fwd := Vector3(0.0, -0.06, -1.0).normalized()
	_build_lights([
		[Vector3(-tip, h * 0.26, tip_z), red, 0.9 * sc, LightKind.STEADY, Vector3.ZERO],
		[Vector3(tip, h * 0.26, tip_z), green, 0.9 * sc, LightKind.STEADY, Vector3.ZERO],
		[Vector3(0.0, h * 0.36, length * 0.5), white, 0.8 * sc, LightKind.STEADY, Vector3.ZERO],
		[Vector3(-tip, h * 0.26, tip_z + 0.4), white, 1.6 * sc, LightKind.STROBE, Vector3.ZERO],
		[Vector3(tip, h * 0.26, tip_z + 0.4), white, 1.6 * sc, LightKind.STROBE, Vector3.ZERO],
		[Vector3(0.0, h * 0.40, length * 0.5), white, 1.3 * sc, LightKind.STROBE, Vector3.ZERO],
		[Vector3(0.0, h * 0.47, -length * 0.05), red, 1.1 * sc, LightKind.BEACON, Vector3.ZERO],
		[Vector3(0.0, h * 0.06, length * 0.02), red, 1.1 * sc, LightKind.BEACON, Vector3.ZERO],
		[Vector3(-length * 0.075, h * 0.20, -length * 0.03), land, 2.6 * sc, LightKind.LANDING, fwd],
		[Vector3(length * 0.075, h * 0.20, -length * 0.03), land, 2.6 * sc, LightKind.LANDING, fwd],
		[Vector3(0.0, h * 0.08, -length * 0.40), land, 1.6 * sc, LightKind.LANDING, fwd],
	])


# --- Flight -----------------------------------------------------------------------------------

## Target speed on an arrival, `s` metres before the aim point.
func _approach_speed(s: float) -> float:
	if s > 5000.0:
		return approach_speeds.x + minf((s - 5000.0) * 0.004, 30.0)
	if s > 2200.0:
		return lerpf(approach_speeds.y, approach_speeds.x, (s - 2200.0) / 2800.0)
	if s > 600.0:
		return lerpf(approach_speeds.z, approach_speeds.y, (s - 600.0) / 1600.0)
	return lerpf(approach_speeds.w, approach_speeds.z, clampf(s / 600.0, 0.0, 1.0))


func _fly(dt: float) -> void:
	if phase == Phase.GROUND or phase == Phase.PARKED:
		_fly_ground(dt)
		if done:
			return
		if fading_out and _step_fade(dt):
			_finish()
		elif not fading_out and fade > 0.0:
			_step_fade(dt)
		return
	match plan:
		Plan.ARRIVAL:
			_fly_arrival(dt)
		Plan.DEPARTURE:
			_fly_departure(dt)
		Plan.CROSSING:
			speed = move_toward(speed, cruise_speed, 3.0 * dt)
			_along_route(dt, climb_attitude * 0.3)
			set_engine(0.0, 1.0)
			set_landing_lights(false)
			if d >= route.length - 1.0:
				_leave()
	if done:
		return
	_update_shimmer()
	if fading_out and _step_fade(dt):
		_finish()
	elif not fading_out and fade > 0.0:
		_step_fade(dt)


## Follows the route's own height (everything but the flare and the runway).
func _along_route(dt: float, attitude_deg: float) -> void:
	d = minf(d + speed * dt, route.length)
	var smp := route.sample(d)
	var prev := world_pos
	world_pos = smp.pos
	yaw = smp.yaw
	var bank := clampf(atan(speed * speed * float(smp.turn) / 9.8), -deg_to_rad(max_bank), deg_to_rad(max_bank))
	roll = lerp_angle(roll, bank, 1.0 - exp(-bank_rate * dt))
	pitch = lerp_angle(pitch, atan(float(smp.grade)) + deg_to_rad(attitude_deg), 1.0 - exp(-1.5 * dt))
	velocity = (world_pos - prev) / dt if dt > 0.0 else yaw_dir(yaw) * speed


## On the runway: along the centre line, at runway height plus `_h`.
func _along_runway(dt: float) -> void:
	d = minf(d + speed * dt, route.length)
	var smp := route.sample(d)
	var prev := world_pos
	world_pos = Vector3(smp.pos.x, runway_y + maxf(_h, 0.0), smp.pos.z)
	yaw = smp.yaw
	roll = lerp_angle(roll, 0.0, 1.0 - exp(-3.0 * dt))
	velocity = (world_pos - prev) / dt if dt > 0.0 else yaw_dir(yaw) * speed


func _fly_arrival(dt: float) -> void:
	var aim: float = route.marks.get("aim", route.length)
	match phase:
		Phase.AIRBORNE:
			speed = move_toward(speed, _approach_speed(aim - d), 2.2 * dt)
			_along_route(dt, approach_attitude)
			var above := world_pos.y - runway_y
			set_landing_lights(aim - d < 9000.0)
			set_engine(-2.0, 0.92)
			if above < flare_height and aim - d < 900.0:
				phase = Phase.FLARE
				_h = above
				_vs = minf(speed * float(route.sample(d).grade), -touchdown_sink)
				_vs_entry = _vs
		Phase.FLARE:
			speed = move_toward(speed, approach_speeds.w, 1.2 * dt)
			var want := maxf(-maxf(touchdown_sink, _h * flare_rate), _vs_entry)
			_vs = move_toward(_vs, want, 2.5 * dt)
			_h += _vs * dt
			pitch = lerp_angle(pitch, deg_to_rad(flare_attitude), 1.0 - exp(-1.2 * dt))
			if _h <= 0.0:
				_h = 0.0
				phase = Phase.ROLLOUT
				_since_touchdown = 0.0
				var smp := route.sample(d)
				touchdown_world = Vector3(smp.pos.x, runway_y, smp.pos.z)
			_along_runway(dt)
		Phase.ROLLOUT:
			_since_touchdown += dt
			speed = move_toward(speed, taxi_speed, rollout_decel * dt)
			# Derotation: the nose comes down over a couple of seconds.
			pitch = lerp_angle(pitch, 0.0, 1.0 - exp(-1.3 * dt))
			# Reverse thrust roars for the first seconds of the roll.
			set_engine(3.0 if _since_touchdown < 5.0 else -4.0, 1.08 if _since_touchdown < 5.0 else 0.8)
			engine_level = 0.8 if _since_touchdown < 5.0 else 0.35
			_along_runway(dt)
			if speed <= taxi_speed + 0.05:
				phase = Phase.TAXI
		Phase.TAXI:
			speed = move_toward(speed, taxi_speed, 2.0 * dt)
			set_engine(-9.0, 0.72)
			engine_level = 0.3
			set_landing_lights(false)
			_along_runway(dt)
			# AirportGround takes an airliner off the runway to a free gate (once it has rolled
			# out); with no gate free, or the way blocked, it fades out at the runway end as before.
			if not _asked_ground:
				_asked_ground = true
				var ctl := _ground_ctl()
				if ctl and ctl.claim_arrival(self):
					return
			if d >= float(route.marks.get("fade_start", route.length - 60.0)):
				fading_out = true
			if d >= route.length - 0.5:
				fading_out = true
				fade = maxf(fade, 0.98)


func _fly_departure(dt: float) -> void:
	var lift: float = route.marks.get("liftoff", 0.0)
	match phase:
		Phase.LINEUP:
			set_engine(-10.0, 0.7)
			engine_level = 0.3
			set_landing_lights(true)
			_along_runway(0.0)
			velocity = Vector3.ZERO
			pitch = 0.0
			set_ground_lights(true, true)
			var ctl := _ground_ctl()
			# Held while an arrival crosses the runway it is about to roll down.
			if fade < 0.001 and not (ctl and ctl.runway_held_for(self)):
				_hold_left -= dt
				if _hold_left <= 0.0:
					phase = Phase.ROLL
		Phase.ROLL:
			speed += roll_accel * dt
			var spool := clampf(speed / liftoff_speed, 0.0, 1.0)
			set_engine(lerpf(-2.0, 4.0, spool), lerpf(0.85, 1.1, spool))
			engine_level = lerpf(0.6, 1.0, spool)
			_along_runway(dt)
			# The nose comes up over the last few metres per second before lift-off.
			var rot := clampf((speed - (liftoff_speed - 7.0)) / 7.0, 0.0, 1.0)
			pitch = deg_to_rad(rotate_attitude) * rot
			if d >= lift:
				phase = Phase.AIRBORNE
		Phase.AIRBORNE:
			var climbed := d - lift
			var target := climb_speed if climbed < 3000.0 else cruise_speed
			speed = move_toward(speed, target, (2.4 if climbed < 3000.0 else 1.2) * dt)
			var att := lerpf(rotate_attitude - atan(float(route.sample(d).grade)) * 57.3, climb_attitude, clampf(climbed / 400.0, 0.0, 1.0))
			_along_route(dt, att)
			set_engine(3.0 if climbed < 2500.0 else 0.0, 1.05)
			set_landing_lights(world_pos.y < 900.0)
			if d >= route.length - 1.0:
				_leave()
			elif climbed > 1500.0:
				var cam := _camera()
				if cam and cam.global_position.distance_to(global_position) > despawn_distance:
					_leave()


# --- On the ground (AirportGround) ---------------------------------------------------------

## On the field under AirportGround's control (taxiing, pushing, at a stand), not yet a departure
## lined up or an arrival rolling out.
func on_stand_or_taxi() -> bool:
	return phase == Phase.GROUND or phase == Phase.PARKED


func _ground_ctl() -> AirportGround:
	if traffic == null:
		return null
	var g: Variant = traffic.get("ground")
	return g as AirportGround


## Drives `legs` from the start of the first (AirportGround builds them; `on_done` is called
## when the last one ends, with the jet standing).
func start_ground(legs: Array, on_done: Callable = Callable()) -> void:
	ground_legs = legs
	ground_leg = 0
	ground_done = on_done
	d = 0.0
	phase = Phase.GROUND
	ground_wait = float(legs[0].get("wait", 0.0)) if not legs.is_empty() else 0.0
	_leg_entered = false
	set_landing_lights(false)
	set_ground_lights(engine_level > 0.05, false)


## Standing at a gate, engines off, lights out but the nav lights.
func park() -> void:
	phase = Phase.PARKED
	speed = 0.0
	velocity = Vector3.ZERO
	ground_legs = []
	engine_level = 0.0
	set_ground_lights(false, false)
	set_landing_lights(false)


## Beacons (red, while the engines run) and strobes (white, on the runway).
func set_ground_lights(beacon: bool, strobe: bool) -> void:
	if _light_mat:
		_light_mat.set_shader_parameter("beacon_on", 1.0 if beacon else 0.0)
		_light_mat.set_shader_parameter("strobe_on", 1.0 if strobe else 0.0)


## Where along the current leg the jet stands, its route and the leg itself.
func ground_leg_data() -> Dictionary:
	return ground_legs[ground_leg] if ground_leg < ground_legs.size() else {}


func _fly_ground(dt: float) -> void:
	var ctl := _ground_ctl()
	_engine_sound()
	if phase == Phase.PARKED or ground_leg >= ground_legs.size():
		velocity = Vector3.ZERO
		_update_shimmer()
		return
	var leg: Dictionary = ground_legs[ground_leg]
	var r: AirRoute = leg.route
	if not _leg_entered:
		# At the start of a leg: its wait, then whatever it must be cleared for.
		if ground_wait > 0.0:
			ground_wait -= dt
			speed = 0.0
			_ground_pose(r, 0.0, bool(leg.reverse), dt)
			return
		var tag: String = leg.get("tag", "")
		if tag != "" and ctl and not ctl.may_enter(self, tag):
			speed = 0.0
			_ground_pose(r, 0.0, bool(leg.reverse), dt)
			return
		_leg_entered = true
	var limit := _leg_limit(leg, d)
	# Something ahead (another jet, a flyable jet, a tagged leg it is not cleared into): stop
	# short of it.
	var room := ctl.room_ahead(self) if ctl else INF
	if room < INF:
		limit = minf(limit, sqrt(2.0 * ground_brake * maxf(room, 0.0)))
	var acc := ground_accel if limit > speed else ground_brake * 1.6
	speed = move_toward(speed, limit, acc * dt)
	d += speed * dt
	if d >= r.length - 0.02:
		var carry := d - r.length
		d = r.length
		_ground_pose(r, d, bool(leg.reverse), dt)
		ground_leg += 1
		if bool(leg.get("stop", false)):
			speed = 0.0
			carry = 0.0
		if ground_leg >= ground_legs.size():
			speed = 0.0
			if ground_done.is_valid():
				ground_done.call(self)
			return
		d = minf(maxf(carry, 0.0), 0.5) if carry > 0.0 else 0.0
		var nxt: Dictionary = ground_legs[ground_leg]
		ground_wait = float(nxt.get("wait", 0.0))
		_leg_entered = false
		return
	_ground_pose(r, d, bool(leg.reverse), dt)
	_update_shimmer()


## The speed allowed at `at` metres into `leg` (its precomputed profile: straights, turns, the
## stop at the end and the next leg's start).
func _leg_limit(leg: Dictionary, at: float) -> float:
	var prof: PackedFloat32Array = leg.prof
	var r: AirRoute = leg.route
	var i := r.index_at(at)
	var j := mini(i + 1, prof.size() - 1)
	var span := maxf(r.dist[j] - r.dist[i], 0.001)
	# Never quite zero inside a leg, or a jet that braked to its end would stop a hair short.
	return maxf(lerpf(prof[i], prof[j], clampf((at - r.dist[i]) / span, 0.0, 1.0)), 0.35)


func _ground_pose(r: AirRoute, at: float, reverse: bool, dt: float) -> void:
	var smp := r.sample(at)
	var prev := world_pos
	var p: Vector3 = smp.pos
	var ctl := _ground_ctl()
	var y := ctl.surface_y(Vector2(p.x, p.z)) if ctl else runway_y
	world_pos = Vector3(p.x, y, p.z)
	yaw = float(smp.yaw) + (PI if reverse else 0.0)
	pitch = lerp_angle(pitch, 0.0, 1.0 - exp(-2.0 * dt)) if dt > 0.0 else 0.0
	roll = lerp_angle(roll, 0.0, 1.0 - exp(-3.0 * dt)) if dt > 0.0 else 0.0
	velocity = (world_pos - prev) / dt if dt > 0.0 else Vector3.ZERO


## The engine loop by `engine_level`: silent off, the idle whine, a roar at take-off thrust.
func _engine_sound() -> void:
	if engine_level <= 0.01:
		set_engine(-60.0, 0.4)
	else:
		set_engine(lerpf(-22.0, -9.0, clampf(engine_level / 0.3, 0.0, 1.0)) + maxf(engine_level - 0.3, 0.0) * 18.0, lerpf(0.42, 0.72, clampf(engine_level / 0.3, 0.0, 1.0)) + maxf(engine_level - 0.3, 0.0) * 0.5)


# --- Heat behind the engines --------------------------------------------------------------

## Where each engine's exhaust is, in the jet's frame (measured off the models: the airliner's
## wing-mounted pair, the private jet's pods either side of the tail), fitted to `length`.
func engine_spots() -> Array[Vector3]:
	var k := length / 38.0 if kind == Aircraft.Kind.AIRLINER else length / 20.0
	if kind == Aircraft.Kind.AIRLINER:
		return [Vector3(-5.0, 2.2, -0.4) * k, Vector3(5.0, 2.2, -0.4) * k]
	return [Vector3(-1.25, 3.5, 7.7) * k, Vector3(1.25, 3.5, 7.7) * k]


## A cone of shimmering air behind each engine (shaders/jet_exhaust.gdshader reads the screen):
## desktop only (on the web that is a full back-buffer copy per draw), within `shimmer_range`.
func _build_shimmer() -> void:
	if OS.has_feature("web") or not shimmer_enabled:
		return
	if _shimmer_shader == null:
		_shimmer_shader = load("res://shaders/jet_exhaust.gdshader")
	_shimmer_mat = ShaderMaterial.new()
	_shimmer_mat.shader = _shimmer_shader
	_shimmer_mat.render_priority = Material.RENDER_PRIORITY_MIN
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 12
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var scale_k := length / 38.0
	for spot in engine_spots():
		var mi := MeshInstance3D.new()
		mi.name = "Exhaust%d" % _shimmers.size()
		mi.mesh = cone
		mi.material_override = _shimmer_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.visibility_range_end = shimmer_range
		# The cylinder's axis is Y: laid along +Z (aft), its top (the narrow end) at the nozzle.
		var length_m := 26.0 * scale_k
		var radius := 2.2 * scale_k
		mi.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled_local(Vector3(radius, length_m, radius)), spot + Vector3(0.0, 0.0, length_m * 0.5))
		mi.visible = false
		_visual.add_child(mi)
		_shimmers.append(mi)


func _update_shimmer() -> void:
	if _shimmer_mat == null:
		return
	var on := engine_level > 0.02 and life == Life.FLYING
	for m in _shimmers:
		m.visible = on
	if on:
		_shimmer_mat.set_shader_parameter("strength", clampf(engine_level, 0.0, 1.0))


## Gone for good (off the end of its route or far past the far plane): no fade needed.
func _leave() -> void:
	_finish()


func _on_ground() -> bool:
	return phase in [Phase.LINEUP, Phase.ROLL, Phase.ROLLOUT, Phase.TAXI, Phase.GROUND, Phase.PARKED]


func _begin_fall() -> void:
	if _on_ground():
		return
	velocity = yaw_dir(yaw) * speed + Vector3.UP * velocity.y


## A shot-down jet keeps most of its speed, loses its lift, noses over and rolls into the dive.
func _fall_motion(dt: float) -> void:
	velocity.y -= 7.5 * dt
	velocity *= 1.0 - 0.04 * dt
	world_pos += velocity * dt
	var horiz := Vector2(velocity.x, velocity.z).length()
	pitch = lerp_angle(pitch, atan2(velocity.y, maxf(horiz, 1.0)) - 0.08, 1.0 - exp(-1.5 * dt))
	roll += deg_to_rad(38.0) * dt
	set_engine(2.0, 0.8)


func _smoke_origin() -> Vector3:
	return Vector3(wingspan * 0.18, _model_height * 0.2, 0.0)
