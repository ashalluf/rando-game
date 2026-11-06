extends SceneTree
## One city load, one frame per step with a group of nodes hidden (and shown again after), for
## telling which node draws a stray band or sheet (web-review-5: the Santa Ana bookmark).
##   STEPS='Weather;Player;Ground,Ground_tile*' OUT=/tmp/bisect FRAMES=60 xvfb-run -a godot \
##     --rendering-driver opengl3 --path . --script tools/web_probe/render_bisect.gd --resolution 960x540 \
##     -- --spawn=7,420,3,12 --hour=18.5 --weather=santa_ana --nohud
## Saves <OUT>_0.png (nothing hidden) and <OUT>_<i>.png per step; patterns are find_children
## wildcards under the City node, matching Node3Ds and CanvasLayers. Prints each step's mean of the
## frame's bottom quarter (BISECT lines).

func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 40
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/bisect"
	var steps := OS.get_environment("STEPS").split(";", false)
	for i in frames:
		await process_frame
	var city := get_root().get_node("City")
	_save(out + "_0.png", "none")
	for k in steps.size():
		var hidden: Array = []
		for pattern in steps[k].split(",", false):
			for n in city.find_children(pattern, "", true, false):
				if (n is Node3D or n is CanvasLayer) and n.visible:
					n.visible = false
					hidden.append(n)
		for i in 3:
			await process_frame
		_save("%s_%d.png" % [out, k + 1], "%s (%d nodes)" % [steps[k], hidden.size()])
		for n in hidden:
			if is_instance_valid(n):
				n.visible = true
	quit()


func _save(path: String, label: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png(path)
	var h := img.get_height()
	var w := img.get_width()
	var s := Vector3.ZERO
	var k := 0
	for y in range(h * 3 / 4, h, 4):
		for x in range(0, w, 8):
			var c := img.get_pixel(x, y)
			s += Vector3(c.r, c.g, c.b)
			k += 1
	s = s / maxf(1.0, k) * 255.0
	print("BISECT %s -> %s bottom %d %d %d" % [label, path, s.x, s.y, s.z])
