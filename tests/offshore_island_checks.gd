extends RefCounted
## The island offshore (OffshoreIsland, shaders/offshore_island.gdshaderinc, docs/HANDOFF.md "The
## island offshore"): checks for tests/smoke_test.gd. Loaded at run time, so it compiles after the
## autoloads. No shader runs under --headless, so these hold the data, the weather table, the
## wiring into the sky and the uniforms the node pushes; tools/offshore_island/island_shot.gd and
## still_shot.gd show the pixels.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_where_it_stands(city)
	_the_air()
	_wired_into_the_sky(city)


## 30-40 km out from the beach, the hills and downtown; past the camera's far plane and the
## horizon plane; at sea all round; the town on the side that faces the mainland.
func _where_it_stands(city: Node3D) -> void:
	var c := OffshoreIsland.CENTRE
	var views := {"beach": Vector2(-760, 800), "hills": Vector2(300, -1500), "downtown": Vector2(2800, 100),
		"esplanade": Vector2(-440, 3535)}
	var bad: Array[String] = []
	for k in views:
		var d: float = OffshoreIsland.seen_from(views[k]).y
		if d < 30000.0 or d > 42000.0:
			bad.append("%s %.1f km" % [k, d / 1000.0])
	_t._check(bad.is_empty(), "the island's centre is 30-42 km from the beach, hills, downtown and the Esplanade %s" % [bad])
	# Its nearest point to the beach is still past the 12 km far plane and the 7 km horizon plane.
	var near_d := INF
	var perp := Vector2(-OffshoreIsland.AXIS.y, OffshoreIsland.AXIS.x)
	for i in 72:
		var a := TAU * float(i) / 72.0
		var p := c + OffshoreIsland.AXIS * cos(a) * OffshoreIsland.HALF_LEN + perp * sin(a) * OffshoreIsland.HALF_WID
		near_d = minf(near_d, p.distance_to(views["beach"]))
	_t._check(near_d > 14000.0, "the island's footprint stays past the far plane from the beach (nearest %.1f km)" % [near_d / 1000.0])
	var plan = city.get("plan")
	var macro = plan.macro if plan else null
	var dry := 0
	if macro:
		for i in 72:
			var a := TAU * float(i) / 72.0
			for r: float in [0.0, 0.5, 1.0]:
				var p: Vector2 = c + OffshoreIsland.AXIS * cos(a) * OffshoreIsland.HALF_LEN * r + perp * sin(a) * OffshoreIsland.HALF_WID * r
				if int(macro.zone_at(p)) != int(MacroMap.Zone.OCEAN):
					dry += 1
	_t._check(macro != null and dry == 0, "the island's footprint lies over open ocean on the map (%d points on land)" % dry)
	var town: Vector2 = OffshoreIsland.town()[0]
	var toward := (town - c).dot(perp) * signf(perp.dot(-c))
	_t._check(toward > 500.0, "the island's town is on its mainland side (%.1f km off the axis toward the coast)" % [toward / 1000.0])


## The weather table: gone in the marine layer and the rain, faint under overcast, crisp in a
## Santa Ana, hazier in the golden-hour smog; the lights follow the night.
func _the_air() -> void:
	var clear := OffshoreIsland.air([1.0, 0, 0, 0, 0, 0], 0.0, 0.0, 0.35)
	var marine := OffshoreIsland.air([0, 0, 0, 0, 1.0, 0], 0.0, 0.0, 0.35)
	var rain := OffshoreIsland.air([0, 0, 1.0, 0, 0, 0], 0.0, 0.0, 0.35)
	var over := OffshoreIsland.air([0, 1.0, 0, 0, 0, 0], 0.0, 0.0, 0.35)
	var santa := OffshoreIsland.air([0, 0, 0, 0, 0, 1.0], 0.0, 0.0, 0.35)
	var golden := OffshoreIsland.air([1.0, 0, 0, 0, 0, 0], 1.0, 0.0, 0.35)
	var none := OffshoreIsland.air([], 0.0, 1.0, 0.35)
	var half := OffshoreIsland.air([0.5, 0, 0, 0, 0.5, 0], 0.0, 0.0, 0.35)
	_t._check(clear.x == 1.0 and marine.x == 0.0 and rain.x == 0.0 and over.x > 0.0 and over.x < 0.5
		and santa.x == 1.0 and is_equal_approx(half.x, 0.5),
		"the island shows on a clear day and in a Santa Ana, faintly under overcast, not in the marine layer or rain")
	_t._check(santa.y > clear.y * 2.0 and golden.y < clear.y and over.y < clear.y,
		"the air over the island: Santa Ana far clearer, golden-hour smog and overcast hazier (%.0f / %.0f / %.0f / %.0f km)" % [santa.y, clear.y, golden.y, over.y])
	_t._check(clear.z == 0.0 and none.z == 1.0 and none.x == 1.0,
		"the island's lights are off by day and on at night; no Weather reads as clear")
	_t._check(OffshoreIsland.AMOUNT_BY_STATE.size() == 6 and OffshoreIsland.HAZE_BY_STATE.size() == 6,
		"the island's weather tables have a row per Weather.State")


## The sky draws it: sky.gdshader includes the island and calls it before the clouds, the include
## has every uniform the node sets, DayNight made the node and its pushes reached the material.
func _wired_into_the_sky(city: Node3D) -> void:
	var sky_src := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	var inc := FileAccess.get_file_as_string("res://shaders/offshore_island.gdshaderinc")
	var call_at := sky_src.find("island_draw(")
	var clouds_at := sky_src.find("// --- Cumulus ---")
	_t._check(sky_src.find("offshore_island.gdshaderinc") >= 0 and call_at > 0 and clouds_at > call_at,
		"sky.gdshader includes the island and draws it before the clouds")
	var names := ["island_amount", "island_centre", "island_axis", "island_half_len", "island_half_wid",
		"island_peak", "island_haze_km", "island_glare", "island_land", "island_town", "island_town_out",
		"island_lights", "island_seed"]
	var missing: Array[String] = []
	for n in names:
		if inc.find("uniform ") < 0 or inc.find(" " + n + " ") < 0:
			missing.append(n)
	_t._check(missing.is_empty(), "the island include declares every uniform OffshoreIsland sets %s" % [missing])
	var day: Node = city.get_node_or_null("DayNight")
	var node: Node = day.get_node_or_null("OffshoreIsland") if day else null
	_t._check(node != null, "DayNight made the OffshoreIsland node")
	var env: Environment = null
	for n in city.find_children("*", "WorldEnvironment", true, false):
		env = (n as WorldEnvironment).environment
	var sky := env.sky.sky_material as ShaderMaterial if env and env.sky else null
	if node == null or sky == null:
		_t._check(false, "the island's sky material is reachable")
		return
	node.call("_push")
	var c: Vector2 = sky.get_shader_parameter("island_centre")
	var amount: float = sky.get_shader_parameter("island_amount")
	var weather: Node = city.find_child("Weather", true, false)
	var weights := []
	if weather:
		for s in 6:
			weights.append(float(weather.call("weight_of", s)))
	var want := OffshoreIsland.air(weights, float(day.get("golden")), float(day.get("night_factor")), 0.35)
	_t._check(c.is_equal_approx(OffshoreIsland.CENTRE / 1000.0) and is_equal_approx(amount, want.x),
		"the island's shape and the weather's amount reach the sky (centre %s, amount %.2f, want %.2f)" % [c, amount, want.x])
