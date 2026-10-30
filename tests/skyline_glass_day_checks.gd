extends RefCounted
## The skyline's glass by day (SkylineGlass, shaders/skyline_glass.gdshaderinc, docs/HANDOFF.md
## "The skyline's glass by day"): checks for tests/smoke_test.gd. Loaded at run time, so it
## compiles after the autoloads. No shader runs under --headless, so the CPU side is held to the
## shader source; tools/glshot/still_shot.gd (SHOTS, SKYLINE_GLASS=0 the before) shows the pixels.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_packing_round_trips()
	_landmarks_are_inside_their_plans()
	_pick_is_the_tallest_for_their_distance()
	_shaders_share_it()
	_the_node_feeds_the_globals(city)


## The half sizes ride in one float (round(hx * 4) + round(hz * 4) * 1024), decoded by the shader.
func _packing_round_trips() -> void:
	var why := ""
	for h: Vector2 in [Vector2(21.0, 29.0), Vector2(0.25, 255.75), Vector2(14.6, 14.6), Vector2(70.0, 3.5)]:
		var back := SkylineGlass.unpack_half(SkylineGlass.pack_half(h))
		if back.distance_to(h) > 0.13:
			why += " %s -> %s" % [h, back]
	var mats := SkylineGlass.pack([[Vector2(2800.0, 100.0), Vector2(20.0, 30.0), 200.0]])
	if mats.size() != 2 or not is_equal_approx(mats[0].x.w, 200.0) or mats[0].y.w > -1000.0 or mats[1].w.w > -1000.0:
		why += " the slots %s" % [mats]
	_t._check(why == "", "the skyline glass's tower boxes pack into two mat4s and back%s" % why)


## Every downtown tower is a box (a pair two) inside its own plan, as tall as the table says.
func _landmarks_are_inside_their_plans() -> void:
	var why := ""
	var boxes := SkylineGlass.landmark_boxes()
	var pairs := 0
	for id: String in LandmarkDowntown.TOWERS:
		var plan: Vector2 = LandmarkDowntown.TOWERS[id].plan
		if maxf(plan.x, plan.y) > minf(plan.x, plan.y) * 2.2:
			pairs += 1
	if boxes.size() != LandmarkDowntown.TOWERS.size() + pairs:
		why += " %d boxes for %d towers (%d pairs)" % [boxes.size(), LandmarkDowntown.TOWERS.size(), pairs]
	for b: Array in boxes:
		var inside := false
		for id: String in LandmarkDowntown.TOWERS:
			var row: Dictionary = LandmarkDowntown.TOWERS[id]
			var foot := Rect2(LandmarkDowntown.anchor(id) - (row.plan as Vector2) * 0.5, row.plan).grow(0.01)
			var box := Rect2((b[0] as Vector2) - (b[1] as Vector2), (b[1] as Vector2) * 2.0)
			if foot.encloses(box) and absf(float(b[2]) - LandmarkDowntown.BASE_Y - float(row.height)) < 0.01:
				inside = true
				break
		if not inside:
			why += " box %s outside every plan" % [b]
			break
	_t._check(why == "", "every downtown tower is a skyline glass box inside its plan, a pair two%s" % why)


## pick(): at most eight, none past REACH or under MIN_HEIGHT, the tallest for their distance
## first; from Pershing Square the sail and the round tower are among them.
func _pick_is_the_tallest_for_their_distance() -> void:
	var why := ""
	var cands := SkylineGlass.landmark_boxes()
	cands.append([Vector2(2810.0, 110.0), Vector2(10.0, 10.0), 30.0])
	var cam := Vector3(DowntownReal.GAME_ANCHOR.x, 60.0, DowntownReal.GAME_ANCHOR.y)
	var got := SkylineGlass.pick(cands, cam)
	if got.size() != SkylineGlass.SLOTS:
		why += " %d picked" % got.size()
	var last := INF
	for b: Array in got:
		var d := (b[0] as Vector2).distance_to(Vector2(cam.x, cam.z))
		var s := float(b[2]) / maxf(d, 60.0)
		if s > last + 1e-6:
			why += " out of order"
		last = s
		if float(b[2]) < SkylineGlass.MIN_HEIGHT or d > SkylineGlass.REACH:
			why += " %s should not be picked" % [b]
	for id: String in ["dt_sail_tower", "dt_crown_cylinder"]:
		var at := LandmarkDowntown.anchor(id)
		var found := false
		for b: Array in got:
			if (b[0] as Vector2).distance_to(at) < 1.0:
				found = true
		if not found:
			why += " %s not picked" % id
	if not SkylineGlass.pick(cands, Vector3(-9000.0, 0.0, -9000.0)).is_empty():
		why += " picked from 10 km away"
	_t._check(why == "", "the skyline glass traces the tallest towers for their distance, eight at most%s" % why)


