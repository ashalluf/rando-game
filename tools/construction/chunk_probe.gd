extends SceneTree
## Builds one chunk FULL (BLOCK=ix,iz) and lists what Construction put in it (seconds, headless).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 8:
		await process_frame
	var city = current_scene
	var b := OS.get_environment("BLOCK").split(",")
	var k := Vector2i(int(b[0]), int(b[1]))
	var con: GDScript = load("res://scripts/world/construction.gd")
	var site: Dictionary = con.call("tower_site", city.plan, k.x, k.y)
	print("SITE ", site.get("foot"), " seed ", site.get("seed"))
	var chunk = city._new_chunk(k, 0)
	chunk.build()
	for c in chunk.get_children():
		if c.get("lot_size") != null or String(c.name).begins_with("Constr") or c.is_in_group("tower_crane"):
			print("CHILD ", c.name, " ", c.get_class(), " ", c.position, " ", c.get("seed"))
			if c is MeshInstance3D and c.mesh:
				print("   MESH surfaces=", c.mesh.get_surface_count(), " aabb=", c.mesh.get_aabb(), " custom=", c.custom_aabb, " vis=", c.visible)
	quit()
