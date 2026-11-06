extends Node
## Prints one estate's plan in world space (wings, deck, pool, the view) and a refcam eye on its
## pool deck looking out over the view:
##   EST=392 godot --headless --path . res://tools/rc5_hill_home/probe.tscn

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var macro := MacroMap.new()
	macro.seed = city.world_seed
	var plan := CityPlan.new()
	plan.seed = macro.seed
	for key in ["block_size_range", "street_width", "avenue_width", "sidewalk_width", "downtown_radius", "midtown_radius"]:
		plan.set(key, city.get(key))
	plan.macro = macro
	city.free()
	macro.setup()
	var kit: GDScript = load("res://scripts/world/hill_home_kit.gd")
	for id_s in OS.get_environment("EST").split(","):
		var m: Dictionary = macro.hill_roads.mansions[int(id_s)]
		var hp: Dictionary = kit.plan_home(plan, m)
		print("EST %s %s floor %.2f Wp %.1f Dp %.1f fu %s fv %s o %s left %s" % [id_s, hp.style_name, hp.floor, hp.Wp, hp.Dp, hp.fu, hp.fv, hp.o, hp.get("left")])
		for w: Dictionary in hp.wings:
			print("  WING %s r %s y %.1f glass %s" % [w.role, w.r, w.y, w.glass])
		print("  DECK %s POOL %s" % [hp.deck, hp.pool])
		var pl: Dictionary = hp.pool
		if not pl.is_empty():
			var r: Rect2 = pl.r
			for c in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
				print("  POOLCORNER %s" % kit.frame_point(hp, c))
		var fv: Vector2 = hp.fv
		var yaw := rad_to_deg(atan2(-fv.x, -fv.y))
		print("  VIEWYAW %.1f" % yaw)
	get_tree().quit()
