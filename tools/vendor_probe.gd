extends SceneTree
## Lists the street vendors (StreetVendors.plan_block) round a point at an hour, for framing stills:
##   godot --headless --path . --script tools/vendor_probe.gd -- --spawn=x,z,0,0 [--hour=21]
## R=metres (default 400), KIND=truck|fruit|elote|hotdog|paleta|flowers to filter.
## Each line: kind, place, the block and face, the stand's true-world point on the pavement (or
## the truck's lane point) and an EYE for still_shot.gd 7 m out on the pavement looking at it.
## Headless is enough: only the plan is read (StreetVendors is loaded at run time, so the tool
## compiles before the autoloads exist).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	var hour := 21.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
		if arg.begins_with("--hour="):
			hour = arg.trim_prefix("--hour=").to_float()
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var sv: GDScript = load("res://scripts/world/street_vendors.gd")
	var cc: GDScript = load("res://scripts/world/city_chunk.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 400.0
	var want := OS.get_environment("KIND")
	var names := ["truck", "fruit", "elote", "hotdog", "paleta", "flowers"]
	var places := ["none", "downtown", "midtown", "industrial", "park", "macarthur", "arena", "beach"]
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 2
	var found := 0
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var block: Dictionary = plan.block(ix, iz)
			var rect: Rect2 = block.rect
			if rect.get_center().distance_to(c) > reach:
				continue
			var edges: Array = cc.call("_sidewalk_edges", rect)
			for v: Dictionary in sv.call("plan_block", plan, ix, iz, hour):
				var kind: String = names[int(v.kind)]
				if want != "" and kind != want:
					continue
				var e: Array = edges[int(v.face)]
				var a: Vector2 = e[0]
				var b: Vector2 = e[1]
				var inward: Vector2 = e[2]
				var dir := (b - a).normalized()
				var p := a + dir * float(v.t) + inward * 1.5
				var eye := p + inward * 2.0 + dir * 7.0
				var look := p - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				print("VENDOR %s %s block=%d,%d face=%d at=%.1f,%.1f hours=%.1f-%.1f EYE=%.1f,1.7,%.1f,%.0f,-4" % [
					kind, places[int(v.place)], ix, iz, int(v.face), p.x, p.y, v.hours.x, v.hours.y, eye.x, eye.y, yaw])
				found += 1
	print("FOUND ", found)
	quit()
