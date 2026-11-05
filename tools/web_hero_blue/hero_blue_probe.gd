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
				# Split at the first "=" only (glob:<name>=<v> carries one).
				var kv := part.split("=", true, 1)
				_q[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()


func _process(_delta: float) -> void:
	# ap_slow=<ms>: every frame takes at least that long (a browser frame under SwiftShader), so a
	# native run sees the same huge process deltas.
	var slow := int(_arg("ap_slow", "0"))
	if slow > 0:
		OS.delay_msec(slow)


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
			var h: String = hides[i - 1]
			if h.begins_with("plume:"):
				# One change to every fountain plume (web-build-5's A/B of the MacArthur glare).
				for n in get_tree().root.find_children("*FountainPlume", "CPUParticles3D", true, false):
					var pl := n as CPUParticles3D
					match h.substr(6):
						"fixed":
							pl.fixed_fps = 30
						"unshaded":
							((pl.mesh as QuadMesh).material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						"nocurve":
							pl.scale_amount_curve = null
						"nodamp":
							pl.damping_min = 0.0
							pl.damping_max = 0.0
						"local":
							pl.local_coords = true
						"restart":
							pl.restart()
			elif h.begins_with("q:"):
				# q:<level> runs Quality.apply_level() as a native build does at start (the web never does).
				var qn := get_tree().current_scene.get_node_or_null("Quality")
				if qn:
					qn.call("apply_level", int(h.substr(2)))
			elif h == "sun:noshadow" or h == "sun:shadow" or h.begins_with("sun:pssm"):
				# The shadowed sun is drawn in an additive pass of its own on Compatibility.
				for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
					var dl := n as DirectionalLight3D
					if h == "sun:noshadow":
						dl.shadow_enabled = false
					elif h == "sun:shadow":
						dl.shadow_enabled = true
					else:
						dl.directional_shadow_mode = int(h.substr(8)) as DirectionalLight3D.ShadowMode
					print("AUTOPROBE_SUN %s shadow=%s mode=%d max=%.0f" % [dl.get_path(), dl.shadow_enabled, dl.directional_shadow_mode, dl.directional_shadow_max_distance])
			elif h == "sun:on" or h == "omni:on":
				for n in get_tree().root.find_children("*", "Light3D", true, false):
					if (h == "sun:on") == (n is DirectionalLight3D):
						(n as Light3D).visible = true
			elif h == "omni:off" or h == "sun:off" or h == "omni:count":
				var nl := 0
				for n in get_tree().root.find_children("*", "Light3D", true, false):
					var l := n as Light3D
					if l.is_visible_in_tree() and not (l is DirectionalLight3D):
						nl += 1
					if h == "omni:off" and not (l is DirectionalLight3D):
						l.visible = false
					elif h == "sun:off" and l is DirectionalLight3D:
						l.visible = false
				print("AUTOPROBE_LIGHTS visible non-directional %d" % nl)
			elif h.begins_with("cf:"):
				# cf:<far> sets every material's CameraFade reach (cf:0 = rc2-hero-foot's fade off).
				var seen := {}
				for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
					var mats: Array = [(n as GeometryInstance3D).material_override]
					if n is MeshInstance3D and (n as MeshInstance3D).mesh:
						for si in (n as MeshInstance3D).mesh.get_surface_count():
							mats.append((n as MeshInstance3D).mesh.surface_get_material(si))
					elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
						var mm := (n as MultiMeshInstance3D).multimesh.mesh
						for si in mm.get_surface_count():
							mats.append(mm.surface_get_material(si))
					for m in mats:
						if m is ShaderMaterial and not seen.has(m) and (m as ShaderMaterial).get_shader_parameter("cf_far") != null:
							seen[m] = true
							(m as ShaderMaterial).set_shader_parameter("cf_far", h.substr(3).to_float())
				print("AUTOPROBE_CF %d materials" % seen.size())
			elif h.begins_with("cq:"):
				var csn := get_tree().root.get_node_or_null("ContactShadows")
				var q := csn.get_node_or_null("ContactQuads") as MultiMeshInstance3D if csn else null
				if q:
					match h:
						"cq:stop":
							csn.set_process(false)
						"cq:go":
							csn.set_process(true)
						"cq:prio0":
							(q.material_override as ShaderMaterial).render_priority = 0
						"cq:quadmesh":
							var qm := QuadMesh.new()
							qm.orientation = PlaneMesh.FACE_Y
							q.multimesh.mesh = qm
						"cq:dump":
							var mm := q.multimesh
							for k in mm.visible_instance_count:
								print("AUTOPROBE_CQ %d %s col=%s cu=%s" % [k, mm.get_instance_transform(k), mm.get_instance_color(k), mm.get_instance_custom_data(k)])
			elif h == "mm:scan":
				_mm_scan()
			elif h == "list:big":
				_list_big()
			elif h.begins_with("hero:"):
				_hero_step(h.substr(5))
			elif h.begins_with("env:") or h.begins_with("glob:"):
				# env:refl / env:amb / env:fog / env:glow switch one Environment term off;
				# glob:<name>=<v> sets a shader global (the hero in the rain on the web).
				var we2 := get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
				var e2: Environment = we2.environment if we2 else null
				match h:
					"env:refl":
						if e2: e2.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
					"env:amb":
						if e2: e2.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
					"env:fog":
						if e2: e2.fog_enabled = false
					"env:glow":
						if e2: e2.glow_enabled = false
					"env:skyq":
						if e2 and e2.sky: e2.sky.process_mode = Sky.PROCESS_MODE_QUALITY
					_:
						if h.begins_with("glob:") and h.contains("="):
							var kv := h.substr(5).split("=")
							RenderingServer.global_shader_parameter_set(kv[0], kv[1].to_float())
			elif h.begins_with("gmat:"):
				# gmat:<uniform>=<float> on the horizon plane's material (and so the far ring).
				var gm: ShaderMaterial = get_tree().current_scene.get("_ground_material")
				var kv2 := h.substr(5).split("=")
				if gm:
					var v0: Variant = gm.get_shader_parameter(kv2[0])
					if kv2[1] == "nil":
						gm.set_shader_parameter(kv2[0], null)
					elif v0 is bool or kv2[0] == "aerial_review" or kv2[0] == "macro_mirror":
						gm.set_shader_parameter(kv2[0], kv2[1] == "1")
					elif v0 is int or kv2[0] == "paint_debug":
						gm.set_shader_parameter(kv2[0], int(kv2[1]))
					else:
						gm.set_shader_parameter(kv2[0], kv2[1].to_float())
					print("AUTOPROBE_GMAT %s was %s now %s" % [kv2[0], v0, gm.get_shader_parameter(kv2[0])])
			elif h == "mat:ground":
				_dump_ground()
			elif h.begins_with("show:"):
				# show:<substr> undoes a hide (one subtree at a time, then back).
				for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
					if str(n.get_path()).contains(h.substr(5)):
						(n as Node3D).visible = true
			else:
				var nh := 0
				for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
					if str(n.get_path()).contains(h) and (n as Node3D).visible:
						(n as Node3D).visible = false
						nh += 1
				print("AUTOPROBE_HID %s %d" % [h, nh])
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
	var wx := get_tree().current_scene.get_node_or_null("Weather") if get_tree().current_scene else null
	if wx:
		line += " weather=%s blend=%.2f wet=%.3f rain=%.2f dry=%.2f" % [wx.get("state"), wx.get("blend"), wx.get("wetness"), wx.get("rain_level"), wx.get("drying")]
	print(line)
	# Lights near the camera (a flash left on, a runaway energy).
	if cam:
		for n in get_tree().root.find_children("*", "Light3D", true, false):
			var l := n as Light3D
			if l.is_visible_in_tree() and (l is DirectionalLight3D or l.global_position.distance_to(cam.global_position) < 40.0 or (l.global_position.distance_to(cam.global_position) < 120.0 and l.light_energy > 2.0)):
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
		if not OS.has_feature("web") and _arg("ap_out", "") != "":
			img.save_png(_arg("ap_out", "") + "_%d.png" % i)
			return
		print("PROBE_IMG ap%d %s" % [i, Marshalls.raw_to_base64(img.save_png_to_buffer())])


## hero:<step> (web-hero-blue): one change to the hero's own materials. c2=0 / c2=1 the cloth's
## closeup2, cloth=flat a plain dark StandardMaterial3D on the tracksuit, hair=flat the same on
## the hair, wetgain=0 the wet_gain of the WET_MATERIALS, list prints every hero surface.
func _hero_step(step: String) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	for n in player.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s)
			if m == null:
				m = mi.mesh.surface_get_material(s)
			var sh := ""
			if m is ShaderMaterial and (m as ShaderMaterial).shader:
				sh = (m as ShaderMaterial).shader.resource_path.get_file()
			if step == "list":
				print("AUTOPROBE_HERO %s %d %s %s" % [mi.name, s, m.resource_name if m else "-", sh])
				continue
			var cloth := sh == "hero_cloth.gdshader"
			var hair := sh.begins_with("hero_hair")
			if step.begins_with("c2=") and cloth:
				(m as ShaderMaterial).set_shader_parameter("closeup2", step.substr(3).to_float())
			elif step.begins_with("wetgain=") and m is ShaderMaterial:
				(m as ShaderMaterial).set_shader_parameter("wet_gain", step.substr(8).to_float())
			elif (step == "cloth=flat" and cloth) or (step == "hair=flat" and hair):
				var f := StandardMaterial3D.new()
				f.albedo_color = Color(0.05, 0.05, 0.05)
				f.roughness = 0.8
				mi.set_surface_override_material(s, f)
			elif step.begins_with("cloth:") and cloth:
				var kv := step.substr(6).split("=")
				(m as ShaderMaterial).set_shader_parameter(kv[0], kv[1].to_float())


## list:big (web-hero-blue): every drawn GeometryInstance3D whose box is over 120 m across or that
## is drawn without depth, with its material's shader: what could draw a straight-edged wedge.
func _list_big() -> void:
	var cam := get_viewport().get_camera_3d()
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var bb := g.global_transform * g.get_aabb()
		if bb.size.length() < 120.0:
			continue
		if g is MultiMeshInstance3D:
			continue
		var m: Material = g.material_override
		if m == null and g is MeshInstance3D and (g as MeshInstance3D).mesh and (g as MeshInstance3D).mesh.get_surface_count() > 0:
			m = (g as MeshInstance3D).get_active_material(0)
		var sh := ""
		if m is ShaderMaterial and (m as ShaderMaterial).shader:
			sh = (m as ShaderMaterial).shader.resource_path.get_file()
			if sh == "":
				sh = "inline:" + (m as ShaderMaterial).shader.code.substr(0, 60).replace("\n", " ")
		elif m:
			sh = m.get_class()
		print("AUTOPROBE_BIG %s size=%s d=%.0f %s" % [g.get_path(), bb.size.round(), bb.get_center().distance_to(cam.global_position) if cam else -1.0, sh])


## mm:scan (web-hero-blue): every drawn MultiMesh's visible instances, CPU side: one with a NaN, a
## basis column over 300 m or an origin over 30 km from its node is printed (the stray wedges).
## Also every MultiMeshInstance3D outside /root/City with its instance counts.
func _mm_scan() -> void:
	var nodes := 0
	var bad := 0
	for n in get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
		var mi := n as MultiMeshInstance3D
		if not mi.is_visible_in_tree() or mi.multimesh == null:
			continue
		var mm := mi.multimesh
		nodes += 1
		var vis := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		if not str(mi.get_path()).begins_with("/root/City/"):
			print("AUTOPROBE_MMROOT %s inst=%d vis=%d colors=%s custom=%s" % [mi.get_path(), mm.instance_count, vis, mm.use_colors, mm.use_custom_data])
		for i in mini(vis, 4096):
			var x := mm.get_instance_transform(i)
			var big := maxf(x.basis.x.length(), maxf(x.basis.y.length(), x.basis.z.length()))
			if is_nan(big) or big > 300.0 or x.origin.length() > 30000.0 or is_nan(x.origin.x):
				bad += 1
				if bad < 40:
					print("AUTOPROBE_MMBAD %s i=%d/%d big=%.1f o=%s" % [mi.get_path(), i, vis, big, x.origin.round()])
	print("AUTOPROBE_MMSCAN nodes=%d bad=%d" % [nodes, bad])


## mat:ground (web-hero-blue): every uniform of the horizon plane's material (the far mountains
## read lime on the web), textures by size and format, to diff a web run against a native one.
func _dump_ground() -> void:
	var m: Material = get_tree().current_scene.get("_ground_material")
	if not (m is ShaderMaterial):
		print("AUTOPROBE_MAT not a ShaderMaterial")
		return
	var sm := m as ShaderMaterial
	for u in sm.shader.get_shader_uniform_list():
		var v: Variant = sm.get_shader_parameter(u.name)
		if v is Texture2D:
			var t := v as Texture2D
			var img := t.get_image()
			var px := ""
			if img:
				if img.is_compressed():
					img.decompress()
				px = "%s c=%s m=%s" % [img.get_format(), img.get_pixel(img.get_width() / 2, img.get_height() / 4), img.get_pixel(img.get_width() / 2, img.get_height() / 2)]
			print("AUTOPROBE_MAT %s tex %dx%d %s" % [u.name, t.get_width(), t.get_height(), px])
		else:
			print("AUTOPROBE_MAT %s = %s" % [u.name, v])
	for gname in ["sky_tint", "sun_direction", "night_factor", "lamp_factor", "wind_factor", "aerial_review", "night_flight"]:
		print("AUTOPROBE_GLOB %s = %s" % [gname, RenderingServer.global_shader_parameter_get(gname)])
