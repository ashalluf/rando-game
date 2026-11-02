extends SceneTree
## Photo mode stills from one load (scripts/ui/photo_mode.gd): the panel over the view, the view
## with a grade (and the depth of field on Forward+), a letterboxed shot, and TAKE PHOTO's toast
## plus the file it saved.
##
##   OUT=/tmp/photo LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/photo_shot.gd --resolution 1280x720 -- --spawn=2400,700,30,-6 --hour=17.4
##
## Env: OUT (prefix; writes <OUT>_panel.png, _grade.png, _letterbox.png, _saved.png and the file
## TAKE PHOTO wrote into <OUT>_files/), FRAMES (streaming frames before photo mode opens, 40),
## EYE=x,y,z,yaw,pitch (true world; the free camera's start, else where the player camera was),
## FOV, GRADE (index into PhotoMode.GRADES, 1), FOCUS (metres, 0 = focus on centre), FSTOP (2),
## LETTER_GRADE (5, Noir), FRAME (1, 2.39 : 1), ROOM=1 (the test room instead of the city: small
## enough for lavapipe, where the depth of field shows - Compatibility has none).

func _initialize() -> void:
	Engine.set_meta("postfx_motion_blur", 0.0)
	var room := OS.get_environment("ROOM") == "1"
	var scene: Node
	if room:
		scene = (load("res://scenes/levels/test_box.tscn") as PackedScene).instantiate()
		root.add_child(scene)
	else:
		change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := int(_env("FRAMES", "40"))
	for i in frames:
		await process_frame
	if scene == null:
		scene = root.get_child(root.get_child_count() - 1)
	var photo: Node = scene.get_node_or_null("PhotoMode")
	if photo == null:
		photo = (load("res://scripts/ui/photo_mode.gd") as GDScript).new()
		scene.add_child(photo)
		await process_frame
	var out := _env("OUT", "/tmp/photo")
	photo.call("open")
	var cam: Camera3D = photo.get("camera")
	var eye := _env("EYE", "")
	if eye != "" and cam:
		var p := eye.split(",")
		var ws: Node = root.get_node("/root/WorldState")
		var at: Vector3 = ws.call("to_local", Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float()))
		photo.set("_anchor", at)
		cam.global_position = at
		photo.set("_yaw", deg_to_rad(p[3].to_float()))
		photo.set("_pitch", deg_to_rad(p[4].to_float()))
		photo.call("_apply_rotation")
	if _env("FOV", "") != "":
		photo.call("set_fov", float(_env("FOV", "60")))
		(photo.get("_sliders")["fov"] as HSlider).set_value_no_signal(float(_env("FOV", "60")))
	await _settle(8)
	_save(out + "_panel.png")

	# The grade (and the depth of field), panel hidden.
	(photo.get("_ui") as Control).visible = false
	photo.call("set_grade", int(_env("GRADE", "1")))
	var focus := float(_env("FOCUS", "0"))
	if focus > 0.0:
		photo.call("set_focus", focus)
		photo.call("set_dof", true)
	else:
		photo.call("autofocus")
	photo.call("set_fstop", float(_env("FSTOP", "2")))
	print("PHOTO focus %.1f m  f/%.1f  dof %s" % [float(photo.get("_focus")), float(photo.get("_fstop")),
		str(photo.call("dof_supported"))])
	await _settle(6)
	_save(out + "_grade.png")

	photo.call("set_grade", int(_env("LETTER_GRADE", "5")))
	photo.call("set_frame", int(_env("FRAME", "1")))
	await _settle(6)
	_save(out + "_letterbox.png")

	# TAKE PHOTO, then the toast over the view.
	(photo.get("_ui") as Control).visible = true
	photo.set("save_dir_override", ProjectSettings.globalize_path(out + "_files") if out.begins_with("res://") else out + "_files")
	photo.call("take_photo")
	await _settle(6)
	print("PHOTO saved %s" % String(photo.get("last_saved")))
	_save(out + "_saved.png")
	photo.call("close")
	await _settle(2)
	print("PHOTO closed: paused %s  time scale %.2f" % [str(paused), Engine.time_scale])
	quit()


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _save(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
