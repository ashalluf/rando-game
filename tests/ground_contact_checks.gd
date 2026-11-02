extends RefCounted
## Ground contact (fleet wave 4, `ground-shadow-contact`; docs/HANDOFF.md "Ground contact"), for
## tests/smoke_test.gd: what stands on the ground meets it. GroundContact's table (trunks, poles,
## furniture: round feet, grime), the people's blobs (who gets one, the ground under them), the
## contact shader's new inputs, a street tree sunk into its dirt well with the dirt, and a slope's
## planter standing on the paving with its shrubs on its soil. Under --headless a MultiMesh reads
## its transforms back as identity, so the checks hold the tables, the pure helpers and the batch
## data before it is built; tools/ground_contact/probe.tscn (opengl3) measures a built block.

var _t: Node


func run(t: Node, city: Node3D = null) -> void:
	_t = t
	_table()
	_shader_source()
	_people(city)
	_well()
	_planter(city)


## Trunks and poles are round at their own diameter; lit quads and grates get nothing; ContactShadows
## takes the table for every batch it is handed.
func _table() -> void:
	var was := GroundContact.enabled
	GroundContact.enabled = true
	var cobra := GroundContact.spec("lamp_cobra")
	_t._check(not cobra.is_empty() and float(cobra[0]) > 0.1 and float(cobra[0]) < 0.6 and float(cobra[3]) > 0.0,
		"a cobra lamp gets a round foot of its pole's size, with grime (not its arm's box)")
	for key in ["lamp_pool", "tree_grate", "atmos_glow_halo", "sig_head", "shop_spill"]:
		_t._check(GroundContact.spec(key).is_empty(), "%s gets no contact quad (lit, flat or overhead)" % key)
	for key in ["tree_1", "palm_3", "la_olive_1", "upole", "bollard", "sig_pole", "lamp_lantern"]:
		var row := GroundContact.spec(key)
		_t._check(not row.is_empty() and float(row[0]) > 0.0 and float(row[0]) < 0.7, "%s stands on a round contact quad" % key)
	_t._check(GroundContact.grime("hydrant") > 0.5 and GroundContact.grime("bench") == 0.0,
		"a hydrant collects grime round its foot, a bench does not")
	GroundContact.enabled = false
	_t._check(GroundContact.spec("tree_1").is_empty() and GroundContact.grime("hydrant") == 0.0,
		"GROUND_CONTACT=0 hands ContactShadows nothing new (its own set as it was)")
	GroundContact.enabled = was
	var src := FileAccess.get_file_as_string("res://scripts/world/contact_shadows.gd")
	_t._check(src.contains("GroundContact.spec(key)") and src.contains("_people_quads("),
		"ContactShadows lays GroundContact's feet in its BatchContact and its people's blobs in its own quads")


## The shader: round corners and grime from the instance colour, noise in true world metres, still
## no instance uniforms.
func _shader_source() -> void:
	var s := FileAccess.get_file_as_string("res://shaders/contact_shadow.gdshader")
	_t._check(s.contains("v_round = clamp(COLOR.g") and s.contains("v_grime = COLOR.b") and s.contains("origin_shift"),
		"contact_shadow.gdshader takes the corner rounding and the grime from COLOR, its noise in true world space")
	_t._check(not s.contains("instance uniform") and s.contains("ALBEDO = vec3(0.0)"),
		"contact_shadow.gdshader is still a darkening with no instance uniforms")


## Who gets a blob: a drawn person near the camera, not a hidden one, not the player in a car; the
## ground under them by one ray.
func _people(city: Node3D) -> void:
	if city == null or not GroundContact.enabled:
		return
	var cam := _t.get_viewport().get_camera_3d()
	if cam == null:
		_t._check(true, "ground contact people: no camera (skipped)")
		return
	var players := _t.get_tree().get_nodes_in_group("player")
	var player := players[0] as Node3D if not players.is_empty() else null
	var holder := Node3D.new()
	holder.name = "GroundContactCheck"
	city.add_child(holder)
	var eye := cam.global_position
	var walker := Node3D.new()
	walker.add_to_group("pedestrian")
	holder.add_child(walker)
	walker.global_position = eye + Vector3(2.0, 0.0, 0.0)
	var hidden := Node3D.new()
	hidden.add_to_group("pedestrian")
	holder.add_child(hidden)
	hidden.global_position = eye + Vector3(-2.0, 0.0, 0.0)
	hidden.visible = false
	var far := Node3D.new()
	far.add_to_group("pedestrian")
	holder.add_child(far)
	far.global_position = eye + Vector3(GroundContact.people_reach + 20.0, 0.0, 0.0)
	var near := GroundContact.people_near(_t.get_tree(), eye)
	var got := {}
	for e in near:
		got[(e[1] as Node).get_instance_id()] = true
	_t._check(got.has(walker.get_instance_id()) and not got.has(hidden.get_instance_id()) and not got.has(far.get_instance_id()),
		"a near, drawn walker gets a contact blob; a hidden one or one past the reach does not")
	_t._check(near.size() <= GroundContact.people_budget, "at most people_budget blobs (%d)" % near.size())
	if player:
		var v: Variant = player.get("vehicle")
		_t._check(GroundContact.is_person(player) == (v == null and player.is_visible_in_tree()),
			"the player on foot gets a blob, in a car none")
		# One metre over the ground under the player: the ray finds it a metre down.
		var probe := Node3D.new()
		holder.add_child(probe)
		var space := player.get_world_3d().direct_space_state
		var under := GroundContact.ground_drop(space, player)
		if not is_nan(under):
			# A metre over the surface the player's ray hits, not over his origin: half on a kerb (or
			# still settling) his feet stood 0.19 m under the pavement top it found, which ground_drop
			# clamps to 0, and the probe read 0.81 (shuffled gate 2303).
			var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.4, player.global_position + Vector3.DOWN * 6.0, 1)
			q.exclude = [(player as CollisionObject3D).get_rid()]
			var hit := space.intersect_ray(q)
			var ground_y: float = (hit.position as Vector3).y if not hit.is_empty() else player.global_position.y - under
			probe.global_position = Vector3(player.global_position.x, ground_y + 1.0, player.global_position.z)
			var drop := GroundContact.ground_drop(space, probe)
			_t._check(not is_nan(drop) and absf(drop - 1.0) < 0.15,
				"ground_drop() finds the ground a metre under a point a metre up (%.2f, the player's %.2f)" % [drop, under])
	var cs := ContactShadows.instance()
	if cs and cs._mm:
		_t._check(cs._mm.instance_count >= ContactShadows.budget + GroundContact.people_budget,
			"ContactShadows' quads have room for the cars, the props and the people")
	holder.queue_free()


