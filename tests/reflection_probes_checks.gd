extends RefCounted
## Reflection probes (ReflectionProbes, scripts/world/reflection_probes.gd) for tests/smoke_test.gd.
## Loaded at run time, so it may name the class. Under the dummy renderer the city builds none
## (Forward+ only), so the manager is made here with `force` and driven by hand: the street boxes
## the plan gives (pure, nearest first, over open roads, the eye over the street), the open box off
## the grid, one render a slot, re-renders when the light moves or the origin re-centres, the
## shaders' hand-over global, and the street HDRI under the sky (Forward+ only in the shader).

var _t: Node


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	_check(city.get_node_or_null("ReflectionProbes") == null and not ReflectionProbes.supported(),
		"reflection probes: none on the dummy renderer (Forward+ only)")
	_check(ProjectSettings.has_setting("shader_globals/probe_reach"), "reflection probes: the probe_reach shader global exists")

	# Boxes round a point on a downtown street (road 0 of each axis crosses at the origin).
	var at := Vector2(plan.road_pos(CityPlan.AXIS_X, 0) + 1.0, (plan.road_pos(CityPlan.AXIS_Z, 0) + plan.road_pos(CityPlan.AXIS_Z, 1)) * 0.5)
	var boxes := ReflectionProbes.candidates(plan, at, 9)
	var again := ReflectionProbes.candidates(plan, at, 9)
	var keys := boxes.map(func(b: Dictionary) -> String: return b.key)
	_check(boxes.size() == 9 and keys == again.map(func(b: Dictionary) -> String: return b.key),
		"reflection probes: nine boxes round a street, the same twice (%d)" % boxes.size())
	var sorted := true
	for i in range(1, boxes.size()):
		sorted = sorted and float(boxes[i].dist) >= float(boxes[i - 1].dist)
	_check(sorted, "reflection probes: boxes nearest first")
	var first: Dictionary = boxes[0] if not boxes.is_empty() else {}
	var inside := false
	if not first.is_empty():
		var c: Vector3 = first.center
		var sz: Vector3 = first.size
		inside = absf(at.x - c.x) <= sz.x * 0.5 and absf(at.y - c.z) <= sz.z * 0.5
	_check(inside, "reflection probes: the nearest box holds the street the camera is on")
	var eyes_ok := true
	var open_ok := true
	for b: Dictionary in boxes:
		var c: Vector3 = b.center
		var o: Vector3 = b.origin
		var sz: Vector3 = b.size
		var ground := maxf(plan.height_at(Vector2(c.x, c.z)), 0.0)
		eyes_ok = eyes_ok and absf(c.y + o.y - ground - 4.2) < 0.05 and absf(o.y) < sz.y * 0.5
		var key: String = b.key
		if key.begins_with("road:"):
			var parts := key.split(":")
			var axis := int(parts[1])
			var along := c.z if axis == CityPlan.AXIS_X else c.x
			open_ok = open_ok and plan.road_open(axis, int(parts[2]), along)
	_check(eyes_ok, "reflection probes: each eye 4.2 m over the street, inside its box")
	_check(open_ok, "reflection probes: street boxes only on open roads")
	# Off the grid: the ocean's open box.
	var sea := Vector2(-6000.0, 0.0)
	if plan.zone_at(sea) != MacroMap.Zone.CITY:
		var sb := ReflectionProbes.candidates(plan, sea, 3)
		_check(not sb.is_empty() and String(sb[0].key).begins_with("open:"), "reflection probes: an open box off the street grid")

	# The manager, by hand: one render a slot, nearest first; stale light and a re-centre re-render.
	ReflectionProbes.force = true
	var budget_was := ReflectionProbes.budget
	ReflectionProbes.budget = 3
	var rp := ReflectionProbes.new()
	rp.plan = plan
	city.add_child(rp)
	rp.set_process(false)
	rp._wanted = ReflectionProbes.candidates(plan, at, 3, rp)
	rp._assign()
	_check(rp._slots.size() == 3 and rp.get_child_count() == 0 and rp.shown_count() == 0, "reflection probes: three slots, no probe before its turn")
	rp._render_next(at)
	var one: ReflectionProbe = null
	for s: Dictionary in rp._slots:
		if s.shown:
			one = s.probe
	_check(rp.shown_count() == 1 and rp.get_child_count() == 1 and one != null and one.visible and one.box_projection
		and one.update_mode == ReflectionProbe.UPDATE_ONCE and one.ambient_mode == ReflectionProbe.AMBIENT_DISABLED,
		"reflection probes: one rendered per slot, box-projected, once, no ambient")
	_check(one != null and (one.cull_mask & ReflectionProbes.VEHICLE_LAYER) == 0, "reflection probes: vehicles' layer left out of the probe's render")
	var car := Node3D.new()
	var body := MeshInstance3D.new()
	car.add_child(body)
	ReflectionProbes.set_vehicle_layer(car)
	_check(body.layers == ReflectionProbes.VEHICLE_LAYER and car.has_meta("probe_layer"), "reflection probes: a vehicle's meshes moved onto the vehicle layer")
	car.free()
	var nearest_key: String = rp._wanted[0].key
	var shown_key := ""
	for s: Dictionary in rp._slots:
		if s.shown:
			shown_key = s.key
	_check(shown_key == nearest_key, "reflection probes: the nearest box rendered first")
	rp._render_next(at)
	rp._render_next(at)
	_check(rp.shown_count() == 3 and rp.renders == 3 and not rp._render_next(at), "reflection probes: all three rendered, then nothing due")
	rp._publish_reach(at)
	_check(float(RenderingServer.global_shader_parameter_get("probe_reach")) > 10.0, "reflection probes: probe_reach published while they stand")
	# The light moves an hour: the next slot re-renders one where it stands.
	for s: Dictionary in rp._slots:
		s.light = [float(s.light[0]) + 1.0, s.light[1], s.light[2]]
	var before := (rp._slots[0].probe as Node3D).position
	_check(rp._render_next(at) and rp.renders == 4, "reflection probes: a stale probe re-renders")
	var moved := false
	for s: Dictionary in rp._slots:
		moved = moved or (s.probe as Node3D).position.distance_to(WorldState.to_local(s.box.center)) < 0.01
	_check(moved and before.is_finite(), "reflection probes: re-rendered in place (a millimetre's nudge)")
	# A re-centre moves them all: none counts toward the reach until re-placed, one a slot.
	var off_was: Vector3 = WorldState.world_offset
	WorldState.world_offset = off_was + Vector3(1000.0, 0.0, 0.0)
	rp._publish_reach(at)
	_check(float(RenderingServer.global_shader_parameter_get("probe_reach")) == 0.0, "reflection probes: a re-centre takes them out of the reach")
	rp._render_next(at)
	var placed := 0
	for s: Dictionary in rp._slots:
		if s.offset == WorldState.world_offset:
			placed += 1
	_check(placed == 1, "reflection probes: re-placed one a slot after a re-centre")
	WorldState.world_offset = off_was
	# The budget shrinks (Quality LOW): the pool shrinks with it.
	ReflectionProbes.budget = 0
	rp._wanted = []
	rp._assign()
	await _t.get_tree().process_frame
	_check(rp._slots.is_empty(), "reflection probes: none at a zero budget")
	rp.queue_free()
	await _t.get_tree().process_frame
	_check(float(RenderingServer.global_shader_parameter_get("probe_reach")) == 0.0, "reflection probes: probe_reach back to 0 when they go")
	ReflectionProbes.force = false
	ReflectionProbes.budget = budget_was

	# The street HDRI: the texture loads, the sky reads it only off the Compatibility renderer,
	# and street_sky() hands it to a sky material.
	var tex := load(ReflectionProbes.STREET_HDRI) as Texture2D
	_check(tex != null and tex.get_width() == 1024 and tex.get_height() == 512, "reflection probes: the street HDRI loads (1024 x 512)")
	var src := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	var at_hdri := src.find("if (street_hdri_amount > 0.0)")
	var guard := src.rfind("#if CURRENT_RENDERER != RENDERER_COMPATIBILITY", at_hdri)
	_check(at_hdri > 0 and guard > 0 and src.find("#endif", guard) > at_hdri, "reflection probes: the sky's street HDRI is Forward+ only")
	var env := Environment.new()
	env.sky = Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sky.gdshader")
	env.sky.sky_material = mat
	ReflectionProbes.street_sky(env)
	_check(mat.get_shader_parameter("street_hdri") == tex and float(mat.get_shader_parameter("street_hdri_amount")) == 1.0,
		"reflection probes: street_sky() hands the HDRI to the sky")
	_check(FileAccess.get_file_as_string("res://shaders/car_paint.gdshaderinc").contains("global uniform float probe_reach"),
		"reflection probes: car paint reads probe_reach")
