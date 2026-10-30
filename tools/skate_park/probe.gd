extends SceneTree
## THE PIT's probe (SkatePark, SkateParkLife): builds the park's geometry on its own, prints its
## size, samples every skater line and checks each against the surface, prints EYEs for stills.
## Headless, seconds:
##   godot --headless --path . --script tools/skate_park/probe.gd
## Under --script the autoloads are missing, so SkateParkLife is loaded by path.

func _initialize() -> void:
	var t0 := Time.get_ticks_usec()
	var g := SkatePark.Geo.new(true)
	SkatePark._build_geo(g, PackedVector2Array([Vector2(14.0, -7.5), Vector2(14.0, 7.5)]), true)
	print("SKATE geometry near: %d triangles, %.1f ms" % [g.verts.size() / 3, (Time.get_ticks_usec() - t0) / 1000.0])
	var gf := SkatePark.Geo.new(false)
	SkatePark._build_geo(gf, PackedVector2Array(), false)
	print("SKATE geometry far: %d triangles" % [gf.verts.size() / 3])
	for k in ["pool", "snake"]:
		pass
	print("SKATE surface pool centre %.2f deck %.2f terrace %.2f stairs mid %.2f mini lip %.2f" % [
		SkatePark.surface_y(SkatePark.POOL_C), SkatePark.surface_y(Vector2(-14.0, -21.0)),
		SkatePark.surface_y(Vector2(0.0, 10.0)), SkatePark.surface_y(Vector2(4.0, 1.5)),
		SkatePark.mini_y(SkatePark.MINI_ZC + SkatePark.MINI_FLAT * 0.5 + SkatePark.mini_reach())])
	var life: GDScript = load("res://scripts/world/skate_park_life.gd")
	for name: String in ["pool", "snake", "mini", "street", "stairs"]:
		var t1 := Time.get_ticks_usec()
		var tb: Dictionary = life.sample(name)
		var pos: PackedVector3Array = tb.pos
		var worst_step := 0.0
		var below := 0.0
		var air := 0
		for i in pos.size():
			var a := pos[i]
			var b := pos[(i + 1) % pos.size()]
			worst_step = maxf(worst_step, Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)))
			below = maxf(below, SkatePark.surface_y(Vector2(a.x, a.z)) - a.y)
			if int(tb.pose[i]) == 2:
				air += 1
		print("SKATE line %s: %.1f s, %d samples, max step %.2f m (%.1f m/s), worst below surface %.3f m, %d air samples, %.0f ms" % [
			name, tb.length, pos.size(), worst_step, worst_step * 30.0, below, air, (Time.get_ticks_usec() - t1) / 1000.0])
	quit()
