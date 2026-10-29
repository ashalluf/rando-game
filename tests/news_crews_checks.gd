extends RefCounted
## TV news crews (NewsCrews, NewsVan, NewsCrew, NewsKit) for tests/smoke_test.gd. Loaded at run
## time (not named there), so it compiles after the autoloads. Checks: the stations are invented;
## the kit's meshes build inside a triangle budget; a van of each uplink builds as its model with
## its roof gear, raises it on scene (the mast to ~10 m, the dish up off the roof) and stows it
## before it drives; the live-shot layout is pure and sane (the reporter on the pavement about
## `report_distance` off the scene, the camera beyond them facing back, the tape between the
## reporter and the scene); a blast opens ONE story after the desk's delay and tells the news
## helicopter; a van staged at a story has its crew out on air behind the tape with the light
## stand; a van sent from off the street drives the lanes and pulls up near the story; on a wrap
## the crew boards and the van leaves and is pooled; a crew member knocked down is a body like
## anyone's and wraps the story.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node
var _nc: NewsCrews
var _made: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	_nc = city.get_node_or_null("NewsCrews") as NewsCrews
	_check(_nc != null, "the city has a NewsCrews node")
	if _nc == null:
		return
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = _ws.to_world(player.global_position)
	_nc.enabled = true
	var scan_was := _nc.scan_interval
	_nc.scan_interval = 1e9
	_nc._scan_t = 1e9
	_nc.clear()
	_stations()
	_kit()
	await _vans(player)
	_layout()
	_blast_story(player)
	_nc.clear()
	_traffic.staged = true
	_clear_traffic()
	await _on_air(player)
	_nc.clear()
	await _send(player)
	_nc.clear()
	for c in _made:
		if is_instance_valid(c):
			(c as Node).queue_free()
	_made.clear()
	_traffic.staged = false
	_nc.enabled = false
	_nc.scan_interval = scan_was
	_nc._scan_t = 0.0
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(5)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _clear_traffic() -> void:
	for c in _traffic.cars.duplicate():
		if is_instance_valid(c):
			_traffic._retire(c)
	_traffic.cars.clear()


func _road_point(along: float, lat: float) -> Vector3:
	var x := _plan.road_pos(CityPlan.AXIS_X, 0) + lat
	var z := _plan.road_pos(CityPlan.AXIS_Z, 0) + along
	return Vector3(x, _plan.height_at(Vector2(x, z)) + CityChunk.ROAD_TOP, z)


func _stations() -> void:
	# Real Los Angeles broadcasters' names and networks: none may appear.
	var real := ["KTLA", "KABC", "KNBC", "KCBS", "KTTV", "KCAL", "KMEX", "KVEA", "KCOP", "KTLA",
		"ABC", "NBC", "CBS", "FOX", "CNN", "UNIVISION", "TELEMUNDO", "MSNBC", "PBS", "KCET"]
	var ok := NewsKit.STATIONS.size() >= 3
	var names := {}
	for s: Dictionary in NewsKit.STATIONS:
		var words := (String(s.name) + " " + String(s.tag) + " " + String(s.slogan)).to_upper()
		for r: String in real:
			for w in words.split(" ", false):
				ok = ok and w != r
		names[s.name] = true
		ok = ok and (s.uplink == "dish" or s.uplink == "mast")
	_check(ok and names.size() == NewsKit.STATIONS.size(), "the news stations are invented, each with its own name and an uplink (%d)" % NewsKit.STATIONS.size())


func _tris(m: Mesh) -> int:
	var n := 0
	if m == null:
		return 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		n += (idx.size() if idx.size() > 0 else v.size()) / 3
	return n


