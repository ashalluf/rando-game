extends SceneTree
## The houses round the suburb_night refcam and their HouseNights rolls at 21:30 (rc5-suburb-night):
##   godot --headless --path . --script tools/rc5_suburb_night/house_probe.gd -- --spawn=1979,4256.8
## Each line: the lot's centre (TRUE world), distance from the spawn, the house key, dark (nobody
## home), the share of rooms lit at HOUR (default 21.5), TV, porch light.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2(1979.0, 4256.8)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 21.5
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var hk: GDScript = load("res://scripts/world/house_kit.gd")
	var hn: GDScript = load("res://scripts/world/house_nights.gd")
	var start: Vector2i = plan.block_index_at(c)
	for ix in range(start.x - 2, start.x + 3):
		for iz in range(start.y - 2, start.y + 3):
			var b: Dictionary = plan.block(ix, iz)
			var lots: Array = plan.lots(ix, iz)
			lots.append_array(hk.extra_lots(plan, ix, iz))
			for lot: Dictionary in lots:
				var h: Dictionary = hk.plan_house(plan, ix, iz, lot, int(b.district))
				if h.is_empty() or not h.has("seed"):
					continue
				var at: Vector2 = lot.get("center", Vector2.ZERO)
				var d := at.distance_to(c)
				if d > 90.0:
					continue
				var k: int = hn.key(int(h.seed))
				print("HOUSE at %.0f,%.0f d %.0f key %d dark %s share %.2f tv %s porch %s" % [at.x, at.y, d, k,
					hn.dark(k), hn.share(k, hour), hn.tv(k), hn.porch_on(k)])
	quit()
