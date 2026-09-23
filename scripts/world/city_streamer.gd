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
## How often the window is re-evaluated. Halved (was 0.25) together with the per-tick build
## budgets below, which keeps the THROUGHPUT identical - 8 full chunks a second either way -
## while halving the work any single frame can be asked to do. A chunk is generated
## synchronously, so two of them landing in one frame is a visible hitch; one is half of one.
## Nothing is built at lower detail and nothing is drawn differently: the same city arrives at
## the same rate, in smaller pieces.
@export var update_interval: float = 0.125
## Chunks STARTED per update, to spread the work out. Must keep up with a car at nitro speed.
@export var max_full_builds_per_update: int = 1
@export var max_lod_builds_per_update: int = 4
## Milliseconds of chunk building allowed per frame while playing. A chunk is built in steps
## (CityChunk.build_step(): the roads, then each building, each pedestrian...) and as many run
## each frame as fit, at least one. It used to be built whole inside one frame: a detailed block
## is about a hundred milliseconds of work on a slow machine, and the physics then ran up to
## eight catch-up steps in the next frame to make up for the stall, so flying over the city
## stuttered every few blocks. Same city, same order; it just arrives a slice a frame, and the
## block it replaces stays up until it is complete.
@export var build_budget_ms: float = 4.0
## Chunks that may be under construction at once. Starting more does not build them any faster -
## the budget is per frame - it only leaves more half-built blocks in the tree.
@export var max_pending_builds: int = 6
## Seconds of travel the streaming window is pushed ahead of the player by. The window used to
## be centred on where they were standing, which is always behind where they are going: at boost
## or nitro speed the builder was still starting the block they had already reached. Leading it
## is what every open-world streamer does, and this player is faster than most.
@export var stream_lookahead: float = 1.5
## Ceiling on that lead, in metres, so a jet at full throttle does not ask for the far side of
## the basin and starve the blocks it is actually flying over.
@export var stream_lookahead_max: float = 300.0
## Blocks a chunk is kept for after it drops out of the wanted window. Bigger than
## `lod_radius_blocks` would avoid re-building a chunk that sits exactly on the edge, but it is
## NOT worth it: every kept chunk is about fourteen draw-producing nodes, so one extra ring cost
## ~560 draw calls on a frame that already submits over three thousand - to save rebuilding
## boxes. Kept equal to `lod_radius_blocks`, i.e. no hysteresis, which is the cheap answer.
## Raise it by 1 only if profiling ever shows edge rebuilds costing more than the draws do.
@export var keep_radius_blocks: int = 7
## Blocks around the player that stay full detail no matter where the lead is pointing (1 = the
## 3 x 3 around them). This is the cost of leading the window: the full-detail set is the union
## of the led one and this one, so it is a few more chunks than the old centred window built.
## Drop it to 0 to pay for nothing but the block underfoot.
@export var min_full_radius_blocks: int = 1
## Seconds a coarse LOD chunk spends dissolving once its detailed replacement is standing in the
## same place. This is the last of the swap: build-before-free stopped the block going missing,
## and this stops it changing in a single frame. 0 turns it off and swaps instantly.
@export var lod_fade_time: float = 0.45
## Tiles of coarse far city kept around the player (see scripts/world/skyline.gd). 5 reaches
## about three kilometres at six blocks a tile, which is what makes the skyline visible from
## across the basin instead of the world ending seven blocks out. Each tile is ONE draw call.
@export var skyline_tiles: int = 7
## Show the loading screen at startup: compiles every shader and pre-builds a wide area, so the
## stalls that would otherwise land mid-play (first explosion, first rain, first unseen car
## paint) are paid once, up front. See scripts/ui/loading_screen.gd.
@export var show_loading_screen: bool = true
## Far tiles built per update. They are cheap next to a FULL chunk (no nodes, no collision, no
## props) but a tile still scans 36 blocks, so it is budgeted like everything else.
@export var max_skyline_builds_per_update: int = 3
## When the player is this far from the origin, the whole world shifts back to it.
@export var recenter_distance: float = 1000.0
## The ground follower is the whole world outside the streamed chunks, so it has to reach past
## anything the player can see from the air. At 4 km across, its edge WAS the horizon.
@export var ground_size: float = 14000.0
## How many metres across the baked macro map covers, and its resolution. 256 costs about a
## quarter of a second once, at load.
@export var macro_span: float = 16000.0
## Corner darkening over the whole frame (0 turns it off). See shaders/vignette.gdshader.
@export var vignette_strength: float = 0.24
## Subdivisions of the ground follower (PlaneMesh.subdivide_*). The plane's world position is
## snapped to its vertex spacing so its vertices land on fixed world points; without that the
## lifted mountains swim as you walk. N subdivisions make N + 1 quads - see ground_step().
const GROUND_SUBDIVISIONS := 200

