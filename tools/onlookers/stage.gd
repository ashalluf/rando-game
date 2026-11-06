extends RefCounted
## Stages an onlooker scene in front of the camera for stills (tools/glshot/still_shot.gd
## ONLOOKER_SCENE=body|wreck|blast|leave): on the pavement of the block the camera looks at, a
## body (a walker knocked down), a burnt-out car at the kerb, or a blast's scorch; a crowd of
## walkers on that block and the one across the road; the scene opened quiet already and the
## nearest of them put straight into their places round it (Onlookers.stage). `leave` is the body
## with an ambulance sent (Emergency on), so the crowd breaks up as it pulls in.
## Returns the free camera (an EYE string) from the road, looking at the scene; ONLOOKER_EYE=
## behind is over a filmer's shoulder, front in front of a filmer; ONLOOKER_SHOTS=1 queues them all.
## ONLOOKERS=0 is the before: the same scene and walkers, nobody comes to look.
##
## Env: ONLOOKER_AHEAD (m, default 24) how far ahead the scene is looked for; ONLOOKER_PEOPLE
## (default 16) walkers added; ONLOOKER_COUNT (default 11) put in place at once.


static func stage(tree: SceneTree, city: Node, kind: String, cam: Camera3D) -> String:
	var plan: CityPlan = city.get("plan")
	if plan == null or cam == null:
		return ""
	var em: Node = city.get_node_or_null("Emergency")
	if em:
		em.set("enabled", kind == "leave")
	var cw := WorldState.to_world(cam.global_position)
	var fwd := -cam.global_basis.z
	var f2 := Vector2(fwd.x, fwd.z).normalized()
	var ahead := float(OS.get_environment("ONLOOKER_AHEAD")) if OS.get_environment("ONLOOKER_AHEAD") != "" else 24.0
	var goal := Vector2(cw.x, cw.z) + f2 * ahead
	var bi := plan.block_index_at(goal)
	var rect: Rect2 = plan.block(bi.x, bi.y).rect
	var chunks: Dictionary = city.get("chunks")
	var chunk: Node3D = chunks.get(bi)
	if chunk == null:
		print("ONLOOKER_SCENE: no chunk at %s" % bi)
		return ""
	# The edge of the block facing the camera, and a point on its pavement level with the camera.
	var c2 := Vector2(cw.x, cw.z)
	var d := [c2.x - rect.position.x, rect.end.x - c2.x, c2.y - rect.position.y, rect.end.y - c2.y]
	var outs := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	var edge := 0
	for i in 4:
		if d[i] < d[edge]:
			edge = i
	var out: Vector2 = outs[edge]
	var inset := 2.4
	var at := goal.clamp(rect.position + Vector2.ONE * 8.0, rect.end - Vector2.ONE * 8.0)
	match edge:
		0:
			at.x = rect.position.x + inset
		1:
			at.x = rect.end.x - inset
		2:
			at.y = rect.position.y + inset
		_:
			at.y = rect.end.y - inset
	var gy := chunk.call("ground_y", at.x, at.y) as float
	var world := Vector3(at.x, gy, at.y)
	# Walkers: most on the scene's block, a few on the block across the road.
	var people := int(OS.get_environment("ONLOOKER_PEOPLE")) if OS.get_environment("ONLOOKER_PEOPLE") != "" else 16
	var across := plan.block_index_at(at + out * (plan.sidewalk_width + 14.0))
	var other: Node3D = chunks.get(across)
	var spawned := 0
	for i in people:
		var on_other := other != null and i % 4 == 3
		var ch: Node3D = other if on_other else chunk
		var r: Rect2 = plan.block(across.x, across.y).rect if on_other else rect
		var p := Pedestrian.new()
		p.setup(r, plan.sidewalk_width, 51000 + i * 131)
		p.pause_chance = 0.0
		p.jogger_share = Vector2.ZERO
		p.dog_share = Vector2.ZERO
		p.set_meta("no_trim", true)
		var q := p._random_ring_point(plan.sidewalk_width)
		for k in 6:
			if q.distance_to(at) < 30.0:
				break
			q = p._random_ring_point(plan.sidewalk_width)
		p.position = Vector3(q.x, (ch.call("ground_y", q.x, q.y) as float) + 0.1, q.y)
		ch.add_child(p)
		spawned += 1
	for i in 12:
		await tree.physics_frame
	var ref: Object = null
	var okind := Onlookers.Kind.BODY
	match kind:
		"wreck":
			okind = Onlookers.Kind.WRECK
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			var car := Vehicle.random_car(rng)
			var kerb := at + out * (inset + 1.4)
			var yaw := atan2(-out.y, out.x) # side-on to the road
			car.transform = Transform3D(Basis(Vector3.UP, yaw + 0.3), WorldState.to_local(Vector3(kerb.x, gy + 0.6, kerb.y)))
			city.add_child(car)
			for i in 3:
				await tree.physics_frame
			var dmg: CarDamage = car.damage_state()
			dmg._staged = true
			dmg.become_wreck()
			ref = car
			# Debris time is wall-clock, and a software still takes minutes a view.
			car.set_meta("debris_life", 100000.0)
			# A wreck is tossed when it goes up: where it comes to rest is the scene.
			for i in 90:
				await tree.physics_frame
			world = WorldState.to_world(car.global_position)
			var rest := Vector2(world.x, world.z)
			at = rest - out * (inset + 1.4)
		"blast":
			okind = Onlookers.Kind.BLAST
		_:
			var victim := Pedestrian.new()
			victim.setup(rect, plan.sidewalk_width, 50999)
			victim.position = Vector3(at.x, gy + 0.1, at.y)
			chunk.add_child(victim)
			for i in 3:
				await tree.physics_frame
			victim.knock(Vector3(out.x * 0.6, 0.4, out.y * 0.6))
			ref = victim._doll
			for i in 40:
				await tree.physics_frame
			if is_instance_valid(ref) and ref is Ragdoll and not (ref as Ragdoll).bodies.is_empty():
				world = WorldState.to_world(((ref as Ragdoll).bodies[0] as Node3D).global_position)
				(ref as Node).set_meta("debris_life", 100000.0)
				(ref as Node).set_meta("onlooked", true)
	var count := int(OS.get_environment("ONLOOKER_COUNT")) if OS.get_environment("ONLOOKER_COUNT") != "" else 11
	var node := Onlookers.find()
	var s: Dictionary = {}
	if node != null and Onlookers.enabled:
		s = node.stage(okind, world, ref, count)
		print("ONLOOKER_SCENE %s at %s: %d of %d walkers in place" % [kind, world, (s.members as Array).size(), spawned])
		for m: Pedestrian in s.members:
			print("  ONLOOKER %s role %s at %s" % [m.name, Onlookers.Role.keys()[int(m.watch.role)], WorldState.to_world(m.global_position)])
	else:
		print("ONLOOKER_SCENE %s at %s: onlookers off" % [kind, world])
	# The cameras: across the pavement from the road (the ring and the body), over a filmer's
	# shoulder, and in front of a filmer (the face, the phone held up). ONLOOKER_SHOTS=1 queues the
	# other views (and the first again at ONLOOKER_NIGHT, default 21.5) as SHOTS for the same load.
	var look := Vector3(world.x, world.y + 0.9, world.z)
	var side := Vector2(-out.y, out.x)
	var back := 20.0 if okind == Onlookers.Kind.WRECK else 11.0
	var main := _eye_at(Vector3(at.x, gy + 1.75, at.y) + Vector3(out.x, 0.0, out.y) * back + Vector3(side.x, 0.0, side.y) * 2.5, look)
	var filmer: Pedestrian = null
	var best := INF
	for m: Pedestrian in s.get("members", []):
		var d2 := m.global_position.distance_to(WorldState.to_local(world))
		if int(m.watch.role) == Onlookers.Role.FILM and d2 < best:
			best = d2
			filmer = m
	var behind := main
	var front := main
	if filmer != null:
		var fp := WorldState.to_world(filmer.global_position)
		var to := (Vector2(world.x, world.z) - Vector2(fp.x, fp.z)).normalized()
		var sd := Vector2(-to.y, to.x)
		var b2 := Vector2(fp.x, fp.z) - to * 1.6 + sd * 0.5
		behind = _eye_at(Vector3(b2.x, fp.y + 1.8, b2.y), Vector3(world.x, world.y + 0.3, world.z))
		var fr2 := Vector2(fp.x, fp.z) + to * 3.2 + sd * 1.6
		front = _eye_at(Vector3(fr2.x, fp.y + 1.55, fr2.y), fp + Vector3.UP * 1.45)
	if OS.get_environment("ONLOOKER_SHOTS") == "1":
		var hour := OS.get_environment("ONLOOKER_HOUR") if OS.get_environment("ONLOOKER_HOUR") != "" else "14"
		var night := OS.get_environment("ONLOOKER_NIGHT") if OS.get_environment("ONLOOKER_NIGHT") != "" else "21.5"
		OS.set_environment("SHOTS", "%s@%s@40;%s@%s@40;%s@%s;%s@%s@40" % [behind, hour, front, hour, main, night, front, night])
	match OS.get_environment("ONLOOKER_EYE"):
		"behind":
			return behind
		"front":
			return front
	return main


static func _eye_at(e: Vector3, look: Vector3) -> String:
	var dv := look - e
	var yaw_deg := rad_to_deg(atan2(-dv.x, -dv.z))
	var pitch := rad_to_deg(atan2(dv.y, Vector2(dv.x, dv.z).length()))
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [e.x, e.y, e.z, yaw_deg, pitch]
