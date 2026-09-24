extends SceneTree
## A 360-degree panorama from one vantage point, for judging the distance: does the world reach
## the horizon in every direction, and where does each tier of detail hand over to the next?
##
##   OUT=pano.png VIEWS=4 PITCH=-8 FOV=90 LIBGL_ALWAYS_SOFTWARE=1 \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/glshot/lod_pano.gd \
##     --resolution 960x540 -- --spawn=700,250,0,-8,260 --hour=13 --nohud
##
## The player is held at the --spawn point (x, z, yaw, pitch, height) while the city streams in,
## then a camera of its own at the same spot turns through VIEWS headings (starting at YAW0,
## default the spawn yaw) at PITCH degrees and FOV degrees across, and the frames are laid side by
## side into one image. The camera copies the player camera's near and far planes and its
## attributes, so what it sees is what the game draws; FAR=<metres> overrides the far plane.
##
## TIERS=1 paints each tier a flat colour instead of shading it, which is the fastest way to see
## a gap between two of them: FULL chunks keep their own look, LOD chunks are red, the far city
## (Skyline tiles, less the blocks it has handed to a chunk) blue, far landmarks magenta, and the
## horizon plane is left as it is. Anything horizon-plane coloured where a city should be is a
## hole; blue and red on the same block is a block drawn twice. The hill planting keeps its look.
## FRAMES (default 30) is how many frames to let the streaming run first; MOVE=vx,vz (metres a
## second) keeps the player moving at that velocity during them, so the panorama shows the
## streaming mid-flight rather than at rest.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := int(_env("FRAMES", "30"))
	var views := int(_env("VIEWS", "4"))
	var pitch := float(_env("PITCH", "-8"))
	var fov := float(_env("FOV", "90"))
	var hold := Vector3.INF
	var yaw0 := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var parts := arg.trim_prefix("--spawn=").split(",")
			if parts.size() >= 5:
				hold = Vector3(parts[0].to_float(), parts[4].to_float(), parts[1].to_float())
			if parts.size() >= 3:
				yaw0 = parts[2].to_float()
	if _env("YAW0", "") != "":
		yaw0 = float(_env("YAW0", "0"))
	var move := Vector2.ZERO
	if _env("MOVE", "") != "":
		var mv := _env("MOVE", "0,0").split(",")
		move = Vector2(mv[0].to_float(), mv[1].to_float())
	var player: Node3D = null
	for i in frames:
		await process_frame
		player = get_first_node_in_group("player")
		_hold(player, hold, move, i)
	var city := current_scene as Node3D
	var src := get_root().get_camera_3d()
	var cam := Camera3D.new()
	cam.name = "PanoCam"
	city.add_child(cam)
	if src:
		cam.near = src.near
		cam.far = src.far
		cam.attributes = src.attributes
	if _env("FAR", "") != "":
		cam.far = float(_env("FAR", "2000"))
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = fov
	cam.current = true
	if player:
		var vis := player.get_node_or_null("Visual") as Node3D
		if vis:
			vis.visible = false
	if _env("TIERS", "") == "1":
		_paint_tiers(city)
	var shots: Array[Image] = []
	for v in views:
		var yaw := yaw0 + 360.0 * float(v) / float(views)
		for f in 3:
			await process_frame
			_hold(player, hold, move, frames + v * 3 + f)
			cam.global_position = player.global_position + Vector3(0.0, 1.6, 0.0) if player else Vector3.ZERO
			cam.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
		shots.append(get_root().get_texture().get_image())
		# What that view cost to draw (real under opengl3; all zero under --headless).
		print("GEO view=%d yaw=%.0f tris=%d draws=%d objects=%d" % [v, yaw,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var pano := Image.create(w * views, h, false, shots[0].get_format())
	for v in views:
		pano.blit_rect(shots[v], Rect2i(0, 0, w, h), Vector2i(w * v, 0))
	var out := _env("OUT", "pano.png")
	pano.save_png(out)
	var counts: Vector2i = city.call("chunk_counts") if city.has_method("chunk_counts") else Vector2i.ZERO
	var sky: Node = city.get_node_or_null("Skyline")
	print("PANO far=%d full=%d lod=%d skyline_tiles=%d -> %s" % [int(cam.far), counts.x, counts.y,
		(sky.call("tile_count") if sky else 0), out])
	quit()


func _hold(player: Node3D, hold: Vector3, move: Vector2, frame: int) -> void:
	if player == null or hold == Vector3.INF:
		return
	var off: Vector3 = get_root().get_node("/root/WorldState").get("world_offset")
	# Moving: the spawn point advances by `move` per (simulated) second - a sixtieth a frame,
	# which is the rate the physics would carry the player at if the frame were real time.
	var at := hold + Vector3(move.x, 0.0, move.y) * (float(frame) / 60.0)
	player.global_position = at - Vector3(off.x, 0.0, off.z)
	player.set("velocity", Vector3(move.x, 0.0, move.y))


## Flat colours per tier (see the header). Materials are replaced on every geometry node, so this
## is for coverage only: it says which tier drew each pixel, not what it looks like.
func _paint_tiers(city: Node) -> void:
	var red := _flat(Color(0.9, 0.15, 0.1))
	# The far city hides a block by its instances' colour alpha (Skyline), so its flat colour has
	# to honour that or every block a chunk stands on would be painted blue over the chunk.
	var blue := _flat_masked(Color(0.15, 0.3, 0.95))
	var magenta := _flat(Color(0.9, 0.2, 0.85))
	for child in city.get_children():
		var n := String(child.name)
		var mat: Material = null
		if n.begins_with("Chunk_"):
			mat = red if int(child.get("level")) == 1 else null
		elif n == "Skyline":
			mat = blue
		elif n.begins_with("FarLandmark_"):
			mat = magenta
		if mat == null:
			continue
		for g in child.find_children("*", "GeometryInstance3D", true, false):
			if String(g.name).begins_with("Planting_"):
				continue
			(g as GeometryInstance3D).material_override = mat


func _flat_masked(c: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded;
uniform vec3 col;
varying float keep;
void vertex() { keep = COLOR.a; if (COLOR.a < 0.004) { VERTEX = vec3(0.0); } }
void fragment() { if (keep < 0.5) { discard; } ALBEDO = col; }
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", Vector3(c.r, c.g, c.b))
	return m


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
