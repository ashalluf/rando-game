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

@export_group("Map")
## Use the big-picture map (ocean west, hills north, peninsula south-west, downtown east).
## Off = the plain endless grid with districts in rings around the origin.
@export var use_macro_map: bool = true

@export_group("Streaming")
## Blocks around the player that get full detail (2 = a 5 x 5 area).
@export var load_radius_blocks: int = 2
## Blocks around the player that get cheap LOD boxes (the skyline).
@export var lod_radius_blocks: int = 7
@export var update_interval: float = 0.25
## Chunks built per update, to spread the work out. Must keep up with a car at nitro speed.
@export var max_full_builds_per_update: int = 2
@export var max_lod_builds_per_update: int = 8
## When the player is this far from the origin, the whole world shifts back to it.
@export var recenter_distance: float = 1000.0
@export var ground_size: float = 4000.0

@export_group("Street life")
@export var lamp_spacing: float = 24.0
@export var tree_spacing: float = 12.0
@export var trash_cans_per_block: int = 2
## Parked cars per block (physics bodies; count against the PhysicsBudget cap).
@export var cars_per_block: int = 5
@export var pedestrians_per_block: int = 4
## Grass blades per park block (MultiMesh, wind shader).
@export var grass_per_park: int = 2500
## Hard cap on live pedestrians.
@export var max_pedestrians: int = 70
## Cars driving around at once.
@export var traffic_cars: int = 14

@export_group("Look")
@export var sun_rotation_degrees: Vector3 = Vector3(-48.0, 35.0, 0.0)
@export var ground_color: Color = Color(0.45, 0.48, 0.36)
@export var asphalt_color: Color = Color(0.20, 0.20, 0.22)
@export var sidewalk_color: Color = Color(0.68, 0.66, 0.62)
@export var grass_color: Color = Color(0.36, 0.58, 0.30)
@export var plaza_color: Color = Color(0.78, 0.74, 0.68)
@export var path_color: Color = Color(0.80, 0.76, 0.66)
@export var water_color: Color = Color(0.25, 0.55, 0.80)
@export var ocean_color: Color = Color(0.12, 0.42, 0.66)
@export var sand_color: Color = Color(0.80, 0.72, 0.52)
@export var hill_grass_color: Color = Color(0.38, 0.47, 0.25)
@export var hill_rock_color: Color = Color(0.48, 0.43, 0.38)
@export var tarmac_color: Color = Color(0.32, 0.32, 0.33)
@export var runway_color: Color = Color(0.42, 0.42, 0.43)
@export var concrete_color: Color = Color(0.58, 0.57, 0.55)

var plan: CityPlan
## Vector2i(ix, iz) -> CityChunk
var chunks: Dictionary = {}
var recenter_count: int = 0

var _player: Node3D
var _ground: StaticBody3D
var _timer: float = 0.0
## Far (always loaded) versions of the landmarks, keyed by id.
var _far_landmarks: Dictionary = {}


func _ready() -> void:
	add_to_group("city")
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = sun_rotation_degrees
	WorldState.world_offset = Vector3.ZERO
	if WorldState.pending_seed >= 0:
		world_seed = WorldState.pending_seed
		WorldState.pending_seed = -1
	plan = CityPlan.new()
	plan.seed = world_seed
	plan.block_size_range = block_size_range
	plan.street_width = street_width
	plan.avenue_width = avenue_width
	plan.sidewalk_width = sidewalk_width
	plan.downtown_radius = downtown_radius
	plan.midtown_radius = midtown_radius
	if use_macro_map:
		plan.macro = MacroMap.new()
		plan.macro.seed = world_seed
		plan.macro.setup()
	_build_ground()
	_build_far_landmarks()
	var traffic := TrafficManager.new()
	traffic.name = "Traffic"
	traffic.plan = plan
	traffic.max_cars = traffic_cars
	add_child(traffic)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_apply_spawn_override()
	update_streaming(true)


## Cheap versions of every landmark, always present, so the sign and the wheel show from anywhere.
func _build_far_landmarks() -> void:
	if plan.macro == null:
		return
	for lm in Landmarks.all():
		var holder := Node3D.new()
		holder.name = "FarLandmark_" + lm.id
		holder.position = -WorldState.world_offset
		add_child(holder)
		Landmarks.build(lm, holder, null, plan, false)
		_far_landmarks[lm.id] = holder


