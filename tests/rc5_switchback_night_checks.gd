extends RefCounted
## The switchback_night refcam (fleet wave 8, rc5-switchback-night; docs/HANDOFF.md "Stadium Way's
## switchbacks at night"): checks for tests/smoke_test.gd. CPU and source only:
##   * the camera row is in tools/refcams/cameras_w8.json, on Stadium Way's upper hairpin, with its
##     staged car;
##   * the curve chevrons (RcSwitchback.chevrons) stand round the hairpin's outside, off every road,
##     their boards pointing at the bend's centre, and the same answer twice (pure);
##   * the guardrail's reflectors every fourth post; the shaders carry the rc5 paths and the hill
##     roads' materials have them on.
## RC5_SWITCHBACK=0 is the A/B: nothing is built, and the checks only say so.

var _t: Node

## The refcam's eye: the outside of Stadium Way's upper hairpin (tools/refcams/cameras_w8.json).
const EYE := Vector2(2805.0, -2533.0)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_camera_row()
	if not RcSwitchback.on():
		_t._check(true, "rc5-switchback-night: off (RC5_SWITCHBACK=0)")
		return
	_shaders()
	var plan: CityPlan = city.get("plan") if city else null
	if plan and plan.macro and plan.macro.hill_roads:
		_chevrons(plan)
	_reflectors()


func _camera_row() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var found := false
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "switchback_night":
				found = absf(float(c.eye[0]) - EYE.x) < 0.01 and absf(float(c.eye[2]) - EYE.y) < 0.01 and c.get("hill_car", null) is Dictionary and absf(float(c.hour) - 22.0) < 0.01
	_t._check(found, "rc5-switchback-night: the switchback_night row is in cameras_w8.json at Stadium Way's hairpin, 22:00, with its car")


func _shaders() -> void:
	var road := FileAccess.get_file_as_string("res://shaders/canyon_road.gdshader")
	_t._check(road.contains("uniform float rc5") and road.contains("marker_spacing") and road.contains("EMISSION"),
		"rc5-switchback-night: the canyon road draws raised markers that glow after dark")
	var rail := FileAccess.get_file_as_string("res://shaders/canyon_guardrail.gdshader")
	_t._check(rail.contains("uniform float rc5") and rail.contains("sheeting") and rail.contains("legend"),
		"rc5-switchback-night: the guardrail shader draws the chevrons' sheeting and legend")
	_t._check(float(CanyonRoad.road_material().get_shader_parameter("rc5")) == 1.0 and float(CanyonRoad.rail_material().get_shader_parameter("rc5")) == 1.0,
		"rc5-switchback-night: the hill roads' materials have the rc5 paths on")


func _chevrons(plan: CityPlan) -> void:
	var area := Rect2(EYE - Vector2(160.0, 160.0), Vector2(320.0, 320.0))
	var cs: Array = RcSwitchback.chevrons(plan, area)
	var again: Array = RcSwitchback.chevrons(plan, area)
	_t._check(cs.size() >= 3 and cs.size() == again.size(), "rc5-switchback-night: chevrons round Stadium Way's hairpins (%d), the same twice" % cs.size())
	# Off the asphalt of every road, and pointing (h = -o) at the bend's centre: the road's centre
	# line is nearer along -o than along +o.
	var hr: HillRoads = plan.macro.hill_roads
	var off_road := 0
	var inward := 0
	for c: Dictionary in cs:
		var p: Vector2 = c.pos
		var o: Vector2 = c.o
		var clear := true
		for seg: Dictionary in hr.segments_in(Rect2(p - Vector2(15, 15), Vector2(30, 30))):
			if not seg.get("draw", true) or seg.get("drive", false):
				continue
			var q := Geometry2D.get_closest_point_to_segment(p, seg.a, seg.b)
			if p.distance_to(q) < float(seg.width) * 0.5 + 1.0:
				clear = false
		if clear:
			off_road += 1
		if absf(o.length() - 1.0) < 0.01 and absf(o.dot(c.t)) < 0.35:
			inward += 1
	_t._check(off_road == cs.size() and inward == cs.size(),
		"rc5-switchback-night: every chevron off the roads (%d of %d) and square to the road, facing along it (%d)" % [off_road, cs.size(), inward])
	# A straight stretch gets none: the area round Stadium Way's long eastbound leg's middle.
	var straight: Array = RcSwitchback.chevrons(plan, Rect2(Vector2(2590.0, -2615.0), Vector2(40.0, 25.0)))
	_t._check(straight.is_empty(), "rc5-switchback-night: no chevrons on a straight leg (%d)" % straight.size())


func _reflectors() -> void:
	var n := 0
	for i in 40:
		if RcSwitchback.reflector_at(float(i) * CanyonRoad.POST_SPACING):
			n += 1
	_t._check(n == 10, "rc5-switchback-night: a guardrail reflector every fourth post (%d of 40)" % n)
