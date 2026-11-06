extends SceneTree
## The dogs in the city: a dog walker staged on the pavement of the block at the spawn, filmed from
## the kerb beside the dog (MODE=walker), or the yard dog nearest the spawn barking over its fence
## at the player, seen from the street (MODE=yard).
##
##   MODE=walker OUT=walker.png LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/dog_city_shot.gd --resolution 1280x720 \
##     -- --spawn=-593,-102,0,0 --hour=10 --weather=clear --nohud
##
## Env: MODE walker | yard; OUT; SEED (the walker, default 9150; its dog's breed follows from it,
## other SEEDs give other breeds); WALK (physics ticks it walks first, default 150); CAM_DIST, CAM_H, FOV;
## SEQ=n (walker: n frames STEP ticks apart, OUT_00.png ...). Scripts are loaded at run time, so
## this compiles before the autoloads, like still_shot.gd.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 40:
		await process_frame
	var city: Node3D = current_scene
	var plan = city.get("plan")
	var ws: Node = root.get_node("/root/WorldState")
	var player: Node3D = get_first_node_in_group("player") as Node3D
	var mode := OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "walker"
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 40.0
	cam.near = 0.03
	cam.far = 4000.0
	city.add_child(cam)
	var dist := float(OS.get_environment("CAM_DIST")) if OS.get_environment("CAM_DIST") != "" else 3.2
	var cam_h := float(OS.get_environment("CAM_H")) if OS.get_environment("CAM_H") != "" else 0.9
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "dog_city.png"
	if mode == "yard":
		var best: Node3D = null
		var bd := INF
		for n in root.find_children("*", "Node3D", true, false):
			var sc: Script = n.get_script()
			if sc and sc.resource_path.ends_with("/yard_dog.gd") and (n.get("fence_front") == true or OS.get_environment("BACK") == "1"):
				var d := (n as Node3D).global_position.distance_to(player.global_position)
				if d < bd:
					bd = d
					best = n
		if best == null:
			print("dog_city_shot: no yard dog near the spawn")
			quit()
			return
		# The player out on the street in front of the yard (beyond the fence), the camera beside
		# him, low, looking over the fence at the dog.
		var fo: Vector2 = best.get("frame_o")
		var fu: Vector2 = best.get("frame_u")
		var fv: Vector2 = best.get("frame_v")
		var patch: Rect2 = best.get("patch")
		var ch: Node3D = best.get("chunk")
		var mid := fo + fu * patch.get_center().x
		var street := mid - fv * 2.6
		var p3 := ch.to_global(Vector3(street.x, best.position.y + 0.3, street.y))
		player.global_position = p3 + Vector3(fu.x, 0.0, fu.y) * 2.5
		for i in 150:
			await physics_frame
		var dogp := best.global_position + Vector3.UP * 0.35
		var eye := ch.to_global(Vector3(street.x, best.position.y, street.y)) + Vector3(-fu.x, 0.0, -fu.y) * 1.2 + Vector3.UP * cam_h
		cam.look_at_from_position(eye, dogp)
		cam.current = true
		for i in 6:
			await process_frame
		get_root().get_texture().get_image().save_png(out)
		var w: Vector3 = ws.call("to_world", best.global_position)
		print("dog_city_shot: yard %s at %.1f,%.1f state %d -> %s" % [best.get("breed"), w.x, w.z, best.get("state"), out])
		quit()
		return
	# A walker of our own on this block's pavement, walking its dog toward +x.
	var bi: Vector2i = plan.block_index_at(Vector2((ws.call("to_world", player.global_position) as Vector3).x, (ws.call("to_world", player.global_position) as Vector3).z))
	var chunk: Node3D = (city.get("chunks") as Dictionary).get(bi)
	if chunk == null:
		print("dog_city_shot: no chunk at the spawn")
		quit()
		return
	var rect: Rect2 = plan.block(bi.x, bi.y).rect
	var ped_script: GDScript = load("res://scripts/npc/pedestrian.gd")
	var p: Node3D = ped_script.new()
	var seed_v := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 9150
	p.call("setup", rect, plan.sidewalk_width, seed_v)
	p.set("jogger_share", Vector2.ZERO)
	p.set("dog_share", Vector2.ONE)
	p.set("pause_chance", 0.0)
	p.set("cross_chance", 0.0)
	p.set("life_spawn_chance", 0.0)
	var at := Vector2(rect.position.x + 6.0, rect.position.y + float(plan.sidewalk_width) * 0.5)
	p.position = Vector3(at.x, chunk.call("ground_y", at.x, at.y) + 0.1, at.y)
	chunk.add_child(p)
	player.global_position = chunk.to_global(p.position + Vector3(0.0, 0.5, -12.0))
	var walk := int(OS.get_environment("WALK")) if OS.get_environment("WALK") != "" else 150
	for i in 3:
		await physics_frame
	var dog: Node3D = p.get("_dog")
	for i in walk:
		await physics_frame
	var seq := int(OS.get_environment("SEQ")) if OS.get_environment("SEQ") != "" else 0
	var step := int(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 6
	for f in maxi(seq, 1):
		dog = p.get("_dog")
		if dog == null or not is_instance_valid(dog):
			print("dog_city_shot: the walker has no dog")
			quit()
			return
		var fwd := -dog.global_basis.z
		var side := Vector3(fwd.z, 0.0, -fwd.x).normalized()
		var target := dog.global_position + Vector3.UP * 0.32 + fwd * 0.3
		# From the road side of the walker (the dog walks at its owner's left).
		var eye := target + side * dist * (1.0 if side.dot(dog.global_position - p.global_position) > 0.0 else -1.0) + fwd * dist * 0.55 + Vector3.UP * (cam_h - 0.32)
		cam.look_at_from_position(eye, target)
		cam.current = true
		for i in 4:
			await process_frame
		var path := out if seq <= 0 else out.trim_suffix(".png") + "_%02d.png" % f
		get_root().get_texture().get_image().save_png(path)
		print("dog_city_shot: walker with a %s (%s) -> %s" % [dog.get("breed"), dog.get("look"), path])
		for i in step:
			await physics_frame
	quit()
