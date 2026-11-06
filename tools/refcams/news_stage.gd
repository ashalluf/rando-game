extends RefCounted
## The "news_live" reference camera's staging (tools/refcams/cameras_w8.json, `"stage": "news"`):
## a TV news crew live at a burning wreck's aftermath. NewsCrews.stage_for_shot() stages the story
## on the street ahead of the row's eye (the wreck burning in the road, the live truck pulled up
## with its uplink raised, the reporter and the camera operator on air, the tape), Emergency stages
## a fire engine at the wreck with its crew working (Emergency.open_call + stage, the way its own
## stage_for_shot does), walkers are brought onto the blocks round it and an Onlookers scene opened
## (filmers, pointers, gawkers). The free eye stands behind the camera operator, given in the
## operator's frame (x toward the road, y up from the pavement, -z toward the reporter), and looks
## at a point given in the same frame. Loaded at run time by refcams_shot.gd (after the autoloads),
## so it may name NewsCrews, Emergency, Onlookers and Pedestrian.
##
##   "news": {"station": 0..3 (NewsKit.STATIONS), "people": walkers added, "count": onlookers put
##     in place, "settle": physics frames before the shot, "eye" / "look": [x, y, z] in the
##     operator's frame}
##
## Env NEWS_EYE=x,y,z / NEWS_LOOK=x,y,z / NEWS_STATION override the row for framing work.

static var hero_at := Vector3.INF
static var hero_yaw := 0.0
static var _people: Array = []
static var _engine: Node = null
static var _nc: Node = null
static var _em: Node = null


