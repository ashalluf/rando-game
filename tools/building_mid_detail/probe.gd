extends SceneTree
## Builds generated Buildings headless and prints what FacadeMid hung on each (triangles by kind),
## so a still can be aimed at a seed that has the piece you want to look at:
##
##   godot --headless --path . --script tools/building_mid_detail/probe.gd
##
## Env: SEEDS=a-b (default 1-40), FINISH, STYLE (as building_shot.gd), LOT, HMIN, HMAX, SHOPS=0.

const KINDS := ["paint", "galv", "fabric", "leaf", "pot", "plastic", "room", "glass", "sign", "wood", "louvre", "rubber", "dish", "soil"]


func _initialize() -> void:
	for i in 3:
		await process_frame
	var scene := load("res://scenes/props/building.tscn") as PackedScene
	var rng := OS.get_environment("SEEDS")
	var a := 1
	var z := 40
	if rng != "":
		a = int(rng.get_slice("-", 0))
		z = int(rng.get_slice("-", 1))
	for sd in range(a, z + 1):
		var b: Node = scene.instantiate()
		b.seed = sd
		var lot := float(_env("LOT", "24"))
		b.lot_size = Vector2(lot, lot)
		b.min_height = float(_env("HMIN", "12"))
		b.max_height = float(_env("HMAX", "24"))
		if _env("FINISH", "") != "":
			b.finish_options.assign([int(_env("FINISH", "0"))])
		if _env("STYLE", "") != "":
			b.window_style_force = int(_env("STYLE", "0"))
		if _env("SHOPS", "") == "0":
			b.allow_storefront = false
		get_root().add_child(b)
		var mi := b.get_node_or_null("MidDress") as MeshInstance3D
		var line := "seed %d finish %d style %d h %.1f: " % [sd, b.finish, b.window_style, b.height]
		if mi == null:
			print(line, "none")
		else:
			var cols: PackedColorArray = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var counts := {}
			for k in range(0, cols.size(), 4):
				var kind := int(floor(cols[k].a * 16.0 + 0.5))
				counts[KINDS[kind]] = int(counts.get(KINDS[kind], 0)) + 2
			print(line, counts)
		b.free()
	quit()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d
