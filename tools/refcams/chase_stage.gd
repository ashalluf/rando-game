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
var _under: Array = []
var _box: Array = []


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
	var dbg := OS.get_environment("CHASE_DEBUG") == "1"
	while t < seconds - 0.0001:
		_steer(v)
		await tree.physics_frame
		if dbg:
			var st := PhysicsServer3D.body_get_direct_state(car.get_rid())
			for i in st.get_contact_count():
				var o: Object = st.get_contact_collider_object(i)
				print("CHASE_TICK %.2f contact %s local %s" % [t, str(o.get_path()) if o is Node else str(o), str(st.get_contact_local_position(i) - st.transform.origin)])
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
	# The road's real top by a ray (plan.height_at() is the relief, which downtown's hills and the
	# street slabs do not follow exactly: a car dropped from it sat sunk in the GroundBody box and
	# scraped it, sparking, the whole drive).
	var gy := plan.height_at(Vector2(world.x, world.z))
	var top := WorldState.to_local(Vector3(world.x, gy + 40.0, world.z))
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 80.0, 1)
	q.exclude = [car.get_rid(), player.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		print("REFCAM drive: road top %.3f (plan %.3f) under %s" % [WorldState.to_world(hit.position).y, gy, str(hit.collider.get_path() if hit.collider is Node else hit.collider)])
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


## CHASE_DEBUG=1: what is drawn round the car that is not the car (a census of small geometry and
## every particle system within 30 m, with where it lands on screen), and CHASE_AB=a,b,... renders
## the frame again with each named node under the root or the scene hidden (<name>.png in out).
func debug(out_dir: String) -> void:
	if OS.get_environment("CHASE_DEBUG") == "1":
		var st := PhysicsServer3D.body_get_direct_state(car.get_rid())
		print("CHASE_CONTACTS %d monitor %s mask %d layer %d" % [st.get_contact_count(), str(car.contact_monitor), car.collision_mask, car.collision_layer])
		for i in st.get_contact_count():
			var o: Object = st.get_contact_collider_object(i)
			print("CHASE_CONTACT %s local %s normal %s" % [str(o.get_path()) if o is Node else str(o), str(st.get_contact_local_position(i) - st.transform.origin), str(st.get_contact_local_normal(i))])
		for c in car.find_children("*", "GeometryInstance3D", true, false):
			var gi := c as GeometryInstance3D
			if gi.is_visible_in_tree():
				var mat: Variant = gi.material_override
				print("CHASE_PART %s %s aabb %s mat %s" % [gi.get_class(), str(car.get_path_to(gi)), str(gi.get_aabb()), str(mat.resource_path if mat else "")])
		# Everything drawn where the box beside the rear bumper shows (CHASE_AB=box:*).
		var probes := [car.global_transform * Vector3(1.2, 0.45, 2.4), car.global_transform * Vector3(-1.2, 0.45, 2.4), car.global_transform * Vector3(1.15, 0.6, 1.8)]
		var cam_p := player.camera.global_position
		for n in tree.root.find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if not g.is_visible_in_tree():
				continue
			var gb := g.global_transform * g.get_aabb()
			if gb.size.length() > 200.0:
				continue
			var hitp := false
			for pr: Vector3 in probes:
				# Anything on the line from the camera to the probe.
				for k in 9:
					if gb.grow(0.05).has_point(cam_p.lerp(pr, 0.2 + 0.1 * k)):
						hitp = true
			if hitp:
				_box.append(g)
				print("CHASE_BOX %s %s size %s" % [g.get_class(), str(g.get_path()), str(gb.size)])
		var ground := car.global_position + Vector3.DOWN * 0.4
		var cover := []
		for n in tree.root.find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if not g.is_visible_in_tree() or car.is_ancestor_of(g):
				continue
			var gb := g.global_transform * g.get_aabb()
			if gb.grow(0.5).has_point(ground) or gb.grow(0.5).has_point(ground + car.global_basis.z * 3.0):
				var sh := ""
				var m: Material = g.material_override
				if m == null and g is MeshInstance3D and (g as MeshInstance3D).mesh and (g as MeshInstance3D).mesh.get_surface_count() > 0:
					m = (g as MeshInstance3D).mesh.surface_get_material(0)
				if m is ShaderMaterial and (m as ShaderMaterial).shader:
					sh = (m as ShaderMaterial).shader.resource_path
				_under.append(g)
				print("CHASE_UNDER %s %s size %s shader %s" % [g.get_class(), str(g.get_path()), str(gb.size), sh])
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
	if OS.get_environment("CHASE_BISECT") == "1":
		await _bisect(out_dir)
	var ab := OS.get_environment("CHASE_AB")
	if ab == "":
		return
	var names := []
	for name in ab.split(",", false):
		if name == "2d:*":
			for n in tree.root.find_children("*", "CanvasLayer", true, false):
				if (n as CanvasLayer).visible:
					names.append("path:" + str(n.get_path()))
			continue
		if name == "decal:*":
			for n in tree.root.find_children("*", "VisualInstance3D", true, false):
				if not (n is GeometryInstance3D) and (n as Node3D).is_visible_in_tree() and (n as Node3D).global_position.distance_to(car.global_position) < 30.0:
					print("CHASE_VI %s %s at %s" % [n.get_class(), str(n.get_path()), str((n as Node3D).global_position - car.global_position)])
					names.append("path:" + str(n.get_path()))
			continue
		if name == "lights:*":
			for n in tree.root.find_children("*", "Light3D", true, false):
				if (n as Node3D).is_visible_in_tree() and (n as Node3D).global_position.distance_to(car.global_position) < 25.0:
					names.append("path:" + str(n.get_path()))
			continue
		if name == "root:*":
			for n in tree.root.get_children():
				if n is Node3D and n != city and (n as Node3D).visible:
					names.append("path:" + str(n.get_path()))
			continue
		if name == "cam:*":
			# Everything under the player that draws (the camera rig, the body, its effects).
			for n in player.find_children("*", "Node3D", true, false):
				if (n is GeometryInstance3D or n is Decal or n is Light3D) and (n as Node3D).is_visible_in_tree():
					names.append("path:" + str(n.get_path()))
			for n in player.camera.find_children("*", "Node", true, false):
				if n is CanvasItem or n is CanvasLayer:
					names.append("path:" + str(n.get_path()))
			continue
		if name == "fx:*":
			for n in tree.root.find_children("*", "GeometryInstance3D", true, false):
				if (n is CPUParticles3D or n is GPUParticles3D) and (n as Node3D).is_visible_in_tree() and bool(n.get("emitting")) and (n as Node3D).global_position.distance_to(car.global_position) < 40.0:
					names.append("path:" + str(n.get_path()))
			continue
		if name == "box:*":
			for g in _box:
				names.append("path:" + str(g.get_path()))
			continue
		if name == "under:*":
			for g in _under:
				names.append("path:" + str(g.get_path()))
			continue
		if name == "car:*":
			for c in car.get_children():
				if c is Node3D and (c as Node3D).visible:
					names.append("car:" + String(c.name))
		else:
			names.append(name)
	for name: String in names:
		if name.begins_with("dbg:"):
			var mode: int = {"unshaded": Viewport.DEBUG_DRAW_UNSHADED, "wireframe": Viewport.DEBUG_DRAW_WIREFRAME, "overdraw": Viewport.DEBUG_DRAW_OVERDRAW, "lighting": Viewport.DEBUG_DRAW_LIGHTING}.get(name.substr(4), 0)
			tree.root.debug_draw = mode
			for i in 3:
				await tree.process_frame
			tree.root.get_texture().get_image().save_png(out_dir.path_join("dbg_%s.png" % name.substr(4)))
			tree.root.debug_draw = Viewport.DEBUG_DRAW_DISABLED
			print("CHASE_AB debug draw %s" % name)
			continue
		var n: Node = car.get_node_or_null(name.substr(4)) if name.begins_with("car:") else (tree.root.get_node_or_null(name.substr(5)) if name.begins_with("path:") else tree.root.find_child(name, true, false))
		if not (n is Node3D or n is CanvasItem or n is CanvasLayer):
			print("CHASE_AB skip %s" % name)
			print("CHASE_AB no node %s" % name)
			continue
		n.set("visible", false)
		for i in 3:
			await tree.process_frame
		tree.root.get_texture().get_image().save_png(out_dir.path_join("hide_%s.png" % name.validate_filename()))
		n.set("visible", true)
		print("CHASE_AB hid %s (%s)" % [name, str(n.get_path())])


## CHASE_BISECT=1: finds what draws the pale box behind the car by halving the set of visible
## drawables until one is left (the box measured as the road's brightness inside it minus outside).
func _box_level() -> float:
	for i in 3:
		await tree.process_frame
	var img := tree.root.get_texture().get_image()
	var sc := Vector2(img.get_width(), img.get_height()) / Vector2(1280.0, 720.0)
	var a := img.get_pixel(int(540 * sc.x), int(510 * sc.y))
	var b := img.get_pixel(int(520 * sc.x), int(510 * sc.y))
	return (a.r + a.g + a.b - b.r - b.g - b.b) * 255.0 / 3.0


func _bisect(out_dir: String) -> void:
	var all: Array = []
	for n in tree.root.find_children("*", "VisualInstance3D", true, false):
		if (n as Node3D).is_visible_in_tree():
			all.append(n)
	var base: float = await _box_level()
	print("CHASE_BISECT %d drawables, box %.1f" % [all.size(), base])
	var cand := all
	while cand.size() > 1:
		var half := cand.slice(0, cand.size() / 2)
		for n in half:
			(n as Node3D).visible = false
		var lvl: float = await _box_level()
		for n in half:
			(n as Node3D).visible = true
		print("CHASE_BISECT %d hidden -> box %.1f" % [half.size(), lvl])
		cand = half if lvl < base * 0.6 else cand.slice(cand.size() / 2)
	if cand.size() == 1:
		var n: Node3D = cand[0]
		n.visible = false
		var lvl: float = await _box_level()
		tree.root.get_texture().get_image().save_png(out_dir.path_join("bisect_hidden.png"))
		n.visible = true
		print("CHASE_BISECT found %s %s (box %.1f -> %.1f)" % [n.get_class(), str(n.get_path()), base, lvl])
