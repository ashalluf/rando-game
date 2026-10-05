extends Node
## Road hardware probe (RoadHardware): lists the blocks round a point with their roads (width,
## avenue or street, open) and an EYE on each road a few metres up, for block_shot / still_shot.
##
##   godot --headless --path . res://tools/road_detail/probe.tscn -- 900,600 [radius_blocks]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := Vector2(900, 600)
	var rad := 2
	if args.size() > 0:
		var p := args[0].split(",")
		at = Vector2(float(p[0]), float(p[1]))
	if args.size() > 1:
		rad = int(args[1])
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
	var c := plan.block_index_at(at)
	for dz in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var b := plan.block(c.x + dx, c.y + dz)
			var r: Rect2 = b.rect
			if plan.zone_at(r.get_center()) != MacroMap.Zone.CITY:
				continue
			for road in RoadHardware.roads_of(plan, c.x + dx, c.y + dz, r):
				var mid := (float(road.a) + float(road.b)) * 0.5
				var p := RoadHardware.road_point(road, float(road.a) + 14.0, float(road.w) * 0.25)
				var yaw := 0.0 if road.along_z else -90.0
				# Looking along +z is yaw 180 (yaw 0 looks north, -z).
				yaw = 180.0 if road.along_z else -90.0
				print("ROAD block %d,%d dist %s kind %s axis %d w %.1f len %.0f mid %.0f EYE=%.1f,1.6,%.1f,%.0f,-12" % [c.x + dx, c.y + dz, CityPlan.District.keys()[b.district], CityPlan.BlockKind.keys()[b.kind], road.axis, road.w, float(road.b) - float(road.a), mid, p.x, p.y, yaw])
	city.free()
	get_tree().quit()
