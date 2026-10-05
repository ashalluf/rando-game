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
## FOV camera field of view; BOOST=1 poses the player mid-boost (held in place), BOOST=fly really
## flies them (FLY_TIME, FLY_SCALE; see the block before the HUD); FX_AT=metres
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
## STREET_AHEAD / STREET_CARS / STREET_PEDS / STREET_FRAMES; STREET_MIX=14,15,16,17,18 makes the
## queue's cars those body types in turn). With --hour=21 it is the lit heads
## at night. STREET_EYE=1 then moves a free camera onto the pavement behind the queue, looking up
## it (STREET_EYE_BACK, _SIDE, _TURN, _HEIGHT, _PITCH).
## SHOTS="x,y,z,yaw,pitch@hour[@fov];..." then takes more EYE shots from the same load, saved as OUT
## with _1, _2, ... (SHOT_FRAMES frames each to stream in; GEO_n lines give each one's cost). An empty camera ("@21.5") is the last
## shot's camera at another hour.
## EYE=x,y,z,yaw,pitch puts a free camera at a true world point; with EYE_AGL=1 its y is metres
## above the ground there.
## Every shot also prints the frame's cost (GEO: triangles, draw calls, objects, split into the
## camera pass and the shadow passes); SPLIT=1 then hides one category at a time (cars, people,
## buildings, trees, props, far city, ...) with the world held still and prints what each costs,
## like tools/tri_split.gd but on the bookmark's exact frame, then the Building category again by
## node kind (BSPLIT lines: walls, facade detail, kit (surrounds, storefronts, awnings, curtain caps,
## the rest), roof plant, rooftop units, shop and blade-sign names).
## DIFF=1 makes a frame that renders the same twice, for before/after pixel diffs: shader TIME
## held at zero, the clock of day held at --hour, the signals on a fixed clock, and people, cars,
## aircraft, particles and the player hidden (two runs differ in a handful of pixels by 1-2/255).
## LIFE_REPORT=1 lists the people within 80 m of the camera doing something (crowd life), with
## true world positions to frame an EYE on; LIFE_FOCUS=jog|dog|talk|sit|stand|lean|window frames the
## nearest person doing that (LIFE_FOCUS_DIST metres off, default 5); CROWD_LIFE=0 turns the crowd's life off (the A/B).
## AFTERMATH=palms|burning|charred|column|crater stages what a blast leaves by the nearest palm
## row (tools/glshot/aftermath_stage.gd: AF_FIND, AF_TIME, AF_EYE_DIST, AF_FAR, ...).
## BIRD=ground|flush|wire stages birds ahead of the camera (BIRD_SPECIES, BIRD_DIST, BIRD_COUNT,
## BIRD_FLY; see the block before STREET); BIRDS=0 removes the birds (the A/B).
## ROOF_TRIS=1 prints what the rooftop units really cost (per instance, by the LOD rule).
## INDUSTRIAL=0 builds the industrial district without Industrial (Building warehouses on bare
## paving: the A/B of the warehouses, docks and yards).
## HOUSES=0 builds the suburbs' and the beach town's house lots as Building boxes again (HouseKit's
## A/B). YARD_FILL=0 builds the city without YardFill (beach-town yards, the campus's ground, the
## freeway's right of way: the A/B; SPLIT counts its two meshes in the LotFill line).
## STOREFRONT_KIT=0 builds the buildings without ShopfrontKit's storefront pieces, awnings and
## curtain-wall caps (the A/B of that kit). CAR_GLASS=0 puts every car back on its model's own
## opaque glass with nobody inside (CarCabin's A/B). CAR_LIGHTS=1 runs CarLights' real headlights
## on opengl3 too (Forward+ only in the game); every GEO line is followed by a LIGHTS line (car
## spot lights and street-lamp lights, on and in view). MERGE_STATIC=0 builds the chunks'
## solid boxes and the far landmarks one node per box again (CityChunk.merge_boxes,
## MultiMeshBatch.merge_enabled), the "before" side of that measurement.
## The frame-cost cuts of HANDOFF 9bf, each with its A/B: SHADOW_REACH=0 casts the facade kit's
## roofline (cornices, copings) to its draw distance again (MultiMeshBatch.shadow_reach_enabled),
## GROUND_SHADOW=0 casts the FULL chunks' whole ground grids again (CityChunk.ground_skirt_shadows),
## LAMPS_AT_ZERO=1 leaves the street lamps' lights shown at zero energy by day
## (DayNight.hide_dark_lamps).
## LIGHT_WORLD=1 loads a smaller world (far city LIGHT_FAR m, default 2500; LOD ring LIGHT_LOD
## blocks, default 4; fewer people and cars) so a Forward+ still under lavapipe fits in RAM.
## HIDE=Ground,Chunk_* hides every node whose name matches (String.match) just before the shot,
## to tell which layer a surface belongs to.
## PALM_AB=1 prints the same frame's GEO again with every palm at full detail (its level 0 and
## no LODs, in the view and the shadow) and saves that frame as <OUT>_palmfull.png: the A/B of
## the palms' hand-built LOD ladder (PropFactory.PALM_LEVELS) with the clock held still.
## TREE_AB=1 does the same for the scanned trees, bushes and flowers: the frame again with every
## one of them on the old generated LODs (the simplifier's own errors, the old shadow stand-ins,
## no instance-scale LOD bias), saved as <OUT>_treeold.png, then back on FoliageLod's ladders.
## TREE_AB=2 adds the parts: no instance bias, lower shadow-twin bias, old shadows, per group.
## MOTION_BLUR=1 leaves the camera's motion blur on (Forward+ only; off by default so a still
## is sharp). Traffic is allowed to build freely during the warm-up, so the streets look the way they do a
## minute into play rather than the first second of it.
func _initialize() -> void:
	# Stills are sharp: no motion blur (CameraPost; Forward+ only) unless MOTION_BLUR=1.
	if OS.get_environment("MOTION_BLUR") != "1":
		Engine.set_meta("postfx_motion_blur", 0.0)
	# DIFF=1: a frame that renders the same twice, for before/after pixel diffs. Shader TIME is
	# held at zero (it only ever runs to the rollover, so a microsecond one keeps clouds, sway,
	# water and the film grain at their first instant), the global rng is seeded, the clock of
	# day is held at --hour, and everything that moves by itself - people, cars, aircraft,
	# particles, the player - is hidden for the shot (_diff_freeze()).
	if OS.get_environment("DIFF") == "1":
		ProjectSettings.set_setting("rendering/limits/time/time_rollover_secs", 0.000001)
		seed(12345)
	# MERGE_STATIC=0: the chunks' solid boxes and the far landmarks' boxes one node each, as
	# before they were merged (the A/B of that change). Through the script resources, not the
	# class names: CityChunk uses autoloads, and this script compiles before they exist.
	# STOREFRONT_KIT=0: the buildings without ShopfrontKit's pieces (the A/B of that kit).
	if OS.get_environment("STOREFRONT_KIT") == "0":
		(load("res://scripts/world/shopfront_kit.gd") as GDScript).set("enabled", false)
	# YARD_FILL=0: the city without YardFill's yards, campus ground and right of way (the A/B).
	# INDUSTRIAL=0: the industrial district as it was before Industrial (the A/B).
	if OS.get_environment("INDUSTRIAL") == "0":
		(load("res://scripts/world/industrial.gd") as GDScript).set("enabled", false)
	if OS.get_environment("YARD_FILL") == "0":
		(load("res://scripts/world/yard_fill.gd") as GDScript).set("enabled", false)
	# HOUSES=0: the suburbs' and the beach town's house lots as Building boxes (HouseKit's A/B).
	if OS.get_environment("HOUSES") == "0":
		(load("res://scripts/world/house_kit.gd") as GDScript).set("enabled", false)
	# CAR_GLASS=0: every car on its model's own opaque glass, nobody inside (CarCabin's A/B).
	# CAR_LIGHTS=1: CarLights' real headlights on the Compatibility renderer too (they are
	# Forward+ only in the game), so an opengl3 still shows where they fall.
	if OS.get_environment("CAR_LIGHTS") == "1":
		(load("res://scripts/vehicles/car_lights.gd") as GDScript).set("force", true)
	if OS.get_environment("CAR_GLASS") == "0":
		(load("res://scripts/vehicles/car_cabin.gd") as GDScript).set("enabled", false)
	if OS.get_environment("MERGE_STATIC") == "0":
		(load("res://scripts/world/city_chunk.gd") as GDScript).set("merge_boxes", false)
		(load("res://scripts/util/multimesh_batch.gd") as GDScript).set("merge_enabled", false)
	_audit_toggles()
	if OS.get_environment("LIGHT_WORLD") == "1":
		# A smaller world for Forward+ (lavapipe) stills: a whole city under lavapipe grows past
		# the box's RAM (killed at 12 GB, HIGH and MEDIUM alike), so the far city, the LOD ring
		# and the crowd and traffic caps come down before the streamer's _ready builds anything.
		var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
		city.set("far_city_radius", _env_float("LIGHT_FAR", 2500.0))
		city.set("far_city_immediate_radius", _env_float("LIGHT_FAR", 2500.0))
		city.set("lod_radius_blocks", _env_int("LIGHT_LOD", 4))
		city.set("keep_radius_blocks", _env_int("LIGHT_LOD", 4))
		city.set("max_pedestrians", 160)
		city.set("traffic_cars", 40)
		root.add_child.call_deferred(city)
		set_deferred("current_scene", city)
	else:
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
		if OS.get_environment("DIFF") == "1":
			var day_n := scene.get_node_or_null("DayNight")
			if day_n:
				day_n.call("set_paused", true)
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
	# BOOST=fly: really boost along the camera for FLY_TIME seconds of game time (default 1.2),
	# the clock slowed to FLY_SCALE so the trail is laid down at the rate a real frame rate lays
	# it, then shoot from behind as usual. Godot caps a frame at eight physics ticks however long
	# it really takes, so the default 0.125 is one tick a (slow) software frame; 0.02 was a sixth
	# of a tick and a flight took twenty minutes.
	if OS.get_environment("BOOST") == "fly" and player:
		_flying = true
		player.set("velocity", Vector3.ZERO)
		Input.action_press("boost")
		Engine.time_scale = _env_float("FLY_SCALE", 0.125)
		var flown := 0.0
		var fly_time := _env_float("FLY_TIME", 1.2)
		var fly_frames := 0
		while flown < fly_time:
			await process_frame
			flown += get_root().get_process_delta_time()
			fly_frames += 1
			if fly_frames % 20 == 0:
				print("fly: frame %d, %.2f s, %.1f m/s" % [fly_frames, flown, (player.get("velocity") as Vector3).length()])
		print("fly: %.2f s at %.1f m/s, now at %s" % [flown, (player.get("velocity") as Vector3).length(), player.global_position])
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
			var ws_air := root.get_node("/root/WorldState")
			print("AIR staged ", placed.name if placed else "nothing", " at world ", ws_air.call("to_world", (placed as Node3D).global_position) if placed else Vector3.ZERO,
				" camera world ", ws_air.call("to_world", air_cam.global_position), " visible ", (placed as Node3D).is_visible_in_tree() if placed else false)
			for i in _env_int("AIR_FRAMES", 4):
				await process_frame
				_pose(player, anchor, hold, boost, fov)
		else:
			print("AIR: no AirTraffic in the scene")
	# BIRD=ground|flush|wire: birds for the shot (Birds.stage_for_shot): a flock of BIRD_SPECIES
	# (default pigeon; crow for a wire) BIRD_DIST metres ahead of the camera (default 9) on the
	# ground, the same flock bursting up BIRD_FLY seconds after the camera flushed it (default
	# 0.7), or BIRD_COUNT crows on the power line nearest that point. BIRDS=0 removes every bird.
	var bird_env := OS.get_environment("BIRD")
	if bird_env != "" and current_scene:
		var birds_node := current_scene.get_node_or_null("Birds")
		var bcam := get_root().get_camera_3d()
		if birds_node and bcam:
			birds_node.call("stage_for_shot", bird_env, bcam, _env_float("BIRD_DIST", 9.0), OS.get_environment("BIRD_SPECIES"), _env_int("BIRD_COUNT", 24), _env_float("BIRD_FLY", 0.7))
			for i in 2:
				await process_frame
				_pose(player, anchor, hold, boost, fov)
		else:
			print("BIRD: no Birds node or camera")
	# STREET=queue|crossing: a signalised junction ahead of the camera, a queue at its red, and
	# for `crossing` people out on the crosswalk in front of it (see _stage_street).
	var street_env := OS.get_environment("STREET")
	if street_env != "" and current_scene:
		_stage_street(street_env)
		for i in _env_int("STREET_FRAMES", 8):
			await process_frame
			_pose(player, anchor, hold, boost, fov)
	# BIG=bus|semi: a bus standing at its stop (doors open, kneeling) or a semi on the freeway
	# nearest the camera, and a free camera framing it (see _stage_big).
	var big_env := OS.get_environment("BIG")
	if big_env != "" and current_scene:
		_stage_big(big_env)
		_eye(player, fov)
		if current_scene.has_method("update_streaming"):
			current_scene.call("update_streaming", true)
		for i in _env_int("BIG_FRAMES", 40):
			await process_frame
			_pose(player, anchor, hold, boost, fov)
	# EMERGENCY=fire|hose|medic|station: a fire engine and an ambulance at work in front of the
	# camera, or the nearest fire station (Emergency.stage_for_shot), framed by a free camera.
	var em_env := OS.get_environment("EMERGENCY")
	if em_env != "" and current_scene and current_scene.get_node_or_null("Emergency"):
		var em_eye: String = await current_scene.get_node("Emergency").call("stage_for_shot", em_env, get_root().get_camera_3d())
		if em_eye != "":
			OS.set_environment("EYE", em_eye)
		print("EMERGENCY %s eye %s" % [em_env, em_eye])
		_eye(player, fov)
		if current_scene.has_method("update_streaming"):
			current_scene.call("update_streaming", true)
		for i in _env_int("EMERGENCY_FRAMES", 30):
			await process_frame
			_pose(player, anchor, hold, boost, fov)
	# AFTERMATH=palms|burning|charred|column|crater: what a blast leaves behind, staged by the
	# nearest palm row and framed by a free camera (tools/glshot/aftermath_stage.gd), then AF_TIME
	# seconds of it at FX_SCALE.
	var af_env := OS.get_environment("AFTERMATH")
	if af_env != "" and current_scene:
		var af_eye: String = load("res://tools/glshot/aftermath_stage.gd").stage(self, af_env, get_root().get_camera_3d())
		if af_eye != "":
			OS.set_environment("EYE", af_eye)
		print("AFTERMATH %s eye %s" % [af_env, af_eye])
		_eye(player, fov)
		if current_scene.has_method("update_streaming"):
			current_scene.call("update_streaming", true)
		Engine.time_scale = _env_float("FX_SCALE", 0.375)
		var af_t := 0.0
		while af_t < _env_float("AF_TIME", 0.3):
			await process_frame
			af_t += get_root().get_process_delta_time()
			_pose(player, anchor, hold, boost, fov)
	# Then all but freeze the clock for the last frames: a software frame takes seconds, and at
	# normal speed everything that moves - people, traffic, leaves, fire - smears under TAA.
	# Held still, TAA and the GI converge on one instant, as crisp as it is on the Mac.
	Engine.time_scale = float(OS.get_environment("TIME_SCALE")) if OS.get_environment("TIME_SCALE") != "" else 0.0005
	if OS.get_environment("DIFF") == "1":
		_diff_freeze(player)
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
			var nl := car.get_node_or_null("NightLights") as MeshInstance3D
			if nl:
				var lm := nl.material_override as ShaderMaterial
				print("car %s %s lamps visible=%s in_tree=%s brake=%s signal=%s traffic=%s seats=%s" % [car.name, car.call("display_name"), nl.visible, nl.is_visible_in_tree(), lm.get_shader_parameter("brake") if lm else "-", lm.get_shader_parameter("signal_side") if lm else "-", car.call("is_traffic"), car.call("cabin_seats")])
			for mi in car.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial if (mi as MeshInstance3D).get_surface_override_material_count() > 0 else null
				if m and m.get_shader_parameter("paint") != null:
					print("car %s at %s px %s paint %s metal %.2f geo_glass %s" % [car.name, cp.round(), gib_cam.unproject_position(cp).round(), m.get_shader_parameter("paint"), m.get_shader_parameter("paint_metallic"), m.get_shader_parameter("geo_glass")])
					break
	var day := current_scene.get_node_or_null("DayNight") if current_scene else null
	if day:
		print("clock ", day.clock_text())
	# HIDE=pattern,pattern hides every node whose name matches one of them (String.match
	# wildcards: Ground, Chunk_*, Skyline) for the shot, so a layer can be told apart from the
	# ones behind it - which tier a surface in the frame belongs to, say.
	var hide_env := OS.get_environment("HIDE")
	if hide_env != "" and current_scene:
		var hidden := 0
		for pat in hide_env.split(","):
			for n in current_scene.find_children(pat, "Node3D", true, false):
				(n as Node3D).visible = false
				hidden += 1
		print("HIDE %s: %d nodes" % [hide_env, hidden])
		for i in 3:
			await process_frame
	# LIFE_FOCUS=jog|dog|talk|sit|stand|lean|window: the camera moves to frame the nearest person
	# (within 120 m) doing that, from LIFE_FOCUS_DIST metres (default 5) off their right front.
	var focus := OS.get_environment("LIFE_FOCUS")
	if focus != "" and current_scene:
		var acts_by := {"stand": 1, "lean": 2, "window": 3, "talk": 4, "sit": 5}
		var cam0 := get_root().get_camera_3d()
		var best: Node3D = null
		var best_d := 120.0
		for n in get_nodes_in_group("pedestrian"):
			var p := n as Node3D
			var ok := false
			match focus:
				"jog":
					ok = bool(p.get("_jogger"))
				"dog":
					ok = bool(p.get("_dog_walker"))
				_:
					ok = p.get("_act") != null and int(p.get("_act")) == int(acts_by.get(focus, -1)) and int(p.get("_stage")) == 2
			if ok and cam0 and p.global_position.distance_to(cam0.global_position) < best_d:
				best_d = p.global_position.distance_to(cam0.global_position)
				best = p
		if best:
			var vis: Node3D = best.get("_visual")
			var yaw := vis.global_rotation.y if vis else 0.0
			var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var right := Vector3(cos(yaw), 0.0, -sin(yaw))
			var dist := _env_float("LIFE_FOCUS_DIST", 5.0)
			var target := best.global_position + Vector3.UP * 1.0
			var cam_at := best.global_position + (fwd * 0.8 + right * 0.6).normalized() * dist + Vector3.UP * 1.6
			var d := target - cam_at
			var cyaw := rad_to_deg(atan2(-d.x, -d.z))
			var cpitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
			var world: Vector3 = root.get_node("/root/WorldState").to_world(cam_at)
			OS.set_environment("EYE", "%.2f,%.2f,%.2f,%.2f,%.2f" % [world.x, world.y, world.z, cyaw, cpitch])
			print("LIFE focus %s at %s, eye %s" % [focus, root.get_node("/root/WorldState").to_world(best.global_position), OS.get_environment("EYE")])
			_eye(player, _env_float("FOV", 45.0))
			for i in 4:
				await process_frame
		else:
			print("LIFE focus %s: nobody in range" % focus)
	# LIFE_REPORT=1: every pedestrian within 80 m of the camera that is doing something (crowd
	# life: Pedestrian._act, CrowdLife.Act) with its true world position, to frame a shot on.
	if OS.get_environment("LIFE_REPORT") == "1":
		var cam := get_root().get_camera_3d()
		var acts := ["none", "stand", "lean", "window", "talk", "sit"]
		var counts := {}
		for n in get_nodes_in_group("pedestrian"):
			var p := n as Node3D
			if cam == null or p.global_position.distance_to(cam.global_position) > 80.0:
				continue
			var act: int = int(p.get("_act")) if p.get("_act") != null else 0
			var key: String = acts[act] + ("/jog" if p.get("_jogger") else "") + ("/dog" if p.get("_dog_walker") else "")
			counts[key] = int(counts.get(key, 0)) + 1
			if act != 0 or p.get("_jogger") or p.get("_dog_walker"):
				print("LIFE %s at %s clip %s carry %s" % [key, (get_root().get_node("/root/WorldState").to_world(p.global_position) as Vector3).snapped(Vector3.ONE * 0.1), p.get("_clip"), p.get("_carry")])
		print("LIFE counts ", counts)
	var out := OS.get_environment("OUT")
	if out == "":
		out = "still.png"
	var img := get_root().get_texture().get_image()
	if img:
		img.save_png(out)
		print("saved ", out)
	# The frame's cost, split into the camera's pass and the shadow passes (the counters are
	# real here: this runs under opengl3 or vulkan, never --headless). SPLIT=1 then hides one
	# category at a time, the world held still, as tools/tri_split.gd does - so every bookmark
	# still also gives a cost table for the exact frame it shot.
	await _geo_report("GEO")
	if OS.get_environment("ROOF_TRIS") == "1":
		_roof_unit_tris()
	if OS.get_environment("PALM_AB") == "1":
		# Every palm drawn at full detail (its level 0 with no LODs), in the view and the shadow,
		# for the same frame: what the hand-built ladder (PropFactory.PALM_LEVELS) changes.
		var factory = load("res://scripts/world/prop_factory.gd")
		var swap := {}
		for v in factory.PALM_VARIANTS:
			var full := ArrayMesh.new()
			full.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, factory._palm_level(v, factory.PALM_LEVELS[0]))
			full.surface_set_material(0, factory.foliage_material())
			var mesh: Mesh = factory.palm(v)
			swap[mesh] = full
			if factory.shadow_proxy(mesh):
				swap[factory.shadow_proxy(mesh)] = full
		var back := {}
		for n in current_scene.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm and swap.has(mm.mesh):
				back[mm] = mm.mesh
				mm.mesh = swap[mm.mesh]
		await _geo_report("GEO palms full (%d batches)" % back.size())
		img = get_root().get_texture().get_image()
		if img:
			img.save_png(out.get_basename() + "_palmfull.png")
		for mm: MultiMesh in back:
			mm.mesh = back[mm]
		await _geo_report("GEO palms ladder")
	if OS.get_environment("TREE_AB") in ["1", "2"]:
		await _tree_ab(out)
	if OS.get_environment("SPLIT") == "1":
		await _geo_split(player, anchor, hold, boost, fov)
	# SHOTS="x,y,z,yaw,pitch@hour[@fov];..." takes more EYE shots from the same load (the load is most
	# of a shot's eight minutes): each moves the free camera there, sets the hour, streams the
	# chunks round it in at once, runs SHOT_FRAMES frames and saves OUT with _1, _2, ... added.
	var shots_env := OS.get_environment("SHOTS")
	var streamer := current_scene
	var k := 0
	for entry in shots_env.split(";", false):
		k += 1
		var bits := entry.split("@")
		# An empty camera ("@21.5") keeps the last one: the same frame at another hour.
		if bits[0] != "":
			OS.set_environment("EYE", bits[0])
		if bits.size() > 1 and day and bits[1] != "":
			day.set("hour", bits[1].to_float())
		Engine.time_scale = 1.0
		# A third field is this shot's own field of view ("x,y,z,yaw,pitch@hour@fov").
		if bits.size() > 2:
			fov = bits[2].to_float()
		_eye(player, fov)
		if streamer and streamer.has_method("update_streaming"):
			streamer.call("update_streaming", true)
		for i in _env_int("SHOT_FRAMES", 24):
			await process_frame
			_pose(player, anchor, hold, boost, fov)
		Engine.time_scale = 0.0005
		for i in _env_int("SETTLE", 6):
			await process_frame
			_pose(player, anchor, hold, boost, fov)
		var more := out.get_basename() + "_%d.png" % k
		get_root().get_texture().get_image().save_png(more)
		print("saved ", more, " at ", bits[0], " hour ", bits[1] if bits.size() > 1 else "-")
		await _geo_report("GEO_%d" % k)
	quit()


