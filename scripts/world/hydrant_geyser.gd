class_name HydrantGeyser
extends Node3D
## A sheared fire hydrant (PropBreak): the water main under it throws a column of white water
## ten metres and more into the air for a while, falls back as a ring of rain round it, foams at
## the foot and soaks the pavement in a spreading wet patch (shaders/wet_patch.gdshader), with the
## roar of it (Sfx `amb_fountain` and `rain`, on the World bus). Then the pressure drops, the
## column sags to a gush and stops, and the patch dries back from its edge.
## Over the top on purpose: whoever stands in the column is thrown up it, and loose props and
## cars over it are lifted (an impulse a step - VehicleBody3D clears its force accumulator).
## All of it is this node's children, under the chunk the hydrant stood in, so it rides every
## origin shift and goes when the chunk does. `max_live` at once: a new one ends the oldest.

## Seconds at full pressure, then the fall to nothing.
@export var full_seconds: float = 45.0
@export var fade_seconds: float = 8.0
## Seconds the wet patch takes to dry once the water stops.
@export var dry_seconds: float = 40.0
## Speed the water leaves the main at (m/s): v^2 / 2g is the column's height (16 -> 13 m).
@export var jet_speed: float = 16.0
## How wide the wet patch spreads (m) and how long it takes.
@export var patch_radius: float = 5.5
@export var patch_grow_seconds: float = 14.0
## Upward speed the column gives whoever stands in it (m/s), and its radius (m).
@export var lift_speed: float = 15.0
@export var lift_radius: float = 0.75
## Lift on loose bodies over it: acceleration in g (1 just floats them).
@export var body_lift_g: float = 1.25

static var max_live: int = 6
static var _live: Array = []

var _t: float = 0.0
var _pressure: float = 1.0
var _jet: CPUParticles3D
var _crown: CPUParticles3D
var _rain: CPUParticles3D
var _foam: CPUParticles3D
var _patch: MeshInstance3D
var _patch_mat: ShaderMaterial
var _roar: AudioStreamPlayer3D
var _hiss: AudioStreamPlayer3D
var _bodies: Array = []
## The unshaded puffs' materials, dimmed with the night (the streaks dim themselves).
var _puff_mats: Array = []
var _night_t: float = 0.0
var _query_t: float = 0.0
var _stopped: bool = false


## A geyser at `at` (the hydrant's foot, `parent`'s space).
static func start(parent: Node3D, at: Vector3) -> HydrantGeyser:
	var keep: Array = []
	for g in _live:
		if is_instance_valid(g):
			keep.append(g)
	_live = keep
	while _live.size() >= max_live:
		var old: HydrantGeyser = _live.pop_front()
		old.end_now()
	var g := HydrantGeyser.new()
	g.name = "HydrantGeyser"
	g.position = at
	parent.add_child(g)
	_live.append(g)
	return g


static func live_count() -> int:
	var c := 0
	for g in _live:
		if is_instance_valid(g) and not (g as HydrantGeyser)._stopped:
			c += 1
	return c


func _ready() -> void:
	var web := OS.has_feature("web")
	var k := 0.5 if web else 1.0
	# The column: a rope of water streaks stretched along their own velocity.
	_jet = _streaks(int(110 * k), 1.45, jet_speed * 0.94, jet_speed, 3.5, Vector2(2.6, 3.6), 0.9)
	# The crown: white puffs where the column breaks up, tumbling down as spray.
	_crown = _puffs(int(70 * k), 2.6, jet_speed * 0.72, jet_speed * 0.92, 9.0, 1.6, 0.42)
	# The rain falling back round it.
	_rain = _streaks(int(140 * k), 2.6, jet_speed * 0.55, jet_speed * 0.85, 16.0, Vector2(0.6, 1.0), 0.6)
	# Foam and splash at the foot.
	_foam = _puffs(int(40 * k), 0.9, 1.5, 3.2, 80.0, 0.9, 0.55)
	_foam.position = Vector3(0.0, 0.15, 0.0)
	_patch = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * patch_radius * 2.0
	_patch.mesh = plane
	_patch_mat = ShaderMaterial.new()
	_patch_mat.shader = load("res://shaders/wet_patch.gdshader")
	_patch_mat.set_shader_parameter("radius01", 0.05)
	_patch.material_override = _patch_mat
	_patch.position = Vector3(0.0, 0.012, 0.0)
	_patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_patch)
	_roar = _loop("amb_fountain", 6.0, 0.72)
	_hiss = _loop("rain", 0.0, 1.25)


func _loop(name_: String, db: float, pitch: float) -> AudioStreamPlayer3D:
	if not Sfx.has(name_):
		return null
	var p := Sfx.loop_player(name_, db)
	p.bus = &"World"
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = 90.0
	p.position = Vector3(0.0, 1.5, 0.0)
	add_child(p)
	p.play()
	return p


