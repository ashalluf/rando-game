extends SceneTree
## One gun on its own, big in frame, lit like a studio product shot - for judging the weapon
## models (tools/make_weapons.py) up close, which the hero shot only shows at arm's length.
##
##   OUT=gun.png WEAPON=0 YAW=0 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/weapon_shot.gd --resolution 1200x600
##
## Env: OUT (png), WEAPON (0 AK, 1 rocket launcher, 2 shotgun: the Weapon node the game
## builds, code-built parts and all) or MODEL (a res:// .glb on its own), YAW (degrees round
## the gun; 0 looks at its right side, 180 its left, 90 down the muzzle), PITCH (degrees the
## camera looks down), ZOOM (1 frames the whole gun, 3 is three times closer), FOCUS (x,y,z in
## the gun's space to aim at instead of the middle of its bounds). Prints each mesh's triangle
## count and how many LODs Godot generated for it.
func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.45, 0.58)
	sky_mat.sky_horizon_color = Color(0.72, 0.70, 0.66)
	sky_mat.ground_horizon_color = Color(0.45, 0.42, 0.38)
	sky_mat.ground_bottom_color = Color(0.16, 0.15, 0.14)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.31, 0.33)
	# The city's own daylight numbers (city.tscn, DayNight): AgX at exposure 1.25, a 1.3 sun and
	# a weak sky fill, so a finish judged here looks the same in the street.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	e.tonemap_white = 5.0
	env.environment = e
	stage.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, 200.0, 0.0)
	rim.light_energy = 0.4
	stage.add_child(rim)

	var gun: Node3D
	var model := OS.get_environment("MODEL")
	if model != "":
		gun = (load(model) as PackedScene).instantiate()
	else:
		# By path, not class name: this script compiles before the autoloads the weapons use.
		var which := int(OS.get_environment("WEAPON")) if OS.get_environment("WEAPON") != "" else 0
		var scripts := ["assault_rifle", "rocket_launcher", "shotgun"]
		gun = (load("res://scripts/weapons/%s.gd" % scripts[which]) as GDScript).new()
	stage.add_child(gun)
	await process_frame

	var box := AABB()
	var first := true
	for mi in _meshes(gun):
		var tris := 0
		var lods := []
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var surf: Dictionary = RenderingServer.mesh_get_surface(mi.mesh.get_rid(), s)
			lods.append((surf.get("lods", []) as Array).size())
		print("mesh ", mi.name, ": ", tris, " triangles, LODs per surface ", lods)
		var b: AABB = gun.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("bounds ", box.position, " size ", box.size)
	var focus := box.get_center()
	var f := OS.get_environment("FOCUS").split(",")
	if f.size() == 3:
		focus = Vector3(float(f[0]), float(f[1]), float(f[2]))
	var yaw := deg_to_rad(float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 0.0)
	var pitch := deg_to_rad(float(OS.get_environment("PITCH")) if OS.get_environment("PITCH") != "" else 8.0)
	var zoom := float(OS.get_environment("ZOOM")) if OS.get_environment("ZOOM") != "" else 1.0
	var cam := Camera3D.new()
	cam.fov = 24.0
	cam.near = 0.01
	stage.add_child(cam)
	var dist := box.size.length() * 1.35 / zoom
	var dir := Vector3(cos(yaw) * cos(pitch), sin(pitch), -sin(yaw) * cos(pitch))
	cam.look_at_from_position(focus + dir * dist, focus, Vector3.UP)
	cam.current = true
	for i in 6:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "weapon_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
		found.append(n)
	for c in n.get_children():
		found.append_array(_meshes(c))
	return found
