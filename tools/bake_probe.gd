extends SceneTree
## Times MacroMap.bake() at several resolutions and reports metres per texel, so the horizon
## bake's resolution is chosen from numbers rather than from a guess. Run headless:
##
##   godot --headless --path . --script tools/bake_probe.gd
func _initialize() -> void:
	var plan := CityPlan.new()
	plan.seed = 1337
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	plan.macro = macro
	var span := 16000.0
	for size in [160, 256, 384, 512]:
		var t0 := Time.get_ticks_msec()
		var img: Image = macro.bake(Vector2.ZERO, span, size)
		var ms := Time.get_ticks_msec() - t0
		print("size=", size, " metres_per_texel=", span / float(size), " ms=", ms,
			" kb=", img.get_data().size() / 1024)
	quit()
