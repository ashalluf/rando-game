class_name Boat
extends Vehicle
## The player's boats: the SALTRUNNER 24 speedboat and the WAVEKITE jet ski (BoatKit's meshes),
## moored at the marina's east headwalk (BoatMoorings) and entered like a car (interact). A boat
## is a Vehicle with no wheels: everything else - the enter / exit contract, PhysicsBudget, the
## engine voice (EngineAudio, meta engine_profile), the bumper, the jump and the car's flight -
## is the car's.
##
## It floats on the water that is DRAWN: SwimWater gives the surface under a point (the sea and
## the bay through SeaSurface - ocean.gdshader's Gerstner swells and surf worked out in GDScript,
## as Surf mirrors the surf -, the marina's basin, the lakes), sampled at three points of the
## hull (the bow, the stern quarters) and fitted with a plane, so a hull rides the swell's slope.
## Buoyancy pushes up at HULL_POINTS by how deep each is (a spring with critical-ish damping), the
## keel resists sideways slip, the drag sets the top speed, the propulsion pushes only while the
## stern is wet, the hull lifts onto the plane with speed (and the bow with it, over the hump),
## the jet ski leans into its turns. Out of the water the car's flight takes over (Vehicle._fly).
##
## The water has no floor (the city's GroundBody is at y 0 under the sea and the basin), so a boat
## over water carries a collision exception with the GroundBody - Swim's rule for the swimmer -
## and drops it once it is out over land with its keel above the ground; on the sand it grounds
## on the beach's own collision and stops: beached.
##
## Damage is the boat's own (`health`, no CarDamage): rounds, blasts and crashes take it down; at
## zero it blows up (Explosion.blast), throws the driver out, burns and sinks stern first, and
## goes once it is under. `BOATS=0` in the environment: no boats (the A/B, BoatMoorings).

@export_group("Boat")
## Thrust at full throttle as an acceleration (m/s^2); boost multiplies it (nitro_multiplier).
@export var thrust_accel: float = 7.0
## Top speed on the plane at full throttle (m/s): sets the drag.
@export var boat_top_speed: float = 22.0
## Astern thrust share.
@export var reverse_share: float = 0.35
## Turn rate at full lock and speed (rad/s).
@export var turn_rate: float = 1.15
## Sideways (keel) drag per second while wet: how hard the hull carves instead of skidding.
@export var keel_drag: float = 2.6
## Lean into a turn (rad at full lock and speed): the jet ski's is large.
@export var turn_lean: float = 0.12
## Bow rise over the hump (rad, at about a third of top speed) and how much of the hull's weight
## the plane carries at top speed.
@export var hump_trim: float = 0.09
@export var plane_lift: float = 0.35
## Buoyancy: how deep the hull points sit at rest (m) and the damping share of critical.
@export var rest_draft: float = 0.3
@export var buoy_damping: float = 0.55
## Hop out of the water (m/s up), and how hard a landing must be (m/s down) to slap and splash.
@export var hop_speed: float = 6.5
@export var slap_speed: float = 3.0

@export_group("Damage")
@export var max_boat_health: float = 600.0
## Damage per rifle round's damage point, per blast at its centre, per m/s of crash over the limit.
@export var bullet_gain: float = 1.3
@export var blast_damage: float = 900.0
@export var crash_gain: float = 18.0
## How long the wreck takes to go under (s) and how long it stays on the bottom.
@export var sink_seconds: float = 9.0
@export var sunk_seconds: float = 25.0

static var enabled: bool = OS.get_environment("BOATS") != "0"
## Metres offshore past which the world layer leaves the mask (_ground_rule()).
const OPEN_SEA := 22.0
## The guard's caps (m/s): the boat's own climb (a hop, the flight on boost) stays well under.
const MAX_RISE := 35.0
const MAX_SPEED := 90.0
static var _debug: bool = OS.get_environment("BOAT_DEBUG") == "1"

var kind: int = BoatKit.Kind.SPEEDBOAT
## The hull graphic's accent (BoatKit.ACCENTS) and the upholstery canvas (Marina.CANVAS).
var accent: int = 0
var canvas: int = 0
var boat_paint: Color = Color(0.93, 0.93, 0.92)
var health: float = 600.0
## 0..1 how much of the hull is in the water (the share of HULL_POINTS wet), last tick.
var wet: float = 0.0
## The water under the boat last tick (SwimWater.at()): {} over land.
var water: Dictionary = {}
## Burning / sinking, and when it went (physics clock, s).
var sinking: bool = false
var sink_t: float = 0.0
var throttle: float = 0.0

