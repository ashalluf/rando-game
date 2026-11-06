extends "res://tools/glshot/still_shot.gd"
## Which pass of the sea is that? Run like still_shot.gd with TREES_AB=1 (the per-shot hook): the
## held frame again (_again; GAIN= sets Weather.surf_gain first), with the crest's step back (crest_carry 0, _crest0), with the ocean materials' glints off (_glint0), then ocean_closeup 0
## (_closeup0), then water_review 0 (_review0), saved beside the shot.

func _ocean_mats() -> Array:
	var out := []
	for n in current_scene.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var mats := []
		if gi.material_override:
			mats.append(gi.material_override)
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			for i in (gi as MeshInstance3D).mesh.get_surface_count():
				var m := (gi as MeshInstance3D).get_active_material(i)
				if m:
					mats.append(m)
		for m in mats:
			if m is ShaderMaterial and (m as ShaderMaterial).shader and String((m as ShaderMaterial).shader.resource_path).ends_with("ocean.gdshader") and not out.has(m):
				out.append(m)
	return out


func _save(path: String, tag: String) -> void:
	for i in 3:
		await process_frame
	get_root().get_texture().get_image().save_png(path.get_basename() + "_%s.png" % tag)


func _trees_ab(path: String) -> void:
	var mats := _ocean_mats()
	print("WATER_AB ocean materials ", mats.size())
	if OS.get_environment("GAIN") != "":
		current_scene.get_node("Weather").set("surf_gain", float(OS.get_environment("GAIN")))
	await _save(path, "again")
	# REPEAT=n: n more held frames (something on this sea flickered frame to frame).
	for k in int(OS.get_environment("REPEAT")) if OS.get_environment("REPEAT") != "" else 0:
		await _save(path, "again%d" % k)
	for m: ShaderMaterial in mats:
		m.set_shader_parameter("crest_carry", 0.0)
	await _save(path, "crest0")
	for m: ShaderMaterial in mats:
		m.set_shader_parameter("crest_carry", 1.0)
	for m: ShaderMaterial in mats:
		m.set_shader_parameter("glint_energy", 0.0)
	await _save(path, "glint0")
	RenderingServer.global_shader_parameter_set("ocean_closeup", 0.0)
	await _save(path, "closeup0")
	RenderingServer.global_shader_parameter_set("water_review", 0.0)
	await _save(path, "review0")
