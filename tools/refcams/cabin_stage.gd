extends RefCounted
## The "cabin" staging of a reference camera (tools/refcams/cameras_w8.json, driver_rain): the
## player at the wheel of his own car, STOPPED in a queue at a red on a downtown street, and the
## shot taken from a free eye inside the cabin just behind the driver's head (the car's own frame:
## x right, y up from the road, -z ahead). Loaded by path from refcams_shot.gd once the autoloads
## exist (it names Vehicle and Player). Same interface as chase_stage.gd: run(), hold(), debug(),
## finish().
##
## The camera row's "cabin" key (every field optional but road):
##   {"axis": 0, "x": 2610.8,          the road: AXIS_X (0) at that x, or AXIS_Z (1) at "z"
##    "dir": -1, "lane": 0,            dir -1 = toward -along; lane 0 = by the centre line
##    "near": 700.0,                   the junction ahead is the first crossing past this (TRUE world along)
##    "queue": 1,                      cars standing ahead of him at the stop line (same lane)
##    "beside": 1,                     cars standing in the other lane (0 / 1 / 2)
##    "cross": [[dir, lane, offset, kmh, body or ""], ...]   cars running through on the cross road's green
##    "eye": [x, y, z],                the eye from the driver's head (CarCabin's measured front seat:
##                                     x right, y up, z back, metres in the car's frame)
##    "look": [x, y, z],               the point looked at, from the head the same way (-z ahead)
##    "body": "SEDAN", "paint": [r, g, b]}   (a body CarInteriors builds a real cabin for)
## The light for his axis is forced red every frame (TrafficSignals.force), so the queue stands and
## the cross street runs. TrafficManager.staged keeps the upkeep from shedding the placed cars.

var tree: SceneTree
var city: Node
var player: Player
var car: Vehicle
var traffic: Node
var plan: CityPlan
var _police_was := true
var _staged_was := false
var _placed: Array = []
var _fov := 62.0
var _eye := Vector3(0.12, 0.06, 0.42)
var _look := Vector3(0.25, -0.35, -8.0)
## The driver's head in the body mesh's space and that mesh (CarCabin.for_car()).
var _head := Vector3.ZERO
var _mesh: MeshInstance3D = null
var _jx := 0
var _jz := 0
var _axis := 0


func run(st: SceneTree, cam: Dictionary, p: Node3D) -> void:
	tree = st
	city = tree.current_scene
	player = p as Player
	_fov = float(cam.get("fov", 62.0))
	var d: Dictionary = cam.get("cabin", {})
	plan = city.get("plan")
	_axis = int(d.get("axis", CityPlan.AXIS_X))
	var road_at := float(d.get("x", d.get("z", 0.0)))
	var index := _road_index(plan, _axis, road_at)
	var dir := int(d.get("dir", -1))
	var lane_n := int(d.get("lane", 0))
	var near := float(d.get("near", 0.0))
	if d.has("eye"):
		var e: Array = d.eye
		_eye = Vector3(float(e[0]), float(e[1]), float(e[2]))
	if d.has("look"):
		var l: Array = d.look
		_look = Vector3(float(l[0]), float(l[1]), float(l[2]))
	var police: Node = city.get_node_or_null("Police")
	if police:
		_police_was = bool(police.get("enabled"))
		police.set("enabled", false)
	traffic = city.get_node_or_null("Traffic")
	if traffic:
		_staged_was = bool(traffic.get("staged"))
		traffic.set("staged", true)
	# The crossing ahead: the first road of the other axis past `near` in the travel direction.
	var other := 1 - _axis
	var k := _road_index(plan, other, near)
	for i in 6:
		var pos := plan.road_pos(other, k)
		if (pos - near) * float(dir) > 0.0:
			break
		k += dir
	var cross_pos := plan.road_pos(other, k)
	var cross_w := plan.road_width(other, k)
	if _axis == CityPlan.AXIS_X:
		_jx = index
		_jz = k
	else:
		_jx = k
		_jz = index
	TrafficSignals.force(plan, _jx, _jz, _axis, TrafficSignals.Light.RED, 2.0)
	# The stop line: the crossing road's near kerb less a couple of metres; the queue behind it.
	var line := cross_pos - float(dir) * (cross_w * 0.5 + 2.2)
	var queue := int(d.get("queue", 1))
	var gap := 7.0
	var my_along := line - float(dir) * (2.6 + gap * float(queue))
	var width := plan.road_width(_axis, index)
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	var side := -dir if _axis == CityPlan.AXIS_X else dir
	var lane := float(side) * CityPlan.lane_center(width, lanes, clampi(lane_n, 0, lanes - 1))
	var rp := plan.road_pos(_axis, index) + lane
	var start := Vector3(rp, 0.0, my_along) if _axis == CityPlan.AXIS_X else Vector3(my_along, 0.0, rp)
	var fwd := Vector3(0, 0, dir) if _axis == CityPlan.AXIS_X else Vector3(dir, 0, 0)
	var yaw := atan2(-fwd.x, -fwd.z)
	car = Vehicle.new()
	var body_name := String(d.get("body", "SEDAN"))
	var body: int = Vehicle.BodyType.get(body_name, Vehicle.BodyType.SEDAN)
	var pc: Array = d.get("paint", [0.06, 0.07, 0.08])
	car.setup(body, Color(float(pc[0]), float(pc[1]), float(pc[2])), Vehicle.Addon.NONE)
	car.name = "CabinCar"
	city.add_child(car)
	car.collision_mask = 1
	await _place(start, yaw)
	player.visible = true
	player.enter_vehicle(car)
	if traffic:
		# Standing in his lane at the line, standing beside him, and the cross street on green.
		for q in queue:
			var a := line - float(dir) * (2.6 + gap * float(q))
			_put(traffic.call("place_car", _axis, index, dir, lane_n, a, 0.0, false, -1))
		var other_lane := 1 - lane_n if lanes > 1 else lane_n
		var beside := int(d.get("beside", 1)) if lanes > 1 else 0
		for q in beside:
			var a := line - float(dir) * (2.6 + gap * float(q))
			_put(traffic.call("place_car", _axis, index, dir, other_lane, a, 0.0, false, -1))
		var mine := plan.road_pos(_axis, index)
		for row: Array in d.get("cross", []):
			var kind := -1
			if row.size() > 4 and String(row[4]) != "":
				kind = Vehicle.BodyType.get(String(row[4]), -1)
			_put(traffic.call("place_car", other, k, int(row[0]), int(row[1]), mine + float(row[2]), float(row[3]) / 3.6, false, kind))
	# A second to settle on the springs, the wipers, the lamps on; then until the real cabin is up
	# (CarInteriors splits the doors on a worker thread).
	var t := 0.0
	var rig := false
	while t < 1.6 or (not rig and t < 30.0):
		_hold_still()
		await tree.physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var ci: Node = tree.root.get_node_or_null("CarInteriors")
		rig = ci != null and (ci.get("rigs") as Dictionary).has(car.get_instance_id())
	_find_head()
	hold()
	print("REFCAM cabin: %s on road %d at %s, junction (%d, %d) line %.1f, %d cars placed, interior %s after %.1f s, head %s" % [body_name, index, str(WorldState.to_world(car.global_position)), _jx, _jz, line, _placed.size(), str(rig), t, str(_head)])


func _put(c: Variant) -> void:
	if c:
		_placed.append(c)


## Holds him at the line and the free eye in the cabin (refcams' SETTLE frames).
func hold() -> void:
	if not is_instance_valid(car):
		return
	_hold_still()
	TrafficSignals.force(plan, _jx, _jz, _axis, TrafficSignals.Light.RED, 2.0)
	var b := car.global_transform.basis.orthonormalized()
	var head := _mesh.global_transform * _head if is_instance_valid(_mesh) else car.global_transform * Vector3(-0.37, 1.15, 0.2)
	var at := head + b * _eye
	var to := head + b * _look
	OS.set_environment("EYE", "%.3f,%.3f,%.3f,0,0" % [WorldState.to_world(at).x, WorldState.to_world(at).y, WorldState.to_world(at).z])
	OS.set_environment("EYE_KEEP_PLAYER", "1")
	OS.set_environment("EYE_AGL", "")
	tree.call("_eye", player, _fov)
	var cam: Camera3D = tree.get("_eye_cam")
	if cam:
		cam.near = 0.02
		cam.global_transform = Transform3D.IDENTITY.translated(at).looking_at(to, b.y)
		cam.make_current()


## The driver's head where CarCabin traces the driver (car_glass_open.gdshader's people_view):
## his seat's x, the crown just under the side glass's top, the front seat row.
func _find_head() -> void:
	var data := CarCabin.for_car(car)
	for m in car._body_meshes:
		if is_instance_valid(m) and not String(m.name).ends_with("_far"):
			_mesh = m
			break
	var lo: Vector3 = data.cabin_lo
	var hi: Vector3 = data.cabin_hi
	var cx := (lo.x + hi.x) * 0.5
	var half_w := (hi.x - lo.x) * 0.5
	var sx := cx + float(data.driver_side) * (half_w + 0.03) * 0.5
	var sz: Vector2 = data.seat_z
	_head = Vector3(sx, float(data.side_top) - 0.12, sz.x)


func _hold_still() -> void:
	car.linear_velocity = Vector3(0.0, car.linear_velocity.y, 0.0)
	car.angular_velocity = Vector3(car.angular_velocity.x * 0.5, 0.0, car.angular_velocity.z * 0.5)
	car.hold_crash_watch(2)


func debug(_out_dir: String) -> void:
	pass


func finish() -> void:
	OS.set_environment("EYE_KEEP_PLAYER", "")
	if is_instance_valid(car):
		if player.get("vehicle") == car:
			player.exit_vehicle()
		car.queue_free()
	for c in _placed:
		if is_instance_valid(c):
			(c as Node).queue_free()
	if traffic:
		traffic.set("staged", _staged_was)
	var police: Node = city.get_node_or_null("Police")
	if police:
		police.set("enabled", _police_was)


func _road_index(p: CityPlan, axis: int, at: float) -> int:
	var i := p.block_index_at(Vector2(at, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, at))
	var k := i.x if axis == CityPlan.AXIS_X else i.y
	var best := k
	for j in range(k - 2, k + 3):
		if absf(p.road_pos(axis, j) - at) < absf(p.road_pos(axis, best) - at):
			best = j
	return best


func _place(world: Vector3, yaw: float) -> void:
	player.global_position = WorldState.to_local(world) + Vector3.UP * 2.0
	city.call("update_streaming", true)
	for i in 4:
		await tree.process_frame
	var gy := plan.height_at(Vector2(world.x, world.z))
	var top := WorldState.to_local(Vector3(world.x, gy + 40.0, world.z))
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 80.0, 1)
	q.exclude = [car.get_rid(), player.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		gy = WorldState.to_world(hit.position).y
	car.hold_crash_watch(6)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), WorldState.to_local(Vector3(world.x, gy + 0.6, world.z)))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	city.call("update_streaming", true)
	var t := 0.0
	while t < 0.6:
		await tree.process_frame
		t += tree.root.get_process_delta_time()
