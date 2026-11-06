extends RefCounted
## The refinery at night refcam (RefineryNight, tools/refcams/cameras_w6.json's refinery_night), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The camera row: 22:30 clear, on the street outside the fence, the plant in front of it. The flares:
## every flame's tip handed to the plant's shader in TRUE world, their light strong on the derrick,
## faint across the plant and nothing past its reach; the GDScript copy agrees with the shader's
## numbers. The A/B: the shaders' night_look defaults to 0 (the old look).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_camera()
	_shader_defaults()
	if not Refinery.enabled:
		return
	var plan: CityPlan = city.plan
	var lay := Refinery.layout(plan)
	if lay.is_empty():
		return
	_flares(plan, lay)
	_light()


func _camera() -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w6.json", FileAccess.READ)
	_t._check(f != null, "cameras_w6.json is there")
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if String(c.get("name", "")) == "refinery_night":
				row = c
	_t._check(not row.is_empty(), "cameras_w6.json has the refinery_night row")
	if row.is_empty():
		return
	_t._check(absf(float(row.hour) - 22.5) < 0.01 and String(row.weather) == "clear", "refinery_night is 22:30, clear")
	var eye: Array = row.eye
	var p := Vector2(float(eye[0]), float(eye[2]))
	var outside := p.x < Refinery.WEST_X or p.x > Refinery.EAST_X or p.y < Refinery.NORTH_Z or p.y > Refinery.SOUTH_Z - 2.0
	var near := p.distance_to(Refinery.ANCHOR) < 600.0
	_t._check(outside and near and float(eye[1]) < 3.0, "the eye stands on the road outside the fence, at eye height (%s)" % [p])


func _shader_defaults() -> void:
	for path in ["res://shaders/refinery.gdshader", "res://shaders/refinery_flame.gdshader", "res://shaders/refinery_plume.gdshader"]:
		var src := FileAccess.get_file_as_string(path)
		_t._check(src.contains("uniform float night_look = 0.0;"), "%s keeps the old look until RefineryNight turns it on" % path.get_file())
	var src := FileAccess.get_file_as_string("res://shaders/refinery.gdshader")
	_t._check(src.contains("uniform float flare_reach = %.1f;" % RefineryNight.FLARE_REACH)
		and src.contains("uniform float flare_half = %.1f;" % RefineryNight.FLARE_HALF)
		and src.contains("uniform vec4 flare_tips[%d];" % RefineryNight.MAX_FLARES),
		"refinery.gdshader's flare numbers are RefineryNight's")
	_t._check(src.contains("dot(nrm_world, d / max(dist, 0.01)) * 0.7 + 0.3") and src.contains("smoothstep(flare_reach * 0.55, flare_reach, dist)"),
		"the shader's flare falloff is RefineryNight.flare_light()'s")


func _flares(plan: CityPlan, lay: Dictionary) -> void:
	var n := 0
	for it: Dictionary in lay.items:
		if String(it.type) == "flare":
			n += 1
	var tips := RefineryNight.flare_tips(lay, plan)
	_t._check(n > 0 and tips.size() == mini(n, RefineryNight.MAX_FLARES), "every flare's tip is taken (%d of %d)" % [tips.size(), n])
	var high := true
	var inside := true
	var R: Rect2 = lay.rect
	for tp: Vector4 in tips:
		high = high and tp.y > Refinery.BASE_Y + 70.0
		inside = inside and R.has_point(Vector2(tp.x, tp.z))
	_t._check(high and inside, "the tips stand over the plant, 70 m up and more")
	if not RefineryNight.enabled:
		return
	var mat := RefineryKit.material()
	_t._check(float(mat.get_shader_parameter("night_look")) > 0.5 and int(mat.get_shader_parameter("flare_count")) == tips.size(),
		"the plant's material has the night look and the flares (%s)" % [mat.get_shader_parameter("flare_count")])
	_t._check(float(Refinery.flame_material().get_shader_parameter("night_look")) > 0.5
		and float(Refinery.plume_material().get_shader_parameter("night_look")) > 0.5, "the flames and the steam have it too")


func _light() -> void:
	var tip := Vector4(0.0, 90.0, 0.0, 0.0)
	var tips: Array[Vector4] = [tip]
	var at_top := RefineryNight.flare_light(tips, Vector3(4.0, 84.0, 0.0), Vector3(-4.0, 6.0, 0.0).normalized())
	var at_foot := RefineryNight.flare_light(tips, Vector3(10.0, 0.0, 0.0), Vector3.UP)
	var across := RefineryNight.flare_light(tips, Vector3(120.0, 10.0, 0.0), Vector3.LEFT)
	var past := RefineryNight.flare_light(tips, Vector3(170.0, 10.0, 0.0), Vector3.LEFT)
	_t._check(at_top > 0.85, "the derrick under a flame is lit by it (%.2f)" % at_top)
	_t._check(at_foot > 0.02 and at_foot < 0.15, "the pad 90 m under it faintly (%.3f)" % at_foot)
	_t._check(across > 0.0 and across < at_foot, "the plant across the way less (%.3f)" % across)
	_t._check(past == 0.0, "and nothing past the reach")
	var away := RefineryNight.flare_light(tips, Vector3(4.0, 84.0, 0.0), Vector3(4.0, -6.0, 0.0).normalized())
	_t._check(away < at_top * 0.5, "a face turned away takes less (%.2f vs %.2f)" % [away, at_top])
