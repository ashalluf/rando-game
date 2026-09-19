class_name CityStreamer
extends Node3D
## Root of the city scene. Streams CityChunks around the player (full detail near, cheap boxes
## far), moves the ground under the player, and re-centers the world origin when the player
## gets far from it so positions never lose precision. Everything comes from `world_seed`.

@export_group("City")
@export var world_seed: int = 1337
@export var block_size_range: Vector2 = Vector2(70.0, 120.0)
@export var street_width: float = 14.0
@export var avenue_width: float = 24.0
@export var sidewalk_width: float = 4.0
## District rings (meters from the origin).
@export var downtown_radius: float = 180.0
@export var midtown_radius: float = 380.0

@export_group("Streaming")
## Blocks around the player that get full detail (2 = a 5 x 5 area).
@export var load_radius_blocks: int = 2
## Blocks around the player that get cheap LOD boxes (the skyline).
@export var lod_radius_blocks: int = 7
@export var update_interval: float = 0.4
## Chunks built per update, to spread the work out.
@export var max_full_builds_per_update: int = 1
@export var max_lod_builds_per_update: int = 6
## When the player is this far from the origin, the whole world shifts back to it.
@export var recenter_distance: float = 1000.0
@export var ground_size: float = 4000.0

@export_group("Street life")
@export var lamp_spacing: float = 24.0
@export var tree_spacing: float = 12.0
@export var trash_cans_per_block: int = 2

@export_group("Look")
@export var sun_rotation_degrees: Vector3 = Vector3(-48.0, 35.0, 0.0)
@export var ground_color: Color = Color(0.45, 0.48, 0.36)
@export var asphalt_color: Color = Color(0.20, 0.20, 0.22)
@export var sidewalk_color: Color = Color(0.68, 0.66, 0.62)
@export var grass_color: Color = Color(0.36, 0.58, 0.30)
@export var plaza_color: Color = Color(0.78, 0.74, 0.68)
@export var path_color: Color = Color(0.80, 0.76, 0.66)
@export var water_color: Color = Color(0.25, 0.55, 0.80)

var plan: CityPlan
## Vector2i(ix, iz) -> CityChunk
var chunks: Dictionary = {}
var recenter_count: int = 0

var _player: Node3D
var _ground: StaticBody3D
var _timer: float = 0.0


func _ready() -> void:
	add_to_group("city")
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = sun_rotation_degrees
	WorldState.world_offset = Vector3.ZERO
	plan = CityPlan.new()
	plan.seed = world_seed
	plan.block_size_range = block_size_range
	plan.street_width = street_width
	plan.avenue_width = avenue_width
	plan.sidewalk_width = sidewalk_width
	plan.downtown_radius = downtown_radius
	plan.midtown_radius = midtown_radius
	_build_ground()
	_player = get_tree().get_first_node_in_group("player") as Node3D
	update_streaming(true)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= update_interval:
		_timer = 0.0
		update_streaming(false)


func _physics_process(_delta: float) -> void:
	if _player and Vector2(_player.position.x, _player.position.z).length() > recenter_distance:
		recenter()


func world_position(local: Vector3) -> Vector3:
	return WorldState.to_world(local)


func district_name_at(local_pos: Vector3) -> String:
	if plan == null:
		return ""
	var wp := world_position(local_pos)
	return CityPlan.district_name(plan.district_at(Vector2(wp.x, wp.z)))


func building_count() -> int:
	var n := 0
	for chunk in chunks.values():
		n += chunk.building_count
	return n


func chunk_counts() -> Vector2i:
	var full := 0
	var lod := 0
	for chunk in chunks.values():
		if chunk.level == CityChunk.Level.FULL:
			full += 1
		else:
			lod += 1
	return Vector2i(full, lod)


## Loads and frees chunks around the player. With `immediate`, builds everything at once.
func update_streaming(immediate: bool) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var local := _player.global_position
	_ground.position = Vector3(local.x, 0.0, local.z)
	var wp := world_position(local)
	var center := plan.block_index_at(Vector2(wp.x, wp.z))

	var wanted := {}
	for dx in range(-lod_radius_blocks, lod_radius_blocks + 1):
		for dz in range(-lod_radius_blocks, lod_radius_blocks + 1):
			var ring := maxi(absi(dx), absi(dz))
			wanted[Vector2i(center.x + dx, center.y + dz)] = CityChunk.Level.FULL if ring <= load_radius_blocks else CityChunk.Level.LOD

	for k in chunks.keys():
		if not wanted.has(k) or wanted[k] != chunks[k].level:
			chunks[k].queue_free()
			chunks.erase(k)

	var todo: Array = []
	for k in wanted:
		if not chunks.has(k):
			todo.append(k)
	todo.sort_custom(func(a, b): return (a - center).length_squared() < (b - center).length_squared())
	var full_budget := max_full_builds_per_update if not immediate else 1000000
	var lod_budget := max_lod_builds_per_update if not immediate else 1000000
	for k in todo:
		var level: CityChunk.Level = wanted[k]
		if level == CityChunk.Level.FULL:
			if full_budget <= 0:
				continue
			full_budget -= 1
		else:
			if lod_budget <= 0:
				continue
			lod_budget -= 1
		_build_chunk(k, level)


func _build_chunk(k: Vector2i, level: CityChunk.Level) -> void:
	var chunk := CityChunk.new()
	chunk.plan = plan
	chunk.ix = k.x
	chunk.iz = k.y
	chunk.level = level
	chunk.style = {
		"asphalt": asphalt_color, "sidewalk": sidewalk_color, "grass": grass_color, "plaza": plaza_color,
		"path": path_color, "water": water_color, "lamp_spacing": lamp_spacing, "tree_spacing": tree_spacing,
		"trash_cans_per_block": trash_cans_per_block,
	}
	add_child(chunk)
	chunk.build()
	chunks[k] = chunk


## Shifts every 3D child (chunks, player, rockets, debris) so the player is back near the origin.
func recenter() -> void:
	if _player == null:
		return
	var offset := Vector3(_player.position.x, 0.0, _player.position.z)
	WorldState.world_offset += offset
	for child in get_children():
		if child is Node3D:
			child.position -= offset
	if _player.has_method("shift_origin"):
		_player.shift_origin(offset)
	recenter_count += 1


func _build_ground() -> void:
	_ground = StaticBody3D.new()
	_ground.name = "Ground"
	_ground.collision_layer = 1
	_ground.collision_mask = 7
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)
	mesh.mesh = plane
	mesh.material_override = PropFactory.material(ground_color, 0.95)
	_ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ground_size, 2.0, ground_size)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
