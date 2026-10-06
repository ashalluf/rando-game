extends SceneTree
## Drops a car, lets it settle, then drops it again from height, and prints the physics hub
## height against the VISIBLE wheel node's height each frame. The two have to move together: if
## the visible column never changes the wheels are welded to the body and every landing pushes
## the tyres through the road.
##
##   godot --headless --path . --script tools/glshot/wheel_travel_probe.gd -- --type=0
func _initialize() -> void:
	var only := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--type="):
			only = arg.trim_prefix("--type=").to_int()
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)
	await process_frame
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400.0, 2.0, 400.0)
	cs.shape = bs
	cs.position.y = -1.0
	ground.add_child(cs)
	world.add_child(ground)
	# A camera, because the visible wheels only update within Vehicle.wheel_draw_distance.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.0, 10.0)
	world.add_child(cam)
	cam.current = true
	var script: GDScript = load("res://scripts/vehicles/vehicle.gd")
	var car: Node3D = script.new()
	car.call("setup", only, Color(0.7, 0.13, 0.11), 0)
	car.position = Vector3(0.0, 0.9, 0.0)
	world.add_child(car)
	for i in 180:
		await physics_frame
	var wheels: Array = car.get("wheels")
	var rigs: Array = car.get("_wheel_rigs")
	print("type %d: %d physics wheels, %d visible rigs" % [only, wheels.size(), rigs.size()])
	var rest_hub: float = (wheels[0] as Node3D).position.y
	var rest_vis: float = (rigs[0][0] as Node3D).position.y
	print("at rest: hub y %.4f  visible y %.4f" % [rest_hub, rest_vis])
	# Now throw it in the air and watch the front left wheel through the landing.
	car.set("linear_velocity", Vector3(0.0, 9.0, 0.0))
	var lo := 9.0
	var hi := -9.0
	for i in 200:
		await physics_frame
		var d: float = (rigs[0][0] as Node3D).position.y - rest_vis
		lo = minf(lo, d)
		hi = maxf(hi, d)
		if i % 20 == 0:
			print("  f%3d body y %.2f  hub %+.4f  visible %+.4f" % [i, (car as Node3D).position.y,
					(wheels[0] as Node3D).position.y - rest_hub, d])
	print("visible wheel travelled %.4f m down, %.4f m up around its resting height" % [lo, hi])
	quit()
