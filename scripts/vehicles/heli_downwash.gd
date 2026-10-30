class_name HeliDownwash
extends Node3D
## A helicopter's rotor wash on the ground under it (FlyableHeli makes one and drives it every
## physics tick with the hub's position and the rotor's strength):
##   - a ray under the hub finds the ground; inside `reach` metres a ring of dust is kicked up
##     there and races outward (spray over the sea, the marina, a lake), thicker the lower and
##     harder the rotor works;
##   - the `heli_downwash` shader global (hub xyz in the scene's frame, strength in w) is what
##     palms, trees and grass read to bend away from under it and flutter (foliage.gdshader,
##     foliage_tex, la_tree, grass): one global, so the strongest wash in the scene owns it;
##   - loose props (trash cans and the like, RigidBody3D on the props layer) inside
##     `push_radius` are blown outward.

## Height of the hub over the ground (m) where the wash is full, and where it is gone.
@export var full_height: float = 7.0
@export var reach: float = 36.0
## Radius on the ground (m) in which loose props are pushed, and the push (m/s per second).
@export var push_radius: float = 9.0
@export var push_accel: float = 9.0
## Dust colour (sRGB, alpha is its thickness) and spray colour.
@export var dust_color: Color = Color(0.64, 0.6, 0.53, 0.42)
@export var spray_color: Color = Color(0.86, 0.9, 0.94, 0.5)
## Off the hills' dry grass and off the beach's sand.
@export var hills_color: Color = Color(0.62, 0.56, 0.42, 0.45)
@export var sand_color: Color = Color(0.82, 0.74, 0.6, 0.6)
## Off a park's or a school's lawn: a thin pale haze of spray and clippings, not dust (in brown,
## the puffs read as dead patches on the grass).
@export var lawn_color: Color = Color(0.78, 0.8, 0.72, 0.16)

## The wash's strength on the ground this tick (0..1) and where it lands (local), for the tests.
var ground_strength: float = 0.0
var ground_point: Vector3 = Vector3.INF
var over_water: bool = false
## Metres from the hub down to the ground under it (INF past `reach`): the auto-flare reads it.
var ground_gap: float = INF

var _dust: CPUParticles3D
var _billow: CPUParticles3D
var _ray_left: float = 0.0
var _push_left: float = 0.0
var _hit: Dictionary = {}

## The wash that owns the shader global, and how strong it was.
static var _owner_id: int = 0
static var _owner_k: float = 0.0


func _ready() -> void:
	# Two layers, both lit (DrivingFX's puff: lit on the face and through it, soft where it meets
	# the ground) - unshaded, the wash was the same flat beige at noon and at dusk:
	# a low sheet of grit skimming outward along the ground (most of what a real wash is), and
	# fewer, slower billows that rise and roll out round it.
	_dust = _layer("WashDust", 72, 1.4, 0.8, 1.8, 1.0, 2.6)
	_billow = _layer("WashBillow", 22, 2.6, 2.0, 4.0, 2.2, 4.4)
	_billow.spread = 40.0
	_billow.radial_accel_min = 5.0
	_billow.radial_accel_max = 11.0
	_billow.gravity = Vector3(0.0, 0.35, 0.0)


## One particle layer of the wash: `amount` puffs living `life` s, launched up at `v0`..`v1`
## m/s and sized `s0`..`s1` m at birth (they grow to three times that).
func _layer(name_: String, amount: int, life: float, v0: float, v1: float, s0: float, s1: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = name_
	p.top_level = true
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 7.0
	p.emission_ring_inner_radius = 2.0
	p.emission_ring_height = 0.2
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.radial_accel_min = 12.0
	p.radial_accel_max = 26.0
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.gravity = Vector3(0.0, -2.0, 0.0)
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	var curve := Curve.new()
	# A growth above 1 needs the cap raised first (CLAUDE.md, effects).
	curve.max_value = 3.0
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.4, 1.8))
	curve.add_point(Vector2(1.0, 3.0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
	p.color_ramp = ramp
	p.color = dust_color
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material()
	p.mesh = quad
	p.custom_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120))
	p.emitting = false
	add_child(p)
	return p


static var _mat: StandardMaterial3D


## The wash's puff: DrivingFX's lit dust (its albedo is the particle colour), shared by every wash.
static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = DrivingFX._puff_material(Color(1.0, 1.0, 1.0), 0.7)
	return _mat


func _exit_tree() -> void:
	clear(true)


