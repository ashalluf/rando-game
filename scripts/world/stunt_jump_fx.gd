class_name StuntJumpFX
extends RefCounted
## What a car's jump off a stunt piece looks like (wave 8 refcam `stunt_jump`, docs/HANDOFF.md
## "The stunt jump off the freeway pair"):
##  - the air it flies through is clear: the freeway pair's flight box (StuntRamps' "flight" key on
##    the launch site, pure) collapses the tree crowns standing in it, after every roll
##    (`clear_flights()`, a _run_last step of the FULL chunks it reaches) - the right of way's
##    eucalyptus row stood in the arc and the car flew through a crown;
##  - a launch kicks up the run-up: a rolling dust cloud where the tyres leave the dirt for the
##    plate, a dust trail down the run-up, grit and rust flakes shaken off the deck at the lip
##    (`launch()`, called by StuntDirector the moment it arms a lip for a car);
##  - a touch-down throws dust and, on steel, a spray of sparks (`land()`);
##  - an airborne car's wheels hang on their springs to the stop (`HANG` in Vehicle._update_wheels
##    through `hang()`; a placed, kinematic car via `hang_pose()`).
## The bursts are one-shot CPUParticles3D under the scene root (they ride the origin shift),
## `MAX_BURSTS` alive at once, freed when done; `stage()` builds them already `age` seconds old
## (preprocess) for stills. RC5_STUNT_JUMP=0 in the environment: none of it (the A/B).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_STUNT_JUMP") != "0"

## The flight box's room either side of the deck's width (m) and past the landing's end.
const FLIGHT_SIDE := 5.0
## Batch keys collapsed in a flight box: tree crowns only (shrubs and hedges are under the arc).
const CROWN_KEYS := ["tree_", "la_", "palm_"]
## How far an airborne wheel hangs below its rest (m): to the spring's stop.
const HANG := 0.17
## Seconds for a wheel to drop to the stop once the car is off the ground.
const HANG_SECONDS := 0.18
## Bursts alive at once (each is a few emitters).
const MAX_BURSTS := 4
## Dust colours: the right of way's dry dirt, lit; grit and rust flakes.
const DUST := Color(0.70, 0.62, 0.50)
const GRIT := Color(0.24, 0.20, 0.17)

static var bursts_made: int = 0
static var _bursts: Array = []
static var _dust_mat: Material = null
static var _grit_mesh: Mesh = null
static var _spark_mat: ShaderMaterial = null
## Landing watch (one player car at a time).
static var _flying_id: int = 0
static var _flying_air: float = 0.0


## The box a pair's jump flies through, from the launch's foot to the landing's end: {c, dir
## (unit, the ride), hl, hw} in the XZ plane. Pure.
static func flight_box(foot: Vector2, ride: Vector2, end: Vector2, w: float) -> Dictionary:
	var c := (foot + end) * 0.5
	return {"c": c, "dir": ride.normalized(), "hl": foot.distance_to(end) * 0.5 + 4.0, "hw": w * 0.5 + FLIGHT_SIDE}


static func _flight_rect(f: Dictionary) -> Rect2:
	var d: Vector2 = f.dir
	var a := Vector2(-d.y, d.x)
	return Footbridges._turned_rect(f.c, d, a, float(f.hl), float(f.hw))


static func in_flight(f: Dictionary, p: Vector2) -> bool:
	var q: Vector2 = p - (f.c as Vector2)
	var d: Vector2 = f.dir
	return absf(q.dot(d)) <= float(f.hl) and absf(q.dot(Vector2(-d.y, d.x))) <= float(f.hw)


## The flight boxes of every freeway pair reaching `rect` (true world XZ).
static func flights_in(plan: CityPlan, rect: Rect2) -> Array:
	var out: Array = []
	if not enabled:
		return out
	for s: Dictionary in StuntRamps.freeway_sites(plan):
		if s.has("flight") and _flight_rect(s.flight).intersects(rect):
			out.append(s.flight)
	return out


## Collapses this chunk's tree crowns standing in the flight boxes (every roll already made).
static func clear_flights(ch: CityChunk, flights: Array) -> void:
	var batches: Dictionary = ch._batch._batches
	var zero := Basis().scaled(Vector3(0.0001, 0.0001, 0.0001))
	var hidden := 0
	for key: String in batches:
		var crown := false
		for pre: String in CROWN_KEYS:
			if key.begins_with(pre):
				crown = true
		if not crown:
			continue
		var xforms: Array = batches[key].xforms
		for i in xforms.size():
			var xf: Transform3D = xforms[i]
			var p := Vector2(xf.origin.x, xf.origin.z)
			for f: Dictionary in flights:
				if in_flight(f, p):
					xforms[i] = Transform3D(zero, xf.origin)
					hidden += 1
					break
	ch.set_meta("stunt_flight_cleared", int(ch.get_meta("stunt_flight_cleared", 0)) + hidden)


