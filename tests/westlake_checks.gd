extends RefCounted
## MacArthur Park and the downtown encampments, for tests/smoke_test.gd (run near the end of the
## city test). Loaded at run time, not named there, so it compiles after the autoloads and can
## name the classes that use them (Encampment, RoughSleeper, Explosion...). Kept quick: every
## check reads what the chunk builds or asks the plan, and the only waiting is a second of ticks
## to see who stays put.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var plan: CityPlan = city.plan
	var player := _tree.get_first_node_in_group("player") as Node3D
	var police: Node = city.get_node_or_null("Police")
	if police:
		police.set("enabled", false)
	_plan_checks(plan)
	await _park(city, plan, player)
	await _camps(city, plan, player)


func _plan_checks(plan: CityPlan) -> void:
	var site := plan.site_by_id(LandmarkMacArthurPark.SITE.id)
	_t._check(not site.is_empty() and (site.halves as Array).size() == 2 and (site.keep_z as Array).size() == 1,
		"MacArthur Park's site snaps to whole blocks with Wilshire kept through it")
	if site.is_empty():
		return
	var wil: int = site.keep_z[0]
	_t._check(plan.road_name(CityPlan.AXIS_Z, wil) == "WILSHIRE BLVD" and plan.road_name(CityPlan.AXIS_X, site.ix0) == "PARK VIEW ST"
		and plan.road_name(CityPlan.AXIS_X, site.ix1) == "ALVARADO ST", "the park's streets carry their real names")
	var r: Rect2 = site.rect
	var inner_x: int = int(site.ix0) + 1
	var closed := inner_x < int(site.ix1) and not plan.road_open(CityPlan.AXIS_X, inner_x, (site.halves[1] as Rect2).get_center().y)
	var wil_open := plan.road_open(CityPlan.AXIS_Z, wil, r.get_center().x)
	var edge_open := plan.road_open(CityPlan.AXIS_X, int(site.ix0), r.get_center().y) and plan.road_open(CityPlan.AXIS_Z, int(site.iz1), r.get_center().x)
	var outside_open := plan.road_open(CityPlan.AXIS_X, inner_x, r.position.y - 40.0)
	_t._check(closed and wil_open and edge_open and outside_open, "roads through the park are closed; Wilshire, the edges and the roads beyond it are open")
	var lots_in_park := 0
	for ix in range(int(site.ix0), int(site.ix1)):
		for iz in range(int(site.iz0), int(site.iz1)):
			lots_in_park += plan.lots(ix, iz).size()
	_t._check(lots_in_park == 0, "no building lots in the park (%d)" % lots_in_park)
	var lay := LandmarkMacArthurPark.layout(plan)
	_t._check(not lay.is_empty() and (lay.lake as PackedVector2Array).size() > 30 and (lay.south as Rect2).encloses((lay.lake_bounds as Rect2)),
		"the lake sits inside the south half")
	_t._check(Geometry2D.is_point_in_polygon(lay.fountain, lay.lake), "the fountain stands in the lake")


