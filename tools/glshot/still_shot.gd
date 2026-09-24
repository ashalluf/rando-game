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
## pedestrian in the road exactly FX_AT metres ahead first. FX_SHOOT=N fires N AK-47 rounds into
## that pedestrian instead of the blast (see _rifle_burst for SHOT_YAW / SHOT_DIST / SHOT_HEIGHT /
## SHOT_GAP), and FX_SCALE sets the clock scale the effect runs at (default 0.375; 1.0 for an
## aftermath shot many seconds later). Debris is kept alive for the shot:
## its lifetime is wall-clock seconds, and a software frame takes seconds.
## AIR=final|takeoff|news|police stages an aircraft for the shot (AIR_DIST, AIR_SIDE metres to
## the right, AIR_CLEAR, AIR_FRAMES; see the block before the freeze).
## CAR_PARAM=name=value sets one car paint uniform on every car (A/B tests); CAR_REPORT=1 prints
## each car on screen with its paint; AIM=1 holds GTA-style aim for the shot. WHEEL=<index> opens
## the weapon wheel just before the shot with that segment highlighted (-1 = none), time already
## slowed; leave out --nohud for it, the wheel lives in the HUD.
## STARS=n puts a wanted level on and stages the police in front of the camera (Police.stage_for_shot):
## POLICE=standoff (default) is cruisers stopped across the street with their crews out and
## shooting, POLICE=pursuit is cruisers bearing down the street at the player. POLICE_FRAMES
## (default 24; 6 for a pursuit) lets them move before the shot, and a standoff ends with every
## officer firing once, so the tracers and muzzle flashes are in the frame. HUD=1 (with --nohud,
## which skips the loading screen) puts the HUD back for the shot: the stars, the health bar and
## the police on the minimap.
## STREET=queue|crossing stages the signalised junction ahead of the camera: a queue waiting at
## its red, and for `crossing` people out on the crosswalk in front of it (see _stage_street for
## STREET_AHEAD / STREET_CARS / STREET_PEDS / STREET_FRAMES). With --hour=21 it is the lit heads
## at night.
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
		# FX_SCALE raises it for aftermath shots that want many seconds of effect time.
		Engine.time_scale = float(OS.get_environment("FX_SCALE")) if OS.get_environment("FX_SCALE") != "" else 0.375
		var shots := _env_int("FX_SHOOT", 0)
		if shots > 0:
			await _rifle_burst(player, at, shots, forward.normalized())
		else:
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
	# HUD=1 with --nohud: skip the loading screen (which --nohud does) but put the HUD back up for
	# the shot, in its CLEAN mode - without --nohud the loading screen fills the first hundred frames.
	if OS.get_environment("HUD") == "1" and current_scene:
		var hud_node := current_scene.get_node_or_null("DebugHud")
		if hud_node:
			hud_node.set("mode", 0)
			hud_node.call("_apply_mode")
	# STARS=n: the police, staged in front of the camera and given a moment to move.
	var stars_env := OS.get_environment("STARS")
	if stars_env != "" and player:
		var police := current_scene.get_node_or_null("Police")
		if police:
			var scene_kind := OS.get_environment("POLICE") if OS.get_environment("POLICE") != "" else "standoff"
			police.call("stage_for_shot", int(stars_env), scene_kind)
			var frames_p := _env_int("POLICE_FRAMES", 6 if scene_kind == "pursuit" else 24)
			for i in frames_p:
				await process_frame
				police.call("report_sighting")
				_pose(player, anchor, hold, boost, fov)
			if scene_kind != "pursuit":
				# Freeze the clock first: a software frame is seconds of process time, which is
				# the whole life of a tracer, so a volley fired at full speed is gone before the
				# frame that would show it.
				Engine.time_scale = float(OS.get_environment("TIME_SCALE")) if OS.get_environment("TIME_SCALE") != "" else 0.0005
				for o in police.get("officers"):
					if is_instance_valid(o) and o.get("police") != null:
						var target: Vector3 = police.call("player_aim_point")
						o.call("_shoot", target, (o as Node3D).global_position.distance_to(target))
				await process_frame
			print("police: %d stars, %d cruisers, %d officers, player hp %.0f" % [int(police.get("stars")), (police.get("cruisers") as Array).size(), (police.get("officers") as Array).size(), float(player.get("health").get("health")) if player.get("health") else -1.0])
		else:
			print("STARS: no Police node in the scene")
	# AIM=1 holds GTA-style aim (alt_fire) through the last frames, so the shot shows the
	# over-the-shoulder view and the lock brackets on whoever it picks up.
	if OS.get_environment("AIM") == "1":
		Input.action_press("alt_fire")
		for i in 12:
			await process_frame
			_pose(player, anchor, hold, boost, fov)
		var lock: Node = player.get("lock_on") if player else null
		print("aim lock: ", lock.get("target").name if lock and lock.get("target") else "none")
	# CAR_PARAM=name=value overrides one car paint uniform on every car (A/B tests).
	var car_param := OS.get_environment("CAR_PARAM")
	if car_param.contains("="):
		var kv := car_param.split("=")
		for car in current_scene.find_children("*", "VehicleBody3D", true, false):
			for mi in car.find_children("*", "MeshInstance3D", true, false):
				for si in (mi as MeshInstance3D).get_surface_override_material_count():
					var m := (mi as MeshInstance3D).get_surface_override_material(si) as ShaderMaterial
					if m:
						m.set_shader_parameter(kv[0], kv[1].to_float())
	# WHEEL=<index>: the weapon wheel, open, with that segment highlighted. Looked up and called
	# rather than named: this script compiles before the autoloads exist.
	var wheel_env := OS.get_environment("WHEEL")
	if wheel_env != "":
		var wheel := get_first_node_in_group("weapon_wheel")
		if wheel:
			wheel.call("show_for_shot", int(wheel_env))
			await process_frame
		else:
			print("WHEEL: no weapon wheel in the scene")
	# AIR=final|takeoff|news|police stages an aircraft AIR_DIST metres ahead of the camera (and
	# AIR_SIDE to its right)
	# (AirTraffic.stage(): an airliner on short final, a departure just past lift-off, the news
	# helicopter, or police circling the player with the searchlight on him), AIR_CLEAR=1 empties
	# the rest of the sky first, then AIR_FRAMES frames run so it settles.
	var air_env := OS.get_environment("AIR")
	if air_env != "":
		var air := current_scene.get_node_or_null("AirTraffic")
		var air_cam := get_root().get_camera_3d()
		if air and air_cam:
			if OS.get_environment("AIR_CLEAR") == "1":
				air.call("clear_all")
			var dist := float(OS.get_environment("AIR_DIST")) if OS.get_environment("AIR_DIST") != "" else 300.0
			var side := float(OS.get_environment("AIR_SIDE")) if OS.get_environment("AIR_SIDE") != "" else 0.0
			var placed: Node = air.call("stage", air_env, air_cam, dist, side)
			print("AIR staged ", placed.name if placed else "nothing", " at ", (placed as Node3D).global_position if placed else Vector3.ZERO)
			for i in _env_int("AIR_FRAMES", 4):
				await process_frame
				_pose(player, anchor, hold, boost, fov)
		else:
			print("AIR: no AirTraffic in the scene")
	# STREET=queue|crossing: a signalised junction ahead of the camera, a queue at its red, and
	# for `crossing` people out on the crosswalk in front of it (see _stage_street).
	var street_env := OS.get_environment("STREET")
	if street_env != "" and current_scene:
		_stage_street(street_env)
		for i in _env_int("STREET_FRAMES", 8):
			await process_frame
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
	# CAR_REPORT=1 prints every car on screen with its paint, finish and pixel position, so a car
	# that looks the wrong colour can be told apart from one that IS that colour.
	if OS.get_environment("CAR_REPORT") == "1" and gib_cam:
		for car in current_scene.find_children("*", "VehicleBody3D", true, false):
			var cp: Vector3 = (car as Node3D).global_position
			if gib_cam.is_position_behind(cp) or cp.distance_to(gib_cam.global_position) > 90.0:
				continue
			for mi in car.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial if (mi as MeshInstance3D).get_surface_override_material_count() > 0 else null
				if m and m.get_shader_parameter("paint") != null:
					print("car %s at %s px %s paint %s metal %.2f geo_glass %s" % [car.name, cp.round(), gib_cam.unproject_position(cp).round(), m.get_shader_parameter("paint"), m.get_shader_parameter("paint_metallic"), m.get_shader_parameter("geo_glass")])
					break
	var day := current_scene.get_node_or_null("DayNight") if current_scene else null
	if day:
		print("clock ", day.clock_text())
	var out := OS.get_environment("OUT")
	if out == "":
		out = "still.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


