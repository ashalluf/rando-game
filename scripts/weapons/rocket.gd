class_name Rocket
extends Node3D
## Dumb-fire rocket. Flies straight, explodes on contact or after `lifetime` seconds.

var speed: float = 70.0
var lifetime: float = 6.0
var explosion_radius: float = 9.0
var explosion_launch_speed: float = 30.0
var player_launch_speed: float = 35.0
var direction: Vector3 = Vector3.FORWARD
var exclude: Array[RID] = []

var _age: float = 0.0
var _exploded: bool = false


func _ready() -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 0.7
	cyl.radial_segments = 8
	body.mesh = cyl
	body.material_override = WeaponFX.unshaded(Color(0.75, 0.2, 0.15))
	body.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(body)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.25
	cone.radial_segments = 8
	nose.mesh = cone
	nose.material_override = WeaponFX.unshaded(Color(0.9, 0.85, 0.3))
	nose.position = Vector3(0.0, 0.0, -0.47)
	nose.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(nose)
	var flame := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	flame.mesh = sphere
	flame.material_override = WeaponFX.unshaded(Color(1.0, 0.6, 0.2))
	flame.position = Vector3(0.0, 0.0, 0.42)
	add_child(flame)

	var smoke := CPUParticles3D.new()
	smoke.amount = 40
	smoke.lifetime = 0.8
	smoke.local_coords = false
	smoke.direction = Vector3(0.0, 0.0, 1.0)
	smoke.spread = 8.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 2.0
	smoke.gravity = Vector3(0.0, 1.5, 0.0)
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.0
	var puff := SphereMesh.new()
	puff.radius = 0.15
	puff.height = 0.3
	puff.radial_segments = 6
	puff.rings = 3
	puff.material = WeaponFX.unshaded(Color(0.8, 0.8, 0.8, 0.6))
	smoke.mesh = puff
	smoke.position = Vector3(0.0, 0.0, 0.45)
	add_child(smoke)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_age += delta
	var step := direction * speed * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, Player.AIM_MASK, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		explode(hit.position)
		return
	global_position += step
	if _age >= lifetime:
		explode(global_position)


func explode(at: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	Explosion.blast(self, at, explosion_radius, explosion_launch_speed, player_launch_speed)
	queue_free()
