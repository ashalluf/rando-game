extends Node
## An autoload for a probe export of the REAL main build (tools/web_probe/export_probe.sh): every
## `every` seconds after `settle`, prints the frame's exposure, glow, fog and sky state and the
## whole frame (half size) as AUTOPROBE / PROBE_IMG lines, so the browser log says what changed
## when the picture did (web-build-5: the MacArthur Park washout that the change_scene probe
## never showed). Query string: ap_settle (s, 300), ap_every (s, 120), ap_n (6), ap_img (1).

var _q := {}


func _arg(k: String, d: String) -> String:
	return _q.get(k, OS.get_environment(k.to_upper()) if OS.get_environment(k.to_upper()) != "" else d)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String:
			for part in (search as String).trim_prefix("?").split("&", false):
				var kv := part.split("=")
				_q[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var settle := _arg("ap_settle", "300").to_float() * 1000.0
	while Time.get_ticks_msec() - t0 < settle:
		await get_tree().process_frame
	# ap_stage=fire|hose|medic: Emergency's own staging ahead of the player camera.
	var stage := _arg("ap_stage", "")
	var em := get_tree().current_scene.get_node_or_null("Emergency") if get_tree().current_scene else null
	if stage != "" and em:
		var eye: String = await em.call("stage_for_shot", stage, get_viewport().get_camera_3d())
		print("AUTOPROBE_STAGE %s eye %s" % [stage, eye])
	# ap_hide=a,b,...: after the first report, each report hides one more group of particle
	# emitters (path contains the name) before it is taken: which one draws the glare.
	var hides := _arg("ap_hide", "").split(",", false)
	for i in int(_arg("ap_n", "6")):
		if i >= 1 and i - 1 < hides.size():
			for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
				if str(n.get_path()).contains(hides[i - 1]):
					(n as Node3D).visible = false
			print("AUTOPROBE_HIDE %d %s" % [i, hides[i - 1]])
		_report(i)
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < _arg("ap_every", "120").to_float() * 1000.0:
			await get_tree().process_frame
	print("AUTOPROBE_DONE")


func _report(i: int) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	var env: Environment = null
	var we := get_tree().current_scene.find_child("WorldEnvironment", true, false) if get_tree().current_scene else null
	if we is WorldEnvironment:
		env = (we as WorldEnvironment).environment
	var line := "AUTOPROBE %d t=%.0f fps=%.2f frames=%d" % [i, Time.get_ticks_msec() / 1000.0, Engine.get_frames_per_second(), Engine.get_process_frames()]
	if env:
		line += " exp=%.3f glow=%s/%.2f/%.2f/%.2f fog=%s/%.4f/%.2f vfog=%s amb=%.2f/%.2f adj=%s/%.2f/%.2f/%.2f bg=%.2f" % [
			env.tonemap_exposure, env.glow_enabled, env.glow_intensity, env.glow_bloom, env.glow_hdr_threshold,
			env.fog_enabled, env.fog_density, env.fog_aerial_perspective, env.volumetric_fog_enabled,
			env.ambient_light_energy, env.ambient_light_sky_contribution, env.adjustment_enabled,
			env.adjustment_brightness, env.adjustment_contrast, env.adjustment_saturation, env.background_energy_multiplier]
		line += " fogc=%s" % [env.fog_light_color]
	if cam:
		line += " cam=%s far=%.0f" % [(get_node("/root/WorldState").call("to_world", cam.global_position) as Vector3).round(), cam.far]
		var ca := cam.attributes
		if ca is CameraAttributesPractical:
			var p := ca as CameraAttributesPractical
			line += " ae=%s/%.2f/%.2f ev=%.2f dof=%s" % [p.auto_exposure_enabled, p.auto_exposure_scale, p.auto_exposure_speed,
				p.exposure_multiplier, p.dof_blur_far_enabled]
	line += " ts=%.3f paused=%s" % [Engine.time_scale, get_tree().paused]
	for g in ["night_factor", "lamp_factor", "road_wetness", "wet_world"]:
		line += " %s=%s" % [g, RenderingServer.global_shader_parameter_get(g)]
	print(line)
	# Lights near the camera (a flash left on, a runaway energy).
	if cam:
		for n in get_tree().root.find_children("*", "Light3D", true, false):
			var l := n as Light3D
			if l.is_visible_in_tree() and (l is DirectionalLight3D or l.global_position.distance_to(cam.global_position) < 120.0) and l.light_energy > 2.0:
				print("AUTOPROBE_LIGHT %d %s %s e=%.2f ind=%.2f col=%s" % [i, l.get_class(), l.get_path(), l.light_energy, l.light_indirect_energy, l.light_color])
	# Canvas layers drawing over the 3D (a flash rect left up).
	for n in get_tree().root.find_children("*", "ColorRect", true, false):
		var cr := n as ColorRect
		if cr.is_visible_in_tree() and (cr.color.a > 0.02 or cr.material != null):
			print("AUTOPROBE_RECT %d %s col=%s mat=%s" % [i, cr.get_path(), cr.color, cr.material.shader.resource_path.get_file() if cr.material is ShaderMaterial else ""])
	# Particle emitters near the camera: which one draws what.
	if cam:
		for n in get_tree().root.find_children("*", "CPUParticles3D", true, false):
			var p := n as CPUParticles3D
			if not p.is_visible_in_tree() or p.global_position.distance_to(cam.global_position) > 80.0:
				continue
			var mat: Material = p.material_override
			if mat == null and p.mesh and p.mesh.get_surface_count() > 0:
				mat = p.mesh.surface_get_material(0)
			var mdesc := mat.get_class() if mat else "none"
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				mdesc += "/blend%d/shade%d/bb%d/tex%s" % [sm.blend_mode, sm.shading_mode, sm.billboard_mode, sm.albedo_texture != null]
			elif mat is ShaderMaterial:
				mdesc += "/" + (mat as ShaderMaterial).shader.resource_path.get_file()
			var ramp := ""
			if p.color_ramp:
				for k in p.color_ramp.get_point_count():
					ramp += "%s " % [p.color_ramp.get_color(k)]
			print("AUTOPROBE_PART %d %s d=%.0f emit=%s amt=%d life=%.2f col=%s scale=%.2f-%.2f mat=%s ramp=[%s]" % [i, p.get_path(),
				p.global_position.distance_to(cam.global_position), p.emitting, p.amount, p.lifetime, p.color,
				p.scale_amount_min, p.scale_amount_max, mdesc, ramp])
	if _arg("ap_img", "1") == "1":
		var img := vp.get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		print("PROBE_IMG ap%d %s" % [i, Marshalls.raw_to_base64(img.save_png_to_buffer())])