## TREE_AB: every batch of a scanned plant on its FoliageLod ladder redrawn with the old mesh
## (PropFactory.foliage_ladders off: the generated LODs at the simplifier's errors, the old
## shadow stand-in), lod bias 1 as before, for one frame; then everything put back.
## TREE_AB=2 also prints, for the same frame: the ladders with no instance-scale bias, the
## shadow twins at the tree's own LOD bias and at 0.3 of it (FoliageLod.SHADOW_LOD_SCALE is
## 0.5), the old shadows under the new trees, and each group of
## plants (the five city trees, the hill trees, the bushes, the rest) put back on its old mesh
## alone - what each part of the change costs or saves.
func _tree_ab(out: String) -> void:
	var factory = load("res://scripts/world/prop_factory.gd")
	var getters := [["model_tree", factory.CITY_TREES], ["model_hill_tree", factory.HILL_TREES],
		["model_bush", factory.BUSHES], ["model_plant", factory.PLANTS],
		["model_flower", factory.FLOWERS], ["model_grass_clump", factory.GRASS_CLUMPS]]
	var swap := {}
	var file_of := {}
	for g: Array in getters:
		for v in (g[1] as Array).size():
			factory.foliage_ladders = true
			var now: Mesh = factory.call(g[0], v)
			factory.foliage_ladders = false
			var old: Mesh = factory.call(g[0], v)
			if now != old and now.has_meta("foliage_ladder"):
				swap[now] = old
				file_of[now] = g[1][v]
	factory.foliage_ladders = true
	var entries: Array = []
	for n in current_scene.find_children("Batch_*", "MultiMeshInstance3D", true, false):
		var node := n as MultiMeshInstance3D
		var mm := node.multimesh
		if mm == null or not swap.has(mm.mesh):
			continue
		var twin: MultiMeshInstance3D = node.get_meta("shadow_twin") if node.has_meta("shadow_twin") else null
		entries.append({"node": node, "new": mm.mesh, "old": swap[mm.mesh], "twin": twin,
			"twin_mesh": twin.multimesh.mesh if twin else null, "old_proxy": factory.shadow_proxy(swap[mm.mesh]),
			"bias": node.lod_bias, "twin_factor": twin.lod_bias / maxf(node.lod_bias, 1e-6) if twin else 1.0,
			"cast": node.cast_shadow, "file": file_of[mm.mesh]})
	for e: Dictionary in entries:
		_ab_set(e, true, true, 1.0, 1.0)
	await _geo_report("GEO trees old (%d batches)" % entries.size())
	_true_tris("TRUE trees old", entries)
	var img := get_root().get_texture().get_image()
	if img:
		img.save_png(out.get_basename() + "_treeold.png")
	for e: Dictionary in entries:
		_ab_set(e, false, false, e.bias, e.twin_factor)
	await _geo_report("GEO trees ladder")
	_true_tris("TRUE trees ladder", entries)
	if OS.get_environment("TREE_AB") == "2":
		for e: Dictionary in entries:
			_ab_set(e, false, false, 1.0, e.twin_factor)
		await _geo_report("GEO ab ladders, no instance bias")
		for f in [1.0, 0.3]:
			for e: Dictionary in entries:
				_ab_set(e, false, false, e.bias, f)
			await _geo_report("GEO ab ladders, shadow twin bias x%.1f" % f)
			_true_tris("TRUE ab ladders, shadow twin bias x%.1f" % f, entries)
		for e: Dictionary in entries:
			_ab_set(e, false, true, e.bias, 1.0)
		await _geo_report("GEO ab ladders, old shadows")
		var groups := {"tree_a": ["tree_a.glb"], "tree_b": ["tree_b.glb"], "tree_c": ["tree_c.glb"], "tree_d": ["tree_d.glb"],
			"jacaranda": ["tree_jacaranda.glb"], "hill trees": factory.HILL_TREES, "bushes": factory.BUSHES}
		var grouped := []
		for gname: String in groups:
			grouped.append_array(groups[gname])
		groups["plants, flowers, grass"] = []
		for e: Dictionary in entries:
			if not grouped.has(e.file) and not (groups["plants, flowers, grass"] as Array).has(e.file):
				groups["plants, flowers, grass"].append(e.file)
		for gname: String in groups:
			var n := 0
			for e: Dictionary in entries:
				var inside: bool = (groups[gname] as Array).has(e.file)
				n += 1 if inside else 0
				_ab_set(e, inside, inside, 1.0 if inside else e.bias, 1.0 if inside else e.twin_factor)
			if n > 0:
				_true_tris("TRUE ab only %s old (%d batches)" % [gname, n], entries)
		for e: Dictionary in entries:
			_ab_set(e, false, false, e.bias, e.twin_factor)
	for e: Dictionary in entries:
		if e.has("extra"):
			(e.extra as Node).queue_free()


