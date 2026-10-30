extends RefCounted
## The player's boats (Boat, BoatKit, BoatWake, BoatRidePose, BoatMoorings;
## scripts/vehicles/boat*.gd), for tests/smoke_test.gd: the meshes keep to their budgets and step
## down level by level; the moorings are in the marina's water, the same for a seed, two of them;
## the ride pose has every limb. Then the real thing at the marina: both boats are built with the
## chunk and float level at the waterline, over the GroundBody (excepted); interact gets the
## player in, the hero is drawn seated; the throttle drives the speedboat up onto the plane and
## the wake comes on; the helm turns it; out at sea it rides the drawn swell; driven at the beach
## it grounds on the sand; a rocket's worth of blasts blows it up, throws the driver out, and it
## sinks and cannot be boarded; `BOATS=0` builds none.
## Untyped access to the player and the city (autoloads, see smoke_test.gd).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan = city.get("plan")
	var m: MacroMap = plan.macro if plan else null
	_check(m != null and m.marina != null and m.marina.ok, "the boats have the city's marina")
	if m == null or m.marina == null or not m.marina.ok:
		return
	_check_meshes()
	_check_spots(m)
	_check_pose()
	await _check_live(city, m)
	await _t.call("stage_home")


func _check_meshes() -> void:
	var ok := true
	var info := []
	for k in 2:
		var tris := [BoatKit.triangles(k, 0), BoatKit.triangles(k, 1), BoatKit.triangles(k, 2)]
		info.append(str(tris))
		ok = ok and tris[0] > tris[1] and tris[1] > tris[2] and tris[0] < 9000 and tris[2] < 700 and tris[2] > 40
	_check(ok, "the boats' meshes step down level by level within budget (%s)" % ", ".join(info))
	var regions_ok := true
	var m := BoatKit.mesh(BoatKit.Kind.JETSKI, 0, 1)
	var cols: PackedColorArray = m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for c in cols:
		var r := floori(c.a * 16.0)
		if r < 0 or r > BoatMesh.Region.ENGINE:
			regions_ok = false
			break
	_check(regions_ok and cols.size() > 0, "every vertex carries a boat shader region (COLOR.a)")


func _check_spots(m: MacroMap) -> void:
	var sp := BoatMoorings.spots(m.marina)
	var wet := true
	for s: Dictionary in sp:
		var p: Vector2 = s.p
		var beam: float = (BoatKit.SIZE[int(s.kind)] as Vector2).y
		var len: float = (BoatKit.SIZE[int(s.kind)] as Vector2).x
		for off: Vector2 in [Vector2(-beam * 0.5, -len * 0.5), Vector2(beam * 0.5, len * 0.5), Vector2(-beam * 0.5, len * 0.5), Vector2(beam * 0.5, -len * 0.5)]:
			wet = wet and m.marina.in_water(p + off)
	_check(sp.size() == 2 and wet, "two moorings, each boat's whole hull in the marina's water (%d)" % sp.size())
	var again := BoatMoorings.spots(m.marina)
	var same := again.size() == sp.size()
	for i in mini(sp.size(), again.size()):
		same = same and (again[i].p as Vector2).is_equal_approx(sp[i].p) and int(again[i].look) == int(sp[i].look)
	_check(same, "the moorings and the boats' looks are the same every time (hashes)")


func _check_pose() -> void:
	var ok := true
	for k in 2:
		var tg := BoatRidePose.ride_targets(k, 0.5)
		for b: String in ["Spine02", "LeftUpLeg", "RightLeg", "LeftArm", "RightForeArm"]:
			ok = ok and tg.has(b) and (tg[b] as Vector3).length() > 0.5
	var helm := BoatRidePose.ride_targets(BoatKit.Kind.SPEEDBOAT, 0.0)
	_check(ok and (helm["LeftUpLeg"] as Vector3).z > 0.8, "the ride pose seats him: thighs forward, every limb aimed")


func _boats(city: Node3D) -> Array:
	var out := []
	for n in city.get_tree().get_nodes_in_group("vehicle"):
		if n is Boat and not (n as Boat).sinking:
			out.append(n)
	return out


