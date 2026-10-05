extends RefCounted
## Los Angeles weather (LaWeather, MarineLayer, SantaAnaFx, HeatHaze, RoofRain and their states in
## Weather), for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after
## the autoloads.
##
## Checks the marine layer's clock (covered overnight, burnt off inland first, clear at the coast
## by early afternoon, waiting offshore, rolling back in as a bank at evening), that the shader's
## copy of the edge wobble is the script's, that forcing each state drives DayNight, the height
## fog, the deck, the wind and the fire, that the hour weights the auto roll, that the heat shimmer
## follows the afternoon and stays off where it cannot be drawn, that rain splashes off car roofs,
## and that the pause menu offers every state.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_clock()
	_shader_mirror()
	var weather: Node = city.get_node_or_null("Weather")
	var day: Node = city.get_node_or_null("DayNight")
	_t._check(weather != null and day != null, "LA weather: the city has Weather and DayNight")
	if weather == null or day == null:
		return
	var saved := {}
	for key in ["state", "_previous", "blend", "wetness", "drying", "_forced", "_timer"]:
		saved[key] = weather.get(key)
	var saved_hour: float = float(day.get("hour"))
	_marine(city, weather, day)
	_santa_ana(city, weather, day)
	_heat(weather, day)
	_roll(weather)
	_roof_rain(city, weather)
	var menu_consts: Dictionary = (load("res://scripts/ui/pause_menu.gd") as GDScript).get_script_constant_map()
	_t._check((menu_consts["WEATHERS"] as Array).size() == Weather.State.size() + 1,
		"LA weather: the pause menu has Auto and a chip per weather state (%d)" % (menu_consts["WEATHERS"] as Array).size())
	for key in saved:
		weather.set(key, saved[key])
	day.set("hour", saved_hour)
	_settle(weather, day)


func _settle(weather: Node, day: Node) -> void:
	for i in 4:
		day.call("_apply")
		weather.call("_process", 0.05)


func _hold(weather: Node, day: Node, s: int, hour: float) -> void:
	day.set("hour", hour)
	weather.call("force_state", s)
	weather.set("_previous", s)
	weather.set("blend", 1.0)
	_settle(weather, day)


func _clock() -> void:
	var coast := -900.0
	var downtown := Vector2(2800.0, 0.0)
	var beach := Vector2(coast + 60.0, 0.0)
	var sea := Vector2(coast - 3300.0, 0.0)
	var c := func(h: float, p: Vector2) -> float: return LaWeather.cover_at(coast, h, p.x, p.y)
	_t._check(c.call(5.0, downtown) > 0.99 and c.call(9.0, downtown) > 0.99 and c.call(9.0, beach) > 0.99,
		"marine layer: the whole basin is under the deck overnight and at 09:00")
	# Inland first: downtown clears while the beach is still grey.
	var dt_clear := _first_clear(coast, downtown)
	var beach_clear := _first_clear(coast, beach)
	_t._check(dt_clear > 10.0 and dt_clear < 11.8 and beach_clear > dt_clear + 0.6 and beach_clear < 13.6,
		"marine layer: burns off downtown at %.1f h, then the beach at %.1f h" % [dt_clear, beach_clear])
	_t._check(c.call(15.0, downtown) < 0.01 and c.call(15.0, beach) < 0.01 and c.call(15.0, sea) > 0.99,
		"marine layer: in the afternoon the deck waits offshore as a bank")
	_t._check(c.call(18.5, beach) < 0.05 and c.call(18.5, Vector2(coast - 1400.0, 0.0)) > 0.95 and LaWeather.bank_amount(18.5) > 0.99,
		"marine layer: at 18:30 the fog bank stands off the beach and reads as a wall")
	_t._check(c.call(23.0, downtown) > 0.9 and LaWeather.bank_amount(10.0) < 0.01,
		"marine layer: it is back over the city by night, and the morning edge is no wall")


func _first_clear(coast: float, p: Vector2) -> float:
	var h := 8.0
	while h < 16.0:
		if LaWeather.cover_at(coast, h, p.x, p.y) < 0.5:
			return h
		h += 0.05
	return 99.0


func _shader_mirror() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/marine_layer.gdshader")
	_t._check(src.contains("260.0 * sin(z * 0.0011 + 1.3) + 140.0 * sin(z * 0.0029 + 0.4)"),
		"marine layer: the shader's edge wobble is LaWeather.edge_wobble()")


func _marine(_city: Node3D, weather: Node, day: Node) -> void:
	_hold(weather, day, Weather.State.MARINE, 6.5)
	var env: Environment = weather.get("_env")
	var layer: Node3D = weather.get_node_or_null("MarineLayer")
	var sun: DirectionalLight3D = weather.get("_sun")
	_t._check(float(weather.get("marine_here")) > 0.9 and float(day.get("marine")) > 0.9,
		"marine layer: at 06:30 the camera is under the deck (%.2f)" % float(weather.get("marine_here")))
	_t._check(env == null or (env.fog_height_density < 0.0 and absf(env.fog_height - LaWeather.FOG_START) < 0.01),
		"marine layer: the height fog thickens UP into the deck, fading the tower tops")
	_t._check(layer != null and layer.visible, "marine layer: the deck is drawn")
	_t._check(sun == null or sun.shadow_opacity < 0.5, "marine layer: the light under it is nearly shadowless")
	_hold(weather, day, Weather.State.MARINE, 15.0)
	_t._check(float(weather.get("marine_here")) < 0.05 and (env == null or env.fog_height_density >= 0.0) and layer.visible,
		"marine layer: burnt off over the city at 15:00, the bank still drawn offshore")
	_hold(weather, day, Weather.State.CLEAR, 15.0)
	_t._check(not layer.visible and float(day.get("marine")) == 0.0 and (sun == null or sun.shadow_opacity > 0.99),
		"marine layer: a clear day has no deck and full shadows")


