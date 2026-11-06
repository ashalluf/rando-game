extends SceneTree
## What the wet-street shading costs: one street slab of road.gdshader filling the screen, drawn
## FRAMES times in each weather (dry, raining, drying), reporting the GPU time per frame. No
## city, so the only thing that changes between the rows is the road's fragment work.
##
##   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/road_cost.gd --resolution 960x540
##
## Under llvmpipe the numbers are software rasteriser milliseconds: read the RATIOS between rows,
## not the absolute times. Never run it with --headless (the dummy renderer draws nothing).

# name, road_wetness, road_drying, rain_intensity, lamp_factor (night)
const CASES := [
	["dry", 0.0, 0.0, 0.0, 0.0],
	["raining", 1.0, 0.0, 1.0, 0.0],
	["drying 0.45", 0.45, 1.0, 0.0, 0.0],
	["drying 0.15", 0.15, 1.0, 0.0, 0.0],
	["night dry", 0.0, 0.0, 0.0, 1.0],
	["night rain", 1.0, 0.0, 1.0, 1.0],
	["night drying", 0.45, 1.0, 0.0, 1.0],
]

var _cam: Camera3D
var _vp: RID


func _initialize() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.35, 0.4)
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	root3d.add_child(sun)
	# A street slab the way CityChunk lays one: UV 0..1 across its rect, lamps along Z.
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(14.0, 600.0)
	var mat: ShaderMaterial = (load("res://scripts/world/prop_factory.gd") as GDScript).call("road", "asphalt", 7.0, Color(0.72, 0.72, 0.74), 1234)
	mat.set_shader_parameter("lamp_axis", 1)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0.0, 0.0, -280.0)
	root3d.add_child(mi)
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 1.6, 0.0)
	_cam.rotation_degrees = Vector3(-38.0, 0.0, 0.0)
	_cam.fov = 60.0
	root3d.add_child(_cam)
	RenderingServer.global_shader_parameter_set("ground_detail", 1.0)
	_run.call_deferred()


func _run() -> void:
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES").is_valid_int() else 40
	_vp = get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	for c in CASES:
		RenderingServer.global_shader_parameter_set("road_wetness", c[1])
		# Guarded, so the same script times an older road shader that has neither global.
		if ProjectSettings.has_setting("shader_globals/road_drying"):
			RenderingServer.global_shader_parameter_set("road_drying", c[2])
		if ProjectSettings.has_setting("shader_globals/rain_intensity"):
			RenderingServer.global_shader_parameter_set("rain_intensity", c[3])
		RenderingServer.global_shader_parameter_set("lamp_factor", c[4])
		for i in 8:
			await process_frame
		var gpu := 0.0
		var wall := Time.get_ticks_usec()
		for i in frames:
			await process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		var wall_ms := float(Time.get_ticks_usec() - wall) / 1000.0 / frames
		print("ROADCOST %-13s gpu %.2f ms  wall %.2f ms" % [c[0], gpu / frames, wall_ms])
	quit()
