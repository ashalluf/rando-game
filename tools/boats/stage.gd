extends RefCounted
## Stages a boat run for stills (tools/glshot/still_shot.gd BOAT=speedboat|jetski|dock): the
## player put in a fresh boat out on the bay (BOAT_AT=x,z true world; default 260 m off the
## beach 700 m south of the marina's channel), heading BOAT_HEADING degrees (the --spawn yaw: 0 north, 90 west),
## the throttle held (BOAT_BOOST=1 with the boost) for BOAT_TICKS physics ticks so the wake and
## spray have built; then a free camera framed on it: BOAT_VIEW=chase (behind and above), side
## (abeam, low), front (ahead, low, looking back at the bow), high (an aerial over the wake).
## `dock` frames the moored pair from the headwalk. Returns the EYE string.


static func stage(tree: SceneTree, city: Node, kind: String, _cam: Camera3D) -> String:
	var plan: CityPlan = city.get("plan")
	var m: MacroMap = plan.macro if plan else null
	var player := tree.get_first_node_in_group("player") as Player
	if m == null or m.marina == null or player == null:
		return ""
	if kind == "dock":
		var sp := BoatMoorings.spots(m.marina)
		var p: Vector2 = sp[0].p
		var at := Vector3(p.x + 3.2, Marina.DOCK_Y + 1.7, p.y - 12.0)
		player.global_position = WorldState.to_local(at + Vector3(0.0, 0.0, 40.0))
		city.call("update_streaming", true)
		city.call("ensure_loaded_at", WorldState.to_local(Vector3(p.x, 0.0, p.y)))
		for i in 240:
			await tree.physics_frame
		return "%.2f,%.2f,%.2f,%.1f,%.1f" % [at.x, at.y, at.z, 168.0, -14.0]
	var k := BoatKit.Kind.JETSKI if kind == "jetski" else BoatKit.Kind.SPEEDBOAT
	var at2 := Vector2(m.coast_x(m.marina.zc + 700.0) - 260.0, m.marina.zc + 700.0)
	var env := OS.get_environment("BOAT_AT")
	if env != "":
		var q := env.split(",")
		at2 = Vector2(q[0].to_float(), q[1].to_float())
	var heading := deg_to_rad(float(OS.get_environment("BOAT_HEADING")) if OS.get_environment("BOAT_HEADING") != "" else 0.0)
	var b := Boat.new()
	b.name = "StagedBoat"
	b.setup_boat(k, int(OS.get_environment("BOAT_LOOK")) if OS.get_environment("BOAT_LOOK") != "" else 11)
	b.position = WorldState.to_local(Vector3(at2.x, 0.4, at2.y))
	b.rotation.y = heading
	city.add_child(b)
	# In at once: a player capsule left standing inside the hull for a step is a depenetration.
	player.enter_vehicle(b)
	city.call("update_streaming", true)
	await tree.physics_frame
	var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
	b.linear_velocity = fwd * (16.0 if k == BoatKit.Kind.SPEEDBOAT else 18.0)
	Input.action_press("move_forward")
	if OS.get_environment("BOAT_BOOST") == "1":
		Input.action_press("boost")
	var steer := OS.get_environment("BOAT_STEER")
	var ticks := int(OS.get_environment("BOAT_TICKS")) if OS.get_environment("BOAT_TICKS") != "" else 420
	for i in ticks:
		if steer != "" and i > ticks - 90:
			Input.action_press("move_right" if steer == "right" else "move_left")
		await tree.physics_frame
	city.call("update_streaming", true)
	var bw := WorldState.to_world(b.global_position)
	var f := Vector3(-b.global_basis.z.x, 0.0, -b.global_basis.z.z).normalized()
	var r := Vector3(b.global_basis.x.x, 0.0, b.global_basis.x.z).normalized()
	var big := k == BoatKit.Kind.SPEEDBOAT
	var view := OS.get_environment("BOAT_VIEW")
	if view == "all":
		# The chase now, the rest as SHOTS from the same (frozen) moment.
		var hour := OS.get_environment("BOAT_HOUR") if OS.get_environment("BOAT_HOUR") != "" else "17.4"
		var more: Array[String] = []
		for v: String in ["side", "front", "high"]:
			more.append(_eye_for(bw, f, r, big, v) + "@" + hour + "@50")
		OS.set_environment("SHOTS", ";".join(more))
		view = "chase"
	print("BOAT staged %s at %s speed %.1f wet %.2f" % [kind, str(bw.snapped(Vector3.ONE * 0.1)), b.linear_velocity.length(), b.wet])
	return _eye_for(bw, f, r, big, view)


static func _eye_for(bw: Vector3, f: Vector3, r: Vector3, big: bool, view: String) -> String:
	var eye := Vector3.ZERO
	match view:
		"side":
			eye = bw + r * (9.0 if big else 6.0) + f * 2.0 + Vector3.UP * 1.6
		"front":
			eye = bw + f * (12.0 if big else 8.0) + r * 2.5 + Vector3.UP * 1.4
		"high":
			eye = bw - f * 26.0 + r * 10.0 + Vector3.UP * 22.0
		_:
			eye = bw - f * (11.0 if big else 7.5) + r * 1.5 + Vector3.UP * (3.4 if big else 2.4)
	var look := bw + Vector3.UP * 0.6 + f * (0.5 if view != "front" else 0.0)
	var d := (look - eye).normalized()
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(asin(d.y))
	return "%.2f,%.2f,%.2f,%.1f,%.1f" % [eye.x, eye.y, eye.z, yaw, pitch]
