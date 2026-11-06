extends RefCounted
## The body of tools/gondolas/gondola_shot.gd (loaded after the autoloads exist).

func run(tree: SceneTree) -> void:
	var TG = load("res://scripts/world/tower_gondolas.gd")
	var LD = load("res://scripts/world/landmark_downtown.gd")
	if OS.get_environment("LIST") == "1":
		for id: String in LD.TOWERS:
			var s: Dictionary = TG.landmark_sites(id, 1337)
			print("TOWER ", id, " faces=", TG.faces(LD.tower(id).tiers, TG._hull_boxes(LD.tower(id).hulls), id).size(),
				" hung=", s.hung.size(), " parked=", s.parked.size(), " stowed=", s.stowed.size())
			var T := float(OS.get_environment("T")) if OS.get_environment("T") != "" else 0.0
			var a: Vector2 = LD.anchor(id)
			for site: Dictionary in s.hung:
				print("   site m=", site.m, " n=", site.n, " top=%.1f bottom=%.1f lanes=%s" % [site.top, site.bottom, str(site.lanes)])
				# An EYE for still_shot.gd on the cradle at clock T: 30 m out, 10 m along, a little below.
				var p: Dictionary = TG.pose_at(site, T)
				var c: Vector3 = Vector3(a.x, 0.0, a.y) + (site.m as Vector3) + (site.t as Vector3) * float(p.lane) + (site.n as Vector3) * TG.GAP
				c.y = float(p.y) + 1.0
				var eye: Vector3 = c + (site.n as Vector3) * 30.0 + (site.t as Vector3) * 10.0 + Vector3.DOWN * 4.0
				var d: Vector3 = (c - eye).normalized()
				print("   EYE=%.1f,%.1f,%.1f,%.1f,%.1f cradle=%.1f,%.1f,%.1f n=%s" % [eye.x, eye.y, eye.z, rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(asin(d.y)), c.x, c.y, c.z, str(site.n)])
		tree.quit()
		return
	var id := OS.get_environment("TOWER") if OS.get_environment("TOWER") != "" else "dt_bronze_slab"
	var night := OS.get_environment("NIGHT") == "1"
	var root := Node3D.new()
	tree.root.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	if night:
		ps.sky_top_color = Color(0.02, 0.03, 0.06)
		ps.sky_horizon_color = Color(0.1, 0.08, 0.08)
	sky.sky_material = ps
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -30, 0)
	sun.light_energy = 0.05 if night else 1.2
	sun.shadow_enabled = true
	root.add_child(sun)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	var holder := Node3D.new()
	holder.name = "City"
	root.add_child(holder)
	var statics := StaticBody3D.new()
	holder.add_child(statics)
	LD.build({"id": id, "anchor": Vector2.ZERO}, holder, statics, true)
	var rigs: Array = tree.get_nodes_in_group("tower_gondola")
	print("rigs ", rigs.size())
	if rigs.is_empty():
		tree.quit()
		return
	var k := clampi(int(OS.get_environment("SITE")), 0, rigs.size() - 1)
	for r in rigs:
		r.force = true
	await tree.physics_frame
	await tree.physics_frame
	print("T built ", Time.get_ticks_msec())
	var rig = rigs[k]
	var body: Node3D = rig._body
	var site: Dictionary = rig.site
	var n: Vector3 = site.n
	var t: Vector3 = site.t
	var hits := OS.get_environment("HIT")
	if hits != "":
		var dir := (-n + t * 0.4).normalized()
		if hits == "blast":
			body.take_hit(0, 110.0, (n + Vector3.UP * 0.3).normalized())
		else:
			for i in int(hits):
				body.take_hit(0, 10.0, dir)
		var after := float(OS.get_environment("SHOT_AFTER")) if OS.get_environment("SHOT_AFTER") != "" else 0.8
		for i in int(after * 60.0):
			rig._update(1.0 / 60.0)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	cam.far = 3000.0
	var c := body.global_position + Vector3.UP * 1.0
	var rel := Vector3(9.0, 2.5, 4.0)
	match OS.get_environment("VIEW"):
		"side":
			rel = Vector3(3.0, 1.0, 9.0)
		"below":
			rel = Vector3(14.0, -18.0, 6.0)
		"roof":
			rel = Vector3(22.0, float(site.top) - c.y + 14.0, 10.0)
		"far":
			rel = Vector3(70.0, -15.0, 30.0)
		"close":
			rel = Vector3(3.6, 0.6, 1.4)
	var cv := OS.get_environment("CAM").split(",")
	if cv.size() == 3:
		rel = Vector3(cv[0].to_float(), cv[1].to_float(), cv[2].to_float())
	cam.global_position = c + n * rel.x + Vector3.UP * rel.y + t * rel.z
	var look := c
	if OS.get_environment("VIEW") == "roof":
		look = Vector3(c.x, float(site.top), c.z) - n * 2.0
	cam.look_at(look, Vector3.UP)
	cam.current = true
	print("T cam ", Time.get_ticks_msec())
	for i in 12:
		await tree.process_frame
		print("T frame ", i, " ", Time.get_ticks_msec())
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "gondola.png"
	tree.root.get_texture().get_image().save_png(out)
	print("saved ", out, " cradle ", body.global_position, " tris=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	tree.quit()
