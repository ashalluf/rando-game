extends RefCounted
## Verify pack checks for tests/smoke_test.gd (VerifyPack, docs/VERIFY.md): its camera table is
## tools/refcams/cameras.json's; the pause menu has the button and the city the node; the folder
## is named from the build and never overwrites; the luminance numbers are refcams.py's; and a
## real run of one camera (a short hold, into a test folder) writes its report and puts the
## player, the camera, the clock, the weather, the graphics level and the HUD back as they were.
## Headless renders nothing, so the run saves no picture here: harness runs prove the pictures.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_check_table()
	_check_pure()
	if not VerifyPack.enabled():
		_check(city.get_node_or_null("VerifyPack") == null, "verify pack off (VERIFY_PACK=0): no node")
		return
	var menu := city.get_node_or_null("PauseMenu")
	_check(menu != null and menu.find_child("VerifyButton", true, false) != null,
		"the pause menu has the VERIFY PACK button")
	for i in 3:
		await _tree.process_frame
	var pack := city.get_node_or_null("VerifyPack")
	_check(pack != null, "the city has a VerifyPack node beside the pause menu")
	if pack:
		await _check_run(city, pack)


func _check_table() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras.json"))
	var json: Array = parsed.get("cameras", []) if parsed is Dictionary else []
	var same := json.size() == VerifyPack.CAMERAS.size() and json.size() == 10
	if same:
		for i in json.size():
			var a: Dictionary = json[i]
			var b: Dictionary = VerifyPack.CAMERAS[i]
			same = same and a.name == b.name and float(a.hour) == float(b.hour) \
					and a.weather == b.weather and bool(a.get("agl", false)) == bool(b.agl) \
					and float(a.get("fov", 55)) == float(b.fov)
			for k in 5:
				same = same and is_equal_approx(float(a.eye[k]), float(b.eye[k]))
	_check(same, "VerifyPack.CAMERAS is tools/refcams/cameras.json (%d cameras)" % VerifyPack.CAMERAS.size())


func _check_pure() -> void:
	_check(BuildInfo.number() == (BuildInfo.BUILD if BuildInfo.BUILD != "" else "dev"),
		"the build number is the stamp, or dev (%s)" % BuildInfo.label())
	var base := "user://verify_pack_test"
	_rm_tree(base)
	var first := VerifyPack.folder_in(base)
	DirAccess.make_dir_recursive_absolute(first)
	var second := VerifyPack.folder_in(base)
	_check(first.get_file() == "verify_%s" % BuildInfo.number() and second.get_file() == "verify_%s_2" % BuildInfo.number(),
		"a second run gets its own folder (%s, %s)" % [first.get_file(), second.get_file()])
	_rm_tree(base)
	# 0..255 grey ramp: p50 is the middle, p5 / p95 near the ends (PIL's "L").
	var img := Image.create(256, 4, false, Image.FORMAT_RGB8)
	for x in 256:
		for y in 4:
			img.set_pixel(x, y, Color8(x, x, x))
	var lum := VerifyPack.luminance(img)
	_check(lum.size() == 5 and absi(int(lum[2]) - 127) <= 1 and absi(int(lum[1]) - 12) <= 1 \
			and absi(int(lum[3]) - 242) <= 1, "the luminance percentiles read a grey ramp right (%s)" % str(lum))
	var red := Image.create(8, 8, false, Image.FORMAT_RGB8)
	red.fill(Color8(255, 0, 0))
	_check(int(VerifyPack.luminance(red)[2]) == 76, "luminance is PIL's L weighting (pure red 76)")
	OS.set_environment("VERIFY_ONLY", "beach,hills")
	var only := VerifyPack.cameras()
	OS.set_environment("VERIFY_ONLY", "")
	_check(only.size() == 2 and only[0].name == "beach" and VerifyPack.cameras().size() == 10,
		"VERIFY_ONLY narrows the run")


