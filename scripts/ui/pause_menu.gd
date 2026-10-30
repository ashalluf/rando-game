extends CanvasLayer
## Pause menu: Esc toggles it. The frozen game blurred and darkened behind a column of frosted
## glass type (shaders/pause_backdrop.gdshader): Resume; the time of day (jumps the clock);
## the weather (held, or Auto to let it roll); graphics quality (held, or Auto to adapt to the
## frame rate); the world seed with Rebuild; Settings; Quit - and the controls on a glass card on
## the right. SETTINGS swaps the column and the card for a settings screen (sliders and On / Off
## chips on one wide glass card, saved through GameSettings, scripts/ui/game_settings.gd;
## SETTINGS_MENU=0 is the A/B: no button, nothing loaded).
## Built in code (the scene is only the CanvasLayer); every size is in 1080-line pixels and the
## whole menu is scaled to the window.

## Time-of-day presets: label and hour.
const TIMES := [["Sunrise", 6.6], ["Morning", 9.0], ["Noon", 12.0], ["Golden hour", 17.7], ["Night", 21.5]]
## Weather chips: Auto, then Weather.State in order (index - 1 is the state). Two rows.
const WEATHERS := ["Auto", "Clear", "Cloudy", "Rain", "Storm", "Marine layer", "Santa Ana"]
const WEATHER_ROW := 4
const GRAPHICS := ["Auto", "High", "Medium", "Low"]
## The controls card: key, what it does.
const CONTROLS := [
	["W A S D", "Move"],
	["Shift", "Boost (in the air it flies where you look)"],
	["Space", "Jump, and again in the air"],
	["Left click", "Fire"],
	["Right click", "Aim and lock on"],
	["1  2  3 / wheel", "Switch weapon"],
	["Hold Tab", "Weapon wheel (slows time)"],
	["E", "Get in or out of a car"],
	["M", "Map: click sets a waypoint"],
	["R", "Respawn"],
	["P", "Photo mode"],
	["F1", "HUD: clean, full, hidden"],
	["F11", "Fullscreen"],
	["In a car", "W / S drive, Space jumps, Shift nitro"],
]
const FONT_SEMIBOLD := "res://assets/fonts/Inter-SemiBold.woff2"
const FONT_MEDIUM := "res://assets/fonts/Inter-Medium.woff2"
## How long the menu takes to fade in or out (real seconds).
const FADE := 0.16

var _open: bool = false
var _root: Control
var _frame: Control
var _clock: Label
var _info: Label
var seed_edit: LineEdit
var _weather_buttons: Array[Button] = []
var _graphics_buttons: Array[Button] = []
var _semibold: Font
var _medium: Font
var _tween: Tween
## The two views: the menu (column and controls card) and the settings screen.
var _main_view: Control
var _settings_view: Control
## Setting key -> its control (HSlider or the On chip) and its value label.
var settings_controls: Dictionary = {}
var _settings_values: Dictionary = {}
var _settings_dirty: bool = false
var _foot: Label

## The settings screen: section, then rows of [key, label, value format]. A format of "" is an
## On / Off toggle; "x" a multiplier, "deg" degrees, "pct" a percentage.
const SETTINGS_LAYOUT := [
	["CONTROLS", [["mouse_sensitivity", "Look sensitivity", "x"], ["invert_y", "Invert look", ""]]],
	["CAMERA", [["fov", "Field of view", "deg"], ["car_fov", "Field of view in cars", "deg"]]],
	["AUDIO", [["volume_master", "Master volume", "pct"], ["volume_world", "World volume", "pct"],
		["volume_ambience", "Ambience volume", "pct"]]],
	["GRAPHICS", [["motion_blur", "Motion blur", ""], ["depth_of_field", "Depth of field", ""],
		["film_grain", "Film grain", ""], ["vignette", "Vignette", ""],
		["render_scale", "Render scale", "pct"]]],
	["HUD", [["hud_scale", "HUD size", "pct"]]],
]
## How many sections go in the card's left column (the rest on the right).
const SETTINGS_LEFT := 3


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_semibold = _load_font(FONT_SEMIBOLD)
	_medium = _load_font(FONT_MEDIUM)
	_build()
	_root.visible = false
	# Photo mode (scripts/ui/photo_mode.gd) lives beside the menu in the city scene.
	if get_parent() and get_parent().get_node_or_null("PhotoMode") == null:
		var photo := PhotoMode.new()
		photo.name = "PhotoMode"
		get_parent().add_child.call_deferred(photo)
	var city := get_tree().get_first_node_in_group("city")
	if city:
		seed_edit.text = str(city.get("world_seed"))
	# The saved settings, applied once the scene's nodes (the player, Quality, the vignette) are in.
	# The smoke test never reads the player's own file.
	if GameSettings.enabled():
		if get_tree().root.get_node_or_null("SmokeTest") == null:
			GameSettings.ensure_loaded()
		_apply_settings.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		if _open and settings_open():
			_show_settings(false) # Esc steps back out of the settings screen first
		elif _open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync()
	_show_settings(false)
	_layout()
	_root.visible = true
	_fade(1.0)


