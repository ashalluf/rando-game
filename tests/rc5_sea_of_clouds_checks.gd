extends RefCounted
## The marine layer from above (SeaOfClouds, the sea_of_clouds reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there.
##
## Checks: the camera row (08:30, marine, high on the east range, above the deck); the top's inland
## thinning (full at the coast, low inland, the morning only, never under the deck's underside);
## the street views under the deck keep their deck (marine_morning's eye under it); the shader
## mirrors top_at() and reads the depth for the soft shore; the planes; SEA_OF_CLOUDS=0.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var was := SeaOfClouds.enabled
	SeaOfClouds.enabled = true
	_pure()
	_shader()
	_camera(city)
	_planes(city)
	SeaOfClouds.enabled = false
	_t._check(SeaOfClouds.morning(8.5) == 0.0 and SeaOfClouds.top_at(-900.0, 8.5, 2800.0, 520.0) == 520.0
		and SeaOfClouds.look() == 0.0, "SEA_OF_CLOUDS=0: the flat top at its old height, the old look")
	SeaOfClouds.enabled = was


func _pure() -> void:
	var coast := -900.0
	var top := LaWeather.deck_heights(8.5).y
	var at_coast := SeaOfClouds.top_at(coast, 8.5, coast + 200.0, top)
	var downtown := SeaOfClouds.top_at(coast, 8.5, 2800.0, top)
	_t._check(absf(at_coast - SeaOfClouds.COAST_TOP) < 1.0 and downtown < 300.0 and downtown > LaWeather.DECK_BASE + 5.0,
		"sea of clouds: the deck's top %.0f m at the coast, %.0f m over downtown at 08:30 (crowns out, over the underside)" % [at_coast, downtown])
	_t._check(SeaOfClouds.morning(18.5) == 0.0 and SeaOfClouds.morning(2.0) == 0.0 and SeaOfClouds.morning(15.0) == 0.0
		and SeaOfClouds.morning(8.5) > 0.99,
		"sea of clouds: the top thins inland only in the morning (none at 02:00, 15:00, 18:30)")
	var prev := 1.0e9
	var falls := true
	for i in 30:
		var y := SeaOfClouds.top_at(coast, 9.0, coast + float(i) * 200.0, top)
		falls = falls and y <= prev + 0.001
		prev = y
	_t._check(falls, "sea of clouds: the top only falls going inland")
	# The beach town's street (marine_morning's eye) is still under its deck.
	var beach := SeaOfClouds.top_at(coast, 8.0, -585.0, LaWeather.deck_heights(8.0).y)
	_t._check(LaWeather.under_deck(1.7, beach) > 0.99 and beach > LaWeather.DECK_BASE + 100.0,
		"sea of clouds: the beach town at 08:00 is still under its deck (top %.0f m)" % beach)


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/marine_layer.gdshader")
	_t._check(src.contains("float inland = smoothstep(dip_near, dip_far, x - coast_x);")
		and src.contains("mix(deck_top, min(deck_top, mix(coast_top, inland_top, inland)), top_dip)"),
		"sea of clouds: the shader's top_y() is SeaOfClouds.top_at()")
	_t._check(src.contains("hint_depth_texture") and src.contains("if (top_look > 0.5)")
		and src.contains("uniform float top_look = 0.0;") and src.contains("uniform float top_dip = 0.0;"),
		"sea of clouds: the billowed top and the soft shore are behind top_look / top_dip (0 = the old top)")


func _camera(city: Node3D) -> void:
	var txt := FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json")
	var data: Variant = JSON.parse_string(txt)
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if c.get("name", "") == "sea_of_clouds":
				row = c
	_t._check(not row.is_empty() and float(row.hour) == 8.5 and row.weather == "marine",
		"sea of clouds: the camera row (08:30, marine)")
	if row.is_empty():
		return
	var e: Array = row.eye
	var plan: Variant = city.get("plan")
	var ground: float = plan.height_at(Vector2(float(e[0]), float(e[2]))) if plan else 600.0
	var y := ground + float(e[1])
	_t._check(y > SeaOfClouds.COAST_TOP + 30.0,
		"sea of clouds: the eye %.0f m up stands above the morning deck's highest top (%.0f m)" % [y, SeaOfClouds.COAST_TOP])
	var here := SeaOfClouds.top_at(-900.0, 8.5, float(e[0]), LaWeather.deck_heights(8.5).y)
	_t._check(LaWeather.under_deck(y, here) < 0.01, "sea of clouds: the eye is out of the deck's haze")


func _planes(city: Node3D) -> void:
	var ml: Node = city.find_child("MarineLayer", true, false)
	_t._check(ml != null, "sea of clouds: the city has its MarineLayer")
	if ml == null:
		return
	var top := ml.get_node_or_null("DeckTop") as MeshInstance3D
	var pm := top.mesh as PlaneMesh if top else null
	_t._check(pm != null and pm.size.x >= SeaOfClouds.FAR_RADIUS * 2.0 - 1.0 and pm.subdivide_width >= 60,
		"sea of clouds: the deck's top runs out to %.0f km and is subdivided to fall inland" % (SeaOfClouds.FAR_RADIUS / 1000.0))