static func _vec(spec: Dictionary, key: String, env: String, fallback: Vector3) -> Vector3:
	var s := OS.get_environment(env)
	if s != "":
		var p := s.split(",")
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	var a: Variant = spec.get(key)
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func stage(tree: SceneTree, scene: Node, cam: Camera3D, _player: Node3D, place: Callable, row: Dictionary = {}) -> void:
	var spec: Dictionary = row.get("news", {}) if row.get("news", null) is Dictionary else {}
	var plan: CityPlan = scene.get("plan")
	_nc = scene.get_node_or_null("NewsCrews")
	_em = scene.get_node_or_null("Emergency")
	if plan == null or _nc == null or cam == null:
		push_warning("refcams news: no NewsCrews")
		return
	var station := int(OS.get_environment("NEWS_STATION")) if OS.get_environment("NEWS_STATION") != "" else int(spec.get("station", 1))
	var eye0: String = await _nc.call("stage_for_shot", "crew", cam, station)
	if eye0 == "":
		push_warning("refcams news: no story staged")
		return
	var stories: Array = _nc.get("stories")
	var s: Dictionary = stories[stories.size() - 1]
	var lay: Dictionary = s.layout
	var wreck: Vehicle = null
	for p in s.props:
		if p is Vehicle:
			wreck = p
	# The fire engine at the wreck, its crew straight to work (Emergency.stage_for_shot's way).
	if _em != null and wreck != null and is_instance_valid(wreck):
		_em.set("enabled", true)
		var inc: Dictionary = _em.call("open_call", "fire", WorldState.to_world(wreck.global_position), wreck)
		_engine = _em.call("stage", EmergencyCar.Kind.ENGINE, inc)
		for k in 3:
			for c in _em.get("crews"):
				if is_instance_valid(c):
					c.call("_think")
	# Walkers onto the pavements round the scene, then the onlookers' scene opened round the wreck.
	var chunks: Dictionary = scene.get("chunks")
	var scn: Vector2 = lay.scene
	var people := int(spec.get("people", 18))
	var blocks: Array = []
	for d: Vector2 in [Vector2.ZERO, Vector2(18, 0), Vector2(-18, 0), Vector2(0, 18), Vector2(0, -18)]:
		var bi := plan.block_index_at(scn + d)
		if chunks.has(bi) and not blocks.has(bi):
			blocks.append(bi)
	for i in people:
		if blocks.is_empty():
			break
		var bi: Vector2i = blocks[i % blocks.size()]
		var chunk := chunks.get(bi) as Node3D
		var rect: Rect2 = plan.block(bi.x, bi.y).rect
		var p := Pedestrian.new()
		p.setup(rect, plan.sidewalk_width, 71000 + i * 151)
		p.pause_chance = 0.0
		p.jogger_share = Vector2.ZERO
		p.dog_share = Vector2.ZERO
		p.set_meta("no_trim", true)
		var q := p._random_ring_point(plan.sidewalk_width)
		for k in 10:
			if q.distance_to(scn) < 30.0:
				break
			q = p._random_ring_point(plan.sidewalk_width)
		p.position = Vector3(q.x, (chunk.call("ground_y", q.x, q.y) as float) + 0.1, q.y)
		chunk.add_child(p)
		_people.append(p)
	for i in 30:
		await tree.physics_frame
	var node := Onlookers.find()
	if node != null and Onlookers.enabled and wreck != null and is_instance_valid(wreck):
		var sc: Dictionary = node.stage(Onlookers.Kind.WRECK, WorldState.to_world(wreck.global_position), wreck, int(spec.get("count", 10)))
		print("REFCAM news: %d onlookers in place" % (sc.members as Array).size())
	for i in int(spec.get("settle", 120)):
		await tree.physics_frame
	# The eye in the operator's frame: -z toward the reporter, x toward the road.
	var rep: Vector2 = lay.reporter
	var camp: Vector2 = lay.camera
	var fwd2 := (rep - camp).normalized()
	var across := Vector2(1.0, 0.0) if int(lay.axis) == CityPlan.AXIS_X else Vector2(0.0, 1.0)
	var to_road := across * -float(lay.side)
	var gy := plan.height_at(camp) + CityChunk.SIDEWALK_TOP
	var fr := func(v: Vector3) -> Vector3:
		var xz := camp + to_road * v.x - fwd2 * v.z
		return Vector3(xz.x, gy + v.y, xz.y)
	var eye: Vector3 = fr.call(_vec(spec, "eye", "NEWS_EYE", Vector3(0.6, 1.9, 3.0)))
	var look: Vector3 = fr.call(_vec(spec, "look", "NEWS_LOOK", Vector3(1.5, 1.6, -12.0)))
	var d := (look - eye).normalized()
	var eye_text := "%.3f,%.3f,%.3f,%.3f,%.3f" % [eye.x, eye.y, eye.z, rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))]
	OS.set_environment("EYE", eye_text)
	OS.set_environment("EYE_AGL", "")
	for i in 4:
		await tree.process_frame
		place.call()
	# Nobody standing in the lens.
	var eye_l := WorldState.to_local(eye)
	for p in tree.get_nodes_in_group("pedestrian"):
		var n := p as Node3D
		if n != null and n.global_position.distance_to(eye_l) < 1.6 and not (n is NewsCrew):
			n.visible = false
	var van: Node3D = s.get("van")
	print("REFCAM news: station %d, scene %s, reporter %s, operator %s, van %s, engine %s, eye %s" % [station, scn, rep, camp,
			WorldState.to_world(van.global_position) if van else "none",
			WorldState.to_world((_engine as Node3D).global_position) if _engine else "none", eye_text])


static func unstage() -> void:
	# The staged units out of the traffic's lists first: clear() frees them, and a freed car left
	# in TrafficManager.cars is an error a tick in _drive_streets and Ambience._probe.
	var traffic: Node = _nc.get("traffic") if _nc != null and is_instance_valid(_nc) else null
	if traffic != null and is_instance_valid(traffic):
		var units: Array = []
		if _em != null and is_instance_valid(_em):
			units.append_array(_em.get("units"))
		units.append_array(_nc.get("vans"))
		var cars: Array = traffic.get("cars")
		for u in units:
			if is_instance_valid(u):
				cars.erase(u)
	for p in _people:
		if is_instance_valid(p):
			(p as Node).queue_free()
	_people.clear()
	if _em != null and is_instance_valid(_em):
		_em.call("clear")
		_em.set("enabled", false)
	if _nc != null and is_instance_valid(_nc):
		_nc.call("clear")
		_nc.set("enabled", false)
		if traffic != null and is_instance_valid(traffic):
			traffic.set("staged", false)
	_engine = null
