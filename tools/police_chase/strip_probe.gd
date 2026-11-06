extends Node3D
## A car rolled over a spike strip on a flat slab, alone (seconds, headless):
##   godot --headless --path . tools/police_chase/strip_probe.tscn
## Prints the car's speed, the strip's watch list and the flats as it crosses.

func _ready() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	ground.add_child(cs)
	add_child(ground)
	ground.position = Vector3(0, -0.5, 0)
	var strip := ChaseSpikeStrip.new()
	strip.length = 7.0
	add_child(strip)
	strip.deploy()
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color.RED, Vehicle.Addon.NONE)
	add_child(car)
	car.global_position = Vector3(0, 0.9, 14)
	for i in 20:
		await get_tree().physics_frame
	car.linear_velocity = Vector3.FORWARD * 14.0
	for i in 150:
		if i > 0 and ChaseFlatTyres.flats(car) > 0 and i % 5 == 0:
			print("  y %.3f vy %.2f" % [car.global_position.y, car.linear_velocity.y])
		await get_tree().physics_frame
		if i % 10 == 0 or ChaseFlatTyres.flats(car) > 0:
			print("t%d z %.2f v %.1f watch %d flats %d wheels %d sleeping %s" % [i, car.global_position.z, car.linear_velocity.length(), strip._watch.size(), ChaseFlatTyres.flats(car), car.wheels.size(), car.sleeping])
		if ChaseFlatTyres.flats(car) >= 4 and i > 140:
			break
	get_tree().quit()