var _points: PackedVector3Array = PackedVector3Array()
var _sea: Array = []
var _dbg_v: float = 0.0
var _sea_age: float = 9.0
var _ground: StaticBody3D
var _ground_excepted: bool = false
var _fx: BoatWake
var _rider: BoatRidePose
var _rider_of: Node3D
var _prev_vy: float = 0.0
var _clock: float = 0.0
var _lod_nodes: Array[MeshInstance3D] = []
var _hull_sound: AudioStreamPlayer3D
var _fire: CPUParticles3D
var _smoke: CPUParticles3D
## The roll the driver asks for (into the turn, rad) and the water plane's slope under the hull.
var _lean_target: float = 0.0
## The bow sample's water (SwimWater.Kind) and how far offshore it is at sea.
var _kind: int = 0
var _offshore: float = 0.0
## The world layer is off the mask (out at sea).
var _open_sea: bool = false
var _slope: Vector2 = Vector2.ZERO


## Set up before adding to the tree. `look` is a hash (paint, accent, upholstery).
func setup_boat(k: int, look: int) -> void:
	kind = k
	var paints := [Color(0.93, 0.93, 0.92), Color(0.06, 0.07, 0.09), Color(0.72, 0.06, 0.06), Color(0.05, 0.16, 0.38),
		Color(0.83, 0.84, 0.86), Color(0.02, 0.36, 0.42), Color(0.96, 0.78, 0.1)]
	boat_paint = paints[absi(look) % paints.size()]
	accent = absi(look / 7) % BoatKit.ACCENTS.size()
	# An accent the same as the hull reads as no graphic: take the next.
	if boat_paint.get_luminance() < 0.1 and accent == 0:
		accent = 4
	canvas = absi(look / 53) % 6
	body_type = BodyType.SEDAN
	paint = boat_paint
	if k == BoatKit.Kind.JETSKI:
		set_meta("engine_profile", "moto")
		thrust_accel = 9.5
		boat_top_speed = 24.0
		turn_rate = 2.1
		keel_drag = 3.2
		turn_lean = 0.42
		hump_trim = 0.05
		plane_lift = 0.25
		rest_draft = 0.17
		hop_speed = 7.5
		max_boat_health = 320.0
		enter_radius = 3.0
	else:
		set_meta("engine_profile", "v8")
		enter_radius = 5.0
	health = max_boat_health


func display_name() -> String:
	return "Wavekite" if kind == BoatKit.Kind.JETSKI else "Saltrunner 24"


func can_take_damage() -> bool:
	return false


func is_wreck() -> bool:
	return sinking


func has_headlights() -> bool:
	return false


func lights_running() -> bool:
	return false


func road_lift() -> float:
	return rest_draft


## Sinks into the hull points' rest draft: what the moorings place it at.
func rest_height(surface: float) -> float:
	return surface


func _ready() -> void:
	super()
	var s: Vector2 = BoatKit.SIZE[kind]
	mass = 1900.0 if kind == BoatKit.Kind.SPEEDBOAT else 380.0
	angular_damp = 0.4
	linear_damp = 0.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.05, 0.25 if kind == BoatKit.Kind.SPEEDBOAT else 0.15)
	# Hull points: three stations, two across, on the bottom (rest_draft under the waterline).
	var half := s.x * 0.5
	for st: Array in [[-0.36, 0.42], [0.0, 0.62], [0.36, 0.7]]:
		for side: float in [-1.0, 1.0]:
			_points.append(Vector3(side * s.y * 0.5 * float(st[1]) * 0.8, -rest_draft, float(st[0]) * half * 2.0))
	# Over water from the first step: a hull put on the water already reaches under the ground
	# box's top (y 0), and the depenetration would throw it in the air before the first tick.
	_set_ground_exception(true)
	_fx = BoatWake.new()
	_fx.boat = self
	add_child(_fx)
	# A body near the camera is simulated; moored boats far off freeze (set_script_active()).
	contact_monitor = true
	max_contacts_reported = 4


