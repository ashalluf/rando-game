extends SceneTree
## Where the GPU time goes, pass by pass, under the real Forward+ renderer (lavapipe, no GPU):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan \
##     --display-driver x11 --audio-driver Dummy --gpu-profile --path . \
##     --script tools/gpu_profile.gd --resolution 1280x720 \
##     -- --spawn=734.9,300,0,-3 --quality=0 --nohud | python3 tools/gpu_profile.py
##
## `--gpu-profile` makes the engine print its per-pass GPU times (the editor's Visual Profiler)
## about once a second; this script only loads the city, lets it settle for FRAMES frames
## (default 40), and marks the SAMPLES frames (default 6) that gpu_profile.py should average.
## A software GPU is not the owner's Mac: read the SHARES, not the milliseconds - which passes
## dominate, and what a change does to them.
## LIGHT_WORLD=1 is still_shot.gd's smaller world (far city LIGHT_FAR m, default 2500; LOD ring
## LIGHT_LOD blocks, default 4; 160 people, 40 cars): since 2026-10-04 the whole city under
## lavapipe grows past 12.7 GB and is OOM-killed on the 14.3 GB box, so a profile needs it.
## LAMPS_AT_ZERO=1 shows the street lamps' lights at zero energy by day, as they were before
## DayNight hid them (the A/B of that change).
func _initialize() -> void:
	# MERGE_STATIC=0: the chunks' and far landmarks' boxes one node each (see still_shot.gd).
	if OS.get_environment("MERGE_STATIC") == "0":
		(load("res://scripts/world/city_chunk.gd") as GDScript).set("merge_boxes", false)
		(load("res://scripts/util/multimesh_batch.gd") as GDScript).set("merge_enabled", false)
	if OS.get_environment("LAMPS_AT_ZERO") == "1":
		(load("res://scripts/world/day_night.gd") as GDScript).set("hide_dark_lamps", false)
	if OS.get_environment("LIGHT_WORLD") == "1":
		var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
		city.set("far_city_radius", _env_float("LIGHT_FAR", 2500.0))
		city.set("far_city_immediate_radius", _env_float("LIGHT_FAR", 2500.0))
		city.set("lod_radius_blocks", _env_int("LIGHT_LOD", 4))
		city.set("keep_radius_blocks", _env_int("LIGHT_LOD", 4))
		city.set("max_pedestrians", 160)
		city.set("traffic_cars", 40)
		root.add_child.call_deferred(city)
		set_deferred("current_scene", city)
	else:
		change_scene_to_file("res://scenes/levels/city.tscn")
	for i in _env_int("FRAMES", 40):
		await process_frame
	print("GPU_PROFILE_BEGIN")
	for i in _env_int("SAMPLES", 6):
		await process_frame
	print("GPU_PROFILE_END")
	var vp := get_root()
	var vis := Viewport.RENDER_INFO_TYPE_VISIBLE
	var sh := Viewport.RENDER_INFO_TYPE_SHADOW
	print("GEO tris=%d draws=%d objects=%d | camera tris=%d draws=%d | shadow tris=%d draws=%d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		vp.get_render_info(vis, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		vp.get_render_info(vis, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(sh, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		vp.get_render_info(sh, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	var mb := 1.0 / (1024.0 * 1024.0)
	print("MEM video=%.0f MB (textures %.0f, buffers %.0f) static=%.0f MB objects=%d nodes=%d" % [
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) * mb,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) * mb,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) * mb,
		Performance.get_monitor(Performance.MEMORY_STATIC) * mb,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	# Positional lights the renderer keeps (visible, and inside their distance fade): lit ones and
	# ones at zero energy, which cost the clusters just the same.
	var cam := vp.get_camera_3d()
	var lit := 0
	var dark := 0
	var shadowed := 0
	for n in vp.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l is DirectionalLight3D or not l.is_visible_in_tree():
			continue
		if cam and l.distance_fade_enabled and cam.global_position.distance_to(l.global_position) > l.distance_fade_begin + l.distance_fade_length:
			continue
		if l.light_energy > 0.0:
			lit += 1
		else:
			dark += 1
		if l.shadow_enabled:
			shadowed += 1
	print("LIGHTS positional in fade range: lit %d, at zero energy %d, shadowed %d" % [lit, dark, shadowed])
	quit()


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback


static func _env_float(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback
