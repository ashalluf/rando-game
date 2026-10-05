extends SceneTree
## Lists the micromobility round a point (Micromobility.plan_block, lane_on), for framing stills:
##   godot --headless --path . --script tools/micro_probe.gd -- --spawn=x,z,0,0
## R=metres (default 400), KIND=scooter|station|rack|lane to filter. Each line: what, the block and
## face (or road), its true-world point and an EYE for still_shot.gd looking at it. Headless is
## enough: only the plan is read (the scripts are loaded at run time, after the autoloads).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var mm: GDScript = load("res://scripts/world/micromobility.gd")
	var cc: GDScript = load("res://scripts/world/city_chunk.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 400.0
	var want := OS.get_environment("KIND")
	var names := ["scooter", "station", "rack"]
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 2
	var counts := {"scooter": 0, "station": 0, "rack": 0, "lane": 0}
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var block: Dictionary = plan.block(ix, iz)
			var rect: Rect2 = block.rect
			if rect.get_center().distance_to(c) > reach:
				continue
			var edges: Array = cc.call("_sidewalk_edges", rect)
			for v: Dictionary in mm.call("plan_block", plan, ix, iz):
				var kind: String = names[int(v.item)]
				counts[kind] += 1
				if want != "" and kind != want:
					continue
				var e: Array = edges[int(v.face)]
				var a: Vector2 = e[0]
				var b: Vector2 = e[1]
				var inward: Vector2 = e[2]
				var dir := (b - a).normalized()
				var p := a + dir * float(v.t) + inward * 1.0
				var eye := p + inward * 2.6 + dir * 6.5
				var look := p - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				var extra := ""
				if kind == "scooter":
					var fallen := 0
					for i in int(v.n):
						if mm.call("_h01", [plan.seed, ix, iz, String(v.id), i, "fall"]) < mm.get("FALLEN_SHARE"):
							fallen += 1
					extra = " fallen=%d gutter=%s tree=%s" % [fallen, str(v.gutter), str(v.tree)]
				print("MICRO %s block=%d,%d face=%d at=%.1f,%.1f n=%s%s EYE=%.1f,1.7,%.1f,%.0f,-14" % [
					kind, ix, iz, int(v.face), p.x, p.y, str(v.get("n", v.get("docks", ""))), extra, eye.x, eye.y, yaw])
			# The bike lanes on the block's +x and +z roads.
			for axis in 2:
				var index: int = ix + 1 if axis == 0 else iz + 1
				var k: int = iz if axis == 0 else ix
				if not mm.call("lane_on", plan, axis, index, k):
					continue
				counts.lane += 1
				if want != "" and want != "lane":
					continue
				var sp: Vector2 = mm.call("lane_span", plan, axis, index, k)
				var at: float = plan.road_pos(axis, index)
				var w: float = plan.road_width(axis, index)
				var mid := (sp.x + sp.y) * 0.5
				# Standing in the road's middle, looking down the +side lane.
				var eye := Vector2(at, sp.x - 2.0) if axis == 0 else Vector2(sp.x - 2.0, at)
				var yaw := 180.0 if axis == 0 else -90.0
				print("LANE axis=%d road=%d k=%d name=%s width=%.1f span=%.0f..%.0f style=%s EYE=%.1f,2.2,%.1f,%.0f,-8" % [
					axis, index, k, plan.road_name(axis, index), w, sp.x, sp.y, str(mm.call("lane_style", plan, axis, index)), eye.x, eye.y, yaw])
	print("COUNTS ", counts)
	quit()
