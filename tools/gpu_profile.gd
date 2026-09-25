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
func _initialize() -> void:
	# MERGE_STATIC=0: the chunks' and far landmarks' boxes one node each (see still_shot.gd).
	if OS.get_environment("MERGE_STATIC") == "0":
		(load("res://scripts/world/city_chunk.gd") as GDScript).set("merge_boxes", false)
		(load("res://scripts/util/multimesh_batch.gd") as GDScript).set("merge_enabled", false)
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
	quit()


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
