class_name VerifyPack
extends CanvasLayer
## The verify pack (docs/VERIFY.md): the ten reference cameras (tools/refcams/cameras.json) shot on
## the machine the game runs on - the owner's Mac, the only true Forward+ check. The pause menu's
## VERIFY PACK button (or `-- --verify` on the command line) hides the HUD, parks the player, and
## for each camera puts a free camera on its eye, sets its hour and weather (the streets soaked or
## dried to match), streams the blocks round it at once, holds it `hold_seconds` (the auto
## exposure settles, the frame rate is measured), and saves a PNG at the window's resolution to
## Pictures/Rando Game/verify_<build>/ (user://verify when there is no Pictures folder). Then a
## contact sheet, a report (the machine, the renderer, every shot's frame rate, GPU time, frame
## cost and luminance) and a `send` folder of small JPGs, and a card saying where it all is. The
## player, the clock, the weather, the graphics level and the HUD are put back exactly as they
## were. No render feature of its own: what it saves is what the game draws.
##
## Env: VERIFY_PACK=0 (the A/B: no button, `--verify` ignored), VERIFY_HOLD=<s> the hold,
## VERIFY_ONLY=<names> a subset, VERIFY_DIR=<dir> where the folder goes, VERIFY_QUIT=1 quit when
## done (the harness). Off on the web (a browser cannot write a folder).

## The ten cameras, as tools/refcams/cameras.json (the export ships no .json, so the table is
## here; tests/mac_verify_pack_checks.gd holds the two equal). eye = TRUE world x, y, z, yaw,
## pitch; agl: y is over the plan's ground there.
const CAMERAS := [
	{"name": "street_noon", "label": "Street, noon (Flower at Olympic)", "eye": [2359.4, 2.0, 880.0, 0.0, 2.0], "agl": true, "hour": 12.0, "weather": "clear", "fov": 55},
	{"name": "street_night", "label": "Street, 21:30 rain", "eye": [2359.4, 2.0, 880.0, 0.0, 2.0], "agl": true, "hour": 21.5, "weather": "rain", "fov": 55},
	{"name": "sunset", "label": "Esplanade at sunset 17:51", "eye": [-441.66, 9.94, 3534.58, -178.0, -1.5], "agl": false, "hour": 17.85, "weather": "clear", "fov": 44},
	{"name": "golden_aerial", "label": "Golden hour aerial, downtown from the SW 17:12", "eye": [1450.0, 140.0, 2150.0, -38.0, 4.0], "agl": true, "hour": 17.2, "weather": "clear", "fov": 55},
	{"name": "downtown_aerial", "label": "Downtown aerial, civic centre noon", "eye": [2600.0, 60.0, -450.0, -50.0, -4.0], "agl": true, "hour": 12.5, "weather": "clear", "fov": 55},
	{"name": "beach", "label": "Beach at the waterline 14:00", "eye": [-732.0, 2.1, 800.0, 105.0, -4.0], "agl": false, "hour": 14.0, "weather": "clear", "fov": 55},
	{"name": "hills", "label": "Front range from 260 m, 15:00", "eye": [300.0, 260.0, -650.0, 0.0, -6.0], "agl": true, "hour": 15.0, "weather": "clear", "fov": 55},
	{"name": "freeway", "label": "The 110 deck by downtown 13:00", "eye": [1989.0, 12.0, 160.0, -6.0, -3.0], "agl": false, "hour": 13.0, "weather": "clear", "fov": 55},
	{"name": "macarthur", "label": "MacArthur Park from the south 11:00", "eye": [300.0, 120.0, 528.0, 0.0, -35.0], "agl": true, "hour": 11.0, "weather": "clear", "fov": 55},
	{"name": "pier_night", "label": "The pier from the beach 21:00", "eye": [-945.0, 1.8, -235.0, 61.7, 7.0], "agl": false, "hour": 21.0, "weather": "clear", "fov": 55},
]

## Seconds each camera is held before its picture (auto exposure settles; the fps is measured).
@export var hold_seconds: float = 3.0
## Frames after the blocks are streamed in before the hold starts (the late build steps land).
@export var settle_frames: int = 20
## The JPGs in the folder's `send` subfolder are this wide (small enough to attach).
@export var send_width: int = 1280
## One thumbnail of the contact sheet is this wide.
@export var sheet_thumb: int = 480

