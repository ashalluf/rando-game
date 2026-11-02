extends SceneTree
## Compiles the shaders the specular-aliasing pass touched on a REAL renderer (the dummy one of
## --headless parses Godot's shader language only; a GLSL error in a renderer-only branch such as
## `#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS` only shows here): a box per shader in front of a
## camera, a few frames, then quit. Look for "SHADER ERROR" / "ERROR" in the output.
##
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --rendering-driver vulkan \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/specular_aliasing/fwd_compile.gd
##   (and --rendering-driver opengl3 for the Compatibility side)

const SHADERS := ["res://shaders/car_paint.gdshader", "res://shaders/car_paint_damage.gdshader",
	"res://shaders/car_park_car.gdshader", "res://shaders/road.gdshader", "res://shaders/road_paint.gdshader",
	"res://shaders/building.gdshader", "res://shaders/facade_detail.gdshader"]


func _initialize() -> void:
	var root3 := Node3D.new()
	get_root().add_child.call_deferred(root3)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2, 12)
	root3.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.4, 0)
	root3.add_child(sun)
	var x := -6.0
	for p: String in SHADERS:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.4, 1.4, 1.4)
		mi.mesh = bm
		var m := ShaderMaterial.new()
		m.shader = load(p)
		mi.material_override = m
		mi.position = Vector3(x, 1.0, 0.0)
		x += 2.0
		root3.add_child(mi)
	for i in 6:
		await process_frame
	print("FWD_COMPILE done (%s)" % RenderingServer.get_current_rendering_driver_name())
	quit()
