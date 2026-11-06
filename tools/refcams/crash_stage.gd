extends RefCounted
## The "crash_closeup" reference camera's staging (tools/refcams/cameras_w8.json, `"stage":
## "crash"`): an everyday sedan that left the lane, jumped the kerb and wrapped its nose round a
## street lamp, a few minutes after. The lamp nearest the row's point on that kerb is BENT over
## by the hit (PropBreak's lean, through CityChunk.damage_prop()), the car is placed with its
## crushed nose against the pole and given the crash through the one entry point
## (Vehicle.take_hit(HIT_CRASH) at the pole: CrashDeform's crumple, CrashBreakup's glass and
## bonnet, the airbags fired and gone limp), walkers are brought onto the block and the
## Onlookers scene opened round the wreck (filmers, pointers, gawkers). The free eye stands on
## the pavement at arm's length, given in the car's own frame (x right, y up from the road, -z
## ahead of the nose). Loaded at run time by refcams_shot.gd (after the autoloads), so it may
## name CarDamage, Onlookers, PropBreak and Pedestrian.
##
##   "crash": {"axis": "x" | "z" (the road's constant axis, as park_car), "at": the road's
##     coordinate, "along": TRUE world coordinate down the road near which the lamp is taken,
##     "side": +1 / -1 (which kerb), "type": a Vehicle.BodyType name, "seed": look search start,
##     "kmh": the impact speed, "offset": metres right of the car's centre line the pole meets
##     the nose, "angle": degrees the car is turned in toward the kerb, "people": walkers added,
##     "count": onlookers put in place, "eye" / "look": [x, y, z] in the car's frame}
##
## Env CRASH_EYE=x,y,z / CRASH_LOOK=x,y,z / CRASH_KMH / CRASH_ANGLE / CRASH_OFFSET override the
## row for framing work.

static var hero_at := Vector3.INF
static var hero_yaw := 0.0
static var _car: Vehicle = null
static var _people: Array = []


static func _vec(spec: Dictionary, key: String, env: String, fallback: Vector3) -> Vector3:
	var s := OS.get_environment(env)
	if s != "":
		var p := s.split(",")
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	var a: Variant = spec.get(key)
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func _num(spec: Dictionary, key: String, env: String, fallback: float) -> float:
	var s := OS.get_environment(env)
	if s != "":
		return float(s)
	return float(spec.get(key, fallback))


