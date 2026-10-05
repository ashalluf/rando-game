extends SceneTree
## What each kind of thing really costs the renderer in one frame: hides one category at a time
## (cars, trees, people, buildings, ...) and reads the frame's triangle, draw-call and object
## counters with it gone, then does the same with only its SHADOWS switched off. The differences
## are that category's share after LODs and culling - unlike a census, which counts full detail.
##
##   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 800x600x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/tri_split.gd --resolution 800x600 -- --spawn=734.9,300,0,-3 --quality=0
##
## Must run under a real renderer (see tools/geo_count.gd): --headless reads zero for all of it.
const CATEGORIES := ["Vehicle", "Pedestrian", "Building", "Trees", "Grass", "StreetProps", "FarGround", "Landmark", "Other"]


func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in _env_int("FRAMES", 40):
		await process_frame
	var nodes := {}
	for c in CATEGORIES:
		nodes[c] = []
	for n in current_scene.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.visible:
			nodes[_category(gi)].append(gi)
	var base := await _measure()
	print("BASE tris=%d draws=%d objects=%d" % base)
	for c in CATEGORIES:
		var list: Array = nodes[c]
		if list.is_empty():
			continue
		for gi: GeometryInstance3D in list:
			if is_instance_valid(gi):
				gi.visible = false
		var hidden := await _measure()
		for gi: GeometryInstance3D in list:
			if is_instance_valid(gi):
				gi.visible = true
		var saved := {}
		for gi: GeometryInstance3D in list:
			if is_instance_valid(gi):
				saved[gi] = gi.cast_shadow
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var unshadowed := await _measure()
		for gi in saved:
			if is_instance_valid(gi):
				(gi as GeometryInstance3D).cast_shadow = saved[gi]
		print("%-12s nodes %5d   costs tris %9d (%4.1f%%) draws %5d objects %5d   of which shadows: tris %9d draws %5d" % [
			c, list.size(), base[0] - hidden[0], 100.0 * (base[0] - hidden[0]) / maxf(base[0], 1),
			base[1] - hidden[1], base[2] - hidden[2], base[0] - unshadowed[0], base[1] - unshadowed[1]])
	quit()


func _measure() -> Array:
	for i in 3:
		await process_frame
	return [int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))]


func _category(gi: GeometryInstance3D) -> String:
	var n: Node = gi
	while n != null:
		var cls := String(n.get_script().get_global_name()) if n.get_script() else ""
		match cls:
			"Building":
				return "Building"
			"Vehicle", "Aircraft":
				return "Vehicle"
			"Pedestrian", "Ragdoll", "Avatar", "Player":
				return "Pedestrian"
			"CityChunk":
				var nm := String(gi.name)
				for k in ["tree", "palm", "bush", "shrub", "flower", "plant", "gclump", "Planting"]:
					if nm.contains(k):
						return "Trees"
				if nm.contains("grass"):
					return "Grass"
				if nm.contains("FarGround"):
					return "FarGround"
				if nm.begins_with("Batch"):
					return "StreetProps"
				return "Other"
		if String(n.name).begins_with("Landmark") or String(n.name).begins_with("FarLandmark"):
			return "Landmark"
		n = n.get_parent()
	return "Other"


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
