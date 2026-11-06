extends SceneTree
## Lists the grid street stretches along the coast whose owning chunk is beach or ocean (sand laid
## over the road strip) and whether CityPlan / the traffic call them open. Headless, seconds:
##   godot --headless --path . --script tools/rc_beach/sand_roads_probe.gd
## Z0, Z1 (default -1500, 2500).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var z0 := float(OS.get_environment("Z0")) if OS.get_environment("Z0") != "" else -1500.0
	var z1 := float(OS.get_environment("Z1")) if OS.get_environment("Z1") != "" else 2500.0
	var sr: GDScript = load("res://scripts/npc/sand_roads.gd")
	var a: Vector2i = plan.block_index_at(Vector2(plan.macro.coast_x(z0) - 200.0, z0))
	var b: Vector2i = plan.block_index_at(Vector2(plan.macro.coast_x(z1) + 600.0, z1))
	var n := 0
	for ax in [0, 1]:
		var i0: int = mini(a.x, b.x) if ax == 0 else a.y
		var i1: int = maxi(a.x, b.x) if ax == 0 else b.y
		for index in range(i0, i1 + 1):
			var along: float = z0 if ax == 0 else plan.macro.coast_x(plan.road_pos(1, index)) - 100.0
			var stop: float = z1 if ax == 0 else along + 900.0
			while along < stop:
				var p: Vector2 = Vector2(plan.road_pos(0, index), along) if ax == 0 else Vector2(along, plan.road_pos(1, index))
				var sand: bool = sr.call("on_sand", plan, ax, index, along)
				if sand and plan.road_open(ax, index, along):
					print("SAND axis=%d index=%d at=%.0f,%.0f zone=%d" % [ax, index, p.x, p.y, plan.zone_at(p)])
					n += 1
				along += 25.0
	print("SAND_TOTAL ", n)
	quit()
