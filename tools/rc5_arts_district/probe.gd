extends SceneTree
## Lists the Arts District's (Industrial.arts()) industrial lots round a point - brick or tilt-up,
## murals, docks - with an EYE on the pavement across the street for each brick front:
##   godot --headless --path . --script tools/rc5_arts_district/probe.gd -- --spawn=x,z [R=blocks]
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2(4150, 300)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var city = current_scene
	var plan = city.get("plan")
	var ind: GDScript = load("res://scripts/world/industrial.gd")
	var r := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 1
	var k0: Vector2i = plan.block_index_at(c)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := k0 + Vector2i(dx, dz)
			var b: Dictionary = plan.block(k.x, k.y)
			var rr: Rect2 = plan.owned_rect(k.x, k.y)
			print("BLOCK %d,%d district=%d kind=%d rect=%s arts=%s" % [k.x, k.y, int(b.district), int(b.kind), str(rr), str(ind.call("arts", plan, rr.get_center()))])
			var chunk = city.call("_new_chunk", k, 0)
			chunk.build()
			var e: Dictionary = chunk.get("_ind")
			for en: Dictionary in e.get("entries", []):
				var lp: Dictionary = en.plan
				var lot: Dictionary = en.lot
				if lp.is_empty():
					print("  LOT bldg at %s size %s" % [str(lot.center), str(lot.get("size", ""))])
					continue
				var f: Dictionary = lp.frame
				var mid := (float(lp.u0) + float(lp.u1)) * 0.5
				var front: Vector2 = ind.call("fp", f, mid, float(lp.v0))
				var out: Vector2 = -(f.n as Vector2)
				var eye := front + out * 22.0
				var look := front - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				print("  WH brick=%s court=%.1f murals=%s h=%.1f front=%.1f,%.1f side=%d len=%.1f EYE=%.1f,1.7,%.1f,%.0f,6" % [str(lp.brick), float(lp.court), str(lp.murals), float(lp.h), front.x, front.y, int(lp.side), float(lp.u1) - float(lp.u0), eye.x, eye.y, yaw])
			chunk.queue_free()
	quit()
