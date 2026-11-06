extends SceneTree
## Walks the coast and prints what BeachAmenities plans (restrooms, the stand, gyms, showers, racks,
## poles, drums) with an EYE for still_shot.gd looking at each station, and how long the meshes
## take to build. Headless, seconds:
##   godot --headless --path . --script tools/beach_amenities/probe.gd
## Z0, Z1 (default -1500, 2500); KIND=restroom|concession|gym|court|shower only lists that kind.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var ba: GDScript = load("res://scripts/world/beach_amenities.gd")
	var z0 := float(OS.get_environment("Z0")) if OS.get_environment("Z0") != "" else -1500.0
	var z1 := float(OS.get_environment("Z1")) if OS.get_environment("Z1") != "" else 2500.0
	var only := OS.get_environment("KIND")
	var t0 := Time.get_ticks_usec()
	ba.call("warm")
	print("WARM meshes %.1f ms" % [(Time.get_ticks_usec() - t0) / 1000.0])
	for key: String in (ba.get("_meshes") as Dictionary).keys():
		var m: Mesh = ba.get("_meshes")[key]
		var tris := 0
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print("MESH %s %d triangles" % [key, tris])
	t0 = Time.get_ticks_usec()
	var items: Array = ba.call("plan_stretch", plan, z0, z1, [])
	print("PLAN %.1f ms" % [(Time.get_ticks_usec() - t0) / 1000.0])
	var counts := {}
	for it: Dictionary in items:
		var k := String(it.kind)
		counts[k] = int(counts.get(k, 0)) + 1
		if only != "" and k != only:
			continue
		if k in ["can", "rack", "shower"] and only == "":
			continue
		var at: Vector2 = it.at
		var yaw: float = it.yaw
		# A camera in front (seaward) of it, 16 m off, a little up, looking at it.
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var eye := at + fwd * 16.0 + Vector2(fwd.y, -fwd.x) * 6.0
		var d := at - eye
		var cam_yaw := rad_to_deg(atan2(-d.x, -d.y))
		print("ITEM %s %s at=%.1f,%.1f EYE=%.1f,2.4,%.1f,%.0f,-6" % [k, it.mesh, at.x, at.y, eye.x, eye.y, cam_yaw])
	print("COUNTS ", counts)
	quit()