func _kit() -> void:
	var parts := {"rack": NewsKit.rack_mesh(3.2, 1.5), "mast base": NewsKit.mast_base_mesh(),
		"mast section": NewsKit.mast_section_mesh(0), "mast head": NewsKit.mast_head_mesh(),
		"coil": NewsKit.coil_mesh(), "dish base": NewsKit.dish_base_mesh(), "dish": NewsKit.dish_mesh(),
		"camera": NewsKit.camera_mesh(), "mic": NewsKit.mic_mesh(0), "light stand": NewsKit.light_stand_mesh(),
		"tape post": NewsKit.post_mesh()}
	var total := 0
	var empty: Array = []
	for k: String in parts:
		var n := _tris(parts[k])
		total += n
		if n <= 0:
			empty.append(k)
	_check(empty.is_empty() and total < 40000, "every piece of the news kit builds, %d triangles in all (empty: %s)" % [total, str(empty)])
	var tops: Array[Vector3] = [Vector3(0, 1, 0), Vector3(4, 1, 0), Vector3(4, 1, 5)]
	var tape := NewsKit.tape_mesh(tops)
	_check(_tris(tape) > 0 and tape.surface_get_material(0) is ShaderMaterial, "the caution tape is a strip on its own shader (%d triangles)" % _tris(tape))


func _vans(player: Player) -> void:
	player.global_position = _ws.to_local(_road_point(-60.0, 0.0)) + Vector3.UP * 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var dish := -1
	var mast := -1
	for i in NewsKit.STATIONS.size():
		if NewsKit.station(i).uplink == "dish" and dish < 0:
			dish = i
		if NewsKit.station(i).uplink == "mast" and mast < 0:
			mast = i
	var k := 0
	for si: int in [dish, mast]:
		if si < 0:
			continue
		var t0 := Time.get_ticks_usec()
		var van := NewsVan.make(si, rng)
		van.position = _ws.to_local(_road_point(30.0 + 14.0 * k, 0.0)) + Vector3.UP * van.road_lift()
		_city.add_child(van)
		_made.append(van)
		k += 1
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var gear := van.get_node_or_null("NewsGear")
		_check(van._has_model and gear != null and van.cabin_seats() > 0,
				"a %s van builds as its model with its roof gear and the crew in the cab (model %s)" % [van.uplink(), van._has_model])
		_check(ms < 400.0, "a news van builds inside the budget (%.1f ms)" % ms)
		var top0 := _gear_top(van)
		van.mode = NewsVan.Mode.ON_SCENE
		for i in 40:
			van._process(1.0)
		var top1 := _gear_top(van)
		_check(van.gear_up() and top1 > top0 + (7.0 if van.uplink() == "mast" else 0.25),
				"on scene the %s goes up (top %.2f m -> %.2f m over the van)" % [van.uplink(), top0, top1])
		van.mode = NewsVan.Mode.LEAVING
		for i in 40:
			van._process(1.0)
		_check(van.gear_down() and absf(_gear_top(van) - top0) < 0.05, "leaving it comes down again before it drives (%.2f m)" % _gear_top(van))
		await _tree.process_frame


## The highest point of the van's roof gear over the van's origin (m).
func _gear_top(van: NewsVan) -> float:
	var top := -INF
	var inv := van.global_transform.affine_inverse()
	var stack: Array = [van.get_node("NewsGear")]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var aabb: AABB = (n as MeshInstance3D).get_aabb()
			var xf := inv * (n as MeshInstance3D).global_transform
			for c in 8:
				top = maxf(top, (xf * aabb.get_endpoint(c)).y)
	return top