func _build() -> void:
	var s: Vector2 = BoatKit.SIZE[kind]
	_has_model = true
	var holder := Node3D.new()
	holder.name = "BodyModel"
	add_child(holder)
	var mat := BoatKit.material(boat_paint, canvas)
	var ranges := [[0.0, 45.0], [45.0, 160.0], [160.0, 700.0]] if kind == BoatKit.Kind.SPEEDBOAT else [[0.0, 30.0], [30.0, 110.0], [110.0, 420.0]]
	for lv in 3:
		var mi := MeshInstance3D.new()
		mi.name = "Hull%d" % lv
		mi.mesh = BoatKit.mesh(kind, lv, accent)
		mi.material_override = mat
		mi.visibility_range_begin = float(ranges[lv][0])
		mi.visibility_range_end = float(ranges[lv][1])
		mi.visibility_range_begin_margin = 2.0 if lv > 0 else 0.0
		mi.visibility_range_end_margin = 2.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lv < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		_lod_nodes.append(mi)
	# Collision: the hull (its keel at -0.3) and the cockpit's coaming.
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	if kind == BoatKit.Kind.SPEEDBOAT:
		box.size = Vector3(s.y * 0.86, 1.1, s.x * 0.9)
		col.position = Vector3(0.0, 0.25, 0.1)
	else:
		box.size = Vector3(s.y * 0.85, 0.8, s.x * 0.9)
		col.position = Vector3(0.0, 0.12, 0.05)
	col.shape = box
	add_child(col)
	_seat = Node3D.new()
	_seat.name = "Seat"
	_seat.position = BoatKit.SEAT[kind]
	add_child(_seat)
	_model_top_y = 1.6 if kind == BoatKit.Kind.SPEEDBOAT else 1.1
	# The bumper: a boat running into a swimmer or someone on a dock's edge throws them.
	var bumper := Area3D.new()
	bumper.collision_layer = 0
	bumper.collision_mask = 2 | 8
	bumper.monitorable = false
	var bshape := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(s.y, 1.4, s.x * 0.5)
	bshape.shape = bbox
	bshape.position = Vector3(0.0, 0.4, -s.x * 0.3)
	bumper.add_child(bshape)
	bumper.body_entered.connect(_on_bumper_hit)
	add_child(bumper)


func exit_candidates() -> Array[Vector3]:
	var side := Vector3(global_basis.x.x, 0.0, global_basis.x.z)
	side = side.normalized() if side.length() > 0.2 else Vector3.RIGHT
	var fwd := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	fwd = fwd.normalized() if fwd.length() > 0.2 else Vector3.FORWARD
	var s: Vector2 = BoatKit.SIZE[kind]
	var base := global_position + Vector3.UP * 0.9
	var reach := s.y * 0.5 + 0.9
	return [base + side * reach, base - side * reach, base - fwd * (s.x * 0.5 + 1.2), base + fwd * (s.x * 0.5 + 1.2), global_position + Vector3.UP * 2.2]


func settle() -> void:
	pass


## PhysicsBudget switches a far car's script off; a boat's buoyancy IS its script, so an empty one
## is frozen where it floats (no wheels, so freezing it is safe) and thawed when it comes near.
func set_script_active(on: bool) -> void:
	if on == is_physics_processing():
		return
	if not on and driver == null:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	elif on and freeze and not sinking:
		freeze = false
	set_physics_process(on)


func is_airborne() -> bool:
	return wet < 0.01 and not _touching()


func _touching() -> bool:
	return get_contact_count() > 0


func take_hit(_shape_index: int, damage: float, dir: Vector3, at: Vector3 = Vector3.INF, k: int = HIT_PROP) -> void:
	if sinking:
		return
	var dmg := 0.0
	match k:
		HIT_BULLET, HIT_PELLET:
			dmg = damage * bullet_gain
		HIT_BLAST:
			dmg = damage * blast_damage
			if freeze:
				freeze = false
			apply_central_impulse((dir + Vector3.UP * 0.6).normalized() * damage * 9.0 * mass)
		HIT_CRASH:
			dmg = damage * crash_gain
		_:
			dmg = damage
	if at != Vector3.INF and k != HIT_CRASH and is_inside_tree():
		_fx.hit_spark(at, dir)
	health = maxf(health - dmg, 0.0)
	if health <= 0.0:
		destroy()


