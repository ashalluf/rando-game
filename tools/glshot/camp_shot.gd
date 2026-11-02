extends SceneTree
## A sidewalk encampment laid out against a wall, close up, with a row of the people who live there
## in every pose - for judging the kit and the poses (RoughSleeper), which a street camera shows
## eighty pixels tall.
##
##   OUT=camp.png LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/camp_shot.gd --resolution 1280x720
##
## Env: OUT (png), YAW (degrees to orbit the camera; 0 is front-on), DIST (metres), HEIGHT (camera
## height), LOOK_X (slides the camera and its target along the wall, metres), PEOPLE=0 leaves the people out, KIT=0 leaves the kit out, SEED (shifts the people's
## seeds, so a different set of rigs), POSES (comma list of the poses to show: 0 sit, 1 lie,
## 2 slump, 3 in a camp chair, 4 standing, 5 pushing a loaded cart; default all), COWER=1
## frightens them first (the slumped cower, the rest get up).
## Everything is loaded dynamically: this script compiles before the autoloads exist.
func _initialize() -> void:
	var yaw := deg_to_rad(float(OS.get_environment("YAW"))) if OS.get_environment("YAW") != "" else 0.0
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 7.5
	var height := float(OS.get_environment("HEIGHT")) if OS.get_environment("HEIGHT") != "" else 1.9
	var seed_shift := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 0
	var look_x := float(OS.get_environment("LOOK_X")) if OS.get_environment("LOOK_X") != "" else 0.0
	var poses := [0, 1, 2, 3, 4, 5]
	if OS.get_environment("POSES") != "":
		poses = []
		for p in OS.get_environment("POSES").split(","):
			poses.append(int(p))

	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.68, 0.76)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.74, 0.78, 0.86)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	root.add_child(sun)
	# Pavement and a building wall behind it (the wall's face at z = -0.05).
	_slab(root, Vector3(22.0, 0.2, 9.0), Vector3(0.0, -0.1, 2.5), Color(0.52, 0.51, 0.49))
	_slab(root, Vector3(22.0, 6.0, 0.4), Vector3(0.0, 3.0, -0.25), Color(0.56, 0.47, 0.40))
	_slab(root, Vector3(22.0, 0.2, 3.0), Vector3(0.0, -0.12, 8.5), Color(0.18, 0.18, 0.19))
	# Something to stand on for the one who walks (PUSH): the slabs above are only drawn.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 0.2, 40.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0.0, -0.1, 0.0)
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)

	await process_frame
	await process_frame
	var pf = load("res://scripts/world/prop_factory.gd")
	var enc = load("res://scripts/world/encampment.gd")
	if OS.get_environment("KIT") != "0":
		# [piece, x, z (the piece's back to the wall), yaw, colour]
		var layout := [
			["tent_dome", -8.2, 1.1, 0.0, enc.TENT_COLORS[0]],
			["tarp_canopy", -5.2, 1.2, 0.0, enc.TARP_COLORS[0]],
			["mattress", -5.2, 0.6, 0.0, Color.WHITE],
			["bedding", -5.2, 0.55, 0.0, enc.CLOTH_COLORS[1]],
			["cart", -2.6, 0.7, 0.3, Color.WHITE],
			["bags_pile", -1.5, 0.45, 0.0, enc.BAG_COLORS[0]],
			["tent_pop", 1.0, 1.0, 0.0, enc.TENT_COLORS[4]],
			["cardboard", 3.2, 0.6, 0.0, Color.WHITE],
			["chair", 4.6, 0.7, -0.4, enc.CLOTH_COLORS[2]],
			["bicycle", 6.2, 0.5, 0.0, enc.BIKE_COLORS[1]],
			["tarp_mound", 8.3, 0.9, 0.0, enc.TARP_COLORS[2]],
			["bag_trash", 2.2, 1.9, 0.6, enc.BAG_COLORS[0]],
			["bag_duffel", 4.0, 1.8, 1.1, enc.CLOTH_COLORS[4]],
			["bike_wheel", 7.1, 1.7, 1.4, enc.BIKE_COLORS[0]],
			["bike_frame", 5.4, 2.1, 0.9, enc.BIKE_COLORS[3]],
			["box", -1.1, 1.7, 0.2, Color.WHITE],
			["cardboard", 6.6, 3.0, 0.1, Color.WHITE],
			["loaded_cart", -9.6, 2.4, 1.2, enc.CLOTH_COLORS[0]],
			["bundle", -0.5, 1.6, 0.4, enc.CLOTH_COLORS[3]],
		]
		for item: Array in layout:
			var mesh: Mesh = pf.encampment(item[0])
			if mesh == null:
				print("camp_shot: no piece ", item[0])
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, float(item[3])), Vector3(float(item[1]), 0.0, float(item[2]))))
			mm.set_instance_color(0, item[4])
			mm.set_instance_custom_data(0, Color(0.5, 0.37, 0.0, 0.0))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			root.add_child(mmi)
	if OS.get_environment("PEOPLE") != "0":
		var rs = load("res://scripts/npc/rough_sleeper.gd")
		# [pose, x, z, lift, yaw]: on the mattress under the tarp, against the wall, on the
		# cardboard, two standing slumped on the pavement, one on cardboard at the kerb side, one
		# in the camp chair, two standing talking by the bundle, one pushing a cart past.
		var people := [[1, -5.2, 0.62, 0.21], [0, -0.2, 0.5, 0.02], [0, 3.2, 0.5, 0.02],
			[2, -3.0, 2.8, 0.0], [2, 1.6, 3.0, 0.0], [1, 6.6, 3.0, 0.02],
			[3, 4.6 + sin(-0.4) * 0.05, 0.7 - cos(-0.4) * 0.05, 0.0, PI - 0.4],
			[4, -1.3, 2.3, 0.0, PI * 0.5 + 0.3], [4, 0.1, 2.5, 0.0, -PI * 0.5 - 0.2],
			[5, -7.0, 3.6, 0.0, -PI * 0.5]]
		for i in people.size():
			var spec: Array = people[i]
			if not poses.has(int(spec[0])):
				continue
			var ped: CharacterBody3D = rs.new()
			var at := Vector2(float(spec[1]), float(spec[2]))
			var face: float = float(spec[4]) if spec.size() > 4 else PI
			ped.setup_sleeper(Rect2(-60.0, -60.0, 120.0, 120.0), 3.0, 7771 + i * 131 + seed_shift, int(spec[0]), at, face)
			ped.set("lift", float(spec[3]))
			ped.position = Vector3(at.x, float(spec[3]), at.y)
			root.add_child(ped)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.position = Vector3(look_x + sin(yaw) * dist, height, 1.3 + cos(yaw) * dist)
	root.add_child(cam)
	cam.look_at(Vector3(look_x, 0.55, 1.3), Vector3.UP)
	cam.current = true
	for i in 16:
		await process_frame
	if OS.get_environment("COWER") == "1":
		for n in get_nodes_in_group("pedestrian"):
			n.call("_scare", Vector3(0.0, 0.0, 12.0))
		for i in 40:
			await physics_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "camp_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


func _slab(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