func _layout() -> void:
	var scene := Vector2(_plan.road_pos(CityPlan.AXIS_X, 0) + 3.0, _plan.road_pos(CityPlan.AXIS_Z, 0) + 70.0)
	var a := _nc.layout(_plan, scene, _nc.report_distance)
	var b := _nc.layout(_plan, scene, _nc.report_distance)
	_check(not a.is_empty() and str(a) == str(b), "the live shot's layout is worked out the same way twice")
	if a.is_empty():
		return
	var rep: Vector2 = a.reporter
	var cam: Vector2 = a.camera
	var d_rep := rep.distance_to(scene)
	_check(d_rep > _nc.report_distance * 0.6 and d_rep < _nc.report_distance * 1.3,
			"the reporter stands about %.0f m off the scene (%.1f m)" % [_nc.report_distance, d_rep])
	# On the pavement: off the carriageway of the road it is laid along.
	var axis := int(a.axis)
	var road := _plan.road_pos(axis, int(a.index))
	var width := _plan.road_width(axis, int(a.index))
	var across := rep.x if axis == CityPlan.AXIS_X else rep.y
	_check(absf(across - road) > width * 0.5 and absf(across - road) < width * 0.5 + _plan.sidewalk_width,
			"the reporter is on the pavement (%.1f m off the road's centre, half width %.1f)" % [absf(across - road), width * 0.5])
	_check(cam.distance_to(scene) > d_rep and cam.distance_to(rep) > 2.0 and cam.distance_to(rep) < 5.0,
			"the camera stands beyond the reporter, so the scene is behind them in the shot")
	var tape: Array = a.tape
	var t0: Vector2 = tape[0]
	_check(tape.size() >= 3 and t0.distance_to(scene) < d_rep, "the tape runs between the reporter and the scene")


func _blast_story(player: Player) -> void:
	_nc.clear()
	_nc._ensure_refs()
	var at := _road_point(80.0, 0.0)
	player.global_position = _ws.to_local(_road_point(20.0, 0.0)) + Vector3.UP
	var count := Explosion.blast_count
	Explosion.blast_count = count + 1
	Explosion.last_blast_world = at
	_nc._scan(1.0)
	_check(_nc.stories.size() == 1 and _nc.stories[0].kind == NewsCrews.KIND_BLAST and _nc.vans.is_empty(),
			"a blast opens a story, and no van goes before the desk hears of it (%d stories, %d vans)" % [_nc.stories.size(), _nc.vans.size()])
	Explosion.blast_count = count + 2
	Explosion.last_blast_world = at + Vector3(10.0, 0.0, 5.0)
	_nc._scan(1.0)
	_check(_nc.stories.size() == 1, "a second blast beside it is the same story")
	var air := _city.get_node_or_null("AirTraffic")
	if air:
		var f: Vector3 = air.get("news_focus")
		_check(f != Vector3.INF and Vector2(f.x - at.x, f.z - at.z).length() < 20.0, "the news helicopter is told to cover it")


func _on_air(player: Player) -> void:
	var at := _road_point(70.0, 3.0)
	player.global_position = _ws.to_local(_road_point(-20.0, -8.0)) + Vector3.UP
	_city.update_streaming(true)
	await _ticks(10)
	var s := _nc.open_story(NewsCrews.KIND_BLAST, at)
	var van := _nc.stage(s)
	_check(van != null, "a van can be staged on scene at a story")
	if van == null:
		return
	await _ticks(20)
	var rep: NewsCrew = null
	var cam: NewsCrew = null
	for c in _nc.crews:
		if is_instance_valid(c) and c.van == van:
			if c.role == NewsCrew.Role.REPORTER:
				rep = c
			else:
				cam = c
	_check(rep != null and cam != null, "its reporter and camera operator are out")
	if rep == null or cam == null:
		return
	_check(rep.task == NewsCrew.Task.WORK and cam.task == NewsCrew.Task.WORK and rep.live,
			"both are in place and the reporter is on air")
	var rep_l: Vector3 = _ws.to_local(Vector3(s.layout.reporter.x, 0.0, s.layout.reporter.y))
	var dr := Vector2(rep.global_position.x - rep_l.x, rep.global_position.z - rep_l.z).length()
	_check(dr < 1.5, "the reporter stands on the live-shot spot (%.2f m off)" % dr)
	var holder: Node = _nc.get_node_or_null("NewsScene%d" % int(s.id))
	_check(holder != null and holder.get_node_or_null("Tape") != null and holder.get_node_or_null("LightStand") != null,
			"the tape and the light stand are up")
	_check(van.gear_up() and van.lights_running(), "the uplink is up and the hazards run")
	# Wrap: the crew walk back, board, and the van leaves with its gear down.
	s.air_for = 0.0
	_nc._upkeep(0.5)
	var boarded := false
	for i in 60 * 30:
		await _tree.physics_frame
		if i % 30 == 0:
			_nc._upkeep(0.5)
		if van.mode == NewsVan.Mode.LEAVING:
			boarded = true
			break
	if not boarded:
		for c in _nc.crews:
			if is_instance_valid(c):
				print("NEWS wrap: crew role %d task %d at %s door %s stuck %.1f van %s" % [c.role, c.task, str(c.global_position), str(c._door()), c._stuck_t, str(van.global_position)])
	_check(boarded and _nc.crews.is_empty() and not is_instance_valid(holder),
			"on a wrap the crew boards and the scene is cleared (%s)" % boarded)
	# Out of sight it goes back to the pool.
	await _ticks(2)
	van.unseen_time = 10.0
	var pool_was: int = _nc._pool.size()
	var far := player.global_position + Vector3(0.0, 0.0, _nc.despawn_distance + 50.0)
	van.global_position = far
	_nc._upkeep(0.5)
	_check(not _nc.vans.has(van) and (_nc._pool.size() > pool_was or not is_instance_valid(van) or van.is_queued_for_deletion()),
			"a van gone out of range is retired to the pool")


