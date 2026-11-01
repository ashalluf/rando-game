extends RefCounted
## The street_noon review (docs/HANDOFF.md "The street at noon", StreetNoonReview) for
## tests/smoke_test.gd:
## - asphalt materials are taken toward grey (texture and tint), pavements are left alone, and the
##   road's patches and RoadWear's stamps match the road;
## - RoadHardware may mark the middle of a light-rail street over the tunnel, never where the line
##   is in the street (trench, grade, structure) or where the underground station opens;
## - a road with two lanes each way is a double yellow;
## - the bike lanes carry their grime;
## - STREET_NOON=0 is a real A/B (every rule says "as before" with it off).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	_materials()
	_markings(plan)
	_switch()


func _materials() -> void:
	var asphalt := PropFactory.road("asphalt", 7.0, Color(0.920, 0.885, 0.848), 4242)
	var aerial := PropFactory.road("asphalt_aerial", 9.0, Color(0.786, 0.808, 0.873), 4243)
	var walk := PropFactory.road("sidewalk", 3.0, Color(1.52, 1.52, 1.52), 4244, 1.5, 0.45)
	var d0 := float(asphalt.get_shader_parameter("albedo_desat"))
	var d1 := float(aerial.get_shader_parameter("albedo_desat"))
	var d2 := float(walk.get_shader_parameter("albedo_desat"))
	_t._check(d0 > 0.5 and d1 > 0.3 and d2 == 0.0,
		"street noon: asphalt is taken toward grey (%.2f, aerial %.2f), the pavement is not (%.2f)" % [d0, d1, d2])
	var tint: Color = asphalt.get_shader_parameter("tint")
	_t._check(tint.r - tint.b < 0.04,
		"street noon: a warm road tint is neutralised (r %.3f, b %.3f; was 0.920 / 0.848)" % [tint.r, tint.b])
	var patch_mat := PropFactory.patch().surface_get_material(0)
	if patch_mat == null:
		patch_mat = (PropFactory.patch() as PrimitiveMesh).material
	_t._check(patch_mat != null and is_equal_approx(float(patch_mat.get_shader_parameter("albedo_desat")), d0),
		"street noon: the road's patches take the road's desaturation")
	var shader := (load("res://shaders/road.gdshader") as Shader).code
	_t._check(shader.contains("road_desat(texture(albedo_tex, uv).rgb) * tint") and shader.contains("road_desat(texture(albedo_tex, uv2).rgb) * tint"),
		"street noon: road.gdshader desaturates both of its texture fetches before the tint")
	var bike := Micromobility.lane_mesh().surface_get_material(0) as ShaderMaterial
	_t._check(bike != null and float(bike.get_shader_parameter("grime")) > 0.5,
		"street noon: the bike lanes wear their grime")


func _markings(plan: CityPlan) -> void:
	_t._check(StreetNoonReview.double_yellow(20.0, plan.street_width) and not StreetNoonReview.double_yellow(plan.street_width, plan.street_width),
		"street noon: a 20 m road (two lanes each way) is a double yellow, a %.0f m street is not" % plan.street_width)
	var rail := LightRail.of(plan)
	if rail == null:
		_t._check(true, "street noon: no light rail on this seed")
		return
	var tunnel := -1
	var grade := -1
	for i in rail.mode.size():
		if rail.mode[i] == LightRail.Mode.TUNNEL and tunnel < 0:
			# Well inside the tunnel and away from the station's openings.
			var p := rail.pts[i]
			if not StreetNoonReview.rail_surface_near(plan, p):
				tunnel = i
		if rail.mode[i] == LightRail.Mode.GRADE and grade < 0:
			grade = i
	_t._check(tunnel >= 0, "street noon: some of the light rail's tunnel lies under a markable street")
	_t._check(grade >= 0 and StreetNoonReview.rail_surface_near(plan, rail.pts[grade]),
		"street noon: where the line runs at grade the street's middle stays unmarked")
	if tunnel >= 0:
		_t._check(StreetNoonReview.marks_rail_street(plan, rail.pts[tunnel]),
			"street noon: over the tunnel (%.0f, %.0f) the street gets its markers and dots" % [rail.pts[tunnel].x, rail.pts[tunnel].y])
	# The station's openings (the stair kiosks in the median) keep the middle clear too.
	var area := MetroStation.cut_rect(rail)
	if area.has_area():
		var cuts := MetroStation.cuts_in(plan, area.grow(120.0))
		_t._check(not cuts.is_empty() and StreetNoonReview.rail_surface_near(plan, cuts[0].get_center()),
			"street noon: no markers over the underground station's openings (%d cuts)" % cuts.size())


func _switch() -> void:
	var held := StreetNoonReview.enabled
	StreetNoonReview.enabled = false
	var off_ok := StreetNoonReview.desat("asphalt") == 0.0 and not StreetNoonReview.double_yellow(30.0, 14.0) \
		and not StreetNoonReview.marks_rail_street(null, Vector2.ZERO)
	StreetNoonReview.enabled = held
	_t._check(off_ok, "street noon: STREET_NOON=0 puts the old road, markings and lanes back")
