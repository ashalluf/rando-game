extends RefCounted
## The brush_fire refcam (fleet wave 8, rc5-brush-fire; docs/HANDOFF.md "The brush fire on a Santa
## Ana evening"): checks for tests/smoke_test.gd. CPU only:
##   * the brush_fire row is in tools/refcams/cameras_w8.json at 18:30 in a Santa Ana, on a
##     midtown street, looking north toward the fire;
##   * BrushFireLook's sky smoke is none by day and in other weather, there at dusk, and moves the
##     horizon toward amber-brown; forcing the Santa Ana at 18:30 browns DayNight's fog;
##   * SantaAnaFx builds the pall and the ash, the column and the card take the look, the fire card
##     stands under the site, and they all hide with the weather.
## BRUSH_FIRE_LOOK=0 is the A/B.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan") if city else null
	_camera_row(plan)
	_sky()
	if not BrushFireLook.enabled:
		_t._check(true, "rc5-brush-fire: off (BRUSH_FIRE_LOOK=0)")
		return
	var weather: Node = city.get_node_or_null("Weather") if city else null
	var day: Node = city.get_node_or_null("DayNight") if city else null
	if weather == null or day == null:
		_t._check(true, "rc5-brush-fire: no Weather / DayNight in this scene")
		return
	var saved := {}
	for key in ["state", "_previous", "blend", "wetness", "drying", "_forced", "_timer"]:
		saved[key] = weather.get(key)
	var saved_hour: float = float(day.get("hour"))
	_live(weather, day, plan)
	for key in saved:
		weather.set(key, saved[key])
	day.set("hour", saved_hour)
	for i in 4:
		day.call("_apply")
		weather.call("_process", 0.05)


func _camera_row(plan: CityPlan) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "brush_fire":
				row = c
	_t._check(not row.is_empty() and String(row.get("weather", "")) == "santa_ana" and absf(float(row.get("hour", 0.0)) - 18.5) < 0.01,
		"rc5-brush-fire: the brush_fire row is in cameras_w8.json, 18:30 in a Santa Ana")
	if row.is_empty() or plan == null:
		return
	var eye: Array = row.eye
	var at := Vector2(float(eye[0]), float(eye[2]))
	_t._check(plan.district_at(at) == CityPlan.District.MIDTOWN, "rc5-brush-fire: the camera stands in midtown")
	# Looking toward the fire: yaw within 10 degrees of the bearing (forward is -Z).
	var fire := LaWeather.fire_site(plan)
	var d := Vector2(fire.x, fire.z) - at
	var bearing := rad_to_deg(atan2(-d.x, -d.y))
	_t._check(absf(wrapf(bearing - float(eye[3]), -180.0, 180.0)) < 10.0,
		"rc5-brush-fire: the camera looks at the fire (bearing %.1f, yaw %.1f)" % [bearing, float(eye[3])])


func _sky() -> void:
	var top := Color(0.1, 0.19, 0.48)
	var rim := Color(1.0, 0.6, 0.38)
	_t._check(BrushFireLook.sky_weight(0.0, 1.0, 0.0) == 0.0, "rc5-brush-fire: no smoke in the sky without a Santa Ana")
	_t._check(BrushFireLook.sky_weight(1.0, 0.0, 0.0) == 0.0, "rc5-brush-fire: no smoke in the sky by day (the wind clears the basin)")
	if not BrushFireLook.enabled:
		return
	var w := BrushFireLook.sky_weight(1.0, 1.0, 0.0)
	_t._check(w > 0.9, "rc5-brush-fire: the dusk sky carries the smoke (%.2f)" % w)
	var out: Array = BrushFireLook.sky(top, rim, 1.0, 1.0, 0.0)
	var r: Color = out[1]
	_t._check(r.b < rim.b and r.r > r.b * 2.0, "rc5-brush-fire: the dusk horizon goes amber-brown (%s)" % r)
	var same: Array = BrushFireLook.sky(top, rim, 1.0, 0.0, 0.0)
	_t._check(same[0] == top and same[1] == rim, "rc5-brush-fire: the day sky is untouched")


func _hold(weather: Node, day: Node, s: int, hour: float) -> void:
	day.set("hour", hour)
	weather.call("force_state", s)
	weather.set("_previous", s)
	weather.set("blend", 1.0)
	for i in 4:
		day.call("_apply")
		weather.call("_process", 0.05)


func _live(weather: Node, day: Node, plan: CityPlan) -> void:
	var env: Environment = weather.get("_env")
	_hold(weather, day, Weather.State.CLEAR, 18.5)
	var clear_fog: Color = env.fog_light_color if env else Color.BLACK
	_hold(weather, day, Weather.State.SANTA_ANA, 18.5)
	var fx: Node3D = weather.get_node_or_null("SantaAna")
	_t._check(fx != null and fx.visible, "rc5-brush-fire: the fire is drawn at 18:30 in a Santa Ana")
	if fx == null:
		return
	if env:
		var f := env.fog_light_color
		_t._check(f.r > f.b * 1.3 and f != clear_fog, "rc5-brush-fire: the dusk fog is smoke brown (%s, clear %s)" % [f, clear_fog])
	var pall := fx.get_node_or_null("SmokePall") as CPUParticles3D
	var ash := fx.get_node_or_null("Ash") as CPUParticles3D
	_t._check(pall != null and pall.emitting and pall.local_coords, "rc5-brush-fire: the smoke pall drifts off the column (local, emitting)")
	_t._check(ash != null, "rc5-brush-fire: ash in the air round the player")
	var plume := fx.get_node_or_null("SmokeColumn") as CPUParticles3D
	if plume:
		var mat := (plume.mesh as QuadMesh).material as ShaderMaterial
		_t._check(float(mat.get_shader_parameter("look")) > 0.5 and plume.amount == BrushFireLook.PLUME_PUFFS,
			"rc5-brush-fire: the column takes the look (%d puffs)" % plume.amount)
	var glow := fx.get_node_or_null("FireGlow") as MeshInstance3D
	if glow:
		var site := LaWeather.fire_site(plan)
		var ws: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/WorldState")
		var foot: float = (ws.call("to_world", glow.global_position) as Vector3).y if ws else glow.global_position.y
		_t._check(absf(foot - (site.y - BrushFireLook.FOOT_DROP)) < 1.0, "rc5-brush-fire: the fire card stands under the site (%.1f vs %.1f)" % [foot, site.y])
		var gm := glow.material_override as ShaderMaterial
		_t._check(float(gm.get_shader_parameter("look")) > 0.5, "rc5-brush-fire: the fire line follows the crest's flanks")
	_hold(weather, day, Weather.State.CLEAR, 18.5)
	_t._check(not fx.visible and pall != null and not pall.emitting, "rc5-brush-fire: the pall goes with the wind")
