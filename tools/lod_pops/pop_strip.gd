extends SceneTree
## Frame strips along a scripted drive or flight, for finding POPS: a free camera moves a fixed
## distance every frame (run with --fixed-fps 60, so streaming, fades and crowd tiers all see
## 1/60 s of game time a frame however long a software frame takes), every frame is saved, and
## every chunk the streamer installs or retires is logged with the frame it happened on.
## tools/lod_pops/pops.py then finds the regions that change in ONE frame (a pop) rather than
## smoothly (parallax, traffic) and lists them with the chunk events of that frame.
##
##   OUT_DIR=build/pops/drive ROUTE=drive xvfb-run -a -s "-screen 0 960x540x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --fixed-fps 60 --script tools/lod_pops/pop_strip.gd --resolution 960x540 -- --hour=13 --nohud
##
## Env: ROUTE=drive|fly|low (or PATH_PTS="x,y,z;x,y,z;..." in true world, y above the ground),
## SPEED m/s (default 20 drive, 45 fly), FRAMES cap, WARM frames before the run (default 40),
## SAVE_EVERY (1), PITCH degrees (default -4 drive, -18 fly).
const ROUTES := {
	# North up Flower St from Olympic, through the downtown core.
	"drive": "2363,1.9,960;2363,1.9,200",
	# A suburban / midtown drive west along 5th's line.
	"mid": "900,1.9,10;300,1.9,10",
	# Low flight over midtown and on into downtown.
	"low": "300,40,250;1500,40,280",
	# A fast high flight across the basin.
	"fly": "-600,110,320;700,110,250;1500,110,280",
}


func _initialize() -> void:
	Engine.set_meta("postfx_motion_blur", 0.0)
	change_scene_to_file("res://scenes/levels/city.tscn")
	var route_name := _env("ROUTE", "drive")
	var pts_s := _env("PATH_PTS", ROUTES.get(route_name, ROUTES.drive))
	var pts: Array[Vector3] = []
	for s in pts_s.split(";"):
		var p := s.split(",")
		pts.append(Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float()))
	var flying := pts[0].y > 10.0
	var speed := float(_env("SPEED", "45" if flying else "20"))
	var pitch := deg_to_rad(float(_env("PITCH", "-18" if flying else "-4")))
	var out_dir := _env("OUT_DIR", "build/pops/" + route_name)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cap := int(_env("FRAMES", "100000"))
	var save_every := int(_env("SAVE_EVERY", "1"))
	for i in 3:
		await process_frame
	var city: Node = current_scene
	var plan = city.get("plan")
	var ws: Node = root.get_node("/root/WorldState")
	var player: Node3D = get_first_node_in_group("player")
	var police := city.get_node_or_null("Police")
	if police:
		police.set("enabled", false)
	var cam := Camera3D.new()
	cam.name = "PopCamera"
	root.add_child(cam)
	var pc := root.get_camera_3d()
	if pc and pc != cam:
		cam.attributes = pc.attributes
		cam.far = pc.far
		cam.near = pc.near
	cam.fov = float(_env("FOV", "60"))
	cam.make_current()
	player.visible = false
	var log := FileAccess.open(out_dir + "/events.txt", FileAccess.WRITE)
	# Warm up at the start: streaming, the far city, exposure.
	var warm := int(_env("WARM", "40"))
	var seg := 0
	var along := 0.0
	var frame := -warm
	var last_chunks := {}
	while seg < pts.size() - 1 and frame < cap:
		var a := pts[seg]
		var b := pts[seg + 1]
		var len := Vector2(b.x - a.x, b.z - a.z).length()
		if frame >= 0:
			along += speed / 60.0
		if along > len:
			along -= len
			seg += 1
			continue
		var t := along / len
		var xz := Vector2(lerpf(a.x, b.x, t), lerpf(a.z, b.z, t))
		var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
		var ground: float = plan.height_at(xz) if plan else 0.0
		var y := ground + lerpf(a.y, b.y, t)
		var world := Vector3(xz.x, y, xz.y)
		var off: Vector3 = ws.get("world_offset")
		var local := world - off
		var yaw := atan2(-dir.x, -dir.y)
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), local)
		player.global_position = Vector3(local.x, ground - off.y + (y - ground if flying else 1.0), local.z)
		player.set("velocity", Vector3.ZERO)
		await process_frame
		if frame >= 0:
			# Chunk events this frame.
			var now := {}
			var chunks: Dictionary = city.get("chunks")
			for k: Vector2i in chunks:
				var ch = chunks[k]
				if is_instance_valid(ch):
					now[k] = int(ch.get("level"))
			for k: Vector2i in now:
				if not last_chunks.has(k) or last_chunks[k] != now[k]:
					log.store_line("%d IN %d,%d %s d=%.0f" % [frame, k.x, k.y, "FULL" if now[k] == 0 else "LOD", _dist(plan, k, xz)])
			for k: Vector2i in last_chunks:
				if not now.has(k):
					log.store_line("%d OUT %d,%d d=%.0f" % [frame, k.x, k.y, _dist(plan, k, xz)])
			last_chunks = now
			if frame % save_every == 0:
				var img := root.get_texture().get_image()
				img.save_jpg("%s/f%04d.jpg" % [out_dir, frame / save_every], 0.92)
				log.store_line("%d CAM %.1f,%.1f,%.1f" % [frame, world.x, world.y, world.z])
		elif frame == -warm + 2 and city.has_method("finish_far_city"):
			city.call("finish_far_city")
		if frame % 20 == 0:
			print("POPSTRIP frame %d" % frame)
		frame += 1
	log.close()
	print("POPSTRIP frames=%d out=%s" % [frame, out_dir])
	quit()


func _dist(plan, k: Vector2i, xz: Vector2) -> float:
	if plan == null:
		return -1.0
	var r: Rect2 = plan.owned_rect(k.x, k.y)
	return r.get_center().distance_to(xz)


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d
