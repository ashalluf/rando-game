extends RefCounted
## The distance (owner, 2026-09-24: "certain areas of the map aren't loading properly at a
## distance ... do whatever GTA does"): checks for tests/smoke_test.gd that the tiers of detail -
## FULL chunks, LOD chunks, the far city (Skyline) and the horizon plane - cover the whole visible
## world with no gap between them and no block drawn twice, that the distances they hand over at
## agree with each other, and that the streaming queue is ordered by what the camera sees.
## Loaded at run time, so it compiles after the autoloads and can name CityStreamer and Skyline.
##
## Everything here is bookkeeping, deliberately: under --headless the MultiMesh instance data
## reads back as identity (CLAUDE.md), so "is this block drawn" is asked of the tier that owns
## the block - an installed chunk, or the far city's per-block visibility - never of the GPU.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var streamer := city as CityStreamer
	var sky := city.get_node_or_null("Skyline") as Skyline
	t._check(streamer != null and sky != null, "the city has a far-city tier (Skyline)")
	if streamer == null or sky == null:
		return
	var player := _tree.get_first_node_in_group("player") as Node3D
	var cam := player.get_node("CameraRig/SpringArm3D/Camera3D") as Camera3D
	_handoff_distances(streamer, sky, cam)
	_same_city(streamer)
	await _view_priority(streamer, player)
	# The whole far city, as the loading screen builds it on desktop.
	streamer.finish_far_city()
	# From where the test stands, at street level and then 600 m up (from the air the old far
	# tier was drawn right over the detailed city), and from the hills over the basin.
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var here: Vector3 = ws.to_world(player.global_position)
	await _vantage(streamer, sky, player, cam, Vector3(here.x, maxf(here.y, 2.0), here.z), "street level")
	await _vantage(streamer, sky, player, cam, Vector3(here.x, 600.0, here.z), "600 m up")
	# Over the foot of the front range, where the city starts: 250 m south of where this stood before
	# downtown went in at 1:1 (DowntownReal). The real streets pinned across the map made the blocks
	# here 184 m deep, and the FULL ring stops at CityStreamer.full_reach_metres(), so from z -1150
	# every full-detail chunk was hillside and the full tier had no city to show.
	await _vantage(streamer, sky, player, cam, Vector3(300.0, 520.0, -900.0), "the hills over the basin")
	_fade_handoff(streamer, sky)


## The distances each tier hands over at have to agree, or there is a ring nobody draws.
func _handoff_distances(streamer: CityStreamer, sky: Skyline, cam: Camera3D) -> void:
	var half := streamer.ground_size * 0.5
	_t._check(cam.far >= half * sqrt(2.0), "the camera draws to the corners of the horizon plane (far %.0f m, corners %.0f m)" % [cam.far, half * sqrt(2.0)])
	_t._check(sky.radius >= half and is_equal_approx(sky.radius, streamer.far_city_radius), "the far city reaches the horizon plane's edge (%.0f m of %.0f)" % [sky.radius, half])
	# Nothing in the far city is drawn by distance: it is handed over per block, so it cannot
	# leave a ring between where the LOD chunks stop and where it starts.
	var gated := 0
	for n in sky.get_children():
		if n is GeometryInstance3D and ((n as GeometryInstance3D).visibility_range_begin > 0.0 or (n as GeometryInstance3D).visibility_range_end > 0.0):
			gated += 1
	_t._check(sky.draw_from == 0.0 and gated == 0 and sky.tile_count() > 0, "the far city has no distance gate (%d tiles, %d gated)" % [sky.tile_count(), gated])
	_t._check(is_equal_approx(sky.fade_time, streamer.lod_fade_time) and streamer.lod_fade_time > 0.0, "every tier hands over in the same dissolve (%.2f s)" % sky.fade_time)
	_t._check(streamer.keep_radius_blocks >= streamer.lod_radius_blocks and streamer.lod_radius_blocks > streamer.load_radius_blocks,
		"chunks are kept at least as far as they are wanted (keep %d, LOD %d, FULL %d blocks)" % [streamer.keep_radius_blocks, streamer.lod_radius_blocks, streamer.load_radius_blocks])
	# Numbers in other files that have to agree with the far plane: aircraft lights are pulled
	# in to just inside it, and the horizon plane must not bury the far city it now stands under.
	var lights: Shader = load("res://shaders/aircraft_lights.gdshader")
	var depth := _uniform_default(lights.code, "max_depth")
	_t._check(depth > 2000.0 and depth < cam.far, "aircraft lights are pulled in to just inside the far plane (%.0f of %.0f m)" % [depth, cam.far])
	var ground: Shader = load("res://shaders/macro_ground.gdshader")
	_t._check(_uniform_default(ground.code, "urban_lift") <= 0.0, "the horizon plane does not lift itself over the far city")