## Blows it up: the blast, the driver thrown clear, fire and smoke, and it starts to sink.
func destroy() -> void:
	if sinking:
		return
	sinking = true
	sink_t = _clock
	health = 0.0
	var d := driver
	if d != null and d.has_method("exit_vehicle"):
		d.call("exit_vehicle")
		if d.has_method("launch"):
			d.call("launch", Vector3(randf_range(-4.0, 4.0), 13.0, randf_range(-4.0, 4.0)))
	if freeze:
		freeze = false
	set_physics_process(true)
	if is_inside_tree():
		Explosion.blast(self, global_position + Vector3.UP * 0.6, 7.0 if kind == BoatKit.Kind.SPEEDBOAT else 5.0, 12.0, 16.0, self)
		_start_fire()
		for mi in _lod_nodes:
			var m := mi.material_override as ShaderMaterial
			if m:
				m = m.duplicate() as ShaderMaterial
				m.set_shader_parameter("solo_paint", Vector3(0.05, 0.045, 0.04))
				mi.material_override = m


func _start_fire() -> void:
	_fire = CPUParticles3D.new()
	_fire.amount = 36
	_fire.lifetime = 0.9
	_fire.local_coords = false
	_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var s: Vector2 = BoatKit.SIZE[kind]
	_fire.emission_box_extents = Vector3(s.y * 0.3, 0.2, s.x * 0.3)
	_fire.direction = Vector3.UP
	_fire.spread = 12.0
	_fire.initial_velocity_min = 2.0
	_fire.initial_velocity_max = 4.5
	_fire.gravity = Vector3(0.0, 2.0, 0.0)
	_fire.scale_amount_min = 0.9
	_fire.scale_amount_max = 1.8
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = CarDamage.fire_material()
	_fire.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(3.0, 1.4, 0.35, 0.95))
	g.set_color(1, Color(0.6, 0.15, 0.05, 0.0))
	_fire.color_ramp = g
	_fire.custom_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 12, 12))
	_fire.position = Vector3(0.0, 0.6, 0.6)
	add_child(_fire)
	_smoke = CPUParticles3D.new()
	_smoke.amount = 30
	_smoke.lifetime = 4.5
	_smoke.local_coords = false
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 0.6
	_smoke.direction = Vector3.UP
	_smoke.spread = 18.0
	_smoke.initial_velocity_min = 2.0
	_smoke.initial_velocity_max = 3.5
	_smoke.gravity = Vector3(0.6, 1.0, 0.0)
	_smoke.scale_amount_min = 2.0
	_smoke.scale_amount_max = 4.0
	var curve := Curve.new()
	curve.max_value = 3.0
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 3.0))
	_smoke.scale_amount_curve = curve
	var q2 := QuadMesh.new()
	q2.size = Vector2.ONE
	q2.material = SwimFX.mist_material()
	_smoke.mesh = q2
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.06, 0.055, 0.05, 0.85))
	g2.set_color(1, Color(0.2, 0.19, 0.18, 0.0))
	_smoke.color_ramp = g2
	_smoke.custom_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 40, 30))
	_smoke.position = Vector3(0.0, 1.0, 0.5)
	add_child(_smoke)


func _city() -> Node:
	return get_tree().get_first_node_in_group("city") if is_inside_tree() else null


func _macro() -> MacroMap:
	var city := _city()
	var plan = city.get("plan") if city else null
	return plan.macro if plan is CityPlan else null


func _ground_body() -> StaticBody3D:
	if _ground == null or not is_instance_valid(_ground):
		var city := _city()
		if city == null and is_inside_tree():
			city = get_tree().root.get_node_or_null("City")
		_ground = city.get_node_or_null("GroundBody") as StaticBody3D if city else null
	return _ground


func _set_ground_exception(on: bool) -> void:
	var g := _ground_body()
	if g == null or on == _ground_excepted:
		return
	if on:
		add_collision_exception_with(g)
	else:
		remove_collision_exception_with(g)
	_ground_excepted = on


## The water surface under TRUE world xz this tick, or NAN over land. Keeps the bow sample's
## water (`_kind`, `_offshore`) for the collision rule.
func _surface_at(m: MacroMap, xz: Vector2, t: float, first: bool) -> float:
	var w := SwimWater.at(m, Vector3(xz.x, 0.0, xz.y), t, _sea)
	if first:
		_kind = int(w.get("kind", 0))
		_offshore = float(w.get("s", 0.0))
	if w.is_empty():
		return NAN
	return float(w.surface)


