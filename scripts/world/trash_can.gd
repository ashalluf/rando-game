class_name TrashCan
extends RigidBody3D
## Knock-over-able street trash can. Joins the physics_prop group so PhysicsBudget manages it.


func _init() -> void:
	collision_layer = 4
	collision_mask = 7
	mass = 6.0
	add_to_group("physics_prop")
	var mesh := MeshInstance3D.new()
	mesh.mesh = PropFactory.trash_can_mesh()
	mesh.position = Vector3(0.0, 0.5, 0.0)
	add_child(mesh)
	var lid := MeshInstance3D.new()
	lid.mesh = PropFactory.cylinder("trash_lid", 0.38, 0.08, Color(0.2, 0.28, 0.25), -1.0, 8)
	lid.position = Vector3(0.0, 1.02, 0.0)
	add_child(lid)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.36
	cyl.height = 1.06
	shape.shape = cyl
	shape.position = Vector3(0.0, 0.53, 0.0)
	add_child(shape)


func _ready() -> void:
	set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)
