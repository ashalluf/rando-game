extends RefCounted
## A hill home's pool deck at dusk (Rc5HillHome, the hill_home_dusk reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the camera row stands on estate 392's pool deck (on the pad, behind the pool) looking out
## over its view; the glass and pool passes are in the shaders, off by default, and switched on by
## the materials; the pool knows the lit glass wall beside it; no terrace tree stands in the pool's
## view and every other tree keeps its place; the spill material and its "hh_spill" surface; the
## loungers are BackyardKit's pair; RC5_HILL_HOME=0 puts the old plan back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var was := Rc5HillHome.enabled
	Rc5HillHome.enabled = true
	var plan: CityPlan = city.plan
	_shaders()
	if plan.macro != null and plan.macro.hill_roads != null:
		_camera(plan)
		_trees(plan)
	else:
		_t._check(false, "rc5 hill home: the plan has hill roads")
	Rc5HillHome.enabled = false
	var gm := ShaderMaterial.new()
	Rc5HillHome.material("hh_glass", gm)
	_t._check(float(gm.get_shader_parameter("rc5")) == 0.0, "RC5_HILL_HOME=0: the glass pass off")
	Rc5HillHome.enabled = was


func _shaders() -> void:
	var g := FileAccess.get_file_as_string("res://shaders/hill_glass.gdshader")
	_t._check(g.contains("uniform float rc5 = 0.0;") and g.contains("!open_plan"),
		"the hill glass's open-plan pass is off by default and drops the bay partitions")
	var p := FileAccess.get_file_as_string("res://shaders/hill_pool.gdshader")
	_t._check(p.contains("uniform float rc5 = 0.0;") and p.contains("COLOR.b > 0.01"),
		"the pool's pass is off by default and mirrors the glass wall from COLOR.b")
	var s := FileAccess.get_file_as_string("res://shaders/rc5_hill_spill.gdshader")
	_t._check(s.contains("blend_add") and s.contains("fog_disabled") and s.contains("lamp_factor"),
		"the spill is additive, out of the fog, and off by day")
	var gm := HillHomeKit.material("hh_glass") as ShaderMaterial
	var wm := HillHomeKit.material("hh_water") as ShaderMaterial
	_t._check(gm != null and wm != null and float(gm.get_shader_parameter("rc5")) == 1.0 and float(wm.get_shader_parameter("rc5")) == 1.0,
		"the hill glass and pool materials carry the pass")
	_t._check(HillHomeKit.material("hh_spill") == Rc5HillHome.spill_material() and "hh_spill" in HillHomeKit.NO_SHADOW,
		"the spill surface wears the spill material and casts nothing")
	_t._check(BackyardKit.get_mesh("loungers") != null, "the chaise pair exists")


func _row() -> Dictionary:
	var f := FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json")
	var data: Variant = JSON.parse_string(f)
	if not data is Dictionary:
		return {}
	for c: Dictionary in data.get("cameras", []):
		if c.name == "hill_home_dusk":
			return c
	return {}


func _camera(plan: CityPlan) -> void:
	var row := _row()
	_t._check(not row.is_empty() and is_equal_approx(float(row.hour), 19.25) and row.weather == "clear",
		"the hill_home_dusk row is at 19:15 clear")
	if row.is_empty():
		return
	var estates: Array = plan.macro.hill_roads.mansions
	if estates.size() <= 392:
		_t._check(false, "rc5 hill home: estate 392 exists")
		return
	var h := HillHomeKit.plan_home(plan, estates[392])
	var eye: Array = row.eye
	var e := Vector2(float(eye[0]), float(eye[2]))
	var rel := e - (h.o as Vector2)
	var uv := Vector2(rel.dot(h.fu), rel.dot(h.fv))
	var pl: Dictionary = h.pool
	_t._check(h.style_name == "cantilever" and not pl.is_empty() and bool(pl.infinity),
		"estate 392 is a cantilever with an infinity pool (%s)" % h.style_name)
	if pl.is_empty():
		return
	var r: Rect2 = pl.r
	_t._check(uv.x > 0.0 and uv.x < float(h.Wp) and uv.y < r.position.y and uv.y > r.position.y - 8.0,
		"the eye stands on the pad behind the pool (frame %.1f, %.1f)" % [uv.x, uv.y])
	_t._check(absf(float(eye[1]) - (float(h.floor) + 1.7)) < 0.5, "the eye is at standing height on the deck")
	# Its yaw looks out over the view side (fv), not back at the house.
	var yaw := deg_to_rad(float(eye[3]))
	var look := Vector2(-sin(yaw), -cos(yaw))
	_t._check(look.dot(h.fv) > 0.85, "the camera looks out over the view (%.2f)" % look.dot(h.fv))
	_t._check(Rc5HillHome.pool_wall(h) > 0.0, "the pool knows the lit glass wall beside it")


func _trees(plan: CityPlan) -> void:
	var estates: Array = plan.macro.hill_roads.mansions
	var dropped := 0
	var moved := 0
	var n := mini(estates.size(), 200)
	for i in n:
		Rc5HillHome.enabled = true
		var on := HillHomeKit.plan_home(plan, estates[i])
		Rc5HillHome.enabled = false
		var off := HillHomeKit.plan_home(plan, estates[i])
		Rc5HillHome.enabled = true
		var a: Array = on.trees
		var b: Array = off.trees
		dropped += b.size() - a.size()
		# Every tree kept is one the old plan had, in the same place.
		for tr: Array in a:
			var found := false
			for tb: Array in b:
				if tb[0] == tr[0] and (tb[1] as Vector2).is_equal_approx(tr[1]) and is_equal_approx(float(tb[2]), float(tr[2])):
					found = true
					break
			if not found:
				moved += 1
		for tr: Array in a:
			var p: Vector2 = tr[1]
			if p.y > float(on.Dp) and Rc5HillHome.blocks_view(on, p):
				moved += 1
	_t._check(dropped > 0 and moved == 0, "terrace trees in the pools' view dropped (%d), every other tree in place (%d moved)" % [dropped, moved])