## The water under the hull as a plane through three samples (the bow, the stern quarters): true
## world [origin, normal-free slope dh/dx, dh/dz], or [] when none of them is over water.
func water_plane() -> Array:
	var m := _macro()
	var s: Vector2 = BoatKit.SIZE[kind]
	var t := SeaSurface.now()
	var samples: Array[Vector3] = []
	for off: Vector3 in [Vector3(0.0, 0.0, -s.x * 0.4), Vector3(-s.y * 0.4, 0.0, s.x * 0.38), Vector3(s.y * 0.4, 0.0, s.x * 0.38)]:
		var p := WorldState.to_world(global_transform * off)
		var h := _surface_at(m, Vector2(p.x, p.z), t, samples.is_empty() and off.z < 0.0)
		if not is_nan(h):
			samples.append(Vector3(p.x, h, p.z))
	if samples.is_empty():
		return []
	if samples.size() < 3:
		var avg := 0.0
		for q in samples:
			avg += q.y
		return [Vector3(samples[0].x, avg / samples.size(), samples[0].z), Vector2.ZERO, samples.size()]
	# Plane through the three: h = h0 + gx (x - x0) + gz (z - z0).
	var a := samples[0]
	var e1 := samples[1] - a
	var e2 := samples[2] - a
	var det := e1.x * e2.z - e1.z * e2.x
	var g := Vector2.ZERO
	if absf(det) > 1e-5:
		g = Vector2((e1.y * e2.z - e1.z * e2.y) / det, (e1.x * e2.y - e1.y * e2.x) / det)
	g = g.limit_length(0.8)
	return [a, g, 3]


func _physics_process(delta: float) -> void:
	_clock += delta
	if _debug and int(_clock * 60.0) % 60 == 0:
		print(debug_line())
	if not enabled:
		return
	_sea_age += delta
	if _sea_age > 0.5 or _sea.is_empty():
		_sea = SeaSurface.state(get_tree())
		_sea_age = 0.0
	_watch_rider()
	# BOAT_DEBUG: a jump in speed between two ticks lists what was round her (how a kinematic body
	# moved kilometres in a step was found).
	if _debug and absf(linear_velocity.length() - _dbg_v) > 15.0:
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 30.0
		q.shape = sh
		q.transform = Transform3D(Basis(), global_position)
		q.collision_mask = 0xFFFF
		q.exclude = [get_rid()]
		var names := []
		for r in get_world_3d().direct_space_state.intersect_shape(q, 16):
			var o: Object = r.collider
			names.append("%s(%s) d%.1f" % [o.name, o.get_class(), (o as Node3D).global_position.distance_to(global_position) if o is Node3D else -1.0])
		print("BOATJUMP v %.1f -> %.1f mask %d near %s" % [_dbg_v, linear_velocity.length(), collision_mask, str(names)])
	_dbg_v = linear_velocity.length()
	# A guard against depenetration: something left overlapping the hull (a capsule, a pile) can
	# fire a body off at hundreds of m/s. Before any impulse of this tick (a velocity written after
	# one wipes it).
	var lv := linear_velocity
	if lv.y > MAX_RISE or lv.length() > MAX_SPEED:
		lv.y = minf(lv.y, MAX_RISE)
		linear_velocity = lv.limit_length(MAX_SPEED)
	var plane := water_plane()
	var xf := global_transform
	var n_wet := 0
	var buoy_k := mass * 9.8 / (_points.size() * rest_draft)
	var crit := 2.0 * sqrt(buoy_k * mass / _points.size())
	var speed := linear_velocity.dot(-xf.basis.z)
	var plane_share := clampf(absf(speed) / boat_top_speed, 0.0, 1.2)
	var sink_k := 1.0
	if sinking:
		sink_k = clampf(1.0 - (_clock - sink_t) / sink_seconds, 0.0, 1.0)
	for i in _points.size():
		var lp := _points[i]
		var p := xf * lp
		if plane.is_empty():
			continue
		var tw := WorldState.to_world(p)
		var o: Vector3 = plane[0]
		var g: Vector2 = plane[1]
		var h := o.y + g.x * (tw.x - o.x) + g.y * (tw.z - o.z)
		var depth := h - tw.y
		if depth <= 0.0:
			continue
		n_wet += 1
		var d := minf(depth, rest_draft * 3.5)
		var pv := linear_velocity + angular_velocity.cross(p - xf.origin)
		var lift := buoy_k * d * (1.0 + plane_lift * plane_share * plane_share * (1.25 if lp.z > 0.0 else 0.6))
		# Sinking: the stern lets go first, the bow last.
		if sinking:
			lift *= clampf(sink_k * (1.6 if lp.z < 0.0 else 0.7), 0.0, 1.0)
		var f := Vector3.UP * (lift - crit * buoy_damping * pv.y)
		apply_impulse(f * delta, p - xf.origin)
	wet = float(n_wet) / float(_points.size())
	water = {} if plane.is_empty() else {"surface": (plane[0] as Vector3).y}
	_slope = plane[1] if not plane.is_empty() else Vector2.ZERO
	_ground_rule(plane)
	if wet > 0.0:
		_water_forces(delta, speed, plane_share)
	if driver == null or sinking:
		throttle = move_toward(throttle, 0.0, delta * 2.0)
		_lean_target = 0.0
		if wet > 0.0 and linear_velocity.length() < 0.6 and not sinking:
			# Moored: settle on the water's own drift (the mooring lines).
			apply_central_impulse(-linear_velocity * 1.5 * mass * delta)
		if _engine_sound and _engine_sound.playing:
			_engine_sound.stop()
		_after_tick(delta)
		return
	_drive(delta, speed, plane_share)
	_after_tick(delta)


