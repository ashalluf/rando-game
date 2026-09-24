extends Node
## Headless smoke test, run as a scene so every autoload exists before it compiles.
## Loads the test room and the city, drives the player with simulated input and checks
## movement, weapons, buildings, streaming, NPCs, cars and polish. Exit code 0 = pass.
## Run:  godot --headless --path . res://tests/smoke_test.tscn

const LEVEL_PATH := "res://scenes/levels/test_box.tscn"

var _failures: PackedStringArray = []
var _checks := 0


func _ready() -> void:
	# Watchdog: a broken test must never hang the check.
	get_tree().create_timer(300.0).timeout.connect(func():
		printerr("SMOKE TEST TIMED OUT")
		get_tree().quit(2))
	# Deferred: the root is still busy adding this scene during _ready().
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(LEVEL_PATH)
	_check(packed != null, "level scene loads")
	if packed == null:
		_finish()
		return
	var level := packed.instantiate()
	get_tree().root.add_child(level)
	_check(get_tree().root.get_node_or_null("PhysicsBudget") != null, "PhysicsBudget autoload present")

	await _ticks(30)
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	_check(player != null, "player found in group 'player'")
	if player == null:
		_finish()
		return
	_check(player.is_on_floor(), "player stands on the ground after settling")
	var props := get_tree().get_nodes_in_group("physics_prop").size()
	_check(props >= 50, "crates spawned (%d)" % props)

	# Walk forward for one second.
	var start := player.global_position
	Input.action_press("move_forward")
	var walk_speed := await _run_and_measure_speed(player, 60)
	Input.action_release("move_forward")
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check(moved > 6.0, "moving forward covers ground (%.1f m in 1 s)" % moved)
	_check(player.global_position.z < start.z, "forward is -Z relative to the camera")
	_check(absf(walk_speed - player.walk_speed) < 1.0, "walk speed reaches %.1f (target %.1f)" % [walk_speed, player.walk_speed])
	await _ticks(30)

	# Boost is much faster than running (run back the other way so nothing is in the path).
	Input.action_press("move_back")
	Input.action_press("boost")
	var boost_speed := await _run_and_measure_speed(player, 90)
	Input.action_release("boost")
	Input.action_release("move_back")
	_check(boost_speed > player.walk_speed + 15.0 and boost_speed <= player.boost_max_speed + 0.5,
		"boost speed reaches %.1f (cap %.1f)" % [boost_speed, player.boost_max_speed])
	await _ticks(90)

	# Full jump, holding the button through the apex.
	var ground_y := player.global_position.y
	var peak := await _jump_and_measure(player, ground_y)
	_check(peak > player.jump_height * 0.75 and peak < player.jump_height * 1.25,
		"ground jump peaks at %.1f m (target %.1f)" % [peak, player.jump_height])
	await _wait_for_floor(player, 400)
	_check(player.is_on_floor(), "player lands after the jump")
	_check(absf(player.last_jump_peak - peak) < 0.5, "HUD jump peak %.1f matches measured %.1f" % [player.last_jump_peak, peak])

	# Double jump goes higher than a single jump.
	var peak2 := await _double_jump_and_measure(player, player.global_position.y)
	_check(peak2 > peak + player.double_jump_height * 0.5,
		"double jump peaks at %.1f m (single %.1f)" % [peak2, peak])
	await _wait_for_floor(player, 400)

	# Respawn returns to the start.
	Input.action_press("respawn")
	await _ticks(2)
	Input.action_release("respawn")
	_check(player.global_position.distance_to(Vector3(0, 1, 0)) < 2.0, "respawn returns to spawn")

	await _test_weapons(player)
	_test_buildings()
	level.free() # Free now, so the city scene cannot pick up this level's player.
	await get_tree().process_frame
	await _test_city()
	_finish()


