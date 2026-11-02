extends RefCounted
## The pier by day (PierDay, the pier_day reference camera in tools/refcams/cameras_w6.json), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: the deck wears the board shader (and the old plank photo under the A/B), its rail
## outline fits the shader's array; the park's material carries the weathering (0 under the A/B);
## the crowd's extra people follow the hour and the weather, and people_steps() spawns them after
## the 48; the rail spots stand on the deck, clear of the benches, lamps and stands, facing out to
## sea; the bevels; the camera row.

var _t: Object


func run(t: Object) -> void:
	_t = t
	var was := PierDay.enabled
	PierDay.enabled = true
	_deck()
	_crowd()
	_rail()
	_camera()
	PierDay.enabled = false
	_t._check(PierDay.extra_people(15.0) == 0 and PierDay.rail_spots().is_empty() and PierDay.weathered() == 0.0
		and PierDay.bevel(0.07) == 0.0 and not (PierDay.deck_material() is ShaderMaterial),
		"PIER_DAY=0: no extra people, no rail spots, no weathering or bevels, the old plank photo")
	PierDay.enabled = was


func _deck() -> void:
	var mat := PierDay.deck_material() as ShaderMaterial
	_t._check(mat != null and mat.shader != null and mat.shader.resource_path == "res://shaders/pier_deck.gdshader",
		"the pier's deck wears the board shader")
	var src := FileAccess.get_file_as_string("res://shaders/pier_deck.gdshader")
	_t._check(src.contains("uniform vec2 outline[12]") and PierPark.OUTLINE.size() <= 12
		and int(mat.get_shader_parameter("outline_count")) == PierPark.OUTLINE.size(),
		"the rail outline fits the deck shader's array (%d points)" % PierPark.OUTLINE.size())
	_t._check(src.contains("color_space.gdshaderinc") and src.contains("cs_out(alb"),
		"the deck works in linear on both renderers")
	var park := FileAccess.get_file_as_string("res://shaders/pier_park.gdshader")
	_t._check(park.contains("uniform float weathered = 0.0") and park.contains("pier_weather("),
		"the park's shader carries the weathering, off by default")
	var m := PierMesh.material("rc3_pier_day_probe")
	_t._check(is_equal_approx(float(m.get_shader_parameter("weathered")), PierDay.WEATHERED),
		"a park material is made weathered")


func _crowd() -> void:
	_t._check(PierDay.density(15.0) == 1.0 and PierDay.density(3.0) < 0.2 and PierDay.density(9.0) < PierDay.density(13.0),
		"the pier fills through the morning, is full in the afternoon, near empty at 3:00")
	_t._check(PierDay.extra_people(15.0) == PierDay.EXTRA_PEOPLE and PierDay.extra_people(15.0, 0.05) < 10,
		"the afternoon gets %d extra people, rain hardly any" % PierDay.EXTRA_PEOPLE)
	var was_hour := BeachLife.force_hour
	BeachLife.force_hour = 15.0
	var chunk := CityChunk.new()
	var steps := PierPark.people_steps(Vector2(-940.0, -350.0), chunk)
	var want := PierPark.PEOPLE + PierDay.extra_people(15.0, BeachLife.weather_factor(chunk))
	_t._check(steps.size() == want, "people_steps() makes the 48 and the afternoon's extras (%d of %d)" % [steps.size(), want])
	BeachLife.force_hour = 3.0
	var night := PierPark.people_steps(Vector2(-940.0, -350.0), chunk).size()
	_t._check(night < want, "fewer people at 3:00 (%d)" % night)
	BeachLife.force_hour = was_hour
	chunk.free()
	for i: int in PierDay.PROMENADE:
		var p: Vector2 = PierPark.WALK_NODES[i]
		if absf(p.y) > 6.0:
			_t._check(false, "promenade node %d stands on the promenade" % i)
			return


func _rail() -> void:
	var spots := PierDay.rail_spots()
	_t._check(spots.size() >= 40, "people stop at the rail (%d spots)" % spots.size())
	var bad := ""
	var benches := PierPark.benches()
	for s: Array in spots:
		var p: Vector2 = s[0]
		var yaw: float = s[1]
		if not PierPark.MAIN.grow(-0.3).has_point(p):
			bad += " off(%.0f,%.0f)" % [p.x, p.y]
		for b: Array in benches:
			if p.distance_to(b[0] as Vector2) < 1.5:
				bad += " bench(%.0f,%.0f)" % [p.x, p.y]
		# Facing out: the nearest rail is ahead.
		var face := Vector2(-sin(yaw), -cos(yaw))
		var out := Vector2(0.0, signf(p.y)) if absf(p.y) > 10.0 else Vector2(-1.0, 0.0)
		if face.dot(out) < 0.9:
			bad += " facing(%.0f,%.0f)" % [p.x, p.y]
		for st: Array in PierPark.STANDS:
			if p.distance_to(Vector2(st[0], st[1])) < 3.0:
				bad += " stand(%.0f,%.0f)" % [p.x, p.y]
	_t._check(bad == "", "the rail spots stand on the deck facing the sea, clear of benches and stands%s" % bad)
	_t._check(PierDay.bevel(0.07) == 0.07, "the stands and booths are chamfered")


func _camera() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w6.json"))
	var found := {}
	if data is Dictionary:
		for c in data.get("cameras", []):
			if c.get("name", "") == "pier_day":
				found = c
	_t._check(not found.is_empty() and float(found.get("hour", 0)) == 15.0 and found.get("weather", "") == "clear"
		and absf(float(found.eye[1]) - (PierPark.DECK_TOP + 1.7)) < 0.2,
		"the pier_day camera stands on the deck at 15:00 clear")
