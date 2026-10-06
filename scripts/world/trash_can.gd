class_name TrashCan
extends RigidBody3D
## Knock-over-able street trash can (Poly Haven metal can, clean or rusty). Joins the physics_prop
## group so PhysicsBudget manages it. Set `rusty` before adding it to the tree.

## How far a prop draws (metres), see _ready().
const DRAW_DISTANCE := 140.0

## Rusty variant of the model.
var rusty: bool = false
## 1: StreetFurniture's perforated downtown bin instead of the Poly Haven can (set by the chunk).
var style: int = 0


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
	if style == 1:
		# The perforated bin, a MultiMesh of one so it gets its paint and wear (instance custom).
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = StreetFurniture.mesh_bin()
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, StreetFurniture.bin_custom(position))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = DRAW_DISTANCE
		mmi.visibility_range_end_margin = DRAW_DISTANCE * 0.1
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	else:
		var mesh := MeshInstance3D.new()
		mesh.mesh = PropFactory.model_trash_can(rusty)
		# A node each (one draw, and one per shadow cascade): past DRAW_DISTANCE a can or a tyre is
		# a few pixels, so it stops drawing (a few hundred stood in every street frame).
		mesh.visibility_range_end = DRAW_DISTANCE
		mesh.visibility_range_end_margin = DRAW_DISTANCE * 0.1
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mesh)
	set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)
