class_name BlastPool
extends Node3D
## A pool of burning fuel on the road (Blast4, fleet wave 5 "explosions-4"): where a car's tank or
## a petrol pump went up, the fuel is thrown over the ground and burns there for `life` seconds -
## a dark wet puddle that spreads in its first second (`shaders/blast_pool.gdshader`: a ragged
## outline from the tiling noise, the burning surface in flickering patches, soot creeping out
## from its rim), flames licking up off it (the car fire's own material, so it reads as the same
## fire as the wreck beside it), embers, a flickering light on the street (desktop) that also
## lights the blast's smoke from below (Blast3's fire list), and its crackle. It shrinks as the
## fuel burns away and leaves the soot. `max_pools` alive at once (the oldest burns out early).

static var life_range: Vector2 = Vector2(15.0, 24.0)
static var max_pools: int = 4
## Pool radius in metres for a blast radius of 7 (a car's); scaled with the blast.
static var pool_radius: float = 3.1
static var flame_count: int = 46

static var _pools: Array = []
static var _shader: Shader

var life: float = 18.0
var radius: float = 3.0
var age: float = 0.0
var gas: bool = false
var _mat: ShaderMaterial
var _flames: CPUParticles3D
var _tall: CPUParticles3D
var _embers: CPUParticles3D
var _light: OmniLight3D
var _sound: AudioStreamPlayer3D


## A pool under `at` (global; the ground is found by a ray). Null when there is no ground in reach.
static func spawn(node: Node, parent: Node, at: Vector3, blast_radius: float, is_gas: bool = false) -> BlastPool:
	var space := WeaponFX._space(node)
	if space == null:
		return null
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at - Vector3.UP * 6.0, 1))
	if hit.is_empty():
		return null
	_pools = _pools.filter(func(p): return is_instance_valid(p) and not (p as Node).is_queued_for_deletion())
	while _pools.size() >= max_pools:
		var old: BlastPool = _pools.pop_front()
		old.life = minf(old.life, old.age + 1.5)
	var p := BlastPool.new()
	p.name = "BlastPool"
	p.gas = is_gas
	p.radius = pool_radius * clampf(blast_radius / 7.0, 0.6, 1.8)
	p.life = randf_range(life_range.x, life_range.y) * (0.75 if is_gas else 1.0)
	parent.add_child(p)
	p.global_position = (hit.position as Vector3) + (hit.normal as Vector3) * 0.03
	p.global_basis = WeaponFX._basis_up(hit.normal)
	_pools.append(p)
	return p


static func alive() -> int:
	_pools = _pools.filter(func(p): return is_instance_valid(p) and not (p as Node).is_queued_for_deletion())
	return _pools.size()