func close() -> void:
	_open = false
	_save_settings()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_fade(0.0)


func _process(_delta: float) -> void:
	if _open:
		_layout()
		var day := _scene_node("DayNight")
		if day and _clock:
			_clock.text = day.call("clock_text")


func _fade(to: float) -> void:
	if _tween:
		_tween.kill()
	if not is_inside_tree():
		_root.modulate.a = to
		_root.visible = to > 0.0
		return
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_root, "modulate:a", to, FADE)
	if to <= 0.0:
		_tween.tween_callback(func(): _root.visible = false)


## Scales the 1080-line layout to the window.
func _layout() -> void:
	var view := _root.get_viewport_rect().size if _root.is_inside_tree() else Vector2(1920, 1080)
	var s := clampf(view.y / 1080.0, 0.6, 3.0)
	_frame.scale = Vector2(s, s)
	_frame.size = view / s


# --- Actions -----------------------------------------------------------------------------------

func _set_hour(hour: float) -> void:
	var day := _scene_node("DayNight")
	if day == null:
		return
	day.set("hour", hour)
	# The tree is paused, so DayNight's own _process is not running: redraw the sky now.
	if day.has_method("_apply"):
		day.call("_apply")
	if _clock:
		_clock.text = day.call("clock_text")


func _set_weather(index: int) -> void:
	var weather := _scene_node("Weather")
	if weather and weather.has_method("force_state"):
		weather.call("force_state", index - 1)
	_sync()


func _set_graphics(index: int) -> void:
	var quality := _scene_node("Quality")
	if quality and quality.has_method("force_level"):
		quality.call("force_level", index - 1)
	_sync()


func _apply_seed() -> void:
	var text := seed_edit.text.strip_edges()
	var new_seed := text.to_int() if text.is_valid_int() else hash(text)
	WorldState.pending_seed = new_seed
	WorldState.reset_destruction()
	get_tree().paused = false
	_open = false
	get_tree().reload_current_scene()


## Lights the weather and graphics buttons for what is in force now.
func _sync() -> void:
	var weather := _scene_node("Weather")
	var w := 0
	if weather and weather.has_method("is_forced") and bool(weather.call("is_forced")):
		w = int(weather.get("state")) + 1
	for i in _weather_buttons.size():
		_weather_buttons[i].set_pressed_no_signal(i == w)
	var quality := _scene_node("Quality")
	var g := 0
	if quality and quality.has_method("is_forced") and bool(quality.call("is_forced")):
		g = mini(int(quality.get("level")) + 1, GRAPHICS.size() - 1)
	for i in _graphics_buttons.size():
		_graphics_buttons[i].set_pressed_no_signal(i == g)
	if _info:
		var parts: PackedStringArray = []
		if weather and weather.has_method("state_name"):
			parts.append("Weather: %s" % weather.call("state_name"))
		if quality and quality.has_method("level_name"):
			parts.append("Graphics: %s" % quality.call("level_name"))
		_info.text = "   ".join(parts)


## A node of the city scene (the menu is a child of its root; in the smoke test the city is not
## the current scene, so this asks the parent rather than current_scene).
func _scene_node(n: String) -> Node:
	var scene := get_parent()
	return scene.get_node_or_null(n) if scene else null


# --- Settings ----------------------------------------------------------------------------------

func _apply_settings() -> void:
	if is_inside_tree():
		GameSettings.apply(get_parent())


## Shows the settings screen (true) or the menu (false); leaving the screen saves.
func _show_settings(on: bool) -> void:
	if _settings_view == null:
		return
	if not on and _settings_view.visible:
		_save_settings()
	_settings_view.visible = on
	_main_view.visible = not on
	if _foot:
		_foot.text = "Esc   Back" if on else "Esc   Resume"
	if on:
		_sync_settings()


func settings_open() -> bool:
	return _settings_view != null and _settings_view.visible


## A control changed `key`: store it, apply it at once (the frozen frame shows a graphics toggle),
## and mark the file to be written when the screen is left.
func _setting_changed(key: String, v: Variant) -> void:
	var stored: Variant = GameSettings.set_value(key, v)
	_settings_dirty = true
	_show_value(key, stored)
	_apply_settings()


