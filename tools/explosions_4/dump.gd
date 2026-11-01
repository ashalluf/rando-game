extends SceneTree
## Lists every node a blast added (name, class, global position) after T seconds: a quick way to
## find which layer draws what in a still. Headless:
##   godot --headless --path . --script tools/explosions_4/dump.gd   (T=0.1, CAR=1)

func _initialize() -> void:
	var level: Node = (load("res://scenes/levels/test_box.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for i in 4:
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	var before := {}
	for n in _all(root):
		before[n] = true
	var at := player.global_position + Vector3(0, 0.6, -30)
	if OS.get_environment("CAR") == "1":
		var car: Node3D = load("res://scripts/vehicles/vehicle.gd").random_car(RandomNumberGenerator.new())
		root.add_child(car)
		car.global_position = at + Vector3(0.0, 0.8, 0.0)
		for i in 6:
			await physics_frame
		for n in _all(root):
			before[n] = true
		car.call("damage_state").explode()
	else:
		load("res://scripts/weapons/explosion.gd").blast(player, at, 9.0, 30.0, 0.0)
	var want := float(OS.get_environment("T")) if OS.get_environment("T") != "" else 0.1
	var el := 0.0
	while el < want:
		await process_frame
		el += root.get_process_delta_time()
	for n in _all(root):
		if before.has(n) or not (n is Node3D):
			continue
		var p := (n as Node3D).global_position - at
		var extra := ""
		if n is CPUParticles3D:
			extra = " emit=%s amount=%d vis=%s" % [(n as CPUParticles3D).emitting, (n as CPUParticles3D).amount, (n as Node3D).visible]
		print("NODE %s %s rel=(%.1f, %.1f, %.1f)%s" % [n.get_path(), n.get_class(), p.x, p.y, p.z, extra])
	quit()


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
