extends Node3D
## Particle effects side by side on a plain ground under the city's own Environment, small enough
## to load in a browser in a minute (web-build-5: the fire, smoke and hose blew out into huge
## green / white glare on the web only). Export it as the main scene
## (MAIN=res://tools/web_probe/fx_room.tscn tools/web_probe/export_probe.sh with AUTOPROBE=0)
## or run it natively:
##   OUT=/tmp/fx.png xvfb-run -a godot --rendering-driver opengl3 --path . res://tools/web_probe/fx_room.tscn
## Left to right: FireSmoke (CarDamage's: HDR ramp x a dark colour), a fire puff (the plain puff on
## the web), HoseSpray (the smoke material, white ramp), HoseWater (hose_water.gdshader), a
## FountainPlume-like spray (lit). Prints FX <name> r g b: the mean over each column. Knobs:
## frames (40), fixed (1: fixed 30 fps particles), quit (1).
## web-bonfire added: per-fire tokens copy[.prop...] (the row fire's properties, less the listed
## ones), sharemesh / onemesh / dupmesh / plainq / co0 / latemesh / late0 / late1 / remesh3 (which
## mesh object the flames draw), nodepth / dupmat / tq / tqmat (the material), up / up3, life0,
## amt20, notongue / noflame / noember / nosmoke; params rowoff=1 (hide the effect row), norow=1,
## fires=1 (a car engine fire and a burning tree crown beside the fires), shots=a.b.c (also save
## those frames), diff=1 (print the row fire's properties that differ from the flames'). With
## tools/web_probe/glprobe.js (GLPROBE=1 on webshot.js) and ANGLE=gl|swiftshader on webshot.js.

