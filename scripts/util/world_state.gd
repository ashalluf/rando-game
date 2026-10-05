extends Node
## Autoload: things that must survive chunks being freed and rebuilt.
## - Which props were destroyed in which chunk (keyed by chunk key, then prop id).
## - The world origin offset: local position + world_offset = true world position.

## Every change also goes to the `origin_shift` shader global, so a shader holding TRUE world
## positions can find them in the shifted scene (shaders/facade_detail.gdshader).
var world_offset: Vector3 = Vector3.ZERO:
	set(value):
		world_offset = value
		RenderingServer.global_shader_parameter_set("origin_shift", value)
## Seed the next city scene should use (set by the pause menu), or -1 for the scene's own.
var pending_seed: int = -1
var _destroyed: Dictionary = {}
## Damage done to buildings (BuildingDamage), by building key: survives the building's chunk.
var building_damage: Dictionary = {}


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
	pending_seed = -1
	_destroyed.clear()
	building_damage.clear()


func reset_destruction() -> void:
	_destroyed.clear()
	building_damage.clear()


func to_world(local: Vector3) -> Vector3:
	return local + world_offset


func to_local(world: Vector3) -> Vector3:
	return world - world_offset