func _save_settings() -> void:
	if not _settings_dirty or not GameSettings.enabled():
		return
	_settings_dirty = false
	GameSettings.save_file()


func _reset_settings() -> void:
	GameSettings.reset()
	_settings_dirty = true
	_sync_settings()
	_apply_settings()


## Puts every control at the value in force.
func _sync_settings() -> void:
	for key: String in settings_controls:
		var c: Control = settings_controls[key]
		var v: Variant = GameSettings.get_value(key)
		if c is HSlider:
			(c as HSlider).set_value_no_signal(float(v))
		elif c is Button:
			var on_chip := c as Button
			on_chip.set_pressed_no_signal(bool(v))
			var off_chip: Button = on_chip.get_meta("off")
			off_chip.set_pressed_no_signal(not bool(v))
		_show_value(key, v)


func _show_value(key: String, v: Variant) -> void:
	var l: Label = _settings_values.get(key)
	if l == null:
		return
	match String(l.get_meta("format")):
		"x":
			l.text = "%.2fx" % float(v)
		"deg":
			l.text = "%d\u00b0" % roundi(float(v))
		"pct":
			l.text = "%d %%" % roundi(float(v) * 100.0)
		_:
			l.text = ""


func _build_settings() -> void:
	_settings_view = Control.new()
	_settings_view.name = "Settings"
	_settings_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_view.visible = false
	_frame.add_child(_settings_view)
	var column := VBoxContainer.new()
	column.position = Vector2(96.0, 84.0)
	column.custom_minimum_size = Vector2(360.0, 0.0)
	column.add_theme_constant_override("separation", 10)
	_settings_view.add_child(column)
	column.add_child(_label("RANDO", _semibold, 74, Color.WHITE, 6.0))
	column.add_child(_label("SETTINGS", _medium, 17, Color(1, 1, 1, 0.62), 5.0))
	column.add_child(_spacer(22.0))
	var back := _big_button("Back")
	back.name = "BackButton"
	back.custom_minimum_size = Vector2(360.0, 58.0)
	back.pressed.connect(func(): _show_settings(false))
	column.add_child(back)
	var defaults := _big_button("Reset to defaults")
	defaults.custom_minimum_size = Vector2(360.0, 58.0)
	defaults.add_theme_font_size_override("font_size", 20)
	defaults.pressed.connect(_reset_settings)
	column.add_child(defaults)
	column.add_child(_spacer(10.0))
	var note := _label("Changes apply at once and are saved\non this computer when you leave.",
			_medium, 15, Color(1, 1, 1, 0.5), 0.5)
	column.add_child(note)

	var card := PanelContainer.new()
	card.name = "SettingsCard"
	card.add_theme_stylebox_override("panel", _glass_box(20.0, 34.0))
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -1300.0
	card.offset_right = -96.0
	card.offset_top = 150.0
	_settings_view.add_child(card)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 56)
	card.add_child(cols)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for v: VBoxContainer in [left, right]:
		v.add_theme_constant_override("separation", 12)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.custom_minimum_size = Vector2(530.0, 0.0)
		cols.add_child(v)
	for si in SETTINGS_LAYOUT.size():
		var section: Array = SETTINGS_LAYOUT[si]
		var box := left if si < SETTINGS_LEFT else right
		if box.get_child_count() > 0:
			box.add_child(_spacer(10.0))
		box.add_child(_section(String(section[0])))
		for row: Array in section[1]:
			box.add_child(_setting_row(String(row[0]), String(row[1]), String(row[2])))
	_sync_settings()