## What the TREE_AB batches really cost the frame, counted the way the GPU draws them: every
## instance. The renderer's own counters cannot be used for this: Compatibility adds a surface
## that has LODs ONCE per draw call, whatever its instance count, and one without LODs once per
## instance (rasterizer_scene_gles3.cpp, _fill_render_list), so a batch of forty trees counts as
## one tree or as forty depending on whether its last level happens to have a LOD below it -
## which is exactly what differs between the old meshes and the ladders. So: each batch's LOD per
## surface by the renderer's rule (distance from the camera to the batch's box, times the lod
## bias, against the viewport's mesh_lod_threshold in pixels), times its instances; in the view
## if its box meets the camera frustum; in the shadow once per cascade whose slice sphere it
## meets, swept 150 m back towards the sun (4 splits at the Sun's split distances, out to its
## max distance) - on a controlled scene that draws each batch into the same number of cascades
## as the renderer does.
func _true_tris(label: String, entries: Array) -> void:
	var cam := get_root().get_camera_3d()
	var vp := get_root()
	var width := float(vp.get_visible_rect().size.x)
	var threshold := vp.mesh_lod_threshold / maxf(width, 1.0)
	var multiplier := cam.get_camera_projection().get_lod_multiplier()
	var planes := cam.get_frustum()
	var sun: DirectionalLight3D = null
	for n in current_scene.find_children("*", "DirectionalLight3D", true, false):
		if (n as DirectionalLight3D).shadow_enabled:
			sun = n
			break
	# Each cascade's slice of the view frustum (its own near and far at the split distances),
	# and the way to the sun: a caster between the slice and the sun shades it too.
	var slices: Array = []
	var to_sun := Vector3.UP
	if sun:
		to_sun = sun.global_transform.basis.z
		var splits := [0.0, sun.directional_shadow_split_1, sun.directional_shadow_split_2, sun.directional_shadow_split_3, 1.0]
		var far := sun.directional_shadow_max_distance
		var fwd := -cam.global_transform.basis.z
		for k in 4:
			var near_d := maxf(float(splits[k]) * far, cam.near)
			var far_d := float(splits[k + 1]) * far
			var pl: Array = [planes[2], planes[3], planes[4], planes[5]]
			pl.append(Plane(-fwd, cam.global_position + fwd * near_d))
			pl.append(Plane(fwd, cam.global_position + fwd * far_d))
			slices.append(pl)
	var cam_tris := 0
	var shadow_tris := 0
	for e: Dictionary in entries:
		var node: MultiMeshInstance3D = e.node
		if not node.is_visible_in_tree():
			continue
		var box: AABB = node.global_transform * node.get_aabb()
		var n := node.multimesh.instance_count
		var reach := Vector3.ZERO.max(box.position - cam.global_position).max(cam.global_position - box.end).length()
		if node.visibility_range_end > 0.0 and reach > node.visibility_range_end:
			continue
		if node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and _box_in_frustum(box, planes):
			cam_tris += _lod_tris(node.multimesh.mesh, box, cam.global_position, node.lod_bias, multiplier, threshold) * n
		var casters: Array = []
		if node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters.append(node)
		for extra: Variant in [e.twin, e.get("extra")]:
			if extra != null and (extra as GeometryInstance3D).is_visible_in_tree():
				casters.append(extra)
		var swept := box.merge(AABB(box.position - to_sun * 150.0, box.size))
		var cascades := 0
		for sl: Array in slices:
			if _box_in_frustum(swept, sl):
				cascades += 1
		for caster: MultiMeshInstance3D in casters:
			if cascades > 0:
				shadow_tris += _lod_tris(caster.multimesh.mesh, box, cam.global_position, caster.lod_bias, multiplier, threshold) * n * cascades
	print("%s camera tris=%d shadow tris=%d total=%d (every instance counted; %d batches)" % [label, cam_tris, shadow_tris, cam_tris + shadow_tris, entries.size()])