signal finished(folder: String, shots: int)

var running := false
## Where the last run wrote (absolute), "" before one.
var last_folder := ""
## The last run's shots: name, file, fps, gpu ms, tris, draws, luminance ...
var last_shots: Array = []

var _cancel := false
var _overlay: Control
var _progress: Label
var _card: Control
var _card_text: Label
var _cam: Camera3D
var _saved := {}
var _hidden_layers: Array[CanvasLayer] = []


static func enabled() -> bool:
	return OS.get_environment("VERIFY_PACK") != "0" and not OS.has_feature("web")


## `--verify` (after `--`, or among the engine's own arguments) starts a run once the city is in.
static func asked_on_command_line() -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--verify":
			return true
	return "--verify" in OS.get_cmdline_args()


func _ready() -> void:
	layer = 7 # over photo mode (6) and the pause menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if enabled() and asked_on_command_line() and get_tree().root.get_node_or_null("SmokeTest") == null:
		_autostart.call_deferred()


func _autostart() -> void:
	# The loading screen first (it builds the whole far city), then a few seconds of the game.
	var city := get_parent()
	while city and city.get_node_or_null("LoadingScreen") != null:
		await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	await run()
	if OS.get_environment("VERIFY_QUIT") == "1":
		get_tree().quit()


func _input(event: InputEvent) -> void:
	if _card and _card.visible:
		if event.is_action_pressed("toggle_mouse"):
			_close_card()
			get_viewport().set_input_as_handled()
		return
	if not running:
		return
	# Nothing reaches the game during a run (no shots, no photo mode, no pause menu); Esc stops it.
	if event.is_action_pressed("toggle_mouse"):
		_cancel = true
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()


# --- The run -----------------------------------------------------------------------------------

## Shoots every camera (or VERIFY_ONLY's), writes the folder, puts everything back and shows the
## card. Returns the folder ("" when nothing could be written).
func run() -> String:
	if running:
		return ""
	var city := get_parent()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if city == null or player == null:
		return ""
	running = true
	_cancel = false
	last_shots = []
	var folder := _make_folder()
	last_folder = folder
	var cams := cameras()
	_begin(city, player)
	var shots: Array = []
	for i in cams.size():
		if _cancel or not is_inside_tree():
			break
		var shot: Dictionary = await _shoot(city, player, cams[i], i, cams.size(), folder)
		if shot.is_empty():
			continue
		shots.append(shot)
		last_shots = shots
	_restore(city, player)
	if folder != "" and is_inside_tree():
		await _write_sheet(folder, shots)
		_write_report(folder, shots)
	running = false
	if is_inside_tree():
		_show_card(folder, shots.size(), cams.size())
	finished.emit(folder, shots.size())
	return folder


## The cameras this run shoots (VERIFY_ONLY narrows them).
static func cameras() -> Array:
	var only := OS.get_environment("VERIFY_ONLY")
	if only == "":
		return CAMERAS.duplicate(true)
	var want := only.split(",", false)
	return CAMERAS.filter(func(c: Dictionary) -> bool: return String(c.name) in want)


## Everything the run changes, kept to put back.
func _begin(city: Node, player: Node3D) -> void:
	_saved.clear()
	var day := city.get_node_or_null("DayNight")
	var weather := city.get_node_or_null("Weather")
	var quality := city.get_node_or_null("Quality")
	if player.get("vehicle") != null and player.has_method("exit_vehicle"):
		player.call("exit_vehicle")
	_saved.player_true = WorldState.to_world(player.global_position)
	_saved.player_mode = player.process_mode
	_saved.player_visible = player.visible
	_saved.camera = get_viewport().get_camera_3d()
	_saved.mouse = Input.mouse_mode
	_saved.time_scale = Engine.time_scale
	if day:
		_saved.hour = float(day.get("hour"))
		_saved.day_paused = bool(day.get("_paused"))
		day.call("set_paused", true)
	if weather:
		_saved.weather_state = int(weather.get("state"))
		_saved.weather_forced = bool(weather.call("is_forced"))
		_saved.wetness = float(weather.get("wetness"))
	if quality:
		# Auto would drop a level on the teleports' hitches and shoot half the set at another one.
		_saved.quality_forced = bool(quality.call("is_forced"))
		_saved.quality_level = int(quality.get("level"))
		if not _saved.quality_forced:
			quality.call("force_level", _saved.quality_level)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.set("velocity", Vector3.ZERO)
	player.visible = false
	_hide_hud()
	var src: Camera3D = _saved.camera
	_cam = Camera3D.new()
	_cam.name = "VerifyCamera"
	city.add_child(_cam)
	if src:
		_cam.far = src.far
		_cam.near = src.near
		if src.attributes:
			# The player camera's auto exposure, without its depth of field (CameraPost drives
			# that from the player's aim, which is not what a reference view is).
			var attr := src.attributes.duplicate() as CameraAttributes
			if attr is CameraAttributesPractical:
				attr.dof_blur_far_enabled = false
				attr.dof_blur_near_enabled = false
			_cam.attributes = attr
	_cam.make_current()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_overlay.visible = true