func _park(city: Node3D, plan: CityPlan, player: Node3D) -> void:
	var lay := LandmarkMacArthurPark.layout(plan)
	if lay.is_empty():
		return
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var anchor: Vector2 = LandmarkMacArthurPark.SITE.anchor
	await _go(city, player, Vector3(anchor.x, 3.0, anchor.y))
	var fountain: Vector2 = lay.fountain
	var lake_chunk: Node3D = city.chunks.get(plan.block_index_at(fountain))
	_t._check(lake_chunk != null and lake_chunk.level == 0 and lake_chunk.get_node_or_null("Lake") != null and lake_chunk.get_node_or_null("LakeBasin") != null,
		"the park's chunk builds the lake and its basin")
	var water: MeshInstance3D = lake_chunk.get_node_or_null("Lake") if lake_chunk else null
	_t._check(water != null and water.material_override is ShaderMaterial and (water.material_override as ShaderMaterial).shader.resource_path.ends_with("lake.gdshader"),
		"the lake wears the water shader")
	# Collision: from above the water down, past the city's ground box (which the lake lets bodies
	# through), the first thing of the park's own hit is the lake floor (wading depth). Anything
	# else in the way (something an earlier check threw in) is reported and looked past.
	var space := player.get_world_3d().direct_space_state
	var ground_body: Node = city.get_node_or_null("GroundBody")
	var dive := Vector2.INF
	var floor_y := INF
	var in_way := ""
	for k in 8:
		var probe := fountain + Vector2.from_angle(TAU * k / 8.0) * 10.0
		var found := _floor_hit(space, ws, probe, ground_body, city)
		if not found.is_empty():
			floor_y = found.y
			in_way += String(found.other)
			if String(found.other) == "":
				dive = probe
				break
	if in_way != "":
		printerr("westlake: in the lake before the checks:", in_way)
	_t._check(absf(floor_y - LandmarkMacArthurPark.FLOOR_Y) < 0.3, "the lake has a floor to land on under the water (hit at %.2f)" % floor_y)
	# The player jumps in: through the water to the floor, not standing on the surface.
	if dive != Vector2.INF:
		player.global_position = ws.to_local(Vector3(dive.x, 3.0, dive.y))
		player.set("velocity", Vector3(0.0, -8.0, 0.0))
		await _t._ticks(30)
	var in_y: float = ws.to_world(player.global_position).y
	_t._check(dive != Vector2.INF and in_y < LandmarkMacArthurPark.WATER_Y - 0.4 and in_y > LandmarkMacArthurPark.FLOOR_Y - 0.3,
		"the player lands in the lake and stands on its floor (%.2f)" % in_y)
	# And out again: once out of the water the ground holds him as before.
	var dry: Rect2 = lay.north_in
	player.global_position = ws.to_local(Vector3(dry.end.x - 30.0, 3.0, dry.get_center().y))
	player.set("velocity", Vector3.ZERO)
	await _t._ticks(25)
	var out_y: float = ws.to_world(player.global_position).y
	_t._check(out_y > -0.05, "out of the lake the ground holds again (%.2f)" % out_y)
	var n_in: Rect2 = lay.north_in
	var lawn := Vector2(n_in.end.x - 30.0, n_in.get_center().y)
	var q := PhysicsRayQueryParameters3D.create(ws.to_local(Vector3(lawn.x, 30.0, lawn.y)), ws.to_local(Vector3(lawn.x, -10.0, lawn.y)), 1)
	var hit := space.intersect_ray(q)
	var lawn_y: float = ws.to_world(hit.position).y if not hit.is_empty() else INF
	_t._check(not hit.is_empty() and lawn_y > LandmarkMacArthurPark.LAWN_TOP - 0.4, "the park's lawn is solid ground (hit at %.2f)" % lawn_y)
	var built := false
	for k in city.chunks:
		if (city.chunks[k].built_landmarks as Array).has(LandmarkMacArthurPark.SITE.id):
			built = true
	var jets := 0
	for n in _tree.root.find_children("FountainJet", "", true, false):
		if (n as Node3D).is_visible_in_tree():
			jets += 1
	_t._check(built and jets >= 1, "the fountain jet and the boathouse are built (%d jet in view)" % jets)
	var palms := 0
	var walkers := 0
	for k in city.chunks:
		var c: Node3D = city.chunks[k]
		if not (plan.block(k.x, k.y) as Dictionary).has("site") or c.level != 0:
			continue
		for child in c.get_children():
			if child is MultiMeshInstance3D and str(child.name).begins_with("Batch_palm_"):
				palms += (child as MultiMeshInstance3D).multimesh.instance_count
			if child is Pedestrian:
				walkers += 1
	_t._check(palms >= 30 and walkers >= 6, "palms ring the lake and lawns (%d) and people walk the park (%d)" % [palms, walkers])
	# Nothing of the street grid inside: no parked car or traffic car on a closed road.
	var traffic: Node = city.get_node("Traffic")
	await _t._ticks(15)
	var bad := 0
	for car in traffic.cars:
		if not is_instance_valid(car):
			continue
		var tt: Dictionary = car.traffic
		var wp: Vector3 = ws.to_world(car.global_position)
		var along: float = wp.z if int(tt.axis) == CityPlan.AXIS_X else wp.x
		if not plan.road_open(int(tt.axis), int(tt.index), along):
			bad += 1
			printerr("westlake: traffic on a closed road at %s: %s" % [str(wp.snapped(Vector3.ONE)), str(tt)])
	# Parked cars: the kerbs round and through the park get none. (A car driven or thrown in is
	# not parked: only cars standing still with nobody in them and no traffic lane count.)
	var parked_in := 0
	for car in _tree.get_nodes_in_group("vehicle"):
		var cw: Vector3 = ws.to_world((car as Node3D).global_position)
		if not plan.in_site(Vector2(cw.x, cw.z)) or car.is_in_group("police_car") or car.get("driver") != null:
			continue
		var lane: Variant = car.get("traffic")
		if lane is Dictionary and not (lane as Dictionary).is_empty():
			continue
		if car is RigidBody3D and (car as RigidBody3D).linear_velocity.length() > 0.5:
			continue
		parked_in += 1
		printerr("westlake: a car standing in the park at %s (%s)" % [str(cw.snapped(Vector3.ONE)), car.name])
	_t._check(bad == 0 and parked_in == 0, "no car drives or parks inside the park (%d driving, %d standing)" % [bad, parked_in])


