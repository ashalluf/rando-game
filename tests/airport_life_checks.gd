extends RefCounted
## The airport's ground (AirportGround) for tests/smoke_test.gd: the taxi layout follows the paint
## and keeps clear of the parked jets, a landed airliner is taken off the runway to a free stand
## (crossing the departure runway only when it owns it), parks on the stop bar and becomes the
## stand's instance, a departure is pushed back by its tug, taxis out, holds, lines up and takes
## off, the gates swap seamlessly (the live jet and the instance are the same model, place and
## livery), the bridges follow the stands, the baggage trains keep apart on the service road and
## the catering truck's box rises at the door. Loaded at run time, so it compiles after the
## autoloads; everything is stepped by hand (minutes of the field in a frame).

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var air: AirTraffic = city.get_node_or_null("AirTraffic") as AirTraffic
	if air == null or air.macro == null:
		return
	for i in 3:
		await _tree.physics_frame
	var ground := air.ground
	t._check(ground != null, "the airport has its ground traffic (AirportGround)")
	if ground == null:
		return
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	air.set_physics_process(false)
	ground.set_physics_process(false)
	air.clear_all()
	await _tree.physics_frame
	_layout(air)
	_registry(air)
	await _fit(air)
	await _arrival(air, ground)
	await _departure(air, ground)
	_trains(ground)
	_catering(ground)
	air.clear_all()
	ground.set_physics_process(true)
	air.set_physics_process(true)
	if police and police_was != null:
		police.set("enabled", police_was)


## Each stand's lead-in starts on the taxiway centre line, ends on the stop with the jet facing the
## building, turns no tighter than its radius, and its swept path stays clear of the stands either
## side; the arrival and departure legs line up end to end.
func _layout(air: AirTraffic) -> void:
	var macro := air.macro
	var gs := Airport.gates()
	var worst_end := 0.0
	var worst_yaw := 0.0
	var worst_side := INF
	var tightest := INF
	for i in gs.size():
		var g: Dictionary = gs[i]
		var r := AirportGround.lead_in_route(macro, g)
		worst_end = maxf(worst_end, r.xz[r.xz.size() - 1].distance_to(g.centre))
		worst_yaw = maxf(worst_yaw, absf(wrapf(r.yaw[r.yaw.size() - 1] - float(g.yaw), -PI, PI)))
		worst_end = maxf(worst_end, absf(r.xz[0].y - macro.taxiway_z))
		for k in r.turn.size():
			if absf(r.turn[k]) > 1e-4:
				tightest = minf(tightest, 1.0 / absf(r.turn[k]))
		for j in [i - 1, i + 1]:
			if j < 0 or j >= gs.size():
				continue
			for q: Vector2 in r.xz:
				worst_side = minf(worst_side, q.distance_to(gs[j].centre))
	_t._check(worst_end < 0.6 and rad_to_deg(worst_yaw) < 1.0 and tightest > 14.0 and worst_side > 38.0,
		"every stand's lead-in runs from the taxiway centre line to the stop bar, facing the building (%.2f m, %.2f deg), turns no tighter than %.0f m and keeps %.0f m from the next stand's jet" % [worst_end, rad_to_deg(worst_yaw), tightest, worst_side])
	# A departure's legs and an arrival's join end to end (no jump at a leg boundary).
	var probe := air.spawn_ground_jet(Aircraft.Kind.AIRLINER, 0, Vector3(0.0, 0.1, 800.0), 0.0)
	var gap := 0.0
	var arr := air.ground.arrival_legs(Vector2(-300.0, macro.runway_zs[macro.arrival_runway]), 3, probe)
	var dep := air.ground.departure_legs(3, probe)
	for legs: Array in [arr, dep]:
		for k in range(1, legs.size()):
			var a: AirRoute = legs[k - 1].route
			var b: AirRoute = legs[k].route
			gap = maxf(gap, a.xz[a.xz.size() - 1].distance_to(b.xz[0]))
	var start := air.departure_start()
	var t2: AirRoute = dep[dep.size() - 1].route
	var lined := t2.xz[t2.xz.size() - 1].distance_to(start)
	var dr: AirRoute = air.routes["departure_%d_left" % Aircraft.Kind.AIRLINER]
	_t._check(gap < 0.05 and lined < 0.05 and dr.xz[0].distance_to(start) < 0.05,
		"the ground legs join end to end (%.3f m) and the taxi-out ends where the departure route starts (%.3f m)" % [gap, lined])
	probe.remove()


## The concourse's parked jets are registered with the ground (every stand an instance) and the
## chunks' gate sets as they build.
func _registry(air: AirTraffic) -> void:
	var stands := {}
	for reg: Array in AirportGround._jet_regs:
		if is_instance_valid(reg[0]):
			for gi: int in reg[1]:
				stands[gi] = true
	_t._check(stands.size() == Airport.GATE_COUNT and AirportGround.gate_count() == Airport.GATE_COUNT,
		"every stand's parked jet is registered with the airport's ground (%d of %d)" % [stands.size(), Airport.GATE_COUNT])
	var _a := air


