class_name PhysicsProp
extends RigidBody3D
## A knock-around street object with a real model (barrels, tyres). Joins the physics_prop group
## so PhysicsBudget manages it. Call setup() before adding it to the tree.

## How far a prop draws (metres), see _ready().
const DRAW_DISTANCE := 140.0

var _mesh: Mesh
var _shape: Shape3D
var _shape_offset := Vector3.ZERO


func setup(mesh: Mesh, shape: Shape3D, shape_offset: Vector3, mass_kg: float) -> void:
	_mesh = mesh
	_shape = shape
	_shape_offset = shape_offset
	mass = mass_kg


func _init() -> void:
	collision_layer = 4
	collision_mask = 7
	add_to_group("physics_prop")


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	# A node each (one draw, and one per shadow cascade): past DRAW_DISTANCE a can or a tyre is
	# a few pixels, so it stops drawing (a few hundred stood in every street frame).
	mi.visibility_range_end = DRAW_DISTANCE
	mi.visibility_range_end_margin = DRAW_DISTANCE * 0.1
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mi)
	var shape := CollisionShape3D.new()
	shape.shape = _shape
	shape.position = _shape_offset
	add_child(shape)
	set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)