func _test_city() -> void:
	var packed: PackedScene = load("res://scenes/levels/city.tscn")
	_check(packed != null, "city scene loads")
	if packed == null:
		return
	# Untyped on purpose: naming CityStreamer here would compile it before the autoloads exist.
	var city: Node3D = packed.instantiate()
	get_tree().root.add_child(city)
	await _ticks(30)
	var plan: CityPlan = city.plan
	var lod_r: int = city.lod_radius_blocks
	var load_r: int = city.load_radius_blocks
	var counts: Vector2i = city.chunk_counts()
	_check(counts.x == (2 * load_r + 1) * (2 * load_r + 1), "%d full-detail chunks around the player" % counts.x)
	_check(counts.y == (2 * lod_r + 1) * (2 * lod_r + 1) - counts.x, "%d far LOD chunks" % counts.y)
	_check(city.building_count() >= 100, "city has buildings (%d)" % city.building_count())
	# The facade kit goes on the buildings of the full-detail chunks. Counted from the batches'
	# instance counts, which are real under --headless (the transforms are not: they read back
	# as identity there, see CLAUDE.md).
	var kit_buildings := 0
	var kit_pieces := 0
	var kit_kinds := {}
	for k in city.chunks:
		for child in (city.chunks[k] as Node).get_children():
			if child is Building:
				var n := _kit_count(child, "Batch_kit_")
				if n > 0:
					kit_buildings += 1
				kit_pieces += n
				for grand in (child as Node).get_children():
					if grand is MultiMeshInstance3D and str(grand.name).begins_with("Batch_kit_"):
						kit_kinds[str(grand.name).trim_prefix("Batch_kit_").get_slice("_", 0)] = true
	_check(kit_buildings >= 20 and kit_pieces >= 1000 and kit_kinds.size() >= 4,
		"full-detail chunks carry the facade kit (%d buildings, %d pieces, kinds %s)" % [kit_buildings, kit_pieces, ",".join(kit_kinds.keys())])
	var districts := {}
	var kinds := {}
	var inter_kinds := {}
	for k in city.chunks:
		var block := plan.block(k.x, k.y)
		districts[block.district] = true
		kinds[block.kind] = true
		inter_kinds[plan.intersection(k.x + 1, k.y + 1).kind] = true
	_check(districts.size() >= 3, "loaded area spans %d districts" % districts.size())
	_check(kinds.size() >= 2, "parks or plazas as well as buildings (%d kinds)" % kinds.size())
	_check(inter_kinds.size() >= 2, "%d intersection types" % inter_kinds.size())
	_check(plan.district_at(Vector2.ZERO) == CityPlan.District.MIDTOWN, "spawn is in midtown")
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	_check(player != null and player.is_on_floor(), "player stands at the center intersection")
	var start_ground: float = city.ground_height_at(player.global_position)
	_check(player.global_position.y > start_ground - 0.6, "player starts on top of the rolling ground (y %.1f, ground %.1f)" % [player.global_position.y, start_ground])
	_check(not city.under_city_ground(player.global_position) and city.under_city_ground(player.global_position - Vector3(0.0, 4.0, 0.0)), "under-ground detection works at the spawn")
	var cans := 0
	for node in get_tree().get_nodes_in_group("physics_prop"):
		if node is TrashCan:
			cans += 1
	_check(cans > 0, "trash cans are physics props (%d)" % cans)

	# Breaking a lamp: it disappears, drops debris, and is remembered.
	var home_key: Vector2i = plan.block_index_at(Vector2.ZERO)
	var home_chunk: Node3D = city.chunks[home_key]
	var lamp: Dictionary = {}
	for record in home_chunk.prop_records:
		if record.kind == "lamp":
			lamp = record
			break
	_check(not lamp.is_empty(), "home chunk has a lamp to break")
	var lamp_id: String = lamp.get("id", "")
	if not lamp.is_empty():
		home_chunk.damage_prop(lamp, 999.0, Vector3.UP)
		await _ticks(2)
		_check(lamp.dead and _world_state().is_destroyed(home_chunk.key, lamp_id), "lamp breaks and is recorded as destroyed")
		_check(get_tree().get_nodes_in_group("debris").size() >= 3, "broken lamp drops debris")

	# Walk far away: chunks stream, the old home chunk becomes LOD or unloads.
	var far := Vector3(700.0, 2.0, 0.0)
	player.global_position = far
	player.velocity = Vector3.ZERO
	city.update_streaming(true)
	var far_key: Vector2i = plan.block_index_at(Vector2(far.x, far.z))
	_check(city.chunks.has(far_key) and city.chunks[far_key].level == 0, "chunk under the player is full detail after moving 700 m")
	_check(not city.chunks.has(home_key) or city.chunks[home_key].level == 1, "home chunk is no longer full detail")

	# Origin re-centering: the world shifts so the player is back near zero.
	player.global_position = Vector3(1200.0, 2.0, 0.0)
	city.recenter()
	_check(_world_state().world_offset.x > 1100.0 and player.global_position.length() < 5.0, "world re-centered (offset %.0f m)" % _world_state().world_offset.x)
	_check(city.district_name_at(player.global_position) != "Downtown", "district lookup uses world coordinates after re-centering")
	city.update_streaming(true)
	var here: Vector2i = plan.block_index_at(Vector2(_world_state().world_offset.x, 0.0))
	_check(city.chunks.has(here) and city.chunks[here].level == 0, "chunks stream correctly after re-centering")
	_check(city.chunks[here].position.is_equal_approx(-_world_state().world_offset), "chunk nodes sit at minus the world offset")

	# Come home: the lamp is still gone.
	player.global_position = _world_state().to_local(Vector3(0.0, 2.0, 0.0))
	city.update_streaming(true)
	var home_again: Node3D = city.chunks.get(home_key)
	_check(home_again != null and home_again.level == 0, "home chunk rebuilt at full detail")
	if home_again and not lamp_id.is_empty():
		_check(not home_again.has_prop(lamp_id), "destroyed lamp stays destroyed after the chunk is rebuilt")

	# The big-picture map: ocean west, beach at the coast, hills north, flat city at the origin.
	var macro: MacroMap = plan.macro
	_check(macro != null, "city uses the macro map")
	if macro:
		_check(macro.zone_at(Vector2.ZERO) == MacroMap.Zone.CITY and macro.raw_height_at(Vector2.ZERO) == 0.0, "origin is city, not mountain")
		_check(macro.relief_at(Vector2.ZERO) >= 0.0 and macro.relief_at(Vector2.ZERO) <= macro.relief_height and macro.height_at(Vector2.ZERO) == macro.relief_at(Vector2.ZERO), "city relief is bounded and part of height_at")
		var relief_max := 0.0
		for x in range(-600, 1100, 100):
			for z in range(-800, 900, 100):
				var p := Vector2(x, z)
				if macro.zone_at(p) == MacroMap.Zone.CITY:
					relief_max = maxf(relief_max, macro.relief_at(p))
		_check(relief_max > 4.0, "the city actually rolls (max relief %.1f m)" % relief_max)
		var malls := 0
		var bigboxes := 0
		var mall_block: Dictionary = {}
		for bx in range(-12, 13):
			for bz in range(-12, 13):
				var b := plan.block(bx, bz)
				if b.kind == CityPlan.BlockKind.MALL:
					malls += 1
					if mall_block.is_empty() and plan.zone_at((b.rect as Rect2).get_center()) == MacroMap.Zone.CITY:
						mall_block = b
				elif b.kind == CityPlan.BlockKind.BIGBOX:
					bigboxes += 1
		_check(malls > 0 and bigboxes > 0, "the plan has shopping plazas (%d) and big-box stores (%d)" % [malls, bigboxes])
		if not mall_block.is_empty():
			var mc: Vector2 = (mall_block.rect as Rect2).get_center()
			player.global_position = _world_state().to_local(Vector3(mc.x, 3.0, mc.y))
			player.velocity = Vector3.ZERO
			city.update_streaming(true)
			await _ticks(5)
			var mall_chunk = city.chunks.get(Vector2i(mall_block.ix, mall_block.iz))
			_check(mall_chunk != null and mall_chunk.level == 0 and mall_chunk.prop_records.size() > 0, "a shopping plaza chunk builds with its signs and props")
		_check(macro.relief_at(macro.airport_rect.get_center()) == 0.0 and macro.relief_at(Landmarks.all()[3].anchor) == 0.0, "airport and landmarks stay flat")
		_check(macro.zone_at(Vector2(-2500.0, 0.0)) == MacroMap.Zone.OCEAN, "far west is ocean")
		# built_amount() in macro_ground.gdshader tells city from open country by the baked
		# colour alone - low saturation AND low luminance, in linear light. Both halves of that
		# window live in two files, so brightening a district past it silently stops the city
		# being drawn on the horizon plane. Re-run the classifier here on every palette entry.
		# The luminance window is read out of the shader rather than written here a second time:
		# this guard exists precisely because that number and the palette have to move together.
		var built_src: String = (load("res://shaders/macro_ground.gdshader") as Shader).code
		var built_win := PackedFloat32Array([0.100, 0.130])
		var built_re := RegEx.new()
		built_re.compile("smoothstep\\(([0-9.]+), *([0-9.]+), *lum\\)")
		var built_m := built_re.search(built_src)
		if built_m:
			built_win = PackedFloat32Array([built_m.get_string(1).to_float(), built_m.get_string(2).to_float()])
		var built_ok := built_m != null
		var built_why := "" if built_m else " window not found in macro_ground.gdshader"
		for entry in [["downtown", MacroMap.BAKE_DOWNTOWN, true], ["midtown", MacroMap.BAKE_MIDTOWN, true],
				["industrial", MacroMap.BAKE_INDUSTRIAL, true], ["suburb", MacroMap.BAKE_SUBURB, true],
				["campus", MacroMap.BAKE_CAMPUS, true], ["freeway", MacroMap.BAKE_FREEWAY, true],
				["concrete", MacroMap.BAKE_CONCRETE, false], ["port", MacroMap.BAKE_PORT, false],
				["rock", MacroMap.BAKE_ROCK, false], ["scrub", MacroMap.BAKE_SCRUB, false],
				["grass", MacroMap.BAKE_GRASS, false], ["snow", MacroMap.BAKE_SNOW, false],
				["sand", MacroMap.BAKE_SAND, false]]:
			var c: Color = (entry[1] as Color).srgb_to_linear()
			var mx: float = maxf(c.r, maxf(c.g, c.b))
			var mn: float = minf(c.r, minf(c.g, c.b))
			var sat: float = (mx - mn) / maxf(mx, 0.0008)
			var lum: float = (c.r + c.g + c.b) / 3.0
			var built: float = (1.0 - smoothstep(0.17, 0.30, sat)) * (1.0 - smoothstep(built_win[0], built_win[1], lum))
			var want: bool = entry[2]
			if (built > 0.5) != want:
				built_ok = false
				built_why += " %s=%.2f" % [entry[0], built]
		_check(built_ok, "the baked palette still separates city from country%s" % built_why)
		# Ground albedo. Every ground tint in the project multiplies a PHOTOGRAPHED texture whose
		# own mean already IS the real reflectance of that material, and both `uniform vec3 tint
		# : source_color` and StandardMaterial3D.albedo_color are sRGB-decoded by Godot - so
		# Color(0.40) multiplies by 0.133, not by 0.40. Written as if it were linear, the whole
		# city laid its roads at 0.0065..0.017 and its pavements at 0.05..0.08: five to fifteen
		# times darker than anything real, which is what made the basin a dark sheet from the
		# air. These means are measured off the committed texture files with
		#   python3 -c "from PIL import Image; import numpy as np; im=np.asarray(Image.open('assets/textures/Asphalt033/Asphalt033_1K-JPG_Color.jpg').convert('RGB')).astype(float)/255; l=np.where(im<=0.04045, im/12.92, ((im+0.055)/1.055)**2.4); print((0.2126*l[:,:,0]+0.7152*l[:,:,1]+0.0722*l[:,:,2]).mean())"
		# and they only change if the asset changes.
		var tex_mean := {"asphalt": 0.0849, "asphalt_aerial": 0.1300, "sidewalk": 0.1024,
				"pavers": 0.1939, "paving": 0.2951, "concrete": 0.4818}
		var albedo_of := func(set_key: String, tint: Color) -> float:
			var lum := 0.2126 * tint.r + 0.7152 * tint.g + 0.0722 * tint.b
			var linear: float = lum / 12.92 if lum <= 0.04045 else pow((lum + 0.055) / 1.055, 2.4)
			return float(tex_mean.get(set_key, 0.2)) * linear
		var albedo_why := ""
		for tint: Color in CityChunk.ROAD_TINTS:
			# Asphalt is 0.05-0.12 in daylight; the coarser aerial set lands higher for the same
			# tint, which is a newly surfaced street, so the window has to hold both.
			var a: float = albedo_of.call("asphalt", tint)
			var b: float = albedo_of.call("asphalt_aerial", tint)
			if a < 0.030 or b > 0.140:
				albedo_why += " road(%.3f,%.3f)" % [a, b]
		for d in CityPlan.District.size():
			for row in (CityPlan.DISTRICTS[d] as Dictionary).get("paving", []):
				var a: float = albedo_of.call(str(row[0]), row[2] as Color)
				# Concrete pavement is 0.20-0.40. Anything under 0.15 is darker than the road
				# beside it, which is the tell that a tint was written as if it were linear.
				if a < 0.15 or a > 0.45:
					albedo_why += " %s.%s(%.3f)" % [CityPlan.district_name(d), str(row[0]), a]
		_check(albedo_why == "", "ground surfaces have a physical albedo%s" % albedo_why)
		# The airport drop-off: the lane paths the traffic manager drives, the kerb the crowd
		# stands on and the road Landmarks builds under them were three independent sets of
		# coordinates. They are one set now (MacroMap.terminal_road / terminal_curb /
		# terminal_loops), but nothing in code forces the lanes to lie ON the road - so check it,
		# because a drop-off lane off the edge of its own asphalt is cars driving on tarmac and
		# nothing errors.
		var lane_why := ""
		for loop: PackedVector2Array in macro.terminal_loops:
			for pt in loop:
				if not macro.terminal_road.grow(1.0).has_point(pt):
					lane_why += " (%.0f,%.0f)" % [pt.x, pt.y]
		if not macro.terminal_road.grow(1.0).encloses(macro.terminal_curb.grow(-4.0)) \
				and not macro.terminal_road.intersects(macro.terminal_curb):
			lane_why += " kerb off the road"
		_check(lane_why == "", "the airport drop-off lanes lie on the drop-off road%s" % lane_why)
		# Height and zone have to agree on where the water starts. They did not around the
		# headland - the coast bulge is a function of z alone and the peninsula is a circle - so
		# the waterline cut across a 100 m cliff and left a sail of hillside hanging over the
		# sea off the Redondo pier. Probe the whole coast, and the bay, for land in the water.
		var offshore_max := 0.0
		var offshore_at := Vector2.ZERO
		for zi in range(-30, 40):
			var pz := float(zi) * 90.0
			for xi in range(1, 9):
				var pp := Vector2(macro.coast_x(pz) - float(xi) * 25.0, pz)
				var ph: float = macro.raw_height_at(pp)
				if ph > offshore_max:
					offshore_max = ph
					offshore_at = pp
		for zi in range(0, 20):
			for xi in range(0, 14):
				var pp := Vector2(-1200.0 + float(xi) * 110.0, macro.bay_z + 60.0 + float(zi) * 90.0)
				if not macro.in_bay(pp):
					continue
				var ph: float = macro.raw_height_at(pp)
				if ph > offshore_max:
					offshore_max = ph
					offshore_at = pp
		_check(offshore_max < 4.0, "no land stands out of the water (%.1f m at %.0f,%.0f)" % [offshore_max, offshore_at.x, offshore_at.y])
		_check(macro.zone_at(Vector2(macro.coast_x(0.0) + 30.0, 0.0)) == MacroMap.Zone.BEACH, "just inland of the coast is beach")
		_check(macro.zone_at(Vector2(0.0, -1600.0)) == MacroMap.Zone.HILLS and macro.height_at(Vector2(0.0, -1600.0)) > 80.0, "far north is hills (%.0f m)" % macro.height_at(Vector2(0.0, -1600.0)))
		_check(macro.district_at(macro.downtown_center) == CityPlan.District.DOWNTOWN, "downtown is where the map says")
		# Stand on the beach: sand, palms, no buildings.
		var beach := Vector3(macro.coast_x(0.0) + 30.0, 2.0, 0.0)
		player.global_position = _world_state().to_local(beach)
		city.update_streaming(true)
		var beach_key: Vector2i = plan.block_index_at(Vector2(beach.x, beach.z))
		var beach_chunk: Node3D = city.chunks.get(beach_key)
		var beach_palms := false
		if beach_chunk:
			for child in beach_chunk.get_children():
				if child.name.begins_with("Batch_palm_"):
					beach_palms = true
		_check(beach_chunk != null and beach_chunk.zone == MacroMap.Zone.BEACH and beach_chunk.building_count == 0 and beach_palms, "beach chunk has palms and no buildings")
		# Stand in the hills: terrain tile with collision under the player.
		var hill := Vector3(0.0, 0.0, -1400.0)
		hill.y = macro.height_at(Vector2(hill.x, hill.z)) + 3.0
		player.global_position = _world_state().to_local(hill)
		player.velocity = Vector3.ZERO
		city.update_streaming(true)
		var hill_key: Vector2i = plan.block_index_at(Vector2(hill.x, hill.z))
		var hill_chunk: Node3D = city.chunks.get(hill_key)
		_check(hill_chunk != null and hill_chunk.zone == MacroMap.Zone.HILLS and hill_chunk.has_node("Terrain"), "hill chunk has a terrain tile")
		await _wait_for_floor(player, 240)
		var ground_h: float = _world_state().to_world(player.global_position).y
		_check(player.is_on_floor() and ground_h > 20.0, "player stands on the hills at %.0f m" % ground_h)
		# Hill roads: a boulevard plus canyon roads and estate loops, carved flat into the terrain.
		var hr = macro.hill_roads
		_check(hr != null and hr.roads.size() >= 12 and hr.mansions.size() >= 20, "hill roads and mansions planned (%d roads, %d lots)" % [hr.roads.size() if hr else 0, hr.mansions.size() if hr else 0])
		if hr:
			var road0: Dictionary = hr.roads[0]
			var rp: Vector2 = road0.points[6]
			var rh: float = road0.heights[6]
			_check(absf(plan.height_at(rp) - rh) < 0.05, "terrain is carved to the road bed (%.1f vs %.1f m)" % [plan.height_at(rp), rh])
			var road_spot := Vector3(rp.x, rh + 2.0, rp.y)
			player.global_position = _world_state().to_local(road_spot)
			player.velocity = Vector3.ZERO
			city.update_streaming(true)
			var road_chunk: Node3D = city.chunks.get(plan.block_index_at(rp))
			_check(road_chunk != null and road_chunk.has_node("HillRoad"), "the chunk under Sunset Drive has an asphalt strip")
			await _wait_for_floor(player, 240)
			_check(player.is_on_floor() and absf(_world_state().to_world(player.global_position).y - rh) < 1.0, "player stands on the hill road (y %.1f, road %.1f)" % [_world_state().to_world(player.global_position).y, rh])
			player.global_position = _world_state().to_local(hill)
			player.velocity = Vector3.ZERO
			city.update_streaming(true)
			await _ticks(5)
		# Far (LOD) hill chunks keep terrain collision so a fast car cannot drop through them.
		var lod_hill_with_collision := false
		for chunk in city.chunks.values():
			if chunk.zone == MacroMap.Zone.HILLS and chunk.level != chunk.Level.FULL and chunk.has_node("TerrainBody"):
				lod_hill_with_collision = true
				break
		_check(lod_hill_with_collision, "far hill chunks have terrain collision")
		# Ending up under a hill (any height) lifts you back onto the surface.
		var under: Vector3 = _world_state().to_local(Vector3(hill.x, 0.5, hill.z))
		player.global_position = under
		player.velocity = Vector3.ZERO
		await _ticks(30)
		var lifted_y: float = _world_state().to_world(player.global_position).y
		_check(lifted_y > macro.height_at(Vector2(hill.x, hill.z)) - 3.0, "player under a hill is lifted onto it (y %.0f)" % lifted_y)

	# The basin is ringed by mountains, and the inland valley is a city floor at altitude.
	if macro:
		var front_h: float = macro.raw_height_at(Vector2(200.0, macro.hills_full_z))
		var back_h: float = macro.raw_height_at(Vector2(200.0, macro.back_full_z))
		var east_h: float = macro.raw_height_at(Vector2(macro.east_full_x, 300.0))
		_check(front_h > 200.0 and back_h > front_h and east_h > 200.0,
			"the basin is ringed by mountains (front %.0f, back %.0f, east %.0f m)" % [front_h, back_h, east_h])
		# The valley floor is past valley_to_z: the window between it and valley_from_z is the
		# front range's own flank, and sampling there reads the mountain, not the valley.
		var valley := Vector2(300.0, macro.valley_to_z - 400.0)
		var valley_h: float = macro.height_at(valley)
		_check(macro.zone_at(valley) == MacroMap.Zone.CITY and valley_h > 80.0 and macro.raw_height_at(valley) == 0.0,
			"the inland valley is city built on a plateau at %.0f m" % valley_h)
		# The pass: a canyon through the front range, so the valley is reachable on the ground.
		var pass_z: float = (macro.hills_full_z + macro.valley_from_z) * 0.5
		var in_pass: float = macro.raw_height_at(Vector2(macro.pass_center_x, pass_z))
		var on_flank: float = macro.raw_height_at(Vector2(macro.pass_center_x + 1100.0, pass_z))
		_check(in_pass < 120.0 and on_flank > in_pass * 3.0,
			"a pass is cut through the front range (%.0f m in it, %.0f m beside it)" % [in_pass, on_flank])
		_check(macro.plateau_at(Vector2.ZERO) == 0.0 and macro.plateau_at(macro.airport_rect.get_center()) == 0.0,
			"the basin floor and the airport stay at sea level")

	# The freeway: long curved routes on an elevated deck, with ramps down to the streets.
	if macro:
		var fw = macro.freeway
		_check(fw != null and fw.routes.size() >= 3 and fw.ramps.size() >= 6,
			"freeway routes and ramps planned (%d routes, %d ramps)" % [fw.routes.size() if fw else 0, fw.ramps.size() if fw else 0])
		if fw:
			# Every route curves: a straight line would have a constant heading.
			var bends := 0
			for route: Dictionary in fw.routes:
				var pts: PackedVector2Array = route.points
				var h0: float = (pts[1] - pts[0]).angle()
				var h1: float = (pts[pts.size() - 1] - pts[pts.size() - 2]).angle()
				if absf(angle_difference(h0, h1)) > 0.12:
					bends += 1
			_check(bends == fw.routes.size(), "every freeway route curves (%d of %d)" % [bends, fw.routes.size()])
			# The deck rides above the ground, on a drivable grade.
			var route0: Dictionary = fw.routes[0]
			var pts0: PackedVector2Array = route0.points
			var hs0: PackedFloat32Array = route0.heights
			var clear := true
			var steep := false
			for i in pts0.size():
				if hs0[i] - macro.height_at(pts0[i]) < 2.5:
					clear = false
				if i > 0 and absf(hs0[i] - hs0[i - 1]) > Freeway.MAX_GRADE * pts0[i].distance_to(pts0[i - 1]) + 0.01:
					steep = true
			_check(clear and not steep, "the deck clears the ground the whole way at a drivable grade")
			# Stand under the deck: the chunk builds it, and nothing is built in its corridor.
			var deck_i := int(pts0.size() * 0.5)
			var deck_xz: Vector2 = pts0[deck_i]
			var deck_spot := Vector3(deck_xz.x, macro.height_at(deck_xz) + 2.0, deck_xz.y)
			player.global_position = _world_state().to_local(deck_spot)
			player.velocity = Vector3.ZERO
			city.update_streaming(true)
			await _ticks(5)
			var deck_chunk: Node3D = city.chunks.get(plan.block_index_at(deck_xz))
			var deck_built := false
			for chunk in city.chunks.values():
				if chunk.has_node("FreewayDeck") and chunk.has_node("FreewayBody"):
					deck_built = true
					break
			_check(deck_built, "a chunk under the freeway builds the deck and its collision")
			# The corridor has to exist and be narrow: a grid over the basin should be mostly clear.
			var blocked := 0
			var sampled := 0
			for gx in range(-12, 13):
				for gz in range(-12, 13):
					sampled += 1
					if fw.blocks(Vector2(gx * 130.0, gz * 130.0), 0.0):
						blocked += 1
			_check(fw.blocks(deck_xz, 0.0) and blocked > 0 and blocked * 6 < sampled,
				"the freeway corridor is narrow (%d of %d samples under a deck)" % [blocked, sampled])
			if deck_chunk:
				var under_count := 0
				for child in deck_chunk.get_children():
					if child is Building and fw.blocks(Vector2(_world_state().to_world(child.global_position).x, _world_state().to_world(child.global_position).z), 0.0):
						under_count += 1
				_check(under_count == 0, "no buildings stand under the deck")
			# Traffic on the deck: stand on the freeway and cars should appear, on it and moving.
			var traffic = city.get_node_or_null("Traffic")
			if traffic:
				var on_deck := Vector3(deck_xz.x, fw.point_at(0, pts0.size() * 0.5 * 24.0)[0].y + 2.0, deck_xz.y)
				var t_mid: float = fw.length_of(0) * 0.5
				var mid_pt: Vector3 = fw.point_at(0, t_mid)[0]
				on_deck = Vector3(mid_pt.x, mid_pt.y + 2.0, mid_pt.z)
				player.global_position = _world_state().to_local(on_deck)
				player.velocity = Vector3.ZERO
				city.update_streaming(true)
				await _ticks(70)
				# One new car a frame (TrafficManager.builds_per_frame): wait, bounded, for both
				# directions to have arrived.
				for i in 30:
					var dirs := {}
					for car in traffic.freeway_cars:
						dirs[int(car.traffic.dir)] = true
					if dirs.size() >= 2:
						break
					await _ticks(10)
				_check(traffic.freeway_cars.size() > 0, "cars cruise the freeway deck (%d)" % traffic.freeway_cars.size())
				var on_the_deck := 0
				var both_ways := {}
				for car in traffic.freeway_cars:
					var cw: Vector3 = _world_state().to_world(car.global_position)
					var near: Array = fw.nearest_on(car.traffic.fw, Vector2(cw.x, cw.z))
					var deck: Vector3 = fw.point_at(car.traffic.fw, float(near[0]))[0]
					if float(near[1]) < fw.routes[car.traffic.fw].width * 0.5 and absf(cw.y - deck.y) < 3.0:
						on_the_deck += 1
					both_ways[int(car.traffic.dir)] = true
				_check(on_the_deck == traffic.freeway_cars.size(),
					"every freeway car is on the deck, not beside or under it (%d of %d)"
						% [on_the_deck, traffic.freeway_cars.size()])
				_check(both_ways.size() == 2, "the freeway runs both ways (%d directions)" % both_ways.size())
			var back_home := Vector3(0.0, 0.0, 0.0)
			back_home.y = macro.height_at(Vector2.ZERO) + 3.0
			player.global_position = _world_state().to_local(back_home)
			player.velocity = Vector3.ZERO
			city.update_streaming(true)
			await _ticks(5)

	# The campus district and its main hall.
	if macro:
		_check(macro.district_at(macro.campus_center) == CityPlan.District.CAMPUS and CityPlan.district_name(CityPlan.District.CAMPUS) == "Campus", "campus district around the university")
		# Every table that is indexed by district must have an entry for every district. Adding a
		# district and missing one of these is an out-of-bounds read on a code path that only
		# runs when the player happens to stand in the new district, which is exactly the kind
		# of defect that reaches a build.
		var per_district := {
			"CityPlan.DISTRICTS": CityPlan.DISTRICTS.size(),
			"DISTRICT_NAMES": CityPlan.DISTRICT_NAMES.size(),
			"StreetDetail.POLE_ODDS": StreetDetail.POLE_ODDS.size(),
			"StreetDetail.LOADING_ODDS": StreetDetail.LOADING_ODDS.size(),
			"StreetDetail.METER_ODDS": StreetDetail.METER_ODDS.size(),
		}
		var short_tables := ""
		for table_name in per_district:
			if int(per_district[table_name]) != CityPlan.District.size():
				short_tables += " %s=%d" % [table_name, int(per_district[table_name])]
		_check(short_tables == "", "every per-district table covers all %d districts%s" % [CityPlan.District.size(), short_tables])
		# And every district really does produce a block: DISTRICTS is keyed by the enum, so a
		# missing key is a silent failure rather than a crash.
		var missing_district := ""
		for d in CityPlan.District.size():
			if not CityPlan.DISTRICTS.has(d):
				missing_district += " %d" % d
		_check(missing_district == "", "every district has generation parameters%s" % missing_district)
		# The coast towns: the place readout has to change as you drive the highway.
		var town_names := {}
		for town in MacroMap.COAST_TOWNS:
			var probe := Vector2(macro.coast_x(float(town[0]) + 40.0) + 90.0, float(town[0]) + 40.0)
			town_names[macro.place_name(probe)] = true
		_check(town_names.size() >= 6, "the coast is a chain of named towns (%d distinct)" % town_names.size())
		# The beach must be ABOVE the sea, not under it. The sand is a ramp from below the waves
		# up to the town, and if its waterline height drops under the sea surface the whole
		# beach floods - which looks, from the air, exactly like a beach at high tide, so it is
		# the kind of defect that survives a screenshot.
		_check(CityChunk.SAND_EDGE > 0.16 and CityChunk.SAND_HIGH > CityChunk.SAND_EDGE and CityChunk.SAND_LOW < 0.0,
				"the sand rises out of the water (low %.2f, edge %.2f, high %.2f)" % [CityChunk.SAND_LOW, CityChunk.SAND_EDGE, CityChunk.SAND_HIGH])
		# And every landmark the map lists has a label on the minimap: the fallback prints the
		# raw id, so a missing one ships as "venice_boardwalk" written across the map.
		var unlabelled := ""
		for lm in Landmarks.all():
			if not Minimap.LANDMARK_NAMES.has(lm.id):
				unlabelled += " " + str(lm.id)
		_check(unlabelled == "", "every landmark has a minimap label%s" % unlabelled)
		# The flat zones (airport, port, harbour) are checked by zone_at() BEFORE the coastline,
		# so a rect whose west edge reaches past the waterline wins and lays tarmac out over the
		# sea. The airport did exactly that for a long time. Walk each rect's seaward edge and
		# assert it stays inland of the sand.
		var wet_rects := ""
		for named_rect in [["airport", macro.airport_rect], ["port", macro.port_rect]]:
			var r: Rect2 = named_rect[1]
			for k in 9:
				var z: float = r.position.y + r.size.y * float(k) / 8.0
				if r.position.x < macro.coast_x(z) + macro.beach_width:
					wet_rects += " %s@z%.0f" % [str(named_rect[0]), z]
					break
		_check(wet_rects == "", "no flat zone reaches past the waterline%s" % wet_rects)
		# --- Numbers that live in two files ---------------------------------------------------
		# An audit of the project turned up fifteen pairs of constants that have to agree across
		# a file boundary with nothing in code connecting them. Drift is always silent - no
		# error, no crash, just a wrong picture - so the ones whose failure would be visible get
		# a guard here. Read the second copy out of the source rather than writing it a third
		# time: a guard that repeats the number is one more copy to keep in step.
		var shader_nums := func(src: String, decl: String) -> PackedFloat32Array:
			var out := PackedFloat32Array()
			var at := src.find(decl)
			if at < 0:
				return out
			var end := src.find(";", at)
			var body := src.substr(at + decl.length(), end - at - decl.length())
			for part in body.replace("vec3(", "").replace(")", "").split(","):
				out.append(part.strip_edges().to_float())
			return out
		# Past handover_start the ocean chunks stop drawing their own water and RE-DRAW the far
		# plane's, from their own copy of MacroMap's sea palette decoded to linear. Re-tune the
		# bake without touching the shader and the streamed water keeps painting the old colour:
		# a hard-edged rectangle of differently coloured sea about 500 m across, locked to the
		# player, following him round the bay. That is the exact failure ocean.gdshader's own
		# header spends twenty-five lines on.
		var sea_src: String = (load("res://shaders/ocean.gdshader") as Shader).code
		var sea_why := ""
		for pair in [["uniform vec3 deep_color =", MacroMap.BAKE_OCEAN_DEEP],
				["uniform vec3 shelf_color =", MacroMap.BAKE_OCEAN_SHALLOW],
				["uniform vec3 bake_surf_color =", MacroMap.BAKE_SURF]]:
			var want: Color = (pair[1] as Color).srgb_to_linear()
			var got: PackedFloat32Array = shader_nums.call(sea_src, pair[0])
			if got.size() != 3:
				sea_why += " %s missing" % str(pair[0])
				continue
			for i in 3:
				var w: float = [want.r, want.g, want.b][i]
				if absf(got[i] - w) > maxf(0.0002, w * 0.06):
					sea_why += " %s[%d]=%.5f want %.5f" % [str(pair[0]).substr(13), i, got[i], w]
		var surf_w: PackedFloat32Array = shader_nums.call(sea_src, "uniform float bake_surf_width =")
		if surf_w.size() != 1 or absf(surf_w[0] - MacroMap.BAKE_SURF_WIDTH) > 0.5:
			sea_why += " bake_surf_width"
		_check(sea_why == "", "the ocean shader still paints MacroMap's baked sea%s" % sea_why)
		# The coastline the ocean shader draws its shore effects against is MacroMap.coast_x()
		# written out a second time in GLSL. If they disagree the surf line, the shallow water
		# and the sand stop being in the same place.
		var coast_why := ""
		for pair in [["coast_base_x", macro.coast_base_x], ["coast_wobble", macro.coast_wobble],
				["coast_period", macro.coast_period], ["peninsula_radius", macro.peninsula_radius],
				["peninsula_bulge", macro.peninsula_bulge], ["bay_z", macro.bay_z],
				["bay_east_x", macro.bay_east_x]]:
			var got: PackedFloat32Array = shader_nums.call(sea_src, "uniform float %s =" % str(pair[0]))
			if got.size() != 1 or absf(got[0] - float(pair[1])) > 0.5:
				coast_why += " %s=%s want %.0f" % [str(pair[0]), str(got), float(pair[1])]
		_check(coast_why == "", "the ocean shader's coastline matches MacroMap's%s" % coast_why)
		# built_amount() in macro_ground.gdshader stops calling ground "city" above 420 m, so the
		# inland valley floor the city is built on has to stay well under that or the whole
		# valley district quietly vanishes from the horizon plane.
		var ground_src: String = (load("res://shaders/macro_ground.gdshader") as Shader).code
		_check(ground_src.contains("smoothstep(420.0, 700.0, height_m)") and macro.valley_height < 360.0,
				"the inland valley stays inside the horizon shader's height gate (%.0f m)" % macro.valley_height)
		# The pavement top is written out in the chunk that lays it and again in the commercial
		# blocks that stand on it; a shopfront half a step above its own kerb is the result.
		var chunk_consts: Dictionary = (load("res://scripts/world/city_chunk.gd") as GDScript).get_script_constant_map()
		var comm_consts: Dictionary = (load("res://scripts/world/commercial.gd") as GDScript).get_script_constant_map()
		_check(is_equal_approx(float(chunk_consts["SIDEWALK_TOP"]), float(comm_consts["TOP"])),
				"shopfronts stand on the same pavement top the chunk lays (%.2f / %.2f)" % [chunk_consts["SIDEWALK_TOP"], comm_consts["TOP"]])
		# Per-index tables against their enums. This is the shape of bug that shipped as
		# "Out of bounds get index '5'" when BEACHTOWN joined CityPlan.District: a table one
		# row short of its enum either crashes or silently reads the wrong row.
		var table_why := ""
		if MacroMap.ZONE_NAMES.size() != MacroMap.Zone.size():
			table_why += " MacroMap.ZONE_NAMES"
		if Minimap.DISTRICT_COLORS.size() != CityPlan.District.size():
			table_why += " Minimap.DISTRICT_COLORS"
		var veh_consts: Dictionary = (load("res://scripts/vehicles/vehicle.gd") as GDScript).get_script_constant_map()
		var body_types: int = (veh_consts["BodyType"] as Dictionary).size()
		if (veh_consts["BODY_NAMES"] as Array).size() != body_types:
			table_why += " Vehicle.BODY_NAMES"
		if (veh_consts["BODY_MODELS"] as Dictionary).size() != body_types:
			table_why += " Vehicle.BODY_MODELS"
		var body_odds: Dictionary = veh_consts["BODY_ODDS"]
		var odds_sum := 0
		for k in body_odds:
			odds_sum += int(body_odds[k])
		if body_odds.size() != body_types or odds_sum != 1000:
			table_why += " Vehicle.BODY_ODDS(%d rows, sums %d)" % [body_odds.size(), odds_sum]
		var wx_consts: Dictionary = (load("res://scripts/world/weather.gd") as GDScript).get_script_constant_map()
		var wx_states: int = (wx_consts["State"] as Dictionary).size()
		if (wx_consts["STATE_NAMES"] as Array).size() != wx_states:
			table_why += " Weather.STATE_NAMES"
		var wx_node: Node = city.get_node_or_null("Weather")
		if wx_node:
			for named in [["odds", wx_node.odds], ["wave_scale_by_state", wx_node.wave_scale_by_state],
					["fog_by_state", wx_node.fog_by_state], ["volumetric_by_state", wx_node.volumetric_by_state]]:
				if (named[1] as PackedFloat32Array).size() != wx_states:
					table_why += " Weather.%s" % str(named[0])
		var q_consts: Dictionary = (load("res://scripts/util/quality.gd") as GDScript).get_script_constant_map()
		var q_levels: int = (q_consts["Level"] as Dictionary).size()
		var q_node: Node = city.get_node_or_null("Quality")
		if q_node:
			for named in [["render_scale", q_node.render_scale], ["population", q_node.population],
					["shadow_distance", q_node.shadow_distance], ["lod_threshold", q_node.lod_threshold],
					["pixel_budget", q_node.pixel_budget]]:
				if (named[1] as PackedFloat32Array).size() != q_levels:
					table_why += " Quality.%s" % str(named[0])
		_check(table_why == "", "every per-index table has a row per enum member%s" % table_why)
		_check(city.has_node("FarLandmark_campus_hall"), "far version of the campus hall exists")
	# Landmarks: far versions always exist; the detailed one appears when its chunk is loaded.
	if macro:
		_check(city.has_node("FarLandmark_sign") and city.has_node("FarLandmark_pier") and city.has_node("FarLandmark_observatory"), "far versions of the sign, pier and observatory exist")
		# The boardwalk's shop strip follows the shore across the ends of straight streets, and
		# cars parked there spawned inside a shop and were pushed out onto its roof.
		var bw: Vector2 = _landmark_anchor("venice_boardwalk")
		var shop_mid: Vector3 = LandmarkVeniceBoardwalk._at(bw, plan, LandmarkVeniceBoardwalk.SHOP_FRONT_X + LandmarkVeniceBoardwalk.SHOP_DEPTH * 0.5, 150.0, 0.0)
		var walk_mid: Vector3 = LandmarkVeniceBoardwalk._at(bw, plan, 0.0, 150.0, 0.0)
		_check(Landmarks.covers(plan, Vector2(shop_mid.x, shop_mid.z), 0.0) and not Landmarks.covers(plan, Vector2(walk_mid.x, walk_mid.z), 0.0), "street parking keeps out of the boardwalk shops")
		var pier_anchor: Vector2 = _landmark_anchor("pier")
		player.global_position = _world_state().to_local(Vector3(pier_anchor.x + 10.0, 3.0, pier_anchor.y))
		player.velocity = Vector3.ZERO
		city.update_streaming(true)
		var pier_key: Vector2i = plan.block_index_at(pier_anchor)
		var pier_chunk: Node3D = city.chunks.get(pier_key)
		_check(pier_chunk != null and pier_chunk.built_landmarks.has("pier"), "pier chunk built the detailed pier")
		_check(not city.get_node("FarLandmark_pier").visible, "far pier is hidden while the detailed pier is loaded")
		var wheel_found := false
		for child in pier_chunk.get_children():
			if child is FerrisWheel:
				wheel_found = true
		_check(wheel_found, "the pier has a Ferris wheel")
		# Stand on the deck: it is solid.
		player.global_position = _world_state().to_local(Vector3(pier_anchor.x - 60.0, 9.0, pier_anchor.y))
		player.velocity = Vector3.ZERO
		await _wait_for_floor(player, 120)
		var deck_y: float = _world_state().to_world(player.global_position).y
		_check(player.is_on_floor() and deck_y > 5.0, "player stands on the pier deck at %.1f m" % deck_y)

	# Skyline, airport, port.
	if macro:
		_check(macro.zone_at(Vector2(-350.0, 800.0)) == MacroMap.Zone.AIRPORT and macro.height_at(Vector2(-350.0, 800.0)) == 0.0, "airport zone is flat")
		_check(macro.zone_at(Vector2(800.0, 1150.0)) == MacroMap.Zone.PORT and macro.zone_at(Vector2(800.0, 1420.0)) == MacroMap.Zone.OCEAN, "port sits on a harbor")
		var crown: Vector2 = _landmark_anchor("crown_tower")
		player.global_position = _world_state().to_local(Vector3(crown.x + 40.0, 2.0, crown.y + 40.0))
		player.velocity = Vector3.ZERO
		city.update_streaming(true)
		var crown_chunk: Node3D = city.chunks.get(plan.block_index_at(crown))
		_check(crown_chunk != null and crown_chunk.built_landmarks.has("crown_tower"), "downtown chunk built the crown tower")
		var overlaps := 0
		if crown_chunk:
			for child in crown_chunk.get_children():
				if child is Building:
					var b := child as Building
					var foot := Rect2(Vector2(b.position.x, b.position.z) - b.footprint * 0.5, b.footprint)
					if foot.intersects(Rect2(crown - Vector2(34.0, 34.0), Vector2(68.0, 68.0))):
						overlaps += 1
		_check(overlaps == 0, "no seeded building overlaps the crown tower footprint")
		var runway := Vector2(-300.0, 760.0)
		player.global_position = _world_state().to_local(Vector3(runway.x, 2.0, runway.y))
		city.update_streaming(true)
		var airport_chunk: Node3D = city.chunks.get(plan.block_index_at(runway))
		_check(airport_chunk != null and airport_chunk.zone == MacroMap.Zone.AIRPORT and airport_chunk.has_node("Runway") and airport_chunk.building_count == 0, "airport chunk has a runway and no buildings")
		# The terminal drop-off: a loop of crawling cars and a crowd on the curb.
		var curb_c: Vector2 = macro.terminal_curb.get_center()
		player.global_position = _world_state().to_local(Vector3(curb_c.x, 2.0, curb_c.y + 20.0))
		city.update_streaming(true)
		var loop_mgr: Node3D = city.get_node("Traffic")
		# Traffic builds at most one new car a frame (TrafficManager.builds_per_frame), so the jam
		# forms over a few frames rather than in one; give it a bounded while to get there.
		for i in 40:
			await _ticks(10)
			if loop_mgr.loop_cars.size() >= 20:
				break
		_check(loop_mgr.loop_cars.size() >= 20, "airport drop-off loop is jammed (%d cars)" % loop_mgr.loop_cars.size())
		var curb_people := 0
		for ped in get_tree().get_nodes_in_group("pedestrian"):
			var wp: Vector3 = _world_state().to_world(ped.global_position)
			if macro.terminal_curb.grow(6.0).has_point(Vector2(wp.x, wp.z)):
				curb_people += 1
		_check(curb_people >= 15, "crowd on the terminal curb (%d)" % curb_people)
		if loop_mgr.loop_cars.size() > 0:
			var lc: Node3D = loop_mgr.loop_cars[0]
			var lp0: Vector3 = lc.global_position
			await _ticks(60)
			_check(is_instance_valid(lc) and lc.global_position.distance_to(lp0) > 1.0, "loop cars crawl forward")
		var port := Vector2(800.0, 1150.0)
		player.global_position = _world_state().to_local(Vector3(port.x, 2.0, port.y))
		city.update_streaming(true)
		var port_chunk: Node3D = city.chunks.get(plan.block_index_at(port))
		_check(port_chunk != null and port_chunk.zone == MacroMap.Zone.PORT and port_chunk.has_node("Batch_container"), "port chunk has container stacks")

	# Cars: parked in the streets, drivable.
	player.global_position = _world_state().to_local(Vector3(0.0, 2.0, 0.0))
	player.velocity = Vector3.ZERO
	city.update_streaming(true)
	await _ticks(10)
	var cars: Array = []
	for c in get_tree().get_nodes_in_group("vehicle"):
		if not c.is_traffic():
			cars.append(c)
	_check(cars.size() >= 5, "parked cars spawned (%d)" % cars.size())
	# A quiet street for the driving checks: no traffic and no crowd nearby (both are tested
	# below), otherwise a passing car or a knocked pedestrian can pin the test car.
	var traffic_mgr: Node3D = city.get_node("Traffic")
	var traffic_cap: int = traffic_mgr.max_cars
	traffic_mgr.max_cars = 0
	for c in traffic_mgr.cars.duplicate():
		if is_instance_valid(c):
			c.queue_free()
	traffic_mgr.cars.clear()
	if cars.size() > 0:
		for ped in get_tree().get_nodes_in_group("pedestrian"):
			if ped.global_position.distance_to(cars[0].global_position) < 90.0:
				ped.queue_free()
	await _ticks(2)
	if cars.size() > 0:
		var car: Node3D = cars[0]
		var types := {}
		for c in cars:
			types[c.body_type] = true
		_check(types.size() >= 2, "cars come in %d body types" % types.size())
		# Put the test car on a known straight road (the +X road of block 0,0, heading -Z) and
		# clear every other car nearby, so the drive and turn checks never depend on what happened
		# to be parked ahead. The road is 14+ m wide and runs the whole block length.
		var road_x: float = plan.road_pos(CityPlan.AXIS_X, 1)
		var block0: Dictionary = plan.block(0, 0)
		# The road sits on the rolling relief, so ask the city how high it is there (the car used
		# to be dropped at y 0.6, under the slab, and drove on the ground follower plane).
		var road_xz := Vector2(road_x, (block0.rect as Rect2).end.y - 6.0)
		var road_start := Vector3(road_xz.x, city.ground_height_at(_world_state().to_local(Vector3(road_xz.x, 0.0, road_xz.y))) + 0.6, road_xz.y)
		for c in get_tree().get_nodes_in_group("vehicle"):
			if c != car and not c.is_traffic() and c.global_position.distance_to(_world_state().to_local(road_start)) < 140.0:
				c.queue_free()
		car.global_position = _world_state().to_local(road_start)
		car.rotation = Vector3.ZERO
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		await _ticks(20)
		player.global_position = car.global_position + Vector3(2.5, 0.5, 0.0)
		player.velocity = Vector3.ZERO
		await _ticks(5)
		await _press("interact")
		_check(player.is_driving() and player.vehicle == car, "interact gets into the nearest car")
		var start: Vector3 = car.global_position
		var nose: Vector3 = -car.global_basis.z
		Input.action_press("move_forward")
		await _ticks(120)
		var driven: float = (car.global_position - start).dot(nose)
		_check(driven > 8.0, "car drives toward its headlights %.1f m in 2 s" % driven)
		var yaw0: float = car.rotation.y
		Input.action_press("move_right")
		await _ticks(45)
		Input.action_release("move_right")
		Input.action_release("move_forward")
		var turned: float = wrapf(car.rotation.y - yaw0, -PI, PI)
		var planted := 0
		for w in car.wheels:
			if w.is_in_contact():
				planted += 1
		_check(turned < -0.15 and car.global_basis.y.y > 0.9, "D turns the car right (%.2f rad) and it stays flat (%d wheels down)" % [turned, planted])
		await _ticks(30)
		# Space makes the car jump. Wait for all four wheels to be down first: a car only jumps
		# from the ground, and after the turn test it is still settling (airborne cars now fall
		# at reduced gravity, so settling takes longer than it used to).
		for i in 180:
			await get_tree().physics_frame
			if not car.is_airborne() and absf(car.linear_velocity.y) < 0.4:
				break
		var car_y0: float = car.global_position.y
		var top_y: float = car_y0
		var worst_tilt := 0.0
		Input.action_press("jump")
		for i in 40:
			await get_tree().physics_frame
			top_y = maxf(top_y, car.global_position.y)
			worst_tilt = maxf(worst_tilt, 1.0 - car.global_basis.y.y)
		Input.action_release("jump")
		_check(top_y > car_y0 + 1.0, "Space makes the car jump (%.1f m)" % (top_y - car_y0))
		# Owner, 2026-09-20: the nose must not tip over on a jump.
		_check(worst_tilt < 0.1, "the car stays level through a jump (worst tilt %.3f)" % worst_tilt)

		# Flight: hold boost in the air and the car climbs where the camera looks, staying level.
		car.global_position += Vector3(0.0, 14.0, 0.0)
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3(2.0, 1.0, 2.0) # give it a tumble to recover from
		player.camera_rig.set_look(0.0, 35.0)
		await _ticks(4)
		var fly_y0: float = car.global_position.y
		Input.action_press("boost")
		var fly_tilt := 0.0
		for i in 70:
			await get_tree().physics_frame
			if i > 25:
				fly_tilt = maxf(fly_tilt, 1.0 - car.global_basis.y.y)
		Input.action_release("boost")
		_check(car.global_position.y > fly_y0 + 3.0, "boost flies the car upward (%.1f m gained)" % (car.global_position.y - fly_y0))
		_check(fly_tilt < 0.45, "the flying car stabilises itself instead of tumbling (tilt %.2f)" % fly_tilt)
		# Put the car back on the known-clear stretch of road it started from. Leaving it
		# wherever the flight ended means the exit test runs next to whatever happens to be
		# there, which changes every time the world's seeded layout shifts.
		car.global_position = _world_state().to_local(road_start)
		car.rotation = Vector3.ZERO
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		for i in 180:
			await get_tree().physics_frame
			if not car.is_airborne() and absf(car.linear_velocity.y) < 0.4:
				break
		await _ticks(20)
		await _press("interact")
		_check(not player.is_driving() and player.visible and player.global_position.distance_to(car.global_position) < 5.0, "interact gets out next to the car")
		if macro:
			# A car that ends up under a hill gets lifted onto the surface while you drive it.
			await _ticks(30)
			# Stand on the roof: always free, whatever the car parked next to.
			player.global_position = car.global_position + Vector3.UP * 2.5
			player.velocity = Vector3.ZERO
			await _ticks(3)
			await _press("interact")
			_check(player.is_driving(), "interact gets back in")
			var hill_xz := Vector2(0.0, -1400.0)
			var hill_h: float = macro.height_at(hill_xz)
			car.global_position = _world_state().to_local(Vector3(hill_xz.x, 0.5, hill_xz.y))
			car.linear_velocity = Vector3.ZERO
			await get_tree().physics_frame
			city.update_streaming(true)
			var lifted := false
			for i in 120:
				await get_tree().physics_frame
				if _world_state().to_world(car.global_position).y > hill_h - 3.0:
					lifted = true
					break
			var car_w: Vector3 = _world_state().to_world(car.global_position)
			_check(lifted, "car under a hill is lifted onto it (y %.0f of %.0f)" % [car_w.y, hill_h])
			# Getting out of a car lying on its side never puts you in the ground.
			await _ticks(90)
			var side_t := car.global_transform
			side_t.basis = Basis(Vector3.FORWARD, PI * 0.5) * side_t.basis
			side_t.origin.y += 1.0
			car.global_transform = side_t
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			await _ticks(20)
			player.exit_vehicle() # the E key itself is covered above; this isolates the placement
			await _ticks(20)
			var out_w: Vector3 = _world_state().to_world(player.global_position)
			var ground_here: float = macro.height_at(Vector2(out_w.x, out_w.z))
			var apart: float = player.global_position.distance_to(car.global_position)
			# (Both slide down the slope a bit, so the distance check is loose.)
			_check(not player.is_driving() and out_w.y > ground_here - 2.0, "getting out of a car on its side lands above ground (y %.0f, hill %.0f, %.0f m from the car, driving %s)" % [out_w.y, ground_here, apart, player.is_driving()])
			player.global_position = _world_state().to_local(Vector3(0.0, 2.0, 0.0))
			player.velocity = Vector3.ZERO
			city.update_streaming(true)
		# Falling through the world lifts you back onto loaded ground where you are.
		var far_spot := Vector3(2600.0, -20.0, 300.0)
		player.global_position = _world_state().to_local(far_spot)
		player.velocity = Vector3(0, -30, 0)
		await _ticks(40)
		var back_w: Vector3 = _world_state().to_world(player.global_position)
		_check(back_w.y > -1.0 and Vector2(back_w.x, back_w.z).distance_to(Vector2(far_spot.x, far_spot.z)) < 20.0, "falling through the world recovers in place (y %.1f)" % back_w.y)
		await _wait_for_floor(player, 240)
		_check(player.is_on_floor(), "and lands on solid ground")
		player.global_position = _world_state().to_local(Vector3(0.0, 2.0, 0.0))
		player.velocity = Vector3.ZERO
		city.update_streaming(true)

	# Jets: taxi down the runway under throttle, then pull up and fly.
	if macro:
		var apron: Vector2 = macro.apron_spots[0][0]
		player.global_position = _world_state().to_local(Vector3(apron.x, 3.0, apron.y + 7.0))
		player.velocity = Vector3.ZERO
		city.update_streaming(true)
		await _ticks(15)
		var jet: Node3D = null
		for node in get_tree().get_nodes_in_group("vehicle"):
			if node is Aircraft and node.global_position.distance_to(player.global_position) < 40.0:
				jet = node
		_check(jet != null, "a jet waits on the apron")
		if jet:
			await _press("interact")
			_check(player.is_driving() and player.vehicle == jet, "interact climbs into the jet (%s)" % jet.display_name())
			Input.action_press("boost")
			await _ticks(330)
			var ground_speed: float = jet.linear_velocity.length()
			var y_before: float = _world_state().to_world(jet.global_position).y
			_check(ground_speed > 30.0, "full throttle rolls the jet down the field (%.0f m/s, y %.1f)" % [ground_speed, y_before])
			Input.action_press("move_back")
			var top_y := y_before
			for i in 300:
				await get_tree().physics_frame
				top_y = maxf(top_y, _world_state().to_world(jet.global_position).y)
			Input.action_release("move_back")
			Input.action_release("boost")
			_check(top_y > 25.0, "pulling up takes off (peak %.0f m)" % top_y)
			await _ticks(20)
			player.exit_vehicle()
			player.global_position = _world_state().to_local(Vector3(0.0, 2.0, 0.0))
			player.velocity = Vector3.ZERO
			city.update_streaming(true)
			await _ticks(5)
	# Pedestrians and traffic.
	traffic_mgr.max_cars = traffic_cap
	player.global_position = _world_state().to_local(Vector3(0.0, 2.0, 0.0))
	player.velocity = Vector3.ZERO
	city.update_streaming(true)
	await _ticks(130)
	var peds := get_tree().get_nodes_in_group("pedestrian")
	_check(peds.size() >= 10 and peds.size() <= city.max_pedestrians, "pedestrians on the sidewalks (%d)" % peds.size())
	if peds.size() > 0:
		# The nearest one, not peds[0]: the ragdoll lives in the pedestrian's chunk, and the first
		# in the group can be in a chunk at the edge of the window that is swapped for its far
		# version a tick later, taking the ragdoll with it.
		var ped: Node3D = peds[0]
		for p: Node3D in peds:
			if not p.is_queued_for_deletion() and p.global_position.distance_to(player.global_position) < ped.global_position.distance_to(player.global_position):
				ped = p
		var before_dolls := {}
		for n in get_tree().get_nodes_in_group("debris"):
			if n is Ragdoll:
				before_dolls[n.get_instance_id()] = true
		ped.knock(Vector3(5.0, 8.0, 0.0))
		await _ticks(3)
		# Other ragdolls come and go (traffic, debris timeouts); look for one that is new.
		var new_dolls := 0
		for n in get_tree().get_nodes_in_group("debris"):
			if n is Ragdoll and not before_dolls.has(n.get_instance_id()):
				new_dolls += 1
		_check(not is_instance_valid(ped) or ped.is_queued_for_deletion(), "knocked pedestrian is removed")
		_check(new_dolls >= 1, "a ragdoll takes its place")
		# The ragdoll is the same rigged character, not a box body (owner, 2026-09-20).
		var rigged_doll := false
		for n in get_tree().get_nodes_in_group("debris"):
			if n is Ragdoll and not before_dolls.has(n.get_instance_id()) and n.find_child("Skeleton3D", true, false) != null:
				rigged_doll = true
		_check(rigged_doll, "the ragdoll keeps the pedestrian's real model")
		# Bullets hurt people: the AK-47 ray must hit the npc layer and knock the target over.
		# The nearest ones: past Pedestrian.physics_range a pedestrian's hit zone is switched off.
		# A lamp post, a car or a bin between the muzzle and the target takes the bullet instead,
		# so try the nearest few until one shot lands on somebody.
		var targets: Array = []
		for p in peds:
			if is_instance_valid(p) and not (p as Node).is_queued_for_deletion():
				targets.append(p)
		targets.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
		var rifle: Node = player.weapon_manager.get_node_or_null("AssaultRifle")
		if rifle == null:
			for w in player.weapon_manager.get_children():
				if w is AssaultRifle:
					rifle = w
		var hit_a_person := false
		var struck_id: int = 0
		for target: Node3D in targets.slice(0, 5):
			# Fire from close range and follow whoever the bullet actually hits: the crowd is
			# dense enough now that a long shot often passes through somebody else first.
			var from: Vector3 = target.global_position + Vector3(0.0, 1.0, 0.0) + Vector3(-2.5, 0.0, 0.0)
			var hit: Dictionary = rifle.fire_ray(from, Vector3.RIGHT)
			var struck: Node = hit.get("collider") as Node
			while struck != null and not (struck is Pedestrian):
				struck = struck.get_parent()
			# Decide what we hit before awaiting: knocking it over frees the node.
			if struck is Pedestrian:
				hit_a_person = true
				struck_id = struck.get_instance_id()
				break
		if not targets.is_empty():
			await _ticks(3)
			var gone := hit_a_person and (not is_instance_valid(instance_from_id(struck_id)) or (instance_from_id(struck_id) as Node).is_queued_for_deletion())
			_check(hit_a_person and gone, "an AK-47 bullet knocks a pedestrian down")
		# Gunfire scares people (owner, 2026-09-23: "NPCs screaming"): the ones near it run.
		var runner: Node3D = null
		for p in get_tree().get_nodes_in_group("pedestrian"):
			if is_instance_valid(p) and not (p as Node).is_queued_for_deletion() and not p.get("_down"):
				if runner == null or (p as Node3D).global_position.distance_to(player.global_position) < runner.global_position.distance_to(player.global_position):
					runner = p
		if runner != null:
			Pedestrian.alarm(get_tree(), runner.global_position + Vector3(3.0, 0.0, 0.0), 15.0, 2, true)
			await _ticks(12)
			var flat_speed := Vector2(runner.velocity.x, runner.velocity.z).length() if is_instance_valid(runner) else 0.0
			_check(is_instance_valid(runner) and float(runner.get("_panic_left")) > 0.0 and flat_speed > float(runner.get("walk_speed")) * 1.5,
				"a gunshot sends the people near it running (%.1f m/s)" % flat_speed)
		# GTA-style aim (owner, 2026-09-24: "aiming that auto locks onto targets"): look roughly
		# at somebody, hold aim with the AK, and the lock takes them and the shot goes at them.
		# The nearest few in turn, because a lamp post or a car can stand in the line of sight.
		var lock: Node = player.get("lock_on")
		var manager: Node = player.get("weapon_manager")
		manager.equip(0)
		var locked: Node3D = null
		var aim_ok := false
		var candidates: Array = []
		for p in get_tree().get_nodes_in_group("pedestrian"):
			if is_instance_valid(p) and not (p as Node).is_queued_for_deletion() and not p.get("_down"):
				candidates.append(p)
		candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
		for cand: Node3D in candidates.slice(0, 5):
			# A few degrees off, so the lock has to find them rather than be handed them.
			player.get("camera_rig").look_at_point(cand.global_position + Vector3(0.6, 1.2, 0.0))
			Input.action_press("alt_fire")
			for i in 8:
				await get_tree().process_frame
			locked = lock.get("target")
			if locked != null:
				var aim: Dictionary = player.get_aim()
				var to_target: Vector3 = (locked.global_position + Vector3.UP * 1.2 - aim.origin).normalized()
				aim_ok = aim.get("target") == locked and (aim.direction as Vector3).dot(to_target) > 0.995
				break
			Input.action_release("alt_fire")
			await get_tree().process_frame
		_check(locked is Pedestrian and aim_ok, "holding aim locks onto a pedestrian and the shot goes at them")
		Input.action_release("alt_fire")
		for i in 3:
			await get_tree().process_frame
		_check(lock.get("target") == null and not lock.get("aiming"), "letting go of aim drops the lock")
	# Quality levels scale the population, not just the effects (owner: "still super laggy").
	var quality_node: Node = city.get_node("Quality")
	var full_cap: int = city.max_pedestrians
	quality_node.apply_level(3)
	await _ticks(3)
	_check(city.max_pedestrians < full_cap and get_tree().get_nodes_in_group("pedestrian").size() <= city.max_pedestrians + 2, "lowest quality trims the crowd to %d (was cap %d)" % [city.max_pedestrians, full_cap])
	quality_node.apply_level(0)
	# Characters: every rig wears the character shader, and a crowd shows several outfits and
	# several heights rather than three models copied (owner, 2026-09-20).
	var shaded := 0
	var outfits := {}
	var heights := {}
	for ped in get_tree().get_nodes_in_group("pedestrian"):
		for mi in (ped as Node).find_children("*", "MeshInstance3D", true, false):
			var ov := (mi as MeshInstance3D).material_override
			if ov is ShaderMaterial:
				shaded += 1
				outfits[Vector3(ov.get_shader_parameter("cloth_hue"), ov.get_shader_parameter("cloth_sat"), ov.get_shader_parameter("cloth_strength"))] = true
		var vis: Node3D = (ped as Node).get("_visual")
		if vis:
			heights[snappedf(vis.scale.y, 0.01)] = true
	_check(shaded > 10, "pedestrians use the character shader (%d)" % shaded)
	# Every character model has to arrive wearing something. One of the generated rigs came back
	# as bare skin from head to foot, and because the garment recolour only touches pixels that
	# are already off the skin hue, it walked the city as a naked orange mannequin. Measured as
	# how much of the texture sits away from its own average colour: a clothed character has
	# hair, shoes and fabric well off its skin tone (0.31 and 0.71 for the two in use), a nude
	# one is all one tone (0.001). Hue alone will not do it - brown clothing is a skin hue.
	var dressed := true
	var worst := 1.0
	# Loaded by path: naming the class here would pull in a script that uses an autoload.
	var ped_script: GDScript = load("res://scripts/npc/pedestrian.gd")
	for path in ped_script.MODELS:
		var rig: Node = (load(path) as PackedScene).instantiate()
		var tex: Texture2D = null
		for mi in rig.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
			if m and m.albedo_texture:
				tex = m.albedo_texture
				break
		rig.free()
		if tex == null:
			continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		var step := maxi(img.get_width() / 96, 1)
		var mean := Color(0, 0, 0)
		var total := 0
		for y in range(0, img.get_height(), step):
			for x in range(0, img.get_width(), step):
				mean += img.get_pixel(x, y)
				total += 1
		mean /= maxf(float(total), 1.0)
		var away := 0
		for y in range(0, img.get_height(), step):
			for x in range(0, img.get_width(), step):
				var c := img.get_pixel(x, y)
				if Vector3(c.r - mean.r, c.g - mean.g, c.b - mean.b).length() > 0.18:
					away += 1
		var ratio := float(away) / maxf(float(total), 1.0)
		worst = minf(worst, ratio)
		if ratio < 0.10:
			dressed = false
	_check(dressed, "every character model is wearing clothes (plainest is %.0f%% off its own skin tone)" % (worst * 100.0))
	_check(outfits.size() >= 5, "the crowd wears %d different outfits" % outfits.size())
	var tones := {}
	for ped in get_tree().get_nodes_in_group("pedestrian"):
		for mi in (ped as Node).find_children("*", "MeshInstance3D", true, false):
			var ov2 := (mi as MeshInstance3D).material_override
			if ov2 is ShaderMaterial:
				tones[ov2.get_shader_parameter("skin_tint")] = true
	_check(tones.size() >= 4, "the crowd has %d skin tones" % tones.size())
	_check(heights.size() >= 5, "the crowd has %d different heights" % heights.size())
	var avatar: Node = player.get_node_or_null("Visual/Avatar")
	_check(avatar != null and avatar.find_child("AnimationPlayer", true, false) != null and not player.get_node("Visual/Body").visible, "the player wears the animated character, capsule hidden")
	var traffic_node: Node3D = city.get_node("Traffic")
	var moving: int = traffic_node.cars.size()
	_check(moving >= 4, "traffic cars are driving (%d)" % moving)
	if moving > 0:
		var tcar: Node3D = traffic_node.cars[0]
		var p0: Vector3 = tcar.global_position
		await _ticks(60)
		_check(is_instance_valid(tcar) and tcar.global_position.distance_to(p0) > 4.0, "traffic car moved %.1f m in 1 s" % (tcar.global_position.distance_to(p0) if is_instance_valid(tcar) else 0.0))
		if is_instance_valid(tcar):
			tcar.drop_out_of_traffic(Vector3(0.0, 4000.0, 0.0))
			await _ticks(2)
			_check(not tcar.is_traffic() and not tcar.freeze, "a hit traffic car becomes a physics car")

	# Polish: grass in parks, day/night, sounds, pause menu, seed rebuild.
	var park_chunk: Node3D = null
	for k in city.chunks:
		var c: Node3D = city.chunks[k]
		if c.level == 0 and plan.block(k.x, k.y).kind == CityPlan.BlockKind.PARK and c.zone == MacroMap.Zone.CITY:
			park_chunk = c
			break
	if park_chunk == null:
		# Walk to any park nearby so one gets built in full detail.
		for k in city.chunks:
			var blk := plan.block(k.x, k.y)
			if blk.kind == CityPlan.BlockKind.PARK and plan.zone_at((blk.rect as Rect2).get_center()) == MacroMap.Zone.CITY:
				var c2: Vector2 = (blk.rect as Rect2).get_center()
				player.global_position = _world_state().to_local(Vector3(c2.x, 2.0, c2.y))
				city.update_streaming(true)
				park_chunk = city.chunks.get(k)
				break
	_check(park_chunk != null and park_chunk.has_node("Batch_grass") and (park_chunk.has_node("Batch_shrub_0") or park_chunk.has_node("Batch_shrub_1") or park_chunk.has_node("Batch_shrub_2") or park_chunk.has_node("Batch_shrub_3")), "a park has grass and bushes")
	var day: Node = city.get_node("DayNight")
	var h0: float = day.hour
	await _ticks(30)
	_check(day.hour > h0, "the clock advances (%s)" % day.clock_text())
	day.hour = 23.0
	day._apply()
	_check(day.night_factor > 0.9, "night raises night_factor (%.2f)" % day.night_factor)
	# Night lighting. Before this the streets were pitch black: the city had no light sources at
	# all except the sun, and the first attempt at lamps left every light that streamed in after
	# the level last changed sitting at zero energy, so the check forces night and then reads the
	# lights back rather than trusting that they were set.
	day.hour = 23.0
	day._apply()
	await _ticks(2)
	day._apply()
	var lamp_lights := get_tree().get_nodes_in_group("lamp_light")
	var lit_lamps := 0
	for l in lamp_lights:
		if (l as OmniLight3D).light_energy > 0.5:
			lit_lamps += 1
	_check(lamp_lights.size() > 20 and lit_lamps == lamp_lights.size(), "street lamps light up at night (%d of %d)" % [lit_lamps, lamp_lights.size()])
	var pools := 0
	for n in city.find_children("Batch_lamp_pool", "MultiMeshInstance3D", true, false):
		pools += (n as MultiMeshInstance3D).multimesh.instance_count
	_check(pools > 20, "lamps throw a pool of light on the pavement (%d)" % pools)
	# Every car carries its headlights, tail lights and road beam as one mesh (one draw, not
	# five - there are up to 150 cars on the road).
	var car_lights := 0
	var cars_seen := 0
	for car in traffic_cars_for_lights(city):
		cars_seen += 1
		var lights: Node = (car as Node).get_node_or_null("NightLights")
		if lights and (lights as MeshInstance3D).mesh and (lights as MeshInstance3D).mesh.surface_get_material(0) is ShaderMaterial:
			car_lights += 1
	_check(cars_seen > 0 and car_lights == cars_seen, "cars carry head and tail lights (%d of %d)" % [car_lights, cars_seen])
	day.hour = 12.0
	day._apply()
	_check(day.night_factor < 0.05, "noon clears it")
	var sfx: Node = get_tree().root.get_node("/root/Sfx")
	_check(sfx.has("shot") and sfx.has("explosion") and sfx.has("engine_loop"), "sound effects are synthesized")
	_check(sfx.has("rain") and sfx.has("thunder"), "rain and thunder are synthesized")
	# Weather: force a storm and watch the waves, wind and rain follow.
	var weather = city.get_node_or_null("Weather")
	_check(weather != null, "city has a Weather node")
	if weather:
		weather.state = 3
		weather._previous = 3
		weather.blend = 1.0
		for i in 3:
			weather._process(0.1)
		_check(weather.wave_scale > 3.0, "a storm raises the ocean's wave scale (%.1f)" % weather.wave_scale)
		_check(weather._rain.emitting, "a storm turns the rain on")
		_check(city.get_node("DayNight").weather_darken > 0.5, "a storm darkens the sky")
		weather.state = 0
		weather._previous = 0
		weather.blend = 1.0
		for i in 3:
			weather._process(0.1)
		_check(not weather._rain.emitting, "clear weather turns the rain off")
	# Ground surfaces are textured: either a triplanar PBR material or the road/pavement wear
	# shader, which carries its own albedo texture.
	var road_textured := false
	var ground_worn := false
	var home_full: Node3D = city.chunks.get(plan.block_index_at(Vector2.ZERO))
	if home_full:
		for child in home_full.get_children():
			if not (child is MeshInstance3D):
				continue
			var ov: Material = (child as MeshInstance3D).material_override
			if ov is StandardMaterial3D:
				var m := ov as StandardMaterial3D
				if m.albedo_texture != null and m.uv1_triplanar:
					road_textured = true
			elif ov is ShaderMaterial:
				var sm := ov as ShaderMaterial
				if sm.get_shader_parameter("albedo_tex") != null:
					road_textured = true
					ground_worn = true
	_check(road_textured, "roads and sidewalks use real textures")
	_check(ground_worn, "roads and pavements use the wear shader")
	# Everything outside the streamed chunks is the ground follower, and it has to be painted
	# from the baked map of the basin, not left as a flat green plane whose edge is the horizon.
	var follower: Node = city.get_node_or_null("Ground")
	var macro_ok := false
	var macro_land := 0
	var macro_water := 0
	if follower:
		for child in follower.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).material_override is ShaderMaterial:
				var gm := (child as MeshInstance3D).material_override as ShaderMaterial
				var tex: Texture2D = gm.get_shader_parameter("macro_tex")
				if tex:
					macro_ok = true
					var mi := tex.get_image()
					if mi.is_compressed():
						mi.decompress()
					for y in range(0, mi.get_height(), 7):
						for x in range(0, mi.get_width(), 7):
							if mi.get_pixel(x, y).a > 0.0005:
								macro_land += 1
							else:
								macro_water += 1
	_check(macro_ok and city.ground_size >= 10000.0, "the horizon is the baked macro map on a %.0f m plane" % (city.ground_size if follower else 0.0))
	# Both have to be in there: alpha is exactly zero on water and never zero on land, and the
	# shader tells the sea apart by that.
	_check(macro_land > 100 and macro_water > 100, "the baked map has land and sea (%d / %d samples)" % [macro_land, macro_water])
	_check(PropFactory.texture("brick", "Color") != null and PropFactory.texture("rock", "NormalGL") != null, "texture sets load")
	# The HUD starts clean: crosshair, minimap and weapons, no wall of developer text. F1 cycles
	# clean -> full -> hidden.
	var hud: CanvasLayer = city.get_node("DebugHud")
	_check(hud.visible and not hud.get_node("Stats").visible and not hud.get_node("Hints").visible,
		"the HUD starts clean (no stats, no hints)")
	hud.mode = 1
	hud._apply_mode()
	_check(hud.visible and hud.get_node("Stats").visible, "F1 brings the stats back")
	hud.mode = 2
	hud._apply_mode()
	_check(not hud.visible, "F1 again hides the HUD")
	hud.mode = 0
	hud._apply_mode()
	var minimap: Control = city.get_node("DebugHud/MinimapFrame/Minimap")
	_check(minimap != null and minimap.world_to_map(Vector2(0.0, -100.0), Vector2.ZERO).y < minimap.size.y * 0.5, "minimap exists and north is up")
	# Palms: a real generated tree (trunk, feathered fronds, skirt, coconuts) and palm-lined
	# blocks somewhere in the loaded city (owner, 2026-09-20: "it's Cali, put palm trees").
	var palm_mesh: Mesh = PropFactory.palm(0)
	var palm_idx = palm_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var palm_tris: int = (palm_idx as PackedInt32Array).size() / 3 if palm_idx != null else (palm_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_check(palm_mesh.get_surface_count() == 1 and palm_tris > 400, "the palm is one generated mesh (%d triangles)" % palm_tris)
	var palm_blocks := 0
	for k in city.chunks:
		for child in city.chunks[k].get_children():
			if child.name.begins_with("Batch_palm_"):
				palm_blocks += 1
				break
	_check(palm_blocks > 0, "palm-lined blocks in the loaded city (%d)" % palm_blocks)
	minimap.queue_redraw()
	await _ticks(3)
	var env: Environment = city.get_node("WorldEnvironment").environment
	_check(env.sdfgi_enabled and env.ssao_enabled and env.glow_enabled and env.tonemap_mode == Environment.TONE_MAPPER_AGX, "environment has GI, AO, glow and AgX filmic tonemapping")
	# The realism pass: bounce light, sky-coloured ambient and aerial perspective haze. The
	# threshold used to be 0.5, which quietly made the washed-out look a requirement: at 0.7 the
	# far half of every wide shot lerped into flat sky blue. The guard is that the effect is
	# still THERE, not that it is turned up.
	_check(env.ssil_enabled and env.fog_aerial_perspective > 0.15 and env.fog_height_density > 0.0, "environment has indirect light and aerial-perspective haze")
	# The grade. Contrast is what a frame lives on, and all three of these have been lost once:
	# a LUT the tonemapper runs every pixel through, a key light that out-runs the sky fill by a
	# real margin, and shadows that reach further than three blocks.
	_check(env.adjustment_enabled and env.adjustment_color_correction != null, "the frame is graded through a colour LUT")
	var day_node: Node = city.get_node("DayNight")
	day_node._process(0.0)
	_check(env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY, "ambient light comes from the sky, not a flat colour")
	var key_ratio: float = day_node.day_sun_energy / maxf(day_node.day_ambient_energy, 0.001)
	_check(key_ratio > 2.5, "the sun out-runs the sky fill (%.1fx)" % key_ratio)
	var qual: Node = city.get_node_or_null("Quality")
	if qual:
		var reach: float = qual.shadow_distance[0]
		_check(reach >= 500.0, "shadows reach across the city on HIGH (%.0f m)" % reach)
	var menu: Node = city.get_node("PauseMenu")
	menu.open()
	_check(get_tree().paused and menu.is_open(), "pause menu pauses the game")
	menu.close()
	_check(not get_tree().paused, "resume unpauses")
	_world_state().pending_seed = 4321
	var city2: Node3D = packed.instantiate()
	get_tree().root.add_child(city2)
	await get_tree().process_frame
	_check(city2.world_seed == 4321 and _world_state().pending_seed == -1, "a pending seed rebuilds the city with that seed")
	_check(city2.plan.road_pos(0, 3) != plan.road_pos(0, 3), "a different seed gives a different city")
	city2.queue_free()

	# Same seed, same plan.
	var a := CityPlan.new()
	a.seed = 777
	var b := CityPlan.new()
	b.seed = 777
	_check(a.road_pos(0, 5) == b.road_pos(0, 5) and a.road_pos(1, -4) == b.road_pos(1, -4) and a.block(3, -2).rect == b.block(3, -2).rect and a.block(3, -2).kind == b.block(3, -2).kind and a.intersection(2, 2).kind == b.intersection(2, 2).kind, "same seed gives the same city plan")
	# Basis.scaled() is a LEFT multiply, so its factors land on the WORLD axes after the
	# rotation, not on the mesh's own. Every flat additive quad in the game (lamp pools, pier
	# pools) is a +Z QuadMesh tipped -90 degrees about X, and written the obvious way round -
	# .scaled(SIZE, SIZE, 1) - the second SIZE is spent on the normal and the pool comes out a
	# one-metre-deep bar. Measure the transform's real world extents rather than trust the
	# argument order. Uses the live constants so a retune moves the assertion with it.
	var cc: GDScript = load("res://scripts/world/city_chunk.gd")
	var pool_size: float = cc.get_script_constant_map().get("LAMP_POOL_SIZE", 0.0)
	var pool_basis := Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(pool_size, 1.0, pool_size))
	# A unit QuadMesh spans local X and Y; its world footprint is what has to be square.
	var span_a := pool_basis * Vector3(1.0, 0.0, 0.0)
	var span_b := pool_basis * Vector3(0.0, 1.0, 0.0)
	var normal := pool_basis * Vector3(0.0, 0.0, 1.0)
	_check(pool_size > 1.0 and absf(span_a.length() - pool_size) < 0.01 and absf(span_b.length() - pool_size) < 0.01,
		"lamp light pool is square in world space (%.1f x %.1f m, wants %.1f)" % [span_a.length(), span_b.length(), pool_size])
	_check(absf(normal.length() - 1.0) < 0.01 and absf(normal.y) > 0.99, "lamp light pool lies flat with a unit normal")

	city.queue_free()
	_world_state().reset()