@export_group("Street life")
@export var lamp_spacing: float = 24.0
@export var tree_spacing: float = 12.0
@export var trash_cans_per_block: int = 2
## Parked cars per block (physics bodies; count against the PhysicsBudget cap).
@export var cars_per_block: int = 5 # fallback; districts set "parked"
@export var pedestrians_per_block: int = 8 # fallback; districts set "people"
## Grass blades per park block (MultiMesh, wind shader).
@export var grass_per_park: int = 6500
## Hard cap on live pedestrians (animated characters; the web build is capped lower below).
@export var max_pedestrians: int = 650
## Cars driving around at once.
@export var traffic_cars: int = 150
## The browser build renders with WebGL at a fraction of desktop speed: caps used there instead.
@export var web_max_pedestrians: int = 140
@export var web_traffic_cars: int = 36
## Cars crawling the airport drop-off loop while the player is near the terminal (web: fewer).
@export var airport_loop_cars: int = 90
## Cars cruising the freeway decks near the player (web: fewer).
@export var freeway_cars: int = 70
@export var web_freeway_cars: int = 20
@export var web_airport_loop_cars: int = 30
## People packed on the terminal curb.
@export var airport_crowd: int = 45

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
## Where the streaming window was last centred; chunks read it to size their collision.
var _center_block: Vector2i = Vector2i.ZERO
## The block the led streaming window is centred on (update_streaming), for build priority.
var _focus_block: Vector2i = Vector2i.ZERO
var _skyline: Skyline
var _ground_material: ShaderMaterial
## The far hill planting's material (shaders/far_canopy.gdshader). It computes the ground
## follower's height itself, so every uniform that height reads is set on both materials.
var _canopy_material: ShaderMaterial
## Every material that computes the far ground's height (the canopy and anything seated with it),
## so the uniforms that height reads are kept in step on all of them.
var _far_ground_materials: Array[ShaderMaterial] = []
var _timer: float = 0.0
## Chunks being built over several frames, by block, hidden until finished (see _advance_builds).
var _pending: Dictionary = {}
## Far (always loaded) versions of the landmarks, keyed by id.
var _far_landmarks: Dictionary = {}


func _ready() -> void:
	add_to_group("city")
	if OS.has_feature("web"):
		max_pedestrians = mini(max_pedestrians, web_max_pedestrians)
		traffic_cars = mini(traffic_cars, web_traffic_cars)
		airport_loop_cars = mini(airport_loop_cars, web_airport_loop_cars)
		freeway_cars = mini(freeway_cars, web_freeway_cars)
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
	_build_skyline()
	_start_loading_screen()
	_build_vignette()
	_build_far_landmarks()
	var traffic := TrafficManager.new()
	traffic.name = "Traffic"
	traffic.plan = plan
	traffic.max_cars = traffic_cars
	traffic.max_loop_cars = airport_loop_cars
	traffic.max_freeway_cars = freeway_cars
	add_child(traffic)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_apply_spawn_override()
	update_streaming(true)
	_settle_player()


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
		if lm.id == "sign":
			_seat_far_sign(holder, lm.anchor)


