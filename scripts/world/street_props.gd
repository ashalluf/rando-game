class_name StreetProps
extends StaticBody3D
## One body per chunk holding the collision shapes of all its street props.
## Weapons call take_hit() with the shape index they hit; the chunk decides what breaks.

var chunk: Node3D


func _init() -> void:
	name = "StreetProps"
	collision_layer = 1
	collision_mask = 0 # static never detects; a mask here only makes useless pairs (CLAUDE.md)


func take_hit(shape_index: int, damage: float, hit_dir: Vector3 = Vector3.UP) -> void:
	if shape_index < 0 or chunk == null:
		return
	var owner_id := shape_find_owner(shape_index)
	var node := shape_owner_get_owner(owner_id) as CollisionShape3D
	if node and node.has_meta("prop"):
		chunk.damage_prop(node.get_meta("prop"), damage, hit_dir)