func _test_buildings() -> void:
	var buildings := get_tree().get_nodes_in_group("building")
	_check(buildings.size() >= 8, "city block has buildings (%d)" % buildings.size())
	var looks := {}
	var all_solid := true
	var all_shaded := true
	for node in buildings:
		var b := node as Building
		if b == null:
			continue
		looks[[b.shape, b.finish, b.window_style]] = true
		var shapes := 0
		var shaded := 0
		for child in b.get_children():
			if child is CollisionShape3D:
				shapes += 1
			if child is MeshInstance3D and (child as MeshInstance3D).material_override is ShaderMaterial:
				shaded += 1
		all_solid = all_solid and shapes > 0
		all_shaded = all_shaded and shaded > 0
		_check(b.height >= 4.0 and b.footprint.x > 2.0, "building %d has size %.0f x %.0f x %.0f m (%s)" % [b.seed % 1000, b.footprint.x, b.height, b.footprint.y, Building.Shape.keys()[b.shape]])
	_check(all_solid, "every building has collision")
	_check(all_shaded, "every building uses the building shader")
	# Windows show a traced fake room behind the glass, not a painted gradient. The uniforms
	# are left at their defaults by Building, so check the shader declares them.
	var uniforms := {}
	for u in Building.SHADER.get_shader_uniform_list():
		uniforms[u.name] = true
	_check(uniforms.has("room_depth") and uniforms.has("interior_enabled"), "the building shader does interior mapping")
	# Glass reflects the sky above the horizon and the street below it, and the room behind it
	# is dark against daylight. Without both, every pane reads as a beige card over the opening.
	_check(uniforms.has("sky_zenith") and uniforms.has("street_reflect") and uniforms.has("reflect_strength"),
		"window glass reflects sky and street")
	_check(uniforms.has("interior_exposure"), "rooms behind the glass are exposed for daylight outside")
	var framed := 0
	var frames_fit := true
	for b in get_tree().get_nodes_in_group("building"):
		if b.has_node("Frames") and b.get_node("Frames").multimesh.instance_count > 0:
			framed += 1
			# Frames and cornices must sit on the walls, never float above the roof (build 64 bug).
			var frame_top: float = (b.get_node("Frames").multimesh.get_aabb() as AABB).end.y
			if frame_top > b.height + 0.5:
				frames_fit = false
			if b.has_node("Details"):
				var detail_top: float = (b.get_node("Details").multimesh.get_aabb() as AABB).end.y
				if detail_top > b.height + 0.5:
					frames_fit = false
	_check(framed > 0, "buildings carry real window frames (%d)" % framed)
	# Shop names on the storefront sign bands, lined up with the shader's shop runs.
	var named := 0
	var sign_nodes := 0
	for b in get_tree().get_nodes_in_group("building"):
		var found := false
		for child in (b as Node).get_children():
			if child is MeshInstance3D and str((child as Node).name).begins_with("Sign"):
				sign_nodes += 1
				found = true
		if found:
			named += 1
	_check(named > 3 and sign_nodes > named, "storefronts carry shop names (%d signs on %d buildings)" % [sign_nodes, named])
	var with_balconies := 0
	for b in get_tree().get_nodes_in_group("building"):
		if (b.has_node("Balconies") and b.get_node("Balconies").multimesh.instance_count > 0) or _kit_count(b, "Batch_kit_balcony") > 0:
			with_balconies += 1
	_check(with_balconies > 0, "some buildings have balconies (%d)" % with_balconies)
	# Fire escapes only go on brick blocks, and the handful of buildings in the test room are
	# rarely brick, so build a deterministic sample rather than sampling whatever is loaded.
	var escape_scene: PackedScene = load("res://scenes/props/building.tscn")
	var sample: Array = []
	for si in range(1, 13):
		var eb: Building = escape_scene.instantiate()
		eb.seed = si
		eb.lot_size = Vector2(30.0, 30.0)
		eb.min_height = 26.0
		eb.max_height = 40.0
		eb.finish_options.assign([Building.Finish.BRICK])
		# Well away from anything: these are solid bodies, and at the origin they sit exactly
		# where the city spawns the player.
		eb.position = Vector3(4000.0 + float(si) * 60.0, 0.0, 4000.0)
		add_child(eb)
		sample.append(eb)
	await _ticks(2)
	var with_escapes := 0
	# The facade kit on the same brick sample: a surround at every window frame (they are
	# placed in the same loop, so the counts must match exactly), a moulded cornice, and the
	# lowest landing of every fire escape carrying the drop ladder.
	var surrounds_match := true
	var surrounded := 0
	var corniced := 0
	var ladders_ok := true
	for eb in sample:
		if (eb.has_node("FireEscape") and eb.get_node("FireEscape").multimesh.instance_count > 0) or _kit_count(eb, "Batch_kit_fe_") > 0:
			with_escapes += 1
		# Every part adds its own frames node, and the second one onwards is renamed on adding,
		# so find them by their mesh rather than their name.
		var frames_n := 0
		for fc in eb.get_children():
			if fc is MultiMeshInstance3D:
				var fm: Mesh = (fc as MultiMeshInstance3D).multimesh.mesh
				if fm == PropFactory.window_frame(true) or fm == PropFactory.window_frame(false):
					frames_n += (fc as MultiMeshInstance3D).multimesh.instance_count
		var surround_n := _kit_count(eb, "Batch_kit_surround")
		if surround_n > 0:
			surrounded += 1
			if surround_n != frames_n:
				surrounds_match = false
		if _kit_count(eb, "Batch_kit_cornice") > 0:
			corniced += 1
		var landings := _kit_count(eb, "Batch_kit_fe_")
		if landings > 0 and _kit_count(eb, "Batch_kit_fe_bottom") < 1:
			ladders_ok = false
		eb.free()
	_check(with_escapes >= 4, "brick blocks get fire escapes (%d of 12)" % with_escapes)
	_check(surrounded >= 10 and surrounds_match, "brick windows get the kit's stone surrounds, one per frame (%d of 12)" % surrounded)
	_check(corniced >= 10, "brick blocks get a moulded cornice (%d of 12)" % corniced)
	_check(ladders_ok, "every kit fire escape ends in a drop ladder")
	# Every kit piece loads with its geometry and wears the kit shader. The mesh AABB is kept on
	# the resource, so it is real under --headless.
	var kit_ok := true
	var kit_why := ""
	for piece in ["cornice_classic", "cornice_bracket", "cornice_simple", "coping", "surround_brick_a",
			"surround_brick_b", "surround_stucco", "ac_window", "awning", "balcony", "fe_stair_l",
			"fe_stair_r", "fe_bottom", "water_tank", "vent_mushroom", "vent_turbine", "hvac"]:
		var km := PropFactory.facade_kit(piece)
		if km == null or km.get_surface_count() == 0 or km.get_aabb().size.length() < 0.2:
			kit_ok = false
			kit_why += " %s missing" % piece
			continue
		for s in km.get_surface_count():
			var sm := km.surface_get_material(s) as ShaderMaterial
			if sm == null or not str(sm.shader.resource_path).begins_with("res://shaders/facade_kit"):
				kit_ok = false
				kit_why += " %s surface %d not on the kit shader" % [piece, s]
	_check(kit_ok, "every facade kit piece loads on the kit shader%s" % kit_why)
	# The roofline runs are 2 m and centred, which is what the mitre in the kit shader assumes.
	var run_box := PropFactory.facade_kit("cornice_classic").get_aabb()
	_check(absf(run_box.position.x + 1.0) < 0.005 and absf(run_box.end.x - 1.0) < 0.005, "cornice runs span x -1..1 (%.3f..%.3f)" % [run_box.position.x, run_box.end.x])
	# Surrounds line up with the windows the shader draws only if Building's window rects are
	# the shader's. Read the shader's copies out of its source rather than writing them a third time.
	var rx := RegEx.new()
	rx.compile("abs\\(fu - ([0-9.]+)\\) < ([0-9.]+) && abs\\(fv - ([0-9.]+)\\) < ([0-9.]+)")
	var shader_rects: Array = []
	for m in rx.search_all(Building.SHADER.code):
		shader_rects.append([m.get_string(1).to_float(), m.get_string(3).to_float(), m.get_string(2).to_float(), m.get_string(4).to_float()])
	var rects_ok := true
	for style in [Building.WindowStyle.PUNCHED, Building.WindowStyle.NARROW]:
		var mine: Array = Building.WINDOW_RECTS[style]
		var hit := false
		for sr: Array in shader_rects:
			if absf(sr[0] - mine[0]) < 1e-4 and absf(sr[1] - mine[1]) < 1e-4 and absf(sr[2] - mine[2]) < 1e-4 and absf(sr[3] - mine[3]) < 1e-4:
				hit = true
		rects_ok = rects_ok and hit
	_check(rects_ok and shader_rects.size() >= 2, "Building.WINDOW_RECTS matches the shader's punched and slot windows (%d found)" % shader_rects.size())
	# The kit must not move anything the building's seeded rolls placed: the same brick block
	# with the kit off and on puts its rooftop units and shop names in exactly the same spots.
	var same := true
	var kit_was := Building.kit_enabled
	for si in [3, 7, 11]:
		var spots: Array = []
		for on in [false, true]:
			Building.kit_enabled = on
			var kb: Building = escape_scene.instantiate()
			kb.seed = si
			kb.lot_size = Vector2(30.0, 30.0)
			kb.min_height = 26.0
			kb.max_height = 40.0
			kb.finish_options.assign([Building.Finish.BRICK])
			kb.position = Vector3(5000.0, 0.0, 5000.0)
			add_child(kb)
			var found: Array = []
			for child in kb.get_children():
				if child is MeshInstance3D and not (child is MultiMeshInstance3D):
					var mi := child as MeshInstance3D
					if str(mi.name).begins_with("Sign") or mi.mesh == PropFactory.model_ac(false) or mi.mesh == PropFactory.model_ac(true):
						found.append(mi.position)
			spots.append(found)
			kb.free()
		same = same and spots[0] == spots[1] and not (spots[0] as Array).is_empty()
	Building.kit_enabled = kit_was
	_check(same, "the facade kit leaves the seeded layout alone (roof units and shop names unmoved)")
	_check(frames_fit, "window frames and cornices stay within the building height")
	_check(looks.size() >= 5, "buildings vary (%d distinct looks)" % looks.size())

	# Same seed, same building.
	var a := Building.new()
	a.seed = 4242
	get_tree().root.add_child(a)
	var c := Building.new()
	c.seed = 4242
	get_tree().root.add_child(c)
	_check(a.footprint == c.footprint and a.height == c.height and a.shape == c.shape, "same seed gives the same building")
	a.queue_free()
	c.queue_free()