func _restore(city: Node, player: Node3D) -> void:
	var day := city.get_node_or_null("DayNight")
	var weather := city.get_node_or_null("Weather")
	var quality := city.get_node_or_null("Quality")
	_overlay.visible = false
	Engine.time_scale = float(_saved.get("time_scale", 1.0))
	if weather and _saved.has("weather_state"):
		weather.call("force_state", int(_saved.weather_state), true)
		if not bool(_saved.weather_forced):
			weather.call("force_state", -1)
		weather.set("wetness", float(_saved.wetness))
	if day and _saved.has("hour"):
		day.set("hour", float(_saved.hour))
		day.call("set_paused", bool(_saved.day_paused))
		day.call("_apply")
	if quality and _saved.has("quality_forced") and not bool(_saved.quality_forced):
		quality.call("force_level", -1)
	if is_instance_valid(player):
		player.global_position = WorldState.to_local(_saved.player_true)
		player.process_mode = _saved.player_mode
		player.visible = bool(_saved.player_visible)
		player.set("velocity", Vector3.ZERO)
	var src: Camera3D = _saved.get("camera")
	if is_instance_valid(src):
		src.make_current()
	if is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	for l in _hidden_layers:
		if is_instance_valid(l):
			l.visible = true
	_hidden_layers.clear()
	if city.has_method("update_streaming"):
		city.call("update_streaming", true)
	Input.mouse_mode = _saved.get("mouse", Input.MOUSE_MODE_CAPTURED)


## One camera: placed, its hour and weather, streamed, held, saved. {} if the run was stopped.
func _shoot(city: Node, player: Node3D, cam: Dictionary, i: int, n: int, folder: String) -> Dictionary:
	var day := city.get_node_or_null("DayNight")
	var weather := city.get_node_or_null("Weather")
	var eye: Array = cam.eye
	var at := Vector3(float(eye[0]), float(eye[1]), float(eye[2]))
	var plan: Variant = city.get("plan")
	if cam.get("agl", false) and plan != null:
		at.y += float(plan.height_at(Vector2(at.x, at.z)))
	var basis := Basis.from_euler(Vector3(deg_to_rad(float(eye[4])), deg_to_rad(float(eye[3])), 0.0))
	_progress.text = "VERIFY PACK   %d / %d   %s   Esc stops" % [i + 1, n, String(cam.label)]
	_set_weather(weather, String(cam.get("weather", "clear")))
	_set_hour(day, float(cam.hour))
	Engine.time_scale = 1.0
	_cam.fov = float(cam.get("fov", 55.0))
	_place(player, at, basis)
	if city.has_method("update_streaming"):
		city.call("update_streaming", true)
	for f in settle_frames:
		await get_tree().process_frame
		if _cancel or not is_inside_tree():
			return {}
		_place(player, at, basis)
		_set_hour(day, float(cam.hour))
	# The hold: the frame rate, the CPU and GPU time are measured over it.
	var hold := _hold()
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var gpu_sum := 0.0
	var cpu_sum := 0.0
	var worst := 0.0
	var last := t0
	var vrid := get_viewport().get_viewport_rid()
	while (Time.get_ticks_usec() - t0) < int(hold * 1_000_000.0):
		await get_tree().process_frame
		if _cancel or not is_inside_tree():
			return {}
		_place(player, at, basis)
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
		cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(vrid)
	var elapsed := maxf((Time.get_ticks_usec() - t0) / 1_000_000.0, 0.001)
	var geo := [Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)]
	# The picture, without the progress line.
	_overlay.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = null
	var tex := get_viewport().get_texture()
	if tex:
		img = tex.get_image()
	_overlay.visible = true
	var file := "%02d_%s.png" % [i + 1, cam.name]
	var shot := {"name": cam.name, "label": cam.label, "file": file, "hour": float(cam.hour),
		"weather": String(cam.get("weather", "clear")), "eye": [at.x, at.y, at.z, eye[3], eye[4]],
		"fps": frames / elapsed, "worst_ms": worst,
		"gpu_ms": gpu_sum / maxf(frames, 1), "cpu_ms": cpu_sum / maxf(frames, 1),
		"tris": int(geo[0]), "draws": int(geo[1]), "objects": int(geo[2]), "saved": false}
	if img != null and not img.is_empty():
		shot.size = [img.get_width(), img.get_height()]
		shot.lum = luminance(img)
		if folder != "":
			shot.saved = img.save_png(folder.path_join(file)) == OK
			var small := _scaled(img, send_width)
			small.save_jpg(folder.path_join("send").path_join(file.get_basename() + ".jpg"), 0.88)
			shot.thumb = _scaled(img, sheet_thumb)
	return shot


