extends RefCounted
## Storm drama (StormDrama, scripts/world/storm_drama.gd), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Pure parts: the gust clock is 0..1 and peaky (strong gusts, long lulls); the trees' lean runs
## down the storm's wind and never drops to nothing in a lull; the wind the shaders hard-code is
## Weather's rain_wind; the day sky goes darker and greener and the night keeps its colours; a bolt
## is the same bolt for the same strike, from the cloud base to the ground with its branches; the
## sky's flash keeps the old even flash by default and the curtain its old look with no sheets.
## Live: a forced storm drives the node (the lean global, the sheets, the inner curtain, the spray,
## DayNight's hook), a forced strike draws a bolt with the thunder on its way at 343 m/s, and the
## run-off probe finds a roof edge and an awning on a staged building in the air. The weather, the
## staged building and the player are put back.

var _t: Object
var _tree: SceneTree
var _city: Node3D
var _deck: Node3D


func run(t: Object, city: Node3D) -> void:
	_t = t
	_tree = (t as Node).get_tree()
	_city = city
	_pure()
	_sources()
	await _live()


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _pure() -> void:
	var lo := 1.0
	var hi := 0.0
	var mean := 0.0
	var inside := true
	for i in 1200:
		var g := StormDrama.gust(float(i) * 0.1)
		inside = inside and g >= 0.0 and g <= 1.0
		lo = minf(lo, g)
		hi = maxf(hi, g)
		mean += g / 1200.0
	_check(inside and hi > 0.85 and lo < 0.1 and mean < 0.55,
		"the storm's gusts are 0..1 and peaky: strong gusts, long lulls (min %.2f, max %.2f, mean %.2f)" % [lo, hi, mean])
	var calm := StormDrama.lean_for(0.0, 3.0)
	var ok := calm == Vector2.ZERO
	for i in 60:
		var l := StormDrama.lean_for(1.0, float(i) * 1.7)
		ok = ok and l.normalized().dot(StormDrama.WIND_DIR) > 0.999 \
			and l.length() >= StormDrama.LEAN * StormDrama.LEAN_LULL - 0.001 and l.length() <= StormDrama.LEAN + 0.001
	_check(ok, "a storm leans the trees down its wind, never less than the lull's share, none without a storm")
	var w := Vector2(6.0, 2.0).normalized()
	_check(w.distance_to(StormDrama.WIND_DIR) < 0.002, "StormDrama's wind is Weather's rain_wind (%s vs %s)" % [StormDrama.WIND_DIR, w])
	var old_top := Color(0.16, 0.17, 0.2)
	var old_rim := Color(0.3, 0.31, 0.34)
	var day: Array = StormDrama.sky(old_top, old_rim, 1.0, 0.0)
	var night: Array = StormDrama.sky(old_top, old_rim, 1.0, 1.0)
	var top: Color = day[0]
	var rim: Color = day[1]
	_check(top.get_luminance() < old_top.get_luminance() and rim.get_luminance() < old_rim.get_luminance()
		and top.g > top.r and top.g > top.b and rim.g > rim.r and rim.g > rim.b,
		"a storm's day sky is darker and greener than the rain's grey (top %s, horizon %s)" % [top, rim])
	_check(night[0] == old_top and night[1] == old_rim, "a storm's night sky keeps the city's cloud base")
	var a := Vector3(10.0, 820.0, -5.0)
	var b := Vector3(400.0, 0.0, 300.0)
	var p1: Array = StormDrama.bolt_paths(7, a, b)
	var p2: Array = StormDrama.bolt_paths(7, a, b)
	var p3: Array = StormDrama.bolt_paths(8, a, b)
	var main: PackedVector3Array = p1[0]
	_check(main == p2[0] and main != p3[0] and main[0] == a and main[main.size() - 1] == b
		and (p1[1] as Array).size() >= 2 and (p1[1] as Array).size() <= 4 and main.size() == 65,
		"a bolt is the same bolt for the same strike, cloud base to ground, with 2-4 branches (%d points)" % main.size())


func _sources() -> void:
	var sky := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	_check(sky.contains("uniform float flash_spread = 1.0;") and sky.contains("flash * flash_lobe"),
		"the sky's flash leans toward the strike, the old even flash by default (flash_spread 1)")
	var wsrc := FileAccess.get_file_as_string("res://scripts/world/weather.gd")
	_check(wsrc.contains("uniform float sheets = 0.0;") and wsrc.contains("if (sheets > 0.0)")
		and wsrc.contains("uniform float slant = 0.0;") and wsrc.contains("uniform vec2 sheet_dir = vec2(0.949, 0.316);"),
		"the rain curtain's sheets and slant are off by default (the old curtain) and run down the storm's wind")
	var run := FileAccess.get_file_as_string("res://shaders/storm_runoff.gdshader")
	_check(run.contains("vec2(0.949, 0.316)") and not run.contains("sampler2D")
		and not FileAccess.get_file_as_string("res://shaders/storm_bolt.gdshader").contains("sampler2D"),
		"the run-off and the bolt spend no sampler and blow down the same wind")