func _send(player: Player) -> void:
	var at := _road_point(70.0, 3.0)
	player.global_position = _ws.to_local(_road_point(-20.0, -8.0)) + Vector3.UP
	_city.update_streaming(true)
	await _ticks(5)
	var smin := _nc.spawn_min
	var smax := _nc.spawn_max
	_nc.spawn_min = 70.0
	_nc.spawn_max = 100.0
	var s := _nc.open_story(NewsCrews.KIND_BLAST, at)
	var van := _nc.send(s)
	_nc.spawn_min = smin
	_nc.spawn_max = smax
	_check(van != null and van.is_traffic() and van.mode == NewsVan.Mode.DRIVE, "a van can be sent along a street out of sight")
	if van == null:
		return
	var arrived := false
	var moved := 0.0
	var last := van.global_position
	for i in 60 * 80:
		await _tree.physics_frame
		moved += van.global_position.distance_to(last)
		last = van.global_position
		if van.mode == NewsVan.Mode.ON_SCENE:
			arrived = true
			break
		if OS.get_environment("NEWS_DEBUG") == "1" and i % 60 == 0:
			var wp: Vector3 = _ws.to_world(van.global_position)
			print("NEWSDBG t%d at %.0f,%.0f road %s speed %.1f dest %s nodes %s" % [i, wp.x, wp.z, str([van.traffic.axis, van.traffic.index, van.traffic.dir]), van.traffic_speed, str(van._dest), str(van._nodes)])
	var at_l: Vector3 = _ws.to_local(at)
	var d := Vector2(van.global_position.x - at_l.x, van.global_position.z - at_l.z).length()
	_check(arrived and d < 60.0, "it drives the lanes to the story and pulls up near it (%.1f m off, drove %.0f m, %s)" % [d, moved, arrived])
	if not arrived:
		return
	await _ticks(20)
	var crew: NewsCrew = null
	for c in _nc.crews:
		if is_instance_valid(c) and c.van == van:
			crew = c
	_check(crew != null, "its crew gets out")
	if crew == null:
		return
	var parent := crew.get_parent()
	var dolls_before := parent.get_children().filter(func(n: Node) -> bool: return n is Ragdoll).size()
	crew.knock(Vector3(0.0, 2.0, 4.0))
	await _ticks(2)
	var dolls := parent.get_children().filter(func(n: Node) -> bool: return n is Ragdoll).size()
	_check(dolls > dolls_before and not _nc.crews.has(crew), "a crew member knocked down is a body like anyone's (%d -> %d bodies)" % [dolls_before, dolls])
	_check(bool(s.get("wrap", false)), "and the story wraps: the rest pack up")
