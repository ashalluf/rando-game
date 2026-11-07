extends Node3D
## Drive-train probe (headless, about a minute): one of each body type on a flat 4 km slab, all
## driven at once by the same simulated input (Input.action_press): full throttle for `RUN` s,
## then lift off (coast + engine braking), then the brakes to a stop and reverse. Prints per car:
## 0-60 / 0-100 / 0-160 km/h, speed after 5 and 10 s, top speed, the coast-down decel from top
## speed, reverse top speed, and the drive-train's gear / rpm at the end of the run.
##   godot --headless --fixed-fps 60 --path . res://tools/drive_engine/probe.tscn
##   DRIVETRAIN=0 ... (the A/B)    PROBE_TYPES=0,8,3 (body types)    PROBE_BOOST=1 (nitro held)
##   PROBE_RUN=40 (seconds of throttle)

const DEFAULT_TYPES := [0, 8, 14, 1, 2, 3, 4, 6, 36, 15, 25, 9, 10, 11, 27, 29]
var cars: Array = []
var rec: Array = []
var t := 0.0
var phase := 0
var run := 40.0
var driver: Node3D


func _ready() -> void:
	run = float(OS.get_environment("PROBE_RUN")) if OS.get_environment("PROBE_RUN") != "" else 40.0
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1200, 1, 6000)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, -2800)
	ground.add_child(cs)
	add_child(ground)
	driver = Node3D.new()
	add_child(driver)
	var types: Array = DEFAULT_TYPES
	if OS.get_environment("PROBE_TYPES") != "":
		types = []
		for s in OS.get_environment("PROBE_TYPES").split(","):
			types.append(int(s))
	var i := 0
	for ty: int in types:
		var car: Vehicle
		if ty >= Vehicle.BodyType.MOTO_SPORT and ty <= Vehicle.BodyType.MOTO_SCOOTER:
			car = Motorcycle.make(ty, 3)
		elif BigVehicles.is_big(ty) and ty in [9, 10, 11]:
			car = BigVehicles.make(ty, 1)
		else:
			car = Vehicle.new()
			car.setup(ty, Color(0.6, 0.1, 0.1), Vehicle.Addon.NONE)
		car.position = Vector3((i - types.size() * 0.5) * 14.0, 1.2, 0.0)
		add_child(car)
		cars.append(car)
		rec.append({"t60": -1.0, "t100": -1.0, "t160": -1.0, "v5": 0.0, "v10": 0.0, "top": 0.0,
			"coast": 0.0, "rev": 0.0, "ty": ty, "shifts": 0})
		i += 1


func _physics_process(delta: float) -> void:
	t += delta
	if phase == 0 and t > 2.5:
		for c: Vehicle in cars:
			c.set_meta("drive_train_test", true)
			c.driver = driver
		Input.action_press("move_forward")
		if OS.get_environment("PROBE_BOOST") == "1":
			Input.action_press("boost")
		phase = 1
		t = 0.0
	elif phase == 1:
		for k in cars.size():
			var c: Vehicle = cars[k]
			var r: Dictionary = rec[k]
			var kmh := c.linear_velocity.dot(-c.global_basis.z) * 3.6
			if r.t60 < 0.0 and kmh >= 60.0: r.t60 = t
			if r.t100 < 0.0 and kmh >= 100.0: r.t100 = t
			if r.t160 < 0.0 and kmh >= 160.0: r.t160 = t
			if absf(t - 5.0) < delta * 0.5: r.v5 = kmh
			if absf(t - 10.0) < delta * 0.5: r.v10 = kmh
			r.top = maxf(r.top, kmh)
			if k == 0 and OS.get_environment("PROBE_LOG") == "1" and Engine.get_physics_frames() % 30 == 0:
				var st: Variant = DriveTrain.state_of(c)
				var acc := (kmh / 3.6 - float(r.get("lastv", 0.0))) / 0.5
				r.lastv = kmh / 3.6
				print("LOG t=%.1f v=%.1f acc=%.2f ef=%.0f br=%.2f gear=%s want=%.2f skid=%.2f contact=%s damp=%.2f" % [t, kmh / 3.6, acc, c.engine_force, c.brake,
					str(int(st.gear) + 1) if st != null else "-", (float(st.force) * 4.0 / c.mass) if st != null else 0.0,
					c.wheels[0].get_skidinfo(), str(c.wheels[0].is_in_contact()), PhysicsServer3D.body_get_direct_state(c.get_rid()).total_linear_damp])
		if t > run:
			Input.action_release("move_forward")
			Input.action_release("boost")
			for k in cars.size():
				rec[k]["vlift"] = cars[k].linear_velocity.length() * 3.6
				var dt_st: Variant = DriveTrain.state_of(cars[k]) if DriveTrain.enabled else null
				rec[k]["gear"] = int(dt_st.gear) + 1 if dt_st != null else 0
				rec[k]["rpm"] = float(dt_st.rpm) if dt_st != null else 0.0
				rec[k]["shifts"] = int(dt_st.shifts) if dt_st != null else 0
			phase = 2
			t = 0.0
	elif phase == 2 and t > 3.0:
		for k in cars.size():
			var v: float = cars[k].linear_velocity.length() * 3.6
			rec[k]["coast"] = (float(rec[k]["vlift"]) - v) / 3.6 / 3.0
		Input.action_press("move_back")
		phase = 3
		t = 0.0
	elif phase == 3:
		for k in cars.size():
			var c: Vehicle = cars[k]
			var kmh := c.linear_velocity.dot(-c.global_basis.z) * 3.6
			rec[k]["rev"] = minf(float(rec[k]["rev"]), kmh)
		if t > 25.0:
			Input.action_release("move_back")
			_report()
			get_tree().quit()


func _f(x: float) -> String:
	return "  -  " if x < 0.0 else "%5.2f" % x


func _report() -> void:
	print("DRIVE_PROBE drivetrain=%s boost=%s" % [str(DriveTrain.enabled), OS.get_environment("PROBE_BOOST")])
	print("%-18s %6s %6s %6s %6s %6s %6s %7s %6s %4s %5s %4s" % ["body", "mass", "0-60", "0-100", "0-160", "v5s", "v10s", "top", "coast", "rev", "rpm", "gear"])
	for k in cars.size():
		var r: Dictionary = rec[k]
		var c: Vehicle = cars[k]
		print("DRIVE %-15s %6.0f %s %s %s %6.1f %6.1f %7.1f %6.2f %4.0f %5.0f %4d" % [c.display_name(), c.mass,
			_f(r.t60), _f(r.t100), _f(r.t160), r.v5, r.v10, r.top, r.coast, -float(r.rev), float(r.rpm), int(r.gear)])
