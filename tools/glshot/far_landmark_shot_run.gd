extends RefCounted
## The work of far_landmark_shot.gd (compiled only once the autoloads are in; see there).

const SKIP := ["airfield_lights", "macarthur_park", "marisol_canals"]


var tree: SceneTree


func run(t: SceneTree) -> void:
	tree = t
	var night := OS.get_environment("NIGHT") == "1"
	var nf := 1.0 if night else 0.0
	RenderingServer.global_shader_parameter_set("night_factor", nf)
	RenderingServer.global_shader_parameter_set("lamp_factor", nf)
	var sun_dir := Vector3(-0.45, 0.70, 0.55).normalized()
	RenderingServer.global_shader_parameter_set("sun_direction", sun_dir)
	var sky := Color(0.03, 0.035, 0.06) if night else Color(0.52, 0.66, 0.86)
	RenderingServer.global_shader_parameter_set("sky_tint", sky)
	var root3d := Node3D.new()
	tree.get_root().add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.10, 0.11, 0.16) if night else Color(0.55, 0.62, 0.72)
	e.ambient_light_energy = 0.4 if night else 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
	sun.light_energy = 0.08 if night else 1.3
	sun.shadow_enabled = true
	root3d.add_child(sun)

	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	city.free()

	var ids: Array = []
	if OS.get_environment("IDS") != "":
		ids.assign(OS.get_environment("IDS").split(",", false))
	else:
		for lm in Landmarks.all():
			if not SKIP.has(lm.id):
				ids.append(lm.id)
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "far_landmark"
	var dist0 := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 260.0
	var yaw := deg_to_rad(float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 35.0)
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 6
	var cam := Camera3D.new()
	cam.far = 9000.0
	root3d.add_child(cam)
	cam.make_current()
	for id: String in ids:
		var lm: Dictionary = {}
		for l in Landmarks.all():
			if l.id == id:
				lm = l
		if lm.is_empty():
			print("FAR_LANDMARK %s: no such landmark" % id)
			continue
		var near := Node3D.new()
		near.name = "Near_" + id
		root3d.add_child(near)
		var statics := StaticBody3D.new()
		near.add_child(statics)
		var t0 := Time.get_ticks_msec()
		Landmarks.build(lm, near, statics, plan, true)
		var t1 := Time.get_ticks_msec()
		var far := Node3D.new()
		far.name = "Far_" + id
		root3d.add_child(far)
		Landmarks.build(lm, far, null, plan, false)
		MultiMeshBatch.merge_meshes(far)
		var t2 := Time.get_ticks_msec()
		var box := _bounds(near, lm.anchor, plan)
		var c := box.get_center()
		var r := maxf(box.size.length() * 0.5, 8.0)
		var dist := maxf(dist0, r * 1.25)
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		var ground := plan.height_at(Vector2(c.x, c.z))
		var eye := c + dir * dist
		eye.y = maxf(ground + 2.0 + dist * 0.08, c.y - box.size.y * 0.15)
		cam.fov = clampf(rad_to_deg(2.0 * atan(r * 1.1 / dist)), 6.0, 70.0)
		cam.look_at_from_position(eye, c, Vector3.UP)
		var stem := "%s_%s" % [out, id]
		near.visible = false
		far.visible = false
		await _frames(frames)
		tree.get_root().get_texture().get_image().save_png(stem + "_empty.png")
		near.visible = true
		await _frames(frames)
		tree.get_root().get_texture().get_image().save_png(stem + "_near.png")
		var near_draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var near_tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		near.visible = false
		far.visible = true
		await _frames(frames)
		tree.get_root().get_texture().get_image().save_png(stem + "_far.png")
		var far_draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var far_tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		print("FAR_LANDMARK %s dist %.0f fov %.1f size %s  near %d ms %d draws %d tris  far %d ms %d draws %d tris  EYE=%.1f,%.1f,%.1f" % [
			id, dist, cam.fov, box.size, t1 - t0, near_draws, near_tris, t2 - t1, far_draws, far_tris, eye.x, eye.y, eye.z])
		near.queue_free()
		far.queue_free()
		await _frames(2)
	print("FAR_LANDMARK done (%s)" % RenderingServer.get_current_rendering_method())
	tree.quit()


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


## The detailed copy's world bounds (its geometry, not its collision), clipped to a sane box round
## the anchor so one stray far-flung node cannot frame a landmark as a speck.
func _bounds(node: Node3D, anchor: Vector2, plan: CityPlan) -> AABB:
	var box := AABB()
	var first := true
	for n in node.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var b: AABB = vi.global_transform * vi.get_aabb()
		if b.size.length() > 3000.0 or not b.size.is_finite():
			continue
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	if first:
		var h := plan.height_at(anchor)
		return AABB(Vector3(anchor.x - 20.0, h, anchor.y - 20.0), Vector3(40.0, 40.0, 40.0))
	return box
