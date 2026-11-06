extends SceneTree
## The knee-high plants (PropFactory.PLANTS, FLOWERS, GRASS_CLUMPS) in a row on a lawn-grey floor,
## seen from a crouching player's eye about a metre and a half off: the close-range proof for
## their texture budget (tools/texture_budget/budget.txt).
##
##   OUT=plants.png LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/texture_budget/plant_lineup.gd --resolution 1280x720
##
## Env: OUT, DIST (camera distance, default 1.6), SPACING (default 0.75).

func _init() -> void:
	_build.call_deferred()


func _build() -> void:
	await process_frame
	var root := Node3D.new()
	get_root().add_child(root)
	await process_frame
	# PropFactory's PLANTS, FLOWERS and GRASS_CLUMPS (it needs the autoloads, so not loaded here).
	var files: Array = []
	var d := DirAccess.open("res://assets/models")
	for f in d.get_files():
		if f.ends_with(".glb") and (f.begins_with("plant_") or f.begins_with("flower_") or f.begins_with("grass_")):
			files.append(f)
	files.sort()
	var cursor := 0.0
	var spots: Array = [] # [centre x, width]
	for i in files.size():
		var scene := load("res://assets/models/" + files[i]) as PackedScene
		if scene == null:
			continue
		var inst := scene.instantiate() as Node3D
		root.add_child(inst)
		var aabb := AABB()
		var first := true
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
		inst.position = Vector3(cursor - aabb.position.x, -aabb.position.y, -aabb.get_center().z)
		spots.append([cursor + aabb.size.x * 0.5, maxf(aabb.size.x, aabb.size.y)])
		cursor += aabb.size.x + 0.5
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.33, 0.28)
	pm.material = fm
	floor.mesh = pm
	root.add_child(floor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	root.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 50
	root.add_child(cam)
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "plants.png"
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 0.0
	for k in spots.size():
		var cx: float = spots[k][0]
		var w: float = spots[k][1]
		var dd := dist if dist > 0.0 else clampf(w * 1.1, 0.9, 3.0)
		cam.position = Vector3(cx, w * 0.45 + 0.3, dd)
		cam.look_at(Vector3(cx, w * 0.3, 0))
		for i in 4:
			await process_frame
		var path := out.get_basename() + "_%02d.png" % k
		get_root().get_texture().get_image().save_png(path)
		print("saved ", path, " ", files[k])
	quit()