func _santa_ana(city: Node3D, weather: Node, day: Node) -> void:
	_hold(weather, day, Weather.State.CLEAR, 14.0)
	var env: Environment = weather.get("_env")
	var clear_fog := env.fog_density if env else 0.0
	_hold(weather, day, Weather.State.SANTA_ANA, 14.0)
	var fx: Node3D = weather.get_node_or_null("SantaAna")
	_t._check(float(weather.get("santa_ana_weight")) > 0.99 and float(day.get("santa_ana")) > 0.99,
		"Santa Ana: forcing it drives DayNight")
	_t._check(env == null or env.fog_density < clear_fog * 0.6, "Santa Ana: the air is clearer than a clear day (%.6f < %.6f)" % [env.fog_density if env else 0.0, clear_fog])
	var lean: Vector2 = weather.get("_lean_now")
	_t._check(lean.length() > 0.9 and lean.x < 0.0 and lean.y > 0.0, "Santa Ana: the trees lean offshore, toward the south-west")
	_t._check(fx != null and fx.visible, "Santa Ana: the fire, dust and litter are drawn")
	if fx:
		var site: Vector3 = fx.get("site")
		var plan: CityPlan = city.plan
		_t._check(site.y > 120.0 and plan.zone_at(Vector2(site.x, site.z)) == MacroMap.Zone.HILLS
			and site == LaWeather.fire_site(plan),
			"Santa Ana: the brush fire burns on a ridge of the front range (%.0f, %.0f, %.0f)" % [site.x, site.y, site.z])
	_hold(weather, day, Weather.State.CLEAR, 14.0)
	_t._check(not fx.visible and (weather.get("_lean_now") as Vector2).length() < 0.01, "Santa Ana: the wind drops with it")


func _heat(weather: Node, day: Node) -> void:
	_hold(weather, day, Weather.State.CLEAR, 14.5)
	var hot := float(weather.get("heat"))
	_hold(weather, day, Weather.State.SANTA_ANA, 14.5)
	var hotter := float(weather.get("heat"))
	_hold(weather, day, Weather.State.CLEAR, 21.0)
	var night := float(weather.get("heat"))
	_hold(weather, day, Weather.State.RAIN, 14.5)
	var wet := float(weather.get("heat"))
	_t._check(hot > 0.3 and hotter > hot and night == 0.0 and wet == 0.0,
		"heat haze: a clear afternoon shimmers (%.2f), a Santa Ana more (%.2f), never at night or in rain" % [hot, hotter])
	_t._check(not HeatHaze.supported() == (weather.get_node_or_null("HeatHaze") == null),
		"heat haze: built only where it can be drawn (Forward+ desktop)")


func _roll(weather: Node) -> void:
	var share := func(o: PackedFloat32Array, i: int) -> float:
		var tot := 0.0
		for v in o:
			tot += v
		return o[i] / tot
	var morning: PackedFloat32Array = weather.call("odds_at", 7.0)
	var afternoon: PackedFloat32Array = weather.call("odds_at", 14.0)
	_t._check(share.call(morning, Weather.State.MARINE) > 0.3 and share.call(afternoon, Weather.State.MARINE) < 0.1
		and share.call(morning, Weather.State.SANTA_ANA) < 0.06,
		"weather roll: the marine layer is common on mornings (%.2f), rare by afternoon (%.2f), the Santa Ana rare" % [share.call(morning, Weather.State.MARINE), share.call(afternoon, Weather.State.MARINE)])


func _roof_rain(city: Node3D, weather: Node) -> void:
	var rr: RoofRain = weather.get_node_or_null("RoofRain")
	_t._check(rr != null and rr.multimesh != null and rr.multimesh.instance_count > 0, "rain: the roof splash pool is built")
	if rr == null:
		return
	var car: Node3D = null
	for v in city.get_tree().get_nodes_in_group("vehicle"):
		if v is Vehicle and not (v is Aircraft) and (v as Node3D).is_inside_tree():
			car = v
			break
	if car == null:
		_t._check(true, "rain: no car to splash on (skipped)")
		return
	var before := 0
	for a in rr.get("_age"):
		if float(a) <= rr.life:
			before += 1
	rr.call("_spawn", car)
	var after := 0
	var top_y := -1.0e9
	var ages: PackedFloat32Array = rr.get("_age")
	var xfs: Array = rr.get("_xf")
	for i in ages.size():
		if ages[i] <= rr.life:
			after += 1
			if ages[i] == 0.0:
				top_y = (xfs[i] as Transform3D).origin.y
	var roof := (car.global_transform * Vector3(0.0, float(car.get("_model_top_y")), 0.0)).y
	_t._check(after == before + 1 and absf(top_y - roof) < 0.6, "rain: a splash lands on a car's roof (%.2f m against %.2f m)" % [top_y, roof])