## The far city draws a block exactly as its LOD chunk does: same boxes, same colours, same
## facade data - because it is the LOD chunk's own block build, captured.
func _same_city(streamer: CityStreamer) -> void:
	var plan: CityPlan = streamer.plan
	var checked := 0
	var same := 0
	# Blocks the LOD build puts no boxes on (a downtown tower site is a landmark, drawn by its
	# far version) prove nothing and are skipped, so there are spares.
	for k: Vector2i in [Vector2i(7, 2), Vector2i(3, -3), Vector2i(-6, 4), Vector2i(10, 5), Vector2i(5, -2), Vector2i(-3, 6)]:
		var b := plan.block(k.x, k.y)
		if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
			continue
		# The LOD chunk, built to just before its finish (which would turn the batch into nodes).
		var lod := CityChunk.new()
		lod.plan = plan
		lod.ix = k.x
		lod.iz = k.y
		lod.level = CityChunk.Level.LOD
		lod.style = streamer.chunk_style()
		lod.begin_build()
		while lod._step < lod._steps.size() - 1:
			lod.build_step()
		var a: Dictionary = lod._batch.data().get("lod_box", {"xforms": [], "colors": []})
		var cap := CityChunk.new()
		cap.plan = plan
		cap.ix = k.x
		cap.iz = k.y
		cap.level = CityChunk.Level.LOD
		cap.style = streamer.chunk_style()
		cap.capturing = true
		cap.build()
		var c: Dictionary = cap.captured.batch.get("lod_box", {"xforms": [], "colors": []})
		if not (a.xforms as Array).is_empty():
			checked += 1
			if a.xforms == c.xforms and a.colors == c.colors:
				same += 1
		lod.free()
		cap.free()
	_t._check(checked >= 3 and same == checked, "the far city's massing is the LOD chunk's own, box for box (%d of %d blocks)" % [same, checked])
	_airport_ground(streamer)


## Outside the city a far plate wears the colour the LOD chunk's ground is really drawn in (the
## airport apron is road() at a tint of 1.25 - three times what the city's far ground rule gave,
## so the far airport was a dark slab beside a pale near one), and a runway is its own strip.
func _airport_ground(streamer: CityStreamer) -> void:
	var plan: CityPlan = streamer.plan
	var macro := plan.macro
	if macro == null:
		return
	var k: Vector2i = plan.block_index_at(Vector2(macro.airport_rect.get_center().x, macro.runway_zs[0]))
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = streamer.chunk_style()
	cap.capturing = true
	cap.build()
	var ground: Array = cap.captured.ground
	var apron := PropFactory.far_albedo(PropFactory.road("asphalt", 8.0, Color(1.25, 1.25, 1.27), 0), Color.BLACK)
	var sky := Skyline.new()
	sky.setup(plan, streamer.chunk_style())
	sky._work = {"xforms": [], "colors": [], "customs": []}
	sky._add_plate(k, cap.zone, ground, cap)
	var colors: Array = sky._work.colors
	var runway := CityChunk.far_tint(streamer.chunk_style().runway, Color.BLACK)
	var has_runway := false
	var apron_ok := false
	for c: Color in colors:
		has_runway = has_runway or c.is_equal_approx(PropFactory.far_albedo(PropFactory.material(streamer.chunk_style().runway, 0.95), runway))
		apron_ok = apron_ok or c.is_equal_approx(apron)
	_t._check(cap.zone == MacroMap.Zone.AIRPORT and ground.size() >= 2 and colors.size() >= 2 and has_runway and apron_ok,
		"a far airport block wears the apron the chunk draws and its runway as a strip (%d plates)" % colors.size())
	sky.free()
	cap.free()


## The build queue puts what the camera looks at first: at equal distance a block ahead of the
## view is built before one behind it, and a near block before a far one either way.
func _view_priority(streamer: CityStreamer, player: Node3D) -> void:
	var rig: Node = player.get("camera_rig")
	if rig:
		rig.call("set_look", -90.0, 0.0) # facing +X
	player.set("velocity", Vector3.ZERO)
	await _tree.process_frame
	await _tree.process_frame
	streamer.update_streaming(false)
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var wp: Vector3 = ws.to_world(player.global_position)
	var eye := Vector2(wp.x, wp.z)
	var plan: CityPlan = streamer.plan
	var here: Vector2i = plan.block_index_at(eye)
	var ahead := plan.block_index_at(eye + Vector2(420.0, 0.0))
	var behind := plan.block_index_at(eye - Vector2(420.0, 0.0))
	var near_behind := plan.block_index_at(eye - Vector2(130.0, 0.0))
	var queue := streamer.stream_queue([behind, ahead, near_behind, here])
	_t._check(queue[0] == here and queue.find(ahead) < queue.find(behind),
		"the build queue favours the view (order %s for here %s, ahead %s, behind %s)" % [str(queue), str(here), str(ahead), str(behind)])
	_t._check(queue.find(near_behind) < queue.find(behind), "a near block is built before a far one behind the camera")
	var pa := streamer.stream_priority_at(eye + Vector2(400.0, 0.0))
	var pb := streamer.stream_priority_at(eye - Vector2(400.0, 0.0))
	_t._check(pa < pb * 0.75, "a point in view waits less than one as far behind (%.0f vs %.0f)" % [pa, pb])
	if rig:
		rig.call("set_look", 0.0, -8.0)


