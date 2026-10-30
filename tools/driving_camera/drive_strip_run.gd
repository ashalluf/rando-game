extends RefCounted
## The body of tools/driving_camera/drive_strip.gd (loaded once the autoloads exist).

var tree: SceneTree
var out_dir: String
var prefix: String
var car: Vehicle
var player: Player
var city: Node
var ws: Node
## Flower St northbound, kerb lane, south of Olympic (true world).
const START := Vector3(2363.0, 0.0, 960.0)


func run(st: SceneTree) -> void:
	tree = st
	out_dir = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "build/drivecam"
	prefix = OS.get_environment("PREFIX")
	if not out_dir.begins_with("/"):
		out_dir = ProjectSettings.globalize_path("res://" + out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	city = tree.current_scene
	ws = tree.root.get_node("/root/WorldState")
	player = tree.get_first_node_in_group("player") as Player
	var police: Node = city.get_node_or_null("Police")
	if police:
		police.set("enabled", false)
	for i in 30:
		await tree.process_frame
	car = Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.55, 0.04, 0.05), Vehicle.Addon.NONE)
	city.add_child(car)
	# Through the traffic and the props: only the world stops it.
	car.collision_mask = 1
	await _place(START, 0.0)
	player.enter_vehicle(car)
	await _wait(1.5)
	var want := OS.get_environment("SCENARIOS")
	var all := ["s30", "s80", "s150", "corner", "jump"]
	for sc: String in all:
		if want != "" and not want.split(",").has(sc):
			continue
		print("STRIP ", sc)
		match sc:
			"s30":
				await _straight(30.0, sc)
			"s80":
				await _straight(80.0, sc)
			"s150":
				await _straight(150.0, sc)
			"corner":
				await _corner(sc)
			"jump":
				await _jump(sc)


func _straight(kmh: float, sc: String) -> void:
	var v := kmh / 3.6
	# Start far enough back that the shots are taken near Olympic, wherever the speed.
	await _place(START + Vector3(0.0, 0.0, v * 2.6), 0.0)
	await _run(v, 0.0, 1.6, [], sc)
	await _run(v, 0.0, 1.2, [0.0, 0.4, 0.8, 1.2], sc, 0)


func _corner(sc: String) -> void:
	var v := 35.0 / 3.6
	var r := 13.0
	# The arc starts at z = (Olympic's eastbound lane) + r and ends heading east.
	var turn_z := 883.5 + r
	await _place(Vector3(START.x, 0.0, turn_z + v * 2.2), 0.0)
	await _run(v, 0.0, 2.2, [1.9], sc, 0)
	var quarter := (PI * 0.5) * r / v
	await _run(v, -v / r, quarter, [quarter * 0.35, quarter * 0.7, quarter], sc, 1)
	await _run(v, 0.0, 0.6, [0.5], sc, 4)


func _jump(sc: String) -> void:
	var v := 80.0 / 3.6
	await _place(START + Vector3(0.0, 0.0, v * 3.2), 0.0)
	await _run(v, 0.0, 1.4, [], sc)
	car.linear_velocity.y = 9.0
	car.hold_crash_watch(4)
	var landed := -1.0
	var t := 0.0
	var n := 0
	var shots := [0.3, 0.9]
	while t < 3.0:
		_steer(v, 0.0, true)
		await tree.physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if n < shots.size() and t >= float(shots[n]):
			await _shot(sc, n)
			n += 1
		if landed < 0.0 and t > 0.4 and _grounded():
			landed = t
			print("STRIP jump landed after %.2f s" % t)
		if landed >= 0.0 and n == 2 and t >= landed + 0.06:
			await _shot(sc, 2)
			n = 3
		if landed >= 0.0 and n == 3 and t >= landed + 0.22:
			await _shot(sc, 3)
			break


func _grounded() -> bool:
	for c in car.get_children():
		if c is VehicleWheel3D and (c as VehicleWheel3D).is_in_contact():
			return true
	return false


## Drives `seconds` at `v` m/s turning `yaw_rate`, taking a still at each of `at` (seconds in).
func _run(v: float, yaw_rate: float, seconds: float, at: Array, sc: String, first: int = 0) -> void:
	var t := 0.0
	var n := 0
	tree.root.disable_3d = true
	while t < seconds - 0.0001:
		_steer(v, yaw_rate, false)
		await tree.physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if n < at.size() and t >= float(at[n]) - 0.0001:
			await _shot(sc, first + n)
			n += 1


func _steer(v: float, yaw_rate: float, air: bool) -> void:
	var f := -car.global_basis.z
	f.y = 0.0
	f = f.normalized()
	car.linear_velocity = Vector3(f.x * v, car.linear_velocity.y, f.z * v)
	if not air:
		car.angular_velocity = Vector3(car.angular_velocity.x * 0.5, yaw_rate, car.angular_velocity.z * 0.5)
	car.hold_crash_watch(2)


func _place(world: Vector3, yaw: float) -> void:
	var p: Vector3 = ws.call("to_local", world)
	player.global_position = p + Vector3.UP * 2.0
	city.call("update_streaming", true)
	for i in 4:
		await tree.process_frame
	var plan: CityPlan = city.get("plan")
	var gy := plan.height_at(Vector2(world.x, world.z)) if plan else 0.0
	var at: Vector3 = ws.call("to_local", Vector3(world.x, gy + 0.9, world.z))
	car.hold_crash_watch(6)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	city.call("update_streaming", true)
	await _wait(0.6)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await tree.process_frame
		t += tree.root.get_process_delta_time()


func _shot(sc: String, n: int) -> void:
	tree.root.disable_3d = false
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := tree.root.get_texture().get_image()
	var dc: Variant = player.camera_rig.get("drive")
	var info := ""
	if dc != null:
		info = "speed %.0f km/h, lag %.1f deg, dist %.2f m, fov +%.1f" % [dc.speed * 3.6, dc.lag_deg, dc.distance, dc.fov_add]
	var path := "%s/%s%s_%d.jpg" % [out_dir, prefix, sc, n]
	img.save_jpg(path, 0.88)
	print("STRIP shot %s  %s  cam fov %.1f" % [path, info, player.camera.fov])
	tree.root.disable_3d = true