## The far ridge sign stands on the far ground, not the real one. It is built level with the
## highest real ground under its letters, and from across the basin the drawn ridge is lower, so
## the name hung in the sky beside the peak. far_canopy.gdshader's rigid mode moves the whole
## thing onto the drawn ridge in one piece, so it stays level.
func _seat_far_sign(holder: Node3D, anchor: Vector2) -> void:
	if _canopy_material == null:
		return
	var line := Landmarks.sign_line(anchor, plan)
	var mat := _canopy_material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("rigid", true)
	mat.set_shader_parameter("seat_a", line.a)
	mat.set_shader_parameter("seat_b", line.b)
	mat.set_shader_parameter("seat_ground", line.ground)
	_far_ground_materials.append(mat)
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		# Moved by up to tens of metres in the shader, past the bounds the renderer culls on.
		(mi as MeshInstance3D).extra_cull_margin = 120.0


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
		if parts.size() >= 5:
			y = parts[4].to_float() # optional height, for aerial views
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
	# No traffic in the showroom: it sits on a road and cars kept flattening the exhibits.
	for node in get_children():
		if node is TrafficManager:
			(node as TrafficManager).max_cars = 0
			(node as TrafficManager).max_freeway_cars = 0
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := forward.cross(Vector3.UP)
	for i in Vehicle.BodyType.size():
		var car := Vehicle.new()
		car.setup(i as Vehicle.BodyType, Vehicle.PAINTS[i * 2 % Vehicle.PAINTS.size()], Vehicle.Addon.NONE)
		car.position = at + forward * 12.0 + right * (float(i) - 1.5) * 6.0 + Vector3.UP * 1.0
		car.rotation.y = yaw + PI * 0.5
		add_child(car)
	for k in Aircraft.Kind.size():
		var jet := Aircraft.new()
		jet.setup_aircraft(k as Aircraft.Kind)
		jet.position = at + forward * 34.0 + right * (float(k) - 0.5) * 44.0 + Vector3.UP * 1.0
		jet.rotation.y = yaw + PI * 0.5
		add_child(jet)
	var props: Array[Mesh] = [PropFactory.model_hydrant(false), PropFactory.model_hydrant(true), PropFactory.model_trash_can(false), PropFactory.model_trash_can(true), PropFactory.model_bench(), PropFactory.model_barrier(), PropFactory.model_barrel(), PropFactory.model_tyre(), PropFactory.model_planter(), PropFactory.model_cafe_set(), PropFactory.model_lamp(), PropFactory.model_shrub(0), PropFactory.model_shrub(2), PropFactory.model_manhole(), PropFactory.model_barrier_tall(), PropFactory.model_tree(0), PropFactory.model_tree(1), PropFactory.model_tree(2), PropFactory.model_tree(3), PropFactory.model_tree(4), PropFactory.model_hill_tree(0), PropFactory.model_hill_tree(1), PropFactory.model_hill_tree(2), PropFactory.model_hill_tree(3)]
	for i in props.size():
		var mi := MeshInstance3D.new()
		mi.mesh = props[i]
		mi.position = at + forward * 4.0 + right * (float(i) - float(props.size() - 1) * 0.5) * 1.7 + Vector3.UP * CityChunk.ROAD_TOP
		mi.rotation.y = yaw + 0.6
		add_child(mi)
	for i in Pedestrian.MODELS.size():
		var ped := Pedestrian.new()
		var spot := at + forward * 5.0 + right * (float(i) - float(Pedestrian.MODELS.size() - 1) * 0.5) * 1.6
		ped.setup(Rect2(spot.x - 1.0, spot.z - 1.0, 2.0, 2.0), 1.0, 1000 + i)
		ped.position = spot + Vector3.UP * 0.5
		add_child(ped)
		ped.set_meta("showroom", true)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= update_interval:
		_timer = 0.0
		update_streaming(false)
	_advance_builds()


## Runs build steps for the chunks in progress, nearest first, until this frame's budget is spent.
## Always at least one step, so a slow machine still gets its city, just in more frames.
func _advance_builds() -> void:
	if _pending.is_empty():
		return
	var start := Time.get_ticks_usec()
	var budget := int(build_budget_ms * 1000.0)
	var keys: Array = _pending.keys()
	var here := _center_block
	keys.sort_custom(func(a, b): return _build_priority(a, _focus_block, here) < _build_priority(b, _focus_block, here))
	for k: Vector2i in keys:
		var chunk: CityChunk = _pending[k]
		while true:
			if chunk.build_step():
				_pending.erase(k)
				_install_chunk(k, chunk)
				break
			if Time.get_ticks_usec() - start >= budget:
				return
		if Time.get_ticks_usec() - start >= budget:
			return


