extends Node
## Finds the roadside pads (Roadside) for framing stills and times their build, headless:
##   godot --headless --path . res://tools/roadside_probe.tscn -- --spawn=x,z   (env R=blocks)
## (a scene, not --script: it names CityChunk, which needs the autoloads.)
## Builds the far city's capture of every block within R (default 8) blocks of the point with
## Roadside.recording on and prints every pad: kind, size, true-world centre, which way it faces,
## and two EYEs for tools/glshot/still_shot.gd - from across the street, and from the air. With
## FULL=n it then builds the FULL chunks of the first n pads (KIND= to filter) and prints the time
## each took and the roadside triangle count.

func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	add_child(city)
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 30:
		await get_tree().process_frame
	var plan: CityPlan = city.get("plan")
	var r := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 8
	var want := OS.get_environment("KIND")
	var k0: Vector2i = plan.block_index_at(c)
	Roadside.recording = true
	Roadside.record.clear()
	for bx in range(k0.x - r, k0.x + r + 1):
		for bz in range(k0.y - r, k0.y + r + 1):
			var cap := CityChunk.new()
			cap.plan = plan
			cap.ix = bx
			cap.iz = bz
			cap.level = CityChunk.Level.LOD
			cap.style = city.chunk_style()
			cap.capturing = true
			cap.build()
			cap.free()
	var counts := {}
	var picked: Array = []
	for e: Dictionary in Roadside.record:
		var name: String = Roadside.KIND_NAMES[int(e.kind)]
		counts[name] = int(counts.get(name, 0)) + 1
		if want != "" and name != want:
			continue
		var ctr: Vector2 = e.centre
		var dir: Vector2 = e.dir
		var g: float = float(e.g)
		# Across the street, a little to one side, looking back at the pad.
		var side := Vector2(-dir.y, dir.x)
		var eye: Vector2 = ctr + dir * (float(e.d) * 0.5 + 22.0) + side * 9.0
		var look := ctr - eye
		var yaw := rad_to_deg(atan2(-look.x, -look.y))
		var air: Vector2 = ctr + dir * (float(e.d) * 0.5 + 45.0) + side * 25.0
		var alook := ctr - air
		var ayaw := rad_to_deg(atan2(-alook.x, -alook.y))
		print("PAD %s %.0fx%.0f at=%.1f,%.1f face=%s block=%s EYE=%.1f,%.1f,%.1f,%.0f,-4 AIR=%.1f,%.1f,%.1f,%.0f,-28" % [
			name, float(e.w), float(e.d), ctr.x, ctr.y, dir, e.block, eye.x, g + 1.95, eye.y, yaw, air.x, g + 34.0, air.y, ayaw])
		picked.append(e)
	print("PADS ", Roadside.record.size(), " ", counts)
	var full := int(OS.get_environment("FULL")) if OS.get_environment("FULL") != "" else 0
	for i in mini(full, picked.size()):
		var k: Vector2i = picked[i].block
		Roadside.built_tris = 0
		Roadside.built_usec = 0
		var t0 := Time.get_ticks_usec()
		Roadside.record.clear()
		var chunk: CityChunk = city.call("_new_chunk", k, CityChunk.Level.FULL)
		chunk.build()
		for e: Dictionary in Roadside.record:
			print("   built ", Roadside.KIND_NAMES[int(e.kind)], " at ", e.centre)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("FULL block %s (%s) chunk %.1f ms, roadside pads %.1f ms, %d triangles" % [k, Roadside.KIND_NAMES[int(picked[i].kind)], ms, Roadside.built_usec / 1000.0, Roadside.built_tris])
		chunk.free()
	get_tree().quit()