func _check_run(city: Node3D, pack: Node) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	var day := city.get_node_or_null("DayNight")
	var weather := city.get_node_or_null("Weather")
	var quality := city.get_node_or_null("Quality")
	if player == null or day == null or weather == null:
		_check(false, "the verify run has a player, DayNight and Weather")
		return
	var base := "user://verify_pack_run"
	_rm_tree(base)
	var before_pos := WorldState.to_world(player.global_position)
	var before_hour := float(day.get("hour"))
	var before_state := int(weather.get("state"))
	var before_forced := bool(weather.call("is_forced"))
	var before_cam := city.get_viewport().get_camera_3d()
	var before_mode := player.process_mode
	var before_q := bool(quality.call("is_forced")) if quality else false
	var hud_layers: Array = []
	for n in city.find_children("*", "CanvasLayer", true, false):
		if n != pack and (n as CanvasLayer).visible and (n as CanvasLayer).layer >= 0 and (n as CanvasLayer).layer < 128:
			hud_layers.append(n)
	OS.set_environment("VERIFY_DIR", ProjectSettings.globalize_path(base))
	OS.set_environment("VERIFY_ONLY", "street_night")
	OS.set_environment("VERIFY_HOLD", "0.2")
	pack.set("settle_frames", 3)
	var seen := {"running": false, "hour": -1.0, "rain": false, "player_off": false, "hud_off": false}
	var watch := func() -> void:
		seen.running = bool(pack.get("running"))
		seen.hour = float(day.get("hour"))
		seen.rain = int(weather.get("state")) == 2
		seen.player_off = player.process_mode == Node.PROCESS_MODE_DISABLED and not player.visible
		seen.hud_off = hud_layers.all(func(l): return not l.visible)
	var folder: String = ""
	var done := {"v": false}
	var runner := func() -> void:
		await pack.call("run")
		done.v = true
	runner.call()
	var t0 := Time.get_ticks_msec()
	var mid := false
	while not done.v and Time.get_ticks_msec() - t0 < 120000:
		await _tree.process_frame
		if not mid and bool(pack.get("running")):
			watch.call()
			mid = seen.player_off
	OS.set_environment("VERIFY_DIR", "")
	OS.set_environment("VERIFY_ONLY", "")
	OS.set_environment("VERIFY_HOLD", "")
	pack.set("settle_frames", 20)
	_check(done.v, "a one-camera verify run finishes")
	folder = String(pack.get("last_folder"))
	_check(mid and seen.rain and is_equal_approx(seen.hour, 21.5) and seen.hud_off,
		"during the run the camera's hour (21:30) and weather (rain) are set, the player parked hidden, the HUD hidden")
	var shots: Array = pack.get("last_shots")
	_check(shots.size() == 1 and shots[0].name == "street_night" and float(shots[0].fps) > 0.0,
		"the run recorded its one shot with a frame rate")
	_check(folder != "" and FileAccess.file_exists(folder.path_join("report.txt"))
			and FileAccess.file_exists(folder.path_join("report.json"))
			and FileAccess.file_exists(folder.path_join("send/report.txt")),
		"the run wrote report.txt, report.json and send/report.txt (%s)" % folder)
	_check(WorldState.to_world(player.global_position).distance_to(before_pos) < 0.5 and player.visible
			and player.process_mode == before_mode, "the player is back where he was, shown and running")
	_check(city.get_viewport().get_camera_3d() == before_cam, "the player's camera is current again")
	_check(is_equal_approx(float(day.get("hour")), before_hour), "the clock is back (%.2f)" % before_hour)
	_check(int(weather.get("state")) == before_state and bool(weather.call("is_forced")) == before_forced,
		"the weather is back as it was")
	_check(quality == null or bool(quality.call("is_forced")) == before_q, "the graphics level is back on its old mode")
	_check(hud_layers.all(func(l): return l.visible), "every HUD layer is shown again")
	if bool(pack.call("card_open")):
		pack.call("_close_card")
	_check(not _tree.paused and not bool(pack.call("card_open")), "the card closes and the game runs on")
	_rm_tree(base)


func _rm_tree(path: String) -> void:
	var full := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(full):
		return
	var d := DirAccess.open(full)
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(full.path_join(sub))
	DirAccess.remove_absolute(full)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