## One tick: `hub` (scene frame) and the rotor's strength 0..1.
func drive(hub: Vector3, strength: float, delta: float) -> void:
	if not is_inside_tree():
		return
	_ray_left -= delta
	if _ray_left <= 0.0 or (_hit.is_empty() and strength > 0.05):
		_ray_left = 0.1
		_hit = {}
		if strength > 0.02:
			var q := PhysicsRayQueryParameters3D.create(hub, hub + Vector3.DOWN * reach, 1 | 16)
			var parent := get_parent() as CollisionObject3D
			if parent:
				q.exclude = [parent.get_rid()]
			_hit = get_world_3d().direct_space_state.intersect_ray(q)
	var k := 0.0
	ground_gap = INF
	if not _hit.is_empty():
		var h := hub.y - float(_hit.position.y)
		ground_gap = h
		k = strength * (1.0 - smoothstep(full_height, reach, h))
	ground_strength = k
	if k > 0.05:
		var at: Vector3 = _hit.position
		ground_point = at
		over_water = _water_at(at)
		var c := spray_color if over_water else _ground_color(_hit)
		c.a *= clampf(k * 1.4, 0.0, 1.0)
		for p: CPUParticles3D in [_dust, _billow]:
			p.global_position = at + Vector3.UP * (0.15 if not over_water else 0.2)
			p.color = c
			p.speed_scale = 0.7 + 0.5 * k
			p.emitting = true
		_push_left -= delta
		if _push_left <= 0.0:
			_push_left = 0.25
			_push_props(at, k)
	else:
		ground_point = Vector3.INF
		_dust.emitting = false
		_billow.emitting = false
	_publish(hub, strength * (0.0 if _hit.is_empty() else 1.0 - smoothstep(full_height + 10.0, reach + 20.0, hub.y - float(_hit.position.y))))


## What the wash throws up off this ground: grit off paving and roofs, dry grass and dust off
## the hills (terrain layer), sand on the beach, a faint haze off a park's or a school's lawn.
func _ground_color(hit: Dictionary) -> Color:
	var obj := hit.get("collider") as CollisionObject3D
	if obj and (obj.collision_layer & CityChunk.TERRAIN_LAYER) != 0:
		return hills_color
	var city := get_tree().get_first_node_in_group("city")
	if city and ("plan" in city) and city.plan != null:
		var w := WorldState.to_world(hit.position)
		var w2 := Vector2(w.x, w.z)
		var zone: int = city.plan.zone_at(w2)
		if zone == MacroMap.Zone.BEACH:
			return sand_color
		if zone == MacroMap.Zone.CITY:
			var bi: Vector2i = city.plan.block_index_at(w2)
			var kind := int(city.plan.block(bi.x, bi.y).get("kind", -1))
			if kind == CityPlan.BlockKind.PARK or kind == CityPlan.BlockKind.SCHOOL:
				return lawn_color
	return dust_color


func _water_at(at: Vector3) -> bool:
	if at.y > 0.6:
		return false
	var city := get_tree().get_first_node_in_group("city")
	if city == null or not ("plan" in city) or city.plan == null:
		return false
	var w := WorldState.to_world(at)
	return city.plan.zone_at(Vector2(w.x, w.z)) == MacroMap.Zone.OCEAN


## The global the foliage reads: the strongest wash in the scene owns it.
func _publish(hub: Vector3, k: float) -> void:
	var me := get_instance_id()
	if k > 0.01:
		if _owner_id == me or _owner_id == 0 or k >= _owner_k or not is_instance_id_valid(_owner_id):
			_owner_id = me
			_owner_k = k
			RenderingServer.global_shader_parameter_set("heli_downwash", Vector4(hub.x, hub.y, hub.z, k))
	elif _owner_id == me:
		clear()


## Takes this wash off the ground and out of the shader global (`leaving`: the node is on its way
## out of the tree, so nothing is touched on it and the global is reset after the frame's frees).
func clear(leaving: bool = false) -> void:
	ground_strength = 0.0
	if not leaving and _dust and is_instance_valid(_dust):
		_dust.emitting = false
		_billow.emitting = false
	if _owner_id == get_instance_id():
		_owner_id = 0
		_owner_k = 0.0
		if leaving:
			RenderingServer.global_shader_parameter_set.call_deferred("heli_downwash", Vector4(0.0, -10000.0, 0.0, 0.0))
		else:
			RenderingServer.global_shader_parameter_set("heli_downwash", Vector4(0.0, -10000.0, 0.0, 0.0))


func _push_props(at: Vector3, k: float) -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = push_radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), at + Vector3.UP * 1.0)
	q.collision_mask = 4
	var parent := get_parent() as CollisionObject3D
	if parent:
		q.exclude = [parent.get_rid()]
	for r: Dictionary in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var body := r.collider as RigidBody3D
		if body == null or body is VehicleBody3D or body.freeze:
			continue
		var away := body.global_position - at
		away.y = 0.0
		var d := away.length()
		var f := k * (1.0 - clampf(d / push_radius, 0.0, 1.0))
		if f <= 0.0:
			continue
		var dir := away / d if d > 0.1 else Vector3.RIGHT
		body.sleeping = false
		body.apply_central_impulse((dir + Vector3.UP * 0.25) * push_accel * f * body.mass * 0.25)
