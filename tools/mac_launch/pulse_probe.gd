extends Node3D
## The load's frame stalls on a RenderingDevice renderer, old way against LoadPulse's (mac-launch,
## docs/HANDOFF.md "The Mac launch"). A first launch: delete the shader and pipeline caches first.
##
##   rm -rf ~/.local/share/godot/app_userdata/Rando\ Game/{shader_cache,vulkan}
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json MODE=old|pulse SHADERS=40 \
##     xvfb-run -a -s "-screen 0 960x540x24" godot --path . --rendering-driver vulkan \
##     --resolution 480x270 res://tools/mac_launch/pulse_probe.tscn
##
## It adds SHADERS of the game's .gdshader files on three meshes each (a box, a sphere, a
## MultiMesh) in front of the camera - what a city build hands the renderer - and prints every
## frame's time until the frames are quick again. MODE=old draws them at once (each frame waits for
## its pipelines); MODE=pulse adds them while LoadPulse holds the 3D off, waits on the drain, then
## draws. Prints PROBE lines: the worst frame while the work was going on (the window's longest
## freeze), the time until everything is drawn, and the pipelines counted.

var _mode := OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "pulse"
var _count := int(OS.get_environment("SHADERS")) if OS.get_environment("SHADERS") != "" else 40


func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 6)
	add_child(cam)
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.sdfgi_enabled = true
	we.environment = env
	add_child(we)
	get_viewport().use_taa = true
	_run.call_deferred()


func _run() -> void:
	for i in 3:
		await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var worst := 0
	var frames := 0
	if _mode == "pulse":
		LoadPulse.begin(get_viewport())
	var p0 := _pipelines()
	var holder := Node3D.new()
	add_child(holder)
	var files := _files()
	var meshes: Array[Mesh] = [BoxMesh.new(), SphereMesh.new()]
	var n := 0
	for path in files:
		if n >= _count:
			break
		var sh := load(path) as Shader
		if sh == null or sh.get_mode() != Shader.MODE_SPATIAL:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = sh
		for j in meshes.size():
			var mi := MeshInstance3D.new()
			mi.mesh = meshes[j]
			mi.material_override = mat
			mi.position = Vector3((n % 8) - 3.5, 0.5 + j, -(n / 8))
			holder.add_child(mi)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = meshes[0]
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(), Vector3((n % 8) - 3.5, 2.5, -(n / 8))))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		holder.add_child(mmi)
		n += 1
		# A city build presents a frame between pieces of work (LoadPulse.tick in the loops).
		if _mode == "pulse":
			var f0 := Time.get_ticks_msec()
			LoadPulse.tick(true)
			worst = maxi(worst, Time.get_ticks_msec() - f0)
			frames += 1
	if _mode == "pulse":
		var d0 := Time.get_ticks_msec()
		var last := Time.get_ticks_msec()
		# drain() is a coroutine: run it while timing the frames it lets through.
		var state := {"done": false}
		_drain_then(state)
		while not state.done:
			await get_tree().process_frame
			var now := Time.get_ticks_msec()
			worst = maxi(worst, now - last)
			last = now
			frames += 1
		print("PROBE drain %d ms" % (Time.get_ticks_msec() - d0))
		LoadPulse.end()
	var quick := 0
	var last2 := Time.get_ticks_msec()
	var settle_worst := 0
	while quick < 5 and frames < 2000:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		var ms := now - last2
		last2 = now
		frames += 1
		settle_worst = maxi(settle_worst, ms)
		if _mode == "old":
			worst = maxi(worst, ms)
		quick = quick + 1 if ms < 400 else 0
	print("PROBE mode=%s shaders=%d worst_frame=%d ms settle_worst=%d ms total=%d ms frames=%d pipelines=%d" % [_mode, n,
			worst, settle_worst, Time.get_ticks_msec() - t0, frames, _pipelines() - p0])
	get_tree().quit()


func _drain_then(state: Dictionary) -> void:
	await LoadPulse.drain(get_tree())
	state.done = true


func _pipelines() -> int:
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE)) \
			+ int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)) \
			+ int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH))


func _files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at("res://shaders"):
		var name := f.trim_suffix(".remap")
		if name.ends_with(".gdshader"):
			out.append("res://shaders/" + name)
	return out
