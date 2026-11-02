class_name BonfireFire
extends Node3D
## The fire in one beach bonfire ring (Bonfires), a child of the chunk at the ring's centre on the
## sand. It asks the clock every CHECK_SECONDS whether its ring burns now (Bonfires.lit_at(): the
## ring's own window that night, no fires in rain, a storm or a Santa Ana) and how far the camera
## is, and builds what it needs the first time it is lit near the player:
##
## * the stack of logs on its coals (Bonfires.stack_mesh(), the hot material: the coals glow and
##   flicker under the logs);
## * flames - CarDamage's fire material and colour ramps, at a camp fire's size: a body of flame
##   rolling up off the coals and tongues licking up the logs of the teepee -, embers riding the
##   heat up and drifting off with the breeze, and pale wood smoke (not a car fire's black) whose
##   first moments glow the fire's colour;
## * an additive pool of firelight on the sand (light_pool.gdshader, every renderer);
## * a flickering warm OmniLight3D on the sand and the people round it (desktop only; the nearest
##   LIGHT_BUDGET lit fires within LIGHT_REACH, the nearest one within SHADOW_REACH casting
##   shadows), and the crackle (Sfx `fire_loop`) close by.
##
## Out of range, or out, it stops emitting and hides; the ring itself is the chunk's batch.

## Seconds between looks at the clock and the camera.
const CHECK_SECONDS := 0.8
## The particles burn only within this of the camera (m); the stack and the pool draw further.
const FIRE_RANGE := 230.0
const STACK_RANGE := 300.0
## Real lights: how many fires carry one, how near, and how near the one that casts shadows is.
const LIGHT_BUDGET := 6
const LIGHT_REACH := 110.0
const SHADOW_REACH := 26.0
## The light's colour (sRGB), energy, range and height over the sand.
const LIGHT_COLOR := Color(1.0, 0.55, 0.24)
const LIGHT_ENERGY := 2.6
const LIGHT_RANGE := 12.0
const LIGHT_Y := 1.3
## The crackle's reach (m).
const SOUND_REACH := 45.0

var ring_k: int = 0
var plan: CityPlan
## The group round the fire (BonfireFigure) and their things ([batch key, instance index] in the
## chunk's batches): sent home when the fire goes out (a chunk built at night lives on into the day).
var figures: Array = []
var props: Array = []

var lit: bool = false
var _near: bool = false
var _built: bool = false
var _t: float = 0.0
var _phase: float = 0.0
var _stack: MeshInstance3D
var _pool: MeshInstance3D
var _flames: CPUParticles3D
var _licks: CPUParticles3D
var _embers: CPUParticles3D
var _smoke: CPUParticles3D
var _light: OmniLight3D
var _sound: AudioStreamPlayer3D
var _cam_dist: float = INF

## Every fire node in the tree (for the light budget), and when the budget was last dealt.
static var _all: Array = []
static var _dealt_ms: int = -100000


func _ready() -> void:
	_all.append(self)
	_phase = float(absi(hash([ring_k, "bonfire_phase"])) % 1000) / 1000.0 * TAU
	_t = CHECK_SECONDS * _phase / TAU
	_check()


func _exit_tree() -> void:
	_all.erase(self)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = CHECK_SECONDS
		_check()
	if _light and _light.visible:
		var t := float(Time.get_ticks_msec()) * 0.001 + _phase
		# Two fast flickers over a slow breathing: a wood fire, not a strobe.
		var f := 0.78 + 0.1 * sin(t * 1.7) + 0.07 * sin(t * 9.3 + 1.1) + 0.05 * sin(t * 15.7 + 0.4)
		_light.light_energy = LIGHT_ENERGY * f
		_light.position = Vector3(0.04 * sin(t * 6.1), LIGHT_Y + 0.05 * sin(t * 4.3), 0.04 * cos(t * 5.3))


func _check() -> void:
	if plan == null:
		return
	var c := Bonfires.clock(self)
	lit = Bonfires.lit_at(plan, ring_k, c[0], c[1], c[2])
	if not lit and (not figures.is_empty() or not props.is_empty()):
		_dismiss()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() else null
	_cam_dist = global_position.distance_to(cam.global_position) if cam else 0.0
	var want := lit and _cam_dist < STACK_RANGE
	if lit and not _built:
		_build()
	if not _built:
		return
	_stack.visible = want
	# The pool is one quad: it shows from anywhere while the fire burns (the row of glows along a
	# night beach seen from the air).
	_pool.visible = lit
	var burn := want and _cam_dist < FIRE_RANGE
	for p: CPUParticles3D in [_flames, _licks, _embers, _smoke]:
		p.emitting = burn
		if burn:
			p.visible = true
	_near = burn
	if _sound:
		var hear := burn and _cam_dist < SOUND_REACH
		if hear and not _sound.playing:
			_sound.play()
		elif not hear and _sound.playing:
			_sound.stop()
	_deal_lights()


