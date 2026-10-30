extends Node
## The real city in the browser, then one suspect at a time switched off, the hero's colour read
## back after each (docs/HANDOFF.md "The hero in the rain on the web"). Export it as the main
## scene (MAIN=res://tools/web_hero_rain/hero_probe.tscn tools/web_hero_rain/export_web.sh) and
##   WEB_ROOT=build/web_hero QS='?spawn=2359.4,880,0,12,2&hour=13&weather=rain' LOG=probe.log \
##     WAIT=1500000 SHOT_TIMEOUT=1200000 NOCLICK=1 node tools/webshot/webshot.js
## It also runs natively (opengl3; QS keys as env: SETTLE, STEPS). Prints PROBE <step> r g b (the
## mean of the hero's upper back, 0..255) and LIGHTNEAR lines (the lights that reach him).

const CITY := "res://scenes/levels/city.tscn"

var _q := {}


func _arg(k: String, d: String) -> String:
	if _q.has(k):
		return _q[k]
	var v := OS.get_environment(k.to_upper())
	return v if v != "" else d


func _ready() -> void:
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String:
			for part in (search as String).trim_prefix("?").split("&", false):
				var kv := part.split("=")
				_q[kv[0]] = kv[1] if kv.size() > 1 else "1"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_go.call_deferred()


func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	get_tree().change_scene_to_file(CITY)
	# Wait for the player, then for the city to settle (seconds of wall clock).
	var t0 := Time.get_ticks_msec()
	while get_tree().get_first_node_in_group("player") == null:
		await get_tree().process_frame
	var settle := _arg("settle", "240").to_float() * 1000.0
	while Time.get_ticks_msec() - t0 < settle:
		await get_tree().process_frame
	_report_lights()
	var steps := _arg("steps", "base,lamps,wet,refl,sun,ambient,all").split(",")
	for s in steps:
		_apply(s, true)
		for i in int(_arg("frames", "3")):
			await get_tree().process_frame
		print("PROBE %s %s" % [s, _torso()])
		_apply(s, false)
	print("PROBE_DONE")


var _hidden: Array = []
var _saved := {}


func _apply(step: String, on: bool) -> void:
	var env := get_viewport().world_3d.environment if get_viewport().world_3d else null
	var we := get_tree().current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		env = we.environment
	match step:
		"lamps", "all":
			if on:
				for n in get_tree().current_scene.find_children("*", "Light3D", true, false):
					var l := n as Light3D
					if l.visible and not (l is DirectionalLight3D):
						l.visible = false
						_hidden.append(l)
			else:
				for l in _hidden:
					if is_instance_valid(l):
						l.visible = true
				_hidden.clear()
	match step:
		"wet":
			RenderingServer.global_shader_parameter_set("wet_world", 0.0 if on else 1.0)
		"refl":
			if env:
				if on:
					_saved["refl"] = env.reflected_light_source
				env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if on else _saved["refl"]
		"ambient":
			if env:
				if on:
					_saved["amb"] = env.ambient_light_source
				env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED if on else _saved["amb"]
		"sun", "all":
			for n in get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false):
				var d := n as DirectionalLight3D
				if on:
					_saved[d] = d.visible
					d.visible = false
				elif _saved.has(d):
					d.visible = _saved[d]


func _report_lights() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var at := p.global_position + Vector3(0, 1.2, 0)
	for n in get_tree().current_scene.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if not l.is_visible_in_tree():
			continue
		var reach := 1e9
		if l is OmniLight3D:
			reach = (l as OmniLight3D).omni_range
		elif l is SpotLight3D:
			reach = (l as SpotLight3D).spot_range
		var d := l.global_position.distance_to(at)
		if d < reach:
			print("LIGHTNEAR %s %s d=%.1f e=%.2f col=%s path=%s" % [l.get_class(), l.name, d, l.light_energy, l.light_color, l.get_path()])
	for g in ["road_wetness", "road_drying", "rain_intensity", "wet_world", "lamp_factor", "night_factor"]:
		print("GLOBAL %s %s" % [g, RenderingServer.global_shader_parameter_get(g)])


func _torso() -> String:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if p == null or cam == null:
		return "none"
	var img := get_viewport().get_texture().get_image()
	var c := p.global_position
	var a := cam.unproject_position(c + Vector3(0, 1.45, 0))
	var b := cam.unproject_position(c + Vector3(0, 1.05, 0))
	var w := maxf(2.0, absf(a.y - b.y) * 0.35)
	var s := Vector3.ZERO
	var n := 0
	for y in range(int(min(a.y, b.y)), int(max(a.y, b.y))):
		for x in range(int(a.x - w), int(a.x + w)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var col := img.get_pixel(x, y)
			s += Vector3(col.r, col.g, col.b)
			n += 1
	if n == 0:
		return "none"
	s = s / n * 255.0
	return "%d %d %d (px %d, at %d,%d)" % [roundi(s.x), roundi(s.y), roundi(s.z), n, int(a.x), int(a.y)]