## One instance's triangles of `mesh` at the LOD the renderer picks for a batch with box `box`.
static func _lod_tris(mesh: Mesh, box: AABB, eye: Vector3, bias: float, multiplier: float, threshold: float) -> int:
	var d := Vector3.ZERO.max(box.position - eye).max(eye - box.end).length()
	var tot := 0
	for s in mesh.get_surface_count():
		var surf := RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		var count := int(surf.get("index_count", 0))
		var per := float((surf.get("index_data", PackedByteArray()) as PackedByteArray).size()) / maxf(float(count), 1.0)
		var pick := count
		for lod: Dictionary in surf.get("lods", []):
			if float(lod.edge_length) * bias / maxf(d * multiplier, 1e-6) <= threshold:
				pick = int(float((lod.index_data as PackedByteArray).size()) / per)
			else:
				break
		tot += pick / 3
	return tot


static func _box_in_frustum(box: AABB, planes: Array) -> bool:
	for pl: Plane in planes:
		var outside := true
		for i in 8:
			if not pl.is_point_over(box.get_endpoint(i)):
				outside = false
				break
		if outside:
			return false
	return true


## One TREE_AB batch drawn with its old or new mesh in the view and in the shadow, at lod bias
## `bias` (the twin at `bias * twin_factor`).
func _ab_set(e: Dictionary, camera_old: bool, shadow_old: bool, bias: float, twin_factor: float) -> void:
	var node: MultiMeshInstance3D = e.node
	node.multimesh.mesh = e.old if camera_old else e.new
	node.lod_bias = 1.0 if camera_old else bias
	var twin: MultiMeshInstance3D = e.twin
	var old_shadow: Mesh = e.old_proxy
	if twin:
		twin.visible = true
		if shadow_old:
			twin.multimesh.mesh = old_shadow if old_shadow else e.old
			twin.lod_bias = 1.0
		else:
			twin.multimesh.mesh = e.twin_mesh
			twin.lod_bias = bias * twin_factor
		return
	# The ladder casts from the batch itself; the old mesh had a stand-in.
	if shadow_old and old_shadow:
		if not e.has("extra"):
			var extra := MultiMeshInstance3D.new()
			extra.name = "TreeAbShadow"
			var emm := MultiMesh.new()
			emm.transform_format = MultiMesh.TRANSFORM_3D
			emm.use_colors = true
			emm.use_custom_data = true
			emm.mesh = old_shadow
			emm.instance_count = node.multimesh.instance_count
			emm.buffer = node.multimesh.buffer
			extra.multimesh = emm
			extra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			node.add_sibling(extra)
			extra.transform = node.transform
			e.extra = extra
		(e.extra as Node3D).visible = true
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		if e.has("extra"):
			(e.extra as Node3D).visible = false
		node.cast_shadow = e.cast


