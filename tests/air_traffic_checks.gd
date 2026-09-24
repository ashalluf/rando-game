extends RefCounted
## Air traffic checks for tests/smoke_test.gd, run near the end of the city test. Loaded at run
## time (not named there), so it compiles after the autoloads and can name AirTraffic, the
## aircraft, Explosion and Rocket freely. Everything that can be run as maths is: the aircraft
## and AirTraffic are stepped by hand with advance(), minutes of flight in one frame, and only
## the rocket needs real physics frames.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var air: AirTraffic = city.get_node_or_null("AirTraffic") as AirTraffic
	t._check(air != null, "the city has an AirTraffic node")
	if air == null:
		return
	for i in 3:
		await _tree.physics_frame
	t._check(air.routes.has("arrival_south") and air.routes.has("departure_%d_left" % Aircraft.Kind.AIRLINER), "air traffic built its approach and departure routes")
	t._check(air.crafts().size() >= 3, "the sky is populated from the start (%d aircraft)" % air.crafts().size())
	var heli_count := air.helicopters().size()
	t._check(heli_count >= 1, "helicopters are flying at load (%d)" % heli_count)
	# From here the test drives the schedule itself, with the real wanted system quiet: its
	# stars count too (AirTraffic reads the most any "wanted" node says), and the blasts below
	# would be crimes.
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
		if police.has_method("clear"):
			police.call("clear")
	air.set_physics_process(false)
	air.clear_all()
	await _tree.physics_frame
	await _arrival(air)
	await _departure(air)
	await _origin_shift(air, city)
	await _news(air, city)
	await _police(air, city)
	await _rocket(air, city)
	air.clear_all()
	air.forced_stars = -1
	air.set_physics_process(true)
	if police and police_was != null:
		police.set("enabled", police_was)


func _arrival(air: AirTraffic) -> void:
	var macro := air.macro
	var jet := air.spawn_arrival(Aircraft.Kind.AIRLINER, 3000.0, "arrival_south")
	await _tree.physics_frame
	jet.set_physics_process(false)
	var start_y := jet.world_pos.y
	var prev_y := start_y
	var climb := 0.0
	var t := 0.0
	while t < 180.0 and jet.touchdown_world == Vector3.INF:
		jet.advance(1.0 / 30.0)
		t += 1.0 / 30.0
		climb = maxf(climb, jet.world_pos.y - prev_y)
		prev_y = jet.world_pos.y
	var td := jet.touchdown_world
	_t._check(td != Vector3.INF, "an arrival touches down (%.0f s from 3 km out)" % t)
	if td != Vector3.INF:
		var rz: float = macro.runway_zs[macro.arrival_runway]
		var rect := macro.airport_rect
		_t._check(absf(td.z - rz) < 0.5 and td.x > rect.position.x and td.x < rect.end.x and absf(td.y - air.runway_top) < 0.05,
			"it touches down on the runway centre line (%.2f m off it, at x %.0f)" % [absf(td.z - rz), td.x])
		_t._check(start_y - td.y > 100.0 and climb < 0.05, "it descends the whole way in (from %.0f m, never climbing)" % start_y)
	# The roll-out ends in a fade at the runway end, and the jet is gone.
	while t < 260.0 and not jet.done:
		jet.advance(1.0 / 30.0)
		t += 1.0 / 30.0
	_t._check(jet.done, "the arrival rolls out, taxis and fades out at the runway end")
	await _tree.process_frame


func _departure(air: AirTraffic) -> void:
	var jet := air.spawn_departure(Aircraft.Kind.AIRLINER, 0.0, false)
	await _tree.physics_frame
	jet.set_physics_process(false)
	var start := jet.world_pos
	var t := 0.0
	var lifted := -1.0
	while t < 60.0 and not jet.done:
		jet.advance(1.0 / 30.0)
		t += 1.0 / 30.0
		if lifted < 0.0 and jet.phase == AmbientJet.Phase.AIRBORNE:
			lifted = t
	var gone := Vector2(jet.world_pos.x - start.x, jet.world_pos.z - start.z).length()
	_t._check(lifted > 0.0 and jet.world_pos.y > 150.0 and gone > 2000.0,
		"a departure takes off and climbs out (lift-off at %.0f s, %.0f m up and %.0f m out after a minute)" % [lifted, jet.world_pos.y, gone])
	jet.remove()
	await _tree.process_frame


