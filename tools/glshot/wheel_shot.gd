extends SceneTree
## Renders the generated car wheels on their own, close up, in a bare scene. No city, no
## streaming, so it takes seconds instead of minutes - use it for the iteration loop on the
## wheel and keep city_shot.gd for checking the result in the real street.
##
##   OUT=wheels.png LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/wheel_shot.gd --resolution 1280x720 -- --dist=1.6 --yaw=35
##
## `--dist` is how far the camera stands from a 0.7 m wheel (1.6 m is arm's length, 5.0 is the
## other side of the road), `--yaw` / `--pitch` where it stands, `--sun` where the sun is (the
## default lights the OUTBOARD face; the old default had the sun behind the wheels, which made
## everything read dark whatever the material was doing), and `--mode` picks what to line up:
## `styles` one of each spoke pattern, `kits` one of each finish, `lod` the far meshes, `one`
## a single wheel filling the frame. Add `_clay` for a matte grey (judge FORM) or `_metal` to
## force the Forward+ metal path on a renderer that cannot light it (judge the fallback).

static func _clay() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.62, 0.63)
	m.roughness = 0.55
	m.metallic = 0.0
	m.vertex_color_use_as_albedo = true
	return m


func _initialize() -> void:
	var dist := 1.7
	var yaw := 34.0
	var pitch := -10.0
	var mode := "styles"
	var sun_yaw := 42.0
	var sun_pitch := -40.0
	var style := 0
	var kit := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dist="):
			dist = arg.trim_prefix("--dist=").to_float()
		elif arg.begins_with("--yaw="):
			yaw = arg.trim_prefix("--yaw=").to_float()
		elif arg.begins_with("--pitch="):
			pitch = arg.trim_prefix("--pitch=").to_float()
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--sun="):
			sun_yaw = arg.trim_prefix("--sun=").to_float()
		elif arg.begins_with("--sunpitch="):
			sun_pitch = arg.trim_prefix("--sunpitch=").to_float()
		elif arg.begins_with("--style="):
			style = arg.trim_prefix("--style=").to_int()
		elif arg.begins_with("--kit="):
			kit = arg.trim_prefix("--kit=").to_int()
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)
	await process_frame

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# AgX desaturates hard, which is right for a photograph and useless for a debug view that
	# encodes numbers in the colour channels.
	env.tonemap_mode = (Environment.TONE_MAPPER_LINEAR if mode.ends_with("debug") or mode.ends_with("normals")
			else Environment.TONE_MAPPER_AGX)
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(sun_pitch, sun_yaw, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = not mode.ends_with("noshadow")
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	ground.material_override = PropFactory.material(Color(0.46, 0.46, 0.47), 0.85)
	ground.position.y = -0.36
	world.add_child(ground)

	var rows: Array = []
	var base := mode.trim_suffix("clay").trim_suffix("metal").trim_suffix("flat").trim_suffix("_")
	var metal := mode.ends_with("metal")
	if base == "one":
		rows.append([style, kit, true])
	elif base == "kits":
		for k in PropFactory.WHEEL_KITS.size():
			rows.append([0, k, true])
	elif base == "lod":
		for st in PropFactory.WHEEL_FACES.size():
			rows.append([st, 0, false])
	else:
		for st in PropFactory.WHEEL_FACES.size():
			rows.append([st, st % PropFactory.WHEEL_KITS.size(), true])
	var pitchw := 0.90
	for i in rows.size():
		var holder := Node3D.new()
		holder.position = Vector3((float(i) - float(rows.size() - 1) * 0.5) * pitchw, 0.0, 0.0)
		# Turned so the outboard face looks at the camera the way the right-hand wheels do.
		holder.rotation.y = deg_to_rad(-yaw)
		world.add_child(holder)
		var mi := MeshInstance3D.new()
		mi.mesh = PropFactory.car_wheel(int(rows[i][0]), 0.35, 0.235, bool(rows[i][2]))
		# Clay: the same meshes in a matte grey, which is the only way to judge the FORM here.
		# The real material is metal, and metal under the Compatibility renderer with nothing
		# but a procedural sky to reflect comes out near black whatever its albedo says.
		if mode.ends_with("clay") and not mode.ends_with("debug"):
			mi.material_override = _clay()
		elif mode.ends_with("flat"):
			# The rim FACE slot's resolved numbers as a PLAIN material, no lookup strip and no
			# vertex colour. If this is bright and the real one is dark, the lookup is at fault;
			# if both are dark, it is the geometry or the lighting.
			var fm := StandardMaterial3D.new()
			fm.albedo_color = Color(0.937, 0.945, 0.955)
			fm.metallic = 0.22
			fm.roughness = 0.44
			mi.material_override = fm
		else:
			var wm: Material = PropFactory.wheel_material(int(rows[i][1]), metal)
			if mode.ends_with("debug"):
				# Red = the material class the fragment resolves to, green = the vertex shade.
				# If a spoke comes out red 2/7 = 0.29 and green near 1, the wheel is asking for
				# bright aluminium and something after this is darkening it.
				var dbg := Shader.new()
				dbg.code = "shader_type spatial;\nrender_mode unshaded;\nvoid fragment() {\n\tint s = int(clamp(UV.x * 8.0, 0.0, 7.999));\n\tALBEDO = vec3(float(s) / 7.0, COLOR.r, 0.0);\n}\n"
				var dm := ShaderMaterial.new()
				dm.shader = dbg
				wm = dm
			elif mode.ends_with("normals"):
				# World-space normal in the colour channels: a spoke face that is meant to look
				# straight out of the wheel has to come out red where the wheel faces +X.
				var dbg2 := Shader.new()
				dbg2.code = "shader_type spatial;\nrender_mode unshaded;\nvarying vec3 wn;\nvoid vertex() {\n\twn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;\n}\nvoid fragment() {\n\tALBEDO = normalize(wn) * 0.5 + 0.5;\n}\n"
				var dm2 := ShaderMaterial.new()
				dm2.shader = dbg2
				wm = dm2
			mi.material_override = wm
			if i == 0 and wm is ShaderMaterial and base == mode:
				var parts: Array = []
				for q in PropFactory.WHEEL_SLOTS:
					var nm: String = PropFactory.WHEEL_UNIFORMS[q]
					parts.append("%s a=%v mr=%v" % [nm,
							(wm as ShaderMaterial).get_shader_parameter("c_" + nm),
							(wm as ShaderMaterial).get_shader_parameter("m_" + nm)])
				print("SLOTS ", " | ".join(parts))
		holder.add_child(mi)
		var cal := MeshInstance3D.new()
		cal.mesh = PropFactory.car_caliper(int(rows[i][0]), 0.35, 0.235)
		cal.material_override = mi.material_override
		holder.add_child(cal)

	# A reference ball and slab beside the line-up, in a plain StandardMaterial3D at exactly the
	# numbers the rim's FACE slot resolves to. If the wheel face is darker than the ball, the
	# material is wrong; if they match, what looks dark is the lighting or the geometry.
	for j in 2:
		var ref := MeshInstance3D.new()
		if j == 0:
			var sp := SphereMesh.new()
			sp.radius = 0.16
			sp.height = 0.32
			ref.mesh = sp
		else:
			var bx := BoxMesh.new()
			bx.size = Vector3(0.30, 0.30, 0.04)
			ref.mesh = bx
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.937, 0.945, 0.955)
		rm.metallic = 0.0 if j == 0 else 0.22
		rm.roughness = 0.44
		ref.material_override = rm
		ref.position = Vector3((float(rows.size()) * 0.5 + 0.35 + float(j) * 0.42) * pitchw, 0.0, 0.0)
		ref.rotation.y = deg_to_rad(-yaw)
		world.add_child(ref)

	var cam := Camera3D.new()
	var span := pitchw * maxf(float(rows.size()), 1.0)
	# Centred on the LINE-UP, not on the world: with one wheel and a reference ball beside it the
	# two are off to one side, and a camera at x 0 framed half a wheel and a lot of ground.
	cam.position = Vector3((float(rows.size()) - 1.0) * 0.5 * pitchw, 0.05,
			span * 0.5 / tan(deg_to_rad(35.0)) * (dist / 1.7))
	cam.rotation_degrees = Vector3(pitch, 0.0, 0.0)
	cam.fov = 60.0
	world.add_child(cam)
	cam.current = true

	for i in 6:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "wheel_shot.png"
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