func _place(player: Node3D, at_true: Vector3, basis: Basis) -> void:
	var at := WorldState.to_local(at_true)
	_cam.global_transform = Transform3D(basis, at)
	# The player parked (disabled) on the camera: the streaming follows him.
	player.global_position = at
	player.set("velocity", Vector3.ZERO)


func _set_hour(day: Node, hour: float) -> void:
	if day == null:
		return
	day.set("hour", hour)
	day.call("_apply")


## The camera's weather held, with the streets as wet as that weather leaves them (refcams' rule:
## a clear shot after the rainy one would otherwise show the street drying).
func _set_weather(weather: Node, key: String) -> void:
	if weather == null:
		return
	var keys: Array = weather.get_script().get_script_constant_map().get("STATE_KEYS", [])
	var idx := keys.find(key)
	if idx < 0:
		return
	weather.call("force_state", idx, true)
	var rain := float(weather.call("_rain_level", idx))
	weather.set("wetness", clampf(rain * 1.2, 0.0, 1.0))


func _hold() -> float:
	var v := OS.get_environment("VERIFY_HOLD")
	return maxf(float(v), 0.0) if v.is_valid_float() else hold_seconds


## Every HUD layer hidden for the run (photo mode's rule: < 0 is part of the picture).
func _hide_hud() -> void:
	_hidden_layers.clear()
	var scene := get_parent()
	if scene == null:
		return
	for nd in scene.find_children("*", "CanvasLayer", true, false):
		var l := nd as CanvasLayer
		if l == self or l.layer < 0 or l.layer >= 128 or not l.visible:
			continue
		l.visible = false
		_hidden_layers.append(l)


# --- The folder --------------------------------------------------------------------------------

## Pictures/Rando Game/verify_<build>, with _2, _3 ... when that is taken; user://verify if the
## Pictures folder cannot be written. "" if nothing can.
func _make_folder() -> String:
	var bases: Array[String] = []
	var override := OS.get_environment("VERIFY_DIR")
	if override != "":
		bases.append(override)
	else:
		var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
		if pictures != "":
			bases.append(pictures.path_join("Rando Game"))
		bases.append("user://verify")
	for b in bases:
		var path := folder_in(b)
		if DirAccess.make_dir_recursive_absolute(path.path_join("send")) == OK:
			return ProjectSettings.globalize_path(path)
	return ""


## The first free verify_<build>[_n] under `base`.
static func folder_in(base: String) -> String:
	var name := "verify_%s" % BuildInfo.number()
	var path := base.path_join(name)
	var n := 2
	while DirAccess.dir_exists_absolute(path):
		path = base.path_join("%s_%d" % [name, n])
		n += 1
	return path


func _scaled(img: Image, width: int) -> Image:
	var out := img.duplicate() as Image
	if out.get_width() > width:
		var h := maxi(1, int(round(float(out.get_height()) * width / out.get_width())))
		out.resize(width, h, Image.INTERPOLATE_LANCZOS)
	out.convert(Image.FORMAT_RGB8)
	return out


