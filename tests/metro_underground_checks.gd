extends RefCounted
## The Coral Line's underground station (MetroStation, MetroBuild, MetroRider; LightRail's spread,
## LightRailKit's hand-over, LightRailSystem's tunnel trains, the player's fall-through rule) for
## tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. Stages everything
## it needs: the player at the station's street (streaming round it), the clock held and set; puts
## them back at the end.
##
## Checks: the plan (the frame, the tracks spread round the wider island and back, the levels
## room for a train and for people, the stairs' slopes); the streamed chunk builds the station
## (its meshes, collision, zone, riders) and the old kiosks are gone; the road is cut over both
## stairs and the ground under every place you walk is the station's (rays); `shelters()` holds
## inside and not outside; the player stood on the platform stays there (not lifted out by the
## fall-through rule, not thrown out of the ground box); the trains are drawn in the tunnel with
## the player down here and not from the street; the riders wait at the platform's height; the
## A/B builds the old kiosks; and nothing else in the chunk moves with the station on or off.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var plan: CityPlan = city.plan
	var line := LightRail.of(plan)
	_check(line != null and MetroStation.enabled, "the line resolves with the underground station on")
	if line == null or not MetroStation.enabled:
		return
	var f := MetroStation.frame(line)
	_check(not f.is_empty() and int(line.stations[0].mode) == LightRail.Mode.TUNNEL, "the line's first station is the underground one")
	if f.is_empty():
		return
	_plan(line, f)
	await _built(city, plan, line, f)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _plan(line: LightRail, f: Dictionary) -> void:
	var s0 := float(f.s)
	var want := MetroStation.PLATFORM_WIDTH * 0.5 + LightRail.PLATFORM_GAP + LightRail.CAR_HALF_WIDTH
	_check(absf(float(line.sample(s0).half) - want) < 0.01 and float(line.stations[0].width) == MetroStation.PLATFORM_WIDTH,
		"the tracks spread round the 7 m island (%.2f m from the centre)" % float(line.sample(s0).half))
	var far_half := float(line.sample(s0 + MetroStation.TUNNEL_U - 4.0).half)
	_check(far_half < 2.6, "and close up again inside the drawn tunnel (%.2f m)" % far_half)
	var car_top := 3.9
	_check(MetroStation.PLAT_CEIL - float(f.rail) > car_top + 1.4 and MetroStation.CONC_CEIL - MetroStation.CONC_FLOOR > 3.5,
		"room for a train and its wire under the concourse, a high concourse (%.1f m, %.1f m)" % [MetroStation.PLAT_CEIL - float(f.rail), MetroStation.CONC_CEIL - MetroStation.CONC_FLOOR])
	var stair_slope := (0.16 - MetroStation.CONC_FLOOR) / MetroStation.RUN
	var bank_slope := (MetroStation.CONC_FLOOR - float(f.plat)) / (MetroStation.BANK_U * 2.0 - 0.6)
	_check(stair_slope < 0.62 and bank_slope < 0.62, "both flights are walkable slopes (%.2f, %.2f)" % [stair_slope, bank_slope])
	_check(float(f.s) - MetroStation.MOUTH_U > 0.0, "both kiosks stand on the line")
	# shelters(): needs a registered station, so the pure frame is tested through a temporary one.
	MetroStation.register(f)
	var inside := MetroStation.to_world(f, Vector3(0.0, float(f.plat) + 1.0, 2.0))
	var conc := MetroStation.to_world(f, Vector3(20.0, MetroStation.CONC_FLOOR + 1.0, 4.0))
	var stair := MetroStation.to_world(f, Vector3(-25.0, -2.0, -0.6))
	var street := MetroStation.to_world(f, Vector3(0.0, 5.0, 0.0))
	var aside := MetroStation.to_world(f, Vector3(0.0, -5.0, 30.0))
	_check(MetroStation.shelters(inside) and MetroStation.shelters(conc) and MetroStation.shelters(stair),
		"the platform, the concourse and the stairwells shelter")
	_check(not MetroStation.shelters(street) and not MetroStation.shelters(aside), "the street above and the ground beside do not")
	MetroStation.unregister(f)


