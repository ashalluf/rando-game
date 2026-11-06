extends RefCounted
## The marketplace lane at 12:30 (PuebloLaneLook, the pueblo_lane reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there.
##
## Checks: the lane's crowd by the hour (quiet at night, packed at lunch, capped); a seller in
## every second stall; the worn brick and the weathered paint reach the materials; the shader
## has the weathering behind its uniform; the camera row stands in the lane's east aisle under
## the pergola looking north; PUEBLO_LANE_LOOK=0 is the lane as before.

var _t: Object


func run(t: Object, city: Node) -> void:
	_t = t
	var was := PuebloLaneLook.enabled
	PuebloLaneLook.enabled = true
	var lunch := PuebloLaneLook.lane_extra(12.5)
	var night := PuebloLaneLook.lane_extra(3.0)
	_t._check(lunch >= 25 and night == 0 and PuebloLaneLook.LANE_BASE + PuebloLaneLook.lane_extra(13.0) <= PuebloLaneLook.LANE_MOST,
		"PuebloLaneLook: the lane's crowd by the hour (lunch +%d, night +%d, capped)" % [lunch, night])
	_t._check(PuebloLaneLook.vendor_every() == 2 and PuebloLaneLook.paint_weather() > 0.5,
		"PuebloLaneLook: a seller in every second stall, the paint weathered")
	var src := FileAccess.get_file_as_string("res://shaders/pueblo_market.gdshaderinc")
	_t._check(src.contains("uniform float weather = 0.0;") and src.contains("if (weather > 0.0)") and src.contains("uniform float foot_y"),
		"PuebloLaneLook: pueblo_market.gdshaderinc weathers the paint behind its own uniform (0 = the old paint)")
	_t._check(is_equal_approx(float(PuebloMarket.solid_material().get_shader_parameter("weather")), PuebloLaneLook.PAINT_WEATHER),
		"PuebloLaneLook: the stall material carries the weathering")
	_camera(city.get("plan"))
	PuebloLaneLook.enabled = false
	_t._check(PuebloLaneLook.lane_extra(12.5) == 0 and PuebloLaneLook.vendor_every() == 4 and PuebloLaneLook.paint_weather() == 0.0
		and PuebloLaneLook.brick_tint() == Color(0.92, 0.8, 0.72) and is_equal_approx(PuebloLaneLook.brick_wear(), 0.25),
		"PUEBLO_LANE_LOOK=0: the lane's crowd, sellers, brick and paint as before")
	PuebloLaneLook.enabled = was


func _camera(plan: CityPlan) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row := {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if c.get("name", "") == "pueblo_lane":
				row = c
	if row.is_empty() or plan == null:
		_t._check(false, "PuebloLaneLook: the pueblo_lane camera row exists")
		return
	var eye: Array = row.eye
	var info := CivicSites.site(plan, PuebloLane.ID)
	var L := PuebloLane.layout(info.local, PuebloLane.kiosk_local(info))
	var lane := CivicSites.rect_to_world(info, L.lane as Rect2)
	var p := Vector2(float(eye[0]), float(eye[2]))
	# In the lane, east of its middle (the aisle between the stalls and the east row), looking north.
	var in_aisle := lane.has_point(p) and p.x > lane.get_center().x + PuebloMarket.STALL_D and absf(float(eye[3])) < 20.0
	_t._check(in_aisle and float(row.hour) == 12.5 and row.weather == "clear",
		"PuebloLaneLook: the pueblo_lane camera stands in the lane's east aisle looking north at 12:30 (%s in %s)" % [p, lane])