## A bare dirt well cut round a street tree takes the trunk down with the dirt, nothing else.
func _well() -> void:
	var was := GroundContact.enabled
	GroundContact.enabled = true
	var t0 := Transform3D(Basis(), Vector3(10.0, 0.25, 20.0))
	var t1 := Transform3D(Basis(), Vector3(14.0, 0.25, 20.0))
	var data := {
		"tree_1": {"xforms": [t0, t1]},
		"tree_grate": {"xforms": [t0]},
		"bench": {"xforms": [t0]},
	}
	GroundContact.sink_trunk(data, Vector2(10.05, 20.0), 0.035)
	_t._check(is_equal_approx((data.tree_1.xforms[0] as Transform3D).origin.y, 0.215)
		and is_equal_approx((data.tree_1.xforms[1] as Transform3D).origin.y, 0.25)
		and is_equal_approx((data.tree_grate.xforms[0] as Transform3D).origin.y, 0.25)
		and is_equal_approx((data.bench.xforms[0] as Transform3D).origin.y, 0.25),
		"a dirt well sinks the trunk standing in it by the dirt's depth, and only that trunk")
	var k := FileAccess.get_file_as_string("res://scripts/world/kerbs.gd")
	_t._check(k.contains("GroundContact.sink_trunk(data, c, WELL_DIRT_DEPTH)"), "Kerbs sinks a well's tree with its dirt")
	GroundContact.enabled = was


## A raised planter on a slope: its box reaches the paving at its lowest corner, and every shrub in
## it stands on its soil (the same height whatever the slope under it).
func _planter(city: Node3D) -> void:
	if city == null:
		return
	var plan: CityPlan = city.get("plan")
	if plan == null:
		return
	var ch := CityChunk.new()
	ch.plan = plan
	ch.level = CityChunk.Level.FULL
	ch._batch.ground = ch._gy
	# A sloping spot of the city: the steepest of a few, along x.
	var best := Vector2.ZERO
	var best_slope := 0.0
	for p: Vector2 in [Vector2(-494.0, -16.3), Vector2(-480.0, 60.0), Vector2(300.0, -600.0), Vector2(-200.0, 1500.0), Vector2(1200.0, 600.0)]:
		var sl := absf(ch._gy(p.x + 4.0, p.y) - ch._gy(p.x - 4.0, p.y)) / 8.0
		if sl > best_slope:
			best_slope = sl
			best = p
	if best_slope < 0.02:
		_t._check(true, "ground contact planter: no slope found (skipped)")
		ch.free()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var r := Rect2(best - Vector2(4.0, 0.65), Vector2(8.0, 1.3))
	LotFill._planter(ch, r, rng, false)
	var soil := INF
	var spread := 0.0
	var n := 0
	for key: String in ch._batch.data():
		if not (key.begins_with("bush_") or key.begins_with("la_")):
			continue
		for x: Transform3D in ch._batch.data()[key].xforms:
			if is_inf(soil):
				soil = x.origin.y
			spread = maxf(spread, absf(x.origin.y - soil))
			n += 1
	var gc := ch._gy(best.x, best.y)
	var low := minf(minf(ch._gy(r.position.x, r.position.y), ch._gy(r.end.x, r.position.y)), minf(ch._gy(r.end.x, r.end.y), ch._gy(r.position.x, r.end.y)))
	var bottom := INF
	for mat: Material in ch._boxes:
		var verts: PackedVector3Array = (ch._boxes[mat] as Array)[0]
		for v in verts:
			bottom = minf(bottom, v.y)
	_t._check(n > 0 and spread < 0.01,
		"the shrubs of a planter on a %.0f %% slope stand on its soil, level (spread %.3f m over %d)" % [best_slope * 100.0, spread, n])
	_t._check(not is_inf(bottom) and bottom <= low + CityChunk.SIDEWALK_TOP + LotFill.PAVING_LIFT + 0.005 and gc - low > 0.05,
		"its box reaches the paving at its lowest corner (bottom %.2f, paving %.2f)" % [bottom, low + CityChunk.SIDEWALK_TOP + LotFill.PAVING_LIFT])
	ch.free()