## BOAT_DEBUG=1: one line a second of what the hull is doing.
func debug_line() -> String:
	var tw := WorldState.to_world(global_position)
	return "BOAT %s y %.2f wet %.2f surf %s v %s freeze %s proc %s sleep %s grav %.2f mass %.0f contacts %d exc %s" % [
		display_name(), tw.y, wet, str(water.get("surface", "-")), str(linear_velocity.snapped(Vector3.ONE * 0.01)),
		freeze, is_physics_processing(), sleeping, gravity_scale, mass, get_contact_count(), _ground_excepted]


## Over water: no GroundBody (the water has no floor). Out over land, the keel clear of y 0: put
## the ground back (a beached boat on the sand, a boat the player hopped onto a quay).
func _ground_rule(plane: Array) -> void:
	# Out at sea the water chunks' floor box (top 0.1 m under the mean water) is in the way too:
	# past OPEN_SEA metres offshore, and clear of the marina's jetties and breakwater, the world
	# layer leaves the mask, Swim's rule for the swimmer. Inshore she keeps it, so she runs
	# aground in the shallows and up the sand.
	var open := _kind == SwimWater.Kind.SEA and _offshore > OPEN_SEA and not _near_marina()
	if open != _open_sea and not freeze:
		_open_sea = open
		collision_mask = 6 if open else _mask()
	if not plane.is_empty():
		_set_ground_exception(true)
	elif _ground_excepted:
		var keel := (global_transform * Vector3(0.0, -rest_draft - 0.2, 0.0)).y
		if WorldState.to_world(Vector3(0.0, keel, 0.0)).y > 0.05:
			_set_ground_exception(false)


## Keel drag, hull drag, the turn's lean and the righting moment, while wet.
func _near_marina() -> bool:
	var m := _macro()
	if m == null or m.marina == null:
		return false
	var tw := WorldState.to_world(global_position)
	return m.marina.outer_bounds().grow(20.0).has_point(Vector2(tw.x, tw.z))