## One vantage: stand there, let the window settle and the dissolves finish, then walk rays out
## in every direction to the horizon and ask who draws each city block they cross.
func _vantage(streamer: CityStreamer, sky: Skyline, player: Node3D, cam: Camera3D, at: Vector3, label: String) -> void:
	var ws: Node = _tree.root.get_node("/root/WorldState")
	player.global_position = ws.to_local(at)
	player.set("velocity", Vector3.ZERO)
	streamer.update_streaming(true)
	# Real time, not frames: the dissolves run on the frame delta, and headless frames are short.
	var until := Time.get_ticks_msec() + int((sky.fade_time + 0.3) * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < until or frames < 10:
		await _tree.process_frame
		frames += 1
		player.global_position = ws.to_local(at)
		player.set("velocity", Vector3.ZERO)
	var plan: CityPlan = streamer.plan
	var reach := minf(cam.far, streamer.ground_size * 0.5)
	var samples := 0
	var gaps := 0
	var doubled := 0
	var by_tier := {"full": 0, "lod": 0, "far": 0}
	var gap_at := ""
	var seen := {}
	for a in 32:
		var dir := Vector2.from_angle(TAU * float(a) / 32.0)
		var d := 20.0
		while d <= reach:
			var p := Vector2(at.x, at.z) + dir * d
			d += 45.0
			var k := plan.chunk_index_at(p)
			if seen.has(k):
				continue
			seen[k] = true
			# A block is city or not by its centre, as the chunk and the far city both decide it;
			# the horizon plane draws the hills, the sand and the sea everywhere else.
			if plan.zone_at((plan.block(k.x, k.y).rect as Rect2).get_center()) != MacroMap.Zone.CITY:
				continue
			samples += 1
			var chunk: CityChunk = streamer.chunks.get(k)
			var alpha := sky.block_alpha(k)
			var far_drawn := alpha > 0.999 and sky.block_instances(k) > 0
			if chunk != null and alpha > 0.001:
				doubled += 1
			if chunk != null:
				by_tier["full" if chunk.level == CityChunk.Level.FULL else "lod"] += 1
			elif far_drawn:
				by_tier.far += 1
			else:
				gaps += 1
				if gap_at == "":
					gap_at = "%s at %.0f m (alpha %.2f)" % [str(k), p.distance_to(Vector2(at.x, at.z)), alpha]
	_t._check(samples > 50 and gaps == 0, "from %s every city block out to the horizon is drawn (%d blocks, %d gaps%s)" % [label, samples, gaps, (": first " + gap_at) if gap_at != "" else ""])
	_t._check(doubled == 0, "from %s no block is drawn by two tiers at once (%d)" % [label, doubled])
	_t._check(by_tier.full > 0 and by_tier.lod > 0 and by_tier.far > 0, "from %s all three city tiers are in use (full %d, LOD %d, far %d)" % [label, by_tier.full, by_tier.lod, by_tier.far])


## The handoff itself: a chunk taking a block over dissolves the far city out, and a chunk leaving
## is kept standing until the far city has dissolved back in over it.
func _fade_handoff(streamer: CityStreamer, sky: Skyline) -> void:
	var k := Vector2i(1 << 20, 0)
	for block: Vector2i in sky._blocks:
		if not sky.is_covered(block) and sky.block_alpha(block) == 1.0:
			k = block
			break
	sky.cover(k, CityChunk.Level.LOD)
	sky._process(sky.fade_time * 0.5)
	var mid := sky.block_alpha(k)
	sky._process(sky.fade_time)
	var gone := sky.block_alpha(k)
	sky.uncover(k)
	sky._process(sky.fade_time * 0.5)
	var back_mid := sky.block_alpha(k)
	sky._process(sky.fade_time)
	var back := sky.block_alpha(k)
	var built := mid >= 0.0
	_t._check(built and (mid > 0.2 and mid < 0.8 and gone == 0.0 and back_mid > 0.2 and back_mid < 0.8 and back == 1.0),
		"the far city dissolves out and back in over a block (%.2f, %.2f, %.2f, %.2f)" % [mid, gone, back_mid, back])


## A float uniform's default, read out of a shader's source.
func _uniform_default(code: String, uniform_name: String) -> float:
	var re := RegEx.new()
	re.compile("uniform\\s+float\\s+" + uniform_name + "\\s*(?::[^=]*)?=\\s*(-?[0-9.]+)")
	var m := re.search(code)
	return float(m.get_string(1)) if m else NAN