func _live() -> void:
	var weather: Node = _city.get_node_or_null("Weather")
	if weather == null:
		_check(false, "the city has a Weather node")
		return
	var drama: Node = weather.get_node_or_null("StormDrama")
	_check(drama != null, "Weather makes the StormDrama node (STORM_DRAMA on)")
	if drama == null:
		return
	var saved := {}
	for key in ["state", "_previous", "blend", "_forced", "wetness", "_next_flash", "_strike_age", "_thunder_in"]:
		saved[key] = weather.get(key)
	weather.force_state(3, true)
	await _ticks(8)
	var lean: Variant = RenderingServer.global_shader_parameter_get("wind_lean")
	var sheets := float((weather.get("_curtain_mat") as ShaderMaterial).get_shader_parameter("sheets"))
	_check(absf(float(drama.get("storm")) - 1.0) < 0.01 and sheets > 0.5
		and (lean == null or (lean as Vector2).length() > StormDrama.LEAN * StormDrama.LEAN_LULL * 0.9),
		"a forced storm drives StormDrama: the sheets on the curtain, the trees' lean (%s)" % [lean])
	var daynight: Node = _city.get_node_or_null("DayNight")
	var spray: Node = weather.get("_spray")
	_check((daynight == null or float(daynight.get("storm")) > 0.99) and (spray == null or float(spray.get("gain")) > 1.5),
		"DayNight's storm hook and the heavier tyre spray follow the storm")
	var inner: Node3D = drama.get("_inner")
	_check(OS.has_feature("web") or (inner != null and inner.visible), "the inner rain sheets stand round the camera in a storm")
	var bolts := int(drama.get("bolts"))
	weather.force_strike(900.0, Vector3(1.0, 0.0, 0.0))
	await _ticks(2)
	var bolt: MeshInstance3D = drama.get("_bolt")
	_check(int(drama.get("bolts")) == bolts + 1 and bolt.mesh != null and bolt.visible
		and absf(float(weather.get("_thunder_in")) - 900.0 / 343.0) < 0.2,
		"a strike 900 m off draws its bolt for the flash, its thunder %.2f s behind" % float(weather.get("_thunder_in")))
	var far_bolts := int(drama.get("bolts"))
	weather.force_strike(StormDrama.BOLT_REACH + 300.0, Vector3(0.0, 0.0, 1.0))
	_check(int(drama.get("bolts")) == far_bolts, "a strike past BOLT_REACH flashes with no bolt")
	await _runoff(drama)
	# Put the weather back as it was (no roll of its rng).
	for key in saved:
		weather.set(key, saved[key])
	await _ticks(2)


func _runoff(drama: Node) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	var at := player.global_position + Vector3(40.0, 300.0, -30.0)
	_deck = Node3D.new()
	_city.add_child(_deck)
	# A ring of four low buildings 9 m round a point, one with an awning 3.2 m up.
	for i in 4:
		var d := Vector3(cos(i * PI * 0.5), 0.0, sin(i * PI * 0.5))
		_box(at + d * 14.0 + Vector3(0.0, 6.0, 0.0), Vector3(10.0, 12.0, 10.0))
	_box(at + Vector3(7.0, 3.2, 0.0), Vector3(3.0, 0.15, 6.0))
	_box(at + Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))
	await _ticks(3)
	drama.set("_streams", [] as Array[Dictionary])
	drama.set("_stream_keys", {})
	var kinds := {}
	for i in 40:
		drama.call("_probe", at, at.y)
	for s: Dictionary in drama.get("_streams"):
		kinds[int(s["kind"])] = true
	_check(int(drama.call("stream_count")) >= 3 and kinds.has(0) and kinds.has(2),
		"the run-off probe finds the roof edges round the street and the awning's drip line (%d streams, kinds %s)" % [int(drama.call("stream_count")), kinds.keys()])
	drama.set("_dirty", true)
	drama.call("_write_runoff")
	var mm := (drama.get("_runoff") as MultiMeshInstance3D).multimesh
	_check(mm.visible_instance_count >= int(drama.call("stream_count")), "every stream is drawn (with its splash)")
	drama.set("_streams", [] as Array[Dictionary])
	drama.set("_stream_keys", {})
	drama.call("_write_runoff")
	_deck.queue_free()
	await _ticks(2)


func _box(c: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_deck.add_child(body)
	body.global_position = c
