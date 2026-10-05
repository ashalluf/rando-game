extends SceneTree
## The landmarks' LOD line, side by side (FarBuilding's far_building_shot.gd for Landmarks): each
## landmark is built twice - detailed, as the chunk round it builds it (Landmarks.build(..., true)
## with a StaticBody3D), and far, as CityStreamer._build_far_landmarks() does (no statics, then
## MultiMeshBatch.merge_meshes()) - and rendered from the SAME camera with nothing else in the
## scene: <OUT>_<id>_near.png, <OUT>_<id>_far.png and <OUT>_<id>_empty.png (the background alone,
## so tools/glshot/far_landmark_pair.py can find each copy's silhouette by difference, whatever
## its shaders do in the vertex stage).
##
##   OUT=/tmp/fl IDS=dt_sail,arena LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/far_landmark_shot.gd --resolution 960x540
##   python3 tools/glshot/far_landmark_pair.py /tmp/fl_*_near.png
##
## Env: OUT (path stem), IDS (comma list of Landmarks.all() ids; default every landmark with a
## far version), DIST (metres from the landmark's centre, default 260: about where the FULL ring
## hands it over), YAW (degrees round from the south toward the east the camera stands, default
## 35), NIGHT=1 (21:00: lamp_factor / night_factor 1, the sun down to a moon), FRAMES (frames
## before each shot, default 6), SEED (default the city's). The light is a fixed sun and sky, not
## DayNight: judge the two frames against each other.


func _initialize() -> void:
	# The landmark builders compile against the autoloads, which exist only after the first frames.
	for i in 3:
		await process_frame
	var runner: RefCounted = load("res://tools/glshot/far_landmark_shot_run.gd").new()
	runner.call("run", self)
