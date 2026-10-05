extends Node3D
## The 25 road wear stamps laid out on a strip of real road (the road's own material), lit by the
## city scene's environment, for judging the library in seconds:
##   OUT=/tmp/rw_show.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . res://tools/road_wear/showroom.tscn --resolution 1280x720
## ROW=0 every stamp once (5 x 5, 4 m apart; CAM / LOOK / FOV place the camera); ROW=n stamp n
## eight times with its variations (threshold, mirror, age, a pair); WET=0..1 road_wetness,
## RAIN=0..1 rain_intensity, HOUR for the sun's height (14 by default).

func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	for c in city.get_children():
		if c is WorldEnvironment or c is DirectionalLight3D:
			c.owner = null
			city.remove_child(c)
			add_child(c)
			if c is DirectionalLight3D:
				(c as DirectionalLight3D).rotation_degrees = Vector3(-52.0, 35.0, 0.0)
				(c as DirectionalLight3D).light_energy = 1.0
	city.free()
	RenderingServer.global_shader_parameter_set("road_wetness", float(OS.get_environment("WET")) if OS.get_environment("WET") != "" else 0.0)
	RenderingServer.global_shader_parameter_set("rain_intensity", float(OS.get_environment("RAIN")) if OS.get_environment("RAIN") != "" else 0.0)
	RenderingServer.global_shader_parameter_set("ground_detail", 1.0)
	RenderingServer.global_shader_parameter_set("road_stamp_near", 1.0)
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	road.mesh = plane
	road.material_override = PropFactory.road("asphalt", 7.0, Color(0.842, 0.842, 0.884), 12345)
	add_child(road)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = RoadWear.mesh()
	var row := int(OS.get_environment("ROW")) if OS.get_environment("ROW") != "" else 0
	var items: Array = []
	if row <= 0:
		for i in RoadWearTable.STAMPS.size():
			items.append([i, Vector3((i % 5 - 2) * 4.2, 0.005, (i / 5 - 2) * 4.2), 0, 0, 0.3, -1])
	else:
		var i := row - 1
		var thr := [0, 8, 16, 24, 0, 12, 0, 20]
		var ages := [0.0, 0.0, 0.0, 0.0, 1.0, 0.5, 0.3, 0.8]
		var pairs := [-1, -1, -1, -1, -1, -1, 5, 11]
		for k in 8:
			items.append([i, Vector3((k % 4 - 1.5) * 4.0, 0.005, (k / 4 - 0.5) * 5.0), thr[k], 1 if k == 5 else 0, ages[k], pairs[k]])
	mm.instance_count = items.size()
	for n in items.size():
		var it: Array = items[n]
		var size: Vector2 = RoadWearTable.STAMPS[it[0]][1]
		var s := minf(1.0, 3.6 / maxf(size.x, size.y))
		mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(size.x * s, 1.0, size.y * s)), it[1]))
		var flags: int = it[3] + (64 if (int(RoadWearTable.STAMPS[it[0]][3]) & RoadWearTable.SURFACE) != 0 else 0) + (128 if (int(RoadWearTable.STAMPS[it[0]][3]) & RoadWearTable.DEEP) != 0 else 0)
		var r := float(it[0]) + (32.0 * float(it[5] + 1) if it[5] >= 0 else 0.0)
		mm.set_instance_custom_data(n, Color(r, float(flags), float(int(it[2]) * 32 + 8), 2.0))
		mm.set_instance_color(n, Color(0.842, 0.842, 0.884, it[4]))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var cam := Camera3D.new()
	add_child(cam)
	var p := _vec(OS.get_environment("CAM"), Vector3(0, 9.0, 12.0) if row <= 0 else Vector3(0, 4.5, 7.5))
	var look := _vec(OS.get_environment("LOOK"), Vector3(0, 0, 0))
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 55.0
	cam.look_at_from_position(p, look)
	cam.make_current()
	for f in 12:
		await get_tree().process_frame
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/rw_show.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()


func _vec(s: String, fallback: Vector3) -> Vector3:
	if s == "":
		return fallback
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
