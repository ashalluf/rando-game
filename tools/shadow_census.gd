extends SceneTree
## What the sun's shadow pass has to draw: every visible shadow-casting mesh within the shadow
## reach of the player, as triangles (at LOD 0) per category, next to the same count for what is
## drawn at all. The directional shadow pass renders each caster once per cascade it falls in, so
## this is the list to cut from when that pass dominates the GPU profile (tools/gpu_profile.gd).
##
##   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 800x600x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/shadow_census.gd --resolution 800x600 -- --spawn=734.9,300,0,-3
##
## Not --headless: the dummy renderer keeps no mesh data, so every count reads zero.
var _tri_cache := {}


func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in _env_int("FRAMES", 40):
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	var reach := 500.0
	var sun := current_scene.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		reach = sun.directional_shadow_max_distance
	var shadow := {}
	var drawn := {}
	for n in current_scene.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var tris := _instance_tris(gi)
		if tris <= 0:
			continue
		var d := gi.global_transform * gi.get_aabb().get_center()
		var dist := d.distance_to(player.global_position)
		var cat := _category(gi)
		_add(drawn, cat, tris)
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and dist < reach + gi.get_aabb().size.length() * 0.5:
			_add(shadow, cat + (" [far]" if dist > 150.0 else " [near]"), tris)
	_report("SHADOW CASTERS within %.0f m (LOD0 triangles; [near] < 150 m)" % reach, shadow)
	_report("DRAWN at all (LOD0 triangles)", drawn)
	quit()


func _add(table: Dictionary, key: String, tris: int) -> void:
	if not table.has(key):
		table[key] = [0, 0]
	table[key][0] += 1
	table[key][1] += tris


func _report(title: String, table: Dictionary) -> void:
	var total := 0
	for k in table:
		total += int(table[k][1])
	print("%s: %d total" % [title, total])
	var keys := table.keys()
	keys.sort_custom(func(a, b): return table[a][1] > table[b][1])
	for k in keys.slice(0, _env_int("TOP", 30)):
		print("  %10d tris %5.1f%%  nodes %5d  %s" % [table[k][1], 100.0 * table[k][1] / maxf(total, 1), table[k][0], k])


## What a node is, for grouping: the kind of thing that owns it, plus the batch name for the
## chunks' MultiMeshes (their node names are the batch keys).
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
				return cls
			"CityChunk":
				var lvl := "FULL" if int(n.get("level")) == 0 else "LOD"
				var nm := String(gi.name).rstrip("0123456789_@")
				return "Chunk %s %s" % [lvl, nm]
		n = n.get_parent()
	return "Other " + String(gi.name).rstrip("0123456789_@")


func _instance_tris(gi: GeometryInstance3D) -> int:
	if gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			return 0
		var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		return _mesh_tris(mm.mesh) * count
	if gi is MeshInstance3D:
		var mesh := (gi as MeshInstance3D).mesh
		return _mesh_tris(mesh) if mesh else 0
	return 0


func _mesh_tris(mesh: Mesh) -> int:
	if _tri_cache.has(mesh):
		return _tri_cache[mesh]
	var t := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		if a.is_empty():
			continue
		var idx = a[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			t += idx.size() / 3
		else:
			t += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_tri_cache[mesh] = t
	return t


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