## Drops a chunk that is still being built (it left the window, or it is wanted at another level).
func _cancel_build(k: Vector2i) -> void:
	var chunk: CityChunk = _pending.get(k)
	_pending.erase(k)
	if chunk:
		remove_child(chunk)
		chunk.queue_free()


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
	# A named place beats both the zone and the district: driving the coast highway should read
	# "Santa Monica" and then "Venice", not "Beach" for twenty blocks. It is deliberately checked
	# ahead of the zone, so the sand and the hillside of a named town carry its name too.
	if plan.macro:
		var place := plan.macro.place_name(xz)
		if place != "":
			return place
	if zone != MacroMap.Zone.CITY:
		return MacroMap.zone_name(zone)
	return CityPlan.district_name(plan.district_at(xz))


## Makes sure the chunk under a local position exists at full detail, right now.
func ensure_loaded_at(local_pos: Vector3) -> void:
	if plan == null:
		return
	var wp := world_position(local_pos)
	var k := plan.block_index_at(Vector2(wp.x, wp.z))
	if chunks.has(k) and chunks[k].level == CityChunk.Level.FULL:
		return
	if _pending.has(k) and _pending[k].level == CityChunk.Level.FULL:
		_finish_now(k)
		return
	_replace_chunk(k, CityChunk.Level.FULL)


## Height of solid ground at a local position (terrain, or the sidewalk top in the city).
## Frees the pedestrians farthest from the player until the count is under max_pedestrians
## (Quality lowers the cap at run time).
func trim_pedestrians() -> void:
	var peds := get_tree().get_nodes_in_group("pedestrian")
	var over := peds.size() - max_pedestrians
	if over <= 0 or _player == null:
		return
	var pp := _player.global_position
	peds.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(pp) > b.global_position.distance_squared_to(pp))
	for i in over:
		(peds[i] as Node).queue_free()


## The scene places the player at y 1.5, but the city rolls (relief is 5.5 m at the origin):
## lift the start point onto the ground so nobody spawns under the slab. Aerial `?spawn` heights
## are left alone.
func _settle_player() -> void:
	if _player == null:
		return
	var ground := ground_height_at(_player.global_position)
	if _player.global_position.y < ground + 0.2:
		_player.global_position.y = ground + 0.6
		if _player.has_method("respawn"):
			_player.set("_spawn_transform", _player.global_transform)


