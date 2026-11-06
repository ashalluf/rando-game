extends SceneTree
## What stands at a few world points under the ridge-sign refcam (zone, block, kind, site, height).
##   godot --headless --path . --script tools/rc3_ridge_sign/spot_probe.gd -- 546,-853 337,-839

func _initialize() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	plan.macro.setup()
	for a in OS.get_cmdline_user_args():
		var xy := a.split(",")
		var p := Vector2(float(xy[0]), float(xy[1]))
		var bi: Vector2i = plan.block_index_at(p)
		var b: Dictionary = plan.block(bi.x, bi.y)
		var keys := {}
		for k in b.keys():
			if typeof(b[k]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL, TYPE_STRING_NAME]:
				keys[k] = b[k]
		print("SPOT ", p, " zone ", plan.zone_at(p), " h ", snappedf(plan.height_at(p), 0.1), " block ", bi, " lots ", plan.lots(bi.x, bi.y).size(), " ", keys)
	for a in OS.get_environment("LOTS").split(";", false):
		var ij := a.split(",")
		var lots: Array = plan.lots(int(ij[0]), int(ij[1]))
		print("LOTS ", a, " n ", lots.size(), " block ", plan.block(int(ij[0]), int(ij[1])).keys())
		for l: Dictionary in lots:
			var d := {}
			for k in l.keys():
				if typeof(l[k]) != TYPE_DICTIONARY and typeof(l[k]) != TYPE_ARRAY:
					d[k] = l[k]
			print("   ", d)
	city.free()
	quit()
