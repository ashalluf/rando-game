class_name Ragdoll
extends Node3D
## A floppy six-piece body (torso, head, two arms, two legs) held together by pin joints.
## Spawned when a pedestrian gets hit. Registered as debris so PhysicsBudget frees it later.

var bodies: Array[RigidBody3D] = []


func build(shirt: Color, pants: Color, skin: Color) -> void:
	var torso := _piece(Vector3(0.5, 0.65, 0.3), Vector3(0.0, 1.05, 0.0), shirt, 8.0)
	var head := _piece(Vector3(0.28, 0.28, 0.28), Vector3(0.0, 1.55, 0.0), skin, 3.0, true)
	var l_arm := _piece(Vector3(0.16, 0.6, 0.16), Vector3(-0.36, 1.05, 0.0), skin, 2.0)
	var r_arm := _piece(Vector3(0.16, 0.6, 0.16), Vector3(0.36, 1.05, 0.0), skin, 2.0)
	var l_leg := _piece(Vector3(0.2, 0.7, 0.2), Vector3(-0.14, 0.38, 0.0), pants, 4.0)
	var r_leg := _piece(Vector3(0.2, 0.7, 0.2), Vector3(0.14, 0.38, 0.0), pants, 4.0)
	_pin(torso, head, Vector3(0.0, 1.4, 0.0))
	_pin(torso, l_arm, Vector3(-0.3, 1.33, 0.0))
	_pin(torso, r_arm, Vector3(0.3, 1.33, 0.0))
	_pin(torso, l_leg, Vector3(-0.14, 0.72, 0.0))
	_pin(torso, r_leg, Vector3(0.14, 0.72, 0.0))


func _ready() -> void:
	set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)


func fling(impulse: Vector3) -> void:
	for b in bodies:
		b.apply_central_impulse(impulse * b.mass / 23.0)
		b.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))


func _piece(size: Vector3, pos: Vector3, color: Color, piece_mass: float, round_head: bool = false) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 5 # world and props, not other characters
	body.mass = piece_mass
	body.position = pos
	var mesh := MeshInstance3D.new()
	if round_head:
		var sphere := SphereMesh.new()
		sphere.radius = size.x * 0.5
		sphere.height = size.x
		sphere.radial_segments = 8
		sphere.rings = 4
		mesh.mesh = sphere
	else:
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
	mesh.material_override = PropFactory.material(color, 0.8)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	add_child(body)
	bodies.append(body)
	return body


func _pin(a: RigidBody3D, b: RigidBody3D, at: Vector3) -> void:
	var joint := PinJoint3D.new()
	joint.position = at
	add_child(joint)
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
