extends SceneTree
## Blood and gore at arm's length (blood-gore-2) in the test room, in a minute: the real player,
## a crowd rig's ragdoll and WeaponFX's real blood, staged and shot close.
##
##   OUT=/tmp/gore STAGE=wounds xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/blood_gore/gore_shot.gd --resolution 1280x720
##
## STAGE: wounds (a body lying face up, three rounds into the chest, seen from a metre) | stump (a
## body with two limbs torn off, the camera on the shoulder) | hero (rounds into a person a metre
## and a half in front of him, then the camera turned round onto his front) | car (a bleeding body
## laid on a parked car's bonnet) | pool (a body bleeding out on a tilted slab: the pool runs
## downhill). WAIT seconds of effect time before the shot (default per stage), MODEL crowd rig
## index, CAM_DIST, CAM_UP. BLOOD_GORE_2=0 is the before. Saves OUT_<stage>.png.
## Under --rendering-driver vulkan (lavapipe) the marks are Decals, as on the Mac.

var _t := 0.0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/levels/test_box.tscn")
	var level := packed.instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var stage := _env("STAGE", "wounds")
	seed(int(_env("SEED", "3")))
	var player := get_first_node_in_group("player") as Node3D
	# Out of the way unless he is the subject.
	var hud := level.find_child("DebugHud", true, false)
	if hud:
		hud.set("visible", false)
	for c in root.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	Engine.time_scale = float(_env("SCALE", "1.0"))
	var origin := player.global_position + Vector3(0.0, 0.0, -4.0)
	var ground := _ground(origin)
	var cam := Camera3D.new()
	cam.fov = float(_env("FOV", "50"))
	cam.near = 0.02
	level.add_child(cam)
	cam.make_current()
	var fx: GDScript = load("res://scripts/weapons/weapon_fx.gd")
	fx.set("blood_budget", 1000)
	var look_at := ground
	var from := ground + Vector3(0.0, 1.2, 1.0)
	match stage:
		"wounds", "stump", "pool":
			var tilt := stage == "pool"
			if tilt:
				ground = _slab(level, ground + Vector3(0.0, 0.0, 0.0), deg_to_rad(float(_env("TILT", "4"))))
			var doll := _doll(level, ground, 0.0, 0.0 if tilt else INF)
			await _settle(1.6)
			var chest := _bone(doll, "Spine2")
			print("DOLL chest ", chest, " ground ", ground, " bodies ", (doll.get("bodies") as Array).size())
			if stage == "stump":
				print("TORN ", doll.call("dismember", int(_env("GIBS", "2")), Vector3(4.0, 2.0, 0.0)))
				await _settle(0.5)
			else:
				for i in int(_env("ROUNDS", "3")):
					# A round from above and to the side, onto the body's own collision.
					var aim := chest + Vector3(randf_range(-0.12, 0.12), 0.0, randf_range(-0.12, 0.12))
					var src := aim + Vector3(0.6, 1.6, 0.9)
					var hit := _ray(src, aim + (aim - src) * 0.6, 4)
					var at: Vector3 = hit.position if not hit.is_empty() else aim
					print("ROUND hit ", (hit.collider as Node).name if not hit.is_empty() else "nothing")
					doll.call("shot", at, (aim - src).normalized(), Vector3.ZERO, 1.0)
					await _settle(0.15)
			await _settle(float(_env("WAIT", "9" if stage != "pool" else "16")))
			chest = _bone(doll, "Spine2")
			print("STAINS ", doll.get("_wounds"), " mat ", doll.get("_stain_mat"))
			var sm: ShaderMaterial = doll.get("_stain_mat")
			if sm:
				print("  count ", sm.get_shader_parameter("wound_count"), " w0 ", sm.get_shader_parameter("wound_0"), " holes ", sm.get_shader_parameter("wound_holes"), " gore ", sm.get_shader_parameter("wound_gore"))
			look_at = chest
			# Close on a wound: along its outward normal (WOUND picks which).
			var wounds: Array = doll.get("_wounds")
			var skel := doll.find_child("Skeleton3D", true, false) as Skeleton3D
			if stage == "wounds" and not wounds.is_empty() and skel != null:
				# The wound facing most up (the camera stays above the floor), or WOUND=i.
				var pick := int(_env("WOUND", "-1"))
				if pick < 0:
					var best := -2.0
					for i in wounds.size():
						var bw: Dictionary = wounds[i]
						var up_n: float = (skel.global_basis * (skel.get_bone_global_pose(int(bw.bone)).basis * (bw.nrm as Vector3))).normalized().y
						if up_n > best:
							best = up_n
							pick = i
				var w: Dictionary = wounds[clampi(pick, 0, wounds.size() - 1)]
				var pose := skel.get_bone_global_pose(int(w.bone))
				var wp: Vector3 = skel.global_transform * (pose * (w.local as Vector3))
				var wn: Vector3 = (skel.global_basis * (pose.basis * (w.nrm as Vector3))).normalized()
				wn = (wn + Vector3.UP * 0.8).normalized()
				look_at = wp
				from = wp + wn * float(_env("CAM_DIST", "0.6")) + Vector3(0.05, 0.05, 0.0)
			if stage == "stump":
				var stumps: Array = []
				# The thrown limb's torn end, lying in the open (STUMP_ON=body: the body's).
				if _env("STUMP_ON", "limb") == "limb":
					for g in get_nodes_in_group("gib"):
						for c in (g as Node).get_children():
							if c is MeshInstance3D and (c.name == "Stump" or (c as MeshInstance3D).mesh is SphereMesh):
								stumps.append(c)
				if stumps.is_empty():
					stumps = doll.find_children("Stump", "MeshInstance3D", true, false)
				if stumps.is_empty():
					# BLOOD_GORE_2=0: the old cap, a sphere on a bone attachment.
					for att in doll.find_children("*", "BoneAttachment3D", true, false):
						for c in att.get_children():
							if c is MeshInstance3D and (c as MeshInstance3D).mesh is SphereMesh:
								stumps.append(c)
				print("STUMPS ", stumps.size())
				look_at = (stumps[0] as Node3D).global_position if not stumps.is_empty() else chest
				if not stumps.is_empty():
					var ax := (stumps[0] as Node3D).global_basis.y.normalized()
					from = look_at + Vector3(0.5, 0.55, 0.35).normalized() * float(_env("CAM_DIST", "0.6"))
			var d := float(_env("CAM_DIST", "1.1" if stage != "pool" else "3.2"))
			var up := float(_env("CAM_UP", "0.7" if stage != "pool" else "2.4"))
			if from == ground + Vector3(0.0, 1.2, 1.0) or stage == "pool":
				from = look_at + Vector3(0.35, up, d)
		"hero":
			# A person a metre and a half in front of him, shot through toward him.
			var front := -player.global_basis.z
			var spot := player.global_position + front * float(_env("GAP", "1.4"))
			var doll := _doll(level, _ground(spot), 0.0)
			await _settle(0.1)
			for i in int(_env("ROUNDS", "3")):
				var at := _bone(doll, "Spine2")
				fx.call("blood", doll, at, (-front + Vector3(0.0, 0.1, 0.0)).normalized(), 1.5, doll)
				doll.call("shot", at, (-front).normalized(), Vector3.ZERO, 1.0)
				await _settle(0.12)
			await _settle(float(_env("WAIT", "1.5")))
			doll.queue_free()
			look_at = player.global_position + Vector3.UP * 1.2
			look_at = player.global_position + Vector3.UP * float(_env("LOOK_UP", "1.15"))
			from = look_at + front * float(_env("CAM_DIST", "0.9")) + Vector3.UP * float(_env("CAM_UP", "0.15")) + front.cross(Vector3.UP) * 0.25
			var hb: GDScript = load("res://scripts/player/hero_blood.gd")
			var cur: Object = hb.get("current")
			print("HERO spatters ", (cur.get("spats") as Array).size() if cur != null else -1)
		"car":
			var car := _car(level, ground + Vector3(0.0, 0.0, 0.0))
			await _settle(1.0)
			var top := _top_of(car, ground + Vector3(0.0, 0.0, -1.2))
			var doll := _doll(level, top + Vector3(0.0, 0.25, 0.0), PI * 0.5, 0.0)
			doll.set("bleed", 2.0)
			doll.call("_wounded", 2.0, Vector3(0.0, 0.9, 0.0))
			await _settle(float(_env("WAIT", "10")))
			look_at = top + Vector3(0.0, -0.3, -0.6)
			from = look_at + Vector3(1.6, 0.6, -2.0)
			print("CAR blood ", fx.call("blood_counts"), " state ", doll.get("_car_blood"))
			var marks := 0
			for c in car.get_children():
				if c.is_in_group("blood"):
					marks += 1
					print("  mark ", c.name, " at ", (c as Node3D).global_position, " vis ", (c as Node3D).visible)
			var st: Dictionary = doll.get("_car_blood")
			if st.has("edge"):
				var e: Vector3 = car.global_transform * (st.edge as Vector3)
				look_at = e + Vector3(0.0, -0.25, 0.0)
				var out := Vector3(e.x - top.x, 0.0, e.z - top.z).normalized()
				from = e + out * float(_env("CAM_DIST", "1.6")) + Vector3.UP * float(_env("CAM_UP", "0.5")) + out.cross(Vector3.UP) * 0.7
	if stage != "hero":
		player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	print("CAM from ", from, " at ", look_at, " player ", player.global_position)
	cam.global_position = from
	cam.look_at(look_at)
	for i in 4:
		cam.make_current()
		await process_frame
	var out := _env("OUT", "/tmp/gore") + "_" + stage + ".png"
	root.get_texture().get_image().save_png(out)
	print("SAVED ", out, " blood ", fx.call("blood_counts"))
	quit()