func _origin_shift(air: AirTraffic, city: Node3D) -> void:
	var jet := air.spawn_arrival(Aircraft.Kind.AIRLINER, 1500.0, "arrival_south")
	var heli := air.spawn_helicopter(Helicopter.Role.NEWS, air.player_world() + Vector3(120.0, 90.0, 0.0), "cover")
	await _tree.physics_frame
	jet.set_physics_process(false)
	heli.set_physics_process(false)
	var jet_before := WorldState.to_world(jet.global_position)
	var heli_before := WorldState.to_world(heli.global_position)
	var player := _tree.get_first_node_in_group("player") as Node3D
	var home := player.global_position
	var home_world := WorldState.to_world(home)
	player.global_position = home + Vector3(1400.0, 0.0, 300.0)
	city.recenter()
	var moved := WorldState.to_world(jet.global_position).distance_to(jet_before) + WorldState.to_world(heli.global_position).distance_to(heli_before)
	# And after a tick that re-derives the position from world space.
	jet.advance(0.0)
	heli.advance(0.0)
	var drift := WorldState.to_world(jet.global_position).distance_to(jet_before) + WorldState.to_world(heli.global_position).distance_to(heli_before)
	_t._check(moved < 0.01 and drift < 0.01, "aircraft keep their world positions across an origin shift (%.3f m, %.3f m)" % [moved, drift])
	# Back where he was in the world (the origin has moved under him).
	player.global_position = WorldState.to_local(home_world)
	jet.remove()
	heli.remove()
	await _tree.process_frame


func _step(air: AirTraffic, seconds: float, dt: float = 0.05) -> void:
	var t := 0.0
	while t < seconds:
		air.advance(dt)
		for c in air.crafts():
			c.set_physics_process(false)
			c.advance(dt)
		t += dt


func _news(air: AirTraffic, city: Node3D) -> void:
	air.news_heat = 0.0
	var player := _tree.get_first_node_in_group("player") as Node3D
	var p := air.player_world()
	var heli := air.spawn_helicopter(Helicopter.Role.NEWS, p + Vector3(-450.0, 260.0, 380.0), "cruise")
	await _tree.physics_frame
	_step(air, 1.0)
	_t._check(heli.task == "cruise", "the news helicopter cruises with nothing going on")
	var at := player.global_position + Vector3(25.0, 0.5, 20.0)
	Explosion.blast(player, at, 5.0, 18.0, 0.0)
	var blast := WorldState.to_world(at)
	_step(air, 45.0)
	var off := Vector2(heli.world_pos.x - blast.x, heli.world_pos.z - blast.z).length()
	_t._check(heli.task == "cover" and heli.mode == Helicopter.Mode.ORBIT and off > air.news_orbit_radius * 0.6 and off < air.news_orbit_radius * 1.4,
		"after an explosion the news helicopter comes and circles it (%.0f m out, %.0f m up)" % [off, heli.world_pos.y - air.ground_height(Vector2(blast.x, blast.z))])
	_t._check(heli.world_pos.y > air.obstacle_top(Vector2(heli.world_pos.x, heli.world_pos.z)) + 10.0, "and it flies clear of the buildings under it")
	air.clear_all()
	air.news_heat = 0.0
	await _tree.process_frame