func _test_weapons(player: Player) -> void:
	var manager := player.weapon_manager
	_check(manager != null and manager.weapons.size() == 3, "three weapons loaded")
	if manager == null:
		return
	_check(manager.current is AssaultRifle, "starts with the AK-47")
	await _press("weapon_2")
	_check(manager.current is RocketLauncher, "weapon_2 selects the rocket launcher")
	await _press("weapon_3")
	_check(manager.current is GravityGun, "weapon_3 selects the gravity gun")
	await _press("next_weapon")
	_check(manager.current is AssaultRifle, "next_weapon wraps around to the AK-47")

	# AK-47: shoot the crate wall and see a crate move.
	var wall_crate := _nearest_crate(Vector3(-14.0, 2.5, -4.0))
	_check(wall_crate != null, "found a crate in the wall")
	if wall_crate:
		var before := wall_crate.global_position
		player.camera_rig.look_at_point(wall_crate.global_position)
		await _ticks(2)
		Input.action_press("fire")
		await _ticks(45)
		Input.action_release("fire")
		await _ticks(30)
		var moved := wall_crate.global_position.distance_to(before)
		_check(moved > 0.15, "AK-47 bullets shove crates (crate moved %.2f m)" % moved)

	# Rocket launcher: blast the pyramid and see crates fly.
	await _press("weapon_2")
	var pile_crate := _nearest_crate(Vector3(18.0, 2.0, -6.0))
	if pile_crate:
		var pile_before := pile_crate.global_position
		player.camera_rig.look_at_point(pile_crate.global_position)
		await _ticks(2)
		await _press("fire")
		await _ticks(150)
		var flew := pile_crate.global_position.distance_to(pile_before)
		_check(flew > 1.0, "rocket explosion scatters the pyramid (crate moved %.2f m)" % flew)
	# The explosion has to be more than a couple of spheres: a real light flash, layered
	# billboarded fire / smoke / spark particles and a shockwave ring.
	var fx_before := _count_fx()
	WeaponFX.explosion(self, player.global_position + Vector3(0.0, 1.0, 14.0), 8.0)
	await _ticks(2)
	var fx_after := _count_fx()
	_check(fx_after.lights > fx_before.lights, "an explosion lights the scene (%d flash lights)" % fx_after.lights)
	_check(fx_after.particles - fx_before.particles >= 4, "an explosion has layered particles (%d systems)" % (fx_after.particles - fx_before.particles))
	_check(player.camera_rig._shake > 0.0, "a nearby explosion shakes the camera")

	# Gravity gun: grab a crate, hold it up, launch it.
	await _press("weapon_3")
	var gun := manager.current as GravityGun
	var crate := _nearest_crate(Vector3(-14.0, 1.0, 0.0))
	if crate and gun:
		player.global_position = crate.global_position + Vector3(6.0, 0.6, 0.0)
		player.velocity = Vector3.ZERO
		await _ticks(5)
		player.camera_rig.look_at_point(crate.global_position)
		await _ticks(2)
		await _press("fire")
		_check(gun.is_holding(), "gravity gun grabs a crate")
		player.camera_rig.look_at_point(player.global_position + Vector3(-10.0, 1.6, 0.0))
		await _ticks(60)
		var hold_dist := crate.global_position.distance_to(player.global_position)
		_check(gun.is_holding() and hold_dist < gun.hold_distance + 3.0 and crate.global_position.y > 1.0,
			"held crate floats near the player (%.1f m away, %.1f m up)" % [hold_dist, crate.global_position.y])
		# Aim up into open sky so the launched crate cannot hit anything before we measure.
		player.camera_rig.look_at_point(player.global_position + Vector3(0.0, 30.0, -10.0))
		await _ticks(20)
		await _press("fire")
		await _ticks(2)
		_check(not gun.is_holding() and crate.linear_velocity.length() > gun.launch_speed * 0.6,
			"gravity gun launches the crate at %.1f m/s" % crate.linear_velocity.length())


