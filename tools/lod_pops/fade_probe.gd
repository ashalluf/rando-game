extends SceneTree
## Does VISIBILITY_RANGE_FADE_SELF dither on this renderer, and is a near/far pair complementary?
## A red box (end 10, margin 4) and a green box (begin 10, margin 4) at the same spot, the camera
## D metres off (default 12: inside both margins). Prints the share of red, green and background.
##   xvfb-run -a -s "-screen 0 320x240x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --path . --script tools/lod_pops/fade_probe.gd --resolution 320x240
func _initialize() -> void:
	var d := float(OS.get_environment("D")) if OS.get_environment("D") != "" else 12.0
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 0, d)
	cam.fov = 8.0
	cam.make_current()
	var which := OS.get_environment("ONLY")
	for c in [Color(1, 0, 0), Color(0, 1, 0)]:
		if which == "r" and c.g > 0.5: continue
		if which == "g" and c.r > 0.5: continue
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 1, 1)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		if OS.get_environment("LIT") == "": m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		mi.material_override = m
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if c.r > 0.5:
			mi.visibility_range_end = 10.0
			mi.visibility_range_end_margin = 4.0
		else:
			mi.visibility_range_begin = 10.0
			mi.visibility_range_begin_margin = 4.0
		root.add_child(mi)
	await process_frame
	if OS.get_environment("TRANS") != "":
		for n in root.get_children():
			if n is GeometryInstance3D: n.transparency = float(OS.get_environment("TRANS"))
	for i in 30:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("/tmp/claude-0/fade_probe.png")
	for n in root.get_children():
		if n is GeometryInstance3D: print("NODE ", n.transparency, " ", n.visibility_range_end, " ", n.visibility_range_fade_mode)
	var r := 0
	var g := 0
	var y := 0
	var bg := 0
	for py in range(100, 140):
		for px in range(140, 180):
			var c := img.get_pixel(px, py)
			if c.r > 0.5 and c.g > 0.5: y += 1
			elif c.r > 0.5: r += 1
			elif c.g > 0.5: g += 1
			else: bg += 1
	print("FADEPROBE center=%s" % str(img.get_pixel(160, 120)))
	print("FADEPROBE d=%.1f red=%d green=%d both=%d bg=%d" % [d, r, g, y, bg])
	quit()
