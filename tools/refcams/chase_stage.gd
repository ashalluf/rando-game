extends RefCounted
## The "drive" staging of a reference camera (tools/refcams/cameras_w5.json, chase_cam): the
## player at the wheel of his own car driving a street at a steady speed, a few placed traffic
## cars round him, and the shot taken from the player's OWN camera (DriveCam), not the free eye.
## Loaded by path from refcams_shot.gd once the autoloads exist (it names Vehicle and Player).
##
## The camera row's "drive" key (every field optional but road and along):
##   {"axis": 0, "x": 2610.8,            the road: AXIS_X (0) at that x, or AXIS_Z (1) at "z"
##    "dir": -1, "lane": 0,              dir -1 = toward -along (north on an AXIS_X road); lane 0 = by the centre line
##    "along": 760.0, "kmh": 40.0,       where the car is at the shot, and its speed
##    "lead": 2.6,                       seconds of driving before the shot (the camera settles)
##    "body": "LUX_SEDAN", "paint": [r, g, b],
##    "traffic": [[dir, lane, metres ahead of the car, kmh, body or ""], ...]}
## The car's velocity is set every physics tick (it still rides its wheels on the road), its
## collision mask is the world only, so nothing a placed car does stops it. TrafficManager.staged
## stops the upkeep adding or shedding street cars round it while it runs.

var tree: SceneTree
var city: Node
var player: Player
var car: Vehicle
var traffic: Node
var _police_was := true
var _staged_was := false
var _placed: Array = []
var _fwd := Vector3.FORWARD


func run(st: SceneTree, cam: Dictionary, p: Node3D) -> void:
	tree = st
	city = tree.current_scene
	player = p as Player
	var d: Dictionary = cam.get("drive", {})
	var plan: CityPlan = city.get("plan")
	var axis := int(d.get("axis", CityPlan.AXIS_X))
	var road_at := float(d.get("x", d.get("z", 0.0)))
	var index := _road_index(plan, axis, road_at)
	var dir := int(d.get("dir", -1))
	var lane_n := int(d.get("lane", 0))
	var along := float(d.get("along", 0.0))
	var kmh := float(d.get("kmh", 40.0))
	var v := kmh / 3.6
	var lead := float(d.get("lead", 2.6))
	var police: Node = city.get_node_or_null("Police")
	if police:
		_police_was = bool(police.get("enabled"))
		police.set("enabled", false)
	traffic = city.get_node_or_null("Traffic")
	# The street's own cars stay; staged keeps the upkeep from shedding the placed ones.
	if traffic:
		_staged_was = bool(traffic.get("staged"))
		traffic.set("staged", true)
	# Start `lead` seconds back so the car passes `along` at the shot.
	var start_along := along - float(dir) * v * lead
	var width := plan.road_width(axis, index)
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	var side := -dir if axis == CityPlan.AXIS_X else dir
	var lane := float(side) * CityPlan.lane_center(width, lanes, clampi(lane_n, 0, lanes - 1))
	var rp := plan.road_pos(axis, index) + lane
	var start := Vector3(rp, 0.0, start_along) if axis == CityPlan.AXIS_X else Vector3(start_along, 0.0, rp)
	_fwd = Vector3(0, 0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0, 0)
	var yaw := atan2(-_fwd.x, -_fwd.z)
	car = Vehicle.new()
	var body_name := String(d.get("body", "LUX_SEDAN"))
	var body: int = Vehicle.BodyType.get(body_name, Vehicle.BodyType.SEDAN)
	var pc: Array = d.get("paint", [0.42, 0.03, 0.04])
	car.setup(body, Color(float(pc[0]), float(pc[1]), float(pc[2])), Vehicle.Addon.NONE)
	car.name = "ChaseCar"
	city.add_child(car)
	car.collision_mask = 1
	await _place(plan, start, yaw)
	player.visible = true
	player.enter_vehicle(car)
	player.camera.make_current()
	# The traffic round him, placed relative to where the car will be at the shot.
	if traffic:
		for row: Array in d.get("traffic", []):
			var tdir := int(row[0])
			var t_along := along + float(dir) * float(row[2])
			# Cars in his direction start where they will be once he has driven `lead` seconds
			# at their speed; oncoming ones start further out along their own way.
			var tv := float(row[3]) / 3.6
			t_along -= float(tdir) * tv * lead
			var kind := -1
			if row.size() > 4 and String(row[4]) != "":
				kind = Vehicle.BodyType.get(String(row[4]), -1)
			var c: Variant = traffic.call("place_car", axis, index, tdir, int(row[1]), t_along, tv, false, kind)
			if c:
				_placed.append(c)
	# The lead-in: rendering off while it drives (seconds a frame on the software renderer).
	tree.root.disable_3d = true
	await _drive(v, lead - 0.5)
	tree.root.disable_3d = false
	await _drive(v, 0.5)
	print("REFCAM drive: %s on road %d at %s, %.0f km/h, %d cars placed" % [body_name, index, str(WorldState.to_world(car.global_position)), car.linear_velocity.length() * 3.6, _placed.size()])


## Keeps the car going while the shot settles (refcams' SETTLE frames at a crawling time scale).
func hold() -> void:
	if is_instance_valid(car):
		_steer(car.linear_velocity.length())


## Puts everything back for the next camera: the player out and the car gone, the police and the
## traffic upkeep as they were. The caller makes its free camera current again.
func finish() -> void:
	if is_instance_valid(car):
		if player.get("vehicle") == car:
			player.exit_vehicle()
		car.queue_free()
	if traffic:
		traffic.set("staged", _staged_was)
	var police: Node = city.get_node_or_null("Police")
	if police:
		police.set("enabled", _police_was)


func _road_index(plan: CityPlan, axis: int, at: float) -> int:
	var i := plan.block_index_at(Vector2(at, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, at))
	var k := i.x if axis == CityPlan.AXIS_X else i.y
	var best := k
	for j in range(k - 1, k + 3):
		if absf(plan.road_pos(axis, j) - at) < absf(plan.road_pos(axis, best) - at):
			best = j
	return best


func _drive(v: float, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		_steer(v)
		await tree.physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func _steer(v: float) -> void:
	var f := -car.global_basis.z
	f.y = 0.0
	f = f.normalized()
	car.linear_velocity = Vector3(f.x * v, car.linear_velocity.y, f.z * v)
	car.angular_velocity = Vector3(car.angular_velocity.x * 0.5, 0.0, car.angular_velocity.z * 0.5)
	car.hold_crash_watch(2)


func _place(plan: CityPlan, world: Vector3, yaw: float) -> void:
	player.global_position = WorldState.to_local(world) + Vector3.UP * 2.0
	city.call("update_streaming", true)
	for i in 4:
		await tree.process_frame
	var gy := plan.height_at(Vector2(world.x, world.z))
	car.hold_crash_watch(6)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), WorldState.to_local(Vector3(world.x, gy + 0.9, world.z)))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	city.call("update_streaming", true)
	var t := 0.0
	while t < 0.6:
		await tree.process_frame
		t += tree.root.get_process_delta_time()


## CHASE_DEBUG=1: what is drawn round the car that is not the car (a census of small geometry and
## every particle system within 30 m, with where it lands on screen), and CHASE_AB=a,b,... renders
## the frame again with each named node under the root or the scene hidden (<name>.png in out).
func debug(out_dir: String) -> void:
	if OS.get_environment("CHASE_DEBUG") == "1":
		var cam := player.camera
		var here := car.global_position
		for n in tree.root.find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if not g.is_visible_in_tree() or car.is_ancestor_of(g):
				continue
			var box := g.global_transform * g.get_aabb()
			var c := box.get_center()
			var is_fx := g is GPUParticles3D or g is CPUParticles3D
			if c.distance_to(here) > 30.0 or (not is_fx and box.size.length() > 12.0):
				continue
			if cam.is_position_behind(c):
				continue
			var sp := cam.unproject_position(c)
			print("CHASE_NODE %s %s size %s screen %s" % [g.get_class(), str(g.get_path()).trim_prefix("/root/"), str(box.size), str(sp)])
	var ab := OS.get_environment("CHASE_AB")
	if ab == "":
		return
	for name in ab.split(",", false):
		var n: Node = tree.root.find_child(name, true, false)
		if not (n is Node3D or n is CanvasItem or n is CanvasLayer):
			print("CHASE_AB no node %s" % name)
			continue
		n.set("visible", false)
		for i in 3:
			await tree.process_frame
		tree.root.get_texture().get_image().save_png(out_dir.path_join("hide_%s.png" % name))
		n.set("visible", true)
		print("CHASE_AB hid %s (%s)" % [name, str(n.get_path())])
