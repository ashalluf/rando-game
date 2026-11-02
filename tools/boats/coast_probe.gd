extends SceneTree
## The coast round the marina: zone, coast x and beach width at a few z (for picking test spots).
##   godot --headless --path . --script tools/boats/coast_probe.gd
func _initialize() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	print("marina outer ", macro.marina.outer_bounds())
	for z: float in [-2000.0, -1500.0, -1100.0, -700.0, 700.0, 1100.0, 1500.0]:
		var cx := macro.coast_x(z)
		print("z %6.0f coast %8.1f beach %5.1f zone sea %d zone land %d" % [z, cx, macro.beach_width_at(z), macro.zone_at(Vector2(cx - 200.0, z)), macro.zone_at(Vector2(cx + 10.0, z))])
	quit()