var _q := {}
var _cols: Array = []
var _one_mesh: QuadMesh = null


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
	# webmat=1: natively, build every effect material the way the web build does.
	if _arg("webmat", "0") == "1":
		WeaponFX._web_cache = 1
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var we := city.get_node("WorldEnvironment").duplicate() as WorldEnvironment
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.6
	add_child(sun)
	city.free()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.3, 0.3)
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2.5, 14)
	cam.look_at(Vector3(0, 2.0, 0))
	cam.current = true
	var fixed := int(_arg("fixed", "0"))
	# FireSmoke as CarDamage builds it.
	_emit("smoke", -6.0, WeaponFX.smoke_material(), Color(0.035, 0.032, 0.03),
		WeaponFX._ramp([Color(8.0, 3.4, 1.1, 0.6), Color(1.6, 1.15, 1.0, 0.97), Color(1, 1, 1, 0.92),
			Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.26), Color(1, 1, 1, 0.0)]), 5.5, 32, Vector3(0, 1.5, 0), fixed)
	if _arg("norow", "0") != "1": _emit("fire", -3.0, CarDamage.fire_material(), Color(1, 1, 1),
		WeaponFX._ramp([Color(1.25, 0.64, 0.07, 0.0), Color(1.3, 0.66, 0.07, 0.95), Color(1.05, 0.48, 0.05, 0.9),
			Color(0.65, 0.25, 0.03, 0.6), Color(0.3, 0.09, 0.015, 0.22), Color(0.06, 0.04, 0.025, 0.0)]), 0.85, 20, Vector3(0, 2.0, 0), fixed)
	_emit("spray", 0.0, WeaponFX.smoke_material(), Color(0.85, 0.87, 0.9),
		WeaponFX._ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)]), 1.6, 12, Vector3(0, 0.4, 0), fixed)
	var hw := _emit("hose", 3.0, EmergencyCrew.water_material(), Color(1, 1, 1),
		WeaponFX._ramp([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)]), 0.85, 60, Vector3(0, -9.8, 0), fixed)
	hw.particle_flag_align_y = true
	hw.direction = Vector3(0, 0.3, -1)
	hw.initial_velocity_min = 8.0
	hw.initial_velocity_max = 9.0
	var plain := StandardMaterial3D.new()
	plain.albedo_texture = WeaponFX.puff_texture()
	plain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plain.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	plain.billboard_keep_scale = true
	plain.vertex_color_use_as_albedo = true
	_emit("lit", 6.0, plain, Color(1, 1, 1), WeaponFX._ramp([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)]), 3.6, 60, Vector3(0, 0.5, 0), fixed)
	# fountain=1: MacArthur Park's real fountain (jet, plume, boil) 40 m behind the row;
	# plume=unshaded draws the plume's particles unshaded (the web-build-5 A/B).
	if _arg("fountain", "0") == "1":
		var holder := Node3D.new()
		add_child(holder)
		LandmarkMacArthurPark._build_fountain(holder, {"fountain": Vector2(0.0, -40.0)}, true)
		var pl := holder.get_node_or_null("FountainPlume") as CPUParticles3D
		if pl and _arg("plume", "") == "unshaded":
			var plm := (pl.mesh as QuadMesh).material as StandardMaterial3D
			plm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cam.position = Vector3(0, 2.5, 30)
		cam.look_at(Vector3(0, 8.0, -40))
	# bonfire=1: a lit beach fire ring (BonfireFire, built straight away, no plan or clock) 8 m
	# behind the row's middle; night=1 turns the sun off and lamp_factor on (web-review-5).
	# bonfire=1: a lit beach fire ring (BonfireFire, built straight away, no plan or clock) 8 m
	# ahead; bonfire=variants: five in a row, each flame system changed one way (none, nocurve,
	# noinit, ldr, add) to bisect what the browser does not draw.
	var bf := _arg("bonfire", "0")
	if bf != "0":
		var variants: Array = ["none"] if bf == "1" else (["none", "nocurve", "noinit", "ldr", "add"] if bf == "variants" else Array(bf.split(",")))
		for i in variants.size():
			var f := BonfireFire.new()
			f.position = Vector3((float(i) - (variants.size() - 1) * 0.5) * 3.0, 0.0, -8.0)
			add_child(f)
			f._build()
			f.lit = true
			for p: CPUParticles3D in [f._flames, f._licks, f._embers, f._smoke]:
				p.emitting = true
				p.visible = true
			for p: CPUParticles3D in [f._flames, f._licks]:
				for tok: String in String(variants[i]).split("+"):
					match tok:
						"nocurve":
							p.scale_amount_curve = null
						"noinit":
							p.color_initial_ramp = null
						"ldr":
							p.color_ramp = WeaponFX._ramp([Color(1.0, 0.6, 0.07, 0.0), Color(1.0, 0.62, 0.08, 0.95),
								Color(1.0, 0.5, 0.06, 0.7), Color(0.9, 0.38, 0.05, 0.28), Color(0.7, 0.24, 0.03, 0.05), Color(0.5, 0.15, 0.02, 0.0)])
						"add":
							(p.mesh as QuadMesh).material = WeaponFX._puff_material(true)
						"point":
							p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
						"pre3":
							p.preprocess = 3.0
						"noangle":
							p.angle_min = 0.0
							p.angle_max = 0.0
						"big":
							p.scale_amount_min = 2.0
							p.scale_amount_max = 2.5
						"life3":
							p.lifetime = 3.0
						"nodamp":
							p.damping_min = 0.0
							p.damping_max = 0.0
						"rowlike":
							p.preprocess = 3.0
							p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
							p.damping_min = 0.0
							p.damping_max = 0.0
							p.scale_amount_curve = null
							p.color_initial_ramp = null
							p.angle_min = 0.0
							p.angle_max = 0.0
							p.lifetime = 0.85
						"sq":
							p.scale_amount_curve = null
							p.scale_amount_min = 1.0
							p.scale_amount_max = 1.0
						"rowmesh":
							var rq := QuadMesh.new()
							rq.size = Vector2.ONE
							rq.material = CarDamage.fire_material()
							p.mesh = rq
						"shadowon":
							p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
						"local":
							p.local_coords = true
						"rowramp":
							p.color_ramp = WeaponFX._ramp([Color(1.25, 0.64, 0.07, 0.0), Color(1.3, 0.66, 0.07, 0.95), Color(1.05, 0.48, 0.05, 0.9),
								Color(0.65, 0.25, 0.03, 0.6), Color(0.3, 0.09, 0.015, 0.22), Color(0.06, 0.04, 0.025, 0.0)])
						"nograv":
							p.gravity = Vector3(0, 2.0, 0)
							p.initial_velocity_min = 0.8
							p.initial_velocity_max = 1.6
							p.spread = 25.0
						"noaabb":
							p.custom_aabb = AABB()
						"amt20":
							p.amount = 20
						"restart":
							p.restart()
						"onemesh":
							if _one_mesh == null:
								_one_mesh = QuadMesh.new()
								_one_mesh.material = CarDamage.fire_material()
							p.mesh = _one_mesh
						"latemesh":
							var lp := p
							get_tree().create_timer(0.0).timeout.connect(func() -> void:
								for _k in 3:
									await get_tree().process_frame
								var lq := QuadMesh.new()
								lq.material = CarDamage.fire_material()
								lp.mesh = lq)
						"late0", "late1", "remesh3", "reown3":
							var lp2 := p
							var tk: String = tok
							var own: Mesh = p.mesh
							if tk == "late0":
								(func() -> void:
									var q0 := QuadMesh.new()
									q0.material = CarDamage.fire_material()
									lp2.mesh = q0).call_deferred()
							else:
								get_tree().create_timer(0.0).timeout.connect(func() -> void:
									for _k in (1 if tk == "late1" else 3):
										await get_tree().process_frame
									if tk == "late1":
										var q1 := QuadMesh.new()
										q1.material = CarDamage.fire_material()
										lp2.mesh = q1
									elif tk == "remesh3":
										# The same mesh object, unset and set again.
										lp2.mesh = null
										lp2.mesh = own
									else:
										# The same mesh object onto a brand-new system's multimesh.
										lp2.amount = lp2.amount + 1)
						"sharemesh":
							p.mesh = get_node("fire").mesh
						"co0":
							var cq := QuadMesh.new()
							cq.size = Vector2.ONE
							cq.center_offset = Vector3.ZERO
							cq.material = CarDamage.fire_material()
							p.mesh = cq
						"plainq":
							var pq := QuadMesh.new()
							pq.material = CarDamage.fire_material()
							p.mesh = pq
						"dupmesh":
							p.mesh = (get_node("fire").mesh as QuadMesh).duplicate()
						"nodepth":
							var nm := (CarDamage.fire_material() as StandardMaterial3D).duplicate() as StandardMaterial3D
							nm.no_depth_test = true
							(p.mesh as QuadMesh).material = nm
						"dupmat":
							(p.mesh as QuadMesh).material = (CarDamage.fire_material() as StandardMaterial3D).duplicate()
						"tq":
							Blast4.tongue_quad(p.mesh as QuadMesh)
						"tqmat":
							(p.mesh as QuadMesh).material = Blast4.flame_material()
						"up":
							p.position.y += 1.0
						"up3":
							p.position.y += 3.0
						"life0":
							p.lifetime_randomness = 0.0
						_:
							# copy[.prop.prop...]: every stored property of the room's "fire" column onto
							# this system but the listed ones (web-bonfire's bisect).
							if tok.begins_with("copy") and has_node("fire"):
								var keep: PackedStringArray = tok.split(".").slice(1)
								var src := get_node("fire")
								for pr: Dictionary in src.get_property_list():
									var pn: String = pr["name"]
									if (int(pr["usage"]) & PROPERTY_USAGE_STORAGE) == 0 or pn in keep:
										continue
									if pn in ["name", "transform", "position", "rotation", "scale", "quaternion", "basis", "global_transform", "global_position", "script", "unique_name_in_owner"]:
										continue
									p.set(pn, src.get(pn))
			f._pool.visible = true
			if f._glow:
				f._glow.visible = true
			if "reparent" in String(variants[i]):
				for p: CPUParticles3D in [f._flames, f._licks]:
					p.reparent(self, true)
			if "notongue" in String(variants[i]):
				f._licks.visible = false
				f._licks.emitting = false
			if "noflame" in String(variants[i]):
				f._flames.visible = false
				f._flames.emitting = false
			if "noember" in String(variants[i]):
				f._embers.visible = false
			if "nosmoke" in String(variants[i]):
				f._smoke.visible = false
				f._smoke.emitting = false
			if _arg("diff", "0") == "1" and i == 0 and has_node("fire"):
				var src2 := get_node("fire")
				for pr: Dictionary in src2.get_property_list():
					var pn2: String = pr["name"]
					if (int(pr["usage"]) & PROPERTY_USAGE_STORAGE) != 0 and str(src2.get(pn2)) != str(f._flames.get(pn2)):
						print("DIFF %s row=%s flames=%s" % [pn2, src2.get(pn2), f._flames.get(pn2)])
			if "nostack" in String(variants[i]):
				f._stack.visible = false
			if "nopool" in String(variants[i]):
				f._pool.visible = false
			if "noglow" in String(variants[i]) and f._glow:
				f._glow.visible = false
			if "bare" in String(variants[i]):
				f._stack.visible = false
				f._pool.visible = false
				if f._glow:
					f._glow.free()
					f._glow = null
		cam.position = Vector3(0, 1.6, -1.0) if variants.size() == 1 else Vector3(0, 2.0, 2.0)
		cam.look_at(Vector3(0, 0.9, -8.0))
		_cols.append(["bonfire", 0.0])
	# fires=1 (web-bonfire): the other CPUParticles fires beside the bonfires - a car's engine fire
	# as CarDamage._start_fire() builds it (x -6) and a burning tree crown (TreeFire.Burn, x 6).
	if _arg("fires", "0") == "1":
		var cd := CarDamage.new()
		cd.position = Vector3(-6.0, 0.6, -8.0)
		add_child(cd)
		var ef: CPUParticles3D = cd._flame_system("EngineFire", 40, Vector2.ONE, 180.0)
		ef.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		ef.emission_box_extents = Vector3(0.6, 0.1, 0.5)
		ef.spread = 22.0
		ef.lifetime = 0.85
		ef.lifetime_randomness = 0.4
		ef.initial_velocity_min = 1.0
		ef.initial_velocity_max = 2.0
		ef.gravity = Vector3(0.0, 2.5, 0.0)
		ef.scale_amount_min = 0.7
		ef.scale_amount_max = 1.1
		ef.preprocess = 1.5
		var tb := TreeFire.Burn.new()
		tb.tree = {"id": 1, "crown": WorldState.to_world(Vector3(6.0, 4.0, -9.0)), "r": 2.5, "palm": false}
		tb.rec = {"key": "fxroom", "chunk": weakref(null), "trees": [], "nodes": {}, "charred": {}}
		tb.id = "fxroom_tree"
		tb.staged = 0.3
		add_child(tb)
	# rowoff=1: hide the whole effect row (its smoke and spray stand between the camera and the
	# fires: web-bonfire's depth A/B).
	if _arg("rowoff", "0") == "1":
		for rn in ["smoke", "fire", "spray", "hose", "lit"]:
			var rnode := get_node_or_null(rn) as CPUParticles3D
			if rnode:
				rnode.visible = false
				rnode.emitting = false
	if _arg("night", "0") == "1":
		sun.visible = false
		RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
		RenderingServer.global_shader_parameter_set("night_factor", 1.0)
		we.environment.background_energy_multiplier = 0.05
	_shoot.call_deferred()


