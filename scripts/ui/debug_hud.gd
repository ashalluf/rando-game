extends CanvasLayer
## The HUD. F1 cycles three modes:
##   CLEAN   crosshair, minimap and weapon list only. What the game looks like while playing.
##   FULL    plus the stats line, the frame-time breakdown and the control hints.
##   HIDDEN  nothing, for screenshots.
## It starts CLEAN: the debug block is genuinely useful (screenshot the frame line when
## reporting lag) but it is a wall of developer text across the top of every frame.

@onready var stats: Label = $Stats
@onready var hints: Label = $Hints
@onready var weapon_label: Label = $Weapon

enum Mode { CLEAN, FULL, HIDDEN }
var mode: Mode = Mode.CLEAN

var _player: Player
## The weapon the list was last written for, so it is rebuilt only on a switch.
var _labelled_weapon: Weapon


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if OS.has_feature("web"):
		hints.text = "Click the game to grab the mouse.\n"
		# ?nohud in the page URL hides the overlay (used by the screenshot harness).
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String and (search as String).contains("nohud"):
			mode = Mode.HIDDEN
	elif "--nohud" in OS.get_cmdline_user_args():
		mode = Mode.HIDDEN # desktop / tools/glshot: `-- --nohud`
	elif "--stats" in OS.get_cmdline_user_args():
		mode = Mode.FULL
	_apply_mode()
	hints.text += "WASD move   Shift boost (hold; in the air it follows where you look)   Space jump (again in air)   Mouse look   E get in / out of a car\n" \
		+ "Left click fire   Right click drop (gravity gun)   1 / 2 / 3 or scroll to switch weapons   hold Tab weapon wheel   R respawn   Esc pause / seed   F1 hide   F11 fullscreen\n" \
		+ "Driving: W / S gas and brake   A / D steer   Shift nitro   Space jump   right click handbrake   in the air W / S flip, A / D roll\n" \
		+ "Flying (jets at the airport): Shift throttle up   right click throttle down   S pull up, W nose down   A / D roll   S on the ground brakes\n" \
		+ "Gamepad: left stick move   B boost   A jump   Y car   right stick look   RT fire   LT drop   LB tap previous / hold wheel   RB next   Back respawn"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and not OS.has_feature("web"):
		var win := get_window()
		var full := win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		win.mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN
	if event.is_action_pressed("toggle_hud"):
		mode = ((mode + 1) % Mode.size()) as Mode
		_apply_mode()


## Shows and hides the parts that belong to the current mode.
func _apply_mode() -> void:
	visible = mode != Mode.HIDDEN
	stats.visible = mode == Mode.FULL
	hints.visible = mode == Mode.FULL


func _process(_delta: float) -> void:
	if not visible:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	# The weapon list shows in CLEAN mode too (it used to be filled only in FULL, so CLEAN
	# showed "..." in its place).
	_update_weapon_label()
	if mode != Mode.FULL:
		return
	var budget := get_node_or_null("/root/PhysicsBudget")
	var bodies: int = budget.active_body_count() if budget else 0
	var frozen: int = budget.frozen_count if budget else 0
	var state := "on floor" if _player.is_on_floor() else "airborne"
	if _player.is_driving():
		state = "driving %s" % _player.vehicle.display_name()
	if _player.is_boosting():
		state += "  BOOST"
	var jumps: String = "∞" if _player.unlimited_air_jumps else str(_player.air_jumps_left)
	stats.text = "FPS %d   speed %.1f m/s   vertical %+.1f m/s   %s   air jumps %s\n" % [
		Engine.get_frames_per_second(), _player.horizontal_speed(), _player.velocity.y,
		state, jumps,
	] + "last jump peak %.1f m   physics props %d (frozen %d)" % [_player.last_jump_peak, bodies, frozen]
	var city := get_tree().get_first_node_in_group("city")
	if city and city.has_method("district_name_at"):
		stats.text += "   district: %s" % city.district_name_at(_player.global_position)
	var day := get_tree().current_scene.get_node_or_null("DayNight") if get_tree().current_scene else null
	if day:
		stats.text += "   %s" % day.clock_text()
	var weather := get_tree().current_scene.get_node_or_null("Weather") if get_tree().current_scene else null
	if weather and weather.has_method("state_name"):
		stats.text += "   %s" % weather.state_name()
	var peds := get_tree().get_nodes_in_group("pedestrian").size()
	var traffic := get_tree().get_first_node_in_group("traffic")
	stats.text += "   people %d" % peds
	var quality := get_tree().current_scene.get_node_or_null("Quality")
	if quality and not OS.has_feature("web"):
		stats.text += "   quality %s" % quality.level_name()
		if quality.render_pixels.x > 0:
			stats.text += " (3D %dx%d)" % [quality.render_pixels.x, quality.render_pixels.y]
	# Where the frame time goes (ms): script + engine on the CPU, physics, GPU render, and how
	# much the renderer draws. Screenshot this line when reporting lag.
	var cpu_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var rid := get_viewport().get_viewport_rid()
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var tris := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000
	stats.text += "\nframe: cpu %.1f ms   physics %.1f ms   gpu %.1f ms   draws %d   objects %d   tris %dk" % [cpu_ms, phys_ms, gpu_ms, draws, objects, tris]
	if city and city.has_method("chunk_counts"):
		var counts: Vector2i = city.chunk_counts()
		var wp: Vector3 = city.world_position(_player.global_position)
		stats.text += "   chunks %d full / %d far   world pos %d, %d   wrecked %d" % [counts.x, counts.y, int(wp.x), int(wp.z), WorldState.destroyed_count()]


func _update_weapon_label() -> void:
	var manager := _player.weapon_manager
	if manager and manager.current and manager.current != _labelled_weapon:
		_labelled_weapon = manager.current
		var parts: PackedStringArray = []
		for i in manager.weapons.size():
			var name := manager.weapons[i].display_name
			parts.append("[%d] %s" % [i + 1, name.to_upper() if manager.weapons[i] == manager.current else name])
		weapon_label.text = "   ".join(parts)
