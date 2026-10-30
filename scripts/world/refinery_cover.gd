class_name RefineryCover
extends Node
## Left by a FULL refinery chunk (Refinery._commit()): while the chunk it is in is shown, the far
## piece of its block (RefineryFar) is hidden, so the plant is never drawn twice. A chunk is built
## hidden and swapped in when complete, and a retired one stays drawn while it fades, so the cover
## asks whether it is visible rather than whether it exists.

## The block (ix, iz) whose far piece this chunk stands for.
var key: Vector2i

static var covers: Dictionary = {}


func _enter_tree() -> void:
	var list: Array = covers.get(key, [])
	list.append(self)
	covers[key] = list


func _exit_tree() -> void:
	var list: Array = covers.get(key, [])
	list.erase(self)
	if list.is_empty():
		covers.erase(key)


## True while a shown chunk covers block `k`.
static func covered(k: Vector2i) -> bool:
	for c: Node in covers.get(k, []):
		if is_instance_valid(c) and c.get_parent() is Node3D and (c.get_parent() as Node3D).is_visible_in_tree():
			return true
	return false