# --- The wheels ----------------------------------------------------------------------------------

## A physical car's airborne wheel offset (m, negative = down) eased toward the stop; `cur` the
## offset the springs give, `air` seconds off the ground. Vehicle._update_wheels asks it.
static func hang(cur: float, air: float, limit: float) -> float:
	if not enabled or air <= 0.0:
		return cur
	var k := clampf(air / HANG_SECONDS, 0.0, 1.0)
	return minf(cur, lerpf(cur, -minf(HANG, limit), k * k * (3.0 - 2.0 * k)))


## A placed car (no physics wheels): every wheel at the stop now.
static func hang_pose(car: Vehicle) -> void:
	if not enabled or car == null:
		return
	var limit := car.suspension_travel + car.suspension_rest_length * 0.5
	for rig: Array in car._wheel_rigs:
		(rig[0] as Node3D).position.y = float(rig[5]) - minf(HANG, limit)


# --- The bursts ----------------------------------------------------------------------------------

static func _dust_material() -> Material:
	if _dust_mat == null:
		_dust_mat = DrivingFX._puff_material(Color(1.0, 1.0, 1.0), 0.7)
	return _dust_mat


static func _parent(near: Node) -> Node:
	var tree := near.get_tree() if near != null and near.is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root


static func _emitter(parent: Node, at: Vector3, amount: int, life: float, mesh: Mesh) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.visibility_aabb = AABB(Vector3(-30.0, -6.0, -30.0), Vector3(60.0, 30.0, 60.0))
	parent.add_child(p)
	p.global_position = at
	return p


## A rolling dust cloud at `at` (local space), thrown along `dir` (unit, world) at `push` m/s,
## `size` metres a puff.
static func _dust(parent: Node, at: Vector3, dir: Vector3, push: float, size: float, amount: int, box: Vector3, age: float, axis := Basis()) -> CPUParticles3D:
	var quad := QuadMesh.new()
	quad.material = _dust_material()
	var p := _emitter(parent, at, amount, 3.6, quad)
	p.global_basis = axis
	p.lifetime_randomness = 0.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = axis.inverse() * (dir + Vector3.UP * 0.35).normalized()
	p.spread = 55.0
	p.initial_velocity_min = push * 0.3
	p.initial_velocity_max = push
	p.gravity = Vector3(0.0, 0.35, 0.0)
	p.damping_min = 1.6
	p.damping_max = 3.2
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.3
	p.scale_amount_curve = DrivingFX._grow_curve(0.3)
	p.color = DUST
	p.color_ramp = WeaponFX._ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.0)])
	p.preprocess = age
	p.emitting = true
	return p


static func _grit(parent: Node, at: Vector3, vel: Vector3, amount: int, age: float) -> CPUParticles3D:
	if _grit_mesh == null:
		var b := BoxMesh.new()
		b.size = Vector3(0.035, 0.012, 0.028)
		var m := StandardMaterial3D.new()
		m.albedo_color = GRIT
		m.roughness = 0.9
		m.vertex_color_use_as_albedo = true
		b.material = m
		_grit_mesh = b
	var p := _emitter(parent, at, amount, 2.4, _grit_mesh)
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.2, 0.05, 0.4)
	p.direction = vel.normalized()
	p.spread = 22.0
	p.initial_velocity_min = vel.length() * 0.35
	p.initial_velocity_max = vel.length() * 0.75
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 2.2
	p.color = Color(1, 1, 1)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.30, 0.24, 0.19))
	ramp.set_color(1, Color(0.42, 0.24, 0.12))
	p.color_initial_ramp = ramp
	p.preprocess = age
	p.emitting = true
	return p


static func _sparks(parent: Node, at: Vector3, vel: Vector3, age: float) -> CPUParticles3D:
	if _spark_mat == null:
		_spark_mat = ShaderMaterial.new()
		_spark_mat.shader = load("res://shaders/spark_streak.gdshader")
	var quad := QuadMesh.new()
	quad.material = _spark_mat
	var p := _emitter(parent, at, 40, 0.6, quad)
	p.lifetime_randomness = 0.5
	p.particle_flag_align_y = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = (vel.normalized() + Vector3.UP * 0.3).normalized()
	p.spread = 35.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 16.0
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.09
	p.preprocess = age
	p.emitting = true
	return p