func _camps(city: Node3D, plan: CityPlan, player: Node3D) -> void:
	var ws: Node = _tree.root.get_node("/root/WorldState")
	# A downtown block that has camps.
	var centre: Vector2 = plan.macro.downtown_center
	var ci := plan.block_index_at(centre)
	var pick := Vector2i(999999, 0)
	for r in 4:
		for ix in range(ci.x - r, ci.x + r + 1):
			for iz in range(ci.y - r, ci.y + r + 1):
				if pick.x == 999999 and Encampment.block_has_camps(plan, ix, iz):
					pick = Vector2i(ix, iz)
	_t._check(pick.x != 999999, "some downtown blocks have encampments")
	if pick.x == 999999:
		return
	var at: Vector2 = (plan.block(pick.x, pick.y).rect as Rect2).get_center()
	await _go(city, player, Vector3(at.x, 3.0, at.y))
	var camp_chunks := 0
	var items_total := 0
	var wrong := 0
	var over_cap := 0
	var sleepers: Array = []
	for k in city.chunks:
		var c: Node3D = city.chunks[k]
		if c.level != 0:
			continue
		var items := 0
		var people := 0
		for child in c.get_children():
			if child is EncampmentItem:
				items += 1
			elif child is RoughSleeper:
				people += 1
				sleepers.append(child)
		var batch := 0
		for child in c.get_children():
			if child is MultiMeshInstance3D and str(child.name).begins_with("Batch_camp_"):
				batch += (child as MultiMeshInstance3D).multimesh.instance_count
		var block := plan.block(k.x, k.y)
		if int(block.district) != CityPlan.District.DOWNTOWN or int(block.kind) != CityPlan.BlockKind.BUILDINGS:
			if items > 0 or batch > 0 or people > 0:
				wrong += 1
		elif batch > 0:
			camp_chunks += 1
		if batch > Encampment.MAX_ITEMS or people > Encampment.MAX_SLEEPERS:
			over_cap += 1
		items_total += items
	_t._check(camp_chunks >= 1 and items_total >= 4, "downtown chunks get encampments (%d chunks, %d knockable pieces)" % [camp_chunks, items_total])
	_t._check(wrong == 0, "no encampments outside downtown blocks of buildings (%d chunks wrong)" % wrong)
	_t._check(over_cap == 0 and _tree.get_nodes_in_group("pedestrian").size() <= int(city.max_pedestrians) + 2,
		"encampments stay under their caps and the crowd cap (%d over)" % over_cap)
	_t._check(sleepers.size() >= 1, "people at the camps (%d)" % sleepers.size())
	if sleepers.is_empty():
		return
	# They hold their poses: nobody at a camp walks.
	var start := {}
	var kinds := {}
	for s in sleepers:
		start[s] = (s as Node3D).global_position
		kinds[int(s.pose)] = true
	await _t._ticks(30)
	var moved := 0
	var posed := 0
	for s in sleepers:
		if not is_instance_valid(s):
			continue
		if (s as Node3D).global_position.distance_to(start[s]) > 0.05:
			moved += 1
		if s.is_posed():
			posed += 1
	_t._check(moved == 0 and posed == sleepers.size(), "the people at the camps hold their poses and do not walk (%d moved, %d posed, %d poses)" % [moved, posed, kinds.size()])
	var worn := false
	for s in sleepers:
		for mi in (s as Node).find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).material_override as ShaderMaterial
			if m and float(m.get_shader_parameter("grime")) > 0.3:
				worn = true
	_t._check(worn, "their clothes wear the worn, dirty look")
	# Gunfire: someone sitting or lying gets up and goes; someone slumped cowers where they stand.
	var one: Node3D = sleepers[0]
	Pedestrian.alarm(_tree, one.global_position + Vector3(4.0, 0.0, 0.0), 12.0, 0, true, "")
	await _t._ticks(20)
	if is_instance_valid(one):
		var state: int = int(one.get("_state"))
		var ok: bool = state == RoughSleeper.State.COWER if int(one.pose) == RoughSleeper.Pose.SLUMP else (state == RoughSleeper.State.FLEE or state == RoughSleeper.State.RETURN)
		_t._check(ok, "a nearby shot sends them running, or cowering if slumped (pose %d, state %d)" % [int(one.pose), state])
	# A blast scatters a camp: its pieces are thrown as bodies and stay gone.
	var item: EncampmentItem = null
	for k in city.chunks:
		for child in (city.chunks[k] as Node).get_children():
			if child is EncampmentItem and item == null:
				item = child
	if item:
		var id := item.item_id
		var key: String = item.chunk.get("key")
		var before := _tree.get_nodes_in_group("debris").size()
		Explosion.blast(item, item.global_position + Vector3(0.0, 0.5, 0.0), 8.0, 20.0, 10.0)
		await _t._ticks(3)
		_t._check(not is_instance_valid(item) and ws.is_destroyed(key, id) and _tree.get_nodes_in_group("debris").size() > before,
			"a blast throws a camp's pieces as bodies and they stay gone")


