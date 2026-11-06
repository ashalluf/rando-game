extends SceneTree
## Prints one tower site's layout (foot, cell, gate, walkway, hoist, crane) for framing a camera:
##   godot --headless --path . --script tools/construction/site_probe.gd -- --block=30,0
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var bx := 0
	var bz := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--block="):
			var p := arg.trim_prefix("--block=").split(",")
			bx = int(p[0])
			bz = int(p[1])
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var con: GDScript = load("res://scripts/world/construction.gd")
	var t: Dictionary = con.call("tower_site", plan, bx, bz)
	if t.is_empty():
		print("SITE none")
		quit()
		return
	print("SITE foot=%s cell=%s street=%s gate=%d walk=%d hoist=%d built=%d clad=%d top=%.1f core=%s" % [t.foot, t.cell, t.street, t.gate, t.walkway, t.hoist, t.built, t.clad, t.top, t.core])
	print("CRANE %s" % [t.crane])
	print("BLOCK %s ground=%.2f" % [plan.block(bx, bz).rect, plan.height_at((t.foot as Rect2).get_center())])
	quit()