## A live jet at a stand is exactly the stand's instance: same model, scale, place and heading.
func _fit(air: AirTraffic) -> void:
	var g: Dictionary = Airport.gates()[2]
	var c: Vector2 = g.centre
	var jet := air.spawn_ground_jet(Aircraft.Kind.AIRLINER, 1, Vector3(c.x, air.macro.tarmac_top, c.y), float(g.yaw))
	await _tree.process_frame
	var inst: Node3D = null
	for n in jet.find_children("*", "Node3D", true, false):
		if n.get_parent() == jet.get_node_or_null("Visual") and not String(n.name).begins_with("Exhaust"):
			inst = n as Node3D
			break
	var ok := inst != null
	var err := INF
	if inst:
		var live := WorldState.to_world(inst.global_position)
		var want := AirportTerminal.jet_transform(c, float(g.yaw), air.macro.tarmac_top)
		err = live.distance_to(want.origin) + (inst.global_basis.x - want.basis.x).length() * 10.0
		ok = err < 0.05
	_t._check(ok, "a live jet at a stand stands exactly where the stand's parked instance does (%.3f)" % err)
	var shimmer := jet.find_children("Exhaust*", "MeshInstance3D", true, false)
	_t._check(shimmer.size() == (0 if OS.has_feature("web") else 2), "an airliner carries heat shimmer behind its two engines on desktop (%d)" % shimmer.size())
	jet.remove()
	await _tree.process_frame


func _step(air: AirTraffic, ground: AirportGround, dt: float, jets: Array) -> void:
	ground.advance(dt)
	for j: AmbientJet in jets:
		if is_instance_valid(j) and not j.done:
			j.set_physics_process(false)
			j.advance(dt)


func _arrival(air: AirTraffic, ground: AirportGround) -> void:
	var macro := air.macro
	# Make room: stand 4 empty (as if its jet had left).
	var gi := 4
	AirportGround.g_state[gi] = AirportGround.G.EMPTY
	AirportGround.g_jet_shown[gi] = false
	AirportGround.g_set_shown[gi] = false
	AirportGround.g_bridge_to[gi] = 0.0
	AirportGround.g_bridge[gi] = 0.0
	for i in AirportGround.gate_count():
		if i != gi and AirportGround.g_state[i] == AirportGround.G.EMPTY:
			AirportGround.g_state[i] = AirportGround.G.INBOUND
	AirportGround._apply_jet(gi)
	var jet := air.spawn_arrival(Aircraft.Kind.AIRLINER, 2600.0, "arrival_south")
	await _tree.physics_frame
	var t := 0.0
	var dt := 1.0 / 20.0
	var claimed := false
	var off_paving := 0
	var top_speed := 0.0
	var crossed_owned := true
	var rz_dep: float = macro.runway_zs[macro.departure_runway]
	var hw := macro.runway_width * 0.5
	var parked_at := Vector2.INF
	var parked_yaw := 0.0
	while t < 400.0 and is_instance_valid(jet) and not jet.done:
		_step(air, ground, dt, [jet])
		t += dt
		if jet.phase == AmbientJet.Phase.GROUND:
			claimed = true
			top_speed = maxf(top_speed, jet.speed)
			var p := Vector2(jet.world_pos.x, jet.world_pos.z)
			if not _on_paving(macro, p):
				off_paving += 1
			if absf(p.y - rz_dep) < hw + jet.length * 0.5 and ground.runway_owner() != jet:
				crossed_owned = false
		if jet.phase == AmbientJet.Phase.PARKED and parked_at == Vector2.INF:
			parked_at = Vector2(jet.world_pos.x, jet.world_pos.z)
			parked_yaw = jet.yaw
	var g: Dictionary = Airport.gates()[gi]
	_t._check(claimed and ground.gate_of(jet) in [gi, -1], "a landed airliner is taken off the runway to the free stand (%s)" % ("claimed" if claimed else "rolled to the end"))
	_t._check(parked_at.distance_to(g.centre) < 0.5 and absf(wrapf(parked_yaw - float(g.yaw), -PI, PI)) < 0.03,
		"it taxis in and stops on the stand's stop bar (%.2f m off, %.1f deg)" % [parked_at.distance_to(g.centre), rad_to_deg(absf(wrapf(parked_yaw - float(g.yaw), -PI, PI)))])
	_t._check(off_paving == 0 and top_speed < jet.ground_speed + 1.2 and crossed_owned,
		"on the ground it stays on the paving (%d samples off), under taxi speed (%.1f m/s) and crosses the departure runway only as its owner" % [off_paving, top_speed])
	_t._check(AirportGround.g_jet_shown[gi] and AirportGround.g_state[gi] == AirportGround.G.PARKED and AirportGround.g_bridge[gi] > 0.99 and (not is_instance_valid(jet) or jet.done),
		"docked, the bridge swings out and the jet becomes the stand's instance (bridge %.2f)" % AirportGround.g_bridge[gi])