## FX_SHOOT=N: N AK-47 rounds into the pedestrian nearest `at` (FX_AT_PED=1, and FX_PED_PLACE=1
## to stand them in the road first), one every SHOT_GAP seconds of effect time (default 0.12).
## The first round puts them down; the rest go into the body where it lies. SHOT_YAW turns where
## the shooter stands round the target from the camera's line of sight, in degrees (default 90:
## from the left of the frame, so the exit spray crosses the picture; 0 = from the camera, 180 =
## towards it); SHOT_DIST is how far away (default 6 m), SHOT_HEIGHT where the rounds land on a
## standing person (default 1.25 m, the chest). SHOT_WEAPON=shotgun fires whole shotgun volleys
## instead (the gun's own _fire(), so pellets are summed per person). FX_PED_WALL=metres first stands the target that
## far in front of the first wall down the line of fire (wall splatter). The tracer still starts
## at the hero's muzzle. The log prints the blood counts after the burst.
func _rifle_burst(player: Node3D, at: Vector3, shots: int, forward: Vector3) -> void:
	var rifle: Node = null
	var manager: Node = player.get("weapon_manager")
	var want_shotgun := OS.get_environment("SHOT_WEAPON") == "shotgun"
	if manager:
		for w in manager.get_children():
			if (w.has_method("fire_pellet") if want_shotgun else w.has_method("fire_ray")):
				rifle = w
				break
	if rifle == null:
		print("FX_SHOOT: no %s on the player" % ("shotgun" if want_shotgun else "rifle"))
		return
	var yaw := deg_to_rad(_env_float("SHOT_YAW", 90.0))
	var dist := _env_float("SHOT_DIST", 6.0)
	var height := _env_float("SHOT_HEIGHT", 1.25)
	var gap := _env_float("SHOT_GAP", 0.12)
	var from_dir := (-forward).rotated(Vector3.UP, -yaw).normalized()
	var target: Node3D = null
	for p in get_nodes_in_group("pedestrian"):
		if target == null or (p as Node3D).global_position.distance_to(at) < target.global_position.distance_to(at):
			target = p
	# FX_PED_WALL=metres: find the first wall down the line of fire and stand the target that far
	# in front of it, so the exit spray reaches it.
	var wall_gap := _env_float("FX_PED_WALL", 0.0)
	if target and wall_gap > 0.0:
		var chest := target.global_position + Vector3.UP * height
		var space := target.get_world_3d().direct_space_state
		var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest - from_dir * 30.0, 1))
		if not wall.is_empty() and absf((wall.normal as Vector3).y) < 0.5:
			var spot: Vector3 = (wall.position as Vector3) + from_dir * wall_gap
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2.0, spot + Vector3.DOWN * 4.0, 1))
			spot.y = (down.position as Vector3).y if not down.is_empty() else target.global_position.y
			target.global_position = Vector3(spot.x, spot.y, spot.z)
			target.set("velocity", Vector3.ZERO)
			target.set("_pause_left", 30.0)
			print("stood the target %.1f m in front of %s at %s" % [wall_gap, (wall.collider as Node).name, spot.round()])
			for i in 2:
				await physics_frame
		else:
			print("FX_PED_WALL: no wall down the line of fire")
	var last := at
	for i in shots:
		var aim_at := last
		if is_instance_valid(target) and not target.is_queued_for_deletion():
			aim_at = target.global_position + Vector3.UP * height
		else:
			# Down: aim at the middle of the newest body near where they were.
			var body := _nearest_doll_body(last)
			if body:
				aim_at = body.global_transform * Vector3(0.0, 0.87, 0.0)
		last = aim_at
		var from := aim_at + from_dir * dist + Vector3.UP * 0.25
		if want_shotgun:
			# A whole volley, through the gun's own _fire(): pellets summed per person.
			rifle.call("_fire", {"origin": from, "direction": (aim_at - from).normalized()})
			print("volley %d at %s" % [i, aim_at.round()])
		else:
			var hit: Dictionary = rifle.fire_ray(from, (aim_at - from).normalized())
			var who: Object = hit.get("collider")
			print("shot %d at %s hit %s" % [i, aim_at.round(), (who as Node).name if who is Node else "nothing"])
		var waited := 0.0
		while waited < gap:
			await process_frame
			waited += get_root().get_process_delta_time()
	var fx: GDScript = load("res://scripts/weapons/weapon_fx.gd")
	if fx.get("blood_stats") != null:
		print("blood after the burst: live ", fx.call("blood_counts"), " totals ", fx.get("blood_stats"))


