extends Node
## rc4-refinery-road probe (headless, seconds): the refinery's rect, its perimeter roads, the
## flares and masts the road takes light from, and RcRefineryRoad.light_at() along the south street.
##   godot --headless --path . res://tools/rc4_refinery_road/probe.tscn

func _ready() -> void:
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
	var lay := Refinery.layout(plan)
	print("RECT ", lay.rect, " INNER ", lay.inner)
	for axis in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var c: Vector2 = (lay.rect as Rect2).get_center()
		var i0 := plan.block_index_at(c - (lay.rect as Rect2).size * 0.6)
		var i1 := plan.block_index_at(c + (lay.rect as Rect2).size * 0.6)
		var a := (i0.x if axis == CityPlan.AXIS_X else i0.y)
		var b := (i1.x if axis == CityPlan.AXIS_X else i1.y)
		for i in range(a - 1, b + 3):
			print("ROAD axis %d idx %d pos %.1f w %.1f perimeter %s" % [axis, i, plan.road_pos(axis, i), plan.road_width(axis, i), RcRefineryRoad.perimeter_road(plan, axis, i)])
	for f in RcRefineryRoad.flares(lay, plan):
		print("FLARE ", f)
	for m in RcRefineryRoad.masts(lay, plan):
		print("MAST ", m)
	var gy := plan.height_at(Vector2(3180, 5838))
	for x in range(2700, 3300, 50):
		print("LIGHT x %d: %.3f" % [x, RcRefineryRoad.light_at(lay, plan, Vector3(x, gy, 5838))])
	print("LAMP ", RcRefineryRoad.lamp_state(plan, Vector2(3180, 5845)))
	get_tree().quit()
