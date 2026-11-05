extends SceneTree
## What does a camera ray land on? Loads the city headless at a spawn, waits for the chunks, then
## casts rays from EYE=x,y,z,yaw,pitch (true world, y over ground) across the view (FOV, a COLSxROWS
## grid) and prints the collider's path and, for a MeshInstance-backed building, its owner.
##   godot --headless --path . --script tools/rc3_broadway_night/pick.gd -- --spawn=x,z,yaw,pitch
##   env EYE=2999,1.7,190,200,5 FOV=55 COLS=9 ROWS=5
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	var streamer: Node3D = scene.instantiate()
	root.add_child(streamer)
	for i in 400:
		await process_frame
	var e := OS.get_environment("EYE").split(",")
	var ws: Node = root.get_node("/root/WorldState")
	var plan: Variant = streamer.get("plan")
	var tw := Vector3(float(e[0]), 0.0, float(e[2]))
	var gy: float = plan.height_at(Vector2(tw.x, tw.z)) if plan != null else 0.0
	tw.y = gy + float(e[1])
	var eye: Vector3 = ws.call("to_local", tw)
	var yaw := deg_to_rad(float(e[3]))
	var pitch := deg_to_rad(float(e[4]))
	var fov := deg_to_rad(float(OS.get_environment("FOV") if OS.get_environment("FOV") != "" else "55"))
	var cols := int(OS.get_environment("COLS") if OS.get_environment("COLS") != "" else "9")
	var rows := int(OS.get_environment("ROWS") if OS.get_environment("ROWS") != "" else "5")
	var space: PhysicsDirectSpaceState3D = streamer.get_world_3d().direct_space_state
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var aspect := 16.0 / 9.0
	for r in rows:
		for c in cols:
			var sx := (float(c) + 0.5) / float(cols) * 2.0 - 1.0
			var sy := 1.0 - (float(r) + 0.5) / float(rows) * 2.0
			var dir := b * Vector3(sx * tan(fov * 0.5) * aspect, sy * tan(fov * 0.5), -1.0).normalized()
			var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 400.0, 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				print("PICK r%d c%d sky" % [r, c])
				continue
			var n: Node = hit.collider
			var p: Vector3 = ws.call("to_world", hit.position)
			var path := str(n.get_path()).replace("/root/", "")
			var extra := ""
			if n.get_script() != null:
				extra = str(n.get_script().resource_path.get_file())
			print("PICK r%d c%d d%.0f at %.0f,%.0f,%.0f n%s %s %s" % [r, c, eye.distance_to(hit.position), p.x, p.y, p.z, str(hit.normal.snapped(Vector3.ONE * 0.1)), path.right(90), extra])
	quit()