func _nearest_doll_body(near: Vector3) -> RigidBody3D:
	var best: RigidBody3D = null
	for d in get_nodes_in_group("debris"):
		if d.get_script() == null or d.get_script().get_global_name() != "Ragdoll":
			continue
		for b in (d as Node).get_children():
			if b is RigidBody3D and (best == null or (b as Node3D).global_position.distance_to(near) < best.global_position.distance_to(near)):
				best = b
	return best


## STREET=queue|crossing: the signalised junction nearest the point STREET_AHEAD metres ahead of
## the camera (default 38) gets a red for the road the camera looks along, and STREET_CARS cars
## (default 6) wait at its line in every lane of that approach, noses to the stop line; the
## traffic stops placing its own there (TrafficManager.staged). `crossing` also puts STREET_PEDS
## walkers (default 10) out on the crosswalk in front of the queue on their walking figure, from
## both kerbs, at seeded points of the way over. Loaded, not named: this script compiles before
## the autoloads exist.
func _stage_street(kind: String) -> void:
	var scene := current_scene
	var plan: Variant = scene.get("plan")
	var traffic := scene.get_node_or_null("Traffic")
	var cam := get_root().get_camera_3d()
	if plan == null or traffic == null or cam == null:
		print("STREET: nothing to stage with")
		return
	var ws := root.get_node("/root/WorldState")
	var signals: GDScript = load("res://scripts/world/traffic_signals.gd")
	var cp: Vector3 = ws.to_world(cam.global_position)
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var ahead := Vector2(cp.x, cp.z) + Vector2(fwd.x, fwd.z) * _env_float("STREET_AHEAD", 38.0)
	var bi: Vector2i = plan.block_index_at(ahead)
	var node := Vector2i.ZERO
	var best := INF
	for dx in [0, 1]:
		for dz in [0, 1]:
			var n: Vector2i = bi + Vector2i(dx, dz)
			if not signals.is_signal(plan, n.x, n.y):
				continue
			var d: float = (plan.intersection(n.x, n.y).pos as Vector2).distance_to(ahead)
			if d < best:
				best = d
				node = n
	if best == INF:
		print("STREET: no signalised junction near ", ahead)
		return
	# The approach the camera looks along, driving away from it into the junction.
	var axis := 0 if absf(fwd.z) >= absf(fwd.x) else 1
	var dir := (1 if fwd.z > 0.0 else -1) if axis == 0 else (1 if fwd.x > 0.0 else -1)
	var index: int = node.x if axis == 0 else node.y
	var cross_axis := 1 - axis
	var cross_index: int = node.y if axis == 0 else node.x
	var cross_pos: float = plan.road_pos(cross_axis, cross_index)
	var cw: float = plan.road_width(cross_axis, cross_index)
	# Red for this approach, three seconds in: the cross street is a moment into its green, so the
	# walking figure is up for anyone crossing in front of the queue.
	signals.force(plan, node.x, node.y, axis, 2, 3.0)
	traffic.set("staged", true)
	var cars: Array = traffic.get("cars")
	for c in cars.duplicate():
		if is_instance_valid(c) and int(c.traffic.get("axis", -1)) == axis and int(c.traffic.get("index", -99999)) == index:
			cars.erase(c)
			traffic.call("_retire", c)
	var line: float = cross_pos - float(dir) * (cw * 0.5 + float(traffic.get("stop_line_back")))
	var width: float = plan.road_width(axis, index)
	var lanes := 2 if width > float(plan.street_width) + 1.0 else 1
	var per := int(ceil(float(_env_int("STREET_CARS", 6)) / float(lanes)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([node, "street_shot"])
	for n in lanes:
		var nose := line - float(dir) * (0.6 + 2.5 * float(n))
		for k in per:
			var car: Node = traffic.call("place_car", axis, index, dir, n, line, 10.0, false)
			car.traffic.v = 0.0
			car.set("traffic_speed", 0.0)
			var half: float = car.traffic.half
			var along := nose - float(dir) * half
			var lane: float = car.traffic.lane
			var p2 := Vector2(plan.road_pos(axis, index) + lane, along) if axis == 0 else Vector2(along, plan.road_pos(axis, index) + lane)
			var h: float = traffic.call("_relief", p2)
			(car as Node3D).global_position = ws.to_local(Vector3(p2.x, 0.55 + h, p2.y))
			nose = along - float(dir) * (half + float(traffic.get("min_gap")) + rng.randf_range(0.1, 1.4))
	var placed := 0
	if kind == "crossing":
		# The crosswalk across this road on the near side of the junction, from both kerbs.
		var pos: Vector2 = plan.intersection(node.x, node.y).pos
		var side := -dir
		for k in _env_int("STREET_PEDS", 10):
			var q := 1 if k % 2 == 0 else -1
			var qx := q if axis == 0 else side
			var qz := side if axis == 0 else q
			var b := Vector2i(node.x + (0 if qx > 0 else -1), node.y + (0 if qz > 0 else -1))
			var chunk: Node3D = scene.get("chunks").get(b)
			if chunk == null:
				continue
			var rect: Rect2 = plan.block(b.x, b.y).rect
			var at := Vector2(rect.position.x + 2.0 if qx > 0 else rect.end.x - 2.0, rect.position.y + 2.5 if qz > 0 else rect.end.y - 2.5)
			var ped: Node3D = load("res://scripts/npc/pedestrian.gd").new()
			ped.call("setup", rect, float(plan.sidewalk_width), rng.randi())
			ped.set("cross_chance", 0.0)
			ped.position = Vector3(at.x, chunk.call("ground_y", at.x, at.y) + 0.1, at.y)
			chunk.add_child(ped)
			if ped.call("plan_crossing", axis):
				ped.call("cross_now", rng.randf_range(0.08, 0.85))
				placed += 1
	print("STREET %s at junction %s: %d lanes, %d walkers on the crosswalk, light %d" % [kind, node, lanes, placed, signals.light(plan, node.x, node.y, axis)])


static func _env_float(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback


## Keeps the player where the shot wants them: at the --spawn height, and for BOOST held in
## place mid-boost (the boost itself would carry them off between software frames).
func _pose(player: Node3D, anchor: Vector3, hold: Vector3, boost: bool, fov: float) -> void:
	if player == null:
		return
	_eye(player, fov)
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


## EYE=x,y,z,yaw,pitch: a free camera at that TRUE world point (yaw 0 looks north, 90 west, as
## --spawn does), the player hidden - for matching a reference photograph from a fixed viewpoint
## (a Street View car's lens is about 2.5 m above the road). FOV is the vertical field of view.
var _eye_cam: Camera3D


func _eye(player: Node3D, fov: float) -> void:
	var env := OS.get_environment("EYE")
	if env == "":
		return
	var p := env.split(",")
	if p.size() < 5:
		return
	var world_state := root.get_node_or_null("/root/WorldState")
	var offset: Vector3 = world_state.get("world_offset") if world_state else Vector3.ZERO
	var at := Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float()) - offset
	var player_cam := get_root().get_camera_3d() if _eye_cam == null else null
	if _eye_cam == null:
		_eye_cam = Camera3D.new()
		_eye_cam.name = "EyeCamera"
		root.add_child(_eye_cam)
		if player_cam:
			_eye_cam.attributes = player_cam.attributes
			_eye_cam.far = player_cam.far
			_eye_cam.near = player_cam.near
		_eye_cam.make_current()
	_eye_cam.fov = fov if fov > 0.0 else 45.0
	_eye_cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(p[4].to_float()), deg_to_rad(p[3].to_float()), 0.0)), at)
	player.visible = false
	# Keep the streaming centred where the camera is.
	player.global_position = Vector3(at.x, player.global_position.y, at.z)


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