func _on_paving(macro: MacroMap, p: Vector2) -> bool:
	var hw := macro.runway_width * 0.5
	for rz: float in macro.runway_zs:
		if absf(p.y - rz) < hw and p.x > macro.airport_rect.position.x:
			return true
	for cx: float in Airport.CONNECTOR_XS:
		if absf(p.x - cx) < Airport.CONNECTOR_WIDTH * 0.5 + 0.5 and p.y > macro.taxiway_z - 2.0:
			return true
	if absf(p.y - macro.taxiway_z) < macro.taxiway_width * 0.5 + 0.5:
		return true
	# The apron: north of the taxiway, inside the field.
	return p.y < macro.taxiway_z and macro.airport_rect.has_point(p)


func _departure(air: AirTraffic, ground: AirportGround) -> void:
	# Stand 2 is ready, its trucks gone (nobody watches a headless test).
	var gi := 2
	AirportGround.g_ready_at[gi] = 0.0
	AirportGround.g_set_shown[gi] = false
	AirportGround.g_state[gi] = AirportGround.G.PARKED
	AirportGround.g_jet_shown[gi] = true
	AirportGround.g_bridge[gi] = 1.0
	AirportGround.g_bridge_to[gi] = 1.0
	var jet := ground.push_back(gi)
	await _tree.physics_frame
	var g: Dictionary = Airport.gates()[gi]
	var backward := 0
	var forward_in_push := 0
	var lined := false
	var held_for_crossing := true
	var t := 0.0
	var dt := 1.0 / 20.0
	var lifted := false
	var freed_at := -1.0
	while t < 420.0 and is_instance_valid(jet) and not jet.done and not lifted:
		_step(air, ground, dt, [jet])
		t += dt
		if jet.phase == AmbientJet.Phase.GROUND and jet.ground_leg == 0 and jet.speed > 0.2:
			var facing := Vector2(-sin(jet.yaw), -cos(jet.yaw))
			var moving := Vector2(jet.velocity.x, jet.velocity.z)
			if facing.dot(moving) < 0.0:
				backward += 1
			else:
				forward_in_push += 1
		if jet.plan == AmbientJet.Plan.DEPARTURE and jet.phase == AmbientJet.Phase.LINEUP:
			lined = true
		if jet.phase == AmbientJet.Phase.AIRBORNE:
			lifted = true
		if freed_at < 0.0 and AirportGround.g_state[gi] == AirportGround.G.EMPTY:
			freed_at = t
	_t._check(not AirportGround.g_jet_shown[gi] and backward > 20 and forward_in_push == 0,
		"a departure turns the stand's instance into a live jet and is pushed back tail first (%d samples)" % backward)
	_t._check(lined and lifted, "it taxis out, holds short, lines up and takes off (%.0f s from the stand)" % t)
	_t._check(freed_at > 0.0 and AirportGround.g_bridge[gi] < 0.01, "its stand is free once it is off the lead-in, the bridge drawn in (%.0f s)" % freed_at)
	if is_instance_valid(jet):
		jet.remove()
	await _tree.process_frame
	var _g := g
	var _h := held_for_crossing


## The trains run the service road on one schedule a period apart: never closer than a train's
## length, always on the apron.
func _trains(ground: AirportGround) -> void:
	var closest := INF
	var length := ground._train_route.length
	var t := 0.0
	while t < ground._train_period:
		for a in ground.trains:
			for b in ground.trains:
				if a < b:
					var d := absf(ground.train_s(a, t) - ground.train_s(b, t))
					closest = minf(closest, minf(d, length - d))
		t += 1.0
	var off := 0
	for i in ground._train_route.xz.size():
		var p: Vector2 = ground._train_route.xz[i]
		if p.y >= ground.macro.taxiway_z - ground.macro.taxiway_width * 0.5 or Airport.near_gate(p, -2.0):
			off += 1
	var need := AirportGround.CART_PITCH * float(ground.train_carts + 1) + 6.0
	_t._check(closest > need and off == 0, "the baggage trains keep apart on the service road (closest %.0f m, need %.0f) behind the stands (%d points off)" % [closest, need, off])


func _catering(ground: AirportGround) -> void:
	ground._near = false
	ground._tend_vehicles(0.0)
	if ground._catering == null:
		ground._build_vehicles()
	AirportGround.g_ready_at[1] = AirportGround.clock + 900.0
	ground._send_catering(1)
	var top := 0.0
	var t := 0.0
	var m = ground._catering
	while t < 400.0 and m.busy(AirportGround.clock):
		AirportGround.clock += 0.25
		ground._tend_catering_lift()
		top = maxf(top, ground.catering_lift())
		t += 0.25
	_t._check(top > 3.2 and ground.catering_lift() < 0.3, "the catering truck drives to the rear door, lifts its box to the sill and lowers it to drive home (%.1f m)" % top)
