extends SceneTree
## The dogs alone on a pavement, lit with the city's daylight numbers: a lineup of breeds in a
## pose, for judging DogMesh / DogRig / dog.gdshader / dog_fur.gdshader in seconds, without the
## city.
##
##   OUT=dogs.png LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/dog_shot.gd --resolution 1280x720
##
## Env: OUT (png; with SEQ a prefix), BREEDS (comma list of breed or breed:look; default all six),
## VIEW side | front | three | rear | top (default three: a three-quarter view from the front
## left), POSE stand | walk | trot | gallop | sit | sniff | look | bark | fear (default stand),
## LOD 0 near (default) / 1 mid / 2 far, SEQ=n (n frames of the pose, STEP seconds apart: a gait
## sequence; the dogs run on a treadmill), STEP (0.06), CAM / LOOK (x,y,z) and FOV to frame it
## yourself, SPACING (metres between dogs, default 1.15), TRIS=1 prints the meshes' triangles.

const ALL := ["labrador", "shepherd", "husky", "pitbull", "terrier", "chihuahua"]


func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	await process_frame
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.45, 0.58)
	sky_mat.sky_horizon_color = Color(0.72, 0.70, 0.66)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	e.tonemap_white = 5.0
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.46, 0.45, 0.43)
	gm.roughness = 0.9
	ground.material_override = gm
	stage.add_child(ground)
	var names := (OS.get_environment("BREEDS") if OS.get_environment("BREEDS") != "" else ",".join(ALL)).split(",")
	var lod := int(OS.get_environment("LOD")) if OS.get_environment("LOD") != "" else 0
	var pose := OS.get_environment("POSE") if OS.get_environment("POSE") != "" else "stand"
	var spacing := float(OS.get_environment("SPACING")) if OS.get_environment("SPACING") != "" else 1.15
	var rigs: Array[DogRig] = []
	var n := names.size()
	var tallest := 0.0
	for i in n:
		var parts := names[i].split(":")
		var breed := parts[0]
		var look := parts[1] if parts.size() > 1 else String(DogMesh.breed(breed).looks[0][0])
		var rig := DogRig.make(breed, look, 7 + i)
		rig.position = Vector3((float(i) - float(n - 1) * 0.5) * spacing, 0.0, 0.0)
		stage.add_child(rig)
		rig.force_level(lod)
		rigs.append(rig)
		tallest = maxf(tallest, float(DogMesh.breed(breed).h))
		if OS.get_environment("TRIS") == "1":
			for lv in 3:
				var t := DogMesh.triangle_count(breed, lv)
				print("TRIS %s lod %d: skin %d shells %d" % [breed, lv, t.x, t.y])
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 32.0
	cam.near = 0.02
	stage.add_child(cam)
	var width := float(n) * spacing
	var mid := Vector3(0.0, tallest * 0.5, 0.0)
	var view := OS.get_environment("VIEW") if OS.get_environment("VIEW") != "" else "three"
	var dist := maxf(width * 1.25, tallest * 3.4)
	var at := mid + Vector3(-dist * 0.55, dist * 0.22, -dist * 0.8)
	match view:
		"side":
			# Every dog turned to face along the row, the camera square to it: profiles nose to tail.
			for rig in rigs:
				rig.rotation.y = PI * 0.5
			at = mid + Vector3(0.0, dist * 0.04, -dist)
		"front":
			at = mid + Vector3(0.0, dist * 0.1, -dist)
		"rear":
			at = mid + Vector3(0.0, dist * 0.15, dist)
		"top":
			at = mid + Vector3(0.0, dist, -0.01)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), at), _vec(OS.get_environment("LOOK"), mid))
	for rig in rigs:
		_apply(rig, pose, cam)
	var seq := int(OS.get_environment("SEQ")) if OS.get_environment("SEQ") != "" else 0
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 0.06
	# Settle into the pose (sits and sniffs ease in).
	for k in 90:
		for rig in rigs:
			rig.advance(1.0 / 30.0)
	for i in 6:
		await process_frame
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "dogs.png"
	if seq <= 0:
		get_root().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
		return
	for f in seq:
		for rig in rigs:
			rig.advance(step)
		for i in 3:
			await process_frame
		var path := out.trim_suffix(".png") + "_%02d.png" % f
		get_root().get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()


func _apply(rig: DogRig, pose: String, cam: Camera3D) -> void:
	var sh := sqrt(float(DogMesh.breed(rig.breed).h))
	match pose:
		"walk":
			rig.speed = 1.2 * sh / 0.75
		"trot":
			rig.speed = 2.6 * sh / 0.75
		"gallop":
			rig.speed = 7.0 * sh / 0.75
		"sit":
			rig.sit = 1.0
			rig.look_at = rig.to_local(cam.global_position)
		"sniff":
			rig.sniff = 1.0
		"look":
			rig.look_at = rig.to_local(cam.global_position)
		"bark":
			rig.bark = 1.0
			rig.look_at = rig.to_local(cam.global_position)
		"fear":
			rig.fear = 1.0


func _vec(s: String, fallback: Vector3) -> Vector3:
	if s == "":
		return fallback
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