func _water_forces(delta: float, speed: float, plane_share: float) -> void:
	var b := global_basis
	var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
	var v := linear_velocity
	var lat := v.dot(right)
	var k := wet
	# The keel: sideways speed bled into the heading (a carve), not just lost.
	apply_central_impulse(-right * lat * keel_drag * k * mass * delta)
	apply_central_impulse(fwd * absf(lat) * keel_drag * 0.35 * k * mass * delta * signf(speed + 0.01))
	# Hull drag: quadratic, set so thrust and drag meet at top speed; a little linear for coasting.
	var drag_q := thrust_accel / (boat_top_speed * boat_top_speed)
	var f_drag := -fwd * signf(speed) * (speed * speed * drag_q + absf(speed) * 0.08) * k * mass
	apply_central_impulse(f_drag * delta)
	# Vertical: water resists heave beyond the springs (planing hulls slam less with this).
	apply_central_impulse(Vector3.UP * -v.y * 0.6 * k * mass * delta)
	# Attitude: the hull follows the water's slope under it (the plane fitted to the swell), the
	# bow lifted over the hump and trimmed on the plane, leaned into the driver's turn. Eased on the
	# angular velocity (the buoyancy points alone leave a boat rocking forever).
	var hump := sin(clampf(plane_share / 0.62, 0.0, 1.0) * PI) * hump_trim * maxf(throttle, 0.0)
	var trim := hump + plane_share * 0.025
	var sea_pitch := atan(_slope.dot(Vector2(fwd.x, fwd.z)))
	var sea_roll := atan(_slope.dot(Vector2(right.x, right.z)))
	var roll_now := asin(clampf(b.x.y, -1.0, 1.0))
	var pitch_now := asin(clampf(-b.z.y, -1.0, 1.0))
	var e := 1.0 - exp(-3.0 * k * delta)
	var w := angular_velocity
	var want_roll := (sea_roll + _lean_target - roll_now) * 3.0
	var want_pitch := (sea_pitch + trim - pitch_now) * 3.0
	_spin(b.z * (want_roll - w.dot(b.z)) * e + b.x * (want_pitch - w.dot(b.x)) * e)


func _drive(delta: float, speed: float, plane_share: float) -> void:
	if EngineAudio.covers(self):
		if _engine_sound and _engine_sound.playing:
			_engine_sound.stop()
	else:
		if _engine_sound == null:
			_engine_sound = Sfx.loop_player("engine_loop", -8.0)
			add_child(_engine_sound)
		if not _engine_sound.playing:
			_engine_sound.play()
		_engine_sound.pitch_scale = 0.7 + clampf(absf(speed) / boat_top_speed, 0.0, 1.3) * 1.2
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var want := -input.y
	throttle = move_toward(throttle, want, delta * 2.5)
	var boost := nitro_multiplier if Input.is_action_pressed("boost") else 1.0
	light_reverse = throttle < -0.05
	var b := global_basis
	var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	# The prop / the pump: only while the stern is in the water.
	var stern := global_transform * Vector3(0.0, -rest_draft, BoatKit.SIZE[kind].x * 0.42)
	var stern_wet := false
	if not water.is_empty():
		stern_wet = WorldState.to_world(stern).y < float(water.surface) + 0.12
	if stern_wet:
		var push := thrust_accel * (throttle if throttle > 0.0 else throttle * reverse_share) * (boost if throttle > 0.0 else 1.0)
		apply_central_impulse(fwd * push * mass * delta)
		if Input.is_action_pressed("alt_fire"):
			# Hard over and the throttle off: a power turn's brake.
			apply_central_impulse(-linear_velocity * 0.8 * mass * delta * Vector3(1.0, 0.0, 1.0))
	# Steering: a turn rate that grows with speed (a rudder / the jet needs flow), a little at rest.
	var steer_k := clampf(0.18 + absf(speed) / (boat_top_speed * 0.45), 0.0, 1.0) * (1.0 if wet > 0.0 else 0.0)
	var turn := -input.x * turn_rate * steer_k * signf(speed + 0.5)
	if Input.is_action_pressed("alt_fire"):
		turn *= 1.6
	if wet > 0.0:
		var yaw_rate := angular_velocity.dot(Vector3.UP)
		_spin(Vector3.UP * (turn - yaw_rate) * (1.0 - exp(-7.0 * delta)))
	# Lean into the turn (the jet ski all the way over, the speedboat a little).
	_lean_target = -input.x * turn_lean * clampf(absf(speed) / (boat_top_speed * 0.6), 0.0, 1.0)
	steering = lerpf(steering, -input.x * max_steer, 1.0 - exp(-steer_speed * delta))
	# Jump: a hop off the water (the car's rules, the boat's height); in the air, the car's flight.
	_jump_timer = maxf(_jump_timer - delta, 0.0)
	if Input.is_action_just_pressed("jump") and _jump_timer <= 0.0 and (wet > 0.0 or air_jump):
		_jump_timer = jump_cooldown
		var up := hop_speed * (1.0 if wet > 0.0 else air_jump_factor)
		if wet <= 0.0 and linear_velocity.y < 0.0:
			apply_central_impulse(Vector3.UP * -linear_velocity.y * mass)
		apply_central_impulse(Vector3.UP * up * mass)
		hold_crash_watch(3)
		Sfx.play("jump", global_position, -2.0, 0.7)
	_air_time = _air_time + delta if is_airborne() else 0.0
	if _air_time >= flight_grace:
		_fly(delta, input)
	else:
		if _was_airborne:
			gravity_scale = 1.0
		_was_airborne = false
		if global_basis.y.y < 0.15 and linear_velocity.length() < 2.0 and wet > 0.0:
			# Capsized: roll her back up.
			_spin(b.z * -signf(b.x.y + 0.0001) * 2.5 * delta)


