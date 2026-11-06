extends RefCounted
## Body of tools/rc5_fire_station/probe.gd.

func run(_tree: SceneTree) -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	var s = scene.instantiate()
	var plan := CityPlan.new()
	plan.seed = s.world_seed
	plan.block_size_range = s.block_size_range
	plan.street_width = s.street_width
	plan.avenue_width = s.avenue_width
	plan.sidewalk_width = s.sidewalk_width
	plan.downtown_radius = s.downtown_radius
	plan.midtown_radius = s.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	var r := float(OS.get_environment("RADIUS")) if OS.get_environment("RADIUS") != "" else 3500.0
	var c := Vector2(2800, 100)
	var n := int(ceil(r / FireStation.CELL))
	var c0 := Vector2i(floori(c.x / FireStation.CELL), floori(c.y / FireStation.CELL))
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			var st := FireStation.for_cell(plan, c0 + Vector2i(dx, dz))
			if st.is_empty():
				continue
			var front: Vector2 = st.front
			var b: Dictionary = plan.block((st.block as Vector2i).x, (st.block as Vector2i).y)
			var f: Dictionary = st.frame
			var out2: Vector2 = -(f.n as Vector2)
			var a2: Vector2 = f.a
			var w := plan.road_width(int(st.road[0]), int(st.road[1]))
			# Across the street on the far pavement, a little to one side, looking back at the bays.
			var e := front + out2 * (w * 0.5 + 2.0) + a2 * 9.0
			var tgt := front - out2 * 8.0
			var d := tgt - e
			var yaw := rad_to_deg(atan2(-d.x, -d.y))
			var bb := StationExit.bays(plan, st)
			if not bb.is_empty():
				var face: Vector2 = bb.face
				print("   BAYS face (%.1f, %.1f) y %.2f doors %s to_kerb %.1f depth %.1f x (%.2f, %.2f)" % [face.x, face.y, bb.y, bb.doors, bb.to_kerb, bb.depth, (bb.x as Vector2).x, (bb.x as Vector2).y])
			print("STATION %d cell %s block %s district %d street '%s' w %.1f front (%.1f, %.1f) out (%.2f, %.2f) along (%.2f, %.2f) h %.1f EYE %.1f,%.1f,%.1f,%.1f,-2" % [
				st.number, st.cell, st.block, int(b.district), plan.road_name(int(st.road[0]), int(st.road[1])), w,
				front.x, front.y, out2.x, out2.y, a2.x, a2.y, plan.height_at(front), e.x, plan.height_at(e) + 1.7, e.y, yaw])