func _doll(level: Node, at: Vector3, yaw: float, fling: float = INF) -> Node3D:
	var rd: GDScript = load("res://scripts/npc/ragdoll.gd")
	var ped: GDScript = load("res://scripts/npc/pedestrian.gd")
	var doll: Node3D = rd.new()
	doll.position = at
	doll.rotation.y = yaw
	level.add_child(doll)
	var models: Array = ped.get("MODELS")
	doll.call("build_from_rig", models[int(_env("MODEL", "0")) % models.size()], int(_env("LOOK", "3")))
	doll.call("fling", Vector3(0.0, 0.0, float(_env("FLING", "-6")) if fling == INF else fling))
	return doll


func _car(level: Node, at: Vector3) -> Node3D:
	var vh: GDScript = load("res://scripts/vehicles/vehicle.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_env("CAR_SEED", "7"))
	var car: Node3D = vh.call("random_car", rng)
	level.add_child(car)
	car.global_position = at + Vector3.UP * 0.2
	return car


func _top_of(car: Node3D, at: Vector3) -> Vector3:
	var space := car.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 4.0, at, 4))
	return hit.position if not hit.is_empty() else at + Vector3.UP * 1.0


func _slab(level: Node, at: Vector3, tilt: float) -> Vector3:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.2, 8.0)
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.35, 0.36)
	mat.roughness = 0.85
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	level.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.RIGHT, tilt), at + Vector3.UP * 0.4)
	return at + Vector3.UP * 0.55


func _ray(a: Vector3, b: Vector3, mask: int) -> Dictionary:
	var space := root.get_viewport().world_3d.direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, mask))


func _ground(at: Vector3) -> Vector3:
	var space := (current_scene if current_scene else root).get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 10.0, 1))
	return hit.position if not hit.is_empty() else at


func _bone(doll: Node3D, bone: String) -> Vector3:
	var skel := doll.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return doll.global_position + Vector3.UP * 0.3
	var b := skel.find_bone(bone)
	for alt in ["Spine02", "Spine01", "Spine1", "Spine", "Hips"]:
		if b < 0 and bone.begins_with("Spine"):
			b = skel.find_bone(alt)
	if b < 0:
		return Vector3.ZERO
	return skel.global_transform * skel.get_bone_global_pose(b).origin


func _settle(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		t += root.get_process_delta_time()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d
