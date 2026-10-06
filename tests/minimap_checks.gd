extends RefCounted
## The map checks for tests/smoke_test.gd: MapData's basin records, the GPS route along the street
## grid (GpsRoute: every stretch it drives is open, it goes round MacArthur Park's closed roads,
## both ends on the road nearest them), the full-screen map (WorldMap: the `map` action, pausing,
## zoom, a click setting and clearing the waypoint, the beacon in the world, the route kept and
## recomputed), and the minimap drawing it all (MapPainter) without a script error. Loaded at run
## time, so it compiles after the autoloads.

var _t: Node
var _tree: SceneTree


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var plan: CityPlan = city.plan
	_input_map()
	_map_data(plan)
	_routes(plan)
	_shields(plan)
	await _world_map(city, plan)


func _input_map() -> void:
	_check(InputMap.has_action("map"), "the map has its input action")
	var keys := false
	var back := false
	for e in InputMap.action_get_events("map"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_M:
			keys = true
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_BACK:
			back = true
	_check(keys and back, "the map opens on M and on the pad's Back")
	var clash := ""
	for action in InputMap.get_actions():
		if action == "map" or str(action).begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_BACK:
				clash += " " + str(action)
			if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_M:
				clash += " " + str(action)
	_check(clash == "", "no other action on M or Back%s" % clash)


func _map_data(plan: CityPlan) -> void:
	var data := MapData.of(plan)
	var t0 := Time.get_ticks_msec()
	while not data.warm(200000):
		pass
	var ms := Time.get_ticks_msec() - t0
	var kinds := {}
	for b: Dictionary in data.blocks:
		kinds[int(b.kind)] = true
	_check(data.ready and data.blocks.size() > 1000 and data.roads.size() > data.blocks.size(),
		"the basin's map is built (%d blocks, %d roads, %d ms)" % [data.blocks.size(), data.roads.size(), ms])
	_check(kinds.has(MapData.Kind.DISTRICT) and kinds.has(MapData.Kind.PARK) and kinds.has(MapData.Kind.AIRPORT) and kinds.has(MapData.Kind.BEACH),
		"the map has city, park, airport and beach ground")
	_check(data.district_labels.size() >= 5, "districts are named on the map (%d labels)" % data.district_labels.size())
	# A small view finds its blocks through the index: every block overlapping it, and no other.
	var view := Rect2(2500.0, 0.0, 600.0, 600.0)
	var found := 0
	var missed := 0
	var listed := {}
	for i in data.indices_in(view):
		listed[i] = true
	for i in data.blocks.size():
		if (data.blocks[i].owned as Rect2).intersects(view):
			found += 1
			if not listed.has(i):
				missed += 1
	_check(found > 10 and missed == 0, "the map's cell index finds every block in a view (%d, missed %d)" % [found, missed])
	# No closed road is drawn as a street: MacArthur Park's inner roads and the river's dead ends.
	var bad := 0
	for rd: Dictionary in data.roads:
		var r: Rect2 = rd.rect
		var along := r.get_center().y if int(rd.axis) == CityPlan.AXIS_X else r.get_center().x
		if not plan.road_open(int(rd.axis), int(rd.index), along):
			bad += 1
			var school := Schools.enabled and Schools.road_closed(plan, int(rd.axis), int(rd.index), along)
			var river: bool = plan.macro.river != null and not plan.macro.river.road_open(plan, int(rd.axis), int(rd.index), along)
			print("CLOSED ROAD ON THE MAP: axis %d index %d along %.1f (school %s, river %s)" % [rd.axis, rd.index, along, school, river])
	if not Schools.late_closed.is_empty():
		print("SCHOOLS CLOSED LATE: %s" % [Schools.late_closed])
	_check(bad == 0, "the map draws no closed road (%d)" % bad)


func _routes(plan: CityPlan) -> void:
	var trips := [[Vector2(2800, 100), Vector2(-300, 1200)], [Vector2(300, 300), Vector2(4200, 2400)],
		[Vector2(2800, 100), Vector2(3000, 5600)]]
	# Across MacArthur Park (its inner roads are closed; only Wilshire runs through).
	var park := plan.site_by_id("macarthur_park")
	if not park.is_empty():
		var w := plan.road_pos(CityPlan.AXIS_X, int(park.ix0)) - 60.0
		var e := plan.road_pos(CityPlan.AXIS_X, int(park.ix1)) + 60.0
		var z := (plan.road_pos(CityPlan.AXIS_Z, int(park.iz0)) + plan.road_pos(CityPlan.AXIS_Z, int(park.iz0) + 1)) * 0.5
		trips.append([Vector2(w, z), Vector2(e, z)])
	for trip: Array in trips:
		var a: Vector2 = trip[0]
		var b: Vector2 = trip[1]
		var t0 := Time.get_ticks_usec()
		var r := GpsRoute.new(plan, a, b)
		while not r.step(100000):
			pass
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var label := "GPS %s -> %s" % [a, b]
		_check(r.ok and r.points.size() >= 3, "%s finds a route (%d points, %.0f m, %.0f ms)" % [label, r.points.size(), r.length, ms])
		if not r.ok:
			continue
		_check(r.points[0] == a and r.points[r.points.size() - 1] == b and r.length >= a.distance_to(b) - 1.0,
			"%s runs from the player to the waypoint" % label)
		# Every stretch between its first and last road points runs along an open road.
		var closed := 0
		for i in range(1, r.points.size() - 2):
			var p := r.points[i]
			var q := r.points[i + 1]
			var axis_aligned := absf(p.x - q.x) < 0.01 or absf(p.y - q.y) < 0.01
			if not axis_aligned:
				closed += 1
				continue
			var m := (p + q) * 0.5
			if absf(p.x - q.x) < 0.01:
				if not plan.road_open_at(CityPlan.AXIS_X, m.x, m.y):
					closed += 1
			elif not plan.road_open_at(CityPlan.AXIS_Z, m.y, m.x):
				closed += 1
		_check(closed == 0, "%s keeps to open streets (%d off)" % [label, closed])


func _shields(plan: CityPlan) -> void:
	var numbers := {}
	for route: Dictionary in plan.macro.freeway.routes:
		numbers[FreewayKit.route_number(str(route.name))] = true
	var own := true
	for n: int in numbers:
		if not (FreewayKit.ROUTE_NUMBERS.values() as Array).has(n):
			own = false
	_check(own and numbers.size() >= 3, "every freeway's shield carries the game's own number %s" % str(numbers.keys()))


func _world_map(city: Node3D, plan: CityPlan) -> void:
	var wm: WorldMap = _tree.get_first_node_in_group("world_map")
	_check(wm != null, "the full-screen map is in the HUD")
	if wm == null:
		return
	var player: Node3D = _tree.get_first_node_in_group("player")
	var ws := _tree.root.get_node("/root/WorldState")
	var here: Vector3 = ws.to_world(player.global_position)
	var home := Vector2(here.x, here.z)
	# Opening pauses the game; closing gives it back.
	wm.open()
	await _tree.process_frame
	_check(wm.is_open() and _tree.paused, "the map opens over a paused game")
	var before := wm.ppm
	wm.call("_zoom_at", wm.get_viewport().get_visible_rect().size * 0.5, 2.0)
	_check(wm.ppm > before * 1.9, "the map zooms")
	# A click sets the waypoint where it lands; a click on it clears it.
	var sp := wm.get_viewport().get_visible_rect().size * 0.5 + Vector2(120, 80)
	wm.call("_click", sp)
	var wp := wm.waypoint_xz()
	_check(wm.has_waypoint() and wp.distance_to(wm.screen_to_world(sp)) < 0.5, "a click on the map sets the waypoint there")
	wm.call("_click", sp)
	_check(not wm.has_waypoint(), "a click on the waypoint clears it")
	await _tree.process_frame
	wm.close()
	await _tree.process_frame
	_check(not wm.is_open() and not _tree.paused, "closing the map unpauses the game")
	# A waypoint a few blocks off: the route, the beacon over it in the world, the minimap drawing.
	var target := home + Vector2(420.0, -380.0)
	wm.set_waypoint(target)
	wm.finish_route()
	_check(wm.has_route() and wm.route_points()[0].distance_to(home) < 2.0, "a waypoint gets a GPS route from the player (%.0f m)" % (wm.route().length if wm.route() else 0.0))
	var beacon: Node3D = wm.get_node_or_null("WaypointBeacon")
	var bw: Vector3 = ws.to_world(beacon.global_position) if beacon else Vector3.INF
	_check(beacon != null and beacon.visible and Vector2(bw.x, bw.z).distance_to(target) < 0.5, "the waypoint's beacon stands at it in the world")
	var minimap: Control = city.get_node("DebugHud/MinimapFrame/Minimap")
	minimap.queue_redraw()
	await _tree.process_frame
	await _tree.process_frame
	# Off the route: the player somewhere else gets a new one from there.
	var old: GpsRoute = wm.route()
	wm.set("_route_t", 0.0)
	var away := home + Vector2(-250.0, 260.0)
	var old_pos := player.global_position
	player.global_position = ws.to_local(Vector3(away.x, here.y, away.y))
	wm.call("_update_route", 0.0)
	wm.finish_route()
	_check(wm.route() != old and wm.route() != null and wm.route().points[0].distance_to(away) < 1.0, "leaving the route plans a new one from where the player is")
	player.global_position = old_pos
	# Arriving clears it.
	wm.set_waypoint(home + Vector2(3.0, 0.0))
	wm.call("_update_route", 0.0)
	_check(not wm.has_waypoint() and not beacon.visible, "arriving at the waypoint clears it")