## True when a city-zone position is below the rolling ground it should stand on (the player
## got under a ground slab). Beaches, water and hills are judged elsewhere.
func under_city_ground(local_pos: Vector3) -> bool:
	if plan == null:
		return false
	var wp := world_position(local_pos)
	if plan.zone_at(Vector2(wp.x, wp.z)) != MacroMap.Zone.CITY:
		return false
	# City ground sits on the relief alone (CityChunk._gy); height_at() also carries the hill
	# noise, which can be a couple of meters higher inside the city zone.
	var ground := plan.macro.relief_at(Vector2(wp.x, wp.z)) if plan.macro else plan.height_at(Vector2(wp.x, wp.z))
	return local_pos.y < ground - 1.5


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
	# Snapped to the plane's own vertex spacing, in world space, so every vertex stays on the
	# same world point as the player walks. Unsnapped, the lifted mountains crawl and shimmer.
	var gstep := ground_step()
	var off := WorldState.world_offset
	_ground.position = Vector3(
		snappedf(local.x + off.x, gstep) - off.x, 0.0,
		snappedf(local.z + off.z, gstep) - off.z)
	# The macro map is addressed in true world XZ, so the plane has to know how far the scene's
	# origin has been shifted from under it.
	var offset_xz := Vector2(WorldState.world_offset.x, WorldState.world_offset.z)
	if _ground_material:
		_ground_material.set_shader_parameter("world_offset", offset_xz)
	# The far planting follows the plane's actual triangles, so it needs to know where they are.
	for mat in _far_ground_materials:
		mat.set_shader_parameter("world_offset", offset_xz)
		mat.set_shader_parameter("plane_origin", Vector2(_ground.position.x, _ground.position.z))
	var wp := world_position(local)
	var here := plan.block_index_at(Vector2(wp.x, wp.z))
	_center_block = here
	# Stream towards where the player is GOING, not where they are standing. `velocity` is kept
	# in step with the car or the jet while riding one (see Player._physics_process), so this one
	# read covers walking, boosting, driving and flying alike.
	var focus := Vector2(wp.x, wp.z)
	var vel: Variant = _player.get("velocity")
	if vel is Vector3:
		var v: Vector3 = vel
		focus += (Vector2(v.x, v.z) * stream_lookahead).limit_length(stream_lookahead_max)
	var center := plan.block_index_at(focus)
	_focus_block = center

	var wanted := {}
	for dx in range(-lod_radius_blocks, lod_radius_blocks + 1):
		for dz in range(-lod_radius_blocks, lod_radius_blocks + 1):
			var ring := maxi(absi(dx), absi(dz))
			wanted[Vector2i(center.x + dx, center.y + dz)] = CityChunk.Level.FULL if ring <= load_radius_blocks else CityChunk.Level.LOD
	# Whatever the lead asks for, the ground actually under the player is always full detail.
	# Leading the window alone would let a hard turn or a fast stop downgrade the block they are
	# standing on, which is the one block that can never be a box.
	for dx in range(-min_full_radius_blocks, min_full_radius_blocks + 1):
		for dz in range(-min_full_radius_blocks, min_full_radius_blocks + 1):
			wanted[Vector2i(here.x + dx, here.y + dz)] = CityChunk.Level.FULL

	# Free only what has left the keep radius, measured from the player rather than from the led
	# focus so nothing behind them is dropped the instant they face away.
	# A chunk whose LEVEL merely changed is deliberately NOT freed here. It used to be, and its
	# replacement then had to wait its turn behind `max_full_builds_per_update`, so a block that
	# was about to become detailed spent one or more ticks as NOTHING - not a crude version, an
	# absent one. That is the hole in the world you see when moving fast. Upgrades and downgrades
	# now go through _replace_chunk(), which builds first and removes afterwards.
	for k in chunks.keys():
		if maxi(absi(k.x - here.x), absi(k.y - here.y)) > keep_radius_blocks:
			for id in chunks[k].built_landmarks:
				_set_far_landmark_visible(id, true)
			chunks[k].queue_free()
			chunks.erase(k)
	for k in _pending.keys():
		if maxi(absi(k.x - here.x), absi(k.y - here.y)) > keep_radius_blocks:
			_cancel_build(k)

	var todo: Array = []
	for k in wanted:
		if not chunks.has(k) or chunks[k].level != wanted[k]:
			# Already on its way: let it finish, even at the other level - a hard turn would
			# otherwise throw away a half-built block and start it again. When everything is
			# wanted NOW, finish it here, or start over if it is the wrong level.
			if _pending.has(k):
				if not immediate:
					continue
				if _pending[k].level == wanted[k]:
					_finish_now(k)
					continue
				_cancel_build(k)
			todo.append(k)
	todo.sort_custom(func(a, b): return _build_priority(a, center, here) < _build_priority(b, center, here))
	var full_budget := max_full_builds_per_update if not immediate else 1000000
	var lod_budget := max_lod_builds_per_update if not immediate else 1000000
	for k in todo:
		if not immediate and _pending.size() >= max_pending_builds:
			break
		var level: CityChunk.Level = wanted[k]
		if level == CityChunk.Level.FULL:
			if full_budget <= 0:
				continue
			full_budget -= 1
		else:
			if lod_budget <= 0:
				continue
			lod_budget -= 1
		if immediate:
			_replace_chunk(k, level)
		else:
			_start_build(k, level)
	_update_skyline(here, immediate)


## Keeps the coarse far city around the player: build the nearest missing tiles, drop the ones
## that have fallen out of range. Cheap enough to run every update - a tile that holds no city
## (ocean, hills, empty basin) is remembered as empty and never rescanned.
func _update_skyline(here: Vector2i, immediate: bool) -> void:
	if _skyline == null:
		return
	var t := Vector2i(floori(float(here.x) / float(Skyline.TILE_BLOCKS)), floori(float(here.y) / float(Skyline.TILE_BLOCKS)))
	_skyline.trim(t, skyline_tiles + 1)
	var budget := max_skyline_builds_per_update if not immediate else 1000000
	# Nearest ring first, so the gap the player is looking at closes before the far corners.
	for ring in range(0, skyline_tiles + 1):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var k := Vector2i(t.x + dx, t.y + dz)
				if _skyline.has_tile(k):
					continue
				_skyline.build_tile(k)
				budget -= 1
				if budget <= 0:
					return