func _built(city: Node3D, plan: CityPlan, line: LightRail, f: Dictionary) -> void:
	var player := _tree.get_first_node_in_group("player") as CharacterBody3D
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var home: Vector3 = ws.to_world(player.global_position)
	var sys: LightRailSystem = city.get_node_or_null("LightRail") as LightRailSystem
	var hold_was := sys.hold if sys else false
	var clock_was := LightRail.clock
	if sys:
		sys.hold = true
		if not sys._ready_done:
			sys._setup()
	# Up at the street beside the south kiosk, the city streamed round it.
	var up := MetroStation.to_world(f, Vector3(40.0, 1.2, -5.5))
	player.global_position = ws.to_local(up)
	player.velocity = Vector3.ZERO
	city.update_streaming(true)
	for i in 6:
		await _tree.physics_frame
	var key := plan.chunk_index_at(f.o)
	var chunk: CityChunk = city.chunks.get(key) as CityChunk
	_check(chunk != null and chunk.level == CityChunk.Level.FULL, "the station's chunk is streamed in full")
	if chunk == null:
		await _restore(city, player, ws, home, sys, hold_was, clock_was)
		return
	var body := chunk.get_node_or_null("MetroBody") as StaticBody3D
	var mesh := chunk.get_node_or_null("MetroStation") as MeshInstance3D
	_check(mesh != null and mesh.mesh != null and chunk.has_node("MetroSigns") and chunk.has_node("MetroGlass") and chunk.has_node("MetroShadow") and chunk.has_node("MetroOccluder"),
		"the chunk builds the station's meshes")
	_check(body != null and body.get_child_count() > 100 and body.collision_layer == 1 and body.collision_mask == 0,
		"and its collision on the world layer, mask 0 (%d boxes)" % (body.get_child_count() if body else 0))
	var zone := chunk.get_node_or_null("MetroZone") as Area3D
	_check(zone != null and not zone.monitorable and MetroStation.built(), "the zone over it is in, the station registered")
	if mesh and mesh.mesh:
		var tris := 0
		var finite := true
		for si in mesh.mesh.get_surface_count():
			var vs: PackedVector3Array = mesh.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			tris += vs.size() / 3
			for v in vs:
				finite = finite and is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
		_check(finite and tris > 8000 and tris < 60000, "the station is real geometry inside its budget (%d triangles), no NaN" % tris)
	# The road is cut over both stairs, and the ground under where you walk is the station's.
	var cuts := MetroStation.cuts_in(plan, Rect2((f.o as Vector2) - Vector2(60, 60), Vector2(120, 120)))
	_check(cuts.size() == 2, "the road is cut over both stairs (%d openings)" % cuts.size())
	await _tree.physics_frame
	var space := player.get_world_3d().direct_space_state
	var ground: PhysicsBody3D = city.get_node_or_null("GroundBody") as PhysicsBody3D
	var spots := {
		"the platform": [Vector3(-20.0, 0.0, 1.8), float(f.plat)],
		"the concourse": [Vector3(15.0, 0.0, -5.0), MetroStation.CONC_FLOOR],
		"the street stair's foot": [Vector3(-16.8, 0.0, -0.8), MetroStation.CONC_FLOOR],
		"the stair's top in the kiosk": [Vector3(-30.6, 0.0, -0.8), 0.16],
		"the platform under the bank's foot": [Vector3(6.6, 0.0, -0.8), float(f.plat)],
	}
	for label: String in spots:
		var at: Vector3 = spots[label][0]
		var want: float = spots[label][1]
		var from := MetroStation.to_world(f, Vector3(at.x, want + 1.5, at.z))
		var to := MetroStation.to_world(f, Vector3(at.x, want - 3.0, at.z))
		var q := PhysicsRayQueryParameters3D.create(ws.to_local(from), ws.to_local(to), 1)
		if ground:
			q.exclude = [ground.get_rid()]
		var hit := space.intersect_ray(q)
		var got: float = (ws.to_world(hit.position).y - float(f.y0)) if not hit.is_empty() else INF
		_check(not hit.is_empty() and absf(got - want) < 0.35, "you can stand on %s (floor at %.2f, want %.2f)" % [label, got, want])
	# Down a stair: the ramp under the treads falls all the way.
	var mid := MetroStation.to_world(f, Vector3(-24.0, 3.0, -0.8))
	var q2 := PhysicsRayQueryParameters3D.create(ws.to_local(mid), ws.to_local(mid + Vector3.DOWN * 12.0), 1)
	if ground:
		q2.exclude = [ground.get_rid()]
	var h2 := space.intersect_ray(q2)
	var y2: float = ws.to_world(h2.position).y - float(f.y0) if not h2.is_empty() else INF
	_check(not h2.is_empty() and y2 < -2.0 and y2 > MetroStation.CONC_FLOOR, "halfway down the stair the floor is halfway down (%.2f)" % y2)
	# The player on the platform: stays there.
	var stand := MetroStation.to_world(f, Vector3(-22.0, float(f.plat) + 1.0, 2.0))
	player.global_position = ws.to_local(stand)
	player.velocity = Vector3.ZERO
	MetroStation.admit(player)
	for i in 40:
		await _tree.physics_frame
	var at_w: Vector3 = ws.to_world(player.global_position)
	var rel := MetroStation.to_frame(f, at_w)
	_check(absf(rel.y - float(f.plat)) < 0.3 and absf(rel.x + 22.0) < 1.0,
		"the player stood on the platform stays on it (%.2f from the street, want %.2f)" % [rel.y, float(f.plat)])
	# The trains: in the tunnel, drawn while the player is down here.
	if sys:
		LightRail.clock = line.clock_at_station(0, 0)
		sys.step()
		var near_train := false
		for c in sys.get_children():
			if c is LightRailTrain and (c as LightRailTrain).visible:
				for sec in (c as LightRailTrain).sections:
					var tw: Vector3 = ws.to_world(sec.global_position)
					near_train = near_train or (sec.visible and absf(MetroStation.to_frame(f, tw).x) < LightRail.PLATFORM_LENGTH * 0.5)
		_check(near_train, "a train dwelling at the platform is drawn with the player down here")
		var riders_aboard := 0
		for c in sys.get_children():
			if c is LightRailTrain and (c as LightRailTrain).visible and (c as LightRailTrain).doors_open > 0.9:
				riders_aboard += 1
		_check(riders_aboard > 0, "with its doors open onto the island")
		sys.focus = MetroStation.to_world(f, Vector3(0.0, 30.0, 0.0))
		sys.step()
		var drawn_from_street := false
		for c in sys.get_children():
			if c is LightRailTrain and (c as LightRailTrain).visible:
				for sec in (c as LightRailTrain).sections:
					drawn_from_street = drawn_from_street or sec.visible
		_check(not drawn_from_street, "and not from the street (the tunnel stays nobody's)")
		sys.focus = Vector3.INF
	# The riders.
	var riders := 0
	var level_ok := true
	for n in chunk.get_children():
		if n is MetroRider:
			riders += 1
			var r := n as MetroRider
			var y: float = ws.to_world(r.global_position).y - float(f.y0)
			var want_y := (float(f.plat) if r.level == 0 else MetroStation.CONC_FLOOR)
			level_ok = level_ok and absf(y - want_y) < 1.2
	_check(riders >= 3 and level_ok, "people wait in the station, on their floors (%d)" % riders)
	# The A/B and the rolls: the same chunk built again with the station off keeps everything else.
	var a := _census(city, key, CityChunk.Level.FULL)
	MetroStation.enabled = false
	var b := _census(city, key, CityChunk.Level.FULL)
	MetroStation.enabled = true
	_check(b.metro == 0 and b.kiosk and a.metro >= 5, "METRO_STATION=0 builds the old kiosks and no station")
	_check(a.buildings == b.buildings and a.props == b.props and a.cars == b.cars,
		"nothing else in the chunk moves with the station on or off (%d/%d buildings, %d/%d props, %d/%d cars)" % [a.buildings, b.buildings, a.props, b.props, a.cars, b.cars])
	await _restore(city, player, ws, home, sys, hold_was, clock_was)


## A fresh build of chunk `key` (outside the streamer's books, freed after): what it holds.
func _census(city: Node3D, key: Vector2i, level: int) -> Dictionary:
	var ch: CityChunk = city._new_chunk(key, level)
	ch.build()
	var out := {"metro": 0, "kiosk": false, "buildings": ch.building_count, "props": ch.prop_records.size(), "cars": ch._cars.size()}
	for n in ch.get_children():
		if String(n.name).begins_with("Metro"):
			out.metro += 1
		if n.name == "RailBody":
			out.kiosk = true
	for c in ch._cars:
		if is_instance_valid(c):
			c.queue_free()
	ch.get_parent().remove_child(ch)
	ch.free()
	return out


func _restore(city: Node3D, player: CharacterBody3D, ws: Node, home: Vector3, sys: LightRailSystem, hold_was: bool, clock_was: float) -> void:
	LightRail.clock = clock_was
	if sys:
		sys.hold = hold_was
		sys.step()
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	await _tree.physics_frame
	await _tree.physics_frame
