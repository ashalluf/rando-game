extends Node
## The coast and the freeway round the power plant, printed (headless, seconds): coast_x and the
## beach's width every 50 m of z, the deck segments near, the line's towers. For framing the
## power_plant_dusk refcam.
##   godot --headless --path . res://tools/rc5_power_plant/coast_probe.tscn

func _ready() -> void:
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = MacroMap.new()
	plan.macro.seed = 1337
	plan.macro.setup()
	for z in range(800, 1650, 50):
		var cx := plan.macro.coast_x(float(z))
		print("COAST z %d coast_x %.1f beach_w %.1f zone(-660)=%s h(-680)=%.2f" % [z, cx, plan.macro.beach_width_at(float(z)),
			MacroMap.zone_name(plan.zone_at(Vector2(-660.0, float(z)))), plan.height_at(Vector2(-680.0, float(z)))])
	if plan.macro.freeway != null:
		for sg: Dictionary in plan.macro.freeway.segments_in(Rect2(-900.0, 900.0, 800.0, 400.0)):
			print("DECK %s %s route %s y %.1f" % [sg.a, sg.b, sg.get("route", -1), float(sg.get("ya", 0.0))])
	var ln := PowerPlant.line(plan)
	if not ln.is_empty():
		for t: Dictionary in ln.towers:
			print("TOWER %s h %.0f" % [t.pos, t.h])
	var lay := PowerPlant.layout(plan)
	print("RECT ", lay.get("rect"), " STACKS ", lay.get("stacks"), " GANTRY ", lay.get("gantry", {}).get("pos"))
	get_tree().quit()