## The fire is out: its people go home and take their chairs, blankets, cooler and wood (anyone
## already woken by gunfire is a live person and stays where they ran).
func _dismiss() -> void:
	var ch := get_parent()
	for fig in figures:
		if is_instance_valid(fig) and not fig._awake:
			if fig.figure_mesh and is_instance_valid(fig.figure_mesh):
				fig.figure_mesh.hide_figure(fig.figure_index)
			fig.queue_free()
	figures.clear()
	for pr: Array in props:
		var node := ch.get_node_or_null("Batch_" + String(pr[0])) as MultiMeshInstance3D if ch else null
		if node:
			MultiMeshBatch.hide_instance(node, int(pr[1]))
	props.clear()


## The real lights go to the nearest lit fires, the shadow to the nearest of all (desktop only).
static func _deal_lights() -> void:
	var now := Time.get_ticks_msec()
	if now - _dealt_ms < 400:
		return
	_dealt_ms = now
	var lit_fires: Array = []
	for f: BonfireFire in _all:
		if is_instance_valid(f) and f._light != null:
			if f._near and f._cam_dist < LIGHT_REACH:
				lit_fires.append(f)
			else:
				f._light.visible = false
	lit_fires.sort_custom(func(a: BonfireFire, b: BonfireFire) -> bool: return a._cam_dist < b._cam_dist)
	var lamps := _lamp_scale()
	for i in lit_fires.size():
		var f: BonfireFire = lit_fires[i]
		f._light.visible = i < LIGHT_BUDGET and lamps > 0.0
		f._light.shadow_enabled = i == 0 and f._cam_dist < SHADOW_REACH


## DayNight.lamp_scale (Quality zeroes it below MEDIUM: no real lights there).
static func _lamp_scale() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var scene := tree.current_scene if tree else null
	var dn := scene.get_node_or_null("DayNight") if scene else null
	if dn and dn.get("lamp_scale") != null:
		return float(dn.get("lamp_scale"))
	return 1.0


