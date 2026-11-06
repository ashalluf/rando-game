extends SceneTree
## Lists the street performers (Buskers.plan_block) round a point at an hour, for framing stills:
##   godot --headless --path . --script tools/buskers/probe.gd -- --spawn=x,z,0,0 [--hour=15]
## R=metres (default 600), KIND=guitar|drums|break|statue|mariachi to filter. Each line: kind,
## place, block and face (-1: a plaza), the performer's true-world point and an EYE for
## still_shot.gd 6 m off on the pavement looking at them. Headless: only the plan is read.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	var hour := 15.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
		if arg.begins_with("--hour="):
			hour = arg.trim_prefix("--hour=").to_float()
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var bk: GDScript = load("res://scripts/world/buskers.gd")
	var cc: GDScript = load("res://scripts/world/city_chunk.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 600.0
	var want := OS.get_environment("KIND")
	var names := ["guitar", "drums", "break", "statue", "mariachi"]
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 2
	var found := {}
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var block: Dictionary = plan.block(ix, iz)
			var rect: Rect2 = block.rect
			if rect.get_center().distance_to(c) > reach:
				continue
			for v: Dictionary in bk.call("plan_block", plan, ix, iz, hour):
				var kind: String = names[int(v.kind)]
				if want != "" and kind != want:
					continue
				var p: Vector2
				var eye: Vector2
				if int(v.face) < 0:
					var inner := rect.grow(-2.0)
					var axis := Vector2(1, 0) if inner.size.x >= inner.size.y else Vector2(0, 1)
					p = inner.get_center() + axis * (1.0 if int(v.slot) == 0 else -1.0) * (minf(inner.size.x, inner.size.y) * 0.12 + 6.5)
					eye = p + Vector2(axis.y, axis.x) * 7.0
				else:
					var e: Array = cc.call("_sidewalk_edges", rect)[int(v.face)]
					var a: Vector2 = e[0]
					var dir := ((e[1] as Vector2) - a).normalized()
					var inward: Vector2 = e[2]
					p = a + dir * float(v.t) + inward * 3.15
					eye = a + dir * (float(v.t) + 5.0) + inward * 0.9
				var look := p - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				print("BUSKER %s place=%d block=%d,%d face=%d at=%.1f,%.1f hours=%.1f-%.1f EYE=%.1f,1.7,%.1f,%.0f,-6" % [
					kind, int(v.place), ix, iz, int(v.face), p.x, p.y, v.hours.x, v.hours.y, eye.x, eye.y, yaw])
				found[kind] = int(found.get(kind, 0)) + 1
	print("FOUND ", found)
	quit()