## One row: the name, then a slider and its value, or Off / On chips.
func _setting_row(key: String, text: String, format: String) -> HBoxContainer:
	var r := _row()
	r.name = "Row_" + key
	r.add_theme_constant_override("separation", 14)
	var name_label := _label(text, _medium, 18, Color(1, 1, 1, 0.9), 0.0)
	name_label.custom_minimum_size = Vector2(230.0, 44.0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(name_label)
	if format == "":
		var fill := Control.new()
		fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(fill)
		var group := ButtonGroup.new()
		var off := _chip("Off", true)
		var on := _chip("On", true)
		for b: Button in [off, on]:
			b.button_group = group
			b.custom_minimum_size = Vector2(84.0, 44.0)
			r.add_child(b)
		off.pressed.connect(func(): _setting_changed(key, false))
		on.pressed.connect(func(): _setting_changed(key, true))
		on.set_meta("off", off)
		settings_controls[key] = on
		return r
	var range_: Array = GameSettings.RANGES[key]
	var slider := HSlider.new()
	slider.min_value = range_[0]
	slider.max_value = range_[1]
	slider.step = range_[2]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(180.0, 30.0)
	slider.value_changed.connect(func(v: float): _setting_changed(key, v))
	r.add_child(slider)
	var value := _label("", _semibold, 17, Color.WHITE, 0.5)
	value.custom_minimum_size = Vector2(76.0, 44.0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.set_meta("format", format)
	r.add_child(value)
	settings_controls[key] = slider
	_settings_values[key] = value
	return r


## A soft white disc with a faint rim, the sliders' grabber (made once).
func _grabber(d: int, alpha: float) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	for y in d:
		for x in d:
			var r := Vector2(x - c, y - c).length()
			var a := clampf(c - r + 0.5, 0.0, 1.0)
			var shade := lerpf(1.0, 0.86, clampf((r - (c - 2.0)) / 2.0, 0.0, 1.0))
			img.set_pixel(x, y, Color(shade, shade, shade, a * alpha))
	return ImageTexture.create_from_image(img)


# --- Building ----------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pause_backdrop.gdshader")
	backdrop.material = mat
	_root.add_child(backdrop)
	_frame = Control.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.theme = _theme()
	_root.add_child(_frame)
	_main_view = Control.new()
	_main_view.name = "Main"
	_main_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(_main_view)

	# The menu column, left.
	var column := VBoxContainer.new()
	column.name = "Column"
	column.position = Vector2(96.0, 84.0)
	column.custom_minimum_size = Vector2(620.0, 0.0)
	column.add_theme_constant_override("separation", 10)
	_main_view.add_child(column)
	column.add_child(_label("RANDO", _semibold, 74, Color.WHITE, 6.0))
	column.add_child(_label("PAUSED", _medium, 17, Color(1, 1, 1, 0.62), 5.0))
	column.add_child(_spacer(22.0))
	var resume := _big_button("Resume")
	resume.pressed.connect(close)
	column.add_child(resume)
	column.add_child(_spacer(12.0))

	var time_head := HBoxContainer.new()
	time_head.add_child(_section("TIME OF DAY"))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_head.add_child(fill)
	_clock = _label("--:--", _medium, 16, Color(1, 1, 1, 0.6), 1.5)
	time_head.add_child(_clock)
	column.add_child(time_head)
	var times := _row()
	for t: Array in TIMES:
		var b := _chip(String(t[0]), false)
		var hour: float = t[1]
		b.pressed.connect(func(): _set_hour(hour))
		times.add_child(b)
	column.add_child(times)
	column.add_child(_spacer(8.0))

	column.add_child(_section("WEATHER"))
	var weathers := _row()
	var wgroup := ButtonGroup.new()
	for i in WEATHERS.size():
		if i == WEATHER_ROW:
			column.add_child(weathers)
			weathers = _row()
		var b := _chip(WEATHERS[i], true)
		b.button_group = wgroup
		var idx := i
		b.pressed.connect(func(): _set_weather(idx))
		weathers.add_child(b)
		_weather_buttons.append(b)
	column.add_child(weathers)
	column.add_child(_spacer(8.0))

	column.add_child(_section("GRAPHICS"))
	var graphics := _row()
	var ggroup := ButtonGroup.new()
	for i in GRAPHICS.size():
		var b := _chip(GRAPHICS[i], true)
		b.button_group = ggroup
		var idx := i
		b.pressed.connect(func(): _set_graphics(idx))
		graphics.add_child(b)
		_graphics_buttons.append(b)
	column.add_child(graphics)
	column.add_child(_spacer(8.0))

	column.add_child(_section("WORLD SEED"))
	var seed_row := _row()
	seed_edit = LineEdit.new()
	seed_edit.name = "SeedEdit"
	seed_edit.placeholder_text = "any number or word"
	seed_edit.custom_minimum_size = Vector2(300.0, 44.0)
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.text_submitted.connect(func(_t): _apply_seed())
	seed_row.add_child(seed_edit)
	var rebuild := _chip("Rebuild city", false)
	rebuild.pressed.connect(_apply_seed)
	seed_row.add_child(rebuild)
	column.add_child(seed_row)
	column.add_child(_spacer(22.0))

	if GameSettings.enabled():
		var settings := _big_button("Settings")
		settings.name = "SettingsButton"
		settings.pressed.connect(func(): _show_settings(true))
		column.add_child(settings)

	var quit := _big_button("Quit")
	quit.pressed.connect(func(): get_tree().quit())
	column.add_child(quit)
	column.add_child(_spacer(6.0))
	_info = _label("", _medium, 14, Color(1, 1, 1, 0.45), 0.5)
	column.add_child(_info)

	# The controls, on a glass card to the right.
	var card := PanelContainer.new()
	card.name = "Controls"
	card.add_theme_stylebox_override("panel", _glass_box(20.0, 30.0))
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -560.0
	card.offset_right = -96.0
	card.offset_top = 150.0
	_main_view.add_child(card)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 14)
	card.add_child(cbox)
	cbox.add_child(_section("CONTROLS"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 11)
	for c: Array in CONTROLS:
		grid.add_child(_label(String(c[0]), _semibold, 16, Color.WHITE, 0.5))
		var what := _label(String(c[1]), _medium, 16, Color(1, 1, 1, 0.66), 0.0)
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.custom_minimum_size = Vector2(250.0, 0.0)
		grid.add_child(what)
	cbox.add_child(grid)

	var foot := _label("Esc   Resume", _medium, 15, Color(1, 1, 1, 0.5), 1.0)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 96.0
	foot.offset_top = -64.0
	_frame.add_child(foot)
	_foot = foot
	if GameSettings.enabled():
		_build_settings()


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font = _medium
	t.default_font_size = 18
	var empty := StyleBoxEmpty.new()
	# Chips: frosted pills; the one in force is solid white with dark type.
	t.set_stylebox("normal", "Button", _pill(Color(1, 1, 1, 0.08)))
	t.set_stylebox("hover", "Button", _pill(Color(1, 1, 1, 0.18)))
	t.set_stylebox("pressed", "Button", _pill(Color(1, 1, 1, 0.94)))
	t.set_stylebox("hover_pressed", "Button", _pill(Color(1, 1, 1, 1.0)))
	t.set_stylebox("focus", "Button", empty)
	t.set_stylebox("disabled", "Button", _pill(Color(1, 1, 1, 0.04)))
	t.set_color("font_color", "Button", Color(1, 1, 1, 0.9))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.06, 0.07, 0.09))
	t.set_color("font_hover_pressed_color", "Button", Color(0.06, 0.07, 0.09))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_font("font", "Button", _semibold)
	t.set_font_size("font_size", "Button", 17)
	# The seed field.
	var field := _pill(Color(0, 0, 0, 0.32))
	field.border_color = Color(1, 1, 1, 0.16)
	field.set_border_width_all(1)
	t.set_stylebox("normal", "LineEdit", field)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = Color(1, 1, 1, 0.55)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.38))
	t.set_color("caret_color", "LineEdit", Color.WHITE)
	t.set_font("font", "LineEdit", _medium)
	t.set_font_size("font_size", "LineEdit", 18)
	# The settings sliders: a thin frosted track, filled white up to a white disc.
	var track := _pill(Color(1, 1, 1, 0.14))
	track.set_corner_radius_all(3)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	track.content_margin_left = 0.0
	track.content_margin_right = 0.0
	t.set_stylebox("slider", "HSlider", track)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = Color(1, 1, 1, 0.86)
	t.set_stylebox("grabber_area", "HSlider", filled)
	var filled_hi := filled.duplicate() as StyleBoxFlat
	filled_hi.bg_color = Color(1, 1, 1, 1.0)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled_hi)
	t.set_icon("grabber", "HSlider", _grabber(22, 0.96))
	t.set_icon("grabber_highlight", "HSlider", _grabber(26, 1.0))
	t.set_stylebox("focus", "HSlider", empty)
	return t


func _pill(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	sb.anti_aliasing = true
	return sb


func _glass_box(radius: float, pad: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.05, 0.42)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(radius))
	sb.set_content_margin_all(pad)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 18
	sb.anti_aliasing = true
	return sb


func _big_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(620.0, 58.0)
	b.add_theme_font_size_override("font_size", 26)
	var normal := _pill(Color(1, 1, 1, 0.0))
	normal.content_margin_left = 20.0
	var hover := _pill(Color(1, 1, 1, 0.14))
	hover.content_margin_left = 20.0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


func _chip(text: String, toggle: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(0.0, 44.0)
	return b


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	return r


func _section(text: String) -> Label:
	return _label(text, _semibold, 14, Color(1, 1, 1, 0.5), 3.0)


func _label(text: String, font: Font, size: int, color: Color, tracking: float) -> Label:
	var l := Label.new()
	l.text = text
	var f := font
	if tracking != 0.0:
		var fv := FontVariation.new()
		fv.base_font = font
		fv.spacing_glyph = int(round(tracking))
		f = fv
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f:
			return f
	return ThemeDB.fallback_font
