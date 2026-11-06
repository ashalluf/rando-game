extends Node
## The film lot's crew, printed (headless, a couple of minutes): builds the studio street's FULL
## chunks and lists each walker, whether Rc4FilmLot.dress_crew() marked it crew and what its body
## material's top / trousers are.  godot --headless --path . res://tools/rc4_film_lot/crew_probe.tscn

func _ready() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(city)
	for i in 10:
		await get_tree().process_frame
	var plan = city.get("plan")
	for k: Vector2i in [Vector2i(6, -3), Vector2i(7, -3)]:
		var ch = city.call("_new_chunk", k, 0)
		ch.build()
		for f in 3:
			await get_tree().process_frame
		for c in ch.get_children():
			if c is Pedestrian:
				var p := c as Pedestrian
				var desc := ""
				for mi: MeshInstance3D in p._meshes:
					if mi.material_override is ShaderMaterial:
						var m := mi.material_override as ShaderMaterial
						desc += " %s top=%s/%s pants=%s id=%d" % [m.shader.resource_path.get_file(), m.get_shader_parameter("cloth_value"), m.get_shader_parameter("cloth_strength"), m.get_shader_parameter("pants_value"), m.get_instance_id()]
				print("WALKER %s crew=%s ready=%s meshes=%d%s" % [p.name, p.get_meta("rc4_crew", "-"), p.is_node_ready(), p._meshes.size(), desc])
	get_tree().quit()
