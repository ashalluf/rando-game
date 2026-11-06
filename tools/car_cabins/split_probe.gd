extends Node
## CarDoorSplit on every body it knows: time, the body's and each door's triangles, the hinge.
## Needs mesh data: xvfb-run -a godot --rendering-driver opengl3 --path . tools/car_cabins/split_probe.tscn

func _ready() -> void:
	await get_tree().process_frame
	for type: int in CarDoorSplit.DOORS.keys():
		var path: String = Vehicle.BODY_MODELS[type]
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		var mesh: Mesh = null
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			if not String(mi.name).ends_with("_far"):
				mesh = (mi as MeshInstance3D).mesh
		var t0 := Time.get_ticks_usec()
		CarDoorSplit.request(type, mesh)
		var job: Variant = CarDoorSplit._jobs.get(type)
		var worst := 0.0
		var per := {}
		while job != null and not job.finished:
			var st: int = job._stage
			var ts := Time.get_ticks_usec()
			job.advance()
			var dt := (Time.get_ticks_usec() - ts) / 1000.0
			worst = maxf(worst, dt)
			per[st] = snappedf(maxf(per.get(st, 0.0), dt), 0.1)
		CarDoorSplit.step(1 << 30)
		var r := CarDoorSplit.result(type)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("  %s: longest single step %.1f ms %s" % [Vehicle.BODY_NAMES[type], worst, per])
		var line := "%s: %.0f ms real=%s body=%d" % [Vehicle.BODY_NAMES[type], ms, r.real, _tris(r.body)]
		for d: Dictionary in r.doors:
			line += " | door %+d tris=%d surfs=%s hinge=%s skin=%.3f belt=%.3f top=%.3f" % [int(d.side), _tris(d.mesh), d.surf_map, d.hinge, d.skin_x, d.belt, d.top]
		print(line)
		var car := Vehicle.new()
		car.setup(type as Vehicle.BodyType, Color.WHITE, Vehicle.Addon.NONE)
		CarCabin._cache.erase(type)
		var data := CarCabin.measure(type, mesh, CarCabin.context(car, Transform3D.IDENTITY))
		var tk := Time.get_ticks_usec()
		var kit := CarInteriorKit.build(type, data, r.doors)
		var tris := 0
		for m: Mesh in [kit.cabin, kit.wheel] + kit.cards:
			tris += _tris(m)
		print("  kit %.1f ms, %d triangles (cabin + wheel + cards)" % [(Time.get_ticks_usec() - tk) / 1000.0, tris])
		car.free()
		inst.free()
	get_tree().quit()


func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var n := 0
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		if arr[Mesh.ARRAY_INDEX] != null:
			n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		else:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