## Luminance percentiles p1/p5/p50/p95/p99 on PIL's "L" (refcams.py's numbers, so the Mac's shots
## read against the fleet's opengl3 ones), from a 256-wide copy.
static func luminance(img: Image) -> Array:
	var s := img.duplicate() as Image
	s.convert(Image.FORMAT_RGB8)
	if s.get_width() > 256:
		s.resize(256, maxi(1, int(round(256.0 * s.get_height() / s.get_width()))), Image.INTERPOLATE_BILINEAR)
	var hist := PackedInt32Array()
	hist.resize(256)
	var data := s.get_data()
	var count := data.size() / 3
	for k in count:
		var l := (data[k * 3] * 299 + data[k * 3 + 1] * 587 + data[k * 3 + 2] * 114) / 1000
		hist[clampi(l, 0, 255)] += 1
	var out: Array = []
	for p: float in [1.0, 5.0, 50.0, 95.0, 99.0]:
		var want := p / 100.0 * count
		var acc := 0
		var v := 255
		for b in 256:
			acc += hist[b]
			if acc >= want:
				v = b
				break
		out.append(v)
	return out


## The 5 x 2 contact sheet, drawn in a SubViewport with each shot's numbers under it.
func _write_sheet(folder: String, shots: Array) -> void:
	var thumbs := shots.filter(func(s: Dictionary) -> bool: return s.has("thumb"))
	if thumbs.is_empty():
		return
	var cols := mini(5, thumbs.size())
	var rows := ceili(thumbs.size() / float(cols))
	var th: Image = thumbs[0].thumb
	var tw := th.get_width()
	var thh := th.get_height()
	var cap := 58
	var pad := 12
	var head := 64
	var vp := SubViewport.new()
	vp.size = Vector2i(cols * (tw + pad) + pad, head + rows * (thh + cap + pad) + pad)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.07)
	bg.size = vp.size
	vp.add_child(bg)
	var title := _text("RANDO GAME  VERIFY PACK   %s   %s   %s" % [BuildInfo.label(), _renderer_text(), _when()],
		HudTheme.display_bold(), 30, Color.WHITE)
	title.position = Vector2(pad, 14)
	vp.add_child(title)
	for k in thumbs.size():
		var s: Dictionary = thumbs[k]
		var x := pad + (k % cols) * (tw + pad)
		var y := head + (k / cols) * (thh + cap + pad)
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(s.thumb)
		tr.position = Vector2(x, y)
		tr.size = Vector2(tw, thh)
		vp.add_child(tr)
		var l1 := _text("%s   %s %s" % [s.file.get_basename(), _clock(s.hour), s.weather], HudTheme.text_medium(), 17, Color.WHITE)
		l1.position = Vector2(x, y + thh + 4)
		vp.add_child(l1)
		var lum: Array = s.get("lum", [0, 0, 0, 0, 0])
		var l2 := _text("%.0f fps  gpu %.1f ms   %.2f M tris  %d draws   L %d/%d/%d" % [s.fps, s.gpu_ms,
			s.tris / 1.0e6, s.draws, lum[1], lum[2], lum[3]], HudTheme.text(), 15, Color(1, 1, 1, 0.7))
		l2.position = Vector2(x, y + thh + 28)
		vp.add_child(l2)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image() if vp.get_texture() else null
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGB8)
		img.save_jpg(folder.path_join("sheet.jpg"), 0.9)
		img.save_jpg(folder.path_join("send").path_join("sheet.jpg"), 0.9)
	vp.queue_free()