## Counts the explosion effect nodes currently alive in the scene.
func _count_fx() -> Dictionary:
	var lights := 0
	var particles := 0
	for child in get_tree().current_scene.get_children():
		if child is OmniLight3D:
			lights += 1
		elif child is CPUParticles3D:
			particles += 1
	return {"lights": lights, "particles": particles}


func _nearest_crate(near: Vector3) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("physics_prop"):
		var body := node as RigidBody3D
		if body == null:
			continue
		var d := body.global_position.distance_to(near)
		if d < best_dist:
			best_dist = d
			best = body
	return best


func _press(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _run_and_measure_speed(player: CharacterBody3D, ticks: int) -> float:
	var top := 0.0
	for i in ticks:
		await get_tree().physics_frame
		top = maxf(top, player.horizontal_speed())
	return top


func _jump_and_measure(player: CharacterBody3D, ground_y: float) -> float:
	var peak := 0.0
	Input.action_press("jump")
	for i in 240:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y - ground_y)
		if player.velocity.y <= 0.0 and i > 2:
			break
	Input.action_release("jump")
	return peak


func _double_jump_and_measure(player: CharacterBody3D, ground_y: float) -> float:
	var peak := 0.0
	Input.action_press("jump")
	for i in 240:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y - ground_y)
		if player.velocity.y <= 0.0 and i > 2:
			break
	Input.action_release("jump")
	await get_tree().physics_frame
	Input.action_press("jump")
	for i in 240:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y - ground_y)
		if player.velocity.y <= 0.0 and i > 2:
			break
	Input.action_release("jump")
	return peak


