extends Node
## Autoload: things that must survive chunks being freed and rebuilt.
## - Which props were destroyed in which chunk (keyed by chunk key, then prop id).
## - The world origin offset: local position + world_offset = true world position.

var world_offset: Vector3 = Vector3.ZERO
var _destroyed: Dictionary = {}


func mark_destroyed(chunk_key: String, prop_id: String) -> void:
	if not _destroyed.has(chunk_key):
		_destroyed[chunk_key] = {}
	_destroyed[chunk_key][prop_id] = true


func is_destroyed(chunk_key: String, prop_id: String) -> bool:
	return _destroyed.has(chunk_key) and _destroyed[chunk_key].has(prop_id)


func destroyed_count() -> int:
	var n := 0
	for key in _destroyed:
		n += _destroyed[key].size()
	return n


func reset() -> void:
	world_offset = Vector3.ZERO
	_destroyed.clear()


func to_world(local: Vector3) -> Vector3:
	return local + world_offset


func to_local(world: Vector3) -> Vector3:
	return world - world_offset