## Puts the loading screen up and lets it drive the warm-up. Deferred so the rest of _ready()
## finishes first - it needs the player, the camera and the plan to exist before it can build
## anything or draw a shader in front of anything.
func _start_loading_screen() -> void:
	if not show_loading_screen or OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	# The screenshot harnesses (tools/glshot/*, tools/webshot) drive the game with `--nohud` and
	# grab a frame after a fixed number of frames. With the loading screen up they photograph
	# the loading screen - a flat 14/15/19 rectangle - which is exactly what happened the first
	# time this shipped, and screenshots are the only way anyone on this project can see the
	# game at all. `--noload` skips it explicitly; `--nohud` implies it.
	for arg in OS.get_cmdline_user_args():
		if arg == "--noload" or arg == "--nohud":
			return
	var screen := LoadingScreen.new()
	screen.name = "LoadingScreen"
	add_child(screen)
	screen.call_deferred("run", self)


func _build_skyline() -> void:
	_skyline = Skyline.new()
	_skyline.name = "Skyline"
	# Where the LOD chunks stop is where this starts. Derived from the ring count rather than
	# hard-coded so the two can never drift apart when the radius is tuned.
	var reach := float(lod_radius_blocks) * plan.block_size_range.y
	_skyline.setup(plan, reach, reach * 0.18, _canopy_material)
	add_child(_skyline)


## How soon a chunk gets built: by whichever it sits closer to, the led focus or the player.
## Sorting by the focus alone starves the blocks beside the player the moment they turn hard,
## because everything between them and the lead sorts ahead of it.
func _build_priority(k: Vector2i, center: Vector2i, here: Vector2i) -> int:
	return mini((k - center).length_squared(), (k - here).length_squared())


## Builds a chunk and only then takes down whatever was standing in its place. The two never
## coexist for a frame and the block is never empty for one either: the old chunk is still being
## drawn while the new one is generated, and leaves the tree in the same frame the new one
## enters it. This is the whole reason a level change no longer shows as a hole.
func _replace_chunk(k: Vector2i, level: CityChunk.Level) -> void:
	if _pending.has(k):
		_cancel_build(k)
	var chunk := _new_chunk(k, level)
	chunk.build()
	_install_chunk(k, chunk)


## Starts building a chunk over the next few frames (see _advance_builds). It stays hidden, and
## whatever stands in its place stays up, until it is complete.
func _start_build(k: Vector2i, level: CityChunk.Level) -> void:
	if _pending.has(k):
		_cancel_build(k)
	var chunk := _new_chunk(k, level)
	chunk.visible = false
	chunk.begin_build()
	_pending[k] = chunk


## Completes a chunk that is being built over several frames, right now.
func _finish_now(k: Vector2i) -> void:
	var chunk: CityChunk = _pending.get(k)
	if chunk == null:
		return
	_pending.erase(k)
	while not chunk.build_step():
		pass
	_install_chunk(k, chunk)


## Puts a finished chunk in the window and takes down whatever stood in its place.
func _install_chunk(k: Vector2i, chunk: CityChunk) -> void:
	var old_chunk: CityChunk = chunks.get(k)
	chunk.reveal()
	chunks[k] = chunk
	for id in chunk.built_landmarks:
		_set_far_landmark_visible(id, false)
	if old_chunk == null or old_chunk == chunk:
		return
	# Landmarks the old chunk owned and the new one does not have to go back to being far
	# versions; the ones both build stay hidden, because the loop above has just hidden them.
	for id in old_chunk.built_landmarks:
		if not chunk.built_landmarks.has(id):
			_set_far_landmark_visible(id, true)
	# Coming INTO detail is the swap the player is looking at, so dissolve the boxes over the
	# new buildings instead of cutting. Going the other way happens behind them, at the far edge
	# of the window, where a cut costs nothing and a second set of boxes would cost draws.
	if lod_fade_time > 0.0 and old_chunk.level == CityChunk.Level.LOD and chunk.level == CityChunk.Level.FULL:
		old_chunk.begin_fade_out(lod_fade_time)
		return
	remove_child(old_chunk)
	old_chunk.queue_free()


