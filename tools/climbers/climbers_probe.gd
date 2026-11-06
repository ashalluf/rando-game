extends Node
## Climbing plants round a point, headless and in seconds: builds the FULL chunks round each
## AT=x,z (or, with no AT, the first FIND=n blocks of DISTRICT, default 5 = BEACHTOWN, in a scan of
## the plan) through the real CityChunk build and prints what ClimbingPlants grew in each: cards
## per species, the triangles of the three meshes, the build step's time, and an EYE for every
## plant spot (a pavement view of it, for tools/glshot/still_shot.gd or block_shot.tscn).
##
##   godot --headless --path . res://tools/climbers/climbers_probe.tscn
##
## Env: AT="x,z;x,z", DISTRICT, FIND (default 3), CLIMBERS=0 (the A/B), SEED.
## Scene, not --script: CityChunk names autoloads.

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	var style: Dictionary = city.chunk_style()
	var keys: Array[Vector2i] = []
	if OS.get_environment("AT") != "":
		for e in OS.get_environment("AT").split(";", false):
			var v := e.split_floats(",")
			keys.append(plan.block_index_at(Vector2(v[0], v[1])))
	else:
		var want := int(OS.get_environment("DISTRICT")) if OS.get_environment("DISTRICT") != "" else CityPlan.District.BEACHTOWN
		var find := int(OS.get_environment("FIND")) if OS.get_environment("FIND") != "" else 3
		var c0 := plan.block_index_at(Vector2(0.0, 2500.0))
		for r in range(0, 40):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r or keys.size() >= find:
						continue
					var k := c0 + Vector2i(dx * 2, dz * 2)
					var b := plan.block(k.x, k.y)
					if int(b.district) == want and int(b.kind) == CityPlan.BlockKind.BUILDINGS and not b.has("site") and (b.rect as Rect2).size.x < 160.0 and (b.rect as Rect2).size.y < 160.0 \
							and plan.zone_at((b.rect as Rect2).get_center()) == MacroMap.Zone.CITY and not plan.lots(k.x, k.y).is_empty():
						keys.append(k)
	ClimbingPlants.debug = OS.get_environment("SLOW") == "1"
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	for k in keys:
		var ch = chunk_script.new()
		ch.plan = plan
		ch.ix = k.x
		ch.iz = k.y
		ch.level = 0
		ch.style = style
		add_child(ch)
		var t0 := Time.get_ticks_usec()
		ch.build()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var m: Dictionary = ch.get_meta("climbers", {})
		var rect: Rect2 = plan.block(k.x, k.y).rect
		print("BLOCK %s district=%d rect=%s build=%.0f ms" % [k, int(plan.block(k.x, k.y).district), rect, ms])
		print("  usec=%s worst_step=%s commit=%s cards=%s leaf_tris=%s shadow_tris=%s accent_tris=%s counts=%s" % [m.get("usec"), m.get("worst_usec"), 0, m.get("cards"), m.get("leaf_tris"), m.get("shadow_tris"), m.get("accent_tris"), m.get("counts")])
		for nm in ["Climbers", "ClimbersShadow", "ClimberAccents"]:
			var mi := ch.get_node_or_null(nm) as MeshInstance3D
			if mi:
				print("  NODE %s aabb=%s vis_end=%.0f" % [nm, mi.get_aabb(), mi.visibility_range_end])
		for s: Array in m.get("spots", []):
			var p: Vector3 = s[1]
			var n: Vector3 = s[2] if s.size() > 2 else Vector3(0, 0, 1)
			var e := p + n * 6.0
			print("  SPOT %-14s %.1f,%.1f  EYE=%.1f,1.6,%.1f,%.0f,2" % [s[0], p.x, p.z, e.x, e.z, rad_to_deg(atan2(n.x, n.z))])
		ch.free()
	city.free()
	get_tree().quit()