## SHADOW_REACH=0, GROUND_SHADOW=0, LAMPS_AT_ZERO=1: the "before" sides of HANDOFF 9bf's cuts.
## Through the script resources (this compiles before the autoloads Building and DayNight use).
## Shared with tools/gpu_profile.gd.
static func _audit_toggles() -> void:
	if OS.get_environment("SHADOW_REACH") == "0":
		(load("res://scripts/util/multimesh_batch.gd") as GDScript).set("shadow_reach_enabled", false)
	if OS.get_environment("GROUND_SHADOW") == "0":
		(load("res://scripts/world/city_chunk.gd") as GDScript).set("ground_skirt_shadows", false)
	if OS.get_environment("LAMPS_AT_ZERO") == "1":
		(load("res://scripts/world/day_night.gd") as GDScript).set("hide_dark_lamps", false)


func _geo_counts() -> Array:
	var vp := get_root()
	var vis := Viewport.RENDER_INFO_TYPE_VISIBLE
	var sh := Viewport.RENDER_INFO_TYPE_SHADOW
	return [int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		vp.get_render_info(vis, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		vp.get_render_info(sh, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		vp.get_render_info(vis, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(sh, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)]


func _geo_report(label: String) -> Array:
	await process_frame
	await process_frame
	var c := _geo_counts()
	print("%s tris=%d draws=%d objects=%d | camera tris=%d draws=%d | shadow tris=%d draws=%d" % [
		label, c[0], c[1], c[2], c[3], c[5], c[4], c[6]])
	_light_report(label)
	return c


## The real lights in the frame: CarLights' spots (and how many of them are in view), the street
## lamps' omni lights in view (their whole range box against the frustum, as the renderer culls).
func _light_report(label: String) -> void:
	var cam := get_root().get_camera_3d()
	if cam == null:
		return
	var frustum := cam.get_frustum()
	var counts := [0, 0, 0, 0] # car lights on, car lights in view, lamps on, lamps in view
	for n in get_root().find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if not l.is_visible_in_tree() or l.light_energy <= 0.0 or l is DirectionalLight3D:
			continue
		var car := String(l.get_parent().name) == "CarLights"
		var reach := (l as SpotLight3D).spot_range if l is SpotLight3D else (l as OmniLight3D).omni_range if l is OmniLight3D else 0.0
		var inside := true
		for plane: Plane in frustum:
			if plane.distance_to(l.global_position) > reach:
				inside = false
				break
		var k := 0 if car else 2
		counts[k] += 1
		if inside:
			counts[k + 1] += 1
	print("LIGHTS %s car=%d (in view %d) lamps=%d (in view %d)" % [label, counts[0], counts[1], counts[2], counts[3]])


const SPLIT_CATEGORIES := ["Vehicle", "Pedestrian", "Building", "Trees", "Grass", "Camp", "LotFill", "Houses", "Industrial", "Parks", "River", "LightRail", "Birds", "Billboards", "Vendors", "PhysProps", "StreetProps", "FarCity", "FarGround", "Landmark", "Other"]


func _geo_split(player: Node3D, anchor: Vector3, hold: Vector3, boost: bool, fov: float) -> void:
	var nodes := {}
	for c in SPLIT_CATEGORIES:
		nodes[c] = []
	for n in current_scene.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.is_visible_in_tree():
			nodes[_split_category(gi)].append(gi)
	_pose(player, anchor, hold, boost, fov)
	var base := await _geo_report("SPLIT base")
	for c in SPLIT_CATEGORIES:
		var list: Array = nodes[c]
		if list.is_empty():
			continue
		for gi: GeometryInstance3D in list:
			if is_instance_valid(gi):
				gi.visible = false
		var hidden := await _geo_report("  (hidden %s)" % c)
		for gi: GeometryInstance3D in list:
			if is_instance_valid(gi):
				gi.visible = true
		print("SPLIT %-12s nodes %5d  tris %9d (%4.1f%%)  draws %5d  objects %5d  | shadow tris %9d draws %5d" % [
			c, list.size(), base[0] - hidden[0], 100.0 * (base[0] - hidden[0]) / maxf(base[0], 1),
			base[1] - hidden[1], base[2] - hidden[2], base[4] - hidden[4], base[6] - hidden[6]])
	# OSPLIT=1: the Other and StreetProps categories again by node name stem, the 30 stems with
	# the most estimated triangles (LOD 0 x instances) hidden one at a time.
	if OS.get_environment("OSPLIT") == "1":
		var stems := {}
		var est := {}
		for c in ["Other", "StreetProps", "LightRail", "River", "Parks", "Houses", "Industrial"]:
			for gi: GeometryInstance3D in nodes[c]:
				if not is_instance_valid(gi):
					continue
				var stem: String = c + "/" + String(gi.name).rstrip("0123456789_").replace("BatchShadow_", "Batch_")
				if not stems.has(stem):
					stems[stem] = []
					est[stem] = 0
				(stems[stem] as Array).append(gi)
				est[stem] += _est_tris(gi)
		var order := stems.keys()
		order.sort_custom(func(a, b): return est[a] > est[b])
		for k: String in order.slice(0, 30):
			var list: Array = stems[k]
			for gi: GeometryInstance3D in list:
				gi.visible = false
			var hidden := await _geo_report("  (hidden %s)" % k)
			for gi: GeometryInstance3D in list:
				gi.visible = true
			if k.contains("@"):
				var by := {}
				for gi: GeometryInstance3D in list:
					var mat: Material = gi.material_override
					if mat == null and gi is MeshInstance3D and (gi as MeshInstance3D).mesh and (gi as MeshInstance3D).mesh.get_surface_count() > 0:
						mat = (gi as MeshInstance3D).mesh.surface_get_material(0)
					var mk := ""
					if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
						mk = (mat as ShaderMaterial).shader.resource_path.get_file()
					elif mat:
						mk = mat.get_class()
					var pk := "%s %s" % [String(gi.get_parent().name).rstrip("0123456789_-"), mk]
					by[pk] = int(by.get(pk, 0)) + _est_tris(gi)
				var pks := by.keys()
				pks.sort_custom(func(a, b): return by[a] > by[b])
				for pk in pks.slice(0, 8):
					print("OSPLIT   by %-40s est tris %d" % [pk, by[pk]])
			print("OSPLIT %-36s nodes %5d  tris %9d  draws %5d  objects %5d  | shadow tris %9d draws %5d" % [
				k, list.size(), base[0] - hidden[0], base[1] - hidden[1], base[2] - hidden[2], base[4] - hidden[4], base[6] - hidden[6]])
	# The Building category again, by the kind of node under a Building: its box parts, the
	# facade MultiMeshes, the kit batches, the shop names, the roof plant.
	var sub := {}
	for gi: GeometryInstance3D in nodes["Building"]:
		if is_instance_valid(gi):
			var k := _building_part_kind(gi)
			if not sub.has(k):
				sub[k] = []
			(sub[k] as Array).append(gi)
	var kinds := sub.keys()
	kinds.sort()
	for k: String in kinds:
		var list: Array = sub[k]
		for gi: GeometryInstance3D in list:
			gi.visible = false
		var hidden := await _geo_report("  (hidden Building/%s)" % k)
		for gi: GeometryInstance3D in list:
			gi.visible = true
		print("BSPLIT %-24s nodes %5d  tris %9d  draws %5d  objects %5d  | camera draws %5d  shadow draws %5d" % [
			k, list.size(), base[0] - hidden[0], base[1] - hidden[1], base[2] - hidden[2],
			base[5] - hidden[5], base[6] - hidden[6]])


## ROOF_TRIS=1: what the rooftop air-conditioning units really cost the camera pass, counted per
## instance by the renderer's LOD rule (see _true_tris: the counters count a LOD'd MultiMesh
## surface once), as one MultiMesh per building picks its LOD (from the batch's box) and as the
## node per unit it used to be would have (each from its own box).
func _roof_unit_tris() -> void:
	var cam := get_root().get_camera_3d()
	var vp := get_root()
	var threshold := vp.mesh_lod_threshold / maxf(float(vp.get_visible_rect().size.x), 1.0)
	var multiplier := cam.get_camera_projection().get_lod_multiplier()
	var planes := cam.get_frustum()
	var batch := 0
	var single := 0
	var units := 0
	for n in current_scene.find_children("RoofUnits*", "MultiMeshInstance3D", true, false):
		var node := n as MultiMeshInstance3D
		if not node.is_visible_in_tree():
			continue
		var mm := node.multimesh
		var box: AABB = node.global_transform * node.get_aabb()
		if not _box_in_frustum(box, planes):
			continue
		batch += _lod_tris(mm.mesh, box, cam.global_position, node.lod_bias, multiplier, threshold) * mm.instance_count
		var xforms := _roof_xforms(node)
		for i in mm.instance_count:
			var ib: AABB = node.global_transform * ((xforms[i] as Transform3D) * mm.mesh.get_aabb())
			if _box_in_frustum(ib, planes):
				single += _lod_tris(mm.mesh, ib, cam.global_position, 1.0, multiplier, threshold)
				units += 1
	print("ROOF_TRIS %d units in view: %d triangles as per-building MultiMeshes, %d as a node each" % [units, batch, single])


## A MultiMesh's instance transforms from its buffer (get_instance_transform is identity headless;
## this runs under a real renderer, but the buffer is what the renderer draws).
static func _roof_xforms(node: MultiMeshInstance3D) -> Array:
	var mm := node.multimesh
	var buf := mm.buffer
	var stride := buf.size() / maxi(mm.instance_count, 1)
	var out: Array = []
	for i in mm.instance_count:
		var o := i * stride
		out.append(Transform3D(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
			Vector3(buf[o + 2], buf[o + 6], buf[o + 10]), Vector3(buf[o + 3], buf[o + 7], buf[o + 11])))
	return out


## DIFF=1: the clock of day back on --hour and held, the signals on one fixed clock, and the
## things that move by themselves hidden (see _initialize).
func _diff_freeze(player: Node3D) -> void:
	var day := current_scene.get_node_or_null("DayNight")
	if day:
		day.call("set_paused", true)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--hour="):
				day.set("hour", fmod(arg.trim_prefix("--hour=").to_float(), 24.0))
	(load("res://scripts/world/traffic_signals.gd") as GDScript).set("clock", 0.0)
	RenderingServer.global_shader_parameter_set("signal_clock", 0.0)
	var hidden := 0
	for g in ["pedestrian", "police", "vehicle", "police_car", "debris", "gib", "player"]:
		for n in get_nodes_in_group(g):
			if n is Node3D:
				(n as Node3D).visible = false
				hidden += 1
	for cls in ["GPUParticles3D", "CPUParticles3D"]:
		for n in current_scene.find_children("*", cls, true, false):
			(n as Node3D).visible = false
			hidden += 1
	for nm in ["AirTraffic"]:
		var n := current_scene.get_node_or_null(nm)
		if n is Node3D:
			(n as Node3D).visible = false
			hidden += 1
	if player:
		player.visible = false
	print("DIFF: %d moving things hidden, clock held at %s" % [hidden, day.call("clock_text") if day else "?"])


## What a node under a Building is, for the BSPLIT lines.
static func _building_part_kind(gi: GeometryInstance3D) -> String:
	var nm := String(gi.name)
	if gi is MultiMeshInstance3D:
		if nm.begins_with("BatchShadow_kit_"):
			return "kit shadow twins"
		if nm.begins_with("Batch_kit_surround"):
			return "kit surrounds"
		if nm.begins_with("Batch_kit_shop_"):
			return "kit storefronts"
		if nm.begins_with("Batch_kit_awning"):
			return "kit awnings"
		if nm.begins_with("Batch_kit_cap_"):
			return "kit curtain caps"
		if nm.begins_with("Batch_kit_"):
			return "kit other"
		return "mm " + nm.rstrip("0123456789")
	var mi := gi as MeshInstance3D
	if mi == null:
		return "other " + gi.get_class()
	if nm.begins_with("Sign"):
		return "shop names"
	if nm.begins_with("BladeText"):
		return "blade sign names"
	if mi.material_override is ShaderMaterial:
		return "box parts"
	if mi.mesh is PrimitiveMesh:
		return "primitives"
	return "mesh " + nm.rstrip("0123456789")


static var _est_cache := {}


## A rough triangle estimate (LOD 0 times instances) to rank the OSPLIT stems.
static func _est_tris(gi: GeometryInstance3D) -> int:
	var mesh: Mesh = null
	var count := 1
	if gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		if mm == null:
			return 0
		mesh = mm.mesh
		count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	elif gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	if mesh == null:
		return 0
	if _est_cache.has(mesh):
		return int(_est_cache[mesh]) * count + 50
	var t := 0
	for i in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(i) if mesh is ArrayMesh else []
		if arr.is_empty():
			t += 100
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	_est_cache[mesh] = t
	return t * count + 50


func _split_category(gi: GeometryInstance3D) -> String:
	var n: Node = gi
	while n != null:
		var cls := String(n.get_script().get_global_name()) if n.get_script() else ""
		match cls:
			"Building":
				return "Building"
			"Vehicle", "Aircraft", "PoliceCar", "AmbientJet", "Helicopter", "EmergencyCar":
				return "Vehicle"
			"Pedestrian", "Ragdoll", "Avatar", "Player", "PoliceOfficer", "RoughSleeper", "ReplicaWalker", \
					"ApronCrew", "EmergencyCrew", "ParkGoer", "RailRider", "StreetVendor", "CrowdDog":
				return "Pedestrian"
			"LightRailSystem", "LightRailTrain", "RailSection", "RailGate":
				return "LightRail"
			"Birds":
				return "Birds"
			"TrashCan", "PhysicsProp":
				return "PhysProps"
			"Skyline":
				return "FarCity"
			"CampFigureMesh":
				return "Camp"
			"CityChunk":
				var nm := String(gi.name)
				for k in ["tree", "palm", "bush", "shrub", "flower", "plant", "gclump", "Planting", "hill_"]:
					if nm.contains(k):
						return "Trees"
				if nm.contains("grass"):
					return "Grass"
				if nm.contains("FarGround"):
					return "FarGround"
				# Encampment pieces and the static figures at them (Encampment, CampFigure).
				if nm.begins_with("Batch_camp") or nm.begins_with("BatchShadow_camp"):
					return "Camp"
				# The lot fill's own ground and the batches only it uses (LotFill; its planting,
				# lamps, benches and bollards share the street's batches and count there).
				# YardFill's two meshes (the yards' ground and everything upright) count here too.
				if nm.begins_with("LotFill") or nm.begins_with("Yard") or nm.contains("apark_car") or nm.contains("pstripe") or nm.contains("fence_") \
						or nm.contains("fill_bronze"):
					return "LotFill"
				if nm.begins_with("Houses") or nm.begins_with("House") or nm.begins_with("Batch_h_") or nm.begins_with("h_"):
					return "Houses"
				if nm.begins_with("Industrial") or nm.contains("ind_"):
					return "Industrial"
				if nm.begins_with("Park") or nm.contains("park_"):
					return "Parks"
				if nm.begins_with("River") or nm.contains("rv_"):
					return "River"
				if nm.begins_with("Rail") or nm.contains("rail_"):
					return "LightRail"
				if nm.contains("bb_"):
					return "Billboards"
				if nm.contains("vend_") or nm.begins_with("Vendor"):
					return "Vendors"
				if nm.begins_with("Batch"):
					return "StreetProps"
				return "Other"
		if String(n.name).begins_with("Landmark") or String(n.name).begins_with("FarLandmark"):
			return "Landmark"
		n = n.get_parent()
	return "Other"


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
	# STREET_MIX=14,15,...: the queue's ordinary cars are these body types in turn (the second
	# wave of road cars; the taxi, 17, in its livery), handed to place_car() through the pool.
	var mix := PackedInt32Array()
	for t in OS.get_environment("STREET_MIX").split(",", false):
		mix.append(t.to_int())
	var mixed := 0
	for n in lanes:
		var nose := line - float(dir) * (0.6 + 2.5 * float(n))
		for k in per:
			# STREET_BIG=<body type>: the second car of the kerb lane is that big vehicle.
			var big_kind := _env_int("STREET_BIG", -1) if (k == 1 and n == lanes - 1) else -1
			if big_kind < 0 and not mix.is_empty():
				var vs: GDScript = load("res://scripts/vehicles/vehicle.gd")
				var t := mix[mixed % mix.size()]
				mixed += 1
				var mc: Node = vs.call("random_car", rng)
				if t == 17:
					mc.call("setup", t, Color(0.96, 0.73, 0.03), 0)
					mc.call("setup_look", 0, 3, Color(0.07, 0.07, 0.08))
				else:
					mc.call("setup", t, mc.get("paint"), 0)
					mc.call("setup_look", 1, 0, Color(0.92, 0.92, 0.93))
				(traffic.get("_pool") as Array).append(mc)
			var car: Node = traffic.call("place_car", axis, index, dir, n, line, 10.0, false, big_kind)
			car.traffic.v = 0.0
			car.set("traffic_speed", 0.0)
			var half: float = car.traffic.half
			var along := nose - float(dir) * half
			var lane: float = car.traffic.lane
			var p2 := Vector2(plan.road_pos(axis, index) + lane, along) if axis == 0 else Vector2(along, plan.road_pos(axis, index) + lane)
			var h: float = traffic.call("_relief", p2)
			(car as Node3D).global_position = ws.to_local(Vector3(p2.x, 0.1 + float(car.call("road_lift")) + h, p2.y))
			nose = along - float(dir) * (float(car.traffic.get("rear", half)) + float(traffic.get("min_gap")) + rng.randf_range(0.1, 1.4))
	# STREET_EYE=1: the camera onto the pavement beside the back of the queue, looking up it (a
	# free EYE camera, STREET_EYE_BACK metres behind the last car, STREET_EYE_SIDE past the kerb).
	if OS.get_environment("STREET_EYE") == "1":
		var kerb := signf(_lane_sign(traffic, axis, index, dir))
		var lateral: float = plan.road_pos(axis, index) + kerb * (width * 0.5 + _env_float("STREET_EYE_SIDE", 1.6))
		var back := line - float(dir) * (float(per) * 7.0 + _env_float("STREET_EYE_BACK", 8.0))
		var e2 := Vector2(lateral, back) if axis == 0 else Vector2(back, lateral)
		var look := Vector3(0.0, 0.0, dir) if axis == 0 else Vector3(dir, 0.0, 0.0)
		look = look.rotated(Vector3.UP, -kerb * float(dir) * deg_to_rad(_env_float("STREET_EYE_TURN", 9.0)) * (1.0 if axis == 0 else -1.0))
		var yaw := rad_to_deg(atan2(-look.x, -look.z))
		OS.set_environment("EYE", "%.2f,%.2f,%.2f,%.2f,%.2f" % [e2.x, _env_float("STREET_EYE_HEIGHT", 1.7), e2.y, yaw, _env_float("STREET_EYE_PITCH", -2.0)])
		OS.set_environment("EYE_AGL", "1")
		print("STREET eye ", OS.get_environment("EYE"))
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


## BIG=bus: the bus stop nearest the camera on a bus line (BigVehicles.block_stop()), a bus
## standing at it with its doors open, the lane behind it emptied, and EYE set to a camera on the
## pavement BIG_AHEAD metres (default 11) ahead of its nose looking back at it (BIG_SIDE metres
## past the kerb, BIG_HEIGHT, BIG_TURN degrees off the kerb line). BIG=semi: a semi on the freeway
## route nearest the camera (BIG_ROUTE to pick one by name, e.g. "110"), BIG_T metres along from
## the nearest point, and EYE beside and behind it on the deck (BIG_BACK, BIG_SIDE, BIG_HEIGHT).
func _stage_big(kind: String) -> void:
	var scene := current_scene
	var plan: Variant = scene.get("plan")
	var traffic := scene.get_node_or_null("Traffic")
	var cam := get_root().get_camera_3d()
	if plan == null or traffic == null or cam == null:
		print("BIG: nothing to stage with")
		return
	var ws := root.get_node("/root/WorldState")
	var bv: GDScript = load("res://scripts/vehicles/big_vehicles.gd")
	var cp: Vector3 = ws.to_world(cam.global_position)
	if kind == "semi" or kind == "box_fw":
		var fw: Variant = plan.macro.freeway
		var best := -1
		var best_d := INF
		var best_t := 0.0
		for ri in fw.routes.size():
			if OS.get_environment("BIG_ROUTE") != "" and not String(fw.routes[ri].name).contains(OS.get_environment("BIG_ROUTE")):
				continue
			var near: Array = fw.nearest_on(ri, Vector2(cp.x, cp.z))
			if float(near[1]) < best_d:
				best_d = float(near[1])
				best = ri
				best_t = float(near[0])
		if best < 0:
			print("BIG: no freeway")
			return
		var t := best_t + _env_float("BIG_T", 0.0)
		var dir := _env_int("BIG_DIR", 1)
		var truck: Node3D = traffic.call("place_freeway_car", best, t, dir, 11 if kind == "semi" else 10, _env_float("BIG_SPEED", 0.5))
		var at: Array = fw.point_at(best, t - float(dir) * _env_float("BIG_BACK", 16.0))
		var p: Vector3 = at[0]
		var d2: Vector2 = at[1] * float(dir)
		var half: float = float(fw.routes[best].width) * 0.5
		var side := Vector2(-d2.y, d2.x) * _env_float("BIG_SIDE", half * 0.15)
		var tp: Vector3 = ws.to_world(truck.global_position)
		var e := Vector3(p.x + side.x, p.y + _env_float("BIG_HEIGHT", 2.2), p.z + side.y)
		var look := (tp + Vector3(0.0, 1.6, 0.0)) - e
		var yaw := rad_to_deg(atan2(-look.x, -look.z))
		var pitch := rad_to_deg(atan2(look.y, Vector2(look.x, look.z).length()))
		OS.set_environment("EYE", "%.2f,%.2f,%.2f,%.2f,%.2f" % [e.x, e.y, e.z, yaw, pitch])
		print("BIG %s on %s at t %.0f, eye %s" % [kind, fw.routes[best].name, t, OS.get_environment("EYE")])
		return
	# A bus at a stop.
	var bi: Vector2i = plan.block_index_at(Vector2(cp.x, cp.z))
	var found := []
	for axis: int in [0, 1]:
		var base: int = bi.x if axis == 0 else bi.y
		var base_k: int = bi.y if axis == 0 else bi.x
		for di in range(-3, 5):
			var index: int = base + di
			for dk in range(-3, 4):
				var k: int = base_k + dk
				for dir: int in [1, -1]:
					var stop: float = bv.call("block_stop", plan, axis, index, k, dir)
					if is_nan(stop):
						continue
					var road: float = plan.road_pos(axis, index)
					var q := Vector2(road, stop) if axis == 0 else Vector2(stop, road)
					found.append([q.distance_to(Vector2(cp.x, cp.z)), axis, index, dir, stop])
	if found.is_empty():
		print("BIG: no bus stop near the camera")
		return
	found.sort_custom(func(a, b): return a[0] < b[0])
	var pick: Array = found[clampi(_env_int("BIG_PICK", 0), 0, found.size() - 1)]
	var axis: int = pick[1]
	var index: int = pick[2]
	var dir: int = pick[3]
	var stop: float = pick[4]
	traffic.set("staged", true)
	var cars: Array = traffic.get("cars")
	for c in cars.duplicate():
		if is_instance_valid(c) and int(c.traffic.get("axis", -1)) == axis and int(c.traffic.get("index", -99999)) == index:
			cars.erase(c)
			traffic.call("_retire", c)
	var width: float = plan.road_width(axis, index)
	var lanes := 2 if width > float(plan.street_width) + 1.0 else 1
	var bus: Node = traffic.call("place_car", axis, index, dir, lanes - 1, stop, 0.0, false, 9)
	var half: float = bus.traffic.half
	var along := stop - float(dir) * half
	bus.traffic.v = 0.0
	bus.traffic.speed = 0.0
	bus.traffic.shift = float(bv.get("STOP_SHIFT"))
	bus.traffic.dwell = 1.0
	bus.traffic.dwell_need = 1e9
	bus.set("traffic_speed", 0.0)
	var lane: float = bus.traffic.lane
	var lat: float = plan.road_pos(axis, index) + lane + signf(lane) * float(bus.traffic.shift)
	var p2 := Vector2(lat, along) if axis == 0 else Vector2(along, lat)
	var h: float = traffic.call("_relief", p2)
	var yaw_b: float = traffic.call("_heading", axis, dir)
	(bus as Node3D).global_transform = Transform3D(Basis(Vector3.UP, yaw_b), ws.to_local(Vector3(p2.x, 0.1 + float(bus.call("road_lift")) + h, p2.y)))
	var fit := bus.get_node_or_null("BusFittings")
	if fit and OS.get_environment("BIG_DOORS") != "0":
		fit.call("set_doors", true)
	# The camera: on the pavement ahead of the nose, looking back along the bus.
	var kerb := signf(lane)
	var lateral: float = plan.road_pos(axis, index) + kerb * (width * 0.5 + _env_float("BIG_SIDE", 2.4))
	var ahead := stop + float(dir) * _env_float("BIG_AHEAD", 11.0)
	var e2 := Vector2(lateral, ahead) if axis == 0 else Vector2(ahead, lateral)
	var target := p2
	var look := Vector3(target.x - e2.x, 0.0, target.y - e2.y)
	look = look.rotated(Vector3.UP, deg_to_rad(_env_float("BIG_TURN", 0.0)))
	var yaw := rad_to_deg(atan2(-look.x, -look.z))
	OS.set_environment("EYE", "%.2f,%.2f,%.2f,%.2f,%.2f" % [e2.x, _env_float("BIG_HEIGHT", 1.7), e2.y, yaw, _env_float("BIG_PITCH", 0.0)])
	OS.set_environment("EYE_AGL", "1")
	print("BIG bus line %d at stop %.1f on road %d/%d dir %d, eye %s" % [int(bv.call("route_of", plan, axis, index)), stop, axis, index, dir, OS.get_environment("EYE")])


## Which side of the road centre a lane of `dir` traffic drives on (+1 / -1).
static func _lane_sign(traffic: Node, axis: int, index: int, dir: int) -> float:
	var off: float = traffic.call("_lane_offset", axis, index, dir)
	return off if off != 0.0 else 1.0


static func _env_float(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback


## Keeps the player where the shot wants them: at the --spawn height, and for BOOST held in
## place mid-boost (the boost itself would carry them off between software frames).
func _pose(player: Node3D, anchor: Vector3, hold: Vector3, boost: bool, fov: float) -> void:
	if player == null or _flying:
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
## BOOST=fly is under way: the pose no longer pins the player.
var _flying: bool = false


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
	# EYE_AGL=1: the height is above the ground there (the city's own plan height), not absolute.
	if OS.get_environment("EYE_AGL") == "1" and current_scene and current_scene.get("plan") != null:
		at.y += float(current_scene.get("plan").height_at(Vector2(p[0].to_float(), p[2].to_float())))
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
