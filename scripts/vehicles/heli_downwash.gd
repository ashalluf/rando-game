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
@export var dust_color: Color = Color(0.56, 0.52, 0.45, 0.55)
@export var spray_color: Color = Color(0.86, 0.9, 0.94, 0.5)

## The wash's strength on the ground this tick (0..1) and where it lands (local), for the tests.
var ground_strength: float = 0.0
var ground_point: Vector3 = Vector3.INF
var over_water: bool = false
## Metres from the hub down to the ground under it (INF past `reach`): the auto-flare reads it.
var ground_gap: float = INF

var _dust: CPUParticles3D
var _ray_left: float = 0.0
var _push_left: float = 0.0
var _hit: Dictionary = {}

## The wash that owns the shader global, and how strong it was.
static var _owner_id: int = 0
static var _owner_k: float = 0.0


func _ready() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "WashDust"
	_dust.top_level = true
	_dust.amount = 56
	_dust.lifetime = 1.7
	_dust.local_coords = false
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_dust.emission_ring_axis = Vector3.UP
	_dust.emission_ring_radius = 7.0
	_dust.emission_ring_inner_radius = 2.0
	_dust.emission_ring_height = 0.3
	_dust.direction = Vector3.UP
	_dust.spread = 60.0
	_dust.initial_velocity_min = 1.5
	_dust.initial_velocity_max = 4.5
	_dust.radial_accel_min = 10.0
	_dust.radial_accel_max = 22.0
	_dust.damping_min = 1.5
	_dust.damping_max = 3.0
	_dust.gravity = Vector3(0.0, -1.2, 0.0)
	_dust.scale_amount_min = 1.6
	_dust.scale_amount_max = 3.6
	var curve := Curve.new()
	# A growth above 1 needs the cap raised first (CLAUDE.md, effects).
	curve.max_value = 3.0
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 3.0))
	_dust.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	_dust.color_ramp = ramp
	_dust.color = dust_color
	_dust.angle_min = -180.0
	_dust.angle_max = 180.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = AmbientCraft._smoke_material()
	_dust.mesh = quad
	_dust.custom_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120))
	_dust.emitting = false
	add_child(_dust)


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
		_dust.global_position = at + Vector3.UP * (0.25 if not over_water else 0.2)
		var c := spray_color if over_water else dust_color
		c.a *= clampf(k * 1.4, 0.0, 1.0)
		_dust.color = c
		_dust.speed_scale = 0.7 + 0.5 * k
		_dust.emitting = true
		_push_left -= delta
		if _push_left <= 0.0:
			_push_left = 0.25
			_push_props(at, k)
	else:
		ground_point = Vector3.INF
		_dust.emitting = false
	_publish(hub, strength * (0.0 if _hit.is_empty() else 1.0 - smoothstep(full_height + 10.0, reach + 20.0, hub.y - float(_hit.position.y))))


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
