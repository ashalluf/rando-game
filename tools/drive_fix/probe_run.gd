extends RefCounted
## Body of tools/drive_fix/probe.gd (loaded once the autoloads exist).

var tree: SceneTree
var root: Node3D
var driver: Node3D
var player: Node
var mode := OS.get_environment("MODE")
var origin := Vector3(0, 1.0, 0) if OS.get_environment("MODE") == "" else Vector3(1200, 1.0, 1500)


func run(st: SceneTree) -> void:
	tree = st
	root = Node3D.new()
	if mode == "city":
		tree.current_scene.add_child(root)
		var police: Node = tree.current_scene.get_node_or_null("Police")
		if police:
			police.set("enabled", false)
		var ws: Node = tree.root.get_node("/root/WorldState")
		origin = ws.to_local(Vector3(2363.0, 0.0, 960.0)) + Vector3(0, 1.5, 0)
		for i in 60:
			await tree.process_frame
		_clear_traffic()
	else:
		tree.root.add_child(root)
	player = tree.get_first_node_in_group("player")
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000) if mode != "city" else Vector3(1, 1, 1)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	floor.add_child(cs)
	root.add_child(floor)
	driver = Node3D.new()
	root.add_child(driver)
	var types := OS.get_environment("TYPES")
	if types == "":
		types = "sedan,crossover,pickup,sports,moto,low"
	for t in types.split(","):
		await _probe(t)


func _make(t: String) -> Vehicle:
	match t:
		"moto":
			return Motorcycle.make(Vehicle.BodyType.MOTO_SPORT, 7)
		"low":
			return Lowrider.make(Vehicle.BodyType.LOWRIDER_HARDTOP, 7)
	var bt: int = Vehicle.BodyType.SEDAN
	match t:
		"crossover": bt = Vehicle.BodyType.CROSSOVER
		"pickup": bt = Vehicle.BodyType.PICKUP
		"sports": bt = Vehicle.BodyType.SPORTS
		"van": bt = Vehicle.BodyType.VAN
		"suv": bt = Vehicle.BodyType.SUV
		"muscle": bt = Vehicle.BodyType.MUSCLE
		"hatch": bt = Vehicle.BodyType.HATCHBACK
	var car := Vehicle.new()
	car.setup(bt, Color(0.5, 0.1, 0.1), Vehicle.Addon.NONE)
	return car


func _release() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "boost", "alt_fire", "jump"]:
		Input.action_release(a)


func _spawn(t: String) -> Vehicle:
	if mode == "city":
		_clear_traffic()
	var car := _make(t)
	root.add_child(car)
	car.global_transform = Transform3D(Basis(), origin)
	if mode != "" and player != null:
		player.enter_vehicle(car)
	else:
		car.driver = driver
	for i in 90:
		await tree.physics_frame
	return car


func _speed(car: Vehicle) -> float:
	return car.linear_velocity.dot(-car.global_basis.z)


func _probe(t: String) -> void:
	_release()
	# --- acceleration from rest -------------------------------------------------------------
	var car := await _spawn(t)
	Input.action_press("move_forward")
	var t60 := -1.0
	var tt := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var top := 0.0
	var drift := 0.0
	while tt < 25.0:
		await tree.physics_frame
		tt += dt
		var v := _speed(car)
		top = maxf(top, v)
		if t60 < 0.0 and v >= 27.78:
			t60 = tt
	drift = car.global_position.x - origin.x
	_release()
	print("DRIVE %s mass %.0f  0-100km/h %s s  speed@25s %.1f m/s (%.0f km/h)  sideways drift %.2f m  yaw %.1f deg" % [
		t, car.mass, ("%.2f" % t60) if t60 > 0 else "never", top, top * 3.6, drift, rad_to_deg(car.global_rotation.y)])
	_free(car)
	await tree.physics_frame
	# --- yaw rate left vs right at speeds -----------------------------------------------------
	for v0: float in [5.0, 15.0, 30.0]:
		var rates := []
		for act: String in ["move_left", "move_right"]:
			var c := await _spawn(t)
			c.linear_velocity = -c.global_basis.z * v0
			await tree.physics_frame
			Input.action_press(act)
			var yaw0 := 0.0
			var sum := 0.0
			var n := 0
			var lat := 0.0
			var vend := 0.0
			for i in 90: # 1.5 s
				# hold speed: a gentle velocity correction along the nose only
				var f := -c.global_basis.z
				var vf := c.linear_velocity.dot(f)
				c.linear_velocity += f * (v0 - vf) * 0.2
				await tree.physics_frame
				if i >= 45:
					sum += c.angular_velocity.y
					n += 1
					lat += absf(c.linear_velocity.dot(c.global_basis.x))
			vend = _speed(c)
			_release()
			rates.append(sum / maxf(n, 1))
			print("  %s v0 %.0f %s: yaw rate %.3f rad/s  steering %.3f  slip %.2f m/s  v %.1f" % [t, v0, act, sum / maxf(n, 1), c.steering, lat / maxf(n, 1), vend])
			_free(c)
			await tree.physics_frame
		var l: float = rates[0]
		var r: float = rates[1]
		print("YAW %s v0 %.0f left %.3f right %.3f  ratio %.2f" % [t, v0, l, r, absf(r) / maxf(absf(l), 0.001)])


func _free(c: Vehicle) -> void:
	if player != null and player.get("vehicle") == c:
		player.exit_vehicle()
	c.queue_free()


func _clear_traffic() -> void:
	var tm: Node = tree.current_scene.find_child("Traffic", true, false)
	if tm == null:
		return
	tm.set("staged", true)
	for c in tm.get("cars"):
		if is_instance_valid(c):
			c.queue_free()
	(tm.get("cars") as Array).clear()
