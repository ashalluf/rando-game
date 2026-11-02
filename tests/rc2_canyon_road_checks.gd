extends RefCounted
## The canyon road refcam (fleet wave 5, rc2-canyon-road; docs/HANDOFF.md "The canyon road
## refcam"): checks for tests/smoke_test.gd. CPU and source only (no pixel is read headless):
##   * the hill roads' materials: the canyon road shader (markings, shoulder) and the guardrail;
##   * the FULL chunk under the refcam's eye builds its road on the canyon road material, with the
##     strip's lateral metres in its UVs, and a guardrail along the fill side;
##   * the hill boulders are gathered (some left out, after their rolls) and bedded lower;
##   * the camera row is in tools/refcams/cameras_w5.json.
## CANYON_ROAD=0 is the A/B: everything goes back, and the checks only say so.

var _t: Node

## The refcam's eye (tools/refcams/cameras_w5.json, canyon_road): on Switchback 35.
const EYE := Vector2(545.0, -1927.6)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_camera_row()
	if not CanyonRoad.on():
		_t._check(true, "rc2-canyon-road: off (CANYON_ROAD=0)")
		return
	_materials()
	_rocks()
	var plan: CityPlan = city.get("plan") if city else null
	if plan and plan.macro and plan.macro.hill_roads:
		_chunk(city, plan)


func _camera_row() -> void:
	var src := FileAccess.get_file_as_string("res://tools/refcams/cameras_w5.json")
	var data: Variant = JSON.parse_string(src)
	var found := false
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "canyon_road":
				found = absf(float(c.eye[0]) - EYE.x) < 0.01 and absf(float(c.eye[2]) - EYE.y) < 0.01
	_t._check(found, "rc2-canyon-road: the canyon_road row is in cameras_w5.json at the switchback")


func _materials() -> void:
	var road := CanyonRoad.road_material()
	_t._check(road.shader != null and road.get_shader_parameter("albedo_tex") != null, "rc2-canyon-road: the hill roads wear the canyon road shader with the asphalt set")
	var src := FileAccess.get_file_as_string("res://shaders/canyon_road.gdshader")
	_t._check(src.contains("paint_yellow") and src.contains("paint_white") and src.contains("gravel") and src.contains("color_space.gdshaderinc"),
		"rc2-canyon-road: the road shader draws the double yellow, the edge lines and the shoulder, in linear")
	var rail := CanyonRoad.rail_material()
	_t._check(rail.shader != null, "rc2-canyon-road: the guardrail has its shader")
	var rsrc := FileAccess.get_file_as_string("res://shaders/canyon_guardrail.gdshader")
	_t._check(rsrc.contains("cull_disabled") and rsrc.contains("color_space.gdshaderinc"), "rc2-canyon-road: the guardrail is two-sided and linear")


func _rocks() -> void:
	var kept := 0
	var lower := 0
	var n := 0
	for i in 40:
		for j in 40:
			var p := EYE + Vector2(i * 7.3, j * 6.1)
			var xf := Transform3D(Basis.IDENTITY, Vector3(p.x, 100.0, p.y))
			var r: Array = CanyonRoad.bed_rock(p, (i + j) % 2, 1.2, xf)
			n += 1
			if r.is_empty():
				continue
			kept += 1
			if (r[0] as Transform3D).origin.y < 100.0 and float(r[1]) > 0.0 and (r[0] as Transform3D).basis.get_scale().y < 1.0:
				lower += 1
			# Pure: the same answer twice.
			if CanyonRoad.bed_rock(p, (i + j) % 2, 1.2, xf).is_empty():
				lower = -100000
	var share := float(kept) / float(n)
	_t._check(share > 0.25 and share < 0.85 and lower == kept,
		"rc2-canyon-road: hill boulders gathered and bedded (%.0f %% kept, %d of %d bedded lower)" % [share * 100.0, lower, kept])


func _chunk(city: Node3D, plan: CityPlan) -> void:
	var k := plan.block_index_at(EYE)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var road := chunk.get_node_or_null("HillRoad") as MeshInstance3D
	_t._check(road != null and road.material_override == CanyonRoad.road_material(),
		"rc2-canyon-road: the switchback's chunk builds its road on the canyon road material")
	var rail := chunk.get_node_or_null("HillGuardrail") as MeshInstance3D
	_t._check(rail != null and rail.material_override == CanyonRoad.rail_material(),
		"rc2-canyon-road: the switchback's chunk builds a guardrail along its fill side")
	# The fill test on the road at the eye: the side toward the basin drops, the other does not
	# drop as far (a road benched into the slope).
	var segs: Array[Dictionary] = plan.macro.hill_roads.segments_in(Rect2(EYE - Vector2(20, 20), Vector2(40, 40)))
	var best: Dictionary = {}
	var bd := INF
	for s in segs:
		var d := EYE.distance_to(Geometry2D.get_closest_point_to_segment(EYE, s.a, s.b))
		if d < bd and s.get("draw", true):
			bd = d
			best = s
	if not best.is_empty():
		var dir: Vector2 = ((best.b as Vector2) - (best.a as Vector2)).normalized()
		var n := Vector2(-dir.y, dir.x)
		var c: Vector2 = Geometry2D.get_closest_point_to_segment(EYE, best.a, best.b)
		var half: float = float(best.width) * 0.5
		var h := plan.height_at(c)
		var left := CanyonRoad.needs_rail(plan, c + n * half, n, h)
		var right := CanyonRoad.needs_rail(plan, c - n * half, -n, h)
		_t._check(left != right, "rc2-canyon-road: the road at the eye is railed on one side only (left %s, right %s)" % [left, right])
	chunk.queue_free()