## The first thing of a detailed chunk's own statics hit straight down at world XZ `at` (the city's
## ground box excluded, since the lake lets bodies through it): {y, other}, `other` naming whatever
## else was in the way first. Empty when no detailed chunk has anything there.
func _floor_hit(space: PhysicsDirectSpaceState3D, ws: Node, at: Vector2, ground_body: Node, city: Node) -> Dictionary:
	var exclude: Array[RID] = []
	if ground_body:
		exclude.append(ground_body.get_rid())
	var other := ""
	for i in 6:
		var q := PhysicsRayQueryParameters3D.create(ws.to_local(Vector3(at.x, 30.0, at.y)), ws.to_local(Vector3(at.x, -10.0, at.y)), 1)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var col := hit.collider as Node
		var owner_chunk: Node = col.get_parent() if col else null
		if owner_chunk and owner_chunk.get("level") == 0 and (city.chunks.values() as Array).has(owner_chunk):
			return {"y": ws.to_world(hit.position).y, "other": other}
		other += " %s@%.2f" % [str(col.get_path()) if col else "?", ws.to_world(hit.position).y]
		exclude.append(hit.rid)
	return {}


## Puts the player at a true world position and the city round him, and waits until physics
## queries see it. The teleport is hundreds of metres, so the origin is re-centred on him first
## (as the streamer would on the next tick) - and the broadphase lags a moved static body by a
## couple of steps, so a ray cast straight after hit the relief floors of far chunks where they
## stood before the shift, three metres over the lake. Idle frames as well as ticks: a far chunk
## replaced by a detailed one is only freed at the end of a frame, and on a slow box several
## ticks run inside one frame.
func _go(city: Node3D, player: Node3D, world: Vector3) -> void:
	var ws: Node = _tree.root.get_node("/root/WorldState")
	player.global_position = ws.to_local(world)
	player.set("velocity", Vector3.ZERO)
	city.recenter()
	city.update_streaming(true)
	await _tree.process_frame
	await _tree.process_frame
	await _t._ticks(4)
