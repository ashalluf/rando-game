extends RefCounted
## The rooms behind the windows, second pass (WindowInteriors; shaders/window_interiors.gdshaderinc,
## window_rooms.gdshaderinc, building.gdshader, building_lod.gdshader, house_glass.gdshader) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads.
## Checks: the include holds WindowInteriors' numbers and the shared integer hash; both building
## shaders include it (near and far roll the same homes, covers and TVs) and the near one traces the
## rooms; the rolls give the shares they promise; an open window is always drapes or sheers; the
## switch turns every building back into offices and the global follows it; the house glass has the
## passer-by and the new covers behind the switch.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	_check(WindowInteriors.enabled, "window interiors: on (WINDOW_INTERIORS is not 0)")
	_shader_mirror()
	_shares()
	_switch()
	print("WINDOW_INTERIORS_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _const(src: String, name: String) -> int:
	var m := RegEx.create_from_string("const int %s = ([0-9]+);" % name).search(src)
	return int(m.get_string(1)) if m != null else -1


func _shader_mirror() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/window_interiors.gdshaderinc")
	var bad: Array = []
	var homes := ["WI_HOME_PUNCHED", "WI_HOME_RIBBON", "WI_HOME_CURTAIN", "WI_HOME_NARROW"]
	for i in homes.size():
		if _const(src, homes[i]) != WindowInteriors.HOME_SHARE[i]:
			bad.append(homes[i])
	var covers := ["WI_COVER_DRAPES", "WI_COVER_SHEER", "WI_COVER_ROLLER", "WI_COVER_VENETIAN", "WI_COVER_VERTICAL"]
	for i in covers.size():
		if _const(src, covers[i]) != WindowInteriors.COVER_EDGES[i]:
			bad.append(covers[i])
	for pair: Array in [["WI_TV", WindowInteriors.TV], ["WI_OPEN", WindowInteriors.OPEN], ["WI_WALKER", WindowInteriors.WALKER],
			["WI_WORKER", WindowInteriors.WORKER]]:
		if _const(src, pair[0]) != pair[1]:
			bad.append(pair[0])
	# The same integer hash (window_lights' wl_hash) and the salts the GDScript copy uses.
	for s: String in ["wl_hash(key, salt) % 1000u", "wi_pm(sd, 100u)", "wi_pm(key, 101u)", "wi_pm(key, 102u)", "wi_pm(key, 103u)",
			"wi_pm(key, 104u)", "wi_pm(key, 106u)", "wl_face_row(b_seed, face, row) + uint(clamp(col, 0.0, 255.0))"]:
		if not src.contains(s):
			bad.append(s)
	_check(bad.is_empty(), "window interiors: the shader include holds WindowInteriors' numbers and hash (%s)" % str(bad))
	# Equal rolls on both sides of the LOD line: both building shaders include it, after window_lights.
	var near := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	var far := FileAccess.get_file_as_string("res://shaders/building_lod.gdshader")
	var inc := "#include \"res://shaders/window_interiors.gdshaderinc\""
	var wl := "#include \"res://shaders/window_lights.gdshaderinc\""
	_check(near.find(inc) > near.find(wl) and near.find(wl) >= 0 and far.find(inc) > far.find(wl) and far.find(wl) >= 0,
		"window interiors: the near walls and the far boxes include the same rolls, after window_lights")
	_check(near.contains("window_rooms.gdshaderinc") and near.contains("home_room(") and near.contains("office_people("),
		"window interiors: the near walls trace the homes and the offices' people")
	_check(far.contains("wi_home(sd, ws)") and far.contains("wi_cover_mean(") and far.contains("wi_home_tone(wk)"),
		"window interiors: the far boxes draw a home's covers at their average and its lamps in its own tone")
	var house := FileAccess.get_file_as_string("res://shaders/house_glass.gdshader")
	_check(house.contains("window_interiors > 0.5") and house.contains("drapes") and house.contains("roller"),
		"window interiors: the house glass has the passer-by, the drapes and the roller blinds behind the switch")


func _shares() -> void:
	# Homes per window style, over every building seed.
	var bad: Array = []
	for style in 4:
		var n := 0
		for sd in 1000:
			if WindowInteriors.home(sd, style):
				n += 1
		if absi(n - WindowInteriors.HOME_SHARE[style]) > 45:
			bad.append("style %d: %d" % [style, n])
	_check(bad.is_empty(), "window interiors: the share of homes per window style is what it promises (%s)" % str(bad))
	# Covers, TVs, open windows over a few thousand windows of a few buildings.
	var counts := [0, 0, 0, 0, 0, 0]
	var tv := 0
	var opened := 0
	var open_bad := 0
	var walk := 0
	var n := 0
	for sd in [3, 7, 121, 640]:
		for face in range(1, 5):
			for row in 12:
				for col in 16:
					var k := WindowInteriors.key(sd, face, row, col)
					counts[WindowInteriors.cover(k)] += 1
					if WindowInteriors.tv(k):
						tv += 1
					if WindowInteriors.walker(k):
						walk += 1
					if WindowInteriors.open_window(k):
						opened += 1
						var c := WindowInteriors.cover(k)
						if c != WindowInteriors.Cover.DRAPES and c != WindowInteriors.Cover.SHEER:
							open_bad += 1
					n += 1
	var edges: Array[int] = WindowInteriors.COVER_EDGES
	var want := [edges[0], edges[1] - edges[0], edges[2] - edges[1], edges[3] - edges[2], edges[4] - edges[3], 1000 - edges[4]]
	var off: Array = []
	for i in 6:
		var got := 1000.0 * float(counts[i]) / float(n)
		if absf(got - float(want[i])) > 40.0:
			off.append("cover %d: %.0f / %d" % [i, got, want[i]])
	_check(off.is_empty(), "window interiors: what hangs at a home's windows comes in its promised shares (%s)" % str(off))
	_check(absf(1000.0 * tv / n - WindowInteriors.TV) < 40.0 and absf(1000.0 * walk / n - WindowInteriors.WALKER) < 40.0,
		"window interiors: TVs and passers-by in their shares (%d, %d of %d)" % [tv, walk, n])
	_check(opened > 0 and open_bad == 0, "window interiors: some windows stand open, always behind drapes or sheers (%d, %d wrong)" % [opened, open_bad])


func _switch() -> void:
	var was := WindowInteriors.enabled
	WindowInteriors.set_enabled(false)
	var any := false
	for sd in 200:
		if WindowInteriors.home(sd, 0):
			any = true
	# The dummy renderer may hand the global back as null: then only the rolls are checked.
	var v_off: Variant = RenderingServer.global_shader_parameter_get("window_interiors")
	WindowInteriors.set_enabled(was)
	var v_on: Variant = RenderingServer.global_shader_parameter_get("window_interiors")
	var g_off := float(v_off) if v_off != null else 0.0
	var g_on := float(v_on) if v_on != null else (1.0 if was else 0.0)
	_check(not any and is_equal_approx(g_off, 0.0) and is_equal_approx(g_on, 1.0 if was else 0.0),
		"window interiors: off, every building is offices again and the global follows (%s -> %s)" % [g_off, g_on])