func _streaks(amount: int, life: float, v0: float, v1: float, spread: float, scale: Vector2, opacity: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(amount, 8)
	p.lifetime = life
	p.lifetime_randomness = 0.25
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.particle_flag_align_y = true
	p.scale_amount_min = scale.x
	p.scale_amount_max = scale.y
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.06
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/hose_water.gdshader")
	mat.set_shader_parameter("opacity", opacity)
	mat.set_shader_parameter("width", 0.11)
	mat.set_shader_parameter("streak_length", 0.8)
	quad.material = mat
	p.mesh = quad
	p.color_ramp = WeaponFX._ramp([Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	_bounds(p, v1, life)
	add_child(p)
	p.emitting = true
	return p


func _puffs(amount: int, life: float, v0: float, v1: float, spread: float, size: float, alpha: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(amount, 6)
	p.lifetime = life
	p.lifetime_randomness = 0.3
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = Vector3(0.0, -7.5, 0.0)
	p.damping_min = 1.0
	p.damping_max = 2.5
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.max_value = 2.0
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 2.0))
	p.scale_amount_curve = curve
	p.angle_min = -180.0
	p.angle_max = 180.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.92, 0.95, 1.0, alpha))
	ramp.set_color(1, Color(0.85, 0.9, 0.95, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = WeaponFX.puff_texture()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if not OS.has_feature("web"):
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 0.6
	quad.material = mat
	_puff_mats.append(mat)
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	_bounds(p, v1, life)
	add_child(p)
	p.emitting = true
	return p


func _bounds(p: CPUParticles3D, v: float, life: float) -> void:
	var up := v * v / 19.6 + 2.0
	var side := v * life * 0.5 + 3.0
	p.custom_aabb = AABB(Vector3(-side, -2.0, -side), Vector3(side * 2.0, up + 4.0, side * 2.0))


func _physics_process(delta: float) -> void:
	_t += delta
	var end := full_seconds + fade_seconds
	_pressure = 1.0 if _t < full_seconds else clampf(1.0 - (_t - full_seconds) / fade_seconds, 0.0, 1.0)
	if _t >= end and not _stopped:
		_stop_water()
	# The column sags with the pressure: its speed is what sets its height.
	if not _stopped:
		var p := maxf(_pressure, 0.05)
		var sp := sqrt(p)
		_jet.initial_velocity_min = jet_speed * 0.94 * sp
		_jet.initial_velocity_max = jet_speed * sp
		_crown.initial_velocity_min = jet_speed * 0.72 * sp
		_crown.initial_velocity_max = jet_speed * 0.92 * sp
		_rain.initial_velocity_min = jet_speed * 0.55 * sp
		_rain.initial_velocity_max = jet_speed * 0.85 * sp
		if _roar:
			_roar.volume_db = Sfx.master_volume_db + 6.0 + linear_to_db(maxf(p, 0.02))
		if _hiss:
			_hiss.volume_db = Sfx.master_volume_db + linear_to_db(maxf(p, 0.02))
		_lift(delta, p)
	_night_t -= delta
	if _night_t <= 0.0:
		_night_t = 0.5
		var night := clampf(DayNight.lamp_now, 0.0, 1.0)
		var l := lerpf(1.0, 0.2, night)
		for m: StandardMaterial3D in _puff_mats:
			m.albedo_color = Color(l, l, l)
	var grow := clampf(_t / patch_grow_seconds, 0.0, 1.0)
	_patch_mat.set_shader_parameter("radius01", 0.08 + 0.92 * (1.0 - pow(1.0 - grow, 2.0)))
	_patch_mat.set_shader_parameter("rain", _pressure)
	var dry := clampf((_t - end) / dry_seconds, 0.0, 1.0) if _t > end else 0.0
	_patch_mat.set_shader_parameter("dry", dry)
	if dry >= 1.0:
		queue_free()


## Throws whoever stands in the column up it, and floats the loose bodies over it.
func _lift(delta: float, p: float) -> void:
	var top := global_position.y + jet_speed * jet_speed * p / 19.6
	for pl in get_tree().get_nodes_in_group("player"):
		var body := pl as CharacterBody3D
		if body == null or (body.has_method("is_driving") and body.call("is_driving")):
			continue
		var d := body.global_position - global_position
		if Vector2(d.x, d.z).length() < lift_radius and d.y > -0.6 and body.global_position.y < top:
			body.velocity.y = maxf(body.velocity.y, lift_speed * sqrt(p))
	_query_t -= delta
	if _query_t <= 0.0:
		_query_t = 0.2
		_bodies.clear()
		var space := get_world_3d().direct_space_state if is_inside_tree() else null
		if space:
			var q := PhysicsShapeQueryParameters3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.1
			cyl.height = 3.0
			q.shape = cyl
			q.transform = Transform3D(Basis(), global_position + Vector3(0.0, 1.6, 0.0))
			q.collision_mask = 4
			for r in space.intersect_shape(q, 8):
				var rb := r.collider as RigidBody3D
				if rb and not rb.freeze and not _bodies.has(rb):
					_bodies.append(rb)
	for rb: RigidBody3D in _bodies:
		if is_instance_valid(rb) and not rb.freeze:
			rb.sleeping = false
			rb.apply_central_impulse(Vector3.UP * rb.mass * 9.8 * body_lift_g * p * delta)


func _stop_water() -> void:
	_stopped = true
	for p in [_jet, _crown, _rain, _foam]:
		if p:
			p.emitting = false
	for s in [_roar, _hiss]:
		if s:
			s.stop()


## Ends it at once (a newer one took its place): the water stops, the patch dries from here.
func end_now() -> void:
	if _t < full_seconds + fade_seconds:
		_t = full_seconds + fade_seconds
