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
	var steps := _arg("steps", "base,cloth,unshaded,hair,skin,wet,refl,ambient,sun,lamps,fog,glow,grade,skyflat,base").split(",")
	for s in steps:
		_apply(s, true)
		for i in int(_arg("frames", "3")):
			await get_tree().process_frame
		print("PROBE %s %s" % [s, _torso()])
		_crop(s)
		_apply(s, false)
	print("PROBE_DONE")


## A PNG crop round the hero, base64 in the console (the harness keeps the console; the web has
## no file to save to): PROBE_IMG <step> <base64>.
func _crop(step: String) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if p == null or cam == null or _arg("crops", "1") != "1":
		return
	var img := get_viewport().get_texture().get_image()
	if _arg("full", "0") == "1":
		# The whole frame at half size (web-build-5: the MacArthur Park glare was not round the hero).
		img.resize(img.get_width() / 2, img.get_height() / 2)
		print("PROBE_IMG %s %s" % [step, Marshalls.raw_to_base64(img.save_png_to_buffer())])
		return
	var a := cam.unproject_position(p.global_position + Vector3(0, 2.1, 0))
	var b := cam.unproject_position(p.global_position + Vector3(0, -0.2, 0))
	var h := absf(b.y - a.y)
	var r := Rect2i(int(a.x - h * 0.45), int(min(a.y, b.y)), int(h * 0.9), int(h))
	r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.size.x < 2 or r.size.y < 2:
		return
	var c := img.get_region(r)
	print("PROBE_IMG %s %s" % [step, Marshalls.raw_to_base64(c.save_png_to_buffer())])


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
		"cloth", "unshaded", "hair", "skin":
			var want := {"cloth": "hero_cloth", "unshaded": "hero_cloth", "hair": "hero_hair", "skin": "hero_skin"}[step] as String
			var av := get_tree().get_first_node_in_group("player")
			for n in av.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				for i in mi.get_surface_override_material_count():
					var m := mi.get_surface_override_material(i)
					if on and m is ShaderMaterial and str((m as ShaderMaterial).shader.resource_path).contains(want):
						_saved[[mi, i]] = m
						var flat := StandardMaterial3D.new()
						flat.albedo_color = Color(0.02, 0.02, 0.02) if step != "skin" else Color(0.5, 0.35, 0.28)
						flat.roughness = 0.45
						if step == "unshaded":
							flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
							flat.albedo_color = Color(0.08, 0.08, 0.08)
						mi.set_surface_override_material(i, flat)
			if not on:
				for k in _saved.keys():
					if k is Array:
						(k[0] as MeshInstance3D).set_surface_override_material(k[1], _saved[k])
						_saved.erase(k)
		"fog":
			if env:
				if on:
					_saved["fog"] = env.fog_enabled
					_saved["vfog"] = env.volumetric_fog_enabled
					env.fog_enabled = false
					env.volumetric_fog_enabled = false
				else:
					env.fog_enabled = _saved["fog"]
					env.volumetric_fog_enabled = _saved["vfog"]
		"scan":
			# Every visible geometry within 400 m whose material reads the screen, or whose box
			# is over 150 m (web-build-5: the MacArthur Park glare), printed as PROBE_GEO lines.
			if on:
				_scan()
		"hidescreen":
			# Hides what "scan" lists as screen-reading.
			if on:
				for gi in _screen_readers():
					gi.visible = false
					_hidden.append(gi)
			else:
				for gi in _hidden:
					if is_instance_valid(gi):
						gi.visible = true
				_hidden.clear()
		"aerial":
			if env:
				if on:
					_saved["aerial"] = env.fog_aerial_perspective
				env.fog_aerial_perspective = 0.0 if on else _saved["aerial"]
		"quality":
			# The sky's radiance filtered in full every frame (PROCESS_MODE_QUALITY) for the step.
			if env and env.sky:
				if on:
					_saved["pmode"] = env.sky.process_mode
				env.sky.process_mode = Sky.PROCESS_MODE_QUALITY if on else _saved["pmode"]
		"glow":
			if env:
				if on:
					_saved["glow"] = env.glow_enabled
				env.glow_enabled = false if on else _saved["glow"]
		"grade":
			if env:
				if on:
					_saved["adj"] = env.adjustment_enabled
				env.adjustment_enabled = false if on else _saved["adj"]
		"skyflat":
			if env:
				if on:
					_saved["bg"] = env.background_mode
					_saved["sky"] = env.sky
					var sk := Sky.new()
					sk.sky_material = ProceduralSkyMaterial.new()
					env.sky = sk
				else:
					env.sky = _saved["sky"]
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


func _materials(gi: GeometryInstance3D) -> Array:
	var out: Array = []
	if gi.material_override:
		out.append(gi.material_override)
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			if mi.get_surface_override_material(i):
				out.append(mi.get_surface_override_material(i))
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				if mi.mesh.surface_get_material(i):
					out.append(mi.mesh.surface_get_material(i))
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh and (gi as MultiMeshInstance3D).multimesh.mesh:
		var m := (gi as MultiMeshInstance3D).multimesh.mesh
		for i in m.get_surface_count():
			if m.surface_get_material(i):
				out.append(m.surface_get_material(i))
	elif gi is CPUParticles3D and (gi as CPUParticles3D).mesh:
		var m2 := (gi as CPUParticles3D).mesh
		for i in m2.get_surface_count():
			if m2.surface_get_material(i):
				out.append(m2.surface_get_material(i))
	return out


func _reads_screen(m: Material) -> bool:
	return m is ShaderMaterial and (m as ShaderMaterial).shader != null \
		and (m as ShaderMaterial).shader.code.contains("hint_screen_texture")


func _screen_readers() -> Array:
	var out: Array = []
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.is_visible_in_tree() and _materials(gi).any(func(m): return _reads_screen(m)):
			out.append(gi)
	return out


func _scan() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var box := gi.global_transform * gi.get_aabb()
		var d := box.get_center().distance_to(at)
		var screen := _materials(gi).any(func(m): return _reads_screen(m))
		if (screen and d < 2000.0) or (box.size.length() > 600.0 and d < 300.0):
			var shaders := []
			for m in _materials(gi):
				shaders.append(str((m as ShaderMaterial).shader.resource_path).get_file() if m is ShaderMaterial else m.get_class())
			print("PROBE_GEO %s %s d=%.0f size=%s screen=%s %s" % [gi.get_class(), gi.get_path(), d, box.size.round(), screen, shaders])
	for n in get_tree().root.find_children("*", "CanvasItem", true, false):
		var ci := n as CanvasItem
		if ci.is_visible_in_tree() and _reads_screen(ci.material):
			print("PROBE_CANVAS %s %s" % [ci.get_path(), str((ci.material as ShaderMaterial).shader.resource_path).get_file()])


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