func _police(air: AirTraffic, city: Node3D) -> void:
	# The sighting needs a clear line from the searchlight to him, and the checks before this one
	# leave the player wherever they finished - under a deck, a mast arm or an awning, depending
	# on the suite (it failed with 0 reports in full runs and passed alone). Stand him in the open
	# at the spawn for this stage and put him back after.
	var player := _tree.get_first_node_in_group("player") as Node3D
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var home: Vector3 = ws.to_world(player.global_position)
	var open_local: Vector3 = ws.to_local(Vector3(0.0, 0.0, 0.0))
	open_local.y = city.surface_height_at(open_local) + 1.0
	player.global_position = open_local
	player.set("velocity", Vector3.ZERO)
	# A stand-in for the wanted system: a node in group "wanted" with a plain `stars` and the
	# report_sighting() the real Police has.
	var script := GDScript.new()
	script.source_code = "extends Node\nvar stars: int = 0\nvar reports: int = 0\nfunc report_sighting(_at: Vector3 = Vector3.INF) -> void:\n\treports += 1\n"
	script.reload()
	var wanted := Node.new()
	wanted.set_script(script)
	wanted.name = "WantedStandIn"
	wanted.add_to_group("wanted")
	city.add_child(wanted)
	air.forced_stars = -1
	_step(air, 1.0)
	var chasing := _pursuers(air)
	_t._check(chasing.is_empty(), "no police helicopter chases the player with no stars")
	wanted.set("stars", 3)
	_step(air, 70.0)
	chasing = _pursuers(air)
	var p := air.player_world()
	var near := false
	for h in chasing:
		var r := Vector2(h.world_pos.x - p.x, h.world_pos.z - p.z).length()
		if h.mode == Helicopter.Mode.ORBIT and r < 150.0 and h.searchlight_on:
			near = true
	_t._check(air.stars == 3 and near, "at three stars a police helicopter circles the player with its searchlight on him (%d)" % chasing.size())
	var seen := int(wanted.get("reports"))
	_step(air, 2.0)
	var reports := int(wanted.get("reports")) - seen
	_t._check(reports > 0, "and while its light holds him it reports him to the wanted system (%d reports)" % reports)
	wanted.set("stars", 0)
	_step(air, 4.0)
	var leaving := 0
	for h in chasing:
		if not is_instance_valid(h) or h.done or h.task == "leaving":
			leaving += 1
	_t._check(not chasing.is_empty() and leaving == chasing.size(), "when the stars clear the police helicopters fly off")
	_step(air, 60.0)
	var gone := 0
	for h in chasing:
		if not is_instance_valid(h) or h.done:
			gone += 1
	_t._check(gone == chasing.size(), "and they are gone a minute later")
	wanted.queue_free()
	air.clear_all()
	player.global_position = ws.to_local(home)
	player.set("velocity", Vector3.ZERO)
	await _tree.process_frame


func _pursuers(air: AirTraffic) -> Array[Helicopter]:
	var out: Array[Helicopter] = []
	for h in air.helicopters(Helicopter.Role.POLICE):
		if h.task == "pursuit":
			out.append(h)
	return out


func _rocket(air: AirTraffic, city: Node3D) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	var cam := player.get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at := WorldState.to_world(player.global_position) + fwd * 55.0 + Vector3.UP * 22.0
	var heli := air.spawn_helicopter(Helicopter.Role.POLICE, at, "pursuit")
	heli.set_physics_process(false)
	# The broadphase learns where a body is on the next step.
	for i in 3:
		await _tree.physics_frame
	var rocket := Rocket.new()
	var from := player.global_position + Vector3.UP * 1.6
	var target := heli.global_position + Vector3.UP * 1.3
	rocket.direction = (target - from).normalized()
	rocket.exclude = [player.get_rid()]
	city.add_child(rocket)
	rocket.global_position = from
	var frames := 0
	while frames < 150 and heli.life == AmbientCraft.Life.FLYING:
		await _tree.physics_frame
		frames += 1
	_t._check(heli.life == AmbientCraft.Life.DOWN, "a rocket brings a helicopter down (%d frames)" % frames)
	var t := 0.0
	var lowest := heli.world_pos.y
	while t < 30.0 and heli.life == AmbientCraft.Life.DOWN:
		heli.advance(1.0 / 30.0)
		t += 1.0 / 30.0
		lowest = minf(lowest, heli.world_pos.y)
	var ground := air.ground_height(Vector2(heli.world_pos.x, heli.world_pos.z))
	_t._check(heli.life == AmbientCraft.Life.WRECK and heli.crash_world.y < ground + 25.0,
		"it spins down and explodes where it hits (%.1f s, %.0f m above the ground)" % [t, heli.crash_world.y - ground])
	_t._check(air._police_respawn_left > 0.0, "and a replacement is scheduled")