## The three shaders include it, behind the switch, and decode what pack() writes; the globals
## exist with the old look as their default.
func _shaders_share_it() -> void:
	var why := ""
	for p: String in ["res://shaders/building.gdshader", "res://shaders/building_lod.gdshader", "res://shaders/tower_crown.gdshader"]:
		var src := FileAccess.get_file_as_string(p)
		if src.find('#include "res://shaders/skyline_glass.gdshaderinc"') < 0:
			why += " %s lacks the include" % p.get_file()
		for want: String in ["sg_on()", "sg_clouds(", "sg_towers(", "sg_glint("]:
			if src.find(want) < 0:
				why += " %s lacks %s" % [p.get_file(), want]
		var sh: Shader = load(p)
		if sh.get_shader_uniform_list().is_empty():
			why += " %s did not compile" % p.get_file()
	var inc := FileAccess.get_file_as_string("res://shaders/skyline_glass.gdshaderinc")
	for want: String in ["floor(tw.z / 1024.0)", "tw.z - hz4 * 1024.0, hz4) * 0.25", "tw.w < -1000.0",
			"const vec3 SG_OLD_TOP = vec3(0.26, 0.44, 0.80);", "const vec3 SG_OLD_RIM = vec3(0.42, 0.47, 0.55);"]:
		if inc.find(want) < 0:
			why += " the include lost '%s'" % want
	for g: String in ["skyline_glass", "skyline_sky_top", "skyline_sky_rim", "skyline_towers_a", "skyline_towers_b"]:
		if not ProjectSettings.has_setting("shader_globals/" + g):
			why += " no global %s" % g
	var top: Variant = ProjectSettings.get_setting("shader_globals/skyline_sky_top", {}).get("value")
	if not (top is Vector4) or (top as Vector4).distance_to(Vector4(0.26, 0.44, 0.8, 0.0)) > 1e-4:
		why += " the default zenith %s" % [top]
	# The near glass's frame lines go to coverage only with it on, and never on a shopfront.
	var near := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	if near.find("if (sg_on() && !storefront && px_m > 0.02 * pitch) {") < 0:
		why += " the frame filter lost its switch"
	_t._check(why == "", "the near walls, the far boxes and the crowns share the skyline glass, behind its switch%s" % why)


## DayNight makes the node; push() hands the globals this hour's sky and the towers round the
## camera (from Pershing Square: eight, the tallest real).
func _the_node_feeds_the_globals(city: Node3D) -> void:
	var why := ""
	var dn := city.get_node_or_null("DayNight")
	var node: Node = dn.get_node_or_null("SkylineGlass") if dn else null
	if node == null:
		_t._check(false, "DayNight makes the SkylineGlass node")
		return
	if not SkylineGlass.enabled:
		_t._check(true, "the skyline glass is off (SKYLINE_GLASS=0): nothing more to check")
		return
	node.push()
	var g: Vector4 = RenderingServer.global_shader_parameter_get("skyline_glass")
	if g.x < 0.5 or g.y < 0.0 or g.y > 1.0 or g.z < 0.0 or g.z > 1.0:
		why += " skyline_glass %s" % g
	var rim: Vector4 = RenderingServer.global_shader_parameter_get("skyline_sky_rim")
	var sky: ShaderMaterial = dn.get("_sky")
	if sky:
		var want: Color = sky.get_shader_parameter("sky_horizon")
		if Vector3(rim.x, rim.y, rim.z).distance_to(Vector3(want.r, want.g, want.b)) > 1e-3:
			why += " the rim %s is not the sky's horizon %s" % [rim, want]
	if rim.w <= 0.0 or rim.w > 1.0:
		why += " the cloud light %.2f" % rim.w
	_t._check(why == "", "SkylineGlass feeds the glass this hour's sky, its clouds and the sun%s" % why)