func _check_live(city: Node3D, m: MacroMap) -> void:
	var tree := _t.get_tree()
	var player := tree.get_first_node_in_group("player") as CharacterBody3D
	var ws: Node = _t.call("_world_state")
	var sp := BoatMoorings.spots(m.marina)
	if sp.is_empty():
		return
	var spot: Vector2 = sp[0].p
	# On the headwalk beside the speedboat.
	var x_dock := spot.x + (BoatKit.SIZE[0] as Vector2).y * 0.5 + 0.45 + Marina.HEAD_W * 0.5
	player.global_position = ws.call("to_local", Vector3(x_dock, Marina.DOCK_Y + 1.2, spot.y))
	player.velocity = Vector3.ZERO
	city.call("update_streaming", true)
	city.call("ensure_loaded_at", player.global_position)
	var boat: Boat = null
	var jet: Boat = null
	for i in 600:
		await tree.physics_frame
		for b: Boat in _boats(city):
			if b.kind == BoatKit.Kind.SPEEDBOAT and boat == null:
				boat = b
			elif b.kind == BoatKit.Kind.JETSKI and jet == null:
				jet = b
		if boat != null and jet != null:
			break
	_check(boat != null and jet != null, "the speedboat and the jet ski are at the marina's headwalk")
	if boat == null:
		return
	for i in 180:
		await tree.physics_frame
	for b: Boat in [boat, jet]:
		if b == null:
			continue
		var tw: Vector3 = ws.call("to_world", b.global_position)
		_check(absf(tw.y - Marina.WATER_Y) < 0.3 and b.global_basis.y.y > 0.97 and b.wet > 0.4,
			"the %s floats level at the waterline (%.2f m off it, up %.3f, %.0f %% wet)" % [b.display_name(), tw.y - Marina.WATER_Y, b.global_basis.y.y, b.wet * 100.0])
	_check(boat._ground_excepted, "over the water the hull is let through the ground box")
	# In: interact beside it.
	player.global_position = ws.call("to_local", Vector3(x_dock, Marina.DOCK_Y + 1.2, spot.y))
	await tree.physics_frame
	Input.action_press("interact")
	await tree.physics_frame
	Input.action_release("interact")
	for i in 4:
		await tree.physics_frame
	_check(player.get("vehicle") == boat, "interact by the speedboat gets him in")
	if player.get("vehicle") != boat:
		return
	var avatar: Node3D = player.get("avatar")
	var seated := avatar != null and avatar.find_child("BoatRidePose", true, false) != null
	_check(seated and player.visible, "the hero is drawn at the helm, posed in the seat")
	# Throttle: out of the aisle and up onto the plane. Point her at the fairway (west) first.
	var west := Basis(Vector3.UP, PI * 0.5)
	boat.global_basis = west
	boat.linear_velocity = Vector3.ZERO
	boat.angular_velocity = Vector3.ZERO
	Input.action_press("move_forward")
	var top := 0.0
	var wake_on := false
	for i in 240:
		await tree.physics_frame
		top = maxf(top, boat.linear_velocity.length())
		wake_on = wake_on or boat._fx.level() > 0.2
	Input.action_release("move_forward")
	_check(top > 6.0, "the throttle drives her (%.1f m/s in four seconds)" % top)
	_check(wake_on, "and her wake comes on")
	# Open sea: put her 200 m off the beach, heading out, and let the swell have her.
	# Away from the marina (its jetties and breakwater keep the world layer on).
	var z := 1100.0
	var sea := Vector3(m.coast_x(z) - 200.0, 1.0, z)
	boat.global_position = ws.call("to_local", sea)
	boat.global_basis = Basis(Vector3.UP, PI * 0.5)
	boat.linear_velocity = Vector3.ZERO
	boat.angular_velocity = Vector3.ZERO
	city.call("update_streaming", true)
	for i in 120:
		await tree.physics_frame
	var lo := INF
	var hi := -INF
	var off := 0.0
	for i in 180:
		await tree.physics_frame
		var tw: Vector3 = ws.call("to_world", boat.global_position)
		var surf := SeaSurface.height(m, Vector2(tw.x, tw.z), SeaSurface.now(), boat._sea)
		lo = minf(lo, tw.y)
		hi = maxf(hi, tw.y)
		off = maxf(off, absf(tw.y - surf))
	_check(off < 0.6 and hi - lo > 0.04, "at sea she rides the drawn swell (%.2f to %.2f m, at most %.2f m off the surface)" % [lo, hi, off])
	# Flat out for seven seconds (boost on for the last two): she stays on the water.
	Input.action_press("move_forward")
	var high := -INF
	for i in 420:
		if i == 300:
			Input.action_press("boost")
		await tree.physics_frame
		high = maxf(high, (ws.call("to_world", boat.global_position) as Vector3).y)
	Input.action_release("boost")
	Input.action_release("move_forward")
	_check(high < 2.5, "flat out she stays on the water (highest %.2f m, %.1f m/s)" % [high, boat.linear_velocity.length()])
	boat.global_position = ws.call("to_local", sea)
	boat.linear_velocity = Vector3.ZERO
	city.call("update_streaming", true)
	for i in 30:
		await tree.physics_frame
	# Steering: hard right at speed turns her to starboard.
	Input.action_press("move_forward")
	for i in 90:
		await tree.physics_frame
	var yaw0 := boat.global_rotation.y
	Input.action_press("move_right")
	for i in 90:
		await tree.physics_frame
	Input.action_release("move_right")
	Input.action_release("move_forward")
	var turned := wrapf(boat.global_rotation.y - yaw0, -PI, PI)
	_check(turned < -0.4, "the helm turns her to starboard (%.0f degrees)" % rad_to_deg(turned))
	# Out: interact again.
	Input.action_press("interact")
	await tree.physics_frame
	Input.action_release("interact")
	for i in 4:
		await tree.physics_frame
	_check(player.get("vehicle") == null and (avatar == null or avatar.find_child("BoatRidePose", true, false) == null), "interact gets him out, and off the seat")
	# Beached: run her at the sand.
	var shore := Vector3(m.coast_x(z) - 30.0, 1.0, z)
	boat.global_position = ws.call("to_local", shore)
	boat.global_basis = Basis(Vector3.UP, -PI * 0.5)
	boat.linear_velocity = Vector3(16.0, 0.0, 0.0)
	boat.angular_velocity = Vector3.ZERO
	player.global_position = ws.call("to_local", shore + Vector3(60.0, 5.0, 0.0))
	city.call("update_streaming", true)
	for i in 420:
		await tree.physics_frame
	var bw: Vector3 = ws.call("to_world", boat.global_position)
	_check(bw.x > m.coast_x(z) - 25.0 and boat.linear_velocity.length() < 2.0 and bw.y > -1.5,
		"driven at the beach she runs up and grounds on the sand (%.1f m past the waterline, %.1f m/s, y %.2f)" % [bw.x - m.coast_x(z), boat.linear_velocity.length(), bw.y])
	# Destroyed: blasts until she goes, the driver thrown out, then she sinks.
	boat.global_position = ws.call("to_local", sea)
	boat.global_basis = Basis()
	boat.linear_velocity = Vector3.ZERO
	boat.angular_velocity = Vector3.ZERO
	player.global_position = ws.call("to_local", sea + Vector3(30.0, 6.0, 0.0))
	city.call("update_streaming", true)
	for i in 30:
		await tree.physics_frame
	player.call("enter_vehicle", boat)
	await tree.physics_frame
	for k in 3:
		boat.take_hit(-1, 1.0, Vector3.UP, boat.global_position, Vehicle.HIT_BLAST)
	await tree.physics_frame
	_check(boat.sinking and boat.is_wreck() and player.get("vehicle") == null, "a few blasts blow her up and throw the driver out")
	for i in int((boat.sink_seconds + 2.0) * 60.0):
		await tree.physics_frame
		if not is_instance_valid(boat):
			break
	if is_instance_valid(boat):
		var tw: Vector3 = ws.call("to_world", boat.global_position)
		_check(tw.y < -0.8, "and she sinks (%.1f m under)" % -tw.y)
	player.call("_try_enter_vehicle")
	_check(player.get("vehicle") == null or player.get("vehicle") != boat, "a wreck cannot be boarded")
	if player.get("vehicle") != null:
		player.call("exit_vehicle")
	# The switch.
	Boat.enabled = false
	var n0 := _boats(city).size()
	var chunk: Node = null
	for c in city.get_children():
		if c is CityChunk and (c as CityChunk).level == CityChunk.Level.FULL and (c as CityChunk).owned_rect().has_point(sp[1].p):
			chunk = c
	if chunk != null:
		BoatMoorings.build(chunk)
	Boat.enabled = true
	_check(_boats(city).size() == n0, "BOATS=0: no boats")


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
