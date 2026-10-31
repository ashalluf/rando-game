extends SceneTree
## Close-ups of crowd rigs framed on their own bones (crowd-closeup-3): hands, feet, head, all in
## one load, composed into one grid image per rig row. Applies the rigs exactly as the game does
## (Pedestrian.prepare_rig and fix_arm_pose), like tools/glshot/crowd_lineup.gd.
##
##   OUT=closeup.jpg MODELS=crowd_a,crowd_g PARTS=rhand,lfoot,head \
##     LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1920x1080x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/crowd_closeup_3/closeup_shot.gd --resolution 960x720
##
## Env: MODELS (names under assets/models, default crowd_a), PARTS (comma list of lhand, rhand,
## lfoot, rfoot, feet, head, hair, torso, legs; default rhand,feet,head), CLIP (default the walk),
## PHASE (0..1), YAW (degrees round the part, 0 = in front of the person), DIST (metres, scales
## each part's own framing), TILE (pixels per tile, default 480), LIGHT=street (AgX, darker
## ground), GRID (columns; default one row per model), FOV.
const FRAMES := {
	# part: [bone(s), distance, yaw offset deg, height offset, fov]
	"rhand": [["RightHand"], 0.32, -35.0, -0.08, 40.0],
	"lhand": [["LeftHand"], 0.32, 35.0, -0.08, 40.0],
	"rfoot": [["RightFoot", "RightToeBase"], 0.42, -50.0, -0.02, 40.0],
	"lfoot": [["LeftFoot", "LeftToeBase"], 0.42, 50.0, -0.02, 40.0],
	"feet": [["LeftToeBase", "RightToeBase"], 0.85, 25.0, 0.12, 40.0],
	"head": [["Head"], 0.55, 20.0, 0.05, 40.0],
	"hair": [["Head"], 0.62, 150.0, 0.08, 40.0],
	"torso": [["Spine"], 1.1, 15.0, 0.0, 40.0],
	"legs": [["LeftLeg", "RightLeg"], 1.3, 20.0, 0.0, 40.0],
	"hem": [["Hips"], 0.6, 25.0, 0.0, 40.0],
	"cuff": [["RightForeArm", "RightHand"], 0.45, -60.0, 0.0, 40.0],
	"collar": [["neck"], 0.45, 25.0, -0.03, 40.0],
	"ankle": [["RightLeg", "RightFoot"], 0.5, -30.0, -0.18, 40.0],
}


func _initialize() -> void:
	var ped_script = load("res://scripts/npc/pedestrian.gd")
	var models := Array(OS.get_environment("MODELS").split(",", false))
	if models.is_empty():
		models = ["crowd_a"]
	var parts := Array(OS.get_environment("PARTS").split(",", false))
	if parts.is_empty():
		parts = ["rhand", "feet", "head"]
	var clip := OS.get_environment("CLIP") if OS.get_environment("CLIP") != "" else "Casual_Walk_inplace"
	var phase := float(OS.get_environment("PHASE")) if OS.get_environment("PHASE") != "" else 0.0
	var yaw_add := float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 0.0
	var dist_k := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 1.0
	var tile := int(OS.get_environment("TILE")) if OS.get_environment("TILE") != "" else 480
	var street := OS.get_environment("LIGHT") == "street"

	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.72) if street else Color(0.62, 0.66, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.70, 0.82) if street else Color(0.75, 0.78, 0.84)
	e.ambient_light_energy = 0.45 if street else 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_AGX if street else Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 30.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.2, 0.21) if street else Color(0.46, 0.46, 0.47)
	ground.material_override = gm
	root.add_child(ground)

	var cam := Camera3D.new()
	cam.near = 0.02
	root.add_child(cam)
	cam.current = true
	var rows: Array = []
	for m in models:
		var path := "res://assets/models/%s.glb" % String(m).strip_edges()
		var packed: PackedScene = load(path)
		if packed == null:
			print("closeup: cannot load ", path)
			continue
		var inst: Node3D = packed.instantiate()
		root.add_child(inst)
		await process_frame
		ped_script.prepare_rig(inst, 0)
		var aps := inst.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var ap: AnimationPlayer = aps[0]
			ped_script.fix_arm_pose(ap, path)
			if ap.has_animation(clip):
				ap.play(clip)
				ap.seek(ap.get_animation(clip).length * phase, true)
				ap.pause()
		var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
		for i in 4:
			await process_frame
		var row: Array = []
		for p in parts:
			var fr: Array = FRAMES[String(p)]
			var c := Vector3.ZERO
			for b in fr[0]:
				var bi := skel.find_bone(b)
				c += (skel.global_transform * skel.get_bone_global_pose(bi)).origin
			c /= float(fr[0].size())
			c.y += fr[3]
			var a := deg_to_rad(float(fr[2]) + yaw_add)
			var d := float(fr[1]) * dist_k
			cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else float(fr[4])
			cam.position = c + Vector3(sin(a) * d, 0.08 * d, cos(a) * d)
			cam.look_at(c, Vector3.UP)
			for i in 6:
				await process_frame
			var img := get_root().get_texture().get_image()
			var s := mini(img.get_width(), img.get_height())
			img = img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
			img.resize(tile, tile, Image.INTERPOLATE_LANCZOS)
			row.append(img)
		rows.append(row)
		inst.queue_free()
		await process_frame
	var cols := 0
	for r in rows:
		cols = maxi(cols, r.size())
	var out_img := Image.create(tile * cols, tile * rows.size(), false, Image.FORMAT_RGB8)
	for ri in rows.size():
		for ci in rows[ri].size():
			var im: Image = rows[ri][ci]
			im.convert(Image.FORMAT_RGB8)
			out_img.blit_rect(im, Rect2i(0, 0, tile, tile), Vector2i(ci * tile, ri * tile))
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "closeup.jpg"
	if out.ends_with(".png"):
		out_img.save_png(out)
	else:
		out_img.save_jpg(out, 0.88)
	print("saved ", out)
	quit()