## Debug helper: start somewhere else. Web: open the page with ?spawn=x,z or ?spawn=x,z,yaw,pitch
## (degrees; yaw 0 faces north/-Z, 90 faces west). Desktop: run with `-- --spawn=x,z,yaw,pitch`.
func _apply_spawn_override() -> void:
	if _player == null:
		return
	var text := ""
	var showroom := false
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String:
			for part in (search as String).trim_prefix("?").split("&"):
				if part.begins_with("spawn="):
					text = part.trim_prefix("spawn=")
				elif part.begins_with("showroom"):
					showroom = true
	else:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--spawn="):
				text = arg.trim_prefix("--spawn=")
			elif arg.begins_with("--showroom"):
				showroom = true
	var wp := Vector2.ZERO
	var yaw := 0.0
	var parts := text.split(",")
	if parts.size() >= 2:
		wp = Vector2(parts[0].to_float(), parts[1].to_float())
		var y := plan.height_at(wp) + 2.0
		_player.global_position = Vector3(wp.x, y, wp.y)
		if _player.has_method("respawn"):
			_player.set("_spawn_transform", _player.global_transform)
		if parts.size() >= 4:
			yaw = parts[2].to_float()
			var rig: Node3D = _player.get("camera_rig")
			if rig and rig.has_method("set_look"):
				rig.set_look(yaw, parts[3].to_float())
	if showroom:
		_build_showroom(Vector3(wp.x, plan.height_at(wp), wp.y), deg_to_rad(yaw))


## Debug (`?showroom` on the web, `-- --showroom` on desktop): every car type and pedestrian
## model lined up in front of the spawn point, to judge generated assets quickly.
func _build_showroom(at: Vector3, yaw: float) -> void:
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := forward.cross(Vector3.UP)
	for i in Vehicle.BodyType.size():
		var car := Vehicle.new()
		car.setup(i as Vehicle.BodyType, Vehicle.PAINTS[i * 2 % Vehicle.PAINTS.size()], Vehicle.Addon.NONE)
		car.position = at + forward * 12.0 + right * (float(i) - 1.5) * 6.0 + Vector3.UP * 1.0
		car.rotation.y = yaw + PI * 0.5
		add_child(car)
	for i in Pedestrian.MODELS.size():
		var ped := Pedestrian.new()
		var spot := at + forward * 5.0 + right * (float(i) - 1.0) * 2.0
		ped.setup(Rect2(spot.x - 1.0, spot.z - 1.0, 2.0, 2.0), 1.0, 1000 + i)
		ped.position = spot + Vector3.UP * 0.5
		add_child(ped)
		ped.set_meta("showroom", true)


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
	var xz := Vector2(wp.x, wp.z)
	var zone := plan.zone_at(xz)
	if zone != MacroMap.Zone.CITY:
		return MacroMap.zone_name(zone)
	return CityPlan.district_name(plan.district_at(xz))


## Makes sure the chunk under a local position exists at full detail, right now.
func ensure_loaded_at(local_pos: Vector3) -> void:
	if plan == null:
		return
	var wp := world_position(local_pos)
	var k := plan.block_index_at(Vector2(wp.x, wp.z))
	if chunks.has(k):
		if chunks[k].level == CityChunk.Level.FULL:
			return
		for id in chunks[k].built_landmarks:
			_set_far_landmark_visible(id, true)
		chunks[k].queue_free()
		chunks.erase(k)
	_build_chunk(k, CityChunk.Level.FULL)


## Height of solid ground at a local position (terrain, or the sidewalk top in the city).
func ground_height_at(local_pos: Vector3) -> float:
	if plan == null:
		return 0.0
	var wp := world_position(local_pos)
	return maxf(plan.height_at(Vector2(wp.x, wp.z)), 0.0) + 0.4


## Where solid ground really is under a local position: loads the chunk, then raycasts down
## onto the world layer. Falls back to the analytic height when nothing is hit yet.
func surface_height_at(local_pos: Vector3) -> float:
	ensure_loaded_at(local_pos)
	var analytic := ground_height_at(local_pos)
	var space := get_world_3d().direct_space_state
	if space == null:
		return analytic
	var from := Vector3(local_pos.x, analytic + 80.0, local_pos.z)
	var to := Vector3(local_pos.x, -10.0, local_pos.z)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	if hit.is_empty():
		return analytic
	return hit.position.y


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
			for id in chunks[k].built_landmarks:
				_set_far_landmark_visible(id, true)
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
		"path": path_color, "water": water_color, "ocean": ocean_color, "sand": sand_color,
		"hill_grass": hill_grass_color, "hill_rock": hill_rock_color,
		"tarmac": tarmac_color, "runway": runway_color, "concrete": concrete_color,
		"lamp_spacing": lamp_spacing, "tree_spacing": tree_spacing, "trash_cans_per_block": trash_cans_per_block,
		"cars_per_block": cars_per_block, "pedestrians_per_block": pedestrians_per_block, "max_pedestrians": max_pedestrians,
		"grass_per_park": grass_per_park,
	}
	add_child(chunk)
	chunk.build()
	chunks[k] = chunk
	for id in chunk.built_landmarks:
		_set_far_landmark_visible(id, false)


func _set_far_landmark_visible(id: String, on: bool) -> void:
	if _far_landmarks.has(id):
		(_far_landmarks[id] as Node3D).visible = on


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
	mesh.material_override = PropFactory.pbr("grass", 6.0, Color(0.85, 0.9, 0.75))
	_ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Thick, so nothing that gets pushed into it by an overlapping shape can pop out underneath.
	box.size = Vector3(ground_size, 40.0, ground_size)
	shape.shape = box
	shape.position = Vector3(0.0, -20.0, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