static func _keep(parent: Node, list: Array) -> void:
	_bursts.append(list)
	bursts_made += 1
	while _bursts.size() > MAX_BURSTS:
		for e: Variant in _bursts.pop_front():
			if is_instance_valid(e):
				(e as Node).queue_free()
	var tree := parent.get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(6.0, false)
	timer.timeout.connect(func() -> void:
		for e: Variant in list:
			if is_instance_valid(e):
				(e as Node).queue_free()
		_bursts.erase(list))


## A launch off `site`'s lip: the run-up's dust and the lip's grit. `car` the car leaving it (or
## null on foot: nothing), `vel` its velocity (world). `age` seconds since the lip (stills).
static func launch(car: Node3D, site: Dictionary, vel: Vector3, age := 0.0) -> Array:
	var out: Array = []
	if not enabled or car == null or not site.has("len"):
		return out
	var parent := _parent(car)
	if parent == null:
		return out
	var xf := StuntBuild.xform(site)
	var lip: Array = StuntRamps.lips(site)[0]
	var ride := (xf.basis * (lip[1] as Vector3)).normalized()
	var w := float(site.get("w", 3.0))
	var len := float(site.len)
	var speed := vel.length()
	var axis := Basis(ride.cross(Vector3.UP).normalized(), Vector3.UP, -ride)
	# Where the tyres left the run-up for the plate: a cloud rolling on along the ride and out.
	var foot := WorldState.to_local(xf * Vector3(0.0, 0.3, -0.6))
	var t_foot := age + len / maxf(speed, 1.0)
	out.append(_dust(parent, foot, ride, clampf(speed * 0.22, 3.0, 8.0), 2.6, 26, Vector3(w * 0.5, 0.2, 1.2), t_foot, axis))
	# The trail down the run-up behind it, older the further back.
	var trail := WorldState.to_local(xf * Vector3(0.0, 0.25, -9.0))
	out.append(_dust(parent, trail, ride * 0.3, 2.5, 2.0, 30, Vector3(w * 0.42, 0.15, 8.0), t_foot + 0.25, axis))
	# The lip: grit, rust and a puff shaken off the plate as the suspension unloads.
	var lip_w := WorldState.to_local(xf * (lip[0] as Vector3) + Vector3.UP * 0.2)
	out.append(_grit(parent, lip_w, vel, 60, age))
	out.append(_dust(parent, lip_w, vel.normalized(), clampf(speed * 0.35, 3.0, 11.0), 2.4, 18, Vector3(w * 0.4, 0.1, 0.3), age, axis))
	_keep(parent, out)
	return out


## A touch-down at `at` (true world) at `vel`: dust, and sparks off steel or concrete.
static func land(car: Node3D, at: Vector3, vel: Vector3, steel := true, age := 0.0) -> Array:
	var out: Array = []
	if not enabled or car == null:
		return out
	var parent := _parent(car)
	if parent == null:
		return out
	var flat := Vector3(vel.x, 0.0, vel.z)
	var dir := flat.normalized() if flat.length() > 0.5 else Vector3.FORWARD
	var axis := Basis(dir.cross(Vector3.UP).normalized(), Vector3.UP, -dir)
	var p := WorldState.to_local(at)
	out.append(_dust(parent, p, dir, clampf(flat.length() * 0.3, 3.0, 9.0), 2.2, 24, Vector3(1.4, 0.15, 1.8), age, axis))
	if steel:
		out.append(_sparks(parent, p + Vector3.UP * 0.2, flat, age))
	_keep(parent, out)
	return out


## One physics tick of the player's car near the pieces (StuntDirector.watch): a car that was
## launched and comes back down after a real flight lands with a burst.
static func tick(car: Vehicle, armed: bool, air: bool, delta: float) -> void:
	if not enabled or car == null:
		return
	var id := car.get_instance_id()
	if air:
		if armed or _flying_id == id:
			_flying_id = id
			_flying_air += delta
		return
	if _flying_id == id and _flying_air > 0.5:
		land(car, WorldState.to_world(car.global_position), car.linear_velocity)
	_flying_id = 0
	_flying_air = 0.0


## A still: the bursts of a launch off `site` `t` s ago at `speed`, and the car's wheels hung.
static func stage(car: Vehicle, site: Dictionary, _speed: float, t: float, vel: Vector3) -> void:
	if not enabled:
		return
	hang_pose(car)
	launch(car, site, vel, t)
