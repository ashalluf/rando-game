extends RefCounted
## The "stunt_jump" reference camera's staging (tools/refcams/cameras_w8.json, `"stage": "stunt"`):
## a car caught mid-flight off a stunt piece (StuntRamps), held where the jump puts it `t` seconds
## after the lip at `speed` m/s, the free eye beside the ramp. The car is a placed body (kinematic,
## no physics wheels, a driver at the wheel), as tools/stunt_ramps/stage.gd places STUNT= stills;
## the jump's look (the wheels hanging on their springs, the dust off the run-up, the lip's grit)
## is StuntJumpFX's, given the moment's age, so the still shows what play draws `t` s after a
## launch. Loaded at run time by refcams_shot.gd (after the autoloads), so it may name game classes.
##
##   "stunt": {"site": a StuntRamps site id (tools/stunt_ramps/probe.tscn lists them), "t": seconds
##     after the lip, "speed": m/s off the lip, "body": a Vehicle.BodyType name, "paint": [r, g, b],
##     "pitch" / "roll": degrees the car is turned off its path, "seed",
##     "eye" / "look": [x, y, z] in the RAMP's frame (+Z the way it is ridden, origin at its foot)}
##
## Env STUNT_EYE=x,y,z / STUNT_LOOK=x,y,z / STUNT_T / STUNT_SPEED override the row (framing work).

static var hero_at := Vector3.INF
static var hero_yaw := 0.0
static var _car: Vehicle = null


static func _vec(spec: Dictionary, key: String, env: String, fallback: Vector3) -> Vector3:
	var s := OS.get_environment(env)
	if s != "":
		var p := s.split(",")
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	var a: Variant = spec.get(key)
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func _num(spec: Dictionary, key: String, env: String, fallback: float) -> float:
	var s := OS.get_environment(env)
	if s != "":
		return float(s)
	return float(spec.get(key, fallback))


## The site's pose at `t` s after its lip at `speed`: [true world position, basis, velocity].
static func flight(s: Dictionary, t: float, speed: float, pitch_deg: float, roll_deg: float) -> Array:
	var xf := StuntBuild.xform(s)
	var lip: Array = StuntRamps.lips(s)[0]
	var at := xf * (lip[0] as Vector3)
	var dir := xf.basis * (lip[1] as Vector3)
	if int(s.kind) != StuntRamps.Kind.QPIPE:
		var ang := 2.0 * atan(float(lip[3]) / float(s.get("len", 4.0)))
		var flat := Vector3(dir.x, 0.0, dir.z).normalized()
		dir = (flat * cos(ang) + Vector3.UP * sin(ang)).normalized()
	var g := 9.8
	var v := dir * speed
	var pos := at + v * t + Vector3.DOWN * 0.5 * g * t * t + Vector3.UP * 0.7
	var vel := v + Vector3.DOWN * g * t
	var fwd := vel.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	fwd = fwd.rotated(side, deg_to_rad(pitch_deg)).normalized()
	var up := side.cross(fwd).normalized()
	up = up.rotated(fwd, deg_to_rad(roll_deg))
	return [pos, Basis(fwd.cross(up).normalized(), up, -fwd).orthonormalized(), vel]


static func stage(tree: SceneTree, scene: Node, _cam: Camera3D, _player: Node3D, place: Callable, row: Dictionary = {}) -> void:
	var spec: Dictionary = row.get("stunt", {}) if row.get("stunt", null) is Dictionary else {}
	var plan: CityPlan = scene.get("plan")
	if plan == null:
		return
	var want := String(spec.get("site", ""))
	var site: Dictionary = {}
	for s: Dictionary in StuntRamps.all_sites(plan):
		if String(s.id) == want:
			site = s
			break
	if site.is_empty():
		print("REFCAM stunt: no site %s" % want)
		return
	var t := _num(spec, "t", "STUNT_T", 0.8)
	var speed := _num(spec, "speed", "STUNT_SPEED", 30.0)
	var fl := flight(site, t, speed, float(spec.get("pitch", 4.0)), float(spec.get("roll", 5.0)))
	var pos: Vector3 = fl[0]
	var basis: Basis = fl[1]
	var vel: Vector3 = fl[2]
	_car = Vehicle.new()
	var body: int = Vehicle.BodyType.get(String(spec.get("body", "MUSCLE")), Vehicle.BodyType.SEDAN)
	var pc: Array = spec.get("paint", [0.55, 0.05, 0.03])
	_car.setup(body, Color(float(pc[0]), float(pc[1]), float(pc[2])), Vehicle.Addon.NONE)
	_car.name = "StuntCar"
	# Foot off the brake (the lamps: a car in the air is on the throttle, not braking at a stop).
	_car.traffic = {"stunt_still": true, "tb_foot": true}
	_car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_car.freeze = true
	scene.add_child(_car)
	_car.global_transform = Transform3D(basis, WorldState.to_local(pos))
	_car.set_meta("stunt_still", true)
	# The jump's own look at this age (StuntJumpFX, when it is in the game: the A/B is its switch).
	StuntJumpFX.stage(_car, site, speed, t, vel)
	var xf := StuntBuild.xform(site)
	var eye := xf * _vec(spec, "eye", "STUNT_EYE", Vector3(-8.0, 1.7, -6.0))
	var look := xf * _vec(spec, "look", "STUNT_LOOK", xf.affine_inverse() * pos)
	var d := (look - eye).normalized()
	var eye_text := "%.3f,%.3f,%.3f,%.3f,%.3f" % [eye.x, eye.y, eye.z, rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))]
	OS.set_environment("EYE", eye_text)
	for i in 6:
		await tree.process_frame
		place.call()
		_car.global_transform = Transform3D(basis, WorldState.to_local(pos))
		StuntJumpFX.hang_pose(_car)
	print("REFCAM stunt: %s %s at t %.2f s, %.0f m/s, car at %s (%.1f m over the lip), eye %s" % [site.id,
		StuntRamps.Kind.keys()[int(site.kind)], t, speed, pos, pos.y - (xf * (StuntRamps.lips(site)[0][0] as Vector3)).y, eye_text])


static func unstage() -> void:
	if is_instance_valid(_car):
		_car.queue_free()
	_car = null