func _new_chunk(k: Vector2i, level: CityChunk.Level) -> CityChunk:
	var chunk := CityChunk.new()
	chunk.plan = plan
	chunk.ix = k.x
	chunk.iz = k.y
	chunk.level = level
	chunk.center_block = _center_block
	chunk.style = {
		"asphalt": asphalt_color, "sidewalk": sidewalk_color, "grass": grass_color, "plaza": plaza_color,
		"path": path_color, "water": water_color, "ocean": ocean_color, "sand": sand_color,
		"hill_grass": hill_grass_color, "hill_rock": hill_rock_color,
		"tarmac": tarmac_color, "runway": runway_color, "concrete": concrete_color,
		"lamp_spacing": lamp_spacing, "tree_spacing": tree_spacing, "trash_cans_per_block": trash_cans_per_block,
		"cars_per_block": cars_per_block, "pedestrians_per_block": pedestrians_per_block, "max_pedestrians": max_pedestrians, "airport_crowd": airport_crowd,
		"grass_per_park": grass_per_park,
	}
	add_child(chunk)
	return chunk


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


## The material the ground follower wears: the baked macro map of the whole basin, plus the
## close-up grass texture for the ground right under the player. See shaders/macro_ground.gdshader.
## A lens vignette over the whole frame, on its own CanvasLayer below the HUD so it survives
## F1 and shows up in screenshots. Subtle on purpose: see shaders/vignette.gdshader.
func _build_vignette() -> void:
	if vignette_strength <= 0.001:
		return
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	layer.layer = -1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vignette.gdshader")
	mat.set_shader_parameter("strength", vignette_strength)
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)


func _build_ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/macro_ground.gdshader")
	var size := 160 if OS.has_feature("web") else 256
	var img := plan.macro.bake(Vector2.ZERO, macro_span, size)
	var tex := ImageTexture.create_from_image(img)
	_canopy_material = ShaderMaterial.new()
	_canopy_material.shader = load("res://shaders/far_canopy.gdshader")
	for m in [mat, _canopy_material]:
		m.set_shader_parameter("macro_tex", tex)
		m.set_shader_parameter("macro_centre", Vector2.ZERO)
		m.set_shader_parameter("macro_span", macro_span)
		m.set_shader_parameter("macro_height", MacroMap.BAKE_HEIGHT_SCALE)
	_canopy_material.set_shader_parameter("plane_half", ground_size * 0.5)
	_canopy_material.set_shader_parameter("plane_step", ground_step())
	_far_ground_materials = [_canopy_material]
	mat.set_shader_parameter("near_albedo", PropFactory.texture("grass", "Color"))
	mat.set_shader_parameter("near_normal", PropFactory.texture("grass", "NormalGL"))
	return mat


## Metres between the ground follower's vertices. PlaneMesh puts N subdivisions as N + 1 quads,
## so this is ground_size / 201, not / 200: snapping by the latter slid every vertex 35 cm per
## step against the world, which is the very swim the snap is there to stop.
func ground_step() -> float:
	return ground_size / float(GROUND_SUBDIVISIONS + 1)


## DayNight keeps the horizon haze in step with the sky it is handing over to.
func set_ground_haze(color: Color, sun_direction: Vector3) -> void:
	if _ground_material:
		_ground_material.set_shader_parameter("haze_color", color)
		_ground_material.set_shader_parameter("sun_dir", sun_direction)


func _build_ground() -> void:
	_ground = StaticBody3D.new()
	_ground.name = "Ground"
	_ground.collision_layer = 1
	_ground.collision_mask = 0 # static never detects; a mask here only makes useless pairs (CLAUDE.md)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)
	mesh.mesh = plane
	_ground_material = _build_ground_material()
	mesh.material_override = _ground_material
	# One flat quad 14 km across would z-fight and shade badly at this size; a few subdivisions
	# cost nothing and keep the interpolated world position honest.
	# Enough vertices to carry a mountain silhouette: 14 km over 200 quads is 70 m a vertex,
	# which is plenty for a range three kilometres out.
	plane.subdivide_width = GROUND_SUBDIVISIONS
	plane.subdivide_depth = GROUND_SUBDIVISIONS
	mesh.extra_cull_margin = ground_size
	# It never casts. It is a 14 km plane under everything, so the only thing it could shadow is
	# itself - but at 200 x 200 quads it is 80,000 triangles, and it was being drawn into all
	# four shadow cascades every frame for nothing. It still RECEIVES, which is what matters.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Thick, so nothing that gets pushed into it by an overlapping shape can pop out underneath.
	box.size = Vector3(ground_size, 40.0, ground_size)
	shape.shape = box
	shape.position = Vector3(0.0, -20.0, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