static func stage(tree: SceneTree, scene: Node, _cam: Camera3D, _player: Node3D, place: Callable, row: Dictionary = {}) -> void:
	var spec: Dictionary = row.get("crash", {}) if row.get("crash", null) is Dictionary else {}
	var plan: CityPlan = scene.get("plan")
	if plan == null:
		return
	# The road and its kerb (park_stage.gd's rule).
	var axis := 0 if String(spec.get("axis", "x")) == "x" else 1
	var at := float(spec.get("at", 0.0))
	var start := plan.block_index_at(Vector2(at, 0.0) if axis == 0 else Vector2(0.0, at))
	var i0 := start.x if axis == 0 else start.y
	var best := i0
	for i in range(i0 - 1, i0 + 3):
		if absf(plan.road_pos(axis, i) - at) < absf(plan.road_pos(axis, best) - at):
			best = i
	var side := 1.0 if float(spec.get("side", 1.0)) >= 0.0 else -1.0
	var road_c := plan.road_pos(axis, best)
	var half := plan.road_width(axis, best) * 0.5
	var kerb := road_c + side * half
	var along := float(spec.get("along", 0.0))
	# The street lamp nearest the point on that kerb.
	var chunks: Dictionary = scene.get("chunks")
	var lamp_rec: Dictionary = {}
	var lamp_ch: CityChunk = null
	var lamp_w := Vector3.ZERO
	var best_d := INF
	for k in chunks:
		var ch := chunks[k] as CityChunk
		if ch == null or ch.level != CityChunk.Level.FULL:
			continue
		for r: Dictionary in ch.prop_records:
			if String(r.kind) != "lamp" or r.dead:
				continue
			var w := WorldState.to_world(ch.to_global(r.position))
			var across := (w.x if axis == 0 else w.z) - kerb
			if across * side < 0.0 or across * side > 2.0:
				continue
			var d := absf((w.z if axis == 0 else w.x) - along)
			if d < best_d:
				best_d = d
				lamp_rec = r
				lamp_ch = ch
				lamp_w = w
	if lamp_ch == null:
		push_warning("refcams crash: no lamp on that kerb")
		return
	# The car's heading: down the kerb side's traffic, turned in toward the kerb by `angle`.
	var lane_dir := Vector3(0.0, 0.0, -side) if axis == 0 else Vector3(side, 0.0, 0.0)
	var out := Vector3(side, 0.0, 0.0) if axis == 0 else Vector3(0.0, 0.0, side)
	var ang := deg_to_rad(_num(spec, "angle", "CRASH_ANGLE", 24.0))
	var heading := (lane_dir * cos(ang) + out * sin(ang)).normalized()
	var yaw := atan2(-heading.x, -heading.z)
	# The car (random_car() walked to the body type, no livery).
	var want := String(spec.get("type", "SEDAN"))
	var types: Dictionary = Vehicle.BodyType
	var want_type := int(types.get(want, 0))
	var s := int(spec.get("seed", 1))
	for k in 400:
		var rng := RandomNumberGenerator.new()
		rng.seed = s + k
		var c := Vehicle.random_car(rng)
		if c.body_type == want_type and c.livery == 0:
			_car = c
			print("REFCAM crash: %s from seed %d" % [want, s + k])
			break
		c.free()
	if _car == null:
		return
	_car.name = "RefcamCrash"
	var basis := Basis(Vector3.UP, yaw)
	var ground := plan.height_at(Vector2(lamp_w.x, lamp_w.z) - Vector2(out.x, out.z) * 2.5)
	_car.position = WorldState.to_local(Vector3(lamp_w.x, ground + 0.6, lamp_w.z) - heading * 6.0)
	_car.rotation.y = yaw
	scene.add_child(_car)
	for i in 3:
		await tree.physics_frame
	var dmg := _car.damage_state()
	var crush_back := _num(spec, "crush_back", "CRASH_BACK", 0.42)
	var off := _num(spec, "offset", "CRASH_OFFSET", 0.25)
	var right := basis * Vector3.RIGHT
	# The car's nose (crushed back `crush_back`) against the pole, `off` right of its centre line.
	var centre := lamp_w - heading * (dmg._len * 0.5 - crush_back) - right * off
	centre.y = ground + 0.45
	_car.global_transform = Transform3D(basis, WorldState.to_local(centre))
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	# The pole: no shove from it (the box is the uncrushed car), and bent over by the hit.
	var props := lamp_ch.get_node_or_null("StreetProps") as PhysicsBody3D
	if props:
		_car.add_collision_exception_with(props)
	lamp_ch.damage_prop(lamp_rec, _num(spec, "pole", "CRASH_POLE", 48.0), heading)
	# The crash itself, through the one entry point (CarDamage.stage()'s way: marks, no health).
	dmg._staged = true
	dmg._stage_hold = true
	var kmh := _num(spec, "kmh", "CRASH_KMH", 55.0)
	var over := kmh / 3.6 - _car.crash_min_dv
	var xf := _car.global_transform
	var mid := dmg._ride + (dmg._top - dmg._ride) * 0.42
	_car.hold_crash_watch(8)
	CrashAftermath.note_pole(CrashAftermath.POLE_WIDTH)
	_car.take_hit(-1, over, xf.basis * Vector3.BACK, xf * Vector3(off, mid, -dmg._len * 0.5 - 0.3), Vehicle.HIT_CRASH)
	dmg._stage_hold = false
	dmg._push()
	_car.set_meta("debris_life", 100000.0)
	# Walkers onto the block the lamp stands on, and the scene opened round the wreck.
	var bi := plan.block_index_at(Vector2(lamp_w.x, lamp_w.z) + Vector2(out.x, out.z) * 4.0)
	var chunk := chunks.get(bi) as Node3D
	var people := int(spec.get("people", 18))
	if chunk != null:
		var rect: Rect2 = plan.block(bi.x, bi.y).rect
		for i in people:
			var p := Pedestrian.new()
			p.setup(rect, plan.sidewalk_width, 61000 + i * 137)
			p.pause_chance = 0.0
			p.jogger_share = Vector2.ZERO
			p.dog_share = Vector2.ZERO
			p.set_meta("no_trim", true)
			var lamp2 := Vector2(lamp_w.x, lamp_w.z)
			var q := p._random_ring_point(plan.sidewalk_width)
			for k in 10:
				if q.distance_to(lamp2) < 26.0:
					break
				q = p._random_ring_point(plan.sidewalk_width)
			p.position = Vector3(q.x, (chunk.call("ground_y", q.x, q.y) as float) + 0.1, q.y)
			chunk.add_child(p)
			_people.append(p)
	for i in 30:
		await tree.physics_frame
	var node := Onlookers.find()
	if node != null and Onlookers.enabled:
		var sc: Dictionary = node.stage(Onlookers.Kind.WRECK, WorldState.to_world(_car.global_position), _car, int(spec.get("count", 10)))
		print("REFCAM crash: %d onlookers in place" % (sc.members as Array).size())
		for m: Pedestrian in sc.members:
			print("REFCAM crash:   onlooker %s at %s" % [Onlookers.Role.keys()[int(m.watch.role)], WorldState.to_world(m.global_position)])
	# Let the car settle on its wheels (the front pair up on the kerb), the airbags sag and the
	# onlookers walk to their places.
	for i in int(spec.get("settle", 150)):
		await tree.physics_frame
	var cw := WorldState.to_world(_car.global_position)
	var cb := _car.global_basis
	var eye := cw + cb * _vec(spec, "eye", "CRASH_EYE", Vector3(2.2, 1.6, -4.0))
	eye.y = cw.y + _vec(spec, "eye", "CRASH_EYE", Vector3(2.2, 1.6, -4.0)).y
	var look := cw + cb * _vec(spec, "look", "CRASH_LOOK", Vector3(0.3, 0.5, -2.0))
	var d := (look - eye).normalized()
	var eye_text := "%.3f,%.3f,%.3f,%.3f,%.3f" % [eye.x, eye.y, eye.z, rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))]
	OS.set_environment("EYE", eye_text)
	for i in 4:
		await tree.process_frame
		place.call()
	# Nobody standing in the lens or between it and the nose.
	var eye_l := WorldState.to_local(eye)
	var nose_l := _car.global_transform * Vector3(0.0, 0.5, -dmg._len * 0.5)
	for p in tree.get_nodes_in_group("pedestrian"):
		var n := p as Node3D
		if n == null:
			continue
		var q := Geometry3D.get_closest_point_to_segment(n.global_position + Vector3.UP, eye_l, nose_l)
		# ... nor walking through the wreck (walkers keep to their ring whatever stands on it).
		var in_car := _car.global_transform.affine_inverse() * n.global_position
		var inside := absf(in_car.x) < dmg._width * 0.5 + 0.35 and absf(in_car.z) < dmg._len * 0.5 + 0.35
		if q.distance_to(n.global_position + Vector3.UP) < 0.9 or inside:
			n.visible = false
	var fl := CrashAftermath.instance()
	var pool_at := "none"
	if fl != null and not fl._pools.is_empty() and is_instance_valid(fl._pools[fl._pools.size() - 1][0]):
		var pm := fl._pools[fl._pools.size() - 1][0] as MeshInstance3D
		pool_at = "%s visible %s" % [WorldState.to_world(pm.global_position), pm.is_visible_in_tree()]
	print("REFCAM crash: crush %.2f m, pools %d (last at %s), steam %s, bonnet %.2f rad" % [dmg._crumple.crush_at_end(-1.0) if dmg._crumple else 0.0,
			fl.pools_made if fl else 0, pool_at, _car.find_child("RadiatorSteam", true, false) != null,
			dmg._breakup.bonnet_angle if dmg._breakup else -1.0])
	print("REFCAM crash: lamp %s/%s at %s lean %.2f, car at %s, eye %s" % [lamp_ch.key, lamp_rec.id, lamp_w, float(lamp_rec.get("lean_angle", 0.0)), cw, eye_text])


static func unstage() -> void:
	if is_instance_valid(_car):
		_car.queue_free()
	_car = null
	for p in _people:
		if is_instance_valid(p):
			(p as Node).queue_free()
	_people.clear()
