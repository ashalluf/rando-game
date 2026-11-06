extends RefCounted
## STUNT=<kind or site id>[:t] on tools/glshot/still_shot.gd: a car caught mid-stunt on the stunt
## piece nearest the camera (kind: kicker, pier, launch, qpipe, loop, dirt; or a site id from
## tools/stunt_ramps/probe.tscn). The car is a placed body (traffic-style: kinematic, no physics
## wheels, a driver at the wheel), held where the jump puts it `t` seconds after the lip (default
## 0.55) at STUNT_SPEED m/s (default 24); on a loop `t` is the share of the turn (default 0.42).
## STUNT_BODY picks the body type, STUNT_VIEW=side|chase|front the framing, STUNT_DIST the eye's
## distance. Returns the EYE line it framed (true world), or "".
## Loaded, not named, by still_shot.gd (it compiles before the autoloads).

static func stage(tree: SceneTree, spec: String, cam: Camera3D) -> String:
	var parts := spec.split(":")
	var want := parts[0]
	var t := float(parts[1]) if parts.size() > 1 else -1.0
	var best: Node3D = null
	var best_d := INF
	var cam_w := WorldState.to_world(cam.global_position)
	for n: Node in tree.get_nodes_in_group("stunt_ramp"):
		var s: Dictionary = (n as Node3D).get_meta("stunt", {})
		if s.is_empty():
			continue
		var kname := String(StuntRamps.Kind.keys()[int(s.kind)]).to_lower()
		if want != String(s.id) and want != kname:
			continue
		var d := cam_w.distance_to(s.p)
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		print("STUNT: no %s built near the camera" % want)
		return ""
	var s: Dictionary = best.get_meta("stunt")
	var xf := StuntBuild.xform(s)
	var speed := _f("STUNT_SPEED", 24.0)
	var g := 9.8
	var pos := Vector3.ZERO
	var basis := Basis()
	var k := int(s.kind)
	if k == StuntRamps.Kind.LOOP:
		var share := t if t >= 0.0 else 0.42
		var phi := TAU * share
		var c := StuntKit.loop_point(float(s.r), float(s.shift), phi)
		var n := StuntKit.loop_normal(phi)
		var d := (StuntKit.loop_point(float(s.r), float(s.shift), phi + 0.01) - c).normalized()
		pos = xf * (c + n * 0.55)
		var up := xf.basis * n
		var fwd := xf.basis * d
		basis = Basis(up.cross(-fwd).normalized(), up, -fwd).orthonormalized()
	else:
		var lips := StuntRamps.lips(s)
		var lip: Array = lips[mini(int(_f("STUNT_LIP", 0.0)), lips.size() - 1)]
		var at := xf * (lip[0] as Vector3)
		var dir := xf.basis * (lip[1] as Vector3)
		if k != StuntRamps.Kind.QPIPE:
			# The slope at the lip: the arc's end angle (kickers), the takeoff's (dirt).
			var ang := 2.0 * atan(float(lip[3]) / float(s.get("len", 4.0)))
			if k == StuntRamps.Kind.DIRT:
				ang = deg_to_rad(30.0)
			var flat := Vector3(dir.x, 0.0, dir.z).normalized()
			dir = (flat * cos(ang) + Vector3.UP * sin(ang)).normalized()
		var tt := t if t >= 0.0 else 0.55
		var v := dir * speed
		pos = at + v * tt + Vector3.DOWN * 0.5 * g * tt * tt + Vector3.UP * 0.7
		var vel := v + Vector3.DOWN * g * tt
		var fwd := vel.normalized()
		# Nose a little up of the path (a car off a kicker rotates late), and a touch of roll.
		var side := fwd.cross(Vector3.UP).normalized()
		fwd = fwd.rotated(side, deg_to_rad(_f("STUNT_PITCH", 6.0))).normalized()
		var up := side.cross(fwd).normalized()
		up = up.rotated(fwd, deg_to_rad(_f("STUNT_ROLL", 7.0)))
		basis = Basis(fwd.cross(up).normalized(), up, -fwd).orthonormalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_f("STUNT_SEED", 11.0))
	var car: Vehicle
	if OS.get_environment("STUNT_BODY") != "":
		car = Vehicle.new()
		car.setup(int(_f("STUNT_BODY", 0.0)), Vehicle.PAINTS[rng.randi() % Vehicle.PAINTS.size()], Vehicle.Addon.NONE)
	else:
		car = Vehicle.random_car(rng)
	car.traffic = {"stunt_still": true}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	var scene: Node = tree.current_scene
	scene.add_child(car)
	car.global_transform = Transform3D(basis, WorldState.to_local(pos))
	car.set_meta("stunt_still", true)
	# Frame it.
	var view := OS.get_environment("STUNT_VIEW")
	var dist := _f("STUNT_DIST", 16.0)
	var fwd_flat := -basis.z
	fwd_flat.y = 0.0
	fwd_flat = fwd_flat.normalized() if fwd_flat.length() > 0.1 else (xf.basis.z)
	var right := fwd_flat.cross(Vector3.UP).normalized()
	var eye: Vector3
	match view:
		"chase":
			eye = pos - fwd_flat * dist + Vector3.UP * dist * 0.18 + right * dist * 0.25
		"front":
			eye = pos + fwd_flat * dist + Vector3.UP * dist * 0.1 - right * dist * 0.3
		_:
			eye = pos + right * dist - fwd_flat * dist * 0.35 + Vector3.DOWN * 1.0
	if k == StuntRamps.Kind.LOOP and view == "":
		var lr := xf.basis.x * signf(float(s.shift))
		eye = xf * Vector3(float(s.shift) * 0.5, float(s.r), 0.0) - lr * (dist + 6.0) + xf.basis.z * 6.0 + Vector3.DOWN * 3.0
	var look := (pos - eye).normalized()
	var yaw := rad_to_deg(atan2(-look.x, -look.z))
	var pitch := rad_to_deg(asin(clampf(look.y, -1.0, 1.0)))
	OS.set_environment("EYE_AGL", "0")
	print("STUNT %s (%s) car %s at %s" % [s.id, StuntRamps.Kind.keys()[k], car.display_name(), pos])
	return "%.2f,%.2f,%.2f,%.1f,%.1f" % [eye.x, eye.y, eye.z, yaw, pitch]


static func _f(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback
