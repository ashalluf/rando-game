extends SceneTree
## The hero holding a gun, close up, in a plain lit room - for judging the grip and the arm pose,
## which a street camera shows at forty pixels tall.
##
##   OUT=hero.png WEAPON=0 AIM=1 YAW=90 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/hero_shot.gd --resolution 900x900
##
## Env: OUT (png), WEAPON (0 AK, 1 rocket launcher, 2 shotgun), AIM=1 raises it to the
## shoulder, YAW (degrees to orbit the camera round the hero; 0 is front-on, 90 his right side),
## WALK=1 plays the walk clip (the IK has to hold the gun whatever the legs do), CAM_DIST and
## CAM_Y (and CAM_FWD, metres in front of him) bring the camera in on the hands, DEBUG=1 marks the IK targets, ROCKET=1 (with WEAPON=1)
## fires a slow rocket so it is in frame just past the muzzle. WEAPON=-1 puts the gun away (arms on
## the clip); CLIP=Idle|Casual_Walk_inplace|run_fast_3_inplace with SEEK (seconds) freezes a clip
## frame. The light is the city's grade (AgX, the look LUT, sky ambient, a shadowed sun at
## SUN_PITCH / SUN_YAW); FLAT=1 is the old flat-lit room. CAM_AT=hands|head aims at the hands
## or the head wherever the pose put them (CAM_Y is then an offset from there). Run it with --rendering-driver vulkan
## (lavapipe) for the Forward+ look: subsurface skin and SSAO only exist there.
func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sun := DirectionalLight3D.new()
	if OS.get_environment("FLAT") == "1":
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.62, 0.66, 0.72)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.75, 0.78, 0.84)
		e.ambient_light_energy = 0.6
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
		sun.light_energy = 1.4
	else:
		# The city's own grade (city.tscn): AgX, the look LUT, sky ambient, a shadowed sun -
		# so skin, velour and gold are judged under the light they are played in.
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.32, 0.46, 0.68)
		sky_mat.sky_horizon_color = Color(0.66, 0.70, 0.74)
		sky_mat.ground_horizon_color = Color(0.52, 0.50, 0.47)
		sky_mat.ground_bottom_color = Color(0.30, 0.28, 0.26)
		var sky := Sky.new()
		sky.sky_material = sky_mat
		e.background_mode = Environment.BG_SKY
		e.sky = sky
		e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		e.ambient_light_energy = float(OS.get_environment("AMBIENT")) if OS.get_environment("AMBIENT") != "" else 0.45
		e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		e.tonemap_mode = Environment.TONE_MAPPER_AGX
		e.tonemap_exposure = 1.25
		e.tonemap_white = 5.0
		var grade := Gradient.new()
		grade.offsets = PackedFloat32Array([0, 0.14, 0.28, 0.45, 0.62, 0.78, 0.9, 1])
		grade.colors = PackedColorArray([Color(0.035, 0.036, 0.041), Color(0.172, 0.176, 0.180), Color(0.318, 0.307, 0.290), Color(0.470, 0.448, 0.412), Color(0.628, 0.598, 0.548), Color(0.772, 0.738, 0.680), Color(0.877, 0.845, 0.786), Color(0.962, 0.936, 0.878)])
		var lut := GradientTexture1D.new()
		lut.gradient = grade
		lut.width = 256
		e.adjustment_enabled = true
		e.adjustment_saturation = 1.32
		e.adjustment_color_correction = lut
		e.ssao_enabled = true
		sun.rotation_degrees = Vector3(float(OS.get_environment("SUN_PITCH")) if OS.get_environment("SUN_PITCH") != "" else -38.0, float(OS.get_environment("SUN_YAW")) if OS.get_environment("SUN_YAW") != "" else 35.0, 0.0)
		sun.light_energy = 1.3
		sun.light_color = Color(1.0, 0.96, 0.9)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 12.0
	env.environment = e
	stage.add_child(env)
	stage.add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	floor_body.add_child(floor_mesh)
	stage.add_child(floor_body)
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	stage.add_child(player)
	for i in 4:
		await process_frame
	var manager: Node = player.get("weapon_manager")
	var weapon := int(OS.get_environment("WEAPON")) if OS.get_environment("WEAPON") != "" else 0
	if weapon < 0:
		(manager as Node3D).visible = false # no gun: the arms go back to the clip
	else:
		manager.equip(weapon)
	var rig: Node = player.get("camera_rig")
	rig.set_look(0.0, 0.0)
	if OS.get_environment("AIM") == "1":
		player.notify_fired()
		player.set("aim_hold_time", 1.0e6)
		player.notify_fired()
	# DEBUG=1 marks the IK targets: red where the right wrist should be, blue the left.
	if OS.get_environment("DEBUG") == "1":
		for pair in [["GripRight", Color(1, 0, 0)], ["GripLeft", Color(0, 0.3, 1)]]:
			var target: Node3D = manager.get_node_or_null(pair[0])
			if target:
				var dot := MeshInstance3D.new()
				var sphere := SphereMesh.new()
				sphere.radius = 0.025
				sphere.height = 0.05
				dot.mesh = sphere
				var m := StandardMaterial3D.new()
				m.albedo_color = pair[1]
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.no_depth_test = true
				dot.material_override = m
				target.add_child(dot)
	var cam := Camera3D.new()
	cam.fov = 40.0
	stage.add_child(cam)
	# CAM_AT=hands aims at the middle of the two hands as the IK left them (CAM_DIST, YAW and
	# CAM_Y as an offset still apply), CAM_AT=head at the head: the stance moves both about.
	var aim_at := OS.get_environment("CAM_AT")
	var at := [Vector3.INF]
	var sk0: Skeleton3D = player.find_child("Skeleton3D", true, false)
	if aim_at != "" and sk0:
		sk0.skeleton_updated.connect(func() -> void:
			var names: Array = ["RightHand", "LeftHand"] if aim_at == "hands" else ["Head", "Head"]
			var a := sk0.to_global(sk0.get_bone_global_pose(sk0.find_bone(names[0])).origin)
			var b := sk0.to_global(sk0.get_bone_global_pose(sk0.find_bone(names[1])).origin)
			at[0] = (a + b) * 0.5)
	var yaw := deg_to_rad(float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 90.0)
	var walk := OS.get_environment("WALK") == "1"
	# CAM_DIST / CAM_Y close in on the hands (default: the whole figure).
	var place := func() -> void:
		var dist := float(OS.get_environment("CAM_DIST")) if OS.get_environment("CAM_DIST") != "" else 2.6
		var centre := Vector3(0.0, float(OS.get_environment("CAM_Y")) if OS.get_environment("CAM_Y") != "" else 1.25, -float(OS.get_environment("CAM_FWD")) if OS.get_environment("CAM_FWD") != "" else 0.0)
		if at[0] != Vector3.INF:
			centre = at[0] + Vector3(0.0, float(OS.get_environment("CAM_Y")) if OS.get_environment("CAM_Y") != "" else 0.0, 0.0)
		cam.global_position = centre + Basis(Vector3.UP, -yaw) * Vector3(0.0, 0.15 * dist / 2.6, -dist)
		cam.look_at(centre, Vector3.UP)
		cam.current = true
	for i in 40:
		if walk:
			Input.action_press("move_forward")
		await physics_frame
		# Keep him on the spot facing -Z however the walk moves him.
		player.global_position = Vector3(0.0, player.global_position.y, 0.0)
		(player.get("visual") as Node3D).rotation.y = 0.0
		place.call()
	# ROCKET=1 (with WEAPON=1 AIM=1): a rocket just out of the launcher, crawling so it is in frame.
	if OS.get_environment("ROCKET") == "1":
		var launcher: Node = manager.get("current")
		if launcher and launcher.has_method("launch_rocket"):
			var muzzle: Node3D = launcher.get("muzzle")
			var shot: Node3D = launcher.launch_rocket(muzzle.global_position, -(launcher as Node3D).global_basis.z)
			shot.set("speed", 3.0)
			for i in 24:
				await physics_frame
	var sk: Skeleton3D = player.find_child("Skeleton3D", true, false)
	var clip := OS.get_environment("CLIP")
	if clip != "":
		var anim: AnimationPlayer = player.find_child("AnimationPlayer", true, false)
		if anim and anim.has_animation(clip):
			player.set_physics_process(false) # or Avatar.drive() picks its own clip back
			anim.play(clip, 0.0)
			anim.seek(float(OS.get_environment("SEEK")) if OS.get_environment("SEEK") != "" else 0.0, true)
			anim.speed_scale = 0.0
			for i in 3:
				await process_frame
			place.call() # the clip's frame moved the head and hands
			await process_frame
	if sk:
		for b in ["Hips", "RightArm", "RightHand", "LeftHand"]:
			print(b, " at ", sk.to_global(sk.get_bone_global_pose(sk.find_bone(b)).origin))
	print("player at ", player.global_position, " mount at ", (manager as Node3D).global_position, " grip R ", (manager.get_node_or_null("GripRight") as Node3D).global_position if manager.get_node_or_null("GripRight") else "none")
	if sk and manager.get_node_or_null("GripRight"):
		var gr: Node3D = manager.get_node("GripRight")
		var hb := sk.find_bone("RightHand")
		var chain := sk.get_bone_pose(hb)
		var p := sk.get_bone_parent(hb)
		while p >= 0:
			chain = sk.get_bone_pose(p) * chain
			p = sk.get_bone_parent(p)
		var hand_world := (sk.global_transform * chain)
		var hb2 := hand_world.basis.orthonormalized()
		var mb := gr.global_basis.orthonormalized()
		print("hand Y ", hb2.y.snapped(Vector3.ONE*0.01), " want Y ", mb.y.snapped(Vector3.ONE*0.01), " hand Z ", hb2.z.snapped(Vector3.ONE*0.01), " want Z ", mb.z.snapped(Vector3.ONE*0.01))
		print("hand at ", hand_world.origin, " marker at ", gr.global_position, " global_pose hand ", sk.to_global(sk.get_bone_global_pose(hb).origin))
	if OS.get_environment("STRETCH") == "1" and sk:
		_report_stretch(player, sk)
	if OS.get_environment("CLEAR_SURF") != "" and sk:
		_report_clearance(player, sk, int(OS.get_environment("CLEAR_SURF")), int(OS.get_environment("CLEAR_REF")) if OS.get_environment("CLEAR_REF") != "" else 0)
	# SURF_COLORS=1: every surface of the hero flat-shaded in its own colour (printed), so a stray
	# piece of geometry in a still can be traced to the surface it belongs to. SURF_HIDE=0,5 hides
	# those surfaces, to see what one is doing under another.
	if OS.get_environment("SURF_COLORS") == "1":
		var palette := [Color.RED, Color.LIME, Color.BLUE, Color.YELLOW, Color.MAGENTA, Color.CYAN,
			Color.ORANGE, Color.PURPLE, Color.WHITE, Color.DEEP_PINK, Color.SADDLE_BROWN,
			Color.DARK_GREEN, Color.NAVY_BLUE, Color.GRAY, Color.GOLD]
		for node in player.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.skin == null:
				continue
			for si in mi.mesh.get_surface_count():
				var m := StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.albedo_color = palette[si % palette.size()]
				var am := mi.get_active_material(si)
				print("SURF %s %d %s = %s" % [mi.name, si, am.resource_name if am else "-", str(m.albedo_color)])
				if str(si) in OS.get_environment("SURF_HIDE").split(","):
					m.albedo_color.a = 0.0
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mi.set_surface_override_material(si, m)
			mi.material_override = null
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "hero.png"
	await process_frame
	# What this frame cost (only under a real renderer; --headless reads zero).
	print("GEO tris=%d draws=%d objects=%d" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


## STRETCH=1: skin every surface of the hero on the CPU in the current pose and report the
## triangles whose edges grew. A torn collar is geometry, not shading, and it is the one thing a
## still cannot tell you the cause of: which surface, which vertices, which bones pull them apart.
## An edge counts as torn when it grew past 1 cm AND by half again over its bind length.
func _report_stretch(player: Node, sk: Skeleton3D) -> void:
	var inv := sk.global_transform.affine_inverse()
	for node in player.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin == null or mi.mesh == null or not mi.visible:
			continue
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var skin := mi.skin
		var bind_bone := PackedInt32Array()
		for b in skin.get_bind_count():
			var bb := skin.get_bind_bone(b)
			bind_bone.append(bb if bb >= 0 else sk.find_bone(skin.get_bind_name(b)))
		# Mesh space -> skeleton space, so the bind and posed lengths are in the same units.
		var m2s := inv * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if bones == null or weights == null or idx.is_empty():
				continue
			var per := int(bones.size() / verts.size())
			var posed := PackedVector3Array()
			posed.resize(verts.size())
			for v in verts.size():
				var acc := Vector3.ZERO
				var wsum := 0.0
				for k in per:
					var w: float = weights[v * per + k]
					if w <= 0.0:
						continue
					var b: int = bones[v * per + k]
					acc += w * ((sk.get_bone_global_pose(bind_bone[b]) * skin.get_bind_pose(b)) * verts[v])
					wsum += w
				posed[v] = acc / maxf(wsum, 1e-6)
			# The rig is in centimetres under a 0.01 armature, so skinned and bind lengths differ by
			# a constant factor that depends on which transform the importer baked the scale into.
			# Take that factor as the surface's median edge ratio and measure growth past it.
			var ratios := PackedFloat32Array()
			for t in range(0, idx.size(), 3):
				var r0 := (m2s * verts[idx[t]]).distance_to(m2s * verts[idx[t + 1]])
				if r0 > 1e-6:
					ratios.append(posed[idx[t]].distance_to(posed[idx[t + 1]]) / r0)
			ratios.sort()
			var unit: float = ratios[ratios.size() / 2] if not ratios.is_empty() else 1.0
			var torn := 0
			var worst := 0.0
			var worst_v := -1
			var bone_hits := {}
			for t in range(0, idx.size(), 3):
				for e in 3:
					var a := idx[t + e]
					var c := idx[t + (e + 1) % 3]
					var rest := (m2s * verts[a]).distance_to(m2s * verts[c]) * unit
					var now := posed[a].distance_to(posed[c])
					if now > rest + 0.01 * unit and now > rest * 1.5:
						torn += 1
						if (now - rest) / unit > worst:
							worst = (now - rest) / unit
							worst_v = a
						for vv in [a, c]:
							var top := -1
							var topw := 0.0
							for k in per:
								if weights[vv * per + k] > topw:
									topw = weights[vv * per + k]
									top = bones[vv * per + k]
							if top >= 0:
								var bn := sk.get_bone_name(bind_bone[top])
								bone_hits[bn] = int(bone_hits.get(bn, 0)) + 1
			if torn == 0:
				continue
			var names := bone_hits.keys()
			names.sort_custom(func(x, y): return bone_hits[x] > bone_hits[y])
			var top_bones := []
			for n in names.slice(0, 5):
				top_bones.append("%s:%d" % [n, bone_hits[n]])
			var mat := mi.get_active_material(si)
			print("STRETCH %s surf %d (%s): %d torn edges of %d, worst +%.1f cm at rest %s, unit %.4f, bones %s" % [mi.name, si,
				mat.resource_name if mat else "-", torn, idx.size(), worst * 100.0,
				str((m2s * verts[worst_v]).snapped(Vector3.ONE * 0.001)), unit, ", ".join(top_bones)])


## Skin a surface's vertices on the CPU, in skeleton space. Returns [rest, posed, dominant bone
## name per vertex, weights summary], rest in bind units and posed rescaled to match.
func _skin_surface(mi: MeshInstance3D, sk: Skeleton3D, si: int) -> Array:
	var skin := mi.skin
	var bind_bone := PackedInt32Array()
	for b in skin.get_bind_count():
		var bb := skin.get_bind_bone(b)
		bind_bone.append(bb if bb >= 0 else sk.find_bone(skin.get_bind_name(b)))
	var m2s := sk.global_transform.affine_inverse() * mi.global_transform
	var arr := mi.mesh.surface_get_arrays(si)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones = arr[Mesh.ARRAY_BONES]
	var weights = arr[Mesh.ARRAY_WEIGHTS]
	var per := int(bones.size() / verts.size())
	var rest := PackedVector3Array()
	var posed := PackedVector3Array()
	var label := PackedStringArray()
	for v in verts.size():
		rest.append(m2s * verts[v])
		var acc := Vector3.ZERO
		var wsum := 0.0
		var parts := []
		for k in per:
			var w: float = weights[v * per + k]
			if w <= 0.001:
				continue
			var b: int = bones[v * per + k]
			acc += w * ((sk.get_bone_global_pose(bind_bone[b]) * skin.get_bind_pose(b)) * verts[v])
			wsum += w
			parts.append([w, sk.get_bone_name(bind_bone[b])])
		parts.sort_custom(func(x, y): return x[0] > y[0])
		var txt := []
		for pr in parts.slice(0, 3):
			txt.append("%s %.2f" % [pr[1], pr[0]])
		label.append(" ".join(txt))
		posed.append(acc / maxf(wsum, 1e-6))
	return [rest, posed, label]


## CLEAR_SURF=N [CLEAR_REF=M]: for each vertex of surface N above the chest, the distance to the
## nearest vertex of surface M (default 0, the skin) at rest and in this pose. A garment that keeps its distance to the skin is
## following the body; one that closes the gap by centimetres is swinging through it. Grouped by
## the vertex's dominant bones, which is what the fix has to change.
func _report_clearance(player: Node, sk: Skeleton3D, n: int, ref: int = 0) -> void:
	var mi: MeshInstance3D = null
	for node in player.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null and (node as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			mi = node
	var body := _skin_surface(mi, sk, ref)
	var garment := _skin_surface(mi, sk, n)
	var brest: PackedVector3Array = body[0]
	var bposed: PackedVector3Array = body[1]
	# Unit: skinned lengths over bind lengths, from the body itself.
	var unit := bposed[0].distance_to(bposed[100]) / maxf(brest[0].distance_to(brest[100]), 1e-6)
	var grid := {}
	for i in brest.size():
		if brest[i].y < 1.25:
			continue
		var key := Vector3i((brest[i] / 0.03).floor())
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	var grest: PackedVector3Array = garment[0]
	var gposed: PackedVector3Array = garment[1]
	var glabel: PackedStringArray = garment[2]
	var groups := {}
	for v in grest.size():
		if grest[v].y < 1.35:
			continue
		var key := Vector3i((grest[v] / 0.03).floor())
		var best := -1
		var bd := 1e9
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					for i in grid.get(key + Vector3i(dx, dy, dz), []):
						var d := grest[v].distance_to(brest[i])
						if d < bd:
							bd = d
							best = i
		if best < 0:
			continue
		var dp := gposed[v].distance_to(bposed[best]) / unit
		var change := dp - bd
		var g: String = glabel[v]
		if not groups.has(g):
			groups[g] = [0, 0.0, 0.0, Vector3.ZERO]
		groups[g][0] += 1
		groups[g][1] += change
		if absf(change) > absf(groups[g][2]):
			groups[g][2] = change
			groups[g][3] = grest[v]
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return absf(groups[a][2]) > absf(groups[b][2]))
	print("CLEAR surf %d vs surf %d, unit %.3f: gap change from rest (cm), by dominant bones" % [n, ref, unit])
	for k in keys.slice(0, 25):
		var g = groups[k]
		print("CLEAR  %4d verts  mean %+5.1f  worst %+5.1f at %s   %s" % [g[0], g[1] / g[0] * 100.0, g[2] * 100.0, str(g[3].snapped(Vector3.ONE * 0.001)), k])