## Changes the spin by `dw` (rad/s, world) as a torque impulse through the body's inertia. Never
## set angular_velocity (or linear_velocity) here: the cached value written back wipes every
## impulse applied before it in the same tick - the buoyancy with it (the boats sank).
func _spin(dw: Vector3) -> void:
	var it := get_inverse_inertia_tensor()
	if absf(it.determinant()) < 1e-12:
		return
	apply_torque_impulse(it.inverse() * dw)


## Speed-dependent bits every tick: the wake and spray, the hull's slap, the hull sound.
func _after_tick(delta: float) -> void:
	var vy := linear_velocity.y
	if wet > 0.0 and _prev_vy < -slap_speed:
		_fx.slap(clampf(-_prev_vy / 8.0, 0.2, 1.6))
		take_hit(-1, maxf(-_prev_vy - 14.0, 0.0), Vector3.DOWN, Vector3.INF, HIT_CRASH)
	_prev_vy = vy if wet <= 0.0 else 0.0
	_fx.drive(delta)
	if sinking:
		var under := _clock - sink_t
		if under > sink_seconds * 0.6 and _fire:
			_fire.emitting = false
		# On the bottom (or deep enough that nobody sees it): hold it there until it goes.
		if not freeze and not water.is_empty() and WorldState.to_world(global_position).y < float(water.surface) - 9.0:
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
		if under > sink_seconds + sunk_seconds:
			queue_free()
	_hull_noise()


func _hull_noise() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var speed := linear_velocity.length()
	var want := wet > 0.0 and speed > 1.5 and (driver != null or speed > 4.0)
	if want and _hull_sound == null:
		_hull_sound = Sfx.loop_player("amb_river", -14.0)
		add_child(_hull_sound)
	if _hull_sound == null:
		return
	if want and not _hull_sound.playing:
		_hull_sound.play()
	elif not want and _hull_sound.playing:
		_hull_sound.stop()
	_hull_sound.pitch_scale = 0.8 + clampf(speed / boat_top_speed, 0.0, 1.5) * 0.9
	_hull_sound.volume_db = -20.0 + clampf(speed / boat_top_speed, 0.0, 1.0) * 14.0


# --- The rider -----------------------------------------------------------------------------------

## The hero is drawn at the helm / astride the saddle (a car hides him in its glass; a boat is
## open): BoatRidePose seats him on his skeleton, the Visual turned with the hull.
func _watch_rider() -> void:
	var p := driver as Player
	if p != _rider_of:
		_leave_rider()
		if p != null and p.avatar != null and enabled and not sinking:
			_rider_of = p
			_rider = BoatRidePose.attach(p, self)
	if _rider_of != null and is_instance_valid(_rider_of):
		var pl := _rider_of as Player
		pl.visible = true
		pl.visual.global_basis = global_basis
		pl.global_position = seat_position()
		pl.avatar.swim_body(0.0, 0.0, -float(BoatRidePose.DROP[kind]))
		_rider.steer = steering / maxf(max_steer, 0.01)


func _leave_rider() -> void:
	if _rider != null and is_instance_valid(_rider):
		_rider.queue_free()
	_rider = null
	if _rider_of != null and is_instance_valid(_rider_of):
		var pl := _rider_of as Player
		if pl.avatar:
			pl.avatar.transform = Transform3D.IDENTITY
		pl.visual.rotation = Vector3(0.0, pl.visual.rotation.y, 0.0)
	_rider_of = null


func _exit_tree() -> void:
	_leave_rider()
	_set_ground_exception(false)
