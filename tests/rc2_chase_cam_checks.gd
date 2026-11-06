extends RefCounted
## The chase_cam review (docs/HANDOFF.md "The chase camera's street", ChaseCamReview) for
## tests/smoke_test.gd:
## - the carriageway's asphalt materials carry `lane_wear`, pavements, plazas and lightly worn
##   surfaces (car parks, yards) do not;
## - road.gdshader applies road_lane_wear() and the include returns "no change" when lane_wear is 0;
## - CHASE_CAM_REVIEW=0 is a real A/B;
## - the camera row exists and its staging script compiles.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var street := PropFactory.road("asphalt", 7.0, Color(0.62, 0.62, 0.64), 5151)
	var aerial := PropFactory.road("asphalt_aerial", 9.0, Color(0.62, 0.62, 0.64), 5152)
	var walk := PropFactory.road("sidewalk", 3.0, Color(1.52, 1.52, 1.52), 5153, 1.5, 0.45)
	var lot := PropFactory.road("asphalt", 7.0, Color(0.6, 0.6, 0.62), 5154, 0.0, 0.7)
	var w0 := float(street.get_shader_parameter("lane_wear"))
	var w1 := float(aerial.get_shader_parameter("lane_wear"))
	var w2 := float(walk.get_shader_parameter("lane_wear"))
	var w3 := float(lot.get_shader_parameter("lane_wear"))
	_t._check(w0 > 0.5 and w1 > 0.5 and w2 == 0.0 and w3 == 0.0,
		"chase cam: street asphalt wears its lanes (%.2f, aerial %.2f), pavement (%.2f) and a car park (%.2f) do not" % [w0, w1, w2, w3])
	var road := (load("res://shaders/road.gdshader") as Shader).code
	_t._check(road.contains("road_lane_wear.gdshaderinc") and road.contains("road_lane_wear(plan_pos, slab_uv"),
		"chase cam: road.gdshader includes and applies road_lane_wear()")
	var inc := FileAccess.get_file_as_string("res://shaders/road_lane_wear.gdshaderinc")
	_t._check(inc.contains("uniform float lane_wear = 0.0;") and inc.contains("if (lane_wear <= 0.0 || axis_mode <= 0) {\n\t\treturn vec4(1.0, 1.0, 0.0, 0.0);"),
		"chase cam: lane_wear defaults to 0 and 0 draws the road exactly as before")
	# The A/B: off, nothing gets lane wear.
	var was := ChaseCamReview.enabled
	ChaseCamReview.enabled = false
	var off := ChaseCamReview.lane_wear("asphalt", 0.0, 1.0)
	ChaseCamReview.enabled = was
	_t._check(off == 0.0 and ChaseCamReview.lane_wear("asphalt", 0.0, 1.0) == (1.0 if was else 0.0),
		"chase cam: CHASE_CAM_REVIEW=0 turns the lane wear off")
	# The reference camera's row and its staging.
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w5.json"))
	var row: Dictionary = {}
	if table is Dictionary:
		for c: Dictionary in table.get("cameras", []):
			if c.get("name", "") == "chase_cam":
				row = c
	_t._check(row.has("drive") and float(row.hour) == 16.0 and String(row.weather) == "clear",
		"chase cam: cameras_w5.json has the chase_cam row, staged, 16:00 clear")
	var stage: GDScript = load("res://tools/refcams/chase_stage.gd")
	_t._check(stage != null and stage.can_instantiate(), "chase cam: tools/refcams/chase_stage.gd compiles")