func _build() -> void:
	_built = true
	_stack = MeshInstance3D.new()
	_stack.name = "Stack"
	_stack.mesh = Bonfires.stack_mesh()
	_stack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stack)
	_pool = MeshInstance3D.new()
	_pool.name = "Pool"
	_pool.mesh = Bonfires.pool_mesh()
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pool.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(Bonfires.POOL_SIZE, Bonfires.POOL_SIZE, 1.0)), Vector3(0.0, 0.06, 0.0))
	add_child(_pool)
	var base := Vector3(0.0, Bonfires.ASH_Y + 0.12, 0.0)
	# The body of the fire, rolling up off the coals.
	_flames = _flame_system("Flames", 30, Vector2.ONE, 180.0)
	_flames.position = base + Vector3(0.0, 0.08, 0.0)
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_flames.emission_box_extents = Vector3(0.17, 0.05, 0.17)
	_flames.spread = 18.0
	_flames.lifetime = 0.9
	_flames.lifetime_randomness = 0.4
	_flames.initial_velocity_min = 0.5
	_flames.initial_velocity_max = 1.1
	_flames.gravity = Vector3(0.08, 2.2, 0.0)
	_flames.damping_min = 0.5
	_flames.damping_max = 1.0
	_flames.scale_amount_min = 0.5
	_flames.scale_amount_max = 0.78
	# Tongues licking up the teepee's logs.
	_licks = _flame_system("Tongues", 20, Vector2(0.32, 0.9), 10.0)
	_licks.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	for i in 7:
		var a := TAU * float(i) / 7.0
		pts.append(Vector3(cos(a) * 0.2, Bonfires.ASH_Y + 0.22, sin(a) * 0.2))
		nrm.append(Vector3(-cos(a) * 0.35, 1.0, -sin(a) * 0.35).normalized())
	_licks.emission_points = pts
	_licks.emission_normals = nrm
	_licks.spread = 10.0
	_licks.lifetime = 0.7
	_licks.lifetime_randomness = 0.35
	_licks.initial_velocity_min = 0.6
	_licks.initial_velocity_max = 1.2
	_licks.gravity = Vector3(0.05, 2.0, 0.0)
	_licks.damping_min = 0.3
	_licks.damping_max = 0.8
	_licks.scale_amount_min = 0.75
	_licks.scale_amount_max = 1.15
	# Embers riding the heat up and off down the breeze.
	_embers = CPUParticles3D.new()
	_embers.name = "Embers"
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_embers.amount = WeaponFX._count(14)
	_embers.lifetime = 2.8
	_embers.lifetime_randomness = 0.5
	_embers.local_coords = false
	_embers.position = base + Vector3(0.0, 0.25, 0.0)
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_embers.emission_box_extents = Vector3(0.18, 0.1, 0.18)
	_embers.direction = Vector3.UP
	_embers.spread = 28.0
	_embers.initial_velocity_min = 1.2
	_embers.initial_velocity_max = 3.0
	_embers.gravity = Vector3(0.7, 0.6, 0.2)
	_embers.damping_min = 0.3
	_embers.damping_max = 0.8
	_embers.scale_amount_min = 0.02
	_embers.scale_amount_max = 0.045
	_embers.color_ramp = WeaponFX._ramp([Color(1.4, 0.76, 0.08, 1.0), Color(1.0, 0.44, 0.04, 1.0),
		Color(0.55, 0.17, 0.02, 0.7), Color(0.2, 0.05, 0.01, 0.0)])
	var eq := QuadMesh.new()
	eq.size = Vector2.ONE
	eq.material = WeaponFX._puff_material(true)
	_embers.mesh = eq
	_embers.custom_aabb = AABB(Vector3(-12.0, -2.0, -12.0), Vector3(24.0, 20.0, 24.0))
	add_child(_embers)
	# Pale wood smoke, lit by the fire where it leaves the flames.
	_smoke = CPUParticles3D.new()
	_smoke.name = "Smoke"
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.amount = WeaponFX._count(40)
	_smoke.lifetime = 7.0
	_smoke.lifetime_randomness = 0.15
	_smoke.local_coords = false
	_smoke.position = base + Vector3(0.0, 1.0, 0.0)
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_smoke.emission_box_extents = Vector3(0.12, 0.1, 0.12)
	_smoke.direction = Vector3.UP
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 0.7
	_smoke.initial_velocity_max = 1.3
	_smoke.gravity = Vector3(0.45, 0.35, 0.15)
	_smoke.damping_min = 0.15
	_smoke.damping_max = 0.35
	_smoke.scale_amount_min = 0.35
	_smoke.scale_amount_max = 0.6
	var curve := Curve.new()
	curve.max_value = 6.0
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.3, 1.7))
	curve.add_point(Vector2(1.0, 5.0))
	_smoke.scale_amount_curve = curve
	# Lit warm only where it leaves the flames, then the night's own grey, thin and fading.
	_smoke.color_ramp = WeaponFX._ramp([Color(2.2, 1.3, 0.75, 0.0), Color(1.15, 1.02, 0.95, 0.2),
		Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.0)])
	_smoke.color = Color(0.42, 0.42, 0.42, 1.0)
	_smoke.angle_min = -180.0
	_smoke.angle_max = 180.0
	var sq := QuadMesh.new()
	sq.size = Vector2.ONE
	sq.material = WeaponFX.smoke_material()
	_smoke.mesh = sq
	_smoke.custom_aabb = AABB(Vector3(-20.0, -2.0, -20.0), Vector3(40.0, 36.0, 40.0))
	_smoke.preprocess = 3.0
	add_child(_smoke)
	if not WeaponFX._web():
		_light = OmniLight3D.new()
		_light.name = "Firelight"
		_light.light_color = LIGHT_COLOR
		_light.light_energy = LIGHT_ENERGY
		_light.omni_range = LIGHT_RANGE
		_light.omni_attenuation = 1.3
		_light.shadow_enabled = false
		# A fire is a big soft source, not a bulb: soft shadow edges.
		_light.shadow_blur = 2.5
		_light.distance_fade_enabled = true
		_light.distance_fade_begin = LIGHT_REACH - 30.0
		_light.distance_fade_length = 25.0
		_light.position = Vector3(0.0, LIGHT_Y, 0.0)
		_light.visible = false
		add_child(_light)
	if Engine.get_main_loop() and (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Sfx"):
		_sound = Sfx.loop_player("fire_loop", -13.0)
		_sound.unit_size = 3.0
		_sound.max_distance = SOUND_REACH + 10.0
		add_child(_sound)


## One flame system on the car fire's material and ramps (CarDamage), puffs of `quad_size`.
func _flame_system(sys_name: String, amount: int, quad_size: Vector2, angle: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = sys_name
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = WeaponFX._count(amount)
	p.local_coords = false
	p.direction = Vector3.UP
	p.color_ramp = CarDamage._flame_ramp()
	p.color_initial_ramp = CarDamage._flame_variety()
	p.angle_min = -angle
	p.angle_max = angle
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.22, 1.0))
	curve.add_point(Vector2(0.6, 0.8))
	curve.add_point(Vector2(1.0, 0.25))
	p.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = quad_size
	quad.center_offset = Vector3(0.0, (quad_size.y - quad_size.x) * 0.5, 0.0)
	quad.material = CarDamage.fire_material()
	p.mesh = quad
	p.custom_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 12.0, 16.0))
	p.preprocess = 1.0
	add_child(p)
	return p
