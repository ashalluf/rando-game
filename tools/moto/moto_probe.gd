extends Node3D
## Motorcycle physics probe (seconds, headless): three bikes parked on a flat slab, then the sport
## bike ridden by a dummy driver with simulated input - throttle, a turn, a wheelie (boost), the
## brakes - printing speed, the body's roll and pitch, the drawn lean and wheelie, and where the
## tyres meet the ground.
##   godot --headless --path . res://tools/moto/moto_probe.tscn

var bikes: Array = []
var t := 0.0
var phase := 0
var driver: Node3D


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2000, 1, 2000)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	add_child(ground)
	for k in 3:
		var m := Motorcycle.make(Motorcycle.TYPES[k], k + 3)
		m.position = Vector3(k * 4.0, 0.6, 0.0)
		add_child(m)
		bikes.append(m)
	driver = Node3D.new()
	add_child(driver)
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color.RED, 0)
	car.position = Vector3(-10, 1, 0)
	add_child(car)
	bikes.append(car)


func _physics_process(delta: float) -> void:
	t += delta
	var m: Motorcycle = bikes[0]
	if phase == 0 and t > 3.0:
		for b in bikes.slice(0, 3):
			print("PARKED %s y=%.3f roll=%.3f up=%.3f lean=%.3f wheels_contact=%s sleeping=%s" % [b.display_name(), b.global_position.y, asin(b.global_basis.x.y), b.global_basis.y.y, b.lean, str([b.wheels[0].is_in_contact(), b.wheels[1].is_in_contact()]), b.sleeping])
		m.driver = driver
		bikes[3].driver = driver
		print("inertia ", PhysicsServer3D.body_get_direct_state(m.get_rid()).inverse_inertia, " mass ", m.mass)
		Input.action_press("move_forward")
		phase = 1
	elif phase == 1 and t > 7.0:
		Input.action_press("move_right")
		phase = 2
	elif phase == 2 and t > 10.0:
		Input.action_release("move_right")
		Input.action_press("boost")
		phase = 3
	elif phase == 3 and t > 12.0:
		Input.action_release("boost")
		Input.action_release("move_forward")
		Input.action_press("move_back")
		phase = 4
	elif phase == 4 and t > 16.0:
		Input.action_release("move_back")
		print("DONE")
		get_tree().quit()
	if Engine.get_physics_frames() % 30 == 0 and phase == 2:
		print("CAR yaw=%.3f steer=%.3f" % [bikes[3].global_rotation.y, bikes[3].steering])
	if Engine.get_physics_frames() % 15 == 0 and phase >= 1:
		var v := m.linear_velocity.dot(-m.global_basis.z)
		print("av=%s ws=%.3f skid=%.2f yaw=%.3f t=%.1f ph=%d v=%.1f roll=%.3f pitch=%.3f lean=%.3f wheelie=%.2f y=%.3f steer=%.2f contact=%s" % [str(m.angular_velocity), m.wheels[0].steering, m.wheels[0].get_skidinfo(), m.global_rotation.y, t, phase, v, asin(clampf(m.global_basis.x.y, -1, 1)), asin(clampf(-m.global_basis.z.y, -1, 1)), m.lean, m.wheelie, m.global_position.y, m.steering, str([m.wheels[0].is_in_contact(), m.wheels[1].is_in_contact()])])
