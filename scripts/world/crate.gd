extends RigidBody3D
## Basic greybox physics crate. Joins the "physics_prop" group (see PhysicsBudget).

@onready var mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)


func set_material(material: Material) -> void:
	if not is_node_ready():
		await ready
	mesh.material_override = material
