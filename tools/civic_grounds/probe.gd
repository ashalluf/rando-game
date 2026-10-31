extends Node
## The civic centre's sites and the ground their blocks leave over (CivicGrounds), headless, seconds.
##   godot --headless --path . res://tools/civic_grounds/probe.tscn (env SEED=n)

func _ready() -> void:
	await get_tree().process_frame
	var seed_value := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var plan := GroundCoverage.make_plan(seed_value)
	for id: String in ["ziggurat_hall", "civic_park", "concert_hall", "lattice_museum"]:
		var info := CivicSites.site(plan, id)
		print("SITE %s anchor %s block %s site %s yaw %.2f y0 %.2f" % [id, CivicSites.anchor(id), Landmarks.site_rect(plan, CivicSites.anchor(id)), info.world, info.yaw, info.y0])
		if ClassDB.class_exists("CivicGrounds") or ResourceLoader.exists("res://scripts/world/civic_grounds.gd"):
			var g: GDScript = load("res://scripts/world/civic_grounds.gd")
			print("  LEFT ", g.leftovers(plan, id))
	for x in range(2750, 3300, 100):
		var bi := plan.block_index_at(Vector2(x, -934))
		var b := plan.block(bi.x, bi.y)
		print("BLOCK x %d %s kind %s site %s grounds %s" % [x, bi, b.kind, b.get("site", ""), b.get("grounds", "")])
	get_tree().quit()