static func material() -> ShaderMaterial:
	if _shader == null:
		_shader = preload("res://shaders/blast_pool.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("noise3d", Blast3.noise_texture())
	return m


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 2.6
	quad.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.name = "Puddle"
	mi.mesh = quad
	_mat = material()
	_mat.set_shader_parameter("seed", Vector2(randf() * 9.0, randf() * 9.0))
	_mat.set_shader_parameter("radius", radius)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# The body of the fire: low rolling flame over the whole pool.
	_flames = _flame_system("PoolFire", flame_count, Vector2.ONE)
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_flames.emission_ring_axis = Vector3.UP
	_flames.emission_ring_height = 0.05
	_flames.emission_ring_inner_radius = 0.0
	_flames.emission_ring_radius = radius * 0.8
	_flames.lifetime = 0.8
	_flames.spread = 18.0
	# Tall tongues standing up out of it here and there.
	_tall = _flame_system("PoolTongues", int(flame_count * 0.4), Vector2(0.6, 1.5))
	_tall.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_tall.emission_ring_axis = Vector3.UP
	_tall.emission_ring_height = 0.05
	_tall.emission_ring_inner_radius = 0.0
	_tall.emission_ring_radius = radius * 0.55
	_tall.lifetime = 1.0
	_tall.spread = 10.0
	_embers = CPUParticles3D.new()
	_embers.name = "PoolEmbers"
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_embers.amount = WeaponFX._count(16)
	_embers.lifetime = 2.4
	_embers.lifetime_randomness = 0.5
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_embers.emission_box_extents = Vector3(radius * 0.6, 0.2, radius * 0.6)
	_embers.direction = Vector3.UP
	_embers.spread = 30.0
	_embers.initial_velocity_min = 1.5
	_embers.initial_velocity_max = 4.0
	_embers.gravity = Vector3(0.5, 1.0, 0.0)
	_embers.scale_amount_min = 0.03
	_embers.scale_amount_max = 0.07
	_embers.color_ramp = WeaponFX._ramp([Color(1.4, 0.76, 0.08, 1.0), Color(1.0, 0.44, 0.04, 1.0),
		Color(0.55, 0.17, 0.02, 0.7), Color(0.2, 0.05, 0.01, 0.0)])
	var eq := QuadMesh.new()
	eq.size = Vector2.ONE
	eq.material = WeaponFX._puff_material(true)
	_embers.mesh = eq
	_embers.custom_aabb = AABB(Vector3(-12.0, -2.0, -12.0), Vector3(24.0, 24.0, 24.0))
	add_child(_embers)
	if not WeaponFX._web():
		_light = OmniLight3D.new()
		_light.name = "PoolLight"
		_light.light_color = Color(1.0, 0.5, 0.17)
		_light.omni_range = radius * 4.5
		_light.omni_attenuation = 1.3
		_light.distance_fade_enabled = true
		_light.distance_fade_begin = 110.0
		_light.distance_fade_length = 30.0
		_light.position = Vector3.UP * 1.1
		add_child(_light)
		Blast3.add_fire(_light)
	_sound = Sfx.loop_player("fire_loop", 0.0)
	if _sound != null:
		_sound.unit_size = 7.0
		add_child(_sound)
		_sound.play()
	_apply(0.0)


func _flame_system(sys_name: String, amount: int, quad_size: Vector2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = sys_name
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = WeaponFX._count(amount)
	p.lifetime_randomness = 0.4
	p.local_coords = false
	p.direction = Vector3.UP
	p.damping_min = 0.5
	p.damping_max = 1.2
	p.color_ramp = CarDamage._flame_ramp()
	p.color_initial_ramp = CarDamage._flame_variety()
	p.angle_min = -14.0
	p.angle_max = 14.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.22, 1.0))
	curve.add_point(Vector2(0.6, 0.8))
	curve.add_point(Vector2(1.0, 0.3))
	p.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = quad_size
	quad.center_offset = Vector3(0.0, (quad_size.y - quad_size.x) * 0.5, 0.0)
	quad.material = CarDamage.fire_material()
	p.mesh = quad
	p.custom_aabb = AABB(Vector3(-12.0, -2.0, -12.0), Vector3(24.0, 16.0, 24.0))
	add_child(p)
	return p


func _process(delta: float) -> void:
	age += delta
	if age >= life + 2.5:
		queue_free()
		return
	_apply(delta)


## How much is burning (0..1): it catches over the first half second, burns, dies down.
func burn() -> float:
	return smoothstep(0.0, 0.35, age) * (1.0 - smoothstep(life * 0.45, life, age))


func _apply(_delta: float) -> void:
	var b := burn()
	var spread := 1.0 - exp(-age / 0.45)
	_mat.set_shader_parameter("spread", spread)
	_mat.set_shader_parameter("burn", b)
	_mat.set_shader_parameter("age", age)
	var r := radius * (0.35 + 0.65 * spread) * (0.55 + 0.45 * b)
	var size := b * (1.25 if gas else 1.0)
	var on := b > 0.03
	for s: CPUParticles3D in [_flames, _tall]:
		s.emitting = on
		s.emission_ring_radius = r * (0.8 if s == _flames else 0.55)
	_flames.initial_velocity_min = 0.3
	_flames.initial_velocity_max = 0.8 + 0.6 * size
	_flames.gravity = Vector3(0.2, 1.4 + 1.0 * size, 0.0)
	_flames.scale_amount_min = 0.5 + 0.35 * size
	_flames.scale_amount_max = 0.8 + 0.6 * size
	_flames.color = Color(1, 1, 1, clampf(0.3 + 0.7 * size, 0.0, 1.0))
	_tall.initial_velocity_min = 0.5 + 0.4 * size
	_tall.initial_velocity_max = 1.2 + 1.2 * size
	_tall.gravity = Vector3(0.1, 1.8 + 1.0 * size, 0.0)
	_tall.scale_amount_min = 0.45 + 0.4 * size
	_tall.scale_amount_max = 0.75 + 0.6 * size
	_tall.color = Color(1, 1, 1, clampf(0.25 + 0.75 * size, 0.0, 1.0))
	_embers.emitting = on
	if _light != null:
		var t := age
		var f := 0.78 + 0.22 * sin(t * 37.0) * sin(t * 13.0 + 0.7) + 0.06 * sin(t * 91.0)
		_light.light_energy = 6.5 * b * f
		_light.visible = b > 0.01
	if _sound != null:
		_sound.volume_db = linear_to_db(maxf(b, 0.001)) - 1.0
