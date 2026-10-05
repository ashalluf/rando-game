extends SceneTree
## Lists the street furniture (StreetFurniture) of the FULL chunks round a point, for framing stills:
##   godot --headless --path . --script tools/street_furniture_probe.gd -- --spawn=x,z,0,0
## R=blocks (default 2), KIND=meter|pay_station|bench_stop|hydrant|cart|rack|planter to filter,
## CARTS=all to put every block's carts out. Each line: the piece, its true-world point and an EYE
## for still_shot.gd 5 m along the pavement and 1.5 m in, looking at it. Classes are loaded at run
## time (the tool compiles before the autoloads exist). Headless: only the chunks' records are read.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var city = current_scene
	var plan = city.get("plan")
	var sf: GDScript = load("res://scripts/world/street_furniture.gd")
	var reach := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 2
	var want := OS.get_environment("KIND")
	var start: Vector2i = plan.block_index_at(c)
	var found := 0
	for ix in range(start.x - reach, start.x + reach + 1):
		for iz in range(start.y - reach, start.y + reach + 1):
			var chunk = city.call("_new_chunk", Vector2i(ix, iz), 0)
			chunk.call("build")
			var district: int = plan.district_at((plan.block(ix, iz).rect as Rect2).get_center())
			for r: Dictionary in chunk.get("prop_records"):
				var kind := String(r.kind)
				if kind == "meter":
					for inst in r.instances:
						kind = String(inst[0])
				if kind == "bus_stop" and sf.call("bench_stop", plan.seed, Vector3((r.position as Vector3).x, 0.12, (r.position as Vector3).z)):
					kind = "bench_stop"
				if not kind in ["meter", "pay_station", "bench_stop", "bus_stop", "hydrant", "cart", "rack", "planter"]:
					continue
				if want != "" and kind != want:
					continue
				var p: Vector3 = WorldState.to_world(r.position) if false else r.position
				var eye := Vector2(p.x, p.z) + Vector2(3.5, 3.5)
				var look := Vector2(p.x, p.z) - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				print("FURN %s %s block=%d,%d district=%d at=%.1f,%.2f,%.1f EYE=%.1f,%.1f,%.1f,%.0f,-14" % [kind, r.id, ix, iz, district, p.x, p.y, p.z, eye.x, p.y + 1.6, eye.y, yaw])
				found += 1
			chunk.get_parent().remove_child(chunk)
			chunk.free()
	print("FOUND ", found)
	quit()
