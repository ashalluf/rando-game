class_name EncampmentItem
extends StaticBody3D
## One knockable thing at a sidewalk encampment - a tent, a tarp, a cart, a heap of bags, a
## mattress, a chair, a bike - standing still until something hits it. Drawn by the chunk's
## MultiMesh batch like any street prop (so a whole camp is a handful of draw calls); this body is
## only its collision. A bullet shoves at it (take_hit), and when it has taken enough, or a car's
## bumper or a blast reaches it (knock), its batch instance is hidden and a real rigid body with
## the same mesh is thrown in its place: an explosion scatters a camp across the street. The body
## is debris, so PhysicsBudget clears it with the rest, and the chunk remembers it is gone
## (WorldState), so it does not stand back up when the chunk is rebuilt.
##
## On the props AND the npc layer: props so the player cannot walk through a tent and blasts
## (Player.BLAST_MASK) find it; npc so a car's bumper zone (Vehicle, mask player | npc) knocks it
## instead of the car stopping dead against it. Mask 0: a static body never detects anything.

var chunk: Node
## The WorldState id under the chunk's key.
var item_id: String = ""
## [batch key, instance index] pairs this item is drawn as.
var instances: Array = []
## What the thrown body is built from: its mesh, collision box size and centre height, mass.
var mesh: Mesh
var box := Vector3.ONE
var box_y: float = 0.5
var mass_kg: float = 8.0
var tint := Color.WHITE
var custom := Color(0.0, 0.0, 0.0, 0.0)
## Damage a bullet does before it tips over rather than just shaking.
var health: float = 45.0
var _gone: bool = false


func _init() -> void:
	collision_layer = 4 | 8
	collision_mask = 0


func setup(size: Vector3, centre_y: float) -> void:
	box = size
	box_y = centre_y
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	shape.position = Vector3(0.0, centre_y, 0.0)
	add_child(shape)


## A bullet (Weapon rays call this on anything that is not a rigid body).
func take_hit(_shape_index: int, damage: float, hit_dir: Vector3 = Vector3.UP) -> void:
	if _gone:
		return
	health -= damage
	if health <= 0.0:
		knock(hit_dir.normalized() * 5.0 + Vector3.UP * 2.0)


## A blast, a car, anything heavy: over it goes, as a real body thrown by `impulse`.
func knock(impulse: Vector3, _gibs: int = 0) -> void:
	if _gone:
		return
	_gone = true
	collision_layer = 0
	if chunk and is_instance_valid(chunk):
		var nodes: Dictionary = chunk.get("_mm_nodes")
		for inst: Array in instances:
			MultiMeshBatch.hide_instance(nodes.get(inst[0]) as MultiMeshInstance3D, int(inst[1]))
		WorldState.mark_destroyed(String(chunk.get("key")), item_id)
	var parent := get_parent()
	if parent and mesh:
		throw(parent, mesh, box, box_y, mass_kg, tint, custom, transform, impulse)
	queue_free()


## A camp piece as a real body thrown by `impulse` from `xform` (in `parent`'s space): debris,
## cleared by PhysicsBudget with the rest. Also a pushed cart let go of (RoughSleeper.knock).
static func throw(parent: Node, piece_mesh: Mesh, size: Vector3, centre_y: float, mass: float, piece_tint: Color, piece_custom: Color, xform: Transform3D, impulse: Vector3) -> void:
	if parent == null or piece_mesh == null or not PhysicsBudget.make_room(1):
		return
	var body := PhysicsProp.new()
	var shape := BoxShape3D.new()
	shape.size = size
	body.setup(piece_mesh, shape, Vector3(0.0, centre_y, 0.0), mass)
	body.transform = xform
	parent.add_child(body)
	# The batch carried the colour and the wear per instance (COLOR, INSTANCE_CUSTOM in
	# shaders/encampment.gdshaderinc), so the thrown body is drawn as a one-instance MultiMesh
	# too rather than a plain mesh that would come out white and new.
	for c in body.get_children():
		var mi := c as MeshInstance3D
		if mi:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = piece_mesh
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D.IDENTITY)
			mm.set_instance_color(0, piece_tint)
			mm.set_instance_custom_data(0, piece_custom)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			body.add_child(mmi)
			mi.queue_free()
	PhysicsBudget.register_debris(body)
	# Light and baggy: a tent or a tarp catches the blast more than its mass says.
	var fling := impulse.limit_length(26.0)
	body.linear_velocity = fling
	body.angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0), randf_range(-4.0, 4.0))