func _text(s: String, f: Font, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


## report.txt (for a person) and report.json (for the fleet's tools), in the folder and in send/.
func _write_report(folder: String, shots: Array) -> void:
	var lines: PackedStringArray = []
	lines.append("Rando Game verify pack")
	lines.append("%s, %s" % [BuildInfo.label(), _when()])
	lines.append("Machine: %s %s, %s (%s)" % [OS.get_name(), OS.get_version(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()])
	lines.append("Renderer: %s" % _renderer_text())
	var vp := get_viewport()
	lines.append("Window %dx%d, 3D scale %.2f, graphics %s" % [vp.size.x, vp.size.y,
		vp.scaling_3d_scale, _quality_name()])
	lines.append("Shots: %d of %d" % [shots.size(), CAMERAS.size()])
	lines.append("")
	lines.append("shot                    hour  weather   fps   worst ms  cpu ms  gpu ms   M tris  draws   lum p5/p50/p95")
	var out: Array = []
	for s: Dictionary in shots:
		var lum: Array = s.get("lum", [0, 0, 0, 0, 0])
		lines.append("%-22s  %s  %-8s %5.1f  %8.1f  %6.2f  %6.2f  %7.2f  %5d   %d/%d/%d%s" % [
			s.file.get_basename(), _clock(s.hour), s.weather, s.fps, s.worst_ms, s.cpu_ms, s.gpu_ms,
			s.tris / 1.0e6, s.draws, lum[1], lum[2], lum[3], "" if s.saved else "   (no picture saved)"])
		var row := s.duplicate()
		row.erase("thumb")
		out.append(row)
	var text := "\n".join(lines) + "\n"
	for p in [folder.path_join("report.txt"), folder.path_join("send").path_join("report.txt")]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f:
			f.store_string(text)
			f.close()
	var j := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	if j:
		j.store_string(JSON.stringify({"build": BuildInfo.number(), "commit": BuildInfo.COMMIT,
			"os": OS.get_name(), "gpu": RenderingServer.get_video_adapter_name(),
			"renderer": _renderer_text(), "window": [vp.size.x, vp.size.y],
			"scale_3d": vp.scaling_3d_scale, "graphics": _quality_name(), "shots": out}, "\t"))
		j.close()


func _renderer_text() -> String:
	return "%s / %s" % [ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
		RenderingServer.get_current_rendering_driver_name()]


func _quality_name() -> String:
	var q := get_parent().get_node_or_null("Quality") if get_parent() else null
	return String(q.call("level_name")) if q and q.has_method("level_name") else "?"


static func _clock(hour: float) -> String:
	return "%02d:%02d" % [int(hour), int(round(fmod(hour, 1.0) * 60.0)) % 60]


static func _when() -> String:
	return Time.get_datetime_string_from_system(false, true)


# --- On screen ---------------------------------------------------------------------------------

func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.name = "Progress"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	_progress = _text("", HudTheme.text_medium(), 20, Color.WHITE)
	_progress.position = Vector2(28, 22)
	_progress.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_progress.add_theme_constant_override("outline_size", 6)
	_overlay.add_child(_progress)

	_card = Control.new()
	_card.name = "Card"
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.visible = false
	add_child(_card)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.add_child(center)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.08, 0.1, 0.92)
	box.set_corner_radius_all(18)
	box.set_content_margin_all(34)
	box.border_color = Color(1, 1, 1, 0.12)
	box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	col.add_child(_text("VERIFY PACK", HudTheme.display_bold(), 44, Color.WHITE))
	_card_text = _text("", HudTheme.text(), 20, Color(1, 1, 1, 0.85))
	_card_text.custom_minimum_size = Vector2(720, 0)
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_card_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var open := Button.new()
	open.name = "OpenFolder"
	open.text = "Open folder"
	open.custom_minimum_size = Vector2(220, 52)
	open.pressed.connect(func(): if last_folder != "": OS.shell_open(last_folder))
	row.add_child(open)
	var done := Button.new()
	done.name = "Done"
	done.text = "Done"
	done.custom_minimum_size = Vector2(160, 52)
	done.pressed.connect(_close_card)
	row.add_child(done)


func _show_card(folder: String, shots: int, wanted: int) -> void:
	var where := folder
	var home := OS.get_environment("HOME")
	if home != "" and where.begins_with(home):
		where = "~" + where.substr(home.length())
	var head := "%d of %d pictures taken." % [shots, wanted] if shots == wanted else \
		"Stopped after %d of %d pictures." % [shots, wanted]
	_card_text.text = "%s  %s.\n\nSaved in %s\n\nSend the files in its \"send\" folder (sheet.jpg, report.txt and the ten small pictures). docs/VERIFY.md has the steps." % [head, BuildInfo.label(), where] \
		if folder != "" else "%s  Nothing could be saved (no folder could be written)." % head
	_card.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _close_card() -> void:
	_card.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func card_open() -> bool:
	return _card != null and _card.visible