func _emit(n: String, x: float, mat: Material, col: Color, ramp: Gradient, life: float, amount: int, grav: Vector3, fixed: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = n
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = grav
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.4
	p.color = col
	p.color_ramp = ramp
	p.preprocess = 3.0
	if fixed > 0:
		p.fixed_fps = 30
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	p.mesh = q
	p.position = Vector3(x, 0.5, float(_arg("rowz", "0")))
	add_child(p)
	_cols.append([n, x])
	return p


func _process(_delta: float) -> void:
	# slow=<ms>: every frame takes that long, as a city frame does in a browser under SwiftShader.
	var slow := int(_arg("slow", "0"))
	if slow > 0:
		OS.delay_msec(slow)


func _shoot() -> void:
	# shots=a.b.c: also save the frame after a, b, c frames (web-bonfire: when does it go wrong).
	var done := 0
	for sf in _arg("shots", "").split(".", false):
		while done < int(sf):
			await get_tree().process_frame
			done += 1
		var simg := get_viewport().get_texture().get_image()
		if OS.has_feature("web"):
			print("PROBE_IMG f%s %s" % [sf, Marshalls.raw_to_base64(simg.save_png_to_buffer())])
		else:
			simg.save_png(_arg("out", "/tmp/fx_room.png").replace(".png", "_f%s.png" % sf))
	for i in maxi(0, int(_arg("frames", "40")) - done):
		await get_tree().process_frame
	# dump=1: each particle system's live instances (count, mean scale, mean colour, mean custom).
	if _arg("dump", "0") == "1":
		_dump(self)
	var img := get_viewport().get_texture().get_image()
	var cam := get_viewport().get_camera_3d()
	for c in _cols:
		var a := cam.unproject_position(Vector3(c[1] - 1.2, 4.5, 0))
		var b := cam.unproject_position(Vector3(c[1] + 1.2, 0.3, 0))
		var s := Vector3.ZERO
		var k := 0
		var w := img.get_width()
		var h := img.get_height()
		for y in range(clampi(int(a.y), 0, h), clampi(int(b.y), 0, h), 2):
			for x in range(clampi(int(a.x), 0, w), clampi(int(b.x), 0, w), 2):
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					var cc := img.get_pixel(x, y)
					s += Vector3(cc.r, cc.g, cc.b)
					k += 1
		s = s / maxf(1.0, k) * 255.0
		print("FX %s %d %d %d" % [c[0], s.x, s.y, s.z])
	if OS.has_feature("web"):
		var half := img.duplicate() as Image
		print("PROBE_IMG fx %s" % Marshalls.raw_to_base64(half.save_png_to_buffer()))
	else:
		img.save_png(_arg("out", "/tmp/fx_room.png"))
	print("FX_DONE")
	if _arg("quit", "1") == "1" and not OS.has_feature("web"):
		get_tree().quit()


func _dump(n: Node) -> void:
	for c in n.get_children():
		if c is CPUParticles3D:
			var cp := c as CPUParticles3D
			var buf := RenderingServer.multimesh_get_buffer(cp.get_base())
			var cnt := RenderingServer.multimesh_get_instance_count(cp.get_base())
			var stride := buf.size() / maxi(1, cnt)
			var sc := 0.0
			var col := Vector4.ZERO
			var cus := Vector4.ZERO
			var live := 0
			var org := Vector3.ZERO
			for i in cnt:
				var o := i * stride
				var s := Vector3(buf[o], buf[o + 4], buf[o + 8]).length()
				if s > 0.0001:
					live += 1
					sc += s
					org += Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
					if stride >= 16:
						col += Vector4(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15])
					if stride >= 20:
						cus += Vector4(buf[o + 16], buf[o + 17], buf[o + 18], buf[o + 19])
			var k := maxf(1.0, float(live))
			print("DUMP %s/%s n=%d stride=%d live=%d scale=%.3f col=%s custom=%s pos=%s org=%s inst_xf=%s" % [n.name, cp.name, cnt, stride, live, sc / k, col / k, cus / k, cp.global_position, org / k, cp.global_transform.origin])
		_dump(c)