func _wait_for_floor(player: CharacterBody3D, max_ticks: int) -> void:
	for i in max_ticks:
		await get_tree().physics_frame
		if player.is_on_floor():
			await _ticks(5)
			return


## Autoloads are looked up at runtime: naming them here would compile this script too early.
func _world_state() -> Node:
	return get_tree().root.get_node("/root/WorldState")


func traffic_cars_for_lights(city: Node) -> Array:
	var out: Array = []
	var traffic: Node = city.get_node_or_null("Traffic")
	if traffic:
		for c in traffic.cars:
			out.append(c)
			if out.size() >= 3:
				break
	return out


## Instances in a building's facade-kit batches (MultiMeshBatch names them Batch_<key>) whose
## node names start with `prefix`.
func _kit_count(b: Node, prefix: String) -> int:
	var n := 0
	for child in b.get_children():
		if child is MultiMeshInstance3D and str(child.name).begins_with(prefix):
			n += (child as MultiMeshInstance3D).multimesh.instance_count
	return n


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	# printerr: unbuffered, so progress is visible even if the run is killed.
	printerr("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE TEST PASSED (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		printerr("SMOKE TEST FAILED: %d of %d checks" % [_failures.size(), _checks])
		get_tree().quit(1)


## A landmark's anchor BY ID. This used to be Landmarks.all()[1] and [3], which quietly tied the
## test to the order of that array: adding a landmark anywhere but the end shifted the indices
## and the test then teleported the player to the wrong place and reported that the pier and the
## crown tower had not been built. The landmark it means is the one it names.
func _landmark_anchor(id: String) -> Vector2:
	for lm in Landmarks.all():
		if lm.id == id:
			return lm.anchor
	_check(false, "landmark '%s' exists" % id)
	return Vector2.ZERO
