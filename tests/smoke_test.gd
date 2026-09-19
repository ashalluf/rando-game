extends SceneTree
## Headless smoke test. Loads the main level, drives the player with simulated
## input and checks that movement and jumping behave. Exit code 0 = pass.
## Run:  godot --headless --path . -s res://tests/smoke_test.gd

const LEVEL_PATH := "res://scenes/levels/test_box.tscn"

var _failures: PackedStringArray = []
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load(LEVEL_PATH)
	_check(packed != null, "level scene loads")
	if packed == null:
		_finish()
		return
	var level := packed.instantiate()
	root.add_child(level)
	_check(root.get_node_or_null("PhysicsBudget") != null, "PhysicsBudget autoload present")

	await _ticks(30)
	var player := get_first_node_in_group("player") as CharacterBody3D
	_check(player != null, "player found in group 'player'")
	if player == null:
		_finish()
		return
	_check(player.is_on_floor(), "player stands on the ground after settling")
	var props := get_nodes_in_group("physics_prop").size()
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
	await process_frame
	await _test_city()
	_finish()


func _test_city() -> void:
	var packed: PackedScene = load("res://scenes/levels/city.tscn")
	_check(packed != null, "city scene loads")
	if packed == null:
		return
	# Untyped on purpose: naming CityStreamer here would compile it before the autoloads exist.
	var city: Node3D = packed.instantiate()
	root.add_child(city)
	await _ticks(30)
	var plan: CityPlan = city.plan
	var lod_r: int = city.lod_radius_blocks
	var load_r: int = city.load_radius_blocks
	var counts: Vector2i = city.chunk_counts()
	_check(counts.x == (2 * load_r + 1) * (2 * load_r + 1), "%d full-detail chunks around the player" % counts.x)
	_check(counts.y == (2 * lod_r + 1) * (2 * lod_r + 1) - counts.x, "%d far LOD chunks" % counts.y)
	_check(city.building_count() >= 100, "city has buildings (%d)" % city.building_count())
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
	var player := get_first_node_in_group("player") as CharacterBody3D
	_check(player != null and player.is_on_floor(), "player stands at the center intersection")
	var cans := 0
	for node in get_nodes_in_group("physics_prop"):
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
		_check(get_nodes_in_group("debris").size() >= 3, "broken lamp drops debris")

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
		_check(macro.zone_at(Vector2.ZERO) == MacroMap.Zone.CITY and macro.height_at(Vector2.ZERO) == 0.0, "origin is flat city")
		_check(macro.zone_at(Vector2(-2500.0, 0.0)) == MacroMap.Zone.OCEAN, "far west is ocean")
		_check(macro.zone_at(Vector2(macro.coast_x(0.0) + 30.0, 0.0)) == MacroMap.Zone.BEACH, "just inland of the coast is beach")
		_check(macro.zone_at(Vector2(0.0, -1600.0)) == MacroMap.Zone.HILLS and macro.height_at(Vector2(0.0, -1600.0)) > 80.0, "far north is hills (%.0f m)" % macro.height_at(Vector2(0.0, -1600.0)))
		_check(macro.district_at(macro.downtown_center) == CityPlan.District.DOWNTOWN, "downtown is where the map says")
		# Stand on the beach: sand, palms, no buildings.
		var beach := Vector3(macro.coast_x(0.0) + 30.0, 2.0, 0.0)
		player.global_position = _world_state().to_local(beach)
		city.update_streaming(true)
		var beach_key: Vector2i = plan.block_index_at(Vector2(beach.x, beach.z))
		var beach_chunk: Node3D = city.chunks.get(beach_key)
		_check(beach_chunk != null and beach_chunk.zone == MacroMap.Zone.BEACH and beach_chunk.building_count == 0 and beach_chunk.has_node("Batch_palm_trunk"), "beach chunk has palms and no buildings")
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

	# Landmarks: far versions always exist; the detailed one appears when its chunk is loaded.
	if macro:
		_check(city.has_node("FarLandmark_sign") and city.has_node("FarLandmark_pier") and city.has_node("FarLandmark_observatory"), "far versions of the sign, pier and observatory exist")
		var pier_anchor: Vector2 = Landmarks.all()[1].anchor
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
		var crown: Vector2 = Landmarks.all()[3].anchor
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
		var port := Vector2(800.0, 1150.0)
		player.global_position = _world_state().to_local(Vector3(port.x, 2.0, port.y))
		city.update_streaming(true)
		var port_chunk: Node3D = city.chunks.get(plan.block_index_at(port))
		_check(port_chunk != null and port_chunk.zone == MacroMap.Zone.PORT and port_chunk.has_node("Batch_container"), "port chunk has container stacks")

	# Same seed, same plan.
	var a := CityPlan.new()
	a.seed = 777
	var b := CityPlan.new()
	b.seed = 777
	_check(a.road_pos(0, 5) == b.road_pos(0, 5) and a.road_pos(1, -4) == b.road_pos(1, -4) and a.block(3, -2).rect == b.block(3, -2).rect and a.block(3, -2).kind == b.block(3, -2).kind and a.intersection(2, 2).kind == b.intersection(2, 2).kind, "same seed gives the same city plan")
	city.queue_free()
	_world_state().reset()


func _test_buildings() -> void:
	var buildings := get_nodes_in_group("building")
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
	_check(looks.size() >= 5, "buildings vary (%d distinct looks)" % looks.size())

	# Same seed, same building.
	var a := Building.new()
	a.seed = 4242
	root.add_child(a)
	var c := Building.new()
	c.seed = 4242
	root.add_child(c)
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


func _nearest_crate(near: Vector3) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_dist := INF
	for node in get_nodes_in_group("physics_prop"):
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
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _run_and_measure_speed(player: CharacterBody3D, ticks: int) -> float:
	var top := 0.0
	for i in ticks:
		await physics_frame
		top = maxf(top, player.horizontal_speed())
	return top


func _jump_and_measure(player: CharacterBody3D, ground_y: float) -> float:
	var peak := 0.0
	Input.action_press("jump")
	for i in 240:
		await physics_frame
		peak = maxf(peak, player.global_position.y - ground_y)
		if player.velocity.y <= 0.0 and i > 2:
			break
	Input.action_release("jump")
	return peak


func _double_jump_and_measure(player: CharacterBody3D, ground_y: float) -> float:
	var peak := 0.0
	Input.action_press("jump")
	for i in 240:
		await physics_frame
		peak = maxf(peak, player.global_position.y - ground_y)
		if player.velocity.y <= 0.0 and i > 2:
			break
	Input.action_release("jump")
	await physics_frame
	Input.action_press("jump")
	for i in 240:
		await physics_frame
		peak = maxf(peak, player.global_position.y - ground_y)
		if player.velocity.y <= 0.0 and i > 2:
			break
	Input.action_release("jump")
	return peak


func _wait_for_floor(player: CharacterBody3D, max_ticks: int) -> void:
	for i in max_ticks:
		await physics_frame
		if player.is_on_floor():
			await _ticks(5)
			return


## Autoloads are looked up at runtime: naming them here would compile this script too early.
func _world_state() -> Node:
	return root.get_node("/root/WorldState")


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE TEST PASSED (%d checks)" % _checks)
		quit(0)
	else:
		printerr("SMOKE TEST FAILED: %d of %d checks" % [_failures.size(), _checks])
		quit(1)
