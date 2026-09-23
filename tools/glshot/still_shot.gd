extends SceneTree
## Store / marketing stills: the city at a --spawn, posed, then held still for a clean frame.
## Run it through the real Forward+ renderer for finals (lavapipe, slow) and opengl3 for framing:
##
##   OUT=still.png FOV=55 BOOST=1 xvfb-run -a -s "-screen 0 1920x1080x24" godot \
##     --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/still_shot.gd --resolution 1920x1080 \
##     -- --spawn=1150,255,90,-6,140 --hour=18.2 --nohud --quality=0
##
## Env: OUT png path; FRAMES frames at normal speed first (streaming, exposure, GI; default 30);
## FOV camera field of view; BOOST=1 poses the player mid-boost (held in place); FX_AT=metres
## puts an explosion that far ahead of the camera (FX_SIDE metres to the right), which really
## launches what it hits, and FX_TIME seconds into it is when the shot is taken (0.25 = fireball
## at its biggest); then SETTLE frames (default 6) with the clock all but frozen (TIME_SCALE,
## default 0.0005): a software frame takes seconds, and at normal speed every moving thing -
## people, traffic, leaves, fire - smears under TAA. Held still, it resolves as crisply as it
## does on the Mac. FX_AT_PED=1 centres the explosion on the nearest pedestrian at least FX_AT
## metres ahead instead (people come apart close to a blast); FX_PED_PLACE=1 also stands that
## pedestrian in the road exactly FX_AT metres ahead first. Debris is kept alive for the shot:
## its lifetime is wall-clock seconds, and a software frame takes seconds.
## Traffic is allowed to build freely during the warm-up, so the streets look the way they do a
## minute into play rather than the first second of it.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := _env_int("FRAMES", 30)
	var hold := Vector3.INF
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var parts := arg.trim_prefix("--spawn=").split(",")
			if parts.size() >= 5:
				hold = Vector3(parts[0].to_float(), parts[4].to_float(), parts[1].to_float())
	var boost := OS.get_environment("BOOST") == "1"
	var fov := float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 0.0
	var player: Node3D = null
	var anchor := Vector3.INF
	for i in frames:
		await process_frame
		var scene := current_scene
		if scene == null:
			continue
		var traffic := scene.get_node_or_null("Traffic")
		if traffic:
			traffic.set("builds_per_frame", 40)
		# Autoloads exist by now (not in _initialize).
		var budget := root.get_node_or_null("/root/PhysicsBudget")
		if budget:
			budget.set("debris_lifetime", 1.0e6)
		if player == null:
			player = get_first_node_in_group("player") as Node3D
			if player:
				anchor = player.global_position
		_pose(player, anchor, hold, boost, fov)
	var traffic_node := current_scene.get_node_or_null("Traffic") if current_scene else null
	if traffic_node:
		traffic_node.set("builds_per_frame", 1)
	var fx_at := float(OS.get_environment("FX_AT")) if OS.get_environment("FX_AT") != "" else 0.0
	if fx_at > 0.0 and player:
		var cam := get_root().get_camera_3d()
		var forward := -cam.global_basis.z
		forward.y = 0.0
		var at := cam.global_position + forward.normalized() * fx_at
		# FX_SIDE metres to the right of the view, so the player is not standing in front of it.
		var side := float(OS.get_environment("FX_SIDE")) if OS.get_environment("FX_SIDE") != "" else 0.0
		at += cam.global_basis.x.normalized() * side
		at.y = player.global_position.y + 0.5
		if OS.get_environment("FX_AT_PED") == "1":
			var best: Node3D = null
			for p in get_nodes_in_group("pedestrian"):
				var to: Vector3 = (p as Node3D).global_position - cam.global_position
				var ahead := to.dot(forward.normalized())
				var placing := OS.get_environment("FX_PED_PLACE") == "1"
				if not placing and (ahead < fx_at or absf(to.dot(cam.global_basis.x.normalized())) > ahead * 0.6):
					continue
				if best == null or to.length() < (best.global_position - cam.global_position).length():
					best = p
			print("fx target pedestrian: ", best.name if best else "none")
			if best and OS.get_environment("FX_PED_PLACE") == "1":
				# Stand them in the road FX_AT metres ahead, so the shot frames them cleanly.
				best.global_position = Vector3(at.x, player.global_position.y, at.z)
				best.set("velocity", Vector3.ZERO)
				best.set("_pause_left", 30.0)
				at = best.global_position + Vector3(0.5, 0.4, 0.3)
				# The blast is a physics query, and the broadphase only learns where a moved body
				# is on the next step: blasted at once, the pedestrian was never hit.
				for i in 2:
					await physics_frame
			elif best:
				at = best.global_position + Vector3(0.6, 0.4, 0.0)
		var radius := float(_env_int("FX_RADIUS", 9))
		# Godot caps a frame at eight physics ticks (0.133 s), whatever the wall clock says, so
		# a scale of 0.375 steps the effect 0.05 s a frame - fine enough to stop where asked.
		Engine.time_scale = 0.375
		# Loaded, not named: this script compiles before the autoloads exist, and Explosion
		# uses one (Sfx), so naming the class here fails the whole script.
		load("res://scripts/weapons/weapon_fx.gd").explosion(player, at, radius)
		var hit: int = load("res://scripts/weapons/explosion.gd").blast(player, at, radius, 26.0, 0.0)
		print("fx blast at %s hit %d bodies; gibs now %d, target down %s" % [at, hit, get_nodes_in_group("gib").size(), "?"])
		for d in get_nodes_in_group("debris"):
			print("  debris ", d.name, " ", d.get_script().get_global_name() if d.get_script() else d.get_class(), " at ", (d as Node3D).global_position)
		var want := float(OS.get_environment("FX_TIME")) if OS.get_environment("FX_TIME") != "" else 0.25
		var elapsed := 0.0
		while elapsed < want:
			await process_frame
			elapsed += get_root().get_process_delta_time()
			_pose(player, anchor, hold, boost, fov)
	# Then all but freeze the clock for the last frames: a software frame takes seconds, and at
	# normal speed everything that moves - people, traffic, leaves, fire - smears under TAA.
	# Held still, TAA and the GI converge on one instant, as crisp as it is on the Mac.
	Engine.time_scale = float(OS.get_environment("TIME_SCALE")) if OS.get_environment("TIME_SCALE") != "" else 0.0005
	for i in _env_int("SETTLE", 6):
		await process_frame
		_pose(player, anchor, hold, boost, fov)
	var gib_cam := get_root().get_camera_3d()
	for g in get_nodes_in_group("gib"):
		var gp: Vector3 = (g as Node3D).global_position
		print("gib at %s, on screen %s" % [gp, gib_cam.unproject_position(gp) if gib_cam and not gib_cam.is_position_behind(gp) else "behind"])
	var day := current_scene.get_node_or_null("DayNight") if current_scene else null
	if day:
		print("clock ", day.clock_text())
	var out := OS.get_environment("OUT")
	if out == "":
		out = "still.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


## Keeps the player where the shot wants them: at the --spawn height, and for BOOST held in
## place mid-boost (the boost itself would carry them off between software frames).
func _pose(player: Node3D, anchor: Vector3, hold: Vector3, boost: bool, fov: float) -> void:
	if player == null:
		return
	if boost:
		Input.action_press("boost")
	if hold != Vector3.INF:
		player.global_position.y = hold.y
	if boost and anchor != Vector3.INF:
		player.global_position.x = anchor.x
		player.global_position.z = anchor.z
	if hold != Vector3.INF or boost:
		player.set("velocity", Vector3.ZERO)
	if fov > 0.0:
		var rig := player.get_node_or_null("CameraRig")
		if rig:
			rig.set("camera_fov", fov)
			rig.set("boost_fov_boost", 0.0)


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
