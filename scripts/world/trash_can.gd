class_name TrashCan
extends RigidBody3D
## Knock-over-able street trash can (Poly Haven metal can, clean or rusty). Joins the physics_prop
## group so PhysicsBudget manages it. Set `rusty` before adding it to the tree.

## Rusty variant of the model.
var rusty: bool = false


func _init() -> void:
	collision_layer = 4
	collision_mask = 7
	mass = 6.0
	add_to_group("physics_prop")
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.31
	cyl.height = 0.92
	shape.shape = cyl
	shape.position = Vector3(0.0, 0.46, 0.0)
	add_child(shape)


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = PropFactory.model_trash_can(rusty)
	add_child(mesh)
	set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)
