extends Node
## Lists the hillside estates and the house HillHomeKit plans on each, in seconds, without a city:
##   godot --headless --path . res://tools/hill_homes/probe.tscn
## One line per estate: position, pad height and radius, the road's bed, how far the ground falls
## off the pad's sides, and the plan (style, view side, cantilever, floors). SEED= another seed.
## EYE=1 adds a still_shot.gd EYE per estate looking up at the house from its downhill side.

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var macro := MacroMap.new()
	var seed_env := OS.get_environment("SEED")
	macro.seed = int(seed_env) if seed_env != "" else city.world_seed
	var plan := CityPlan.new()
	plan.seed = macro.seed
	for key in ["block_size_range", "street_width", "avenue_width", "sidewalk_width", "downtown_radius", "midtown_radius"]:
		plan.set(key, city.get(key))
	plan.macro = macro
	city.free()
	macro.setup()
	var hr: HillRoads = macro.hill_roads
	var styles := {}
	var t0 := Time.get_ticks_usec()
	var n := 0
	for m: Dictionary in hr.mansions:
		var gc := plan.height_at(m.pos)
		var line := "EST %4d ground %6.1f pos %7.1f %7.1f h %6.1f r %4.1f road %6.1f" % [n, gc, m.pos.x, m.pos.y, m.height, m.get("radius", HillRoads.PAD_RADIUS), m.get("drive_h", m.height)]
		if ClassDB.class_exists("HillHomeKit") or ResourceLoader.exists("res://scripts/world/hill_home_kit.gd"):
			var kit: GDScript = load("res://scripts/world/hill_home_kit.gd")
			var hp: Dictionary = kit.plan_home(plan, m)
			styles[hp.style_name] = int(styles.get(hp.style_name, 0)) + 1
			line += "  %s view %s drop %.1f over %.1f wings %d" % [hp.style_name, hp.view_side, hp.drop, hp.get("cantilever", 0.0), (hp.wings as Array).size()]
			if OS.get_environment("EYE") != "":
				line += "  EYE=%s AGL=%s" % [hp.eye, hp.eye_agl]
		print(line)
		n += 1
	# VIEWS=4,138 prints camera bookmarks (hill_ground_shot.gd EYE / SHOTS, y over the ground)
	# for those estates: from the slope below (two angles), from the air, and in the motor court.
	var ids := OS.get_environment("VIEWS")
	if ids != "":
		var kit: GDScript = load("res://scripts/world/hill_home_kit.gd")
		for id_s in ids.split(","):
			var m: Dictionary = hr.mansions[int(id_s)]
			var hp: Dictionary = kit.plan_home(plan, m)
			var fu: Vector2 = hp.fu
			var fv: Vector2 = hp.fv
			var tgt2: Vector2 = kit.frame_point(hp, Vector2(float(hp.Wp) * 0.5, float(hp.Dp)))
			var tgt := Vector3(tgt2.x, float(hp.floor) + 1.0, tgt2.y)
			var views := {"below": [42.0, 16.0, -1.0], "below2": [30.0, -22.0, -1.0], "air": [75.0, 25.0, 40.0], "court": [-30.0, 6.0, 1.7], "far": [260.0, 40.0, -1.0]}
			var out := []
			for name: String in views:
				var v: Array = views[name]
				var e2: Vector2 = tgt2 + fv * float(v[0]) + fu * float(v[1])
				var gy := plan.height_at(e2)
				var ey: float = gy + 1.7 if float(v[2]) < 0.0 else (float(hp.floor) + float(v[2]) if name == "air" else gy + float(v[2]))
				if name == "court":
					e2 = kit.frame_point(hp, Vector2(float(hp.Wp) * 0.5, 1.5))
					ey = float(hp.floor) + 1.5
					tgt = Vector3(tgt2.x, float(hp.floor) + 2.0, tgt2.y)
				var d := tgt - Vector3(e2.x, ey, e2.y)
				var yaw := rad_to_deg(atan2(-d.x, -d.z))
				var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
				out.append("%.1f,%.1f,%.1f,%.0f,%.0f" % [e2.x, ey - plan.height_at(e2), e2.y, yaw, pitch])
				print("VIEW %s %s %s" % [id_s, name, out[out.size() - 1]])
			print("SHOTS %s %s" % [id_s, ";".join(out)])
	print("ESTATES %d  plan %.1f ms  %s" % [n, (Time.get_ticks_usec() - t0) / 1000.0, str(styles)])
	get_tree().quit()
